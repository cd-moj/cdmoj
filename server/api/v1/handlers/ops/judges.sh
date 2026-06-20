# GET /ops/judges   (Bearer, admin) -> JSON
# Status/specs das máquinas de julgamento (substitui /reportmachine|/listjudgesmachine).
# Best-effort: tenta nc ao master em localhost:27000 com {"cmd":"reportmachine"} e
# timeout curto; se indisponível, devolve lista vazia (sem erro).
require_admin

: "${JUDGE_HOST:=localhost}"
: "${JUDGE_PORT:=27000}"

emit_json 200 OK
resp=""
if command -v nc >/dev/null 2>&1; then
  resp="$(printf '{"cmd":"reportmachine"}\n' \
          | nc -w 2 "$JUDGE_HOST" "$JUDGE_PORT" 2>/dev/null)"
fi

if [[ -n "$resp" ]] && jq -e . >/dev/null 2>&1 <<<"$resp"; then
  # repassa a resposta do master sob {success:true, judges:...}
  jq -c '{success:true, judges:.}' <<<"$resp"
else
  jq -cn '{success:true, judges:[]}'
fi
