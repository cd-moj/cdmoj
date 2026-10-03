# GET /contest/admin/preflight?contest=<id>   (admin ou juiz-chefe DO contest)
# CHECKLIST PRÉ-PROVA: roda as verificações operacionais que sempre pegam a organização de
# surpresa e devolve verde/amarelo/vermelho por item — janela, SHOWLOG (anti-vazamento de
# testes em icpc), freeze, juízes online, toolchain das linguagens permitidas, TL calibrado
# de cada problema (+ cache nos juízes online), staff de impressão, contas, spool travado.
# -> {checks:[{id,level:ok|warn|fail,label,detail,label_en,detail_en,label_es,detail_es[,action]}],
#     summary:{ok,warn,fail}}
#    TODO item é TRILÍNGUE: label/detail em PT (nome de campo legado) + `label_en`/`detail_en` +
#    `label_es`/`detail_es` — a Central escolhe pelo idioma da interface. `action` = o botão que a
#    Central põe no item (hoje: "warm_judges" → POST /contest/admin/warm-judges).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin_or_chief || fail 403 "Apenas o admin ou o juiz-chefe" "admin_required"
source "$_DIR/../../judge-gw/sched-lib.sh"
source "$_DIR/lib/tl-store.sh"
source "$_DIR/lib/judge-warm.sh"      # juiz quente × frio por problema (item judges_warm)
source "$_LIBDIR/contest-gate.sh"
source "$_LIBDIR/langs.sh"          # lang_canon_ext (cc/cxx/c++ = cpp, py3 = py) p/ a whitelist

now="$EPOCHSECONDS"
cdir="$CONTESTSDIR/$contest"
CHECKS='[]'
# add3 <id> <level> <label_pt> <detail_pt> <label_en> <detail_en> <label_es> <detail_es> [action]
# — item TRILÍNGUE (+ botão). Texto só por --arg, nunca interpolado no programa jq.
add3(){
  CHECKS="$(jq -c --arg i "$1" --arg lv "$2" --arg lb "$3" --arg d "$4" --arg le "$5" --arg de "$6" \
    --arg ls "$7" --arg ds "$8" --arg a "${9:-}" \
    '. + [{id:$i, level:$lv, label:$lb, detail:$d, label_en:$le, detail_en:$de, label_es:$ls, detail_es:$ds}
          + (if $a == "" then {} else {action:$a} end)]' <<<"$CHECKS")"
}

# conf num subshell-safe: só os campos que precisamos
CONTEST_TYPE=""; CONTEST_START=0; CONTEST_END=0; FREEZE_TIME=""; LANGUAGES=""; LOGIN_START_TIME=""; LOGIN_ENABLED=""
PRINT=""; MANUAL_VERDICT=""; REVIEW_JUDGES=""; PROBS=(); CONTEST_JUDGES=""; DEMO=""
load_contest_conf "$contest"
mode="$(contest_score_mode "$contest")"
# MÓDULOS (lib/modules.sh): checagem de feature de evento só roda com o módulo LIGADO — contest
# sem o módulo não ganha aviso eterno sobre coisa que não usa. Feature configurada com módulo
# desligado vira UM aviso (`modules`, abaixo), que aponta p/ Central › Módulos.
_mods_off_with_data=""
for _m in "${MODULES[@]}"; do
  mod_on "$contest" "$_m" && continue
  _r="$(mod_detect "$contest" "$_m")" && _mods_off_with_data="${_mods_off_with_data:+$_mods_off_with_data, }$_m ($_r)"
done
if [[ -n "$_mods_off_with_data" ]]; then
  add3 modules warn "Módulo desligado com dados existentes" "$_mods_off_with_data — se a prova usa isso, ligue em Central › Módulos (desligado só esconde os painéis; nada foi apagado)" \
    "Module off with existing data" "$_mods_off_with_data — if the contest uses this, turn it on in Central › Modules (off only hides the panels; nothing was deleted)" \
    "Módulo desactivado con datos existentes" "$_mods_off_with_data — si la competencia lo usa, actívalo en Central › Módulos (desactivado solo oculta los paneles; no se borró nada)"
elif mod_any "$contest"; then
  _mods_on="$(mod_raw "$contest" | tr ',' ' ')"
  add3 modules ok "Módulos ligados" "$_mods_on" "Modules on" "$_mods_on" "Módulos activados" "$_mods_on"
else
  add3 modules ok "Sem módulos de evento" "só o básico (problemas, contas, placar); ligue módulos em Central › Módulos quando precisar" \
    "No event modules" "just the basics (problems, accounts, scoreboard); turn modules on in Central › Modules when needed" \
    "Sin módulos de evento" "solo lo básico (problemas, cuentas, marcador); activa módulos en Central › Módulos cuando los necesites"
fi

# --- demonstração -----------------------------------------------------------
# Contest de demo é indistinguível de uma prova de verdade na tela do admin — e ele aceita
# submissões SINTÉTICAS pelo /contest/admin/seed. Dizer isso na Central é o que impede alguém
# de olhar este placar achando que é gente.
[[ "$DEMO" == 1 ]] && add3 demo warn "Contest de DEMONSTRAÇÃO" \
  "DEMO=1 no conf: aceita submissões sintéticas (/contest/admin/seed) e o placar não é de gente de verdade" \
  "DEMO contest" \
  "DEMO=1 in the conf: accepts synthetic submissions (/contest/admin/seed) and the scoreboard is not made of real people" \
  "Competencia de DEMOSTRACIÓN" \
  "DEMO=1 en el conf: acepta envíos sintéticos (/contest/admin/seed) y el marcador no es de personas reales"

# --- janela -----------------------------------------------------------------
if [[ "$CONTEST_START" =~ ^[0-9]+$ && "$CONTEST_END" =~ ^[0-9]+$ ]] \
   && (( CONTEST_START > 0 && CONTEST_END > CONTEST_START )); then
  _ws="$(fmt_epoch "$CONTEST_START" '%d/%m %H:%M' "$contest")"; _we="$(fmt_epoch "$CONTEST_END" '%d/%m %H:%M' "$contest")"
  _wtz="$(contest_tz "$contest")"
  add3 window ok "Janela da prova" "início $_ws → fim $_we ($_wtz)" \
    "Contest window" "start $_ws → end $_we ($_wtz)" \
    "Ventana de la competencia" "inicio $_ws → fin $_we ($_wtz)"
else
  add3 window fail "Janela da prova" "CONTEST_START/CONTEST_END ausentes ou invertidos no conf" \
    "Contest window" "CONTEST_START/CONTEST_END missing or reversed in the conf" \
    "Ventana de la competencia" "CONTEST_START/CONTEST_END ausentes o invertidos en el conf"
fi

# --- abertura do login × janela da rodada ATIVA (03/10/2026) ----------------------------------
# A abertura do login (LOGIN_START_TIME) NÃO acompanha a troca de rodada. No TCP 2026 ela ficou nas 10:50 — posta
# p/ a prova oficial das 11:00 — com o warmup ativo das 10:15 às 10:40, e a API recusa time antes dela
# (`login_not_open`): o warmup não teria nenhum time. Só olha rodada que ainda não acabou (prova encerrada não
# precisa de aviso); conta de papel nunca é barrada e não entra na conta.
_ls="${LOGIN_START_TIME:-}"; [[ "$_ls" =~ ^[0-9]+$ ]] || _ls=0
if [[ "$CONTEST_START" =~ ^[0-9]+$ && "$CONTEST_END" =~ ^[0-9]+$ ]] \
   && (( CONTEST_START > 0 && CONTEST_END > CONTEST_START && EPOCHSECONDS < CONTEST_END )); then
  _ls_s="$(fmt_epoch "$_ls" '%d/%m %H:%M' "$contest")"
  _st_s="$(fmt_epoch "$CONTEST_START" '%d/%m %H:%M' "$contest")"; _en_s="$(fmt_epoch "$CONTEST_END" '%d/%m %H:%M' "$contest")"
  if [[ "${LOGIN_ENABLED:-}" == n ]]; then
    add3 login_open warn "Login dos times fechado" \
      "\"Login habilitado\" está desligado em Regras: nenhum time entra (quem já entrou continua; contas de organização entram)" \
      "Team login closed" \
      "\"Login enabled\" is off in Rules: no team can log in (teams already in stay; organization accounts can log in)" \
      "Inicio de sesión de los equipos cerrado" \
      "\"Inicio de sesión habilitado\" está desactivado en Reglas: ningún equipo entra (quien ya entró sigue; las cuentas de la organización entran)"
  elif (( _ls == 0 )); then
    add3 login_open ok "Abertura do login" "sem horário próprio: os times entram a partir do início ($_st_s)" \
      "Login opening" "no time of its own: teams can log in from the start ($_st_s)" \
      "Apertura del login" "sin horario propio: los equipos entran desde el inicio ($_st_s)"
  elif (( _ls <= CONTEST_START )); then
    _lm=$(( (CONTEST_START - _ls) / 60 ))
    add3 login_open ok "Abertura do login" "$_ls_s, $_lm min antes do início ($_st_s)" \
      "Login opening" "$_ls_s, $_lm min before the start ($_st_s)" \
      "Apertura del login" "$_ls_s, $_lm min antes del inicio ($_st_s)"
  elif (( _ls < CONTEST_END )); then
    _lm=$(( (_ls - CONTEST_START + 59) / 60 ))
    add3 login_open warn "Login abre DEPOIS do início" \
      "a abertura do login é $_ls_s, $_lm min depois do início ($_st_s): os times perdem o começo. Trocar de rodada não muda a abertura — ajuste \"Abertura do login\" em Regras" \
      "Login opens AFTER the start" \
      "the login opening is $_ls_s, $_lm min after the start ($_st_s): teams miss the beginning. Changing the round does not change the opening — adjust \"Login opening\" in Rules" \
      "El inicio de sesión abre DESPUÉS del inicio" \
      "la apertura del login es $_ls_s, $_lm min después del inicio ($_st_s): los equipos pierden el comienzo. Cambiar de ronda no cambia la apertura — ajusta \"Apertura del login\" en Reglas"
  else
    add3 login_open fail "Login abre DEPOIS do fim" \
      "a abertura do login é $_ls_s, depois do fim desta rodada ($_en_s): NENHUM time entra. Trocar de rodada não muda a abertura — ajuste \"Abertura do login\" em Regras" \
      "Login opens AFTER the end" \
      "the login opening is $_ls_s, after the end of this round ($_en_s): NO team can log in. Changing the round does not change the opening — adjust \"Login opening\" in Rules" \
      "El inicio de sesión abre DESPUÉS del fin" \
      "la apertura del login es $_ls_s, después del fin de esta ronda ($_en_s): NINGÚN equipo entra. Cambiar de ronda no cambia la apertura — ajusta \"Apertura del login\" en Reglas"
  fi
fi

# --- anti-vazamento (icpc) ----------------------------------------------------
if [[ "$(showlog_effective "$contest")" == 0 ]]; then
  add3 show_log ok "Log de julgamento oculto" "competidor não vê o report.html (não vaza os casos de teste)" \
    "Judging log hidden" "contestants do not see report.html (test cases do not leak)" \
    "Log de evaluación oculto" "el competidor no ve el report.html (no se filtran los casos de prueba)"
else
  lv=warn; [[ "$mode" == icpc ]] && lv=fail
  add3 show_log "$lv" "Log de julgamento VISÍVEL" "o report.html expõe input+diff de TODOS os testes — desligue em Configurações (show_log)" \
    "Judging log VISIBLE" "report.html exposes input+diff of ALL tests — turn it off in Settings (show_log)" \
    "Log de evaluación VISIBLE" "el report.html expone input+diff de TODAS las pruebas — desactívalo en Configuración (show_log)"
fi

# --- freeze -------------------------------------------------------------------
fz="${FREEZE_TIME:-0}"; [[ "$fz" =~ ^[0-9]+$ ]] || fz=0
if (( fz > 0 && fz > CONTEST_START && fz < CONTEST_END )); then
  _fzs="$(fmt_epoch "$fz" '%d/%m %H:%M' "$contest")"
  add3 freeze ok "Freeze configurado" "congela em $_fzs" \
    "Freeze set" "freezes at $_fzs" \
    "Congelamiento (freeze) configurado" "se congela el $_fzs"
elif (( fz > 0 )); then
  add3 freeze warn "Freeze fora da janela" "FREEZE_TIME não está entre o início e o fim" \
    "Freeze outside the window" "FREEZE_TIME is not between the start and the end" \
    "Congelamiento fuera de la ventana" "FREEZE_TIME no está entre el inicio y el fin"
else
  add3 freeze warn "Sem freeze" "prova ICPC costuma congelar o placar (Configurações → Freeze)" \
    "No freeze" "ICPC contests usually freeze the scoreboard (Settings → Freeze)" \
    "Sin congelamiento" "las competencias ICPC suelen congelar el marcador (Configuración → Freeze)"
fi

# --- envios na fila (submit.sh / judged.sh, 01/10/2026) --------------------------------
# A PRIORIDADE decide: lista (lista-publica/lista-privada; ausente = lista-publica) tem teto de N envios esperando o
# juiz por time (SUBMIT_MAX_INFLIGHT, padrão 3); prova/super não tem teto e perde prioridade a partir do 6º pendente.
# O `warn` é p/ quem NUNCA a escolheu numa prova (icpc/obi sem CONTEST_PRIORITY): lista explícita é configuração
# deliberada e fica `ok`. Escolher (inclusive Lista) em Central › Regras tira o aviso.
_cprio="$(conf_value "$contest" CONTEST_PRIORITY)"; _cprio="${_cprio//\\/}"
case "$_cprio" in
  prova|super)
    add3 submit_cap ok "Envios na fila: sem teto (prioridade $_cprio)" \
      "a partir do 6º envio esperando o juiz, o time perde prioridade na fila de julgamento (nunca é recusado)" \
      "Submissions in the queue: no limit (priority $_cprio)" \
      "from the 6th submission waiting for the judge, the team gets a lower priority in the judging queue (it is never refused)" \
      "Envíos en la cola: sin límite (prioridad $_cprio)" \
      "a partir del 6.º envío esperando al juez, el equipo pierde prioridad en la cola de evaluación (nunca se rechaza)" ;;
  *)
    _cmax="$(conf_value "$contest" SUBMIT_MAX_INFLIGHT)"; _cmax="${_cmax//[^0-9]/}"; _cmax="${_cmax:-${SUBMIT_MAX_INFLIGHT:-3}}"
    _cp="${_cprio:-lista-publica}"
    if (( _cmax == 0 )); then
      add3 submit_cap ok "Envios na fila: sem teto" "SUBMIT_MAX_INFLIGHT=0 no conf" \
        "Submissions in the queue: no limit" "SUBMIT_MAX_INFLIGHT=0 in the conf" \
        "Envíos en la cola: sin límite" "SUBMIT_MAX_INFLIGHT=0 en el conf"
    elif [[ -z "$_cprio" && ( "$mode" == icpc || "$mode" == obi ) ]]; then
      add3 submit_cap warn "Teto de $_cmax envios na fila por time" \
        "a prioridade não foi definida e vale a de lista: cada time tem no máximo $_cmax envios esperando veredicto e o próximo é recusado. Se isto é uma prova, escolha a prioridade Prova em Regras (escolher Lista também tira este aviso)" \
        "Limit of $_cmax submissions in the queue per team" \
        "the priority was not set, so the list priority applies: each team has at most $_cmax submissions waiting for a verdict and the next one is refused. If this is a contest, select the Contest priority in Rules (selecting a List also removes this warning)" \
        "Límite de $_cmax envíos en la cola por equipo" \
        "la prioridad no fue definida y vale la de lista: cada equipo tiene como máximo $_cmax envíos esperando veredicto y el siguiente se rechaza. Si esto es una competencia, elige la prioridad Competencia en Reglas (elegir una Lista también quita este aviso)"
    else
      add3 submit_cap ok "Teto de $_cmax envios na fila por time (prioridade $_cp)" \
        "cada time tem no máximo $_cmax envios esperando veredicto; o próximo é recusado até sair um resultado" \
        "Limit of $_cmax submissions in the queue per team (priority $_cp)" \
        "each team has at most $_cmax submissions waiting for a verdict; the next one is refused until a result comes out" \
        "Límite de $_cmax envíos en la cola por equipo (prioridad $_cp)" \
        "cada equipo tiene como máximo $_cmax envíos esperando veredicto; el siguiente se rechaza hasta que salga un resultado"
    fi ;;
esac

# --- balão × freeze -----------------------------------------------------------
# Só faz sentido com freeze configurado. Nunca `fail`: as duas políticas são legítimas — a
# padrão (retém) protege o placar congelado, e liberar é escolha deliberada do admin.
if (( fz > 0 )) && mod_on "$contest" baloes; then   # módulo baloes
  bdf=0; grep -qE '^[[:space:]]*BALLOONS_DURING_FREEZE=1?\b' "$cdir/conf" 2>/dev/null && bdf=1
  nfz=0
  if [[ -f "$cdir/print-requests/.balloon-frozen" ]]; then
    nfz="$(grep -c '"id"' "$cdir/print-requests/.balloon-frozen" 2>/dev/null)"; nfz="${nfz//[^0-9]/}"; nfz="${nfz:-0}"
  fi
  if (( bdf == 1 )); then
    add3 balloons_freeze warn "Balão ENTREGUE durante o freeze" \
      "permissão ligada: o balão andando pela sala conta o que o placar congelado esconde" \
      "Balloon DELIVERED during the freeze" \
      "permission on: a balloon crossing the room reveals what the frozen scoreboard hides" \
      "Globo ENTREGADO durante el congelamiento" \
      "permiso activado: el globo que cruza la sala revela lo que el marcador congelado oculta"
  else
    _fzh="$(fmt_epoch "$fz" '%H:%M' "$contest")"
    add3 balloons_freeze ok "Balão retido no freeze" \
      "AC a partir de $_fzh não vira tarefa de entrega$( ((nfz>0)) && echo " ($nfz já retido(s))" )" \
      "Balloon held during the freeze" \
      "an AC from $_fzh on does not become a delivery task$( ((nfz>0)) && echo " ($nfz already held)" )" \
      "Globo retenido en el congelamiento" \
      "un AC a partir de las $_fzh no se convierte en tarea de entrega$( ((nfz>0)) && echo " ($nfz ya retenido(s))" )"
  fi
fi

# --- juízes online + linguagens ------------------------------------------------
judges="$( { find "$REGISTRYDIR" -maxdepth 1 -name '*.json' 2>/dev/null | while IFS= read -r jf; do
      jq -c --argjson now "$now" --argjson ttl "$REG_TTL" \
        'select((.last_seen//0) >= ($now-$ttl)) | {host, langs:(.langs//[]), problems:(.problems//{}),
          cpus:(if ((.slot_cpus // 0) >= 1) then ((.total_slots // 1) * .slot_cpus) else 0 end),
          node_cpus:(if ((.slot_cpus // 0) >= 1) then ((((.slots_by_node // {}) | [.[]] | max) // (.total_slots // 1)) * .slot_cpus) else 0 end)}' \
        "$jf" 2>/dev/null
    done; } | jq -cs '.')"
[[ -n "$judges" ]] || judges='[]'
njudges="$(jq -r 'length' <<<"$judges")"
if (( njudges > 0 )); then
  _jhosts="$(jq -r 'map(.host)|join(", ")' <<<"$judges")"
  add3 judges ok "Juízes online" "$njudges juiz(es): $_jhosts" \
    "Judges online" "$njudges judge(s): $_jhosts" \
    "Jueces en línea" "jueces ($njudges): $_jhosts"
else
  add3 judges fail "NENHUM juiz online" "sem juiz, nada é corrigido — verifique moj-agent nas máquinas" \
    "NO judge online" "without a judge nothing gets judged — check moj-agent on the machines" \
    "NINGÚN juez en línea" "sin juez no se evalúa nada — revisa moj-agent en las máquinas"
fi

# --- problemas PARALELOS (CPUNEEDED>1) × largura dos juízes do pool ---------------
# O json servível do banco carrega cpu_needed/same_numa (gen-problem-json.sh; sem abrir pacote).
# Um problema que pede k CPUs por teste só é julgado por juiz NOVO (manda slot_cpus) com
# total_slots×slot_cpus ≥ k (com SAMENUMA, o maior nó); sem um, o job espera e vira Judge Error.
declare -F cs_bank_json >/dev/null 2>&1 || source "$_DIR/lib/contest-statement.sh" 2>/dev/null
par_probs=""; par_bad=""
pjm0='{}'; [[ -f "$cdir/problem-judges.json" ]] && pjm0="$(jq -c . "$cdir/problem-judges.json" 2>/dev/null)"; jq -e . >/dev/null 2>&1 <<<"$pjm0" || pjm0='{}'
for ((i=0; i+4<${#PROBS[@]}; i+=5)); do
  pid="${PROBS[i+4]}"; bj="$(cs_bank_json "$pid" 2>/dev/null)" || continue
  IFS=$'\x01' read -r pk pn < <(jq -j '[((.cpu_needed // 1)|tostring), ((.same_numa // false)|tostring)] | join("\u0001")' "$bj" 2>/dev/null)
  [[ "$pk" =~ ^[0-9]+$ && "$pk" -gt 1 ]] || continue
  par_probs+=" ${PROBS[i+3]}"
  # pool efetivo do problema: override → CONTEST_JUDGES → todos os online
  pool="$(jq -r --arg p "$pid" '([$p, ($p|gsub("#";"/")), ($p|gsub("/";"#"))] | unique) as $vs | ([ $vs[] | .[$vs[]] ] | .[0]) // [] | join(" ")' <<<"$pjm0" 2>/dev/null)"
  [[ -n "$pool" ]] || pool="${CONTEST_JUDGES:-}"
  fit="$(jq -r --arg pool "$pool" --argjson k "$pk" --arg nm "$pn" '
      [ .[] | select(($pool == "") or (($pool | split(" ")) | index(.host)))
            | select((if $nm == "true" then .node_cpus else .cpus end) >= $k) ] | length' <<<"$judges" 2>/dev/null)"
  [[ "$fit" =~ ^[0-9]+$ && "$fit" -gt 0 ]] || par_bad+=" ${PROBS[i+3]}(${pk} CPUs$([[ "$pn" == true ]] && printf ', NUMA'))"
done
if [[ -n "$par_bad" ]]; then
  add3 judges_cpus warn "Problema paralelo sem juiz com as CPUs" \
    "nenhum juiz online do pool serve:$par_bad — o julgamento espera e vira Judge Error (CPUNEEDED do conf; juiz antigo sem slot_cpus não conta)" \
    "Parallel problem without a judge with enough CPUs" \
    "no online judge in the pool fits:$par_bad — judging waits and becomes Judge Error (CPUNEEDED in the conf; an old judge without slot_cpus does not count)" \
    "Problema paralelo sin juez con las CPUs" \
    "ningún juez en línea del pool sirve:$par_bad — la evaluación espera y se vuelve Judge Error (CPUNEEDED del conf; un juez antiguo sin slot_cpus no cuenta)"
elif [[ -n "$par_probs" ]]; then
  add3 judges_cpus ok "Problemas paralelos com juiz" "CPUNEEDED>1 em:$par_probs — há juiz online com as CPUs" \
    "Parallel problems have a judge" "CPUNEEDED>1 in:$par_probs — there is an online judge with enough CPUs" \
    "Problemas paralelos con juez" "CPUNEEDED>1 en:$par_probs — hay un juez en línea con las CPUs"
fi

# --- pool de juízes (contest + overrides por problema) ----------------------------
# ESTRITO: job de contest/problema com pool só sai p/ host do pool — pool offline = fila presa.
pjm='{}'; [[ -f "$cdir/problem-judges.json" ]] && pjm="$(jq -c . "$cdir/problem-judges.json" 2>/dev/null)"
jq -e . >/dev/null 2>&1 <<<"$pjm" || pjm='{}'
pool_all="$(jq -r --arg c "${CONTEST_JUDGES:-}" \
  '([$c|split(" ")[]|select(length>0)] + [.[]?[]?]) | unique | join(" ")' <<<"$pjm" 2>/dev/null)"
if [[ -z "$pool_all" ]]; then
  add3 pool ok "Sem pool de juízes fixo" "qualquer juiz online pode julgar (Configurações → Máquinas de juiz)" \
    "No fixed judge pool" "any online judge may judge (Settings → Judge machines)" \
    "Sin pool fijo de jueces" "cualquier juez en línea puede evaluar (Configuración → Máquinas de juez)"
else
  offline=""
  for h in $pool_all; do
    jq -e --arg h "$h" 'any(.[]; .host == $h)' >/dev/null 2>&1 <<<"$judges" || offline+=" $h"
  done
  c_live=1
  if [[ -n "${CONTEST_JUDGES:-}" ]]; then
    c_live=0
    for h in $CONTEST_JUDGES; do
      jq -e --arg h "$h" 'any(.[]; .host == $h)' >/dev/null 2>&1 <<<"$judges" && { c_live=1; break; }
    done
  fi
  if (( c_live == 0 )); then
    add3 pool fail "Pool de juízes OFFLINE" "nenhum host do pool ($CONTEST_JUDGES) está online — submissões ficarão NA FILA até um voltar" \
      "Judge pool OFFLINE" "no host of the pool ($CONTEST_JUDGES) is online — submissions will stay IN THE QUEUE until one comes back" \
      "Pool de jueces FUERA DE LÍNEA" "ningún host del pool ($CONTEST_JUDGES) está en línea — los envíos quedarán EN LA COLA hasta que vuelva uno"
  elif [[ -n "$offline" ]]; then
    add3 pool warn "Pool com juízes offline/não registrados" "sem heartbeat:$offline (typo no nome? agente parado?)" \
      "Pool with offline/unregistered judges" "no heartbeat:$offline (typo in the name? agent stopped?)" \
      "Pool con jueces fuera de línea/no registrados" "sin heartbeat:$offline (¿error en el nombre? ¿agente detenido?)"
  else
    add3 pool ok "Pool de juízes online" "correção fixada em: $pool_all" \
      "Judge pool online" "judging pinned to: $pool_all" \
      "Pool de jueces en línea" "evaluación fijada en: $pool_all"
  fi
fi

# com pool de contest, a cobertura de linguagem conta SÓ os juízes do pool (são eles que julgam)
# (bind de .host ANTES do filtro: arg de função jq avalia contra o INPUT dela — $p aqui)
judges_eff="$judges"
[[ -n "${CONTEST_JUDGES:-}" ]] && judges_eff="$(jq -c --arg p " $CONTEST_JUDGES " \
  'map(select(.host as $h | ($p | contains(" "+$h+" "))))' <<<"$judges")"

langs_lc="$(printf '%s' "${LANGUAGES:-}" | tr '[:upper:]' '[:lower:]')"
if [[ -n "$langs_lc" ]]; then
  missing=""
  # confs antigos podem ter py3/py2 na whitelist; os juízes anunciam 'py' (python unificado)
  langs_lc="$(for _l in $langs_lc; do lang_canon_ext "$_l"; echo; done | sort -u | paste -sd' ' -)"
  for l in $langs_lc; do
    jq -e --arg l "$l" 'any(.[]; .langs | index($l))' >/dev/null 2>&1 <<<"$judges_eff" || missing+=" $l"
  done
  _ip_pt=""; _ip_en=""; _ip_es=""
  [[ -n "${CONTEST_JUDGES:-}" ]] && { _ip_pt=' no pool'; _ip_en=' in the pool'; _ip_es=' en el pool'; }
  if [[ -z "$missing" ]]; then
    add3 langs ok "Toolchain das linguagens" "todas as permitidas ($langs_lc) têm juiz online$_ip_pt" \
      "Language toolchains" "every allowed one ($langs_lc) has an online judge$_ip_en" \
      "Toolchain de los lenguajes" "todos los permitidos ($langs_lc) tienen juez en línea$_ip_es"
  else
    add3 langs fail "Linguagem sem juiz" "sem toolchain online$_ip_pt p/:$missing" \
      "Language without a judge" "no online toolchain$_ip_en for:$missing" \
      "Lenguaje sin juez" "sin toolchain en línea$_ip_es para:$missing"
  fi
else
  add3 langs warn "Linguagens sem whitelist" "todas as linguagens do MOJ ficam liberadas (Configurações → Linguagens)" \
    "Languages without a whitelist" "every MOJ language is allowed (Settings → Languages)" \
    "Lenguajes sin whitelist" "todos los lenguajes del MOJ quedan habilitados (Configuración → Lenguajes)"
fi

# --- problemas: TL calibrado (do pool EFETIVO, se houver) ------------------------------
# O "está no cache de algum juiz" que morava aqui saiu: lia o inventário do registro, que o agente só
# refaz ao re-registrar, e bastava UM juiz ter o problema. Quem responde "este juiz vai calibrar na 1ª
# submissão?" é o item judges_warm, logo abaixo, juiz por juiz.
noTL=""; noPool=""; nprob=0
for ((i=0; i+4<${#PROBS[@]}; i+=5)); do
  id="${PROBS[i+4]}"; (( nprob++ ))
  # pool efetivo do problema: override (problem-judges.json) -> pool do contest -> todos
  ppool="$(jq -r --arg id "$id" '(.[$id] // []) | join(" ")' <<<"$pjm" 2>/dev/null)"
  [[ -n "$ppool" ]] || ppool="${CONTEST_JUDGES:-}"
  if [[ -n "$ppool" ]]; then
    live=0
    for h in $ppool; do
      jq -e --arg h "$h" 'any(.[]; .host == $h)' >/dev/null 2>&1 <<<"$judges" && { live=1; break; }
    done
    (( live == 0 )) && noPool+=" $id"
    # calibrado = algum host DO POOL reportou TL p/ o problema
    jq -e --arg p "$ppool" '(.hosts // {}) | keys | any(. as $h | ($p|split(" ")|index($h)))' \
      "$(tl_store_file "$id")" >/dev/null 2>&1 || { noTL+=" $id"; continue; }
  else
    if [[ ! -s "$(tl_store_file "$id")" ]]; then noTL+=" $id"; continue; fi
  fi
done
if (( nprob == 0 )); then
  add3 problems fail "Sem problemas" "o contest não tem problemas no conf" \
    "No problems" "the contest has no problems in the conf" \
    "Sin problemas" "la competencia no tiene problemas en el conf"
elif [[ -n "$noTL" ]]; then
  _pp_pt=""; _pp_en=""; _pp_es=""
  [[ -n "$pool_all" ]] && { _pp_pt=' no pool'; _pp_en=' in the pool'; _pp_es=' en el pool'; }
  add3 problems fail "Problema sem TL calibrado$_pp_pt" "sem calibração:$noTL — dispare /ops/updateproblemset e aguarde os juízes" \
    "Problem without a calibrated TL$_pp_en" "not calibrated:$noTL — trigger /ops/updateproblemset and wait for the judges" \
    "Problema sin TL calibrado$_pp_es" "sin calibración:$noTL — ejecuta /ops/updateproblemset y espera a los jueces"
else
  add3 problems ok "Problemas calibrados" "$nprob problema(s) com TL reportado" \
    "Problems calibrated" "$nprob problem(s) with a reported TL" \
    "Problemas calibrados" "$nprob problema(s) con TL reportado"
fi
[[ -n "$noPool" ]] && add3 pool_problems fail "Problema com pool de juízes offline" "nenhum juiz do pool destes problemas está online (fila presa):$noPool" \
  "Problem with an offline judge pool" "no judge in the pool of these problems is online (queue stuck):$noPool" \
  "Problema con pool de jueces fuera de línea" "ningún juez del pool de estos problemas está en línea (cola trabada):$noPool"

# --- juízes aquecidos: CADA juiz online do pool já calibrou CADA problema? (lib/judge-warm.sh) -------
# O TL é por máquina: juiz frio baixa e calibra na 1ª submissão, e ela espera — 7,3 min na XIV Maratona
# UnB (25/09/2026). O botão da Central (action warm_judges) manda a calibração dirigida só aos pares frios.
if (( njudges > 0 && nprob > 0 )); then
  wm="$(jw_matrix "$contest")"
  if [[ -n "$wm" ]] && jq -e '.counts' >/dev/null 2>&1 <<<"$wm"; then
    { read -r w_warm; read -r w_ing; read -r w_cold; read -r w_nh; } \
      < <(jq -r '.counts.warm, .counts.warming, .counts.cold, (.online | length)' <<<"$wm")
    g_cold="$(jw_group "$wm" cold)"; g_ing="$(jw_group "$wm" warming)"
    if (( w_warm + w_ing + w_cold == 0 )); then :   # nenhum juiz do pool online: é o item pool/pool_problems
    elif (( w_cold > 0 )); then
      add3 judges_warm warn "Juízes FRIOS para problemas da prova" \
        "$w_cold par(es) juiz×problema sem calibração da versão atual — $g_cold. A 1ª submissão de cada par espera o juiz baixar e calibrar o problema inteiro (minutos). Aqueça antes do início: cada calibração ocupa um slot do juiz.$([[ -n "$g_ing" ]] && echo " Aquecendo: $g_ing.")" \
        "Judges not warmed up for contest problems" \
        "$w_cold judge×problem pair(s) not calibrated for the current version — $g_cold. The first submission of each pair waits while the judge downloads and calibrates the whole problem (minutes). Warm them up before the start: each calibration takes one judge slot.$([[ -n "$g_ing" ]] && echo " Warming up: $g_ing.")" \
        "Jueces FRÍOS para problemas de la competencia" \
        "$w_cold par(es) juez×problema sin calibración de la versión actual — $g_cold. El primer envío de cada par espera a que el juez descargue y calibre el problema completo (minutos). Caliéntalos antes del inicio: cada calibración ocupa un slot del juez.$([[ -n "$g_ing" ]] && echo " Calentando: $g_ing.")" \
        warm_judges
    elif (( w_ing > 0 )); then
      add3 judges_warm warn "Juízes aquecendo" "$w_ing calibração(ões) na fila ou em andamento — $g_ing. Rode de novo daqui a alguns minutos." \
        "Judges warming up" "$w_ing calibration(s) queued or running — $g_ing. Check again in a few minutes." \
        "Jueces calentando" "$w_ing calibración(es) en cola o en curso — $g_ing. Vuelve a revisar en unos minutos."
    else
      add3 judges_warm ok "Juízes aquecidos" "todo juiz online que pode julgar cada problema já o calibrou na versão atual ($w_warm par(es) juiz×problema, $w_nh juiz(es) online)" \
        "Judges warmed up" "every online judge that may judge each problem has already calibrated it for the current version ($w_warm judge×problem pair(s), $w_nh online judge(s))" \
        "Jueces calentados" "todo juez en línea que puede evaluar cada problema ya lo calibró en la versión actual ($w_warm par(es) juez×problema, jueces en línea: $w_nh)"
    fi
  fi
fi

# --- staff de impressão -----------------------------------------------------------
staff_n="$(find "$cdir/users" -maxdepth 1 -type d -name '*.staff' 2>/dev/null | wc -l | tr -d '[:space:]')"
if [[ "${PRINT:-}" == 0 ]]; then
  add3 print ok "Impressão desligada" "sem balcão de impressão nesta prova" \
    "Printing off" "no print desk in this contest" \
    "Impresión desactivada" "sin mostrador de impresión en esta competencia"
elif (( staff_n > 0 )); then
  add3 print ok "Impressão + staff" "$staff_n conta(s) .staff p/ operar impressão/balões" \
    "Printing + staff" "$staff_n .staff account(s) to run printing/balloons" \
    "Impresión + staff" "$staff_n cuenta(s) .staff para operar impresión/globos"
else
  add3 print warn "Impressão sem staff" "PRINT ligado mas nenhuma conta .staff existe — balões/impressões ficarão sem operador" \
    "Printing without staff" "PRINT is on but no .staff account exists — balloons/prints will have no operator" \
    "Impresión sin staff" "PRINT activado pero no existe ninguna cuenta .staff — globos/impresiones quedarán sin operador"
fi

# --- escopo do staff/chefe de sede -------------------------------------------------
# Sem staff-filters.json (ou com lista vazia), staff_can_see devolve TRUE p/ todo mundo: cada
# chefe de sede imprime as ETIQUETAS COM SENHA de TODOS os times, não só da sede dele.
if mod_on "$contest" sedes; then   # escopo por sede é do módulo sedes
sfj="$cdir/print-requests/staff-filters.json"
cstaff_n="$(find "$cdir/users" -maxdepth 1 -type d -name '*.cstaff' 2>/dev/null | wc -l | tr -d '[:space:]')"
cstaff_n="${cstaff_n//[^0-9]/}"; cstaff_n="${cstaff_n:-0}"
if (( cstaff_n + staff_n <= 1 )); then
  add3 staff_filters ok "Escopo do staff" "$(( cstaff_n + staff_n )) conta(s) de staff — sem sede p/ separar" \
    "Staff scope" "$(( cstaff_n + staff_n )) staff account(s) — no site to separate" \
    "Alcance del staff" "$(( cstaff_n + staff_n )) cuenta(s) de staff — sin sede que separar"
else
  scoped=0
  if [[ -s "$sfj" ]]; then
    while IFS= read -r sl; do
      [[ -n "$sl" ]] || continue
      [[ -d "$cdir/users/$sl" ]] && (( scoped++ ))
    done < <(jq -r 'to_entries[] | select((.value // []) | length > 0) | .key' "$sfj" 2>/dev/null)
  fi
  if (( scoped >= cstaff_n + staff_n )); then
    add3 staff_filters ok "Escopo do staff por sede" "$scoped conta(s) de staff com escopo definido" \
      "Staff scope per site" "$scoped staff account(s) with a defined scope" \
      "Alcance del staff por sede" "$scoped cuenta(s) de staff con alcance definido"
  else
    add3 staff_filters warn "Staff sem escopo de sede" "$(( cstaff_n + staff_n - scoped )) de $(( cstaff_n + staff_n )) conta(s) .staff/.cstaff sem filtro: veem a fila e as ETIQUETAS COM SENHA de todos os times (Operação → Staff)" \
      "Staff without a site scope" "$(( cstaff_n + staff_n - scoped )) of $(( cstaff_n + staff_n )) .staff/.cstaff account(s) without a filter: they see the queue and the LABELS WITH PASSWORDS of every team (Operations → Staff)" \
      "Staff sin alcance de sede" "$(( cstaff_n + staff_n - scoped )) de $(( cstaff_n + staff_n )) cuenta(s) .staff/.cstaff sin filtro: ven la cola y las ETIQUETAS CON CONTRASEÑA de todos los equipos (Operación → Staff)"
  fi
fi
fi   # módulo sedes

# --- balões: cor por letra -----------------------------------------------------------
# Sem balloons.json a cor é o default ICPC A–O (pr_balloon_color); da letra P em diante todo
# balão sai CINZA — em prova com mais de 15 problemas isso é um problema de verdade no balcão.
if ! mod_on "$contest" baloes; then :   # módulo baloes desligado
elif [[ -s "$cdir/balloons.json" ]]; then
  nbc="$(jq -r 'length' "$cdir/balloons.json" 2>/dev/null)"; nbc="${nbc//[^0-9]/}"
  add3 balloons ok "Cores dos balões" "${nbc:-0} letra(s) com cor definida" \
    "Balloon colors" "${nbc:-0} letter(s) with a defined color" \
    "Colores de los globos" "${nbc:-0} letra(s) con color definido"
elif (( nprob > 15 )); then
  add3 balloons warn "Balões sem cor a partir da letra P" "$nprob problemas e o default cobre A–O: da letra P em diante o balão sai CINZA (Prova → Balões)" \
    "Balloons without a color from letter P on" "$nprob problems and the default covers A–O: from letter P on the balloon comes out GRAY (Contest → Balloons)" \
    "Globos sin color a partir de la letra P" "$nprob problemas y el default cubre A–O: de la letra P en adelante el globo sale GRIS (Competencia → Globos)"
else
  add3 balloons ok "Cores dos balões (default ICPC)" "A–O no padrão da maratona; defina em Prova → Balões p/ mudar" \
    "Balloon colors (ICPC default)" "A–O in the ICPC standard; set them in Contest → Balloons to change" \
    "Colores de los globos (default ICPC)" "A–O en el estándar ICPC; defínelos en Competencia → Globos para cambiarlos"
fi

# --- contas ------------------------------------------------------------------------
# (o `cstaff` PRECISA estar na lista: sem ele o chefe de sede era contado como competidor)
users_n="$(find "$cdir/users" -maxdepth 2 -name account.json 2>/dev/null \
  | grep -vcE '\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)/account\.json$')"
users_n="${users_n//[^0-9]/}"; users_n="${users_n:-0}"
src_users="$(_users_source "$contest")"
if [[ "$src_users" != "$contest" ]]; then
  # COMPARTILHADO (USERS_FROM): as contas moram no treino — "nenhum competidor" seria falso. O aviso é
  # o que ninguém adivinha: a senha é a do treino e desfazer é converter (Pessoas › Contas, sem volta).
  if declare -F mod_on >/dev/null && mod_on "$contest" inscricoes && [[ -s "$cdir/registrations.json" ]]; then
    who_pt="só os inscritos entram"; who_en="only registered people get in"; who_es="solo entran los inscritos"
  else
    who_pt="qualquer conta de lá entra"; who_en="any account from there gets in"; who_es="cualquier cuenta de allí entra"
  fi
  add3 shared_users warn "Contas compartilhadas com \"$src_users\"" \
    "login e senha são os de \"$src_users\" ($who_pt); para uma prova, converta em contas próprias em Pessoas › Contas — senhas novas, sem volta" \
    "Accounts shared with \"$src_users\"" \
    "login and password are the \"$src_users\" ones ($who_en); for an exam, convert them into own accounts in People › Accounts — new passwords, no way back" \
    "Cuentas compartidas con \"$src_users\"" \
    "el usuario y la contraseña son los de \"$src_users\" ($who_es); para un examen, conviértelas en cuentas propias en Personas › Cuentas — contraseñas nuevas, sin vuelta atrás"
elif (( users_n > 0 )); then
  add3 users ok "Contas de competidores" "$users_n conta(s)" \
    "Contestant accounts" "$users_n account(s)" \
    "Cuentas de competidores" "$users_n cuenta(s)"
else
  add3 users warn "Nenhum competidor" "crie as contas (Usuários & sessões → carga em lote)" \
    "No contestants" "create the accounts (Users & sessions → bulk load)" \
    "Ningún competidor" "crea las cuentas (Usuarios y sesiones → carga masiva)"
fi

# --- spool travado (daemon) ----------------------------------------------------------
oldest=0
while IFS= read -r f; do
  m="$(stat -c %Y "$f" 2>/dev/null)"; [[ "$m" =~ ^[0-9]+$ ]] || continue
  (( oldest == 0 || m < oldest )) && oldest=$m
done < <(find "$SPOOLDIR" -type f 2>/dev/null | head -50)
if (( oldest > 0 && now - oldest > 120 )); then
  add3 daemon fail "Spool travado" "submissão esperando há $(( (now-oldest)/60 )) min — o daemon moj-judged está rodando?" \
    "Spool stuck" "a submission has been waiting for $(( (now-oldest)/60 )) min — is the moj-judged daemon running?" \
    "Spool trabado" "un envío lleva $(( (now-oldest)/60 )) min esperando — ¿el daemon moj-judged está corriendo?"
else
  add3 daemon ok "Fila de julgamento" "spool sendo consumido" \
    "Judging queue" "spool being consumed" \
    "Cola de evaluación" "el spool se está consumiendo"
fi

# --- informativos ---------------------------------------------------------------------
# `mode` só cobra icpc quando o contest tem cara de evento (algum módulo ligado): lista de
# treino em modo treino não é erro.
if mod_any "$contest"; then
  if [[ "$mode" == icpc ]]; then
    add3 mode ok "Modo do placar" "$mode" "Scoreboard mode" "$mode" "Modo del marcador" "$mode"
  else
    add3 mode warn "Modo do placar" "$mode — prova ICPC usa CONTEST_TYPE=icpc" \
      "Scoreboard mode" "$mode — an ICPC contest uses CONTEST_TYPE=icpc" \
      "Modo del marcador" "$mode — una competencia ICPC usa CONTEST_TYPE=icpc"
  fi
else
  add3 mode ok "Modo do placar" "$mode" "Scoreboard mode" "$mode" "Modo del marcador" "$mode"
fi
# veredicto manual: desde a regra OPT-OUT (lib/review-rules.sh, 25/09/2026) "ligado" com a tabela vazia não
# revisa NADA — tudo sai automático. O item diz quanto vai para revisão e avisa o vazio e o ilegível.
if [[ "${MANUAL_VERDICT:-}" == 1 ]]; then
  source "$_LIBDIR/review-rules.sh"
  _rq="${REVIEW_JUDGES:-2}"; [[ "$_rq" =~ ^[1-5]$ ]] || _rq=2
  _rst="$(rr_state "$contest")"
  if [[ "$_rst" == invalid ]]; then
    add3 manual warn "Regras de revisão ilegíveis" "o auto-verdicts.json não é JSON válido, então TUDO vai para revisão — salve a tabela em Juízes › O que vai para revisão" \
      "Unreadable review rules" "auto-verdicts.json is not valid JSON, so EVERYTHING goes to review — save the table in Judges › What goes to review" \
      "Reglas de revisión ilegibles" "el auto-verdicts.json no es un JSON válido, así que TODO va a revisión — guarda la tabla en Jueces › Qué va a revisión"
  else
    _cids="$(for ((i=0; i+4<${#PROBS[@]}; i+=5)); do c="${PROBS[i+4]}"; [[ "$c" == *"#"* ]] || c="${PROBS[i+1]//\//#}"; printf '%s\n' "$c"; done | jq -R . | jq -cs 'map(select(length > 0))')"
    _rv='{"review":{},"langs":[]}'
    [[ "$_rst" != missing ]] && _rv="$(jq -c --argjson cids "${_cids:-[]}" "$RR_JQ_DEFS rr_view(\$cids)" "$cdir/auto-verdicts.json" 2>/dev/null || echo '{"review":{},"langs":[]}')"
    read -r _rn _rx < <(jq -r '"\([.review[] | length] | add // 0) \([.langs[] | select(.to != "auto")] | length)"' <<<"$_rv")
    if (( ${_rn:-0} + ${_rx:-0} == 0 )); then
      add3 manual warn "Veredicto manual ligado, mas nada vai para revisão" \
        "a tabela \"O que vai para revisão\" está vazia: todo veredicto sai automático (só erro do juiz é revisado). Marque o que os juízes revisam em Juízes › O que vai para revisão ou no painel do juiz-chefe" \
        "Manual verdict is on, but nothing goes to review" \
        "the \"What goes to review\" table is empty: every verdict is automatic (only judge errors are reviewed). Check what the judges review in Judges › What goes to review or in the chief judge panel" \
        "Veredicto manual activado, pero nada va a revisión" \
        "la tabla \"Qué va a revisión\" está vacía: todo veredicto sale automático (solo se revisan los errores del juez). Marca lo que revisan los jueces en Jueces › Qué va a revisión o en el panel del juez principal"
    else
      add3 manual ok "Veredicto manual LIGADO" "${_rn:-0} combinação(ões) problema×veredicto vão para revisão$( (( ${_rx:-0} )) && echo " + ${_rx} exceção(ões) por linguagem"), com $_rq juiz(es) por decisão; o resto sai automático" \
        "Manual verdict ON" "${_rn:-0} problem×verdict combination(s) go to review$( (( ${_rx:-0} )) && echo " + ${_rx} per-language exception(s)"), $_rq judge(s) per decision; the rest is automatic" \
        "Veredicto manual ACTIVADO" "${_rn:-0} combinación(es) problema×veredicto van a revisión$( (( ${_rx:-0} )) && echo " + ${_rx} excepción(es) por lenguaje"), jueces por decisión: $_rq; el resto sale automático"
    fi
  fi
else
  add3 manual ok "Veredicto manual desligado" "veredicto automático direto ao aluno" "Manual verdict off" "automatic verdict straight to the team" \
    "Veredicto manual desactivado" "veredicto automático directo al equipo"
fi
# --- sedes pela regra única (lib/regions.sh): o que o painel de sedes mostra na prévia, em uma linha ------
if mod_on "$contest" sedes && [[ -s "$cdir/regions.json" ]]; then
  source "$_LIBDIR/regions.sh"
  if rgm="$(rg_map "$contest" 2>/dev/null)"; then
    rgs="$(rg_summary "$cdir/var/regions-nodes.json" "$rgm" 2>/dev/null)"
    IFS=$'\t' read -r rg_n rg_none rg_stop rg_orph rg_err rg_nodes < <(jq -r '[.logins, .counts.none, .counts.stopped,
        (.orphans | length), ([.nodes[] | select(.err != null)] | length), ([.nodes[] | select(.orphan | not)] | length)] | map(tostring) | join("\t")' <<<"$rgs")
    rg_errn="$(jq -r '[.nodes[] | select(.err != null) | .name] | .[0:5] | join(", ")' <<<"$rgs")"
    rg_orn="$(jq -r '.orphans[0:5] | join(", ")' <<<"$rgs")"
    if (( ${rg_err:-0} + ${rg_orph:-0} + ${rg_stop:-0} + ${rg_none:-0} > 0 )); then
      d_pt=""; d_en=""; d_es=""
      (( rg_err > 0 ))  && { d_pt+="$rg_err sede(s) com regex recusada ($rg_errn); "; d_en+="$rg_err site(s) with a rejected regex ($rg_errn); "; d_es+="$rg_err sede(s) con regex rechazada ($rg_errn); "; }
      (( rg_orph > 0 )) && { d_pt+="sede gravada fora da árvore: $rg_orn; "; d_en+="site stored outside the tree: $rg_orn; "; d_es+="sede grabada fuera del árbol: $rg_orn; "; }
      (( rg_stop > 0 )) && { d_pt+="$rg_stop time(s) pararam num grupo/país; "; d_en+="$rg_stop team(s) stopped at a group/country; "; d_es+="$rg_stop equipo(s) se quedaron en un grupo/país; "; }
      (( rg_none > 0 )) && { d_pt+="$rg_none de $rg_n time(s) sem sede; "; d_en+="$rg_none of $rg_n team(s) without a site; "; d_es+="$rg_none de $rg_n equipo(s) sin sede; "; }
      add3 regions warn "Sedes a conferir" "${d_pt%; } — Evento › Sedes & escolas mostra quem" \
        "Sites to check" "${d_en%; } — Event › Sites & schools shows who" \
        "Sedes por revisar" "${d_es%; } — Evento › Sedes y escuelas muestra quiénes"
    else
      add3 regions ok "Sedes" "$rg_nodes sede(s)/região(ões); todos os $rg_n times têm sede" \
        "Sites" "$rg_nodes site(s)/region(s); all $rg_n teams have a site" \
        "Sedes" "$rg_nodes sede(s)/región(es); los $rg_n equipos tienen sede"
    fi
  fi
fi

tov="$cdir/time-overrides.json"
ntov=0; [[ -s "$tov" ]] && ntov="$(jq -r 'length' "$tov" 2>/dev/null)"; ntov="${ntov//[^0-9]/}"; ntov="${ntov:-0}"
if ! mod_on "$contest" sedes; then :   # prorrogação por sede é do módulo sedes
elif (( ntov > 0 )); then
  # o freeze vale p/ TODO mundo, inclusive quem tem prorrogação: se o fim prorrogado passa do
  # freeze, aquele grupo joga a última parte com placar congelado (às vezes é o que se quer —
  # mas tem de ser escolha, não surpresa).
  maxend="$(jq -r '[.[]?.end // 0] | max // 0' "$tov" 2>/dev/null)"; maxend="${maxend//[^0-9]/}"; maxend="${maxend:-0}"
  extra=""; extra_en=""; extra_es=""
  if (( fz > 0 && maxend > CONTEST_END )); then
    _mxe="$(fmt_epoch "$maxend" '%d/%m %H:%M' "$contest")"
    extra=" — o fim prorrogado ($_mxe) passa do freeze"
    extra_en=" — the extended end ($_mxe) goes past the freeze"
    extra_es=" — el fin prorrogado ($_mxe) pasa del congelamiento"
  fi
  add3 tov warn "Prorrogação por sede ativa" "$ntov regra(s) em time-overrides.json$extra" \
    "Per-site extension active" "$ntov rule(s) in time-overrides.json$extra_en" \
    "Prórroga por sede activa" "$ntov regla(s) en time-overrides.json$extra_es"
else
  add3 tov ok "Sem prorrogações ativas" "todos seguem o fim normal" \
    "No active extensions" "everyone follows the normal end" \
    "Sin prórrogas activas" "todos siguen el fin normal"
fi

# --- coortes de placar (times convidados) ---------------------------------------------
source "$_LIBDIR/cohorts.sh"
chj="$(ch_get "$contest")"
nch="$(jq -r '(.cohorts // []) | length' <<<"$chj" 2>/dev/null)"; nch="${nch//[^0-9]/}"; nch="${nch:-0}"
if ! mod_on "$contest" coortes; then :   # módulo coortes desligado
elif (( nch == 0 )); then
  add3 cohorts ok "Sem coortes" "um placar só, todos oficiais" \
    "No cohorts" "a single scoreboard, everyone official" \
    "Sin cohortes" "un solo marcador, todos oficiales"
else
  npriv="$(jq -r '[(.cohorts // [])[] | select(.public == false)] | length' <<<"$chj")"; npriv="${npriv//[^0-9]/}"
  if ch_released "$contest"; then
    add3 cohorts warn "Resultados LIBERADOS" "todas as coortes aparecem no placar público — só depois da cerimônia (Pessoas → Coortes)" \
      "Results RELEASED" "every cohort shows on the public scoreboard — only after the ceremony (People → Cohorts)" \
      "Resultados LIBERADOS" "todas las cohortes aparecen en el marcador público — solo después de la ceremonia (Personas → Cohortes)"
  else
    add3 cohorts ok "Coortes configuradas" "$nch coorte(s), ${npriv:-0} privada(s) fora do placar público" \
      "Cohorts set up" "$nch cohort(s), ${npriv:-0} private one(s) off the public scoreboard" \
      "Cohortes configuradas" "$nch cohorte(s), ${npriv:-0} privada(s) fuera del marcador público"
  fi
fi

# --- inscrição (roster + janela) --------------------------------------------------------
# Com registro ligado, quem não está no roster NÃO ENTRA (a API corta no login) — no dia da
# prova isso vira fila no balcão. Aqui o organizador vê quantos entraram, quantos convites
# ficaram pendentes (esses NÃO entram) e se a janela está coerente com o início.
source "$_LIBDIR/registration.sh"
if mod_on "$contest" inscricoes && reg_enabled "$contest"; then
  regj="$(reg_get "$contest")"
  rp="$(jq -r '.entries | length' <<<"$regj")"; rp="${rp//[^0-9]/}"; rp="${rp:-0}"
  rt="$(jq -r '.teams | length' <<<"$regj")"; rt="${rt//[^0-9]/}"; rt="${rt:-0}"
  ri="$(jq -r '[.teams[] | (.invited // []) | length] | add // 0' <<<"$regj")"; ri="${ri//[^0-9]/}"; ri="${ri:-0}"
  rwin="$(reg_window_state "$contest")"
  IFS=$'\t' read -r _rs _rop _rcl _rlt _ranc _rrnd < <(reg_window "$contest")
  # a inscrição fecha no início da PROVA OFICIAL — o aquecimento pode ficar dias no ar
  if [[ "$_rcl" =~ ^[1-9][0-9]*$ ]]; then
    rwhen="$(fmt_epoch "$_rcl" '%d/%m %H:%M' "$contest")"; rwhen_en="closes at $rwhen"; rwhen_es="cierra el $rwhen"
  else
    rwhen='sem prazo'; rwhen_en='no deadline'; rwhen_es='sin plazo'
  fi
  ranchor=""; ranchor_en=""; ranchor_es=""
  if [[ -n "$_rrnd" ]]; then
    ranchor=" (âncora: início da rodada '$_rrnd')"
    ranchor_en=" (anchor: start of round '$_rrnd')"
    ranchor_es=" (ancla: inicio de la ronda '$_rrnd')"
  fi
  if (( rp == 0 )); then
    add3 registration warn "Inscrição ligada, ninguém inscrito" "com o roster ligado SÓ inscrito entra — a inscrição fica em /contests/inscricao/?c=$contest" \
      "Registration on, nobody registered" "with the roster on ONLY registered people get in — registration is at /contests/inscricao/?c=$contest" \
      "Inscripción activada, nadie inscrito" "con el roster activado SOLO entra quien está inscrito — la inscripción está en /contests/inscricao/?c=$contest"
  else
    add3 registration ok "Inscrição ligada" "$rp inscrito(s) · $rt time(s) · janela $rwin, fecha em $rwhen$ranchor" \
      "Registration on" "$rp registered · $rt team(s) · window $rwin, $rwhen_en$ranchor_en" \
      "Inscripción activada" "$rp inscrito(s) · $rt equipo(s) · ventana $rwin, $rwhen_es$ranchor_es"
  fi
  # AQUECIMENTO: a porta fica ABERTA (qualquer conta da fonte entra) até a promoção da prova
  if [[ "$(reg_round_kind "$contest")" == warmup ]]; then
    if [[ -n "$_rrnd" ]]; then
      add3 reg_warmup ok "Aquecimento com porta aberta" "qualquer conta entra até a promoção da rodada '$_rrnd'; na promoção quem não se inscreveu perde a sessão" \
        "Warm-up with an open door" "any account gets in until round '$_rrnd' is promoted; at promotion whoever did not register loses the session" \
        "Calentamiento con puerta abierta" "cualquier cuenta entra hasta la promoción de la ronda '$_rrnd'; en la promoción quien no se inscribió pierde la sesión"
    else
      add3 reg_warmup warn "Aquecimento sem prova planejada" "a inscrição fica SEM PRAZO (a âncora seria o início do aquecimento, já passado): planeje a rodada oficial em Prova → Rodadas" \
        "Warm-up without a planned contest" "registration has NO DEADLINE (the anchor would be the start of the warm-up, already past): plan the official round in Contest → Rounds" \
        "Calentamiento sin competencia planificada" "la inscripción queda SIN PLAZO (el ancla sería el inicio del calentamiento, ya pasado): planifica la ronda oficial en Competencia → Rondas"
    fi
  fi
  if (( ri > 0 )); then
    # o mojinho avisa por DM (na hora do convite e na véspera) — mas só alcança quem tem
    # Telegram VINCULADO. Quem não tem depende de alguém avisar por fora: é o que interessa aqui.
    source "$_LIBDIR/invite-notify.sh"
    rnotg=0
    while IFS= read -r _il; do
      [[ -n "$_il" ]] || continue
      [[ -n "$(inv_chat_of "$contest" "$_il")" ]] || rnotg=$(( rnotg + 1 ))
    done < <(jq -r '[.teams[] | (.invited // [])[]] | unique[]' <<<"$regj" 2>/dev/null)
    rdet="quem não aceitar NÃO entra como membro do time (e talvez nem esteja inscrito)"
    rdet_en="whoever does not accept does NOT join as a team member (and may not even be registered)"
    rdet_es="quien no acepte NO entra como miembro del equipo (y quizás ni siquiera esté inscrito)"
    if ! reg_remind_on "$contest"; then
      rdet="$rdet; o aviso automático do mojinho está DESLIGADO neste contest"
      rdet_en="$rdet_en; the automatic mojinho reminder is OFF in this contest"
      rdet_es="$rdet_es; el aviso automático del mojinho está DESACTIVADO en esta competencia"
    fi
    if (( rnotg > 0 )); then
      rdet="$rdet; $rnotg SEM Telegram vinculado (nenhum lembrete os alcança)"
      rdet_en="$rdet_en; $rnotg WITHOUT a linked Telegram (no reminder reaches them)"
      rdet_es="$rdet_es; $rnotg SIN Telegram vinculado (ningún recordatorio les llega)"
    fi
    add3 reg_invites warn "$ri convite(s) de time pendente(s)" "$rdet" \
      "$ri pending team invitation(s)" "$rdet_en" \
      "$ri invitación(es) de equipo pendiente(s)" "$rdet_es"
  fi
  # contest com contas locais: a inscrição pela web é da conta do TREINO — sem USERS_FROM
  # ninguém consegue se inscrever sozinho, só o admin inscreve à mão
  if [[ "$(reg_source_of "$contest")" == "$contest" ]]; then
    add3 reg_source warn "Inscrição sem fonte compartilhada" "este contest tem contas próprias (sem USERS_FROM): ninguém se inscreve pela web — só o admin, à mão" \
      "Registration without a shared source" "this contest has its own accounts (no USERS_FROM): nobody registers through the web — only the admin, by hand" \
      "Inscripción sin fuente compartida" "esta competencia tiene cuentas propias (sin USERS_FROM): nadie se inscribe por la web — solo el admin, a mano"
  fi
  # coortes: o placar separado depende delas existirem (a semeadura pula quando o contest já
  # tinha coortes configuradas)
  mod_on "$contest" coortes && ! jq -e 'any(.cohorts[]; .id == "times") and any(.cohorts[]; .id == "individual")' <<<"$chj" >/dev/null 2>&1 \
    && add3 reg_cohorts warn "Coortes de inscrição ausentes" "sem as coortes 'individual' e 'times' o placar não separa times de individuais (Pessoas → Coortes)" \
      "Registration cohorts missing" "without the 'individual' and 'times' cohorts the scoreboard does not separate teams from individuals (People → Cohorts)" \
      "Faltan las cohortes de inscripción" "sin las cohortes 'individual' y 'times' el marcador no separa equipos de individuales (Personas → Cohortes)"
fi

# --- gate de navegador por sede ---------------------------------------------------------
if mod_on "$contest" maquinas; then   # gate/trava/sessão única são do módulo maquinas
source "$_LIBDIR/ua-gate.sh"
ugj="$(ug_get "$contest")"
# SEM CONFIGURAÇÃO NENHUMA = gate desligado de fato. O ug_get default é mode:enforce (p/ o
# LOGIN_UA_SUBSTRING legado seguir valendo sem arquivo), mas enforce com ZERO regras deixa
# todo mundo entrar (esperado vazio) — tratar isso como "armado sem regra" era um FAIL falso
# em TODO contest que nunca configurou gate (pego no esquenta 2026-08-04).
ug_has_rules="$(jq -r '((.from_login != null) or ((.by_regex // []) | length > 0)
                        or ((.by_region // {}) | length > 0) or ((.fallback // "") != "")) | tostring' <<<"$ugj")"
[[ -n "$(ug_legacy "$contest")" ]] && ug_has_rules=true
if [[ "$(jq -r '.mode // "off"' <<<"$ugj")" != enforce || "$ug_has_rules" != true ]]; then
  if [[ -n "$(ug_legacy "$contest")" ]]; then
    add3 ua_gate warn "Gate de navegador só no LOGIN_UA_SUBSTRING legado" "configure a regra por sede em Pessoas → Máquinas & gate" \
      "Browser gate only on the legacy LOGIN_UA_SUBSTRING" "set up the per-site rule in People → Machines & gate" \
      "Gate de navegador solo en el LOGIN_UA_SUBSTRING heredado" "configura la regla por sede en Personas → Máquinas y gate"
  else
    add3 ua_gate ok "Gate de navegador desligado" "qualquer navegador entra (confira a sala no aquecimento)" \
      "Browser gate off" "any browser gets in (check the room during the warm-up)" \
      "Gate de navegador desactivado" "cualquier navegador entra (revisa la sala en el calentamiento)"
  fi
else
  # quem está DENTRO do gate e quem ficou sem regra: o time sem esperado entra de qualquer
  # navegador — se isso não foi escolha (lista de isentos), é buraco no gate.
  logins="$(find "$cdir/users" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null \
    | grep -vE '\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$' | jq -R . | jq -cs .)"
  [[ -n "$logins" ]] || logins='[]'
  ugmap="$(ug_expected_map "$contest" "$logins")"
  [[ -n "$ugmap" ]] || ugmap='{}'
  # ISENTO é escolha (a margem do gate); "sem regra" é buraco. Separar os dois é o que faz este
  # item ser útil — senão a lista de isentos viraria aviso p/ sempre.
  cnt="$(jq -c --argjson g "$ugj" '
      [ ($g.exempt // [])[] | tostring | select(length > 0) ] as $ex
      | to_entries
      | { gated:  [ .[] | select((.value // "") != "") ] | length,
          exempt: [ .[] | select((.value // "") == "")
                        | select(.key as $k | ($ex | any(. as $r | (try ($k|test($r;"i")) catch ($k == $r))))) ] | length,
          total:  length }' <<<"$ugmap" 2>/dev/null)"
  [[ -n "$cnt" ]] || cnt='{"gated":0,"exempt":0,"total":0}'
  ng="$(jq -r '.gated' <<<"$cnt")"; ng="${ng//[^0-9]/}"; ng="${ng:-0}"
  nx="$(jq -r '.exempt' <<<"$cnt")"; nx="${nx//[^0-9]/}"; nx="${nx:-0}"
  nt="$(jq -r '.total' <<<"$cnt")"; nt="${nt//[^0-9]/}"; nt="${nt:-0}"
  nu=$(( nt - ng - nx )); (( nu < 0 )) && nu=0
  if (( ng == 0 )); then
    add3 ua_gate fail "Gate armado mas SEM regra que casa" "modo enforce e nenhum time tem UA esperado — ou a regex não casa os logins, ou todos estão isentos" \
      "Gate armed but WITHOUT a matching rule" "enforce mode and no team has an expected UA — either the regex does not match the logins, or everyone is exempt" \
      "Gate armado pero SIN regla que coincida" "modo enforce y ningún equipo tiene UA esperado — o la regex no coincide con los logins, o todos están exentos"
  elif (( nu > 0 )); then
    add3 ua_gate warn "Gate armado com $nu time(s) de fora" "$ng com UA esperado, $nu sem regra (entram de qualquer navegador; isentos declarados: $nx) — confira em Pessoas → Máquinas & gate" \
      "Gate armed with $nu team(s) left out" "$ng with an expected UA, $nu without a rule (they get in from any browser; declared exempt: $nx) — check in People → Machines & gate" \
      "Gate armado con $nu equipo(s) fuera" "$ng con UA esperado, $nu sin regla (entran desde cualquier navegador; exentos declarados: $nx) — revisa en Personas → Máquinas y gate"
  else
    add3 ua_gate ok "Gate de navegador por sede" "$ng time(s) presos à imagem da sede$( (( nx > 0 )) && echo ", $nx isento(s) por escolha")" \
      "Per-site browser gate" "$ng team(s) bound to the site image$( (( nx > 0 )) && echo ", $nx exempt by choice")" \
      "Gate de navegador por sede" "$ng equipo(s) atados a la imagen de la sede$( (( nx > 0 )) && echo ", $nx exento(s) por elección")"
  fi
  # trava de sede por IP (lib/site-lock.sh): com gate, sem trava, `curl --resolve` da máquina
  # de prova ainda chega ao treino/outro contest pelo mesmo IP
  if sl_enabled "$contest"; then
    _nsl="$(sl_list "$contest" | jq -r '[.[] | select(.active)] | length' 2>/dev/null)"; _nsl="${_nsl//[^0-9]/}"; _nsl="${_nsl:-0}"
    add3 site_lock ok "Trava de sede por IP" "ligada: $_nsl IP(s) preso(s) a este contest agora; reivindicações e bloqueios ficam no audit e em Pessoas → Sessões & anomalias" \
      "Per-IP site lock" "on: $_nsl IP(s) bound to this contest right now; claims and blocks go to the audit and to People → Sessions & anomalies" \
      "Bloqueo de sede por IP" "activado: $_nsl IP(s) atado(s) a esta competencia ahora; los reclamos y bloqueos quedan en el audit y en Personas → Sesiones y anomalías"
  else
    add3 site_lock warn "Trava de sede por IP DESLIGADA" "da máquina de prova, curl --resolve chega ao treino e a outros contests pelo mesmo IP do MOJ — ligue em Pessoas → Máquinas & gate (seção 🔒)" \
      "Per-IP site lock OFF" "from a contest machine, curl --resolve reaches the training site and other contests through the same MOJ IP — turn it on in People → Machines & gate (🔒 section)" \
      "Bloqueo de sede por IP DESACTIVADO" "desde la máquina de la competencia, curl --resolve llega al entrenamiento y a otras competencias por la misma IP del MOJ — actívalo en Personas → Máquinas y gate (sección 🔒)"
  fi
  # sessão única por time (lib/session-index.sh): com gate ligado, login em outra máquina
  # derruba a anterior — desligar isso é escolha, mas merece aviso (time em 2 máquinas passa)
  if [[ "$(jq -r '.single_session' <<<"$ugj")" == false ]]; then
    add3 session_single warn "Sessão única por time DESLIGADA" "com o gate ligado, o time pode ficar logado em várias máquinas — ligue em Pessoas → Máquinas & gate; as anomalias aparecem em Pessoas → Sessões & anomalias" \
      "Single session per team OFF" "with the gate on, a team can stay logged in on several machines — turn it on in People → Machines & gate; anomalies show up in People → Sessions & anomalies" \
      "Sesión única por equipo DESACTIVADA" "con el gate activado, el equipo puede quedar conectado en varias máquinas — actívala en Personas → Máquinas y gate; las anomalías aparecen en Personas → Sesiones y anomalías"
  else
    add3 session_single ok "Sessão única por time" "login em outra máquina derruba a sessão anterior; anomalias em Pessoas → Sessões & anomalias" \
      "Single session per team" "logging in on another machine drops the previous session; anomalies in People → Sessions & anomalies" \
      "Sesión única por equipo" "iniciar sesión en otra máquina cierra la sesión anterior; anomalías en Personas → Sesiones y anomalías"
  fi
fi
fi   # módulo maquinas

# --- rodada seguinte (aquecimento → prova) ------------------------------------------------
# Só carrega o motor de rodadas quando HÁ rodada planejada: contest sem rodadas (a maioria) não
# paga nada, e rd_promote_blockers precisa de users.sh + contest-create.sh (cc_probs_json).
if mod_on "$contest" rodadas && [[ -s "$cdir/rounds.json" ]]; then
  nxt="$(jq -r 'first((.rounds // [])[] | select(.state == "pending") | .slug) // ""' "$cdir/rounds.json" 2>/dev/null)"
  if [[ -z "$nxt" ]]; then
    add3 next_round ok "Sem rodada planejada" "a rodada no ar é a última do plano" \
      "No planned round" "the live round is the last one in the plan" \
      "Sin ronda planificada" "la ronda en curso es la última del plan"
  else
    declare -F cc_probs_json >/dev/null || { source "$_LIBDIR/users.sh"; source "$_LIBDIR/contest-create.sh"; }
    source "$_LIBDIR/contest-rounds.sh"
    rblk="$(rd_promote_blockers "$contest")"; [[ -n "$rblk" ]] || rblk='[]'
    nb="$(jq -r 'length' <<<"$rblk" 2>/dev/null)"; nb="${nb//[^0-9]/}"; nb="${nb:-0}"
    if (( nb > 0 )); then
      # os bloqueadores já vêm trilíngues (detail/detail_en/detail_es, lib/contest-rounds.sh)
      _rb_pt="$(jq -r 'map(.detail) | join(" · ")' <<<"$rblk")"
      _rb_en="$(jq -r 'map(.detail_en // .detail) | join(" · ")' <<<"$rblk")"
      _rb_es="$(jq -r 'map(.detail_es // .detail) | join(" · ")' <<<"$rblk")"
      add3 next_round warn "Rodada seguinte: $nxt" "$_rb_pt" \
        "Next round: $nxt" "$_rb_en" \
        "Ronda siguiente: $nxt" "$_rb_es"
    else
      add3 next_round ok "Rodada seguinte: $nxt" "pronta para promover (Prova → Rodadas)" \
        "Next round: $nxt" "ready to promote (Contest → Rounds)" \
        "Ronda siguiente: $nxt" "lista para promover (Competencia → Rondas)"
    fi
  fi
fi

# --- documentos da prova ------------------------------------------------------------------
source "$_LIBDIR/contest-docs.sh"
docs_j="$(doc_index "$contest")"; [[ -n "$docs_j" ]] || docs_j='[]'
ndoc="$(jq -r 'length' <<<"$docs_j")"; ndoc="${ndoc//[^0-9]/}"; ndoc="${ndoc:-0}"
npub="$(jq -r '[.[] | select(.published)] | length' <<<"$docs_j")"; npub="${npub//[^0-9]/}"; npub="${npub:-0}"
if ! mod_on "$contest" documentos; then :   # módulo documentos desligado
elif (( ndoc == 0 )); then
  add3 docs warn "Nenhum documento gerado ou enviado" "ambiente de julgamento, caderno e folha de time limits saem de Evento › Documentos (gere ou envie um PDF pronto)" \
    "No document generated or uploaded" "judging environment, problem booklet and time-limit sheet come from Event › Documents (generate them or upload a ready PDF)" \
    "Ningún documento generado ni subido" "el entorno de evaluación, el cuadernillo y la hoja de time limits salen de Evento › Documentos (genéralos o sube un PDF listo)"
elif (( npub == 0 )); then
  add3 docs warn "Documentos gerados mas não publicados" "$ndoc arquivo(s) só visíveis ao admin/chefe" \
    "Documents generated but not published" "$ndoc file(s) visible only to the admin/chief judge" \
    "Documentos generados pero no publicados" "$ndoc archivo(s) visibles solo para el admin/juez principal"
else
  add3 docs ok "Documentos da prova" "$ndoc gerado(s), $npub publicado(s) p/ a sede" \
    "Contest documents" "$ndoc generated, $npub published to the sites" \
    "Documentos de la competencia" "$ndoc generado(s), $npub publicado(s) para la sede"
fi

# --- esqueletos de código (módulo esqueletos, lib/esqueletos.sh) -------------------------
# fail: módulo ligado com o editor embutido desligado (as portas recusam isso; aqui pega o conf editado à
# mão). warn: modo ICPC (escolha legítima, mas o time da maratona espera o editor vazio) e Java
# personalizado com `public class` (o editor envia solution.java: o javac recusa = CE para todos).
if mod_on "$contest" esqueletos; then
  if ! esq_editor_on "$contest"; then
    add3 esqueletos fail "Esqueletos sem o editor embutido" "o módulo está ligado, mas o editor de código no browser está desligado: o time não vê esqueleto nenhum (ligue o editor nas Regras ou desligue o módulo)" \
      "Skeletons without the built-in editor" "the module is on, but the in-browser code editor is off: teams see no skeleton (turn the editor on in Rules or turn the module off)" \
      "Esqueletos sin el editor integrado" "el módulo está activado, pero el editor de código en el navegador está desactivado: los equipos no ven ningún esqueleto (activa el editor en Reglas o desactiva el módulo)"
  else
    IFS=$'\t' read -r esq_cus esq_off esq_pub < <(esq_langs_json "$contest" | jq -r '[ ([.[] | select(.mode == "custom")] | length),
        ([.[] | select(.mode == "off")] | length),
        ((.java // {}) | if .mode == "custom" and ((.code // "") | test("public\\s+(final\\s+)?class")) then 1 else 0 end) ] | @tsv' 2>/dev/null)
    esq_cus="${esq_cus:-0}"; esq_off="${esq_off:-0}"
    if [[ "${esq_pub:-0}" == 1 ]]; then
      add3 esqueletos warn "Esqueleto Java com public class" "o editor envia o arquivo como solution.java e o javac recusa uma classe pública com outro nome: todo envio Java pelo editor daria Compilation Error (tire o public da classe em Prova › Esqueletos)" \
        "Java skeleton with public class" "the editor sends the file as solution.java, and javac rejects a public class with another name: every Java submission from the editor would get Compilation Error (remove public from the class in Contest › Skeletons)" \
        "Esqueleto Java con public class" "el editor envía el archivo como solution.java y javac rechaza una clase pública con otro nombre: todo envío Java desde el editor daría Compilation Error (quita el public de la clase en Competencia › Esqueletos)"
    elif [[ "$(contest_score_mode "$contest")" == icpc ]]; then
      add3 esqueletos warn "Esqueletos de código em contest ICPC" "o editor do time abre com o esqueleto da linguagem; na maratona o time costuma esperar o editor vazio (enviar o esqueleto intacto é recusado na tela)" \
        "Code skeletons in an ICPC contest" "the team editor opens with the language skeleton; in a programming marathon teams usually expect an empty editor (submitting the untouched skeleton is refused on screen)" \
        "Esqueletos de código en competencia ICPC" "el editor del equipo abre con el esqueleto del lenguaje; en una maratón los equipos suelen esperar el editor vacío (enviar el esqueleto intacto se rechaza en pantalla)"
    else
      add3 esqueletos ok "Esqueletos de código" "padrão do MOJ, $esq_cus personalizado(s), $esq_off sem esqueleto; problema de função abre vazio" \
        "Code skeletons" "MOJ default, $esq_cus custom, $esq_off without skeleton; function problems open empty" \
        "Esqueletos de código" "predeterminado del MOJ, $esq_cus personalizado(s), $esq_off sin esqueleto; los problemas de función abren vacíos"
    fi
  fi
fi

# --- integração nutellaboot (mlinux) -----------------------------------------------------
# Só entra QUANDO CONFIGURADA (contest sem mlinux não ganha aviso eterno). Checa que a
# chave abre a API (curl -m 5 — a Central é do admin e abre pouco).
source "$_LIBDIR/nutella.sh"
if mod_on "$contest" maquinas && nb_configured "$contest"; then
  # `/whoami` responde às DUAS chaves desde 21/09/2026 (a de serviço devolve kind/scopes/images). Chave de
  # serviço: confere os escopos que a integração usa e as imagens do glob. Serviço ANTIGO (401 no whoami de
  # nb3s_): prova acesso lendo as máquinas da 1ª sede, como antes.
  _nbr="$(nb_curl "$contest" GET /whoami)"; _nbs="$(nb_status "$_nbr")"
  if [[ "$_nbs" == 200 ]]; then
    _nbw="$(nb_body "$_nbr")"
    if [[ "$(jq -r '.kind // "admin"' <<<"$_nbw")" == service ]]; then
      _miss="$(jq -r '(["machines:read","commands:write","bindings:write","roster:read","roster:write","webhooks:write"] - (.scopes // [])) | join(" ")' <<<"$_nbw")"
      _nimg="$(jq -r '(.images // []) | length' <<<"$_nbw")"
      if [[ -n "$_miss" ]]; then
        add3 mlinux warn "nutellaboot: chave sem escopo" "faltam: $_miss — peça uma chave com esses escopos (o que falta não funciona: coleta/comando/vínculo/webhook)" \
          "nutellaboot: key missing scopes" "missing: $_miss — ask for a key with these scopes (whatever is missing does not work: collection/command/binding/webhook)" \
          "nutellaboot: clave sin scopes" "faltan: $_miss — pide una clave con esos scopes (lo que falta no funciona: recolección/comando/vínculo/webhook)"
      elif [[ "$_nimg" == 0 ]]; then
        add3 mlinux warn "nutellaboot: chave sem imagem" "o glob da chave não cobre nenhuma site-image" \
          "nutellaboot: key without images" "the key's glob does not cover any site-image" \
          "nutellaboot: clave sin imagen" "el glob de la clave no cubre ninguna site-image"
      else
        _nbname="$(jq -r '.name // ""' <<<"$_nbw")"
        add3 mlinux ok "Integração nutellaboot" "chave de serviço \"$_nbname\" com todos os escopos, $_nimg sede(s) no alcance; panorama/coleta em Máquinas › mlinux" \
          "nutellaboot integration" "service key \"$_nbname\" with every scope, $_nimg site(s) in reach; overview/collection in Machines › mlinux" \
          "Integración nutellaboot" "clave de servicio \"$_nbname\" con todos los scopes, $_nimg sede(s) al alcance; panorama/recolección en Máquinas › mlinux"
      fi
    else
      add3 mlinux ok "Integração nutellaboot" "chave de ADMINISTRAÇÃO válida (mais poder do que a integração precisa: prefira uma nb3s_ por evento); Máquinas › mlinux" \
        "nutellaboot integration" "valid ADMINISTRATION key (more power than the integration needs: prefer one nb3s_ per event); Machines › mlinux" \
        "Integración nutellaboot" "clave de ADMINISTRACIÓN válida (más poder del que la integración necesita: prefiere una nb3s_ por evento); Máquinas › mlinux"
    fi
  elif [[ "$(nb_key_kind "$contest")" == service && "$_nbs" == 401 ]]; then
    _nbi="$(nb_images "$contest" | head -n1)"
    [[ -n "$_nbi" ]] || _nbi="$(jq -r '.sedes[0].id // empty' "$cdir/var/nutella.cache.json" 2>/dev/null)"
    if [[ -z "$_nbi" ]]; then
      add3 mlinux warn "nutellaboot: faltam as site-images" "serviço antigo: chave de serviço não lista as sedes — informe os ids em Máquinas › mlinux" \
        "nutellaboot: site-images missing" "old service: the service key does not list the sites — enter the ids in Machines › mlinux" \
        "nutellaboot: faltan las site-images" "servicio antiguo: la clave de servicio no lista las sedes — indica los ids en Máquinas › mlinux"
    else
      _nbr="$(nb_curl "$contest" GET "/site-images/$_nbi/machines?active_since=$EPOCHSECONDS")"
      _nbs2="$(nb_status "$_nbr")"
      case "$_nbs2" in
        200) add3 mlinux ok "Integração nutellaboot" "chave de serviço válida (lê $_nbi); panorama/coleta em Máquinas › mlinux" \
               "nutellaboot integration" "valid service key (reads $_nbi); overview/collection in Machines › mlinux" \
               "Integración nutellaboot" "clave de servicio válida (lee $_nbi); panorama/recolección en Máquinas › mlinux" ;;
        403) add3 mlinux warn "nutellaboot: chave sem alcance" "a chave de serviço não tem machines:read ou não enxerga a imagem $_nbi (HTTP 403)" \
               "nutellaboot: key without reach" "the service key lacks machines:read or cannot see image $_nbi (HTTP 403)" \
               "nutellaboot: clave sin alcance" "la clave de servicio no tiene machines:read o no ve la imagen $_nbi (HTTP 403)" ;;
        *)   add3 mlinux warn "nutellaboot não responde" "chave inválida ou serviço fora (HTTP $_nbs2) — Máquinas › mlinux" \
               "nutellaboot not responding" "invalid key or service down (HTTP $_nbs2) — Machines › mlinux" \
               "nutellaboot no responde" "clave inválida o servicio caído (HTTP $_nbs2) — Máquinas › mlinux" ;;
      esac
    fi
  else
    _nbcode="$(nb_code "$_nbr")"; _nbcs=""; [[ -n "$_nbcode" ]] && _nbcs=", $_nbcode"
    add3 mlinux warn "nutellaboot não responde" "chave inválida ou serviço fora (HTTP ${_nbs:-000}$_nbcs) — Máquinas › mlinux" \
      "nutellaboot not responding" "invalid key or service down (HTTP ${_nbs:-000}$_nbcs) — Machines › mlinux" \
      "nutellaboot no responde" "clave inválida o servicio caído (HTTP ${_nbs:-000}$_nbcs) — Máquinas › mlinux"
  fi
  # sede com MENOS máquinas do que times (auditoria da Maratona 2026: Trinidad 1 máquina p/ 4
  # times, Tupiza 3 p/ 5 — os times se revezaram numa máquina). Lê o cache da última coleta.
  _nbc="$cdir/var/nutella.cache.json"
  if [[ -s "$_nbc" ]]; then
    # _nb_short <máquinas> <times>: a lista "Sede (N <máquinas> M <times>)" no idioma pedido
    _nb_short(){ jq -r --arg m "$1" --arg t "$2" '[ .sedes[]? | select((.pop.teams // (.teams|length)) > .machines_total)
                       | "\(.name) (\(.machines_total) \($m) \(.pop.teams // (.teams|length)) \($t))" ] | .[0:6] | join(", ")' "$_nbc" 2>/dev/null; }
    _short="$(_nb_short 'máq. p/' times)"
    _nshort="$(jq -r '[ .sedes[]? | select((.pop.teams // (.teams|length)) > .machines_total) ] | length' "$_nbc" 2>/dev/null)"
    _nshort="${_nshort//[^0-9]/}"; _nshort="${_nshort:-0}"
    if (( _nshort > 0 )); then
      _short_en="$(_nb_short 'machine(s) for' teams)"; _short_es="$(_nb_short 'máq. para' equipos)"
      add3 site_short warn "$_nshort sede(s) com menos máquinas que times" "$_short — os times vão se revezar numa máquina; confira com a sede (Operação → mlinux)" \
        "$_nshort site(s) with fewer machines than teams" "$_short_en — teams will take turns on one machine; check with the site (Operations → mlinux)" \
        "$_nshort sede(s) con menos máquinas que equipos" "$_short_es — los equipos se turnarán en una máquina; revisa con la sede (Operación → mlinux)"
    else
      add3 site_short ok "Máquinas por sede" "toda sede tem pelo menos uma máquina mlinux por time (última coleta)" \
        "Machines per site" "every site has at least one mlinux machine per team (last collection)" \
        "Máquinas por sede" "toda sede tiene al menos una máquina mlinux por equipo (última recolección)"
    fi
  fi
fi

# --- telão (Animeitor) -------------------------------------------------------------------
# Só com o módulo telao. Sem rede: a chave (a do MOJ vale por padrão no servidor padrão) e a última
# CONFERÊNCIA gravada (o alimentador confere sozinho; o "validado" é o que a sede vê no reveleitor).
if mod_on "$contest" telao; then
  source "$_LIBDIR/cohorts.sh"; source "$_LIBDIR/animeitor.sh"
  _anu="$(jq -r .url <<<"$(an_cfg "$contest")")"; _ans="$(an_cred_source "$contest" "$_anu")"
  _anv="$(an_verify_summary "$contest")"; _anst="$(jq -r '.state // ""' <<<"$_anv")"
  if [[ "$_ans" == none ]]; then
    if an_moj_cred_available; then
      add3 telao warn "Telão sem chave do Animeitor" \
        "a chave do MOJ só vale no servidor padrão ($AN_DEFAULT_URL) — grave uma chave própria na mesa do telão ou volte ao padrão" \
        "Big screen without an Animeitor key" \
        "the MOJ key only works on the default server ($AN_DEFAULT_URL) — save your own key on the big-screen page or go back to the default" \
        "Pantalla sin clave del Animeitor" \
        "la clave del MOJ solo vale en el servidor predeterminado ($AN_DEFAULT_URL) — guarda una clave propia en la página de la pantalla o vuelve al predeterminado"
    else
      add3 telao warn "Telão sem chave do Animeitor" \
        "grave usuário e token na mesa do telão (/contest/animeitor/)" \
        "Big screen without an Animeitor key" \
        "save user and token on the big-screen page (/contest/animeitor/)" \
        "Pantalla sin clave del Animeitor" \
        "guarda usuario y token en la página de la pantalla (/contest/animeitor/)"
    fi
  elif [[ "$_anst" == no_sites ]]; then
    add3 telao warn "Telão: nenhuma sede do reveleitor casa os times" \
      "a última conferência não achou sede com times — sem sede o Animeitor não gera link de revelação; confira os placares e as sedes na mesa do telão" \
      "Big screen: no reveal site matches the teams" \
      "the last check found no site with teams — without a site the Animeitor makes no reveal link; check the scoreboards and the sites on the big-screen page" \
      "Pantalla: ninguna sede del revelador coincide con los equipos" \
      "la última verificación no encontró sede con equipos — sin sede el Animeitor no genera enlace de revelación; revisa los marcadores y las sedes en la página de la pantalla" \
      open_telao
  elif [[ "$_anst" == diverge || "$_anst" == error ]]; then
    add3 telao warn "Telão: o Animeitor não tem todas as submissões" \
      "na última conferência: $(jq -r '"\(.missing // 0) faltando, \(.wrong // 0) diferentes, \(.extra // 0) a mais\(if .error then " — " + .error else "" end)"' <<<"$_anv") — o alimentador já reenviou; confira de novo na mesa do telão" \
      "Big screen: the Animeitor does not have every submission" \
      "at the last check: $(jq -r '"\(.missing // 0) missing, \(.wrong // 0) different, \(.extra // 0) extra\(if .error then " — " + .error else "" end)"' <<<"$_anv") — the feeder has already resent them; check again on the big-screen page" \
      "Pantalla: el Animeitor no tiene todos los envíos" \
      "en la última verificación: $(jq -r '"\(.missing // 0) faltantes, \(.wrong // 0) diferentes, \(.extra // 0) de más\(if .error then " — " + .error else "" end)"' <<<"$_anv") — el alimentador ya los reenvió; revisa de nuevo en la página de la pantalla"
  elif [[ "$(jq -r '.final == true' <<<"$_anv")" == true ]]; then
    add3 telao ok "Telão validado" "o Animeitor tem todas as submissões e a prova acabou (conferência final)" \
      "Big screen validated" "the Animeitor has every submission and the contest is over (final check)" \
      "Pantalla validada" "el Animeitor tiene todos los envíos y la competencia terminó (verificación final)"
  else
    if [[ "$_ans" == moj ]]; then
      _ank_pt="do MOJ"; _ank_en="the MOJ key"; _ank_es="la clave del MOJ"
    else
      _ank_pt="própria"; _ank_en="its own key"; _ank_es="clave propia"
    fi
    if [[ "$_anst" == ok ]]; then
      _and_pt="a última conferência bateu"; _and_en="the last check matched"; _and_es="la última verificación coincidió"
    else
      _and_pt="publique e ligue o alimentador na mesa do telão; ele confere sozinho durante a prova"
      _and_en="publish and start the feeder on the big-screen page; it checks by itself during the contest"
      _and_es="publica y activa el alimentador en la página de la pantalla; verifica por sí mismo durante la competencia"
    fi
    add3 telao ok "Telão com chave $_ank_pt" "$_and_pt" \
      "Big screen with $_ank_en" "$_and_en" \
      "Pantalla con $_ank_es" "$_and_es"
  fi
  # PLACARES E SEDES do reveleitor (TCP 2026, 03/10/2026: sem a sede "Geral" não há link do RESULTADO GERAL —
  # o organizador tinha de criá-la à mão e esqueceu). Sem rede e sem derivar a proposta (custa ~1 s com 2000
  # times): a configuração gravada (null = a proposta, que hoje sempre traz a Geral) × o que o MOJ PUBLICOU
  # (var/animeitor-managed.json). Placar "geral" = o da visão pública/todos (source view public|all).
  _ansr="$(jq -c --argjson man "$(an_managed "$contest")" '
    def isgen: ((.source.kind // "") == "view" and ((.source.id // "") | IN("public", "all")));
    def iswhole: ((.source.kind // "") == "whole" or (.codes == [".*"]));
    (.contests) as $C
    | (if $C == null then [ {name: "Geral", wn: ["Geral", "Geral (todos)"], cfg_ok: true} ]
       else [ $C[] | select(isgen) | {name, wn: [ (.sites // [])[] | select(iswhole) | .name ], cfg_ok: any((.sites // [])[]; iswhole)} ] end) as $G
    | { missing_cfg: [ $G[] | select(.cfg_ok | not) | .name ],
        missing_pub: (if $man.event == "" then [] else
                        [ $G[] | select(.cfg_ok) | .name as $n | .wn as $w
                          | select($man.contests | has($n)) | select(any($w[]; . as $x | $man.contests[$n].sites | has($x)) | not) | $n ] end),
        empty: (if $C == null then [] else
                  [ $C[] | .name as $cn | (select(.codes == []) | $cn), ((.sites // [])[] | select(.codes == []) | $cn + " › " + .name) ] end),
        published: ($man.event != ""), boards: ($man.contests | length),
        sites: ([ $man.contests[] | (.sites // {}) | length ] | add // 0) }' <<<"$(an_cfg "$contest")" 2>/dev/null)"
  if [[ -n "$_ansr" ]]; then
    _anmc="$(jq -r '.missing_cfg | join(", ")' <<<"$_ansr")"; _anmp="$(jq -r '.missing_pub | join(", ")' <<<"$_ansr")"
    _anem="$(jq -r '.empty | join(", ")' <<<"$_ansr")"
    _anbs="$(jq -r '"\(.boards)\t\(.sites)\t\(.published)"' <<<"$_ansr")"; IFS=$'\t' read -r _anb _ans2 _anpub <<<"$_anbs"
    if [[ -n "$_anmc" ]]; then
      add3 telao_sites warn "Reveleitor sem resultado geral" \
        "o placar $_anmc não tem a sede de TODOS os times — sem ela o reveleitor não tem link do resultado geral; na mesa do telão, use \"+ sede Geral\" no placar (ou volte à proposta automática)" \
        "Reveal tool without the overall result" \
        "the scoreboard $_anmc has no site with ALL the teams — without it the reveal tool has no link for the overall result; on the big-screen page, use \"+ Overall site\" on the scoreboard (or go back to the automatic proposal)" \
        "Revelador sin resultado general" \
        "el marcador $_anmc no tiene la sede de TODOS los equipos — sin ella el revelador no tiene enlace del resultado general; en la página de la pantalla, usa \"+ sede General\" en el marcador (o vuelve a la propuesta automática)" \
        open_telao
    elif [[ -n "$_anmp" ]]; then
      add3 telao_sites warn "Reveleitor publicado sem a sede Geral" \
        "a configuração já tem a sede de todos os times no placar $_anmp, mas o que está no Animeitor foi publicado antes — publique de novo na mesa do telão" \
        "Reveal tool published without the overall site" \
        "the configuration already has the site with all the teams on the scoreboard $_anmp, but the Animeitor has an older publication — publish again on the big-screen page" \
        "Revelador publicado sin la sede General" \
        "la configuración ya tiene la sede con todos los equipos en el marcador $_anmp, pero lo que está en el Animeitor se publicó antes — publica de nuevo en la página de la pantalla" \
        open_telao
    elif [[ -n "$_anem" ]]; then
      add3 telao_sites warn "Reveleitor: placar ou sede sem times" \
        "$_anem não casa time nenhum (regex vazia) — o link revelaria um placar vazio; escreva a regex ou volte ao automático na mesa do telão" \
        "Reveal tool: scoreboard or site without teams" \
        "$_anem matches no team (empty regex) — the link would reveal an empty scoreboard; write the regex or go back to automatic on the big-screen page" \
        "Revelador: marcador o sede sin equipos" \
        "$_anem no coincide con ningún equipo (regex vacía) — el enlace revelaría un marcador vacío; escribe la regex o vuelve al automático en la página de la pantalla" \
        open_telao
    elif [[ "$_anpub" == true ]]; then
      add3 telao_sites ok "Reveleitor com resultado geral" \
        "$_anb placar(es) e $_ans2 sede(s) publicados no Animeitor, com a sede de todos os times no placar geral" \
        "Reveal tool with the overall result" \
        "$_anb scoreboard(s) and $_ans2 site(s) published on the Animeitor, with the site of all the teams on the overall scoreboard" \
        "Revelador con resultado general" \
        "$_anb marcador(es) y $_ans2 sede(s) publicados en el Animeitor, con la sede de todos los equipos en el marcador general"
    else
      add3 telao_sites ok "Reveleitor configurado com resultado geral" \
        "o placar geral tem a sede de todos os times; ainda não publicado — publique na mesa do telão" \
        "Reveal tool configured with the overall result" \
        "the overall scoreboard has the site of all the teams; not published yet — publish on the big-screen page" \
        "Revelador configurado con resultado general" \
        "el marcador general tiene la sede de todos los equipos; aún no publicado — publica en la página de la pantalla"
    fi
  fi
fi

ok_json '{checks:$c, summary:{ok:($c|map(select(.level=="ok"))|length),
                              warn:($c|map(select(.level=="warn"))|length),
                              fail:($c|map(select(.level=="fail"))|length)}}' \
  --argjson c "$CHECKS"
