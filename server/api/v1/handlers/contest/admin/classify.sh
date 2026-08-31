# /contest/admin/classify?contest=<id>  (admin DO contest) — classificação p/ a PRÓXIMA FASE
# GET  -> {stages:[...]} (classification.json inteiro; [] se não existe)
# POST {action, stage?, ...}:
#   preview  {config}            -> roda o MOTOR (score/classify-br.sh) SEM gravar; devolve a relação
#   apply    {config, name?, venue?, when?} -> grava/regrava o stage como RASCUNHO (status:draft)
#                                    com os times do motor (via/sede/place/detail); mantém os
#                                    manuais (via:"comite") já adicionados
#   publish|unpublish            -> troca status draft<->published (só publicado aparece no placar)
#   add      {login, note?}      -> promove time MANUAL (comitê/regra 3): via:"comite"
#   remove   {login}             -> tira o time (qualquer via)
# Etapas futuras (PDA/Mundial) já cabem no shape (stages[] + next_stage) — sem regras hoje.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
CF="$CONTESTSDIR/$contest/classification.json"

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  if [[ -s "$CF" ]]; then ok_json_slurp '{stages:($f[0].stages // [])}' f "$(cat "$CF")"
  else ok_json '{stages:[]}'; fi
  exit 0
fi

require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
action="$(jq -r '.action // ""' <<<"$body")"
stage="$(jq -r '.stage // "final-br"' <<<"$body")"
[[ "$stage" =~ ^[a-z0-9-]{1,32}$ ]] || fail 400 "stage inválido" "stage_invalid"

_stage_upsert(){ # <filtro-jq-do-stage> [args de jq...] — aplica sobre o stage no arquivo
  local filt="$1"; shift
  local cur='{"version":1,"stages":[]}'
  [[ -s "$CF" ]] && cur="$(cat "$CF")"
  local tmp="$CF.tmp.${BASHPID}"
  jq -c --arg sid "$stage" "$@" '
    .stages = ((.stages // []) | if any(.[]?; .id == $sid) then . else . + [{id:$sid, status:"draft", teams:{}}] end)
    | .stages |= map(if .id == $sid then ('"$filt"') else . end)' <<<"$cur" > "$tmp" 2>/dev/null
  [[ -s "$tmp" ]] || { rm -f "$tmp"; fail 500 "Falha ao gravar" "write_fail"; }
  mv -f "$tmp" "$CF"
}

case "$action" in
  preview|apply)
    cfg="$(jq -c '.config // {}' <<<"$body")"
    W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
    printf '%s' "$cfg" > "$W/cfg.json"
    if ! bash "$_DIR/../../score/classify-br.sh" "$contest" "$W/cfg.json" "$W/out.json" 2>"$W/err"; then
      fail 422 "Motor falhou: $(head -c 200 "$W/err")" "engine_failed"
    fi
    if [[ "$action" == preview ]]; then
      ok_json_slurp '{preview:$f[0]}' f "$(cat "$W/out.json")"
      exit 0
    fi
    name="$(jq -r '.name // "Final Brasileira"' <<<"$body")"
    venue="$(jq -r '.venue // "Uberlândia"' <<<"$body")"
    when="$(jq -r '.when // "novembro/2026"' <<<"$body")"
    # apply: times do motor substituem os automáticos; os MANUAIS (via comite) sobrevivem
    _stage_upsert '
      . + {name:$nm, venue:$vn, when:$wh, region:($res[0].region // "Brasil"),
           config:($cfgj|fromjson), applied_at:(now|floor), applied_by:$who,
           next_stage:(.next_stage // "pda"),
           teams:(((.teams // {}) | with_entries(select(.value.via == "comite")))
                  + ($res[0].classified | map({key:.login,
                        value:{via, sede, place, total, detail, at:(now|floor)}}) | from_entries))}' \
      --slurpfile res "$W/out.json" --arg cfgj "$cfg" \
      --arg nm "$name" --arg vn "$venue" --arg wh "$when" --arg who "$SESSION_LOGIN"
    audit_log_to "$contest" classify "apply stage=$stage n=$(jq -r '.total' "$W/out.json") by=$SESSION_LOGIN"
    ok_json_slurp '{applied:true, stage:$s, result:$f[0]}' f "$(cat "$W/out.json")" --arg s "$stage"
    ;;
  publish|unpublish)
    st=published; [[ "$action" == unpublish ]] && st=draft
    [[ -s "$CF" ]] || fail 404 "Nada aplicado ainda" "no_stage"
    _stage_upsert '. + {status:$st} + (if $st == "published" then {published_at:(now|floor)} else {} end)' --arg st "$st"
    audit_log_to "$contest" classify "$action stage=$stage by=$SESSION_LOGIN"
    ok_json '{status:$st, stage:$s}' --arg st "$st" --arg s "$stage"
    ;;
  add)
    login="$(jq -r '.login // ""' <<<"$body")"; note="$(jq -r '.note // ""' <<<"$body")"
    valid_id "$login" || fail 400 "login inválido" "login_invalid"
    user_exists "$contest" "$login" || fail 404 "Time não encontrado" "notfound"
    _stage_upsert '.teams[$l] = {via:"comite", note:$nt, at:(now|floor), by:$who}' \
      --arg l "$login" --arg nt "$note" --arg who "$SESSION_LOGIN"
    audit_log_to "$contest" classify "add stage=$stage login=$login note=$note by=$SESSION_LOGIN"
    ok_json '{added:$l, stage:$s}' --arg l "$login" --arg s "$stage"
    ;;
  remove)
    login="$(jq -r '.login // ""' <<<"$body")"
    valid_id "$login" || fail 400 "login inválido" "login_invalid"
    [[ -s "$CF" ]] || fail 404 "Nada aplicado ainda" "no_stage"
    _stage_upsert 'del(.teams[$l])' --arg l "$login"
    audit_log_to "$contest" classify "remove stage=$stage login=$login by=$SESSION_LOGIN"
    ok_json '{removed:$l, stage:$s}' --arg l "$login" --arg s "$stage"
    ;;
  *) fail 400 "action deve ser preview|apply|publish|unpublish|add|remove" "action_invalid";;
esac
