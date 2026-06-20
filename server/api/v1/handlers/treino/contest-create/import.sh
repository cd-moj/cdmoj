# POST /treino/contest-create/import  (auth treino, pode criar) {tar_b64}
# Importa um contest a partir de um .tar.gz (base64) contendo contest.json + enunciados/ opcional.
# Extração defensiva: rejeita caminhos absolutos e "..".
require_method POST
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
tarb64="$(jq -r '.tar_b64 // empty' <<<"$body")"
[[ -n "$tarb64" ]] || fail 400 "Envie tar_b64 (tar.gz em base64)" "missing_tar"
tarb64="${tarb64#data:*;base64,}"
(( ${#tarb64} <= 30000000 )) || fail 413 "Arquivo muito grande (máx ~22MB)" "tar_large"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf '%s' "$tarb64" | base64 -d > "$tmp/c.tgz" 2>/dev/null || fail 400 "base64 inválido" "tar_b64"
tar -tzf "$tmp/c.tgz" >/dev/null 2>&1 || fail 400 "Não é um tar.gz válido" "tar_bad"
while IFS= read -r m; do
  [[ -z "$m" ]] && continue
  [[ "$m" == /* ]] && fail 400 "tar com caminho absoluto" "tar_abs"
  case "$m" in *..*) fail 400 "tar com '..'" "tar_dotdot";; esac
done < <(tar -tzf "$tmp/c.tgz")
mkdir -p "$tmp/x"
tar --no-same-owner --no-same-permissions -xzf "$tmp/c.tgz" -C "$tmp/x" 2>/dev/null || fail 400 "Falha ao extrair" "tar_extract"

spec_file="$(find "$tmp/x" -maxdepth 2 -name contest.json -type f 2>/dev/null | head -1)"
[[ -n "$spec_file" ]] || fail 422 "tar sem contest.json" "no_spec"
base="$(dirname "$spec_file")"
spec="$(cat "$spec_file")"
jq -e . >/dev/null 2>&1 <<<"$spec" || fail 422 "contest.json inválido" "spec_bad"
cc_create "$spec" "$SESSION_LOGIN" "$SESSION_NAME" "$base/enunciados"
audit_log contest-create "import id=$(jq -r '.contest_id' <<<"$CC_RESULT")"
ok_json '$r' --argjson r "$CC_RESULT"
