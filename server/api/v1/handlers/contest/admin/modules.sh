# GET/POST /contest/admin/modules?contest=<id>   (admin DO contest)
# GET  -> {modules:[{id,on,detected,reason}], enabled:[ids]}   (catálogo de lib/modules.sh)
# POST {on:[ids], off:[ids]} -> liga/desliga (CONTEST_MODULES no conf), 422 em id desconhecido.
#   Desligar NÃO apaga dado da feature (os arquivos ficam; religar restaura). Auditado.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
source "$_LIBDIR/contest-create.sh"

_mods_body(){ ok_json '{modules:$m, enabled:$e}' --argjson m "$(mod_catalog_json "$contest")" --argjson e "$(mod_list_json "$contest")"; }

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then _mods_body; exit 0; fi
require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
mapfile -t ON  < <(jq -r '(.on  // [])[] | tostring' <<<"$body" 2>/dev/null)
mapfile -t OFF < <(jq -r '(.off // [])[] | tostring' <<<"$body" 2>/dev/null)
for m in "${ON[@]}" "${OFF[@]}"; do mod_valid "$m" || fail 422 "Módulo desconhecido: $m" "module_invalid"; done
cur=",$(mod_raw "$contest"),"
for m in "${ON[@]}";  do [[ "$cur" == *",$m,"* ]] || cur="$cur$m,"; done
for m in "${OFF[@]}"; do cur="${cur//,$m,/,}"; done
mod_set "$contest" "$cur"
audit_log_to "$contest" modules-set "on=$(IFS=,; echo "${ON[*]:-}") off=$(IFS=,; echo "${OFF[*]:-}") agora=$(mod_raw "$contest")"
_mods_body
