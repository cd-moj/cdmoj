# POST /ops/calib-cancel   (Bearer, admin)   body: {id, inprogress?:false}
# CANCELA calibrações de um problema na fila: remove as PENDENTES (updates/pending) e os
# comandos DIRECIONADOS ainda não entregues (commands/<host>). Por padrão NÃO toca as em
# execução (o juiz está rodando — a resposta traz `inflight` e a saída é `moj judges reset`);
# {inprogress:true} remove também os claims de updates/inprogress (o juiz ainda vai reportar
# nesse reqid — o report cai num reqid inexistente, inofensivo; use após um reset/restart).
require_method POST
require_admin
source "$_DIR/../../judge-gw/sched-lib.sh"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
[[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
with_inprog="$(jq -r '.inprogress // false' <<<"$body")"

removed_pending=0; removed_targeted=0; removed_inprog=0; inflight=0
mkdir -p "$UPDATESDIR/pending" 2>/dev/null

# As contagens saem por CAPTURA ($(…)), sem arquivo temporário: antes cada bloco gravava em
# "$UPDATESDIR/.cancel-*.${BASHPID}" de dentro de um SUBSHELL (ou com o redirect no subshell), onde o BASHPID
# é o do FILHO — o pai lia outro nome, então removed_pending/removed_inprogress/inflight saíam SEMPRE 0 e os
# temporários ficavam largados em UPDATESDIR (achado de 04/10/2026, mesma armadilha do tg_rename).

# pendentes (sob o MESMO lock do upd_claim — sem janela com um claim concorrente)
removed_pending="$( (
  flock 9 || exit 0
  n=0
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    jq -e --arg t "$id" '.kind=="calibrate" and .target==$t' "$f" >/dev/null 2>&1 || continue
    rm -f "$f" && n=$((n+1))
  done < <(find "$UPDATESDIR/pending" -maxdepth 1 -name '*.json' 2>/dev/null)
  echo "$n"
) 9>"$UPDATESDIR/.lock" )"
removed_pending="${removed_pending//[^0-9]/}"; removed_pending="${removed_pending:-0}"

# direcionados ainda não entregues (flock por host)
out="$(while IFS= read -r hostdir; do
  [[ -d "$hostdir" ]] || continue
  (
    flock 9 || exit 0
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      jq -e --arg t "$id" '.action=="calibrate" and .id==$t' "$f" >/dev/null 2>&1 || continue
      rm -f "$f" && echo x
    done < <(find "$hostdir" -maxdepth 1 -name '*.json' 2>/dev/null)
  ) 9>"$hostdir/.lock"
done < <(find "$CMDDIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null))"
removed_targeted="${out//[^x]/}"; removed_targeted="${#removed_targeted}"

# em execução: conta sempre; remove SÓ com inprogress:true
out="$( (
  flock 9 || exit 0
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    jq -e --arg t "$id" '.kind=="calibrate" and .target==$t' "$f" >/dev/null 2>&1 || continue
    if [[ "$with_inprog" == true ]]; then rm -f "$f" && echo r; else echo i; fi
  done < <(find "$UPDATESDIR/inprogress" -mindepth 2 -name '*.json' 2>/dev/null)
) 9>"$UPDATESDIR/.lock" )"
removed_inprog="${out//[^r]/}"; removed_inprog="${#removed_inprog}"
inflight="${out//[^i]/}"; inflight="${#inflight}"

audit_log "calib-cancel" "id=$id pending=$removed_pending targeted=$removed_targeted inprog_removed=$removed_inprog inflight=$inflight"
ok_json '{action:"calib-cancel", id:$id, removed_pending:$p, removed_targeted:$t,
          removed_inprogress:$r, inflight:$i}' \
  --arg id "$id" --argjson p "$removed_pending" --argjson t "$removed_targeted" \
  --argjson r "$removed_inprog" --argjson i "$inflight"
