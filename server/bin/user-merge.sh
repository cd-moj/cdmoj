#!/usr/bin/env bash
# user-merge.sh <contest> <de> <para> [--apply]
#
# Funde um DIRETÓRIO DE USUÁRIO ÓRFÃO (users/<de>/ SEM account.json) na conta viva
# users/<para>/. Órfão nasce assim: a conta é um diretório e rename é `mv` do diretório —
# uma sessão aberta ANTES da troca de handle continuava autenticada com o login velho e o
# /submit (mkdir -p) recriava o diretório do nome antigo. O furo foi fechado em
# lib/auth.sh (sessão morre com a conta) + rename_contest_sessions; esta ferramenta é o
# conserto do dado que já ficou para trás.
#
# O que faz: history (concatena e ORDENA por epoch), submissions/ results/ mojlog/ (move,
# nunca sobrescreve), metrics_recompute + var/.score-dirty (os caches por evento —
# problem-stats — regeneram sozinhos), e o login do var/editor-log.
# O que NÃO faz de propósito: var/access.log, var/activity-*.log e run/spool/ são TRILHA DE
# AUDITORIA (registram o que de fato aconteceu, com IP e hora) — não se reescreve.
#
# Nada é apagado: o dir esvaziado vai p/ contests/<c>/var/merged/<de>.<epoch>/.
# DRY-RUN por padrão; --apply mexe de fato.
#
# ⚠ Na PRODUÇÃO os caminhos vêm do ambiente (a API roda de imagem; o checkout do host não tem
# etc/common.conf), e o dono dos arquivos é o usuário `moj`:
#   sudo -u moj env CONTESTSDIR=/home/moj/moj/contests RUNDIR=/home/moj/moj/run \
#        bash server/bin/user-merge.sh treino <de> <para> [--apply]
set -uo pipefail

CONTEST="${1:?uso: user-merge.sh <contest> <de> <para> [--apply]}"
FROM_L="${2:?uso: user-merge.sh <contest> <de> <para> [--apply]}"
TO_L="${3:?uso: user-merge.sh <contest> <de> <para> [--apply]}"
APPLY=0; [[ "${4:-}" == "--apply" ]] && APPLY=1

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DIR/../api/v1/lib/common.sh"
source "$_DIR/../api/v1/lib/users.sh"
set +o noglob; shopt -s nullglob

mode="DRY-RUN"; (( APPLY )) && mode="APPLY"
say(){ printf '%s\n' "$*" >&2; }
die(){ printf 'user-merge: %s\n' "$*" >&2; exit 1; }

CDIR="$CONTESTSDIR/$CONTEST"
[[ -d "$CDIR" && -f "$CDIR/conf" ]] || die "contest não encontrado: $CDIR"
[[ -d "$CDIR/users" ]]             || die "$CONTEST não usa o store por-usuário (sem users/)"
valid_id "$FROM_L" || die "login de origem inválido: $FROM_L"
valid_id "$TO_L"   || die "login de destino inválido: $TO_L"
[[ "$FROM_L" != "$TO_L" ]] || die "origem e destino são o mesmo login"

DE="$CDIR/users/$FROM_L"; PARA="$CDIR/users/$TO_L"
[[ -d "$DE" ]]                || die "origem não existe: users/$FROM_L"
[[ -f "$PARA/account.json" ]] || die "destino não é uma conta viva (sem account.json): users/$TO_L"
# fundir duas contas REAIS é outra operação (senha, perfil, Telegram, orgs, limite de trocas):
# esta ferramenta só recolhe resíduo.
[[ -f "$DE/account.json" ]] && die "users/$FROM_L TEM account.json — é conta viva, não resíduo"
# em contest com USERS_FROM, dir local sem account.json é PARTICIPANTE COMPARTILHADO (a
# identidade mora na fonte) — legítimo, não é órfão.
src="$(sed -n 's/^[[:space:]]*USERS_FROM=//p' "$CDIR/conf" 2>/dev/null | tail -1)"
src="${src//\'/}"; src="${src//\"/}"
if [[ -n "$src" && "$src" != "$CONTEST" && -f "$CONTESTSDIR/$src/users/$FROM_L/account.json" ]]; then
  die "users/$FROM_L é participante compartilhado de '$src' (conta viva lá) — não é resíduo"
fi

say "== user-merge ($mode) contest=$CONTEST  $FROM_L → $TO_L =="

# --- history: concatena e ordena por epoch (1º campo; o veredicto contém ':', então NUNCA
# cortar por coluna fixa — só o 1º campo é seguro)
nl_de=0; [[ -f "$DE/history" ]]   && nl_de="$(wc -l < "$DE/history")"
nl_pa=0; [[ -f "$PARA/history" ]] && nl_pa="$(wc -l < "$PARA/history")"
say "-- history: $nl_pa (destino) + $nl_de (origem) = $(( nl_pa + nl_de )) linhas"
if (( APPLY && nl_de )); then
  [[ -f "$PARA/history" ]] || : > "$PARA/history"
  tmp="$(mktemp "$PARA/history.XXXXXX")" || die "mktemp falhou"
  # o history da origem NÃO é truncado: ele viaja inteiro p/ o arquivo morto (evidência).
  # Fora de users/*, não conta duas vezes no emit_history_stream.
  if LC_ALL=C sort -t: -k1,1n -s -- "$PARA/history" "$DE/history" > "$tmp" 2>/dev/null; then
    cat "$tmp" > "$PARA/history"; rm -f "$tmp"
  else rm -f "$tmp"; die "falha ao ordenar o history"; fi
fi

# --- arquivos por submissão (subid é md5: colisão só se o MESMO subid já existir lá)
n_mv=0; n_col=0
for sub in submissions results mojlog; do
  [[ -d "$DE/$sub" ]] || continue
  for f in "$DE/$sub"/*; do
    [[ -f "$f" ]] || continue
    b="${f##*/}"
    if [[ -e "$PARA/$sub/$b" ]]; then say "  ! colisão (mantido o do destino): $sub/$b"; ((n_col++)); continue; fi
    ((n_mv++))
    (( APPLY )) && { mkdir -p "$PARA/$sub"; mv -f -- "$f" "$PARA/$sub/$b"; }
  done
done
say "-- arquivos: $n_mv movido(s), $n_col colisão(ões)"

# --- editor-log (var/<epoch>:<subid>:<login>:<editor>) — alimenta o card "editor da semana"
EL="$CDIR/var/editor-log"
if [[ -f "$EL" ]]; then
  n_el="$(awk -F: -v o="$FROM_L" 'NF>=4 && $3==o{n++} END{print n+0}' "$EL" 2>/dev/null)"
  if (( ${n_el:-0} > 0 )); then
    say "-- editor-log: ${n_el} linha(s) $FROM_L → $TO_L"
    if (( APPLY )); then
      tmp="$(mktemp "$EL.XXXXXX")" \
        && awk -F: -v OFS=: -v o="$FROM_L" -v n="$TO_L" 'NF>=4 && $3==o{$3=n} {print}' "$EL" > "$tmp" \
        && cat "$tmp" > "$EL" && rm -f "$tmp"
    fi
  fi
fi

# --- avisos: coisas que a fusão NÃO resolve sozinha
tgi="$CDIR/var/telegram/by-login/$FROM_L"
[[ -e "$tgi" ]] && say "  ! ATENÇÃO: existe índice Telegram p/ '$FROM_L' (var/telegram/by-login) — confira à mão"
for extra in "$DE"/*; do
  b="${extra##*/}"
  [[ "$b" == history || "$b" == metrics.json || "$b" == submissions || "$b" == results || "$b" == mojlog ]] && continue
  say "  ! sobrou em users/$FROM_L: $b (vai inteiro p/ o arquivo morto)"
done

# --- métricas do destino + placar sujo (regenera os caches por evento)
if (( APPLY )); then
  metrics_recompute "$CONTEST" "$TO_L" || say "  ! metrics_recompute falhou p/ $TO_L"
  _score_dirty "$CONTEST"
  say "-- metrics de $TO_L recomputadas; var/.score-dirty tocado"
else
  say "-- (com --apply: metrics de $TO_L recomputadas + var/.score-dirty)"
fi

# --- arquiva o resíduo (nada é deletado; fora do glob de users/*)
ARCH="$CDIR/var/merged/$FROM_L.$EPOCHSECONDS"
say "-- arquivo morto: var/merged/$FROM_L.$EPOCHSECONDS"
if (( APPLY )); then
  mkdir -p "$CDIR/var/merged" && mv -- "$DE" "$ARCH" || die "falha ao arquivar users/$FROM_L"
fi

say "== fim ($mode) =="
(( APPLY )) || say "   (nada foi alterado — repita com --apply)"
