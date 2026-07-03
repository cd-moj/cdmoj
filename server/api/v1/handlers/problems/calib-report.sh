# GET /problems/calib-report?id=<id>&host=<host>&name=<name>   (Bearer)
# Serve o report.html (rico, do build-and-test) de UMA solução, gerado na calibração daquele
# juiz: run/calib/<id>/r/<host>/<name>.html. Os nomes vêm de GET /problems/calib (hosts[].reports).
require_method GET
require_auth
source "$_DIR/../../judge-gw/sched-lib.sh"   # valid_hostname
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"
: "${RUNDIR:=/home/ribas/moj/run}"; : "${CALIB_DIR:=$RUNDIR/calib}"

id="$(param id)"; [[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
require_problem_edit "$id"   # report.html da solução -> só dono/colaborador (corta na API)
host="$(param host)"; valid_hostname "$host" || fail 400 "Invalid host" "host_invalid"
name="$(param name | tr -cd 'A-Za-z0-9._-')"; [[ -n "$name" ]] || fail 400 "Missing name" "name_missing"

f="$CALIB_DIR/$id/r/$host/$name.html"
[[ -f "$f" ]] || fail 404 "Report não encontrado" "not_found"
emit_html
cat "$f"
