#!/bin/bash
# Setup local/dev do MOJ: cria dirs de runtime, vendora o fcgiwrap, copia
# notícias de exemplo e marca scripts como executáveis. Idempotente.
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"   # .../cdmoj
# RUNDIR (estado de runtime) fica FORA do repo e é configurável; default no workspace.
: "${RUNDIR:=/home/ribas/moj/run}"
: "${NEWSDIR:=$ROOT/server/var/news}"
mkdir -p "$RUNDIR/sessions" "$RUNDIR/spool/submissions" \
         "$RUNDIR/spool/submissions-done" "$RUNDIR/results" "$NEWSDIR"
chmod 700 "$RUNDIR/sessions"
# fcgiwrap: o binário vem versionado em server/bin/fcgiwrap (ou instalado pela distro/imagem).
if [ ! -x "$ROOT/server/bin/fcgiwrap" ] && ! command -v fcgiwrap >/dev/null 2>&1; then
  echo "AVISO: fcgiwrap ausente (nem server/bin/fcgiwrap nem no PATH) — instale-o antes de subir a API." >&2
fi
chmod +x "$ROOT/server/api/v1/router.sh" 2>/dev/null || true
find "$ROOT/server/bin" -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
find "$ROOT/server/daemons" "$ROOT/server/score" "$ROOT/server/judge-gw" -name '*.sh' \
     -exec chmod +x {} + 2>/dev/null || true
# (notícias são conteúdo de runtime, criado pelo admin; NEWSDIR fica fora da árvore de código.)
# serve as CLIs (GET /moj, /moj-contest, /moj-judges): SEMPRE os artefatos AUTO-CONTIDOS do mkdist
# (os scripts do repo sourceiam lib/core.sh e quebrariam baixados isolados por curl)
if [ -f "$ROOT/../moj-cli/mkdist.sh" ]; then
  bash "$ROOT/../moj-cli/mkdist.sh" >/dev/null 2>&1 || true
  for cli in moj moj-contest moj-judges; do
    [ -f "$ROOT/../moj-cli/dist/$cli" ] && install -m755 "$ROOT/../moj-cli/dist/$cli" "$ROOT/web/$cli" 2>/dev/null || true
  done
fi
echo "MOJ setup ok: $ROOT"
echo "  run dirs: $RUNDIR/{sessions,spool,results}"
echo "  next: bash server/bin/start-fcgiwrap.sh &   (e recarregue o nginx-proxy)"
