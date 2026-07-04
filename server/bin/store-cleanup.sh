#!/usr/bin/env bash
# store-cleanup.sh <contest> [--apply]
#
# Limpa os RESÍDUOS do modelo pré-reforma num contest que JÁ usa o store por-usuário
# (caso do treino, migrado antes do corte): move para .legacy-store/ (nada é deletado)
#   controle/ (history congelado, *.d, *.score, placares antigos), data/, passwd,
#   .passwd.lock, var/profiles/ e os flat submissions/ mojlog/ results/ log/ do contest
# (os órfãos que a migração não roteou). Também remove a linha USER_STORE= do conf
# (ninguém mais a lê) e toca var/.score-dirty p/ o próximo regen preguiçoso.
#
# DRY-RUN por padrão; --apply move de fato.
set -uo pipefail

CONTEST="${1:?uso: store-cleanup.sh <contest> [--apply]}"
APPLY=0; [[ "${2:-}" == "--apply" ]] && APPLY=1
: "${CONTESTSDIR:=/home/ribas/moj/contests}"

CDIR="$CONTESTSDIR/$CONTEST"
[[ -d "$CDIR" && -f "$CDIR/conf" ]] || { echo "store-cleanup: contest não encontrado: $CDIR" >&2; exit 1; }
[[ -d "$CDIR/users" ]] || { echo "store-cleanup: $CONTEST não usa o store por-usuário (sem users/) — use store-migrate.sh" >&2; exit 1; }

mode="DRY-RUN"; (( APPLY )) && mode="APPLY"
say(){ printf '%s\n' "$*" >&2; }
say "== store-cleanup ($mode) contest=$CONTEST =="

LEG="$CDIR/.legacy-store"
n=0
stash(){ # <path relativo ao contest>
  local p="$CDIR/$1"
  [[ -e "$p" ]] || return 0
  local sz; sz="$(du -sh "$p" 2>/dev/null | cut -f1)"
  ((n++))
  if (( APPLY )); then mkdir -p "$LEG"; mv -f -- "$p" "$LEG/${1//\//__}"; fi
  say "  stash: $1 ($sz)"
}

# placar-custom (modo outro) é VIVO: vai p/ var/ (o resto do placar é regenerado)
if [[ -f "$CDIR/controle/placar-custom.txt" ]]; then
  (( APPLY )) && { mkdir -p "$CDIR/var"; mv -f "$CDIR/controle/placar-custom.txt" "$CDIR/var/placar-custom.txt"; }
  say "  placar-custom.txt → var/"
fi
stash controle
stash data
stash passwd
stash .passwd.lock
stash var/profiles
stash submissions
stash mojlog
stash results
stash log
say "  itens movidos p/ .legacy-store/: $n"

# remove a linha USER_STORE= do conf (flag morta; o conf é sourced — reescrita atômica)
if grep -q '^USER_STORE=' "$CDIR/conf" 2>/dev/null; then
  if (( APPLY )); then
    tmp="$(mktemp "$CDIR/conf.XXXXXX")" && grep -v '^USER_STORE=' "$CDIR/conf" > "$tmp" \
      && cat "$tmp" > "$CDIR/conf" && rm -f "$tmp"
  fi
  say "  conf: linha USER_STORE removida"
fi

if (( APPLY )); then mkdir -p "$CDIR/var"; touch "$CDIR/var/.score-dirty"; fi
say "== fim ($mode) =="
