# GET /problems/my-stats  (Bearer) -> panorama de submissões dos problemas do login (dono +
# colaborador), agregado em TODA a plataforma (treino + as ~174 listas/turmas): tentativas, acertos,
# erros, veredictos mais comuns, linguagens, usuários distintos, nº de contests e o mais popular.
# FRONTEIRA: só os problemas do login (owners_visible + narrow a dono/colaborador). Nunca públicos de
# terceiros nem ids sem dono. PRIVACIDADE: só agregados por-problema — sem logins, sem NOMES de
# contests (só contests_count) — não vaza que uma prova privada usou a questão.
# O cálculo (pesado, cross-contest) vive em server/score/problem-panorama-gen.sh e é PRECOMPUTADO num
# cache; aqui servimos o cache filtrado, regenerando em BACKGROUND quando velho (padrão do índice).
require_method GET
require_auth
source "$_DIR/lib/problems.sh"

PANO="$CONTESTSDIR/treino/var/problem-panorama.json"
: "${PROBLEM_PANORAMA_TTL_MIN:=30}"
lock="$PANO.lock"
# reaper: um regen abandonado (deploy/OOM/reboot mata o setsid antes do rmdir) não pode travar o
# refresh p/ sempre — descarta lock mais velho que o pior caso de geração (mkdir é o mutex).
[[ -d "$lock" && -n "$(find "$lock" -mmin "+${PROBLEM_PANORAMA_LOCK_STALE_MIN:-15}" 2>/dev/null)" ]] && rmdir "$lock" 2>/dev/null
if [[ ! -f "$PANO" ]]; then
  # frio (1ª vez / cache perdido): gera SÍNCRONO sob o lock (evita estouro de N requests simultâneos);
  # quem não pega o lock serve o envelope vazio deste request (o próximo acha o cache pronto).
  if mkdir "$lock" 2>/dev/null; then
    bash "$SCOREDIR/problem-panorama-gen.sh" "$PANO" >/dev/null 2>&1
    rmdir "$lock" 2>/dev/null
  fi
elif [[ -n "$(find "$PANO" -mmin "+$PROBLEM_PANORAMA_TTL_MIN" 2>/dev/null)" ]]; then
  if mkdir "$lock" 2>/dev/null; then                                        # velho: regen em background
    ( setsid bash -c 'bash "$1" "$2" >/dev/null 2>&1; rmdir "$3" 2>/dev/null' \
        _ "$SCOREDIR/problem-panorama-gen.sh" "$PANO" "$lock" & ) 2>/dev/null
  fi
fi

_empty='{"success":true,"totals":{"owned":0,"with_activity":0,"attempts":0,"accepts":0,"solvers":0},"overall_verdicts":[],"overall_languages":[],"most_popular":null,"problems":[]}'
emit_json 200 OK
if [[ ! -f "$PANO" ]]; then
  printf '%s' "$_empty"
else
  # ids do login (dono/colaborador) + títulos, junto com o panorama (via --slurpfile; ARG_MAX-safe).
  owners_visible \
    | jq -c --arg me "$SESSION_LOGIN" --argjson orgs "$(my_orgs_json)" \
        '.problems | map(select(.owner==$me or ((.collaborators // [])|index($me)|type=="number")
            or (((.repo // (.id|split("#")[0])) as $r | $orgs|index($r))|type=="number")) | {id, title})' \
    | jq -c --slurpfile pano "$PANO" '
        . as $owned
        | ($pano[0].problems // {}) as $P
        | [ $owned[] | . as $o | ($P[$o.id]) as $s | select($s != null and ($s.attempts // 0) > 0)
            | { id:$o.id, title:$o.title, attempts:$s.attempts, accepts:$s.accepts,
                wrong:($s.attempts - $s.accepts), acceptance_rate:$s.acceptance_rate,
                distinct_users:$s.distinct_users, solvers:$s.solvers, contests_count:$s.contests_count,
                verdicts:$s.verdicts, languages:$s.languages, first:$s.first, last:$s.last } ] as $rows
        | { success:true,
            totals: { owned:($owned|length), with_activity:($rows|length),
                      attempts:([$rows[].attempts]|add // 0), accepts:([$rows[].accepts]|add // 0),
                      solvers:([$rows[].solvers]|add // 0) },
            overall_verdicts: ([$rows[].verdicts[]] | group_by(.verdict)
              | map({verdict:.[0].verdict, count:(map(.count)|add)}) | sort_by(-.count)),
            overall_languages: ([$rows[].languages[]] | group_by(.lang)
              | map({lang:.[0].lang, submissions:(map(.submissions)|add), accepted:(map(.accepted)|add)}) | sort_by(-.submissions)),
            most_popular: ($rows | max_by(.attempts) // null | if . == null then null else {id, title, attempts} end),
            problems: ($rows | sort_by(-.attempts)) }' \
    || printf '%s' "$_empty"
fi
