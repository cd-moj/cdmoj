# GET /submission/log?contest=<id>&id=<hash>[&time=<epoch>]   (Bearer) -> TXT
# Log do julgamento, localizado pelo HASH (mojlog/*<hash>*). Se não houver log
# (ex.: submissão mock), responde uma nota amigável. Visível se dono/admin/judge/SHOWCODE.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

sid="$(param id)"
[[ -n "$sid" ]] || fail 400 "Missing submission id" "id_missing"
[[ "$sid" =~ ^[0-9a-f]{32}$ || "$sid" =~ ^[0-9a-f-]{36}$ ]] \
  || fail 400 "Invalid submission id" "id_invalid"

set +o noglob; shopt -s nullglob
sfiles=("$CONTESTSDIR/$contest/submissions/"*"$sid"*)
owner=""
if (( ${#sfiles[@]} > 0 )); then
  base="${sfiles[0]##*/}"; after="${base#*"$sid"-}"; owner="${after%%-*}"
fi
SHOWCODE=0
load_contest_conf "$contest"
if [[ -n "$owner" && "$owner" != "$SESSION_LOGIN" ]] && ! is_judge && [[ "${SHOWCODE:-0}" != 1 ]]; then
  shopt -u nullglob
  fail 403 "Log not visible" "log_forbidden"
fi

logs=("$CONTESTSDIR/$contest/mojlog/"*"$sid"*)
shopt -u nullglob
emit_text
if (( ${#logs[@]} > 0 )); then cat "${logs[0]}"; else printf 'Log indisponível para esta submissão.\n'; fi
