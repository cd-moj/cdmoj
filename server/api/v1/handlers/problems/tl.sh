# GET /problems/tl?id=<id>  (Bearer) -> time_limits ao vivo do problema (store dos juízes) +
# staleness EXATA (recomputa o checksum do pacote AGORA). Espelha /ops/problemtl, mas o acesso é
# membro da org OU público (require_problem_view: 404 se privado e não autorizado), não .admin.
# Ao contrário do /problems/status (stale vem do índice, ≤30 min de atraso), aqui o hash é feito na
# hora — p/ 1 problema — quando se quer o valor fresco/exato.
# Quando PRECISA RECALIBRAR, explica o PORQUÊ: `calibrated_at` (quando calibrou), `reason`
# (checksum velho→novo) e — como cada problema é um repo git — `changes` = os COMMITS desde a
# calibração que tocaram os caminhos que afetam o TL (conf, tests/input, sols/good, scripts —
# exatamente o que o tl-checksum.sh cobre) + `changed_files` (união dos arquivos tocados).
require_method GET
require_auth
source "$_DIR/lib/problems.sh"
source "$_DIR/lib/tl-store.sh"

id="$(param id)"
[[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
require_problem_view "$id"

pdir="$(pkg_path "$id")"
cur="$(pkg_tl_checksum "$pdir")"
store="$(tl_store_get "$id")"
cal="$(jq -r '.checksum // ""' <<<"$store")"
calat="$(jq -r '.updated_at // 0' <<<"$store")"; [[ "$calat" =~ ^[0-9]+$ ]] || calat=0
nhosts="$(jq -r '(.hosts // {}) | length' <<<"$store")"; nhosts="${nhosts//[^0-9]/}"; nhosts="${nhosts:-0}"

changes='[]'; chfiles='[]'; reason=""
if [[ "$nhosts" -gt 0 && -n "$cal" && "$cal" != "$cur" && "$calat" -gt 0 && -d "$pdir/.git" ]]; then
  # commits desde a calibração que tocaram caminhos que AFETAM o TL (paths fixos, nunca input)
  tsv="$(mktemp)"; trap 'rm -f "$tsv" "$tsv.f"' EXIT
  git -C "$pdir" log --since="@$calat" --format="%H%x1f%at%x1f%an%x1f%s" -n 20 \
      -- conf tests/input sols/good scripts 2>/dev/null | tr -d '\r' > "$tsv"
  changes="$(jq -R -s -c 'split("\n") | map(select(length>0) | split("\u001f")
      | {sha:(.[0] // ""), at:(.[1]|tonumber? // 0), author:(.[2] // ""), subject:(.[3] // "")})' \
      < "$tsv" 2>/dev/null)"
  [[ -n "$changes" ]] || changes='[]'
  git -C "$pdir" log --since="@$calat" --name-only --format= \
      -- conf tests/input sols/good scripts 2>/dev/null \
    | grep -v '^$' | LC_ALL=C sort -u | head -30 > "$tsv.f"
  chfiles="$(jq -R -s -c 'split("\n") | map(select(length>0))' < "$tsv.f" 2>/dev/null)"
  [[ -n "$chfiles" ]] || chfiles='[]'
  reason="pacote mudou desde a calibração (checksum ${cal:0:8} -> ${cur:0:8})"
fi

# há calibração ENFILEIRADA/em execução p/ este problema AGORA? (mesma fonte do painel:
# run/updates/{pending,inprogress} + run/commands por kind/action==calibrate). Distingue
# "store de TL vazio porque acabou de enfileirar" de "calibrou e não obteve TL" — o `moj check`
# usa isto p/ não gritar "falhou em TODAS as máquinas" enquanto o juiz nem rodou.
calibrating="$(calibrating_set 2>/dev/null)"; [[ -n "$calibrating" ]] || calibrating='[]'

body="$(jq -cn --arg p "$id" --arg cks "$cur" \
   --argjson tl "$(tl_store_served_for "$id" "$cur")" \
   --argjson store "$store" --argjson calibrating "$calibrating" \
   --arg reason "$reason" --argjson changes "$changes" --argjson chfiles "$chfiles" '
   ($store.checksum // "") as $cal
   | (($store.hosts // {}) | length > 0) as $calibrated
   | ($calibrated and $cal != $cks and $cal != "") as $recal
   | {success:true, problem:$p, checksum:$cks, time_limits:$tl,
      calibrated_checksum:$cal, hosts:($store.hosts // {}),
      updated_at:($store.updated_at // null), calibrated_at:($store.updated_at // null),
      calibrated:$calibrated,
      being_calibrated:(($calibrating | index($p)) != null),
      stale:($cal != $cks and $cal != ""),
      needs_recalibration:$recal}
   + (if $recal then {reason:$reason, changes:$changes, changed_files:$chfiles} else {} end)')"
[[ -n "$body" ]] || fail 500 "Falha ao montar a resposta" "tl_fail"
emit_json 200 OK
printf '%s' "$body"
