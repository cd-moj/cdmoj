#!/bin/bash
# sample-flag-migrate.sh [--apply] [<org>[/<prob>]] — leva ao padrão `SAMPLE=no` os pacotes que não
# declaram exemplo (2026-09-23). Sem --apply só LISTA.
#
# POR QUÊ: exemplo agora é SÓ `tests/input/sample*`; problema sem exemplo (função, interativo,
# linguagem própria…) declara `SAMPLE=no` no conf — docs/PACOTE.md, "Problema sem exemplo". Até aqui
# havia dois legados, que saíram do mojtools (statement-langs.sh):
#   1. o fallback que mostrava os 2 primeiros testes OCULTOS quando faltava sample* (em produção: 47
#      pacotes, 39 de função — relato do Daniel Saad no saad-arvores-bfs-fn);
#   2. o arquivo `samples` VAZIO na raiz, que escondia os exemplos (os interativos).
# O que este script faz, pacote a pacote:
#   - sem sample* e sem linha SAMPLE no conf  -> `SAMPLE=no` no COMEÇO do conf;
#   - arquivo `samples` vazio                 -> sai, e `SAMPLE=no` entra (ele escondia os exemplos,
#                                                inclusive sample* que existissem: mantém o efeito);
#   - arquivo `samples` COM nomes              -> só LISTA (nunca existiu em produção; decida à mão).
# Um commit por pacote (autor `moj`) e, no fim, o reindex dos tocados (reindex-all.sh --only), p/ o
# enunciado servido e o campo `samples` do json saírem sem os testes ocultos.
#
# NADA RECALIBRA: o tl-checksum ignora a linha SAMPLE (mojtools/tl-checksum.sh). A linha vai no
# COMEÇO porque o filtro é `sed` e preserva a falta de \n final — no começo, o conf filtrado é byte a
# byte o de antes. Pacote SEM conf é só LISTADO: criar um conf mudaria o checksum.
# ⚠ Os pacotes mudam de `rev` (a trava de edição): quem tem clone local desses problemas leva 409 no
# próximo `moj push` e resolve com `moj pull`.
#
# Rode onde a API roda (em produção, DENTRO do container: podman exec systemd-moj-api bash
# /opt/moj/cdmoj/server/bin/sample-flag-migrate.sh), fora de horário de prova (um pandoc por
# enunciado no reindex).
set -uo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; _DIR="$HERE/../api/v1"; _LIBDIR="$_DIR/lib"
source "$_LIBDIR/sources.sh" >/dev/null 2>&1 || source "$_LIBDIR/common.sh"
source "$_LIBDIR/problems.sh"

APPLY=0; SEL=""
for a in "$@"; do case "$a" in
  --apply) APPLY=1;;
  -h|--help) sed -n '2,32p' "$0"; exit 0;;
  -*) echo "opção desconhecida: $a" >&2; exit 2;;
  *) SEL="$a";;
esac; done
[[ -d "$MOJ_PROBLEMS_DIR" ]] || { echo "sem $MOJ_PROBLEMS_DIR" >&2; exit 1; }
mapfile -t PKGS < <(
  if [[ -n "$SEL" ]]; then find "$MOJ_PROBLEMS_DIR/$SEL" -maxdepth 1 -mindepth 0 -type d -path "$MOJ_PROBLEMS_DIR/*/*" ! -name .git 2>/dev/null
  else find "$MOJ_PROBLEMS_DIR" -mindepth 2 -maxdepth 2 -type d ! -name '.git' 2>/dev/null; fi | LC_ALL=C sort)

_kind(){ # rótulo p/ o relatório (não decide nada)
  if compgen -G "$1/scripts/*/run.sh" >/dev/null 2>&1 || compgen -G "$1/scripts/arbitro.*" >/dev/null 2>&1; then echo interativo/run
  elif compgen -G "$1/scripts/*/compile.sh" >/dev/null 2>&1; then echo funcao
  else echo comum; fi; }
_rx(){ sed 's/[].[*^$()+?{}|\\]/\\&/g' <<<"$1"; }   # id -> regex literal (o # e o - não são especiais)

n=0; todo=0; skipped=0; listonly=0; ids=()
for p in "${PKGS[@]}"; do
  [[ -d "$p/tests/input" ]] || continue
  n=$((n+1)); rel="${p#"$MOJ_PROBLEMS_DIR/"}"
  has_s=0; compgen -G "$p/tests/input/sample*" >/dev/null 2>&1 && has_s=1
  flag=0;  grep -qE '^[[:space:]]*SAMPLE[[:space:]]*=' "$p/conf" 2>/dev/null && flag=1
  legacy=0; if [[ -f "$p/samples" ]]; then
    if grep -qv '^[[:space:]]*$' "$p/samples" 2>/dev/null; then
      echo "$rel: arquivo samples COM nomes ($(grep -cv '^[[:space:]]*$' "$p/samples")) — não suportado mais; decida à mão"; listonly=$((listonly+1)); continue
    fi
    legacy=1
  fi
  need=0; { (( legacy )) || (( ! has_s )); } && (( ! flag )) && need=1
  (( need || legacy )) || continue
  if (( need )) && [[ ! -f "$p/conf" ]]; then echo "$rel: SEM conf — pulado (crie o conf com SAMPLE=no à mão; muda o tl-checksum)"; skipped=$((skipped+1)); continue; fi
  todo=$((todo+1))
  printf '%s  [%s%s]%s%s\n' "$rel" "$(_kind "$p")" "$( (( has_s )) && echo ", $(ls "$p/tests/input" | grep -c '^sample') sample*")" \
    "$( (( need )) && echo '  + SAMPLE=no')" "$( (( legacy )) && echo '  - samples (vazio)')"
  (( APPLY )) || continue
  if (( need )); then
    tmp="$(mktemp)"; { printf 'SAMPLE=no\n'; cat "$p/conf"; } > "$tmp" && cat "$tmp" > "$p/conf"; rm -f "$tmp"
  fi
  (( legacy )) && rm -f "$p/samples"
  if problem_commit "$p" moj "exemplos: SAMPLE=no (problema sem exemplo declarado; ver docs/PACOTE.md)" >/dev/null 2>&1; then
    ids+=("${rel%%/*}#${rel#*/}")
  else echo "   ⚠ $rel: commit falhou" >&2; fi
done

printf '\n%s pacote(s) varrido(s); %s a migrar; %s sem conf (pulados); %s com lista em samples (à mão).\n' "$n" "$todo" "$skipped" "$listonly"
(( APPLY )) || { echo "(dry-run — nada foi alterado; repita com --apply)"; exit 0; }
(( ${#ids[@]} )) || exit 0
rx="^($(for i in "${ids[@]}"; do _rx "$i"; done | paste -sd'|'))\$"
echo ">> reindexando ${#ids[@]} problema(s)…"
bash "$HERE/reindex-all.sh" --only "$rx"
