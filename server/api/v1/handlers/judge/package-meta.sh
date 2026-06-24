# GET /judge/package-meta?id=<id>   (Bearer mojw_<token>) -> {id, exists, checksum}
# Barato (só o checksum dos arquivos que afetam o TL): o juiz compara com o que tem em
# cache e decide se BAIXA o pacote de novo e RECALIBRA. Sem stream do tar.
require_method GET
require_worker
source "$_DIR/lib/tl-store.sh"

id="$(param id)"; [[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
pkg="$(pkg_path "$id")"
if [[ -n "$pkg" ]]; then
  ok_json '{id:$id, exists:true, checksum:$c}' --arg id "$id" --arg c "$(pkg_tl_checksum "$pkg")"
else
  ok_json '{id:$id, exists:false, checksum:""}' --arg id "$id"
fi
