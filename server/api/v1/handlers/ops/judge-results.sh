# GET /ops/judge-results?host=<h>&limit=<n>   (Bearer, admin)
# RELATÓRIO de correções por juiz: últimas N correções (run/results/<id>.json, que carrega
# o host que julgou) + agregado por host (total, aceitas, judge errors, duração média).
# Fonte: run/results é a cópia central plana escrita pelo daemon (1 arquivo por correção);
# retenção é "últimas N", não histórico eterno (os permanentes vivem em users/*/results).
require_method GET
require_admin

h="$(param host)"
limit="$(param limit)"; [[ "$limit" =~ ^[0-9]+$ && "$limit" -le 500 ]] || limit=50
RESD="${RESULTSDIR:-$RUNDIR/results}"
[[ -d "$RESD" ]] || { emit_json 200 OK; jq -cn '{success:true, results:[], by_host:{}}'; exit 0; }

D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT
# mais recentes primeiro; pega uma janela maior p/ o agregado/filtro e corta no limit
find "$RESD" -maxdepth 1 -name '*.json' -printf '%T@\t%p\n' 2>/dev/null \
  | sort -rn | head -n 2000 | cut -f2 > "$D/files"

: > "$D/nd"
while IFS= read -r f; do
  jq -c '{id, host:(.host // "?"), verdict, login, problem_id, lang,
          duration_s:(.duration_s // null), finalized_at:(.finalized_at // null),
          contest:(.contest // ""), score:(.score // null)}' "$f" 2>/dev/null
done < "$D/files" >> "$D/nd"

emit_json 200 OK
jq -cn --arg h "$h" --argjson lim "$limit" --slurpfile all "$D/nd" '
  ($all | if $h == "" then . else map(select(.host == $h)) end) as $sel |
  {success:true,
   results: ($sel | .[0:$lim]),
   by_host: ($sel | group_by(.host) | map({key:(.[0].host), value:{
      total: length,
      accepted: (map(select(.verdict | startswith("Accepted"))) | length),
      judge_errors: (map(select(.verdict | test("Judge Error"))) | length),
      avg_duration: (if length>0 then ((map(.duration_s // 0) | add) / length * 100 | round / 100) else 0 end),
      last_at: (map(.finalized_at // 0) | max)
   }}) | from_entries)}'
