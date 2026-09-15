# GET/POST /contest/admin/statement-langs?contest=<id>   (admin OU juiz-chefe .cjudge)
# Os IDIOMAS DO ENUNCIADO que a prova OFERECE na sanfona (conf `STATEMENT_LANGS`, 2026-09-15).
# GET  -> {langs:[oferecidos], default, all:[allowlist], locale,
#          available:{"<letra>": {"pt":true, "en":true, …}}}   (idioma com arquivo no contest ou tradução no banco)
# POST {langs:["pt","en"]} -> grava STATEMENT_LANGS (allowlist pt/en/es; lista vazia = só pt),
#      materializa as traduções do banco que faltam (enunciados/<skey>.<lang>.html), invalida o
#      cache de /contest/problems e audita. O `.cjudge` também define (é quem prepara a prova).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin_or_chief || fail 403 "Apenas o admin ou o juiz-chefe" "admin_required"
source "$_LIBDIR/contest-create.sh"
source "$_LIBDIR/contest-statement.sh"

_avail_json(){ # -> {"<letra>": {"<lang>": true}}
  local probs n i letter skey out='{}' l bf have
  probs="$(cc_probs_json "$contest")"; n="$(jq -r 'length' <<<"$probs" 2>/dev/null)"; [[ "$n" =~ ^[0-9]+$ ]] || n=0
  for ((i=0; i<n; i++)); do
    letter="$(jq -r --argjson i "$i" '.[$i].letter // ""' <<<"$probs")"
    skey="$(jq -r --argjson i "$i" '.[$i].statement_key // ""' <<<"$probs")"
    bf=""; cs_bank_json "$skey" >/dev/null 2>&1 && bf="$(cs_bank_json "$skey")"
    have='{}'
    for l in $(stmt_langs_all); do
      if cs_file "$contest" "$skey" "$l" html >/dev/null 2>&1 && { [[ "$l" == pt ]] || [[ -f "$CONTESTSDIR/$contest/enunciados/$skey.$l.html" ]]; } \
         || [[ -f "$CONTESTSDIR/$contest/enunciados/$skey$([[ "$l" == pt ]] || printf '.%s' "$l").pdf" ]] \
         || { [[ -n "$bf" ]] && jq -e --arg l "$l" 'if $l=="pt" then ((.statement_html_b64 // "") != "") else ((.statements[$l].html_b64 // "") != "") end' "$bf" >/dev/null 2>&1; }; then
        have="$(jq -c --arg l "$l" '.[$l]=true' <<<"$have")"
      fi
    done
    out="$(jq -c --arg k "$letter" --argjson v "$have" '.[$k]=$v' <<<"$out")"
  done
  printf '%s' "$out"
}

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  langs="$(cs_langs "$contest")"
  ok_json '{langs:($l|split(" ")), default:$d, all:($a|split(" ")), locale:$loc, available:$av}' \
    --arg l "$langs" --arg d "$(cs_default "$contest" "$langs")" --arg a "$(stmt_langs_all)" \
    --arg loc "$(conf_value "$contest" LOCALE)" --argjson av "$(_avail_json)"
  exit 0
fi

require_method POST
body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
jq -e '.langs | type == "array"' >/dev/null 2>&1 <<<"$body" || fail 400 "langs deve ser uma lista" "langs_invalid"
# `. as $x` ANTES do index: dentro do pipe o `.` já é a lista, não o elemento (armadilha do jq)
bad="$(jq -r --arg all "$(stmt_langs_all)" '($all|split(" ")) as $ok | [.langs[] | . as $x | select(type!="string" or (($ok|index($x)) == null))] | length' <<<"$body")"
[[ "$bad" == 0 ]] || fail 422 "idioma fora da lista ($(stmt_langs_all))" "lang_invalid"
new="$(cs_norm "$(jq -r '.langs | join(" ")' <<<"$body")")"
if [[ "$new" == pt ]]; then cc_del_conf_var "$contest" STATEMENT_LANGS; else cc_set_conf_var "$contest" STATEMENT_LANGS "$new"; fi
# materializa do banco as traduções que faltam (a listagem também faz, preguiçosa — aqui é na hora)
probs="$(cc_probs_json "$contest")"
while IFS= read -r skey; do
  [[ -n "$skey" ]] || continue
  bf="$(cs_bank_json "$skey" 2>/dev/null)" || continue
  CC_KEEP_STATEMENTS=1 cs_bank_write "$bf" "$CONTESTSDIR/$contest" "$skey" langs
done < <(jq -r '.[].statement_key // empty' <<<"$probs")
mkdir -p "$CONTESTSDIR/$contest/var" 2>/dev/null; touch "$CONTESTSDIR/$contest/var/.problems-dirty" 2>/dev/null
audit_log_to "$contest" statement-langs "langs=$new by=$SESSION_LOGIN"
ok_json '{saved:true, langs:($l|split(" ")), default:$d}' --arg l "$new" --arg d "$(cs_default "$contest" "$new")"
