# POST /treino/contest-create/duplicate  (auth treino, pode criar)
# {from, id?, name?, start?, end?, admin?, users?|users_from?} -> cria um contest NOVO a partir
# de um existente: conf+problemas+visual copiados; USUÁRIOS/submissões NUNCA (users/users_from
# só se vierem no body; senão só a conta admin). Datas: start=agora, end=start+duração original.
# Enunciados custom copiados POR ARQUIVO (statement_file + 4º arg do cc_create — sem b64).
# GATE do origem: mesmo do export — created-by + (dono OU admin), senão 404.
require_method POST
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
from="$(jq -r '.from // empty' <<<"$body")"
{ [[ -n "$from" ]] && valid_id "$from"; } || fail 400 "Informe from" "from_missing"
cdir="$CONTESTSDIR/$from"
cowner="$(head -1 "$cdir/owner" 2>/dev/null)"
{ [[ -f "$cdir/created-by" && -f "$cdir/conf" ]] && { is_admin || [[ -n "$cowner" && "$cowner" == "$SESSION_LOGIN" ]]; }; } \
  || fail 404 "Contest não encontrado" "notfound"

base="$(cc_export_spec "$from" none)"
[[ -n "$base" ]] || fail 500 "Falha ao ler o contest" "export_fail"

# enunciados custom do origem entram por statement_file/statement_pdf_file (cópia por arquivo)
srcdir="$cdir/enunciados"
tmpd="$(mktemp -d)" || fail 500 "tmp" "tmp"
: > "$tmpd/probs.jsonl"
while IFS= read -r pj; do
  [[ -n "$pj" ]] || continue
  skey="$(jq -r '.problem_id // ""' <<<"$pj")"; skey="${skey//\//#}"
  hf=""; pf=""
  [[ -n "$skey" && -f "$srcdir/$skey.html" ]] && hf="$skey.html"
  [[ -n "$skey" && -f "$srcdir/$skey.pdf"  ]] && pf="$skey.pdf"
  jq -c --arg hf "$hf" --arg pf "$pf" '.
    + (if $hf != "" then {statement_file:$hf} else {} end)
    + (if $pf != "" then {statement_pdf_file:$pf} else {} end)' <<<"$pj" >> "$tmpd/probs.jsonl"
done < <(jq -c '(.problems // [])[]' <<<"$base")
probs="$(jq -cs '.' "$tmpd/probs.jsonl")"; rm -rf "$tmpd"
[[ -n "$probs" ]] || probs='[]'

spec="$(jq -c --argjson probs "$probs" --argjson o "$body" --argjson now "$EPOCHSECONDS" '
  ((.end // 0) - (.start // 0)) as $dur
  | ((.login_start // 0) as $ls | (.start // 0) as $st | if $ls > 0 and $st > $ls then $st - $ls else 0 end) as $lead
  | ((.freeze // 0) as $fz | (.end // 0) as $en | if $fz > 0 and $en > $fz then $en - $fz else 0 end) as $fb
  | del(.id, .start, .end, .login_start, .freeze)
  | .problems = $probs
  | .name = ($o.name // ("Cópia de " + (.name // "")))
  | .start = ($o.start // $now)
  | .end   = ($o.end // (.start + (if $dur > 0 then $dur else 10800 end)))
  | (if $lead > 0 then .login_start = (.start - $lead) else . end)
  | (if $fb > 0 then .freeze = (.end - $fb) else . end)
  | (if $o.id then .id = $o.id else . end)
  | (if $o.admin then .admin = $o.admin else . end)
  | (if $o.users then .users = $o.users else . end)
  | (if $o.users_from then .users_from = $o.users_from else . end)
  | (if ((.problems // [])|length) == 0 then .allow_empty = true else . end)' <<<"$base")"
[[ -n "$spec" ]] || fail 500 "Falha ao montar o spec" "spec_fail"

cc_create "$spec" "$SESSION_LOGIN" "$SESSION_NAME" "$srcdir"
audit_log contest-create "duplicate from=$from id=$(jq -r '.contest_id' <<<"$CC_RESULT")"
ok_json '$r' --argjson r "$CC_RESULT"
