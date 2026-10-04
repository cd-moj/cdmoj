# GET/POST /contest/admin/regions?contest=<id>   (admin DO contest; GET também p/ o juiz-chefe)
# As SEDES pela regra única (lib/regions.sh): a árvore, a sede de cada login e a prévia do que muda.
#   GET                 -> {tree, sig, mode, summary}   summary = rg_summary (contagens, membros por nó,
#                          órfãs, quem parou no pai, quem ficou sem sede)
#   GET ?login=<l>      -> {login, site:{i,name}|null, flag, nodes:[{i,name,view}]}   (quem é/onde está)
#   GET ?map=1          -> {map:[{login, site, flag}]}  (site = nome ou null; flag x|o|r|p|-)
#   POST {tree?, assign?:[{login, region}], mode?, dry_run?, expect_sig?}
#       tree       — a árvore INTEIRA (null/[] = sem sedes). Forma + regex no subconjunto seguro, senão 422
#                    regions_invalid com error.nodes;
#       assign     — sede GRAVADA por login ("" tira). Inscrito vai no ROSTER (sobrevive ao materialize),
#                    conta no account.json, compartilhado só com dir ganha overlay; membro de time = o time;
#       mode       — simple|rules|tree: o modo do painel (REGIONS_MODE no conf; só dica p/ a interface);
#       dry_run    — true: a PRÉVIA com a árvore/atribuições propostas, nada é gravado;
#       expect_sig — o `sig` que a tela leu: a árvore mudou desde então = 409 regions_changed;
#       renames    — [{from, to}] sedes RENOMEADAS na tela: o escopo do staff (`region:`), o `by_region` do gate
#                    e as sedes do Animeitor acompanham (rg_ref_rename; 03/10/2026).
#   -> {saved|dry_run, sig, summary, assigned:[{login,target}], failed:[{login,code}], refs_renamed,
#       orphan_refs:[{where:staff|ua_gate|animeitor, name, login?}]}  (referência a sede que não existe mais)
require_auth_contest "$(param contest)"
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
source "$_LIBDIR/regions.sh"
source "$_LIBDIR/contest-create.sh"
cdir="$CONTESTSDIR/$contest"

if [[ "${REQUEST_METHOD:-GET}" != POST ]]; then
  is_admin || is_chief || fail 403 "Apenas o admin do contest" "admin_required"
  m="$(rg_map "$contest")" || fail 500 "Falha ao montar o mapa de sedes" "regions_map_failed"
  n="$CONTESTSDIR/$contest/var/regions-nodes.json"
  who="$(param login)"
  if [[ -n "$who" ]]; then
    valid_id "$who" || fail 400 "Login inválido" "login_invalid"
    row="$(gawk -F'\t' -v l="$who" '$1 == l { print; exit }' "$m")"
    [[ -n "$row" ]] || fail 404 "Login fora do contest (ou conta de papel)" "login_not_in_contest"
    IFS=$'\t' read -r _ s ns fl <<<"$row"
    ok_json_slurp '{login:$l, flag:$f,
                    site:(if ($s | tonumber) >= 0 then {i:($s | tonumber), name:$n[0][$s | tonumber].name} else null end),
                    nodes:[($ns | split(",")[] | select(length > 0) | tonumber) as $i | {i:$i, name:$n[0][$i].name, view:$n[0][$i].view}]}' \
      n "$(cat "$n")" --arg l "$who" --arg s "$s" --arg ns "$ns" --arg f "$fl"
    exit 0
  fi
  W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
  if [[ "$(param map)" == 1 ]]; then
    jq -Rn --slurpfile n "$n" '[inputs | split("\t") | {login:.[0], flag:.[3],
        site:((.[1] | tonumber) as $s | if $s >= 0 then $n[0][$s].name else null end)}]' "$m" > "$W/map.json"
    ok_json_slurp '{map:$m[0]}' m "$(cat "$W/map.json")"
    exit 0
  fi
  rg_summary "$n" "$m" > "$W/sum.json"
  if [[ -s "$cdir/regions.json" ]]; then cp "$cdir/regions.json" "$W/tree.json"; else printf '[]' > "$W/tree.json"; fi
  ok_json_slurp '{tree:$t[0], sig:$sig, mode:$mode, summary:$sm[0]}' t "$(cat "$W/tree.json")" \
    --slurpfile sm "$W/sum.json" --arg sig "$(rg_sig "$contest")" --arg mode "$(conf_value "$contest" REGIONS_MODE)"
  exit 0
fi

# --- POST ----------------------------------------------------------------------------------------------
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
body="$(read_body)"
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
dry="$(jq -r 'if .dry_run == true then 1 else 0 end' <<<"$body")"
mode="$(jq -r '.mode // empty' <<<"$body")"
[[ -z "$mode" || "$mode" =~ ^(simple|rules|tree)$ ]] || fail 422 "Modo inválido (simple|rules|tree)" "mode_invalid"
has_tree=0
if jq -e 'has("tree")' >/dev/null 2>&1 <<<"$body"; then
  has_tree=1
  jq -c '.tree | if . == null then [] else . end' <<<"$body" > "$W/tree.json"
  [[ "$(cat "$W/tree.json")" == "[]" ]] || cc_regions_ok "$(cat "$W/tree.json")" || cc_regions_fail
fi
jq -e '(.assign // []) | type == "array" and all(.[]; type == "object" and ((.login // "") | type) == "string"
        and (((.region // "") | type) == "string"))' >/dev/null 2>&1 <<<"$body" \
  || fail 422 "assign = lista de {login, region}" "assign_invalid"
jq -r '(.assign // [])[] | [.login, (.region // "")] | map(gsub("[\t\n\r]"; " ")) | join("\t")' <<<"$body" > "$W/assign.tsv"
(( $(wc -l < "$W/assign.tsv") <= 5000 )) || fail 422 "No máximo 5000 atribuições por vez" "assign_too_many"
jq -e '(.renames // []) | type == "array" and length <= 500 and all(.[]; type == "object"
        and ((.from // "") | type) == "string" and ((.to // "") | type) == "string")' >/dev/null 2>&1 <<<"$body" \
  || fail 422 "renames = lista de {from, to}" "renames_invalid"
jq -r '(.renames // [])[] | select(.from != "" and .to != "" and .from != .to) | [.from, .to] | map(gsub("[\t\n\r]"; " ")) | join("\t")' \
  <<<"$body" > "$W/renames.tsv"

# prévia: nada é gravado
if [[ "$dry" == 1 ]]; then
  rg_preview "$contest" "$([[ $has_tree == 1 ]] && echo "$W/tree.json")" "$W/assign.tsv" "$W/out" \
    || fail 500 "Falha ao montar a prévia" "regions_preview_failed"
  rg_summary "$W/out/nodes.json" "$W/out/map.tsv" > "$W/sum.json"
  rg_resolve "$contest" "$W/assign.tsv" "$W/rv"
  jq -Rsc 'split("\n") | map(select(length > 0) | split("\u001f") | select((.[4] // "") != "") | {login:.[0], code:.[4]})' "$W/rv" > "$W/fail.json"
  ok_json_slurp '{dry_run:true, sig:$sig, summary:$sm[0], failed:$f[0]}' sm "$(cat "$W/sum.json")" \
    --slurpfile f "$W/fail.json" --arg sig "$(rg_sig "$contest")"
  exit 0
fi

# gravar: trava das sedes (+ a da inscrição, se o roster vai mudar)
mkdir -p "$cdir/var"
exec 7>"$cdir/var/.regions.lock"; flock -w 10 7 || fail 409 "Sedes ocupadas — tente de novo" "busy"
want="$(jq -r '.expect_sig // empty' <<<"$body")"
if [[ -n "$want" && "$want" != "$(rg_sig "$contest")" ]]; then
  FAIL_EXTRA="$(jq -cn --arg s "$(rg_sig "$contest")" '{sig:$s}')" \
    fail 409 "As sedes mudaram desde que você abriu a tela — recarregue e refaça" "regions_changed"
fi
if [[ -s "$W/assign.tsv" && -s "$cdir/registrations.json" ]]; then
  source "$_LIBDIR/registration.sh"
  exec 8>"$(reg_lock_file "$contest")"; flock -w 10 8 || fail 409 "Inscrição ocupada — tente de novo" "busy"
fi
if (( has_tree )); then
  if [[ "$(cat "$W/tree.json")" == "[]" ]]; then rm -f "$cdir/regions.json"
  else jq -c . "$W/tree.json" > "$cdir/regions.json.tmp" && mv -f "$cdir/regions.json.tmp" "$cdir/regions.json" \
         || fail 500 "Falha ao gravar as sedes" "regions_write_failed"; fi
fi
: > "$W/res.tsv"
[[ -s "$W/assign.tsv" ]] && rg_assign_many "$contest" "$W/assign.tsv" "$W/res.tsv"
[[ -n "$mode" ]] && cc_set_conf_var "$contest" REGIONS_MODE "$mode"
if [[ -s "$cdir/regions.json" ]] || gawk -F'\t' '$3 == "" { f = 1 } END { exit !f }' "$W/res.tsv"; then
  declare -F mod_enable >/dev/null || source "$_LIBDIR/modules.sh"
  mod_enable "$contest" sedes
fi
# sedes renomeadas: as referências pelo nome acompanham (escopo do staff, gate, Animeitor); o que sobrar apontando
# p/ sede que não existe mais volta em orphan_refs (a tela avisa)
nref=0
while IFS=$'\t' read -r _rf _rt; do
  [[ -n "$_rf" && -n "$_rt" ]] || continue
  _k="$(rg_ref_rename "$contest" "$_rf" "$_rt")"; nref=$(( nref + ${_k:-0} ))
  audit_log_to "$contest" regions-rename "from=$_rf to=$_rt refs=${_k:-0}" 2>/dev/null || true
done < "$W/renames.tsv"
rg_orphan_refs "$contest" > "$W/orph.json"; [[ -s "$W/orph.json" ]] || printf '[]' > "$W/orph.json"
rg_build "$contest" || fail 500 "Sedes gravadas, mas o mapa falhou" "regions_map_failed"
rg_summary "$cdir/var/regions-nodes.json" "$cdir/var/regions-map.tsv" > "$W/sum.json"
jq -Rsc 'split("\n") | map(select(length > 0) | split("\t")) | {ok:[.[] | select((.[2] // "") == "") | {login:.[0], target:.[1]}],
         bad:[.[] | select((.[2] // "") != "") | {login:.[0], code:.[2]}]}' "$W/res.tsv" > "$W/res.json"
audit_log_to "$contest" regions-save \
  "tree=$has_tree assign=$(wc -l < "$W/assign.tsv") ok=$(jq '.ok | length' "$W/res.json") mode=${mode:--}" 2>/dev/null || true
ok_json_slurp '{saved:true, sig:$sig, summary:$sm[0], assigned:$r[0].ok, failed:$r[0].bad, refs_renamed:$nr, orphan_refs:$o[0]}' sm "$(cat "$W/sum.json")" \
  --slurpfile r "$W/res.json" --arg sig "$(rg_sig "$contest")" --argjson nr "$nref" --slurpfile o "$W/orph.json"
