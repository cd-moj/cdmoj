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
  local job
  job="$(jq -cn --arg id "$id" --arg c "$contest" --arg p "$problem" --arg login "$login" \
    --arg lang "$lang" --arg f "${filename:-solution}" --arg b "$code_b64" \
    --arg prio "$prio" --argjson now "$EPOCHSECONDS" \
    '{id:$id, contest:$c, problem_id:$p, login:$login, lang:$lang, filename:$f,
      code_b64:$b, priority:$prio, enqueued_at:$now}')"
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
  case "$login" in *.admin|*.judge|*.cjudge|*.staff|*.cstaff|*.mon) return 1;; esac
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
  [[ -e "$SCORE_BUILD" ]] && bash "$SCORE_BUILD" "$contest" >/dev/null 2>&1
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

# ingest_result <result-json> : finaliza um julgamento vindo do worker (modelo pull).
# Único escritor do history. Herda tempo/login/prob/lang/epoch da linha provisória.
ingest_result() {
  local json="$1"
  local id contest host verdict h_login h_prob h_lang tempo sub_epoch line hist
  id="$(jq -r '.id // empty' <<<"$json")"
  contest="$(jq -r '.contest // empty' <<<"$json")"
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
    json="$(jq -cn --arg c "$rc" --arg l "$r_login" --arg p "$r_prob" --arg lang "$r_lang" \
      --arg b "$r_b64" --arg fn "solution.${r_llang:-txt}" --argjson t "${r_sub:-$EPOCHSECONDS}" --arg id "$rid" \
      '{contest:$c, login:$l, problem_id:$p, filename:$fn, code_b64:$b, lang:$lang, time:$t, id:$id}')"
    comando=submit   # daqui em diante: trata como submit (enfileira/julga + troca a linha :id)
  else
    # JSON do conteúdo (submit/result normais)
    json="$(cat "$f" 2>/dev/null)"
    if ! jq -e . >/dev/null 2>&1 <<<"$json"; then
      log "JSON inválido/vazio em $base — descartado (cmd=$comando)"
      clog "$(cut -d: -f1 <<<"$base")" spool-descartado "base=$base cmd=$comando motivo=json-invalido-ou-vazio"
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
