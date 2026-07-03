# GET /contest/admin/draw?contest=<id>&tags=&collections=<json-array>&count=&match=any|all&difficulty=&seed=
# (admin DO contest) -> sorteio no banco PÚBLICO do treino (mesmo contrato do draw do wizard;
# reusa cc_bank_filter — coleção/tag/dificuldade em AND, reproduzível por seed). Só públicos.
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
source "$_LIBDIR/contest-create.sh"

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
