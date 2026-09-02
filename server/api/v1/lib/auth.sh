# lib/auth.sh — sessões por token (Bearer), guardadas em $SESSIONDIR (modo 700).
# Padrão: header `Authorization: Bearer <token>` (HTTP_AUTHORIZATION).
# Compat: aceita header não-padrão `Bearer: <token>` (HTTP_BEARER) do sistema antigo.

_bearer_token() {
  local a="${HTTP_AUTHORIZATION:-}"
  if [[ "$a" == "Bearer "* ]]; then printf '%s' "${a#Bearer }"; return; fi
  printf '%s' "${HTTP_BEARER:-}"
}

SESSION_TOKEN=""; SESSION_CONTEST=""; SESSION_LOGIN=""; SESSION_NAME=""; SESSION_AT=""
# SESSION_ACTOR = a PESSOA por trás da sessão quando ela não é o próprio login: num contest
# com times (lib/registration.sh), o membro entra com a credencial dele e a sessão é do TIME —
# SESSION_LOGIN é o time (é o competidor: placar, balões, impressão) e SESSION_ACTOR é quem
# estava no teclado. Vazio = sessão comum.
SESSION_ACTOR=""
SESSION_IP=""; SESSION_UA_B64=""; SESSION_MKEY=""

# _session_account_alive <contest> <login> — a conta da sessão ainda EXISTE?
# Sessão do MOJ não expira, então sem este teste ela continua autenticada como um login que
# já não existe: foi assim que uma sessão aberta ANTES de uma troca de handle seguiu submetendo
# com o nome velho e o /submit (mkdir -p) RECRIOU o diretório do usuário renomeado (fantasma
# sem account.json, que ainda aparecia como "solver" nas estatísticas).
# ⚠ O teste tem de ser AQUI, não no submit: em contest com USERS_FROM o participante
# compartilhado tem dir local SEM account.json de propósito (a identidade vem da fonte — ver
# sc_users em score/score-common.sh), e um user_exists cru barraria submissão legítima.
# A fonte só é consultada quando o account.json local falta: custo zero no caminho comum.
_session_account_alive() {
  local c="$1" u="$2" src
  [[ -n "$c" && -n "$u" ]] || return 1
  valid_id "$c" && valid_id "$u" || return 1
  [[ -f "$CONTESTSDIR/$c/users/$u/account.json" ]] && return 0
  src="$(_users_source "$c")"
  [[ "$src" != "$c" && -f "$CONTESTSDIR/$src/users/$u/account.json" ]]
}

# load_session -> 0 se autenticado (popula SESSION_*), 1 caso contrário.
load_session() {
  SESSION_TOKEN="$(_bearer_token)"
  [[ -n "$SESSION_TOKEN" ]] || return 1
  valid_id "$SESSION_TOKEN" || return 1
  local f="$SESSIONDIR/$SESSION_TOKEN"
  [[ -f "$f" ]] || return 1
  local CONTEST="" LOGIN="" USERFULLNAME="" LOGINAT="" ACTOR="" IP="" UA_B64="" MKEY=""
  source "$f"
  SESSION_CONTEST="$CONTEST"; SESSION_LOGIN="$LOGIN"
  SESSION_NAME="$USERFULLNAME"; SESSION_AT="$LOGINAT"; SESSION_ACTOR="$ACTOR"
  # origem da sessão (IP/UA/chave de máquina do LOGIN): o /submit compara com a origem da
  # requisição p/ a trilha de "submissão de outra máquina" (lib/session-index.sh)
  SESSION_IP="$IP"; SESSION_UA_B64="$UA_B64"; SESSION_MKEY="$MKEY"
  [[ -n "$SESSION_LOGIN" ]] || return 1
  _session_account_alive "$SESSION_CONTEST" "$SESSION_LOGIN"
}

require_auth() { load_session || fail 401 "Not authenticated" "auth_required"; }
require_auth_contest() {  # require_auth_contest <contest>
  require_auth
  [[ "$SESSION_CONTEST" == "$1" ]] || fail 403 "Not logged into this contest" "auth_contest"
}

# papéis por substring no username (convenção do MOJ)
is_admin(){ [[ "$SESSION_LOGIN" == *.admin ]]; }
# .cjudge (juiz-chefe) HERDA os poderes de juiz; .admin também é juiz.
is_judge(){ [[ "$SESSION_LOGIN" == *.judge || "$SESSION_LOGIN" == *.cjudge || "$SESSION_LOGIN" == *.admin ]]; }
is_chief(){ [[ "$SESSION_LOGIN" == *.cjudge ]]; }
is_admin_or_chief(){ is_admin || is_chief; }
is_staff(){ [[ "$SESSION_LOGIN" == *.staff ]]; }
# .cstaff (chefe de staff de uma sede) NÃO herda .staff: ele VÊ (etiquetas com senha, fila de
# staff, cerimônia de revelação da sede) mas não AGE — handlers testam is_cstaff explicitamente.
is_cstaff(){ [[ "$SESSION_LOGIN" == *.cstaff ]]; }
is_mon(){ [[ "$SESSION_LOGIN" == *.mon ]]; }
# .animeitor = quem opera o TELÃO. Não submete e não julga: vê o placar SEMPRE DESCONGELADO
# (é ele quem conduz a revelação), gere as FOTOS dos times e as chaves do webcast que alimenta
# o sistema Animeitor. Não herda nada e nada herda dele — handlers testam is_animeitor.
is_animeitor(){ [[ "$SESSION_LOGIN" == *.animeitor ]]; }
# is_reserved_role_login <login> — 0 se o login termina num SUFIXO DE PAPEL reservado. Helper
# central p/ (a) o auto-cadastro NUNCA criar papel por sufixo (signup web/bot) e (b) os handlers
# de admin de contest NÃO tratarem conta privilegiada como aluno (disable/troca de senha em massa/
# logout em massa). NÃO trava o /admin/adduser (admin autenticado cria .judge/.staff de um contest
# legitimamente). Mantém a lista em UM lugar (awk não enxerga a função — ao replicar em regex,
# lembre do .cjudge/.cstaff/.animeitor: \.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$).
is_reserved_role_login(){ case "$1" in *.admin|*.judge|*.cjudge|*.staff|*.cstaff|*.mon|*.animeitor) return 0;; *) return 1;; esac; }
require_admin(){ require_auth; is_admin || fail 403 "Admin only" "admin_required"; }
require_judge(){ require_auth; is_judge || fail 403 "Judge only" "judge_required"; }
require_chief(){ require_auth; is_chief || fail 403 "Chief judge only" "chief_required"; }

# _users_source <contest> — fonte dos usuários: USERS_FROM do conf (ex.: treino) se válido,
# senão o próprio contest. Lido com grep (NÃO faz source do conf no caminho de auth).
_users_source() {
  local c="$1" line src
  line="$(grep -m1 '^USERS_FROM=' "$CONTESTSDIR/$c/conf" 2>/dev/null)"
  src="${line#USERS_FROM=}"; src="${src%\'}"; src="${src#\'}"; src="${src%\"}"; src="${src#\"}"
  if [[ -n "$src" ]] && valid_id "$src" && [[ "$src" != "$c" ]] && [[ -d "$CONTESTSDIR/$src/users" ]]; then
    printf '%s' "$src"
  else printf '%s' "$c"; fi
}

# verify_password <contest> <login> <pass> — confere o users/<login>/account.json do PRÓPRIO
# contest (O(1)) e, se houver USERS_FROM, cai para a fonte compartilhada (ex.: treino).
# valid_id no login ANTES de montar caminho (input do usuário — sem traversal). Senha com
# prefixo '!' = conta desativada (o literal nunca casa com o que o usuário digita).
verify_password() {
  valid_id "$2" || return 1
  local p
  p="$(jq -r '.password // empty' "$CONTESTSDIR/$1/users/$2/account.json" 2>/dev/null)"
  [[ -n "$p" && "$p" == "$3" ]] && return 0
  local src; src="$(_users_source "$1")"
  [[ "$src" != "$1" ]] || return 1
  p="$(jq -r '.password // empty' "$CONTESTSDIR/$src/users/$2/account.json" 2>/dev/null)"
  [[ -n "$p" && "$p" == "$3" ]]
}
user_fullname() {  # <contest> <login> — account.json próprio primeiro, depois USERS_FROM
  valid_id "$2" || return 1
  local n; n="$(jq -r '.fullname // empty' "$CONTESTSDIR/$1/users/$2/account.json" 2>/dev/null)"
  [[ -n "$n" ]] && { printf '%s' "$n"; return; }
  local src; src="$(_users_source "$1")"
  [[ "$src" != "$1" ]] && jq -r '.fullname // empty' "$CONTESTSDIR/$src/users/$2/account.json" 2>/dev/null
}

# IP do cliente: 1º hop de X-Forwarded-For, senão X-Real-IP/REMOTE_ADDR.
# Sanitizado (só chars de IP) — o arquivo de sessão é "sourced", então nada de metachars.
client_ip(){
  local ip="${HTTP_X_FORWARDED_FOR:-}"; ip="${ip%%,*}"
  [[ -z "$ip" ]] && ip="${HTTP_X_REAL_IP:-${REMOTE_ADDR:-}}"
  printf '%s' "$ip" | tr -cd '0-9a-fA-F.:'
}

# create_session <contest> <login> <name> [actor] -> ecoa o token (uuid)
# <actor> só é gravado quando a sessão é de um TIME (o membro que autenticou) — ver
# SESSION_ACTOR acima e o alias em handlers/auth/login.sh.
# Grava também MKEY (chave de máquina do UA/IP — lib/session-index.sh) e indexa o token por
# login (é o que permite "sessão única por time" sem varrer o diretório no login).
create_session() {
  mkdir -p "$SESSIONDIR"; chmod 700 "$SESSIONDIR" 2>/dev/null
  local uuid; uuid="$(</proc/sys/kernel/random/uuid)"
  local ip ua mk
  ip="$(client_ip)"
  ua="$(printf '%s' "${HTTP_USER_AGENT:-}" | base64 -w0)"   # b64 p/ não injetar no source
  mk="$(sess_machine_key "$ip" "${HTTP_USER_AGENT:-}")"
  ( umask 077
    {
      printf 'CONTEST=%q\n'      "$1"
      printf 'LOGIN=%q\n'        "$2"
      printf 'USERFULLNAME=%q\n' "$3"
      printf 'LOGINAT=%q\n'      "$EPOCHSECONDS"
      printf 'IP=%q\n'           "$ip"
      printf 'UA_B64=%q\n'       "$ua"
      printf 'MKEY=%q\n'         "$mk"
      [[ -n "${4:-}" ]] && printf 'ACTOR=%q\n' "$4"
    } > "$SESSIONDIR/$uuid"
  )
  sess_index_add "$1" "$2" "$uuid"
  printf '%s' "$uuid"
}
destroy_session(){ [[ -n "${1:-}" ]] && valid_id "$1" && rm -f "$SESSIONDIR/$1"; }

# remove_contest_sessions <contest> [login] -> ecoa o nº de sessões removidas.
# Sem <login>, remove todas do contest. Usado por deslogar/desabilitar usuário.
# É a varredura COMPLETA (autoritativa) — o índice de lib/session-index.sh é só o atalho do
# login; a entrada dele que ficar órfã é podada na leitura.
remove_contest_sessions(){
  local n; n="$(remove_contest_sessions_v "$1" "${2:-}" | wc -l | tr -d '[:space:]')"
  printf '%s' "${n:-0}"
}
# remove_contest_sessions_v <contest> [login] -> uma linha por sessão removida:
# token \t login \t mkey  (p/ quem precisa registrar o evento — logout-user, logout-mismatch)
remove_contest_sessions_v(){
  local c="$1" want="${2:-}" f CONTEST LOGIN MKEY
  set +o noglob; shopt -s nullglob
  for f in "$SESSIONDIR"/*; do
    [[ -f "$f" ]] || continue
    CONTEST=""; LOGIN=""; MKEY=""; source "$f" 2>/dev/null
    [[ "$CONTEST" == "$c" ]] || continue
    [[ -z "$want" || "$LOGIN" == "$want" ]] || continue
    rm -f "$f" && printf '%s\t%s\t%s\n' "${f##*/}" "$LOGIN" "$MKEY"
  done
  shopt -u nullglob
}

# rename_contest_sessions <contest> <old> <new> -> ecoa o nº de sessões reescritas.
# A conta é um DIRETÓRIO (rename = mv); as sessões guardam o login em texto, então TODAS
# as sessões daquela conta têm de seguir o novo nome — não só o token da requisição que
# pediu a troca. Sem isso, a aba do outro computador (ou o token do moj-cli) continuava
# valendo com o login velho até alguém submeter por ela.
# Casa por FONTE de usuários: sessão de contest que herda os usuários de <contest>
# (USERS_FROM) é do mesmo login e também é reescrita.
rename_contest_sessions(){
  local c="$1" old="$2" new="$3"
  [[ -n "$c" && -n "$old" && -n "$new" && "$old" != "$new" ]] || { printf '0'; return 0; }
  local qnew; printf -v qnew '%q' "$new"
  ( set +o noglob; shopt -s nullglob
    local n=0 f tmp CONTEST LOGIN ACTOR
    for f in "$SESSIONDIR"/*; do
      [[ -f "$f" ]] || continue
      CONTEST=""; LOGIN=""; ACTOR=""; source "$f" 2>/dev/null
      # o ATOR também segue: numa sessão de time o login é o time e o ator é o membro
      [[ ( "$LOGIN" == "$old" || "$ACTOR" == "$old" ) && -n "$CONTEST" ]] || continue
      [[ "$(_users_source "$CONTEST")" == "$c" ]] || continue
      # a decisão é do bash (já temos os valores do source); o awk só reescreve a chave
      local dol=0 doa=0
      [[ "$LOGIN" == "$old" ]] && dol=1
      [[ "$ACTOR" == "$old" ]] && doa=1
      tmp="$(mktemp "$f.XXXXXX")" || continue
      if _NEWLOGIN="$qnew" _DOL="$dol" _DOA="$doa" awk '
             /^LOGIN=/ && ENVIRON["_DOL"] == "1" { print "LOGIN=" ENVIRON["_NEWLOGIN"]; next }
             /^ACTOR=/ && ENVIRON["_DOA"] == "1" { print "ACTOR=" ENVIRON["_NEWLOGIN"]; next }
             {print}' \
           "$f" > "$tmp" 2>/dev/null; then
        chmod 600 "$tmp" 2>/dev/null; mv -f "$tmp" "$f" && ((n++))
        # o índice por login (lib/session-index.sh) é chaveado pelo LOGIN: o token passa a
        # existir sob o nome novo (a entrada velha é podada na leitura, porque LOGIN difere)
        (( dol )) && sess_index_add "$CONTEST" "$new" "${f##*/}"
      else rm -f "$tmp"; fi
    done
    printf '%s' "$n" )
}
