# GET/POST /contest/admin/esqueletos?contest=<id>   (admin DO contest) — módulo `esqueletos`
# O esqueleto de código por linguagem que o editor embutido mostra ao time (lib/esqueletos.sh).
# GET  -> {module_on, editor_on, effective, score_mode, max_bytes, langs:{<lang>:{mode:"custom",code}|{mode:"off"}}}
#         (linguagem ausente = o PADRÃO, que mora só em web/shared/languages.js)
# POST {action:"set",   lang, code}  -> esqueleto personalizado (code vazio = sem esqueleto, como "off")
#      {action:"off",   lang}        -> a linguagem começa VAZIA
#      {action:"reset", lang}        -> volta ao padrão (some do arquivo)
#   -> o mesmo corpo do GET. Gravar LIGA o módulo (mod_enable, doutrina dos módulos) e por isso EXIGE o
#      editor embutido: sem ele, 422 `editor_required`. Linguagem fora da plataforma e do que o contest
#      declara = 422 `lang_invalid`; código acima de ESQ_MAX_BYTES = 422 `code_too_big`. Auditado.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

_esq_body(){
  ok_json_slurp '{module_on:$on, editor_on:$ed, effective:($on and $ed), score_mode:$sm, max_bytes:$max, langs:$L[0]}' \
    L "$(esq_langs_json "$contest")" \
    --argjson on "$(mod_on "$contest" esqueletos && echo true || echo false)" \
    --argjson ed "$(esq_editor_on "$contest" && echo true || echo false)" \
    --arg sm "$(contest_score_mode "$contest")" --argjson max "$ESQ_MAX_BYTES"
}

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then _esq_body; exit 0; fi

require_method POST
bf="$(read_body_file)"; W="$(mktemp -d)"; trap 'rm -rf "$W" "$bf"' EXIT
jq -e 'type == "object"' "$bf" >/dev/null 2>&1 || fail 400 "JSON inválido" "bad_json"
action="$(jq -r '.action // ""' "$bf")"; lang="$(jq -r '.lang // "" | tostring' "$bf")"
case "$action" in set|off|reset) ;; *) fail 422 "Ação inválida (set, off ou reset)" "action_invalid";; esac
esq_lang_allowed "$contest" "$lang" || fail 422 "Linguagem inválida para este contest: $lang" "lang_invalid"
esq_editor_on "$contest" || fail 422 "Esqueletos de código precisam do editor embutido: ligue \"Editor de código no browser\" nas Regras antes" "editor_required"

esq_langs_json "$contest" > "$W/cur.json"
mode="$action"
if [[ "$action" == set ]]; then
  jq -e '(.code | type) == "string"' "$bf" >/dev/null 2>&1 || fail 422 "Falta o código (code)" "code_missing"
  jq -j '.code' "$bf" > "$W/code"                                   # o texto do admin só anda por ARQUIVO
  n="$(wc -c < "$W/code")"; n="${n//[^0-9]/}"
  (( ${n:-0} <= ESQ_MAX_BYTES )) || fail 422 "Esqueleto grande demais (máx. $ESQ_MAX_BYTES bytes)" "code_too_big"
  if [[ -z "$(tr -d '[:space:]' < "$W/code")" ]]; then mode=off; fi   # vazio = sem esqueleto
fi
case "$mode" in
  set)   jq -c --arg l "$lang" --rawfile code "$W/code" '.[$l] = {mode:"custom", code:$code}' "$W/cur.json" > "$W/new.json" ;;
  off)   jq -c --arg l "$lang" '.[$l] = {mode:"off"}' "$W/cur.json" > "$W/new.json" ;;
  reset) jq -c --arg l "$lang" 'del(.[$l])' "$W/cur.json" > "$W/new.json" ;;
esac
[[ -s "$W/new.json" ]] || fail 500 "Falha ao montar os esqueletos" "write_failed"
esq_write "$contest" "$W/new.json" || fail 500 "Falha ao gravar os esqueletos" "write_failed"
mod_on "$contest" esqueletos || mod_enable "$contest" esqueletos
audit_log_to "$contest" esqueletos-"$mode" "lang=$lang${n:+ bytes=$n}"
_esq_body
