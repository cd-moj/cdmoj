# GET /treino/contest-create/problems?q=&limit=  (auth treino, pode criar)
# Busca os problemas que o usuário PODE USAR num contest: públicos (banco do treino) + os
# PRIVADOS a que ele tem acesso (dono, colaborador ou MEMBRO da org — membro opera todos os
# problemas da org, inclusive privados). Autocomplete do seletor de problemas. Itens com enunciado
# traduzido trazem `titles` {pt,en,es} (cc_attach_titles): as opções de nome no assistente.
require_method GET
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
source "$_LIBDIR/problems.sh"

q="$(param q)"; limit="$(param limit)"
[[ "$limit" =~ ^[0-9]+$ ]] || limit=40; (( limit > 100 )) && limit=100

# ids que já têm enunciado pronto (público ou privado já validado)
set +o noglob
have="$( { ls "$CONTESTSDIR"/treino/var/jsons/*.json "$CONTESTSDIR"/treino/var/jsons-private/*.json 2>/dev/null \
          | sed 's@.*/@@; s@\.json$@@'; } | jq -R . | jq -cs 'map({(.):true})|add // {}' 2>/dev/null )"
set -o noglob
[[ -n "$have" ]] || have='{}'

# corpo ANTES do cabeçalho (falha do jq = 500, nunca "200 com lista vazia")
out="$(owners_merged | jq -c --arg me "$SESSION_LOGIN" --argjson orgs "$(my_orgs_json)" \
    --arg q "$q" --argjson n "$limit" --argjson have "$have" '
  [ .problems[]
    | ( if .owner==$me then "mine"
        elif ((.collaborators // [])|index($me)) then "shared"
        elif (((.repo // (.id|split("#")[0])) as $r | $orgs|index($r))|type=="number") then "shared"
        elif .public then "public" else null end ) as $acc
    | select($acc != null)
    | { id, title, tags:(.tags // []), access:$acc, private:(.public|not), has_statement:($have[.id]==true) } ]
  | ( if (($q|length) > 0)
      then map(select( ((.id + " " + (.title // ""))|ascii_downcase) | contains($q|ascii_downcase) ))
      else . end )
  | sort_by(.private|not) as $f                      # privados (seus) primeiro
  | { problems:($f[0:$n]), total:($f|length),
      mine:([$f[]|select(.access=="mine")]|length), shared:([$f[]|select(.access=="shared")]|length) }
' 2>/dev/null)"
[[ -n "$out" ]] || out='{"problems":[],"total":0,"mine":0,"shared":0}'
# `titles` {pt,en,es} nos itens com tradução (só a página devolvida, ≤limit): as opções de nome
_pt="$(jq -c '.problems' <<<"$out" | cc_attach_titles)"
[[ -n "$_pt" ]] && out="$(jq -c --argjson p "$_pt" '.problems = $p' <<<"$out" 2>/dev/null || printf '%s' "$out")"
ok_json_slurp '$o[0]' o "$out"
