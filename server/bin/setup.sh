#!/bin/bash
# Setup local/dev do MOJ: cria dirs de runtime, vendora o fcgiwrap, copia
# notícias de exemplo e marca scripts como executáveis. Idempotente.
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"   # .../moj
mkdir -p "$ROOT/run/sessions" "$ROOT/run/spool/submissions" \
         "$ROOT/run/spool/submissions-done" "$ROOT/run/results" "$ROOT/server/var/news"
chmod 700 "$ROOT/run/sessions"
if [ ! -x "$ROOT/server/bin/fcgiwrap" ]; then
  cp "$ROOT/old/fcgiwrap/fcgiwrap" "$ROOT/server/bin/fcgiwrap" && chmod +x "$ROOT/server/bin/fcgiwrap"
fi
chmod +x "$ROOT/server/api/v1/router.sh" 2>/dev/null || true
find "$ROOT/server/bin" -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
find "$ROOT/server/daemons" "$ROOT/server/score" "$ROOT/server/judge-gw" -name '*.sh' \
     -exec chmod +x {} + 2>/dev/null || true
cp -n "$ROOT/old/moj-prod/html/moj.naquadah.com.br/new/news/"*.json "$ROOT/server/var/news/" 2>/dev/null || true
echo "MOJ setup ok: $ROOT"
echo "  run dirs: $ROOT/run/{sessions,spool,results}"
echo "  next: bash server/bin/start-fcgiwrap.sh &   (e recarregue o nginx-proxy)"
