#!/bin/bash
# bancada-mock-judge.sh <router.sh> <rundir-do-run> — juiz MOCK em modo PULL de verdade.
#
# Faz o que o agente real faz, pelo MESMO caminho de produção (é o que exercita o
# q_claim e o /judge/result reais, os dois pontos quentes do escalonador):
#   loop: POST /judge/heartbeat (Bearer mojw_) → lote assigned[] → p/ cada job, lê o
#   hint `//moj-mock: <veredito>` da fonte, espera JUDGE_MOCK_DELAY_MS e POST
#   /judge/result com o payload no shape do juiz real.
# Herda CONTESTSDIR/RUNDIR/SPOOLDIR/SESSIONDIR do chamador (bancada.sh).
set -u
ROUTER="${1:?router.sh}"; RUND="${2:?rundir}"
: "${JUDGE_MOCK_DELAY_MS:=300}"
TOK="$(cat "$RUNDIR/secrets/worker.token")"

# dois transportes: router DIRETO (rig esteira — sem tier web) ou HTTP (rig prova —
# MOCKJ_BASE/MOCKJ_HOST apontam o nginx local; o custo do handler entra no tier web)
if [[ -n "${MOCKJ_BASE:-}" ]]; then
  call(){ # <path> <body>
    curl -sk -m 20 -X POST -H "Host: ${MOCKJ_HOST:?}" -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $TOK" -d "$2" "$MOCKJ_BASE/api/v1$1" 2>/dev/null
  }
else
  call(){ # <path> <body> -> stdout corpo
    PATH_INFO="$1" REQUEST_METHOD=POST QUERY_STRING="" \
      HTTP_AUTHORIZATION="Bearer $TOK" bash "$ROUTER" <<<"$2" 2>/dev/null \
      | awk 'f{print} /^\r?$/{f=1}'
  }
fi

judge_one(){ # <job-json>
  local j="$1" id contest prob login lang code v first
  # uma extração só (a doutrina da casa vale até no mock)
  IFS=$'\x01' read -r id contest prob login lang code < <(
    jq -j '[.id // "", .contest // "", .problem_id // "", .login // "", .lang // "C",
            .code_b64 // .source_b64 // ""] | join("")' <<<"$j" 2>/dev/null)
  [[ -n "$id" && -n "$contest" ]] || return 0
  v="Accepted,100p"
  first="$(printf '%s' "$code" | base64 -d 2>/dev/null | head -1)"
  [[ "$first" == "//moj-mock: "* ]] && v="${first#//moj-mock: }"
  if [[ "${JUDGE_MOCK_DELAY_MS}" =~ ^[0-9]+$ ]] && (( JUDGE_MOCK_DELAY_MS > 0 )); then
    sleep "$(( JUDGE_MOCK_DELAY_MS / 1000 )).$(printf '%03d' "$(( JUDGE_MOCK_DELAY_MS % 1000 ))")"
  fi
  local body
  body="$(jq -cn --arg id "$id" --arg c "$contest" --arg p "$prob" --arg l "$login" \
     --arg lg "$lang" --arg v "$v" \
     '{host:"mockj", id:$id, contest:$c, problem_id:$p, login:$l, lang:$lg, verdict:$v,
       verdict_canon:($v | sub(",.*$"; "")), score:0, score_max:100, correct:1,
       total_tests:2, duration_s:1, tl_used:1,
       report_html_b64:"PGgxPm1vY2s8L2gxPgo="}')"
  call /judge/result "$body" > /dev/null
}

while :; do
  r="$(call /judge/heartbeat '{"host":"mockj","state":"free","free_slots":'"${MOCKJ_SLOTS:-8}"',"total_slots":'"${MOCKJ_SLOTS:-8}"',"inv_hash":"bancada","status":"ok"}')"
  n=0
  while IFS= read -r j; do
    [[ -n "$j" ]] || continue
    judge_one "$j" &
    n=$(( n + 1 ))
  done < <(jq -c '(.assigned // empty) | if type == "array" then .[] else . end' <<<"$r" 2>/dev/null)
  wait
  (( n == 0 )) && sleep 0.5
done
