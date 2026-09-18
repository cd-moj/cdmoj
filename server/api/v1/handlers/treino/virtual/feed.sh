# GET /treino/virtual/feed?contest=<cid>   (anônimo — é o placar FINAL, já público)
# Feed dos "fantasmas": times do placar público final + todas as runs (segundo, time, problema,
# Y|N|X|?), p/ o cliente reconstruir o placar em qualquer instante t. O PORTÃO roda ANTES de tocar
# no cache: contest que deixou de ser elegível = 404 e o cache some (lib/virtual.sh).
require_method GET
source "$_LIBDIR/virtual.sh"
cid="$(param contest)"; vr_gate "$cid"
vr_feed_fresh "$cid" || vr_feed_build "$cid" || fail 503 "Feed indisponível — tente de novo" "virtual_feed_unavailable"
f="$(vr_feed_file "$cid")"
if [[ -s "$f.gz" && ! "$f" -nt "$f.gz" && "${HTTP_ACCEPT_ENCODING:-}" == *gzip* ]]; then
  printf 'Status: 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nContent-Encoding: gzip\r\nVary: Accept-Encoding\r\n\r\n'
  cat "$f.gz"; exit 0
fi
printf 'Status: 200 OK\r\nContent-Type: application/json; charset=utf-8\r\n\r\n'
cat "$f"
