#!/bin/bash
# calib-summary-rebuild.sh [--apply] [<org>[#<prob>]] — gera o SUMÁRIO DAS SOLUÇÕES (run/calib-sum/<id>.json
# + o mapa run/calib-summary.json) dos problemas que JÁ foram calibrados. Sem --apply só CONTA.
#
# POR QUÊ: o sumário nasceu em 2026-09-24 (lib/calib-expect.sh, relato do Arthur Botelho): quem o grava é
# o /judge/calib-report, a cada calibração. Os problemas calibrados ANTES do deploy têm o resultado das
# soluções em run/calib/<id>/<host>.json, mas não têm sumário — e o Painel os mostraria "sem resultado"
# (pendência `sols_unchecked`) até a próxima calibração de cada um. Este script faz, uma vez, o que o
# calib-report faria: classifica as soluções dos hosts da versão ATUAL do pacote e grava o sumário.
#
# Não muda pacote, não recalibra, não mexe no TL. Custo: a versão do pacote (pkg_judge_version) de cada
# problema — memoizada em run/tl/<id>.pkv; o que não tem memo é hasheado (lê tests/). Rode fora de
# horário de prova e onde a API roda (em produção, DENTRO do container: podman exec systemd-moj-api
# bash /opt/moj/cdmoj/server/bin/calib-summary-rebuild.sh --apply).
set -uo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; _DIR="$HERE/../api/v1"; _LIBDIR="$_DIR/lib"
source "$_LIBDIR/sources.sh" >/dev/null 2>&1 || source "$_LIBDIR/common.sh"
source "$_LIBDIR/tl-store.sh"; source "$_LIBDIR/problems.sh"; source "$_LIBDIR/calib-expect.sh"

APPLY=0; SEL=""
for a in "$@"; do case "$a" in
  --apply) APPLY=1;;
  -h|--help) sed -n '2,14p' "$0"; exit 0;;
  -*) echo "opção desconhecida: $a" >&2; exit 2;;
  *) SEL="$a";;
esac; done
[[ -d "$CALIB_DIR" ]] || { echo "sem $CALIB_DIR — nada a fazer"; exit 0; }
# os ids são os nomes dos diretórios de run/calib (id tem '#', não tem '/')
mapfile -t IDS < <(find "$CALIB_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
  | { if [[ -n "$SEL" ]]; then awk -v s="$SEL" 'index($0, s) == 1'; else cat; fi; } | LC_ALL=C sort)
n=0; ok=0; skip=0; bad=0
for id in "${IDS[@]}"; do
  valid_id "$id" 2>/dev/null || { ((skip++)); continue; }
  pkg="$(pkg_path "$id")"; [[ -n "$pkg" && -d "$pkg" ]] || { ((skip++)); continue; }   # problema que não existe mais
  ((n++))
  (( APPLY )) || continue
  if calx_summary_write "$id"; then ((ok++)); else ((bad++)); echo "  falhou: $id" >&2; fi
done
if (( APPLY )); then
  echo "sumários gravados: $ok · falharam: $bad · ignorados (sem pacote/id inválido): $skip"
  [[ -s "$CAL_SUMMARY" ]] && echo "mapa do Painel: $(jq 'length' "$CAL_SUMMARY") problema(s), $(jq '[.[] | select(.bad > 0)] | length' "$CAL_SUMMARY") com solução divergente"
else
  echo "$n problema(s) calibrado(s) receberiam sumário (ignorados: $skip). Rode com --apply."
fi
