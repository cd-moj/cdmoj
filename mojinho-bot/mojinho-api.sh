#!/bin/bash
#
# mojinho-api.sh — bot Telegram do MOJ como TRANSPORTE FINO da API v1.
#
# A API é dona de toda a lógica/estado/política; o bot só:
#   * recebe updates do Telegram (getUpdates, long-poll curto);
#   * repassa comandos p/ a API v1 autenticado por um token DEDICADO do bot
#     (`mojb_…` em run/secrets/bot.token) — NÃO loga mais como .admin, sem lista GODS;
#   * entrega mensagens/DMs e drena o OUTBOX de ALERTAS (a API decide o quê/quando).
#
# Comandos (todos ancorados no telegram_id — 1 Telegram = 1 conta):
#   /start <nonce>   confirma o cadastro/vínculo iniciado na página (deep-link)
#   /participar      cria+vincula a conta no treino livre (bot-first)
#   /trocarsenha     recupera a senha (prova = posse do Telegram)
#   /status          saúde do MOJ (fila/juízes) — via /index/status (público)
#   /relatorio       painel de submissões p/ o grupo (só admins; gate na API pelo
#                    telegram_id) — via POST /ops/relatorio; funciona no grupo
#   /help /cantar    locais
#
# Config em ./bot.conf (veja bot.conf.sample). Token do Telegram só em ./token.
# Dependências: bash, curl, jq.
set -o pipefail

BOTDIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
cd "$BOTDIR" || { echo "FATAL: não consegui entrar em $BOTDIR" >&2; exit 1; }

# --- token do Telegram (só do arquivo ./token) -----------------------------
TOKEN="$(grep -aoE '[0-9]{6,}:[A-Za-z0-9_-]{20,}' "$BOTDIR/token" 2>/dev/null | head -n1)"
[[ -n "$TOKEN" ]] || { echo "FATAL: token do Telegram ausente em $BOTDIR/token" >&2; exit 1; }
API_TG="https://api.telegram.org/bot$TOKEN"

# --- config (./bot.conf sobrescreve os defaults) ---------------------------
MOJ_API="http://127.0.0.1:8080/api/v1"          # base da API REST
MOJ_HOST="moj.charge.naquadah.com.br"           # Host: que o nginx roteia
MOJ_WEB="https://moj.charge.naquadah.com.br"    # base pública (links de acesso)
MOJ_CONTEST="treino"                            # contest do treino livre
BOT_TOKEN_FILE="/home/ribas/moj/run/secrets/bot.token"   # token mojb_ (bot<->API)
BOT_TOKEN=""                                    # ou defina direto no bot.conf
ALERT_GROUP_CHAT=""                             # chat de grupo p/ broadcast de alertas
ALERT_POLL_SECS=25                              # cadência do poll de alertas (= timeout do getUpdates)
[[ -f "$BOTDIR/bot.conf" ]] && source "$BOTDIR/bot.conf" || \
  echo "AVISO: $BOTDIR/bot.conf ausente; usando defaults (copie bot.conf.sample)." >&2

[[ -n "$BOT_TOKEN" ]] || BOT_TOKEN="$(grep -aoE 'mojb_[A-Za-z0-9]+' "$BOT_TOKEN_FILE" 2>/dev/null | head -n1)"
[[ -n "$BOT_TOKEN" ]] || echo "AVISO: token do bot (mojb_) ausente — chamadas autenticadas vão falhar." >&2

# --- cliente da API (Bearer mojb_; sem sessão, sem re-login) ----------------
# TOKEN FORA DO PS: URL e headers vão por arquivo de config do curl (-K em fd de
# process substitution) e corpos JSON por arquivo temporário — nada de segredo
# (mojb_, token do Telegram, senhas em DM) aparece no argv de /proc.
# api <METHOD> <path> [curl-args...] -> corpo + última linha "HTTP <code>".
api() {
  local method="$1" path="$2"; shift 2
  curl -s -m 60 -w $'\nHTTP %{http_code}' -X "$method" "$@" \
    -K <(printf 'header = "Host: %s"\nheader = "Authorization: Bearer %s"\nurl = "%s%s"\n' \
         "$MOJ_HOST" "$BOT_TOKEN" "$MOJ_API" "$path")
}
api_json() {  # api() com corpo JSON fora do argv (via arquivo)
  local method="$1" path="$2" body="$3" bf rc
  bf="$(mktemp)"; printf '%s' "$body" > "$bf"
  api "$method" "$path" -H 'Content-Type: application/json' -d @"$bf"; rc=$?
  rm -f "$bf"; return $rc
}
api_status() { tail -n1 <<<"$1" | awk '{print $2}'; }
api_body()   { sed '$d' <<<"$1"; }
err_msg() { local m; m="$(jq -r '.error.message // empty' <<<"$1" 2>/dev/null)"; [[ -n "$m" ]] && printf '%s' "$m" || printf '%s' "$1"; }

# --- helpers de envio do Telegram ------------------------------------------
# A URL do Telegram EMBUTE o token do bot ⇒ nunca em argv: sempre via -K <(…).
# O corpo também sai do argv (mensagem de DM carrega SENHA) — vai por arquivo.
tg_api() {  # tg_api <método-tg> <json> [timeout] -> resposta no stdout
  local path="$1" body="$2" tmo="${3:-40}" bf rc
  bf="$(mktemp)"; printf '%s' "$body" > "$bf"
  curl -s -m "$tmo" -X POST -H 'Content-Type: application/json' -d @"$bf" \
    -K <(printf 'url = "%s/%s"\n' "$API_TG" "$path"); rc=$?
  rm -f "$bf"; return $rc
}
TG_LAST_ERROR=""
tg_send() {  # tg_send <chat_id> <json-msg-sem-chat_id> [loud] -> rc 0 entregue; 1 falhou (TG_LAST_ERROR)
  # Silencioso por padrão (alerta de operação não acorda ninguém de madrugada). `loud` = com
  # notificação: é o caso do convite/lembrete, que precisa ser visto ANTES de a inscrição fechar.
  # A resposta do Telegram NÃO é mais jogada fora (2026-09-14: relatório "preso no grupo errado"
  # sem uma linha de log): chat migrado (migrate_to_chat_id), "chat not found", bot removido do
  # grupo e chat_id não numérico viram uma linha no stderr e rc 1 — o chamador decide.
  local chat="$1" msg="$2" loud="${3:-}" out
  TG_LAST_ERROR=""
  [[ "$chat" =~ ^-?[0-9]+$ ]] || { TG_LAST_ERROR="chat_id não numérico: '$chat'"; echo "tg_send falhou: $TG_LAST_ERROR" >&2; return 1; }
  msg="$(jq -c --argjson id "$chat" --argjson q "$( [[ -n "$loud" ]] && echo false || echo true )" \
          '. + {chat_id:$id, disable_notification:$q}' <<<"$msg")"
  out="$(tg_api sendMessage "$msg")" || true
  if [[ "$(jq -r '.ok' <<<"$out" 2>/dev/null)" == true ]]; then return 0; fi
  TG_LAST_ERROR="$(jq -r '(.description // "sem resposta do Telegram") + (if .parameters.migrate_to_chat_id then " (o grupo virou supergrupo: chat_id novo " + (.parameters.migrate_to_chat_id|tostring) + ")" else "" end)' <<<"$out" 2>/dev/null)"
  [[ -n "$TG_LAST_ERROR" ]] || TG_LAST_ERROR="sem resposta do Telegram"
  echo "tg_send chat=$chat falhou: $TG_LAST_ERROR" >&2
  return 1
}
tg_send_document() {  # <chat_id> <file> [caption]
  local chat="$1" file="$2" caption="$3"
  if [[ -n "$caption" ]]; then curl -s -F chat_id="$chat" -F caption="$caption" -F document=@"$file" -K <(printf 'url = "%s/sendDocument"\n' "$API_TG") >/dev/null
  else curl -s -F chat_id="$chat" -F document=@"$file" -K <(printf 'url = "%s/sendDocument"\n' "$API_TG") >/dev/null; fi
}
set_text()      { SUBMITJSON="$(jq -cn --arg t "$1" '{text:$t}')"; }
set_text_md()   { SUBMITJSON="$(jq -cn --arg t "$1" '{text:$t, parse_mode:"Markdown"}')"; }
set_text_html() { SUBMITJSON="$(jq -cn --arg t "$1" '{text:$t, parse_mode:"HTML"}')"; }

# ===========================================================================
# COMANDOS
# ===========================================================================

# /start [<nonce>] — confirma cadastro/vínculo iniciado na página (deep-link).
# Sem nonce: mensagem de boas-vindas. Com nonce: POST /treino/signup/verify.
start() {
  local nonce="$1"
  if [[ -z "$nonce" ]]; then
    set_text_html "Olá! Para criar sua conta no Treino Livre, comece pela página: $MOJ_WEB/treino/cadastro/"$'\n'"Ou envie <b>/participar</b> aqui mesmo."
    return
  fi
  (( REPLYTO < 0 )) && { set_text "O cadastro não pode ser feito em um grupo. Me chame no privado."; return; }
  local body resp st
  body="$(jq -cn --arg n "$nonce" --argjson id "$FROM_ID" --arg u "$USERNAME" --arg f "$FIRST" --arg l "$LAST" \
            '{nonce:$n, telegram_id:$id, telegram_username:$u, first_name:$f, last_name:$l}')"
  resp="$(api_json POST /treino/signup/verify "$body")"
  st="$(api_status "$resp")"; resp="$(api_body "$resp")"
  _signup_reply "$st" "$resp"
}

# /participar [CONTEST SIGLA] — cria+vincula (bot-first), ancorado no telegram_id.
participar() {
  (( REPLYTO < 0 )) && { set_text "O comando *participar* não pode ser usado em grupo. Me chame no privado."; return; }
  local body resp st
  body="$(jq -cn --argjson id "$FROM_ID" --arg u "$USERNAME" --arg f "$FIRST" --arg l "$LAST" \
            '{telegram_id:$id, telegram_username:$u, first_name:$f, last_name:$l}')"
  resp="$(api_json POST /treino/signup/telegram "$body")"
  st="$(api_status "$resp")"; resp="$(api_body "$resp")"
  _signup_reply "$st" "$resp"
}

# resposta comum a signup/verify e signup/telegram
_signup_reply() {
  local st="$1" resp="$2" status login pass
  status="$(jq -r '.status // empty' <<<"$resp" 2>/dev/null)"
  login="$(jq -r '.login // empty' <<<"$resp" 2>/dev/null)"
  pass="$(jq -r '.password // empty' <<<"$resp" 2>/dev/null)"
  case "$status" in
    created)
      set_text_html "Bem-vindo(a) ao Treino Livre!"$'\n'"login: <b>$login</b>"$'\n'"senha: <b>$pass</b>"$'\n'"Acesse: $MOJ_WEB/treino/"$'\n\n'"Iniciante? Comece por aqui: $MOJ_WEB/treino/?searchtag=.comeceaqui" ;;
    linked)
      set_text_html "Telegram vinculado à sua conta <b>$login</b>. Você agora pode receber avisos por aqui." ;;
    already_linked)
      set_text_html "Você já tem conta: <b>$login</b>."$'\n'"Esqueceu a senha? Envie <b>/trocarsenha</b>." ;;
    *)
      if [[ "$st" == "410" ]]; then set_text "O link de confirmação expirou. Recomece o cadastro na página."
      elif [[ "$st" == "404" ]]; then set_text "Link de confirmação inválido. Recomece o cadastro na página."
      else set_text "Não consegui concluir: $(err_msg "$resp")"; fi ;;
  esac
}

# /trocarsenha — recupera a senha pelo vínculo Telegram (POST /treino/recover-password).
trocarsenha() {
  (( REPLYTO < 0 )) && { set_text "O comando *trocarsenha* não pode ser usado em grupo. Me chame no privado."; return; }
  local body resp st status login pass
  body="$(jq -cn --argjson id "$FROM_ID" '{telegram_id:$id}')"
  resp="$(api_json POST /treino/recover-password "$body")"
  st="$(api_status "$resp")"; resp="$(api_body "$resp")"
  status="$(jq -r '.status // empty' <<<"$resp" 2>/dev/null)"
  login="$(jq -r '.login // empty' <<<"$resp" 2>/dev/null)"
  pass="$(jq -r '.password // empty' <<<"$resp" 2>/dev/null)"
  if [[ "$status" == ok ]]; then
    set_text_html "Nova senha para <i>$MOJ_CONTEST</i>:"$'\n'"login: <b>$login</b>"$'\n'"senha: <b>$pass</b>"$'\n'"Acesse: $MOJ_WEB/treino/"
  elif [[ "$status" == not_linked ]]; then
    set_text_html "Você ainda não tem conta vinculada a este Telegram. Crie em: $MOJ_WEB/treino/cadastro/ ou envie /participar."
  else
    set_text "Não consegui trocar a senha: $(err_msg "$resp")"
  fi
}

# /status — saúde do MOJ (fila/juízes), via /index/status (PÚBLICO, sem auth).
status() {
  local resp; resp="$(curl -s -m 20 -H "Host: $MOJ_HOST" "$MOJ_API/index/status" 2>/dev/null)"
  local jon jt qp bq dj alert
  jon="$(jq -r '.judge.online // 0' <<<"$resp" 2>/dev/null)"; jt="$(jq -r '.judge.total // 0' <<<"$resp" 2>/dev/null)"
  qp="$(jq -r '.queue.total_pending // 0' <<<"$resp" 2>/dev/null)"; bq="$(jq -r '.queue.band_queued // 0' <<<"$resp" 2>/dev/null)"
  dj="$(jq -r '.daemons.judged // false' <<<"$resp" 2>/dev/null)"; alert="$(jq -r '.alert.no_judges // false' <<<"$resp" 2>/dev/null)"
  local warn=""; [[ "$alert" == true ]] && warn=$'\n⚠️ Há trabalho pendente e NENHUM juiz online!'
  [[ "$dj" == true ]] || warn="$warn"$'\n⚠️ Daemon de julgamento (judged) parece parado.'
  set_text_html "Juízes online: <b>$jon</b>/$jt"$'\n'"Fila (pendentes): <b>$qp</b> (bandas: $bq)$warn"
}

help() { set_text_html "Comandos: <b>/participar</b> (criar conta), <b>/trocarsenha</b> (recuperar senha), <b>/status</b> (saúde do MOJ), <b>/relatorio</b> (painel de submissões — admins), <b>/cantar</b> 🎵."; }

# /relatorio [AAAA-MM-DD] | config <início> <fim> | aqui | refazer <k> | status — painel de
# submissões (top-10 do período + treino + comparações). SEM guarda de grupo de propósito: o
# ritual é pedir DENTRO do grupo dos professores — e `/relatorio aqui` registra ESSE grupo
# como destino do envio automático (por isso o chat_id/chat_type vão no corpo). Quem pode =
# a API decide (telegram_id → conta .admin do treino); o bot só transporta.
relatorio() {
  local body resp st html
  body="$(jq -cn --argjson id "$FROM_ID" --argjson chat "${REPLYTO:-0}" --arg ct "${CHAT_TYPE:-}" \
           '{telegram_id:$id, args:$ARGS.positional, chat_id:$chat, chat_type:$ct}' --args "$@")"
  resp="$(api_json POST /ops/relatorio "$body")"
  st="$(api_status "$resp")"; resp="$(api_body "$resp")"
  if [[ "$st" == "200" ]]; then
    html="$(jq -r '.html // empty' <<<"$resp" 2>/dev/null)"
    if [[ -n "$html" ]]; then set_text_html "$html"; else set_text "Relatório vazio."; fi
  else
    set_text "Não consegui gerar o relatório: $(err_msg "$resp")"
  fi
}

cantar() {
  local ARQM STRING="" LINE
  ARQM="$(ls "$BOTDIR"/musica.* 2>/dev/null | shuf -n1)"
  [[ -z "$ARQM" ]] && { set_text "Sem músicas no momento. 🎵"; return; }
  while IFS= read -r LINE; do STRING+="$LINE"$'\n'; done < "$ARQM"
  set_text_md "$STRING"
}

erro() { set_text_html "Não entendi. Envie <b>/help</b> para ver os comandos."; }

# ===========================================================================
# ALERTAS — drena o outbox da API e entrega (grupo + DMs). A API decide tudo.
# GET /ops/alerts (bot-token) -> {items:[{id, text, chats:[<chat_id>…], loud, group}]}.
#   group:false — mensagem DIRIGIDA a uma pessoa (ex.: convite de time): NÃO copiar no grupo.
#   loud:true   — entregar com notificação (o default do tg_send é silencioso).
# ===========================================================================
# ENTREGA COM ACK (2026-09-14): cada item tem `id`; depois de tentar todos os chats o bot manda
# POST /ops/alerts {ack:[{id, ok, error}]} — ok = pelo menos um chat recebeu. É o ack que marca
# o relatório de quartil como ENTREGUE (sem ack a API reentrega em 10 min). Item só-grupo sem
# ALERT_GROUP_CHAT deixa de sumir em silêncio: vira ack ok:false + uma linha de log.
deliver_alerts() {
  [[ -n "$BOT_TOKEN" ]] || return 0
  local resp st n i id text chats c loud nogroup acks='[]' ok err
  resp="$(api GET /ops/alerts)"
  st="$(api_status "$resp")"; resp="$(api_body "$resp")"
  [[ "$st" == "200" ]] || return 0
  n="$(jq -r '(.items // []) | length' <<<"$resp" 2>/dev/null)"; [[ "$n" =~ ^[0-9]+$ ]] || return 0
  for (( i=0; i<n; i++ )); do
    text="$(jq -r ".items[$i].text // empty" <<<"$resp")"
    id="$(jq -r ".items[$i].id // empty" <<<"$resp")"
    [[ -n "$text" ]] || continue
    # ⚠ `.group // true` NÃO serve: o // do jq trata false como vazio e o grupo receberia a DM
    # de todo mundo. A pergunta tem de ser explícita.
    nogroup="$(jq -r ".items[$i].group == false" <<<"$resp" 2>/dev/null)"
    loud="$(jq -r ".items[$i].loud == true" <<<"$resp" 2>/dev/null)"
    # destinos: chats do item + grupo configurado (salvo mensagem dirigida)
    mapfile -t chats < <(jq -r ".items[$i].chats[]? // empty" <<<"$resp")
    [[ -n "$ALERT_GROUP_CHAT" && "$nogroup" != "true" ]] && chats+=("$ALERT_GROUP_CHAT")
    local msg; msg="$(jq -cn --arg t "$text" '{text:$t, parse_mode:"HTML"}')"
    ok=false; err=""
    if (( ${#chats[@]} == 0 )); then
      err="sem destino: item só-grupo e ALERT_GROUP_CHAT vazio no bot.conf"
      echo "deliver_alerts item=$id descartado: $err" >&2
    fi
    for c in "${chats[@]}"; do
      [[ -n "$c" ]] || continue
      # `a && x || y` mandaria DUAS vezes se o envio falhasse (o || pega o rc do tg_send)
      if [[ "$loud" == "true" ]]; then
        if tg_send "$c" "$msg" loud; then ok=true; else err="$TG_LAST_ERROR"; fi
      else
        if tg_send "$c" "$msg"; then ok=true; else err="$TG_LAST_ERROR"; fi
      fi
      sleep 0.05    # o Telegram corta acima de ~30 msg/s
    done
    [[ -n "$id" ]] && acks="$(jq -c --arg id "$id" --argjson ok "$ok" --arg e "$err" '. + [{id:$id, ok:$ok, error:$e}]' <<<"$acks")"
  done
  if [[ "$acks" != '[]' ]]; then
    api_json POST /ops/alerts "$(jq -cn --argjson a "$acks" '{ack:$a}')" >/dev/null 2>&1 \
      || echo "deliver_alerts: ack não chegou à API (itens serão reentregues)" >&2
  fi
}

# ===========================================================================
# OFFSET + tabela de comandos
# ===========================================================================
OFFSET=0
[[ -e "$BOTDIR/mojinho-offset" ]] && OFFSET="$(< "$BOTDIR/mojinho-offset")"
[[ "$OFFSET" =~ ^[0-9]+$ ]] || OFFSET=0

declare -A ALLOWEDFUNCTIONS
for f in start participar trocarsenha status help cantar relatorio; do ALLOWEDFUNCTIONS[$f]=true; done

# processa um único update (objeto .message) já extraído em $UPD
process_update() {
  REPLYTO="$(jq -r '.chat.id // empty' <<<"$UPD" 2>/dev/null)"
  [[ -n "$REPLYTO" ]] || return 0
  FROM_ID="$(jq -r '.from.id // empty' <<<"$UPD" 2>/dev/null)"; [[ "$FROM_ID" =~ ^-?[0-9]+$ ]] || FROM_ID=0
  CHAT_TYPE="$(jq -r '.chat.type // empty' <<<"$UPD" 2>/dev/null)"   # private | group | supergroup
  USERNAME="$(jq -r '.from.username // empty' <<<"$UPD" 2>/dev/null)"
  FIRST="$(jq -r '.from.first_name // empty' <<<"$UPD" 2>/dev/null | tr -d ':')"
  LAST="$(jq -r '.from.last_name // empty' <<<"$UPD" 2>/dev/null | tr -d ':')"
  local MESSAGE; MESSAGE="$(jq -r '.text // empty' <<<"$UPD" 2>/dev/null)"
  set -o noglob; CMD=( $MESSAGE ); set +o noglob
  CMD[0]="${CMD[0]##/}"; CMD[0]="${CMD[0]%%@*}"
  [[ -z "${CMD[0]}" ]] && return 0
  SUBMITJSON=""
  if [[ "${ALLOWEDFUNCTIONS[${CMD[0]}]}" == "true" ]]; then "${CMD[@]}"; else erro; fi
  [[ -n "$SUBMITJSON" ]] && { tg_send "$REPLYTO" "$SUBMITJSON" || true; }
  unset SUBMITJSON
}

# ===========================================================================
# LOOP PRINCIPAL — getUpdates (long-poll curto) + entrega de alertas a cada volta.
# ===========================================================================
while true; do
  JSON="$(tg_api getUpdates \
            "{\"offset\": $OFFSET, \"limit\": 20, \"allowed_updates\": [\"message\"], \"timeout\": $ALERT_POLL_SECS}" \
            $(( ALERT_POLL_SECS + 10 )))"
  nupd="$(jq -r '(.result // []) | length' <<<"$JSON" 2>/dev/null)"; [[ "$nupd" =~ ^[0-9]+$ ]] || nupd=0
  for (( k=0; k<nupd; k++ )); do
    UPD="$(jq -c ".result[$k].message // empty" <<<"$JSON" 2>/dev/null)"
    uid="$(jq -r ".result[$k].update_id // empty" <<<"$JSON" 2>/dev/null)"
    [[ "$uid" =~ ^[0-9]+$ ]] && OFFSET=$(( uid + 1 ))
    [[ -n "$UPD" && "$UPD" != null ]] && process_update
  done
  echo "$OFFSET" > "$BOTDIR/mojinho-offset"
  deliver_alerts
done
