# POST /submit?contest=<id>   body: {problem_id, filename, code_b64}   (Bearer)
# Submit ASSÍNCRONO: enfileira no spool e retorna na hora (não bloqueia a CGI).
# O daemon (server/daemons) consome o spool e atualiza o veredicto; o front faz
# polling de /treino/history (ou /contest/history) até sair de "Not Answered Yet".
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

# Gate de submissão (forçado pela API): .admin/.judge sempre; .staff nunca; usuário normal
# e .mon só DURANTE a janela (o .mon submete, mas fica fora do placar). Antes/depois: recusa.
source "$_LIBDIR/contest-gate.sh"
if ! can_submit "$contest"; then
  is_staff && fail 403 "Usuário staff não submete soluções" "submit_forbidden"
  ph="$(contest_phase "$contest")"
  [[ "$ph" == before ]] && fail 403 "A competição ainda não começou" "contest_not_started"
  fail 403 "A competição já terminou" "contest_ended"
fi

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
problem="$(jq -r '.problem_id // empty' <<<"$body")"
filename="$(jq -r '.filename // empty' <<<"$body")"
codeb64="$(jq -r '.code_b64 // empty' <<<"$body")"
[[ -n "$problem" && -n "$codeb64" ]] || fail 400 "Missing problem_id or code_b64" "submit_incomplete"
valid_id "$problem" || fail 400 "Invalid problem id" "problem_invalid"
[[ -n "$filename" ]] || filename="solution"

# extensão -> tipo/linguagem (uppercase), como no MOJ
ext="${filename##*.}"
if [[ "$ext" == "$filename" || -z "$ext" ]]; then FILETYPE="TXT"
else FILETYPE="$(printf '%s' "$ext" | tr '[:lower:]' '[:upper:]')"; fi

AGORA="$EPOCHSECONDS"
ID="$(printf '%s%s%s%s%s' "$contest" "$AGORA" "$SESSION_LOGIN" "$problem" "$RANDOM" | md5sum | cut -d' ' -f1)"

mkdir -p "$SPOOLDIR"
spoolname="$contest:$AGORA:$ID:$SESSION_LOGIN:submit:$problem:$FILETYPE"
tmp="$SPOOLDIR/.in.$ID"
jq -cn --arg c "$contest" --arg l "$SESSION_LOGIN" --arg p "$problem" \
   --arg f "$filename" --arg b "$codeb64" --arg t "$FILETYPE" \
   --argjson ts "$AGORA" --arg id "$ID" \
   '{contest:$c, login:$l, problem_id:$p, filename:$f, code_b64:$b, lang:$t, time:$ts, id:$id}' > "$tmp"
mv -f "$tmp" "$SPOOLDIR/$spoolname"   # atômico: só aparece pronto p/ o daemon

# entrada provisória no histórico (7 campos) p/ o front mostrar "loading" no polling
hist="$CONTESTSDIR/$contest/controle/history"
mkdir -p "$CONTESTSDIR/$contest/controle"
printf '%s:%s:%s:%s:Not Answered Yet:%s:%s\n' \
  "$AGORA" "$SESSION_LOGIN" "$problem" "$FILETYPE" "$AGORA" "$ID" >> "$hist"

# Registra o EDITOR usado (p/ o card "editor da semana" na home). Regra: editor web
# -> "web"; arquivo -> editor declarado do usuário (favorite_editor). O front manda
# {source:"web"|"file"}; sem isso, heurística pelo nome (o editor web usa solution.<ext>).
src="$(jq -r '.source // empty' <<<"$body")"
if [[ "$src" != "web" && "$src" != "file" ]]; then
  [[ "$filename" == "solution" || "$filename" =~ ^solution\.[A-Za-z0-9]+$ ]] && src="web" || src="file"
fi
if [[ "$src" == "web" ]]; then editor="web"
else FAVORITE_EDITOR=""; read_profile "$contest" "$SESSION_LOGIN" 2>/dev/null; editor="${FAVORITE_EDITOR:-outro}"; fi
mkdir -p "$CONTESTSDIR/$contest/var"
printf '%s:%s:%s:%s\n' "$AGORA" "$ID" "$SESSION_LOGIN" "$editor" \
  >> "$CONTESTSDIR/$contest/var/editor-log" 2>/dev/null || true

ok_json '{submission_id:$id, status:"queued"}' --arg id "$ID"
