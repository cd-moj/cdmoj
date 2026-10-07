# lib/modules.sh — MÓDULOS ligáveis do contest (decisão do Ribas, 05/09/2026).
#
# Uma feature de EVENTO (sedes, gate de máquinas, rodadas, documentos, balões, coortes,
# inscrição, telão, classificação) não vem em bloco: uma prova de disciplina liga só o gate
# de máquinas; a Maratona liga tudo. Cada módulo agrupa painéis do admin, checagens do
# preflight, cards da Central e uma seção do spec de levantamento. Ligado/desligado vive no
# conf como CONTEST_MODULES=<ids separados por vírgula> (printf %q de um token só — sem
# escape; ausente = nenhum). Desligar NUNCA apaga dado: os arquivos da feature ficam, e o
# preflight avisa "módulo desligado com dados existentes".
# DESLIGAR DESLIGA A REGRA (decisão do Ribas, 03/10/2026 — revoga o "módulo = só UX"): com o módulo
# desligado a regra dele NÃO vale, mesmo com o arquivo no disco — `maquinas`: gate de navegador, sessão
# única e trava de sede (desligar solta os IPs presos); `sedes`: prorrogação por sede (time-overrides.json);
# `inscricoes`: só inscrito entra (o alias do time continua — é identidade); `coortes`: o corte do placar;
# `baloes`: as tarefas de balão do staff. O ponto de corte é o LEITOR de cada artefato (ug_expected,
# sl_enabled, time_override_end/contest_end_all, reg_gate_active, ch_get/ch_ctx/sc_users, pr_reconcile_balloons
# — e os espelhos do porteiro). Gravar o artefato continua LIGANDO o módulo (mod_enable).
#
# Este catálogo tem um ESPELHO em web/contest/admin/modules.js (nome/descrição/painéis p/ a
# UI). server/test/smoke-admin-nav.sh confere que as duas listas são iguais — módulo novo
# entra nos dois no mesmo commit. O gate na UI é conveniência: o acesso é cortado na API.
MODULES=(sedes maquinas rodadas documentos baloes coortes inscricoes telao classificacao virtual esqueletos)

mod_valid(){ local m; for m in "${MODULES[@]}"; do [[ "$m" == "$1" ]] && return 0; done; return 1; }
# mod_raw <c> — o valor cru do conf ("a,b,c" ou vazio); zero fork (conf_value é builtin)
# (%q escapa a vírgula — `a\,b` no conf; o `source` desfaz, o conf_value não: tira as barras aqui)
mod_raw(){ local v; v="$(conf_value "$1" CONTEST_MODULES)"; printf '%s' "${v//\\/}"; }
# mod_on <c> <id> — rc 0 se o módulo está ligado. ZERO fork (conf_value_to): roda em rota quente
mod_on(){ local __mo_v; conf_value_to __mo_v "$1" CONTEST_MODULES; __mo_v=",${__mo_v//\\/},"; [[ "$__mo_v" == *",$2,"* ]]; }
# mod_any <c> — rc 0 se algum módulo está ligado
mod_any(){ [[ -n "$(mod_raw "$1")" ]]; }
# mod_list_json <c> — ["a","b"] (só ids válidos, na ordem do catálogo)
mod_list_json(){
  local raw m out=()
  raw=",$(mod_raw "$1"),"
  for m in "${MODULES[@]}"; do [[ "$raw" == *",$m,"* ]] && out+=("$m"); done
  if (( ${#out[@]} )); then printf '%s\n' "${out[@]}" | jq -Rc . | jq -cs .; else printf '[]'; fi
}
# mod_normalize "a,b,x" -> "a,b" (só válidos, sem repetição, ordem do catálogo)
mod_normalize(){
  local in=",${1//[[:space:]]/},"; in="${in//;/,}"; local m out=""
  for m in "${MODULES[@]}"; do [[ "$in" == *",$m,"* ]] && out="${out:+$out,}$m"; done
  printf '%s' "$out"
}
# mod_set <c> "a,b" — grava (vazio = apaga a variável). Precisa de cc_set_conf_var (contest-create.sh).
mod_set(){
  local v; v="$(mod_normalize "$2")"
  if [[ -n "$v" ]]; then cc_set_conf_var "$1" CONTEST_MODULES "$v"; else cc_del_conf_var "$1" CONTEST_MODULES; fi
}
# mod_enable <c> <id>… — LIGA módulos (união, idempotente). É o que cada handler chama ao GRAVAR o
# artefato do seu módulo (rodada, coorte, gate em enforce, trava, documento, inscrição, cor de
# balão, sede/prorrogação, chave de webcast, foto de time, classificação): quem usa o recurso pela
# API/CLI não precisa de um passo a mais p/ o painel aparecer. DESLIGAR é sempre manual
# (admin/modules). Auditado `modules-auto` só quando muda algo.
mod_enable(){
  local c="$1"; shift; local cur new m added=""
  cur="$(mod_raw "$c")"; new="$cur"
  for m in "$@"; do
    mod_valid "$m" || continue
    [[ ",$new," == *",$m,"* ]] && continue
    new="${new:+$new,}$m"; added="${added:+$added,}$m"
  done
  [[ -n "$added" ]] || return 0
  declare -F cc_set_conf_var >/dev/null || source "${BASH_SOURCE[0]%/*}/contest-create.sh"
  mod_set "$c" "$new"
  declare -F audit_log_to >/dev/null && audit_log_to "$c" modules-auto "on=$added"
  return 0
}
# mod_detect <c> <id> — rc 0 se há ARTEFATO da feature no contest (ecoa o motivo). É a base da
# detecção única (bin/contest-modules-detect.sh), do pill "dados presentes" do painel e do aviso
# do preflight "módulo desligado com dados existentes".
mod_detect(){
  local d="$CONTESTSDIR/$1"
  case "$2" in
    sedes)
      [[ -s "$d/regions.json" ]] && jq -e 'type=="array" and length>0' "$d/regions.json" >/dev/null 2>&1 && { printf regions.json; return 0; }
      [[ -s "$d/teams-meta.json" ]] && jq -e '(.rules // []) | length > 0' "$d/teams-meta.json" >/dev/null 2>&1 && { printf teams-meta.json; return 0; }
      [[ -s "$d/time-overrides.json" ]] && jq -e 'length > 0' "$d/time-overrides.json" >/dev/null 2>&1 && { printf time-overrides.json; return 0; } ;;
    maquinas)
      [[ -s "$d/ua-gate.json" ]] && [[ "$(jq -r '.mode // "off"' "$d/ua-gate.json" 2>/dev/null)" != off ]] && { printf ua-gate.json; return 0; }
      [[ "$(conf_value "$1" SITE_LOCK)" == 1 ]] && { printf SITE_LOCK; return 0; }
      # o gate LEGADO (a substring única do conf) também é do módulo: desligado, ele não vale (03/10/2026)
      [[ -n "$(conf_value "$1" LOGIN_UA_SUBSTRING)" ]] && { printf LOGIN_UA_SUBSTRING; return 0; }
      [[ -s "$d/secrets/nutellaboot.key" || -n "$(conf_value "$1" NUTELLABOOT_URL)" ]] && { printf nutellaboot; return 0; } ;;
    rodadas)
      [[ -s "$d/rounds.json" ]] && jq -e '(.rounds // []) | length > 0' "$d/rounds.json" >/dev/null 2>&1 && { printf rounds.json; return 0; } ;;
    documentos)
      [[ -s "$d/docs/config.json" ]] && { printf docs/config.json; return 0; } ;;
    baloes)
      [[ -s "$d/balloons.json" ]] && jq -e 'length > 0' "$d/balloons.json" >/dev/null 2>&1 && { printf balloons.json; return 0; } ;;
    coortes)
      [[ -s "$d/cohorts.json" ]] && jq -e '(.cohorts // []) | length > 0' "$d/cohorts.json" >/dev/null 2>&1 && { printf cohorts.json; return 0; } ;;
    inscricoes)
      [[ -s "$d/registrations.json" ]] && { printf registrations.json; return 0; } ;;
    telao)
      [[ -s "$d/animeitor.json" ]] && { printf animeitor.json; return 0; }
      [[ -s "$d/webcast.json" ]] && { printf webcast.json; return 0; }
      compgen -G "$d/users/*/photo.*" >/dev/null 2>&1 && { printf fotos; return 0; } ;;
    virtual)
      compgen -G "$d/virtual/runs/*.json" >/dev/null 2>&1 && { printf virtual/runs; return 0; } ;;
    classificacao)
      [[ -s "$d/classification.json" ]] && jq -e '(.stages // []) | length > 0' "$d/classification.json" >/dev/null 2>&1 && { printf classification.json; return 0; } ;;
    esqueletos)
      [[ -s "$d/esqueletos.json" ]] && jq -e '(.langs // {}) | length > 0' "$d/esqueletos.json" >/dev/null 2>&1 && { printf esqueletos.json; return 0; } ;;
  esac
  return 1
}
# mod_catalog_json <c> — [{id, on, detected, reason}] p/ o painel Módulos e p/ o preflight
mod_catalog_json(){
  local m on det r rq
  for m in "${MODULES[@]}"; do
    on=false; mod_on "$1" "$m" && on=true
    det=false; r=""; r="$(mod_detect "$1" "$m")" && det=true
    # pré-requisito: a tela desabilita o "ligar" e diz o que falta (o código é o mesmo do 422)
    rq='{"ok":true}'; mod_requires_ok "$1" "$m" || rq="$(jq -cn --arg c "$MOD_REQ_CODE" --arg t "$MOD_REQ_MSG" '{ok:false, code:$c, message:$t}')"
    jq -cn --arg id "$m" --argjson on "$on" --argjson det "$det" --arg r "$r" --argjson rq "$rq" '{id:$id, on:$on, detected:$det, reason:$r, requires:$rq}'
  done | jq -cs .
}

# PRÉ-REQUISITOS (07/10/2026): módulo que não FUNCIONA sem outra configuração do contest não liga sem ela — por
# NENHUM caminho (painel Módulos, gravar o artefato que liga o módulo, criação/duplicar/template, CLI). Relato do
# Daniel Valle: `inscricoes` ligado num contest com 135 contas PRÓPRIAS ⇒ "só inscrito entra" barrava todo aluno, e
# a inscrição (com a conta do Treino Livre) não tinha como incluí-los. A tela e a Central dizem o que falta.
# mod_requires_ok <c> <id> -> rc 0 se pode ligar/valer; senão rc 1 com MOD_REQ_CODE e MOD_REQ_MSG (PT; a web traduz
# pelo código). `virtual` tem a sua elegibilidade própria (handlers/contest/admin/modules.sh — depende de tempo e
# dos problemas, não só de configuração).
mod_requires_ok(){
  MOD_REQ_CODE=""; MOD_REQ_MSG=""
  case "$2" in
    inscricoes)
      local _mr_uf; conf_value_to _mr_uf "$1" USERS_FROM
      [[ -n "$_mr_uf" ]] && return 0
      MOD_REQ_CODE=requires_shared_users
      MOD_REQ_MSG="A inscrição usa as contas do Treino Livre (cada aluno se inscreve com a conta dele no treino), e este contest tem contas próprias: com ela ligada, quem não está no roster não entra — e nenhuma conta própria entra nele. Com contas próprias, distribua as credenciais (Pessoas › Contas); para inscrição, o contest precisa usar as contas do treino."
      return 1 ;;
    esqueletos)
      declare -F esq_editor_on >/dev/null || source "${_LIBDIR:-${BASH_SOURCE[0]%/*}}/esqueletos.sh"
      esq_editor_on "$1" && return 0
      MOD_REQ_CODE=editor_required
      MOD_REQ_MSG="Esqueletos de código precisam do editor embutido: ligue \"Editor de código no browser\" nas Regras antes"
      return 1 ;;
  esac
  return 0
}
