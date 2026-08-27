#!/bin/bash
# carga-gerador.sh <tokens-teams> <tokens-staff> <dur_s> <out.log> [contest=zz-carga-2026]
# (roda nas MÁQUINAS GERADORAS — frota da chococino e/ou a dev — nunca no servidor)
# v2: --compressed (como navegador), log de BYTES (verificação de conteúdo),
#     staff busca PDF de balão pendente (5% dos ciclos — é o que dispara magick no servidor),
#     time manda pedido de impressão (0,1% dos ciclos).
# log: <epoch> <rota> <código> <tempo> <bytes>
set -u
TT="$1"; TS="$2"; DUR="$3"; OUT="$4"
CONTEST="${5:-zz-carga-2026}"
B="https://$CONTEST.moj.naquadah.com.br"
Q="contest=$CONTEST"
END=$(( $(date +%s) + DUR ))
: > "$OUT"
SRC_B64="$(printf '#include <stdio.h>\nint main(){ printf("carga\\n"); return 0; }\n' | base64 | tr -d '\n')"

req(){ # <token> <rota> <tag>
  local r; r="$(curl -sk --compressed -o /dev/null -m 25 \
      -w '%{http_code} %{time_total} %{size_download}' \
      -H "Authorization: Bearer $1" "$B/api/v1/$2" 2>/dev/null)"
  echo "$(date +%s) $3 ${r:-000 25.0 0}" >> "$OUT"
}
reqpost(){ # <token> <rota> <tag> <json>
  local r; r="$(curl -sk --compressed -o /dev/null -m 25 -X POST \
      -H 'Content-Type: application/json' -H "Authorization: Bearer $1" \
      -w '%{http_code} %{time_total} %{size_download}' -d "$4" "$B/api/v1/$2" 2>/dev/null)"
  echo "$(date +%s) $3 ${r:-000 25.0 0}" >> "$OUT"
}

team(){ local tok="$1" idx="$2"
  sleep $(( RANDOM % 150 ))
  for r in basic problems navbuttons rounds balloons; do req "$tok" "contest/$r?$Q" "$r"; done
  local score=$(( idx % 2 )) last_s=0 now
  while now=$(date +%s); (( now < END )); do
    req "$tok" "contest/updates?$Q&news_since=0&clar_since=0" updates
    if (( score && now - last_s >= 45 )); then req "$tok" "contest/score?$Q" score; last_s=$now; fi
    if (( RANDOM % 1000 == 0 )); then
      reqpost "$tok" "contest/print?$Q" printreq "{\"filename\":\"sol.c\",\"file_b64\":\"$SRC_B64\"}"
    fi
    sleep $(( 30 + RANDOM % 4 ))
  done
}
staffp(){ local tok="$1"
  sleep $(( RANDOM % 150 ))
  local qf; qf="$(mktemp)"
  while (( $(date +%s) < END )); do
    # a cada ciclo, a fila; em 5% deles, com corpo — para achar um balão pendente e buscar o PDF
    if (( RANDOM % 20 == 0 )); then
      local r id
      r="$(curl -sk --compressed -o "$qf" -m 25 -w '%{http_code} %{time_total} %{size_download}' \
           -H "Authorization: Bearer $tok" "$B/api/v1/contest/staff/queue?$Q" 2>/dev/null)"
      echo "$(date +%s) queue ${r:-000 25.0 0}" >> "$OUT"
      id="$(grep -o '"id":"bln[a-f0-9]*"' "$qf" 2>/dev/null | head -20 | shuf -n1 | cut -d'"' -f4)"
      [[ -n "$id" ]] && req "$tok" "contest/staff/print-pdf?$Q&id=$id" pdf
    else
      req "$tok" "contest/staff/queue?$Q" queue
    fi
    sleep $(( 15 + RANDOM % 6 ))
  done
  rm -f "$qf"
}

i=0
while IFS= read -r tok; do [[ -n "$tok" ]] && team "$tok" "$i" & i=$((i+1)); done < "$TT"
while IFS= read -r tok; do [[ -n "$tok" ]] && staffp "$tok" & done < "$TS"
echo "gerador-v2: $(wc -l < "$TT") times + $(wc -l < "$TS") staff por ${DUR}s"
wait
echo FIM
