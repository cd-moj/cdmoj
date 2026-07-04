# GET /contest/admin/bank?contest=<id>&q=&limit=&collection=  (admin DO contest)
# Busca de problemas p/ a aba Problemas: banco PÚBLICO do treino + os PRIVADOS a que o DONO
# do contest (arquivo owner) tem acesso (dono/colaborador no índice de owners) — o MESMO
# sujeito do gate de add (problems.sh), então a busca lista exatamente o que pode ser
# adicionado. Contest legado sem owner => só públicos. Privados vêm primeiro (como no wizard).
# ?meta=1 -> {tags:[{tag,count}],collections:[{collection,count}]} p/ o painel de sorteio
# (agregado do banco público — o sorteio é só público).
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
cowner="$(head -1 "$CONTESTSDIR/$contest/owner" 2>/dev/null)"
source "$_LIBDIR/problems.sh"

# tudo por --slurpfile (banco+índice podem ter milhares de entradas — nada por argv/ARG_MAX)
tmpd="$(mktemp -d)" || fail 500 "tmp" "tmp"
cc_bank_json > "$tmpd/bank.json"
owners_merged > "$tmpd/owners.json" 2>/dev/null || echo '{"problems":[]}' > "$tmpd/owners.json"
# ids com enunciado pronto (público ou privado já indexado) — mesmo mapa do wizard
set +o noglob
{ ls "$CONTESTSDIR"/treino/var/jsons/*.json "$CONTESTSDIR"/treino/var/jsons-private/*.json 2>/dev/null \
  | sed 's@.*/@@; s@\.json$@@'; } | jq -R . | jq -cs 'map({(.):true})|add // {}' > "$tmpd/have.json" 2>/dev/null
set -o noglob
[[ -s "$tmpd/have.json" ]] || echo '{}' > "$tmpd/have.json"

out="$(jq -cn --arg q "$q" --arg col "$col" --arg own "$cowner" --argjson n "$limit" \
  --slurpfile bank "$tmpd/bank.json" --slurpfile idx "$tmpd/owners.json" --slurpfile have "$tmpd/have.json" '
  ($bank[0] // []) as $pub
  | ($idx[0].problems // []) as $probs
  | ($have[0] // {}) as $H
  | ($pub | map({id, title, tags:(.tags//[]), collections:(.collections//[]),
                 access:"public", private:false, has_statement:($H[.id]==true)})) as $P
  | (if $own == "" then [] else
      [ $probs[]
        | select((.public // false) | not)
        | (if .owner == $own then "mine"
           elif ((.collaborators // [])|index($own)) != null then "shared" else null end) as $acc
        | select($acc != null)
        | {id, title:(.title // .id), tags:[], collections:(.collections // []),
           access:$acc, private:true, has_statement:($H[.id]==true)} ] end) as $PRIV
  | ($PRIV + $P)
  | (if $col != "" then map(select(.collections|index($col))) else . end)
  | (if ($q|length) > 0 then map(select(((.id + " " + (.title // ""))|ascii_downcase)|contains($q|ascii_downcase))) else . end)
  | {problems:(.[0:$n]), total:length,
     mine:([.[]|select(.access=="mine")]|length), shared:([.[]|select(.access=="shared")]|length)}' 2>/dev/null)"
rm -rf "$tmpd"
[[ -n "$out" ]] || out='{"problems":[],"total":0,"mine":0,"shared":0}'
ok_json '$o' --argjson o "$out"
