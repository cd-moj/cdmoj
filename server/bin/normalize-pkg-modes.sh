#!/bin/bash
# normalize-pkg-modes.sh [--apply] [<org>[/<prob>]] — põe os pacotes no MODO CANÔNICO: 644 (arquivo),
# 755 (diretório e arquivo com +x). Roda UMA VEZ, depois do conserto.
#
# POR QUÊ: o fcgiwrap roda com `umask 007` (p/ o socket unix nascer 0770 — senão o nginx do sistema
# toma EACCES), então TODO arquivo que a API gravava saía **660**, enquanto o MESMO pacote vindo de
# `moj upload` (tar+rsync) saía **644**. E o `mojtools/tl-checksum.sh` inclui o **modo** de `scripts/*`
# no hash: o mesmo conteúdo dava checksum diferente conforme o caminho (push × upload) =>
# **recalibração espúria** e conferência "checksum local == servidor" falhando à toa.
# O conserto de verdade está em `_pkg_canon_modes` (lib/problems.sh), que roda nos dois caminhos; este
# script é só p/ o que já foi gravado torto.
#
# ATENÇÃO: mexer no modo de `scripts/*` MUDA o tl-checksum => os problemas com correção especial
# vão pedir recalibração (uma vez). Sem `--apply` só LISTA.
set -uo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"          # .../cdmoj
WS="$(cd "$ROOT/.." && pwd)"                                          # o checkout (workspace)
: "${MOJ_PROBLEMS_DIR:=$WS/moj-problems}"

APPLY=0; SEL=""
for a in "$@"; do case "$a" in
  --apply) APPLY=1;;
  -h|--help) sed -n '2,18p' "$0"; exit 0;;
  *) SEL="$a";;
esac; done

[[ -d "$MOJ_PROBLEMS_DIR" ]] || { echo "sem $MOJ_PROBLEMS_DIR" >&2; exit 1; }
mapfile -t PKGS < <(
  if [[ -n "$SEL" ]]; then printf '%s\n' "$MOJ_PROBLEMS_DIR/$SEL"
  else find "$MOJ_PROBLEMS_DIR" -mindepth 2 -maxdepth 2 -type d ! -name '.git' 2>/dev/null | LC_ALL=C sort; fi)

n=0; touched=0; scripts_touched=0
for p in "${PKGS[@]}"; do
  [[ -d "$p" ]] || continue
  n=$((n+1))
  # o que está fora do canônico? (ignora .git)
  bad="$(find "$p" -name .git -prune -o \( -type f -o -type d \) -printf '%m %y %p\n' 2>/dev/null | awk '
    $2=="d" && $1!="755" {print; next}
    $2=="f" && $1!="644" && $1!="755" {print}')"
  [[ -n "$bad" ]] || continue
  touched=$((touched+1))
  grep -q "/scripts/" <<<"$bad" && scripts_touched=$((scripts_touched+1))
  printf '%s  (%s arquivo(s)/dir(s) fora do canônico%s)\n' "${p#"$MOJ_PROBLEMS_DIR/"}" \
    "$(grep -c . <<<"$bad")" "$(grep -q "/scripts/" <<<"$bad" && echo ', COM scripts/ => recalibra')"
  if (( APPLY )); then
    find "$p" -name .git -prune -o -type d -exec chmod 755 {} + 2>/dev/null
    find "$p" -name .git -prune -o -type f ! -perm -u+x -exec chmod 644 {} + 2>/dev/null
    find "$p" -name .git -prune -o -type f   -perm -u+x -exec chmod 755 {} + 2>/dev/null
  fi
done

printf '\n%s pacote(s) varrido(s); %s fora do canônico (%s com scripts/ => pedem recalibração).\n' \
  "$n" "$touched" "$scripts_touched"
(( APPLY )) && echo "modos normalizados (644/755)." || echo "(dry-run — rode com --apply p/ normalizar)"
