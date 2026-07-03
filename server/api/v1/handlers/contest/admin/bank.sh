# GET /contest/admin/bank?contest=<id>&q=&limit=&collection=  (admin DO contest)
# Busca no banco PÚBLICO do treino p/ adicionar problemas depois de criado (aba Problemas).
# ?meta=1 -> {tags:[{tag,count}],collections:[{collection,count}]} p/ o painel de sorteio.
# Fonte = cc_bank_json (projeção dos PÚBLICOS) — problema privado NUNCA aparece aqui; ele só
# entra pelo add por id, com o gate de dono do contest (problems.sh).
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
source "$_LIBDIR/contest-create.sh"

if [[ "$(param meta)" == 1 ]]; then
  bank="$(cc_bank_json)"
  tags="$(jq -c '[.[].tags[]?] | reduce .[] as $t ({}; .[$t]+=1) | to_entries | map({tag:.key,count:.value}) | sort_by(-.count)' <<<"$bank" 2>/dev/null)"
  cols="$(jq -c '[.[].collections[]?] | reduce .[] as $c ({}; .[$c]+=1) | to_entries | map({collection:.key,count:.value}) | sort_by(-.count)' <<<"$bank" 2>/dev/null)"
  [[ -n "$tags" ]] || tags='[]'; [[ -n "$cols" ]] || cols='[]'
  ok_json '{tags:$t, collections:$c}' --argjson t "$tags" --argjson c "$cols"
  exit 0
fi

q="$(param q)"; limit="$(param limit)"; col="$(param collection)"
[[ "$limit" =~ ^[0-9]+$ ]] || limit=30; (( limit > 100 )) && limit=100
out="$(cc_bank_json | jq -c --arg q "$q" --arg col "$col" --argjson n "$limit" '
  [ .[] | {id, title, tags:(.tags//[]), collections:(.collections//[])} ]
  | (if $col != "" then map(select(.collections|index($col))) else . end)
  | (if ($q|length) > 0 then map(select(((.id + " " + (.title // ""))|ascii_downcase)|contains($q|ascii_downcase))) else . end)
  | {problems:(.[0:$n]), total:length}' 2>/dev/null)"
[[ -n "$out" ]] || out='{"problems":[],"total":0}'
ok_json '$o' --argjson o "$out"
