# lib/rename-cascade.sh — a CASCATA da troca de login do treino, fonte única (04/10/2026).
# Conta = diretório (rename = mv), mas o login aparece em muita coisa: o índice do Telegram, as orgs, as
# inscrições, os contests COMPARTILHADOS, as participações virtuais, a POSSE (problemas, contests, coleções,
# permissão de criar contest) e as sessões abertas. Quem usa:
#   · handlers/treino/profile/username.sh — o próprio usuário troca o handle (preserva o sufixo de papel);
#   · server/bin/user-promote.sh          — o admin da plataforma promove a conta a um papel (idlechara →
#                                           idlechara.admin), o que o usuário não pode fazer sozinho.
# Antes, a cascata morava inline no handler; uma promoção feita à parte esqueceria um elo (e cada elo
# esquecido já custou um incidente: posse solta, roster órfão, sessão que recriava o dir fantasma).
# Requer: lib/common.sh, auth.sh (rename_contest_sessions), users.sh (user_rename, shared_rename_login).
_RC_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -F tg_rename >/dev/null 2>&1 || source "$_RC_LIB/telegram.sh" 2>/dev/null
source "$_RC_LIB/orgs.sh"
source "$_RC_LIB/registration.sh"
source "$_RC_LIB/virtual.sh" 2>/dev/null
source "$_RC_LIB/owner-rename.sh" 2>/dev/null

# treino_rename_cascade <velho> <novo> -> ecoa o nº de sessões renomeadas; rc 1 se o mv da conta falhou.
# Quem chama SEGURA o lock (treino/var/profile.lock) e já conferiu: o velho existe, o novo está livre e não há
# submissão pendente (treino e contests compartilhados).
# (só o nº de sessões sai no stdout: quem chama o captura com $(…))
treino_rename_cascade(){
  local old="$1" new="$2"
  user_rename treino "$old" "$new" >/dev/null || return 1
  # o índice Telegram — by-login/by-tgid
  command -v tg_rename >/dev/null 2>&1 && tg_rename treino "$old" "$new" >/dev/null 2>&1 || true
  # ACESSO: members/admins de TODAS as orgs (sem isso a conta ficava órfã de todas — inclusive da implícita)
  orgs_rename_login "$old" "$new" >/dev/null || true
  # INSCRIÇÕES: sem isto a pessoa "sumia" do roster (e do time) de todo contest em que estava inscrita
  reg_rename_login "$old" "$new" >/dev/null || true
  # CONTESTS COMPARTILHADOS (USERS_FROM=treino): o dir local do participante segue o nome
  shared_rename_login treino "$old" "$new" >/dev/null || true
  # PARTICIPAÇÕES VIRTUAIS: o snapshot publicado fica no contest, chaveado pelo login
  declare -F vr_rename_login >/dev/null 2>&1 && vr_rename_login "$old" "$new" >/dev/null || true
  # A POSSE: o barato vale JÁ; os metas dos pacotes (1 commit cada) vão destacados (MOJ_JOBS_SYNC=1: na hora)
  if declare -F owner_rename_fast >/dev/null 2>&1; then
    owner_rename_fast "$old" "$new" >/dev/null; owner_rename_bg "$old" "$new" "$new" >/dev/null || true
  fi
  # TODAS as sessões do login seguem o novo nome (a sessão velha recriava o diretório fantasma)
  rename_contest_sessions treino "$old" "$new"
}
