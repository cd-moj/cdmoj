# GET  /treino/profile            -> perfil próprio (auth) + cota de troca de username
# GET  /treino/profile?user=X     -> visão pública de X (respeita privacidade)
# POST /treino/profile  {name?, university?, favorite_editor?, profile_public?}

# editores válidos (deve casar com web/shared/editors.js)
_valid_editor(){ case "$1" in
  vim|neovim|emacs|nano|vscode|cursor|sublime|zed|helix|notepadpp|\
  intellij|pycharm|clion|webstorm|goland|rider|phpstorm|rubymine|datagrip|androidstudio|\
  eclipse|visualstudio|xcode|codeblocks|geany|kate|gedit|micro|other) return 0;; *) return 1;; esac; }

quser="$(param user)"

# ---- visão pública de OUTRO usuário ----
if [[ "$REQUEST_METHOD" == GET && -n "$quser" ]]; then
  valid_id "$quser" || fail 400 "Invalid user" "user_invalid"
  user_exists treino "$quser" || fail 404 "Usuário não encontrado" "user_notfound"
  isowner=0; isadm=0
  if load_session && [[ "$SESSION_CONTEST" == treino ]]; then
    [[ "$SESSION_LOGIN" == "$quser" ]] && isowner=1
    is_admin && isadm=1
  fi
  read_profile treino "$quser"
  if [[ "$PROFILE_PUBLIC" == "false" && "$isowner" == 0 && "$isadm" == 0 ]]; then
    ok_json '{login:$l, is_public:false}' --arg l "$quser"; exit 0
  fi
  qname="$(user_fullname_of treino "$quser")"
  haspic="$([[ -f "$(photo_file treino "$quser")" ]] && echo true || echo false)"
  ok_json '{login:$l, name:$n, university:$u, favorite_editor:$fe, has_photo:$hp, is_public:true}' \
    --arg l "$quser" --arg n "$qname" --arg u "$UNIVERSITY" --arg fe "$FAVORITE_EDITOR" --argjson hp "$haspic"
  exit 0
fi

# ---- própria conta ----
require_auth_contest treino
login="$SESSION_LOGIN"
read_profile treino "$login"
name="$(user_fullname_of treino "$login")"

if [[ "$REQUEST_METHOD" == POST ]]; then
  body="$(read_body)"
  jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
  if jq -e 'has("name")' >/dev/null 2>&1 <<<"$body"; then
    newname="$(jq -r '.name' <<<"$body")"
    [[ -z "$newname" || "$newname" == *:* ]] && fail 400 "Nome inválido (não pode ser vazio nem conter ':')" "name_invalid"
    (( ${#newname} <= 80 )) || fail 400 "Nome muito longo" "name_long"
    account_merge treino "$login" '.fullname=$n|.updated_at=$t' \
      --arg n "$newname" --argjson t "$EPOCHSECONDS" || fail 500 "Falha ao salvar o nome" "save_fail"
    name="$newname"
  fi
  if jq -e 'has("university")' >/dev/null 2>&1 <<<"$body"; then
    newuniv="$(jq -r '.university' <<<"$body")"
    (( ${#newuniv} <= 120 )) || fail 400 "Universidade muito longa" "univ_long"
    set_profile_str treino "$login" university "$newuniv"; UNIVERSITY="$newuniv"
  fi
  if jq -e 'has("favorite_editor")' >/dev/null 2>&1 <<<"$body"; then
    fe="$(jq -r '.favorite_editor' <<<"$body")"
    [[ -z "$fe" ]] || _valid_editor "$fe" || fail 400 "Editor inválido" "editor_invalid"
    set_profile_str treino "$login" favorite_editor "$fe"; FAVORITE_EDITOR="$fe"
  fi
  if jq -e 'has("profile_public")' >/dev/null 2>&1 <<<"$body"; then
    pub="$(jq -r 'if .profile_public then "true" else "false" end' <<<"$body")"
    set_profile_field treino "$login" public "$pub"; PROFILE_PUBLIC="$pub"
  fi
fi

used="$(uname_changes_recent "$UNAME_CHANGES")"
remaining=$(( UNAME_CHANGE_LIMIT - used )); (( remaining < 0 )) && remaining=0
nextav="$(uname_next_available "$UNAME_CHANGES")"
haspic="$([[ -f "$(photo_file treino "$login")" ]] && echo true || echo false)"

# vínculo Telegram do próprio login (sem expor o telegram_id — só estado/username/quando)
# + a COTA de desvínculo (1/ano p/ usuário comum; .admin livre) p/ a UI avisar/desabilitar
tgjson='{"linked":false,"username":null,"linked_at":null}'
tgid="$(tg_id_of_login treino "$login" 2>/dev/null)"
if [[ -n "$tgid" ]]; then
  tgjson="$(jq -c '{linked:true, username:(.username // null), linked_at:(.linked_at // null)}' \
            "$(tg_dir treino)/by-tgid/$tgid.json" 2>/dev/null)"
  [[ -n "$tgjson" ]] || tgjson='{"linked":true,"username":null,"linked_at":null}'
fi
if is_admin; then
  tgq='{"changes_limit":null,"changes_used":0,"changes_remaining":null,"next_available":0}'  # livre
else
  tgch="$(account_field treino "$login" '(.telegram_changes // []) | map(tostring) | join(" ")')"
  tgused="$(uname_changes_recent "$tgch")"
  tgrem=$(( TELEGRAM_CHANGE_LIMIT - tgused )); (( tgrem < 0 )) && tgrem=0
  tgnext="$(uname_next_available "$tgch")"
  tgq="$(jq -cn --argjson u "$tgused" --argjson l "$TELEGRAM_CHANGE_LIMIT" \
         --argjson r "$tgrem" --argjson n "${tgnext:-0}" \
         '{changes_limit:$l, changes_used:$u, changes_remaining:$r, next_available:$n}')"
fi
tgjson="$(jq -cn --argjson a "$tgjson" --argjson b "$tgq" '$a + $b')"

ok_json '{login:$l, name:$n, university:$u, favorite_editor:$fe, profile_public:$pub, has_photo:$hp,
          username_changes_used:$used, username_changes_limit:$lim,
          username_changes_remaining:$rem, username_next_available:$next, telegram:$tg}' \
  --arg l "$login" --arg n "$name" --arg u "$UNIVERSITY" --arg fe "$FAVORITE_EDITOR" \
  --argjson pub "$([[ "$PROFILE_PUBLIC" == false ]] && echo false || echo true)" \
  --argjson hp "$haspic" \
  --argjson used "$used" --argjson lim "$UNAME_CHANGE_LIMIT" \
  --argjson rem "$remaining" --argjson next "${nextav:-0}" --argjson tg "$tgjson"
