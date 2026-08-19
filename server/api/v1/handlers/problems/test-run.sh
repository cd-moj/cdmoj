# /problems/test-run — rodar UMA solução avulsa NO JUIZ, para AUTORIA (quem pode editar).
#   POST {id, filename, code_b64} -> {run:<32hex>, status:"queued"}
#     O job entra na fila real (banda lista-privada) com o contest SENTINELA "_testrun":
#     o juiz o julga como submissão normal (mesma jaula, mesmo TL calibrado) e o judged
#     DESVIA o resultado p/ run/testrun/ — nunca toca history/metrics/placar de ninguém.
#   GET ?run=<id> -> registro {run, problem_id, filename, lang, status:queued|done,
#     requested_at, verdict?, verdict_canon?, tests?:[{name,code,time,tl}], report:bool, …}
# Gate: require_problem_edit (404 opaco) — rodar código contra os testes OCULTOS revela o
# problema; é o mesmo domínio de confiança do log de calibração. Auditado (test-run).
require_auth
source "$_DIR/lib/problems.sh"; source "$_DIR/lib/tl-store.sh"
source "$_DIR/../../judge-gw/sched-lib.sh"
: "${RUNDIR:=/home/ribas/moj/run}"
: "${TESTRUN_DIR:=$RUNDIR/testrun}"
: "${TESTRUN_TTL_DAYS:=7}"        # registros/reports somem depois disso (GC preguiçoso)
: "${TESTRUN_MAX_INFLIGHT:=3}"    # runs "queued" simultâneos por login

# GC preguiçoso (no máx 1×/h): apaga registros e reports com mais de TESTRUN_TTL_DAYS
_testrun_gc(){
  local stamp="$TESTRUN_DIR/.gc-stamp" now="$EPOCHSECONDS" last=0
  [[ -f "$stamp" ]] && last="$(stat -c %Y "$stamp" 2>/dev/null)"; last="${last//[^0-9]/}"; last="${last:-0}"
  (( now - last < 3600 )) && return 0
  touch "$stamp" 2>/dev/null
  find "$TESTRUN_DIR" -maxdepth 2 \( -name '*.json' -o -name '*.html' \) \
       -type f -mtime +"$TESTRUN_TTL_DAYS" -delete 2>/dev/null
}

if [[ "${REQUEST_METHOD:-GET}" == POST ]]; then
  bf="$(read_body_file)"; trap 'rm -f "$bf"' EXIT
  jq -e . >/dev/null 2>&1 < "$bf" || fail 400 "Invalid JSON body" "bad_json"
  id="$(jq -r '.id // empty' "$bf")"
  [[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
  valid_id "$id" || fail 400 "Invalid id" "id_invalid"
  require_problem_edit "$id"
  pkg="$(pkg_path "$id")"; [[ -n "$pkg" ]] || fail 404 "Problema não encontrado" "not_found"

  filename="$(jq -r '.filename // empty' "$bf")"; [[ -n "$filename" ]] || filename="solution"
  filename="$(basename "$filename")"

  # a FONTE nunca anda por argv de jq (classe ARG_MAX): corpo -> arquivo -> --rawfile
  B64F="$(mktemp)"; trap 'rm -f "$bf" "$B64F"' EXIT
  jq -r '.code_b64 // empty' "$bf" | tr -d '\r\n' > "$B64F"
  b64sz="$(stat -c%s "$B64F" 2>/dev/null || echo 0)"
  [[ "$b64sz" -gt 0 ]] || fail 400 "Missing code_b64" "code_missing"
  : "${SUBMIT_MAX_KB:=1024}"
  if (( b64sz > SUBMIT_MAX_KB * 1024 * 4 / 3 + 4096 )); then
    fail 413 "Fonte muito grande (máx ${SUBMIT_MAX_KB} KB)" "source_too_large"
  fi

  # linguagem: extensão canonicalizada; aceitas = PLATAFORMA ∪ declaradas do PACOTE
  # (autoria: o dono testa qualquer linguagem que a plataforma rode + as exóticas do pacote,
  # independente da whitelist de submissão do problema)
  source "$_DIR/lib/langs.sh"
  ext="${filename##*.}"
  if [[ "$ext" == "$filename" || -z "$ext" ]]; then FILETYPE="TXT"
  else FILETYPE="$(printf '%s' "$ext" | tr '[:lower:]' '[:upper:]')"; fi
  pkg_langs="$(jq -c '.languages // []' "$pkg/.moj-meta.json" 2>/dev/null)"
  [[ -n "$pkg_langs" ]] || pkg_langs='[]'
  allowed="$(jq -cn --argjson a "$(platform_langs_json)" --argjson b "$pkg_langs" '($a + $b) | unique')"
  if ! lang_allowed "$allowed" "$FILETYPE"; then
    fail 400 "Linguagem .${ext,,} não roda na plataforma (aceitas: $(jq -r 'join(", ")' <<<"$allowed"))" "lang_not_allowed"
  fi

  mkdir -p "$TESTRUN_DIR" 2>/dev/null; _testrun_gc
  # rate: no máx TESTRUN_MAX_INFLIGHT runs ainda na fila por login (varredura única)
  inflight="$(find "$TESTRUN_DIR" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null \
    | xargs -0 -r jq -r --arg l "$SESSION_LOGIN" \
        'select(.login==$l and .status=="queued") | .run' 2>/dev/null | wc -l)"
  inflight="${inflight//[^0-9]/}"; inflight="${inflight:-0}"
  if (( inflight >= TESTRUN_MAX_INFLIGHT )); then
    fail 429 "Você já tem $inflight teste(s) na fila — aguarde terminarem" "testrun_busy"
  fi

  AGORA="$EPOCHSECONDS"
  RUNID="$(printf 'testrun%s%s%s%s' "$AGORA" "$SESSION_LOGIN" "$id" "$RANDOM" | md5sum | cut -d' ' -f1)"

  # registro primeiro (o resultado pode chegar rápido), depois o job na fila
  reg="$TESTRUN_DIR/$RUNID.json"
  ( umask 077; jq -cn --arg r "$RUNID" --arg p "$id" --arg l "$SESSION_LOGIN" \
      --arg f "$filename" --arg lg "$FILETYPE" --argjson now "$AGORA" \
      '{run:$r, problem_id:$p, login:$l, filename:$f, lang:$lg,
        status:"queued", requested_at:$now}' > "$reg" ) 2>/dev/null
  [[ -s "$reg" ]] || fail 500 "Falha ao registrar o teste" "testrun_store_fail"

  job="$(jq -cn --arg id "$RUNID" --arg p "$id" --arg login "$SESSION_LOGIN" \
    --arg lang "$FILETYPE" --arg f "$filename" --rawfile b "$B64F" \
    --arg prio lista-privada --argjson now "$AGORA" \
    '{id:$id, contest:"_testrun", problem_id:$p, login:$login, lang:$lang, filename:$f,
      code_b64:($b | rtrimstr("\n")), priority:$prio, enqueued_at:$now}')"
  if [[ -z "$job" ]] || ! jq -e '.code_b64 | length > 0' >/dev/null 2>&1 <<<"$job"; then
    rm -f "$reg"
    fail 500 "Falha ao montar o job — tente de novo" "testrun_job_fail"
  fi
  q_enqueue "$RUNID" lista-privada "$job"
  audit_log "test-run" "run=$RUNID id=$id login=$SESSION_LOGIN file=$filename lang=$FILETYPE bytes=$b64sz"
  ok_json '{run:$r, status:"queued"}' --arg r "$RUNID"
  exit 0
fi

# ---------- GET ?run= : estado/resultado de um test-run ----------
require_method GET
run="$(param run)"
[[ "$run" =~ ^[a-f0-9]{32}$ ]] || fail 400 "run inválido" "run_invalid"
reg="$TESTRUN_DIR/$run.json"
[[ -s "$reg" ]] || fail 404 "Test-run não encontrado (expirado?)" "not_found"
pid="$(jq -r '.problem_id // empty' "$reg")"
valid_id "$pid" || fail 404 "Test-run não encontrado" "not_found"
require_problem_edit "$pid"   # gate pelo problema DO REGISTRO (membros da org veem)

# CORPO ANTES DO CABEÇALHO; o registro pode carregar o vetor tests (arquivo, não argv)
BODYF="$(mktemp)"; trap 'rm -f "$BODYF"' EXIT
jq -c '{success:true} + .' "$reg" > "$BODYF" 2>/dev/null
[[ -s "$BODYF" ]] || fail 500 "Falha ao ler o registro" "testrun_read_fail"
emit_json 200 OK
cat "$BODYF"
