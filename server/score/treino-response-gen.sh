#!/usr/bin/env bash
#
# treino-response-gen.sh <contest> <outfile>
#
# Gera o JSON de TEMPO DE RESPOSTA do treino (ou de qualquer contest) a partir de:
#   - controle/history (7 campos: tempo:user:prob:lang:verdict:sub_epoch:subid) -> mapa subid->sub_epoch
#   - results/<id>.json (um por submissão julgada pelo pipeline v2) -> finalized_at, duration_s
#
# Métricas (só submissões com finalized_at — único timestamp de veredito persistido):
#   espera (wait)  = finalized_at - sub_epoch   (submit -> veredito; o que o usuário espera)
#   julgamento     = duration_s                  (execução pura no juiz)
#   fila (queue)   = max(0, wait - julgamento)   (gargalo de capacidade/fila vs. juiz)
# Agregados: geral (média/p50/p95/máx), por dia (UTC) e por dia-da-semana × hora (UTC, p/ mapa de calor).
#
# É o "build" das estatísticas de resposta — análogo a server/score/stats-gen.sh. O handler
# /treino/admin/response-stats o usa como cache preguiçoso (lib/common.sh: regen_locked).
# O bloco de percentis espelha handlers/contest/admin/dashboard.sh.
set -u
: "${CONTESTSDIR:=/home/ribas/moj/contests}"

C="${1:-}"; OUT="${2:-}"
[[ -n "$C" && -n "$OUT" ]] || { echo "uso: treino-response-gen.sh <contest> <outfile>" >&2; exit 1; }
case "$C" in *[!A-Za-z0-9._@#+-]* | "" | *..* ) echo "treino-response-gen: invalid contest id" >&2; exit 1;; esac

hist="$CONTESTSDIR/$C/controle/history"
resdir="$CONTESTSDIR/$C/results"
# store-v2: history no formato global (temp) + results espalhados por users/<login>/results/.
_SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$_SDIR/../api/v1/lib/users.sh"
_HT=""; if store_v2 "$C"; then _HT="$(mktemp)"; emit_history_stream "$C" > "$_HT"; hist="$_HT"; fi
mkdir -p "$(dirname "$OUT")" 2>/dev/null
TMP="$(mktemp "$OUT.XXXXXX")" || { echo "treino-response-gen: mktemp falhou" >&2; exit 1; }
MAPTMP="$(mktemp "$OUT.map.XXXXXX")" || { echo "treino-response-gen: mktemp falhou" >&2; exit 1; }
trap 'rm -f "$TMP" "$MAPTMP" "${_HT:-}"' EXIT

empty='{"success":true,"coverage":{"history_total":0,"with_finalized":0},"overall":{"n":0,"avg_wait_s":0,"p50_wait_s":0,"p95_wait_s":0,"max_wait_s":0,"avg_judge_s":0,"avg_queue_s":0},"per_day":[],"by_dow_hour":[]}'

history_total=0
[[ -f "$hist" ]] && history_total="$(wc -l < "$hist" 2>/dev/null | tr -d '[:space:]')"
history_total="${history_total:-0}"

# mapa subid -> sub_epoch a partir do history, gravado em ARQUIVO. Defensivo a ':' no veredito,
# igual ao dashboard.sh: subid = último campo, sub_epoch = penúltimo. Chave duplicada (provisório
# reescrito) -> o último vence em from_entries (sub_epoch é estável). VAI A ARQUIVO porque o treino
# tem dezenas de milhares de linhas: passar o mapa por --argjson estoura ARG_MAX -> --slurpfile.
printf '{}\n' > "$MAPTMP"
if [[ -f "$hist" ]]; then
  awk -F: 'NF>=6 && $(NF)!="" {print $(NF)"\t"$(NF-1)}' "$hist" 2>/dev/null \
    | jq -R -cs 'split("\n")|map(select(length>0)|split("\t"))
                 |map({key:.[0], value:(.[1]|tonumber? // 0)})|from_entries' \
    > "$MAPTMP" 2>/dev/null
  [[ -s "$MAPTMP" ]] || printf '{}\n' > "$MAPTMP"
fi

# coleta os results/<id>.json (cada um já traz id, finalized_at, duration_s).
# store-v2: espalhados em users/<login>/results/; legado: results/ do contest.
set +o noglob; shopt -s nullglob
if store_v2 "$C"; then files=( "$(users_dir "$C")"/*/results/*.json ); else files=( "$resdir"/*.json ); fi
shopt -u nullglob

if (( ${#files[@]} == 0 )); then
  jq -cn --argjson ht "$history_total" '{success:true, coverage:{history_total:$ht, with_finalized:0},
    overall:{n:0,avg_wait_s:0,p50_wait_s:0,p95_wait_s:0,max_wait_s:0,avg_judge_s:0,avg_queue_s:0},
    per_day:[], by_dow_hour:[]}' > "$TMP"
  mv "$TMP" "$OUT"; exit 0   # o trap EXIT limpa o MAPTMP (e o TMP já movido)
fi

# 1ª etapa: registros {sub,wait,judge,queue,day,dow,hour} (só finalized_at>0 + sub_epoch conhecido);
# 2ª etapa: agregação (geral/por dia/dia×hora). PIPE entre as etapas -> nada grande por argv.
# O bloco de percentis espelha handlers/contest/admin/dashboard.sh.
jq -cs --slurpfile mapf "$MAPTMP" '
  ($mapf[0] // {}) as $submap
  | [ .[]
      | select(.id and ((.finalized_at//0) > 0))
      | ($submap[.id] // 0) as $sub
      | select($sub > 0)
      | (.finalized_at - $sub) as $wait
      | select($wait > 0)
      | (.duration_s // 0) as $judge
      | (($sub/86400)|floor) as $epday
      | { sub:$sub, wait:$wait, judge:$judge,
          queue:(if $wait > $judge then ($wait - $judge) else 0 end),
          day:($epday*86400),
          dow:((($epday % 7) + 4) % 7),
          hour:((($sub % 86400)/3600)|floor) } ]' \
  "${files[@]}" 2>/dev/null \
| jq -c --argjson ht "$history_total" '
    def pct(a; p): (a|length) as $n | if $n==0 then 0 else (a|sort)[((($n-1)*p)|floor)] end;
    def avg(a):    (a|length) as $n | if $n==0 then 0 else ((a|add)/$n|floor) end;
    . as $r
    | { success:true,
        coverage:{ history_total:$ht, with_finalized:($r|length) },
        overall: (
          ($r|map(.wait)) as $w | ($r|map(.judge)) as $j | ($r|map(.queue)) as $q |
          { n:($r|length),
            avg_wait_s:avg($w), p50_wait_s:pct($w;0.5), p95_wait_s:pct($w;0.95),
            max_wait_s:(($w + [0])|max),
            avg_judge_s:avg($j), avg_queue_s:avg($q) } ),
        per_day: ( $r | group_by(.day) | map(
            (map(.wait)) as $w |
            { day:.[0].day, n:length,
              avg_wait_s:avg($w), p50_wait_s:pct($w;0.5), p95_wait_s:pct($w;0.95),
              max_wait_s:(($w + [0])|max),
              avg_judge_s:avg(map(.judge)), avg_queue_s:avg(map(.queue)) } )
          | sort_by(.day) ),
        by_dow_hour: ( $r | group_by(.dow*100 + .hour) | map(
            { dow:.[0].dow, hour:.[0].hour, n:length, avg_wait_s:avg(map(.wait)) } )
          | sort_by(.dow*100 + .hour) ) }' \
  > "$TMP" 2>/dev/null || printf '%s\n' "$empty" > "$TMP"

mv "$TMP" "$OUT"   # o trap EXIT limpa o MAPTMP (e o TMP já movido)
