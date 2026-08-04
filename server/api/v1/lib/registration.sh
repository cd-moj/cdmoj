# lib/registration.sh — INSCRIÇÃO em contest (roster + janela) e TIMES formados por contas
# do treino.
#
# PORQUÊ: a conta do MOJ é de UMA pessoa e o placar é uma linha por conta. Para rodar um
# esquenta de maratona com as contas do Treino Livre faltavam duas coisas: juntar até 3 contas
# numa linha só (time) e uma PORTA com horário (não faz sentido entrar com a prova na metade).
#
#   contests/<c>/registrations.json   — EXISTIR = registro LIGADO (mesma doutrina do
#   cohorts.json: ausente = comportamento de sempre, custo zero).
#
#   { "version":1,
#     "teams":   { "<team-login>": {name, captain, members:[…], invited:[…], created_at} },
#     "entries": { "<login>": {kind:"individual"|"team", team:"<team-login>"|null, cohort, at} } }
#
# JANELA (conf, mesmo caminho do settings/config do admin):
#   REG_OPEN          epoch em que o registro abre (ausente = já aberto)
#   REG_CLOSE         epoch em que fecha (ausente = CONTEST_START)
#   REG_LATE_MINUTES  minutos APÓS O INÍCIO em que ainda se entra, mas como ATRASADO
#                     (coorte `unranked`: aparece no placar sem consumir posição — é a
#                     "extra registration" do Codeforces)
#   REG_TEAM_MAX      tamanho do time (default 3)   ·   REG_TEAMS=n  desliga times
#
# MATERIALIZAÇÃO: o roster é a fonte da verdade, mas quem lê o placar/print/admin é o STORE
# POR-USUÁRIO. Toda mudança materializa (como o `cohorts`/`teams materialize` já fazem):
#   - inscrito individual -> users/<login>/account.json local SEM SENHA. Sem senha é de
#     propósito: `verify_password` tenta o local e CAI para a fonte (USERS_FROM=treino), então
#     o overlay dá identidade + coorte sem tocar em credencial.
#   - time -> users/time-<slug>/account.json com password "!<uuid>" (convenção `!` = conta
#     desativada: ninguém loga direto no time) + .team.members. Os membros entram com a
#     PRÓPRIA senha do treino e a sessão vira a do time (alias em handlers/auth/login.sh).
#
# Escrita: o CALLER segura o flock do contest (reg_lock_file) — as funções mutantes aqui
# assumem a trava. Erro sai como CÓDIGO no stdout com rc≠0 (o handler mapeia p/ HTTP).

REG_TEAM_MAX_DEFAULT=3
REG_TEAM_PREFIX=time-

reg_file(){      printf '%s/%s/registrations.json' "$CONTESTSDIR" "$1"; }
reg_lock_file(){ printf '%s/%s/var/registrations.lock' "$CONTESTSDIR" "$1"; }
# reg_enabled <c> — 0 quando o contest tem roster (registro ligado)
reg_enabled(){ [[ -s "$(reg_file "$1")" ]]; }

# reg_source_of <c> — de onde vêm as contas (USERS_FROM); o próprio contest se não houver.
reg_source_of(){
  if declare -F _users_source >/dev/null 2>&1; then _users_source "$1"; else printf '%s' "$1"; fi
}

# reg_get <c> -> roster normalizado (sempre válido, mesmo sem arquivo)
reg_get(){
  local f; f="$(reg_file "$1")"
  if [[ -s "$f" ]] && jq -e '.entries' "$f" >/dev/null 2>&1; then
    jq -c '{ version: (.version // 1),
             teams: ((.teams // {}) | with_entries(.value |= {
                       name:(.name // ""), captain:(.captain // ""),
                       members:((.members // []) | map(tostring)),
                       invited:((.invited // []) | map(tostring)),
                       cohort:(.cohort // "times"), created_at:(.created_at // 0)})),
             entries: ((.entries // {}) | with_entries(.value |= {
                       kind:(.kind // "individual"), team:(.team // null),
                       cohort:(.cohort // ""), at:(.at // 0)})) }' "$f" 2>/dev/null \
      || printf '{"version":1,"teams":{},"entries":{}}'
  else printf '{"version":1,"teams":{},"entries":{}}'; fi
}

reg_save(){  # <c> <json>
  local f; f="$(reg_file "$1")"
  mkdir -p "$CONTESTSDIR/$1/var" 2>/dev/null
  printf '%s\n' "$2" > "$f.tmp" && mv -f "$f.tmp" "$f"
}

# --- a PROVA OFICIAL é a âncora -------------------------------------------
# reg_official_window <c> -> "<início>\t<fim>\t<slug>" da prova que vale.
#
# PORQUÊ: o contest pode passar DIAS em rodada de AQUECIMENTO antes da prova (lib/contest-rounds.sh:
# a rodada ativa É o conf). Ancorar a inscrição no CONTEST_START faria a janela nascer FECHADA
# durante todo o aquecimento, e o intervalo entre o fim do aquecimento e a promoção da oficial
# ainda diria "contest encerrado". A data que interessa é a da PROVA.
#
# Lê o rounds.json CRU (nunca rd_sync_active: aquilo espelha conf→json e grava — caminho de
# leitura não pode ter efeito colateral). Pega a 1ª rodada NÃO-ARQUIVADA com kind=official; se ela
# for a ativa (ou não houver rodadas), o conf é a verdade e cai nele.
reg_official_window(){
  local c="$1" f j cs ce slug act
  f="$CONTESTSDIR/$c/rounds.json"
  cs=0; ce=0; slug=""
  if [[ -s "$f" ]]; then
    j="$(jq -r '
      (.active // "") as $a
      | ((.rounds // []) | map(select((.kind // "official") == "official"
                                      and (.state // "") != "archived")) | first) as $o
      | if $o == null or $o.slug == $a then "" else
          ((($o.start // 0)|tostring) + "\t" + (($o.end // 0)|tostring) + "\t" + ($o.slug // ""))
        end' "$f" 2>/dev/null)"
    if [[ -n "$j" ]]; then
      IFS=$'\t' read -r cs ce slug <<<"$j"
      [[ "$cs" =~ ^[0-9]+$ ]] || cs=0; [[ "$ce" =~ ^[0-9]+$ ]] || ce=0
    fi
  fi
  if (( cs == 0 )); then     # oficial já é a ativa (ou contest sem rodadas): o conf manda
    IFS=$'\x01' read -r cs ce < <( CONTEST_START=""; CONTEST_END=""; ROUND=""
      source "$CONTESTSDIR/$c/conf" 2>/dev/null
      printf '%s\x01%s' "${CONTEST_START:-0}" "${CONTEST_END:-0}" )
    [[ "$cs" =~ ^[0-9]+$ ]] || cs=0; [[ "$ce" =~ ^[0-9]+$ ]] || ce=0
    slug=""
  fi
  printf '%s\t%s\t%s' "$cs" "$ce" "$slug"
}

# reg_round_kind <c> -> warmup|official|extra (do conf; sem rodadas = official)
reg_round_kind(){
  local v; v="$( ( ROUND_KIND=""; source "$CONTESTSDIR/$1/conf" 2>/dev/null; printf '%s' "${ROUND_KIND:-}" ) )"
  printf '%s' "${v:-official}"
}

# reg_gate_active <c> — 0 quando o roster DEVE ser exigido no login agora.
# No AQUECIMENTO a porta fica aberta (decisão do organizador: o esquenta atrai gente; quem quiser
# competir na prova se inscreve). Quem entrou no aquecimento sem se inscrever é varrido na
# promoção — ver reg_sweep_unregistered.
reg_gate_active(){
  reg_enabled "$1" || return 1
  [[ "$(reg_round_kind "$1")" == warmup ]] && return 1
  return 0
}

# --- janela ---------------------------------------------------------------
# reg_window <c> -> "<estado>\t<abre>\t<fecha>\t<atrasado_ate>\t<ancora>\t<rodada>"
#   soon (ainda não abriu) | open | late (só entrada atrasada) | closed
# O `source` do conf roda command substitution (o treino tem CONTEST_END="$(date …)") — é o
# mesmo padrão do contest_phase; por isso roda em subshell.
reg_window(){
  local c="$1" ancs ance ancr
  IFS=$'\t' read -r ancs ance ancr < <(reg_official_window "$c")
  ( local REG_OPEN="" REG_CLOSE="" REG_LATE_MINUTES=""
    source "$CONTESTSDIR/$c/conf" 2>/dev/null
    local op=0 cl=0 lt=0 mins=0 now="$EPOCHSECONDS" st
    [[ "$REG_OPEN"  =~ ^[0-9]+$ ]] && op="$REG_OPEN"
    # sem REG_CLOSE, fecha no início da PROVA OFICIAL (não da rodada corrente)
    if [[ "$REG_CLOSE" =~ ^[0-9]+$ ]]; then cl="$REG_CLOSE"; else cl="$ancs"; fi
    [[ "$REG_LATE_MINUTES" =~ ^[0-9]+$ ]] && mins="$REG_LATE_MINUTES"
    # o atraso é ancorado no INÍCIO DA PROVA (é o que a pessoa entende por "atrasado"),
    # nunca antes do fechamento normal
    if (( mins > 0 )); then
      lt=$(( (ancs > 0 ? ancs : cl) + mins * 60 ))
      (( lt < cl )) && lt=$cl
    fi
    # AQUECIMENTO sem prova planejada: a âncora cairia num instante já passado e ninguém
    # conseguiria se inscrever. Nesse caso a inscrição fica ABERTA (e o pré-prova avisa).
    if [[ "$(reg_round_kind "$c")" == warmup ]] && (( ancs > 0 && ancs <= now )); then
      cl=0; lt=0
    fi
    if   (( op > 0 && now < op ));       then st=soon
    elif (( ance > 0 && now > ance ));   then st=closed   # a PROVA acabou (não o aquecimento)
    elif (( cl == 0 || now <= cl ));     then st=open
    elif (( lt > 0 && now <= lt ));      then st=late
    else st=closed; fi
    printf '%s\t%s\t%s\t%s\t%s\t%s' "$st" "$op" "$cl" "$lt" "$ancs" "$ancr" )
}

reg_window_state(){ reg_window "$1" | cut -f1; }

# reg_team_max <c> / reg_teams_allowed <c>
reg_team_max(){
  local v; v="$( ( REG_TEAM_MAX=""; source "$CONTESTSDIR/$1/conf" 2>/dev/null; printf '%s' "${REG_TEAM_MAX:-}" ) )"
  [[ "$v" =~ ^[1-9][0-9]*$ ]] && printf '%s' "$v" || printf '%s' "$REG_TEAM_MAX_DEFAULT"
}
reg_teams_allowed(){
  local v; v="$( ( REG_TEAMS=""; source "$CONTESTSDIR/$1/conf" 2>/dev/null; printf '%s' "${REG_TEAMS:-}" ) )"
  [[ "$v" == n ]] && return 1 || return 0
}

# --- consulta -------------------------------------------------------------
# reg_kind_of <c> <login> -> individual | team | invited | none
reg_kind_of(){
  local k; k="$(reg_get "$1" | jq -r --arg l "$2" '
      (.entries[$l].kind // empty) //
      (if any(.teams[]; (.invited // []) | index($l)) then "invited" else "none" end)')"
  printf '%s' "${k:-none}"
}
# reg_team_of <c> <login> -> login do time do qual <login> é MEMBRO (vazio se não é)
reg_team_of(){
  reg_get "$1" | jq -r --arg l "$2" '
    (.entries[$l] // {}) | select(.kind == "team") | (.team // "") | select(. != "")' 2>/dev/null
}
# reg_is_registered <c> <login> — 0 se o login pode ENTRAR no contest pelo roster
reg_is_registered(){
  local k; k="$(reg_kind_of "$1" "$2")"
  [[ "$k" == individual || "$k" == team ]]
}

# reg_cohort_for <c> <kind> -> coorte a atribuir AGORA (times/individual + sufixo do atrasado)
reg_cohort_for(){
  local base="individual"; [[ "$2" == team ]] && base="times"
  [[ "$(reg_window_state "$1")" == late ]] && base="$base-atrasado"
  printf '%s' "$base"
}

# --- coortes (semeadas na 1ª inscrição) -----------------------------------
# Só semeia quando NÃO há cohorts.json com coortes: contest que já tem coortes configuradas
# (convidados/CCL) é do organizador — não mexemos. O pré-prova avisa se faltar.
reg_seed_cohorts(){
  # `local a=1 b=$a` NÃO funciona: local é um COMANDO e todos os argumentos são expandidos
  # antes de rodar — $c ainda seria o de fora (aqui: vazio, e o arquivo ia p/ contests//)
  local c="$1" f
  f="$CONTESTSDIR/$c/cohorts.json"
  [[ -s "$f" ]] && jq -e '(.cohorts // []) | length > 0' "$f" >/dev/null 2>&1 && return 0
  jq -n '{version:1, results_released:false, cohorts:[
      {id:"individual", name:"Individual", default:true, public:true, ranking:true,
       sees:["individual","individual-atrasado"]},
      {id:"individual-atrasado", name:"Individual (atrasado)", public:true, unranked:true,
       sees:["individual","individual-atrasado"]},
      {id:"times", name:"Times", public:true, ranking:true, sees:["times","times-atrasado"]},
      {id:"times-atrasado", name:"Times (atrasado)", public:true, unranked:true,
       sees:["times","times-atrasado"]}]}' > "$f.tmp" && mv -f "$f.tmp" "$f"
}

# --- materialização -------------------------------------------------------
# reg_materialize_login <c> <login> <cohort> — overlay da conta compartilhada no store local.
reg_materialize_login(){
  local c="$1" l="$2" co="$3" src d f name
  valid_id "$l" || return 1
  src="$(reg_source_of "$c")"
  d="$(user_dir "$c" "$l")"; f="$d/account.json"
  mkdir -p "$d/submissions" "$d/mojlog" "$d/results" 2>/dev/null || return 1
  [[ -f "$d/history" ]] || : > "$d/history"
  if [[ -f "$f" ]] && [[ -n "$(jq -r '.password // empty' "$f" 2>/dev/null)" ]]; then
    # conta LOCAL de verdade (criada pelo admin): não sobrescreve credencial, só marca a coorte
    account_merge "$c" "$l" '.team = ((.team // {}) + {cohort:$co}) | .updated_at = $t' \
      --arg co "$co" --argjson t "$EPOCHSECONDS"
  else
    name="$(jq -r '.fullname // ""' "$CONTESTSDIR/$src/users/$l/account.json" 2>/dev/null)"
    [[ -n "$name" ]] || name="$l"
    jq -n --arg l "$l" --arg n "$name" --arg co "$co" --argjson t "$EPOCHSECONDS" \
      '{login:$l, fullname:$n, status:"active", registered_at:$t, updated_at:$t,
        team:{cohort:$co}}' > "$f.tmp" 2>/dev/null && mv -f "$f.tmp" "$f"
  fi
  _score_dirty "$c"
}

# reg_unmaterialize_login <c> <login> — desfaz o overlay (só o NOSSO: sem senha e com
# registered_at). Se a pessoa já submeteu, o diretório FICA (o dado dela é dela).
reg_unmaterialize_login(){
  local c="$1" l="$2" d f
  valid_id "$l" || return 1
  d="$(user_dir "$c" "$l")"; f="$d/account.json"
  [[ -f "$f" ]] || return 0
  [[ -n "$(jq -r '.password // empty' "$f" 2>/dev/null)" ]] && return 0        # conta local real
  [[ "$(jq -r '.registered_at // empty' "$f" 2>/dev/null)" ]] || return 0      # não é nosso
  rm -f "$f"
  [[ -s "$d/history" ]] && { _score_dirty "$c"; return 0; }                    # já competiu: mantém
  rm -rf "$d"
  _score_dirty "$c"
}

# reg_materialize_team <c> <team-login> — conta do TIME (fullname = nome, membros no .team)
reg_materialize_team(){
  local c="$1" t="$2" j d f
  valid_id "$t" || return 1
  j="$(reg_get "$c" | jq -c --arg t "$t" '.teams[$t] // empty')"
  [[ -n "$j" ]] || return 1
  d="$(user_dir "$c" "$t")"; f="$d/account.json"
  mkdir -p "$d/submissions" "$d/mojlog" "$d/results" 2>/dev/null || return 1
  [[ -f "$d/history" ]] || : > "$d/history"
  # senha "!<uuid>": convenção do MOJ p/ conta desativada — o time NÃO loga direto,
  # quem entra são os membros (com a senha deles) e a sessão vira a do time.
  local pw; pw="$(jq -r '.password // empty' "$f" 2>/dev/null)"
  [[ -n "$pw" ]] || pw="!$(</proc/sys/kernel/random/uuid)"
  # objeto de UM time (nome + até 3 logins) — cabe folgado em argv, longe do limite do jq
  jq -n --argjson x "$j" --arg t "$t" --arg pw "$pw" --argjson ts "$EPOCHSECONDS" \
    '{login:$t, password:$pw, fullname:($x.name), status:"active", is_team:true,
        registered_at:($x.created_at // $ts), updated_at:$ts,
        team:{cohort:($x.cohort // "times"), members:($x.members), captain:($x.captain)}}' \
    > "$f.tmp" 2>/dev/null && mv -f "$f.tmp" "$f"
  _score_dirty "$c"
}

reg_unmaterialize_team(){
  local c="$1" t="$2" d="$(user_dir "$1" "$2")"
  valid_id "$t" || return 1
  [[ -d "$d" ]] || return 0
  [[ -s "$d/history" ]] && { rm -f "$d/account.json"; _score_dirty "$c"; return 0; }
  rm -rf "$d"; _score_dirty "$c"
}

# --- slug do time ---------------------------------------------------------
# reg_team_slug <nome> -> slug canônico (sem acento, minúsculo, [a-z0-9-]). É ele que decide
# se dois nomes são "o mesmo" (Os Três Ponteiros × Os Tres Ponteiros): dois times com nomes
# que só diferem no acento seriam indistinguíveis no placar.
reg_team_slug(){
  local base slug
  base="$(printf '%s' "$1" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || printf '%s' "$1")"
  slug="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' \
          | sed 's/^-*//; s/-*$//' | cut -c1-24)"
  printf '%s' "${slug:-time}"
}

# nome livre -> login `time-<slug>` único (no contest E na fonte: não pode colidir com um
# login de gente de verdade, senão a conta do time viraria porta de entrada).
reg_team_login(){
  local c="$1" name="$2" slug n=1 cand src
  slug="$(reg_team_slug "$name")"
  src="$(reg_source_of "$c")"
  cand="$REG_TEAM_PREFIX$slug"
  while [[ -e "$(user_dir "$c" "$cand")" ]] || [[ -e "$(user_dir "$src" "$cand")" ]] \
        || reg_get "$c" | jq -e --arg t "$cand" 'has("teams") and (.teams | has($t))' >/dev/null 2>&1; do
    n=$(( n + 1 )); cand="$REG_TEAM_PREFIX$slug-$n"
    (( n > 99 )) && return 1
  done
  printf '%s' "$cand"
}

# --- mutações (caller segura o flock) -------------------------------------
# Todas ecoam um CÓDIGO de erro e retornam ≠0 quando recusam.

reg_register_individual(){  # <c> <login>
  local c="$1" l="$2" k j
  k="$(reg_kind_of "$c" "$l")"
  [[ "$k" == individual ]] && { printf 'already_registered'; return 1; }
  [[ "$k" == team ]] && { printf 'in_team'; return 1; }
  reg_seed_cohorts "$c"
  local co; co="$(reg_cohort_for "$c" individual)"
  j="$(reg_get "$c" | jq -c --arg l "$l" --arg co "$co" --argjson t "$EPOCHSECONDS" \
        '.entries[$l] = {kind:"individual", team:null, cohort:$co, at:$t}
         | .teams |= with_entries(.value.invited |= map(select(. != $l)))')"
  reg_save "$c" "$j"
  reg_materialize_login "$c" "$l" "$co"
}

reg_cancel(){  # <c> <login> — sai da inscrição (individual) ou do time
  local c="$1" l="$2" k
  k="$(reg_kind_of "$c" "$l")"
  case "$k" in
    individual) reg_save "$c" "$(reg_get "$c" | jq -c --arg l "$l" 'del(.entries[$l])')"
                reg_unmaterialize_login "$c" "$l" ;;
    team)       reg_team_leave "$c" "$l" || return 1 ;;
    *)          printf 'not_registered'; return 1 ;;
  esac
}

reg_team_create(){  # <c> <captain> <name> -> ecoa o login do time
  local c="$1" cap="$2" name="$3" t k j co
  reg_teams_allowed "$c" || { printf 'teams_disabled'; return 1; }
  k="$(reg_kind_of "$c" "$cap")"
  [[ "$k" == team ]] && { printf 'in_team'; return 1; }
  name="$(printf '%s' "$name" | tr -d '\t\n\r' | sed 's/^ *//; s/ *$//' | cut -c1-48)"
  [[ ${#name} -ge 2 ]] || { printf 'bad_name'; return 1; }
  # colisão pelo SLUG (não pelo nome cru): "Os Três" e "Os Tres" são o mesmo time no placar
  reg_get "$c" | jq -e --arg t "$REG_TEAM_PREFIX$(reg_team_slug "$name")" '.teams | has($t)' \
    >/dev/null 2>&1 && { printf 'name_taken'; return 1; }
  t="$(reg_team_login "$c" "$name")" || { printf 'slug_failed'; return 1; }
  reg_seed_cohorts "$c"
  co="$(reg_cohort_for "$c" team)"
  j="$(reg_get "$c" | jq -c --arg t "$t" --arg n "$name" --arg cap "$cap" --arg co "$co" \
        --argjson ts "$EPOCHSECONDS" \
        '.teams[$t] = {name:$n, captain:$cap, members:[$cap], invited:[], cohort:$co, created_at:$ts}
         | .entries[$cap] = {kind:"team", team:$t, cohort:$co, at:$ts}
         | .teams |= with_entries(.value.invited |= map(select(. != $cap)))')"
  reg_save "$c" "$j"
  reg_unmaterialize_login "$c" "$cap"     # deixa de valer como individual
  reg_materialize_team "$c" "$t"
  printf '%s' "$t"
}

reg_team_invite(){  # <c> <captain> <login-convidado>
  local c="$1" cap="$2" who="$3" t max n k
  t="$(reg_team_of "$c" "$cap")"; [[ -n "$t" ]] || { printf 'no_team'; return 1; }
  reg_get "$c" | jq -e --arg t "$t" --arg l "$cap" '.teams[$t].captain == $l' >/dev/null 2>&1 \
    || { printf 'not_captain'; return 1; }
  [[ "$who" == "$cap" ]] && { printf 'self_invite'; return 1; }
  k="$(reg_kind_of "$c" "$who")"
  [[ "$k" == team ]] && { printf 'already_in_team'; return 1; }
  max="$(reg_team_max "$c")"
  n="$(reg_get "$c" | jq -r --arg t "$t" '((.teams[$t].members | length) + (.teams[$t].invited | length))')"
  (( n >= max )) && { printf 'team_full'; return 1; }
  reg_get "$c" | jq -e --arg t "$t" --arg l "$who" '(.teams[$t].invited | index($l)) != null' \
    >/dev/null 2>&1 && { printf 'already_invited'; return 1; }
  reg_save "$c" "$(reg_get "$c" | jq -c --arg t "$t" --arg l "$who" \
    '.teams[$t].invited += [$l] | .teams[$t].invited |= unique')"
}

reg_team_accept(){  # <c> <login> <team>
  local c="$1" l="$2" t="$3" max n co
  reg_get "$c" | jq -e --arg t "$t" --arg l "$l" '(.teams[$t].invited // []) | index($l) != null' \
    >/dev/null 2>&1 || { printf 'no_invite'; return 1; }
  [[ "$(reg_kind_of "$c" "$l")" == team ]] && { printf 'already_in_team'; return 1; }
  max="$(reg_team_max "$c")"
  n="$(reg_get "$c" | jq -r --arg t "$t" '.teams[$t].members | length')"
  (( n >= max )) && { printf 'team_full'; return 1; }
  co="$(reg_get "$c" | jq -r --arg t "$t" '.teams[$t].cohort // "times"')"
  reg_save "$c" "$(reg_get "$c" | jq -c --arg t "$t" --arg l "$l" --arg co "$co" --argjson ts "$EPOCHSECONDS" \
    '.teams[$t].members += [$l] | .teams[$t].members |= unique
     | .teams[$t].invited |= map(select(. != $l))
     | .entries[$l] = {kind:"team", team:$t, cohort:$co, at:$ts}')"
  reg_unmaterialize_login "$c" "$l"       # se estava individual, deixa de estar
  reg_materialize_team "$c" "$t"
}

reg_team_decline(){  # <c> <login> <team>
  reg_save "$1" "$(reg_get "$1" | jq -c --arg t "$3" --arg l "$2" \
    'if (.teams | has($t)) then .teams[$t].invited |= map(select(. != $l)) else . end')"
}

# reg_team_leave <c> <login> — membro sai. Capitão que sai passa a capitania p/ o próximo;
# último a sair DISSOLVE o time.
reg_team_leave(){
  local c="$1" l="$2" t n
  t="$(reg_team_of "$c" "$l")"; [[ -n "$t" ]] || { printf 'no_team'; return 1; }
  reg_save "$c" "$(reg_get "$c" | jq -c --arg t "$t" --arg l "$l" \
    '.teams[$t].members |= map(select(. != $l))
     | (if .teams[$t].captain == $l then .teams[$t].captain = (.teams[$t].members[0] // "") else . end)
     | del(.entries[$l])')"
  n="$(reg_get "$c" | jq -r --arg t "$t" '.teams[$t].members | length')"
  if (( n == 0 )); then
    reg_save "$c" "$(reg_get "$c" | jq -c --arg t "$t" 'del(.teams[$t])')"
    reg_unmaterialize_team "$c" "$t"
  else
    reg_materialize_team "$c" "$t"
  fi
}

reg_team_dissolve(){  # <c> <captain>
  local c="$1" cap="$2" t
  t="$(reg_team_of "$c" "$cap")"; [[ -n "$t" ]] || { printf 'no_team'; return 1; }
  reg_get "$c" | jq -e --arg t "$t" --arg l "$cap" '.teams[$t].captain == $l' >/dev/null 2>&1 \
    || { printf 'not_captain'; return 1; }
  reg_save "$c" "$(reg_get "$c" | jq -c --arg t "$t" \
    '(.teams[$t].members // []) as $m
     | .entries |= with_entries(select((.value.team // "") != $t))
     | del(.teams[$t])')"
  reg_unmaterialize_team "$c" "$t"
}

reg_team_rename(){  # <c> <captain> <novo-nome>  (o LOGIN do time não muda)
  local c="$1" cap="$2" name="$3" t
  t="$(reg_team_of "$c" "$cap")"; [[ -n "$t" ]] || { printf 'no_team'; return 1; }
  reg_get "$c" | jq -e --arg t "$t" --arg l "$cap" '.teams[$t].captain == $l' >/dev/null 2>&1 \
    || { printf 'not_captain'; return 1; }
  name="$(printf '%s' "$name" | tr -d '\t\n\r' | sed 's/^ *//; s/ *$//' | cut -c1-48)"
  [[ ${#name} -ge 2 ]] || { printf 'bad_name'; return 1; }
  reg_get "$c" | jq -e --arg t "$t" --arg s "$REG_TEAM_PREFIX$(reg_team_slug "$name")" \
    'any(.teams | to_entries[]; .key != $t and .key == $s)' \
    >/dev/null 2>&1 && { printf 'name_taken'; return 1; }
  reg_save "$c" "$(reg_get "$c" | jq -c --arg t "$t" --arg n "$name" '.teams[$t].name = $n')"
  reg_materialize_team "$c" "$t"
}

# --- cascata do rename ----------------------------------------------------
# reg_rename_login <old> <new> — o handle mudou no treino: segue em TODOS os rosters (e no
# diretório materializado). Sem isto a pessoa "sumia" da inscrição ao trocar de nome.
reg_rename_login(){
  local old="$1" new="$2" f c
  [[ -n "$old" && -n "$new" && "$old" != "$new" ]] || return 0
  ( set +o noglob; shopt -s nullglob
    for f in "$CONTESTSDIR"/*/registrations.json; do
      grep -q "\"$old\"" "$f" 2>/dev/null || continue
      c="${f%/registrations.json}"; c="${c##*/}"
      jq -c --arg o "$old" --arg n "$new" '
        (.entries // {}) as $e
        | if ($e | has($o)) then .entries[$n] = $e[$o] | del(.entries[$o]) else . end
        | .teams |= with_entries(.value.members |= map(if . == $o then $n else . end)
                                | .value.invited |= map(if . == $o then $n else . end)
                                | .value.captain |= (if . == $o then $n else . end))' \
        "$f" > "$f.tmp" 2>/dev/null && mv -f "$f.tmp" "$f" || rm -f "$f.tmp"
      # diretório materializado segue o nome (rename de conta = mv do diretório)
      [[ -d "$CONTESTSDIR/$c/users/$old" && ! -e "$CONTESTSDIR/$c/users/$new" ]] \
        && mv "$CONTESTSDIR/$c/users/$old" "$CONTESTSDIR/$c/users/$new" \
        && jq -c --arg n "$new" '.login = $n' "$CONTESTSDIR/$c/users/$new/account.json" \
             > "$CONTESTSDIR/$c/users/$new/account.json.tmp" 2>/dev/null \
        && mv -f "$CONTESTSDIR/$c/users/$new/account.json.tmp" "$CONTESTSDIR/$c/users/$new/account.json"
      touch "$CONTESTSDIR/$c/var/.score-dirty" 2>/dev/null
    done ) 2>/dev/null
  return 0
}

# --- varredura da promoção ------------------------------------------------
# reg_sweep_unregistered <c> -> "<sessões derrubadas>\t<dirs removidos>"
# Chamada na PROMOÇÃO para uma rodada que NÃO é aquecimento. Durante o aquecimento a porta fica
# aberta (reg_gate_active), então quem entrou sem se inscrever precisa:
#   (a) perder a sessão — sessão do MOJ não expira e a porta só é aplicada no /auth/login: sem
#       isso o turista do esquenta entra na PROVA pela aba que deixou aberta;
#   (b) sumir do store — o dir local vazio (sem account.json) continua listado pelo sc_users via
#       USERS_FROM, e o placar da prova nasceria com dezenas de linhas zeradas.
# Conta LOCAL de verdade (com senha) e conta de PAPEL nunca são tocadas.
reg_sweep_unregistered(){
  local c="$1" ns=0 nd=0 f d u
  reg_enabled "$c" || { printf '0\t0'; return 0; }
  declare -A _REGOK=()
  while IFS= read -r u; do [[ -n "$u" ]] && _REGOK["$u"]=1; done \
    < <(reg_get "$c" | jq -r '((.entries // {}) | keys[]), ((.teams // {}) | keys[])' 2>/dev/null)
  set +o noglob; shopt -s nullglob
  local CONTEST LOGIN
  for f in "$SESSIONDIR"/*; do
    [[ -f "$f" ]] || continue
    CONTEST=""; LOGIN=""; source "$f" 2>/dev/null
    [[ "$CONTEST" == "$c" && -n "$LOGIN" ]] || continue
    is_reserved_role_login "$LOGIN" && continue
    [[ -n "${_REGOK[$LOGIN]:-}" ]] && continue
    rm -f "$f"; ns=$(( ns + 1 ))
  done
  for d in "$CONTESTSDIR/$c/users"/*/; do
    u="${d%/}"; u="${u##*/}"
    is_reserved_role_login "$u" && continue
    [[ -n "${_REGOK[$u]:-}" ]] && continue
    [[ -e "$d/account.json" ]] && continue          # conta local (admin criou) — não é turista
    [[ -s "$d/history" ]] && continue               # ainda tem dado vivo: não mexe
    rm -rf "$d"; nd=$(( nd + 1 ))
  done
  shopt -u nullglob
  (( nd > 0 )) && _score_dirty "$c"
  printf '%s\t%s' "$ns" "$nd"
}

# --- visão p/ o front -----------------------------------------------------
# reg_status_json <c> <login> -> objeto com janela, minha situação, meu time e convites.
reg_status_json(){
  local c="$1" l="${2:-}" st op cl lt anc rnd
  # tab como separador é seguro AQUI porque só o ÚLTIMO campo (slug da rodada) pode ser vazio —
  # o colapso de runs de tab do `IFS=$'\t' read` só morde com campo vazio no MEIO (ver CLAUDE.md)
  IFS=$'\t' read -r st op cl lt anc rnd < <(reg_window "$c")
  reg_get "$c" | jq -c --arg l "$l" --arg st "$st" --argjson op "${op:-0}" \
      --argjson cl "${cl:-0}" --argjson lt "${lt:-0}" --argjson max "$(reg_team_max "$c")" \
      --argjson anc "${anc:-0}" --arg rnd "${rnd:-}" \
      --argjson gate "$(reg_gate_active "$c" && echo true || echo false)" \
      --arg kind "$(reg_round_kind "$c")" \
      --argjson teams_ok "$(reg_teams_allowed "$c" && echo true || echo false)" '
    (.entries[$l] // null) as $me
    | (if $me != null and $me.kind == "team" then .teams[$me.team] else null end) as $team
    | { window:{state:$st, opens_at:$op, closes_at:$cl, late_until:$lt,
                official_start:$anc, official_round:$rnd},
        round_kind:$kind, gate_active:$gate,
        team_max:$max, teams_allowed:$teams_ok,
        me: (if $me == null then {kind:"none"} else ($me + {}) end),
        team: (if $team == null then null
               else {login:($me.team), name:$team.name, captain:$team.captain,
                     members:$team.members, invited:$team.invited, cohort:$team.cohort} end),
        invites: [ .teams | to_entries[] | select((.value.invited // []) | index($l))
                   | {login:.key, name:.value.name, captain:.value.captain,
                      members:.value.members} ],
        totals: { individuals: ([.entries[] | select(.kind == "individual")] | length),
                  teams: (.teams | length),
                  people: (.entries | length) } }'
}
