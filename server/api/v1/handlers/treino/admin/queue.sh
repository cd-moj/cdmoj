# GET /treino/admin/queue  (.admin) -> submissões pendentes (por contest/lista) + spool + calibração
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
source "$_DIR/../../judge-gw/sched-lib.sh"   # contadores da fila de calibração (UPDATESDIR/CMDDIR)
set +o noglob; shopt -s nullglob
declare -a LISTS; total=0
# itera por CONTEST (não por controle/history) — store-v2 não tem history global.
for cdir in "$CONTESTSDIR"/*/; do
  cdir="${cdir%/}"; cid="${cdir##*/}"
  [[ -f "$cdir/conf" ]] || continue
  n="$(count_pending "$cid")"; n="${n//[^0-9]/}"; n="${n:-0}"
  if (( n > 0 )); then
    cname="$( . "$cdir/conf" 2>/dev/null; printf '%s' "${CONTEST_NAME:-$cid}" )"
    LISTS+=("$(jq -cn --arg c "$cid" --arg nm "$cname" --argjson n "$n" '{contest:$c, name:$nm, pending:$n}')")
    ((total+=n))
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
ok_json '{total_pending:$t, spool_queued:$sp, calib_pending:$cp, calib_inflight:$ci, calib_targeted:$ct, lists:$lists}' \
  --argjson t "$total" --argjson sp "${spool:-0}" \
  --argjson cp "${calib_pending:-0}" --argjson ci "${calib_inflight:-0}" --argjson ct "${calib_targeted:-0}" \
  --argjson lists "$lists"
