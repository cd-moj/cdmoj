# lib/contest-create.sh — criação de contest (formulário + import de tar).
# Permissão: lista do admin OU threshold de problemas resolvidos no treino (com denylist);
# usuários .admin sempre podem. Problemas vêm do banco do treino (var/jsons), por ID
# (não-públicos), e/ou com enunciado custom. O conf é SOURCED -> tudo escrito com printf %q.
: "${DEFAULT_SCORE_MODE:=icpc}"
source "${BASH_SOURCE[0]%/*}/verdict.sh"   # penalty_codes_* (validação/normalização)
source "${BASH_SOURCE[0]%/*}/difficulty.sh" # diff_label/diff_bucket: dificuldade do sorteio (fonte única, #30)
source "${BASH_SOURCE[0]%/*}/contest-statement.sh"   # idiomas do enunciado no contest (cs_*), 2026-09-15

cc_perms_file(){ printf '%s/treino/var/contest-perms.json' "$CONTESTSDIR"; }

# JSON de permissões com defaults: {threshold:int, allow:[], deny:[], allow_meta:{}, deny_meta:{}}.
# `allow`/`deny` seguem LISTAS DE LOGIN (todo leitor — cc_can_create, permission, problems/orgs — lê
# só elas); a trilha "quem liberou e quando" mora em `allow_meta`/`deny_meta` = {login:{by,at,note}}
# (2026-09-15, pedido do Ribas). Arquivo antigo sem meta continua válido.
cc_perms_json(){
  local f; f="$(cc_perms_file)"
  if [[ -f "$f" ]]; then
    jq -c '{threshold:((.threshold//0)|floor), allow:(.allow//[]), deny:(.deny//[]), allow_meta:(.allow_meta//{}), deny_meta:(.deny_meta//{})}' "$f" 2>/dev/null \
      || echo '{"threshold":0,"allow":[],"deny":[],"allow_meta":{},"deny_meta":{}}'
  else
    echo '{"threshold":0,"allow":[],"deny":[],"allow_meta":{},"deny_meta":{}}'
  fi
}
# cc_perms_write <json> — escrita atômica do contest-perms.json
cc_perms_write(){ local f; f="$(cc_perms_file)"; mkdir -p "${f%/*}"; printf '%s' "$1" > "$f.tmp" && mv -f "$f.tmp" "$f"; }

# cc_contest_visible_to <viewer> <owner> — FONTE ÚNICA de "quem vê/opera o contest de quem" no painel
# do treino (lista, remover, duplicar, exportar). Super-admin: tudo. `.admin` comum: os seus e os de
# criadores SEM papel de admin (professor não vê prova de outro professor). Outros: só os seus.
cc_contest_visible_to(){
  local viewer="$1" owner="$2"
  [[ -n "$viewer" ]] || return 1
  superadmin_login "$viewer" && return 0
  [[ "$owner" == "$viewer" ]] && return 0
  [[ "$viewer" == *.admin && -n "$owner" && "$owner" != *.admin ]] && return 0
  return 1
}
# cc_contest_owner <id> — dono: arquivo `owner` (o que os gates de problema usam) › created-by
cc_contest_owner(){
  local o; o="$(head -1 "$CONTESTSDIR/$1/owner" 2>/dev/null)"
  [[ -n "$o" ]] || { IFS=$'\t' read -r o _ _ < "$CONTESTSDIR/$1/created-by" 2>/dev/null; }
  printf '%s' "$o"
}

# nº de problemas distintos resolvidos por um usuário no treino livre (O(1) via metrics)
cc_solved_count(){ metrics_solved_count treino "$1"; }

# cc_genpass — senha legível: uma palavra de palavras-para-senha + 4 dígitos (ex.: tartaruga7823).
cc_genpass(){
  local wl="${PASSWORD_WORDLIST:-}" w=""
  [[ -f "$wl" ]] && w="$(shuf -n1 "$wl" 2>/dev/null | tr -cd 'a-z0-9')"
  [[ -n "$w" ]] || w="$(head -c 8 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 6)"
  printf '%s%04d' "$w" "$(( RANDOM % 10000 ))"
}

# cc_can_create <login> -> 0 se pode criar. Popula CC_* (REASON, SOLVED, THRESHOLD, INALLOW, INDENY, ISADMIN).
cc_can_create(){
  local login="$1" perms; perms="$(cc_perms_json)"
  CC_THRESHOLD="$(jq -r '.threshold' <<<"$perms")"
  CC_INALLOW=false; CC_INDENY=false; CC_ISADMIN=false; CC_REASON=""
  jq -e --arg u "$login" '.allow|index($u)' >/dev/null 2>&1 <<<"$perms" && CC_INALLOW=true
  jq -e --arg u "$login" '.deny|index($u)'  >/dev/null 2>&1 <<<"$perms" && CC_INDENY=true
  [[ "$login" == *.admin ]] && CC_ISADMIN=true
  CC_SOLVED=0   # só calculado quando o threshold importa (evita varrer o history à toa)
  if [[ "$CC_ISADMIN" == true ]]; then CC_REASON="administrador"; return 0; fi
  if [[ "$CC_INDENY" == true ]]; then CC_REASON="bloqueado pelo administrador"; return 1; fi
  if [[ "$CC_INALLOW" == true ]]; then CC_REASON="autorizado pelo administrador"; return 0; fi
  if [[ "${CC_THRESHOLD:-0}" =~ ^[0-9]+$ ]] && (( CC_THRESHOLD > 0 )); then
    CC_SOLVED="$(cc_solved_count "$login")"
    if (( CC_SOLVED >= CC_THRESHOLD )); then CC_REASON="resolveu $CC_SOLVED problemas (≥ $CC_THRESHOLD)"; return 0; fi
  fi
  CC_REASON="precisa de autorização do admin ou de resolver mais problemas"; return 1
}

# cc_settings_conf_lines <spec_json> — ecoa as linhas VAR=%q dos toggles/opções do settings
# (paridade com /contest/admin/settings) p/ o conf de um contest NOVO. Semântica: grava só o
# NÃO-default (default = ausência da var) — diferente do bset do settings.sh, que é PATCH por
# chave presente. Validação dura (ua_long) fica no cc_create, ANTES do staging.
cc_settings_conf_lines(){
  local spec="$1" v
  # NUNCA usar `.campo // empty` p/ booleano: o // do jq engole `false` (ausente vira "null")
  # SHOWLOG: grava só o false explícito; ausente = default por modo (showlog_effective em
  # lib/verdict.sh — icpc = oculto). O wizard manda true por default, então NÃO gravar o true
  # aqui é o que mantém contest icpc novo protegido (religar = settings POST, SHOWLOG=1).
  v="$(jq -r '.show_log' <<<"$spec")";       [[ "$v" == false ]] && printf 'SHOWLOG=%q\n' 0
  v="$(jq -r '.show_editor' <<<"$spec")";    [[ "$v" == false ]] && printf 'SHOWEDITOR=%q\n' 0
  v="$(jq -r '.show_tl' <<<"$spec")";        [[ "$v" == false ]] && printf 'SHOWTL=%q\n' 0
  v="$(jq -r '.allow_backup' <<<"$spec")";   [[ "$v" == false ]] && printf 'BACKUP=%q\n' 0
  v="$(jq -r '.allow_print' <<<"$spec")";    [[ "$v" == false ]] && printf 'PRINT=%q\n' 0
  v="$(jq -r '.score_anon' <<<"$spec")";     [[ "$v" == true ]] && printf 'SCORE_ANON=%q\n' 1
  v="$(jq -r '.manual_verdict' <<<"$spec")"; [[ "$v" == true ]] && printf 'MANUAL_VERDICT=%q\n' 1
  v="$(jq -r '.secret' <<<"$spec")";         [[ "$v" == true ]] && printf 'SECRET=%q\n' 1
  # DEMO=1 é TRAVA, não modo: nada no sistema muda de comportamento por causa dele. Ele existe
  # para o `/contest/admin/seed` (dados sintéticos) poder recusar QUALQUER contest que não seja
  # de demonstração — uma prova de verdade nunca pode ser semeada, nem por engano.
  v="$(jq -r '.demo' <<<"$spec")";           [[ "$v" == true ]] && printf 'DEMO=%q\n' 1
  # MÓDULOS (lib/modules.sh): spec.modules = {id:true} ou {id:{…seção…}} (seção presente = ligado,
  # salvo on:false). Compat com spec ANTIGO: regions/teams_meta no topo ligam `sedes`; colors liga
  # `baloes`. Ids desconhecidos são ignorados (mod_normalize).
  v="$(jq -r '[ ((.modules // {}) | to_entries[] | select(if (.value|type) == "object" then ((.value | if has("on") then .on else true end) != false) else (.value == true) end) | .key),
               (if ((.regions // []) | length) > 0 or ((.teams_meta // .teams_meta_rules // []) | length) > 0 then "sedes" else empty end),
               (if ((.colors // {}) | length) > 0 then "baloes" else empty end) ] | unique | join(",")' <<<"$spec" 2>/dev/null)"
  v="$(mod_normalize "$v")"; [[ -n "$v" ]] && printf 'CONTEST_MODULES=%q\n' "$v"
  # seções de módulo que viram VARIÁVEL de conf (o resto vira arquivo em cc_apply_modules_spec).
  # Compat: `balloons_during_freeze` no topo (idioma do settings) também vale.
  v="$(jq -r '(.modules.baloes.during_freeze // .balloons_during_freeze) == true' <<<"$spec" 2>/dev/null)"
  [[ "$v" == true ]] && printf 'BALLOONS_DURING_FREEZE=%q\n' 1
  v="$(jq -r '.modules.maquinas.site_lock.enabled == true' <<<"$spec" 2>/dev/null)"
  if [[ "$v" == true ]]; then
    printf 'SITE_LOCK=%q\n' 1
    v="$(jq -r '.modules.maquinas.site_lock.grace // empty' <<<"$spec" 2>/dev/null)"
    [[ "$v" =~ ^[0-9]+$ ]] && (( v <= 86400 )) && printf 'SITE_LOCK_GRACE=%q\n' "$v"
  fi
  v="$(jq -r '.modules.maquinas.nutella_url // ""' <<<"$spec" 2>/dev/null)"; v="${v//[$'\n\r']/}"
  [[ "$v" =~ ^https?://[A-Za-z0-9._:/-]+$ ]] && printf 'NUTELLABOOT_URL=%q\n' "$v"
  # janela de inscrição (mesmas chaves que admin/registrations grava)
  local k key
  for k in open:REG_OPEN close:REG_CLOSE late_minutes:REG_LATE_MINUTES team_max:REG_TEAM_MAX; do
    key="${k#*:}"; v="$(jq -r ".modules.inscricoes.window.${k%%:*} // empty" <<<"$spec" 2>/dev/null)"
    [[ "$v" =~ ^[0-9]+$ ]] && printf '%s=%q\n' "$key" "$v"
  done
  v="$(jq -r '.modules.inscricoes.window.teams' <<<"$spec" 2>/dev/null)";       [[ "$v" == false ]] && printf 'REG_TEAMS=%q\n' n
  v="$(jq -r '.modules.inscricoes.window.warmup_open' <<<"$spec" 2>/dev/null)"; [[ "$v" == true ]] && printf 'REG_WARMUP_OPEN=%q\n' y
  v="$(jq -r '.login_ua_substring // ""' <<<"$spec")"; v="${v//$'\n'/}"
  [[ -n "$v" ]] && printf 'LOGIN_UA_SUBSTRING=%q\n' "$v"
  v="$(jq -r '(.score_full_users // []) | map(select(type=="string" and test("^[A-Za-z0-9._@#+-]+$"))) | unique | join(" ")' <<<"$spec" 2>/dev/null)"
  [[ -n "$v" ]] && printf 'SCORE_FULL_USERS=%q\n' "$v"
  # pool de juízes do contest (hostnames do registro; mesmo formato/normalização do settings)
  v="$(jq -r '(.judges // []) | map(select(type=="string" and test("^[A-Za-z0-9._-]+$"))) | unique | join(" ")' <<<"$spec" 2>/dev/null)"
  [[ -n "$v" && "$v" != *..* ]] && printf 'CONTEST_JUDGES=%q\n' "$v"
  # penalidade ICPC: grava só o não-default (validação dura fica no cc_create, antes do staging)
  v="$(jq -r '.penalty_minutes // empty' <<<"$spec")"
  [[ "$v" =~ ^[0-9]+$ ]] && (( v != 20 )) && printf 'PENALTY_MINUTES=%q\n' "$v"
  if jq -e '(.penalty_verdicts|type)=="array"' >/dev/null 2>&1 <<<"$spec"; then
    v="$(penalty_codes_normalize "$(jq -c '.penalty_verdicts' <<<"$spec")")"
    [[ "$v" != "$PENALTY_CODES_DEFAULT" ]] && printf 'PENALTY_VERDICTS=%q\n' "$v"
  fi
  return 0
}

# cc_create <spec_json> <creator_login> <creator_name> [enun_src_dir]
# Valida tudo, monta em staging e publica com mv atômico. Sucesso -> popula CC_RESULT (JSON).
# Em erro chama fail (DEVE ser chamada direto no handler, nunca dentro de $(...)).
cc_create(){
  local spec="$1" creator="$2" cname="$3" enun="${4:-}"
  jq -e . >/dev/null 2>&1 <<<"$spec" || fail 400 "Spec JSON inválido" "bad_spec"

  local name mode start end langs priority
  name="$(jq -r '.name // ""' <<<"$spec")"
  mode="$(jq -r '.mode // "icpc"' <<<"$spec")"
  start="$(jq -r '.start // empty' <<<"$spec")"
  end="$(jq -r '.end // empty' <<<"$spec")"
  # languages: array (ids canônicos, normaliza como o settings.sh) OU string legada
  if jq -e '(.languages|type)=="array"' >/dev/null 2>&1 <<<"$spec"; then
    langs="$(jq -r '(.languages // []) | map(select(type=="string") | ascii_downcase
      | (if .=="py3" or .=="py2" then "py" else . end)
      | select(test("^[a-z0-9_+.-]+$"))) | unique | join(" ")' <<<"$spec")"
  else
    langs="$(jq -r '.languages // ""' <<<"$spec")"
  fi
  # (`showcode` do spec é IGNORADO: a opção SHOWCODE foi removida em 2026-09-18 — spec antigo segue aceito)
  # prioridade no escalonador (SEPARADA do modo/CONTEST_TYPE): super>prova>lista-privada>lista-publica
  priority="$(jq -r '.priority // "lista-publica"' <<<"$spec")"

  [[ -n "$name" ]] || fail 422 "Informe o nome do contest" "name_required"
  (( ${#name} <= 160 )) || fail 422 "Nome muito longo" "name_long"
  case "$mode" in
    icpc|obi|treino|heuristic) ;;
    outro|custom) [[ "$creator" == *.admin ]] || fail 403 "Modo '$mode' é exclusivo de admin" "mode_forbidden";;
    *) fail 422 "Modo inválido" "mode_invalid";;
  esac
  # módulo `esqueletos` EXIGE o editor embutido (lib/esqueletos.sh) — vale p/ criar, duplicar e template
  # (a condição ESPELHA o cc_settings_conf_lines: `jq -r .show_editor` == "false" desliga — booleano OU string)
  if jq -e '((.modules // {}).esqueletos) as $e | (($e == true) or ((($e | type) == "object") and ($e.on != false)))
            and ((.show_editor | tostring) == "false")' >/dev/null 2>&1 <<<"$spec"; then
    fail 422 "Esqueletos de código precisam do editor embutido: ligue o editor ou tire o módulo esqueletos" "editor_required"
  fi
  case "$priority" in
    prova|lista-privada|lista-publica) ;;
    # Super passa na frente de TODA fila (inclusive das provas dos outros): só o SUPER-ADMIN do treino (SUPERADMINS
    # no conf do treino) a dá — o `creator` aqui é a sessão do TREINO (wizard/CLI), identidade verificada
    super) superadmin_login "$creator" || fail 403 "A prioridade Super é exclusiva do super-admin do treino" "priority_forbidden";;
    *) fail 422 "Prioridade inválida" "priority_invalid";;
  esac
  [[ -z "$start" || "$start" =~ ^[0-9]+$ ]] || fail 422 "Início (start) inválido" "start_invalid"
  [[ "$end" =~ ^[0-9]+$ ]] || fail 422 "Informe o fim (end) em epoch" "end_required"
  [[ -z "$start" ]] && start="$EPOCHSECONDS"
  (( end > start )) || fail 422 "O fim deve ser depois do início" "end_before_start"
  (( end > EPOCHSECONDS )) || fail 422 "O fim deve estar no futuro" "end_in_past"
  [[ -z "$langs" || "$langs" =~ ^[A-Za-z0-9\ +._-]+$ ]] || fail 422 "Lista de linguagens inválida" "langs_invalid"
  local ua_sub; ua_sub="$(jq -r '.login_ua_substring // ""' <<<"$spec")"; ua_sub="${ua_sub//$'\n'/}"
  (( ${#ua_sub} <= 200 )) || fail 422 "login_ua_substring muito longa" "ua_long"
  local loc_in; loc_in="$(jq -r '.locale // empty' <<<"$spec")"
  [[ -z "$loc_in" ]] || contest_locale_ok "$loc_in" || fail 422 "locale inválido (pt, en ou es)" "locale_invalid"
  # FUSO da prova (o mesmo campo de Central › Regras): o assistente sempre o mostrou e a criação o JOGAVA
  # FORA calada (03/10/2026). Vazio = o padrão da instalação; nome antigo vira o atual (tz_canon).
  local tz_in="" tz_raw; tz_raw="$(jq -r '.tz // empty' <<<"$spec")"
  if [[ -n "$tz_raw" ]]; then tz_in="$(tz_canon "$tz_raw")" || fail 422 "fuso horário desconhecido (ex.: America/Santiago)" "tz_invalid"; fi
  # penalidade do placar ICPC (opcional; só válida em conjunto — a gravação fica no conf_lines)
  local pmin; pmin="$(jq -r '.penalty_minutes // empty' <<<"$spec")"
  if [[ -n "$pmin" ]]; then
    { [[ "$pmin" =~ ^[0-9]+$ ]] && (( pmin <= 100000 )); } || fail 422 "penalty_minutes inválido" "penalty_minutes_invalid"
  fi
  if jq -e 'has("penalty_verdicts")' >/dev/null 2>&1 <<<"$spec"; then
    penalty_codes_normalize "$(jq -c '.penalty_verdicts' <<<"$spec")" >/dev/null \
      || fail 422 "penalty_verdicts inválido (use wa/tle/mle/rte/ce)" "penalty_verdicts_invalid"
  fi

  local id; id="$(jq -r '.id // ""' <<<"$spec")"
  if [[ -z "$id" ]]; then
    id="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed -E 's/^-+|-+$//g')"
    [[ -n "$id" ]] || id="contest"; id="${id:0:48}"; id="$(printf '%s' "$id" | sed -E 's/-+$//')"
  fi
  [[ "$id" =~ ^[a-z0-9][a-z0-9._-]{1,48}$ ]] || fail 422 "id inválido (use a-z, 0-9, . _ -)" "id_invalid"
  case "$id" in treino|admin|api|www|status|docs|shared|index|new|old|run|server|web) fail 409 "id reservado" "id_reserved";; esac
  # ids `icpc*` são da organização da Maratona: só SUPER-ADMIN cria (decisão do Ribas, 2026-09-15);
  # vale p/ create, duplicate e todo caminho que passa por aqui (o creator é quem pede)
  [[ "$id" == icpc* ]] && ! superadmin_login "$creator" && fail 403 "ids que começam por 'icpc' são da organização — peça a um super-admin" "id_prefix_reserved"
  [[ -e "$CONTESTSDIR/$id" ]] && fail 409 "Já existe um contest com o id '$id'" "id_taken"

  local np allow_empty
  np="$(jq '(.problems // []) | length' <<<"$spec")"; [[ "$np" =~ ^[0-9]+$ ]] || np=0
  allow_empty="$(jq -r 'if .allow_empty==true then 1 else 0 end' <<<"$spec")"
  if (( np < 1 )) && [[ "$allow_empty" != 1 ]]; then fail 422 "Inclua ao menos um problema (ou marque criar vazio)" "no_problems"; fi
  (( np <= 200 )) || fail 422 "Máximo de 200 problemas" "too_many"
  local ldup; ldup="$(cc_letters_dup "$(jq -c '.problems // []' <<<"$spec")")"
  [[ -z "$ldup" ]] || fail 422 "Letra de problema repetida: $ldup" "letter_dup"

  local stg="$CONTESTSDIR/.staging-$id-${BASHPID}-$RANDOM"
  rm -rf "$stg"
  mkdir -p "$stg"/{users,enunciados,var} || fail 500 "Falha ao preparar diretório" "mkdir_fail"

  local probs="PROBS=(" i=0
  local lused; lused="$(cc_letters_used "$(jq -c '.problems // []' <<<"$spec")")"
  # idioma do nome padrão: o conf ainda não existe e a criação não grava STATEMENT_LANGS (automático) ⇒ LOCALE
  local plang; plang="$(cc_prob_lang "" "$(jq -r '.locale // "pt"' <<<"$spec")")"
  local p pid src pname letter bankid stmt_b64 stmt_file skey bf html
  local pdf_b64 pdf_file larr plangs='{}' jarr pjudges='{}'
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    pid="$(jq -r '.problem_id // ""' <<<"$p")"
    bankid="$(jq -r '.bank_id // ""' <<<"$p")"
    [[ -z "$pid" && -n "$bankid" ]] && pid="${bankid//#//}"
    pid="${pid//\//#}"   # id canônico 'coleção#problema' (igual ao treino; '#' é o que o juiz exige)
    src="$(jq -r '.source // "cdmoj"' <<<"$p")"
    pname="$(jq -r '.name // .title // ""' <<<"$p")"
    letter="$(jq -r '.letter // ""' <<<"$p")"
    stmt_b64="$(jq -r '.statement_b64 // ""' <<<"$p")"
    stmt_file="$(jq -r '.statement_file // ""' <<<"$p")"
    pdf_b64="$(jq -r '.statement_pdf_b64 // ""' <<<"$p")"
    pdf_file="$(jq -r '.statement_pdf_file // ""' <<<"$p")"
    [[ -n "$pid" ]] || { rm -rf "$stg"; fail 422 "Problema sem id" "prob_no_id"; }
    # sem `name`/`title` no spec: o TÍTULO do banco no idioma da prova, nunca o id cru (cc_prob_title)
    [[ -n "$pname" ]] || pname="$(cc_prob_title "${bankid:-${pid//\//#}}" "$pid" "$plang")"
    { [[ "$pid" =~ ^[A-Za-z0-9._/#@+-]+$ ]] && [[ "$pid" != *..* ]]; } || { rm -rf "$stg"; fail 422 "id de problema inválido: $pid" "prob_id_invalid"; }
    [[ "$src" =~ ^[A-Za-z0-9._-]+$ ]] || { rm -rf "$stg"; fail 422 "source de problema inválido" "src_invalid"; }
    (( ${#pname} <= 160 )) || { rm -rf "$stg"; fail 422 "nome de problema muito longo" "pname_long"; }
    [[ -n "$letter" ]] || cc_letter_next lused letter || letter="$((i+1))"
    [[ "$letter" =~ ^[A-Za-z0-9]{1,3}$ ]] || { rm -rf "$stg"; fail 422 "letra inválida" "letter_invalid"; }
    skey="${pid//\//#}"
    { [[ "$skey" =~ ^[A-Za-z0-9._#@+-]+$ ]] && [[ "$skey" != *..* ]]; } || { rm -rf "$stg"; fail 422 "chave de enunciado inválida" "skey_invalid"; }
    html=""
    if [[ -n "$stmt_b64" ]]; then
      html="$(printf '%s' "$stmt_b64" | base64 -d 2>/dev/null)" || { rm -rf "$stg"; fail 422 "statement_b64 inválido" "stmt_b64"; }
    elif [[ -n "$enun" && -n "$stmt_file" ]]; then
      { [[ "$stmt_file" =~ ^[A-Za-z0-9._#@+-]+$ ]] && [[ -f "$enun/$stmt_file" ]]; } || { rm -rf "$stg"; fail 422 "enunciado não encontrado: $stmt_file" "stmt_file"; }
      html="$(cat "$enun/$stmt_file")"
    elif [[ -n "$bankid" ]]; then
      bf="$CONTESTSDIR/treino/var/jsons/$bankid.json"; [[ -f "$bf" ]] || bf="$CONTESTSDIR/treino/var/jsons-private/$bankid.json"
      [[ -f "$bf" ]] && html="$(jq -r '.statement_html_b64 // ""' "$bf" 2>/dev/null | base64 -d 2>/dev/null)"
    else
      bf="$CONTESTSDIR/treino/var/jsons/$skey.json"; [[ -f "$bf" ]] || bf="$CONTESTSDIR/treino/var/jsons-private/$skey.json"
      [[ -f "$bf" ]] && html="$(jq -r '.statement_html_b64 // ""' "$bf" 2>/dev/null | base64 -d 2>/dev/null)"
    fi
    [[ -n "$html" ]] && printf '%s' "$html" > "$stg/enunciados/$skey.html"
    # traduções do banco (statements{<lang>}) -> enunciados/<skey>.<lang>.html (lib/contest-statement.sh)
    if [[ -z "$stmt_b64" && -z "$stmt_file" ]] && bf="$(cs_bank_json "${bankid:-$skey}")"; then cs_bank_write "$bf" "$stg" "$skey" langs; fi
    # PDF opcional do enunciado (espelha o admin: enunciados/<skey>.pdf)
    if [[ -n "$pdf_b64" ]]; then
      printf '%s' "$pdf_b64" | base64 -d > "$stg/enunciados/$skey.pdf" 2>/dev/null \
        || { rm -rf "$stg"; fail 422 "statement_pdf_b64 inválido" "stmt_pdf_b64"; }
    elif [[ -n "$enun" && -n "$pdf_file" ]]; then
      { [[ "$pdf_file" =~ ^[A-Za-z0-9._#@+-]+$ ]] && [[ -f "$enun/$pdf_file" ]]; } \
        || { rm -rf "$stg"; fail 422 "PDF não encontrado: $pdf_file" "stmt_pdf_file"; }
      cp "$enun/$pdf_file" "$stg/enunciados/$skey.pdf"
    fi
    # linguagens POR problema (mesmo formato/normalização do admin problem-langs.json)
    larr="$(jq -c '(.languages // []) | map(select(type=="string") | ascii_downcase
      | (if .=="py3" or .=="py2" then "py" else . end)
      | select(test("^[a-z0-9_+.-]+$"))) | unique' <<<"$p" 2>/dev/null)"
    [[ -n "$larr" && "$larr" != "[]" ]] && plangs="$(jq -c --arg id "$skey" --argjson v "$larr" '.[$id]=$v' <<<"$plangs")"
    # pool de juízes POR problema (mesmo formato/normalização do admin problem-judges.json)
    jarr="$(jq -c '(.judges // []) | map(select(type=="string") | select(test("^[A-Za-z0-9._-]+$"))) | unique' <<<"$p" 2>/dev/null)"
    [[ -n "$jarr" && "$jarr" != "[]" && "$jarr" != *..* ]] && pjudges="$(jq -c --arg id "$skey" --argjson v "$jarr" '.[$id]=$v' <<<"$pjudges")"
    probs+=" $(printf '%q' "$src") $(printf '%q' "$pid") $(printf '%q' "$pname") $(printf '%q' "$letter") $(printf '%q' "$skey")"
    ((i++))
  done < <(jq -c '.problems[]?' <<<"$spec")
  probs+=" )"
  [[ "$plangs" != "{}" ]] && printf '%s' "$plangs" > "$stg/problem-langs.json"
  [[ "$pjudges" != "{}" ]] && printf '%s' "$pjudges" > "$stg/problem-judges.json"

  [[ -n "$cname" ]] || cname="$creator"

  # --- admin do contest ---
  # NÃO sobrescrever conta admin já existente:
  #  [a] senha digitada (sa_pass)         -> usa exatamente essa (autoritativo);
  #  [b][c] senha vazia + login já existe na fonte compartilhada (USERS_FROM)
  #         -> REUSA a conta existente (login pelo fallback verify_password->USERS_FROM),
  #            sem gravar admin local e sem gerar/trocar senha;
  #  senha vazia + login inexistente     -> gera senha e grava (padrão).
  local sa_login sa_pass sa_name adminlogin adminpass adminname
  local users_from shared="" admin_reused=false admin_local=true
  sa_login="$(jq -r '.admin.login // ""' <<<"$spec")"
  sa_pass="$(jq -r '.admin.password // ""' <<<"$spec")"
  sa_name="$(jq -r '.admin.fullname // ""' <<<"$spec")"
  users_from="$(jq -r '.users_from // ""' <<<"$spec")"
  adminlogin="${sa_login:-$creator}"; [[ "$adminlogin" == *.admin ]] || adminlogin="${adminlogin}.admin"
  valid_id "$adminlogin" || { rm -rf "$stg"; fail 422 "login de admin inválido" "admin_login_invalid"; }
  adminname="${sa_name:-$cname}"

  # a conta admin já existe na fonte compartilhada? (users/<login>/account.json)
  local shared_has_admin=false
  if [[ -n "$users_from" && -f "$CONTESTSDIR/$users_from/users/$adminlogin/account.json" ]]; then
    shared_has_admin=true
  fi
  if [[ -n "$sa_pass" ]]; then
    adminpass="$sa_pass"                         # [a] senha digitada -> autoritativa
  elif [[ "$shared_has_admin" == true ]]; then
    # [b][c] reusa — mas SÓ o `.admin` do PRÓPRIO criador (28/09/2026). Antes qualquer `.admin` do treino
    # servia: indicar o de outro professor, sem senha, dava a ele a administração do contest. O admin
    # reusado fica gravado em SHARED_ADMIN: é o único papel do treino que a auth deixa entrar num contest
    # compartilhado (além dos SUPERADMINS) — ver _shared_role_ok em lib/auth.sh.
    [[ "$adminlogin" == "${creator%.admin}.admin" ]] \
      || { rm -rf "$stg"; fail 422 "Esse login .admin é de outra conta do treino — informe uma senha (cria uma conta local do contest)" "admin_login_foreign"; }
    admin_reused=true; admin_local=false; adminpass=""
  else
    adminpass="$(cc_genpass)"                     # padrão: gera
  fi
  case "$adminpass$adminname" in *:*) rm -rf "$stg"; fail 422 "senha/nome do admin não podem conter ':'" "colon";; esac

  # --- usuários: compartilhados (USERS_FROM) ou específicos do contest ---
  # _cc_stage_user <stg> <login> <pass> <fullname> [email] [team-json] — conta no store
  # (users/<login>/). team-json = objeto `.team` já saneado (team_fields_json); '{}' = sem time.
  _cc_stage_user(){
    local d="$1/users/$2" tm="${6:-}"
    [[ -n "$tm" ]] || tm='{}'
    mkdir -p "$d/submissions" "$d/mojlog" "$d/results" || return 1
    jq -cn --arg l "$2" --arg p "$3" --arg n "$4" --arg e "${5:-}" --argjson t "$EPOCHSECONDS" \
      --argjson tm "$tm" \
      '{login:$l,password:$p,fullname:$n,email:$e,created_at:$t,updated_at:$t,status:"active",uname_changes:[]}
       + (if ($tm|length) > 0 then {team:$tm} else {} end)' \
      > "$d/account.json" || return 1
    [[ -f "$d/history" ]] || : > "$d/history"
  }
  declare -a CREDS
  if [[ "$admin_local" == true ]]; then
    _cc_stage_user "$stg" "$adminlogin" "$adminpass" "$adminname" \
      || { rm -rf "$stg"; fail 500 "Falha ao criar a conta do admin" "mkdir_fail"; }
    CREDS+=("$(jq -cn --arg l "$adminlogin" --arg p "$adminpass" --arg n "$adminname" '{login:$l,password:$p,fullname:$n,role:"admin"}')")
  fi
  if [[ -n "$users_from" ]]; then
    { valid_id "$users_from" && [[ -d "$CONTESTSDIR/$users_from/users" ]]; } || { rm -rf "$stg"; fail 422 "users_from inválido" "users_from_invalid"; }
    shared="$users_from"
  else
    local nu; nu="$(jq '(.users // []) | length' <<<"$spec")"
    (( nu <= 5000 )) || { rm -rf "$stg"; fail 422 "Máximo de 5000 usuários" "too_many_users"; }
    local u ul up un ue
    while IFS= read -r u; do
      [[ -n "$u" ]] || continue
      ul="$(jq -r '.login // ""' <<<"$u")"; up="$(jq -r '.password // ""' <<<"$u")"
      un="$(jq -r '.fullname // ""' <<<"$u")"; ue="$(jq -r '.email // ""' <<<"$u")"
      [[ -n "$ul" ]] || continue
      valid_id "$ul" || { rm -rf "$stg"; fail 422 "login de usuário inválido: $ul" "user_login_invalid"; }
      [[ "$ul" == "$adminlogin" ]] && continue
      [[ -z "$up" ]] && up="$(cc_genpass)"; [[ -z "$un" ]] && un="$ul"
      case "$up$un$ue" in *:*) rm -rf "$stg"; fail 422 "campos de usuário não podem conter ':'" "user_colon";; esac
      _cc_stage_user "$stg" "$ul" "$up" "$un" "$ue" "$(team_fields_json "$u")" \
        || { rm -rf "$stg"; fail 500 "Falha ao criar usuário" "mkdir_fail"; }
      CREDS+=("$(jq -cn --arg l "$ul" --arg p "$up" --arg n "$un" '{login:$l,password:$p,fullname:$n,role:"user"}')")
    done < <(jq -c '(.users // [])[]' <<<"$spec")
  fi

  # campos "basic" opcionais
  local b_locale b_lstart b_lenabled b_freeze
  b_locale="$(jq -r '.locale // empty' <<<"$spec")"
  b_lstart="$(jq -r '.login_start // empty' <<<"$spec")"
  b_lenabled="$(jq -r 'if .login_enabled==false then "n" else "" end' <<<"$spec")"
  b_freeze="$(jq -r '.freeze // empty' <<<"$spec")"

  {
    printf 'CONTEST_ID=%q\n'    "$id"
    printf 'CONTEST_NAME=%q\n'  "$name"
    printf 'CONTEST_TYPE=%q\n'  "$mode"
    printf 'CONTEST_PRIORITY=%q\n' "$priority"
    printf 'CONTEST_START=%q\n' "$start"
    printf 'CONTEST_END=%q\n'   "$end"
    printf '%s\n' "$probs"
    [[ -n "$langs" ]] && printf 'LANGUAGES=%q\n' "$langs"
    [[ -n "$shared" ]] && printf 'USERS_FROM=%q\n' "$shared"
    [[ -n "$shared" && "$admin_reused" == true ]] && printf 'SHARED_ADMIN=%q\n' "$adminlogin"
    [[ -n "$b_locale" ]] && contest_locale_ok "$b_locale" && printf 'LOCALE=%q\n' "$b_locale"
    [[ -n "$tz_in" ]] && printf 'CONTEST_TZ=%q\n' "$tz_in"
    [[ "$b_lstart" =~ ^[0-9]+$ ]] && printf 'LOGIN_START_TIME=%q\n' "$b_lstart"
    [[ "$b_lenabled" == n ]] && printf 'LOGIN_ENABLED=%q\n' "n"
    [[ "$b_freeze" =~ ^[0-9]+$ ]] && printf 'FREEZE_TIME=%q\n' "$b_freeze"
    cc_settings_conf_lines "$spec"
  } > "$stg/conf"
  printf '%s\n' "$creator" > "$stg/owner"
  printf '%s\t%s\t%s\n' "$creator" "$EPOCHSECONDS" "$mode" > "$stg/created-by"

  # configs visuais opcionais (mesmo formato que o placar lê; reeditáveis depois pelo admin do contest)
  # (spec UNIFICADO: a seção do módulo vence; `colors/regions/teams_meta` no topo = compat com
  # templates/exports antigos e com o spec sem módulos)
  local colors_j regions_j teams_j
  colors_j="$(jq -c '.modules.baloes.colors // .colors // empty' <<<"$spec" 2>/dev/null)"
  regions_j="$(jq -c '.modules.sedes.regions // .regions // empty' <<<"$spec" 2>/dev/null)"
  teams_j="$(jq -c '.modules.sedes.teams_meta // .teams_meta // empty' <<<"$spec" 2>/dev/null)"
  [[ -n "$colors_j"  && "$colors_j"  != null ]] && printf '%s' "$colors_j"  > "$stg/balloons.json"
  if [[ -n "$regions_j" && "$regions_j" != null ]]; then
    cc_regions_ok "$regions_j" || { rm -rf "$stg"; cc_regions_fail; }
    printf '%s' "$regions_j" > "$stg/regions.json"
  fi
  [[ -n "$teams_j"   && "$teams_j"   != null ]] && jq -cn --argjson r "$teams_j" '{rules:$r}' > "$stg/teams-meta.json"
  cc_apply_modules_spec "$spec" "$stg" "$creator" || { rm -rf "$stg"; fail 422 "Seção de módulo inválida no spec (${CC_MOD_ERR:-modules})" "modules_spec_invalid"; }

  mv -T "$stg" "$CONTESTSDIR/$id" 2>/dev/null || { rm -rf "$stg"; fail 500 "Falha ao publicar o contest (id pode ter sido criado em paralelo)" "publish_fail"; }

  # a prioridade de nascimento entra na trilha (o contest e a central do treino) — as mudanças depois também
  # entram (cc_set_priority), então "quem pôs esta prova nesta banda" sempre tem resposta
  audit_log_to "$id" priority "de=— para=$priority via=criação"
  audit_log_to treino contest-priority "contest=$id de=— para=$priority via=criação"

  # CREDS pode estar VAZIO (admin reutilizado em modo compartilhado): teste/expansão set -u safe.
  local users_json='[]'
  [[ -n "${CREDS[@]+x}" ]] && users_json="$(printf '%s\n' "${CREDS[@]}" | jq -cs '.')"
  CC_RESULT="$(jq -cn --arg id "$id" --arg al "$adminlogin" --arg pw "$adminpass" --argjson np "$np" \
    --argjson users "$users_json" --arg shared "$shared" --argjson reused "$admin_reused" \
    '{contest_id:$id, admin_login:$al, admin_reused:$reused,
      admin_password:(if $reused then null else $pw end), problems:$np,
      users_from:(if $shared=="" then null else $shared end),
      users:$users, users_count:($users|length),
      url:("/contest/?c="+$id), scoreboard_url:("/contest/score/?c="+$id)}')"
}

# --- SPEC UNIFICADO: seção `modules` ------------------------------------------------------------
# spec.modules = { <id>: true | {on?:bool, …dados reeditáveis do módulo…} }. A presença da seção
# liga o módulo (salvo on:false); os DADOS são gravados pelos MESMOS arquivos que os painéis
# editam depois. Segredos (chave do nutellaboot, chaves do webcast) NUNCA entram no spec — o
# export não os emite e o create não os aceita. Formato por módulo (export ⇄ create):
#   sedes         {regions:[…], teams_meta:[{regex,country,school,school_full}], time_overrides:[…]}
#   baloes        {colors:{A:"RRGGBB",…}, during_freeze:bool}
#   coortes       {cohorts:[{id,name,regex,public,unranked,ranking,default,sees}]}
#   maquinas      {ua_gate:{…ug_get…}, site_lock:{enabled,grace}, nutella_url}
#   rodadas       {active:slug, rounds:[{slug,name,kind,start,end,freeze,problems,colors?,state}]}  (arquivadas nunca;
#                 colors = cores de balão da rodada, formato do balloons.json)
#   documentos    {config:{caderno_version,cover_note,errata}}                (published: nunca)
#   inscricoes    {enabled:bool, window:{open,close,late_minutes,team_max,teams,warmup_open}}
#   telao         {views:[{view,label}]}   (create gera CHAVES NOVAS p/ cada view)
#   classificacao {algorithm, config:{…regras/vagas…}}          (1 estágio, o padrão do motor; draft, sem times)
#                 | {stages:[{id?, algorithm, config, name?, venue?, when?, chip?}]}   (vários; id padrão = o do
#                 motor no catálogo). Motor pela allowlist + config pelo `--check` do motor (lib/classify.sh);
#                 resultado, overrides e status nunca entram (é dado da prova, não configuração)
#   esqueletos    {langs:{<lang>:{mode:"custom",code}|{mode:"off"}}}   (padrão = ausente; exige show_editor)
# cc_apply_modules_spec <spec> <stg> <creator> — grava as seções em ARQUIVO no staging. rc 1 +
# CC_MOD_ERR quando uma seção tem o tipo errado (o chamador vira 422 modules_spec_invalid).
cc_apply_modules_spec(){
  local spec="$1" stg="$2" creator="$3" v
  CC_MOD_ERR=""
  jq -e '(.modules // {}) | type == "object"' >/dev/null 2>&1 <<<"$spec" || { CC_MOD_ERR="modules não é objeto"; return 1; }
  jq -e '(.modules // {}) | all(.[]; type == "boolean" or type == "object")' >/dev/null 2>&1 <<<"$spec" \
    || { CC_MOD_ERR="cada módulo é true/false ou objeto {on?, …seção…}"; return 1; }
  # id de módulo desconhecido = 422 (o admin/modules já recusava; aqui era descartado em silêncio)
  local _mid
  for _mid in $(jq -r '(.modules // {}) | keys[]' <<<"$spec" 2>/dev/null); do
    mod_valid "$_mid" || { CC_MOD_ERR="módulo desconhecido: $_mid"; return 1; }
  done
  # cada seção: (caminho jq, tipo esperado, destino). Seção de módulo com `on:false` é IGNORADA
  # (senão nascia dado com o módulo desligado — aviso eterno do preflight).
  _sec(){ # <jq-path> <tipo> -> ecoa o valor compacto ou vazio; rc 1 se tipo errado
    local val mod; mod="$(cut -d. -f3 <<<"$1")"
    [[ "$(jq -r --arg m "$mod" '.modules[$m].on // "" | tostring' <<<"$spec" 2>/dev/null)" == false ]] && return 0
    val="$(jq -c "$1 // empty" <<<"$spec" 2>/dev/null)"
    [[ -n "$val" ]] || return 0
    jq -e "type == \"$2\"" >/dev/null 2>&1 <<<"$val" || { CC_MOD_ERR="$1 deve ser $2"; return 1; }
    printf '%s' "$val"
  }
  # regex tem de COMPILAR (regra quebrada é engolida por try/catch nos gates = regra muda) e
  # caber em 200 chars — a MESMA régua dos painéis (cohorts/time-overrides/ua-gate)
  _rx_all(){ # <jq-filter que lista as regex> <rótulo>
    local rx
    while IFS= read -r rx; do
      [[ -z "$rx" ]] && continue
      (( ${#rx} <= 200 )) || { CC_MOD_ERR="$2: regex longa demais"; return 1; }
      jq -n --arg r "$rx" '"x" | test($r)' >/dev/null 2>&1 || { CC_MOD_ERR="$2: regex inválida: $rx"; return 1; }
    done < <(jq -r "$1" <<<"$spec" 2>/dev/null)
    return 0
  }
  # sedes.time_overrides -> time-overrides.json (regras {regex,end,reason}; ≤50 regras)
  v="$(_sec '.modules.sedes.time_overrides' array)" || return 1
  if [[ -n "$v" ]]; then
    (( $(jq 'length' <<<"$v") <= 50 )) || { CC_MOD_ERR="sedes.time_overrides: máximo de 50 regras"; return 1; }
    _rx_all '.modules.sedes.time_overrides[]? | .regex // empty' 'sedes.time_overrides' || return 1
    jq -c '[ .[] | select(type=="object" and (.regex // "") != "" and ((.end|tonumber?) // 0) > 0) | {regex, end:(.end|tonumber), reason:((.reason // "")|tostring)} ]' <<<"$v" > "$stg/time-overrides.json"
  fi
  # coortes.cohorts -> cohorts.json (normalizado como ch_get lê; id e regex validados como o painel)
  v="$(_sec '.modules.coortes.cohorts' array)" || return 1
  if [[ -n "$v" ]]; then
    jq -e 'all(.[]; type=="object" and ((.id // "") | test("^[a-z0-9][a-z0-9_-]{0,23}$")))' >/dev/null 2>&1 <<<"$v" \
      || { CC_MOD_ERR="coortes.cohorts: id inválido (minúsculas/dígitos/_-, até 24)"; return 1; }
    _rx_all '.modules.coortes.cohorts[]? | .regex // empty' 'coortes.cohorts' || return 1
    jq -c '{version:1, results_released:false,
      cohorts:[ .[] | select(type=="object" and (.id // "") != "") | {id, name:(.name // .id), regex:(.regex // ""),
        public:(.public != false), unranked:(.unranked == true), ranking:(.ranking == true), default:(.default == true), sees:(.sees // [])} ]}' <<<"$v" > "$stg/cohorts.json"
  fi
  # maquinas.ua_gate -> ua-gate.json (ug_get normaliza na leitura; as regex têm de compilar)
  v="$(_sec '.modules.maquinas.ua_gate' object)" || return 1
  if [[ -n "$v" ]]; then
    _rx_all '.modules.maquinas.ua_gate | ((.by_regex // [])[]? | .regex // empty), (.from_login // empty), ((.by_region // {}) | .. | strings? | select(startswith("~")) | .[1:])' 'maquinas.ua_gate' || return 1
    printf '%s\n' "$v" > "$stg/ua-gate.json"
  fi
  # rodadas -> rounds.json (o PLANO; rd_sync_active espelha a ativa do conf na 1ª leitura).
  # Mesma validação do admin/rounds: epochs, fim > início, freeze 0 ou na janela, kind da lista.
  v="$(_sec '.modules.rodadas.rounds' array)" || return 1
  if [[ -n "$v" ]]; then
    jq -e 'all(.[]; type=="object"
      and ((.slug // "") | test("^[a-z0-9][a-z0-9_-]{0,31}$"))
      and ((.start // 0) | type == "number" and . >= 0) and ((.end // 0) | type == "number" and . >= 0)
      and ((.end // 0) > (.start // 0))
      and ((.freeze // 0) | type == "number") and ((.freeze // 0) == 0 or ((.freeze // 0) > (.start // 0) and (.freeze // 0) < (.end // 0)))
      and ((.kind // "official") | IN("warmup","official","extra")))' >/dev/null 2>&1 <<<"$v" \
      || { CC_MOD_ERR="rodadas.rounds: slug (minúsculas), start/end em epoch com fim > início, freeze 0 ou dentro da janela, kind warmup|official|extra"; return 1; }
    (( $(jq 'length' <<<"$v") <= 50 )) || { CC_MOD_ERR="rodadas.rounds: máximo de 50 rodadas"; return 1; }
    # letra repetida numa rodada (sem diferenciar caixa) — a mesma regra de cc_letters_dup
    local rdup; rdup="$(jq -r '[ .[] | (.slug // "") as $s
        | ((.problems // []) | [ .[]? | objects | (.letter // "") | tostring | ascii_upcase | select(length > 0) ]
           | group_by(.) | map(select(length > 1) | .[0])) as $d
        | select(($d | length) > 0) | "\($s): \($d | join(" "))" ] | join("; ")' <<<"$v" 2>/dev/null)"
    [[ -z "$rdup" ]] || { CC_MOD_ERR="rodadas.rounds: letra de problema repetida ($rdup)"; return 1; }
    local act; act="$(jq -r '.modules.rodadas.active // ""' <<<"$spec")"
    jq -c --arg a "$act" '{version:1, active:$a,
      rounds:[ .[] | select(type=="object" and ((.slug // "") | test("^[a-z0-9][a-z0-9_-]{0,31}$")) and .state != "archived")
               | del(.archived, .archived_at) | . + {state:(if .slug == $a then "active" else (.state // "pending") end)} ]}' <<<"$v" > "$stg/rounds.json"
  fi
  # documentos.config -> docs/config.json (published sempre vazio: publicação é estado do evento)
  v="$(_sec '.modules.documentos.config' object)" || return 1
  if [[ -n "$v" ]]; then
    mkdir -p "$stg/docs"
    jq -c '{caderno_version:((.caderno_version // "v1.0")|tostring), cover_note:((.cover_note // "")|tostring), errata:((.errata // "")|tostring), published:[]}' <<<"$v" > "$stg/docs/config.json"
  fi
  # inscricoes.enabled -> registrations.json vazio (existir = ligado, doutrina do cohorts.json)
  v="$(jq -r '.modules.inscricoes.enabled == true' <<<"$spec" 2>/dev/null)"
  [[ "$v" == true ]] && printf '{"version":1,"teams":{},"entries":{}}\n' > "$stg/registrations.json"
  # telao.views -> webcast.json com CHAVES NOVAS (uma por view; a chave antiga nunca viaja)
  v="$(_sec '.modules.telao.views' array)" || return 1
  if [[ -n "$v" ]]; then
    declare -F wc_newkey >/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/webcast.sh"   # não está no prelúdio
    # só visão que vai EXISTIR: `public` ou uma coorte do MESMO spec com placar próprio (ranking)
    # ou privada — a mesma régua do webcast create (ch_views); chave p/ placar inexistente não nasce
    local okviews; okviews="$(jq -r '["public"] + [ (.modules.coortes.cohorts // [])[]? | select(type=="object" and ((.public == false) or (.ranking == true))) | .id // empty ] | .[]' <<<"$spec" 2>/dev/null)"
    local keys='[]' vw lb k
    while IFS=$'\t' read -r vw lb; do
      [[ -n "$vw" ]] || continue
      grep -qxF "$vw" <<<"$okviews" || { CC_MOD_ERR="telao.views: visão inexistente: $vw"; return 1; }
      k="$(wc_newkey)"
      keys="$(jq -c --arg k "$k" --arg v "$vw" --arg l "$lb" --arg by "$creator" --argjson t "$EPOCHSECONDS" \
        '. + [{id:($k[6:14]), key:$k, view:$v, label:$l, created_by:$by, created_at:$t, revoked_at:0, fetches:0, last_at:0, last_ip:""}]' <<<"$keys")"
    done < <(jq -r '.[] | select(type=="object") | [(.view // "public"), (.label // "")] | @tsv' <<<"$v")
    ( umask 077; jq -cn --argjson k "$keys" '{version:1, keys:$k}' > "$stg/webcast.json" )
  fi
  # esqueletos.langs -> esqueletos.json (lib/esqueletos.sh: só modos válidos, código até o teto). O texto do
  # admin anda por stdin, nunca por argv (ARG_MAX: até ESQ_MAX_BYTES por linguagem)
  v="$(_sec '.modules.esqueletos.langs' object)" || return 1
  if [[ -n "$v" ]]; then
    jq -e --argjson max "${ESQ_MAX_BYTES:-65536}" 'to_entries | all(.[]; (.key | test("^[a-z0-9]{1,16}$"))
        and ((.value.mode == "off") or (.value.mode == "custom" and (.value.code | type) == "string"
             and ((.value.code | utf8bytelength) <= $max))))' >/dev/null 2>&1 <<<"$v" \
      || { CC_MOD_ERR="esqueletos.langs: cada linguagem é {mode:\"custom\",code} ou {mode:\"off\"} (código até ${ESQ_MAX_BYTES:-65536} bytes)"; return 1; }
    jq -c 'if length > 0 then {langs: (with_entries(.value |= (if .mode == "off" then {mode:"off"} else {mode:"custom", code:.code} end)))} else empty end' <<<"$v" > "$stg/esqueletos.json"
    [[ -s "$stg/esqueletos.json" ]] || rm -f "$stg/esqueletos.json"
  fi
  # classificacao -> classification.json com os estágios em RASCUNHO (config, sem times). Formato antigo
  # {algorithm, config} = um estágio só; {stages:[…]} = vários (o export devolve assim quando há mais de um)
  local vc vs
  vc="$(_sec '.modules.classificacao.config' object)" || return 1
  vs="$(_sec '.modules.classificacao.stages' array)" || return 1
  if [[ -n "$vc" || -n "$vs" ]]; then
    declare -F cl_check >/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/classify.sh"
    local cst="$stg/.cl-spec.json" cf="$stg/.cl-cfg.json" sid alg i n
    # a config da PDA traz tabelas (ciclo, aliases de escola): tudo por ARQUIVO, nunca pelo argv do jq
    if [[ -n "$vs" ]]; then jq -c '.modules.classificacao.stages' <<<"$spec" > "$cst"
    else jq -c '.modules.classificacao | [{algorithm:(.algorithm // .config.algorithm // "sbc-fase1"), config:.config}]' <<<"$spec" > "$cst"; fi
    jq -e 'length > 0 and length <= 8 and all(.[]; type == "object" and ((.config // {}) | type) == "object")' "$cst" >/dev/null 2>&1 \
      || { CC_MOD_ERR="classificacao.stages: lista (1 a 8) de {id?, algorithm, config}"; return 1; }
    n="$(jq 'length' "$cst")"
    printf '[]' > "$stg/.cl-stages.json"
    for (( i=0; i<n; i++ )); do
      alg="$(jq -r --argjson i "$i" '.[$i] | .algorithm // .config.algorithm // "sbc-fase1"' "$cst")"
      cl_engine "$alg" >/dev/null || { CC_MOD_ERR="classificacao: algoritmo desconhecido: $alg"; return 1; }
      sid="$(jq -r --argjson i "$i" '.[$i].id // ""' "$cst")"; [[ -n "$sid" ]] || sid="$(cl_stage_default "$alg")"
      [[ "$sid" =~ ^[a-z0-9-]{1,32}$ ]] || { CC_MOD_ERR="classificacao: id de estágio inválido: $sid"; return 1; }
      jq -e --arg s "$sid" 'any(.[]; .id == $s) | not' "$stg/.cl-stages.json" >/dev/null || { CC_MOD_ERR="classificacao: estágio repetido: $sid"; return 1; }
      jq -c --argjson i "$i" --arg a "$alg" '.[$i] | (.config // {}) + {algorithm:$a} | del(.preassigned)' "$cst" > "$cf"
      cl_check "$alg" "$cf" || { CC_MOD_ERR="classificacao ($sid): $(jq -r 'join("; ")' <<<"$CL_CHECK_ERRORS" | head -c 300)"; return 1; }
      jq -c --argjson i "$i" --arg s "$sid" --slurpfile c "$cf" --slurpfile st "$cst" \
        '. + [ {id:$s, status:"draft", teams:{}, config:$c[0]}
               + ($st[0][$i] | {name, venue, when, chip} | with_entries(select((.value | type) == "string" and .value != ""))) ]' \
        "$stg/.cl-stages.json" > "$stg/.cl-stages.tmp" && mv -f "$stg/.cl-stages.tmp" "$stg/.cl-stages.json"
    done
    jq -c '{version:1, stages:.}' "$stg/.cl-stages.json" > "$stg/classification.json"
    rm -f "$cf" "$cst" "$stg/.cl-stages.json"
  fi
  return 0
}

# cc_modules_spec <cid> -> objeto `modules` do spec (só módulos LIGADOS; dados reeditáveis; sem
# segredo). Lê os arquivos direto (as libs normalizam na leitura; aqui basta o que é reeditável).
cc_modules_spec(){
  local cid="$1" cdir="$CONTESTSDIR/$1" out='{}' m sec
  local mods; mods="$(mod_raw "$cid")"
  [[ -n "$mods" ]] || { printf '{}'; return 0; }
  for m in ${mods//,/ }; do
    sec='{"on":true}'
    case "$m" in
      sedes)
        [[ -s "$cdir/regions.json" ]] && jq -e 'type=="array"' "$cdir/regions.json" >/dev/null 2>&1 \
          && sec="$(jq -c --slurpfile r "$cdir/regions.json" '.regions=$r[0]' <<<"$sec")"
        [[ -s "$cdir/teams-meta.json" ]] && sec="$(jq -c --slurpfile t "$cdir/teams-meta.json" '.teams_meta=($t[0].rules // (if ($t[0]|type)=="array" then $t[0] else [] end))' <<<"$sec" 2>/dev/null || printf '%s' "$sec")"
        [[ -s "$cdir/time-overrides.json" ]] && jq -e 'type=="array" and length>0' "$cdir/time-overrides.json" >/dev/null 2>&1 \
          && sec="$(jq -c --slurpfile o "$cdir/time-overrides.json" '.time_overrides=$o[0]' <<<"$sec")";;
      baloes)
        [[ -s "$cdir/balloons.json" ]] && jq -e 'type=="object"' "$cdir/balloons.json" >/dev/null 2>&1 \
          && sec="$(jq -c --slurpfile c "$cdir/balloons.json" '.colors=$c[0]' <<<"$sec")"
        [[ "$(conf_value "$cid" BALLOONS_DURING_FREEZE)" == 1 ]] && sec="$(jq -c '.during_freeze=true' <<<"$sec")";;
      coortes)
        [[ -s "$cdir/cohorts.json" ]] && sec="$(jq -c --slurpfile c "$cdir/cohorts.json" '.cohorts=[ ($c[0].cohorts // [])[] | select((.id // "") != "") | {id, name:(.name // .id), regex:(.regex // ""), public:(.public != false), unranked:(.unranked == true), ranking:(.ranking == true), default:(.default == true), sees:(.sees // [])} ]' <<<"$sec" 2>/dev/null || printf '%s' "$sec")";;
      maquinas)
        [[ -s "$cdir/ua-gate.json" ]] && jq -e 'type=="object"' "$cdir/ua-gate.json" >/dev/null 2>&1 \
          && sec="$(jq -c --slurpfile g "$cdir/ua-gate.json" '.ua_gate=$g[0]' <<<"$sec")"
        local slv slg; slv="$(conf_value "$cid" SITE_LOCK)"; slg="$(conf_value "$cid" SITE_LOCK_GRACE)"
        [[ "$slv" == 1 || "$slv" == y || "$slv" == true ]] && sec="$(jq -c --argjson g "${slg:-3600}" '.site_lock={enabled:true, grace:$g}' <<<"$sec" 2>/dev/null || jq -c '.site_lock={enabled:true, grace:3600}' <<<"$sec")"
        local nu; nu="$(conf_value "$cid" NUTELLABOOT_URL)"; nu="${nu//\\/}"
        [[ -n "$nu" ]] && sec="$(jq -c --arg u "$nu" '.nutella_url=$u' <<<"$sec")";;
      rodadas)
        [[ -s "$cdir/rounds.json" ]] && sec="$(jq -c --slurpfile r "$cdir/rounds.json" '. + {active:($r[0].active // ""), rounds:[ ($r[0].rounds // [])[] | select(.state != "archived") | del(.archived, .archived_at) ]}' <<<"$sec" 2>/dev/null || printf '%s' "$sec")";;
      documentos)
        [[ -s "$cdir/docs/config.json" ]] && sec="$(jq -c --slurpfile d "$cdir/docs/config.json" '.config=($d[0] | {caderno_version, cover_note, errata} | with_entries(select(.value != null)))' <<<"$sec" 2>/dev/null || printf '%s' "$sec")";;
      inscricoes)
        local ro rc rl rm rt rw
        ro="$(conf_value "$cid" REG_OPEN)"; rc="$(conf_value "$cid" REG_CLOSE)"; rl="$(conf_value "$cid" REG_LATE_MINUTES)"
        rm="$(conf_value "$cid" REG_TEAM_MAX)"; rt="$(conf_value "$cid" REG_TEAMS)"; rw="$(conf_value "$cid" REG_WARMUP_OPEN)"
        sec="$(jq -c --arg ro "$ro" --arg rc "$rc" --arg rl "$rl" --arg rm "$rm" --arg rt "$rt" --arg rw "$rw" --argjson en "$([[ -f "$cdir/registrations.json" ]] && echo true || echo false)" '
          .enabled=$en | .window=({}
            + (if ($ro|test("^[0-9]+$")) then {open:($ro|tonumber)} else {} end)
            + (if ($rc|test("^[0-9]+$")) then {close:($rc|tonumber)} else {} end)
            + (if ($rl|test("^[0-9]+$")) then {late_minutes:($rl|tonumber)} else {} end)
            + (if ($rm|test("^[0-9]+$")) then {team_max:($rm|tonumber)} else {} end)
            + (if $rt == "n" then {teams:false} else {} end)
            + (if $rw == "y" then {warmup_open:true} else {} end))' <<<"$sec")";;
      telao)
        [[ -s "$cdir/webcast.json" ]] && sec="$(jq -c --slurpfile w "$cdir/webcast.json" '.views=[ ($w[0].keys // [])[] | select((.revoked_at // 0) == 0 and (.key // "") != "") | {view:(.view // "public"), label:(.label // "")} ]' <<<"$sec" 2>/dev/null || printf '%s' "$sec")";;
      classificacao)
        # um estágio no lugar padrão do motor = formato antigo {algorithm, config}; senão {stages:[…]} (só a
        # CONFIGURAÇÃO: resultado, overrides e status são dados da prova)
        [[ -s "$cdir/classification.json" ]] && sec="$(jq -c --slurpfile c "$cdir/classification.json" \
          --slurpfile k "$(dirname "${BASH_SOURCE[0]}")/../../../score/classify-catalog.json" '
          [ ($c[0].stages // [])[] | select(.config != null) ] as $S
          | if ($S | length) == 0 then .
            elif ($S | length) == 1 and ($S[0].id == (first($k[0].engines[] | select(.id == ($S[0].config.algorithm // "sbc-fase1")) | .stage) // "final-br"))
            then .algorithm = ($S[0].config.algorithm // "sbc-fase1") | .config = ($S[0].config | del(.algorithm))
            else .stages = [ $S[] | {id, algorithm:(.config.algorithm // "sbc-fase1"), config:(.config | del(.algorithm))}
                             + ({name, venue, when, chip} | with_entries(select(.value != null))) ] end' <<<"$sec" 2>/dev/null || printf '%s' "$sec")";;
    esac
    out="$(jq -c --arg m "$m" --argjson s "$sec" '.[$m]=$s' <<<"$out")"
  done
  # esqueletos: o código pode somar centenas de KB — entra por ARQUIVO, nunca pelo argv do jq (ARG_MAX)
  if [[ ",$mods," == *",esqueletos,"* ]]; then
    declare -F esq_langs_json >/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/esqueletos.sh"
    local ef; ef="$(mktemp)"; esq_langs_json "$cid" > "$ef"
    out="$(jq -c --slurpfile l "$ef" 'if (($l[0] // {}) | length) > 0 then .esqueletos.langs = $l[0] else . end' <<<"$out")"
    rm -f "$ef"
  fi
  printf '%s' "$out"
}

# cc_problem_metrics_file — caminho de um cache {id:{total,accepted,solvers,acceptance}} por
# problema, derivado do history do treino (TTL 30min). Usado pelo sorteio por dificuldade.
cc_problem_metrics_file(){
  local f="$CONTESTSDIR/treino/var/problem-metrics.json"
  if [[ ! -s "$f" || -n "$(find "$f" -mmin +30 2>/dev/null)" ]]; then
    mkdir -p "$CONTESTSDIR/treino/var"
    # attempters = tentantes DISTINTOS: a dificuldade do sorteio é a taxa POR USUÁRIO
    # (solvers/attempters), a mesma da busca do treino (lib/difficulty.sh, issue #30)
    emit_history_stream treino \
      | awk -F: '{tot[$3]++; att[$3 SUBSEP $2]=1; if($5 ~ /^Accepted/){acc[$3]++; sol[$3 SUBSEP $2]=1}}
               END{for(k in sol){split(k,a,SUBSEP); ns[a[1]]++}
                   for(k in att){split(k,a,SUBSEP); na[a[1]]++}
                   for(p in tot) printf "%s\t%d\t%d\t%d\t%d\n", p, tot[p], acc[p]+0, ns[p]+0, na[p]+0}' \
      | jq -R -s '
          '"$DIFF_JQ"'
          split("\n")|map(select(length>0)|split("\t")
                  |{key:.[0], value:{total:(.[1]|tonumber), accepted:(.[2]|tonumber), solvers:(.[3]|tonumber),
                     attempters:(.[4]|tonumber),
                     acceptance:(if (.[1]|tonumber)>0 then ((.[2]|tonumber)/(.[1]|tonumber)) else 0 end),
                     user_rate: diff_rate((.[3]|tonumber); (.[4]|tonumber)),
                     difficulty: diff_label((.[3]|tonumber); (.[4]|tonumber))}})
                  |from_entries' > "$f.tmp" 2>/dev/null && mv -f "$f.tmp" "$f" || echo '{}' > "$f"
  fi
  printf '%s' "$f"
}

# cc_bank_json — banco PÚBLICO do treino p/ busca/sorteio: o cache var/problems.json (gerado
# pelo /treino/problems; já traz id/title/tags/collections) ou, a frio, projeção direta de
# var/jsons/*.json — INCLUINDO collections (sem isso o sorteio por coleção falha a frio).
cc_bank_json(){
  local cache="$CONTESTSDIR/treino/var/problems.json" data=""
  if [[ -f "$cache" ]]; then cat "$cache"; return; fi
  set +o noglob
  data="$(jq -s 'map({id, title, tags:(.tags//[]), collections:(.collections//[])})' \
    "$CONTESTSDIR"/treino/var/jsons/*.json 2>/dev/null)"
  set -o noglob
  printf '%s' "${data:-[]}"
}

# cc_bank_private_json <login> — os problemas PRIVADOS que <login> pode usar num contest (dono,
# colaborador ou membro da org: owners_visible_for), no formato do cc_bank_json mais
# {private:true, access:"mine"|"shared"}. Só entra com include_private=1 (opt-in) nas rotas de
# sorteio/tags/coleções: sortear por tag ou coleção pode puxar a prova em elaboração de um colega
# da org, então ninguém recebe privado sem pedir — e quem não pede não paga o custo.
#   • sujeito OBRIGATÓRIO: vazio (contest legado sem owner) = [] — nunca cai no SESSION_LOGIN;
#   • título e coleções vêm do índice (como na busca, contest/admin/bank.sh); do
#     jsons-private/<id>.json lê SÓ as tags, um arquivo por vez (xargs, sem -s): cada um traz o
#     enunciado em base64 e o -s punha todos na memória de uma vez;
#   • has_statement = o jsons-private/<id>.json existe e é legível (é dele que o contest materializa
#     o enunciado). Privado sem ele NÃO sai do sorteio — só vem marcado, como na busca, e o wizard
#     avisa "enunciado em geração". Sem o campo, todo privado sorteado parecia sem enunciado;
#   • arquivo CORROMPIDO não pode levar as tags dos outros: o jq do lote para no primeiro erro de
#     parse (e o xargs devolve 123) — aí refaz um a um e avisa no error.log (molde do rv_scan);
#   • NÃO cacheia: a lista depende do login;
#   • rc 1 (stdout vazio) = índice de owners inutilizável: quem chama responde 503, nunca lista
#     vazia calada (lib/problems.sh, ensure_owners_index).
cc_bank_private_json(){
  local login="$1" d="$CONTESTSDIR/treino/var/jsons-private" tmp out
  [[ -n "$login" ]] || { printf '%s' '[]'; return 0; }
  declare -F owners_visible_for >/dev/null 2>&1 || source "${BASH_SOURCE[0]%/*}/problems.sh"
  tmp="$(mktemp -d)" || return 1
  if ! owners_visible_for "$login" > "$tmp/vis.json" || [[ ! -s "$tmp/vis.json" ]]; then
    rm -rf "$tmp"; return 1
  fi
  jq -r '.problems[] | select((.public // false) | not) | .id' "$tmp/vis.json" 2>/dev/null \
    | while IFS= read -r id; do [[ -f "$d/$id.json" ]] && printf '%s\0' "$d/$id.json"; done > "$tmp/files"
  # o id sai do NOME do arquivo (é a chave que o contest usa), nunca do conteúdo
  local prog='{id:(input_filename | sub("^.*/"; "") | sub("\\.json$"; "")), tags:(.tags // [])}' f
  if ! xargs -0 -r jq -c "$prog" < "$tmp/files" > "$tmp/tags.ndjson" 2>/dev/null; then
    : > "$tmp/tags.ndjson"
    while IFS= read -r -d '' f; do
      jq -c "$prog" "$f" >> "$tmp/tags.ndjson" 2>/dev/null || echo "cc_bank_private_json: ilegível: $f" >&2
    done < "$tmp/files"
  fi
  out="$(jq -cn --arg me "$login" --slurpfile v "$tmp/vis.json" --slurpfile t "$tmp/tags.ndjson" '
    ($t | map({key:.id, value:.tags}) | from_entries) as $T
    | [ $v[0].problems[] | select((.public // false) | not) | .id as $i
        | {id, title:(.title // .id), tags:($T[$i] // []), collections:(.collections // []),
           private:true, access:(if .owner == $me then "mine" else "shared" end),
           has_statement:($T | has($i))} ]' 2>/dev/null)"
  rm -rf "$tmp"
  [[ -n "$out" ]] || return 1
  printf '%s' "$out"
}

# cc_bank_json_for <login|""> <include_private:0|1> — o banco que o sorteio/tags/coleções usam.
# Sem include (o padrão) = o cc_bank_json de sempre. Com include = privados de <login> PRIMEIRO
# e vencendo o cache público: um recém-despublicado consta dos dois (o público sai por TTL) e o
# índice é o fresco — a mesma regra da busca. rc 1 = índice quebrado (só com include).
cc_bank_json_for(){
  local login="$1" inc="$2" priv
  [[ "$inc" == 1 ]] || { cc_bank_json; return 0; }
  priv="$(cc_bank_private_json "$login")" || return 1
  { printf '%s\n' "$priv"; cc_bank_json; } | jq -cs '
    (.[0] // []) as $p | (.[1] // []) as $pub | ($p | map(.id)) as $ids
    | $p + ($pub | map(select(.id as $i | ($ids | index($i)) | not)))' 2>/dev/null
}

# cc_bank_filter <tags_csv> <match:any|all> <diff> [collections_json_array] — filtra o banco
# (stdin = array do cc_bank_json) por tag E coleção (grupos em AND; dentro do grupo, tags casam
# por match, coleções por "qualquer uma") e por dificuldade (buckets de acceptance do
# problem-metrics). Coleção casa EXATO (nome curado, texto livre — nada de normalizar).
# Emite [{id,title,tags,collections,private,access,has_statement,solvers,total,acceptance,bucket}]
# (private/access/has_statement: o que o cc_bank_json_for marcou; público sem marca = private:false,
# access:"public", has_statement:true — o cache público só lista quem tem json servível). O objeto é
# RECONSTRUÍDO aqui: campo novo do banco que o sorteio deva devolver entra nesta lista também.
cc_bank_filter(){
  local tags="$1" match="$2" diff="$3" colls="${4:-[]}" MET
  jq -e 'type=="array" and all(.[]; type=="string")' >/dev/null 2>&1 <<<"$colls" || colls='[]'
  MET="$(cc_problem_metrics_file)"
  jq -c --slurpfile m "$MET" --arg tags "$tags" --arg match "$match" --arg diff "$diff" --argjson colls "$colls" '
    '"$DIFF_JQ"'
    ($tags|split(",")|map(ascii_downcase|gsub("^\\s+|\\s+$";""))|map(select(length>0))) as $T
    | ($m[0] // {}) as $M
    | [ .[]
        | (.tags // []) as $pt
        | ($pt|map(ascii_downcase)) as $ptl
        | (if ($T|length)==0 then true
           elif $match=="all" then ($T|all(. as $t|$ptl|index($t)))
           else ($T|any(. as $t|$ptl|index($t))) end) as $tagok
        | (.collections // []) as $pc
        | (if ($colls|length)==0 then true
           else ($colls | any(. as $c | ($pc|index($c)) != null)) end) as $collok
        | select($tagok and $collok)
        | ($M[.id] // {total:0,accepted:0,solvers:0,attempters:0,acceptance:0}) as $mm
        # bucket pela DIFICULDADE canônica (taxa por usuário): easy = veasy+easy, medium = med
        | (diff_label($mm.solvers; ($mm.attempters // 0))) as $lbl
        | (diff_bucket($lbl)) as $bucket
        | select($diff=="any" or $diff==$bucket or ($diff=="known" and $bucket!="unknown"))
        | {id, title, tags:$pt, collections:$pc, private:(.private // false), access:(.access // "public"),
           has_statement:(.has_statement != false),
           solvers:$mm.solvers, attempters:($mm.attempters // 0), total:$mm.total,
           acceptance:(($mm.acceptance*1000|floor)/1000),
           user_rate:(if ($mm.attempters // 0) > 0 then (($mm.solvers/$mm.attempters*1000|floor)/1000) else null end),
           difficulty:$lbl, bucket:$bucket}
      ]' 2>/dev/null
}

# cc_set_conf_var <contest> <VAR> <value> — define/atualiza uma var no conf (escapada com %q),
# preservando as demais linhas. cc_del_conf_var remove a var.
# --- PRIORIDADE no escalonador (CONTEST_PRIORITY; 01/10/2026) ----------------------------------------
# super > prova > lista-privada > lista-publica; ausente = lista-publica. Decide a BANDA da fila de julgamento e a
# regra de envios (lista: teto SUBMIT_MAX_INFLIGHT no /submit; prova/super: sem teto, menos prioridade a partir do
# 6º pendente). Editável depois da criação: o admin do contest muda entre as três de baixo (Central › Regras,
# /contest/admin/settings); Super só o SUPER-ADMIN do treino dá ou tira (Painel do treino › Contests,
# /treino/admin/contest-priority) — numa sessão de contest a conta `.admin` é LOCAL e o nome não prova identidade.
CC_PRIORITIES="lista-publica lista-privada prova super"
cc_priority_ok(){ [[ -n "$1" && " $CC_PRIORITIES " == *" $1 "* ]]; }
# cc_set_priority <contest> <nova> <via> — grava e AUDITA no contest e na trilha central do treino
# (`contest-priority` no var/admin-audit.log do treino — o feed 📜 Atividade). Quem pode o quê é do CHAMADOR.
# Põe a anterior em CC_PRIO_OLD (vazio = não definida) e CC_PRIO_CHANGED=0|1 (mesma prioridade = nada gravado).
cc_set_priority(){
  local c="$1" new="$2" via="$3" old
  old="$(conf_value "$c" CONTEST_PRIORITY)"; old="${old//\\/}"
  CC_PRIO_OLD="$old"; CC_PRIO_CHANGED=0
  [[ -n "$old" && "$old" == "$new" ]] && return 0
  cc_set_conf_var "$c" CONTEST_PRIORITY "$new" || return 1
  CC_PRIO_CHANGED=1
  audit_log_to "$c" priority "de=${old:-não-definida} para=$new via=$via"
  [[ "$c" == treino ]] || audit_log_to treino contest-priority "contest=$c de=${old:-não-definida} para=$new via=$via"
  return 0
}
cc_set_conf_var(){
  local cf="$CONTESTSDIR/$1/conf" tmp
  [[ -f "$cf" ]] || return 1
  tmp="$(mktemp "${cf}.XXXXXX")" || return 1
  grep -v "^$2=" "$cf" 2>/dev/null > "$tmp"
  printf '%s=%q\n' "$2" "$3" >> "$tmp"
  cat "$tmp" > "$cf" && rm -f "$tmp"
}
cc_del_conf_var(){
  local cf="$CONTESTSDIR/$1/conf" tmp
  [[ -f "$cf" ]] || return 0
  tmp="$(mktemp "${cf}.XXXXXX")" || return 1
  grep -v "^$2=" "$cf" 2>/dev/null > "$tmp"
  cat "$tmp" > "$cf" && rm -f "$tmp"
}

# cc_regions_ok <json> — o regions.json tem a FORMA certa? Lista de nós {name, regex?, subregions?, view?}:
# name texto não-vazio, regex texto, subregions lista (recursivo). É o portão de config.sh e da criação —
# antes nada conferia, e um objeto/texto gravado ali quebrava em silêncio os ~13 leitores (placar, escopo
# do staff, etiquetas, gate, telão…). E a REGEX de cada nó tem de estar no subconjunto seguro (rg_norm de
# lib/regions.sh: casa igual em JS, jq e gawk). Falhou por regex: CC_REGIONS_ERRORS = [{i,path,name,regex,err}]
# (≤ 50, regex cortada em 200 — cabe no FAIL_EXTRA) e cc_regions_fail monta o 422.
cc_regions_ok(){
  CC_REGIONS_ERRORS='[]'
  jq -e 'def ok: type == "object"
            and ((.name | type) == "string") and ((.name | gsub("^\\s+|\\s+$"; "") | length) > 0)
            and (((.regex // "") | type) == "string")
            and (((.subregions // []) | type) == "array")
            and all((.subregions // [])[]; ok);
         type == "array" and all(.[]; ok)' >/dev/null 2>&1 <<<"$1" || return 1
  declare -F rg_tree_errors >/dev/null || source "${_LIBDIR:-${BASH_SOURCE[0]%/*}}/regions.sh"
  local f; f="$(mktemp)" || return 1
  printf '%s' "$1" > "$f"
  CC_REGIONS_ERRORS="$(rg_tree_errors "$f" | jq -c '.[0:50] | map(.regex |= .[0:200])' 2>/dev/null)"
  rm -f "$f"
  [[ -n "$CC_REGIONS_ERRORS" ]] || CC_REGIONS_ERRORS='[]'
  [[ "$CC_REGIONS_ERRORS" == '[]' ]]
}
# cc_regions_fail — o 422 depois de um cc_regions_ok que falhou (forma OU regex). `error.nodes` = os nós
# com regex recusada e o código (a web traduz: regions.js; a CLI mostra o caminho)
cc_regions_fail(){
  if [[ "${CC_REGIONS_ERRORS:-[]}" != '[]' ]]; then
    local m; m="$(jq -r '.[0] | "a regex de \"\(.path)\" está fora do subconjunto seguro (\(.err))"' <<<"$CC_REGIONS_ERRORS")"
    FAIL_EXTRA="$(jq -cn --argjson e "$CC_REGIONS_ERRORS" '{nodes:$e}')" \
      fail 422 "Sedes (regions): $m" "regions_invalid"
  fi
  fail 422 "Sedes (regions) inválidas: lista de {name, regex?, subregions?}" "regions_invalid"
}

# cc_build_probs <target_dir> <problems_json_array> [enun_src_dir] -> ecoa "PROBS=(...)"
# e grava os enunciados em <target_dir>/enunciados/. Letra: usa .letter se válida, senão a 1ª LIVRE (cc_letter_next).
# Retorna 1 em validação inválida.
# **CC_KEEP_STATEMENTS=1**: não re-busca o enunciado do banco quando o contest JÁ tem
# `enunciados/<skey>.html`. Sem isso, um problema sem `statement_b64` no spec faz o helper
# baixar o enunciado do banco e SOBRESCREVER o que o admin subiu à mão (a troca de rodada
# aplica a lista da rodada e clobberaria os enunciados finais da prova).
# cc_prob_title <bank-id|skey> <id-de-fallback> [lang] — NOME do problema quando o spec não traz
# `name`/`title`: o TÍTULO do banco (json servível, público ou privado) NO IDIOMA DA PROVA (`lang`, de
# cc_prob_lang), senão o PT, e só em último caso o id. Spec montado à mão / pela API sem o campo deixava
# "org#id" no lugar do título na sanfona (relato do Daniel Saad, 2026-09-18); e o PT fixo punha o nome em
# português sobre o enunciado em espanhol (TCP 2026, `LOCALE=es`, 03/10/2026).
cc_prob_title(){
  local bf t="" l="${3:-pt}"
  bf="$(cs_bank_json "$1" 2>/dev/null)" && t="$(cs_bank_title_or_pt "$bf" "$l")"
  t="${t//[$'\r\n\t']/ }"; t="${t:0:160}"
  printf '%s' "${t:-$2}"
}
# cc_prob_lang <contest> [locale] — o idioma do NOME padrão = o que a sanfona abre (cs_default sobre os
# idiomas oferecidos: STATEMENT_LANGS=pt com LOCALE=es dá PT). Com `locale` (a criação, o conf ainda não
# existe e STATEMENT_LANGS ausente = automático) o idioma é o LOCALE dado.
cc_prob_lang(){
  if [[ $# -ge 2 ]]; then contest_locale_ok "$2" && printf '%s' "$2" || printf pt; return 0; fi
  cs_default "$1" "$(cs_langs "$1")"
}
# cc_bank_titles <ids_json> -> {id:{pt,en,es}} — títulos por idioma dos problemas, lidos dos json
# servíveis (público › privado) num jq SÓ (input_filename = o id). Só idiomas com título não vazio. Para
# as telas que mostram as opções (Prova › Problemas, `moj-contest problems titles`) e a checagem da Central.
cc_bank_titles(){
  local tmp id bf; tmp="$(mktemp)" || { printf '{}'; return 0; }
  while IFS= read -r id; do
    bf="$(cs_bank_json "$id" 2>/dev/null)" && printf '%s\0' "$bf"
  done < <(jq -r '.[]? | strings' <<<"${1:-[]}" 2>/dev/null) > "$tmp"
  if [[ -s "$tmp" ]]; then
    xargs -0 -r jq -c '{id:(input_filename | sub("^.*/"; "") | sub("\\.json$"; "")),
        t:({pt:(.title // "")} + ((.statements // {}) | if type == "object" then . else {} end
             | with_entries(.value = (if (.value | type) == "object" then (.value.title // "") else "" end))))
          | with_entries(select((.value | type) == "string" and (.value | length) > 0))}' < "$tmp" 2>/dev/null \
      | jq -sc 'map({key:.id, value:.t}) | from_entries' 2>/dev/null || printf '{}'
  else
    printf '{}'
  fi
  rm -f "$tmp"
}
# cc_attach_titles — stdin = array de itens com `.id` (resultado de busca/sorteio, ≤100) → o mesmo array,
# cada item com `titles` {pt,en,es} quando o problema tem MAIS DE UM título distinto (= tem enunciado
# traduzido). É o que as telas usam p/ mostrar as opções de nome; sem tradução, nada muda no item.
# Lê só os json servíveis desses ids (o índice e o sidecar do treino guardam só o título PT).
cc_attach_titles(){
  local tmp; tmp="$(mktemp -d)" || { cat; return 0; }
  cat > "$tmp/items.json"
  if ! jq -e 'type == "array"' "$tmp/items.json" >/dev/null 2>&1; then cat "$tmp/items.json"; rm -rf "$tmp"; return 0; fi
  cc_bank_titles "$(jq -c '[.[]? | .id? | strings]' "$tmp/items.json")" > "$tmp/t.json"
  [[ -s "$tmp/t.json" ]] || echo '{}' > "$tmp/t.json"
  jq -c --slurpfile t "$tmp/t.json" '($t[0] // {}) as $T
    | map(. + (($T[.id] // {}) as $x | if ([$x[]] | unique | length) > 1 then {titles:$x} else {} end))' \
    "$tmp/items.json" 2>/dev/null || cat "$tmp/items.json"
  rm -rf "$tmp"
}
# cc_prob_cid — (jq) o id canônico de uma entrada do cc_probs_json: a statement_key quando já é 'org#prob',
# senão o problem_id com a barra virada em '#' (contest legado). O mesmo cálculo do admin/problems.sh.
CC_PROB_CID_JQ='def cid: (if ((.statement_key // "") | test("#")) then .statement_key else ((.problem_id // "") | gsub("/"; "#")) end);'
# cc_names_chosen_file <contest> — nomes ESCOLHIDOS pelo admin (ação `rename` com nome): {cid: nome}. Nome
# escolhido de propósito em outro idioma não vira aviso eterno na Central (item prob_names).
cc_names_chosen_file(){ printf '%s/%s/var/problem-names-chosen.json' "$CONTESTSDIR" "$1"; }
# cc_title_fixes <contest> -> [{letter,name,to,lang}] — problemas cujo NOME é um título do banco em OUTRO
# idioma que o da prova, quando há título no idioma da prova (cc_prob_lang). É o caso do contest criado antes
# de o nome seguir o idioma (TCP 2026: LOCALE=es com os nomes em PT) e do contest que trocou de LOCALE depois
# de inserir os problemas. Só nome INTOCADO (igual a um título do banco, sem aproximação) e não escolhido de
# propósito (cc_names_chosen_file): nome personalizado nunca é tocado. Lê os json servíveis num jq só.
cc_title_fixes(){
  local c="$1" lang tmp
  lang="$(cc_prob_lang "$c")"
  tmp="$(mktemp -d)" || { printf '[]'; return 0; }
  cc_probs_json "$c" > "$tmp/cur.json"
  cc_bank_titles "$(jq -c "$CC_PROB_CID_JQ"' [.[] | cid]' "$tmp/cur.json" 2>/dev/null)" > "$tmp/t.json"
  [[ -s "$tmp/t.json" ]] || echo '{}' > "$tmp/t.json"
  if [[ -s "$(cc_names_chosen_file "$c")" ]]; then cp "$(cc_names_chosen_file "$c")" "$tmp/k.json"; else echo '{}' > "$tmp/k.json"; fi
  jq -c --slurpfile t "$tmp/t.json" --slurpfile k "$tmp/k.json" --arg l "$lang" "$CC_PROB_CID_JQ"'
    ($t[0] // {}) as $T | (($k[0] // {}) | if type == "object" then . else {} end) as $K
    | [ .[] | cid as $c | ($T[$c] // {}) as $x | ($x[$l] // "") as $to | (.name // "") as $n
        | select(($to | length) > 0 and $n != $to and ([$x[]] | any(. == $n)) and ($K[$c] != $n))
        | {letter, name:$n, to:$to, lang:$l} ]' "$tmp/cur.json" 2>/dev/null || printf '[]'
  rm -rf "$tmp"
}
# LETRA DO PROBLEMA — nunca repetida, SEM diferenciar caixa (o editor de cores e o placar a mostram em
# maiúscula). A letra é a chave de rename/remove/reorder, das clarifications e da cor de balão; com
# duplicata, renomear mexia nas duas, remover tirava as duas e o reorder (map({(.letter): .})) perdia uma
# em silêncio. A automática era pela POSIÇÃO (letterauto[$i]) e colidia sempre que a sequência tinha
# lacuna: remover o C e acrescentar outro problema dava DUAS entradas com a mesma letra (caso real em
# 2026-09-09, contest atividade-ead-2; PR #36). Hoje a automática é a PRIMEIRA LIVRE, pela MESMA regra nos
# dois laços (cc_create e cc_build_probs — mexeu num, mexa no outro), e toda porta que recebe letra
# explícita recusa repetida (422 letter_taken/letter_dup; na promoção de rodada, bloqueador letter_dup).
# cc_letters_used <problems_json> -> " A B W1 " (as explícitas, em MAIÚSCULA, entre espaços)
cc_letters_used(){
  printf ' %s ' "$(jq -r '[.[]? | objects | (.letter // "") | tostring | ascii_upcase | select(length > 0)] | join(" ")' <<<"$1" 2>/dev/null)"
}
# cc_letters_dup <problems_json> -> as letras repetidas (maiúsculas, separadas por espaço) ou vazio
cc_letters_dup(){
  jq -r '[.[]? | objects | (.letter // "") | tostring | ascii_upcase | select(length > 0)]
         | group_by(.) | map(select(length > 1) | .[0]) | join(" ")' <<<"$1" 2>/dev/null
}
# cc_letter_next <var-usadas> <var-saída> — a 1ª letra livre de A..Z, AA..ZZ; acrescenta-a às usadas.
# rc 1 quando as 702 estão ocupadas (o chamador cai na posição numérica).
cc_letter_next(){
  local -n _ccl_u="$1" _ccl_o="$2"; local _ccl_c
  for _ccl_c in {A..Z} {A..Z}{A..Z}; do
    [[ "$_ccl_u" == *" $_ccl_c "* ]] && continue
    _ccl_o="$_ccl_c"; _ccl_u+="$_ccl_c "; return 0
  done
  return 1
}
cc_build_probs(){
  local tdir="$1" spec="$2" enun="${3:-}" probs="PROBS=(" i=0
  local p pid src pname letter bankid stmt_b64 stmt_file skey bf html
  local lused; lused="$(cc_letters_used "$spec")"
  local plang; plang="$(cc_prob_lang "${tdir##*/}")"   # o conf do contest JÁ existe (cc_set_probs)
  mkdir -p "$tdir/enunciados"
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    pid="$(jq -r '.problem_id // ""' <<<"$p")"; bankid="$(jq -r '.bank_id // ""' <<<"$p")"
    [[ -z "$pid" && -n "$bankid" ]] && pid="${bankid//#//}"
    pid="${pid//\//#}"   # id canônico 'coleção#problema'
    src="$(jq -r '.source // "cdmoj"' <<<"$p")"; pname="$(jq -r '.name // .title // ""' <<<"$p")"
    letter="$(jq -r '.letter // ""' <<<"$p")"; stmt_b64="$(jq -r '.statement_b64 // ""' <<<"$p")"
    stmt_file="$(jq -r '.statement_file // ""' <<<"$p")"
    [[ -n "$pid" ]] || { ((i++)); continue; }
    { [[ "$pid" =~ ^[A-Za-z0-9._/#@+-]+$ ]] && [[ "$pid" != *..* ]]; } || return 1
    [[ "$src" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    [[ -n "$letter" ]] || cc_letter_next lused letter || letter="$((i+1))"
    [[ "$letter" =~ ^[A-Za-z0-9]{1,3}$ ]] || return 1
    skey="${pid//\//#}"
    { [[ "$skey" =~ ^[A-Za-z0-9._#@+-]+$ ]] && [[ "$skey" != *..* ]]; } || return 1
    # nome: o do spec (`name`/`title`); sem ele, o TÍTULO do banco no idioma da prova (cc_prob_title)
    [[ -n "$pname" ]] || pname="$(cc_prob_title "${bankid:-$skey}" "$pid" "$plang")"
    html=""
    if [[ "${CC_KEEP_STATEMENTS:-0}" == 1 && -z "$stmt_b64" && -z "$stmt_file" \
          && -s "$tdir/enunciados/$skey.html" ]]; then
      : # enunciado já está no contest e o spec não traz outro: preserva o que está no disco
    elif [[ -n "$stmt_b64" ]]; then html="$(printf '%s' "$stmt_b64" | base64 -d 2>/dev/null)" || return 1
    elif [[ -n "$enun" && -n "$stmt_file" && -f "$enun/$stmt_file" ]]; then html="$(cat "$enun/$stmt_file")"
    elif [[ -n "$bankid" ]]; then bf="$CONTESTSDIR/treino/var/jsons/$bankid.json"; [[ -f "$bf" ]] || bf="$CONTESTSDIR/treino/var/jsons-private/$bankid.json"; [[ -f "$bf" ]] && html="$(jq -r '.statement_html_b64 // ""' "$bf" 2>/dev/null | base64 -d 2>/dev/null)"
    else bf="$CONTESTSDIR/treino/var/jsons/$skey.json"; [[ -f "$bf" ]] || bf="$CONTESTSDIR/treino/var/jsons-private/$skey.json"; [[ -f "$bf" ]] && html="$(jq -r '.statement_html_b64 // ""' "$bf" 2>/dev/null | base64 -d 2>/dev/null)"; fi
    [[ -n "$html" ]] && printf '%s' "$html" > "$tdir/enunciados/$skey.html"
    # traduções do banco -> <skey>.<lang>.html (CC_KEEP_STATEMENTS preserva as que já estão no disco)
    if [[ -z "$stmt_b64" && -z "$stmt_file" ]] && bf="$(cs_bank_json "${bankid:-$skey}")"; then cs_bank_write "$bf" "$tdir" "$skey" langs; fi
    probs+=" $(printf '%q' "$src") $(printf '%q' "$pid") $(printf '%q' "$pname") $(printf '%q' "$letter") $(printf '%q' "$skey")"
    ((i++))
  done < <(jq -c '.[]' <<<"$spec")
  probs+=" )"
  printf '%s' "$probs"
}

# cc_balloons_write <contest> <json> / cc_balloons_clear <contest> — o ÚNICO escritor do
# balloons.json (cores de balão + enableSonic da rodada NO AR). Grava, derruba o cache de
# /contest/balloons (o frescor por presença também cobre, mas o explícito é grátis) e liga o
# módulo `baloes`. Chamado por Evento › Balões (admin/config.sh) e pela troca de rodada
# (rd_apply_obj, quando a rodada tem cores próprias).
cc_balloons_write(){
  local cdir="$CONTESTSDIR/$1"
  jq -e 'type == "object" and length > 0' >/dev/null 2>&1 <<<"$2" || return 1
  printf '%s' "$2" > "$cdir/balloons.json" || return 1
  rm -f "$cdir/var/balloons-cache.json" "$cdir/var/balloons-cache.json.inputs" 2>/dev/null
  declare -F mod_enable >/dev/null && mod_enable "$1" baloes
  return 0
}
cc_balloons_clear(){
  local cdir="$CONTESTSDIR/$1"
  rm -f "$cdir/balloons.json" "$cdir/var/balloons-cache.json" "$cdir/var/balloons-cache.json.inputs" 2>/dev/null
  return 0
}

# cc_set_probs <contest> <problems_json_array> — reescreve a linha PROBS= no conf.
cc_set_probs(){
  local cf="$CONTESTSDIR/$1/conf" line tmp
  line="$(cc_build_probs "$CONTESTSDIR/$1" "$2")" || return 1
  tmp="$(mktemp "${cf}.XXXXXX")" || return 1
  grep -v '^PROBS=' "$cf" 2>/dev/null > "$tmp"
  printf '%s\n' "$line" >> "$tmp"
  cat "$tmp" > "$cf" && rm -f "$tmp"
}

# cc_probs_json <contest> -> [{source,problem_id,name,letter,statement_key}] do PROBS atual
cc_probs_json(){
  ( CONTEST_TYPE=""; PROBS=(); . "$CONTESTSDIR/$1/conf" 2>/dev/null
    for ((i=0; i+4 < ${#PROBS[@]}; i+=5)); do
      jq -cn --arg s "${PROBS[$i]:-}" --arg p "${PROBS[$((i+1))]:-}" --arg n "${PROBS[$((i+2))]:-}" \
         --arg l "${PROBS[$((i+3))]:-}" --arg k "${PROBS[$((i+4))]:-}" \
         '{source:$s, problem_id:$p, name:$n, letter:$l, statement_key:$k}'
    done
  ) | jq -cs '.'
}

# --- templates nomeados de contest (por criador) -----------------------------
# Um arquivo por login: contests/treino/var/contest-templates/<login>.json
#   {templates:{"<nome>":{created_at,updated_at,spec:{...}}}}
# O spec é RELATIVO (duration/login_lead/freeze_before_end; sem datas absolutas) e passa por
# WHITELIST no save (nunca guarda usuários/senhas/id — cliente hostil não contrabandeia campo).
CC_TPL_MAX_PER_USER=20
CC_TPL_MAX_SPEC_BYTES=65536
cc_tpl_file(){ printf '%s/treino/var/contest-templates/%s.json' "$CONTESTSDIR" "$1"; }
cc_tpl_valid_name(){ local n="$1"; [[ -n "$n" ]] || return 1; [[ "$n" =~ [[:cntrl:]] ]] && return 1; (( ${#n} <= 80 )); }
cc_tpl_read(){ local f; f="$(cc_tpl_file "$1")"; local c; c="$(cat "$f" 2>/dev/null)"; jq -e . >/dev/null 2>&1 <<<"$c" || c='{"templates":{}}'; printf '%s' "$c"; }

# cc_tpl_relativize — stdin: spec ABSOLUTO (formato do create/export); stdout: spec de TEMPLATE
# (whitelist + datas viram deltas). Problemas entram só se $keep_problems=="1" (sem enunciado
# embutido — template guarda referências, não conteúdo).
cc_tpl_relativize(){
  local keep_problems="${1:-0}"
  jq -c --arg kp "$keep_problems" '
    def pick($keys): with_entries(select(.key as $k | $keys | index($k)));
    (.start|tonumber? // 0) as $st | (.end|tonumber? // 0) as $en
    | (.login_start|tonumber? // 0) as $ls | (.freeze|tonumber? // 0) as $fz
    | pick(["mode","priority","languages","show_log","show_editor","show_tl",
            "allow_backup","allow_print","score_anon","manual_verdict","secret",
            "login_ua_substring","score_full_users","locale","tz","login_enabled",
            "penalty_minutes","penalty_verdicts",
            "colors","regions","teams_meta","modules"])
    + (if $st > 0 and $en > $st then {duration:($en-$st)} else {} end)
    + (if $ls > 0 and $st > $ls then {login_lead:($st-$ls)} else {} end)
    + (if $fz > 0 and $en > $fz then {freeze_before_end:($en-$fz)} else {} end)
    + (if $kp == "1" then {problems:((.problems // []) | map(del(.statement_b64,.statement_pdf_b64,.statement_file,.statement_pdf_file)))} else {} end)
    | (if (.modules|type) == "object" then .modules |= with_entries(.value |= (if type == "object" then del(.time_overrides, .rounds, .active) else . end)) else . end)'
}

# cc_export_spec <cid> <statements:auto|all|none> — ecoa o SPEC JSON (formato aceito pelo
# cc_create) de um contest existente. NUNCA emite credenciais/usuários (passwd, users[], senha
# de admin) nem dados de prova (submissões/history/logs). users_from entra (é referência a
# fonte compartilhada, não credencial). Enunciados de enunciados/<skey>.{html,pdf}:
#   auto = embute só os SEM json público no banco (material exclusivo do contest, que se
#          perderia); all = embute todos (contest auto-contido); none = nenhum (o duplicate
#          usa none + statement_file, copiando por arquivo). b64 via --rawfile (ARG_MAX).
cc_export_spec(){
  local cid="$1" stmts="${2:-auto}" cdir="$CONTESTSDIR/$1"
  [[ -f "$cdir/conf" ]] || return 1
  local confjson
  confjson="$(
    CONTEST_NAME=""; CONTEST_TYPE=""; CONTEST_PRIORITY=""; CONTEST_START=""; CONTEST_END=""
    LANGUAGES=""; USERS_FROM=""; LOCALE=""; LOGIN_START_TIME=""; LOGIN_ENABLED=""; CONTEST_TZ=""
    FREEZE_TIME=""; SHOWLOG=""; SHOWEDITOR=""; SHOWTL=""; SCORE_ANON=""
    BACKUP=""; PRINT=""; MANUAL_VERDICT=""; LOGIN_UA_SUBSTRING=""; SCORE_FULL_USERS=""; SECRET=""
    PENALTY_MINUTES=""; PENALTY_VERDICTS="__unset"; CONTEST_JUDGES=""; CONTEST_MODULES=""
    . "$cdir/conf" 2>/dev/null
    jq -cn \
      --arg name "$CONTEST_NAME" --arg mode "$CONTEST_TYPE" --arg prio "$CONTEST_PRIORITY" \
      --arg start "$CONTEST_START" --arg end "$CONTEST_END" --arg langs "$LANGUAGES" \
      --arg users_from "$USERS_FROM" --arg locale "$LOCALE" --arg tz "$CONTEST_TZ" \
      --arg lstart "$LOGIN_START_TIME" --arg lenabled "$LOGIN_ENABLED" --arg freeze "$FREEZE_TIME" \
      --arg showlog "$SHOWLOG" --arg showeditor "$SHOWEDITOR" \
      --arg showtl "$SHOWTL" --arg anon "$SCORE_ANON" --arg backup "$BACKUP" --arg prnt "$PRINT" \
      --arg manual "$MANUAL_VERDICT" --arg ua "$LOGIN_UA_SUBSTRING" --arg sfu "$SCORE_FULL_USERS" \
      --arg secret "$SECRET" --arg pmin "$PENALTY_MINUTES" --arg pvd "$PENALTY_VERDICTS" \
      --arg jdg "$CONTEST_JUDGES" '
      {name:$name, mode:(if $mode=="" then "icpc" else $mode end)}
      + (if $prio != "" then {priority:$prio} else {} end)
      + (if ($start|tonumber?) then {start:($start|tonumber)} else {} end)
      + (if ($end|tonumber?) then {end:($end|tonumber)} else {} end)
      + (if $langs != "" then {languages:($langs|split(" ")|map(select(length>0)))} else {} end)
      + (if $users_from != "" then {users_from:$users_from} else {} end)
      + (if $locale != "" then {locale:$locale} else {} end)
      + (if $tz != "" then {tz:$tz} else {} end)
      + (if (($lstart|tonumber?) // 0) > 0 then {login_start:($lstart|tonumber)} else {} end)
      + (if $lenabled == "n" then {login_enabled:false} else {} end)
      + (if (($freeze|tonumber?) // 0) > 0 then {freeze:($freeze|tonumber)} else {} end)
      + (if $showlog == "0" then {show_log:false} else {} end)
      + (if $showeditor == "0" then {show_editor:false} else {} end)
      + (if $showtl == "0" then {show_tl:false} else {} end)
      + (if $anon == "1" then {score_anon:true} else {} end)
      + (if $backup == "0" then {allow_backup:false} else {} end)
      + (if $prnt == "0" then {allow_print:false} else {} end)
      + (if $manual == "1" then {manual_verdict:true} else {} end)
      + (if $secret == "1" then {secret:true} else {} end)
      + (if $ua != "" then {login_ua_substring:$ua} else {} end)
      + (if $sfu != "" then {score_full_users:($sfu|split(" ")|map(select(length>0)))} else {} end)
      + (if (($pmin|tonumber?) // 20) != 20 then {penalty_minutes:($pmin|tonumber)} else {} end)
      + (if $pvd != "__unset" then {penalty_verdicts:($pvd|split(" ")|map(select(length>0)))} else {} end)
      + (if $jdg != "" then {judges:($jdg|split(" ")|map(select(length>0)))} else {} end)'
  )"
  [[ -n "$confjson" ]] || return 1
  # seção `modules` (spec unificado): só módulos ligados, dados reeditáveis, nunca segredo
  # módulos por ARQUIVO, nunca por argv: os esqueletos de código (módulo esqueletos) podem somar centenas
  # de KB, e o Linux limita UM argumento a 128 KiB (o jq morria com E2BIG e o export saía vazio)
  local mf; mf="$(mktemp)" || return 1
  cc_modules_spec "$cid" > "$mf"
  jq -e 'type == "object" and length > 0' "$mf" >/dev/null 2>&1 \
    && confjson="$(jq -c --slurpfile m "$mf" '. + {modules:$m[0]}' <<<"$confjson")"
  rm -f "$mf"

  local plf='{}'
  [[ -f "$cdir/problem-langs.json" ]] && plf="$(jq -c . "$cdir/problem-langs.json" 2>/dev/null)"
  jq -e . >/dev/null 2>&1 <<<"$plf" || plf='{}'
  local pjm='{}'
  [[ -f "$cdir/problem-judges.json" ]] && pjm="$(jq -c . "$cdir/problem-judges.json" 2>/dev/null)"
  jq -e . >/dev/null 2>&1 <<<"$pjm" || pjm='{}'

  local tmpd; tmpd="$(mktemp -d)" || return 1
  : > "$tmpd/probs.jsonl"
  local pj skey emb_html="" emb_pdf=""
  while IFS= read -r pj; do
    [[ -n "$pj" ]] || continue
    skey="$(jq -r '.statement_key // empty' <<<"$pj")"
    jq -cn --argjson p "$pj" --argjson pl "$plf" --argjson pjm "$pjm" '
      ($p.statement_key // "") as $sk
      | (if ($sk|test("#")) then $sk else (($p.problem_id // "")|gsub("/";"#")) end) as $cid
      | {source:($p.source // "cdmoj"), problem_id:$p.problem_id, name:$p.name, letter:$p.letter}
      + (if (($pl[$cid] // [])|length) > 0 then {languages:$pl[$cid]} else {} end)
      + (if (($pjm[$cid] // [])|length) > 0 then {judges:$pjm[$cid]} else {} end)' > "$tmpd/base.json"
    emb_html=""; emb_pdf=""
    if [[ "$stmts" != none && -n "$skey" ]]; then
      if [[ -f "$cdir/enunciados/$skey.html" ]] && { [[ "$stmts" == all ]] || [[ ! -f "$CONTESTSDIR/treino/var/jsons/$skey.json" ]]; }; then
        base64 -w0 "$cdir/enunciados/$skey.html" > "$tmpd/h.b64" 2>/dev/null && emb_html=1
      fi
      if [[ -f "$cdir/enunciados/$skey.pdf" ]] && { [[ "$stmts" == all ]] || [[ ! -f "$CONTESTSDIR/treino/var/jsons/$skey.json" ]]; }; then
        base64 -w0 "$cdir/enunciados/$skey.pdf" > "$tmpd/p.b64" 2>/dev/null && emb_pdf=1
      fi
    fi
    local args=( -c ) filt='.'
    [[ -n "$emb_html" ]] && { args+=( --rawfile h "$tmpd/h.b64" ); filt+=' | .statement_b64=($h|rtrimstr("\n"))'; }
    [[ -n "$emb_pdf" ]] && { args+=( --rawfile pp "$tmpd/p.b64" ); filt+=' | .statement_pdf_b64=($pp|rtrimstr("\n"))'; }
    jq "${args[@]}" "$filt" "$tmpd/base.json" >> "$tmpd/probs.jsonl"
  done < <(cc_probs_json "$cid" | jq -c '.[]')
  printf '%s' "$confjson" > "$tmpd/conf.json"   # idem: o conf carrega os módulos
  jq -cs --slurpfile conf "$tmpd/conf.json" --arg id "$cid" '{id:$id} + $conf[0] + {problems:.}' "$tmpd/probs.jsonl"
  local rc=$?
  rm -rf "$tmpd"
  return $rc
}

# cc_list_created <viewer> [mine] — contests criados pela interface (marcador created-by) que o
# VIEWER pode ver (cc_contest_visible_to; `mine` = só os dele), com o que a tela precisa filtrar:
# {id,name,mode,owner,owner_name,owner_has_photo,owner_is_admin,created_at,start,end,problems_count}.
# Uma leitura só, compartilhada por /treino/admin/contests e /treino/contest-create/mine.
cc_list_created(){
  local viewer="${1:-}" only="${2:-}" d cdir cid owner at _m line arr=() oname ophoto oadm
  set +o noglob; shopt -s nullglob
  for d in "$CONTESTSDIR"/*/created-by; do
    cdir="${d%/created-by}"; cid="${cdir##*/}"
    owner="$(cc_contest_owner "$cid")"
    if [[ "$only" == mine ]]; then [[ -n "$owner" && "$owner" == "$viewer" ]] || continue
    else cc_contest_visible_to "$viewer" "$owner" || continue; fi
    IFS=$'\t' read -r _ at _m < "$d" 2>/dev/null; [[ "$at" =~ ^[0-9]+$ ]] || at=0
    oname="$(user_fullname_of treino "$owner")"; ophoto=false; [[ -f "$CONTESTSDIR/treino/users/$owner/photo.png" ]] && ophoto=true
    oadm=false; [[ "$owner" == *.admin ]] && oadm=true
    line="$(
      CONTEST_NAME=""; CONTEST_TYPE=""; CONTEST_START=0; CONTEST_END=0; CONTEST_PRIORITY=""; PROBS=()
      . "$cdir/conf" 2>/dev/null
      [[ "${CONTEST_START:-0}" =~ ^[0-9]+$ ]] || CONTEST_START=0; [[ "${CONTEST_END:-0}" =~ ^[0-9]+$ ]] || CONTEST_END=0
      jq -cn --arg id "$cid" --arg nm "${CONTEST_NAME:-$cid}" --arg m "${CONTEST_TYPE:-${_m:-}}" \
         --arg o "${owner:-?}" --arg on "$oname" --argjson op "$ophoto" --argjson oa "$oadm" \
         --argjson at "$at" --argjson st "${CONTEST_START:-0}" --argjson en "${CONTEST_END:-0}" \
         --argjson np "$(( ${#PROBS[@]} / 5 ))" --arg pr "${CONTEST_PRIORITY:-}" \
         '{id:$id, name:$nm, mode:$m, owner:$o, owner_name:(if $on=="" then null else $on end), owner_has_photo:$op, owner_is_admin:$oa,
           created_at:$at, start:$st, end:$en, problems_count:$np, priority:(if $pr=="" then null else $pr end)}'
    )"
    [[ -n "$line" ]] && arr+=("$line")
  done
  shopt -u nullglob
  ((${#arr[@]})) && printf '%s\n' "${arr[@]}" | jq -cs 'sort_by(-.created_at)' || echo '[]'
}
