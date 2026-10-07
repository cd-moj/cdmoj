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
    score_anon) _vmsg="o placar é anônimo e o virtual compara com o placar oficial, com nomes — desligue o placar anônimo nas Regras" ;;
    type)    _vmsg="por ora só contests no modo ICPC" ;;
    window)  _vmsg="o contest precisa de início e fim definidos" ;;
    *)       _vmsg="contest não elegível ($VR_REASON)" ;;
  esac
  fail 422 "Participação virtual indisponível: $_vmsg" "virtual_not_eligible"
done
# PRÉ-REQUISITOS (lib/modules.sh mod_requires_ok): `inscricoes` exige as contas do treino (USERS_FROM);
# `esqueletos` exige o editor embutido (o sentido inverso — desligar o editor com o módulo ligado — é recusado no
# admin/settings). Só p/ quem LIGA agora: módulo que já estava ligado sem o pré-requisito não trava o POST (a
# Central avisa; desligar sempre pode).
_curm=",$(mod_raw "$contest"),"
for m in "${ON[@]}"; do
  [[ "$_curm" == *",$m,"* ]] && continue
  mod_requires_ok "$contest" "$m" || fail 422 "$MOD_REQ_MSG" "$MOD_REQ_CODE"
done
cur=",$(mod_raw "$contest"),"
for m in "${ON[@]}";  do [[ "$cur" == *",$m,"* ]] || cur="$cur$m,"; done
for m in "${OFF[@]}"; do cur="${cur//,$m,/,}"; done
mod_set "$contest" "$cur"
# DESLIGAR DESLIGA A REGRA (03/10/2026): efeitos que o arquivo sozinho não dá conta
_was=",$(IFS=,; echo "${ON[*]:-}"),"; _off=",$(IFS=,; echo "${OFF[*]:-}"),"
_rel=0
if [[ "$_off" == *",maquinas,"* ]]; then   # a trava no disco seguiria barrando no router (que só olha o arquivo)
  source "$_LIBDIR/site-lock.sh"; _rel="$(sl_release_contest "$contest")"
fi
if [[ "$_was$_off" == *",coortes,"* || "$_was$_off" == *",sedes,"* || "$_was$_off" == *",baloes,"* ]]; then
  mkdir -p "$CONTESTSDIR/$contest/var"; touch "$CONTESTSDIR/$contest/var/.score-dirty" 2>/dev/null   # placar/visões mudam
fi
# religar os balões: varredura COMPLETA (o carimbo andou com o módulo desligado; o id da tarefa é determinístico)
[[ "$_was" == *",baloes,"* ]] && rm -f "$CONTESTSDIR/$contest/print-requests/.balloon-stamp" "$CONTESTSDIR/$contest/print-requests/.balloon-prev" 2>/dev/null
audit_log_to "$contest" modules-set "on=$(IFS=,; echo "${ON[*]:-}") off=$(IFS=,; echo "${OFF[*]:-}") agora=$(mod_raw "$contest")"
_mods_body
