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
    MOJ_PROBLEMS_DIR="$MOJ_PROBLEMS_DIR" CONTESTSDIR="$CONTESTSDIR" RUNDIR="${RUNDIR:-/home/ribas/moj/run}" \
      bash "$MOJTOOLS_DIR/gen-problem-owners.sh" >/dev/null 2>&1
    return
  fi
  if [[ -n "$(find "$f" -mmin "+$PROBLEM_OWNERS_TTL_MIN" 2>/dev/null)" ]]; then
    local lock="$f.lock"
    if mkdir "$lock" 2>/dev/null; then
      ( MOJ_PROBLEMS_DIR="$MOJ_PROBLEMS_DIR" CONTESTSDIR="$CONTESTSDIR" RUNDIR="${RUNDIR:-/home/ribas/moj/run}" \
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
  # o overlay authored dá visibilidade IMEDIATA ao recém-criado/editado, mas NÃO pode APAGAR os campos
  # que só o índice calcula (tl_checksum, public_at) — por isso é MESCLADO sobre a entrada do índice
  # (base + overlay, overlay vence campo-a-campo) em vez de substituí-la. Sem isso, todo problema no
  # overlay perdia tl_checksum/public_at (staleness e heatmap de entrada sub-reportados).
  jq -s '
    (.[0] // {problems:[]}) as $base
    | ((.[1] // {}) | [to_entries[].value]) as $ov
    | (($base.problems // []) | map({key:.id, value:.}) | from_entries) as $bmap
    | ($ov | map(.id)) as $ids
    | { problems: (($base.problems // []) | map(select((.id as $i | $ids|index($i)) | not)))
                  + ($ov | map(($bmap[.id] // {}) + .)) }
  ' "$OWNERS_INDEX" <(cat "$AUTHORED_INDEX" 2>/dev/null || echo '{}') 2>/dev/null
}

# owners_visible — {problems:[...]} PRÉ-FILTRADO ao que $SESSION_LOGIN PODE VER (público OU dono OU
# colaborador). É A FRONTEIRA DE SEGURANÇA da gestão (a API garante o acesso, NÃO a interface):
# problema privado some das listagens — inclusive p/ .admin. Reusada por owners_emit E
# /problems/status; ter UMA definição só evita divergência do filtro (que é o ponto crítico).
owners_visible(){
  owners_merged \
    | jq -c --arg _me "$SESSION_LOGIN" '.problems |= map(select(.public or .owner==$_me or ((.collaborators // [])|index($_me)|type=="number")))'
}
# owners_emit <jq-program> [jq-args...] — emite {success,...} aplicando o programa sobre o objeto JÁ
# FILTRADO (com .problems só visíveis). Use $login/$name já passados via --arg pelos handlers.
owners_emit(){
  local prog="$1"; shift
  emit_json 200 OK
  owners_visible | jq -c "$@" "$prog" 2>/dev/null || jq -cn '{success:true, problems:[]}'
}

# calibrating_set -> ["<id>",...] em calibração AGORA. Uma varredura só das TRÊS filas de calibração:
# run/updates/{pending,inprogress} (kind=="calibrate"; pending mistura kind=="index", por isso o
# filtro) + run/commands/<host> (action=="calibrate", recalibração direcionada). Conjunto pequeno ->
# o chamador junta com INDEX(.) p/ testar pertinência em O(1). Sem evento de conclusão: "done" é
# inferido pelo run/tl/<id>.json mais novo (best-effort; pode piscar no meio do voo).
calibrating_set(){
  local _ud="${UPDATESDIR:-${RUNDIR:-/home/ribas/moj/run}/updates}"
  local _cd="${CMDDIR:-${RUNDIR:-/home/ribas/moj/run}/commands}"
  { find "$_ud/pending" "$_ud/inprogress" -name '*.json' -exec cat {} + 2>/dev/null \
      | jq -r 'select(.kind=="calibrate") | .target // empty'
    find "$_cd" -mindepth 2 -name '*.json' -exec cat {} + 2>/dev/null \
      | jq -r 'select(.action=="calibrate") | .id // empty'
  } 2>/dev/null | LC_ALL=C sort -u | jq -Rc '[inputs|select(length>0)]' 2>/dev/null || echo '[]'
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
# authored_remove <id> — tira a entrada do overlay (problema removido -> some na hora das listas)
authored_remove(){
  local f="$AUTHORED_INDEX" cur tmp; cur="$(cat "$f" 2>/dev/null)"; [[ -n "$cur" ]] || return 0
  tmp="$f.tmp.$$"
  ( umask 077; jq --arg id "$1" 'del(.[$id])' <<<"$cur" ) > "$tmp" 2>/dev/null && mv -f "$tmp" "$f"
}

# norm <txt> -> minúsculas, sem acento, só [a-z0-9 ] (espelha gen-problem-owners.sh)
prob_norm(){ printf '%s' "$1" | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9 ' ' ' | tr -s ' '; }

# ---- autoria: registro de diretórios (repo Gitea) -> dono(login) --------------------------
REPO_REGISTRY="$CONTESTSDIR/treino/var/problem-repos.json"
repo_owner(){ [[ -f "$REPO_REGISTRY" ]] && jq -r --arg r "$1" '.[$r].owner // empty' "$REPO_REGISTRY" 2>/dev/null; }

# ---- storage MOJ-nativo: repo git LOCAL por problema (sem Gitea) --------------------------
# O canônico É a árvore de trabalho em $MOJ_PROBLEMS_DIR/<org>/<prob> (pkg_path lê dela direto). O
# servidor commita local p/ auditoria; NÃO há mirror, push, remote nem token. ensure_repo_materialized
# vira no-op (o pacote já está no lugar) — mantida só p/ não quebrar chamadas remanescentes.
ensure_repo_materialized(){ return 0; }

# _need_orgs — garante lib/orgs.sh carregada (acesso por org). Idempotente.
_need_orgs(){ declare -F org_is_member >/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/orgs.sh" 2>/dev/null; }

# problem_commit <pkgdir> <login> <msg> -> HEAD sha. git init idempotente + add -A + commit autorado
# pelo login. flock POR-PROBLEMA (dois saves no mesmo problema não corrompem a árvore/índice git).
problem_commit(){
  local pkg="$1" login="${2:-moj}" msg="${3:-update}" em="${2:-moj}@moj.local" lk
  [[ -d "$pkg" ]] || return 1
  mkdir -p "${RUNDIR:-/home/ribas/moj/run}/locks" 2>/dev/null
  lk="${RUNDIR:-/home/ribas/moj/run}/locks/$(printf '%s' "$pkg" | md5sum 2>/dev/null | cut -c1-24).lock"
  (
    flock 9 2>/dev/null
    cd "$pkg" || exit 1
    if [[ ! -d .git ]]; then
      git -c init.defaultBranch=master init -q 2>/dev/null
      printf 'tl\ntl.*\n' >> .git/info/exclude 2>/dev/null   # artefatos de calibração não entram no git
    fi
    git add -A 2>/dev/null
    GIT_AUTHOR_NAME="$login" GIT_AUTHOR_EMAIL="$em" GIT_COMMITTER_NAME="$login" GIT_COMMITTER_EMAIL="$em" \
      git commit -q -m "$msg" 2>/dev/null || true   # "nada a commitar" não é erro
    git rev-parse HEAD 2>/dev/null
  ) 9>"$lk"
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
# (Coleções/repos como MOTOR DE ACESSO foram substituídos pelas ORGS — ver lib/orgs.sh. O campo
#  .moj-meta.json collections continua existindo como TAG de exibição, sem propagar colaborador.)
# grant_problem_collections — NO-OP no modelo por ORG (acesso = ser MEMBRO da org).
grant_problem_collections(){ return 0; }

# problem_access <id> <login> -> mine|shared|public|denied|unknown
# (denied = existe, é privado e o login não é dono/colaborador; unknown = fora do índice)
problem_access(){
  local id="$1" me="$2" org="${1%%#*}" p owner pub
  ensure_owners_index
  p="$(owners_merged | jq -c --arg id "$id" 'first(.problems[]|select(.id==$id)) // empty' 2>/dev/null)"
  [[ -n "$p" ]] || { printf 'unknown'; return; }
  owner="$(jq -r '.owner // empty' <<<"$p")"; pub="$(jq -r 'if .public then 1 else 0 end' <<<"$p")"
  [[ "$owner" == "$me" ]] && { printf 'mine'; return; }
  _need_orgs
  org_is_member "$org" "$me" && { printf 'shared'; return; }
  [[ "$pub" == 1 ]] && { printf 'public'; return; }
  printf 'denied'
}
# require_problem_edit <id> — CORTA NA API (404) se o login não for MEMBRO da ORG do problema. Use nos
# endpoints que devolvem source/pacote/soluções/calibração (conteúdo sensível). Acesso = membro da org
# (org_is_member; membros+admins). SEM atalho de .admin. 404 (não 403) p/ não revelar a EXISTÊNCIA de um
# problema privado. A trava está AQUI na API, nunca só na interface.
require_problem_edit(){
  local id="$1" org="${1%%#*}"
  _need_orgs
  org_is_member "$org" "$SESSION_LOGIN" || fail 404 "Problema não encontrado" "not_found"
}
# require_problem_view <id> — CORTA (404) se o problema é PRIVADO e o login não é dono/colaborador.
# Público => qualquer um vê o detalhe/metadados (mas não o source/pacote -> require_problem_edit).
require_problem_view(){
  local acc; acc="$(problem_access "$1" "$SESSION_LOGIN")"
  [[ "$acc" == mine || "$acc" == shared || "$acc" == public ]] || fail 404 "Problema não encontrado" "not_found"
}

# problem_owner <id> -> login dono (overlay authored -> índice -> registro de repos). Vazio se desconhecido.
problem_owner(){
  local id="$1" o pk
  o="$(jq -r --arg id "$id" '.[$id].owner // empty' "$AUTHORED_INDEX" 2>/dev/null)"
  [[ -n "$o" ]] && { printf '%s' "$o"; return; }
  ensure_owners_index
  o="$(jq -r --arg id "$id" 'first(.problems[]|select(.id==$id)).owner // empty' "$OWNERS_INDEX" 2>/dev/null)"
  [[ -n "$o" ]] && { printf '%s' "$o"; return; }
  declare -F pkg_path >/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/tl-store.sh" 2>/dev/null
  pk="$(pkg_path "$id" 2>/dev/null)"; [[ -n "$pk" && -f "$pk/.moj-meta.json" ]] && jq -r '.owner // empty' "$pk/.moj-meta.json" 2>/dev/null
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
      gg="$(_norm_globs "$(jq -r '.glob // empty' <<<"$grp")")"; gg="${gg%%,*}"; [[ -n "$gg" ]] || gg="${gn}_*"  # só o 1º glob (prefixo p/ renomear teste fixado)
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
          gg="$(_norm_globs "$(jq -r '.glob // empty' <<<"$grp")")"; [[ -n "$gg" ]] || gg="${gn}_*"  # preserva a lista multi-glob (", "-separada)
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
# _norm_globs <raw> -> globs saneados, separados por ", " (um grupo pode ter VÁRIOS globs).
# Vírgula -> espaço; read NUNCA faz glob de path (seguro mesmo sem noglob); rejunta com ", "
# (o separador que o juiz, mojtools/score-summary.sh, tolera — o espaço é obrigatório p/ o
# word-split de lá). Entrada vazia/sem token válido -> "".
_norm_globs(){
  local raw="${1//,/ }" out="" tok; local IFS=$' \t\n'; local -a _ng
  raw="$(printf '%s' "$raw" | tr -cd 'A-Za-z0-9._* -')"   # mantém espaço; solta o resto
  read -ra _ng <<<"$raw"
  for tok in "${_ng[@]}"; do out="${out:+$out, }$tok"; done
  printf '%s' "$out"
}
# _read_score <pkgdir> -> {enabled, groups:[{name,weight,glob}]} a partir de tests/score
# (ignora a linha sample* dos exemplos). Ausente/vazio -> {enabled:false, groups:[]}.
# glob preserva a lista multi-glob (", "-separada); name deriva do PRIMEIRO glob.
_read_score(){
  local pkg="$1" sf="$1/tests/score"   # $1 (não $pkg): num mesmo `local`, o RHS não enxerga o LHS anterior
  [[ -f "$sf" ]] || { printf '{"enabled":false,"groups":[]}'; return; }
  local groups='[]' g s glob w name first
  while IFS='-' read -r g s; do
    glob="$(_norm_globs "$g")"
    [[ -z "$glob" || "$glob" == sample* ]] && continue
    w="$(printf '%s' "$s" | tr -cd '0-9')"; w=${w:-0}
    first="${glob%%,*}"; name="${first%\**}"; name="${name%_}"
    groups="$(jq -c --arg n "$name" --argjson w "$w" --arg gl "$glob" '. + [{name:$n,weight:$w,glob:$gl}]' <<<"$groups")"
  done < "$sf"
  jq -cn --argjson g "$groups" '{enabled:true, groups:$g}'
}
# read_problem_source <pkgdir> -> JSON editável do pacote (enunciado/autor/tags/conf/exemplos/
# testes/soluções good + public/collections/title do .moj-meta.json). Também lista scripts/ (correção
# especial) como caminhos relativos no campo `scripts` — SÓ leitura (não escrito por apply_problem_fields).
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
  # scripts/ (correção especial: compare/compile por linguagem) -> caminhos relativos, SÓ p/ exibir na árvore do pacote
  local tscr; tscr="$(mktemp)"
  [[ -d "$pkg/scripts" ]] && ( cd "$pkg/scripts" && find . -type f -printf '%P\n' 2>/dev/null ) | LC_ALL=C sort > "$tscr"
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
        --rawfile scr "$tscr" \
        --argjson tags "$tags" --argjson meta "$meta" --argjson score "$score" --arg fmt "$fmt" \
        --slurpfile exs "$d/exs" --slurpfile tss "$d/tss" \
        --slurpfile sg "$d/sg" --slurpfile ss "$d/ss" --slurpfile sw "$d/sw" --slurpfile sp "$d/sp" --slurpfile su "$d/su" '
    { format:$fmt, enunciado_md:$enun, author:($author|rtrimstr("\n")), conf_text:$conf,
      tags:$tags, public:($meta.public // false), collections:($meta.collections // []),
      title:($meta.display_title // ""), examples:$exs, tests:$tss, score:$score,
      scripts:($scr | split("\n") | map(select(. != ""))),
      editorial_md:$editorial, sols:{good:$sg, slow:$ss, wrong:$sw, pass:$sp, upcoming:$su} }'
  rm -rf "$d"; rm -f "$te" "$ta" "$tc" "$ted" "$tscr"
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

# _derive_title <pkgdir> -> título do enunciado (%/#+title/\section) ou, em último caso, o nome do
# problema (slug). NUNCA vazio. Mesmo idioma de extração do mojtools/gen-problem-json.sh.
_derive_title(){
  local pkg="$1" t=""
  if [[ -f "$pkg/docs/enunciado.md" ]]; then
    t="$(grep -m1 '^%' "$pkg/docs/enunciado.md" 2>/dev/null | sed 's/^%[[:space:]]*//')"
  elif [[ -f "$pkg/docs/enunciado.org" ]]; then
    t="$(grep -m1 -i '^#+title:' "$pkg/docs/enunciado.org" 2>/dev/null | sed 's/^#+[Tt][Ii][Tt][Ll][Ee]:[[:space:]]*//')"
  elif [[ -f "$pkg/docs/enunciado.tex" ]]; then
    t="$(grep -m1 -E '\\(section|title)\{' "$pkg/docs/enunciado.tex" 2>/dev/null | sed -E 's/.*\\(section|title)\{([^}]*)\}.*/\2/')"
  fi
  [[ -n "$t" ]] || t="$(basename "$pkg")"
  printf '%s' "$t"
}

# write_meta <pkgdir> <owner> <repo> [public:true|false|""] [collections-json|""] [display_title]
# BLINDAGEM: display_title nunca fica ausente — se não veio título E o meta ainda não tem um,
# deriva do enunciado/slug (_derive_title). Assim o editor nunca vem em branco e as 3 telas (editor,
# treino, gestão) ficam consistentes. Meta que já tem título não muda (o merge $cur+{} preserva).
write_meta(){
  local pkg="$1" owner="$2" repo="$3" pub="${4:-}" colls="${5:-}" title="${6:-}" cur='{}'
  [[ -f "$pkg/.moj-meta.json" ]] && cur="$(cat "$pkg/.moj-meta.json" 2>/dev/null)"; [[ -n "$cur" ]] || cur='{}'
  if [[ -z "$title" && -z "$(jq -r '.display_title // empty' <<<"$cur" 2>/dev/null)" ]]; then
    title="$(_derive_title "$pkg")"
  fi
  jq -n --argjson cur "$cur" --arg o "$owner" --arg r "$repo" --arg pub "$pub" \
        --argjson colls "${colls:-null}" --arg title "$title" --argjson now "$EPOCHSECONDS" '
    $cur + {owner:$o, gitea:{owner:$o, repo:$r}}
    + (if $pub=="" then {} elif $pub=="true" then {public:true} else {public:false} end)
    + (if $colls==null then {} else {collections:$colls} end)
    + (if $title=="" then {} else {display_title:$title} end)
    # carimba a 1ª publicação (permanece ao despublicar); alimenta o heatmap "entrada de públicos"
    + (if $pub=="true" and (($cur.public_at // null)==null) then {public_at:$now} else {} end)
  ' > "$pkg/.moj-meta.json"
}
