# POST /problems/webhook   (Gitea -> MOJ; SEM Bearer; autenticado por HMAC X-Gitea-Signature)
# Em cada push num diretório (repo Gitea), enfileira validação+index dos problemas alterados
# (1 juiz pega no heartbeat) e mantém o registro de diretórios. Fecha o laço: editou/migrou,
# o treino reindexa sozinho.
require_method POST
source "$_DIR/lib/problems.sh"; source "$_DIR/../../judge-gw/sched-lib.sh"; source "$_DIR/lib/tl-store.sh"
: "${GITEA_WEBHOOK_SECRET_FILE:=$RUNDIR/secrets/gitea-webhook.secret}"

body="$(read_body)"
secret="$(cat "$GITEA_WEBHOOK_SECRET_FILE" 2>/dev/null)"
sig="${HTTP_X_GITEA_SIGNATURE:-}"
calc="$(printf '%s' "$body" | openssl dgst -sha256 -hmac "$secret" 2>/dev/null | awk '{print $NF}')"
[[ -n "$secret" && -n "$sig" && "$sig" == "$calc" ]] || fail 401 "Assinatura inválida" "hmac_invalid"

event="${HTTP_X_GITEA_EVENT:-push}"
if [[ "$event" != push ]]; then ok_json '{ignored:true, event:$e}' --arg e "$event"; return 2>/dev/null || exit 0; fi
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"

repo="$(jq -r '.repository.name // empty' <<<"$body")"
owner="$(jq -r '.repository.owner.login // .repository.owner.username // empty' <<<"$body")"
[[ "$repo" =~ ^[a-z0-9][a-z0-9._-]{1,63}$ ]] || fail 400 "repo inválido" "repo_invalid"

# garante o registro do diretório (dono do payload) p/ a UI/CLI
[[ -n "$(repo_owner "$repo")" ]] || { [[ "$owner" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && repo_register "$repo" "$owner" "$repo"; }

# modelo cache: atualiza o store do SERVIDOR (o juiz não clona mais) — best-effort.
[[ -d "$MOJ_PROBLEMS_DIR/$repo/.git" ]] && ( cd "$MOJ_PROBLEMS_DIR/$repo" && git pull --recurse-submodules ) >/dev/null 2>&1 || true

# problemas alterados = 1º segmento dos paths tocados (ignora arquivos na raiz):
# (re)indexa NO SERVIDOR (HTML/var-jsons) e pede CALIBRAÇÃO a um juiz (o checksum mudou).
n=0
while IFS= read -r prob; do
  [[ "$prob" =~ ^[a-z0-9][a-z0-9._-]{0,80}$ ]] || continue
  index_problem_bg "$repo#$prob" 1                      # portão estático + index (servidor)
  cal_request "$repo" "$repo#$prob" "webhook" >/dev/null; n=$((n+1))
done < <(jq -r '[.commits[]? | (.added[]?, .modified[]?, .removed[]?)] | map(select(contains("/")) | split("/")[0]) | unique[]' <<<"$body" 2>/dev/null)

# força regen do índice de donos no próximo acesso
[[ -f "$OWNERS_INDEX" ]] && touch -d '1970-01-01' "$OWNERS_INDEX" 2>/dev/null
audit_log "webhook" "repo=$repo owner=$owner queued=$n"
ok_json '{repo:$r, owner:$o, queued:$n}' --arg r "$repo" --arg o "$owner" --argjson n "$n"
