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

# gera (preguiçosamente) as tarefas de balão pendentes (1ª solução de cada time/problema) — DESTACADO: a consulta
# só dispara o reconcile e lista o que já está materializado; o balão novo aparece na consulta seguinte
# (pr_reconcile_balloons_bg, 15/10/2026 — o reconcile dentro da consulta era o p95 de 1,5 s da fila no ensaio)
pr_reconcile_balloons_bg "$contest"
# TAREFAS DE TESTE (pr_test_*): proibidas durante a prova — as que sobraram somem na 1ª consulta depois do início
pr_test_purge_if_running "$contest"

dir="$(pr_dir "$contest")"
# ESCOPO uma vez, não por arquivo. O laço antigo forkava jq DUAS vezes por tarefa (uma p/ ler o
# dono, outra p/ o staff_can_see) — com ~5 mil tarefas e 200 contas de staff polando a cada 5-8 s
# isso é dezenas de milhares de forks por segundo. staff_visible_logins já resolve o escopo em
# UMA passada em lote; rc≠0 = sem escopo = vê tudo (admin idem).
VIS_FILE=""
TV_FILE=""
if ! is_admin; then
  VIS_FILE="$(mktemp)"
  staff_visible_logins "$contest" "$SESSION_LOGIN" > "$VIS_FILE" 2>/dev/null || { rm -f "$VIS_FILE"; VIS_FILE=""; }
  # a tarefa de teste não tem time: entra pela SEDE de quem a criou (pr_task_can_see), em lote
  if [[ -n "$VIS_FILE" ]]; then TV_FILE="$(mktemp)"; pr_test_visible_ids "$contest" > "$TV_FILE" 2>/dev/null; fi
fi
# UMA passada de jq sobre TODOS os arquivos; o recorte por escopo entra no PRÓPRIO jq, com o
# conjunto visível por --rawfile (nunca por argv — ARG_MAX; ver CLAUDE.md).
# `first_site`: este balão é o PRIMEIRO daquela cor NA SEDE do time (★ + "first to solve" na
# fila e na folha). Só nasce decidido — ver pr_reconcile_balloons. Tarefa antiga não tem o campo
# e vem `false`, que é a leitura certa: nunca se anuncia um primeiro lugar que não foi apurado.
# só TAREFA (tem id): o staff-filters.json (e o badges.json legado) moram no mesmo diretório e viravam uma
# linha fantasma na fila do admin (data 1969, tudo vazio)
PICK='select((.id // "") != "") | {id,seq,test:(.test==true),login,fullname,team,univ,kind:(.kind//"print"),short,color_hex,color_name,first_site:(.first_site==true),filename,mime,size,time,status,pages,build_ok,claimed_by,claimed_at,processed_by,processed_at,delivered_by,delivered_at}'
RANK='def rank: if .status=="pending" then 0 elif .status=="printed" then 1 else 2 end;'
# BALÕES ESPERANDO a certeza do 1º da sede (lib/print.sh, `.balloon-hold`): a sala vê quantos e por quê, no mesmo
# escopo das tarefas; o admin vê também o problema e a run que segura (pend = sub_epoch dela, p/ liberar). Teto de 300 linhas (vai por --argjson).
HELD='[]'
if [[ -s "$dir/.balloon-hold" ]]; then
  HELD="$(jq -cs --rawfile vis "${VIS_FILE:-/dev/null}" --argjson scoped "$([[ -n "$VIS_FILE" ]] && echo true || echo false)" \
    --argjson adm "$(is_admin && echo true || echo false)" '
      (($vis|split("\n")|map(select(length>0))|map({(.):true})|add) // {}) as $V
      | map(select(($scoped | not) or $V[(.login // "")] == true))
      | sort_by(.since) | .[0:300]
      | map({login, short, region, since} + (if $adm then {problem, pend, sub_epoch} else {} end))' "$dir/.balloon-hold" 2>/dev/null)"
  [[ -n "$HELD" ]] || HELD='[]'
fi
if [[ -n "$VIS_FILE" ]]; then
  SEL='(($vis|split("\n")|map(select(length>0))|map({(.):true})|add) // {}) as $V
       | (($tv|split("\n")|map(select(length>0))|map({(.):true})|add) // {}) as $TV
       | map(select(if .test then $TV[.id] == true else $V[(.login // "")] == true end))'
  out="$(find "$dir" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null \
    | xargs -0 -r jq -c "$PICK" 2>/dev/null \
    | jq -cs --rawfile vis "$VIS_FILE" --rawfile tv "${TV_FILE:-/dev/null}" "$RANK $SEL | sort_by(rank, .seq)" 2>/dev/null)"
  rm -f "$VIS_FILE" "${TV_FILE:-}"
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
ok_json_slurp '{requests:$r[0], balloons_frozen:$bfz, held:$held}' r "$out" --argjson bfz "$bfz" --argjson held "$HELD"
