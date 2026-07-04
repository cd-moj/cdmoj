# POST /treino/profile/username  {new_username}  -> troca o próprio username (handle).
# Limite: UNAME_CHANGE_LIMIT (2) por ano. Atualiza TODOS os arquivos de controle do
# treino em cascata, sob lock, para manter tudo consistente.
require_method POST
require_auth_contest treino
old="$SESSION_LOGIN"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
new="$(jq -r '.new_username // empty' <<<"$body")"
[[ -n "$new" ]] || fail 400 "Informe o novo nome de usuário" "missing"
[[ "$new" =~ ^[A-Za-z0-9._-]{2,32}$ ]] || fail 400 "Nome de usuário inválido (2–32 caracteres: letras, números, . _ -)" "uname_invalid"
case "$new" in *.admin|*.judge|*.cjudge|*.staff|*.mon) fail 400 "Sufixo reservado não permitido" "uname_reserved";; esac
[[ "$new" == "$old" ]] && fail 400 "É o mesmo nome de usuário atual" "uname_same"

T="$CONTESTSDIR/treino"
set +o noglob

# --- lock para serializar a troca ---
mkdir -p "$T/var"
exec 9>"$T/var/profile.lock" || fail 500 "Não foi possível obter lock" "lock_fail"
flock 9

# já existe?
user_exists treino "$new" && fail 409 "Esse nome de usuário já está em uso" "uname_taken"

# ===== rename = mv do diretório do usuário =====
# limite por ano (uname_changes no account.json)
changes="$(account_field treino "$old" '(.uname_changes // []) | map(tostring) | join(" ")')"
used="$(uname_changes_recent "$changes")"
if (( used >= UNAME_CHANGE_LIMIT )); then
  nextav="$(uname_next_available "$changes")"
  whenstr="$(date -d "@$nextav" '+%d/%m/%Y' 2>/dev/null || echo '-')"
  fail 403 "Limite de $UNAME_CHANGE_LIMIT trocas por ano atingido. Próxima troca disponível em $whenstr." "uname_limit"
fi
# sem submissão pendente (verdict é o 4º campo na linha login-less do history por-usuário)
hf="$(user_hist_file treino "$old")"
if [[ -f "$hf" ]] && grep -qE ':(Not Answered Yet|[Oo]n queue|[Rr]unning):' "$hf"; then
  fail 409 "Você tem submissões pendentes de julgamento. Aguarde o veredicto e tente de novo." "uname_pending"
fi
# mv do diretório (+ account.login) e registro da troca
user_rename treino "$old" "$new" || fail 500 "Falha ao renomear a conta" "save_fail"
account_merge treino "$new" '.uname_changes = ((.uname_changes // []) + [$t])' --argjson t "$EPOCHSECONDS"
# (o índice Telegram — by-login/by-tgid — é ajustado em tg_rename)
command -v tg_rename >/dev/null 2>&1 && tg_rename treino "$old" "$new" 2>/dev/null || true

# mantém a sessão atual logada como o novo username (comum aos dois ramos)
if [[ -n "$SESSION_TOKEN" && -f "$SESSIONDIR/$SESSION_TOKEN" ]]; then
  stmp="$(mktemp)"
  _NL="$new" awk -F= 'BEGIN{OFS="="} /^LOGIN=/{print "LOGIN=\"" ENVIRON["_NL"] "\""; next} {print}' \
    "$SESSIONDIR/$SESSION_TOKEN" > "$stmp" && cat "$stmp" > "$SESSIONDIR/$SESSION_TOKEN"; rm -f "$stmp"
fi

flock -u 9
used2=$(( used + 1 ))
ok_json '{updated:true, new_username:$n, username_changes_used:$u2, username_changes_remaining:$rem}' \
  --arg n "$new" --argjson u2 "$used2" --argjson rem "$(( UNAME_CHANGE_LIMIT - used2 < 0 ? 0 : UNAME_CHANGE_LIMIT - used2 ))"
