# POST /problems/import   (Bearer)   body: {repo(=org), prob?, tar_b64}
# Importa um pacote ICPC/Kattis -> converte p/ pacote MOJ -> cria o problema na ORG (commit LOCAL).
# Exige permissão de criação (mesma regra de criar contest) + ser membro da org.
require_method POST
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"; source "$_DIR/lib/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar problemas" "create_forbidden"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
org="$(jq -r '.repo // .org // empty' <<<"$body")"
[[ "$org" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$ ]] || fail 400 "Org inválida" "org_invalid"
[[ "$org" == "$SESSION_LOGIN" ]] && ensure_implicit_org "$SESSION_LOGIN"
org_exists "$org" || fail 404 "Org não existe (crie com /orgs/create)" "org_missing"
org_is_member "$org" "$SESSION_LOGIN" || fail 403 "Você não é membro dessa org" "forbidden"

tarf="$(mktemp)"; mojpkg="$(mktemp -d)"
trap 'rm -rf "$tarf" "$mojpkg"' EXIT
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
id="$org#$prob"; pdir="$MOJ_PROBLEMS_DIR/$org/$prob"
[[ -e "$pdir" ]] && fail 409 "Problema já existe nessa org" "prob_exists"
mkdir -p "$pdir"; cp -a "$mojpkg/pkg/." "$pdir/"
write_meta "$pdir" "$SESSION_LOGIN" "$org" false "$(jq -cn --arg r "$org" '[$r]')" "$title"

sha="$(problem_commit "$pdir" "$SESSION_LOGIN" "import ICPC: $prob")"
author_txt="$(head -1 "$pdir/author" 2>/dev/null)"
authored_upsert "$id" "$SESSION_LOGIN" "$org" "$prob" "$title" false "$(jq -cn --arg r "$org" '[$r]')" "$author_txt" '[]'
audit_log "import-kattis" "id=$id by=$SESSION_LOGIN"
ok_json '{action:"import", id:$id, prob:$p, sha:$s, source:"icpc/kattis"}' \
  --arg id "$id" --arg p "$prob" --arg s "${sha:0:12}"
