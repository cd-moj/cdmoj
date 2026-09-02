# GET /contest/admin/anomalies?contest=<c>[&round=<slug>]   (admin OU juiz-chefe)
# ANOMALIAS de uso de máquina durante a prova (motor em lib/anomalies.sh): time com 2 sessões
# vivas em máquinas diferentes, máquina com 2+ times, submissão vinda de máquina diferente da
# do login, UA fora do esperado da sede, sede com menos máquinas que times, trocas de máquina e
# a trilha da sessão única (revogações). SÓ vale com o gate de UA ligado (gate.active) — sem
# ele o navegador não identifica a máquina e a rota devolve só as contagens de sessão.
# Só leitura; cache de resposta de 15 s por rodada (o painel atualiza a cada 30 s).
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin_or_chief || fail 403 "Apenas o admin ou o juiz-chefe" "admin_required"
source "$_DIR/lib/users.sh"; source "$_DIR/lib/contest-create.sh"
source "$_DIR/lib/ua-gate.sh"; source "$_DIR/lib/contest-rounds.sh"; source "$_DIR/lib/anomalies.sh"

round="$(param round)"
if [[ -n "$round" ]]; then
  rd_valid_slug "$round" || fail 400 "round inválido" "round_invalid"
  [[ -n "$(rd_round "$contest" "$round")" ]] || fail 404 "Rodada não encontrada" "round_notfound"
fi
cdir="$CONTESTSDIR/$contest"
cf="$cdir/var/.anomalies-cache.${round:-active}.json"
if resp_cache_fresh "$cf" 15 "$cdir/var/access.log" "$cdir/var/submit-origin.log" \
     "$cdir/var/session-events.log" "$cdir/ua-gate.json" "$cdir/var/nutella.cache.json"; then
  emit_json 200 OK; cat "$cf"; exit 0
fi
outf="$(mktemp)" || fail 500 "tmp" "tmp"
if ! an_build "$contest" "$round" "$outf"; then rm -f "$outf"; fail 500 "Falha ao apurar anomalias" "build_fail"; fi
[[ -s "$outf" ]] || { rm -f "$outf"; fail 500 "Falha ao apurar anomalias" "build_fail"; }
# agregado cresce com o evento: por arquivo, nunca por --argjson (ARG_MAX)
ok_json '$a[0]' --slurpfile a "$outf"
resp_cache_store "$cf" "$OK_JSON_BODY"
rm -f "$outf"
