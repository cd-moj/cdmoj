# GET /judge/package?id=<id>   (Bearer mojw_<token>)
# Devolve o PACOTE do problema (.tar.gz) p/ o juiz CACHEAR localmente — substitui o
# clone do repositório inteiro. Inclui as soluções (o juiz calibra). O header
# X-Moj-Checksum traz o checksum dos arquivos que afetam o TL: o juiz guarda-o junto do
# tl que calibrou e recalibra quando ele muda. Fonte: MOJ_PROBLEMS_DIR (store do
# servidor). NÃO embute tl/tl.<host> (cada juiz calibra o seu).
require_method GET
require_worker
source "$_DIR/lib/tl-store.sh"

id="$(param id)"; [[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
prob="${id##*#}"; [[ "$prob" != "$id" ]] || fail 400 "Id sem '#'" "id_invalid"
pkg="$(pkg_path "$id")"; [[ -n "$pkg" ]] || fail 404 "Pacote não encontrado" "not_found"

cks="$(pkg_tl_checksum "$pkg")"
fn="$(printf '%s' "$prob" | tr -cd 'A-Za-z0-9._-')"; [[ -n "$fn" ]] || fn=problema
printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/gzip\r\n'
printf 'X-Moj-Checksum: %s\r\n' "$cks"
printf 'Content-Disposition: attachment; filename="%s.tar.gz"\r\n' "$fn"
printf '\r\n'
tar -czf - -C "$(dirname "$pkg")" --exclude='.git' --exclude='tl' --exclude='tl.*' \
    "$(basename "$pkg")" 2>/dev/null
