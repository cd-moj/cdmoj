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
# a FONTE nunca anda por argv do jq: `--arg b "$codeb64"` estourava o ARG_MAX (128 KiB POR argumento) com fonte
# >~96 KiB — o jq morria, o spool saía com 0 byte e o rejulgamento virava Judge Error com a linha já marcada
# pendente. Hoje: base64 em ARQUIVO + `--rawfile` (molde do /submit) e o spool é CONFERIDO antes de mexer no history.
B64F="$(mktemp)"; trap 'rm -f "$B64F"' EXIT
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
  # linha do history por-usuário (6 campos: tempo:prob:lang:verdict:sub_epoch:subid — o veredicto pode ter ':')
  line="$(awk -F: -v id="$subid" '$NF==id{print; exit}' "$(user_hist_file "$contest" "$r_login")" 2>/dev/null)"
  if [[ -z "$line" ]]; then SKIPPED+=("$subid:sem_history"); continue; fi
  IFS=: read -r r_tempo r_prob r_lang _rest <<<"$line"
  r_sub="${line%:*}"; r_sub="${r_sub##*:}"; [[ "$r_sub" =~ ^[0-9]+$ ]] || r_sub=""
  llang="${r_lang,,}"
  src="$SUB_SRC"
  if [[ -z "$src" || ! -f "$src" ]]; then SKIPPED+=("$subid:sem_fonte"); continue; fi
  if ! base64 -w0 < "$src" > "$B64F" 2>/dev/null || [[ ! -s "$B64F" ]]; then SKIPPED+=("$subid:fonte_vazia"); continue; fi
  # SUBMIT no spool (mesmo id), no shard do DONO (lib/spool-shard.sh) — o daemon re-julga e troca a linha por :id
  FILETYPE="${r_lang:-TXT}"; FILETYPE="${FILETYPE^^}"
  sd="$(spool_shard_dir "$r_login")"
  spoolname="$contest:$AGORA:$subid:$r_login:submit:$r_prob:$FILETYPE"
  innm="$sd/.in.$subid.$AGORA"
  jq -cn --arg c "$contest" --arg l "$r_login" --arg p "$r_prob" --arg f "solution.${llang:-txt}" \
     --rawfile b "$B64F" --arg t "$FILETYPE" --argjson ts "${r_sub:-$AGORA}" --arg id "$subid" \
     '{contest:$c, login:$l, problem_id:$p, filename:$f, code_b64:($b | rtrimstr("\n")), lang:$t, time:$ts, id:$id}' \
     > "$innm" 2>/dev/null
  # FAIL CLOSED: spool inválido não toca o history (a linha segue com o veredicto de antes) e vira "pulada"
  if ! jq -e '.code_b64 | length > 0' "$innm" >/dev/null 2>&1; then
    rm -f "$innm"; SKIPPED+=("$subid:spool_falhou"); continue
  fi
  # provisório no history do dono + metrics (o placar/Situação leem só metrics) — e só então o spool aparece
  user_history_replace "$contest" "$r_login" "$subid" \
    "$r_tempo:$r_prob:$r_lang:Not Answered Yet:${r_sub:-$AGORA}:$subid"
  metrics_recompute "$contest" "$r_login"
  mv -f "$innm" "$sd/$spoolname"
  QUEUED+=("$subid")
done

qids="$( ((${#QUEUED[@]})) && { IFS=,; printf '%s' "${QUEUED[*]}"; } | head -c 300 )"
audit_log_to "$contest" rejudge "ids=${qids:-} count=${#QUEUED[@]} skipped=${#SKIPPED[@]}$( ((${#SKIPPED[@]})) && printf ' [%s]' "$(IFS=,; echo "${SKIPPED[*]}")" | head -c 150)"
# as listas crescem com o rejulgamento (todas as submissões de um problema numa prova grande = milhares de ids):
# nunca por --argjson — saem do stdin p/ um JSON que vai por ARQUIVO (ok_json_slurp)
_res="$( { printf 'Q\t%s\n' ${QUEUED[@]+"${QUEUED[@]}"}; printf 'S\t%s\n' ${SKIPPED[@]+"${SKIPPED[@]}"}; } \
  | jq -Rnc '[inputs | select(length > 2) | split("\t")] as $a
      | {q: [$a[] | select(.[0] == "Q") | .[1]], s: [$a[] | select(.[0] == "S") | .[1]]}')"
[[ -n "$_res" ]] || fail 500 "Falha ao montar a resposta" "build_fail"
ok_json_slurp '{action:"rejudge", queued:$r[0].q, count:($r[0].q|length), skipped:$r[0].s, skipped_count:($r[0].s|length)}' r "$_res"
