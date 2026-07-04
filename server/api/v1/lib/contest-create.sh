# lib/contest-create.sh — criação de contest (formulário + import de tar).
# Permissão: lista do admin OU threshold de problemas resolvidos no treino (com denylist);
# usuários .admin sempre podem. Problemas vêm do banco do treino (var/jsons), por ID
# (não-públicos), e/ou com enunciado custom. O conf é SOURCED -> tudo escrito com printf %q.
: "${DEFAULT_SCORE_MODE:=icpc}"

cc_perms_file(){ printf '%s/treino/var/contest-perms.json' "$CONTESTSDIR"; }

# JSON de permissões com defaults: {threshold:int, allow:[], deny:[]}
cc_perms_json(){
  local f; f="$(cc_perms_file)"
  if [[ -f "$f" ]]; then
    jq -c '{threshold:((.threshold//0)|floor), allow:(.allow//[]), deny:(.deny//[])}' "$f" 2>/dev/null \
      || echo '{"threshold":0,"allow":[],"deny":[]}'
  else
    echo '{"threshold":0,"allow":[],"deny":[]}'
  fi
}

# nº de problemas distintos resolvidos por um usuário no treino livre
cc_solved_count(){
  if command -v store_v2 >/dev/null 2>&1 && store_v2 treino; then metrics_solved_count treino "$1"; return; fi
  local h="$CONTESTSDIR/treino/controle/history"
  [[ -f "$h" ]] || { echo 0; return; }
  awk -F: -v u="$1" '$2==u && $5 ~ /^Accepted/ {s[$3]=1} END{print length(s)+0}' "$h" 2>/dev/null || echo 0
}

# cc_genpass — senha legível: uma palavra de palavras-para-senha + 4 dígitos (ex.: tartaruga7823).
cc_genpass(){
  local wl="${PASSWORD_WORDLIST:-/home/ribas/moj/cdmoj/mojinho-bot/palavras-para-senha}" w=""
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
  v="$(jq -r '.show_log' <<<"$spec")";       [[ "$v" == false ]] && printf 'SHOWLOG=%q\n' 0
  v="$(jq -r '.show_editor' <<<"$spec")";    [[ "$v" == false ]] && printf 'SHOWEDITOR=%q\n' 0
  v="$(jq -r '.show_tl' <<<"$spec")";        [[ "$v" == false ]] && printf 'SHOWTL=%q\n' 0
  v="$(jq -r '.allow_backup' <<<"$spec")";   [[ "$v" == false ]] && printf 'BACKUP=%q\n' 0
  v="$(jq -r '.allow_print' <<<"$spec")";    [[ "$v" == false ]] && printf 'PRINT=%q\n' 0
  v="$(jq -r '.score_anon' <<<"$spec")";     [[ "$v" == true ]] && printf 'SCORE_ANON=%q\n' 1
  v="$(jq -r '.manual_verdict' <<<"$spec")"; [[ "$v" == true ]] && printf 'MANUAL_VERDICT=%q\n' 1
  v="$(jq -r '.allow_late' <<<"$spec")";     [[ "$v" == true ]] && printf 'ALLOWLATEUSER=%q\n' y
  v="$(jq -r '.secret' <<<"$spec")";         [[ "$v" == true ]] && printf 'SECRET=%q\n' 1
  v="$(jq -r '.login_ua_substring // ""' <<<"$spec")"; v="${v//$'\n'/}"
  [[ -n "$v" ]] && printf 'LOGIN_UA_SUBSTRING=%q\n' "$v"
  v="$(jq -r '(.score_full_users // []) | map(select(type=="string" and test("^[A-Za-z0-9._@#+-]+$"))) | unique | join(" ")' <<<"$spec" 2>/dev/null)"
  [[ -n "$v" ]] && printf 'SCORE_FULL_USERS=%q\n' "$v"
  return 0
}

# cc_create <spec_json> <creator_login> <creator_name> [enun_src_dir]
# Valida tudo, monta em staging e publica com mv atômico. Sucesso -> popula CC_RESULT (JSON).
# Em erro chama fail (DEVE ser chamada direto no handler, nunca dentro de $(...)).
cc_create(){
  local spec="$1" creator="$2" cname="$3" enun="${4:-}"
  jq -e . >/dev/null 2>&1 <<<"$spec" || fail 400 "Spec JSON inválido" "bad_spec"

  local name mode start end langs showcode priority
  name="$(jq -r '.name // ""' <<<"$spec")"
  mode="$(jq -r '.mode // "icpc"' <<<"$spec")"
  start="$(jq -r '.start // empty' <<<"$spec")"
  end="$(jq -r '.end // empty' <<<"$spec")"
  # languages: array (ids canônicos, normaliza como o settings.sh) OU string legada
  if jq -e '(.languages|type)=="array"' >/dev/null 2>&1 <<<"$spec"; then
    langs="$(jq -r '(.languages // []) | map(select(type=="string") | ascii_downcase | select(test("^[a-z0-9_+.-]+$"))) | unique | join(" ")' <<<"$spec")"
  else
    langs="$(jq -r '.languages // ""' <<<"$spec")"
  fi
  showcode="$(jq -r 'if .showcode==true then 1 else 0 end' <<<"$spec")"
  # prioridade no escalonador (SEPARADA do modo/CONTEST_TYPE): super>prova>lista-privada>lista-publica
  priority="$(jq -r '.priority // "lista-publica"' <<<"$spec")"

  [[ -n "$name" ]] || fail 422 "Informe o nome do contest" "name_required"
  (( ${#name} <= 160 )) || fail 422 "Nome muito longo" "name_long"
  case "$mode" in
    icpc|obi|treino|heuristic) ;;
    outro|custom) [[ "$creator" == *.admin ]] || fail 403 "Modo '$mode' é exclusivo de admin" "mode_forbidden";;
    *) fail 422 "Modo inválido" "mode_invalid";;
  esac
  case "$priority" in
    prova|lista-privada|lista-publica) ;;
    super) [[ "$creator" == *.admin ]] || fail 403 "Prioridade 'super' é exclusiva de admin" "priority_forbidden";;
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

  local id; id="$(jq -r '.id // ""' <<<"$spec")"
  if [[ -z "$id" ]]; then
    id="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed -E 's/^-+|-+$//g')"
    [[ -n "$id" ]] || id="contest"; id="${id:0:48}"; id="$(printf '%s' "$id" | sed -E 's/-+$//')"
  fi
  [[ "$id" =~ ^[a-z0-9][a-z0-9._-]{1,48}$ ]] || fail 422 "id inválido (use a-z, 0-9, . _ -)" "id_invalid"
  case "$id" in treino|admin|api|www|status|docs|shared|index|new|old|run|server|web) fail 409 "id reservado" "id_reserved";; esac
  [[ -e "$CONTESTSDIR/$id" ]] && fail 409 "Já existe um contest com o id '$id'" "id_taken"

  local np allow_empty
  np="$(jq '(.problems // []) | length' <<<"$spec")"; [[ "$np" =~ ^[0-9]+$ ]] || np=0
  allow_empty="$(jq -r 'if .allow_empty==true then 1 else 0 end' <<<"$spec")"
  if (( np < 1 )) && [[ "$allow_empty" != 1 ]]; then fail 422 "Inclua ao menos um problema (ou marque criar vazio)" "no_problems"; fi
  (( np <= 200 )) || fail 422 "Máximo de 200 problemas" "too_many"

  local stg="$CONTESTSDIR/.staging-$id-$$-$RANDOM"
  rm -rf "$stg"
  mkdir -p "$stg"/{controle,data,enunciados,submissions,log,mojlog,var} || fail 500 "Falha ao preparar diretório" "mkdir_fail"
  : > "$stg/controle/history"

  local probs="PROBS=(" i=0
  local letterauto=( {A..Z} {A..Z}{A..Z} )   # A..Z, depois AA,AB,…
  local p pid src pname letter bankid stmt_b64 stmt_file skey bf html
  local pdf_b64 pdf_file larr plangs='{}'
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    pid="$(jq -r '.problem_id // ""' <<<"$p")"
    bankid="$(jq -r '.bank_id // ""' <<<"$p")"
    [[ -z "$pid" && -n "$bankid" ]] && pid="${bankid//#//}"
    pid="${pid//\//#}"   # id canônico 'coleção#problema' (igual ao treino; '#' é o que o juiz exige)
    src="$(jq -r '.source // "cdmoj"' <<<"$p")"
    pname="$(jq -r '.name // ""' <<<"$p")"
    letter="$(jq -r '.letter // ""' <<<"$p")"
    stmt_b64="$(jq -r '.statement_b64 // ""' <<<"$p")"
    stmt_file="$(jq -r '.statement_file // ""' <<<"$p")"
    pdf_b64="$(jq -r '.statement_pdf_b64 // ""' <<<"$p")"
    pdf_file="$(jq -r '.statement_pdf_file // ""' <<<"$p")"
    [[ -z "$pname" ]] && pname="$pid"
    [[ -n "$pid" ]] || { rm -rf "$stg"; fail 422 "Problema sem id" "prob_no_id"; }
    { [[ "$pid" =~ ^[A-Za-z0-9._/#@+-]+$ ]] && [[ "$pid" != *..* ]]; } || { rm -rf "$stg"; fail 422 "id de problema inválido: $pid" "prob_id_invalid"; }
    [[ "$src" =~ ^[A-Za-z0-9._-]+$ ]] || { rm -rf "$stg"; fail 422 "source de problema inválido" "src_invalid"; }
    (( ${#pname} <= 160 )) || { rm -rf "$stg"; fail 422 "nome de problema muito longo" "pname_long"; }
    [[ -z "$letter" ]] && letter="${letterauto[$i]:-$((i+1))}"
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
    larr="$(jq -c '(.languages // []) | map(select(type=="string") | ascii_downcase | select(test("^[a-z0-9_+.-]+$"))) | unique' <<<"$p" 2>/dev/null)"
    [[ -n "$larr" && "$larr" != "[]" ]] && plangs="$(jq -c --arg id "$skey" --argjson v "$larr" '.[$id]=$v' <<<"$plangs")"
    probs+=" $(printf '%q' "$src") $(printf '%q' "$pid") $(printf '%q' "$pname") $(printf '%q' "$letter") $(printf '%q' "$skey")"
    ((i++))
  done < <(jq -c '.problems[]?' <<<"$spec")
  probs+=" )"
  [[ "$plangs" != "{}" ]] && printf '%s' "$plangs" > "$stg/problem-langs.json"

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

  # a conta admin já existe na fonte compartilhada? (login = 1º campo do passwd)
  local shared_has_admin=false
  if [[ -n "$users_from" && -f "$CONTESTSDIR/$users_from/passwd" ]] \
     && cut -d: -f1 "$CONTESTSDIR/$users_from/passwd" 2>/dev/null | grep -qxF "$adminlogin"; then
    shared_has_admin=true
  fi
  if [[ -n "$sa_pass" ]]; then
    adminpass="$sa_pass"                         # [a] senha digitada -> autoritativa
  elif [[ "$shared_has_admin" == true ]]; then
    admin_reused=true; admin_local=false; adminpass=""   # [b][c] reusa, não grava local
  else
    adminpass="$(cc_genpass)"                     # padrão: gera
  fi
  case "$adminpass$adminname" in *:*) rm -rf "$stg"; fail 422 "senha/nome do admin não podem conter ':'" "colon";; esac

  # --- usuários: compartilhados (USERS_FROM) ou específicos do contest ---
  : > "$stg/passwd"
  declare -a CREDS
  if [[ "$admin_local" == true ]]; then
    printf '%s:%s:%s\n' "$adminlogin" "$adminpass" "$adminname" >> "$stg/passwd"
    CREDS+=("$(jq -cn --arg l "$adminlogin" --arg p "$adminpass" --arg n "$adminname" '{login:$l,password:$p,fullname:$n,role:"admin"}')")
  fi
  if [[ -n "$users_from" ]]; then
    { valid_id "$users_from" && [[ -f "$CONTESTSDIR/$users_from/passwd" ]]; } || { rm -rf "$stg"; fail 422 "users_from inválido" "users_from_invalid"; }
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
      if [[ -n "$ue" ]]; then printf '%s:%s:%s:%s\n' "$ul" "$up" "$un" "$ue" >> "$stg/passwd"
      else printf '%s:%s:%s\n' "$ul" "$up" "$un" >> "$stg/passwd"; fi
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
    printf 'SHOWCODE=%q\n' "$showcode"
    [[ -n "$shared" ]] && printf 'USERS_FROM=%q\n' "$shared"
    [[ "$b_locale" =~ ^(pt|en)$ ]] && printf 'LOCALE=%q\n' "$b_locale"
    [[ "$b_lstart" =~ ^[0-9]+$ ]] && printf 'LOGIN_START_TIME=%q\n' "$b_lstart"
    [[ "$b_lenabled" == n ]] && printf 'LOGIN_ENABLED=%q\n' "n"
    [[ "$b_freeze" =~ ^[0-9]+$ ]] && printf 'FREEZE_TIME=%q\n' "$b_freeze"
    cc_settings_conf_lines "$spec"
    # allow_late explícito no spec vence o automático de mode=treino (false => sem a var)
    [[ "$mode" == treino && "$(jq -r '.allow_late' <<<"$spec")" == null ]] && printf 'ALLOWLATEUSER=y\n'
  } > "$stg/conf"
  printf '%s\n' "$creator" > "$stg/owner"
  printf '%s\t%s\t%s\n' "$creator" "$EPOCHSECONDS" "$mode" > "$stg/created-by"

  # configs visuais opcionais (mesmo formato que o placar lê; reeditáveis depois pelo admin do contest)
  local colors_j regions_j teams_j
  colors_j="$(jq -c '.colors // empty' <<<"$spec" 2>/dev/null)"
  regions_j="$(jq -c '.regions // empty' <<<"$spec" 2>/dev/null)"
  teams_j="$(jq -c '.teams_meta // empty' <<<"$spec" 2>/dev/null)"
  [[ -n "$colors_j"  && "$colors_j"  != null ]] && printf '%s' "$colors_j"  > "$stg/balloons.json"
  [[ -n "$regions_j" && "$regions_j" != null ]] && printf '%s' "$regions_j" > "$stg/regions.json"
  [[ -n "$teams_j"   && "$teams_j"   != null ]] && jq -cn --argjson r "$teams_j" '{rules:$r}' > "$stg/teams-meta.json"

  mv -T "$stg" "$CONTESTSDIR/$id" 2>/dev/null || { rm -rf "$stg"; fail 500 "Falha ao publicar o contest (id pode ter sido criado em paralelo)" "publish_fail"; }

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

# cc_problem_metrics_file — caminho de um cache {id:{total,accepted,solvers,acceptance}} por
# problema, derivado do history do treino (TTL 30min). Usado pelo sorteio por dificuldade.
cc_problem_metrics_file(){
  local f="$CONTESTSDIR/treino/var/problem-metrics.json" h="$CONTESTSDIR/treino/controle/history"
  if [[ ! -s "$f" || -n "$(find "$f" -mmin +30 2>/dev/null)" ]]; then
    mkdir -p "$CONTESTSDIR/treino/var"
    local have=0
    if command -v store_v2 >/dev/null 2>&1 && store_v2 treino; then have=2
    elif [[ -f "$h" ]]; then have=1; fi
    if (( have )); then
      { (( have==2 )) && emit_history_stream treino || cat "$h"; } \
      | awk -F: '{tot[$3]++; if($5 ~ /^Accepted/){acc[$3]++; sol[$3 SUBSEP $2]=1}}
               END{for(k in sol){split(k,a,SUBSEP); ns[a[1]]++}
                   for(p in tot) printf "%s\t%d\t%d\t%d\n", p, tot[p], acc[p]+0, ns[p]+0}' \
      | jq -R -s 'split("\n")|map(select(length>0)|split("\t")
                  |{key:.[0], value:{total:(.[1]|tonumber), accepted:(.[2]|tonumber), solvers:(.[3]|tonumber),
                     acceptance:(if (.[1]|tonumber)>0 then ((.[2]|tonumber)/(.[1]|tonumber)) else 0 end)}})
                  |from_entries' > "$f.tmp" 2>/dev/null && mv -f "$f.tmp" "$f" || echo '{}' > "$f"
    else echo '{}' > "$f"; fi
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

# cc_bank_filter <tags_csv> <match:any|all> <diff> [collections_json_array] — filtra o banco
# (stdin = array do cc_bank_json) por tag E coleção (grupos em AND; dentro do grupo, tags casam
# por match, coleções por "qualquer uma") e por dificuldade (buckets de acceptance do
# problem-metrics). Coleção casa EXATO (nome curado, texto livre — nada de normalizar).
# Emite [{id,title,tags,collections,solvers,total,acceptance,bucket}].
cc_bank_filter(){
  local tags="$1" match="$2" diff="$3" colls="${4:-[]}" MET
  jq -e 'type=="array" and all(.[]; type=="string")' >/dev/null 2>&1 <<<"$colls" || colls='[]'
  MET="$(cc_problem_metrics_file)"
  jq -c --slurpfile m "$MET" --arg tags "$tags" --arg match "$match" --arg diff "$diff" --argjson colls "$colls" '
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
        | ($M[.id] // {total:0,accepted:0,solvers:0,acceptance:0}) as $mm
        | (if $mm.total==0 then "unknown" elif $mm.acceptance>=0.5 then "easy" elif $mm.acceptance>=0.2 then "medium" else "hard" end) as $bucket
        | select($diff=="any" or $diff==$bucket or ($diff=="known" and $bucket!="unknown"))
        | {id, title, tags:$pt, collections:$pc, solvers:$mm.solvers, total:$mm.total,
           acceptance:(($mm.acceptance*1000|floor)/1000), bucket:$bucket}
      ]' 2>/dev/null
}

# cc_set_conf_var <contest> <VAR> <value> — define/atualiza uma var no conf (escapada com %q),
# preservando as demais linhas. cc_del_conf_var remove a var.
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

# cc_build_probs <target_dir> <problems_json_array> [enun_src_dir] -> ecoa "PROBS=(...)"
# e grava os enunciados em <target_dir>/enunciados/. Letra: usa .letter se válida, senão A,B,...
# Retorna 1 em validação inválida.
cc_build_probs(){
  local tdir="$1" spec="$2" enun="${3:-}" probs="PROBS=(" i=0
  local letterauto=( {A..Z} {A..Z}{A..Z} )   # A..Z, depois AA,AB,…
  local p pid src pname letter bankid stmt_b64 stmt_file skey bf html
  mkdir -p "$tdir/enunciados"
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    pid="$(jq -r '.problem_id // ""' <<<"$p")"; bankid="$(jq -r '.bank_id // ""' <<<"$p")"
    [[ -z "$pid" && -n "$bankid" ]] && pid="${bankid//#//}"
    pid="${pid//\//#}"   # id canônico 'coleção#problema'
    src="$(jq -r '.source // "cdmoj"' <<<"$p")"; pname="$(jq -r '.name // ""' <<<"$p")"
    letter="$(jq -r '.letter // ""' <<<"$p")"; stmt_b64="$(jq -r '.statement_b64 // ""' <<<"$p")"
    stmt_file="$(jq -r '.statement_file // ""' <<<"$p")"
    [[ -z "$pname" ]] && pname="$pid"
    [[ -n "$pid" ]] || { ((i++)); continue; }
    { [[ "$pid" =~ ^[A-Za-z0-9._/#@+-]+$ ]] && [[ "$pid" != *..* ]]; } || return 1
    [[ "$src" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    [[ -z "$letter" ]] && letter="${letterauto[$i]:-$((i+1))}"
    [[ "$letter" =~ ^[A-Za-z0-9]{1,3}$ ]] || return 1
    skey="${pid//\//#}"
    { [[ "$skey" =~ ^[A-Za-z0-9._#@+-]+$ ]] && [[ "$skey" != *..* ]]; } || return 1
    html=""
    if [[ -n "$stmt_b64" ]]; then html="$(printf '%s' "$stmt_b64" | base64 -d 2>/dev/null)" || return 1
    elif [[ -n "$enun" && -n "$stmt_file" && -f "$enun/$stmt_file" ]]; then html="$(cat "$enun/$stmt_file")"
    elif [[ -n "$bankid" ]]; then bf="$CONTESTSDIR/treino/var/jsons/$bankid.json"; [[ -f "$bf" ]] || bf="$CONTESTSDIR/treino/var/jsons-private/$bankid.json"; [[ -f "$bf" ]] && html="$(jq -r '.statement_html_b64 // ""' "$bf" 2>/dev/null | base64 -d 2>/dev/null)"
    else bf="$CONTESTSDIR/treino/var/jsons/$skey.json"; [[ -f "$bf" ]] || bf="$CONTESTSDIR/treino/var/jsons-private/$skey.json"; [[ -f "$bf" ]] && html="$(jq -r '.statement_html_b64 // ""' "$bf" 2>/dev/null | base64 -d 2>/dev/null)"; fi
    [[ -n "$html" ]] && printf '%s' "$html" > "$tdir/enunciados/$skey.html"
    probs+=" $(printf '%q' "$src") $(printf '%q' "$pid") $(printf '%q' "$pname") $(printf '%q' "$letter") $(printf '%q' "$skey")"
    ((i++))
  done < <(jq -c '.[]' <<<"$spec")
  probs+=" )"
  printf '%s' "$probs"
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
    | pick(["mode","priority","languages","showcode","show_log","show_editor","show_tl",
            "allow_backup","allow_print","score_anon","manual_verdict","allow_late","secret",
            "login_ua_substring","score_full_users","locale","login_enabled",
            "colors","regions","teams_meta"])
    + (if $st > 0 and $en > $st then {duration:($en-$st)} else {} end)
    + (if $ls > 0 and $st > $ls then {login_lead:($st-$ls)} else {} end)
    + (if $fz > 0 and $en > $fz then {freeze_before_end:($en-$fz)} else {} end)
    + (if $kp == "1" then {problems:((.problems // []) | map(del(.statement_b64,.statement_pdf_b64,.statement_file,.statement_pdf_file)))} else {} end)'
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
    LANGUAGES=""; SHOWCODE=""; USERS_FROM=""; LOCALE=""; LOGIN_START_TIME=""; LOGIN_ENABLED=""
    FREEZE_TIME=""; ALLOWLATEUSER=""; SHOWLOG=""; SHOWEDITOR=""; SHOWTL=""; SCORE_ANON=""
    BACKUP=""; PRINT=""; MANUAL_VERDICT=""; LOGIN_UA_SUBSTRING=""; SCORE_FULL_USERS=""; SECRET=""
    . "$cdir/conf" 2>/dev/null
    jq -cn \
      --arg name "$CONTEST_NAME" --arg mode "$CONTEST_TYPE" --arg prio "$CONTEST_PRIORITY" \
      --arg start "$CONTEST_START" --arg end "$CONTEST_END" --arg langs "$LANGUAGES" \
      --arg showcode "$SHOWCODE" --arg users_from "$USERS_FROM" --arg locale "$LOCALE" \
      --arg lstart "$LOGIN_START_TIME" --arg lenabled "$LOGIN_ENABLED" --arg freeze "$FREEZE_TIME" \
      --arg late "$ALLOWLATEUSER" --arg showlog "$SHOWLOG" --arg showeditor "$SHOWEDITOR" \
      --arg showtl "$SHOWTL" --arg anon "$SCORE_ANON" --arg backup "$BACKUP" --arg prnt "$PRINT" \
      --arg manual "$MANUAL_VERDICT" --arg ua "$LOGIN_UA_SUBSTRING" --arg sfu "$SCORE_FULL_USERS" \
      --arg secret "$SECRET" '
      {name:$name, mode:(if $mode=="" then "icpc" else $mode end)}
      + (if $prio != "" then {priority:$prio} else {} end)
      + (if ($start|tonumber?) then {start:($start|tonumber)} else {} end)
      + (if ($end|tonumber?) then {end:($end|tonumber)} else {} end)
      + (if $langs != "" then {languages:($langs|split(" ")|map(select(length>0)))} else {} end)
      + {showcode:($showcode=="1")}
      + (if $users_from != "" then {users_from:$users_from} else {} end)
      + (if $locale != "" then {locale:$locale} else {} end)
      + (if (($lstart|tonumber?) // 0) > 0 then {login_start:($lstart|tonumber)} else {} end)
      + (if $lenabled == "n" then {login_enabled:false} else {} end)
      + (if (($freeze|tonumber?) // 0) > 0 then {freeze:($freeze|tonumber)} else {} end)
      + (if $late == "y" then {allow_late:true} else {} end)
      + (if $showlog == "0" then {show_log:false} else {} end)
      + (if $showeditor == "0" then {show_editor:false} else {} end)
      + (if $showtl == "0" then {show_tl:false} else {} end)
      + (if $anon == "1" then {score_anon:true} else {} end)
      + (if $backup == "0" then {allow_backup:false} else {} end)
      + (if $prnt == "0" then {allow_print:false} else {} end)
      + (if $manual == "1" then {manual_verdict:true} else {} end)
      + (if $secret == "1" then {secret:true} else {} end)
      + (if $ua != "" then {login_ua_substring:$ua} else {} end)
      + (if $sfu != "" then {score_full_users:($sfu|split(" ")|map(select(length>0)))} else {} end)'
  )"
  [[ -n "$confjson" ]] || return 1

  local plf='{}'
  [[ -f "$cdir/problem-langs.json" ]] && plf="$(jq -c . "$cdir/problem-langs.json" 2>/dev/null)"
  jq -e . >/dev/null 2>&1 <<<"$plf" || plf='{}'

  local tmpd; tmpd="$(mktemp -d)" || return 1
  : > "$tmpd/probs.jsonl"
  local pj skey emb_html="" emb_pdf=""
  while IFS= read -r pj; do
    [[ -n "$pj" ]] || continue
    skey="$(jq -r '.statement_key // empty' <<<"$pj")"
    jq -cn --argjson p "$pj" --argjson pl "$plf" '
      ($p.statement_key // "") as $sk
      | (if ($sk|test("#")) then $sk else (($p.problem_id // "")|gsub("/";"#")) end) as $cid
      | {source:($p.source // "cdmoj"), problem_id:$p.problem_id, name:$p.name, letter:$p.letter}
      + (if (($pl[$cid] // [])|length) > 0 then {languages:$pl[$cid]} else {} end)' > "$tmpd/base.json"
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
  jq -cs --argjson conf "$confjson" --arg id "$cid" '{id:$id} + $conf + {problems:.}' "$tmpd/probs.jsonl"
  local rc=$?
  rm -rf "$tmpd"
  return $rc
}

# lista contests criados pela interface (têm marcador created-by)
cc_list_created(){
  set +o noglob; shopt -s nullglob
  local d cid owner at mode nm arr=()
  for d in "$CONTESTSDIR"/*/created-by; do
    cid="${d%/created-by}"; cid="${cid##*/}"
    IFS=$'\t' read -r owner at mode < "$d" 2>/dev/null
    [[ "$at" =~ ^[0-9]+$ ]] || at=0
    nm="$( . "$CONTESTSDIR/$cid/conf" 2>/dev/null; printf '%s' "${CONTEST_NAME:-$cid}" )"
    arr+=("$(jq -cn --arg id "$cid" --arg nm "$nm" --arg o "${owner:-?}" --argjson at "$at" --arg m "${mode:-}" \
      '{id:$id,name:$nm,owner:$o,created_at:$at,mode:$m}')")
  done
  shopt -u nullglob
  ((${#arr[@]})) && printf '%s\n' "${arr[@]}" | jq -cs 'sort_by(-.created_at)' || echo '[]'
}
