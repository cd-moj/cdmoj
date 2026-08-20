# GET /contest/staff/queue?contest=<c>   (Bearer; .staff, .cstaff ou .admin)
# Fila de tarefas de impressão visíveis a ESTE staff (escopo por staff-filters). Admin vê
# tudo. O .cstaff (chefe de sede) SÓ LÊ a fila do escopo dele — as ações (print-action) e
# o PDF (print-pdf/print-file) continuam vedados a ele (403 lá).
# Ordena: pendentes primeiro, depois impressas, depois entregues; dentro, por nº seq.
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_staff || is_cstaff || is_admin; } || fail 403 "Apenas staff" "staff_required"
source "$_LIBDIR/print.sh"

# gera (preguiçosamente) as tarefas de balão pendentes (1ª solução de cada time/problema)
pr_reconcile_balloons "$contest"

dir="$(pr_dir "$contest")"
set +o noglob; shopt -s nullglob
items=()
for j in "$dir"/*.json; do
  [[ -f "$j" ]] || continue
  own="$(jq -r '.login // ""' "$j" 2>/dev/null)"
  staff_can_see "$contest" "$SESSION_LOGIN" "$own" || continue
  items+=("$(jq -c '{id,seq,login,fullname,team,univ,kind:(.kind//"print"),short,color_hex,color_name,filename,mime,size,time,status,pages,claimed_by,claimed_at,processed_by,processed_at,delivered_by,delivered_at}' "$j" 2>/dev/null)")
done
shopt -u nullglob
out="$( ((${#items[@]})) && printf '%s\n' "${items[@]}" | jq -cs '
  def rank: if .status=="pending" then 0 elif .status=="printed" then 1 else 2 end;
  sort_by(rank, .seq)' || echo '[]')"
# balões que a regra do freeze suprimiu: contagem SÓ p/ o admin. É progresso agregado (quantos
# times resolveram durante o congelamento) — o .staff/.cstaff opera a fila, não precisa do número.
bfz=0
if is_admin; then bfz="$(pr_balloons_frozen_count "$contest")"; bfz="${bfz//[^0-9]/}"; bfz="${bfz:-0}"; fi
ok_json '{requests:$r, balloons_frozen:$bfz}' --argjson r "$out" --argjson bfz "$bfz"
