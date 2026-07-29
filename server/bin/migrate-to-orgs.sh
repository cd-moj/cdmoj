#!/usr/bin/env bash
# migrate-to-orgs.sh — CUT-OVER p/ o storage MOJ-nativo (repo git por problema + orgs). Uma vez.
#   1) semeia contests/treino/var/orgs.json a partir dos dirs atuais + problem-repos.json
#      (owner/colaboradores viram membros; public_allowed = o dir tem algum problema público);
#   2) converte cada MOJ_PROBLEMS_DIR/<org>/<prob> num REPO GIT por problema (git init + commit) e
#      remove o .git/.gitattributes COMPARTILHADO do <org> (não é mais um repo, é só um diretório);
#   3) regenera o índice de donos.
# Preserva id/layout, contests, históricos e usuários. Idempotente (pula problema que já tem .git).
set -uo pipefail
: "${MOJ_PROBLEMS_DIR:=/home/ribas/moj/moj-problems}"
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
: "${RUNDIR:=/home/ribas/moj/run}"
: "${MOJTOOLS_DIR:=/home/ribas/moj/mojtools}"
ORGS="$CONTESTSDIR/treino/var/orgs.json"
REPOS="$CONTESTSDIR/treino/var/problem-repos.json"
now="$(date +%s)"
skip_re='^(\.|mojtools$|.*\.(tar|bz2|gz|tgz|zip)$|repositorio-template.*|trab-.*)'

echo "== 1) semeando orgs.json =="
orgs='{}'
for d in "$MOJ_PROBLEMS_DIR"/*/; do
  d="${d%/}"; [[ -d "$d" ]] || continue; org="$(basename "$d")"
  [[ "$org" =~ $skip_re ]] && continue
  [[ "$org" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || continue
  owner="$(jq -r --arg r "$org" '.[$r].owner // "ribas.admin"' "$REPOS" 2>/dev/null)"; [[ -n "$owner" && "$owner" != null ]] || owner="ribas.admin"
  collabs="$(jq -c --arg r "$org" '.[$r].collaborators // []' "$REPOS" 2>/dev/null)"; [[ -n "$collabs" && "$collabs" != null ]] || collabs='[]'
  pa=false
  for p in "$d"/*/; do [[ -f "$p/.moj-meta.json" ]] && jq -e '.public==true' >/dev/null 2>&1 < "$p/.moj-meta.json" && { pa=true; break; }; done
  orgs="$(jq -cn --argjson o "$orgs" --arg n "$org" --arg ow "$owner" --argjson cb "$collabs" --argjson pa "$pa" --argjson now "$now" '
    $o + { ($n): { created_by:$ow, title:$n, members:(([$ow]+$cb)|unique), admins:[$ow],
                   public_allowed:$pa, at:$now } }')"
  printf '  org %-16s owner=%s public_allowed=%s membros=%s\n' "$org" "$owner" "$pa" "$(jq -cn --arg o "$owner" --argjson cb "$collabs" '([$o]+$cb)|unique')"
done
mkdir -p "$(dirname "$ORGS")"; ( umask 077; printf '%s' "$orgs" | jq . > "$ORGS" )
echo "  -> $ORGS"

echo "== 2) git init por problema (+ remove o .git compartilhado do <org>) =="
for d in "$MOJ_PROBLEMS_DIR"/*/; do
  d="${d%/}"; [[ -d "$d" ]] || continue; org="$(basename "$d")"
  [[ "$org" =~ $skip_re ]] && continue
  n=0
  for p in "$d"/*/; do
    p="${p%/}"; [[ -d "$p" ]] || continue; [[ "$(basename "$p")" == ".git" ]] && continue
    [[ -f "$p/author" || -f "$p/conf" || -d "$p/tests" || -d "$p/docs" ]] || continue
    if [[ ! -d "$p/.git" ]]; then
      ow="$(jq -r '.owner // "ribas.admin"' "$p/.moj-meta.json" 2>/dev/null)"; [[ -n "$ow" && "$ow" != null ]] || ow="ribas.admin"
      git -C "$p" -c init.defaultBranch=master init -q 2>/dev/null
      printf 'tl\ntl.*\n' >> "$p/.git/info/exclude" 2>/dev/null
      git -C "$p" add -A 2>/dev/null
      GIT_AUTHOR_NAME="$ow" GIT_AUTHOR_EMAIL="$ow@moj.local" GIT_COMMITTER_NAME="$ow" GIT_COMMITTER_EMAIL="$ow@moj.local" \
        git -C "$p" commit -q -m "migração: repo git por problema" 2>/dev/null || true
      n=$((n+1))
    fi
  done
  rm -rf "$d/.git" "$d/.gitattributes" 2>/dev/null   # <org> deixa de ser um repo
  printf '  %-16s %s problemas init\x27d; .git compartilhado removido\n' "$org" "$n"
done

echo "== 3) regenerando o índice de donos =="
MOJ_PROBLEMS_DIR="$MOJ_PROBLEMS_DIR" CONTESTSDIR="$CONTESTSDIR" RUNDIR="$RUNDIR" \
  bash "$MOJTOOLS_DIR/gen-problem-owners.sh" >/dev/null 2>&1 && echo "  índice regenerado" || echo "  (falha no índice — rode gen-problem-owners.sh à mão)"
echo "== pronto. orgs=$(jq 'length' "$ORGS" 2>/dev/null) =="
