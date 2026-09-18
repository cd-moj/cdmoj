# GET/POST /treino/virtual/friends   (Bearer do TREINO)
# "MEUS ESCOLHIDOS": os virtuais que ESTE login quer ver sempre no placar da participação virtual
# (amigos p/ se comparar). UMA lista por conta, p/ todos os contests — em cada prova aparecem os
# escolhidos que fizeram o virtual daquela prova. Só o PRÓPRIO login lê e escreve a sua lista: não há
# parâmetro de usuário. Não fala de contest nenhum (por isso não passa pelo portão do virtual) e não
# confere se a conta escolhida existe (seria oráculo de existência).
# GET  -> {logins:[…], max}
# POST {add?:[…], remove?:[…]}   alterna (o 📌 da linha)      | 422 friends_invalid · friends_limit
#      {logins:[…]}              substitui o conjunto (o painel)
require_auth_contest treino
source "$_LIBDIR/virtual.sh"
L="$SESSION_LOGIN"
if [[ "${REQUEST_METHOD:-GET}" == POST ]]; then
  body="$(read_body)"; jq -e 'type=="object"' >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
  # todo login citado tem de ser um id são (o arquivo é JSON, nunca sourced — mas a lista vira
  # comparação de string no cliente e grep no rename: nada de espaço, aspas ou barra)
  bad="$(jq -r '[(.add // []), (.remove // []), (.logins // [])] | add | map(select((type != "string") or (test("^[A-Za-z0-9._@+-]{1,64}$") | not))) | length' <<<"$body" 2>/dev/null)"
  [[ "$bad" == 0 ]] || fail 422 "Login inválido na lista" "friends_invalid"
  vr_lock "$L" || fail 503 "Tente de novo" "virtual_busy"
  cur="$(vr_friends_get "$L")"
  new="$(jq -c --argjson cur "$cur" --arg me "$L" '
      (if has("logins") then .logins else ($cur + (.add // [])) end) as $base
      | (.remove // []) as $rm
      | $base | map(select(. != $me and (. as $x | $rm | index($x) | not))) | unique' <<<"$body" 2>/dev/null)"
  [[ -n "$new" ]] || { vr_unlock; fail 500 "Falha ao montar a lista" "build_fail"; }
  if (( $(jq 'length' <<<"$new") > VR_FRIENDS_MAX )); then vr_unlock; fail 422 "A lista aceita no máximo $VR_FRIENDS_MAX logins" "friends_limit"; fi
  vr_friends_set "$L" "$new" || { vr_unlock; fail 500 "Falha ao gravar" "save_fail"; }
  vr_unlock
fi
ok_json '{logins:$l, max:$m}' --argjson l "$(vr_friends_get "$L")" --argjson m "$VR_FRIENDS_MAX"
