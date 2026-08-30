#!/bin/bash
# bancada-poller.sh <base-url> <tokens-file> <dur_s> <out.log> [pendfile]
#
# Os CLIENTES da bancada (rig prova): reproduz o comportamento medido da Maratona —
# (a) o MIX base de leitura (updates 55% · score 29% · basic 8% · history 5% ·
#     problems 3%, o mesmo do stress.sh) em ritmo proporcional ao nº de times;
# (b) a ESPIRAL: todo time listado em <pendfile> (mantido pelo feeder: 1 login por
#     linha enquanto tiver submissão pendente) pola /contest/history + /submission/summary
#     a cada 5-10 s — taxa REAL, não comprimida: é o acoplamento veredicto-atrasado ⇒
#     mais poll que derrubou o dia 29.
# Um processo só (curl reaproveitado); log: <epoch> <rota> <código> <tempo> <bytes>.
set -u
B="${1:?base}"; TOKF="${2:?tokens}"; DUR="${3:?dur}"; OUT="${4:?out}"; PENDF="${5:-/dev/null}"
Q="contest=${BANCADA_CONTEST:-bz}"
END=$(( EPOCHSECONDS + DUR ))
mapfile -t TOKS < "$TOKF"
NT=${#TOKS[@]}; (( NT > 0 )) || { echo "sem tokens" >&2; exit 1; }

HOSTH=(); [[ -n "${POLLER_HOST:-}" ]] && HOSTH=(-H "Host: $POLLER_HOST")
req(){ # <token> <rota> <tag>
  local r
  r="$(curl -sk --compressed -o /dev/null -m 15 "${HOSTH[@]}" \
      -w '%{http_code} %{time_total} %{size_download}' \
      -H "Authorization: Bearer $1" "$B/api/v1/$2" 2>/dev/null)"
  printf '%s %s %s\n' "$EPOCHSECONDS" "$3" "${r:-000 15.0 0}" >> "$OUT"
}

ROTAS=(updates updates updates updates updates updates updates updates updates updates updates
       score score score score score score basic basic history problems)   # ~55/29/8/5/3
while (( EPOCHSECONDS < END )); do
  # mix base: um cliente aleatório, uma rota do mix
  t="${TOKS[RANDOM % NT]}"
  case "${ROTAS[RANDOM % ${#ROTAS[@]}]}" in
    updates)  req "$t" "contest/updates?$Q" updates ;;
    score)    req "$t" "contest/score?$Q" score ;;
    basic)    req "$t" "contest/basic?$Q" basic ;;
    history)  req "$t" "contest/history?$Q" history ;;
    problems) req "$t" "contest/problems?$Q" problems ;;
  esac
  # a espiral: times com pendência polam history+summary (5-10 s cada um; aqui um por
  # giro). O PENDF guarda o TOKEN de sessão do time (o feeder o alimenta ao submeter).
  if [[ -s "$PENDF" ]]; then
    mapfile -t PEND < "$PENDF" 2>/dev/null
    if (( ${#PEND[@]} > 0 )); then
      pt="${PEND[RANDOM % ${#PEND[@]}]}"
      req "$pt" "contest/history?$Q" phist
      req "$pt" "submission/summary?$Q&ids=deadbeefdeadbeefdeadbeefdeadbeef" psumm
    fi
  fi
  # ritmo: quanto mais times, menor o intervalo (alvo ≈ NT reqs/30s de mix base)
  sleep "0.$(( (RANDOM % 20) + 5 ))"
done
