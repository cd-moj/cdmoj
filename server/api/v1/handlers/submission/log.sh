# GET /submission/log?contest=<id>&id=<hash>[&time=<epoch>]   (Bearer) -> HTML
# Report do julgamento (report.html auto-contido), localizado pelo HASH
# (mojlog/*<hash>*). Se não houver report (ex.: submissão mock), responde uma nota
# amigável. Visível se dono/admin/judge/SHOWCODE.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

sid="$(param id)"
[[ -n "$sid" ]] || fail 400 "Missing submission id" "id_missing"
[[ "$sid" =~ ^[0-9a-f]{32}$ || "$sid" =~ ^[0-9a-f-]{36}$ ]] \
  || fail 400 "Invalid submission id" "id_invalid"

set +o noglob; shopt -s nullglob
resolve_submission "$contest" "$sid"     # store-v2 ou legado
owner="$SUB_OWNER"
SHOWCODE=0; SHOWLOG=""
load_contest_conf "$contest"
# juiz/admin sempre veem; dono vê salvo se o admin escondeu o log (SHOWLOG=0).
if ! is_judge; then
  if [[ -n "$owner" && "$owner" != "$SESSION_LOGIN" && "${SHOWCODE:-0}" != 1 ]]; then
    shopt -u nullglob; fail 403 "Log not visible" "log_forbidden"
  fi
  if [[ "$SHOWLOG" == 0 ]]; then
    shopt -u nullglob; fail 403 "Log oculto pelo admin do contest" "log_hidden"
  fi
fi

shopt -u nullglob
emit_html
if [[ -n "$SUB_LOG" && -f "$SUB_LOG" ]]; then cat "$SUB_LOG"; else printf '<!doctype html><meta charset="utf-8"><p style="font:16px sans-serif;color:#64748b;padding:1rem">Report indisponível para esta submissão.</p>\n'; fi
