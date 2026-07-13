#!/bin/bash
# audit-public-index.sh — audita (e repara) o ÍNDICE PÚBLICO do treino.
#
#   bash server/bin/audit-public-index.sh          # só ACUSA (dry-run, default)
#   bash server/bin/audit-public-index.sh --fix    # remove os intrusos e invalida os caches
#   bash server/bin/audit-public-index.sh --quiet  # só o resumo (p/ cron)
#
# `contests/treino/var/jsons/` é servido **SEM LOGIN** (lista e ENUNCIADO INTEIRO). Um problema só
# pode estar lá se as DUAS coisas valerem:
#   (a) o pacote tem `.moj-meta.json` com **public:true**  (o flag só é escrito pelo /problems/set-public);
#   (b) a **ORG** dele permite público (`public_allowed` em contests/treino/var/orgs.json).
#
# Existe porque um bug de UMA LINHA no gerador (`jq '.public // "unset"'` — o `//` do jq trata FALSE
# como vazio, então public:false virava "unset" e a checagem morria) pôs 14 problemas PRIVADOS nessa
# lista, com o enunciado de provas em elaboração ao vivo p/ qualquer anônimo. Isto é a rede de
# segurança: rode depois de migração/importação e periodicamente (cron).
set -uo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"   # .../cdmoj
[[ -f "$ROOT/server/etc/common.conf" ]] && source "$ROOT/server/etc/common.conf"
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
: "${MOJ_PROBLEMS_DIR:=/home/ribas/moj/moj-problems}"

FIX=0; QUIET=0
for a in "$@"; do case "$a" in
  --fix) FIX=1;; --quiet|-q) QUIET=1;;
  -h|--help) sed -n '2,18p' "$0"; exit 0;;
  *) echo "audit-public-index: opção desconhecida: $a" >&2; exit 2;;
esac; done

JD="$CONTESTSDIR/treino/var/jsons"
ORGS="$CONTESTSDIR/treino/var/orgs.json"
say(){ (( QUIET )) || echo "$@"; }

# org_allows <org> -> 0 se a org permite público. Org NÃO registrada = permite (problema legado,
# de antes das orgs; quem barra nesse caso é o public:true do meta).
org_allows(){
  [[ -f "$ORGS" ]] || return 0
  jq -e --arg n "$1" 'has($n) | not' "$ORGS" >/dev/null 2>&1 && return 0   # org desconhecida
  jq -e --arg n "$1" '.[$n].public_allowed == true' "$ORGS" >/dev/null 2>&1
}

bad=0; ok=0; total=0
shopt -s nullglob
for f in "$JD"/*.json; do
  total=$((total+1))
  id="$(basename "$f" .json)"; org="${id%%#*}"; prob="${id##*#}"
  pkg="$MOJ_PROBLEMS_DIR/$org/$prob"; meta="$pkg/.moj-meta.json"
  why=""
  if [[ ! -d "$pkg" ]]; then why="pacote não existe (órfão)"
  elif [[ ! -f "$meta" ]]; then why="sem .moj-meta.json (fail-closed: privado)"
  elif ! jq -e '.public == true' "$meta" >/dev/null 2>&1; then why="meta NÃO diz public:true"
  elif ! org_allows "$org"; then why="a org '$org' não permite público (public_allowed=false)"
  fi
  if [[ -n "$why" ]]; then
    bad=$((bad+1))
    say "  VIOLAÇÃO: $id — $why"
    (( FIX )) && { rm -f "$f" && say "            removido do índice público"; }
  else
    ok=$((ok+1))
  fi
done
shopt -u nullglob

if (( FIX && bad > 0 )); then
  # caches derivados da lista (senão o vazamento sobrevive até 5 min no cache)
  rm -f "$CONTESTSDIR/treino/var/problems.json" 2>/dev/null
  say "  caches invalidados (var/problems.json)"
fi

echo "audit-public-index: $total no índice público · $ok ok · $bad violação(ões)$( (( FIX )) && echo ' (removidas)' )"
(( bad == 0 )) || (( FIX ))   # exit != 0 se achou violação e NÃO consertou (bom p/ cron/CI)
