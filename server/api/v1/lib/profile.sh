# lib/profile.sh — helpers de perfil self-service (treino).
# O perfil vive DENTRO do account.json do usuário (users/<login>/account.json):
#   {university, favorite_editor, public(bool), uname_changes:[epochs], ...}
# Leitura cai para o contest-fonte (USERS_FROM) quando não há conta local.
# Foto (100x100 png) em users/<login>/photo.png.
: "${UNAME_CHANGE_LIMIT:=2}"

photo_file(){ printf '%s/%s/users/%s/photo.png' "$CONTESTSDIR" "$1" "$2"; }

# _profile_account <c> <login> -> ecoa o caminho do account.json (local, senão USERS_FROM)
_profile_account(){
  local f; f="$(account_file "$1" "$2")"
  if [[ ! -f "$f" ]]; then
    local src; src="$(_users_source "$1")"
    [[ "$src" != "$1" ]] && f="$(account_file "$src" "$2")"
  fi
  printf '%s' "$f"
}

# DEPRECATED (só os ramos legados pré-store-v2 ainda chamam; somem no corte final).
passwd_field(){ # <contest> <login> <n>
  awk -F: -v u="$2" -v n="$3" '$1==u{print $n; exit}' "$CONTESTSDIR/$1/passwd" 2>/dev/null
}
update_passwd_field(){
  local pw="$CONTESTSDIR/$1/passwd" tmp
  tmp="$(mktemp "${pw}.XXXXXX")" || return 1
  _PV="$4" awk -F: -v u="$2" -v n="$3" 'BEGIN{OFS=":"} $1==u{$n=ENVIRON["_PV"]} {print}' "$pw" > "$tmp" \
    && cat "$tmp" > "$pw" && rm -f "$tmp"
}

# read_profile <c> <login> -> UNIVERSITY, FAVORITE_EDITOR, PROFILE_PUBLIC, UNAME_CHANGES
read_profile(){
  UNIVERSITY=""; FAVORITE_EDITOR=""; PROFILE_PUBLIC="true"; UNAME_CHANGES=""
  local f; f="$(_profile_account "$1" "$2")"
  [[ -f "$f" ]] || return 0
  UNIVERSITY="$(jq -r '.university // ""' "$f" 2>/dev/null)"
  FAVORITE_EDITOR="$(jq -r '.favorite_editor // ""' "$f" 2>/dev/null)"
  PROFILE_PUBLIC="$(jq -r 'if .public==false then "false" else "true" end' "$f" 2>/dev/null)"
  UNAME_CHANGES="$(jq -r '(.uname_changes // []) | map(tostring) | join(" ")' "$f" 2>/dev/null)"
}

# set_profile_field <c> <login> <key> <json-value>  (merge atômico no account.json)
set_profile_field(){
  account_merge "$1" "$2" '.[$k]=$v | .updated_at=$t' \
    --arg k "$3" --argjson v "$4" --argjson t "$EPOCHSECONDS"
}
set_profile_str(){ set_profile_field "$1" "$2" "$3" "$(jq -n --arg s "$4" '$s')"; }

# profile_is_public <c> <login> -> 0 (público) se public != false (default público)
profile_is_public(){
  local f; f="$(_profile_account "$1" "$2")"; [[ -f "$f" ]] || return 0
  [[ "$(jq -r 'if .public==false then "n" else "y" end' "$f" 2>/dev/null)" != "n" ]]
}

# nº de trocas de username nos últimos 365 dias
uname_changes_recent(){ # <epochs>
  local cutoff=$(( EPOCHSECONDS - 365*86400 )) n=0 e
  for e in $1; do [[ "$e" =~ ^[0-9]+$ ]] && (( e >= cutoff )) && ((n++)); done
  printf '%s' "$n"
}
# epoch da próxima troca disponível (mais antiga na janela + 1 ano), ou 0 se há cota
uname_next_available(){ # <epochs>
  local cutoff=$(( EPOCHSECONDS - 365*86400 )) oldest=0 e
  for e in $1; do [[ "$e" =~ ^[0-9]+$ ]] && (( e >= cutoff )) && { (( oldest==0 || e<oldest )) && oldest=$e; }; done
  (( oldest > 0 )) && printf '%s' $(( oldest + 365*86400 )) || printf '0'
}
