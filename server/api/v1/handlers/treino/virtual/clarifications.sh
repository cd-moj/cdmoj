# GET /treino/virtual/clarifications?contest=<cid>   (Bearer do TREINO)
# AVISOS E CLARIFICATIONS DA PROVA NO TEMPO RELATIVO (10/11/2026; decisão do Ribas: "as clarifications públicas no
# momento relativo que foram disponibilizadas"). Só o que foi PÚBLICO na prova: a clarification respondida em público,
# o aviso oficial (broadcast) e a notícia do contest. Cada item vale a partir de `rel` = o instante em que saiu −
# CONTEST_START (resposta: answered_at; aviso: time; notícia: date); antes da prova = rel 0.
# O CORTE É AQUI, pelo relógio da run (vr_clock): com a run rodando só sai `rel ≤ decorrido` E dentro da prova; o que
# saiu depois do fim só com a run terminada. O cliente nunca recebe o que ainda não "aconteceu" — nem a CONTAGEM.
# Pergunta privada nunca sai; quem perguntou e quem respondeu também não (o anonimato do relatório público).
# Run não largada = 403 `virtual_not_started`; contest inelegível = o 404 do portão.
require_method GET
require_auth_contest treino
source "$_LIBDIR/virtual.sh"
cid="$(param contest)"; vr_gate "$cid"
vr_clock "$SESSION_LOGIN" "$cid" || fail 403 "Comece a participação virtual para ver os avisos" "virtual_not_started"
d="$CONTESTSDIR/$cid"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
find "$d/clarifications" -maxdepth 1 -name '*.json' -type f -exec cat {} + 2>/dev/null | jq -cs '.' > "$W/c.json" 2>/dev/null \
  || printf '[]' > "$W/c.json"
[[ -s "$W/c.json" ]] || printf '[]' > "$W/c.json"
if [[ -s "$d/news.json" ]] && jq -e 'type == "array"' "$d/news.json" >/dev/null 2>&1; then cp "$d/news.json" "$W/n.json"
else printf '[]' > "$W/n.json"; fi
printf '%s\n' "${VR_SHORT[@]}" | jq -Rn '[inputs | select(length > 0)]' > "$W/l.json"
ok_json '
  $a[0] as $C | $n[0] as $N | $l[0] as $L
  | def relof($at): ([($at | tonumber? // 0) - $st, 0] | max);
    def letter: (tostring) as $p | if ($L | index($p)) != null then $p else "general" end;
  ( [ $C[] | objects | select(.public == true and ((.answer // "") | tostring | length) > 0)
      | (if .broadcast == true then .time else .answered_at end) as $at
      | {kind:(if .broadcast == true then "notice" else "clar" end), id:(.id // "" | tostring),
         problem:(.problem // "general" | letter), question:(.question // "" | tostring),
         answer:(.answer // "" | tostring), rel:relof($at), after:((($at | tonumber? // 0) - $st) > $dur)} ]
  + [ $N[] | objects
      | {kind:"news", id:(.id // "" | tostring), title:(.title // "" | tostring), text:(.text // "" | tostring),
         file:(if (.file.name // "") != "" then {name:(.file.name | tostring), size:(.file.size // 0)} else null end),
         rel:relof(.date), after:((((.date | tonumber? // 0)) - $st) > $dur)} ] )
  | map(select($ended or ((.after | not) and .rel <= $el)))
  | sort_by(-.rel)
  | {contest:$c, elapsed:$el, ended:$ended, items:.}' --slurpfile a "$W/c.json" \
  --slurpfile n "$W/n.json" --slurpfile l "$W/l.json" --arg c "$VR_CID" --argjson st "$VR_START" --argjson dur "$VR_DUR" \
  --argjson el "$VR_ELAPSED" --argjson ended "$( (( VR_ENDED )) && echo true || echo false )"
