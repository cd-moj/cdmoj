#!/usr/bin/env bash
# treino-calib-gen.sh <outfile> — VOLUME de calibrações ao longo do tempo, do log append-only de
# eventos run/updates/log/<host>-<epoch>.log (linhas "[moj-agent HH:MM:SS] cacheado+calibrado <id>").
# Emite {success, calib_per_day:[{day,count}], calib_by_dow_hour:[{dow,hour,n}], total}. O handler
# /treino/admin/calib-activity o cacheia (regen_locked). Dia/dow/hora vêm do EPOCH do nome do log
# (tudo UTC, consistente com os heatmaps de submissão; cada log é uma rodada curta do agente).
# Ressalva: run/ NÃO é versionado e pode rotacionar -> cobertura histórica parcial.
set -u
: "${RUNDIR:=/home/ribas/moj/run}"
LOGDIR="$RUNDIR/updates/log"
OUT="${1:-}"; [[ -n "$OUT" ]] || { echo "uso: treino-calib-gen.sh <outfile>" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")" 2>/dev/null
TMP="$(mktemp "$OUT.XXXXXX")" || { echo "treino-calib-gen: mktemp falhou" >&2; exit 1; }
trap 'rm -f "$TMP"' EXIT
empty='{"success":true,"calib_per_day":[],"calib_by_dow_hour":[],"total":0}'

if [[ ! -d "$LOGDIR" ]]; then printf '%s\n' "$empty" > "$TMP"; mv "$TMP" "$OUT"; exit 0; fi

set +o noglob
# UMA passada de awk sobre TODOS os logs (evita milhares de spawns). FNR==1 -> extrai o epoch do nome
# (dia/dow); conta as linhas "cacheado+calibrado" e a hora (HH). Se o xargs quebrar em lotes, cada END
# emite agregados PARCIAIS que o jq re-soma (group_by) -> correto de qualquer forma.
find "$LOGDIR" -maxdepth 1 -name '*.log' -print0 2>/dev/null \
  | xargs -0 -r awk '
      FNR==1 { f=FILENAME; sub(/.*-/,"",f); sub(/\.log$/,"",f); gsub(/[^0-9]/,"",f);
               ep=f+0; ed=int(ep/86400); day=ed*86400; dow=((ed%7)+4)%7; hh=int((ep%86400)/3600) }
      /cacheado\+calibrado/ { cnt[day]++; hcnt[dow*100+hh]++ }
      END { for (d in cnt) print "D\t" d "\t" cnt[d];
            for (k in hcnt) print "H\t" int(k/100) "\t" (k%100) "\t" hcnt[k] }' 2>/dev/null \
  | jq -R -cs 'split("\n")|map(select(length>0)|split("\t")) as $rows
      | ($rows|map(select(.[0]=="D")|{day:(.[1]|tonumber), n:(.[2]|tonumber)})
          | group_by(.day)|map({day:.[0].day, count:(map(.n)|add)})|sort_by(.day)) as $pd
      | ($rows|map(select(.[0]=="H")|{dow:(.[1]|tonumber), hour:(.[2]|tonumber), n:(.[3]|tonumber)})
          | group_by(.dow*100+.hour)|map({dow:.[0].dow, hour:.[0].hour, n:(map(.n)|add)})|sort_by(.dow*100+.hour)) as $dh
      | {success:true, calib_per_day:$pd, calib_by_dow_hour:$dh, total:(([$pd[].count]|add) // 0)}' \
  > "$TMP" 2>/dev/null || printf '%s\n' "$empty" > "$TMP"
[[ -s "$TMP" ]] || printf '%s\n' "$empty" > "$TMP"
mv "$TMP" "$OUT"
