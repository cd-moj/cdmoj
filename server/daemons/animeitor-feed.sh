#!/bin/bash
# animeitor-feed.sh [--once] — o ALIMENTADOR do telão: manda à API do Animeitor o RELÓGIO e as
# SUBMISSÕES de cada contest com o alimentador ligado. Doc: docs/ANIMEITOR.md.
#
# POR QUE EXISTE: o servidor do Animeitor não avança o relógio sozinho ("a controller or feeder must
# send updates") e não puxa nada do juiz — quem fala é o MOJ.
#
# DESENHO
#   · UM processo p/ todos os contests (flock em $RUNDIR/animeitor/feed.lock: subir duas vezes é no-op).
#   · FORA do caminho do julgamento: o judged nunca espera a rede do telão. Se o Animeitor cair, a
#     prova não sente — o alimentador recua (1, 2, 4… até 30 s) e retoma sozinho.
#   · Só olha $RUNDIR/animeitor/active/<contest> (marcador do `start` da rota /contest/animeitor/api):
#     nada de varrer 1.500 diretórios de contest por segundo.
#   · por contest, a cada `feed.clock_s` (1 s): PATCH …/time (timeout 3 s; depois do fim o relógio
#     pára, e o envio cai p/ 1 a cada 30 s); a cada `feed.runs_s` (2 s): as runs, SÓ se algum
#     `history` mudou (find -newer carimbo) — e só o delta (lib/animeitor.sh: an_push_runs); a cada
#     60 s: se o roster/regiões/coortes/config mudaram, republica (an_publish é idempotente por hash).
#     Run recusada por `unknown_team` força a republicação na hora.
#   · 24 h depois do fim da prova o contest sai sozinho (rejulgamento pós-prova ainda corrige runs).
#
# Sobe pelo deploy/moj-entrypoint (laço com respawn; ANIMEITOR_FEED_DISABLE=1 desliga) e, no dev,
# pela unit server/etc/systemd/moj-animeitor-feed.service. `--once` = uma passada (testes).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_conf="$HERE/../etc/common.conf"; [[ -f "$_conf" ]] && source "$_conf"
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
: "${RUNDIR:=/home/ribas/moj/run}"
export CONTESTSDIR RUNDIR
LIB="$HERE/../api/v1/lib"
source "$LIB/common.sh" 2>/dev/null
source "$LIB/cohorts.sh"
source "$LIB/animeitor.sh"

ONCE=0; [[ "${1:-}" == --once ]] && ONCE=1
D="$RUNDIR/animeitor"; ACTIVE="$D/active"; mkdir -p "$ACTIVE"
LOG="$D/feed.log"
log(){ printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG" 2>/dev/null
       [[ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 1048576 ]] && { tail -n 2000 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"; }; return 0; }

exec {LK}>"$D/feed.lock" || exit 1
flock -n "$LK" || { echo "animeitor-feed: já há um alimentador rodando" >&2; exit 0; }

declare -A T_CLOCK=() T_RUNS=() T_CFG=() FAILS=() HOLD=() SIG=() CFG_MT=() C_URL=() C_EV=() C_CK=() C_RN=() FORCE=()

_cfg_load(){ # cacheia url/evento/cadência por contest; relê só quando o animeitor.json muda (mtime)
  local c="$1" f mt j; f="$(an_cfg_file "$c")"; mt="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
  [[ "${CFG_MT[$c]:-}" == "$mt" ]] && return 0
  j="$(an_cfg "$c")"
  C_URL[$c]="$(jq -r .url <<<"$j")"; C_EV[$c]="$(an_enc "$(jq -r .event <<<"$j")")"
  C_CK[$c]="$(jq -r .feed.clock_s <<<"$j")"; C_RN[$c]="$(jq -r .feed.runs_s <<<"$j")"
  [[ "${C_CK[$c]}" =~ ^[0-9]+$ ]] || C_CK[$c]=1; [[ "${C_RN[$c]}" =~ ^[0-9]+$ ]] || C_RN[$c]=2
  CFG_MT[$c]="$mt"
}

_fail(){ # <c> <onde> <http> <msg> — recuo exponencial (teto 30 s); anota o erro no início da série
  local c="$1" n=$(( ${FAILS[$1]:-0} + 1 )) b; FAILS[$c]=$n
  b=$(( n > 5 ? 30 : (1 << (n - 1)) )); (( b > 30 )) && b=30
  HOLD[$c]=$(( EPOCHSECONDS + b ))
  if (( n == 1 || n % 10 == 0 )); then an_fail_note "$c" "$2" "$3" "$4"; log "$c: $2 falhou (HTTP $3) $4 — recuo ${b}s (série $n)"; fi
}
_ok(){ local c="$1"; if (( ${FAILS[$c]:-0} > 0 )); then log "$c: voltou depois de ${FAILS[$c]} falha(s)"; an_status_set "$c" 'del(.last_error)'; fi; FAILS[$c]=0; HOLD[$c]=0; }

_sig(){ # assinatura BARATA do que a publicação leva: o roster da visão `all` + mtime dos 3 jsons + conta mexida
  local c="$1" d="$CONTESTSDIR/$1" acc=""
  [[ -e "$d/var/animeitor-managed.json" ]] && acc="$(find "$d/users" -mindepth 2 -maxdepth 2 -name account.json -newer "$d/var/animeitor-managed.json" -print -quit 2>/dev/null)"
  { bash "$AN_RUNS_SH" "$c" all --teams 2>/dev/null; stat -c '%n %Y' "$d/regions.json" "$d/cohorts.json" "$d/animeitor.json" 2>/dev/null; printf '%s\n' "${acc:+conta-mexida}"; } | md5sum | cut -c1-32
}

feed_one(){
  local c="$1" d="$CONTESTSDIR/$1" now="$EPOCHSECONDS" st
  [[ -f "$d/conf" ]] || { rm -f "$ACTIVE/$c"; log "$c: contest sumiu — desligado"; return 0; }
  an_has_cred "$c" || return 0
  (( now < ${HOLD[$c]:-0} )) && return 0
  _cfg_load "$c"; _an_times "$c"
  if (( AN_END > 0 && now > AN_END + 86400 )); then
    rm -f "$ACTIVE/$c"; an_cfg_save "$c" "$(jq -c '.enabled = false' <<<"$(an_cfg "$c")")"
    log "$c: 24 h depois do fim — alimentador desligado sozinho"; return 0
  fi

  # --- relógio --------------------------------------------------------------------------------
  local every="${C_CK[$c]}"; (( AN_END > 0 && now > AN_END )) && every=30      # prova encerrada: o relógio parou
  if (( now - ${T_CLOCK[$c]:-0} >= every )); then
    T_CLOCK[$c]="$now"
    local t=$(( now - AN_START )); (( t > AN_DUR )) && t=$AN_DUR
    printf '{"time_seconds":%d}' "$t" > "$D/$c.time.json"
    st="$(an_status "$(AN_URL="${C_URL[$c]}" AN_TIMEOUT="${AN_CLOCK_TIMEOUT:-3}" an_curl "$c" PATCH "/internal/events/${C_EV[$c]}/time" "$D/$c.time.json")")"
    printf '%s %s %s\n' "$now" "$t" "${st:-000}" > "$d/var/animeitor.clock" 2>/dev/null
    if [[ "$st" == 200 ]]; then _ok "$c"
    elif [[ "$st" == 404 ]]; then
      # o evento SUMIU lá (alguém apagou no console do Animeitor, ou o servidor perdeu o estado): não adianta
      # insistir no relógio — cai no bloco de configuração, que recria o evento (o managed diz que era nosso)
      # (o managed local dizia que tudo estava lá: zera o hash do EVENTO p/ a publicação não pular por "nada mudou")
      _fail "$c" relogio 404 "o evento não existe no Animeitor — republicando"; FORCE[$c]=1
      [[ -s "$d/var/animeitor-managed.json" ]] && jq -c '.event_hash = "" | .contests = {}' "$d/var/animeitor-managed.json" > "$d/var/animeitor-managed.json.tmp" 2>/dev/null \
        && mv -f "$d/var/animeitor-managed.json.tmp" "$d/var/animeitor-managed.json"; rm -f "$d/var/animeitor-sent.tsv" "$d/var/.animeitor-runs.stamp"
    else _fail "$c" relogio "${st:-000}" "o Animeitor não aceitou o relógio"; return 0; fi
  fi

  # --- configuração (roster/placares): a cada 60 s, ou JÁ quando uma run voltou por time desconhecido
  if (( now - ${T_CFG[$c]:-0} >= 60 )) || [[ "${FORCE[$c]:-0}" == 1 ]]; then
    T_CFG[$c]="$now"
    local s; s="$(_sig "$c")"
    if [[ "${SIG[$c]:-}" != "$s" || "${FORCE[$c]:-0}" == 1 ]]; then
      local of="$D/$c.publish.json"
      if an_publish "$c" "$of" 0; then SIG[$c]="$s"; [[ "$(jq -r '[.event.action, (.contests[]?.action)] | map(select(. != "unchanged")) | length' "$of" 2>/dev/null)" != 0 ]] && log "$c: configuração republicada"
      else log "$c: republicação recusada — $(jq -c '{event, erros: [.contests[]? | select(.action == "error") | .name]}' "$of" 2>/dev/null)"; fi
      rm -f "$of"; FORCE[$c]=0
    fi
  fi

  # --- runs: só se algum history mudou desde a última passada -----------------------------------
  if (( now - ${T_RUNS[$c]:-0} >= ${C_RN[$c]} )); then
    T_RUNS[$c]="$now"
    local stamp="$d/var/.animeitor-runs.stamp" changed=1 res
    if [[ -e "$stamp" && "${FORCE_RUNS:-0}" != 1 ]]; then
      changed=0; [[ -n "$(find "$d/users" -mindepth 2 -maxdepth 2 -name history -newer "$stamp" -print -quit 2>/dev/null)" ]] && changed=1
    fi
    if (( changed )); then
      # carimbo ANTES de ler: o que mudar durante a leitura entra na próxima
      touch "$stamp.new" 2>/dev/null
      res="$(AN_URL="${C_URL[$c]}" an_push_runs "$c")"
      if [[ $? -eq 0 ]]; then
        mv -f "$stamp.new" "$stamp" 2>/dev/null
        [[ "$(jq -r '.ignored // 0' <<<"$res")" != 0 ]] && { FORCE[$c]=1; rm -f "$stamp"; }     # roster atrasado: publica e manda de novo
        [[ "$(jq -r '.sent // 0' <<<"$res")" != 0 ]] && log "$c: runs $(jq -c '{sent, added, updated, ignored, removed}' <<<"$res")"
      else
        rm -f "$stamp.new"; _fail "$c" runs "$(jq -r '.http // "000"' <<<"$res" 2>/dev/null)" "$(jq -r '.error // "sem resposta"' <<<"$res" 2>/dev/null)"
      fi
    fi
  fi
}

log "alimentador no ar (pid $$, once=$ONCE)"
while :; do
  while IFS= read -r c; do
    [[ -n "$c" ]] && valid_id "$c" && feed_one "$c"
  done < <(find "$ACTIVE" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort)
  printf '%s\n' "$EPOCHSECONDS" > "$D/feed.alive" 2>/dev/null
  (( ONCE )) && break
  # dorme até a virada do próximo segundo (o relógio do telão anda em passos de 1 s, sem deriva)
  _us="${EPOCHREALTIME#*[.,]}"; _us="${_us:0:6}"; _us=$(( 10#${_us:-0} ))
  _rem=$(( 1000000 - _us )); (( _rem < 50000 )) && _rem=50000
  if (( _rem >= 1000000 )); then sleep 1; else sleep "0.$(printf '%06d' "$_rem")" 2>/dev/null || sleep 1; fi
done
