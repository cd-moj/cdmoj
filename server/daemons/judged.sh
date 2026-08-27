#!/bin/bash
# server/daemons/judged.sh — Daemon ASSÍNCRONO de julgamento (consumidor do spool).
#
# A API (server/api/v1/handlers/submit.sh) ENFILEIRA a submissão no $SPOOLDIR e
# retorna {submission_id,status:"queued"} na hora (não bloqueia). Este daemon é o
# consumidor: observa o spool com inotifywait (push) e, para cada arquivo novo:
#   1. lê o JSON {contest,login,problem_id,filename,code_b64,lang,time,id};
#   2. chama judge_run (server/judge-gw/judge.sh) p/ obter o veredicto;
#   3. troca a linha provisória "Not Answered Yet" terminada em ":<id>" no
#      users/<login>/history pelo veredicto real (match seguro
#      pelo sufixo ":<id>", reescrita atômica via mv);
#   4. recomputa users/<login>/metrics.json (fonte do placar);
#   5. arquiva a fonte decodificada em users/<login>/submissions/<id>.<lang>;
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
# Janela de COALESCÊNCIA do rebuild do placar (s). O build.sh relê ~3000 arquivos + monta o
# placar inteiro (~0,7s p/ 1152 users, ~1s p/ 1500) — antes ele rodava INLINE a CADA veredicto,
# então a ingestão travava em ~1,4 veredictos/s (o daemon é serial). Agora o rebuild é
# coalescido: no máx. 1× a cada SCORE_COALESCE_S por contest. Numa rajada de 50 veredictos =
# 1 rebuild, não 50. O trabalho por-veredicto que sobra (metrics_recompute de 1 usuário,
# ~2ms + write_result) não bloqueia mais. Nada se perde: metrics_recompute já tocou
# .score-dirty, então o placar pulado é regenerado pelo próximo veredicto após a janela OU
# pelo /contest/score (regen preguiçoso). 0 desliga a coalescência (volta ao inline).
: "${SCORE_COALESCE_S:=5}"

# gateway de julgamento (expõe judge_run; honra $JUDGE_BACKEND)
JUDGE_GW="$SERVER_DIR/judge-gw/judge.sh"
# shellcheck source=/dev/null
source "$JUDGE_GW"

# escalonador in-daemon (fila por prioridade + registro de workers) + ingestão pull
source "$SERVER_DIR/judge-gw/sched-lib.sh"
# store por-usuário (user_dir, user_history_*, metrics_*) — write-path universal
source "$SERVER_DIR/api/v1/lib/users.sh"
: "${RESULTSDIR:=$RUNDIR/results}"
# INTAKE_MODE=legacy|queue (global); INTAKE_QUEUE_CONTESTS="c1 c2" habilita por contest.
: "${INTAKE_MODE:=legacy}"

# ---- helpers de write-path (store por-usuário) ----------------------------
# report_out_path <c> <login> <problem> <id> : caminho absoluto do report .html.
report_out_path() {
  printf '%s/mojlog/%s.html' "$(user_dir "$1" "$2")" "$4"
}
# report_html_rel <c> <login> <problem> <id> : caminho relativo gravado no result/review json.
report_html_rel() {
  printf 'mojlog/%s.html' "$4"
}
# record_verdict <c> <login> <tempo> <problem> <lang> <verdict> <sub_epoch> <id> : finaliza no history.
record_verdict() {
  local c="$1" login="$2" tempo="$3" prob="$4" lang="$5" verdict="$6" se="$7" id="$8"
  user_history_replace "$c" "$login" "$id" "$tempo:$prob:$lang:$verdict:$se:$id"
  metrics_recompute "$c" "$login"
}
# record_provisional <c> <login> <tempo> <problem> <lang> <sub_epoch> <id> : marca "Not Answered Yet".
record_provisional() {
  local c="$1" login="$2" tempo="$3" prob="$4" lang="$5" se="$6" id="$7"
  user_history_replace "$c" "$login" "$id" "$tempo:$prob:$lang:Not Answered Yet:$se:$id"
  metrics_recompute "$c" "$login"   # placar lê só metrics: PENDING precisa aparecer já
}
# schedule_score_rebuild <contest> — rebuild COALESCIDO do placar (ver SCORE_COALESCE_S).
# Substitui o `bash build.sh` inline por-veredicto. Gate no mtime do PRÓPRIO placar.txt: se
# foi reconstruído há menos de SCORE_COALESCE_S (pelo daemon OU pelo handler /contest/score,
# que também regrava placar.txt), pula. Assim a ingestão não bloqueia no build e a entrega de
# veredicto deixa de ser limitada pelo tempo de placar. build.sh grava atômico (mktemp+mv),
# então um build coalescido e o regen preguiçoso do handler nunca se corrompem.
schedule_score_rebuild() {
  local contest="$1"
  [[ -e "$SCORE_BUILD" ]] || return 0
  local out="$CONTESTSDIR/$contest/var/placar.txt"
  if (( SCORE_COALESCE_S > 0 )) \
     && [[ -n "$(find "$out" -newermt "-$SCORE_COALESCE_S seconds" 2>/dev/null)" ]]; then
    return 0   # placar reconstruído há < janela; o próximo evento/visita cobre o resto
  fi
  # DESTACADO (2026-08-27): o build rodava INLINE aqui — e este processo é o consumidor SERIAL
  # da fila de veredictos. Com o build medido em 4,4 s na escala da Maratona (2.355 contas,
  # 3 visões) e a janela de coalescência em 5 s, a ingestão passaria ~metade do tempo parada
  # montando placar — de volta ao gargalo que o SCORE_COALESCE_S existia para matar, só que
  # maior. O filho carrega o flock do handler (.placar.lock) p/ nunca haver dois builds do
  # mesmo contest; se outro build está em voo, este simplesmente não nasce (-n).
  # ⚠ fds DENTRO do parêntese (a lição do setsid sob CGI vale p/ daemon também: sem isso o
  # filho herda os fds do daemon e aparece preso em ferramentas que esperam o pipe fechar).
  ( setsid bash -c '
      exec 9>>"$1.lock" 2>/dev/null || exit 0
      flock -n 9 || exit 0
      bash "$2" "$3"' _ "$CONTESTSDIR/$contest/var/.placar" "$SCORE_BUILD" "$contest" \
      </dev/null >/dev/null 2>&1 & ) 2>/dev/null
}
# hist_line_by_id <c> <login> <id> : ecoa a linha de history da submissão (normalizada p/ 7 campos
# <tempo>:<login>:<prob>:<lang>:<verdict>:<sub_epoch>:<id>, com login preenchido), ou vazio.
hist_line_by_id() {
  local c="$1" login="$2" id="$3"
  local hf; hf="$(user_hist_file "$c" "$login")"
  awk -F: -v id="$id" -v u="$login" '$NF==id{
    v=$4; for(i=5;i<=NF-2;i++) v=v":"$i;
    print $1":"u":"$2":"$3":"v":"$(NF-1)":"$NF; exit}' "$hf" 2>/dev/null
}

log() { echo "[judged $(date +%H:%M:%S)] $*" >&2; }

# clog <contest> <action> <details> : registra um evento do daemon NO LOG DO CONTEST
# (mesmo arquivo/formato da auditoria do admin, com who="judged") p/ o admin do contest
# enxergar problemas — descartes, erros de juiz, rejulgar que falhou. Sanitiza tab/newline.
clog() {
  local c="$1" action="$2" det="${3//$'\t'/ }"; det="${det//$'\n'/ }"
  [[ "$c" =~ ^[A-Za-z0-9._-]+$ && "$c" != *..* ]] || return 0
  mkdir -p "$CONTESTSDIR/$c/var" 2>/dev/null
  printf '%s\t%s\t%s\t%s\n' "$EPOCHSECONDS" "judged" "$action" "$det" \
    >> "$CONTESTSDIR/$c/var/admin-audit.log" 2>/dev/null || true
}

mkdir -p "$SPOOLDIR" "$SPOOLDONEDIR" 2>/dev/null

# valida id de contest antes de tocar contests/<id>/... (evita path traversal).
valid_contest_id() { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] && [[ "$1" != *..* ]]; }

# contest_is_demo <c> — conf com DEMO=1? Leitura BUILTIN, sem fork e sem `source` (o conf leva
# `printf %q` e nunca é sourceado fora do caminho de contest). ⚠ Reimplementado aqui de
# propósito: o daemon NÃO carrega `api/v1/lib/common.sh` (só users.sh + o judge-gw), então o
# `conf_value` de lá não existe neste processo — a primeira versão desta guarda chamava-o e
# morria com "command not found", deixando o gate mudo (pego pelo teste, não em produção).
contest_is_demo() {
  local f="$CONTESTSDIR/$1/conf" line v
  [[ -r "$f" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == DEMO=* ]] || continue
    v="${line#DEMO=}"; v="${v//\'/}"; v="${v//\"/}"
    [[ "$v" == 1 ]] && return 0
    return 1
  done < "$f"
  return 1
}

# queue_mode_for <contest> : 0 se o intake deste contest deve ir p/ a fila (pull).
queue_mode_for() {
  [[ "${INTAKE_MODE:-legacy}" == queue ]] && return 0
  case " ${INTAKE_QUEUE_CONTESTS:-} " in *" $1 "*) return 0;; esac
  return 1
}

# archive_source <contest> <id> <login> <problem> <lang> <code_b64>
# Arquiva a fonte decodificada em users/<login>/submissions/<id>.<lang>.
archive_source() {
  local contest="$1" id="$2" login="$3" problem="$4" lang="$5" code_b64="$6"
  [[ -n "$code_b64" ]] || return 0
  local llang dest tmp
  llang="$(printf '%s' "$lang" | tr '[:upper:]' '[:lower:]')"
  dest="$(user_dir "$contest" "$login")/submissions/$id.${llang:-txt}"
  mkdir -p "$(dirname "$dest")" 2>/dev/null
  tmp="$dest.tmp.$$"
  if printf '%s' "$code_b64" | base64 -d > "$tmp" 2>/dev/null; then mv -f "$tmp" "$dest"; else rm -f "$tmp"; fi
}

# intake_enqueue ... : enfileira a submissão na banda do CONTEST_PRIORITY (não bloqueia).
intake_enqueue() {
  local json="$1" contest="$2" id="$3" login="$4" problem="$5" lang="$6" filename="$7" code_b64="$8"
  local prio="${CONTEST_PRIORITY:-lista-publica}"
  archive_source "$contest" "$id" "$login" "$problem" "$lang" "$code_b64"
  # pool de juízes EFETIVO (override do problema -> pool do contest -> todas): vira
  # allowed_hosts no job; o q_claim só entrega a host listado (estrito por default).
  # CONTEST_JUDGES vem do conf sourced pelo chamador; tolerante a id 'repo#prob'/'repo/prob'.
  local ah='[]' pjf="$CONTESTSDIR/$contest/problem-judges.json"
  if [[ -f "$pjf" ]]; then
    ah="$(jq -c --arg p "$problem" '
      . as $m | ([$p, ($p|gsub("#";"/")), ($p|gsub("/";"#"))] | unique) as $vs
      | ([ $vs[] | $m[.] // empty ] | .[0]) // []' "$pjf" 2>/dev/null)"
    [[ -n "$ah" ]] || ah='[]'
  fi
  if [[ "$ah" == '[]' && -n "${CONTEST_JUDGES:-}" ]]; then
    ah="$(printf '%s\n' $CONTEST_JUDGES | grep -v '^$' | jq -R . | jq -cs .)"
    [[ -n "$ah" ]] || ah='[]'
  fi
  # a FONTE vai ao jq por ARQUIVO (--rawfile): `--arg b` estoura ARG_MAX >~96 KiB e o job
  # sairia vazio/mudo — a mesma classe do incidente 2026-08-19 no /submit
  local job _bf; _bf="$(mktemp)"; printf '%s' "$code_b64" > "$_bf"
  job="$(jq -cn --arg id "$id" --arg c "$contest" --arg p "$problem" --arg login "$login" \
    --arg lang "$lang" --arg f "${filename:-solution}" --rawfile b "$_bf" \
    --arg prio "$prio" --argjson now "$EPOCHSECONDS" --argjson ah "$ah" \
    '{id:$id, contest:$c, problem_id:$p, login:$login, lang:$lang, filename:$f,
      code_b64:$b, priority:$prio, enqueued_at:$now}
     + (if ($ah|length) > 0 then {allowed_hosts:$ah} else {} end)')"
  rm -f "$_bf"
  if [[ -z "$job" ]]; then
    log "intake_enqueue: job vazio (jq falhou) id=$id — Judge Error em vez de silêncio"
    clog "$contest" intake-falhou "id=$id login=$login prob=$problem motivo=job-vazio"
    record_verdict "$contest" "$login" "$EPOCHSECONDS" "$problem" "$lang" "Judge Error" "$EPOCHSECONDS" "$id"
    schedule_score_rebuild "$contest"; return 1
  fi
  q_enqueue "$id" "$prio" "$job"
}

# ===== Veredicto MANUAL (.judge): segura o veredicto computado p/ revisão de 2 juízes ======

# auto_allows <contest> <cid> <lang> <verdict> : 0 se a matriz auto-verdicts.json permite que
# este (problema, linguagem, veredicto) saia AUTOMÁTICO (lang minúsculo ou '*' = qualquer).
auto_allows() {
  local f="$CONTESTSDIR/$1/auto-verdicts.json"; [[ -f "$f" ]] || return 1
  local lang_lc; lang_lc="$(printf '%s' "$3" | tr '[:upper:]' '[:lower:]')"
  jq -e --arg p "$2" --arg pp "${2//\//#}" --arg l "$lang_lc" --arg v "$4" '
    ((.[$p] // .[$pp] // {})) as $m
    | (($m[$l] // []) + ($m["*"] // [])) | index($v)' "$f" >/dev/null 2>&1
}

# should_hold <contest> <login> <cid> <lang> <verdict> : 0 se deve SEGURAR p/ revisão manual.
# Condições: MANUAL_VERDICT=1 no conf, submissor NÃO-privilegiado, veredicto real (não erro de
# juiz), e NÃO permitido pela matriz auto. Lê MANUAL_VERDICT via grep (ingest_result não dá source).
should_hold() {
  local contest="$1" login="$2" prob="$3" lang="$4" verdict="$5" vcanon="${6:-$5}" mv
  mv="$(grep -m1 '^MANUAL_VERDICT=' "$CONTESTSDIR/$contest/conf" 2>/dev/null | cut -d= -f2-)"
  mv="${mv//\'/}"; mv="${mv//\"/}"
  [[ "$mv" == 1 ]] || return 1
  case "$login" in *.admin|*.judge|*.cjudge|*.staff|*.cstaff|*.mon|*.animeitor) return 1;; esac
  # transientes não viram item de revisão. ERROS de juiz (Judge Error/No_Servers) AGORA são
  # SEGURADOS no modo manual: não vazam p/ o competidor (ele vê só 'Not Answered Yet') — o juiz
  # vê o erro no painel e re-julga. O auto-veredicto casa pelo CANÔNICO (sem o sufixo de score).
  case "$verdict" in "Not Answered Yet"|"On queue"|"Running"|"") return 1;; esac
  auto_allows "$contest" "$prob" "$lang" "$vcanon" && return 1
  return 0
}

# write_review_item <contest> <id> <login> <cid> <lang> <sub_epoch> <verdict> : cria/atualiza
# contests/<c>/review/<id>.json (fila de revisão) e audita verdict-held.
write_review_item() {
  local contest="$1" id="$2" login="$3" prob="$4" lang="$5" sub_epoch="$6" verdict="$7"
  local dir="$CONTESTSDIR/$contest/review"; mkdir -p "$dir"
  local rel; rel="$(report_html_rel "$contest" "$login" "$prob" "$id")"
  jq -cn --arg id "$id" --arg c "$contest" --arg l "$login" --arg p "$prob" --arg lang "$lang" \
    --argjson se "${sub_epoch:-0}" --arg v "$verdict" --arg rel "$rel" --argjson now "$EPOCHSECONDS" \
    '{id:$id, contest:$c, login:$l, problem_id:$p, lang:$lang, sub_epoch:$se,
      computed_verdict:$v, report_html:$rel,
      created_at:$now, status:"open", claimants:[], votes:[], conflict:false,
      released_verdict:null, released_by:null, released_at:null}' \
    > "$dir/.$id.tmp" && mv -f "$dir/.$id.tmp" "$dir/$id.json"
  clog "$contest" verdict-held "id=$id login=$login prob=$prob lang=$lang verdict=$verdict"
}

# consume_setverdict <json> : aplica o veredicto manual decidido (2 juízes / chefe) à submissão.
# Finaliza pelo MESMO escritor único (record_verdict) + write_result_json (p/ entrar no timeline
# de auditoria) e marca review/<id>.json como released. Herda metadados da linha :id do history.
consume_setverdict() {
  local json="$1" contest verdict id username problem
  contest="$(jq -r '.contest // empty' <<<"$json")"
  verdict="$(jq -r '.verdict // empty' <<<"$json")"
  id="$(jq -r '.id // empty' <<<"$json")"
  username="$(jq -r '.username // empty' <<<"$json")"
  problem="$(jq -r '.problem_id // empty' <<<"$json")"
  valid_contest_id "$contest" || { log "setverdict: contest inválido"; return 1; }
  [[ -n "$verdict" ]] || { log "setverdict: sem verdict"; return 1; }
  local cdir="$CONTESTSDIR/$contest" line=""
  [[ -n "$username" ]] && line="$(hist_line_by_id "$contest" "$username" "$id")"
  if [[ -z "$line" && -n "$id" && -f "$cdir/review/$id.json" ]]; then
    local rl; rl="$(jq -r '.login // empty' "$cdir/review/$id.json" 2>/dev/null)"
    [[ -n "$rl" ]] && line="$(hist_line_by_id "$contest" "$rl" "$id")"
  fi
  [[ -n "$line" ]] || { log "setverdict: submissão não achada (id=$id user=$username prob=$problem)"; clog "$contest" verdict-set-falhou "id=$id user=$username prob=$problem motivo=sem-history"; return 1; }
  local tempo h_login h_prob h_lang _v sub_epoch h_id
  IFS=: read -r tempo h_login h_prob h_lang _v sub_epoch h_id <<<"$line"
  [[ -n "$id" ]] || id="$h_id"
  record_verdict "$contest" "$h_login" "$tempo" "$h_prob" "$h_lang" "$verdict" "$sub_epoch" "$id"
  local rjson; rjson="$(jq -cn --arg id "$id" --arg c "$contest" --arg p "$h_prob" --arg l "$h_login" \
    --arg lang "$h_lang" --arg v "$verdict" \
    '{id:$id, contest:$c, problem_id:$p, login:$l, lang:$lang, verdict:$v, host:"manual"}')"
  write_result_json "$contest" "$id" "$h_login" "$h_prob" "$rjson"
  local rf="$cdir/review/$id.json"
  if [[ -f "$rf" ]]; then
    jq -c --arg v "$verdict" --argjson at "$EPOCHSECONDS" '.status="released" | .released_verdict=$v | .released_at=$at' "$rf" > "$rf.tmp" && mv -f "$rf.tmp" "$rf"
  fi
  schedule_score_rebuild "$contest"
  clog "$contest" verdict-released "id=$id verdict=$verdict"
  log "setverdict aplicado id=$id contest=$contest verdict=$verdict"
  return 0
}

# write_result_json ... : grava o results/<id>.json canônico (sem o b64, com ref do HTML).
write_result_json() {
  local contest="$1" id="$2" login="$3" problem="$4" json="$5"
  local out rel resdir
  rel="$(report_html_rel "$contest" "$login" "$problem" "$id")"
  resdir="$(user_dir "$contest" "$login")/results"
  mkdir -p "$resdir" "$RESULTSDIR" 2>/dev/null
  out="$(jq -c --arg login "$login" --arg prob "$problem" --arg rel "$rel" --argjson now "$EPOCHSECONDS" '
    del(.report_html_b64)
    + { login:(.login // $login), problem_id:(.problem_id // $prob),
        report_html:$rel, finalized_at:$now }' \
    <<<"$json" 2>/dev/null)"
  [[ -n "$out" ]] || return 0
  local tmp="$resdir/.$id.tmp"
  printf '%s' "$out" > "$tmp" && mv -f "$tmp" "$resdir/$id.json"
  cp -f "$resdir/$id.json" "$RESULTSDIR/$id.json" 2>/dev/null || true
}

# testrun_finalize <result-json> : resultado de um TEST-RUN de autoria (contest sentinela
# _testrun, enfileirado por /problems/test-run). Funde no registro run/testrun/<id>.json e
# salva o report.html — NUNCA toca history/metrics/placar (não é submissão de ninguém).
testrun_finalize() {
  local json="$1" id reg dir="${TESTRUN_DIR:-$RUNDIR/testrun}"
  id="$(jq -r '.id // empty' <<<"$json")"
  [[ "$id" =~ ^[a-f0-9]{32}$ ]] || { log "testrun: id inválido"; return 1; }
  reg="$dir/$id.json"
  [[ -s "$reg" ]] || { log "testrun: registro ausente id=$id — resultado descartado"; return 1; }
  mkdir -p "$dir/r" 2>/dev/null
  local hb; hb="$(jq -r '.report_html_b64 // empty' <<<"$json")"
  local hasrep=false
  if [[ -n "$hb" ]] && printf '%s' "$hb" | base64 -d > "$dir/r/$id.html" 2>/dev/null \
     && [[ -s "$dir/r/$id.html" ]]; then hasrep=true; else rm -f "$dir/r/$id.html"; fi
  # merge resultado→registro por ARQUIVO (o vetor tests pode ser grande — nunca argv)
  local rf tmp; rf="$(mktemp)"; tmp="$reg.tmp.$$"
  jq -c 'del(.report_html_b64)' <<<"$json" > "$rf" 2>/dev/null
  if ( umask 077; jq -c --slurpfile r "$rf" --argjson now "$EPOCHSECONDS" --argjson rep "$hasrep" \
        '. + ($r[0] // {} | del(.id, .contest, .login))
         + {status:"done", finished_at:$now, report:$rep}' "$reg" > "$tmp" 2>/dev/null ) \
     && [[ -s "$tmp" ]]; then
    mv -f "$tmp" "$reg"
  else rm -f "$tmp"; log "testrun: merge falhou id=$id"; fi
  rm -f "$rf"
  log "testrun concluído id=$id verdict=$(jq -r '.verdict // "?"' <<<"$json")"
}

# ingest_result <result-json> : finaliza um julgamento vindo do worker (modelo pull).
# Único escritor do history. Herda tempo/login/prob/lang/epoch da linha provisória.
ingest_result() {
  local json="$1"
  local id contest host verdict h_login h_prob h_lang tempo sub_epoch line hist
  id="$(jq -r '.id // empty' <<<"$json")"
  contest="$(jq -r '.contest // empty' <<<"$json")"
  # TEST-RUN de autoria: desvia ANTES de qualquer contest/history (sentinela _testrun)
  if [[ "$contest" == "_testrun" ]]; then testrun_finalize "$json"; return $?; fi
  host="$(jq -r '.host // empty' <<<"$json")"
  verdict="$(jq -r '.verdict // "Judge Error"' <<<"$json")"
  # canônico (sem score) p/ casar o auto-veredicto; fallback: tira o sufixo ,Np do verdict.
  local vcanon; vcanon="$(jq -r '.verdict_canon // empty' <<<"$json")"; [[ -n "$vcanon" ]] || vcanon="${verdict%%,*}"
  valid_contest_id "$contest" || { log "result: contest inválido"; return 1; }
  [[ -n "$id" ]] || { log "result: sem id"; return 1; }
  local cdir="$CONTESTSDIR/$contest"
  local j_login; j_login="$(jq -r '.login // ""' <<<"$json")"
  line="$(hist_line_by_id "$contest" "$j_login" "$id")"
  IFS=: read -r tempo h_login h_prob h_lang _ sub_epoch _ <<<"$line"
  [[ -n "$h_login" ]] || h_login="$j_login"
  [[ -n "$h_prob"  ]] || h_prob="$(jq -r '.problem_id // ""' <<<"$json")"
  [[ -n "$h_lang"  ]] || h_lang="$(jq -r '(.lang // "")|ascii_upcase' <<<"$json")"
  [[ -n "$sub_epoch" ]] || sub_epoch="$EPOCHSECONDS"
  [[ -n "$tempo" ]] || tempo="$sub_epoch"
  # MODO VEREDICTO MANUAL: segura o veredicto computado p/ revisão de 2 juízes (não finaliza).
  if should_hold "$contest" "$h_login" "$h_prob" "$h_lang" "$verdict" "$vcanon"; then
    local hb hout; hb="$(jq -r '.report_html_b64 // empty' <<<"$json")"
    hout="$(report_out_path "$contest" "$h_login" "$h_prob" "$id")"; mkdir -p "$(dirname "$hout")" 2>/dev/null
    [[ -n "$hb" ]] && printf '%s' "$hb" | base64 -d > "$hout" 2>/dev/null
    write_review_item "$contest" "$id" "$h_login" "$h_prob" "$h_lang" "$sub_epoch" "$verdict"
    [[ -n "$host" ]] && q_done "$host" "$id"
    log "veredicto SEGURADO p/ revisão id=$id contest=$contest verdict=$verdict"
    return 0
  fi
  record_verdict "$contest" "$h_login" "$tempo" "$h_prob" "$h_lang" "$verdict" "$sub_epoch" "$id"
  local html_b64 hout; html_b64="$(jq -r '.report_html_b64 // empty' <<<"$json")"
  hout="$(report_out_path "$contest" "$h_login" "$h_prob" "$id")"; mkdir -p "$(dirname "$hout")" 2>/dev/null
  [[ -n "$html_b64" ]] && printf '%s' "$html_b64" | base64 -d > "$hout" 2>/dev/null
  write_result_json "$contest" "$id" "$h_login" "$h_prob" "$json"
  [[ -n "$host" ]] && q_done "$host" "$id"
  schedule_score_rebuild "$contest"
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
    local rc rid rlogin; rc="$(cut -d: -f1 <<<"$base")"; rid="$(cut -d: -f3 <<<"$base")"; rlogin="$(cut -d: -f4 <<<"$base")"
    if ! valid_contest_id "$rc"; then log "rejulgar: contest inválido em $base"; mv -f "$f" "$SPOOLDONEDIR/$base" 2>/dev/null; return 1; fi
    local rline; rline="$(hist_line_by_id "$rc" "$rlogin" "$rid")"
    if [[ -z "$rline" ]]; then log "rejulgar: $rid não está no history de $rc"; clog "$rc" rejulgar-falhou "id=$rid motivo=sem-history"; mv -f "$f" "$SPOOLDONEDIR/$base" 2>/dev/null; return 1; fi
    local r_tempo r_login r_prob r_lang r_sub
    IFS=: read -r r_tempo r_login r_prob r_lang _ r_sub _ <<<"$rline"
    local r_llang r_src r_b64=""
    r_llang="$(printf '%s' "$r_lang" | tr '[:upper:]' '[:lower:]')"
    r_src="$(user_dir "$rc" "$r_login")/submissions/$rid.${r_llang:-txt}"
    [[ -f "$r_src" ]] && r_b64="$(base64 -w0 < "$r_src" 2>/dev/null)"
    if [[ -z "$r_b64" ]]; then log "rejulgar: fonte ausente p/ $rid ($r_src)"; clog "$rc" rejulgar-falhou "id=$rid motivo=sem-fonte src=$r_src"; mv -f "$f" "$SPOOLDONEDIR/$base" 2>/dev/null; return 1; fi
    # provisório "Not Answered Yet" -> aparece como PENDENTE na Situação enquanto re-julga
    record_provisional "$rc" "$r_login" "$r_tempo" "$r_prob" "$r_lang" "$r_sub" "$rid"
    local _rbf; _rbf="$(mktemp)"; printf '%s' "$r_b64" > "$_rbf"   # nunca por argv (ARG_MAX)
    json="$(jq -cn --arg c "$rc" --arg l "$r_login" --arg p "$r_prob" --arg lang "$r_lang" \
      --rawfile b "$_rbf" --arg fn "solution.${r_llang:-txt}" --argjson t "${r_sub:-$EPOCHSECONDS}" --arg id "$rid" \
      '{contest:$c, login:$l, problem_id:$p, filename:$fn, code_b64:$b, lang:$lang, time:$t, id:$id}')"
    rm -f "$_rbf"
    comando=submit   # daqui em diante: trata como submit (enfileira/julga + troca a linha :id)
  else
    # JSON do conteúdo (submit/result normais)
    json="$(cat "$f" 2>/dev/null)"
    if ! jq -e . >/dev/null 2>&1 <<<"$json"; then
      log "JSON inválido/vazio em $base — descartado (cmd=$comando)"
      clog "$(cut -d: -f1 <<<"$base")" spool-descartado "base=$base cmd=$comando motivo=json-invalido-ou-vazio"
      # SUBMIT nunca morre mudo: o aluno está vendo "Not Answered Yet" — os metadados estão no
      # NOME do arquivo, então a linha vira Judge Error (não penaliza; ele reenvia). Foi o
      # descarte silencioso que deixou 6 submissões pendentes p/ sempre em 2026-08-19.
      if [[ "$comando" == submit ]]; then
        local d_c d_ep d_id d_login d_prob d_ft
        IFS=: read -r d_c d_ep d_id d_login _ d_prob d_ft <<<"$base"
        if valid_contest_id "$d_c" && [[ -n "$d_id" && -n "$d_login" ]]; then
          record_verdict "$d_c" "$d_login" "${d_ep:-$EPOCHSECONDS}" "$d_prob" "$d_ft" "Judge Error" "${d_ep:-$EPOCHSECONDS}" "$d_id"
          touch "$CONTESTSDIR/$d_c/var/.score-dirty" 2>/dev/null   # invalida o cache de pendentes
          schedule_score_rebuild "$d_c"
          clog "$d_c" spool-judge-error "id=$d_id login=$d_login prob=$d_prob (spool corrompido -> Judge Error)"
        fi
      fi
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

  # ---- comando "setverdict": aplica o veredicto manual decidido (2 juízes / juiz-chefe) ----
  if [[ "$comando" == setverdict ]]; then
    consume_setverdict "$json"
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
  mkdir -p "$(user_dir "$contest" "$login")/submissions" "$(user_dir "$contest" "$login")/mojlog" "$(user_dir "$contest" "$login")/results" 2>/dev/null

  log "julgando $base (contest=$contest login=$login prob=$problem lang=$lang id=$id cmd=${comando:-submit})"

  # ---- carrega do conf: CONTEST_START (tempo), CONTEST_PRIORITY/CONTEST_JUDGES (fila pull).
  # (source seguro: já validamos contest; o conf é confiável no deploy.) As vars CONTEST_END/
  # CONTEST_TYPE/MOJCONTESTSERVERS ficam declaradas local só p/ o source não vazá-las global.
  local CONTEST_START="" CONTEST_END="" CONTEST_TYPE="" MOJCONTESTSERVERS="" CONTEST_PRIORITY="" CONTEST_JUDGES=""
  if [[ -r "$cdir/conf" ]]; then
    # shellcheck source=/dev/null
    source "$cdir/conf" 2>/dev/null || true
  fi

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
  export JUDGE_REPORT_OUT="$(report_out_path "$contest" "$login" "$problem" "$id")"
  mkdir -p "$(dirname "$JUDGE_REPORT_OUT")" 2>/dev/null
  local verdict
  verdict="$(judge_run "$contest" "$problem" "$lang" "$code_b64" "${filename:-solution}")"
  [[ -z "$verdict" ]] && verdict="Judge Error (empty verdict)"
  log "veredicto p/ id=$id: $verdict"
  # erros de juiz (pacote ausente, sandbox, sem servidor...) vão p/ o log DO CONTEST,
  # p/ o admin identificar o problema na aba Auditoria.
  case "$verdict" in
    "Judge Error"*|"No_Servers"*) clog "$contest" judge-error "id=$id login=$login prob=$problem lang=$lang verdict=$verdict" ;;
  esac

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

  # MODO VEREDICTO MANUAL (caminho inline/legacy): segura p/ revisão de 2 juízes.
  # Sem JSON de resultado aqui: o canônico sai do próprio veredicto (corta o sufixo ,Np).
  if should_hold "$contest" "$login" "$problem" "$lang" "$verdict" "${verdict%%,*}"; then
    archive_source "$contest" "$id" "$login" "$problem" "$lang" "$code_b64"   # fonte p/ os juízes verem
    write_review_item "$contest" "$id" "$login" "$problem" "$lang" "$sub_epoch" "$verdict"
    mv -f "$f" "$SPOOLDONEDIR/$base" 2>/dev/null
    log "veredicto SEGURADO p/ revisão (inline) id=$id contest=$contest verdict=$verdict"
    return 0
  fi

  # ---- (3) finaliza no history (troca a provisória :<id> pela definitiva) ----
  # users/<login>/history (login implícito) + metrics.json.
  record_verdict "$contest" "$login" "$tempo" "$problem" "$lang" "$verdict" "$sub_epoch" "$id"

  # ---- (4b) results/<id>.json do sidecar estruturado (dev = prod: alimenta o resumo) --------
  local metaf="$cdir/mojlog/$id-$login-$problem.meta.json"
  if [[ -f "$metaf" ]]; then
    local rjson
    rjson="$(jq -c --arg id "$id" --arg c "$contest" --arg p "$problem" --arg l "$login" \
      --arg lang "$lang" --arg v "$verdict" \
      '. + {id:$id, contest:$c, problem_id:$p, login:$l, lang:$lang, verdict:$v, host:"inline"}' \
      "$metaf" 2>/dev/null)"
    [[ -n "$rjson" ]] && write_result_json "$contest" "$id" "$login" "$problem" "$rjson"
    rm -f "$metaf"
  fi

  # ---- (5) arquiva a fonte decodificada (ramo store-v2 x legado em archive_source) ----
  archive_source "$contest" "$id" "$login" "$problem" "$lang" "$code_b64"

  # ---- (6) recalcula placar (COALESCIDO — ver schedule_score_rebuild) -------
  schedule_score_rebuild "$contest"

  # ---- (7) arquiva o arquivo de spool --------------------------------------
  mv -f "$f" "$SPOOLDONEDIR/$base" 2>/dev/null
  log "concluído $base -> $SPOOLDONEDIR/"
  return 0
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

# ===== RECONCILIADOR de pendência velha ====================================================
# Nada no pipeline pode ficar "Not Answered Yet" para sempre: se um job se perdeu (spool
# corrompido de antes do fail-closed, juiz que morreu com o job, bug futuro), ALGUÉM tem de
# notar. A cada RECONCILE_EVERY_S (600), para cada contest com pendência (count_pending>0,
# que é cacheado e barato), toda linha pendente mais velha que PENDING_TTL_MIN (15) e sem
# rastro vivo em spool/ | queue/ | assigned/ é resolvida:
#   - fonte arquivada existe  -> re-enfileira UMA vez (marcador rejulgar; a 2ª expiração do
#                                MESMO id não insiste — vira Judge Error);
#   - sem fonte               -> Judge Error direto (o aluno reenvia).
# Tudo vai p/ o clog do contest — o log conta a história (incidente 2026-08-19: 6 presas mudas).
: "${PENDING_TTL_MIN:=15}"
: "${RECONCILE_EVERY_S:=600}"
_RECONCILE_LAST=0
_recon_tried_dir="$RUNDIR/.reconciled"   # ids já re-enfileirados (1 tentativa por id)

# --- GC do spool JÁ PROCESSADO ---------------------------------------------------------------
# O `submissions-done/` guarda o job depois de processado — com a FONTE dentro e, nos `result`,
# o relatório inteiro em base64. Nunca era limpo: em 24/08/2026 eram **7,4 GB** em 6.789
# arquivos, o mais antigo de 12 de ABRIL (37 passavam de 50 MB; o maior tinha 200 MB).
# É evidência de incidente — foi lendo isto que se explicou a fila travada de julho —, então a
# retenção é generosa e a varredura é preguiçosa, no molde do `run/testrun/`.
# `SPOOL_DONE_KEEP_DAYS=0` desliga. Apaga só o que JÁ SAIU do pipeline: nunca toca em $SPOOLDIR.
: "${SPOOL_DONE_KEEP_DAYS:=30}"
: "${SPOOL_GC_EVERY_S:=3600}"
_SPOOL_GC_LAST=0

spool_done_gc() {
  local now="$EPOCHSECONDS" n
  (( SPOOL_DONE_KEEP_DAYS > 0 )) || return 0
  (( now - _SPOOL_GC_LAST >= SPOOL_GC_EVERY_S )) || return 0
  _SPOOL_GC_LAST="$now"
  [[ -d "$SPOOLDONEDIR" ]] || return 0
  # um `find` só: imprime um ponto por arquivo removido e o `wc -c` os conta (contar por linhas
  # seria frágil — nome de spool não tem \n, mas o ponto não depende disso).
  n="$(find "$SPOOLDONEDIR" -maxdepth 1 -type f -mtime "+$SPOOL_DONE_KEEP_DAYS" \
        -printf . -delete 2>/dev/null | wc -c)"
  n="${n//[^0-9]/}"
  (( ${n:-0} > 0 )) && log "spool-gc: removidos $n arquivo(s) de submissions-done/ com mais de ${SPOOL_DONE_KEEP_DAYS}d"
  return 0
}

reconcile_stale_pending() {
  local now="$EPOCHSECONDS"
  (( now - _RECONCILE_LAST >= RECONCILE_EVERY_S )) || return 0
  _RECONCILE_LAST="$now"
  mkdir -p "$_recon_tried_dir" 2>/dev/null
  local cdir c n
  for cdir in "$CONTESTSDIR"/*/; do
    c="${cdir%/}"; c="${c##*/}"
    valid_contest_id "$c" || continue
    # contest de DEMONSTRAÇÃO: o `/contest/admin/seed` cria pendente DE PROPÓSITO (`verdicts.
    # pending`) — é a célula "?" que quem desenvolve telão precisa para testar o freeze. Sem esta
    # linha o reconciliador os varria 15 min depois (49 viraram Judge Error no zz-seed-teste em
    # 24/08) e o cliente ficava testando contra um placar que muda sozinho. Não há o que
    # reconciliar aqui: submissão sintética nunca teve job no pipeline.
    contest_is_demo "$c" && continue
    n="$(count_pending "$c" 2>/dev/null)"; n="${n//[^0-9]/}"
    [[ -n "$n" && "$n" -gt 0 ]] || continue
    local hf login line tempo prob lang se id age
    for hf in "$cdir"users/*/history; do
      [[ -f "$hf" ]] || continue
      grep -qE ':(Not Answered Yet|On queue|on queue|Running|running):' "$hf" 2>/dev/null || continue
      login="${hf%/history}"; login="${login##*/}"
      while IFS= read -r line; do
        # campos SEGUROS da linha (verdict pode conter ':'): 1=tempo 2=prob 3=lang NF-1=se NF=id
        IFS=$'\x01' read -r tempo prob lang se id \
          <<<"$(awk -F: '{printf "%s\x01%s\x01%s\x01%s\x01%s", $1, $2, $3, $(NF-1), $NF}' <<<"$line")"
        [[ -n "$id" && "$se" =~ ^[0-9]+$ ]] || continue
        age=$(( now - se ))
        (( age > PENDING_TTL_MIN * 60 )) || continue
        # rastro vivo? (spool de entrada, fila do cluster ou assigned de algum juiz)
        if compgen -G "$SPOOLDIR/*:$id:*" >/dev/null 2>&1 \
           || compgen -G "$QUEUEDIR/*/*_$id.json" >/dev/null 2>&1 \
           || compgen -G "$ASSIGNEDDIR/*/*_$id.json" >/dev/null 2>&1; then
          continue
        fi
        local llang src; llang="$(printf '%s' "$lang" | tr '[:upper:]' '[:lower:]')"
        src="$(user_dir "$c" "$login")/submissions/$id.${llang:-txt}"
        if [[ -s "$src" && ! -e "$_recon_tried_dir/$id" ]]; then
          : > "$_recon_tried_dir/$id"
          : > "$SPOOLDIR/$c:$se:$id:$login:rejulgar:$prob:$lang"
          log "reconciler: pendente ${age}s sem rastro — re-enfileirado id=$id ($c/$login)"
          clog "$c" pendente-reenfileirado "id=$id login=$login prob=$prob idade=${age}s"
        else
          record_verdict "$c" "$login" "$tempo" "$prob" "$lang" "Judge Error" "$se" "$id"
          touch "$CONTESTSDIR/$c/var/.score-dirty" 2>/dev/null   # invalida o cache de pendentes
          schedule_score_rebuild "$c"
          log "reconciler: pendente ${age}s irrecuperável — Judge Error id=$id ($c/$login)"
          clog "$c" pendente-judge-error "id=$id login=$login prob=$prob idade=${age}s fonte=$([[ -s $src ]] && echo re-tentada || echo ausente)"
        fi
      done < <(grep -E ':(Not Answered Yet|On queue|on queue|Running|running):' "$hf" 2>/dev/null)
    done
  done
}

# loop principal: inotify (push) com fallback p/ polling.
# IMPORTANTE: o padrão é DRENA-então-ESPERA-UM-evento (inotifywait sem -m, com -t de
# re-drain). Todo giro drena TODO o spool no topo; então o inotifywait espera UM evento
# ou o timeout de re-drain e sai — e o loop re-drena. Assim um evento perdido (ex.: escritor
# num OUTRO container/namespace, ou race entre sair e re-armar) NÃO trava o julgamento: no
# pior caso o re-drain o pega em WATCH_REDRAIN_SECS. (O `-m` contínuo antigo bloqueava p/
# sempre se um evento não chegasse — sem rede de segurança.)
# heartbeat: a API precisa saber que o daemon está vivo, mas o `pgrep` dela NÃO enxerga este
# processo quando ela roda em OUTRO container (PID namespace separado — que é justamente o
# deploy recomendado: moj-api + moj-judged). Batemos num arquivo do $RUNDIR (volume
# compartilhado) a cada giro do laço; quem lê é o daemon_judged_alive() do lib/common.sh.
: "${JUDGED_ALIVE_FILE:=$RUNDIR/judged.alive}"
beat(){ : > "$JUDGED_ALIVE_FILE" 2>/dev/null || true; }

watch_loop() {
  local f rc
  beat
  if command -v inotifywait >/dev/null 2>&1; then
    log "watch: inotifywait em $SPOOLDIR (re-arma por evento; re-drena a cada ${WATCH_REDRAIN_SECS:-30}s)"
    while true; do
      beat
      while f="$(next_spool_file)"; do process_spool_file "$f" || break; done
      reconcile_stale_pending
      spool_done_gc
      inotifywait -q -e create -e moved_to -t "${WATCH_REDRAIN_SECS:-30}" "$SPOOLDIR" >/dev/null 2>&1
      rc=$?
      # rc 0=evento, 2=timeout (re-drena no topo). Erro real (1/outros): evita busy-loop.
      (( rc == 0 || rc == 2 )) || sleep 1
    done
  else
    log "watch: inotifywait AUSENTE — fallback p/ polling (1s)"
    while true; do
      beat
      while f="$(next_spool_file)"; do process_spool_file "$f" || break; done
      reconcile_stale_pending
      spool_done_gc
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
    --reconcile)
      # roda o reconciliador de pendência velha UMA vez e sai (operação/testes)
      _RECONCILE_LAST=-999999
      reconcile_stale_pending
      exit 0
      ;;
    --gc)
      # limpa o spool processado UMA vez e sai (operação/testes). `--gc-dry` só LISTA.
      _SPOOL_GC_LAST=-999999
      spool_done_gc
      exit 0
      ;;
    --gc-dry)
      # o que o --gc apagaria, sem apagar (é o que se olha antes da primeira limpeza)
      find "$SPOOLDONEDIR" -maxdepth 1 -type f -mtime "+${SPOOL_DONE_KEEP_DAYS:-30}" \
        -printf '%TY-%Tm-%Td  %10s  %f\n' 2>/dev/null | sort | tail -20
      printf 'total: %s arquivo(s), %s\n' \
        "$(find "$SPOOLDONEDIR" -maxdepth 1 -type f -mtime "+${SPOOL_DONE_KEEP_DAYS:-30}" 2>/dev/null | wc -l)" \
        "$(find "$SPOOLDONEDIR" -maxdepth 1 -type f -mtime "+${SPOOL_DONE_KEEP_DAYS:-30}" -printf '%s\n' 2>/dev/null | awk '{s+=$1} END{printf "%.1f GB", s/1073741824}')"
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
      echo "argumento desconhecido: $1 (use --once|--drain|--reconcile|--watch)" >&2
      exit 2
      ;;
  esac
}

main "$@"
