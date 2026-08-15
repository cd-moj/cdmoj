# GET /contest/admin/jplag-results?contest=<id>  (admin) -> status + resultados por problema/lang.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

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
ok_json '{status:$s, results:$r[0]}' --argjson s "$status" --slurpfile r "$tmpres"
