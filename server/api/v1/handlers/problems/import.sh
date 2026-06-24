# POST /problems/import   (Bearer)   body: {repo, prob?, tar_b64}
# Importa um pacote ICPC/Kattis -> converte p/ pacote MOJ -> cria o problema no diretório do
# autor (commit+push). Exige permissão de criação (mesma regra de criar contest).
require_method POST
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"; source "$MOJTOOLS_DIR/git-broker.sh"
source "$_DIR/lib/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar problemas" "create_forbidden"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
repo="$(jq -r '.repo // empty' <<<"$body")"
[[ "$repo" =~ ^[a-z0-9][a-z0-9._-]{1,63}$ ]] || fail 400 "Diretório inválido" "repo_invalid"
owner="$(repo_owner "$repo")"; [[ -n "$owner" ]] || fail 404 "Diretório não existe (crie com repo-create)" "repo_missing"
gitea_can_write "$owner" "$repo" "$SESSION_LOGIN" || fail 403 "Sem permissão de escrita" "forbidden"

tarf="$(mktemp)"; mojpkg="$(mktemp -d)"; tmp=""
trap 'rm -rf "$tarf" "$mojpkg" "$tmp"' EXIT
jq -r '.tar_b64 // ""' <<<"$body" | base64 -d > "$tarf" 2>/dev/null
[[ -s "$tarf" ]] || fail 400 "Pacote vazio/ inválido" "tar_empty"
tar -tf "$tarf" 2>/dev/null | grep -qE '(^/|(^|/)\.\.(/|$))' && fail 400 "Pacote com caminho inseguro" "unsafe"

# converte Kattis -> MOJ
bash "$MOJTOOLS_DIR/kattis/import.sh" "$tarf" "$mojpkg/pkg" >"$mojpkg/log" 2>&1 \
  || fail 422 "Falha ao importar ICPC: $(tail -1 "$mojpkg/log" 2>/dev/null)" "import_fail"
[[ -d "$mojpkg/pkg/docs" || -d "$mojpkg/pkg/tests" ]] || fail 422 "Pacote ICPC sem conteúdo aproveitável" "import_empty"

# nome do problema: do body, senão slug do display_title, senão do uuid
prob="$(jq -r '.prob // empty' <<<"$body")"
if [[ -z "$prob" ]]; then
  prob="$(jq -r '.display_title // ""' "$mojpkg/pkg/.moj-meta.json" 2>/dev/null | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/-\+/-/g; s/^-//; s/-$//')"
  [[ "$prob" =~ ^[a-z0-9] ]] || prob="kattis-$(jq -r '.uuid // "x"' "$mojpkg/pkg/.kattis.json" 2>/dev/null | tr -cd 'a-f0-9' | cut -c1-8)"
fi
[[ "$prob" =~ ^[a-z0-9][a-z0-9._-]{1,80}$ ]] || fail 400 "Nome de problema inválido (passe prob)" "prob_invalid"
title="$(jq -r '.display_title // ""' "$mojpkg/pkg/.moj-meta.json" 2>/dev/null)"

tmp="$(git_broker_open "$SESSION_LOGIN" "$owner" "$repo")" || fail 502 "Falha ao abrir o repositório" "git_open"
wt="$tmp/wt"; [[ -e "$wt/$prob" ]] && fail 409 "Problema já existe nesse diretório" "prob_exists"
mkdir -p "$wt/$prob"; cp -a "$mojpkg/pkg/." "$wt/$prob/"
write_meta "$wt/$prob" "$owner" "$repo" false "$(jq -c --arg r "$repo" '[$r]' <<<'{}')" "$title"

sha="$(git_broker_commit_push "$SESSION_LOGIN" "$owner" "$repo" "$wt" "import ICPC: $prob")" \
  || fail 502 "Falha ao enviar (push)" "git_push"
author_txt="$(head -1 "$wt/$prob/author" 2>/dev/null)"
authored_upsert "$repo#$prob" "$owner" "$repo" "$prob" "$title" false "$(jq -cn --arg r "$repo" '[$r]')" "$author_txt" "$(repo_collabs "$repo")"
audit_log "import-kattis" "id=$repo#$prob by=$SESSION_LOGIN"
ok_json '{action:"import", id:$id, prob:$p, sha:$s, source:"icpc/kattis"}' \
  --arg id "$repo#$prob" --arg p "$prob" --arg s "${sha:0:12}"
