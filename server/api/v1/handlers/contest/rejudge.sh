# POST /contest/rejudge?contest=<id>   (Bearer, admin)
# body: {ids:[...]}  — RE-JULGA cada submissão. Reconstrói a fonte ARQUIVADA
# (users/<login>/submissions/<id>.<lang>) + metadados do history do dono e reinjeta no
# spool como uma SUBMISSÃO normal (mesmo id), marcando a linha como pendente. Assim
# funciona com o daemon que JÁ está rodando (caminho de submit) — sem depender de
# marcador vazio nem de reiniciar o daemon. Reporta as puladas (sem fonte/linha).
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin_or_chief || fail 403 "Admin/juiz-chefe only" "admin_required"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
# normaliza: aceita {ids:[...]} (array) ou ids como string única
mapfile -t IDS < <(jq -r '(.ids // []) | (if type=="array" then .[] else . end) // empty' <<<"$body")
(( ${#IDS[@]} > 0 )) || fail 400 "Missing ids" "ids_missing"

cdir="$CONTESTSDIR/$contest"
mkdir -p "$SPOOLDIR"
AGORA="$EPOCHSECONDS"
declare -a QUEUED SKIPPED
for subid in "${IDS[@]}"; do
  [[ -n "$subid" ]] || continue
  valid_id "$subid" || fail 400 "Invalid submission id: $subid" "id_invalid"
  # dono + fonte pelo store (users/<login>/submissions/<id>.<ext>)
  set +o noglob; shopt -s nullglob
  resolve_submission "$contest" "$subid"
  set -o noglob
  if [[ -z "$SUB_OWNER" ]]; then SKIPPED+=("$subid:sem_history"); continue; fi
  r_login="$SUB_OWNER"
  # linha do history por-usuário (6 campos: tempo:prob:lang:verdict:sub_epoch:subid)
  line="$(awk -F: -v id="$subid" '$NF==id{print; exit}' "$(user_hist_file "$contest" "$r_login")" 2>/dev/null)"
  if [[ -z "$line" ]]; then SKIPPED+=("$subid:sem_history"); continue; fi
  IFS=: read -r r_tempo r_prob r_lang _rest <<<"$line"
  r_sub="$(awk -F: -v id="$subid" '$NF==id{print $(NF-1); exit}' "$(user_hist_file "$contest" "$r_login")" 2>/dev/null)"
  llang="$(printf '%s' "$r_lang" | tr '[:upper:]' '[:lower:]')"
  src="$SUB_SRC"
  if [[ -z "$src" || ! -f "$src" ]]; then SKIPPED+=("$subid:sem_fonte"); continue; fi
  codeb64="$(base64 -w0 < "$src" 2>/dev/null)"
  if [[ -z "$codeb64" ]]; then SKIPPED+=("$subid:fonte_vazia"); continue; fi
  # provisório no history do dono + metrics (o placar/Situação leem só metrics)
  user_history_replace "$contest" "$r_login" "$subid" \
    "$r_tempo:$r_prob:$r_lang:Not Answered Yet:${r_sub:-$AGORA}:$subid"
  metrics_recompute "$contest" "$r_login"
  # injeta no spool como SUBMIT (mesmo id) — o daemon re-julga e troca a linha por :id
  FILETYPE="$(printf '%s' "${r_lang:-TXT}" | tr '[:lower:]' '[:upper:]')"
  spoolname="$contest:$AGORA:$subid:$r_login:submit:$r_prob:$FILETYPE"
  innm="$SPOOLDIR/.in.$subid.$AGORA"
  jq -cn --arg c "$contest" --arg l "$r_login" --arg p "$r_prob" --arg f "solution.${llang:-txt}" \
     --arg b "$codeb64" --arg t "$FILETYPE" --argjson ts "${r_sub:-$AGORA}" --arg id "$subid" \
     '{contest:$c, login:$l, problem_id:$p, filename:$f, code_b64:$b, lang:$t, time:$ts, id:$id}' > "$innm"
  mv -f "$innm" "$SPOOLDIR/$spoolname"
  QUEUED+=("$subid")
done

qids="$( ((${#QUEUED[@]})) && { IFS=,; printf '%s' "${QUEUED[*]}"; } | head -c 300 )"
audit_log_to "$contest" rejudge "ids=${qids:-} count=${#QUEUED[@]} skipped=${#SKIPPED[@]}$( ((${#SKIPPED[@]})) && printf ' [%s]' "$(IFS=,; echo "${SKIPPED[*]}")" | head -c 150)"
ok_json '{action:"rejudge", queued:$q, count:($q|length), skipped:$s, skipped_count:($s|length)}' \
  --argjson q "$(printf '%s\n' ${QUEUED[@]+"${QUEUED[@]}"} | jq -R . | jq -cs 'map(select(length>0))')" \
  --argjson s "$(printf '%s\n' ${SKIPPED[@]+"${SKIPPED[@]}"} | jq -R . | jq -cs 'map(select(length>0))')"
