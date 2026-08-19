# GET /problems/calib?id=<id>   (Bearer)
# Resumo de calibração p/ o editor: por juiz (host) que calibrou — o TL calibrado (do store),
# quando, e o LOG de calibração (run/calib/<id>/<host>.json), p/ o autor ver como cada solução
# se comportou em cada juiz.
require_method GET
require_auth
source "$_DIR/lib/tl-store.sh"; source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"
: "${RUNDIR:=/home/ribas/moj/run}"; : "${CALIB_DIR:=$RUNDIR/calib}"

id="$(param id)"
[[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
require_problem_edit "$id"   # log de calibração revela comportamento das soluções -> só dono/colaborador

store="$(tl_store_get "$id")"; [[ -n "$store" ]] || store='{}'
# agregado por host vai em ARQUIVO (--slurpfile): log (≤60 KB/host) + sols estruturado
# passam fácil do teto de 128 KiB POR ARGUMENTO do jq com 2-3 juízes.
LOGF="$(mktemp)"; trap 'rm -f "$LOGF"' EXIT
d="$CALIB_DIR/$id"
if [[ -d "$d" ]]; then
  find "$d" -maxdepth 1 -name '*.json' -type f -exec cat {} + 2>/dev/null \
    | jq -s -c 'map(select(.host)
        | {(.host): {at:.at, checksum:.checksum, log:.log,
                     reports:(.reports // []), sols:(.sols // [])}}) | add // {}' \
    > "$LOGF" 2>/dev/null
fi
[[ -s "$LOGF" ]] || echo '{}' > "$LOGF"

# linguagens das soluções good (extensão) — p/ apontar as que NÃO calibraram (falharam). O -o noglob
# da API vale aqui -> uso find, não glob.
pkg="$(pkg_path "$id")"; goodlangs='[]'
if [[ -n "$pkg" && -d "$pkg/sols/good" ]]; then
  # extensões py2/py3 legadas contam como 'py' (python unificado)
  goodlangs="$(find "$pkg/sols/good" -maxdepth 1 -type f 2>/dev/null \
    | while IFS= read -r gf; do e="${gf##*.}"; case "$e" in py2|py3) e=py;; esac; [[ "$e" != "$gf" ]] && echo "$e"; done \
    | LC_ALL=C sort -u | jq -Rsc 'split("\n")|map(select(length>0))')"
  [[ -n "$goodlangs" ]] || goodlangs='[]'
fi

# CORPO ANTES DO CABEÇALHO (pode ser grande: log + sols por host — sai p/ arquivo).
# npy normaliza chaves de TL py3/py2 legadas (calibração pré-unificação) p/ 'py'.
BODYF="$(mktemp)"; trap 'rm -f "$LOGF" "$BODYF"' EXIT
jq -cn --argjson store "$store" --slurpfile lg "$LOGF" --argjson gl "$goodlangs" \
   --argjson ov "$(tl_conf_overrides "$pkg")" '
  def npy: if .=="py3" or .=="py2" then "py" else . end;
  ($lg[0] // {}) as $logs
  | ($store.hosts // {}) as $h
  | (($h|keys) + ($logs|keys) | unique) as $hosts
  | ([ $h[]?.tl // {} | keys[] | npy | select(.!="default") ] | unique) as $served   # calibrado em >=1 host
  | { success:true, id:($store.id // ""), checksum:($store.checksum // ""),
      good_langs:$gl, tl_override:$ov,
      missing_langs:[ $gl[] | select(. as $g | ($served|index($g)|not)) ],     # sem TL em NENHUM host
      hosts: [ $hosts[] as $n
               | ($h[$n].tl // {}) as $htl
               | ($htl | keys | map(npy)) as $htlk
               | { host:$n, tl:$htl,
                   missing:[ $gl[] | select(. as $g | ($htlk|index($g)|not)) ],  # sem TL NESTE host
                   at:($h[$n].at // $logs[$n].at // 0),
                   log:($logs[$n].log // null),
                   reports:($logs[$n].reports // []),
                   sols:($logs[$n].sols // []) } ] }' > "$BODYF" 2>/dev/null
[[ -s "$BODYF" ]] || fail 500 "Falha ao montar a resposta" "calib_fail"
emit_json 200 OK
cat "$BODYF"
