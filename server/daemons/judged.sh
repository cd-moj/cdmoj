#!/bin/bash
# server/daemons/judged.sh — Daemon ASSÍNCRONO de julgamento (consumidor do spool).
#
# A API (server/api/v1/handlers/submit.sh) ENFILEIRA a submissão no $SPOOLDIR e
# retorna {submission_id,status:"queued"} na hora (não bloqueia). Este daemon é o
# consumidor: observa o spool com inotifywait (push) e, para cada arquivo novo:
#   1. lê o JSON {contest,login,problem_id,filename,code_b64,lang,time,id};
#   2. chama judge_run (server/judge-gw/judge.sh) p/ obter o veredicto;
#   3. troca a linha provisória "Not Answered Yet" terminada em ":<id>" no
#      contests/<contest>/controle/history pelo veredicto real (match seguro
#      pelo sufixo ":<id>", reescrita atômica via mv);
#   4. registra/atualiza contests/<contest>/data/<login>;
#   5. arquiva a fonte decodificada em
#      contests/<contest>/submissions/<id>-<login>-<problemid>.<lang>;
#   6. chama server/score/build.sh <contest> se existir (ignora se ainda não há);
#   7. move o arquivo de spool p/ $SPOOLDONEDIR.
# Arquivos ":rejulgar:" são tratados igual (re-julga + atualiza).
#
# Sem inotifywait? cai p/ um loop de polling. --once processa 1 arquivo e sai
# (testabilidade). Aditivo e file-based: NÃO altera api/** nem mojtools/**.
#
# Uso:
#   bash judged.sh            # daemon (inotify, ou polling se faltar inotifywait)
#   bash judged.sh --once     # processa exatamente 1 arquivo do spool e sai
#   bash judged.sh --drain    # processa tudo que já está no spool e sai (sem watch)

set -u

DAEMON_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"   # .../server/daemons
SERVER_DIR="$(cd "$DAEMON_DIR/.." && pwd)"                     # .../server

# config base (respeita overrides de ambiente)
_COMMON_CONF="$SERVER_DIR/etc/common.conf"
[[ -r "$_COMMON_CONF" ]] && source "$_COMMON_CONF"

: "${CONTESTSDIR:=/home/ribas/moj/contests}"
: "${RUNDIR:=/home/ribas/moj/run}"
: "${SPOOLDIR:=$RUNDIR/spool/submissions}"
: "${SPOOLDONEDIR:=$RUNDIR/spool/submissions-done}"
: "${SCORE_BUILD:=$SERVER_DIR/score/build.sh}"

# gateway de julgamento (expõe judge_run; honra $JUDGE_BACKEND)
JUDGE_GW="$SERVER_DIR/judge-gw/judge.sh"
# shellcheck source=/dev/null
source "$JUDGE_GW"

log() { echo "[judged $(date +%H:%M:%S)] $*" >&2; }

mkdir -p "$SPOOLDIR" "$SPOOLDONEDIR" 2>/dev/null

# valida id de contest antes de tocar contests/<id>/... (evita path traversal).
valid_contest_id() { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] && [[ "$1" != *..* ]]; }

# ---------------------------------------------------------------------------
# process_spool_file <abs-path-do-arquivo-de-spool>
# Retorna 0 se processou (e moveu p/ done), 1 se pulou.
# ---------------------------------------------------------------------------
process_spool_file() {
  local f="$1"
  local base; base="$(basename "$f")"

  # higiene: ignora dotfiles e temporários ".in.*" (escrita atômica do submit.sh)
  case "$base" in
    .*|*.tmp|.in.*) return 1 ;;
  esac
  [[ -f "$f" ]] || return 1

  # Nome: <contest>:<epoch>:<id>:<login>:<comando>:<problemid>:<FILETYPE>
  # comando ∈ {submit, rejulgar}. Lemos os dados de verdade do JSON (conteúdo).
  local comando; comando="$(cut -d: -f5 <<<"$base")"

  # JSON do conteúdo
  local json; json="$(cat "$f" 2>/dev/null)"
  if ! jq -e . >/dev/null 2>&1 <<<"$json"; then
    log "JSON inválido em $base — movendo p/ done (descartado)"
    mv -f "$f" "$SPOOLDONEDIR/$base" 2>/dev/null
    return 1
  fi

  local contest login problem filename code_b64 lang id
  contest="$(jq -r '.contest    // empty' <<<"$json")"
  login="$(  jq -r '.login      // empty' <<<"$json")"
  problem="$(jq -r '.problem_id // empty' <<<"$json")"
  filename="$(jq -r '.filename  // empty' <<<"$json")"
  code_b64="$(jq -r '.code_b64  // empty' <<<"$json")"
  lang="$(   jq -r '.lang       // empty' <<<"$json")"
  id="$(     jq -r '.id         // empty' <<<"$json")"

  # fallback: se o JSON não trouxe algo, deriva do nome do arquivo de spool.
  [[ -z "$contest" ]] && contest="$(cut -d: -f1 <<<"$base")"
  [[ -z "$id"      ]] && id="$(     cut -d: -f3 <<<"$base")"
  [[ -z "$login"   ]] && login="$(  cut -d: -f4 <<<"$base")"
  [[ -z "$problem" ]] && problem="$(cut -d: -f6 <<<"$base")"
  [[ -z "$lang"    ]] && lang="$(   cut -d: -f7 <<<"$base")"

  if ! valid_contest_id "$contest"; then
    log "contest inválido '$contest' em $base — descartado"
    mv -f "$f" "$SPOOLDONEDIR/$base" 2>/dev/null
    return 1
  fi
  if [[ -z "$id" || -z "$login" || -z "$problem" ]]; then
    log "campos faltando (id/login/problem) em $base — descartado"
    mv -f "$f" "$SPOOLDONEDIR/$base" 2>/dev/null
    return 1
  fi

  local cdir="$CONTESTSDIR/$contest"
  mkdir -p "$cdir/controle" "$cdir/data" "$cdir/submissions" 2>/dev/null

  log "julgando $base (contest=$contest login=$login prob=$problem lang=$lang id=$id cmd=${comando:-submit})"

  # ---- carrega CONTEST_END/CONTEST_TYPE/MOJCONTESTSERVERS p/ o backend cluster.
  # (source seguro: já validamos contest; o conf é confiável no deploy.)
  local CONTEST_START="" CONTEST_END="" CONTEST_TYPE="" MOJCONTESTSERVERS=""
  if [[ -r "$cdir/conf" ]]; then
    # shellcheck source=/dev/null
    source "$cdir/conf" 2>/dev/null || true
  fi
  export CONTEST_END CONTEST_TYPE MOJCONTESTSERVERS

  # ---- (2) chama o juiz ----------------------------------------------------
  local verdict
  verdict="$(judge_run "$contest" "$problem" "$lang" "$code_b64" "${filename:-solution}")"
  [[ -z "$verdict" ]] && verdict="Judge Error (empty verdict)"
  log "veredicto p/ id=$id: $verdict"

  # tempo (campo 1 do history): minutos/segundos desde o início do contest, como
  # no julgador legado. Sem CONTEST_START, usa o epoch (igual ao submit.sh).
  local sub_epoch tempo
  sub_epoch="$(jq -r '.time // empty' <<<"$json")"
  [[ -z "$sub_epoch" ]] && sub_epoch="$(cut -d: -f2 <<<"$base")"
  if [[ -n "${CONTEST_START:-}" && "$CONTEST_START" =~ ^[0-9]+$ && "$sub_epoch" =~ ^[0-9]+$ ]]; then
    tempo=$(( sub_epoch - CONTEST_START ))
  else
    tempo="$sub_epoch"
  fi

  # ---- (3) troca a linha provisória do history pela definitiva --------------
  # Match SEGURO pelo sufixo ":<id>" (o id é md5 — único). Reescrita atômica.
  # Formato (7 campos): <tempo>:<login>:<probid>:<lang>:<verdict>:<epoch>:<id>
  update_history "$cdir/controle/history" "$id" \
    "$tempo:$login:$problem:$lang:$verdict:$sub_epoch:$id"

  # ---- (4) registra/atualiza data/<login> ----------------------------------
  # Formato observado: <epoch>:<id>:<probid>:<verdict>  (1 linha por submissão).
  update_data "$cdir/data/$login" "$id" "$sub_epoch:$id:$problem:$verdict"

  # ---- (5) arquiva a fonte decodificada ------------------------------------
  # contests/<contest>/submissions/<id>-<login>-<problemid>.<lang>
  local llang dest
  llang="$(printf '%s' "$lang" | tr '[:upper:]' '[:lower:]')"
  dest="$cdir/submissions/$id-$login-$problem.${llang:-txt}"
  if [[ -n "$code_b64" ]]; then
    local tmpsrc="$dest.tmp.$$"
    if printf '%s' "$code_b64" | base64 -d > "$tmpsrc" 2>/dev/null; then
      mv -f "$tmpsrc" "$dest"
    else
      rm -f "$tmpsrc"
      log "não consegui decodificar a fonte de $id (base64 inválido)"
    fi
  fi

  # ---- (6) recalcula placar, se o builder existir --------------------------
  if [[ -x "$SCORE_BUILD" || -r "$SCORE_BUILD" ]]; then
    bash "$SCORE_BUILD" "$contest" >/dev/null 2>&1 \
      || log "score/build.sh falhou p/ $contest (ignorando)"
  fi

  # ---- (7) arquiva o arquivo de spool --------------------------------------
  mv -f "$f" "$SPOOLDONEDIR/$base" 2>/dev/null
  log "concluído $base -> $SPOOLDONEDIR/"
  return 0
}

# ---------------------------------------------------------------------------
# update_history <history-file> <id> <nova-linha>
# Substitui a linha que termina em ":<id>" pela <nova-linha>. Se não existir
# (corrida / submit.sh ainda não escreveu), acrescenta. Atômico via mv.
# ---------------------------------------------------------------------------
update_history() {
  local hist="$1" id="$2" newline="$3"
  mkdir -p "$(dirname "$hist")" 2>/dev/null
  [[ -e "$hist" ]] || : > "$hist"

  local tmp="$hist.tmp.$$"
  # awk: match exato do último campo (sufixo ":<id>") — id é md5, sem metachars.
  if grep -q ":$id\$" "$hist" 2>/dev/null; then
    awk -v id=":$id" -v repl="$newline" '
      index($0, id) == length($0) - length(id) + 1 { print repl; next }
      { print }
    ' "$hist" > "$tmp" && mv -f "$tmp" "$hist"
  else
    # sem linha provisória: acrescenta (mantém consistência).
    { cat "$hist"; printf '%s\n' "$newline"; } > "$tmp" && mv -f "$tmp" "$hist"
  fi
}

# ---------------------------------------------------------------------------
# update_data <data-file> <id> <nova-linha>
# Atualiza (ou acrescenta) a linha cujo 2º campo é <id>. Atômico via mv.
# (submit.sh só escreve no history, então normalmente acrescentamos aqui.)
# ---------------------------------------------------------------------------
update_data() {
  local file="$1" id="$2" newline="$3"
  mkdir -p "$(dirname "$file")" 2>/dev/null
  [[ -e "$file" ]] || : > "$file"

  local tmp="$file.tmp.$$"
  if awk -F: -v id="$id" '$2==id{found=1} END{exit !found}' "$file" 2>/dev/null; then
    awk -F: -v id="$id" -v repl="$newline" '
      $2==id { print repl; next } { print }
    ' "$file" > "$tmp" && mv -f "$tmp" "$file"
  else
    { cat "$file"; printf '%s\n' "$newline"; } > "$tmp" && mv -f "$tmp" "$file"
  fi
  chmod go+rw "$file" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Modos de execução
# ---------------------------------------------------------------------------

# pega o "próximo" arquivo elegível do spool (ignora dotfiles/.in.*/.tmp).
next_spool_file() {
  local f
  for f in "$SPOOLDIR"/*; do
    [[ -e "$f" ]] || continue
    local b; b="$(basename "$f")"
    case "$b" in .*|*.tmp|.in.*) continue ;; esac
    printf '%s\n' "$f"
    return 0
  done
  return 1
}

# --drain: processa tudo que já está no spool e sai.
drain_spool() {
  local f processed=0
  while f="$(next_spool_file)"; do
    process_spool_file "$f" && ((processed++))
    # se process pulou (retornou 1) sem mover, evita loop infinito:
    [[ -e "$f" ]] && case "$(basename "$f")" in .*|*.tmp|.in.*) ;; *) ! [[ -e "$f" ]] || break ;; esac
  done
  log "drain: $processed arquivo(s) processado(s)"
}

# loop principal: inotify (push) com fallback p/ polling.
watch_loop() {
  if command -v inotifywait >/dev/null 2>&1; then
    log "watch: inotifywait em $SPOOLDIR (push)"
    # primeiro drena o que já estava lá (eventos perdidos antes do watch).
    local f
    while f="$(next_spool_file)"; do process_spool_file "$f" || break; done
    # então reage a novos arquivos.
    inotifywait -m -q -e create -e moved_to --format '%f' "$SPOOLDIR" | \
    while read -r name; do
      case "$name" in .*|*.tmp|.in.*) continue ;; esac
      process_spool_file "$SPOOLDIR/$name"
    done
  else
    log "watch: inotifywait AUSENTE — fallback p/ polling (1s)"
    while true; do
      local f
      while f="$(next_spool_file)"; do
        process_spool_file "$f" || break
      done
      sleep 1
    done
  fi
}

# espera (até timeout) por um arquivo elegível, p/ o modo --once em testes.
wait_for_one() {
  local timeout="${ONCE_TIMEOUT:-30}" waited=0 f
  while (( waited < timeout )); do
    if f="$(next_spool_file)"; then printf '%s\n' "$f"; return 0; fi
    sleep 0.2
    waited="$(awk -v w="$waited" 'BEGIN{print w+1}')"
  done
  return 1
}

main() {
  case "${1:-}" in
    --once)
      log "modo --once: processa 1 arquivo e sai (SPOOLDIR=$SPOOLDIR, backend=$JUDGE_BACKEND)"
      local f
      if f="$(next_spool_file)" || f="$(wait_for_one)"; then
        process_spool_file "$f"
        exit $?
      fi
      log "--once: nenhum arquivo no spool"
      exit 1
      ;;
    --drain)
      drain_spool
      exit 0
      ;;
    ""|--watch|--daemon)
      watch_loop
      ;;
    -h|--help)
      grep -E '^# (Uso|  bash)' "$0" | sed 's/^# //'
      exit 0
      ;;
    *)
      echo "argumento desconhecido: $1 (use --once|--drain|--watch)" >&2
      exit 2
      ;;
  esac
}

main "$@"
