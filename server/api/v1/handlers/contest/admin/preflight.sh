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
SHOWCODE=0; PRINT=""; MANUAL_VERDICT=""; PROBS=()
load_contest_conf "$contest"
mode="$(contest_score_mode "$contest")"

# --- janela -----------------------------------------------------------------
if [[ "$CONTEST_START" =~ ^[0-9]+$ && "$CONTEST_END" =~ ^[0-9]+$ ]] \
   && (( CONTEST_START > 0 && CONTEST_END > CONTEST_START )); then
  add window ok "Janela da prova" "início $(date -d "@$CONTEST_START" '+%d/%m %H:%M' 2>/dev/null) → fim $(date -d "@$CONTEST_END" '+%d/%m %H:%M' 2>/dev/null)"
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
  add freeze ok "Freeze configurado" "congela em $(date -d "@$fz" '+%d/%m %H:%M' 2>/dev/null)"
elif (( fz > 0 )); then
  add freeze warn "Freeze fora da janela" "FREEZE_TIME não está entre o início e o fim"
else
  add freeze warn "Sem freeze" "prova ICPC costuma congelar o placar (Configurações → Freeze)"
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

langs_lc="$(printf '%s' "${LANGUAGES:-}" | tr '[:upper:]' '[:lower:]')"
if [[ -n "$langs_lc" ]]; then
  missing=""
  for l in $langs_lc; do
    jq -e --arg l "$l" 'any(.[]; .langs | index($l))' >/dev/null 2>&1 <<<"$judges" || missing+=" $l"
  done
  if [[ -z "$missing" ]]; then
    add langs ok "Toolchain das linguagens" "todas as permitidas ($langs_lc) têm juiz online"
  else
    add langs fail "Linguagem sem juiz" "sem toolchain online p/:$missing"
  fi
else
  add langs warn "Linguagens sem whitelist" "todas as linguagens do MOJ ficam liberadas (Configurações → Linguagens)"
fi

# --- problemas: TL calibrado + cache nos juízes online ---------------------------
noTL=""; noCache=""; nprob=0
for ((i=0; i+4<${#PROBS[@]}; i+=5)); do
  id="${PROBS[i+4]}"; (( nprob++ ))
  if [[ ! -s "$(tl_store_file "$id")" ]]; then noTL+=" $id"; continue; fi
  jq -e --arg id "$id" 'any(.[]; .problems | has($id))' >/dev/null 2>&1 <<<"$judges" || noCache+=" $id"
done
if (( nprob == 0 )); then
  add problems fail "Sem problemas" "o contest não tem problemas no conf"
elif [[ -n "$noTL" ]]; then
  add problems fail "Problema sem TL calibrado" "sem calibração:$noTL — dispare /ops/updateproblemset e aguarde os juízes"
elif [[ -n "$noCache" ]]; then
  add problems warn "Problema fora do cache dos juízes online" "será baixado+calibrado na 1ª submissão (lento):$noCache"
else
  add problems ok "Problemas calibrados" "$nprob problema(s) com TL reportado e em cache"
fi

# --- staff de impressão -----------------------------------------------------------
staff_n="$(find "$cdir/users" -maxdepth 1 -type d -name '*.staff' 2>/dev/null | wc -l | tr -d '[:space:]')"
if [[ "${PRINT:-}" == 0 ]]; then
  add print ok "Impressão desligada" "sem balcão de impressão nesta prova"
elif (( staff_n > 0 )); then
  add print ok "Impressão + staff" "$staff_n conta(s) .staff p/ operar impressão/balões"
else
  add print warn "Impressão sem staff" "PRINT ligado mas nenhuma conta .staff existe — balões/impressões ficarão sem operador"
fi

# --- contas ------------------------------------------------------------------------
users_n="$(find "$cdir/users" -maxdepth 2 -name account.json 2>/dev/null \
  | grep -vcE '\.(admin|judge|cjudge|staff|mon)/account\.json$')"
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
(( ntov > 0 )) && add tov warn "Prorrogação por sede ativa" "$ntov regra(s) em time-overrides.json" \
               || add tov ok "Sem prorrogações ativas" "todos seguem o fim normal"

ok_json '{checks:$c, summary:{ok:($c|map(select(.level=="ok"))|length),
                              warn:($c|map(select(.level=="warn"))|length),
                              fail:($c|map(select(.level=="fail"))|length)}}' \
  --argjson c "$CHECKS"
