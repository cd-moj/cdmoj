# lib/sources.sh — a LISTA ÚNICA das libs do prelúdio da API. Dois consumidores:
#   - router.sh (caminho clássico): sourceia isto POR REQUISIÇÃO quando MOJ_LIBS_LOADED não
#     está setado (fcgiwrap, standalone, o setsid de contest/problems.sh);
#   - molde.sh (worker persistente): sourceia isto UMA vez no preload e seta MOJ_LIBS_LOADED.
# Lib nova no prelúdio entra AQUI (e só aqui) — lista duplicada foi vetada de propósito:
# uma lib a mais no router e a menos no molde viraria "function not found" só em produção.
# Espera $_DIR = raiz de api/v1 (o router e o molde o definem antes).
source "$_DIR/lib/common.sh"
source "$_DIR/lib/spool-shard.sh"
source "$_DIR/lib/params.sh"
source "$_DIR/lib/auth.sh"
source "$_DIR/lib/cli-version.sh"     # X-Moj-Cli-Status/Latest + dica p/ CLI antiga (aviso de CLI desatualizada)
source "$_DIR/lib/session-index.sh"   # índice por login + chave de máquina + sessão única
source "$_DIR/lib/site-lock.sh"       # trava de sede por IP (403 site_locked fora do contest dono)
source "$_DIR/lib/worker-auth.sh"
source "$_DIR/lib/bot-auth.sh"
source "$_DIR/lib/profile.sh"
source "$_DIR/lib/users.sh"
source "$_DIR/lib/verdict.sh"
source "$_DIR/lib/telegram.sh"
source "$_DIR/lib/alerts.sh"
