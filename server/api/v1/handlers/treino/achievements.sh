# GET /treino/achievements -> registro de CONQUISTAS do perfil (anônimo).
# Serve contests/treino/var/achievements.json (gerido pela aba 🏅 do admin) quando VÁLIDO;
# ausente/corrompido cai no default embarcado lib/achievements-default.json. As conquistas
# são avaliadas no CLIENTE (web/treino/stat/stat.js) — formato e kinds: docs/PERFIL.md.
F="$CONTESTSDIR/treino/var/achievements.json"
DEF="$_DIR/lib/achievements-default.json"

src="$DEF"; custom=false
if [[ -s "$F" ]] && jq -e '.achievements | type == "array"' "$F" >/dev/null 2>&1; then
  src="$F"; custom=true
fi

# corpo ANTES do cabeçalho (falha ainda pode virar 500)
body="$(jq -c --argjson cust "$custom" \
  '{success:true, custom:$cust, version:(.version // 1), achievements:(.achievements // [])}' \
  "$src" 2>/dev/null)"
[[ -n "$body" ]] || fail 500 "Falha ao ler o registro de conquistas" "achievements_read"

emit_json 200 OK
printf '%s\n' "$body"
