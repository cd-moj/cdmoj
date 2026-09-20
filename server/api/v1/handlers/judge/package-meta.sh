# GET /judge/package-meta?id=<id>   (Bearer mojw_<token>) -> {id, exists, checksum, tl_checksum}
# O juiz compara `checksum` com o que tem em cache e decide se BAIXA o pacote de novo e RECALIBRA.
# ⚠ `checksum` é a VERSÃO DO PACOTE (pkg_judge_version: inclui `sols/` INTEIRO), não o tl_checksum:
# mexer numa solução `pass|slow|wrong` não mudava a chave estreita e o juiz recalibrava o cache
# velho (relato do Arthur Botelho, 2026-09-20). O agente trata o valor como opaco, então a troca
# vale sem mexer no repo `judge/`. `tl_checksum` (estreito) vai junto, p/ diagnóstico. Sem tar.
require_method GET
require_worker
source "$_DIR/lib/tl-store.sh"

id="$(param id)"; [[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
pkg="$(pkg_path "$id")"
if [[ -n "$pkg" ]]; then
  ok_json '{id:$id, exists:true, checksum:$v, tl_checksum:$c}' --arg id "$id" \
    --arg v "$(pkg_judge_version "$pkg" "$id")" --arg c "$(pkg_tl_checksum "$pkg" "$id")"
else
  ok_json '{id:$id, exists:false, checksum:"", tl_checksum:""}' --arg id "$id"
fi
