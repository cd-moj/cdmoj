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
cut -d: -f1 "$T/passwd" 2>/dev/null | grep -qxF -- "$new" && fail 409 "Esse nome de usuário já está em uso" "uname_taken"

if store_v2 treino; then
  # ===== store-v2: rename = mv do diretório =====
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
  # mv do diretório (+ account.login + regen_passwd) e registro da troca
  user_rename treino "$old" "$new" || fail 500 "Falha ao renomear a conta" "save_fail"
  account_merge treino "$new" '.uname_changes = ((.uname_changes // []) + [$t])' --argjson t "$EPOCHSECONDS"
  # (o índice Telegram — by-login/by-tgid — é ajustado em tg_rename; adicionado na fase Telegram)
  command -v tg_rename >/dev/null 2>&1 && tg_rename treino "$old" "$new" 2>/dev/null || true
else
  # ===== legado: cascata sobre tabelas globais =====
  read_profile treino "$old"
  used="$(uname_changes_recent "$UNAME_CHANGES")"
  if (( used >= UNAME_CHANGE_LIMIT )); then
    nextav="$(uname_next_available "$UNAME_CHANGES")"
    whenstr="$(date -d "@$nextav" '+%d/%m/%Y' 2>/dev/null || echo '-')"
    fail 403 "Limite de $UNAME_CHANGE_LIMIT trocas por ano atingido. Próxima troca disponível em $whenstr." "uname_limit"
  fi
  if [[ -f "$T/controle/history" ]] && \
     awk -F: -v o="$old" '$2==o && $5 ~ /Not Answered|[Oo]n queue|[Rr]unning/{found=1} END{exit !found}' "$T/controle/history"; then
    fail 409 "Você tem submissões pendentes de julgamento. Aguarde o veredicto e tente de novo." "uname_pending"
  fi
  # 1) passwd: campo 1 (login)
  update_passwd_field treino "$old" 1 "$new" || fail 500 "Falha ao atualizar passwd" "save_fail"
  # 2) data/<old> -> data/<new>
  [[ -e "$T/data/$old" ]] && mv -f "$T/data/$old" "$T/data/$new"
  # 3) controle/history: campo 2 (username) old -> new
  if [[ -f "$T/controle/history" ]]; then
    htmp="$(mktemp)"
    awk -F: -v o="$old" -v n="$new" 'BEGIN{OFS=":"} $2==o{$2=n} {print}' "$T/controle/history" > "$htmp" \
      && cat "$htmp" > "$T/controle/history"; rm -f "$htmp"
  fi
  # 4) estado por problema e fragmento de placar
  [[ -d "$T/controle/$old.d" ]] && mv -f "$T/controle/$old.d" "$T/controle/$new.d"
  [[ -e "$T/controle/$old.score" ]] && mv -f "$T/controle/$old.score" "$T/controle/$new.score"
  # 5) submissões arquivadas: *-<old>-* -> *-<new>-*
  for f in "$T/submissions/"*"-$old-"*; do
    [[ -e "$f" ]] || continue
    b="${f##*/}"; mv -f "$f" "$T/submissions/${b/-$old-/-$new-}"
  done
  # 6) arquivo de perfil: registra a troca, preserva os campos e renomeia (json + foto)
  jq --argjson t "$EPOCHSECONDS" '.uname_changes = ((.uname_changes // []) + [$t])' \
     <<<"$(profile_json treino "$old")" > "$(profile_file treino "$new")"
  rm -f "$(profile_file treino "$old")"
  [[ -f "$(photo_file treino "$old")" ]] && mv -f "$(photo_file treino "$old")" "$(photo_file treino "$new")"
fi

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
