# POST /treino/admin/managed-update  (.admin) — edita uma conta GERIDA.
# {login, note?, birthdate?, expires_at?|null, disabled?}
#   note/birthdate/expires_at: atualizam o .managed (expires_at null REMOVE a expiração);
#   disabled:true  = senha-sentinela "!..." + derruba sessões (padrão user-disable);
#   disabled:false = reabilita com senha NOVA, devolvida UMA vez.  docs/CONTAS-GERIDAS.md.
require_method POST
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
login="$(jq -r '.login // empty' <<<"$body")"
[[ -n "$login" ]] || fail 400 "Informe login" "login_missing"
valid_id "$login" || fail 400 "Login inválido" "login_invalid"
user_exists treino "$login" || fail 404 "Usuário não encontrado" "user_notfound"
[[ -n "$(managed_json treino "$login")" ]] || fail 400 "Não é uma conta gerida" "not_managed"

changes=()
if jq -e 'has("note")' >/dev/null 2>&1 <<<"$body"; then
  note="$(jq -r '.note // ""' <<<"$body")"
  (( ${#note} <= 200 )) || fail 400 "Nota muito longa (máx. 200)" "note_long"
  account_merge treino "$login" '.managed.note=$v | .updated_at=$t' \
    --arg v "$note" --argjson t "$EPOCHSECONDS" || fail 500 "Falha ao salvar" "save_fail"
  changes+=( "note" )
fi
if jq -e 'has("birthdate")' >/dev/null 2>&1 <<<"$body"; then
  bd="$(jq -r '.birthdate // ""' <<<"$body")"
  [[ "$bd" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && date -d "$bd" +%s >/dev/null 2>&1 \
    || fail 400 "Nascimento inválido (AAAA-MM-DD)" "birthdate_invalid"
  account_merge treino "$login" '.managed.birthdate=$v | .updated_at=$t' \
    --arg v "$bd" --argjson t "$EPOCHSECONDS" || fail 500 "Falha ao salvar" "save_fail"
  changes+=( "birthdate" )
fi
if jq -e 'has("expires_at")' >/dev/null 2>&1 <<<"$body"; then
  exv="$(jq -c '.expires_at' <<<"$body")"
  [[ "$exv" == null || "$exv" =~ ^[0-9]+$ ]] || fail 400 "expires_at deve ser epoch ou null" "expires_invalid"
  account_merge treino "$login" '.managed.expires_at=$v | .updated_at=$t' \
    --argjson v "$exv" --argjson t "$EPOCHSECONDS" || fail 500 "Falha ao salvar" "save_fail"
  changes+=( "expires_at" )
fi

newpass=""
if jq -e 'has("disabled")' >/dev/null 2>&1 <<<"$body"; then
  if jq -e '.disabled == true' >/dev/null 2>&1 <<<"$body"; then
    user_set_password treino "$login" "!$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 16)" \
      || fail 500 "Falha ao desabilitar" "save_fail"
    set +o noglob; shopt -s nullglob
    for f in "$SESSIONDIR"/*; do
      [[ -f "$f" ]] || continue
      lg="$( CONTEST=""; LOGIN=""; source "$f" 2>/dev/null; [[ "$CONTEST" == treino ]] && printf '%s' "$LOGIN" )"
      [[ "$lg" == "$login" ]] && rm -f "$f"
    done
    shopt -u nullglob
    changes+=( "disabled" )
  else
    newpass="$(user_genpass)"
    user_set_password treino "$login" "$newpass" || fail 500 "Falha ao reabilitar" "save_fail"
    changes+=( "enabled" )
  fi
fi
(( ${#changes[@]} )) || fail 400 "Nada para alterar" "nothing"

audit_log managed-update "login=$login changes=$(IFS=,; echo "${changes[*]}")"
if [[ -n "$newpass" ]]; then
  ok_json '{updated:true, login:$l, password:$p}' --arg l "$login" --arg p "$newpass"
else
  ok_json '{updated:true, login:$l}' --arg l "$login"
fi
