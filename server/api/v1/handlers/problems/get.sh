# GET /problems/get?id=<id>   (Bearer)
# Detalhe de um problema: metadados do índice + relatório de validação + enunciado HTML
# (do índice público do treino, quando houver) com tl/tags.
require_method GET
require_auth
source "$_DIR/lib/problems.sh"
source "$_DIR/lib/tl-store.sh"
id="$(param id)"
[[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
require_problem_view "$id"   # privado só p/ dono/colaborador (corta na API; não revela a existência)
base="$(owners_merged | jq -c --arg id "$id" 'first(.problems[]|select(.id==$id)) // empty' 2>/dev/null)"
[[ -n "$base" ]] || base="$(jq -cn --arg id "$id" '{id:$id, unknown:true}')"

vf="$RUNDIR/validation/$id.json"; val='null'; [[ -f "$vf" ]] && val="$(cat "$vf" 2>/dev/null)"
[[ -n "$val" ]] || val='null'

# ⚠ O TL vem do PACOTE, não do json servível. Duas razões, e as duas mordiam o autor:
#   (a) o json servível **público** (`var/jsons/`) só existe depois de publicar — em problema
#       PRIVADO, que é o estado normal de quem está calibrando, o `time_limits` sumia e o editor
#       caía num fallback client-side que mostra o MÁXIMO CRU entre juízes. A coluna em negrito
#       "o tempo-limite que o estudante vê no enunciado" exibia o calibrado, ignorando o override;
#   (b) `/problems/edit` e `/problems/upload` NÃO reindexam: salvar o conf com TLOVERRIDE novo não
#       regenera o json, então mesmo problema público mostrava número velho até validar/publicar.
# `tl_store_served` lê o conf do pacote (por grep, nunca source) e aplica o override — é a mesma
# função do /contest/problems. Rota de GESTÃO de UM problema: a fronteira "não abrir pacote no
# request" é do contest/treino, não daqui. E o checksum vem MATERIALIZADO do índice, então não há
# tl-checksum (que lê tests/*) por requisição.
cks="$(tl_index_checksums "$id" 2>/dev/null | cut -f2)"
tlcal="$(tl_store_served_for "$id" "$cks" 2>/dev/null)"; [[ -n "$tlcal" ]] || tlcal='{}'
ov="$(tl_conf_overrides "$(pkg_path "$id")" 2>/dev/null)"; [[ -n "$ov" ]] || ov='{}'
tleff="$(tl_override_apply "$tlcal" "$ov")"; [[ -n "$tleff" ]] || tleff='{}'

# o enunciado/tags continuam vindo do json servível — com fallback p/ o privado (mesmo padrão de
# contest/problems.sh e lib/langs.sh: o gen grava sempre em jsons-private/ e só COPIA p/ jsons/
# quando o problema é público).
jf="$CONTESTSDIR/treino/var/jsons/$id.json"
[[ -f "$jf" ]] || jf="$CONTESTSDIR/treino/var/jsons-private/$id.json"
emit_json 200 OK
if [[ -f "$jf" ]]; then
  jq -c --argjson base "$base" --argjson val "$val" --argjson tl "$tleff" \
        --argjson tlc "$tlcal" --argjson ov "$ov" '
    {success:true} + $base
    + { validation:$val,
        statement_html_b64:(.statement_html_b64 // null),
        time_limits:$tl, time_limits_calibrated:$tlc, tl_override:$ov,
        tags:(.tags // []) }' "$jf" 2>/dev/null
else
  jq -cn --argjson base "$base" --argjson val "$val" --argjson tl "$tleff" \
         --argjson tlc "$tlcal" --argjson ov "$ov" \
    '{success:true} + $base + {validation:$val, time_limits:$tl,
                               time_limits_calibrated:$tlc, tl_override:$ov}'
fi
