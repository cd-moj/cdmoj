# GET  /treino/admin/queue  (.admin) -> submissões pendentes (por contest/lista) + spool + calibração
#      &details=1            -> pending_details: CADA pendente (quem, o quê, desde quando, estado)
#      &sub=<c>:<login>:<id> -> dossiê de UMA pendente (linha do history, mojlog, fonte, spool)
# POST /treino/admin/queue   -> agir sobre uma pendente (auditado queue-resolve):
#      {action:"requeue", contest, login, id}                      re-enfileira (exige fonte arquivada)
#      {action:"resolve", contest, login, id, verdict:"Judge Error"|"Compilation Error"}
#
# Nasceu do incidente 2026-08-19 (6 submissões "Not Answered Yet" para sempre): o admin via o
# NÚMERO no painel mas não tinha como saber QUAIS eram, ver os logs nem resolvê-las.
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
source "$_DIR/../../judge-gw/sched-lib.sh"   # contadores da fila de calibração (UPDATESDIR/CMDDIR)

_PENDING_RE=':(Not Answered Yet|On queue|on queue|Running|running):'

# estado no pipeline de UMA submissão (pelo id): onde está o rastro dela?
_sub_state(){  # <id>
  local id="$1"
  compgen -G "$SPOOLDIR/*:$id:*" >/dev/null 2>&1 && { printf 'no-spool'; return; }
  compgen -G "${QUEUEDIR:-$RUNDIR/queue}/*/*_$id.json" >/dev/null 2>&1 && { printf 'na-fila'; return; }
  compgen -G "${ASSIGNEDDIR:-$RUNDIR/assigned}/*/*_$id.json" >/dev/null 2>&1 && { printf 'em-julgamento'; return; }
  compgen -G "$SPOOLDONEDIR/*:$id:*" >/dev/null 2>&1 && { printf 'consumido-sem-veredicto'; return; }
  printf 'sem-rastro'
}

# ---------- POST: requeue / resolve ----------
if [[ "${REQUEST_METHOD:-GET}" == POST ]]; then
  body="$(read_body)"
  jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
  action="$(jq -r '.action // ""' <<<"$body")"
  c="$(jq -r '.contest // ""' <<<"$body")"; login="$(jq -r '.login // ""' <<<"$body")"
  id="$(jq -r '.id // ""' <<<"$body")"
  valid_id "$c" && [[ -d "$CONTESTSDIR/$c" ]] || fail 400 "contest inválido" "contest_invalid"
  valid_id "$login" || fail 400 "login inválido" "login_invalid"
  [[ "$id" =~ ^[0-9a-f]{32}$ ]] || fail 400 "id inválido" "id_invalid"
  hf="$(user_hist_file "$c" "$login")"
  hline="$(awk -F: -v id="$id" '$NF==id{print; exit}' "$hf" 2>/dev/null)"
  [[ -n "$hline" ]] || fail 404 "Submissão não está no history" "sub_notfound"
  prob="$(awk -F: '{print $2}' <<<"$hline")"; lang="$(awk -F: '{print $3}' <<<"$hline")"
  se="$(awk -F: '{print $(NF-1)}' <<<"$hline")"
  case "$action" in
    requeue)
      llang="$(printf '%s' "$lang" | tr '[:upper:]' '[:lower:]')"
      src="$(user_dir "$c" "$login")/submissions/$id.${llang:-txt}"
      [[ -s "$src" ]] || fail 409 "Sem fonte arquivada — não há o que rejulgar (resolva com um veredicto)" "no_source"
      mkdir -p "$SPOOLDIR"
      : > "$SPOOLDIR/$c:${se:-$EPOCHSECONDS}:$id:$login:rejulgar:$prob:$lang"
      audit_log_to "$c" queue-resolve "requeue id=$id login=$login prob=$prob by=$SESSION_LOGIN"
      touch "$CONTESTSDIR/$c/var/.score-dirty" 2>/dev/null
      ok_json '{requeued:true, id:$i}' --arg i "$id"
      ;;
    resolve)
      verdict="$(jq -r '.verdict // ""' <<<"$body")"
      case "$verdict" in "Judge Error"|"Compilation Error") ;; *)
        fail 400 "verdict deve ser 'Judge Error' ou 'Compilation Error'" "verdict_invalid";; esac
      source "$_DIR/lib/review.sh"
      rv_emit_setverdict "$c" "$id" "$login" "$prob" "$verdict"
      audit_log_to "$c" queue-resolve "resolve id=$id login=$login prob=$prob verdict=$verdict by=$SESSION_LOGIN"
      touch "$CONTESTSDIR/$c/var/.score-dirty" 2>/dev/null
      ok_json '{resolved:true, id:$i, verdict:$v}' --arg i "$id" --arg v "$verdict"
      ;;
    *) fail 400 "action deve ser requeue|resolve" "action_invalid";;
  esac
  exit 0
fi

# ---------- GET ?sub= : dossiê de UMA pendente ----------
subq="$(param sub)"
if [[ -n "$subq" ]]; then
  IFS=: read -r c login id <<<"$subq"
  valid_id "$c" && valid_id "$login" && [[ "$id" =~ ^[0-9a-f]{32}$ ]] || fail 400 "sub inválido (contest:login:id)" "sub_invalid"
  hf="$(user_hist_file "$c" "$login")"
  hline="$(awk -F: -v id="$id" '$NF==id{print; exit}' "$hf" 2>/dev/null)"
  [[ -n "$hline" ]] || fail 404 "Submissão não está no history" "sub_notfound"
  lang="$(awk -F: '{print $3}' <<<"$hline")"; llang="$(printf '%s' "$lang" | tr '[:upper:]' '[:lower:]')"
  src="$(user_dir "$c" "$login")/submissions/$id.${llang:-txt}"
  mlog="$(user_dir "$c" "$login")/mojlog/$id.html"
  W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
  # mojlog vai por ARQUIVO (--rawfile): pode ser grande, e argv tem teto de 128 KiB
  if [[ -s "$mlog" ]]; then head -c 262144 "$mlog" > "$W/log"; else : > "$W/log"; fi
  printf '%s' "$hline" > "$W/hline"
  ok_json '{history_line:$h, state:$st, has_source:$hs, source_bytes:$sb, mojlog:$lg, mojlog_bytes:$lb}' \
    --rawfile h "$W/hline" --arg st "$(_sub_state "$id")" \
    --argjson hs "$([[ -s "$src" ]] && echo true || echo false)" \
    --argjson sb "$(stat -c%s "$src" 2>/dev/null || echo 0)" \
    --rawfile lg "$W/log" --argjson lb "$(stat -c%s "$mlog" 2>/dev/null || echo 0)"
  exit 0
fi

# ---------- GET: contadores (+details) ----------
want_details="$(param details)"
set +o noglob; shopt -s nullglob
declare -a LISTS; total=0
DETF="$(mktemp)"; trap 'rm -f "$DETF"' EXIT
# itera por CONTEST (não por controle/history) — store-v2 não tem history global.
for cdir in "$CONTESTSDIR"/*/; do
  cdir="${cdir%/}"; cid="${cdir##*/}"
  [[ -f "$cdir/conf" ]] || continue
  n="$(count_pending "$cid")"; n="${n//[^0-9]/}"; n="${n:-0}"
  if (( n > 0 )); then
    cname="$( . "$cdir/conf" 2>/dev/null; printf '%s' "${CONTEST_NAME:-$cid}" )"
    LISTS+=("$(jq -cn --arg c "$cid" --arg nm "$cname" --argjson n "$n" '{contest:$c, name:$nm, pending:$n}')")
    ((total+=n))
    # detalhe: QUAIS são (teto de 100 no total — pendência de verdade é rara; o teto evita
    # que um acidente com milhares vire uma resposta gigante)
    if [[ "$want_details" == 1 ]]; then
      for hf in "$cdir"/users/*/history; do
        (( $(wc -l < "$DETF" 2>/dev/null || echo 0) < 100 )) || break
        grep -qE "$_PENDING_RE" "$hf" 2>/dev/null || continue
        login="${hf%/history}"; login="${login##*/}"
        while IFS= read -r line; do
          IFS=$'\x01' read -r se id prob lang \
            <<<"$(awk -F: '{printf "%s\x01%s\x01%s\x01%s", $(NF-1), $NF, $2, $3}' <<<"$line")"
          [[ "$se" =~ ^[0-9]+$ ]] || continue
          llang="$(printf '%s' "$lang" | tr '[:upper:]' '[:lower:]')"
          src="$(user_dir "$cid" "$login")/submissions/$id.${llang:-txt}"
          jq -cn --arg c "$cid" --arg l "$login" --arg p "$prob" --arg lg "$lang" --arg i "$id" \
             --argjson se "$se" --argjson age "$(( EPOCHSECONDS - se ))" \
             --arg st "$(_sub_state "$id")" \
             --argjson hs "$([[ -s "$src" ]] && echo true || echo false)" \
             '{contest:$c, login:$l, problem:$p, lang:$lg, id:$i, since:$se, age_s:$age,
               state:$st, has_source:$hs}' >> "$DETF"
        done < <(grep -E "$_PENDING_RE" "$hf" 2>/dev/null)
      done
    fi
  fi
done
shopt -u nullglob
spool=0
[[ -d "$SPOOLDIR" ]] && spool="$(find "$SPOOLDIR" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | wc -l)"
# fila de CALIBRAÇÃO (mesmo pool de juízes, filas à parte de run/queue): pendente (kind=calibrate,
# separada dos kind=index), em execução, e recalibrações direcionadas por host. Contador EXPLÍCITO,
# à parte das submissões normais (total_pending). Contadores já saneiam/def. 0.
calib_pending="$(upd_pending_kind_count calibrate)"
calib_inflight="$(upd_inprogress_kind_count calibrate)"
calib_targeted="$(cmd_action_count calibrate)"
lists="$( ((${#LISTS[@]})) && printf '%s\n' "${LISTS[@]}" | jq -cs 'sort_by(-.pending)' || echo '[]')"
# pendências por --slurpfile (nunca agregado por --argjson — teto de 128 KiB por argumento)
ok_json '{total_pending:$t, spool_queued:$sp, calib_pending:$cp, calib_inflight:$ci, calib_targeted:$ct,
          lists:$lists, pending_details:($d | sort_by(.since))}' \
  --argjson t "$total" --argjson sp "${spool:-0}" \
  --argjson cp "${calib_pending:-0}" --argjson ci "${calib_inflight:-0}" --argjson ct "${calib_targeted:-0}" \
  --argjson lists "$lists" --slurpfile d "$DETF"
