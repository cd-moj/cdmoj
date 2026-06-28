# GET/POST /contest/admin/problems?contest=<id>  (admin DO contest)
# GET  -> [{source,problem_id,name,letter,statement_key}] na ordem atual.
# POST {action, ...}: add | remove | reorder | rename. Reescreve PROBS no conf + auditoria.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
source "$_LIBDIR/contest-create.sh"

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  # inclui as linguagens permitidas por problema (problem-langs.json, chaveado pelo id canônico)
  plf="$CONTESTSDIR/$contest/problem-langs.json"; pl='{}'; [[ -f "$plf" ]] && pl="$(jq -c . "$plf" 2>/dev/null)"; jq -e . >/dev/null 2>&1 <<<"$pl" || pl='{}'
  out="$(jq -c --argjson pl "$pl" '[ .[] | . as $p
          | ((if (($p.statement_key // "")|test("#")) then $p.statement_key else (($p.problem_id // "")|gsub("/";"#")) end)) as $cid
          | $p + {languages: ($pl[$cid] // [])} ]' <<<"$(cc_probs_json "$contest")")"
  ok_json '{problems:$p}' --argjson p "$out"
  exit 0
fi

require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
action="$(jq -r '.action // empty' <<<"$body")"
cur="$(cc_probs_json "$contest")"
new=""

case "$action" in
  add)
    prob="$(jq -c '.problem // {}' <<<"$body")"
    [[ "$(jq -r '(.problem_id // .bank_id // "")' <<<"$prob")" != "" ]] || fail 422 "Informe problem_id ou bank_id" "prob_missing"
    new="$(jq -cn --argjson cur "$cur" --argjson p "$prob" '$cur + [$p]')"
    ;;
  remove)
    L="$(jq -r '.letter // empty' <<<"$body")"
    [[ -n "$L" ]] || fail 400 "Informe a letra" "letter_missing"
    new="$(jq -cn --argjson cur "$cur" --arg l "$L" '[ $cur[] | select(.letter != $l) ]')"
    ;;
  rename)
    L="$(jq -r '.letter // empty' <<<"$body")"
    [[ -n "$L" ]] || fail 400 "Informe a letra" "letter_missing"
    new="$(jq -cn --argjson cur "$cur" --argjson b "$body" --arg l "$L" '
      [ $cur[] | if .letter==$l then
          (if ($b|has("name")) then .name=$b.name else . end)
          | (if ($b|has("new_letter")) then .letter=$b.new_letter else . end)
        else . end ]')"
    ;;
  reorder)
    order="$(jq -c '.order // []' <<<"$body")"
    new="$(jq -cn --argjson cur "$cur" --argjson order "$order" '
      ($cur | map({(.letter): .}) | add) as $by
      | [ $order | to_entries[] | . as $e | ($by[$e.value] // empty) | (.letter = ([65 + $e.key] | implode)) ]')"
    ;;
  langs)
    # linguagens permitidas POR problema (ids canônicos minúsculos). Chaveado pelo id
    # canônico 'coleção#problema' (estável a reordenações). Vazio = herda do contest.
    L="$(jq -r '.letter // empty' <<<"$body")"
    [[ -n "$L" ]] || fail 400 "Informe a letra" "letter_missing"
    cid="$(jq -r --arg l "$L" '[.[]|select(.letter==$l)][0]
            | (if ((.statement_key // "")|test("#")) then .statement_key else ((.problem_id // "")|gsub("/";"#")) end) // empty' <<<"$cur")"
    [[ -n "$cid" ]] || fail 404 "Problema não encontrado" "notfound"
    larr="$(jq -c '(.languages // []) | map(ascii_downcase | select(test("^[a-z0-9_+.-]+$"))) | unique' <<<"$body")"
    plf="$CONTESTSDIR/$contest/problem-langs.json"
    base='{}'; [[ -f "$plf" ]] && base="$(cat "$plf" 2>/dev/null)"; jq -e . >/dev/null 2>&1 <<<"$base" || base='{}'
    if [[ "$(jq 'length' <<<"$larr")" -gt 0 ]]; then
      printf '%s' "$base" | jq -c --arg id "$cid" --argjson v "$larr" '.[$id]=$v' > "$plf.tmp" && mv -f "$plf.tmp" "$plf"
    else
      printf '%s' "$base" | jq -c --arg id "$cid" 'del(.[$id])' > "$plf.tmp" && mv -f "$plf.tmp" "$plf"
    fi
    audit_log_to "$contest" problems-langs "letter=$L id=$cid langs=$(jq -r 'join(",")' <<<"$larr")"
    ok_json '{saved:true, problem_id:$id, languages:$v}' --arg id "$cid" --argjson v "$larr"
    exit 0
    ;;
  *) fail 400 "action inválida (add|remove|reorder|rename|langs)" "action_invalid" ;;
esac

[[ -n "$new" ]] || fail 422 "Nada a fazer" "noop"
cc_set_probs "$contest" "$new" || fail 422 "Falha ao gravar problemas (dados inválidos?)" "probs_write"
audit_log_to "$contest" "problems-$action" "$(jq -cr '. | del(.problem.statement_b64)' <<<"$body" 2>/dev/null | head -c 300)"
ok_json '{saved:true, problems:$p}' --argjson p "$(cc_probs_json "$contest")"
