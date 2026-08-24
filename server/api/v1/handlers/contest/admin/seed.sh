# POST /contest/admin/seed?contest=<id>   (admin DO contest, e SÓ em contest com DEMO=1)
#
# Povoa um contest de DEMONSTRAÇÃO com times e submissões SINTÉTICAS: placar cheio, veredictos
# variados e freeze no meio da janela, em segundos e sem encostar em juiz nenhum.
#
# POR QUE EXISTE: quem desenvolve o **Animeitor** (o telão que consome o `/contest/webcast`)
# precisa de um placar de verdade para trabalhar — muitos times, muitos problemas, veredictos
# misturados e um freeze que ele possa mover. Não havia como: o juiz mock só devolve
# `Accepted,100p`, o `/contest/set-verdict` sobrescreve mas não CRIA submissão, e não existia
# gerador de contest povoado (o fixture de 2000 times do `test/load/README.md` foi ad-hoc e
# apagado). Sem isto, testar o telão exigia uma prova acontecendo.
#
# NÃO é um caminho de julgamento: escreve pelos MESMOS escritores do veredicto real
# (`user_history_append` + `metrics_recompute` + `score/build.sh`), então o que sai é
# indistinguível para placar, estatística, webcast e balões.
#
# body: {teams:int, submissions:int, seed:int, freeze_minute:int|null, password:str,
#        verdicts:{accepted,wrong,tle,rte,ce,pending}}   (todos opcionais)
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

# ⚠ A TRAVA. Sem DEMO=1 no conf a rota não existe para efeitos práticos: uma prova de verdade
# nunca pode receber submissão sintética, nem por engano nem por má-fé. A marca só é gravada na
# CRIAÇÃO do contest (`demo:true` no spec — cc_settings_conf_lines), não há toggle que a ligue
# depois; quem quer semear cria um contest novo.
[[ "$(conf_value "$contest" DEMO)" == 1 ]] \
  || fail 403 "Contest não é de demonstração (DEMO=1 no conf, definido na criação)" "demo_required"

source "$_LIBDIR/users.sh"
source "$_LIBDIR/contest-create.sh"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
num(){ local v; v="$(jq -r --arg k "$1" '.[$k] // empty' <<<"$body")"; v="${v//[^0-9]/}"; printf '%s' "${v:-$2}"; }
TEAMS="$(num teams 20)"; SUBS="$(num submissions 200)"; SEED="$(num seed 1)"
FZMIN="$(jq -r '.freeze_minute // empty' <<<"$body")"; FZMIN="${FZMIN//[^0-9]/}"
PW="$(jq -r '.password // "demo1234"' <<<"$body")"
[[ "$PW" =~ ^[A-Za-z0-9._@-]{4,64}$ ]] || fail 422 "Senha inválida" "password_invalid"
(( TEAMS >= 1 && TEAMS <= 500 ))   || fail 422 "teams fora de 1..500" "teams_range"
(( SUBS  >= 0 && SUBS  <= 20000 )) || fail 422 "submissions fora de 0..20000" "subs_range"

# --- o que o contest já é: janela + ids canônicos dos problemas -------------------------------
# ⚠ O probid do history TEM de ser o canônico (`PROBS[i+4]`, o `SC_CANON` do score-common): com
# qualquer outra grafia a célula fica em BRANCO no placar — e em silêncio, porque a estatística e
# o webcast continuam mostrando a submissão. É o jeito mais fácil de a semeadura parecer certa.
readarray -t CINFO < <(
  ( CONTEST_START=0; CONTEST_END=0; PROBS=()
    source "$CONTESTSDIR/$contest/conf" 2>/dev/null
    printf '%s\n%s\n' "${CONTEST_START:-0}" "${CONTEST_END:-0}"
    for ((i=0; i<${#PROBS[@]}; i+=5)); do
      c="${PROBS[i+4]:-}"; [[ "$c" == *"#"* ]] || c="${PROBS[i+1]//\//#}"
      printf '%s\n' "$c"
    done )
)
START="${CINFO[0]//[^0-9]/}"; END="${CINFO[1]//[^0-9]/}"
PROBIDS=("${CINFO[@]:2}")
(( ${#PROBIDS[@]} > 0 )) || fail 422 "Contest sem problemas no conf" "no_problems"
[[ "$START" =~ ^[0-9]+$ && "$END" =~ ^[0-9]+$ ]] && (( END > START )) \
  || fail 422 "Janela do contest inválida (CONTEST_START/CONTEST_END)" "window_invalid"
# probid vai por printf dentro do awk (JSON e history): recusa qualquer coisa fora do alfabeto
for p in "${PROBIDS[@]}"; do
  [[ "$p" =~ ^[A-Za-z0-9._#/-]+$ ]] || fail 422 "Problema com id inesperado: $p" "problem_id_invalid"
done

# --- freeze (opcional): é ele que faz o placar congelado DIFERIR do completo -------------------
FZ=""
if [[ -n "$FZMIN" ]]; then
  FZ=$(( START + FZMIN * 60 ))
  cc_set_conf_var "$contest" FREEZE_TIME "$FZ"   # mexer no conf dispara o recompute em massa
fi

WORK="$(mktemp -d)" || fail 500 "temp" "temp_fail"
trap 'rm -rf "$WORK"' EXIT

# --- times ------------------------------------------------------------------------------------
# Login SEM sufixo reservado (`.admin/.judge/.animeitor/…` são varridos do placar por
# sc_is_real_user). `.team` é o que dá bandeira/sigla/sede para o telão desenhar.
SEDES=(Brasília Curitiba Fortaleza Manaus Recife "Rio de Janeiro" Salvador "São Paulo")
SIGLAS=(UnB UFPR UFC UFAM UFPE UFRJ UFBA USP)
BAND=(br-df br-pr br-ce br-am br-pe br-rj br-ba br-sp)
created=0
for ((t=1; t<=TEAMS; t++)); do
  login="$(printf 'time-%02d' "$t")"
  [[ -f "$(user_dir "$contest" "$login")/account.json" ]] && continue
  k=$(( (t - 1) % ${#SEDES[@]} ))
  user_create "$contest" "$login" "$(printf 'Time %02d — %s' "$t" "${SIGLAS[k]}")" "$PW" >/dev/null || continue
  account_team_merge "$contest" "$login" \
    "$(team_fields_json "$(jq -cn --arg u "${SIGLAS[k]}" --arg f "Universidade ${SIGLAS[k]}" \
        --arg c "${BAND[k]}" --arg r "${SEDES[k]}" '{univ_short:$u, univ_full:$f, country:$c, region:$r}')")"
  created=$((created+1))
done

# --- as submissões ----------------------------------------------------------------------------
# Um único awk determinístico (srand($SEED)) monta TUDO: as linhas de history (uma por arquivo de
# usuário, via `print >> arquivo`) e os results/<id>.json. Um awk só em vez de N forks — e nada
# passa por argv de jq (900 submissões estourariam os 128 KiB de um argumento).
# ⚠ A JANELA TEM DE SER DETERMINÍSTICA. As submissões caem na parte JÁ DECORRIDA da prova, e
# "decorrida" depende do relógio: duas semeaduras com o mesmo `seed` a segundos de distância
# davam placares diferentes — e sem determinismo o desenvolvedor do telão não reproduz um bug.
# Então o vão é arredondado para MINUTO cheio, e `window_minutes` no corpo o fixa de vez.
NOW="$EPOCHSECONDS"
WMIN="$(jq -r '.window_minutes // empty' <<<"$body")"; WMIN="${WMIN//[^0-9]/}"
if [[ -n "$WMIN" ]]; then SPAN=$(( WMIN * 60 ))
else LAST=$(( END < NOW ? END : NOW )); (( LAST > START )) || LAST=$END; SPAN=$(( ((LAST - START) / 60) * 60 )); fi
(( SPAN >= 60 )) || SPAN=60
(( START + SPAN <= END )) || SPAN=$(( END - START ))
printf '%s\n' "${PROBIDS[@]}" > "$WORK/probs"
W_AC="$(jq -r '.verdicts.accepted // 28' <<<"$body")"; W_WA="$(jq -r '.verdicts.wrong // 34' <<<"$body")"
W_TLE="$(jq -r '.verdicts.tle // 14' <<<"$body")"; W_RTE="$(jq -r '.verdicts.rte // 10' <<<"$body")"
W_CE="$(jq -r '.verdicts.ce // 8' <<<"$body")";     W_PEND="$(jq -r '.verdicts.pending // 6' <<<"$body")"
for v in W_AC W_WA W_TLE W_RTE W_CE W_PEND; do [[ "${!v}" =~ ^[0-9]+$ ]] || fail 422 "peso inválido" "weight_invalid"; done

awk -v teams="$TEAMS" -v subs="$SUBS" -v seed="$SEED" -v start="$START" -v span="$SPAN" \
    -v udir="$CONTESTSDIR/$contest/users" -v contest="$contest" -v now="$NOW" \
    -v wac="$W_AC" -v wwa="$W_WA" -v wtle="$W_TLE" -v wrte="$W_RTE" -v wce="$W_CE" -v wpend="$W_PEND" '
  BEGIN{ FS="\n" }
  { probs[++P]=$0 }
  END{
    srand(seed)
    split("C CPP PY JAVA KT", L, " "); nL=5
    tot=wac+wwa+wtle+wrte+wce+wpend; if (tot<=0){ wac=1; tot=1 }
    if (span < 60) span = 60
    n=0; guard=0
    while (n < subs && guard < subs*40 + 1000) {
      guard++
      t = int(rand()*teams) + 1
      p = int(rand()*P) + 1
      key = t "|" p
      if (key in solved) continue          # time não insiste em problema já resolvido
      ep = start + int(rand()*span)
      r = rand()*tot
      if      (r < wac)                          { v="Accepted,100p";            vc="Accepted" ; solved[key]=1 }
      else if (r < wac+wwa)                      { v="Wrong Answer,0p";          vc="Wrong Answer" }
      else if (r < wac+wwa+wtle)                 { v="Time Limit Exceeded,0p";   vc="Time Limit Exceeded" }
      else if (r < wac+wwa+wtle+wrte)            { v="Runtime Error,0p";         vc="Runtime Error" }
      else if (r < wac+wwa+wtle+wrte+wce)        { v="Compilation Error";        vc="Compilation Error" }
      else                                       { v="Not Answered Yet";         vc="Not Answered Yet" }
      login = sprintf("time-%02d", t)
      lang  = L[int(rand()*nL)+1]
      id = sprintf("%08x%08x%08x%08x", seed % 4294967296, n, int(rand()*2147483647), int(rand()*2147483647))
      printf "%d:%s:%s:%s:%d:%s\n", ep - start, probs[p], lang, v, ep, id >> (udir "/" login "/history")
      printf "{\"id\":\"%s\",\"contest\":\"%s\",\"problem_id\":\"%s\",\"login\":\"%s\",\"lang\":\"%s\",\"verdict\":\"%s\",\"verdict_canon\":\"%s\",\"host\":\"seed\",\"finalized_at\":%d}\n", \
             id, contest, probs[p], login, lang, v, vc, now > (udir "/" login "/results/" id ".json")
      close(udir "/" login "/results/" id ".json")
      cnt[vc]++; n++
    }
    for (k in cnt) printf "%s\t%d\n", k, cnt[k] > "/dev/stderr"
    print n
  }' "$WORK/probs" > "$WORK/n" 2> "$WORK/counts"
made="$(tr -cd '0-9' < "$WORK/n")"; made="${made:-0}"

# --- tornar visível: métricas por usuário + placar ---------------------------------------------
touch "$CONTESTSDIR/$contest/var/.score-dirty" 2>/dev/null
while IFS= read -r u; do [[ -n "$u" ]] && metrics_recompute "$contest" "$u" >/dev/null 2>&1; done \
  < <(list_users "$contest")
( cd "$_DIR/../.." 2>/dev/null; bash "$_DIR/../../score/build.sh" "$contest" >/dev/null 2>&1 ) || true

lines=0; [[ -f "$CONTESTSDIR/$contest/var/placar.txt" ]] && lines="$(wc -l < "$CONTESTSDIR/$contest/var/placar.txt")"
audit_log_to "$contest" seed "teams=$TEAMS novos=$created subs=$made seed=$SEED freeze=${FZ:-}"

ok_json_slurp '{teams:$TEAMS, teams_created:$CREATED, submissions:$MADE, seed:$SEED,
                freeze_time:$FZ, password:$PW, board_lines:$LINES, window_minutes:$WM,
                by_verdict:($cnt[0] | split("\n") | map(select(length>0) | split("\t"))
                            | map({(.[0]): (.[1]|tonumber)}) | add // {})}' \
  cnt "$(jq -Rs . < "$WORK/counts")" \
  --argjson TEAMS "$TEAMS" --argjson CREATED "$created" --argjson MADE "$made" \
  --argjson SEED "$SEED" --argjson LINES "${lines//[^0-9]/}" --argjson WM "$(( SPAN / 60 ))" \
  --arg PW "$PW" --argjson FZ "${FZ:-null}"
