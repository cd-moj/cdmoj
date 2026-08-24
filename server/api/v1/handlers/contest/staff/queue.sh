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
# ESCOPO uma vez, não por arquivo. O laço antigo forkava jq DUAS vezes por tarefa (uma p/ ler o
# dono, outra p/ o staff_can_see) — com ~5 mil tarefas e 200 contas de staff polando a cada 5-8 s
# isso é dezenas de milhares de forks por segundo. staff_visible_logins já resolve o escopo em
# UMA passada em lote; rc≠0 = sem escopo = vê tudo (admin idem).
VIS_FILE=""
if ! is_admin; then
  VIS_FILE="$(mktemp)"
  staff_visible_logins "$contest" "$SESSION_LOGIN" > "$VIS_FILE" 2>/dev/null || { rm -f "$VIS_FILE"; VIS_FILE=""; }
fi
# UMA passada de jq sobre TODOS os arquivos; o recorte por escopo entra no PRÓPRIO jq, com o
# conjunto visível por --rawfile (nunca por argv — ARG_MAX; ver CLAUDE.md).
PICK='{id,seq,login,fullname,team,univ,kind:(.kind//"print"),short,color_hex,color_name,filename,mime,size,time,status,pages,build_ok,claimed_by,claimed_at,processed_by,processed_at,delivered_by,delivered_at}'
RANK='def rank: if .status=="pending" then 0 elif .status=="printed" then 1 else 2 end;'
if [[ -n "$VIS_FILE" ]]; then
  SEL='(($vis|split("\n")|map(select(length>0))|map({(.):true})|add) // {}) as $V | map(select($V[(.login // "")] == true))'
  out="$(find "$dir" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null \
    | xargs -0 -r jq -c "$PICK" 2>/dev/null \
    | jq -cs --rawfile vis "$VIS_FILE" "$RANK $SEL | sort_by(rank, .seq)" 2>/dev/null)"
  rm -f "$VIS_FILE"
else
  out="$(find "$dir" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null \
    | xargs -0 -r jq -c "$PICK" 2>/dev/null \
    | jq -cs "$RANK sort_by(rank, .seq)" 2>/dev/null)"
fi
[[ -n "$out" ]] || out='[]'
# balões que a regra do freeze suprimiu: contagem SÓ p/ o admin. É progresso agregado (quantos
# times resolveram durante o congelamento) — o .staff/.cstaff opera a fila, não precisa do número.
bfz=0
if is_admin; then bfz="$(pr_balloons_frozen_count "$contest")"; bfz="${bfz//[^0-9]/}"; bfz="${bfz:-0}"; fi
# a lista INTEIRA não pode ir por --argjson: são 128 KiB por argumento do jq, e com alguns
# milhares de tarefas (contest grande) isso estoura em "Argument list too long" -> 500
# build_fail. É a mesma classe do incidente de 2026-08-19; o helper existe para isso.
ok_json_slurp '{requests:$r[0], balloons_frozen:$bfz}' r "$out" --argjson bfz "$bfz"
