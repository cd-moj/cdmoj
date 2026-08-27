# lib/common.sh — utilidades base da API MOJ (sourced pelo router e handlers).
# Carrega config e fornece helpers de resposta (CGI), JSON, validação.

set -o noglob   # ids podem conter chars de glob; evita expansão acidental

# --- config ---------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == /* && "${BASH_SOURCE[0]}" != *"/./"* && "${BASH_SOURCE[0]}" != *"/../"* ]]; then
  _LIBDIR="${BASH_SOURCE[0]%/*}"          # idem: sem dirname nem subshell
else
  _LIBDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
: "${MOJ_CONF:=$_LIBDIR/../../../etc/common.conf}"
[[ -f "$MOJ_CONF" ]] && source "$MOJ_CONF"
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
: "${SESSIONDIR:=/home/ribas/moj/run/sessions}"
: "${SPOOLDIR:=/home/ribas/moj/run/spool/submissions}"
# defaults DERIVADOS do próprio checkout (_LIBDIR = server/api/v1/lib), nunca caminho de dev
# hardcoded: na imagem de produção (/opt/moj/cdmoj) o caminho de dev NÃO EXISTE e o SCOREDIR
# quebrado fazia TODO regen_locked executar script inexistente, mudo (rc engolido) — os caches
# de response-stats/calib-activity/statistics/panorama nunca nasciam e os painéis serviam o
# fallback zerado p/ sempre. Env (imagem/quadlet) continua vencendo o default.
: "${NEWSDIR:=$_LIBDIR/../../../var/news}"
: "${SCOREDIR:=$_LIBDIR/../../../score}"
: "${DEFAULT_SCORE_MODE:=icpc}"
export CONTESTSDIR SCOREDIR   # herdados por sub-processos (ex.: server/score/build.sh)

# --- FUSO: toda hora que o servidor ESCREVE para gente ---------------------
# A imagem é debian-slim sem TZ ⇒ o processo rodava em UTC e TUDO que o servidor imprimia p/
# humano saía 3 h à frente do relógio de Brasília: a DM do convite, o checklist pré-prova, a data
# do caderno, o relatório final. (A web nunca sofreu disso — ela formata no relógio do browser.)
# Epoch não muda: o que muda é só a renderização (date, jq strflocaltime, awk strftime).
: "${MOJ_TZ:=America/Sao_Paulo}"
export TZ="$MOJ_TZ"

# contest_tz <c> — fuso DO CONTEST (CONTEST_TZ no conf), com fallback p/ o MOJ_TZ.
# Validado contra o zoneinfo: nome inválido faria `date` cair mudo em UTC.
contest_tz(){
  local v; v="$( ( CONTEST_TZ=""; source "$CONTESTSDIR/$1/conf" 2>/dev/null; printf '%s' "${CONTEST_TZ:-}" ) )"
  if [[ -n "$v" && "$v" =~ ^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+){0,2}$ && -f "/usr/share/zoneinfo/$v" ]]
    then printf '%s' "$v"; else printf '%s' "$MOJ_TZ"; fi
}
# fmt_epoch <epoch> <formato-date> [contest] — data legível no fuso certo (vazio se não for epoch)
fmt_epoch(){
  [[ "$1" =~ ^[0-9]+$ ]] && (( $1 > 0 )) || return 0
  if [[ -n "${3:-}" ]]; then TZ="$(contest_tz "$3")" date -d "@$1" "+$2" 2>/dev/null
  else date -d "@$1" "+$2" 2>/dev/null; fi
}

# --- liveness do daemon de julgamento -------------------------------------
# O `pgrep` só enxerga o judged quando ele roda no MESMO namespace de PID que a API. No deploy
# recomendado (imagem podman) são DOIS containers — moj-api e moj-judged — e a API JAMAIS veria
# o processo: o painel o daria por morto e os alertas gritariam "daemon parado" p/ sempre.
# Por isso o daemon bate um heartbeat em $RUNDIR/judged.alive (que está no volume compartilhado)
# e aqui aceitamos os dois sinais. Fonte única: usada por /index/status e por lib/alerts.sh.
: "${RUNDIR:=/home/ribas/moj/run}"
: "${JUDGED_ALIVE_FILE:=$RUNDIR/judged.alive}"
: "${JUDGED_ALIVE_TTL:=120}"          # s; o daemon re-drena (e bate) a cada WATCH_REDRAIN_SECS=30
daemon_judged_alive() {
  pgrep -f 'server/daemons/judged.sh' >/dev/null 2>&1 && return 0
  local m; m="$(stat -c %Y "$JUDGED_ALIVE_FILE" 2>/dev/null)"
  [[ -n "$m" ]] || return 1
  (( EPOCHSECONDS - m <= JUDGED_ALIVE_TTL ))
}

# --- resposta (CGI) -------------------------------------------------------
# CGI: emitimos "Status:" (fcgiwrap/nginx traduzem p/ status HTTP) + Content-Type.
respond() {  # respond <code> <reason> <content-type>
  printf 'Status: %s %s\r\n' "${1:-200}" "${2:-OK}"
  printf 'Content-Type: %s\r\n' "${3:-application/json; charset=utf-8}"
  printf '\r\n'
}
emit_json(){ respond "${1:-200}" "${2:-OK}" "application/json; charset=utf-8"; }
emit_text(){ respond "${1:-200}" "${2:-OK}" "text/plain; charset=utf-8"; }
emit_html(){ respond "${1:-200}" "${2:-OK}" "text/html; charset=utf-8"; }

_reason() {
  case "$1" in
    200) echo OK;; 201) echo Created;; 400) echo "Bad Request";;
    401) echo Unauthorized;; 403) echo Forbidden;; 404) echo "Not Found";;
    405) echo "Method Not Allowed";; 409) echo Conflict;;
    422) echo "Unprocessable Entity";; 500) echo "Internal Server Error";;
    *) echo Error;;
  esac
}

# fail <http-status> <message> [error-code] — envelope de erro + encerra.
fail() {
  local code="${1:-400}" msg="$2" ecode="${3:-$1}"
  emit_json "$code" "$(_reason "$code")"
  jq -cn --arg m "$msg" --arg c "$ecode" '{success:false, error:{message:$m, code:$c}}'
  exit 0
}

# ok_json <jq-filter> [jq-args...] — envelope de sucesso: {success:true} + (filter)
# ex.: ok_json '{token:$t, name:$n}' --arg t "$UUID" --arg n "$NAME"
#
# MONTA O CORPO ANTES DO CABEÇALHO (arquivo temporário, não variável — corpo grande não
# precisa caber na memória do shell). Antes o `emit_json 200 OK` vinha primeiro e QUALQUER
# falha do jq — o caso real: argumento acima do teto de 128KiB do `--argjson` — virava um
# **200 com corpo vazio**, que o front só sabe reportar como "Resposta inválida do servidor",
# sem rastro em log nenhum. Agora falha vira 500 `build_fail` e o stderr do jq vai para o
# error.log. (Corpo grande NÃO é motivo de falha: use --slurpfile/--rawfile — ver ok_json_slurp.)
ok_json() {
  local filter="$1"; shift
  # O corpo é montado ANTES do cabeçalho (regra da casa: quem emite 200 e só depois roda o jq
  # não tem mais como dizer 500 — falha vira "200 com lista vazia", que o cliente lê como "você
  # não tem nada"). A captura é em VARIÁVEL, não em arquivo: o mktemp+cat+rm custava TRÊS
  # processos em toda resposta da API, e a variável dá a mesma garantia. Corpo grande cabe —
  # o que não pode passar por argv é a ENTRADA do jq (ARG_MAX), e p/ isso existe ok_json_slurp.
  local _b
  _b="$(jq -cn "$@" "{success:true} + ($filter)")" || fail 500 "Falha ao montar a resposta" "build_fail"
  [[ -n "$_b" ]] || fail 500 "Falha ao montar a resposta" "build_fail"
  OK_JSON_BODY="$_b"          # p/ quem quiser guardar a resposta (ver resp_cache_store)
  emit_json 200 OK
  printf '%s\n' "$_b"
}

# ok_json_slurp <jq-filter> <nome> <json-grande> [jq-args...] — igual ao ok_json, mas o valor
# GRANDE entra por --slurpfile (arquivo) em vez de --argjson. O jq tem teto de **128KiB POR
# ARGUMENTO**: todo agregado de N arquivos (pares do jplag, times, clarifications, fila de
# impressão, banco de problemas) passa disso num contest grande e o jq falha. No filtro, o
# valor aparece como $<nome>[0] — o slurpfile entrega um ARRAY de documentos.
# ex.: ok_json_slurp '{teams:$t[0]}' t "$teams"
ok_json_slurp() {
  local filter="$1" name="$2" big="$3"; shift 3
  local _sf; _sf="$(mktemp)" || fail 500 "Falha ao montar a resposta" "build_fail"
  printf '%s' "${big:-null}" > "$_sf"
  ok_json "$filter" --slurpfile "$name" "$_sf" "$@"
  rm -f "$_sf"
}

# --- cache de RESPOSTA (rotas do lote de boot) -----------------------------
# Rotas que todo carregamento de página pede e cujo corpo é o MESMO p/ muita gente. O aluno na
# contagem regressiva aperta F5 em vez de esperar, então este lote é o que decide o pico.
#
# DUAS REGRAS, e as duas são de segurança:
#   1. VARIANTE — se o corpo muda por papel/sessão, o arquivo de cache muda junto (o nome leva a
#      variante). Ignorar isso faz o GET de um juiz vazar p/ um competidor;
#   2. FRESCOR PELAS ENTRADAS — em vez de confiar em alguém lembrar de invalidar, compara-se o
#      cache com os arquivos que o alimentam (`-nt` é builtin do bash: zero processos). O teto de
#      idade é a rede p/ o que não é arquivo daqui (TL de juiz, pacote no treino, relógio).
#
# resp_cache_fresh <arquivo> <ttl_s> <entrada>... -> 0 se pode servir do cache
resp_cache_fresh(){
  local cf="$1" ttl="$2"; shift 2
  [[ -s "$cf" ]] || return 1
  local f
  for f in "$@"; do [[ -e "$f" && "$f" -nt "$cf" ]] && return 1; done
  # ttl 0 = SEM teto de idade: só p/ rota cujas entradas cobrem 100% do que muda o corpo (e aí
  # o próprio arquivo do handler entra como entrada, p/ um deploy invalidar). O teto existe p/ o
  # que NÃO é arquivo deste contest — fase da prova pelo relógio, TL reportado por um juiz — e
  # custa um `find` por requisição, que nessas rotas é o processo mais caro que sobra.
  (( ttl > 0 )) || return 0
  [[ -n "$(find "$cf" -newermt "-$ttl seconds" 2>/dev/null)" ]] || return 1
  return 0
}
# resp_cache_store <arquivo> <corpo> — grava por tmp+mv (leitor concorrente nunca vê pela metade)
resp_cache_store(){
  local cf="$1" body="$2"
  mkdir -p "${cf%/*}" 2>/dev/null
  printf '%s' "$body" > "$cf.tmp.$$" 2>/dev/null && mv -f "$cf.tmp.$$" "$cf" 2>/dev/null \
    || rm -f "$cf.tmp.$$" 2>/dev/null
  return 0
}

# --- validação / paths ----------------------------------------------------
valid_id() {  # id seguro (sem traversal). Permite #, @, ., +, -, _ (usados em ids).
  [[ "$1" =~ ^[A-Za-z0-9._@#+-]+$ ]] && [[ "$1" != *..* ]]
}
# safe_src_filename <nome> — normaliza o NOME DE ARQUIVO DA FONTE que o aluno mandou.
#
# É ENTRADA HOSTIL e viaja longe: vai no job, o agente do juiz materializa o arquivo com ELE
# (`judge/agent/moj-agent.sh`), o build-and-test o copia p/ dentro da jaula e os
# `mojtools/lang/*/compile.sh` baseados em make o entregam ao `/bin/sh`. Um `l(1).cpp` — a marca
# que o NAVEGADOR gruda em download repetido, que o time nem escolheu — virava
# `g++ … l(1).cpp -o l` e dava **Compilation Error** (relato de time, 2026-08-24); com espaço
# quebra em mais pontos (o make usa whitespace como separador de lista: lá dentro não tem
# conserto). O juiz também foi blindado, mas quem garante o nome sadio é a porta.
#
# Faz, nesta ordem: basename (sem traversal) · tira espaço/controle · tira o "(N)" final do stem
# · remove metacaractere de shell/make · vazio vira "solution".
#
# ⚠ A remoção é por LISTA NEGRA de ASCII, nunca `[^[:alnum:]…]`: sob fcgiwrap o locale é `C`,
# onde `[:alnum:]` é ASCII puro — a lista branca comeria o `ç` de `Solução.java` em produção e
# passaria no dev (UTF-8). E o nome importa de verdade em JAVA, onde o arquivo tem de casar a
# classe pública — daí preservar acento não ser capricho.
safe_src_filename() {
  local n="${1##*/}" stem ext="" o="" c i
  n="${n//[[:space:]]/}"; n="${n//[[:cntrl:]]/}"
  if [[ "$n" == *.* ]]; then ext="${n##*.}"; stem="${n%.*}"; else stem="$n"; fi
  while [[ "$stem" =~ ^(.+)\([0-9]+\)$ ]]; do stem="${BASH_REMATCH[1]}"; done
  local bad='()[]{}<>|&;$`"'"'"'\*?!#~^%=:,/'
  for ((i = 0; i < ${#stem}; i++)); do c="${stem:i:1}"; [[ "$bad" == *"$c"* ]] || o+="$c"; done
  stem="$o"; o=""
  for ((i = 0; i < ${#ext}; i++)); do c="${ext:i:1}"; [[ "$bad" == *"$c"* ]] || o+="$c"; done
  ext="$o"
  [[ -n "$stem" ]] || stem="solution"
  if [[ -n "$ext" ]]; then printf '%s.%s' "$stem" "$ext"; else printf '%s' "$stem"; fi
}
require_contest() {  # require_contest <id>
  valid_id "$1" || fail 400 "Invalid contest id" "contest_invalid"
  [[ -d "$CONTESTSDIR/$1" && -f "$CONTESTSDIR/$1/conf" ]] \
    || fail 404 "Contest not found" "contest_notfound"
}
# carrega o conf do contest em variáveis (CONTEST_NAME, CONTEST_TYPE, PROBS, ...)
load_contest_conf() { source "$CONTESTSDIR/$1/conf"; }
# conf_value <contest> <CHAVE> -> valor da 1ª linha `CHAVE=…`, sem aspas, SEM PROCESSO NENHUM.
# O conf é *sourced* em outros caminhos, mas aqui não pode ser (é o caminho de auth: conteúdo de
# usuário não vira código) — e o par grep|cut custava DOIS processos numa checagem que roda em
# TODA rota pública de contest. `$(<arquivo)` é caso especial do bash: lê sem forkar.
conf_value() {
  local f="$CONTESTSDIR/$1/conf" k="$2=" line v
  [[ -r "$f" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "$k"* ]] || continue
    v="${line#"$k"}"; v="${v//\'/}"; v="${v//\"/}"; printf '%s' "$v"; return 0
  done < "$f"
  return 0
}
# contest SUPER SECRETO (conf SECRET=1): fora das listagens públicas (home/arquivo/status);
# placar e visual (balloons/regions/teams-meta) exigem sessão DO contest. Lido SEM source
# (caminho quente e de auth — padrão do _users_source).
contest_is_secret() { [[ "$(conf_value "$1" SECRET)" == 1 ]]; }
# gate dos endpoints públicos quando o contest é secreto: exige sessão válida DAQUELE contest.
require_not_secret_or_auth() {  # <contest>
  contest_is_secret "$1" || return 0
  load_session 2>/dev/null && [[ "$SESSION_CONTEST" == "$1" ]] && return 0
  fail 401 "Contest privado — faça login para ver" "secret_login_required"
}
score_mode_of() {  # ecoa o modo de placar do contest (default DEFAULT_SCORE_MODE)
  local t; t="$(. "$CONTESTSDIR/$1/conf" 2>/dev/null; printf '%s' "${CONTEST_TYPE:-}")"
  case "$t" in
    icpc|obi|treino|heuristic|outro|custom) printf '%s' "$t";;
    lista-publica|lista-privada) printf 'treino';;
    *) printf '%s' "$DEFAULT_SCORE_MODE";;
  esac
}

# --- cache preguiçoso (regenera só quando a fonte muda) -------------------
# Espelha o comportamento legado do MOJ: o processamento (placar/estatísticas) só
# é refeito quando houve modificação na fonte (history/conf); senão serve o que já
# está pronto. E se nada foi gerado ainda, gera na hora (lazy).
#
# stale_cache <cache> <fonte...> : 0 (stale) se o cache não existe OU alguma fonte
# é mais nova que ele (mtime). 1 (fresco) caso contrário.
# score_sources_newer <contest> <placar> — 0 se alguma FONTE do placar mudou depois dele.
# Mesmas fontes que o `regen_locked` do /contest/score passa ao `stale_cache`; existe p/ o
# handler poder perguntar isso SEM processo nenhum antes de pagar o `find` do piso.
score_sources_newer() {
  local c="$1" f="$2" s
  for s in "$CONTESTSDIR/$c/var/.score-dirty" "$CONTESTSDIR/$c/conf"; do
    [[ -e "$s" && "$s" -nt "$f" ]] && return 0
  done
  return 1
}
stale_cache() {
  local cache="$1"; shift
  [[ -f "$cache" ]] || return 0
  local s
  for s in "$@"; do [[ -e "$s" && "$s" -nt "$cache" ]] && return 0; done
  return 1
}

# regen_locked <lockfile> <fonte...> -- <comando...> : se o cache estiver velho,
# adquire um flock (evita rebuild concorrente — cache stampede), reconfere e roda o
# comando de geração. O 1º argumento da lista de fontes é tratado como o próprio
# cache p/ a reconferência. Silencioso; nunca aborta a request se a geração falha.
regen_locked() {
  local lock="$1"; shift
  local cache="$1"
  local -a srcs=() cmd=()
  while (( $# )); do [[ "$1" == "--" ]] && { shift; break; }; srcs+=("$1"); shift; done
  cmd=("$@")
  stale_cache "$cache" "${srcs[@]:1}" || return 0
  mkdir -p "$(dirname "$lock")" 2>/dev/null
  # ⚠ ESPERADOR NÃO ESTACIONA (2026-08-27, teste de carga de 10k): quando o cache JÁ EXISTE,
  # quem não pega o lock serve o VELHO na hora (`flock -n`) — um constrói, os demais respondem
  # em ms. Antes era `flock -w 20` para todos: com o placar de 10k linhas custando 9,7 s por
  # build e veredicto tocando o dirty sem parar, cada requisição estacionava um worker do
  # fcgiwrap na fila do lock — o pool inteiro (64) virou sala de espera e TODAS as rotas
  # afundaram (usuários reais a p95 6 s; o teste foi abortado). Servir um placar/estatística
  # alguns segundos velho é doutrina aceita (é o mesmo contrato do SCORE_SERVE_FLOOR_S);
  # estacionar o pool não é. Só o PRIMEIRO build (cache inexistente) continua esperando:
  # ali não há o que servir.
  local _wait=(-n)
  [[ -s "$cache" ]] || _wait=(-w 20)
  (
    flock "${_wait[@]}" 9 || exit 0
    stale_cache "$cache" "${srcs[@]:1}" || exit 0   # double-check após o lock
    "${cmd[@]}" >/dev/null 2>&1 || true
  ) 9>"$lock"
}

# --- util -----------------------------------------------------------------
urldecode() { local s="${1//+/ }"; printf '%b' "${s//%/\\x}"; }
read_body(){ cat -; }
# read_body_file — grava o corpo num ARQUIVO temporário e ecoa o CAMINHO. Obrigatório nos POSTs
# GRANDES (o pacote de um problema chega a 100+ MB de JSON). Com o corpo numa VARIÁVEL, cada
# `jq … <<<"$body"` é um here-string: o bash REGRAVA os 100 MB num temp e o jq RE-PARSEIA tudo —
# o handler de push fazia isso 36 vezes (~50s de CPU + 3,6 GB de I/O) e estourava o
# fastcgi_read_timeout, deixando o pacote META-APLICADO. Com o corpo em arquivo, todo jq lê o
# arquivo direto (`jq … < "$f"`) e dá p/ passar por --slurpfile. Quem chama remove o arquivo.
read_body_file(){ local f; f="$(mktemp)"; cat - > "$f"; printf '%s' "$f"; }
# render_markdown_html: markdown do stdin -> fragmento HTML no stdout (pandoc 3.x).
# raw_html DESABILITADO (conteúdo público; impede <script> injetado); math via --mathml.
# Usado pelas notícias/posts (detalhe e preview do editor).
render_markdown_html() { pandoc -f markdown-raw_html -t html5 --mathml 2>/dev/null; }
require_method() {  # require_method <METHOD>
  [[ "${REQUEST_METHOD:-GET}" == "$1" ]] || fail 405 "Use $1" "method_not_allowed"
}

# audit_log <action> <details> — registra ação administrativa (treino) com quem fez.
# Formato tab-sep: epoch \t admin_login \t action \t details
audit_log() {
  local who="${SESSION_LOGIN:-?}" det="${2//$'\t'/ }"
  det="${det//$'\n'/ }"
  mkdir -p "$CONTESTSDIR/treino/var" 2>/dev/null
  printf '%s\t%s\t%s\t%s\n' "$EPOCHSECONDS" "$who" "$1" "$det" \
    >> "$CONTESTSDIR/treino/var/admin-audit.log" 2>/dev/null || true
}

# activity_log <event> <details> — LOG DE ATIVIDADE do treino: eventos de LEITURA
# (problem-view, log-view, source-download) que escalam com page-view. SEPARADO do
# admin-audit (dominado por report de máquina) e ROTACIONADO POR MÊS no próprio nome
# (var/activity-YYYY-MM.log). TSV: epoch \t login("anon" sem sessão) \t event \t details \t ip.
# Consumido pelo feed /treino/admin/activity-log (kind=read). Evento novo de leitura na
# plataforma ⇒ instrumente com ESTE helper.
activity_log() {
  local who="${SESSION_LOGIN:-anon}" det="${2//$'\t'/ }" ym ip="-"
  det="${det//$'\n'/ }"
  printf -v ym '%(%Y-%m)T' "$EPOCHSECONDS"
  declare -F client_ip >/dev/null 2>&1 && ip="$(client_ip)"
  mkdir -p "$CONTESTSDIR/treino/var" 2>/dev/null
  printf '%s\t%s\t%s\t%s\t%s\n' "$EPOCHSECONDS" "$who" "$1" "$det" "${ip:--}" \
    >> "$CONTESTSDIR/treino/var/activity-$ym.log" 2>/dev/null || true
}

# audit_log_to <contest> <action> <details> — auditoria de um contest específico
# (contests/<contest>/var/admin-audit.log). Usado pelas ações do admin do contest.
audit_log_to() {
  local c="$1" who="${SESSION_LOGIN:-?}" det="${3//$'\t'/ }"
  det="${det//$'\n'/ }"
  valid_id "$c" || return 0
  mkdir -p "$CONTESTSDIR/$c/var" 2>/dev/null
  printf '%s\t%s\t%s\t%s\n' "$EPOCHSECONDS" "$who" "$2" "$det" \
    >> "$CONTESTSDIR/$c/var/admin-audit.log" 2>/dev/null || true
}
