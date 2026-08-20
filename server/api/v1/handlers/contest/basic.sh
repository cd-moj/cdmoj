# GET /contest/basic?contest=<id>   (PÚBLICO)
# Info básica p/ tela de login/countdown: nome, id, início, fim, login_start_time, locale.
# Com sessão DESTE contest no Bearer (opcional), o end_time devolvido é o fim EFETIVO do
# login (prorrogação por sede/grupo via time-overrides.json) — o countdown mostra o certo.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"

CONTEST_ID="$contest"; CONTEST_NAME=""; CONTEST_START=0; CONTEST_END=0
LOGIN_START_TIME=""; LOCALE=""; LOGIN_ENABLED=""; FREEZE_TIME=""; SCORE_ANON=""; LANGUAGES=""; SECRET=""; SCORE_BALLOON_STYLE=""
ROUND=""; ROUND_NAME=""; ROUND_KIND=""
load_contest_conf "$contest"

source "$_LIBDIR/contest-gate.sh"
if load_session && [[ "$SESSION_CONTEST" == "$contest" ]]; then
  CONTEST_END="$(contest_end_effective "$contest" "$SESSION_LOGIN")"
fi

[[ -n "$LOGIN_START_TIME" ]] || LOGIN_START_TIME="$CONTEST_START"
# locale CRU: "" quando não setado (o front cai no seletor/idioma do browser); "pt"/"en"
# explícitos IMPÕEM o idioma da interface do contest (competidor estrangeiro não se perde).
le="$([[ "$LOGIN_ENABLED" == n ]] && echo false || echo true)"
sa="$([[ "$SCORE_ANON" == 1 ]] && echo true || echo false)"
# whitelist de linguagens do contest (conf LANGUAGES="C CPP PY3 …"); vazio => [] => front mostra todas.
langs_json='[]'
[[ -n "$LANGUAGES" ]] && langs_json="$(printf '%s\n' $LANGUAGES | grep -v '^$' | jq -R . | jq -cs .)"

# `secret`: contest SUPER SECRETO (fora das listagens; placar/visual exigem login). O basic
# em si continua público — a tela de login/countdown precisa do nome p/ quem tem o link.
# `round`: rodada ATIVA (aquecimento × prova oficial no mesmo contest). O front avisa o time
# em faixa fixa — competidor não pode confundir aquecimento com prova. null = contest sem rodadas.
round_json=null
[[ -n "$ROUND" ]] && round_json="$(jq -cn --arg s "$ROUND" --arg n "${ROUND_NAME:-$ROUND}" \
   --arg k "${ROUND_KIND:-official}" '{slug:$s, name:$n, kind:$k, warmup:($k == "warmup")}')"

# COORTE do login (times oficiais × convidados): o front avisa o convidado que ele está no
# placar de convidados, e o seletor de visão só aparece p/ quem tem mais de uma. null = contest
# sem coortes (o caso comum). Precisa de sessão DESTE contest — anônimo não recebe nada.
cohort_json=null
source "$_LIBDIR/cohorts.sh"
# PLACARES PARALELOS (ex.: times × individual num contest com inscrição): coorte PÚBLICA com
# `ranking:true` tem placar próprio, e a lista é pública (não depende de sessão) — o seletor
# do /contest/score/ só existe quando há mais de um.
score_views_json='[]'
CH_ON=0; ch_enabled "$contest" && CH_ON=1     # UMA vez: cada chamada forkava um jq
if (( CH_ON )); then
  score_views_json="$(jq -c '[.cohorts[] | select(.public and .ranking) | {id, name}]' <<<"$(ch_get "$contest")")"
  [[ -n "$score_views_json" ]] || score_views_json='[]'
fi
if (( CH_ON )) && load_session 2>/dev/null && [[ "$SESSION_CONTEST" == "$contest" ]]; then
  _co="$(ch_of "$contest" "$SESSION_LOGIN")"
  _cv="$(ch_view_for_login "$contest" "$SESSION_LOGIN")"
  cohort_json="$(jq -cn --arg i "$_co" --arg v "$_cv" --argjson j "$(ch_get "$contest")" '
    ($j.cohorts | map(select(.id == $i)) | first // {}) as $c
    | {id:$i, name:($c.name // $i), unranked:($c.unranked == true), public:($c.public != false),
       view:$v, released:($j.results_released == true),
       views:(if $v == "all" then ["geral","oficial"] else [] end)}')"
fi

# penalty_minutes: REGRA DE PONTUAÇÃO, não segredo — o competidor precisa saber quanto custa
# um erro. Vive aqui porque a cerimônia de revelação (que .animeitor/.judge/.cstaff abrem)
# precisa dela p/ recalcular penalidade e ORDEM das linhas; ela só existia em
# /contest/admin/settings (admin-only), então o telão caía no default 20 e mostrava
# classificação errada em prova com penalidade diferente (2026-08-20).
ok_json '{contest_id:$id, contest_name:$name, start_time:$start, end_time:$end,
          login_start_time:$lst, locale:$loc, login_enabled:$le, freeze_time:$fz, score_anon:$sa,
          penalty_minutes:$pen,
          languages:$langs, secret:$sec, round:$round, cohort:$cohort, score_views:$sv,
          balloon_style:$bstyle}' \
  --arg bstyle "$([[ "$SCORE_BALLOON_STYLE" == fill ]] && echo fill || echo icon)" \
  --argjson round "$round_json" --argjson cohort "$cohort_json" --argjson sv "$score_views_json" \
  --arg id "$CONTEST_ID" --arg name "$CONTEST_NAME" \
  --argjson start "${CONTEST_START:-0}" --argjson end "${CONTEST_END:-0}" \
  --argjson lst "${LOGIN_START_TIME:-0}" --arg loc "$LOCALE" \
  --argjson le "$le" --argjson fz "${FREEZE_TIME:-0}" --argjson sa "$sa" \
  --argjson pen "$(p="${PENALTY_MINUTES:-20}"; [[ "$p" =~ ^[0-9]+$ ]] || p=20; printf %s "$p")" \
  --argjson langs "$langs_json" \
  --argjson sec "$([[ "$SECRET" == 1 ]] && echo true || echo false)"
