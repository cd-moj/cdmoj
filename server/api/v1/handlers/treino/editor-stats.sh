# GET /treino/editor-stats -> estatísticas gerais dos editores DECLARADOS pelos
# usuários do treino (campo favorite_editor do account.json). Público.
# {success, total_users, declared, ranking:[{editor,count}]}. Cache 5 min.
USERS="$CONTESTSDIR/treino/users"
CACHE="$CONTESTSDIR/treino/var/editor-stats.cache.json"

emit_json 200 OK
# cache válido por 5 min (declarações mudam raramente)
if [[ -f "$CACHE" ]] && [[ -z "$(find "$CACHE" -mmin +5 2>/dev/null)" ]]; then
  cat "$CACHE"; exit 0
fi

set +o noglob
total_users="$(find "$USERS" -mindepth 2 -maxdepth 2 -name account.json 2>/dev/null | wc -l)"
total_users="${total_users//[^0-9]/}"; total_users="${total_users:-0}"

# editor declarado em cada account.json -> contagem por editor (desc). Batch find|xargs.
ranking="$(
  { find "$USERS" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
      | xargs -0 -r jq -r '.favorite_editor // empty' 2>/dev/null \
      | sed '/^$/d' | sort | uniq -c | sort -rn | awk '{printf "%s\t%d\n", $2, $1}'; true; } \
  | jq -R -s 'split("\n") | map(select(length>0) | split("\t") | {editor:.[0], count:(.[1]|tonumber)})'
)"
[[ -n "$ranking" ]] || ranking='[]'
declared="$(jq 'map(.count) | add // 0' <<<"$ranking" 2>/dev/null || echo 0)"

out="$(jq -cn --argjson tu "${total_users:-0}" --argjson d "${declared:-0}" --argjson r "$ranking" \
  '{success:true, total_users:$tu, declared:$d, ranking:$r}')"
printf '%s' "$out" > "$CACHE.tmp" 2>/dev/null && mv -f "$CACHE.tmp" "$CACHE" 2>/dev/null
printf '%s\n' "$out"
