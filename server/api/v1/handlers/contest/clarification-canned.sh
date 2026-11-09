# /contest/clarification-canned?contest=<c> — RESPOSTAS PRONTAS de clarification (09/11/2026; pedido do Roberto: o
# botão "sem resposta"). Um clique no editor de resposta manda o texto, em PRIVADO (só o time que perguntou).
#   GET  (quem responde: admin, juiz, .mon)  -> {answers:[texto…], custom}
#   POST (admin ou juiz-chefe) {answers:[texto…]} grava a lista (1..20 textos de até 200 caracteres) | {reset:true}
# Sem lista gravada: as 4 do ICPC no idioma do contest (LOCALE pt/en/es). A lista mora em
# contests/<c>/clarification-canned.json (JSON, nunca no conf: texto de gente não vai para arquivo sourced).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_admin || is_judge || is_mon; } || fail 403 "Apenas admin/juiz/monitor" "answer_forbidden"
f="$CONTESTSDIR/$contest/clarification-canned.json"

default_list() {
  case "$(conf_value "$contest" LOCALE)" in
    en) printf '%s\n' '["No comment.","Read the problem statement.","Yes.","No."]' ;;
    es) printf '%s\n' '["Sin comentarios.","Lee el enunciado.","Sí.","No."]' ;;
    *)  printf '%s\n' '["Sem comentários.","Leia o enunciado.","Sim.","Não."]' ;;
  esac
}

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  if [[ -s "$f" ]] && jq -e 'type == "array" and length > 0' "$f" >/dev/null 2>&1; then
    ok_json '{answers:$a, custom:true}' --argjson a "$(jq -c '[.[] | tostring]' "$f")"
  else
    ok_json '{answers:$a, custom:false}' --argjson a "$(default_list)"
  fi
  exit 0
fi

require_method POST
is_admin_or_chief || fail 403 "Só o juiz-chefe ou o admin editam as respostas prontas" "chief_required"
body="$(read_body)"
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
if [[ "$(jq -r '.reset == true' <<<"$body")" == true ]]; then
  rm -f "$f"
  audit_log_to "$contest" clarification-canned "reset by=$SESSION_LOGIN"
  ok_json '{answers:$a, custom:false}' --argjson a "$(default_list)"
  exit 0
fi
list="$(jq -c '[(.answers // [])[] | select(type == "string") | gsub("^\\s+|\\s+$"; "") | select(length > 0)]' <<<"$body" 2>/dev/null)"
[[ -n "$list" ]] || fail 422 "answers: lista de textos" "answers_invalid"
n="$(jq 'length' <<<"$list")"
(( n >= 1 && n <= 20 )) || fail 422 "De 1 a 20 respostas" "answers_count"
jq -e 'all(.[]; length <= 200)' >/dev/null <<<"$list" || fail 422 "Cada resposta tem até 200 caracteres" "answer_long"
printf '%s\n' "$list" > "$f.tmp" && mv -f "$f.tmp" "$f"
audit_log_to "$contest" clarification-canned "set n=$n by=$SESSION_LOGIN"
ok_json '{answers:$a, custom:true}' --argjson a "$list"
