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
# `virtual` só LIGA em contest que PODE virar virtual: não-secreto, ICPC, janela definida e TODOS os
# problemas públicos no treino (o que o tempo resolve — ainda rodando, placar congelado — não barra:
# o módulo fica inerte até o portão abrir). A garantia de verdade é o portão por requisição de
# lib/virtual.sh; esta recusa é p/ o dono saber NA HORA por que não vai funcionar. Problema
# não-público sai só em CONTAGEM (o dono do contest pode não ser dono do problema).
for m in "${ON[@]}"; do
  [[ "$m" == virtual ]] || continue
  source "$_LIBDIR/virtual.sh"
  VR_IGNORE="module_off running frozen" vr_load "$contest" && continue
  case "$VR_REASON" in
    problems_not_public) _vmsg="há problema(s) NÃO público(s) no treino (${VR_NPRIV/#-1/?}) — a participação virtual só existe para prova com todos os problemas públicos" ;;
    secret)  _vmsg="contest secreto não pode ter participação virtual" ;;
    type)    _vmsg="por ora só contests no modo ICPC" ;;
    window)  _vmsg="o contest precisa de início e fim definidos" ;;
    *)       _vmsg="contest não elegível ($VR_REASON)" ;;
  esac
  fail 422 "Participação virtual indisponível: $_vmsg" "virtual_not_eligible"
done
cur=",$(mod_raw "$contest"),"
for m in "${ON[@]}";  do [[ "$cur" == *",$m,"* ]] || cur="$cur$m,"; done
for m in "${OFF[@]}"; do cur="${cur//,$m,/,}"; done
mod_set "$contest" "$cur"
audit_log_to "$contest" modules-set "on=$(IFS=,; echo "${ON[*]:-}") off=$(IFS=,; echo "${OFF[*]:-}") agora=$(mod_raw "$contest")"
_mods_body
