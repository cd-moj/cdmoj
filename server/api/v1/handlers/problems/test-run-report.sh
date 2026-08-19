# GET /problems/test-run-report?run=<32hex>  (Bearer) -> o report.html do test-run.
# Mesmo gate do registro: quem pode EDITAR o problema do run (404 opaco p/ o resto).
require_method GET
require_auth
source "$_DIR/lib/problems.sh"
: "${RUNDIR:=/home/ribas/moj/run}"
: "${TESTRUN_DIR:=$RUNDIR/testrun}"

run="$(param run)"
[[ "$run" =~ ^[a-f0-9]{32}$ ]] || fail 400 "run inválido" "run_invalid"
reg="$TESTRUN_DIR/$run.json"
[[ -s "$reg" ]] || fail 404 "Test-run não encontrado (expirado?)" "not_found"
pid="$(jq -r '.problem_id // empty' "$reg")"
valid_id "$pid" || fail 404 "Test-run não encontrado" "not_found"
require_problem_edit "$pid"

f="$TESTRUN_DIR/r/$run.html"
[[ -s "$f" ]] || fail 404 "Report não disponível (ainda julgando, ou o juiz não gerou)" "not_found"
emit_html
cat "$f"
