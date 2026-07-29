#!/usr/bin/env bash
# seed-collections.sh — semeia o REGISTRO CURADO de coleções (contests/treino/var/collections.json) =
# (tags distintas em uso nos .moj-meta.json) ∪ (nomes das orgs). owner=ribas.admin. IDEMPOTENTE (não
# sobrescreve dono/at de coleção já registrada). Faz com que todo tag já em uso seja uma coleção válida
# (a curadoria não rejeita o que já existe) e preserva a ponte de histórico (tags legadas = coleções).
set -uo pipefail
: "${MOJ_PROBLEMS_DIR:=/home/ribas/moj/moj-problems}"
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
REG="$CONTESTSDIR/treino/var/collections.json"
ORGS="$CONTESTSDIR/treino/var/orgs.json"
now="$(date +%s)"

tags="$(find "$MOJ_PROBLEMS_DIR" -mindepth 3 -maxdepth 3 -name '.moj-meta.json' -exec cat {} + 2>/dev/null \
  | jq -sc '[.[]|.collections//[]|.[]]|unique')"
[[ -n "$tags" && "$tags" != null ]] || tags='[]'
orgnames="$(jq -c 'keys' "$ORGS" 2>/dev/null)"; [[ -n "$orgnames" && "$orgnames" != null ]] || orgnames='[]'
cur="$(cat "$REG" 2>/dev/null)"; [[ -n "$cur" ]] || cur='{}'
new="$(jq -n --argjson cur "$cur" --argjson tags "$tags" --argjson orgs "$orgnames" --argjson now "$now" '
  ($tags + $orgs | unique | map(select(length>0))) as $names
  | reduce $names[] as $n ($cur;
      .[$n] = {owner:((.[$n].owner)//"ribas.admin"),
               created_by:((.[$n].created_by)//.[$n].owner//"ribas.admin"),
               at:((.[$n].at)//$now)})')"
mkdir -p "$(dirname "$REG")"; ( umask 077; printf '%s' "$new" | jq . > "$REG" )
echo "coleções registradas: $(jq 'length' "$REG") (tags em uso: $(jq 'length' <<<"$tags"), orgs: $(jq 'length' <<<"$orgnames"))"
