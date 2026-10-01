#!/bin/bash
# function-langs-migrate.sh [--apply] [<org>[/<prob>]] — declara `FUNCTION_LANGS` no conf dos pacotes
# de SUBMISSÃO DE FUNÇÃO que já existem (2026-09-30). Sem --apply só LISTA.
#
# POR QUÊ: a linha `FUNCTION_LANGS=c,py` (docs/PACOTE.md, "Submissão de função") diz ao editor do aluno —
# o treino e o módulo `esqueletos` do contest — que naquelas linguagens o aluno escreve SÓ a função: o
# editor abre VAZIO, sem o esqueleto com `main` (que dava CE por main duplicado). É DECLARADA pelo autor
# (decisão do Ribas): ter `scripts/<lang>/compile.sh` não basta, o slot COMPILE também é ban e
# OpenMP/MPI. Os pacotes de antes não têm a linha; este script a PROPÕE pela heurística do mojtools
# (`fn/driver-langs.sh`: o compile.sh escreve um `main` num heredoc — 156 drivers e 45 sem driver no
# acervo de 30/09/2026, nenhum ambíguo).
# O que faz, pacote a pacote:
#   - driver em heredoc e SEM a linha  -> `FUNCTION_LANGS=<as linguagens>` no COMEÇO do conf;
#   - a linha já existe                 -> só LISTA se diverge da heurística (o autor decidiu; não mexe);
#   - pacote SEM conf                   -> só LISTA (criar um conf mudaria o tl-checksum).
# Um commit por pacote (autor `moj`) e, no fim, o reindex dos tocados (reindex-all.sh --only), p/ o json
# servível ganhar o `function_langs`.
#
# NADA RECALIBRA: o tl-checksum ignora a linha (mojtools/tl-checksum.sh, como o SAMPLE). ⚠ Por isso a
# ORDEM do deploy importa: o mojtools com esse filtro tem de estar no servidor E nos juízes ANTES desta
# migração — juiz com o mojtools velho calcularia outro checksum nos pacotes migrados.
# ⚠ Os pacotes mudam de `rev` (a trava de edição): quem tem clone local desses problemas leva 409 no
# próximo `moj push` e resolve com `moj pull`.
#
# Rode onde a API roda (em produção, DENTRO do container: podman exec systemd-moj-api bash
# /opt/moj/cdmoj/server/bin/function-langs-migrate.sh), fora de horário de prova (um pandoc por
# enunciado no reindex).
set -uo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; _DIR="$HERE/../api/v1"; _LIBDIR="$_DIR/lib"
source "$_LIBDIR/sources.sh" >/dev/null 2>&1 || source "$_LIBDIR/common.sh"
source "$_LIBDIR/problems.sh"

APPLY=0; SEL=""
for a in "$@"; do case "$a" in
  --apply) APPLY=1;;
  -h|--help) sed -n '2,30p' "$0"; exit 0;;
  -*) echo "opção desconhecida: $a" >&2; exit 2;;
  *) SEL="$a";;
esac; done
[[ -d "$MOJ_PROBLEMS_DIR" ]] || { echo "sem $MOJ_PROBLEMS_DIR" >&2; exit 1; }
DRV="$MOJTOOLS_DIR/fn/driver-langs.sh"
[[ -f "$DRV" ]] || { echo "sem $DRV — atualize o mojtools antes (git pull)" >&2; exit 1; }
mapfile -t PKGS < <(
  if [[ -n "$SEL" ]]; then find "$MOJ_PROBLEMS_DIR/$SEL" -maxdepth 1 -mindepth 0 -type d -path "$MOJ_PROBLEMS_DIR/*/*" ! -name .git 2>/dev/null
  else find "$MOJ_PROBLEMS_DIR" -mindepth 2 -maxdepth 2 -type d ! -name '.git' 2>/dev/null; fi | LC_ALL=C sort)
_rx(){ sed 's/[].[*^$()+?{}|\\]/\\&/g' <<<"$1"; }   # id -> regex literal

n=0; todo=0; skipped=0; differ=0; ids=()
for p in "${PKGS[@]}"; do
  [[ -d "$p/scripts" ]] || continue
  drv="$(bash "$DRV" "$p" 2>/dev/null | paste -sd, -)"
  [[ -n "$drv" ]] || continue
  n=$((n+1)); rel="${p#"$MOJ_PROBLEMS_DIR/"}"
  cur="$(sed -nE 's/^[[:space:]]*FUNCTION_LANGS=["'"'"']?([^"'"'"'#]*).*/\1/p' "$p/conf" 2>/dev/null | tail -1)"
  if grep -qE '^[[:space:]]*FUNCTION_LANGS[[:space:]]*=' "$p/conf" 2>/dev/null; then
    if [[ "$(tr ', ' '\n\n' <<<"$cur" | grep -v '^$' | sort -u | paste -sd,)" != "$(tr ',' '\n' <<<"$drv" | sort -u | paste -sd,)" ]]; then
      echo "$rel: declarado FUNCTION_LANGS=$cur, driver em $drv — o autor decide (não mexe)"; differ=$((differ+1))
    fi
    continue
  fi
  if [[ ! -f "$p/conf" ]]; then echo "$rel: SEM conf — pulado (driver em $drv; crie o conf à mão: muda o tl-checksum)"; skipped=$((skipped+1)); continue; fi
  todo=$((todo+1)); echo "$rel  + FUNCTION_LANGS=$drv"
  (( APPLY )) || continue
  tmp="$(mktemp)"; { printf 'FUNCTION_LANGS=%s\n' "$drv"; cat "$p/conf"; } > "$tmp" && cat "$tmp" > "$p/conf"; rm -f "$tmp"
  if problem_commit "$p" moj "submissão de função: FUNCTION_LANGS=$drv (o editor do aluno abre vazio nessas linguagens; ver docs/PACOTE.md)" >/dev/null 2>&1; then
    ids+=("${rel%%/*}#${rel#*/}")
  else echo "   ⚠ $rel: commit falhou" >&2; fi
done

printf '\n%s pacote(s) com driver de função; %s a migrar; %s sem conf (pulados); %s já declarado(s) com divergência (à mão).\n' "$n" "$todo" "$skipped" "$differ"
(( APPLY )) || { echo "(dry-run — nada foi alterado; repita com --apply)"; exit 0; }
(( ${#ids[@]} )) || exit 0
rx="^($(for i in "${ids[@]}"; do _rx "$i"; done | paste -sd'|'))\$"
echo ">> reindexando ${#ids[@]} problema(s)…"
bash "$HERE/reindex-all.sh" --only "$rx"
