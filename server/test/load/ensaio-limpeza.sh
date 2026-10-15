#!/bin/bash
# ensaio-limpeza.sh <contest zz-…> [--purge] — desmonta o ENSAIO DE ESCRITA (ensaio-fixture.sh).
#   1. CONFERE que nenhum job do ensaio ficou na fila (queue/*), reivindicado (assigned/*) ou no spool: um job órfão
#      julgado DEPOIS da remoção recriaria diretório fantasma no contest removido. Achou? Para — ou, com --purge (ensaio
#      abortado no meio), apaga-os sob a MESMA trava da fila (queue/.lock) e os do spool;
#   2. derruba as sessões `ze*` e o índice de sessões do contest;
#   3. move o contest p/ contests/.trash/<c>-<epoch> — o MESMO destino do /treino/admin/contest-remove (reversível) — e
#      registra no audit do treino.
# RODA DENTRO DO CONTAINER da API (podman exec -i systemd-moj-api bash -s <contest> [--purge] < ensaio-limpeza.sh).
set -u
export CONTESTSDIR="${CONTESTSDIR:-/data/contests}" RUNDIR="${RUNDIR:-/data/run}"
: "${APIDIR:=/opt/moj/cdmoj/server/api/v1}"
C="${1:?uso: ensaio-limpeza.sh <contest zz-…> [--purge]}"; PURGE=0; [[ "${2:-}" == --purge ]] && PURGE=1
[[ "$C" == zz-* ]] || { echo "ABORTO: só limpa contest de ensaio (zz-…)"; exit 1; }
CD="$CONTESTSDIR/$C"; [[ -f "$CD/conf" ]] || { echo "contest $C não existe"; exit 1; }
grep -q '^DEMO=1' "$CD/conf" || { echo "ABORTO: $C não é DEMO"; exit 1; }
cd "$APIDIR" && export _DIR="$APIDIR" && source lib/sources.sh >/dev/null 2>&1
set +o noglob; shopt -s nullglob
SESSIONDIR="${SESSIONDIR:-$RUNDIR/sessions}"; Q="$RUNDIR/queue"; AS="$RUNDIR/assigned"

# ---- 1. jobs do ensaio ainda vivos? -----------------------------------------------------------------------------
# ⚠ NUNCA `grep/cat <glob>` aqui: com nullglob, glob vazio = comando SEM arquivo = lê o STDIN — e este script roda
# por `bash -s < script`: o stdin é o PRÓPRIO script (o resto dele seria engolido). Sempre via find … -exec.
mapfile -t jobs < <(find "$Q" "$AS" -mindepth 2 -maxdepth 2 -name '*.json' -exec grep -lF "\"contest\":\"$C\"" {} + 2>/dev/null)
mapfile -t spool < <(find "$RUNDIR/spool/submissions" -maxdepth 2 -type f -name "$C:*" 2>/dev/null)
echo "jobs do ensaio na fila/reivindicados: ${#jobs[@]} · no spool: ${#spool[@]}"
if (( ${#jobs[@]} + ${#spool[@]} > 0 )); then
  (( PURGE )) || { echo "PARADO: há trabalho do ensaio em voo — espere o dreno do injetor (pendentes = 0) ou repita com --purge"; exit 2; }
  ( flock -w 30 9 || exit 1; rm -f -- "${jobs[@]}" "${jobs[@]/%.json/.cmeta}" ) 9>"$Q/.lock"
  rm -f -- "${spool[@]}"
  echo "purgados: ${#jobs[@]} job(s) e ${#spool[@]} arquivo(s) de spool"
fi

# ---- 2. sessões -------------------------------------------------------------------------------------------------
ns="$(find "$SESSIONDIR" -maxdepth 1 -type f -name 'ze[0-9a-f]*' | wc -l)"   # find: com nullglob, `ls glob-vazio` listaria o cwd
rm -f "$SESSIONDIR"/ze[0-9a-f]* 2>/dev/null; rm -rf "$SESSIONDIR/.idx/$C" 2>/dev/null
echo "sessões removidas: $ns"

# ---- 3. o contest p/ a lixeira (como o contest-remove) ----------------------------------------------------------
nu="$(find "$CD/users" -mindepth 1 -maxdepth 1 -type d | wc -l)"
nh="$(find "$CD/users" -mindepth 2 -maxdepth 2 -name history -exec cat {} + 2>/dev/null | wc -l)"
du_c="$(du -sh "$CD" 2>/dev/null | cut -f1)"
trash="$CONTESTSDIR/.trash"; mkdir -p "$trash"
mv "$CD" "$trash/$C-$EPOCHSECONDS" || { echo "falhou mover p/ a lixeira"; exit 1; }
SESSION_LOGIN=ops/ensaio audit_log_to treino contest-remove "id=$C motivo=ensaio-de-escrita contas=$nu envios=$nh tamanho=$du_c"
echo "contest movido p/ .trash/$C-$EPOCHSECONDS (contas $nu · envios no history $nh · $du_c)"
