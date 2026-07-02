# GET /treino/editor-stats -> estatísticas gerais dos editores DECLARADOS pelos
# usuários do treino (campo favorite_editor dos perfis). Público.
# {success, total_users, declared, ranking:[{editor,count}]}. Cache 5 min.
PROFILES="$CONTESTSDIR/treino/var/profiles"
PASSWD="$CONTESTSDIR/treino/passwd"
CACHE="$CONTESTSDIR/treino/var/editor-stats.cache.json"

emit_json 200 OK
# cache válido por 5 min (declarações mudam raramente)
if [[ -f "$CACHE" ]] && [[ -z "$(find "$CACHE" -mmin +5 2>/dev/null)" ]]; then
  cat "$CACHE"; exit 0
fi

set +o noglob
total_users=0
# grep -c imprime e sai 1 sem match — capturar direto (sem `|| echo`) e sanear a dígitos.
[[ -f "$PASSWD" ]] && total_users="$(grep -cve '^[[:space:]]*$' "$PASSWD" 2>/dev/null)"
total_users="${total_users//[^0-9]/}"; total_users="${total_users:-0}"

# editor declarado de cada perfil -> contagem por editor (desc).
ranking="$(
  { compgen -G "$PROFILES/*.json" >/dev/null 2>&1 \
      && jq -r '.favorite_editor // empty' "$PROFILES"/*.json 2>/dev/null \
         | sed '/^$/d' | sort | uniq -c | sort -rn | awk '{printf "%s\t%d\n", $2, $1}'; true; } \
  | jq -R -s 'split("\n") | map(select(length>0) | split("\t") | {editor:.[0], count:(.[1]|tonumber)})'
)"
[[ -n "$ranking" ]] || ranking='[]'
declared="$(jq 'map(.count) | add // 0' <<<"$ranking" 2>/dev/null || echo 0)"

out="$(jq -cn --argjson tu "${total_users:-0}" --argjson d "${declared:-0}" --argjson r "$ranking" \
  '{success:true, total_users:$tu, declared:$d, ranking:$r}')"
printf '%s' "$out" > "$CACHE.tmp" 2>/dev/null && mv -f "$CACHE.tmp" "$CACHE" 2>/dev/null
printf '%s\n' "$out"
