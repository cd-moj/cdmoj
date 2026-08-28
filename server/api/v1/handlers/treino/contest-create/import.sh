# POST /treino/contest-create/import  (auth treino, pode criar) {tar_b64}
# Importa um contest a partir de um .tar.gz (base64) contendo contest.json + enunciados/ opcional.
# Extração defensiva: rejeita caminhos absolutos e "..".
# ⚠ O corpo tem MUITOS MB: vai para ARQUIVO e o base64 sai por STREAM — nunca por variável.
# A versão antiga fazia `${var#data:*;base64,}` sobre a string inteira, que no bash é O(n²)
# (~4,2 s/MB² no locale C): os 5,2 MB de um caso real custaram ~2 min de CPU em máquina
# ociosa e ~10 min sob carga, com o nginx desistindo aos 300 s e o bash seguindo preso em R
# (incidente de 28/08/2026, autor bloqueado na véspera da Maratona).
require_method POST
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat - > "$tmp/body"                       # o teto vem ANTES de qualquer parse
(( $(stat -c %s "$tmp/body") <= 32000000 )) || fail 413 "Arquivo muito grande (máx ~22MB)" "tar_large"
jq -e . >/dev/null 2>&1 < "$tmp/body" || fail 400 "JSON inválido" "bad_json"
jq -r '.tar_b64 // empty' < "$tmp/body" > "$tmp/b64"
[[ -s "$tmp/b64" ]] || fail 400 "Envie tar_b64 (tar.gz em base64)" "missing_tar"
# o prefixo data:...;base64, (quando vem de FileReader) sai no stream — sed é O(n)
sed -e '1s/^data:[^;]*;base64,//' "$tmp/b64" | base64 -d > "$tmp/c.tgz" 2>/dev/null \
  || fail 400 "base64 inválido" "tar_b64"
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
