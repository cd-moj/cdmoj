# POST /treino/admin/managed-create  (.admin) — cria contas GERIDAS (menores, SEM Telegram).
# Body: {users:[{fullname, birthdate, login?, note?, expires_at?}]}  (1..500 — serve p/
# individual E lote). Login ausente = slug gerado do nome (nome.sobrenome, dedup).
# Resposta: {created:[{login,password,fullname,birthdate}], skipped:[{fullname,reason}]}
# — as SENHAS (user_genpass, legíveis) só existem nesta resposta. docs/CONTAS-GERIDAS.md.
require_method POST
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"

body="$(read_body)"
jq -e '.users | type == "array" and length >= 1 and length <= 500' >/dev/null 2>&1 <<<"$body" \
  || fail 400 "Body deve ter users:[1..500]" "users_invalid"

# slug ascii nome.sobrenome (≤24) p/ login gerado
_slug(){
  local s w=() first last
  s="$(printf '%s' "$1" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' ' ')"
  read -ra w <<<"$s"
  first="${w[0]:-}"; last=""
  (( ${#w[@]} > 1 )) && last="${w[${#w[@]}-1]}"
  s="$first${last:+.$last}"
  [[ -n "$s" ]] || s="aluno"
  printf '%.24s' "$s"
}
_valid_bd(){  # YYYY-MM-DD, entre 1900 e hoje
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  local e; e="$(date -d "$1" +%s 2>/dev/null)" || return 1
  [[ "$e" =~ ^-?[0-9]+$ ]] || return 1
  (( e >= -2208988800 && e <= EPOCHSECONDS ))   # 1900-01-01 .. hoje
}

declare -a CREATED SKIPPED LOGINS
declare -A TAKEN
while IFS= read -r item; do
  fullname="$(jq -r '.fullname // ""' <<<"$item")"
  birthdate="$(jq -r '.birthdate // ""' <<<"$item")"
  login="$(jq -r '.login // ""' <<<"$item")"
  note="$(jq -r '.note // ""' <<<"$item")"
  expires="$(jq -r '.expires_at // ""' <<<"$item")"; expires="${expires//[^0-9]/}"

  _skip(){ SKIPPED+=( "$(jq -cn --arg f "$fullname" --arg l "$login" --arg r "$1" \
      '{fullname:$f, login:$l, reason:$r}')" ); }

  if [[ -z "$fullname" || "$fullname" == *:* || ${#fullname} -gt 80 ]]; then _skip "nome inválido"; continue; fi
  if ! _valid_bd "$birthdate"; then _skip "nascimento inválido (AAAA-MM-DD)"; continue; fi
  (( ${#note} <= 200 )) || { _skip "nota muito longa (máx. 200)"; continue; }
  if [[ -n "$expires" ]] && (( expires <= EPOCHSECONDS )); then _skip "expiração no passado"; continue; fi

  if [[ -n "$login" ]]; then
    valid_id "$login" || { _skip "login inválido"; continue; }
    is_reserved_role_login "$login" && { _skip "login com sufixo de papel"; continue; }
    { [[ -n "${TAKEN[$login]:-}" ]] || user_exists treino "$login"; } && { _skip "login já existe"; continue; }
  else
    base="$(_slug "$fullname")" login="$base" n=1
    while [[ -n "${TAKEN[$login]:-}" ]] || user_exists treino "$login"; do
      (( n++ )); login="${base}${n}"
      (( n > 999 )) && break
    done
    { [[ -n "${TAKEN[$login]:-}" ]] || user_exists treino "$login"; } && { _skip "não achei login livre"; continue; }
  fi

  pw="$(user_genpass)"
  if ! user_create treino "$login" "$fullname" "$pw"; then _skip "falha ao criar"; continue; fi
  mngd="$(jq -cn --arg by "$SESSION_LOGIN" --arg nt "$note" --arg bd "$birthdate" \
      --argjson ex "${expires:-null}" --argjson t "$EPOCHSECONDS" \
      '{by:$by, note:$nt, birthdate:$bd, expires_at:$ex, created_at:$t}')"
  account_merge treino "$login" '.managed=$m | .public=false | .updated_at=$t' \
    --argjson m "$mngd" --argjson t "$EPOCHSECONDS" \
    || { _skip "falha ao marcar como gerida"; continue; }
  TAKEN["$login"]=1
  LOGINS+=( "$login" )
  CREATED+=( "$(jq -cn --arg l "$login" --arg p "$pw" --arg f "$fullname" --arg bd "$birthdate" \
      '{login:$l, password:$p, fullname:$f, birthdate:$bd}')" )
done < <(jq -c '.users[]' <<<"$body")

jarr(){ if (( $# == 0 )); then printf '[]'; else printf '%s\n' "$@" | jq -cs .; fi; }
audit_log managed-create "count=${#CREATED[@]} logins=$(IFS=,; echo "${LOGINS[*]:-—}")"
ok_json '{created:$c, skipped:$s, counts:{created:($c|length), skipped:($s|length)}}' \
  --argjson c "$(jarr "${CREATED[@]}")" --argjson s "$(jarr "${SKIPPED[@]}")"
