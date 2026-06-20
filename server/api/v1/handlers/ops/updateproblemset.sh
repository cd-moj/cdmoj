# POST /ops/updateproblemset   (Bearer, admin)
# body: {repo}
# Pede aos juízes p/ atualizar o conjunto de problemas (substitui /updateproblemset).
# Best-effort: nc ao master {"cmd":"updateproblemset","repo":<repo>} com timeout;
# indisponível -> enfileira marcador no spool e reporta queued.
require_method POST
require_admin

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
repo="$(jq -r '.repo // empty' <<<"$body")"
[[ -n "$repo" ]] || fail 400 "Missing repo" "repo_missing"

: "${JUDGE_HOST:=localhost}"
: "${JUDGE_PORT:=27000}"

resp=""
if command -v nc >/dev/null 2>&1; then
  req="$(jq -cn --arg r "$repo" '{cmd:"updateproblemset", repo:$r}')"
  resp="$(printf '%s\n' "$req" | nc -w 5 "$JUDGE_HOST" "$JUDGE_PORT" 2>/dev/null)"
fi

if [[ -n "$resp" ]] && jq -e . >/dev/null 2>&1 <<<"$resp"; then
  emit_json 200 OK
  jq -c '{success:true, repo:"'"$repo"'", result:.}' <<<"$resp" 2>/dev/null \
    || jq -cn --arg r "$repo" '{success:true, repo:$r, status:"sent"}'
else
  # master indisponível: deixa marcador no spool p/ processamento posterior
  AGORA="$EPOCHSECONDS"
  ID="$(printf '%s%s%s' "$repo" "$AGORA" "$RANDOM" | md5sum | cut -d' ' -f1)"
  mkdir -p "$SPOOLDIR"
  : > "$SPOOLDIR/_ops:$AGORA:$ID:$SESSION_LOGIN:updateproblemset:$repo"
  ok_json '{action:"updateproblemset", repo:$r, status:"queued"}' --arg r "$repo"
fi
