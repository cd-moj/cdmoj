# POST /judge/calib-report   (Bearer mojw_<token>)
# O juiz reporta o LOG de calibração de um problema, por host, + o report.html POR SOLUÇÃO
# + o vetor ESTRUTURADO `sols` (o que rodou, teste a teste — p/ ferramentas externas).
# Guardamos em run/calib/<id>/<host>.json {host,checksum,at,log,reports:[nomes],sols:[…]} e
# cada report em run/calib/<id>/r/<host>/<nome>.html — p/ o autor inspecionar no editor.
#   body: {host, id, checksum, log,
#          reports:[{name, html_b64}],
#          sols:[{file,lang,category,verdict,tests:[{name,code,time,tl}]}]}   (sols: opcional)
# PRESERVAÇÃO: reports/sols AUSENTES no POST com o MESMO checksum preservam os anteriores —
# o re-envio de boot do agente (só log) e o agente velho (sem sols) não apagam o dado.
# Checksum NOVO zera o que não veio (dado da versão antiga engana).
require_method POST
require_worker
source "$_DIR/../../judge-gw/sched-lib.sh"   # valid_hostname
: "${RUNDIR:=/home/ribas/moj/run}"; : "${CALIB_DIR:=$RUNDIR/calib}"

bf="$(read_body_file)"; trap 'rm -f "$bf"' EXIT
jq -e . >/dev/null 2>&1 < "$bf" || fail 400 "Invalid JSON body" "bad_json"
host="$(jq -r '.host // empty' "$bf")"; valid_hostname "$host" || fail 400 "Invalid host" "host_invalid"
id="$(jq -r '.id // empty' "$bf")"; valid_id "$id" || fail 400 "Invalid id" "id_invalid"
cks="$(jq -r '.checksum // empty' "$bf")"; [[ "$cks" =~ ^[a-f0-9]{0,64}$ ]] || cks=""

d="$CALIB_DIR/$id"; rdir="$d/r/$host"; mkdir -p "$d" "$rdir" 2>/dev/null
f="$d/$host.json"
oldcks="$(jq -r '.checksum // ""' "$f" 2>/dev/null)"
same=0; [[ -n "$cks" && "$cks" == "$oldcks" ]] && same=1

# reports: só mexe no diretório quando o POST TRAZ reports (o re-envio de boot vem sem —
# antes o rm incondicional apagava os HTML a cada reboot de juiz)
nreps="$(jq -r '(.reports // []) | length' "$bf" 2>/dev/null)"; nreps="${nreps//[^0-9]/}"; nreps="${nreps:-0}"
if (( nreps > 0 )); then
  rm -f "$rdir"/*.html 2>/dev/null; names='[]'
  while IFS= read -r rep; do
    rn="$(jq -r '.name // empty' <<<"$rep" | tr -cd 'A-Za-z0-9._-')"; [[ -n "$rn" ]] || continue
    if jq -r '.html_b64 // ""' <<<"$rep" | base64 -d > "$rdir/$rn.html" 2>/dev/null; then
      names="$(jq -c --arg n "$rn" '. + [$n]' <<<"$names")"
    fi
  done < <(jq -c '.reports[]?' "$bf")
elif (( same )); then
  names="$(jq -c '.reports // []' "$f" 2>/dev/null)"; [[ -n "$names" ]] || names='[]'
else
  rm -f "$rdir"/*.html 2>/dev/null; names='[]'
fi

# sols: projeção FECHADA por item (campo desconhecido morre na borda) + teto de 1 MB.
# Vai por ARQUIVO (--slurpfile): o vetor cresce com nº de soluções × testes.
SOLSF="$(mktemp)"; trap 'rm -f "$bf" "$SOLSF"' EXIT
if jq -e '(.sols // null) | type == "array"' "$bf" >/dev/null 2>&1 \
   && (( $(jq -c '.sols' "$bf" 2>/dev/null | wc -c) <= 1048576 )); then
  jq -c '[ .sols[]
           | {file:(.file // "" | tostring), lang:(.lang // "" | tostring),
              category:(.category // "" | tostring), verdict:(.verdict // "" | tostring),
              tests:[ (.tests // [])[]
                      | {name:(.name // "" | tostring), code:(.code // "" | tostring),
                         time:(.time | (tonumber? // null)), tl:(.tl | (tonumber? // null))} ]} ]' \
    "$bf" > "$SOLSF" 2>/dev/null
elif (( same )); then
  jq -c '.sols // []' "$f" > "$SOLSF" 2>/dev/null
fi
[[ -s "$SOLSF" ]] || echo '[]' > "$SOLSF"

tmp="$f.tmp.$$"
( umask 077; jq -c --arg h "$host" --arg c "$cks" --argjson now "$EPOCHSECONDS" \
    --argjson reps "$names" --slurpfile sols "$SOLSF" \
    '{host:$h, checksum:$c, at:$now, log:(.log // ""), reports:$reps, sols:($sols[0] // [])}' \
    "$bf" ) > "$tmp" 2>/dev/null \
  && mv -f "$tmp" "$f" || { rm -f "$tmp"; fail 500 "Could not store calib log" "calib_store_fail"; }
audit_log "calib-report" "id=$id host=$host cks=${cks:0:8} reports=$(jq 'length' <<<"$names") sols=$(jq 'length' "$SOLSF")"
ok_json '{recorded:true, id:$id, host:$h}' --arg id "$id" --arg h "$host"
