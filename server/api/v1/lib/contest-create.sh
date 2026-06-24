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
  langs="$(jq -r '.languages // ""' <<<"$spec")"
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
  local letterauto=( {A..Z} )
  local p pid src pname letter bankid stmt_b64 stmt_file skey bf html
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    pid="$(jq -r '.problem_id // ""' <<<"$p")"
    bankid="$(jq -r '.bank_id // ""' <<<"$p")"
    [[ -z "$pid" && -n "$bankid" ]] && pid="${bankid//#//}"
    src="$(jq -r '.source // "cdmoj"' <<<"$p")"
    pname="$(jq -r '.name // ""' <<<"$p")"
    letter="$(jq -r '.letter // ""' <<<"$p")"
    stmt_b64="$(jq -r '.statement_b64 // ""' <<<"$p")"
    stmt_file="$(jq -r '.statement_file // ""' <<<"$p")"
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
    probs+=" $(printf '%q' "$src") $(printf '%q' "$pid") $(printf '%q' "$pname") $(printf '%q' "$letter") $(printf '%q' "$skey")"
    ((i++))
  done < <(jq -c '.problems[]?' <<<"$spec")
  probs+=" )"

  [[ -n "$cname" ]] || cname="$creator"

  # --- admin do contest (SEMPRE criado; sufixo .admin garantido) ---
  local sa_login sa_pass sa_name adminlogin adminpass adminname
  sa_login="$(jq -r '.admin.login // ""' <<<"$spec")"
  sa_pass="$(jq -r '.admin.password // ""' <<<"$spec")"
  sa_name="$(jq -r '.admin.fullname // ""' <<<"$spec")"
  adminlogin="${sa_login:-$creator}"; [[ "$adminlogin" == *.admin ]] || adminlogin="${adminlogin}.admin"
  valid_id "$adminlogin" || { rm -rf "$stg"; fail 422 "login de admin inválido" "admin_login_invalid"; }
  adminpass="${sa_pass:-$(cc_genpass)}"; adminname="${sa_name:-$cname}"
  case "$adminpass$adminname" in *:*) rm -rf "$stg"; fail 422 "senha/nome do admin não podem conter ':'" "colon";; esac

  # --- usuários: compartilhados (USERS_FROM) ou específicos do contest ---
  local users_from shared=""; users_from="$(jq -r '.users_from // ""' <<<"$spec")"
  : > "$stg/passwd"
  printf '%s:%s:%s\n' "$adminlogin" "$adminpass" "$adminname" >> "$stg/passwd"
  declare -a CREDS
  CREDS+=("$(jq -cn --arg l "$adminlogin" --arg p "$adminpass" --arg n "$adminname" '{login:$l,password:$p,fullname:$n,role:"admin"}')")
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
    [[ "$mode" == treino ]] && printf 'ALLOWLATEUSER=y\n'
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

  local users_json; users_json="$( ((${#CREDS[@]})) && printf '%s\n' "${CREDS[@]}" | jq -cs '.' || echo '[]')"
  CC_RESULT="$(jq -cn --arg id "$id" --arg al "$adminlogin" --arg pw "$adminpass" --argjson np "$np" \
    --argjson users "$users_json" --arg shared "$shared" \
    '{contest_id:$id, admin_login:$al, admin_password:$pw, problems:$np,
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
    if [[ -f "$h" ]]; then
      awk -F: '{tot[$3]++; if($5 ~ /^Accepted/){acc[$3]++; sol[$3 SUBSEP $2]=1}}
               END{for(k in sol){split(k,a,SUBSEP); ns[a[1]]++}
                   for(p in tot) printf "%s\t%d\t%d\t%d\n", p, tot[p], acc[p]+0, ns[p]+0}' "$h" \
      | jq -R -s 'split("\n")|map(select(length>0)|split("\t")
                  |{key:.[0], value:{total:(.[1]|tonumber), accepted:(.[2]|tonumber), solvers:(.[3]|tonumber),
                     acceptance:(if (.[1]|tonumber)>0 then ((.[2]|tonumber)/(.[1]|tonumber)) else 0 end)}})
                  |from_entries' > "$f.tmp" 2>/dev/null && mv -f "$f.tmp" "$f" || echo '{}' > "$f"
    else echo '{}' > "$f"; fi
  fi
  printf '%s' "$f"
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
  local letterauto=( {A..Z} ) p pid src pname letter bankid stmt_b64 stmt_file skey bf html
  mkdir -p "$tdir/enunciados"
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    pid="$(jq -r '.problem_id // ""' <<<"$p")"; bankid="$(jq -r '.bank_id // ""' <<<"$p")"
    [[ -z "$pid" && -n "$bankid" ]] && pid="${bankid//#//}"
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
