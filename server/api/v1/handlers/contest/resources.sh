# GET /contest/resources?contest=<id>   (Bearer)
# Seção "Prova": arquivos adicionais (caderno, time limits...) (opcional).
# Lê contests/<id>/resources.json (array de {label,url[,type,lang]}); senão {items:[]}.
#
# Documento da prova entra aqui com `type`/`lang` (doc_publish) — é o que deixa a aba Contest
# mostrar UMA linha por documento com os idiomas ao lado, em vez de um bullet por idioma.
# ⚠ O MESMO gate de fase do /contest/doc vale aqui: sem ele o time via, antes do início, a
# linha "Caderno de Problemas" (que só daria 404 ao clicar) — anúncio do que não pode ler.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

f="$CONTESTSDIR/$contest/resources.json"
if [[ ! -f "$f" ]] || ! jq -e . "$f" >/dev/null 2>&1; then
  emit_json 200 OK; jq -cn '{success:true, items:[]}'; exit 0
fi

# organização vê tudo; time vê só o que a fase libera (mesma regra do handlers/contest/doc.sh)
_res_org=false
{ is_admin_or_chief || is_judge || is_staff || is_cstaff || is_mon; } && _res_org=true
if [[ "$_res_org" == true ]]; then
  emit_json 200 OK; jq -c '{success:true, items:.}' "$f"; exit 0
fi

source "$_DIR/lib/contest-gate.sh"
phase="$(contest_phase "$contest")"
over=false; contest_over_for_all "$contest" && over=true
emit_json 200 OK
jq -c --arg phase "$phase" --argjson over "$over" '
  {success:true, items: [ .[] | select(
      (.type // "") as $t
      | if   $t == "contest" or $t == "times" then $phase != "before"
        elif $t == "editorial"               then $over
        else true end) ]}' "$f"
