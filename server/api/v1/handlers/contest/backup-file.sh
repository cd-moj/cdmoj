# GET /contest/backup-file?contest=<c>&id=<id>[&login=<login>]   (Bearer)
# Baixa um backup. Sem `login` -> o do PRÓPRIO usuário. Com `login` -> só o admin pode
# (baixar o de qualquer usuário). Serve com o nome original (Content-Disposition).
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

id="$(param id)"
[[ "$id" =~ ^[A-Za-z0-9_]+$ ]] || fail 400 "id inválido" "id_invalid"
who="$(param login)"
if [[ -n "$who" ]]; then
  is_admin || fail 403 "Apenas o admin baixa de outros usuários" "admin_required"
  valid_id "$who" || fail 400 "login inválido" "login_invalid"
else
  who="$SESSION_LOGIN"
fi
bdir="$CONTESTSDIR/$contest/backups/$who"
[[ -f "$bdir/$id" && -f "$bdir/$id.meta" ]] || fail 404 "Backup não encontrado" "notfound"
name="$(jq -r '.name // "arquivo"' "$bdir/$id.meta" 2>/dev/null)"
safe="$(basename "$name" | tr -cd 'A-Za-z0-9._ -')"; [[ -n "$safe" ]] || safe="arquivo"

printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/octet-stream\r\n'
printf 'Content-Disposition: attachment; filename="%s"\r\n' "$safe"
printf '\r\n'
cat "$bdir/$id"
