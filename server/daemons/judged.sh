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

# escalonador in-daemon (fila por prioridade + registro de workers) + ingestão pull
source "$SERVER_DIR/judge-gw/sched-lib.sh"
: "${RESULTSDIR:=$RUNDIR/results}"
# INTAKE_MODE=legacy|queue (global); INTAKE_QUEUE_CONTESTS="c1 c2" habilita por contest.
: "${INTAKE_MODE:=legacy}"

log() { echo "[judged $(date +%H:%M:%S)] $*" >&2; }

mkdir -p "$SPOOLDIR" "$SPOOLDONEDIR" 2>/dev/null

# valida id de contest antes de tocar contests/<id>/... (evita path traversal).
valid_contest_id() { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] && [[ "$1" != *..* ]]; }

# queue_mode_for <contest> : 0 se o intake deste contest deve ir p/ a fila (pull).
queue_mode_for() {
  [[ "${INTAKE_MODE:-legacy}" == queue ]] && return 0
  case " ${INTAKE_QUEUE_CONTESTS:-} " in *" $1 "*) return 0;; esac
  return 1
}

# archive_source <contest> <id> <login> <problem> <lang> <code_b64>
# Arquiva a fonte decodificada em submissions/<id>-<login>-<problem>.<lang>.
archive_source() {
  local contest="$1" id="$2" login="$3" problem="$4" lang="$5" code_b64="$6"
  [[ -n "$code_b64" ]] || return 0
  local cdir="$CONTESTSDIR/$contest" llang dest tmp
  llang="$(printf '%s' "$lang" | tr '[:upper:]' '[:lower:]')"
  mkdir -p "$cdir/submissions" 2>/dev/null
  dest="$cdir/submissions/$id-$login-$problem.${llang:-txt}"; tmp="$dest.tmp.$$"
  if printf '%s' "$code_b64" | base64 -d > "$tmp" 2>/dev/null; then mv -f "$tmp" "$dest"; else rm -f "$tmp"; fi
}

# intake_enqueue ... : enfileira a submissão na banda do CONTEST_PRIORITY (não bloqueia).
intake_enqueue() {
  local json="$1" contest="$2" id="$3" login="$4" problem="$5" lang="$6" filename="$7" code_b64="$8"
  local prio="${CONTEST_PRIORITY:-lista-publica}"
  archive_source "$contest" "$id" "$login" "$problem" "$lang" "$code_b64"
  local job
  job="$(jq -cn --arg id "$id" --arg c "$contest" --arg p "$problem" --arg login "$login" \
    --arg lang "$lang" --arg f "${filename:-solution}" --arg b "$code_b64" \
    --arg prio "$prio" --argjson now "$EPOCHSECONDS" \
    '{id:$id, contest:$c, problem_id:$p, login:$login, lang:$lang, filename:$f,
      code_b64:$b, priority:$prio, enqueued_at:$now}')"
  q_enqueue "$id" "$prio" "$job"
}

# write_result_json ... : grava o results/<id>.json canônico (sem o b64, com ref do HTML).
write_result_json() {
  local contest="$1" id="$2" login="$3" problem="$4" json="$5"
  local cdir="$CONTESTSDIR/$contest" out
  mkdir -p "$cdir/results" "$RESULTSDIR" 2>/dev/null
  out="$(jq -c --arg login "$login" --arg prob "$problem" --argjson now "$EPOCHSECONDS" '
    del(.report_html_b64)
    + { login:(.login // $login), problem_id:(.problem_id // $prob),
        report_html:("mojlog/\(.id)-\($login)-\($prob).html"), finalized_at:$now }' \
    <<<"$json" 2>/dev/null)"
  [[ -n "$out" ]] || return 0
  local tmp="$cdir/results/.$id.tmp"
  printf '%s' "$out" > "$tmp" && mv -f "$tmp" "$cdir/results/$id.json"
  cp -f "$cdir/results/$id.json" "$RESULTSDIR/$id.json" 2>/dev/null || true
}

# ingest_result <result-json> : finaliza um julgamento vindo do worker (modelo pull).
# Único escritor do history. Herda tempo/login/prob/lang/epoch da linha provisória.
ingest_result() {
  local json="$1"
  local id contest host verdict h_login h_prob h_lang tempo sub_epoch line hist
  id="$(jq -r '.id // empty' <<<"$json")"
  contest="$(jq -r '.contest // empty' <<<"$json")"
  host="$(jq -r '.host // empty' <<<"$json")"
  verdict="$(jq -r '.verdict // "Judge Error"' <<<"$json")"
  valid_contest_id "$contest" || { log "result: contest inválido"; return 1; }
  [[ -n "$id" ]] || { log "result: sem id"; return 1; }
  local cdir="$CONTESTSDIR/$contest"; hist="$cdir/controle/history"
  mkdir -p "$cdir/controle" "$cdir/data" "$cdir/mojlog" "$cdir/results" 2>/dev/null
  line="$(grep ":$id\$" "$hist" 2>/dev/null | tail -n1)"
  IFS=: read -r tempo h_login h_prob h_lang _ sub_epoch _ <<<"$line"
  [[ -n "$h_login" ]] || h_login="$(jq -r '.login // ""' <<<"$json")"
  [[ -n "$h_prob"  ]] || h_prob="$(jq -r '.problem_id // ""' <<<"$json")"
  [[ -n "$h_lang"  ]] || h_lang="$(jq -r '(.lang // "")|ascii_upcase' <<<"$json")"
  [[ -n "$sub_epoch" ]] || sub_epoch="$EPOCHSECONDS"
  [[ -n "$tempo" ]] || tempo="$sub_epoch"
  update_history "$hist" "$id" "$tempo:$h_login:$h_prob:$h_lang:$verdict:$sub_epoch:$id"
  update_data "$cdir/data/$h_login" "$id" "$sub_epoch:$id:$h_prob:$verdict"
  local html_b64; html_b64="$(jq -r '.report_html_b64 // empty' <<<"$json")"
  [[ -n "$html_b64" ]] && printf '%s' "$html_b64" | base64 -d \
    > "$cdir/mojlog/$id-$h_login-$h_prob.html" 2>/dev/null
  write_result_json "$contest" "$id" "$h_login" "$h_prob" "$json"
  [[ -n "$host" ]] && q_done "$host" "$id"
  [[ -e "$SCORE_BUILD" ]] && bash "$SCORE_BUILD" "$contest" >/dev/null 2>&1
  log "result ingerido id=$id contest=$contest verdict=$verdict"
  return 0
}

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

  # comando "synctreino": atualização dos problemas do treino (NFS) via update-request.
  # O arquivo de spool é vazio; tratamos antes de tentar ler JSON.
  if [[ "$comando" == synctreino ]]; then
    local sycontest; sycontest="$(cut -d: -f1 <<<"$base")"
    upd_request "${TREINO_REPO:-}" "${sycontest:-treino}" "synctreino" >/dev/null
    mv -f "$f" "$SPOOLDONEDIR/$base" 2>/dev/null
    log "synctreino -> update-request (repo='${TREINO_REPO:-todos}')"
    return 0
  fi

  # comando "rejulgar": o arquivo de spool é VAZIO (só marcador). Reconstruímos a submissão
  # original (metadados do history + fonte arquivada) e RE-JULGAMOS, atualizando a MESMA linha
  # (match por :<id>). Sem isto o rejulgar não fazia NADA (JSON vazio -> descartado).
  local json
  if [[ "$comando" == rejulgar ]]; then
    local rc rid; rc="$(cut -d: -f1 <<<"$base")"; rid="$(cut -d: -f3 <<<"$base")"
    if ! valid_contest_id "$rc"; then log "rejulgar: contest inválido em $base"; mv -f "$f" "$SPOOLDONEDIR/$base" 2>/dev/null; return 1; fi
    local rhist="$CONTESTSDIR/$rc/controle/history" rline
    rline="$(grep ":$rid\$" "$rhist" 2>/dev/null | tail -n1)"
    if [[ -z "$rline" ]]; then log "rejulgar: $rid não está no history de $rc"; mv -f "$f" "$SPOOLDONEDIR/$base" 2>/dev/null; return 1; fi
    local r_tempo r_login r_prob r_lang r_sub
    IFS=: read -r r_tempo r_login r_prob r_lang _ r_sub _ <<<"$rline"
    local r_llang r_src r_b64=""
    r_llang="$(printf '%s' "$r_lang" | tr '[:upper:]' '[:lower:]')"
    r_src="$CONTESTSDIR/$rc/submissions/$rid-$r_login-$r_prob.${r_llang:-txt}"
    [[ -f "$r_src" ]] && r_b64="$(base64 -w0 < "$r_src" 2>/dev/null)"
    if [[ -z "$r_b64" ]]; then log "rejulgar: fonte ausente p/ $rid ($r_src)"; mv -f "$f" "$SPOOLDONEDIR/$base" 2>/dev/null; return 1; fi
    # provisório "Not Answered Yet" -> aparece como PENDENTE na Situação enquanto re-julga
    update_history "$rhist" "$rid" "$r_tempo:$r_login:$r_prob:$r_lang:Not Answered Yet:$r_sub:$rid"
    json="$(jq -cn --arg c "$rc" --arg l "$r_login" --arg p "$r_prob" --arg lang "$r_lang" \
      --arg b "$r_b64" --arg fn "solution.${r_llang:-txt}" --argjson t "${r_sub:-$EPOCHSECONDS}" --arg id "$rid" \
      '{contest:$c, login:$l, problem_id:$p, filename:$fn, code_b64:$b, lang:$lang, time:$t, id:$id}')"
    comando=submit   # daqui em diante: trata como submit (enfileira/julga + troca a linha :id)
  else
    # JSON do conteúdo (submit/result normais)
    json="$(cat "$f" 2>/dev/null)"
    if ! jq -e . >/dev/null 2>&1 <<<"$json"; then
      log "JSON inválido em $base — movendo p/ done (descartado)"
      mv -f "$f" "$SPOOLDONEDIR/$base" 2>/dev/null
      return 1
    fi
  fi

  # ---- comando "result": ingestão do veredicto vindo do worker (modelo pull) ----
  if [[ "$comando" == result ]]; then
    ingest_result "$json"
    mv -f "$f" "$SPOOLDONEDIR/$base" 2>/dev/null
    return 0
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
  mkdir -p "$cdir/controle" "$cdir/data" "$cdir/submissions" "$cdir/mojlog" 2>/dev/null

  log "julgando $base (contest=$contest login=$login prob=$problem lang=$lang id=$id cmd=${comando:-submit})"

  # ---- carrega CONTEST_END/CONTEST_TYPE/MOJCONTESTSERVERS p/ o backend cluster.
  # (source seguro: já validamos contest; o conf é confiável no deploy.)
  local CONTEST_START="" CONTEST_END="" CONTEST_TYPE="" MOJCONTESTSERVERS="" CONTEST_PRIORITY=""
  if [[ -r "$cdir/conf" ]]; then
    # shellcheck source=/dev/null
    source "$cdir/conf" 2>/dev/null || true
  fi
  export CONTEST_END CONTEST_TYPE MOJCONTESTSERVERS

  # ---- INTAKE (modo fila): enfileira p/ o escalonador in-daemon (pull) ----------
  # Em vez de julgar agora (bloqueante), enfileira na banda de prioridade; um worker
  # puxa no heartbeat. O resultado volta depois pelo comando "result".
  if [[ "$comando" == submit ]] && queue_mode_for "$contest"; then
    intake_enqueue "$json" "$contest" "$id" "$login" "$problem" "$lang" "$filename" "$code_b64"
    mv -f "$f" "$SPOOLDONEDIR/$base" 2>/dev/null
    log "enfileirado (queue, prio=${CONTEST_PRIORITY:-lista-publica}) $base"
    return 0
  fi

  # ---- (2) chama o juiz ----------------------------------------------------
  # Diz ao gateway onde gravar o report.html auto-contido (servido pela API em
  # mojlog/*<id>*). Backends que não produzem report ignoram esta variável.
  export JUDGE_REPORT_OUT="$cdir/mojlog/$id-$login-$problem.html"
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
