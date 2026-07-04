# POST /contest/admin/users-set-password?contest=<id>  (admin) {password, include_disabled?}
# Troca a senha de TODOS os usuários não-privilegiados para uma senha única (uso clássico
# em prova: após todos logarem, troca-se a senha de todos por uma secreta). Pula contas
# privilegiadas (lista de is_reserved_role_login, replicada na regex do awk — inclui .cjudge).
# Por padrão pula desabilitados (senha '!...'); include_disabled inclui.
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
password="$(jq -r '.password // empty' <<<"$body")"
inc="$(jq -r 'if .include_disabled==true then "1" else "0" end' <<<"$body")"
[[ -n "$password" ]] || fail 422 "Informe a senha" "password_missing"
(( ${#password} <= 128 )) || fail 422 "Senha muito longa" "password_long"
case "$password" in *:*) fail 422 "Senha não pode conter ':'" "colon";; esac

if store_v2 "$contest"; then
  # v2: troca no account.json de cada não-privilegiado (auth lê direto do account.json)
  count=0
  while IFS= read -r u; do
    [[ -n "$u" ]] || continue
    is_reserved_role_login "$u" && continue
    cur="$(user_password "$contest" "$u")"
    [[ "$inc" != 1 && "${cur:0:1}" == "!" ]] && continue
    account_merge "$contest" "$u" '.password=$p|.updated_at=$t' \
      --arg p "$password" --argjson t "$EPOCHSECONDS" && count=$((count+1))
  done < <(list_users "$contest")
else
  pw="$CONTESTSDIR/$contest/passwd"; [[ -f "$pw" ]] || fail 404 "Contest sem passwd" "no_passwd"
  out="$(NEWP="$password" INC="$inc" awk -F: 'BEGIN{OFS=":"}
    { priv = ($1 ~ /\.(admin|judge|cjudge|staff|mon)$/); dis = (substr($2,1,1)=="!");
      if(!priv && (ENVIRON["INC"]=="1" || !dis)){ $2=ENVIRON["NEWP"]; c++ }
      lines = lines $0 "\n" }
    END { printf "%d\n", c+0; printf "%s", lines }' "$pw")"
  count="$(head -1 <<<"$out")"
  tmp="$(mktemp "${pw}.XXXXXX")" || fail 500 "tmp" "tmp"
  tail -n +2 <<<"$out" > "$tmp" && cat "$tmp" > "$pw" && rm -f "$tmp" || { rm -f "$tmp"; fail 500 "Falha ao gravar" "write_fail"; }
fi
audit_log_to "$contest" users-set-password "count=$count include_disabled=$inc"
ok_json '{updated:true, count:$n}' --argjson n "${count:-0}"
