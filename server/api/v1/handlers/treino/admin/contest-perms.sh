# GET/POST /treino/admin/contest-perms  (.admin) -> quem pode criar contest E problemas/coleções.
# Arquivo: contests/treino/var/contest-perms.json {threshold, allow[], deny[], allow_meta{}, deny_meta{}}
# (meta = {login:{by,at,note}} — a trilha "quem liberou e quando", 2026-09-15).
# GET  -> {perms, allow_info:[{login,name,has_photo,by,by_name,at,note}], deny_info:[…], me}
# POST por AÇÃO (a UI):
#   {action:"add", list:"allow"|"deny", login, note?}  conta tem de existir no treino (404 unknown_login);
#                                                        `*.admin` na allow = 422 already_admin; sai da lista oposta
#   {action:"remove", list, login}
#   {action:"threshold", threshold}
# POST LEGADO {threshold, allow[], deny[]} (substituição total) segue aceito: entrada nova ganha meta
# com o chamador, removida perde a meta.
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
source "$_LIBDIR/contest-create.sh"

_info(){ # <perms-json> <allow|deny> -> [{login,name,has_photo,by,by_name,at,note}]
  local p="$1" k="$2" l out='[]' nm ph by bn at note
  while IFS= read -r l; do
    [[ -n "$l" ]] || continue
    nm="$(user_fullname_of treino "$l")"; ph=false; [[ -f "$CONTESTSDIR/treino/users/$l/photo.png" ]] && ph=true
    by="$(jq -r --arg l "$l" ".${k}_meta[\$l].by // \"\"" <<<"$p")"; at="$(jq -r --arg l "$l" ".${k}_meta[\$l].at // 0" <<<"$p")"
    note="$(jq -r --arg l "$l" ".${k}_meta[\$l].note // \"\"" <<<"$p")"; bn=""; [[ -n "$by" ]] && bn="$(user_fullname_of treino "$by")"
    [[ "$at" =~ ^[0-9]+$ ]] || at=0
    out="$(jq -c --arg l "$l" --arg nm "$nm" --argjson ph "$ph" --arg by "$by" --arg bn "$bn" --argjson at "$at" --arg note "$note" \
      '. + [{login:$l, name:(if $nm=="" then null else $nm end), has_photo:$ph, by:(if $by=="" then null else $by end), by_name:(if $bn=="" then null else $bn end), at:(if $at==0 then null else $at end), note:$note}]' <<<"$out")"
  done < <(jq -r ".${k}[]" <<<"$p")
  printf '%s' "$out"
}
_respond(){ local p; p="$(cc_perms_json)"
  ok_json '{saved:$sv, perms:$p, allow_info:$ai, deny_info:$di, me:$me}' --argjson sv "${1:-false}" --argjson p "$p" \
    --argjson ai "$(_info "$p" allow)" --argjson di "$(_info "$p" deny)" --arg me "$SESSION_LOGIN"; }

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then _respond false; exit 0; fi

require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
cur="$(cc_perms_json)"; action="$(jq -r '.action // ""' <<<"$body")"

if [[ -n "$action" ]]; then
  case "$action" in
    add|remove)
      list="$(jq -r '.list // ""' <<<"$body")"; [[ "$list" == allow || "$list" == deny ]] || fail 400 "list deve ser allow ou deny" "list_invalid"
      login="$(jq -r '.login // ""' <<<"$body")"; login="${login//[[:space:]]/}"
      { [[ -n "$login" ]] && valid_id "$login"; } || fail 422 "login inválido" "login_invalid"
      other=deny; [[ "$list" == deny ]] && other=allow
      if [[ "$action" == add ]]; then
        user_exists treino "$login" || fail 404 "Conta não existe no treino: $login" "unknown_login"
        [[ "$list" == allow && "$login" == *.admin ]] && fail 422 "$login já é administrador (sempre pode criar)" "already_admin"
        note="$(jq -r '.note // ""' <<<"$body")"; note="${note//$'\n'/ }"; note="${note:0:200}"
        new="$(jq -c --arg l "$login" --arg k "$list" --arg o "$other" --arg by "$SESSION_LOGIN" --argjson at "$EPOCHSECONDS" --arg note "$note" '
          .[$k] = ((.[$k] // []) + [$l] | unique) | .[$o] = ((.[$o] // []) | map(select(. != $l)))
          | .[$k+"_meta"][$l] = {by:$by, at:$at, note:$note} | del(.[$o+"_meta"][$l])' <<<"$cur")"
      else
        new="$(jq -c --arg l "$login" --arg k "$list" '.[$k] = ((.[$k] // []) | map(select(. != $l))) | del(.[$k+"_meta"][$l])' <<<"$cur")"
      fi
      cc_perms_write "$new"
      audit_log contest-perms "action=$action list=$list login=$login by=$SESSION_LOGIN";;
    threshold)
      thr="$(jq -r '(.threshold // 0) | floor' <<<"$body")"; [[ "$thr" =~ ^-?[0-9]+$ ]] || fail 422 "threshold inválido" "thr_invalid"
      (( thr < 0 )) && thr=0
      new="$(jq -c --argjson t "$thr" '.threshold = $t' <<<"$cur")"; cc_perms_write "$new"
      audit_log contest-perms "action=threshold threshold=$thr by=$SESSION_LOGIN";;
    *) fail 400 "action inválida (add|remove|threshold)" "action_invalid";;
  esac
  _respond true; exit 0
fi

# legado: substituição total {threshold, allow, deny}
thr="$(jq -r '(.threshold // 0) | floor' <<<"$body")"
[[ "$thr" =~ ^-?[0-9]+$ ]] || fail 422 "threshold inválido" "thr_invalid"
(( thr < 0 )) && thr=0
for L in $(jq -r '((.allow//[]) + (.deny//[])) | .[]' <<<"$body"); do
  valid_id "$L" || fail 422 "login inválido: $L" "login_invalid"
done
new="$(jq -c --argjson t "$thr" --arg by "$SESSION_LOGIN" --argjson at "$EPOCHSECONDS" --argjson cur "$cur" '
  {threshold:$t, allow:((.allow//[])|map(select(.!=""))|unique), deny:((.deny//[])|map(select(.!=""))|unique)} as $n
  | $n + {allow_meta: ([$n.allow[] | {key:., value:($cur.allow_meta[.] // {by:$by, at:$at, note:""})}] | from_entries),
          deny_meta:  ([$n.deny[]  | {key:., value:($cur.deny_meta[.]  // {by:$by, at:$at, note:""})}] | from_entries)}' <<<"$body")"
cc_perms_write "$new"
audit_log contest-perms "threshold=$thr allow=[$(jq -r '.allow|join(",")' <<<"$new")] deny=[$(jq -r '.deny|join(",")' <<<"$new")] by=$SESSION_LOGIN"
_respond true
