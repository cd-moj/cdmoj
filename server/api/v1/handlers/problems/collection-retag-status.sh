# GET /problems/collection-retag-status?[job=<id>][&name=<coleção>]   (Bearer)
# Situação dos JOBS de retag de coleção (rename/delete rodam em background — antes o único
# sinal era uma linha de audit-log e falha parcial era invisível). Devolve os jobs do
# registro var/retag-jobs.json (últimos ~50), mais novos primeiro:
#   {jobs:[{id, from, to, by, started_at, total?, done, failed, finished_at?}]}
# `job=` filtra por id exato (o rename/delete devolvem `retag_job`); `name=` filtra por
# nome de coleção (from OU to). Job sem `finished_at` = ainda rodando (done/total = progresso).
# Gate: só autenticação — o conteúdo é nome de coleção + contagens (nada sensível; o
# registro de coleções já é listável por qualquer login via /problems/collections).
require_method GET
require_auth
source "$_DIR/lib/problems.sh"
job="$(param job)"; name="$(param name)"
jobs='{}'
[[ -f "$RETAG_JOBS" ]] && jobs="$(cat "$RETAG_JOBS" 2>/dev/null)"
[[ -n "$jobs" ]] || jobs='{}'
out="$(jq -c --arg j "$job" --arg n "$name" '
  to_entries | map({id:.key} + .value)
  | (if $j != "" then map(select(.id == $j)) else . end)
  | (if $n != "" then map(select(.to == $n or .from == $n)) else . end)
  | sort_by(-(.started_at // 0))' <<<"$jobs" 2>/dev/null)"
[[ -n "$out" ]] || out='[]'
ok_json '{jobs:$j}' --argjson j "$out"
