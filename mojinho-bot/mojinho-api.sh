#!/bin/bash
#
# mojinho-api.sh — bot Telegram do MOJ, agora como CLIENTE FINO DA API REST.
#
# Diferenças do mojinho.sh original:
#   * NÃO escreve mais arquivos no spool nem fala `nc` direto com os juízes.
#     Toda ação do MOJ vira uma chamada HTTP à API v1 (curl + Host header).
#   * O token do Telegram vem SÓ do arquivo ./token (nunca hardcoded).
#   * Config (endpoint da API, host, credenciais de admin e lista de GODS) vem
#     de ./bot.conf (veja bot.conf.sample).
#   * Continuam locais (sem API): /cantar, /amigod, /help e os logs de auditoria.
#
# Rodar como serviço: server/etc/systemd/moj-bot.service (ExecStart -> este script).
#
# Dependências: bash, curl, jq.  (o original usava jshon; aqui é tudo jq.)
set -o pipefail

# ---------------------------------------------------------------------------
# Diretório do bot: tudo (token, bot.conf, musica.*, logs, offset) é relativo a ele.
# ---------------------------------------------------------------------------
BOTDIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
cd "$BOTDIR" || { echo "FATAL: não consegui entrar em $BOTDIR" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Token do Telegram — SOMENTE do arquivo ./token.
# Formato tolerante: pega a primeira linha que pareça um token de bot
# (<digitos>:<resto>); ignora linhas de lixo/comentário.
# ---------------------------------------------------------------------------
TOKEN="$(grep -aoE '[0-9]{6,}:[A-Za-z0-9_-]{20,}' "$BOTDIR/token" 2>/dev/null | head -n1)"
if [[ -z "$TOKEN" ]]; then
  echo "FATAL: token do Telegram não encontrado em $BOTDIR/token" >&2
  exit 1
fi
API_TG="https://api.telegram.org/bot$TOKEN"

# ---------------------------------------------------------------------------
# Configuração (./bot.conf). Defaults seguros; bot.conf sobrescreve.
# ---------------------------------------------------------------------------
MOJ_API="http://127.0.0.1:8080/api/v1"          # base da API REST
MOJ_HOST="moj.charge.naquadah.com.br"           # Host: que o nginx roteia
MOJ_WEB="https://moj.charge.naquadah.com.br"    # base pública p/ links de acesso
MOJ_ADMIN_CONTEST="treino"                      # contest do usuário .admin
MOJ_ADMIN_USER=""                               # login admin (termina em .admin)
MOJ_ADMIN_PASS=""                               # senha do admin
declare -A GODS                                  # lista de admins do Telegram

if [[ -f "$BOTDIR/bot.conf" ]]; then
  # shellcheck disable=SC1091
  source "$BOTDIR/bot.conf"
else
  echo "AVISO: $BOTDIR/bot.conf não existe; usando defaults (copie bot.conf.sample)." >&2
fi

# ---------------------------------------------------------------------------
# Estado / helpers de token da API (login cacheado, re-login no 401).
# ---------------------------------------------------------------------------
MOJ_TOKEN=""

# moj_login: faz POST /auth/login?contest=<admin-contest> e popula MOJ_TOKEN.
# Retorna 0/1.
moj_login() {
  MOJ_TOKEN=""
  if [[ -z "$MOJ_ADMIN_USER" || -z "$MOJ_ADMIN_PASS" ]]; then
    echo "moj_login: MOJ_ADMIN_USER/MOJ_ADMIN_PASS não configurados em bot.conf" >&2
    return 1
  fi
  local body resp
  body="$(jq -cn --arg u "$MOJ_ADMIN_USER" --arg p "$MOJ_ADMIN_PASS" \
            '{username:$u, password:$p}')"
  resp="$(curl -s -m 30 \
            -H "Host: $MOJ_HOST" \
            -H 'Content-Type: application/json' \
            -d "$body" \
            "$MOJ_API/auth/login?contest=$MOJ_ADMIN_CONTEST")"
  MOJ_TOKEN="$(jq -r '.token // empty' <<<"$resp" 2>/dev/null)"
  [[ -n "$MOJ_TOKEN" ]] || { echo "moj_login falhou: $resp" >&2; return 1; }
  return 0
}

# moj_token: garante um token válido (loga se não houver). Ecoa o token.
moj_token() {
  [[ -n "$MOJ_TOKEN" ]] || moj_login || return 1
  printf '%s' "$MOJ_TOKEN"
}

# api <METHOD> <path> [curl-args...]
#   Faz a chamada à API com Host + Bearer. Se vier 401, re-loga UMA vez e repete.
#   Saída em stdout: corpo da resposta seguido de uma última linha "HTTP <code>".
#   Use api_body / api_status (abaixo) para separar.
api() {
  local method="$1" path="$2"; shift 2
  local tok out code
  tok="$(moj_token)" || { printf 'HTTP 000\n'; return 1; }

  _api_call() {
    curl -s -m 60 -w $'\nHTTP %{http_code}' -X "$method" \
      -H "Host: $MOJ_HOST" \
      -H "Authorization: Bearer $tok" \
      "$@" \
      "$MOJ_API$path"
  }

  out="$(_api_call "$@")"
  code="$(tail -n1 <<<"$out" | awk '{print $2}')"
  if [[ "$code" == "401" ]]; then
    moj_login || { printf '%s\n' "$out"; return 1; }
    tok="$MOJ_TOKEN"
    out="$(_api_call "$@")"
  fi
  printf '%s\n' "$out"
}

# Separadores da saída de api():
api_status() { tail -n1 <<<"$1" | awk '{print $2}'; }   # ex.: 200
api_body()   { sed '$d' <<<"$1"; }                       # tudo menos a última linha

# err_msg <body>: extrai .error.message (ou texto cru) p/ mensagens amigáveis.
err_msg() {
  local m; m="$(jq -r '.error.message // empty' <<<"$1" 2>/dev/null)"
  [[ -n "$m" ]] && { printf '%s' "$m"; return; }
  printf '%s' "$1"
}

# ---------------------------------------------------------------------------
# Helpers de resposta do Telegram (mantidos do original).
#   SUBMITJSON é o objeto de mensagem; o loop principal injeta chat_id e envia.
# ---------------------------------------------------------------------------
# tg_send_document <file> [caption]: envia um arquivo p/ $REPLYTO.
tg_send_document() {
  local file="$1" caption="$2"
  if [[ -n "$caption" ]]; then
    curl -s -F chat_id="$REPLYTO" -F caption="$caption" \
      -F document=@"$file" "$API_TG/sendDocument" >/dev/null
  else
    curl -s -F chat_id="$REPLYTO" -F document=@"$file" \
      "$API_TG/sendDocument" >/dev/null
  fi
}

# set_text <text>: monta SUBMITJSON de texto simples (sem markdown).
set_text() { SUBMITJSON="$(jq -cn --arg t "$1" '{text:$t}')"; }
# set_text_md <text>: idem, com parse_mode Markdown.
set_text_md() { SUBMITJSON="$(jq -cn --arg t "$1" '{text:$t, parse_mode:"Markdown"}')"; }
# set_text_html <text>: idem, com parse_mode HTML.
set_text_html() { SUBMITJSON="$(jq -cn --arg t "$1" '{text:$t, parse_mode:"HTML"}')"; }

# ---------------------------------------------------------------------------
# Permissões (GODS).
# ---------------------------------------------------------------------------
checkgod() {
  set_text "Você não tem permissão para executar este comando."
  [[ "${GODS[$USERNAME]}" == "true" ]] && return 0
  return 1
}

# ===========================================================================
# COMANDOS LOCAIS (sem API) — mantidos do original.
# ===========================================================================
amigod() {
  local GOD=no
  [[ "${GODS[$USERNAME]}" == "true" ]] && GOD=yes
  set_text "@$USERNAME $GOD"
}

cantar() {
  local ARQM STRING="" LINE
  ARQM="$(ls "$BOTDIR"/musica.* 2>/dev/null | shuf -n1)"
  if [[ -z "$ARQM" ]]; then
    set_text "Sem músicas no momento. 🎵"
    return
  fi
  while IFS= read -r LINE; do
    STRING+="$LINE"$'\n'
  done < "$ARQM"
  set_text_md "$STRING"
  echo "$(date -R) $USERNAME ($FULLNAME) $(basename "$ARQM")" >> "$BOTDIR/log-cantar.txt"
}

help() {
  local EXTRA=""
  if [[ "${GODS[$USERNAME]}" == true ]]; then
    EXTRA=$'\n'"Você ainda pode: *${!GODFUNCTIONS[*]}*"
  fi
  set_text_md "$USERNAME comandos aceitos: *${!ALLOWEDFUNCTIONS[*]}*.$EXTRA"
}

erro() {
  set_text "Comando desconhecido $*, comandos aceitos: ${!ALLOWEDFUNCTIONS[*]}"
}

# ===========================================================================
# COMANDOS QUE FALAM COM A API
# ===========================================================================

# /participar CONTEST [SIGLA]  -> POST /admin/adduser  (responde login+senha+URL)
participar() {
  local FNAME LNAME UNAME CONTEST UNINAME MOJNAME
  FNAME="$(jq -r '.result[0].message.from.first_name // empty' <<<"$JSON" | tr -d ':')"
  LNAME="$(jq -r '.result[0].message.from.last_name  // empty' <<<"$JSON" | tr -d ':')"
  UNAME="$USERNAME"
  [[ -z "$UNAME" ]] && UNAME="$REPLYTO"

  set_text_md "O comando **participar** não pode ser invocado de um grupo"
  (( REPLYTO < 0 )) && return

  CONTEST="$(tr -d './' <<<"$1")"
  UNINAME="$2"

  if [[ "$UNINAME" =~ SIGLA ]]; then
    set_text "'[SIGLA_DA_MINHA_UNIVERSIDADE]' deve ser trocado por uma sigla de universidade, como UnB, UFBA... Ou deixe vazio."
    return
  fi

  set_text_md $'Chame este comando da seguinte forma: *participar CONTEST SIGLAUNIVERSIDADE*\nPor exemplo: *participar treino UnB*'
  [[ -z "$CONTEST" ]] && return

  MOJNAME="[$UNINAME] $FNAME $LNAME"
  [[ -z "$UNINAME" ]] && MOJNAME="$FNAME $LNAME"

  # email/telegram: guardamos o chat_id (REPLYTO) como "email" p/ rastrear o dono,
  # preservando o comportamento do MOJ antigo (4º campo do passwd).
  local body resp st
  body="$(jq -cn --arg c "$CONTEST" --arg l "$UNAME" --arg n "$MOJNAME" --arg e "$REPLYTO" \
            '{contest:$c, login:$l, fullname:$n, email:$e}')"
  resp="$(api POST /admin/adduser -H 'Content-Type: application/json' -d "$body")"
  st="$(api_status "$resp")"; resp="$(api_body "$resp")"

  if [[ "$st" == "200" ]]; then
    local login pass extra=""
    login="$(jq -r '.login // empty' <<<"$resp")"
    pass="$(jq -r '.password // empty' <<<"$resp")"
    if [[ "$CONTEST" == "treino" ]]; then
      extra=$'\n\nCaso seja iniciante, recomendo começar pela tag <b>#.comeceaqui</b> - '"$MOJ_WEB/new/treino/?searchtag=.comeceaqui"
    fi
    set_text_html "Bem vindo ao '$CONTEST'"$'\n'"login: <b>$login</b>"$'\n'"senha: <b>$pass</b>"$'\n'"Acesse: $MOJ_WEB/new/$CONTEST/$extra"
  elif [[ "$st" == "409" ]]; then
    set_text "Você já faz parte deste contest. O seu login é '$UNAME'. Caso tenha esquecido a senha, use o comando 'trocarsenha'"
  elif [[ "$st" == "404" ]]; then
    set_text "'$CONTEST' é inválido."
  else
    set_text "Seu usuário não foi criado: $(err_msg "$resp")"
  fi
}

# /trocarsenha CONTEST  -> POST /admin/passwd  (gera nova senha e troca)
trocarsenha() {
  local UNAME CONTEST
  UNAME="$USERNAME"
  [[ -z "$UNAME" ]] && UNAME="$REPLYTO"

  set_text "O comando **trocarsenha** não pode ser invocado de um grupo"
  (( REPLYTO < 0 )) && return

  CONTEST="$(tr -d './' <<<"$1")"
  set_text_md $'Chame este comando da seguinte forma: *trocarsenha CONTEST*\nPor exemplo: *trocarsenha treino*'
  [[ -z "$CONTEST" ]] && return

  # O login do usuário é o próprio username do Telegram (convenção do bot).
  local NEWPASSWD body resp st
  NEWPASSWD="$(shuf -n1 "$BOTDIR/palavras-para-senha" 2>/dev/null)$(( RANDOM % 10000 ))"
  [[ -z "$NEWPASSWD" || "$NEWPASSWD" =~ ^[0-9]+$ ]] && NEWPASSWD="$RANDOM$RANDOM"

  body="$(jq -cn --arg c "$CONTEST" --arg l "$UNAME" --arg np "$NEWPASSWD" \
            '{contest:$c, login:$l, newpass:$np}')"
  resp="$(api POST /admin/passwd -H 'Content-Type: application/json' -d "$body")"
  st="$(api_status "$resp")"; resp="$(api_body "$resp")"

  if [[ "$st" == "200" ]]; then
    set_text_html "Suas credenciais para o contest <i>$CONTEST</i> são:"$'\n'"usuário: <b>$UNAME</b>"$'\n'"senha: <b>$NEWPASSWD</b>"$'\n'"Link de acesso: $MOJ_WEB/new/$CONTEST/"
  elif [[ "$st" == "404" ]]; then
    set_text "Você não faz parte deste contest (ou o contest não existe)."
  else
    set_text "Senha não trocada: $(err_msg "$resp")"
  fi
}

# /alteravigenciacontest CONTEST EPOCHSECONDS -> POST /admin/contest/extend
alteravigenciacontest() {
  local CONTEST="$1" NOVAVIGENCIA="$2"
  set_text_md $'alteravigenciacontest CONTEST EPOCHSECONDS\n\nCONTEST é o unix name do contest\nEPOCHSECONDS é o tempo em segundos da nova vigência'
  [[ -z "$CONTEST" || -z "$NOVAVIGENCIA" ]] && return

  set_text "$CONTEST fora de escopo"
  [[ "$CONTEST" =~ / ]] && return
  set_text "$NOVAVIGENCIA fora de escopo"
  grep -qE '^[0-9]+$' <<<"$NOVAVIGENCIA" || return

  local body resp st
  body="$(jq -cn --arg c "$CONTEST" --argjson e "$NOVAVIGENCIA" \
            '{contest:$c, end_epoch:$e}')"
  resp="$(api POST /admin/contest/extend -H 'Content-Type: application/json' -d "$body")"
  st="$(api_status "$resp")"; resp="$(api_body "$resp")"

  if [[ "$st" == "200" ]]; then
    set_text_md "Vigência do contest \`$CONTEST\` alterada para \`$NOVAVIGENCIA\` ($(date --date=@"$NOVAVIGENCIA"))"
  else
    set_text "Não consegui alterar a vigência: $(err_msg "$resp")"
  fi
}

# /synctreino -> POST /admin/synctreino
synctreino() {
  local resp st
  resp="$(api POST /admin/synctreino -H 'Content-Type: application/json' -d '{}')"
  st="$(api_status "$resp")"; resp="$(api_body "$resp")"
  if [[ "$st" == "200" ]]; then
    set_text "Treino livre agendado para ASAP (sincronização enfileirada)."
  else
    set_text "Falha ao agendar synctreino: $(err_msg "$resp")"
  fi
}

# /rejulgarsubmissao ID [ID2 ...] -> POST /admin/rejudge {ids:[...]}
# IDs no formato TIME:HASH (10 dígitos : 32 hex); a API valida cada id.
rejulgarsubmissao() {
  set_text "rejulgarsubmissao SUBMISSION-ID [SUBMISSION-ID2 ...]"
  [[ -z "$1" ]] && return

  # O contest é necessário; quando chamado por rejulgarcontestproblem, vem em
  # REJUDGE_CONTEST. Caso o operador chame direto, exigimos o contest no início.
  local CONTEST="${REJUDGE_CONTEST:-}"
  local -a IDS=()
  if [[ -z "$CONTEST" ]]; then
    # primeiro argumento que NÃO parece um id é tratado como contest.
    if [[ ! "$1" =~ ^[0-9]{10}:[0-9a-f]{32}$ ]]; then
      CONTEST="$1"; shift
    fi
  fi
  if [[ -z "$CONTEST" ]]; then
    set_text_md $'Uso: *rejulgarsubmissao CONTEST ID [ID2 ...]*\nID no formato TIME:HASH'
    return
  fi

  local ID
  for ID in "$@"; do
    [[ -z "$ID" ]] && continue
    IDS+=("$ID")
  done
  (( ${#IDS[@]} > 0 )) || { set_text "Nenhum id informado."; return; }

  local ids_json body resp st
  ids_json="$(printf '%s\n' "${IDS[@]}" | jq -R . | jq -cs .)"
  body="$(jq -cn --arg c "$CONTEST" --argjson ids "$ids_json" '{contest:$c, ids:$ids}')"
  resp="$(api POST /admin/rejudge -H 'Content-Type: application/json' -d "$body")"
  st="$(api_status "$resp")"; resp="$(api_body "$resp")"

  if [[ "$st" == "200" ]]; then
    local n; n="$(jq -r '.count // (.queued|length) // 0' <<<"$resp" 2>/dev/null)"
    set_text "$n submissão(ões) colocada(s) para rejulgamento."
  else
    set_text "Falha no rejulgamento: $(err_msg "$resp")"
  fi
}

# /rejulgarcontestproblem CONTEST PROBLEM -> POST /admin/rejudge {contest,problem}
rejulgarcontestproblem() {
  local CONTEST="$1" PROBLEMA="$2"
  set_text "rejulgarcontestproblem CONTEST SHORT-PROBLEM-NAME"
  [[ -z "$CONTEST" || -z "$PROBLEMA" ]] && return

  set_text "$CONTEST fora de escopo"; [[ "$CONTEST" =~ / ]] && return
  set_text "$PROBLEMA fora de escopo"; [[ "$PROBLEMA" =~ / ]] && return

  local body resp st
  body="$(jq -cn --arg c "$CONTEST" --arg p "$PROBLEMA" '{contest:$c, problem:$p}')"
  resp="$(api POST /admin/rejudge -H 'Content-Type: application/json' -d "$body")"
  st="$(api_status "$resp")"; resp="$(api_body "$resp")"

  if [[ "$st" == "200" ]]; then
    set_text "Problema '$PROBLEMA' do contest '$CONTEST' enfileirado para rejulgamento."
  else
    set_text "Falha no rejulgamento: $(err_msg "$resp")"
  fi
}

# Divide o MOJHASH antigo (TIME:HASH) em $SUBTIME e $SUBID. Retorna 1 se inválido.
_split_subhash() {
  local h="$1"
  [[ "$h" =~ ^([0-9]{10}):([0-9a-f]{32})$ ]] || return 1
  SUBTIME="${BASH_REMATCH[1]}"; SUBID="${BASH_REMATCH[2]}"
  return 0
}

# /getcode CONTEST TIME:HASH -> GET /submission/source (envia como documento)
getcode() {
  local CONTEST="$1" MOJHASH="$2"
  if [[ -z "$CONTEST" || -z "$MOJHASH" ]]; then
    set_text_md $'Uso: *getcode CONTEST TIME:HASH*'
    return
  fi
  set_text "@$USERNAME, chave inválida"
  _split_subhash "$MOJHASH" || return

  local resp st body tmp
  resp="$(api GET "/submission/source?contest=$CONTEST&time=$SUBTIME&id=$SUBID")"
  st="$(api_status "$resp")"; body="$(api_body "$resp")"

  if [[ "$st" != "200" ]]; then
    set_text "@$USERNAME, não consegui obter o código ($st): $(err_msg "$body")"
    return
  fi
  if [[ -z "$body" ]]; then
    set_text "@$USERNAME, o arquivo armazenado está vazio e NÃO será enviado."
    return
  fi
  tmp="$(mktemp -d)"
  printf '%s\n' "$body" > "$tmp/$SUBTIME-$SUBID.txt"
  tg_send_document "$tmp/$SUBTIME-$SUBID.txt"
  rm -rf "$tmp"
  set_text "@$USERNAME $MOJHASH enviado"
  echo "$(date -R) $USERNAME ($FULLNAME) ${CONTEST} ${MOJHASH}" >> "$BOTDIR/log-getcode.txt"
}

# /getlog CONTEST TIME:HASH -> GET /submission/log (envia como documento)
getlog() {
  local CONTEST="$1" MOJHASH="$2"
  if [[ -z "$CONTEST" || -z "$MOJHASH" ]]; then
    set_text_md $'Uso: *getlog CONTEST TIME:HASH*'
    return
  fi
  set_text "@$USERNAME, chave inválida"
  _split_subhash "$MOJHASH" || return

  local resp st body tmp
  resp="$(api GET "/submission/log?contest=$CONTEST&time=$SUBTIME&id=$SUBID")"
  st="$(api_status "$resp")"; body="$(api_body "$resp")"

  if [[ "$st" != "200" ]]; then
    set_text "@$USERNAME, não consegui obter o log ($st): $(err_msg "$body")"
    return
  fi
  tmp="$(mktemp -d)"
  printf '%s\n' "$body" > "$tmp/$SUBTIME-$SUBID.md"
  gzip "$tmp/$SUBTIME-$SUBID.md"
  tg_send_document "$tmp/$SUBTIME-$SUBID.md.gz"
  rm -rf "$tmp"
  set_text "@$USERNAME log de $MOJHASH enviado"
  echo "$(date -R) $USERNAME ($FULLNAME) ${CONTEST} ${MOJHASH}" >> "$BOTDIR/log-getlog.txt"
}

# /onqueue -> GET /ops/queue
onqueue() {
  local resp st body
  resp="$(api GET /ops/queue)"
  st="$(api_status "$resp")"; body="$(api_body "$resp")"
  if [[ "$st" != "200" ]]; then
    set_text "Não consegui ler a fila ($st): $(err_msg "$body")"
    return
  fi
  local total per
  total="$(jq -r '.total // 0' <<<"$body")"
  per="$(jq -r '(.by_contest // {}) | to_entries | sort_by(.value) | .[] | "  \(.value)\t\(.key)"' <<<"$body")"
  [[ -n "$per" ]] && per=$'\n```\n'"$per"$'\n```' || per=""
  set_text_md "A fila de submissões possui um total de \`$total\` jobs.$per"
}

# /listjudgesmachine -> GET /ops/judges
listjudgesmachine() {
  checkgod || return
  local resp st body
  resp="$(api GET /ops/judges)"
  st="$(api_status "$resp")"; body="$(api_body "$resp")"
  if [[ "$st" != "200" ]]; then
    set_text "Não consegui consultar os juízes ($st): $(err_msg "$body")"
    return
  fi
  # Best-effort: o formato exato de .judges depende do master; serializamos legível.
  local pretty
  pretty="$(jq -r '
    .judges as $j
    | if ($j|type)=="array" and ($j|length)==0 then "Nenhuma máquina respondeu."
      else ($j | tostring) end' <<<"$body" 2>/dev/null)"
  [[ -z "$pretty" ]] && pretty="$(jq -c '.judges' <<<"$body" 2>/dev/null)"
  set_text "Máquinas de julgamento:"$'\n'"$pretty"
}

# /problemtl PROBLEM [PROBLEM2 ...] -> GET /ops/problemtl?problem=<p>
problemtl() {
  checkgod || return
  if [[ -z "$1" ]]; then
    set_text_md $'Uso: /problemtl <id-do-problema>\nExemplo: /problemtl moj-problems#eof'
    return
  fi
  local STRING="" p resp st body
  for p in "$@"; do
    STRING+="#### *$p*"$'\n'
    resp="$(api GET "/ops/problemtl?problem=$(jq -rn --arg s "$p" '$s|@uri')")"
    st="$(api_status "$resp")"; body="$(api_body "$resp")"
    if [[ "$st" != "200" ]]; then
      STRING+="erro ($st): $(err_msg "$body")"$'\n'
      continue
    fi
    local tl
    tl="$(jq -r '(.time_limits // {}) | if (type=="object" and (.|length)==0) then "(sem dados)" else tostring end' <<<"$body" 2>/dev/null)"
    STRING+="\`\`\`"$'\n'"$tl"$'\n'"\`\`\`"$'\n'
  done
  set_text_md "$STRING"
}

# /updateproblemset REPO -> POST /ops/updateproblemset {repo}
updateproblemset() {
  local REPO="$1"
  set_text_md $'Uso: updateproblemset REPOSITORIO\nsendo REPOSITORIO qual repositório deseja atualizar'
  [[ -z "$REPO" ]] && return

  local body resp st rbody
  body="$(jq -cn --arg r "$REPO" '{repo:$r}')"
  resp="$(api POST /ops/updateproblemset -H 'Content-Type: application/json' -d "$body")"
  st="$(api_status "$resp")"; rbody="$(api_body "$resp")"
  if [[ "$st" == "200" ]]; then
    local status; status="$(jq -r '.status // .action // "ok"' <<<"$rbody" 2>/dev/null)"
    set_text "updateproblemset de '$REPO': $status"
  else
    set_text "Falha no updateproblemset: $(err_msg "$rbody")"
  fi
}

# ---------------------------------------------------------------------------
# Offset de long-polling (persistido em ./mojinho-offset).
# ---------------------------------------------------------------------------
OFFSET=0
[[ -e "$BOTDIR/mojinho-offset" ]] && OFFSET="$(< "$BOTDIR/mojinho-offset")"
[[ "$OFFSET" =~ ^[0-9]+$ ]] || OFFSET=0

# ---------------------------------------------------------------------------
# Tabelas de comandos.
#   ALLOWEDFUNCTIONS: liberados a qualquer usuário.
#   GODFUNCTIONS:     exigem GODS[username]=true.
# ---------------------------------------------------------------------------
declare -A ALLOWEDFUNCTIONS GODFUNCTIONS
for f in help amigod participar trocarsenha getlog getcode cantar; do
  ALLOWEDFUNCTIONS[$f]=true
done
for f in alteravigenciacontest updateproblemset listjudgesmachine problemtl \
         rejulgarsubmissao rejulgarcontestproblem onqueue synctreino; do
  GODFUNCTIONS[$f]=true
done

# ===========================================================================
# LOOP PRINCIPAL — long-polling do Telegram (getUpdates) + dispatch.
# ===========================================================================
while true; do
  date
  JSON="$(curl -m 400 -s -X POST -H 'Content-Type: application/json' \
            -d "{ \"offset\": $OFFSET, \"limit\": 1, \"allowed_updates\": [\"message\"], \"timeout\": 300 }" \
            "$API_TG/getUpdates")"

  # avança o offset (mesmo padrão do original)
  local_update="$(jq -r '.result[0].update_id // empty' <<<"$JSON" 2>/dev/null)"
  if [[ -n "$local_update" ]]; then
    OFFSET=$(( local_update + 1 ))
  fi
  echo "$OFFSET" > "$BOTDIR/mojinho-offset"

  REPLYTO="$(jq -r '.result[0].message.chat.id // empty' <<<"$JSON" 2>/dev/null)"
  [[ -z "$REPLYTO" ]] && continue

  USERNAME="$(jq -r '.result[0].message.from.username // empty' <<<"$JSON" 2>/dev/null)"
  FULLNAME="$(jq -r '.result[0].message.from | "\(.id) \(.first_name // "") \(.last_name // "")"' <<<"$JSON" 2>/dev/null)"
  MESSAGE="$(jq -r '.result[0].message.text // empty' <<<"$JSON" 2>/dev/null)"

  # quebra a mensagem em comando + args (sem glob)
  set -o noglob
  # shellcheck disable=SC2206
  CMD=( $MESSAGE )
  set +o noglob
  CMD[0]="${CMD[0]##/}"        # tira a barra inicial do comando
  CMD[0]="${CMD[0]%%@*}"       # tira "@nomedobot" (menções em grupo)

  if [[ -z "${CMD[0]}" ]]; then
    continue
  elif [[ "${ALLOWEDFUNCTIONS[${CMD[0]}]}" == "true" ]]; then
    "${CMD[@]}"
  elif [[ "${GODS[$USERNAME]}" == true && "${GODFUNCTIONS[${CMD[0]}]}" == "true" ]]; then
    "${CMD[@]}"
  else
    erro "${CMD[@]}"
  fi

  # injeta chat_id + silencioso e envia a resposta
  [[ -z "$SUBMITJSON" ]] && SUBMITJSON='{"text":"(sem resposta)"}'
  SUBMITJSON="$(jq -c --argjson id "$REPLYTO" \
                  '. + {chat_id:$id, disable_notification:true}' <<<"$SUBMITJSON")"
  echo "$SUBMITJSON"
  curl -s -X POST -H 'Content-Type: application/json' -d "$SUBMITJSON" \
    "$API_TG/sendMessage" >/dev/null
  unset SUBMITJSON
done
