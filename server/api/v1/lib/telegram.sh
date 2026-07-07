# lib/telegram.sh — identidade Telegram (overlay do treino) + ciclo de vida do nonce.
#
# Índice canônico em contests/<c>/var/telegram/ (JSON, nunca *sourced* — só jq):
#   by-tgid/<telegram_id>.json  = {telegram_id, login, username, linked_at, source, last_seen}
#   by-login/<login>            = uma linha com o <telegram_id>
#   .lock                       = flock para link/unlink/rename (consistência dos 2 índices)
# Verificações pendentes (efêmeras) em run/telegram/{pending,done}/<nonce>.json.
# 1 Telegram = no máx 1 conta (anti-duplicata). telegram_id imutável (troca de @username não duplica).

: "${RUNDIR:=/home/ribas/moj/run}"
: "${TG_NONCE_TTL:=900}"   # 15 min

tg_dir(){ printf '%s/%s/var/telegram' "$CONTESTSDIR" "$1"; }

# valid_tgid <id> — id de chat privado do Telegram: inteiro positivo.
valid_tgid(){ [[ "$1" =~ ^[0-9]+$ ]]; }

# --- consultas ------------------------------------------------------------
tg_login_of_id(){ # <c> <tgid> -> login vinculado (ou vazio)
  local f; f="$(tg_dir "$1")/by-tgid/$2.json"; [[ -f "$f" ]] && jq -r '.login // empty' "$f" 2>/dev/null
}
tg_id_of_login(){ # <c> <login> -> telegram_id (ou vazio)
  local f; f="$(tg_dir "$1")/by-login/$2"; [[ -f "$f" ]] && cat "$f" 2>/dev/null
}

# --- mutações (sob flock — consistência dos dois índices) -----------------
# tg_link <c> <tgid> <login> [username] [source] -> 0 ok | 2 tgid já vinculado a OUTRO login
tg_link(){
  local c="$1" tgid="$2" login="$3" uname="${4:-}" src="${5:-link}" d
  d="$(tg_dir "$c")"; mkdir -p "$d/by-tgid" "$d/by-login"
  ( flock 9
    local cur; cur="$(tg_login_of_id "$c" "$tgid")"
    [[ -n "$cur" && "$cur" != "$login" ]] && exit 2
    ( umask 077
      jq -cn --argjson id "$tgid" --arg l "$login" --arg u "$uname" --arg s "$src" --argjson t "$EPOCHSECONDS" \
        '{telegram_id:$id, login:$l, username:(if $u=="" then null else $u end),
          linked_at:$t, source:$s, last_seen:$t}' > "$d/by-tgid/$tgid.json"
      printf '%s\n' "$tgid" > "$d/by-login/$login" )
  ) 9>"$d/.lock"
}

tg_unlink(){ # <c> <tgid>
  local c="$1" tgid="$2" d; d="$(tg_dir "$c")"; [[ -d "$d" ]] || return 0
  ( flock 9
    local login; login="$(tg_login_of_id "$c" "$tgid")"
    rm -f "$d/by-tgid/$tgid.json"
    [[ -n "$login" ]] && rm -f "$d/by-login/$login"
  ) 9>"$d/.lock" 2>/dev/null
}

tg_touch(){ # <c> <tgid> [username] — atualiza username/last_seen (barato, sem lock)
  local f; f="$(tg_dir "$1")/by-tgid/$2.json"; [[ -f "$f" ]] || return 0
  local tmp="$f.tmp.$$"
  jq -c --arg u "${3:-}" --argjson t "$EPOCHSECONDS" \
     '.username=(if $u=="" then .username else $u end) | .last_seen=$t' "$f" > "$tmp" 2>/dev/null \
     && mv -f "$tmp" "$f"
}

# tg_rename <c> <old> <new> — segue o rename de conta (by-login key + by-tgid .login). Chamado
# pela cascata de username; no-op se o login não tinha Telegram vinculado.
tg_rename(){
  local c="$1" old="$2" new="$3" d tgid; d="$(tg_dir "$c")"
  tgid="$(tg_id_of_login "$c" "$old")"; [[ -n "$tgid" ]] || return 0
  ( flock 9
    printf '%s\n' "$tgid" > "$d/by-login/$new"; rm -f "$d/by-login/$old"
    local f="$d/by-tgid/$tgid.json"
    [[ -f "$f" ]] && { jq -c --arg l "$new" '.login=$l' "$f" > "$f.tmp.$$" && mv -f "$f.tmp.$$" "$f"; }
  ) 9>"$d/.lock" 2>/dev/null
}

# --- nonce (verificação por deep-link) ------------------------------------
# tg_nonce_new <purpose> [extra-json] -> ecoa o nonce (uuid). purpose ∈ {signup,link}.
tg_nonce_new(){
  local purpose="$1" extra="${2:-}" n dir
  [[ -n "$extra" ]] || extra='{}'
  n="$(</proc/sys/kernel/random/uuid)"
  dir="$RUNDIR/telegram/pending"; mkdir -p "$dir"
  ( umask 077
    jq -cn --arg n "$n" --arg p "$purpose" --argjson t "$EPOCHSECONDS" \
       --argjson ttl "$TG_NONCE_TTL" --argjson x "$extra" \
       '$x + {nonce:$n, purpose:$p, created_at:$t, expires_at:($t+$ttl)}' > "$dir/$n.json" )
  printf '%s' "$n"
}

# tg_nonce_claim <nonce> -> ecoa o JSON do pending e o CONSOME (uso único via mv atômico).
# rc: 0 ok | 1 inexistente/inválido | 2 expirado.
tg_nonce_claim(){
  local n="$1" pf tmp js exp
  valid_id "$n" || return 1
  pf="$RUNDIR/telegram/pending/$n.json"
  tmp="$RUNDIR/telegram/pending/.claim.$n.$$"
  mv "$pf" "$tmp" 2>/dev/null || return 1     # atômico: só um claim vence
  js="$(cat "$tmp" 2>/dev/null)"; rm -f "$tmp"
  exp="$(jq -r '.expires_at // 0' <<<"$js" 2>/dev/null)"
  [[ "$exp" =~ ^[0-9]+$ ]] && (( EPOCHSECONDS <= exp )) || return 2
  printf '%s' "$js"; return 0
}

# tg_nonce_done <nonce> <status> [login] — grava o resultado p/ o polling de status (SEM senha).
tg_nonce_done(){
  local dir="$RUNDIR/telegram/done"; mkdir -p "$dir"
  ( umask 077; jq -cn --arg s "$2" --arg l "${3:-}" --argjson t "$EPOCHSECONDS" \
      '{status:$s, login:(if $l=="" then null else $l end), at:$t}' > "$dir/$1.json" )
}

# tg_nonce_status <nonce> -> {status: pending|created|already_linked|expired, login?}
tg_nonce_status(){
  local n="$1" df pf exp
  valid_id "$n" || { jq -cn '{status:"expired"}'; return; }
  df="$RUNDIR/telegram/done/$n.json"; pf="$RUNDIR/telegram/pending/$n.json"
  if [[ -f "$df" ]]; then cat "$df"
  elif [[ -f "$pf" ]]; then
    exp="$(jq -r '.expires_at // 0' "$pf" 2>/dev/null)"
    if [[ "$exp" =~ ^[0-9]+$ ]] && (( EPOCHSECONDS <= exp )); then jq -cn '{status:"pending"}'; else jq -cn '{status:"expired"}'; fi
  else jq -cn '{status:"expired"}'; fi
}

# tg_deeplink <nonce> -> URL do deep-link (t.me/<bot>?start=<nonce>). Bot username do conf.
tg_deeplink(){ printf 'https://t.me/%s?start=%s' "${TELEGRAM_BOT_USERNAME:-mojinho_bot}" "$1"; }

# tg_derive_login <username> <tgid> -> login candidato a partir do @username (só [A-Za-z0-9_],
# nunca contém '.', então nunca casa sufixo de papel). Sem username usável -> "tg<tgid>".
tg_derive_login(){
  local u; u="$(printf '%s' "${1:-}" | tr -cd 'A-Za-z0-9_')"
  (( ${#u} >= 2 )) && printf '%s' "$u" || printf 'tg%s' "$2"
}
# tg_unique_login <c> <login> -> login único (sufixa _2, _3… se já existir)
tg_unique_login(){
  local c="$1" base="$2" cand="$2" i=2
  while user_exists "$c" "$cand"; do cand="${base}_$i"; ((i++)); done
  printf '%s' "$cand"
}
# tg_reserved_login <login> -> 0 se termina em sufixo de papel reservado (delega ao helper
# central de lib/auth.sh; fallback local se sourced isolado).
tg_reserved_login(){
  if declare -F is_reserved_role_login >/dev/null 2>&1; then is_reserved_role_login "$1"
  else case "$1" in *.admin|*.judge|*.cjudge|*.staff|*.cstaff|*.mon) return 0;; *) return 1;; esac; fi
}
