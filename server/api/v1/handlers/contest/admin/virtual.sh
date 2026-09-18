# GET/POST /contest/admin/virtual?contest=<id>   (admin DO contest)
# Painel da PARTICIPAÇÃO VIRTUAL (módulo `virtual`, lib/virtual.sh).
# GET  -> {enabled, eligible, reason, checks:[{id,ok,detail}], url, virtuals:[{login,name,solved,
#          penalty,start,used,official,removed}]}
#   `checks` é o portão aberto em partes, p/ o dono ver O QUE falta (o público só vê 404).
# POST {action:"remove"|"restore", login} -> moderação: tira/devolve uma linha do placar virtual
#   (o snapshot fica, marcado `removed`). Auditado.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
source "$_LIBDIR/virtual.sh"
RD="$CONTESTSDIR/$contest/virtual/runs"

if [[ "${REQUEST_METHOD:-GET}" == POST ]]; then
  body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
  action="$(jq -r '.action // empty' <<<"$body")"; login="$(jq -r '.login // empty' <<<"$body")"
  valid_id "$login" && [[ -f "$RD/$login.json" ]] || fail 404 "Participação não encontrada" "virtual_run_notfound"
  case "$action" in remove) v=true;; restore) v=false;; *) fail 400 "Ação inválida" "action_invalid";; esac
  t="$RD/$login.json.tmp.$BASHPID"
  jq -c --argjson v "$v" --arg by "$SESSION_LOGIN" --argjson now "$EPOCHSECONDS" \
    '.removed=$v | .removed_by=$by | .removed_at=$now' "$RD/$login.json" > "$t" && mv -f "$t" "$RD/$login.json" \
    || { rm -f "$t"; fail 500 "Falha ao gravar" "save_fail"; }
  touch "$RD"; rm -f "$CONTESTSDIR/$contest/var/virtual-board.json"
  audit_log_to "$contest" "virtual-$action" "login=$login"
fi

enabled=false; mod_on "$contest" virtual && enabled=true
eligible=false; vr_load "$contest" && eligible=true; reason="$VR_REASON"
# checklist: cada condição isolada (VR_IGNORE com todas as OUTRAS)
ALL="module_off conf_unreadable secret type window running frozen no_problems problem_invalid problems_not_public"
checks="$(for r in module_off secret type window running frozen problems_not_public; do
  ok=true; VR_IGNORE="${ALL/$r/}" vr_load "$contest" || ok=false
  det=""; [[ "$r" == problems_not_public && "$ok" == false ]] && det="${VR_NPRIV/#-1/?}"
  jq -cn --arg id "$r" --argjson ok "$ok" --arg d "$det" '{id:$id, ok:$ok, detail:$d}'
done | jq -cs .)"
virt='[]'
[[ -d "$RD" ]] && virt="$(find "$RD" -maxdepth 1 -name '*.json' -print0 2>/dev/null | xargs -0 -r cat 2>/dev/null \
  | jq -cs 'map({login, name, solved, penalty, start, used, official, removed:(.removed // false)}) | sort_by(-.solved, .penalty)')"
[[ -n "$virt" ]] || virt='[]'
ok_json_slurp '{enabled:$en, eligible:$el, reason:$r, checks:$ck, url:("/treino/virtual/?c=" + $c), virtuals:$v[0]}' v "$virt" \
  --argjson en "$enabled" --argjson el "$eligible" --arg r "$reason" --argjson ck "$checks" --arg c "$contest"
