# GET/POST /contest/animeitor/webcast?contest=<id>   (Bearer: .animeitor ou admin do contest)
# As CHAVES do streaming de placar para o sistema Animeitor.
#   GET                                   -> {views:[…], keys:[…], url_base:"…"}
#   POST {action:"create", view, label}   -> cria (devolve a chave e a URL prontas)
#   POST {action:"revoke", id}            -> revoga
# A chave em si aparece para este papel de propósito: é o que ele copia para configurar o
# Animeitor. Quem busca o pacote é /contest/webcast?key=… (sem sessão) — ver docs/WEBCAST.md.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_animeitor || is_admin; } || fail 403 "Apenas a conta de placar (.animeitor) ou o admin" "animeitor_required"
source "$_LIBDIR/webcast.sh"
source "$_LIBDIR/cohorts.sh"

# visões disponíveis: as que o build.sh gera (public = o placar geral; + uma por coorte)
views_json(){
  local v lbl out='[]'
  while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    case "$v" in
      public) lbl="Geral";;
      all)    lbl="Geral (com convidados)";;
      *) lbl="$(jq -r --arg i "$v" 'first(.cohorts[]|select(.id==$i)|.name) // $i' <<<"$(ch_get "$contest")" 2>/dev/null)";;
    esac
    out="$(jq -c --arg i "$v" --arg l "${lbl:-$v}" '. + [{id:$i, name:$l}]' <<<"$out")"
  done < <(ch_views "$contest" 2>/dev/null)
  printf '%s' "$out"
}

if [[ "${REQUEST_METHOD:-GET}" == POST ]]; then
  body="$(read_body)"
  jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
  action="$(jq -r '.action // empty' <<<"$body")"
  case "$action" in
    create)
      view="$(jq -r '.view // "public"' <<<"$body")"
      view="$(printf '%s' "$view" | tr -cd 'A-Za-z0-9_-')"; [[ -n "$view" ]] || view=public
      # só visão que EXISTE (senão a chave serviria um placar que nunca é gerado)
      ch_views "$contest" 2>/dev/null | grep -qxF "$view" || fail 422 "Visão inexistente" "view_invalid"
      label="$(jq -r '.label // ""' <<<"$body" | tr -d '\n\r\t' | cut -c1-60)"
      k="$(wc_create "$contest" "$view" "$label" "$SESSION_LOGIN")" \
        || fail 500 "Não consegui criar a chave" "create_failed"
      audit_log_to "$contest" webcast-key "create view=$view id=${k:6:8} by=$SESSION_LOGIN"
      ok_json '{created:true, key:$k, view:$v}' --arg k "$k" --arg v "$view"
      exit 0;;
    revoke)
      id="$(jq -r '.id // empty' <<<"$body" | tr -cd 'A-Za-z0-9')"
      [[ -n "$id" ]] || fail 400 "Informe id" "id_missing"
      wc_revoke "$contest" "$id" || fail 404 "Chave não encontrada (ou já revogada)" "key_notfound"
      audit_log_to "$contest" webcast-key "revoke id=$id by=$SESSION_LOGIN"
      ok_json '{revoked:true, id:$i}' --arg i "$id"
      exit 0;;
    *) fail 400 "Ação desconhecida" "action_invalid";;
  esac
fi

# GET: as chaves + as visões + a base da URL (o front monta o link completo com o host atual)
ok_json_slurp '{keys:($w[0].keys | sort_by(-.created_at)), views:$v[0],
                url_path:"/api/v1/contest/webcast", contest:$c}' \
  w "$(wc_get "$contest")" --slurpfile v <(views_json) --arg c "$contest"
