# GET /submission/source?contest=<id>&id=<hash>[&time=<epoch>]   (Bearer) -> TXT
# Localiza o fonte pelo HASH da submissão (chave única), aceitando os dois padrões de
# nome: legado "<time>:<hash>-<login>-<prob>.<ext>" e novo "<hash>-<login>-<prob>.<ext>".
# Visível se: dono da submissão, OU admin/judge, OU SHOWCODE=1.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

sid="$(param id)"
[[ -n "$sid" ]] || fail 400 "Missing submission id" "id_missing"
[[ "$sid" =~ ^[0-9a-f]{32}$ || "$sid" =~ ^[0-9a-f-]{36}$ ]] \
  || fail 400 "Invalid submission id" "id_invalid"

set +o noglob; shopt -s nullglob
files=("$CONTESTSDIR/$contest/submissions/"*"$sid"*)
shopt -u nullglob
(( ${#files[@]} > 0 )) || fail 404 "Submission source not found" "source_notfound"
src="${files[0]}"

# dono: tudo depois de "<hash>-" é "<login>-<prob>.<ext>"
base="${src##*/}"; after="${base#*"$sid"-}"; owner="${after%%-*}"

SHOWCODE=0
load_contest_conf "$contest"
if [[ "$owner" != "$SESSION_LOGIN" ]] && ! is_judge && [[ "${SHOWCODE:-0}" != 1 ]]; then
  fail 403 "Source not visible" "source_forbidden"
fi

emit_text
# Defensivo: algumas submissões legadas foram arquivadas como o JSON da submissão
# ({problem_id,filename,code_b64,...}) em vez do fonte. Se for esse o caso, decodifica.
if jq -e 'type=="object" and has("code_b64")' < "$src" >/dev/null 2>&1; then
  jq -r '.code_b64 // ""' < "$src" | base64 -d 2>/dev/null
else
  cat "$src"
fi
