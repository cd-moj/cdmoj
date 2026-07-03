# GET /treino/contest-create/draw?tags=a,b&collections=<json-array>&count=8&match=any|all&difficulty=any|easy|medium|hard|known&seed=
# (auth treino, pode criar) -> sorteia problemas do banco por tag, COLEÇÃO e dificuldade
# (grupos em AND; reproduzível por seed). `collections` é um ARRAY JSON url-encoded
# (nome de coleção é texto livre — pode ter vírgula/espaço; CSV seria ambíguo).
require_method GET
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
tags="$(param tags)"; count="$(param count)"; match="$(param match)"; diff="$(param difficulty)"; seed="$(param seed)"
colls="$(param collections)"
[[ "$count" =~ ^[0-9]+$ ]] || count=5; (( count < 1 )) && count=1; (( count > 100 )) && count=100
[[ "$match" == all ]] || match=any
case "$diff" in easy|medium|hard|known) ;; *) diff=any;; esac
[[ "$seed" =~ ^[0-9]+$ ]] || seed="$RANDOM"
jq -e 'type=="array" and all(.[]; type=="string")' >/dev/null 2>&1 <<<"$colls" || colls='[]'

list="$(cc_bank_json | cc_bank_filter "$tags" "$match" "$diff" "$colls")"
[[ -n "$list" ]] || list='[]'
candidates="$(jq 'length' <<<"$list" 2>/dev/null)"; [[ "$candidates" =~ ^[0-9]+$ ]] || candidates=0
drawn="$(jq -c '.[]' <<<"$list" 2>/dev/null | awk -v seed="$seed" 'BEGIN{srand(seed)} {print rand()"\t"$0}' | sort -n | cut -f2- | head -n "$count" | jq -cs '.' 2>/dev/null)"
[[ -n "$drawn" ]] || drawn='[]'
ok_json '{problems:$d, candidates:$c, drawn:($d|length), seed:$s, count:$n, collections:$cl}' \
  --argjson d "$drawn" --argjson c "$candidates" --argjson s "$seed" --argjson n "$count" --argjson cl "$colls"
