# GET /treino/virtual/doc?contest=<cid>&type=<contest|info-sheet|times|editorial>&lang=<pt|en|es>   (Bearer do TREINO)
# O PDF de um documento PUBLICADO do contest para quem faz o virtual (10/11/2026), pela regra do /treino/virtual/docs:
# desde a largada, e o EDITORIAL só com a run terminada. Não publicado, sem PDF, ou editorial antes da hora = 404 (o
# mesmo corpo). Só PDF: o HTML/ODT gerados são da organização (/contest/doc).
require_method GET
require_auth_contest treino
source "$_LIBDIR/virtual.sh"
source "$_LIBDIR/contest-docs.sh"
cid="$(param contest)"; vr_gate "$cid"
vr_clock "$SESSION_LOGIN" "$cid" || fail 403 "Comece a participação virtual para ver os arquivos" "virtual_not_started"
t="$(param type)"; l="$(param lang)"
case "$t" in info-sheet|contest|times|editorial) ;; *) fail 400 "type inválido" "type_invalid";; esac
doc_lang_ok "$l" || fail 400 "lang deve ser um de: $DOC_LANGS" "lang_invalid"
[[ "$t" == editorial ]] && (( ! VR_ENDED )) && fail 404 "Documento não disponível" "not_available"
doc_conf_get "$cid" | jq -e --arg k "$t.$l" '((.published // []) | index($k)) != null' >/dev/null 2>&1 \
  || fail 404 "Documento não disponível" "not_available"
file="$(doc_pdf_served "$cid" "$t" "$l")"
[[ -n "$file" && -s "$file" ]] || fail 404 "Documento não disponível" "not_available"
printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/pdf\r\n'
printf 'Content-Disposition: inline; filename="%s"\r\n' "$cid-$t.$l.pdf"
printf 'Content-Length: %s\r\n' "$(stat -c%s "$file" 2>/dev/null || echo 0)"
printf '\r\n'
cat "$file"
