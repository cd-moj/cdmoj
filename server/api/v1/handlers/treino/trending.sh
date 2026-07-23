# GET /treino/trending
# Top-N problemas por SUBMISSÕES (todas, não só aceitas) nos ÚLTIMOS 7 DIAS (janela móvel) —
# alimenta o estado inicial da página do Treino Livre ("🔥 Mais enviados na última semana").
# Anônimo. Cache var/trending.json invalidado POR EVENTO: var/.score-dirty (submissão julgada
# muda a contagem) e var/.treino-list-dirty (problema despublicado tem de SUMIR — privacidade).
# PISO LONGO de 6h: a janela é semanal, ninguém precisa de frescor de minutos — a varredura do
# history de ~927 contas é cara, então regenera no MÁX. 1×/6h. flock contra stampede.
set +o noglob

TREINO="$CONTESTSDIR/treino"
JDIR="$TREINO/var/jsons"        # índice VIVO (título = display_title)
QDIR="$TREINO/var/questoes"     # índice legado (fallback histórico)
CACHE="$TREINO/var/trending.json"
DIRTY="$TREINO/var/.score-dirty"; LSTAMP="$TREINO/var/.treino-list-dirty"
N=10; WINDOW=$(( EPOCHSECONDS - 7*86400 ))

_trfresh(){ [[ -f "$CACHE" ]] \
  && { { [[ ! "$DIRTY" -nt "$CACHE" ]] && [[ ! "$LSTAMP" -nt "$CACHE" ]]; } \
       || [[ -z "$(find "$CACHE" -mmin +360 2>/dev/null)" ]]; }; }
if _trfresh; then emit_json 200 OK; cat "$CACHE"; exit 0; fi
mkdir -p "$TREINO/var"
exec 8>>"$CACHE.lock"; flock 8
if _trfresh; then emit_json 200 OK; cat "$CACHE"; exit 0; fi   # regenerado na espera

HIST="$(mktemp)"; trap '[[ -n "$HIST" ]] && rm -f "$HIST"' EXIT
emit_history_stream treino > "$HIST"

# título do problema (probid usa '#'); índice vivo -> legado -> o próprio id
_title(){ local p="$1" ttl
  ttl="$(jq -r '.title // empty' "$JDIR/$p.json" 2>/dev/null)"
  [[ -n "$ttl" ]] && { printf '%s' "$ttl"; return; }
  [[ -f "$QDIR/$p/title" ]] && { cat "$QDIR/$p/title"; return; }
  printf '%s' "${p/\#/.}"; }
# ANÔNIMO: esconde o que o sistema SABE ser privado (json só em jsons-private/, não em jsons/).
# Sem isto, um problema privado (prova em elaboração) que alguém enviou vazaria id/título/link.
_private(){ [[ ! -f "$JDIR/$1.json" && -f "$TREINO/var/jsons-private/$1.json" ]]; }

# top por submissões na janela; over-fetch (40) p/ sobrar N após remover privados.
declare -a P
while read -r total prob; do
  [[ -z "$prob" ]] && continue
  (( ${#P[@]} >= N )) && break
  _private "$prob" && continue
  P+=( "$(jq -cn --arg pid "$prob" --arg title "$(_title "$prob")" --argjson n "$total" \
      --arg url "/treino/problema/?id=${prob//\#/%23}" \
      '{id:$pid, title:$title, count:$n, url:$url}')" )
done <<< "$(awk -F: -v s="$WINDOW" '$6>=s {print $3}' "$HIST" \
            | sort | uniq -c | sort -rn | head -n 40 | awk '{print $1, $2}')"

jarr(){ if (( $# == 0 )); then printf '[]'; else printf '%s\n' "$@" | jq -cs .; fi; }
out="$(jq -cn --argjson problems "$(jarr "${P[@]}")" --argjson now "$EPOCHSECONDS" \
  '{success:true, window_days:7, generated_at:$now, problems:$problems}')"
[[ -n "$out" ]] || fail 500 "Falha ao montar o trending" "trending_failed"
printf '%s' "$out" > "$CACHE.tmp.$$" && mv -f "$CACHE.tmp.$$" "$CACHE"
emit_json 200 OK
printf '%s' "$out"
