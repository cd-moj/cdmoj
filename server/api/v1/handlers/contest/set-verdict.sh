# POST /contest/set-verdict?contest=<id>   (Bearer, admin ou juiz-CHEFE)
# body: {problem_id, verdict, username}
# Registra um override de veredicto: grava arquivo de spool p/ o daemon aplicar.
# ⚠ GATE: sobrescrever o veredicto de um time é ato de CHEFIA — no fluxo de veredicto manual o
# juiz comum vota (review/vote) e o desempate é do chefe (review/resolve). A UI já escondia a
# coluna do juiz puro (a lista dele é anônima e o set-verdict exige username), mas a rota
# aceitava qualquer is_judge: por curl/moj-cli um juiz comum sobrescrevia veredicto sozinho.
# Regra da casa: acesso é da API, nunca só da interface (2026-08-20).
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin_or_chief || fail 403 "Só o juiz-chefe ou o admin sobrescreve veredicto" "chief_required"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
problem="$(jq -r '.problem_id // empty' <<<"$body")"
verdict="$(jq -r '.verdict // empty' <<<"$body")"
username="$(jq -r '.username // empty' <<<"$body")"
[[ -n "$problem" && -n "$verdict" && -n "$username" ]] \
  || fail 400 "Missing problem_id, verdict or username" "incomplete"
valid_id "$problem" || fail 400 "Invalid problem id" "problem_invalid"
valid_id "$username" || fail 400 "Invalid username" "username_invalid"

AGORA="$EPOCHSECONDS"
ID="$(printf '%s%s%s%s%s' "$contest" "$AGORA" "$SESSION_LOGIN" "$username" "$RANDOM" \
      | md5sum | cut -d' ' -f1)"

mkdir -p "$SPOOLDIR"
_sd="$(spool_shard_dir "$username")"   # shard do ALUNO alvo (K=1 ⇒ raiz)
spoolname="$contest:$AGORA:$ID:$SESSION_LOGIN:setverdict:$problem"
tmp="$_sd/.in.$ID"
jq -cn --arg c "$contest" --arg j "$SESSION_LOGIN" --arg p "$problem" \
   --arg v "$verdict" --arg u "$username" --argjson ts "$AGORA" --arg id "$ID" \
   '{action:"set-verdict", contest:$c, judge:$j, problem_id:$p,
     verdict:$v, username:$u, time:$ts, id:$id}' > "$tmp"
mv -f "$tmp" "$_sd/$spoolname"

ok_json '{action:"set-verdict", id:$id, status:"queued"}' --arg id "$ID"
