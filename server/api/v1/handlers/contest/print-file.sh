# GET /contest/print-file?contest=<c>&id=<id>   (Bearer)
# Baixa o arquivo CRU de um pedido de impressão. O dono baixa o próprio; admin baixa
# qualquer um; staff baixa os do seu escopo (regex). Serve com o nome original. Auditado.
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
source "$_LIBDIR/print.sh"

id="$(param id)"
[[ "$id" =~ ^[A-Za-z0-9_]+$ ]] || fail 400 "id inválido" "id_invalid"
dir="$(pr_dir "$contest")"
meta="$dir/$id.json"
[[ -f "$meta" && -f "$dir/$id.src" ]] || fail 404 "Pedido não encontrado" "notfound"
owner="$(jq -r '.login // ""' "$meta" 2>/dev/null)"
seq="$(jq -r '.seq // 0' "$meta" 2>/dev/null)"

if [[ "$owner" != "$SESSION_LOGIN" ]]; then
  # não é o dono: admin sempre, staff só dentro do escopo
  if is_admin; then :
  elif is_staff && staff_can_see "$contest" "$SESSION_LOGIN" "$owner"; then :
  else fail 403 "Sem permissão para este arquivo" "forbidden"; fi
fi

name="$(jq -r '.filename // "arquivo"' "$meta" 2>/dev/null)"
safe="$(basename "$name" | tr -cd 'A-Za-z0-9._ -')"; [[ -n "$safe" ]] || safe="arquivo"
mime="$(jq -r '.mime // "application/octet-stream"' "$meta" 2>/dev/null)"

audit_log_to "$contest" print-download "seq=$seq by=$SESSION_LOGIN owner=$owner id=$id"
printf 'Status: 200 OK\r\n'
printf 'Content-Type: %s\r\n' "$mime"
printf 'Content-Disposition: attachment; filename="%s"\r\n' "$safe"
printf '\r\n'
cat "$dir/$id.src"
