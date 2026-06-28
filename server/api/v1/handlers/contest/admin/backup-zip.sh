# GET /contest/admin/backup-zip?contest=<c>&login=<login>   (admin DO contest)
# Baixa um ZIP com TODOS os backups de um usuário, com os nomes originais (prefixados por
# índice+data p/ distinguir versões do mesmo arquivo).
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

who="$(param login)"
valid_id "$who" || fail 400 "login inválido" "login_invalid"
bdir="$CONTESTSDIR/$contest/backups/$who"
[[ -d "$bdir" ]] || fail 404 "Sem backups deste usuário" "notfound"

stg="$(mktemp -d 2>/dev/null)" || fail 500 "tmp" "tmp"
trap 'rm -rf "$stg"' EXIT
set +o noglob; shopt -s nullglob
i=0
for m in "$bdir"/*.meta; do
  [[ -f "$m" ]] || continue
  bid="$(basename "$m" .meta)"; [[ -f "$bdir/$bid" ]] || continue
  name="$(jq -r '.name // "arquivo"' "$m" 2>/dev/null)"; t="$(jq -r '.time // 0' "$m" 2>/dev/null)"
  ts="$(date -d "@$t" +%Y%m%d-%H%M%S 2>/dev/null || echo "$t")"
  safe="$(basename "$name" | tr -cd 'A-Za-z0-9._ -')"; [[ -n "$safe" ]] || safe="arquivo"
  i=$((i+1))
  cp -f "$bdir/$bid" "$stg/$(printf '%03d' "$i")_${ts}_${safe}" 2>/dev/null
done
shopt -u nullglob
(( i > 0 )) || fail 404 "Sem arquivos" "empty"

fn="backups-$(printf '%s' "$who" | tr -cd 'A-Za-z0-9._-').zip"
printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/zip\r\n'
printf 'Content-Disposition: attachment; filename="%s"\r\n' "$fn"
printf '\r\n'
( cd "$stg" && zip -q -r - . )
