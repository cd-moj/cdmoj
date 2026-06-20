# GET/POST /treino/admin/contest-perms  (.admin) -> lê/define quem pode criar contest.
# {threshold:int, allow:[logins], deny:[logins]}. threshold<=0 desativa o auto-grant.
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
source "$_LIBDIR/contest-create.sh"
f="$(cc_perms_file)"

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  ok_json '{perms:$p}' --argjson p "$(cc_perms_json)"
  exit 0
fi

require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
thr="$(jq -r '(.threshold // 0) | floor' <<<"$body")"
[[ "$thr" =~ ^-?[0-9]+$ ]] || fail 422 "threshold inválido" "thr_invalid"
(( thr < 0 )) && thr=0
for L in $(jq -r '((.allow//[]) + (.deny//[])) | .[]' <<<"$body"); do
  valid_id "$L" || fail 422 "login inválido: $L" "login_invalid"
done
new="$(jq -c --argjson t "$thr" '{threshold:$t, allow:((.allow//[])|map(select(.!=""))|unique), deny:((.deny//[])|map(select(.!=""))|unique)}' <<<"$body")"
mkdir -p "$CONTESTSDIR/treino/var"
printf '%s' "$new" > "$f.tmp" && mv -f "$f.tmp" "$f"
audit_log contest-perms "threshold=$thr allow=[$(jq -r '.allow|join(",")' <<<"$new")] deny=[$(jq -r '.deny|join(",")' <<<"$new")]"
ok_json '{saved:true, perms:$p}' --argjson p "$new"
