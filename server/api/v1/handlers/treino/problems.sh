# GET /treino/problems
# Lista todos os problemas do treino: [{id, title, tags, collections, solved_count, attempted_count}]
# Serve um cache (var/problems.json) se existir e estiver fresco; senão gera na hora.
JD="$CONTESTSDIR/treino/var/jsons"
CACHE="$CONTESTSDIR/treino/var/problems.json"
COUNTS="$CONTESTSDIR/treino/var/json-count"

emit_json 200 OK
# cache válido por 5 min
if [[ -f "$CACHE" ]] && [[ -z "$(find "$CACHE" -mmin +5 2>/dev/null)" ]]; then
  cat "$CACHE"; exit 0
fi

set +o noglob
# Contagens por problema vêm de var/json-count/<arquivo>.json (mesmo basename que
# var/jsons/, ou seja, o id na forma '#'). O id INTERNO do json-count é pontilhado,
# então casamos pelo NOME DO ARQUIVO (input_filename), não pelo campo .id.
counts="$(jq -n '
  reduce inputs as $x ({};
    . + { (input_filename | sub(".*/";"") | sub("\\.json$";"")):
          {solved_count: ($x.solved_count // 0), attempted_count: ($x.attempted_count // 0)} })
' "$COUNTS"/*.json 2>/dev/null)"
[[ -n "$counts" ]] || counts='{}'

# base: id/title/tags/collections de var/jsons + as contagens reais casadas por id ('#').
jq -s --argjson c "$counts" '
  map({id, title, tags: (.tags // []), collections: (.collections // [])} + ($c[.id] // {solved_count:0, attempted_count:0}))
' "$JD"/*.json 2>/dev/null | tee "$CACHE.tmp" >/dev/null
mv -f "$CACHE.tmp" "$CACHE" 2>/dev/null
cat "$CACHE"
