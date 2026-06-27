# lib/problems.sh — apoio aos handlers de gestão de problemas (Meus/Compartilhados/Públicos/
# Coleções). Serve o índice de donos (contests/treino/var/problem-owners.json) e o regenera
# em BACKGROUND quando velho (nunca bloqueia o request, exceto na 1ª geração a frio).
: "${MOJTOOLS_DIR:=/home/ribas/moj/mojtools}"
: "${PROBLEM_OWNERS_TTL_MIN:=30}"
OWNERS_INDEX="$CONTESTSDIR/treino/var/problem-owners.json"

# ensure_owners_index — garante que o índice exista; se velho, dispara regen em background.
ensure_owners_index(){
  local f="$OWNERS_INDEX"
  if [[ ! -f "$f" ]]; then
    MOJ_PROBLEMS_DIR="$MOJ_PROBLEMS_DIR" CONTESTSDIR="$CONTESTSDIR" \
      bash "$MOJTOOLS_DIR/gen-problem-owners.sh" >/dev/null 2>&1
    return
  fi
  if [[ -n "$(find "$f" -mmin "+$PROBLEM_OWNERS_TTL_MIN" 2>/dev/null)" ]]; then
    local lock="$f.lock"
    if mkdir "$lock" 2>/dev/null; then
      ( MOJ_PROBLEMS_DIR="$MOJ_PROBLEMS_DIR" CONTESTSDIR="$CONTESTSDIR" \
        setsid bash -c 'bash "$1" >/dev/null 2>&1; rmdir "$2" 2>/dev/null' \
          _ "$MOJTOOLS_DIR/gen-problem-owners.sh" "$lock" & ) 2>/dev/null
    fi
  fi
}

AUTHORED_INDEX="$CONTESTSDIR/treino/var/authored.json"   # overlay de problemas recém-criados no Gitea

# owners_merged — emite {problems:[...]} mesclando o índice gerado (NFS) + o overlay authored
# (Gitea recém-autorado vence por id). Dá visibilidade IMEDIATA ao que foi criado/editado.
owners_merged(){
  ensure_owners_index
  jq -s '
    (.[0] // {problems:[]}) as $base
    | ((.[1] // {}) | [to_entries[].value]) as $ov
    | ($ov | map(.id)) as $ids
    | { problems: (($base.problems // []) | map(select((.id as $i | $ids|index($i)) | not))) + $ov }
  ' "$OWNERS_INDEX" <(cat "$AUTHORED_INDEX" 2>/dev/null || echo '{}') 2>/dev/null
}

# owners_emit <jq-program> [jq-args...] — emite {success,...} aplicando o programa sobre o
# objeto mesclado (com .problems). Use $login/$name já passados via --arg pelos handlers.
owners_emit(){
  local prog="$1"; shift
  emit_json 200 OK
  owners_merged | jq -c "$@" "$prog" 2>/dev/null || jq -cn '{success:true, problems:[]}'
}

# authored_upsert <id> <owner> <repo> <prob> <title> <public:true|false> <collections-json> <author> [collabs-json]
authored_upsert(){
  local f="$AUTHORED_INDEX" cur tmp; cur="$(cat "$f" 2>/dev/null)"; [[ -n "$cur" ]] || cur='{}'
  mkdir -p "$(dirname "$f")" 2>/dev/null; tmp="$f.tmp.$$"
  ( umask 077; jq -n --argjson cur "$cur" --arg id "$1" --arg o "$2" --arg r "$3" --arg p "$4" \
      --arg t "$5" --arg pub "$6" --argjson colls "${7:-[]}" --arg au "$8" --argjson cb "${9:-[]}" '
      ($cur[$id] // {}) as $old
      | $cur + { ($id): ($old + {
          id:$id, owner:$o, repo:$r, prob:$p,
          title:(if $t=="" then ($old.title // $p) else $t end),
          author:$au, author_norm:($au|ascii_downcase),
          collaborators:$cb, collections:$colls, public:($pub=="true"), html:false }) }
    ' ) > "$tmp" 2>/dev/null && mv -f "$tmp" "$f"
}
# authored_patch <id> <jq-expr-sobre-a-entrada> [jq-args...] — patch parcial de 1 entrada
authored_patch(){
  local id="$1" expr="$2"; shift 2
  local f="$AUTHORED_INDEX" cur tmp; cur="$(cat "$f" 2>/dev/null)"; [[ -n "$cur" ]] || return 0
  tmp="$f.tmp.$$"
  ( umask 077; jq "$@" --arg _id "$id" "if has(\$_id) then .[\$_id] |= ($expr) else . end" <<<"$cur" ) \
    > "$tmp" 2>/dev/null && mv -f "$tmp" "$f"
}
# authored_set_repo_collabs <repo> <collabs-json> — propaga colaboradores a todas as entradas do repo
authored_set_repo_collabs(){
  local f="$AUTHORED_INDEX" cur tmp; cur="$(cat "$f" 2>/dev/null)"; [[ -n "$cur" ]] || return 0
  tmp="$f.tmp.$$"
  ( umask 077; jq --arg r "$1" --argjson cb "$2" \
      'with_entries(if .value.repo==$r then .value.collaborators=$cb else . end)' <<<"$cur" ) \
    > "$tmp" 2>/dev/null && mv -f "$tmp" "$f"
}

# norm <txt> -> minúsculas, sem acento, só [a-z0-9 ] (espelha gen-problem-owners.sh)
prob_norm(){ printf '%s' "$1" | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9 ' ' ' | tr -s ' '; }

# ---- autoria: registro de diretórios (repo Gitea) -> dono(login) --------------------------
REPO_REGISTRY="$CONTESTSDIR/treino/var/problem-repos.json"
repo_owner(){ [[ -f "$REPO_REGISTRY" ]] && jq -r --arg r "$1" '.[$r].owner // empty' "$REPO_REGISTRY" 2>/dev/null; }

# ensure_repo_materialized <repo> [login] — espelha o repo Gitea em $MOJ_PROBLEMS_DIR/<repo>
# (clona se faltar; senão fetch + reset --hard) para o INDEXADOR e os endpoints
# /judge/package(-meta) acharem o pacote (pkg_path lê de MOJ_PROBLEMS_DIR). Repo sem dono no
# registro = desconhecido (não-Gitea) -> nada a materializar. Best-effort (rc!=0 não derruba o caller).
# Sem isso, um problema criado no Gitea fica invisível para os juízes ("pkg inexistente").
ensure_repo_materialized(){
  local repo="$1" login="${2:-}" owner dst tok
  owner="$(repo_owner "$repo")"; [[ -n "$owner" ]] || return 0   # repo não registrado (não-Gitea)
  declare -F git_broker_clone >/dev/null || source "$MOJTOOLS_DIR/git-broker.sh" 2>/dev/null
  declare -F git_broker_clone >/dev/null || return 1
  [[ -n "$login" ]] || login="$owner"
  dst="$MOJ_PROBLEMS_DIR/$repo"; tok="$(_gb_token "$login" 2>/dev/null)"; [[ -n "$tok" ]] || return 1
  if [[ -d "$dst/.git" ]]; then
    git_broker_run "$login" "$tok" "$dst" fetch -q origin 2>/dev/null \
      && git_broker_run "$login" "$tok" "$dst" reset -q --hard '@{u}' 2>/dev/null
  else
    mkdir -p "$(dirname "$dst")" 2>/dev/null
    git_broker_clone "$login" "$owner" "$repo" "$dst" 2>/dev/null
  fi
}
repo_register(){  # <repo> <owner> [collections-csv]
  local r="$1" o="$2" c="${3:-}" cur tmp; cur="$(cat "$REPO_REGISTRY" 2>/dev/null)"; [[ -n "$cur" ]] || cur='{}'
  mkdir -p "$(dirname "$REPO_REGISTRY")" 2>/dev/null; tmp="$REPO_REGISTRY.tmp.$$"
  ( umask 077; jq -n --argjson cur "$cur" --arg r "$r" --arg o "$o" --arg c "$c" --argjson now "$EPOCHSECONDS" '
      ($cur[$r] // {}) as $old
      | $cur + { ($r): ($old + {owner:$o, collections:($c|split(",")|map(select(length>0))), at:$now,
                                collaborators:($old.collaborators // []) }) }' ) > "$tmp" 2>/dev/null \
    && mv -f "$tmp" "$REPO_REGISTRY"
}
repo_collabs(){ [[ -f "$REPO_REGISTRY" ]] && jq -c --arg r "$1" '.[$r].collaborators // []' "$REPO_REGISTRY" 2>/dev/null; }
repo_set_collabs(){  # <repo> <collabs-json>
  local r="$1" cb="$2" cur tmp; cur="$(cat "$REPO_REGISTRY" 2>/dev/null)"; [[ -n "$cur" ]] || return 0
  tmp="$REPO_REGISTRY.tmp.$$"
  ( umask 077; jq --arg r "$r" --argjson cb "$cb" 'if has($r) then .[$r].collaborators=$cb else . end' <<<"$cur" ) \
    > "$tmp" 2>/dev/null && mv -f "$tmp" "$REPO_REGISTRY"
}
# ---- coleções (competição/curso) com grupo de setters -------------------------------------
COLLECTIONS_REGISTRY="$CONTESTSDIR/treino/var/collections.json"
collection_owner(){ [[ -f "$COLLECTIONS_REGISTRY" ]] && jq -r --arg n "$1" '.[$n].owner // empty' "$COLLECTIONS_REGISTRY" 2>/dev/null; }
collection_members(){ local m; [[ -f "$COLLECTIONS_REGISTRY" ]] && m="$(jq -c --arg n "$1" '.[$n].members // []' "$COLLECTIONS_REGISTRY" 2>/dev/null)"; printf '%s' "${m:-[]}"; }
collection_admins(){ local a; [[ -f "$COLLECTIONS_REGISTRY" ]] && a="$(jq -c --arg n "$1" '.[$n].admins // []' "$COLLECTIONS_REGISTRY" 2>/dev/null)"; printf '%s' "${a:-[]}"; }
# quem pode editar uma problema da coleção = membros ∪ admins (co-organizadores)
collection_access(){ jq -cn --argjson m "$(collection_members "$1")" --argjson a "$(collection_admins "$1")" '($m+$a)|unique'; }
# collection_can_manage <name> <login> — dono OU admin da coleção OU admin global do treino
collection_can_manage(){
  local n="$1" login="$2" o; o="$(collection_owner "$n")"; [[ -n "$o" ]] || return 1
  [[ "$login" == "$o" ]] && return 0
  { declare -F is_admin >/dev/null && is_admin; } && return 0
  jq -e --arg u "$login" 'index($u)' >/dev/null 2>&1 <<<"$(collection_admins "$n")"
}
collection_register(){  # <name> <owner> [members-csv] [title] [admins-csv]
  local n="$1" o="$2" m="${3:-}" t="${4:-}" a="${5:-}" cur tmp; cur="$(cat "$COLLECTIONS_REGISTRY" 2>/dev/null)"; [[ -n "$cur" ]] || cur='{}'
  mkdir -p "$(dirname "$COLLECTIONS_REGISTRY")" 2>/dev/null; tmp="$COLLECTIONS_REGISTRY.tmp.$$"
  ( umask 077; jq -n --argjson cur "$cur" --arg n "$n" --arg o "$o" --arg m "$m" --arg t "$t" --arg a "$a" --argjson now "$EPOCHSECONDS" '
      ($cur[$n] // {}) as $old
      | $cur + { ($n): ($old + { owner:($old.owner // $o),
                  title:(if $t=="" then ($old.title // $n) else $t end),
                  members:((($old.members // []) + ($m|split(",")|map(select(length>0)))) | unique),
                  admins:((($old.admins // []) + ($a|split(",")|map(select(length>0)))) | unique), at:$now }) }' ) >"$tmp" 2>/dev/null \
    && mv -f "$tmp" "$COLLECTIONS_REGISTRY"
}
collection_set_field(){  # <name> <field> <json>  (members|admins)
  local n="$1" k="$2" v="$3" cur tmp; cur="$(cat "$COLLECTIONS_REGISTRY" 2>/dev/null)"; [[ -n "$cur" ]] || return 0
  tmp="$COLLECTIONS_REGISTRY.tmp.$$"
  ( umask 077; jq --arg n "$n" --arg k "$k" --argjson v "$v" 'if has($n) then .[$n][$k]=$v else . end' <<<"$cur" ) >"$tmp" 2>/dev/null && mv -f "$tmp" "$COLLECTIONS_REGISTRY"
}
collection_set_members(){ collection_set_field "$1" members "$2"; }
collection_set_admins(){  collection_set_field "$1" admins  "$2"; }
# collection_grant_repo <name> <repo> <acting> — membros+admins da coleção viram colaboradores
# do repo (só se o acting for dono do repo ou admin). Espelha no registro/overlay. Best-effort.
collection_grant_repo(){
  local name="$1" repo="$2" acting="$3" owner m u; owner="$(repo_owner "$repo")"
  [[ -n "$owner" ]] || return 0
  { [[ "$acting" == "$owner" ]] || { declare -F is_admin >/dev/null && is_admin; }; } || return 0
  m="$(collection_access "$name")"; [[ "$m" != "[]" ]] || return 0
  while IFS= read -r u; do [[ -n "$u" && "$u" != "$owner" ]] || continue
    declare -F gitea_ensure_user >/dev/null && gitea_ensure_user "$u" "$u" "$u@moj.local" \
      && gitea_set_collaborator "$owner" "$repo" "$u" write
  done < <(jq -r '.[]?' <<<"$m" 2>/dev/null)
  local cur merged; cur="$(repo_collabs "$repo")"; cur="${cur:-[]}"
  merged="$(jq -cn --argjson a "$cur" --argjson b "$m" '($a+$b)|unique')"
  repo_set_collabs "$repo" "$merged"; authored_set_repo_collabs "$repo" "$merged"
}
# grant_problem_collections <id> <repo> <acting> — concede acesso aos membros de TODAS as
# coleções do problema (chamado após create/edit/set-collections).
grant_problem_collections(){
  local id="$1" repo="$2" acting="$3" c
  while IFS= read -r c; do [[ -n "$c" ]] && collection_grant_repo "$c" "$repo" "$acting"; done \
    < <(owners_merged | jq -r --arg id "$id" 'first(.problems[]|select(.id==$id)).collections[]?' 2>/dev/null)
}

# problem_access <id> <login> -> mine|shared|public|denied|unknown
# (denied = existe, é privado e o login não é dono/colaborador; unknown = fora do índice)
problem_access(){
  ensure_owners_index
  owners_merged | jq -r --arg id "$1" --arg me "$2" '
    (first(.problems[]|select(.id==$id))) as $p
    | if $p==null then "unknown"
      elif $p.owner==$me then "mine"
      elif (($p.collaborators // [])|index($me)) then "shared"
      elif $p.public then "public" else "denied" end' 2>/dev/null
}

# problem_owner <id> -> login dono (overlay authored -> índice -> registro de repos). Vazio se desconhecido.
problem_owner(){
  local id="$1" repo="${1%%#*}" o
  o="$(jq -r --arg id "$id" '.[$id].owner // empty' "$AUTHORED_INDEX" 2>/dev/null)"
  [[ -n "$o" ]] && { printf '%s' "$o"; return; }
  ensure_owners_index
  o="$(jq -r --arg id "$id" 'first(.problems[]|select(.id==$id)).owner // empty' "$OWNERS_INDEX" 2>/dev/null)"
  [[ -n "$o" ]] && { printf '%s' "$o"; return; }
  repo_owner "$repo"
}

# ---- autoria: materialização do pacote (escreve só os campos presentes no body) -----------
# grava o conteúdo de stdin num arquivo com EXATAMENTE 1 \n final (vazio continua vazio).
# Idempotente e auto-corretivo: sem isto, cada "Salvar" acumulava uma linha em branco nos
# arquivos (jq -r encerra a saída com \n; o valor lido já trazia o \n do arquivo).
_putfile(){ local f="$1" c; c="$(cat)"; if [[ -n "$c" ]]; then printf '%s\n' "$c" > "$f"; else : > "$f"; fi; }
apply_problem_fields(){  # <pkgdir> <body-json>
  local pkg="$1" body="$2"
  mkdir -p "$pkg/docs" "$pkg/tests/input" "$pkg/tests/output" "$pkg/sols/good"
  if jq -e 'has("enunciado_md")' >/dev/null 2>&1 <<<"$body"; then
    # preserva o FORMATO do enunciado (md/org/tex): usa o explícito, senão o do arquivo existente, senão md
    local efmt; efmt="$(jq -r '.enunciado_format // empty' <<<"$body")"
    if [[ -z "$efmt" ]]; then for e in md org tex; do [[ -f "$pkg/docs/enunciado.$e" ]] && { efmt="$e"; break; }; done; fi
    [[ "$efmt" =~ ^(md|org|tex)$ ]] || efmt=md
    local e; for e in md org tex; do [[ "$e" != "$efmt" && -f "$pkg/docs/enunciado.$e" ]] && rm -f "$pkg/docs/enunciado.$e"; done
    jq -r '.enunciado_md' <<<"$body" | _putfile "$pkg/docs/enunciado.$efmt"
  fi
  jq -e 'has("author")'       >/dev/null 2>&1 <<<"$body" && jq -r '.author'       <<<"$body" > "$pkg/author"
  jq -e 'has("tags")'         >/dev/null 2>&1 <<<"$body" && jq -r '.tags[]?'       <<<"$body" > "$pkg/tags"
  jq -e 'has("conf_text")'    >/dev/null 2>&1 <<<"$body" && jq -r '.conf_text'     <<<"$body" | _putfile "$pkg/conf"
  if jq -e 'has("examples")' >/dev/null 2>&1 <<<"$body"; then
    find "$pkg/tests/input"  -name 'sample*' -delete 2>/dev/null
    find "$pkg/tests/output" -name 'sample*' -delete 2>/dev/null
    local i=0 pair
    while IFS= read -r pair; do i=$((i+1))
      jq -r '.input'  <<<"$pair" | _putfile "$pkg/tests/input/sample$i"
      jq -r '.output' <<<"$pair" | _putfile "$pkg/tests/output/sample$i"
    done < <(jq -c '.examples[]?' <<<"$body")
    # explicação por exemplo (na ordem) -> docs/sample-notes.json. Só mexe se o cliente for
    # "ciente de explicação" (algum exemplo traz a chave .explanation). Assim, clientes que não
    # enviam explicações (ex.: uma CLI antiga) NÃO apagam as notas já existentes.
    if jq -e 'any(.examples[]?; has("explanation"))' >/dev/null 2>&1 <<<"$body"; then
      local notes; notes="$(jq -c '[.examples[]? | (.explanation // "")]' <<<"$body")"
      if [[ "$(jq -r 'map(select(.!=""))|length' <<<"$notes" 2>/dev/null)" -gt 0 ]]; then
        printf '%s' "$notes" > "$pkg/docs/sample-notes.json"
      else rm -f "$pkg/docs/sample-notes.json"; fi
    fi
  fi
  # ---- resolução/editorial (só p/ setters; docs/solucao.md; não vai p/ o aluno) -------------
  if jq -e 'has("editorial_md")' >/dev/null 2>&1 <<<"$body"; then
    local edmd; edmd="$(jq -r '.editorial_md // ""' <<<"$body")"
    if [[ -n "$edmd" ]]; then printf '%s' "$edmd" > "$pkg/docs/solucao.md"; else rm -f "$pkg/docs/solucao.md"; fi
  fi
  # ---- pontuação por grupos (subtasks) ----------------------------------------
  # score = {enabled, groups:[{name,weight,glob}]}; cada teste pode trazer .group p/
  # ser FIXADO num grupo (renomeado p/ <prefixo>NN); sem .group, mantém o nome (auto,
  # casado pelo glob no juiz). Sem o campo "score" no body → comportamento legado.
  local SCORE_ENABLED=0
  declare -A GGLOB
  if jq -e '.score.enabled == true' >/dev/null 2>&1 <<<"$body"; then
    SCORE_ENABLED=1
    local grp gn gg
    while IFS= read -r grp; do
      gn="$(jq -r '.name // empty' <<<"$grp" | tr -cd 'A-Za-z0-9._-')"; [[ -n "$gn" ]] || continue
      gg="$(jq -r '.glob // empty' <<<"$grp" | tr -cd 'A-Za-z0-9._*-')"; [[ -n "$gg" ]] || gg="${gn}_*"
      GGLOB[$gn]="$gg"
    done < <(jq -c '.score.groups[]?' <<<"$body")
  fi
  if jq -e 'has("tests")' >/dev/null 2>&1 <<<"$body"; then
    # substitui os testes OCULTOS (mantém os sample*); remoções valem
    local inp nm0
    set +o noglob; shopt -s nullglob
    for inp in "$pkg/tests/input"/*; do nm0="$(basename "$inp")"; [[ "$nm0" == sample* ]] && continue
      rm -f "$inp" "$pkg/tests/output/$nm0"; done
    shopt -u nullglob; set -o noglob
    local i=0 pair nm tgrp gpre n cand
    while IFS= read -r pair; do i=$((i+1)); nm="$(jq -r '.name // empty' <<<"$pair" | tr -cd 'A-Za-z0-9._-')"; [[ -n "$nm" ]] || nm="$i"
      [[ "$nm" == sample* ]] && nm="t$nm"   # nomes sample* são reservados aos exemplos
      if (( SCORE_ENABLED )); then
        tgrp="$(jq -r '.group // empty' <<<"$pair" | tr -cd 'A-Za-z0-9._-')"
        if [[ -n "$tgrp" && -n "${GGLOB[$tgrp]:-}" ]]; then
          gpre="${GGLOB[$tgrp]%\**}"                         # g2_* -> g2_
          # FIXADO: mantém se já é <prefixo><dígitos> livre; senão pega o próximo <prefixo>NN livre
          if [[ "$nm" == "$gpre"* && "${nm#$gpre}" =~ ^[0-9]+$ && ! -e "$pkg/tests/input/$nm" ]]; then :
          else n=1; while cand="${gpre}$(printf '%02d' "$n")"; [[ -e "$pkg/tests/input/$cand" ]]; do n=$((n+1)); done; nm="$cand"; fi
        fi
      fi
      jq -r '.input'  <<<"$pair" | _putfile "$pkg/tests/input/$nm"
      jq -r '.output' <<<"$pair" | _putfile "$pkg/tests/output/$nm"
    done < <(jq -c '.tests[]?' <<<"$body")
  fi
  # grava/remove tests/score conforme o modo (só quando o body traz o campo "score")
  if jq -e 'has("score")' >/dev/null 2>&1 <<<"$body"; then
    if (( SCORE_ENABLED )); then
      { compgen -G "$pkg/tests/input/sample*" >/dev/null 2>&1 && echo "sample* - 0 pontos"
        local grp gn gg gw
        while IFS= read -r grp; do
          gn="$(jq -r '.name // empty' <<<"$grp" | tr -cd 'A-Za-z0-9._-')"; [[ -n "$gn" ]] || continue
          gg="$(jq -r '.glob // empty' <<<"$grp" | tr -cd 'A-Za-z0-9._*-')"; [[ -n "$gg" ]] || gg="${gn}_*"
          gw="$(jq -r '.weight // 0' <<<"$grp" | tr -cd '0-9')"; gw=${gw:-0}
          echo "$gg - $gw pontos"
        done < <(jq -c '.score.groups[]?' <<<"$body")
      } > "$pkg/tests/score"
    else
      rm -f "$pkg/tests/score"
    fi
  fi
  # soluções por categoria (substitui a categoria inteira quando presente)
  if jq -e 'has("sols")' >/dev/null 2>&1 <<<"$body"; then
    local cat s fn
    for cat in good slow wrong pass upcoming; do
      jq -e --arg c "$cat" '.sols | has($c)' >/dev/null 2>&1 <<<"$body" || continue
      rm -rf "$pkg/sols/$cat"; mkdir -p "$pkg/sols/$cat"
      while IFS= read -r s; do
        fn="$(basename "$(jq -r '.filename // empty' <<<"$s")")"; [[ "$fn" =~ ^[A-Za-z0-9._-]+$ ]] || continue
        jq -r '.code // ""' <<<"$s" | _putfile "$pkg/sols/$cat/$fn"
      done < <(jq -c --arg c "$cat" '.sols[$c][]?' <<<"$body")
    done
  fi
  # compat: good_sol único (CLI/legado) — adiciona a sols/good
  if jq -e 'has("good_sol")' >/dev/null 2>&1 <<<"$body"; then
    local fn; fn="$(basename "$(jq -r '.good_sol.filename // "sol.cpp"' <<<"$body")")"
    [[ "$fn" =~ ^[A-Za-z0-9._-]+$ ]] || fn="sol.cpp"
    jq -r '.good_sol.code // ""' <<<"$body" | _putfile "$pkg/sols/good/$fn"
  fi
}
# _read_pairs <pkgdir> <sample|hidden> <outfile> -> escreve NDJSON {name,input,output} (1/linha).
# Via jq --rawfile (lê os testes de ARQUIVO); o chamador junta com --slurpfile. Sem conteúdo de
# teste no argv (passar via --argjson estourava o ARG_MAX -> source vazio -> editor em branco).
_read_pairs(){
  local pkg="$1" which="$2" of="$3" inp nm outp
  : > "$of"
  set +o noglob; shopt -s nullglob
  for inp in "$pkg/tests/input"/*; do
    [[ -f "$inp" ]] || continue; nm="$(basename "$inp")"
    if [[ "$which" == sample ]]; then [[ "$nm" == sample* ]] || continue
    else [[ "$nm" == sample* ]] && continue; fi
    outp="$pkg/tests/output/$nm"; [[ -f "$outp" ]] || outp=/dev/null
    jq -nc --arg nm "$nm" --rawfile i "$inp" --rawfile o "$outp" '{name:$nm, input:$i, output:$o}' >> "$of"
  done
  shopt -u nullglob; set -o noglob
}
# _read_score <pkgdir> -> {enabled, groups:[{name,weight,glob}]} a partir de tests/score
# (ignora a linha sample* dos exemplos). Ausente/vazio -> {enabled:false, groups:[]}.
_read_score(){
  local pkg="$1" sf="$pkg/tests/score"
  [[ -f "$sf" ]] || { printf '{"enabled":false,"groups":[]}'; return; }
  local groups='[]' g s glob w name
  while IFS='-' read -r g s; do
    glob="$(printf '%s' "$g" | tr -d '[:space:],')"
    [[ -z "$glob" || "$glob" == sample* ]] && continue
    w="$(printf '%s' "$s" | tr -cd '0-9')"; w=${w:-0}
    name="${glob%\**}"; name="${name%_}"
    groups="$(jq -c --arg n "$name" --argjson w "$w" --arg gl "$glob" '. + [{name:$n,weight:$w,glob:$gl}]' <<<"$groups")"
  done < "$sf"
  jq -cn --argjson g "$groups" '{enabled:true, groups:$g}'
}
# read_problem_source <pkgdir> -> JSON editável do pacote (enunciado/autor/tags/conf/exemplos/
# testes/soluções good + public/collections/title do .moj-meta.json).
read_problem_source(){
  local pkg="$1" enunf="" fmt="md" ef
  for ef in docs/enunciado.md enunciado.md docs/enunciado.org docs/enunciado.tex; do
    [[ -f "$pkg/$ef" ]] && { enunf="$pkg/$ef"; [[ "$ef" == *.org ]] && fmt=org; [[ "$ef" == *.tex ]] && fmt=tex; break; }
  done
  local te ta tc ted; te="$(mktemp)"; ta="$(mktemp)"; tc="$(mktemp)"; ted="$(mktemp)"
  [[ -n "$enunf" ]] && cat "$enunf" > "$te"
  [[ -f "$pkg/author" ]] && cat "$pkg/author" > "$ta"
  [[ -f "$pkg/conf" ]] && cat "$pkg/conf" > "$tc"
  [[ -f "$pkg/docs/solucao.md" ]] && cat "$pkg/docs/solucao.md" > "$ted"   # editorial (só setters)
  local tags='[]'; [[ -f "$pkg/tags" ]] && tags="$(jq -R . "$pkg/tags" 2>/dev/null | jq -sc . 2>/dev/null)"; [[ -n "$tags" ]] || tags='[]'
  local meta='{}'; [[ -f "$pkg/.moj-meta.json" ]] && meta="$(cat "$pkg/.moj-meta.json" 2>/dev/null)"; [[ -n "$meta" ]] || meta='{}'
  local score; score="$(_read_score "$pkg")"
  # exemplos/testes/soluções -> NDJSON em arquivos; entram no jq por --slurpfile (jq lê o arquivo).
  # ANTES: --argjson tss "$tss" estourava o ARG_MAX em problema com muitos testes -> source VAZIO -> editor em branco.
  local d; d="$(mktemp -d)"
  _read_pairs "$pkg" sample "$d/exs"; _read_pairs "$pkg" hidden "$d/tss"
  _read_sols "$pkg" good "$d/sg"; _read_sols "$pkg" slow "$d/ss"; _read_sols "$pkg" wrong "$d/sw"
  _read_sols "$pkg" pass "$d/sp"; _read_sols "$pkg" upcoming "$d/su"
  # explicação por exemplo (docs/sample-notes.json, na ordem) -> examples[].explanation
  local notes='[]'; [[ -f "$pkg/docs/sample-notes.json" ]] && notes="$(cat "$pkg/docs/sample-notes.json" 2>/dev/null)"; jq -e . >/dev/null 2>&1 <<<"$notes" || notes='[]'
  jq -cn --slurpfile all "$d/exs" --argjson n "$notes" \
     '$all | to_entries[] | .value + {explanation: ($n[.key] // "")}' > "$d/exs2" 2>/dev/null && mv -f "$d/exs2" "$d/exs"
  jq -n --rawfile enun "$te" --rawfile author "$ta" --rawfile conf "$tc" --rawfile editorial "$ted" \
        --argjson tags "$tags" --argjson meta "$meta" --argjson score "$score" --arg fmt "$fmt" \
        --slurpfile exs "$d/exs" --slurpfile tss "$d/tss" \
        --slurpfile sg "$d/sg" --slurpfile ss "$d/ss" --slurpfile sw "$d/sw" --slurpfile sp "$d/sp" --slurpfile su "$d/su" '
    { format:$fmt, enunciado_md:$enun, author:($author|rtrimstr("\n")), conf_text:$conf,
      tags:$tags, public:($meta.public // false), collections:($meta.collections // []),
      title:($meta.display_title // ""), examples:$exs, tests:$tss, score:$score,
      editorial_md:$editorial, sols:{good:$sg, slow:$ss, wrong:$sw, pass:$sp, upcoming:$su} }'
  rm -rf "$d"; rm -f "$te" "$ta" "$tc" "$ted"
}
# _read_sols <pkgdir> <cat> <outfile> -> escreve NDJSON {filename,code} (1/linha) de sols/<cat>/*
_read_sols(){
  local pkg="$1" cat="$2" of="$3" f
  : > "$of"
  set +o noglob; shopt -s nullglob
  for f in "$pkg/sols/$cat"/*; do [[ -f "$f" ]] || continue
    jq -nc --arg fn "$(basename "$f")" --rawfile code "$f" '{filename:$fn, code:$code}' >> "$of"
  done
  shopt -u nullglob; set -o noglob
}

# write_meta <pkgdir> <owner> <repo> [public:true|false|""] [collections-json|""] [display_title]
write_meta(){
  local pkg="$1" owner="$2" repo="$3" pub="${4:-}" colls="${5:-}" title="${6:-}" cur='{}'
  [[ -f "$pkg/.moj-meta.json" ]] && cur="$(cat "$pkg/.moj-meta.json" 2>/dev/null)"; [[ -n "$cur" ]] || cur='{}'
  jq -n --argjson cur "$cur" --arg o "$owner" --arg r "$repo" --arg pub "$pub" \
        --argjson colls "${colls:-null}" --arg title "$title" '
    $cur + {owner:$o, gitea:{owner:$o, repo:$r}}
    + (if $pub=="" then {} elif $pub=="true" then {public:true} else {public:false} end)
    + (if $colls==null then {} else {collections:$colls} end)
    + (if $title=="" then {} else {display_title:$title} end)
  ' > "$pkg/.moj-meta.json"
}
