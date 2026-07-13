# POST /problems/validate   (Bearer)   body: {id}      [era /problems/publish — alias deprecado]
# PORTÃO DE QUALIDADE, NÃO PUBLICAÇÃO. Roda o validador estático + gera o índice (HTML/enunciado) NO
# SERVIDOR, em background, e pede CALIBRAÇÃO a um juiz livre (que roda as soluções good = portão
# dinâmico, e reporta o TL). **NÃO mexe no flag `public`**: um problema privado continua privado —
# publicar é o /problems/set-public, que é quem checa a trava `public_allowed` da ORG.
# (O nome antigo, "publish", fazia parecer que validar publicava — e não havia como validar sem
# "publicar". Relatório: GET /problems/validation?id=…)
require_method POST
require_auth
source "$_DIR/../../judge-gw/sched-lib.sh"
source "$_DIR/lib/tl-store.sh"
source "$_DIR/lib/problems.sh"   # require_problem_edit (acesso por org)

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
[[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
require_problem_edit "$id"   # validar/calibrar é ação de autoria -> só dono/colaborador

# org = parte antes de '#' (ou '/'); pacote já está local (repo git por problema)
repo="${id%%#*}"; [[ "$repo" == "$id" ]] && repo="${id%%/*}"
index_problem_bg "$id" 1                                  # portão estático + HTML + índice (servidor)
reqid="$(cal_request "$repo" "$id" "$SESSION_LOGIN")"     # juiz calibra (roda as good) + reporta TL
audit_log "validate" "id=$id reqid=$reqid"
ok_json '{action:"validate", id:$i, reqid:$r, status:"queued"}' --arg i "$id" --arg r "$reqid"
