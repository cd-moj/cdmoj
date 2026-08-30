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
  { is_staff || is_cstaff; } && fail 403 "Usuário staff não submete soluções" "submit_forbidden"
  is_animeitor && fail 403 "Conta de placar (.animeitor) não submete soluções" "submit_forbidden"
  ph="$(contest_phase "$contest")"
  [[ "$ph" == before ]] && fail 403 "A competição ainda não começou" "contest_not_started"
  fail 403 "A competição já terminou" "contest_ended"
fi

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
problem="$(jq -r '.problem_id // empty' <<<"$body")"
filename="$(jq -r '.filename // empty' <<<"$body")"
# ⚠ a FONTE nunca passa por variável de argv: vai do corpo direto para ARQUIVO. O spool era
# escrito com `--arg b "$codeb64"` — fonte >~96 KiB estourava o ARG_MAX do jq, o spool saía com
# 0 BYTES e a submissão ficava "Not Answered Yet" para sempre (incidente de 2026-08-19: 6 presas).
B64F="$(mktemp)"; trap 'rm -f "$B64F"' EXIT
jq -r '.code_b64 // empty' <<<"$body" | tr -d '\r\n' > "$B64F"
b64sz="$(stat -c%s "$B64F" 2>/dev/null || echo 0)"
[[ -n "$problem" && "$b64sz" -gt 0 ]] || fail 400 "Missing problem_id or code_b64" "submit_incomplete"
valid_id "$problem" || fail 400 "Invalid problem id" "problem_invalid"
[[ -n "$filename" ]] || filename="solution"
# nome de arquivo do aluno é ENTRADA HOSTIL (ver safe_src_filename): o juiz o materializa e os
# compile.sh de make o entregam ao /bin/sh. `l(1).cpp` — a marca de download repetido do
# navegador — dava Compilation Error.
filename="$(safe_src_filename "$filename")"

# teto da FONTE (política, não limite técnico — o técnico morreu com o --arg): base64 ≈ 4/3
: "${SUBMIT_MAX_KB:=1024}"
if (( b64sz > SUBMIT_MAX_KB * 1024 * 4 / 3 + 4096 )); then
  fail 413 "Fonte muito grande (máx ${SUBMIT_MAX_KB} KB)" "source_too_large"
fi

# extensão -> tipo/linguagem (uppercase), como no MOJ
ext="${filename##*.}"
if [[ "$ext" == "$filename" || -z "$ext" ]]; then FILETYPE="TXT"
else FILETYPE="$(printf '%s' "$ext" | tr '[:lower:]' '[:upper:]')"; fi

# WHITELIST de linguagens do problema — FORÇADA AQUI (o dropdown da web é só conveniência;
# antes disto a restrição era decorativa: trocar a extensão burlava até o ban de função).
# Mesma cadeia da listagem (lib/langs.sh): override do contest -> LANGUAGES -> pacote -> todas.
source "$_LIBDIR/langs.sh"
_wl="$(effective_problem_langs "$contest" "$problem")"
if ! lang_allowed "$_wl" "$FILETYPE"; then
  [[ -z "$_wl" || "$_wl" == '[]' ]] && _wl="$(platform_langs_json)"   # mostra o CHÃO real
  _wll="$(jq -r 'join(", ")' <<<"$_wl" 2>/dev/null)"
  if [[ "$FILETYPE" == TXT ]]; then
    fail 400 "Arquivo sem extensão de linguagem — este problema aceita: ${_wll:-?}" "lang_not_allowed"
  fi
  fail 400 "Linguagem .${ext,,} não aceita neste problema (aceitas: ${_wll:-?})" "lang_not_allowed"
fi

AGORA="$EPOCHSECONDS"
ID="$(printf '%s%s%s%s%s' "$contest" "$AGORA" "$SESSION_LOGIN" "$problem" "$RANDOM" | md5sum | cut -d' ' -f1)"

mkdir -p "$SPOOLDIR"
_sd="$(spool_shard_dir "$SESSION_LOGIN")"   # shard do DONO (lib/spool-shard.sh; K=1 ⇒ raiz)
spoolname="$contest:$AGORA:$ID:$SESSION_LOGIN:submit:$problem:$FILETYPE"
tmp="$_sd/.in.$ID"
jq -cn --arg c "$contest" --arg l "$SESSION_LOGIN" --arg p "$problem" \
   --arg f "$filename" --rawfile b "$B64F" --arg t "$FILETYPE" \
   --argjson ts "$AGORA" --arg id "$ID" \
   '{contest:$c, login:$l, problem_id:$p, filename:$f, code_b64:($b | rtrimstr("\n")), lang:$t, time:$ts, id:$id}' > "$tmp"
# FAIL CLOSED: só confirma ao aluno (e só escreve o history) com o spool VÁLIDO no disco.
# Antes, o jq falhava calado e o mv publicava um arquivo de 0 bytes — pendente eterno.
if ! jq -e '.code_b64 | length > 0' "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"
  fail 500 "Falha ao gravar a submissão — tente de novo" "spool_write_failed"
fi
mv -f "$tmp" "$_sd/$spoolname"   # atômico: só aparece pronto p/ o daemon (no shard do dono)

# entrada provisória no histórico p/ o front mostrar "loading" no polling
# (users/<login>/history: login implícito, linha de 6 campos).
mkdir -p "$(user_dir "$contest" "$SESSION_LOGIN")" 2>/dev/null
user_history_append "$contest" "$SESSION_LOGIN" \
  "$AGORA:$problem:$FILETYPE:Not Answered Yet:$AGORA:$ID"
# metrics carregam o PENDING que o placar (gerado só de metrics) mostra na hora
metrics_recompute "$contest" "$SESSION_LOGIN"

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
# Sessão de TIME: a submissão é do time (é ele que compete), mas o organizador precisa saber
# QUEM estava no teclado — nem o history nem o results carregam isso.
[[ -n "${SESSION_ACTOR:-}" ]] && printf '%s:%s:%s:%s\n' "$AGORA" "$ID" "$SESSION_LOGIN" "$SESSION_ACTOR" \
  >> "$CONTESTSDIR/$contest/var/actor-log" 2>/dev/null || true

ok_json '{submission_id:$id, status:"queued"}' --arg id "$ID"
