#!/usr/bin/env bash
# contest-modules-detect.sh [--apply] [--only <id>] [-q]
# Detecção ÚNICA dos módulos de um contest a partir dos ARTEFATOS que ele já tem (lib/modules.sh
# mod_detect: regions.json → sedes, ua-gate/trava/nutella → maquinas, rounds.json → rodadas,
# docs/config.json → documentos, balloons.json → baloes, cohorts.json → coortes,
# registrations.json → inscricoes, webcast/fotos → telao, classification.json → classificacao).
# Sem --apply é DRY-RUN: só lista. Com --apply grava CONTEST_MODULES (união com o que já está
# ligado) só onde muda, e audita (modules-detect). Idempotente: 2ª rodada = 0 mudanças.
# Saída: TSV `contest<TAB>decisão<TAB>módulos<TAB>motivos` no stdout; resumo no stderr.
# Estado de runtime (roda uma vez na produção depois do deploy) — não é código do request.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_DIR="$HERE/../api/v1"
source "$_DIR/lib/common.sh"; source "$_DIR/lib/modules.sh"; source "$_DIR/lib/auth.sh"
source "$_DIR/lib/users.sh"; source "$_DIR/lib/contest-create.sh"
set +o noglob   # o prelúdio da API desliga o glob; aqui a varredura de contests/*/conf precisa dele
APPLY=0; ONLY=""; QUIET=0
while (( $# )); do
  case "$1" in
    --apply) APPLY=1;; --only) ONLY="${2:-}"; shift;; -q) QUIET=1;;
    -h|--help) sed -n 2,10p "$0"; exit 0;;
    *) echo "opção desconhecida: $1" >&2; exit 2;;
  esac; shift
done
export SESSION_LOGIN="bin/contest-modules-detect"
n=0; nnew=0; nskip=0; nnone=0
for cf in "$CONTESTSDIR"/*/conf; do
  [[ -f "$cf" ]] || continue
  c="${cf%/conf}"; c="${c##*/}"
  [[ "$c" == treino ]] && continue
  [[ -n "$ONLY" && "$c" != "$ONLY" ]] && continue
  valid_id "$c" || continue
  n=$((n+1))
  cur="$(mod_raw "$c")"
  found=""; why=""
  for m in "${MODULES[@]}"; do
    r="$(mod_detect "$c" "$m")" && { found="${found:+$found,}$m"; why="${why:+$why }$m=$r"; }
  done
  new="$(mod_normalize "${cur:+$cur,}$found")"
  if [[ -z "$found" ]]; then
    nnone=$((nnone+1)); (( QUIET )) || printf '%s\tnenhum\t%s\t-\n' "$c" "${cur:--}"
  elif [[ "$new" == "$cur" ]]; then
    nskip=$((nskip+1)); (( QUIET )) || printf '%s\tja-ligado\t%s\t%s\n' "$c" "$cur" "$why"
  else
    nnew=$((nnew+1)); printf '%s\t%s\t%s\t%s\n' "$c" "$([[ $APPLY == 1 ]] && echo LIGADO || echo ligaria)" "$new" "$why"
    if (( APPLY )); then
      mod_set "$c" "$new"
      audit_log_to "$c" modules-detect "de=${cur:--} para=$new ($why)"
    fi
  fi
done
echo "contests: $n · com módulo novo: $nnew · já ligados: $nskip · sem artefato: $nnone$([[ $APPLY == 1 ]] || echo ' — dry-run: use --apply p/ gravar')" >&2
