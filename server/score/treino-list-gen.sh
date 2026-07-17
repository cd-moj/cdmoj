#!/bin/bash
# treino-list-gen.sh — (re)gera var/problems.json, a lista do GET /treino/problems.
# Chamado pelo handler: em FOREGROUND (sob o flock do handler) quando a composição da lista
# mudou (stamp .treino-list-dirty), e em BACKGROUND quando só as CONTAGENS envelheceram
# (score-dirty mais novo + piso de idade — o request serve o stale e este script atualiza).
#
# Fontes:
#  - SIDECARS var/jsons-meta/<id>.json (metadados minúsculos; auto-cura a partir de
#    var/jsons e remove órfão — nunca ressuscita problema que saiu);
#  - CONTAGENS solved/attempted POR PROBLEMA: base legada var/json-count/ (job antigo,
#    quando existir) SOBREPOSTA pela agregação do STORE NOVO — users/*/metrics.json
#    (.solved/.attempted são arrays de ids canônicos; 1 usuário = 1 em cada contagem).
# Sem lock aqui dentro (o chamador serializa); escrita atômica (tmp+mv); NUNCA troca um
# cache bom por vazio.
set -u -o pipefail
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
T="$CONTESTSDIR/treino"
JD="$T/var/jsons"; META="$T/var/jsons-meta"; COUNTS="$T/var/json-count"
CACHE="$T/var/problems.json"

mkdir -p "$META" 2>/dev/null
shopt -u nullglob 2>/dev/null || true

# --- sidecars: auto-cura (json sem sidecar ou mais novo) + órfãos ---------------------
# (${var##*/}, nunca $(basename): 2×N forks de subshell custavam ~3s)
for j in "$JD"/*.json; do
  [[ -f "$j" ]] || continue
  m="$META/${j##*/}"
  [[ -f "$m" && ! "$j" -nt "$m" ]] && continue
  jq -c '{id, title, public, tags:(.tags // []), collections:(.collections // [])}' "$j" \
    > "$m.tmp" 2>/dev/null && mv -f "$m.tmp" "$m" || rm -f "$m.tmp"
done
for m in "$META"/*.json; do
  [[ -f "$m" && ! -f "$JD/${m##*/}" ]] && rm -f "$m"
done

# --- contagens: legado (json-count) + store novo (metrics.json), novo VENCE por id ----
tmpd="$(mktemp -d)"; trap 'rm -rf "$tmpd"' EXIT
# legado: casa pelo NOME DO ARQUIVO (o .id interno é pontilhado)
jq -n '
  reduce inputs as $x ({};
    . + { (input_filename | sub(".*/";"") | sub("\\.json$";"")):
          {solved_count: ($x.solved_count // 0), attempted_count: ($x.attempted_count // 0)} })
' "$COUNTS"/*.json 2>/dev/null > "$tmpd/legacy"
[[ -s "$tmpd/legacy" ]] || echo '{}' > "$tmpd/legacy"
# store novo: 1 passada por users/*/metrics.json (find|xargs — ARG_MAX; lote de 200 p/ um
# json corrompido não derrubar a agregação inteira). Cada usuário conta 1× por problema.
find "$T/users" -mindepth 2 -maxdepth 2 -name metrics.json -print0 2>/dev/null \
  | { xargs -0 -r -n 200 jq -c '{solved:(.solved // []), attempted:(.attempted // [])}' 2>/dev/null || true; } \
  | jq -sc '
      reduce .[] as $u ({};
        reduce ($u.attempted // [])[] as $p (.;
          .[$p] = ((.[$p] // {solved_count:0, attempted_count:0}) | .attempted_count += 1))
      | reduce ($u.solved // [])[] as $p (.;
          .[$p] = ((.[$p] // {solved_count:0, attempted_count:0}) | .solved_count += 1)))
    ' > "$tmpd/store" 2>/dev/null
[[ -s "$tmpd/store" ]] || echo '{}' > "$tmpd/store"
jq -n --slurpfile a "$tmpd/legacy" --slurpfile b "$tmpd/store" \
  '($a[0] // {}) + ($b[0] // {})' > "$tmpd/counts" 2>/dev/null
[[ -s "$tmpd/counts" ]] || echo '{}' > "$tmpd/counts"

# --- lista final (sidecars + contagens) -----------------------------------------------
# `select(.public != false)`: 3ª camada anti-vazamento — a lista é ANÔNIMA; json legado sem
# o campo passa, só o explicitamente privado é barrado. Ver mojtools/gen-problem-json.sh.
body="$(jq -s --slurpfile c "$tmpd/counts" '
  ($c[0] // {}) as $cnt
  | map(select(.public != false)
      | {id, title, tags: (.tags // []), collections: (.collections // [])}
        + ($cnt[.id] // {solved_count:0, attempted_count:0}))
' "$META"/*.json 2>/dev/null)"
if [[ -z "$body" ]]; then
  # sem sidecar nenhum = base legitimamente vazia; com sidecar, corpo vazio é ERRO
  compgen -G "$META/*.json" >/dev/null 2>&1 && exit 1 || body='[]'
fi
printf '%s' "$body" > "$CACHE.tmp.$$" && mv -f "$CACHE.tmp.$$" "$CACHE"
