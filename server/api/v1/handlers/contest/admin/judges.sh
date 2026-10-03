# GET /contest/admin/judges?contest=<c>   (admin ou juiz-chefe do contest)
# Os juízes do registro pull — a lista do seletor de POOL de juízes em Regras (o mesmo formato do
# /problems/judges, lib/judges-registry.sh). Existe porque no subdomínio do contest o roteador só aceita rotas
# de contest: o seletor chamava /problems/judges e levava 403 `contest_isolated` a cada abertura do painel
# (TCP 2026 / LATAM, 03/10/2026), caindo no campo de texto livre.
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin_or_chief || fail 403 "Apenas o admin ou o juiz-chefe" "admin_required"
source "$_LIBDIR/judges-registry.sh"
ok_json '{judges:$j}' --argjson j "$(jr_list_json)"
