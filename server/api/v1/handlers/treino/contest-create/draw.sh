# GET /treino/contest-create/draw?tags=a,b&count=8&match=any|all&difficulty=any|easy|medium|hard|known&seed=
# (auth treino, pode criar) -> sorteia problemas do banco por tag e dificuldade (reproduzível por seed).
require_method GET
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
tags="$(param tags)"; count="$(param count)"; match="$(param match)"; diff="$(param difficulty)"; seed="$(param seed)"
[[ "$count" =~ ^[0-9]+$ ]] || count=5; (( count < 1 )) && count=1; (( count > 100 )) && count=100
[[ "$match" == all ]] || match=any
case "$diff" in easy|medium|hard|known) ;; *) diff=any;; esac
[[ "$seed" =~ ^[0-9]+$ ]] || seed="$RANDOM"

CACHE="$CONTESTSDIR/treino/var/problems.json"
if [[ -f "$CACHE" ]]; then data="$(cat "$CACHE")"
else set +o noglob; data="$(jq -s 'map({id,title,tags:(.tags//[])})' "$CONTESTSDIR"/treino/var/jsons/*.json 2>/dev/null)"; set -o noglob; [[ -n "$data" ]] || data='[]'; fi
MET="$(cc_problem_metrics_file)"

list="$(jq -c --slurpfile m "$MET" --arg tags "$tags" --arg match "$match" --arg diff "$diff" '
  ($tags|split(",")|map(ascii_downcase|gsub("^\\s+|\\s+$";""))|map(select(length>0))) as $T
  | ($m[0] // {}) as $M
  | [ .[]
      | (.tags // []) as $pt
      | ($pt|map(ascii_downcase)) as $ptl
      | (if ($T|length)==0 then true
         elif $match=="all" then ($T|all(. as $t|$ptl|index($t)))
         else ($T|any(. as $t|$ptl|index($t))) end) as $tagok
      | select($tagok)
      | ($M[.id] // {total:0,accepted:0,solvers:0,acceptance:0}) as $mm
      | (if $mm.total==0 then "unknown" elif $mm.acceptance>=0.5 then "easy" elif $mm.acceptance>=0.2 then "medium" else "hard" end) as $bucket
      | select($diff=="any" or $diff==$bucket or ($diff=="known" and $bucket!="unknown"))
      | {id, title, tags:$pt, solvers:$mm.solvers, total:$mm.total, acceptance:(($mm.acceptance*1000|floor)/1000), bucket:$bucket}
    ]' <<<"$data" 2>/dev/null)"
[[ -n "$list" ]] || list='[]'
candidates="$(jq 'length' <<<"$list" 2>/dev/null)"; [[ "$candidates" =~ ^[0-9]+$ ]] || candidates=0
drawn="$(jq -c '.[]' <<<"$list" 2>/dev/null | awk -v seed="$seed" 'BEGIN{srand(seed)} {print rand()"\t"$0}' | sort -n | cut -f2- | head -n "$count" | jq -cs '.' 2>/dev/null)"
[[ -n "$drawn" ]] || drawn='[]'
ok_json '{problems:$d, candidates:$c, drawn:($d|length), seed:$s, count:$n}' \
  --argjson d "$drawn" --argjson c "$candidates" --argjson s "$seed" --argjson n "$count"
