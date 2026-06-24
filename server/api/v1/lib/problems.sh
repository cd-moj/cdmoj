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
apply_problem_fields(){  # <pkgdir> <body-json>
  local pkg="$1" body="$2"
  mkdir -p "$pkg/docs" "$pkg/tests/input" "$pkg/tests/output" "$pkg/sols/good"
  jq -e 'has("enunciado_md")' >/dev/null 2>&1 <<<"$body" && jq -r '.enunciado_md' <<<"$body" > "$pkg/docs/enunciado.md"
  jq -e 'has("author")'       >/dev/null 2>&1 <<<"$body" && jq -r '.author'       <<<"$body" > "$pkg/author"
  jq -e 'has("tags")'         >/dev/null 2>&1 <<<"$body" && jq -r '.tags[]?'       <<<"$body" > "$pkg/tags"
  jq -e 'has("conf_text")'    >/dev/null 2>&1 <<<"$body" && jq -r '.conf_text'     <<<"$body" > "$pkg/conf"
  if jq -e 'has("examples")' >/dev/null 2>&1 <<<"$body"; then
    find "$pkg/tests/input"  -name 'sample*' -delete 2>/dev/null
    find "$pkg/tests/output" -name 'sample*' -delete 2>/dev/null
    local i=0 pair
    while IFS= read -r pair; do i=$((i+1))
      jq -r '.input'  <<<"$pair" > "$pkg/tests/input/sample$i"
      jq -r '.output' <<<"$pair" > "$pkg/tests/output/sample$i"
    done < <(jq -c '.examples[]?' <<<"$body")
  fi
  if jq -e 'has("tests")' >/dev/null 2>&1 <<<"$body"; then
    # substitui os testes OCULTOS (mantém os sample*); remoções valem
    local inp nm0
    set +o noglob; shopt -s nullglob
    for inp in "$pkg/tests/input"/*; do nm0="$(basename "$inp")"; [[ "$nm0" == sample* ]] && continue
      rm -f "$inp" "$pkg/tests/output/$nm0"; done
    shopt -u nullglob; set -o noglob
    local i=0 pair nm
    while IFS= read -r pair; do i=$((i+1)); nm="$(jq -r '.name // empty' <<<"$pair" | tr -cd 'A-Za-z0-9._-')"; [[ -n "$nm" ]] || nm="$i"
      [[ "$nm" == sample* ]] && nm="t$nm"   # nomes sample* são reservados aos exemplos
      jq -r '.input'  <<<"$pair" > "$pkg/tests/input/$nm"
      jq -r '.output' <<<"$pair" > "$pkg/tests/output/$nm"
    done < <(jq -c '.tests[]?' <<<"$body")
  fi
  # soluções por categoria (substitui a categoria inteira quando presente)
  if jq -e 'has("sols")' >/dev/null 2>&1 <<<"$body"; then
    local cat s fn
    for cat in good slow wrong pass upcoming; do
      jq -e --arg c "$cat" '.sols | has($c)' >/dev/null 2>&1 <<<"$body" || continue
      rm -rf "$pkg/sols/$cat"; mkdir -p "$pkg/sols/$cat"
      while IFS= read -r s; do
        fn="$(basename "$(jq -r '.filename // empty' <<<"$s")")"; [[ "$fn" =~ ^[A-Za-z0-9._-]+$ ]] || continue
        jq -r '.code // ""' <<<"$s" > "$pkg/sols/$cat/$fn"
      done < <(jq -c --arg c "$cat" '.sols[$c][]?' <<<"$body")
    done
  fi
  # compat: good_sol único (CLI/legado) — adiciona a sols/good
  if jq -e 'has("good_sol")' >/dev/null 2>&1 <<<"$body"; then
    local fn; fn="$(basename "$(jq -r '.good_sol.filename // "sol.cpp"' <<<"$body")")"
    [[ "$fn" =~ ^[A-Za-z0-9._-]+$ ]] || fn="sol.cpp"
    jq -r '.good_sol.code // ""' <<<"$body" > "$pkg/sols/good/$fn"
  fi
}
# _read_pairs <pkgdir> <sample|hidden> -> JSON array [{name,input,output}]
_read_pairs(){
  local pkg="$1" which="$2" out='[' first=1 inp nm outp
  set +o noglob; shopt -s nullglob
  for inp in "$pkg/tests/input"/*; do
    [[ -f "$inp" ]] || continue; nm="$(basename "$inp")"
    if [[ "$which" == sample ]]; then [[ "$nm" == sample* ]] || continue
    else [[ "$nm" == sample* ]] && continue; fi
    outp="$pkg/tests/output/$nm"; [[ -f "$outp" ]] || outp=/dev/null
    [[ $first -eq 1 ]] || out+=','; first=0
    out+="$(jq -n --arg nm "$nm" --rawfile i "$inp" --rawfile o "$outp" '{name:$nm, input:$i, output:$o}')"
  done
  shopt -u nullglob; set -o noglob
  printf '%s]' "$out"
}
# read_problem_source <pkgdir> -> JSON editável do pacote (enunciado/autor/tags/conf/exemplos/
# testes/soluções good + public/collections/title do .moj-meta.json).
read_problem_source(){
  local pkg="$1" enunf="" fmt="md" ef
  for ef in docs/enunciado.md enunciado.md docs/enunciado.org docs/enunciado.tex; do
    [[ -f "$pkg/$ef" ]] && { enunf="$pkg/$ef"; [[ "$ef" == *.org ]] && fmt=org; [[ "$ef" == *.tex ]] && fmt=tex; break; }
  done
  local te ta tc; te="$(mktemp)"; ta="$(mktemp)"; tc="$(mktemp)"
  [[ -n "$enunf" ]] && cat "$enunf" > "$te"
  [[ -f "$pkg/author" ]] && cat "$pkg/author" > "$ta"
  [[ -f "$pkg/conf" ]] && cat "$pkg/conf" > "$tc"
  local tags='[]'; [[ -f "$pkg/tags" ]] && tags="$(jq -R . "$pkg/tags" 2>/dev/null | jq -sc . 2>/dev/null)"; [[ -n "$tags" ]] || tags='[]'
  local meta='{}'; [[ -f "$pkg/.moj-meta.json" ]] && meta="$(cat "$pkg/.moj-meta.json" 2>/dev/null)"; [[ -n "$meta" ]] || meta='{}'
  local exs tss; exs="$(_read_pairs "$pkg" sample)"; tss="$(_read_pairs "$pkg" hidden)"
  local sg ss sw sp su
  sg="$(_read_sols "$pkg" good)"; ss="$(_read_sols "$pkg" slow)"
  sw="$(_read_sols "$pkg" wrong)"; sp="$(_read_sols "$pkg" pass)"; su="$(_read_sols "$pkg" upcoming)"
  jq -n --rawfile enun "$te" --rawfile author "$ta" --rawfile conf "$tc" \
        --argjson tags "$tags" --argjson meta "$meta" --argjson exs "$exs" --argjson tss "$tss" \
        --argjson sg "$sg" --argjson ss "$ss" --argjson sw "$sw" --argjson sp "$sp" --argjson su "$su" --arg fmt "$fmt" '
    { format:$fmt, enunciado_md:$enun, author:($author|rtrimstr("\n")), conf_text:$conf,
      tags:$tags, public:($meta.public // false), collections:($meta.collections // []),
      title:($meta.display_title // ""), examples:$exs, tests:$tss,
      sols:{good:$sg, slow:$ss, wrong:$sw, pass:$sp, upcoming:$su} }'
  rm -f "$te" "$ta" "$tc"
}
# _read_sols <pkgdir> <cat> -> JSON array [{filename,code}] de sols/<cat>/*
_read_sols(){
  local pkg="$1" cat="$2" out='[' first=1 f
  set +o noglob; shopt -s nullglob
  for f in "$pkg/sols/$cat"/*; do [[ -f "$f" ]] || continue
    [[ $first -eq 1 ]] || out+=','; first=0
    out+="$(jq -n --arg fn "$(basename "$f")" --rawfile code "$f" '{filename:$fn, code:$code}')"
  done
  shopt -u nullglob; set -o noglob
  printf '%s]' "$out"
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
