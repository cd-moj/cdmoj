# test/fixture.sh — helpers de fixture do store por-usuário (source nos smokes).
# fx_user <contestdir> <login> <pass> [fullname] [email] — cria users/<login>/ completo.
# fx_conf_v2 <contestdir> — garante USER_STORE=v2 no conf (idempotente).
fx_user() {
  local cdir="$1" login="$2" pass="$3" name="${4:-$2}" email="${5:-}"
  local d="$cdir/users/$login"
  mkdir -p "$d/submissions" "$d/mojlog" "$d/results"
  jq -cn --arg l "$login" --arg p "$pass" --arg n "$name" --arg e "$email" \
    '{login:$l,password:$p,fullname:$n,email:$e,created_at:0,updated_at:0,status:"active",uname_changes:[]}' \
    > "$d/account.json"
  : > "$d/history"
}
fx_conf_v2() {
  grep -q '^USER_STORE=v2' "$1/conf" 2>/dev/null || printf 'USER_STORE=v2\n' >> "$1/conf"
}
