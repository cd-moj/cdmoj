# GET /contest/admin/jplag-results?contest=<id>  (juiz/chefe/admin) -> status + resultados
# por problema/lang. O juiz COMUM vê os pares só com o login (sem nome do time/univ — a mesma
# isonomia de "Todas as submissões" anônima); chefe e admin veem tudo (2026-09-14).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_judge || fail 403 "Apenas juiz, juiz-chefe ou admin" "judge_required"

jdir="$CONTESTSDIR/$contest/jplag"
status="$( [[ -f "$jdir/status.json" ]] && jq -c . "$jdir/status.json" 2>/dev/null || echo '{"running":false,"message":"nunca executado"}')"
[[ -n "$status" ]] || status='{"running":false,"message":"nunca executado"}'
# ⚠ O agregado dos r-*.json NÃO pode ir por --argjson: o jq tem teto de 128KiB POR ARGUMENTO
# e o corpo cresce com o nº de pares (o esquenta 2026, com 22 problemas e 552 pares nomeados,
# deu 138KB) — acima disso o jq falha e a resposta sai vazia. Vai por --slurpfile.
tmpres="$(mktemp)"; trap 'rm -f "$tmpres"' EXIT
{ set +o noglob; shopt -s nullglob
  for f in "$jdir"/r-*.json; do [[ -f "$f" ]] && cat "$f"; done
} | jq -cs 'sort_by(.problem, .lang)' > "$tmpres" 2>/dev/null
[[ -s "$tmpres" ]] || printf '[]' > "$tmpres"
full=true; is_admin_or_chief || full=false
ok_json '{status:$s, full:$full, can_run:$full,
          results:(if $full then $r[0] else ($r[0] | map(.pairs |= map(del(.a_name, .a_univ, .b_name, .b_univ)))) end)}' \
  --argjson s "$status" --argjson full "$full" --slurpfile r "$tmpres"
