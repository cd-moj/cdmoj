#!/bin/bash
# carga-gerador.sh <tokens-teams> <tokens-staff> <dur_s> <out.log> [contest=zz-carga-2026] [fator×10=10]
# (roda nas MÁQUINAS GERADORAS — frota da chococino e/ou a dev — nunca no servidor)
#
# O 6º arg ACELERA o relógio dos clientes preservando o MIX: 25 = todo mundo pola 2,5× mais
# rápido (updates 30s→12s, fila 15-20s→6-8s, score 45s→18s). É como se atinge N× o req/s do
# teste base com a MESMA distribuição de rotas/balões — 12k clientes a 2,5× ≈ 28k clientes
# reais, e o servidor não distingue (validado: fator 10 = ~430 req/s; fator 25 → ~1000 req/s).
# v2: --compressed (como navegador), log de BYTES (verificação de conteúdo),
#     staff busca PDF de balão pendente (5% dos ciclos — é o que dispara magick no servidor),
#     time manda pedido de impressão (0,1% dos ciclos).
# log: <epoch> <rota> <código> <tempo> <bytes>
set -u
TT="$1"; TS="$2"; DUR="$3"; OUT="$4"
CONTEST="${5:-zz-carga-2026}"
B="https://$CONTEST.moj.naquadah.com.br"
Q="contest=$CONTEST"
FA="${6:-10}"                                    # fator ×10 (inteiro; 10 = ritmo real)
SCORE_IV=$(( 450 / FA ))                         # intervalo do score em segundos, já acelerado
END=$(( $(date +%s) + DUR ))
# sleep acelerado sem fork: décimos de segundo por aritmética pura de bash
slp(){ local ds=$(( $1 * 100 / FA )); (( ds < 5 )) && ds=5; sleep "$(( ds/10 )).$(( ds%10 ))"; }
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
    if (( score && now - last_s >= SCORE_IV )); then req "$tok" "contest/score?$Q" score; last_s=$now; fi
    if (( RANDOM % 1000 == 0 )); then
      reqpost "$tok" "contest/print?$Q" printreq "{\"filename\":\"sol.c\",\"file_b64\":\"$SRC_B64\"}"
    fi
    slp $(( 30 + RANDOM % 4 ))
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
    slp $(( 15 + RANDOM % 6 ))
  done
  rm -f "$qf"
}

i=0
while IFS= read -r tok; do [[ -n "$tok" ]] && team "$tok" "$i" & i=$((i+1)); done < "$TT"
while IFS= read -r tok; do [[ -n "$tok" ]] && staffp "$tok" & done < "$TS"
echo "gerador-v2: $(wc -l < "$TT") times + $(wc -l < "$TS") staff por ${DUR}s"
wait
echo FIM
