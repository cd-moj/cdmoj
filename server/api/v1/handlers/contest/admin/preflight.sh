# GET /contest/admin/preflight?contest=<id>   (admin ou juiz-chefe DO contest)
# CHECKLIST PRÉ-PROVA: roda as verificações operacionais que sempre pegam a organização de
# surpresa e devolve verde/amarelo/vermelho por item — janela, SHOWLOG (anti-vazamento de
# testes em icpc), freeze, juízes online, toolchain das linguagens permitidas, TL calibrado
# de cada problema (+ cache nos juízes online), staff de impressão, contas, spool travado.
# -> {checks:[{id,level:ok|warn|fail,label,detail}], summary:{ok,warn,fail}}
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin_or_chief || fail 403 "Apenas o admin ou o juiz-chefe" "admin_required"
source "$_DIR/../../judge-gw/sched-lib.sh"
source "$_DIR/lib/tl-store.sh"
source "$_LIBDIR/contest-gate.sh"

now="$EPOCHSECONDS"
cdir="$CONTESTSDIR/$contest"
CHECKS='[]'
add(){ # add <id> <level> <label> <detail>
  CHECKS="$(jq -c --arg i "$1" --arg lv "$2" --arg lb "$3" --arg d "$4" \
    '. + [{id:$i, level:$lv, label:$lb, detail:$d}]' <<<"$CHECKS")"
}

# conf num subshell-safe: só os campos que precisamos
CONTEST_TYPE=""; CONTEST_START=0; CONTEST_END=0; FREEZE_TIME=""; LANGUAGES=""
SHOWCODE=0; PRINT=""; MANUAL_VERDICT=""; PROBS=(); CONTEST_JUDGES=""
load_contest_conf "$contest"
mode="$(contest_score_mode "$contest")"

# --- janela -----------------------------------------------------------------
if [[ "$CONTEST_START" =~ ^[0-9]+$ && "$CONTEST_END" =~ ^[0-9]+$ ]] \
   && (( CONTEST_START > 0 && CONTEST_END > CONTEST_START )); then
  add window ok "Janela da prova" "início $(fmt_epoch "$CONTEST_START" '%d/%m %H:%M' "$contest") → fim $(fmt_epoch "$CONTEST_END" '%d/%m %H:%M' "$contest") ($(contest_tz "$contest"))"
else
  add window fail "Janela da prova" "CONTEST_START/CONTEST_END ausentes ou invertidos no conf"
fi

# --- anti-vazamento (icpc) ----------------------------------------------------
if [[ "$(showlog_effective "$contest")" == 0 ]]; then
  add show_log ok "Log de julgamento oculto" "competidor não vê o report.html (não vaza os casos de teste)"
else
  lv=warn; [[ "$mode" == icpc ]] && lv=fail
  add show_log "$lv" "Log de julgamento VISÍVEL" "o report.html expõe input+diff de TODOS os testes — desligue em Configurações (show_log)"
fi
if [[ "${SHOWCODE:-0}" == 1 ]]; then
  add show_code warn "Código das submissões PÚBLICO" "show_code ligado: qualquer um vê o fonte dos outros"
else
  add show_code ok "Código das submissões restrito" "só dono/juiz/admin"
fi

# --- freeze -------------------------------------------------------------------
fz="${FREEZE_TIME:-0}"; [[ "$fz" =~ ^[0-9]+$ ]] || fz=0
if (( fz > 0 && fz > CONTEST_START && fz < CONTEST_END )); then
  add freeze ok "Freeze configurado" "congela em $(fmt_epoch "$fz" '%d/%m %H:%M' "$contest")"
elif (( fz > 0 )); then
  add freeze warn "Freeze fora da janela" "FREEZE_TIME não está entre o início e o fim"
else
  add freeze warn "Sem freeze" "prova ICPC costuma congelar o placar (Configurações → Freeze)"
fi

# --- balão × freeze -----------------------------------------------------------
# Só faz sentido com freeze configurado. Nunca `fail`: as duas políticas são legítimas — a
# padrão (retém) protege o placar congelado, e liberar é escolha deliberada do admin.
if (( fz > 0 )); then
  bdf=0; grep -qE '^[[:space:]]*BALLOONS_DURING_FREEZE=1?\b' "$cdir/conf" 2>/dev/null && bdf=1
  nfz=0
  if [[ -f "$cdir/print-requests/.balloon-frozen" ]]; then
    nfz="$(grep -c '"id"' "$cdir/print-requests/.balloon-frozen" 2>/dev/null)"; nfz="${nfz//[^0-9]/}"; nfz="${nfz:-0}"
  fi
  if (( bdf == 1 )); then
    add balloons_freeze warn "Balão ENTREGUE durante o freeze" \
      "permissão ligada: o balão andando pela sala conta o que o placar congelado esconde"
  else
    add balloons_freeze ok "Balão retido no freeze" \
      "AC a partir de $(fmt_epoch "$fz" '%H:%M' "$contest") não vira tarefa de entrega$( ((nfz>0)) && echo " ($nfz já retido(s))" )"
  fi
fi

# --- juízes online + linguagens ------------------------------------------------
judges="$( { find "$REGISTRYDIR" -maxdepth 1 -name '*.json' 2>/dev/null | while IFS= read -r jf; do
      jq -c --argjson now "$now" --argjson ttl "$REG_TTL" \
        'select((.last_seen//0) >= ($now-$ttl)) | {host, langs:(.langs//[]), problems:(.problems//{})}' \
        "$jf" 2>/dev/null
    done; } | jq -cs '.')"
[[ -n "$judges" ]] || judges='[]'
njudges="$(jq -r 'length' <<<"$judges")"
if (( njudges > 0 )); then
  add judges ok "Juízes online" "$njudges juiz(es): $(jq -r 'map(.host)|join(", ")' <<<"$judges")"
else
  add judges fail "NENHUM juiz online" "sem juiz, nada é corrigido — verifique moj-agent nas máquinas"
fi

# --- pool de juízes (contest + overrides por problema) ----------------------------
# ESTRITO: job de contest/problema com pool só sai p/ host do pool — pool offline = fila presa.
pjm='{}'; [[ -f "$cdir/problem-judges.json" ]] && pjm="$(jq -c . "$cdir/problem-judges.json" 2>/dev/null)"
jq -e . >/dev/null 2>&1 <<<"$pjm" || pjm='{}'
pool_all="$(jq -r --arg c "${CONTEST_JUDGES:-}" \
  '([$c|split(" ")[]|select(length>0)] + [.[]?[]?]) | unique | join(" ")' <<<"$pjm" 2>/dev/null)"
if [[ -z "$pool_all" ]]; then
  add pool ok "Sem pool de juízes fixo" "qualquer juiz online pode julgar (Configurações → Máquinas de juiz)"
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
    add pool fail "Pool de juízes OFFLINE" "nenhum host do pool ($CONTEST_JUDGES) está online — submissões ficarão NA FILA até um voltar"
  elif [[ -n "$offline" ]]; then
    add pool warn "Pool com juízes offline/não registrados" "sem heartbeat:$offline (typo no nome? agente parado?)"
  else
    add pool ok "Pool de juízes online" "correção fixada em: $pool_all"
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
  langs_lc="$(printf '%s\n' $langs_lc | sed 's/^py[23]$/py/' | sort -u | paste -sd' ' -)"
  for l in $langs_lc; do
    jq -e --arg l "$l" 'any(.[]; .langs | index($l))' >/dev/null 2>&1 <<<"$judges_eff" || missing+=" $l"
  done
  if [[ -z "$missing" ]]; then
    add langs ok "Toolchain das linguagens" "todas as permitidas ($langs_lc) têm juiz online$([[ -n "${CONTEST_JUDGES:-}" ]] && echo ' no pool')"
  else
    add langs fail "Linguagem sem juiz" "sem toolchain online$([[ -n "${CONTEST_JUDGES:-}" ]] && echo ' no pool') p/:$missing"
  fi
else
  add langs warn "Linguagens sem whitelist" "todas as linguagens do MOJ ficam liberadas (Configurações → Linguagens)"
fi

# --- problemas: TL calibrado + cache nos juízes online (do pool EFETIVO, se houver) ----
noTL=""; noCache=""; noPool=""; nprob=0
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
    jq -e --arg id "$id" --arg p " $ppool " \
      'any(.[]; .host as $h | ($p | contains(" "+$h+" ")) and (.problems | has($id)))' \
      >/dev/null 2>&1 <<<"$judges" || noCache+=" $id"
  else
    if [[ ! -s "$(tl_store_file "$id")" ]]; then noTL+=" $id"; continue; fi
    jq -e --arg id "$id" 'any(.[]; .problems | has($id))' >/dev/null 2>&1 <<<"$judges" || noCache+=" $id"
  fi
done
if (( nprob == 0 )); then
  add problems fail "Sem problemas" "o contest não tem problemas no conf"
elif [[ -n "$noTL" ]]; then
  add problems fail "Problema sem TL calibrado$([[ -n "$pool_all" ]] && echo ' no pool')" "sem calibração:$noTL — dispare /ops/updateproblemset e aguarde os juízes"
elif [[ -n "$noCache" ]]; then
  add problems warn "Problema fora do cache dos juízes online" "será baixado+calibrado na 1ª submissão (lento):$noCache"
else
  add problems ok "Problemas calibrados" "$nprob problema(s) com TL reportado e em cache"
fi
[[ -n "$noPool" ]] && add pool_problems fail "Problema com pool de juízes offline" "nenhum juiz do pool destes problemas está online (fila presa):$noPool"

# --- staff de impressão -----------------------------------------------------------
staff_n="$(find "$cdir/users" -maxdepth 1 -type d -name '*.staff' 2>/dev/null | wc -l | tr -d '[:space:]')"
if [[ "${PRINT:-}" == 0 ]]; then
  add print ok "Impressão desligada" "sem balcão de impressão nesta prova"
elif (( staff_n > 0 )); then
  add print ok "Impressão + staff" "$staff_n conta(s) .staff p/ operar impressão/balões"
else
  add print warn "Impressão sem staff" "PRINT ligado mas nenhuma conta .staff existe — balões/impressões ficarão sem operador"
fi

# --- escopo do staff/chefe de sede -------------------------------------------------
# Sem staff-filters.json (ou com lista vazia), staff_can_see devolve TRUE p/ todo mundo: cada
# chefe de sede imprime as ETIQUETAS COM SENHA de TODOS os times, não só da sede dele.
sfj="$cdir/print-requests/staff-filters.json"
cstaff_n="$(find "$cdir/users" -maxdepth 1 -type d -name '*.cstaff' 2>/dev/null | wc -l | tr -d '[:space:]')"
cstaff_n="${cstaff_n//[^0-9]/}"; cstaff_n="${cstaff_n:-0}"
if (( cstaff_n + staff_n <= 1 )); then
  add staff_filters ok "Escopo do staff" "$(( cstaff_n + staff_n )) conta(s) de staff — sem sede p/ separar"
else
  scoped=0
  if [[ -s "$sfj" ]]; then
    while IFS= read -r sl; do
      [[ -n "$sl" ]] || continue
      [[ -d "$cdir/users/$sl" ]] && (( scoped++ ))
    done < <(jq -r 'to_entries[] | select((.value // []) | length > 0) | .key' "$sfj" 2>/dev/null)
  fi
  if (( scoped >= cstaff_n + staff_n )); then
    add staff_filters ok "Escopo do staff por sede" "$scoped conta(s) de staff com escopo definido"
  else
    add staff_filters warn "Staff sem escopo de sede" "$(( cstaff_n + staff_n - scoped )) de $(( cstaff_n + staff_n )) conta(s) .staff/.cstaff sem filtro: veem a fila e as ETIQUETAS COM SENHA de todos os times (Operação → Staff)"
  fi
fi

# --- balões: cor por letra -----------------------------------------------------------
# Sem balloons.json a cor é o default ICPC A–O (pr_balloon_color); da letra P em diante todo
# balão sai CINZA — em prova com mais de 15 problemas isso é um problema de verdade no balcão.
if [[ -s "$cdir/balloons.json" ]]; then
  nbc="$(jq -r 'length' "$cdir/balloons.json" 2>/dev/null)"; nbc="${nbc//[^0-9]/}"
  add balloons ok "Cores dos balões" "${nbc:-0} letra(s) com cor definida"
elif (( nprob > 15 )); then
  add balloons warn "Balões sem cor a partir da letra P" "$nprob problemas e o default cobre A–O: da letra P em diante o balão sai CINZA (Prova → Balões)"
else
  add balloons ok "Cores dos balões (default ICPC)" "A–O no padrão da maratona; defina em Prova → Balões p/ mudar"
fi

# --- contas ------------------------------------------------------------------------
# (o `cstaff` PRECISA estar na lista: sem ele o chefe de sede era contado como competidor)
users_n="$(find "$cdir/users" -maxdepth 2 -name account.json 2>/dev/null \
  | grep -vcE '\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)/account\.json$')"
users_n="${users_n//[^0-9]/}"; users_n="${users_n:-0}"
if (( users_n > 0 )); then add users ok "Contas de competidores" "$users_n conta(s)"
else add users warn "Nenhum competidor" "crie as contas (Usuários & sessões → carga em lote)"; fi

# --- spool travado (daemon) ----------------------------------------------------------
oldest=0
while IFS= read -r f; do
  m="$(stat -c %Y "$f" 2>/dev/null)"; [[ "$m" =~ ^[0-9]+$ ]] || continue
  (( oldest == 0 || m < oldest )) && oldest=$m
done < <(find "$SPOOLDIR" -maxdepth 1 -type f 2>/dev/null | head -50)
if (( oldest > 0 && now - oldest > 120 )); then
  add daemon fail "Spool travado" "submissão esperando há $(( (now-oldest)/60 )) min — o daemon moj-judged está rodando?"
else
  add daemon ok "Fila de julgamento" "spool sendo consumido"
fi

# --- informativos ---------------------------------------------------------------------
add mode "$([[ "$mode" == icpc ]] && echo ok || echo warn)" "Modo do placar" "$mode$([[ "$mode" != icpc ]] && echo ' — prova ICPC usa CONTEST_TYPE=icpc')"
[[ "${MANUAL_VERDICT:-}" == 1 ]] && add manual ok "Veredicto manual LIGADO" "2 juízes decidem cada submissão" \
                                 || add manual ok "Veredicto manual desligado" "veredicto automático direto ao aluno"
tov="$cdir/time-overrides.json"
ntov=0; [[ -s "$tov" ]] && ntov="$(jq -r 'length' "$tov" 2>/dev/null)"; ntov="${ntov//[^0-9]/}"; ntov="${ntov:-0}"
if (( ntov > 0 )); then
  # o freeze vale p/ TODO mundo, inclusive quem tem prorrogação: se o fim prorrogado passa do
  # freeze, aquele grupo joga a última parte com placar congelado (às vezes é o que se quer —
  # mas tem de ser escolha, não surpresa).
  maxend="$(jq -r '[.[]?.end // 0] | max // 0' "$tov" 2>/dev/null)"; maxend="${maxend//[^0-9]/}"; maxend="${maxend:-0}"
  extra=""
  (( fz > 0 && maxend > CONTEST_END )) && extra=" — o fim prorrogado ($(fmt_epoch "$maxend" '%d/%m %H:%M' "$contest")) passa do freeze"
  add tov warn "Prorrogação por sede ativa" "$ntov regra(s) em time-overrides.json$extra"
else
  add tov ok "Sem prorrogações ativas" "todos seguem o fim normal"
fi

# --- coortes de placar (times convidados) ---------------------------------------------
source "$_LIBDIR/cohorts.sh"
chj="$(ch_get "$contest")"
nch="$(jq -r '(.cohorts // []) | length' <<<"$chj" 2>/dev/null)"; nch="${nch//[^0-9]/}"; nch="${nch:-0}"
if (( nch == 0 )); then
  add cohorts ok "Sem coortes" "um placar só, todos oficiais"
else
  npriv="$(jq -r '[(.cohorts // [])[] | select(.public == false)] | length' <<<"$chj")"; npriv="${npriv//[^0-9]/}"
  if ch_released "$contest"; then
    add cohorts warn "Resultados LIBERADOS" "todas as coortes aparecem no placar público — só depois da cerimônia (Pessoas → Coortes)"
  else
    add cohorts ok "Coortes configuradas" "$nch coorte(s), ${npriv:-0} privada(s) fora do placar público"
  fi
fi

# --- inscrição (roster + janela) --------------------------------------------------------
# Com registro ligado, quem não está no roster NÃO ENTRA (a API corta no login) — no dia da
# prova isso vira fila no balcão. Aqui o organizador vê quantos entraram, quantos convites
# ficaram pendentes (esses NÃO entram) e se a janela está coerente com o início.
source "$_LIBDIR/registration.sh"
if reg_enabled "$contest"; then
  regj="$(reg_get "$contest")"
  rp="$(jq -r '.entries | length' <<<"$regj")"; rp="${rp//[^0-9]/}"; rp="${rp:-0}"
  rt="$(jq -r '.teams | length' <<<"$regj")"; rt="${rt//[^0-9]/}"; rt="${rt:-0}"
  ri="$(jq -r '[.teams[] | (.invited // []) | length] | add // 0' <<<"$regj")"; ri="${ri//[^0-9]/}"; ri="${ri:-0}"
  rwin="$(reg_window_state "$contest")"
  IFS=$'\t' read -r _rs _rop _rcl _rlt _ranc _rrnd < <(reg_window "$contest")
  # a inscrição fecha no início da PROVA OFICIAL — o aquecimento pode ficar dias no ar
  rwhen="$([[ "$_rcl" =~ ^[1-9][0-9]*$ ]] && fmt_epoch "$_rcl" '%d/%m %H:%M' "$contest" || echo 'sem prazo')"
  ranchor="$([[ -n "$_rrnd" ]] && echo " (âncora: início da rodada '$_rrnd')" || echo "")"
  if (( rp == 0 )); then
    add registration warn "Inscrição ligada, ninguém inscrito" "com o roster ligado SÓ inscrito entra — a inscrição fica em /contests/inscricao/?c=$contest"
  else
    add registration ok "Inscrição ligada" "$rp inscrito(s) · $rt time(s) · janela $rwin, fecha em $rwhen$ranchor"
  fi
  # AQUECIMENTO: a porta fica ABERTA (qualquer conta da fonte entra) até a promoção da prova
  if [[ "$(reg_round_kind "$contest")" == warmup ]]; then
    if [[ -n "$_rrnd" ]]; then
      add reg_warmup ok "Aquecimento com porta aberta" "qualquer conta entra até a promoção da rodada '$_rrnd'; na promoção quem não se inscreveu perde a sessão"
    else
      add reg_warmup warn "Aquecimento sem prova planejada" "a inscrição fica SEM PRAZO (a âncora seria o início do aquecimento, já passado): planeje a rodada oficial em Prova → Rodadas"
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
    reg_remind_on "$contest" || rdet="$rdet; o aviso automático do mojinho está DESLIGADO neste contest"
    (( rnotg > 0 )) && rdet="$rdet; $rnotg SEM Telegram vinculado (nenhum lembrete os alcança)"
    add reg_invites warn "$ri convite(s) de time pendente(s)" "$rdet"
  fi
  # contest com contas locais: a inscrição pela web é da conta do TREINO — sem USERS_FROM
  # ninguém consegue se inscrever sozinho, só o admin inscreve à mão
  if [[ "$(reg_source_of "$contest")" == "$contest" ]]; then
    add reg_source warn "Inscrição sem fonte compartilhada" "este contest tem contas próprias (sem USERS_FROM): ninguém se inscreve pela web — só o admin, à mão"
  fi
  # coortes: o placar separado depende delas existirem (a semeadura pula quando o contest já
  # tinha coortes configuradas)
  jq -e 'any(.cohorts[]; .id == "times") and any(.cohorts[]; .id == "individual")' <<<"$chj" >/dev/null 2>&1 \
    || add reg_cohorts warn "Coortes de inscrição ausentes" "sem as coortes 'individual' e 'times' o placar não separa times de individuais (Pessoas → Coortes)"
fi

# --- gate de navegador por sede ---------------------------------------------------------
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
    add ua_gate warn "Gate de navegador só no LOGIN_UA_SUBSTRING legado" "configure a regra por sede em Pessoas → Máquinas & gate"
  else
    add ua_gate ok "Gate de navegador desligado" "qualquer navegador entra (confira a sala no aquecimento)"
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
    add ua_gate fail "Gate armado mas SEM regra que casa" "modo enforce e nenhum time tem UA esperado — ou a regex não casa os logins, ou todos estão isentos"
  elif (( nu > 0 )); then
    add ua_gate warn "Gate armado com $nu time(s) de fora" "$ng com UA esperado, $nu sem regra (entram de qualquer navegador; isentos declarados: $nx) — confira em Pessoas → Máquinas & gate"
  else
    add ua_gate ok "Gate de navegador por sede" "$ng time(s) presos à imagem da sede$( (( nx > 0 )) && echo ", $nx isento(s) por escolha")"
  fi
fi

# --- rodada seguinte (aquecimento → prova) ------------------------------------------------
# Só carrega o motor de rodadas quando HÁ rodada planejada: contest sem rodadas (a maioria) não
# paga nada, e rd_promote_blockers precisa de users.sh + contest-create.sh (cc_probs_json).
if [[ -s "$cdir/rounds.json" ]]; then
  nxt="$(jq -r 'first((.rounds // [])[] | select(.state == "pending") | .slug) // ""' "$cdir/rounds.json" 2>/dev/null)"
  if [[ -z "$nxt" ]]; then
    add next_round ok "Sem rodada planejada" "a rodada no ar é a última do plano"
  else
    declare -F cc_probs_json >/dev/null || { source "$_LIBDIR/users.sh"; source "$_LIBDIR/contest-create.sh"; }
    source "$_LIBDIR/contest-rounds.sh"
    rblk="$(rd_promote_blockers "$contest")"; [[ -n "$rblk" ]] || rblk='[]'
    nb="$(jq -r 'length' <<<"$rblk" 2>/dev/null)"; nb="${nb//[^0-9]/}"; nb="${nb:-0}"
    if (( nb > 0 )); then
      add next_round warn "Rodada seguinte: $nxt" "$(jq -r 'map(.detail) | join(" · ")' <<<"$rblk")"
    else
      add next_round ok "Rodada seguinte: $nxt" "pronta para promover (Prova → Rodadas)"
    fi
  fi
fi

# --- documentos da prova ------------------------------------------------------------------
source "$_LIBDIR/contest-docs.sh"
docs_j="$(doc_index "$contest")"; [[ -n "$docs_j" ]] || docs_j='[]'
ndoc="$(jq -r 'length' <<<"$docs_j")"; ndoc="${ndoc//[^0-9]/}"; ndoc="${ndoc:-0}"
npub="$(jq -r '[.[] | select(.published)] | length' <<<"$docs_j")"; npub="${npub//[^0-9]/}"; npub="${npub:-0}"
if (( ndoc == 0 )); then
  add docs warn "Nenhum documento gerado" "info sheet, caderno e folha de time limits saem de Prova → Documentos"
elif (( npub == 0 )); then
  add docs warn "Documentos gerados mas não publicados" "$ndoc arquivo(s) só visíveis ao admin/chefe"
else
  add docs ok "Documentos da prova" "$ndoc gerado(s), $npub publicado(s) p/ a sede"
fi

ok_json '{checks:$c, summary:{ok:($c|map(select(.level=="ok"))|length),
                              warn:($c|map(select(.level=="warn"))|length),
                              fail:($c|map(select(.level=="fail"))|length)}}' \
  --argjson c "$CHECKS"
