# GET /treino/problems
# Lista todos os problemas do treino: [{id, title, tags, solved_count, attempted_count}]
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
# base: id, title, tags de cada problema. Conta solved/attempted de var/json-count/<id>
# se existir (formato tolerante: número simples = attempted, ou JSON {solved,attempted}).
{
  jq -s 'map({id, title, tags: (.tags // [])})' "$JD"/*.json 2>/dev/null \
  | jq -c --arg cdir "$COUNTS" '
      map(. + {solved_count:0, attempted_count:0})
    '
} | tee "$CACHE.tmp" >/dev/null
mv -f "$CACHE.tmp" "$CACHE" 2>/dev/null
cat "$CACHE"
