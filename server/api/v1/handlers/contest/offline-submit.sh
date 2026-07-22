# POST /contest/offline-submit?contest=<id>   (Bearer)   body: {packets:["<pkt-json>",…]}
# Rota EMERGENCIAL do moj-comp: recebe pacotes cifrados criados SEM rede e contabiliza cada
# submissão NO horário reivindicado (claimed) — a penalidade sai certa porque o placar usa o
# sub_epoch. Política (decisão do Ribas): pacote VÁLIDO auto-contabiliza, MARCADO p/ o
# organizador (var/offline-log + audit) adjudicar exceções.
#
# Validações por pacote (qualquer falha rejeita SÓ aquele pacote, com motivo):
#   decripta com a chave do contest (adulterado/estranho não abre) · v==1 · login do pacote
#   == sessão · contest confere · beacon assinado pelo contest, do MESMO login/contest ·
#   beacon.t ≤ claimed ≤ now+OFFLINE_SKEW_MAX (piso: nasceu depois do beacon; teto: chegada)
#   · claimed dentro da janela DO ALUNO (start ≤ claimed ≤ fim efetivo, extend/--group conta)
#   · claimed ≥ último claimed aceito (monotonicidade HARD) · dedup por sha256 do pacote.
#   prev_sha256 fora da cadeia NÃO rejeita (SOFT): vira nota no audit — rejeição em cascata
#   puniria aluno honesto depois de 1 pacote rejeitado.
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
[[ "$contest" != treino ]] || fail 400 "Offline-submit é de contest" "not_a_contest"
source "$_LIBDIR/contest-gate.sh"
source "$_LIBDIR/contest-offline.sh"
source "$_LIBDIR/langs.sh"
{ is_staff || is_cstaff; } && fail 403 "Usuário staff não submete soluções" "submit_forbidden"

body="$(read_body)"
jq -e '.packets | type == "array" and length > 0' >/dev/null 2>&1 <<<"$body" \
  || fail 400 "Body deve ter packets:[…]" "packets_missing"
NP="$(jq -r '.packets | length' <<<"$body")"
(( NP <= 50 )) || fail 400 "Máximo de 50 pacotes por chamada" "too_many_packets"

CDIR="$CONTESTSDIR/$contest"
UDIR="$(user_dir "$contest" "$SESSION_LOGIN")"; mkdir -p "$UDIR" 2>/dev/null
CHAINF="$UDIR/.offline-chain"        # NDJSON {sha,claimed,id,at} por pacote ACEITO (flock)
NOW="$EPOCHSECONDS"

# janela DO ALUNO (extend/--group respeitado); start do conf
CSTART="$(grep -m1 '^CONTEST_START=' "$CDIR/conf" 2>/dev/null | cut -d= -f2 | tr -dc 0-9)"
CEND="$(contest_end_effective "$contest" "$SESSION_LOGIN")"
[[ "$CSTART" =~ ^[0-9]+$ ]] || CSTART=0
[[ "$CEND"   =~ ^[0-9]+$ ]] || CEND=0

RESULTS='[]'
i=0
while (( i < NP )); do
  pkt="$(jq -r --argjson i "$i" '.packets[$i]' <<<"$body")"; i=$((i+1))
  sha="$(printf '%s' "$pkt" | sha256sum | cut -d' ' -f1)"
  reject(){ RESULTS="$(jq -c --arg s "$sha" --arg r "$1" '. + [{sha:$s, status:"rejected", reason:$r}]' <<<"$RESULTS")"; }

  inner="$(offline_packet_decrypt "$contest" "$pkt")" || { reject "não decripta (pacote adulterado ou de outro contest)"; continue; }
  jq -e . >/dev/null 2>&1 <<<"$inner" || { reject "conteúdo não é JSON"; continue; }
  pv="$(jq -r '.v // 0' <<<"$inner")"
  pl="$(jq -r '.l // empty' <<<"$inner")"
  pc="$(jq -r '.c // empty' <<<"$inner")"
  problem="$(jq -r '.problem_id // empty' <<<"$inner")"
  filename="$(jq -r '.filename // "solution"' <<<"$inner")"
  codeb64="$(jq -r '.code_b64 // empty' <<<"$inner")"
  claimed="$(jq -r '.claimed_utc // 0' <<<"$inner")"
  beacon="$(jq -r '.beacon // empty' <<<"$inner")"
  prevsha="$(jq -r '.prev_sha256 // empty' <<<"$inner")"
  [[ "$pv" == 1 ]] || { reject "versão de pacote desconhecida"; continue; }
  [[ "$pl" == "$SESSION_LOGIN" ]] || { reject "pacote de outro login"; continue; }
  [[ "$pc" == "$contest" ]] || { reject "pacote de outro contest"; continue; }
  [[ -n "$problem" && -n "$codeb64" ]] || { reject "faltou problem_id/code_b64"; continue; }
  valid_id "$problem" || { reject "problem_id inválido"; continue; }
  [[ "$claimed" =~ ^[0-9]+$ ]] || { reject "claimed_utc inválido"; continue; }
  # WHITELIST de linguagens do problema — mesma regra do /submit online (lib/langs.sh):
  # pacote offline com extensão fora da lista é rejeitado NA CHEGADA (motivo visível).
  wlx="${filename##*.}"; [[ "$wlx" == "$filename" || -z "$wlx" ]] && wlx=TXT
  lang_allowed "$(effective_problem_langs "$contest" "$problem")" "$wlx" \
    || { reject "linguagem .$(printf '%s' "$wlx" | tr '[:upper:]' '[:lower:]') não aceita neste problema"; continue; }

  bp="$(offline_beacon_verify "$contest" "$beacon")" || { reject "beacon inválido (assinatura)"; continue; }
  bl="$(jq -r '.l' <<<"$bp")"; bc="$(jq -r '.c' <<<"$bp")"; bt="$(jq -r '.t' <<<"$bp")"
  [[ "$bl" == "$SESSION_LOGIN" && "$bc" == "$contest" ]] || { reject "beacon de outro login/contest"; continue; }
  (( claimed >= bt )) || { reject "claimed anterior ao beacon (carimbo impossível)"; continue; }
  (( claimed <= NOW + OFFLINE_SKEW_MAX )) || { reject "claimed no futuro"; continue; }
  (( CSTART == 0 || claimed >= CSTART )) || { reject "claimed antes do início da prova"; continue; }
  (( CEND == 0 || claimed <= CEND )) || { reject "claimed depois do fim da sua prova"; continue; }

  # cadeia por usuário (flock): dedup HARD por sha; monotonicidade HARD do claimed;
  # prev_sha divergente é SOFT (nota no audit)
  exec 8>>"$CHAINF"; flock -x 8
  if grep -q "\"sha\":\"$sha\"" "$CHAINF" 2>/dev/null; then
    exec 8>&-; RESULTS="$(jq -c --arg s "$sha" '. + [{sha:$s, status:"duplicate"}]' <<<"$RESULTS")"; continue
  fi
  last="$(tail -n1 "$CHAINF" 2>/dev/null)"
  lastsha="$(jq -r '.sha // empty' <<<"$last" 2>/dev/null)"
  lastclaimed="$(jq -r '.claimed // 0' <<<"$last" 2>/dev/null)"
  [[ "$lastclaimed" =~ ^[0-9]+$ ]] || lastclaimed=0
  if (( claimed < lastclaimed )); then
    exec 8>&-; reject "claimed retrocede o último pacote aceito"; continue
  fi
  chainnote=""
  [[ -n "$lastsha" && "$prevsha" != "$lastsha" ]] && chainnote=" chain_mismatch"

  # extensão -> tipo (como no submit.sh)
  ext="${filename##*.}"
  if [[ "$ext" == "$filename" || -z "$ext" ]]; then FILETYPE="TXT"
  else FILETYPE="$(printf '%s' "$ext" | tr '[:lower:]' '[:upper:]')"; fi

  ID="$(printf '%s%s%s%s%s' "$contest" "$claimed" "$SESSION_LOGIN" "$problem" "$RANDOM" | md5sum | cut -d' ' -f1)"
  mkdir -p "$SPOOLDIR"
  spoolname="$contest:$claimed:$ID:$SESSION_LOGIN:submit:$problem:$FILETYPE"
  tmp="$SPOOLDIR/.in.$ID"
  jq -cn --arg c "$contest" --arg l "$SESSION_LOGIN" --arg p "$problem" \
     --arg f "$filename" --arg b "$codeb64" --arg t "$FILETYPE" \
     --argjson ts "$claimed" --arg id "$ID" \
     '{contest:$c, login:$l, problem_id:$p, filename:$f, code_b64:$b, lang:$t,
       time:$ts, id:$id, offline:true}' > "$tmp"
  mv -f "$tmp" "$SPOOLDIR/$spoolname"

  user_history_append "$contest" "$SESSION_LOGIN" \
    "$claimed:$problem:$FILETYPE:Not Answered Yet:$claimed:$ID"
  metrics_recompute "$contest" "$SESSION_LOGIN"

  printf '%s\n' "$(jq -cn --arg s "$sha" --argjson cl "$claimed" --arg id "$ID" --argjson at "$NOW" \
    '{sha:$s, claimed:$cl, id:$id, at:$at}')" >> "$CHAINF"
  exec 8>&-

  # marcador p/ o organizador: var/offline-log (arrival:claimed:beacon_t:login:id:sha) + audit
  printf '%s:%s:%s:%s:%s:%s\n' "$NOW" "$claimed" "$bt" "$SESSION_LOGIN" "$ID" "$sha" \
    >> "$CDIR/var/offline-log" 2>/dev/null || true
  audit_log_to "$contest" offline-submit \
    "login=$SESSION_LOGIN id=$ID prob=$problem claimed=$claimed beacon=$bt arrival=$NOW gap_beacon=$((claimed-bt)) gap_arrival=$((NOW-claimed))${chainnote}"

  RESULTS="$(jq -c --arg s "$sha" --arg id "$ID" --argjson cl "$claimed" \
    '. + [{sha:$s, status:"accepted", submission_id:$id, counted_at:$cl}]' <<<"$RESULTS")"
done

ok_json '{results:$r, accepted:($r|map(select(.status=="accepted"))|length),
          rejected:($r|map(select(.status=="rejected"))|length)}' --argjson r "$RESULTS"
