# lib/contest-docs.sh — DOCUMENTOS DA PROVA (info sheet, caderno, folha de time limits).
#
# Gera HTML + PDF, em pt e en, a partir do que o contest já tem: conf (nome/datas/limites/
# linguagens), PROBS (letra/nome/enunciado), enunciados/<key>.{html,pdf}, run/tl (time limits)
# e o registry dos juízes (versões de compilador). Nada aqui inventa dado novo.
#
# PDF: `soffice --headless --convert-to pdf` é o ÚNICO engine da imagem (não há LaTeX,
# wkhtmltopdf nem chromium) — o mesmo caminho que a fila de impressão já usa (lib/print.sh).
# Caderno com PDF custom de problema: junta com `pdfunite` e a CAPA é regerada no fim com o
# total real de páginas (pdfinfo).
#
# Idioma: PT/EN vale para o CHROME do documento (capa, títulos, tabelas, info sheet). O corpo
# do ENUNCIADO sai no idioma em que foi escrito — o MOJ não tem enunciado bilíngue.
#
# Layout em disco:
#   contests/<c>/docs/config.json            {caderno_version, cover_note, errata, published:[…]}
#   contests/<c>/docs/info-sheet.<lang>.md   template editável (default: server/etc/)
#   contests/<c>/docs/<tipo>.<lang>.{html,pdf}
#   contests/<c>/docs/index.json             [{type,lang,fmt,bytes,generated_at,by}]
: "${DOC_TYPES:=info-sheet contest times}"
# cadeia de linguagens permitidas (folha de time limits) — fonte única, a MESMA do /submit
declare -F effective_problem_langs >/dev/null || source "$_DIR/lib/langs.sh" 2>/dev/null || true

doc_dir(){ printf '%s/%s/docs' "$CONTESTSDIR" "$1"; }
doc_file(){ printf '%s/%s.%s.%s' "$(doc_dir "$1")" "$2" "$3" "$4"; }   # <c> <tipo> <lang> <fmt>

_doc_esc(){ sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
_doc_escs(){ printf '%s' "${1:-}" | _doc_esc; }

# _doc_t <lang> <chave> -> rótulo traduzido (chrome do documento)
_doc_t(){
  local l="$1" k="$2"
  case "$l:$k" in
    pt:problem) printf 'Problema';;      en:problem) printf 'Problem';;
    pt:name)    printf 'Nome';;          en:name)    printf 'Name';;
    pt:tl)      printf 'Tempo limite por teste';; en:tl) printf 'Time limit per test';;
    pt:langs)   printf 'Linguagens aceitas';;     en:langs) printf 'Accepted languages';;
    pt:times_title) printf 'Limites de tempo da prova';; en:times_title) printf 'Time Limits for the Contest Session';;
    pt:errata)  printf 'Errata';;        en:errata)  printf 'Errata';;
    pt:seconds) printf 'Tempos em segundos.';;    en:seconds) printf 'Times are given in seconds.';;
    pt:session) printf 'Caderno de Problemas';;   en:session) printf 'Contest Session';;
    pt:contains) printf 'Este caderno contém';;   en:contains) printf 'This problem set contains';;
    pt:problems_w) printf 'problemas';;  en:problems_w) printf 'problems';;
    pt:pages) printf 'páginas numeradas de 1 a';; en:pages) printf 'pages are numbered from 1 to';;
    pt:general) printf 'Informações gerais';;     en:general) printf 'General information';;
    pt:sites) printf 'Sedes participantes';;      en:sites) printf 'Participating sites';;
    pt:author) printf 'Autor';;          en:author)  printf 'Author';;
    *) printf '%s' "$k";;
  esac
}

# _doc_html_head <título> -> abre um HTML standalone com o CSS de impressão
_doc_html_head(){
  local css="$_DIR/../../etc/contest-doc.css"
  [[ -f "$css" ]] || css="$_DIR/etc/contest-doc.css"
  printf '<!DOCTYPE html><html><head><meta charset="utf-8"><title>%s</title><style>\n' "$(_doc_escs "$1")"
  cat "$css" 2>/dev/null
  printf '</style></head><body>\n'
}
_doc_html_foot(){ printf '</body></html>\n'; }

# doc_conf_get <c> -> config.json (defaults se não existir)
doc_conf_get(){
  local f; f="$(doc_dir "$1")/config.json"
  if [[ -s "$f" ]] && jq -e . "$f" >/dev/null 2>&1; then cat "$f"
  else printf '{"caderno_version":"v1.0","cover_note":"","errata":"","published":[]}'; fi
}

# _doc_meta <c> -> define CNAME/CDATE/CLANGS/CMEM/CSTACK a partir do conf do contest.
# O conf é SOURCED (por isso o subshell, p/ não poluir o processo) e volta por `eval` de
# uma linha com printf %q — nada de arquivo temporário (um /tmp/… compartilhado por PID
# falhava em silêncio e o documento saía com o cabeçalho VAZIO).
_doc_meta(){
  local c="$1" _kv
  CNAME=""; CDATE=""; CLANGS=""; CMEM=""; CSTACK=""
  # `declare -A ULIMITS` ANTES do source: o conf usa ULIMITS[-s]/[-u] como array ASSOCIATIVO
  # (é o que build-and-test.sh/calibreitor.sh fazem) e, sob `set -u`, ler `${ULIMITS[-s]}` sem
  # o array declarado aborta o subshell inteiro — o documento saía com cabeçalho vazio e data
  # "—" em todo contest que não define ULIMITS (o caso comum).
  _kv="$( declare -A ULIMITS 2>/dev/null || true
    . "$CONTESTSDIR/$c/conf" 2>/dev/null
    printf 'CNAME=%q CDATE=%q CLANGS=%q CMEM=%q CSTACK=%q' \
      "${CONTEST_NAME:-$c}" "${CONTEST_START:-0}" "${LANGUAGES:-}" \
      "${MEMLIMITMB:-1024}" "${ULIMITS[-s]:-131072}" )"
  [[ -n "$_kv" ]] && eval "$_kv"
  [[ -n "$CNAME" ]] || CNAME="$c"
}

_doc_date(){  # <epoch> <lang>
  local e="${1:-0}" l="$2"
  [[ "$e" =~ ^[0-9]+$ && "$e" -gt 0 ]] || { printf '—'; return; }
  if [[ "$l" == pt ]]; then LC_ALL=pt_BR.UTF-8 date -d "@$e" '+%d/%m/%Y' 2>/dev/null || date -d "@$e" '+%d/%m/%Y'
  else LC_ALL=C date -d "@$e" '+%B %d, %Y' 2>/dev/null || date -d "@$e" '+%Y-%m-%d'; fi
}

# _doc_pool <c> <problem_id> -> pool de hosts p/ o TL (problem-judges.json > CONTEST_JUDGES)
_doc_pool(){
  local c="$1" id="$2" pj="$CONTESTSDIR/$1/problem-judges.json" out=""
  [[ -f "$pj" ]] && out="$(jq -r --arg i "$id" '(.[$i] // []) | join(" ")' "$pj" 2>/dev/null)"
  [[ -n "$out" ]] || out="$( . "$CONTESTSDIR/$c/conf" 2>/dev/null; printf '%s' "${CONTEST_JUDGES:-}" )"
  printf '%s' "$out"
}

# doc_tl_rows <c> -> TSV: letra \t nome \t tl_texto  (tl vazio = não calibrado)
doc_tl_rows(){
  local c="$1" probs; probs="$(cc_probs_json "$c")"
  local n i letter name pid tl allow
  n="$(jq -r 'length' <<<"$probs" 2>/dev/null)"; [[ "$n" =~ ^[0-9]+$ ]] || n=0
  for ((i=0; i<n; i++)); do
    letter="$(jq -r --argjson i "$i" '.[$i].letter // ""' <<<"$probs")"
    name="$(jq -r --argjson i "$i" '.[$i].name // ""' <<<"$probs")"
    pid="$(jq -r --argjson i "$i" '.[$i].statement_key // .[$i].problem_id // ""' <<<"$probs")"
    tl="$(tl_store_served "$pid" "$(_doc_pool "$c" "$pid")" 2>/dev/null)"
    # SÓ as linguagens que o competidor pode usar neste problema (override por problema >
    # whitelist do contest > default do pacote — a mesma cadeia do /submit). O store guarda o
    # TL medido de TODAS as linguagens calibradas; publicar Rust numa prova só-C confunde.
    allow="[]"; declare -F effective_problem_langs >/dev/null && allow="$(effective_problem_langs "$c" "$pid" 2>/dev/null)"
    [[ -n "$allow" ]] || allow='[]'
    # texto: se todas as linguagens têm o mesmo TL, mostra um número; senão "lang: t" por linguagem
    tl="$(jq -r --argjson allow "$allow" '
      (to_entries | map(select(.key != "default"))
        | map(.key as $k | select(($allow|length) == 0 or (($allow|index($k)) != null)))) as $e
      | if ($e|length) == 0 then ""
        elif (($e | map(.value) | unique | length) == 1) then ($e[0].value | tonumber | (.*1000|round)/1000 | tostring)
        else ($e | sort_by(.key) | map("\(.key): \(.value|tonumber|(.*1000|round)/1000)") | join(" · ")) end' <<<"${tl:-\{\}}" 2>/dev/null)"
    printf '%s\t%s\t%s\n' "$letter" "$name" "$tl"
  done
}

# _doc_lang_name <id> -> nome de exibição da linguagem
_doc_lang_name(){
  case "$1" in
    c) printf C;; cpp) printf 'C++';; py) printf 'Python 3 (PyPy3)';; java) printf Java;;
    kt) printf Kotlin;; rs) printf Rust;; go) printf Go;; js) printf JavaScript;;
    sh) printf 'Shell (bash)';; pas) printf Pascal;; cs) printf 'C#';; hs) printf Haskell;;
    ml) printf OCaml;; pl) printf Prolog;; *) printf '%s' "$1";;
  esac
}

# _doc_toolchain [<c>] -> linhas "Linguagem — versão" do que os JUÍZES reportam
# (`toolchain` do registry, medido DENTRO da jaula pelo agente: judge/agent/inventory.sh).
# Com o contest, filtra pelas linguagens aceitas nele — a info sheet não lista compilador
# que ninguém pode usar. Juiz antigo (sem o campo) simplesmente não contribui.
_doc_toolchain(){
  local c="${1:-}" langs="" tmp
  [[ -n "$c" ]] && langs="$( . "$CONTESTSDIR/$c/conf" 2>/dev/null; printf '%s' "${LANGUAGES:-}" )"
  tmp="$(find "${REGISTRYDIR:-$RUNDIR/registry}" -maxdepth 1 -name '*.json' -exec cat {} + 2>/dev/null \
    | jq -rs --arg only "$langs" '
        ($only | split(" ") | map(select(. != ""))) as $keep
        | [ .[] | (.toolchain // .report.toolchain // {}) | to_entries[]? ]
        | map(.key as $k | select(($keep | length) == 0 or (($keep | index($k)) != null)))
        | group_by(.key) | map({k: .[0].key, v: (map(.value) | unique | join(" / "))})
        | sort_by(.k)[] | "\(.k)\t\(.v)"' 2>/dev/null)"
  local k v
  while IFS=$'\t' read -r k v; do
    [[ -n "$k" ]] || continue
    printf '%s — %s\n' "$(_doc_lang_name "$k")" "$v"
  done <<<"$tmp"
}

# _doc_langs_table <c> <lang> -> tabela HTML das linguagens aceitas no contest
_doc_langs_table(){
  local c="$1" l="$2" langs
  langs="$( . "$CONTESTSDIR/$c/conf" 2>/dev/null; printf '%s' "${LANGUAGES:-}" )"
  [[ -n "$langs" ]] || { printf '<p>%s</p>' "$(_doc_t "$l" langs)"; return; }
  printf '<table class="doc-tbl"><thead><tr><th>%s</th><th>%s</th></tr></thead><tbody>' \
    "$(_doc_t "$l" langs)" "$([[ "$l" == pt ]] && printf 'Extensão do arquivo' || printf 'File extension')"
  local x
  for x in $langs; do
    printf '<tr><td>%s</td><td><code>.%s</code></td></tr>' \
      "$(_doc_escs "$(_doc_lang_name "$x")")" "$(_doc_escs "$x")"
  done
  printf '</tbody></table>'
}

# _doc_tl_table <c> <lang> -> tabela HTML letra|nome|TL
_doc_tl_table(){
  local c="$1" l="$2" letter name tl
  printf '<table class="doc-tbl"><thead><tr><th>%s</th><th>%s</th><th>%s</th></tr></thead><tbody>' \
    "$(_doc_t "$l" problem)" "$(_doc_t "$l" name)" "$(_doc_t "$l" tl)"
  while IFS=$'\t' read -r letter name tl; do
    [[ -n "$letter$name" ]] || continue
    printf '<tr><td class="c">%s</td><td>%s</td><td class="c">%s</td></tr>' \
      "$(_doc_escs "$letter")" "$(_doc_escs "$name")" "$(_doc_escs "${tl:-—}")"
  done < <(doc_tl_rows "$c")
  printf '</tbody></table>'
}

# ---------- HTML de cada documento ----------------------------------------------------
# _doc_html_infosheet <c> <lang>
_doc_html_infosheet(){
  local c="$1" l="$2" tpl tmp
  _doc_meta "$c"
  tpl="$(doc_dir "$c")/info-sheet.$l.md"
  [[ -f "$tpl" ]] || tpl="$_DIR/../../etc/info-sheet.$l.md"
  [[ -f "$tpl" ]] || tpl="$_DIR/etc/info-sheet.$l.md"
  [[ -f "$tpl" ]] || { printf '<p>template ausente</p>'; return 1; }
  tmp="$(mktemp)"
  # marcadores -> conteúdo gerado (tabelas entram como HTML puro depois do pandoc)
  sed -e "s|{{CONTEST_NAME}}|$(_doc_escs "$CNAME")|g" \
      -e "s|{{DATE}}|$(_doc_date "$CDATE" "$l")|g" \
      -e "s|{{MEMLIMIT}}|${CMEM:-1024} MB|g" \
      -e "s|{{STACK}}|$(( ${CSTACK:-131072} / 1024 )) MB|g" \
      "$tpl" > "$tmp"
  local body; body="$(render_markdown_html < "$tmp" 2>/dev/null)"
  rm -f "$tmp"
  local tc; tc="$(_doc_toolchain "$c")"
  local tchtml="<ul>"; while IFS= read -r line; do [[ -n "$line" ]] && tchtml+="<li>$(_doc_escs "$line")</li>"; done <<<"$tc"; tchtml+="</ul>"
  [[ -n "$tc" ]] || tchtml="<p><i>$([[ "$l" == pt ]] && printf 'nenhum juiz reportou versões ainda' || printf 'no judge reported versions yet')</i></p>"
  _doc_html_head "$CNAME — info sheet"
  printf '<h1>%s</h1><div class="sub">%s</div>\n' "$(_doc_escs "$CNAME")" "$(_doc_date "$CDATE" "$l")"
  # substitui os marcadores de BLOCO que sobraram no HTML renderizado
  printf '%s' "$body" \
    | sed -e "s|{{TOOLCHAIN}}|$(printf '%s' "$tchtml" | sed 's/[&|]/\\&/g')|" \
          -e "s|{{LANGS_TABLE}}|$(_doc_langs_table "$c" "$l" | sed 's/[&|]/\\&/g')|" \
          -e "s|{{TL_TABLE}}|$(_doc_tl_table "$c" "$l" | sed 's/[&|]/\\&/g')|"
  _doc_html_foot
}

# _doc_html_times <c> <lang>
_doc_html_times(){
  local c="$1" l="$2" cfg errata
  _doc_meta "$c"; cfg="$(doc_conf_get "$c")"; errata="$(jq -r '.errata // ""' <<<"$cfg")"
  _doc_html_head "$CNAME — time limits"
  printf '<h1>%s</h1><div class="sub">%s</div>\n' "$(_doc_escs "$CNAME")" "$(_doc_date "$CDATE" "$l")"
  printf '<h2 class="center">%s</h2>\n' "$(_doc_t "$l" times_title)"
  _doc_tl_table "$c" "$l"
  printf '<p class="foot"><sup>1</sup> %s</p>\n' "$(_doc_t "$l" seconds)"
  if [[ -n "$errata" ]]; then
    printf '<h3>%s</h3>%s\n' "$(_doc_t "$l" errata)" "$(printf '%s' "$errata" | render_markdown_html 2>/dev/null)"
  fi
  _doc_html_foot
}

# CAPA — três modos (o admin escolhe):
#   1. PDF ENVIADO   docs/cover.<lang>.pdf  -> usado como está (o gerador nem monta capa)
#   2. EDITADA       docs/cover.<lang>.md   -> markdown do admin com marcadores
#   3. GERADA        (default) o layout abaixo
# Marcadores da capa editada: {{CONTEST_NAME}} {{DATE}} {{N_PROBLEMS}} {{N_PAGES}} {{SITES}} {{VERSION}}
doc_cover_pdf(){ printf '%s/cover.%s.pdf' "$(doc_dir "$1")" "$2"; }   # <c> <lang>
doc_cover_md(){  printf '%s/cover.%s.md'  "$(doc_dir "$1")" "$2"; }

# _doc_html_cover <c> <lang> <n_problems> <n_pages>  (n_pages vazio = sem a linha de páginas)
_doc_html_cover(){
  local c="$1" l="$2" np="$3" pg="$4" cfg note ver sites md
  _doc_meta "$c"; cfg="$(doc_conf_get "$c")"
  note="$(jq -r '.cover_note // ""' <<<"$cfg")"; ver="$(jq -r '.caderno_version // "v1.0"' <<<"$cfg")"
  sites="$(jq -r '[.[].name] | join(", ")' "$CONTESTSDIR/$c/regions.json" 2>/dev/null)"

  # modo 2: capa EDITADA pelo admin (markdown próprio, com os marcadores substituídos)
  md="$(doc_cover_md "$c" "$l")"
  if [[ -s "$md" ]]; then
    _doc_html_head "$CNAME"
    printf '<div class="cover">'
    sed -e "s|{{CONTEST_NAME}}|$(_doc_escs "$CNAME")|g" \
        -e "s|{{DATE}}|$(_doc_date "$CDATE" "$l")|g" \
        -e "s|{{N_PROBLEMS}}|$np|g" \
        -e "s|{{N_PAGES}}|${pg:-?}|g" \
        -e "s|{{SITES}}|$(_doc_escs "$sites")|g" \
        -e "s|{{VERSION}}|$(_doc_escs "$ver")|g" "$md" \
      | render_markdown_html 2>/dev/null
    printf '</div>\n'
    _doc_html_foot
    return 0
  fi

  _doc_html_head "$CNAME"
  printf '<div class="cover"><h1>%s</h1><div class="sub">%s</div>\n' "$(_doc_escs "$CNAME")" "$(_doc_date "$CDATE" "$l")"
  printf '<h2 class="session">%s</h2>\n' "$(_doc_t "$l" session)"
  printf '<p class="center">%s <b>%s</b> %s' "$(_doc_t "$l" contains)" "$np" "$(_doc_t "$l" problems_w)"
  [[ -n "$pg" ]] && printf '; %s %s' "$(_doc_t "$l" pages)" "$pg"
  printf '.</p>\n'
  [[ -n "$note" ]] && printf '<div class="center note">%s</div>\n' "$(printf '%s' "$note" | render_markdown_html 2>/dev/null)"
  [[ -n "$sites" ]] && printf '<p class="center sites"><b>%s:</b> %s</p>\n' "$(_doc_t "$l" sites)" "$(_doc_escs "$sites")"
  printf '<p class="center ver">%s</p></div>\n' "$(_doc_escs "$ver")"
  _doc_html_foot
}

# _doc_html_contest <c> <lang> — caderno inteiro em HTML (capa + enunciados embutidos)
_doc_html_contest(){
  local c="$1" l="$2" probs n i letter name skey f
  probs="$(cc_probs_json "$c")"; n="$(jq -r 'length' <<<"$probs")"; [[ "$n" =~ ^[0-9]+$ ]] || n=0
  _doc_html_cover "$c" "$l" "$n" ""
  for ((i=0; i<n; i++)); do
    letter="$(jq -r --argjson i "$i" '.[$i].letter // ""' <<<"$probs")"
    name="$(jq -r --argjson i "$i" '.[$i].name // ""' <<<"$probs")"
    skey="$(jq -r --argjson i "$i" '.[$i].statement_key // ""' <<<"$probs")"
    printf '<div class="prob"><h1>%s %s — %s</h1>\n' "$(_doc_t "$l" problem)" "$(_doc_escs "$letter")" "$(_doc_escs "$name")"
    f="$CONTESTSDIR/$c/enunciados/$skey.html"
    if [[ ! -f "$f" ]]; then
      local jf="$CONTESTSDIR/treino/var/jsons/$skey.json"
      [[ -f "$jf" ]] || jf="$CONTESTSDIR/treino/var/jsons-private/$skey.json"
      if [[ -f "$jf" ]]; then
        local tmpf; tmpf="$(mktemp)"
        jq -r '.statement_html_b64 // ""' "$jf" 2>/dev/null | base64 -d > "$tmpf" 2>/dev/null
        [[ -s "$tmpf" ]] && f="$tmpf" || rm -f "$tmpf"
      fi
    fi
    if [[ -f "$f" ]]; then
      # só o miolo do <body> (o enunciado é HTML standalone com <head> próprio)
      sed -n '/<body[^>]*>/,/<\/body>/p' "$f" | sed -e 's|<body[^>]*>||' -e 's|</body>||'
    else
      printf '<p><i>%s</i></p>' "$([[ "$l" == pt ]] && printf 'enunciado indisponível' || printf 'statement unavailable')"
    fi
    printf '</div>\n'
  done
  _doc_html_foot
}

# ---------- PDF ----------------------------------------------------------------------
# _doc_html2pdf <html-file> <pdf-out> -> 0/1 (soffice; único engine da imagem)
_doc_html2pdf(){
  local src="$1" out="$2" work; work="$(mktemp -d)"
  cp -f "$src" "$work/doc.html"
  soffice --headless -env:UserInstallation="file://$work/lo" --convert-to pdf \
          --outdir "$work" "$work/doc.html" >/dev/null 2>&1
  if [[ -s "$work/doc.pdf" ]]; then mv -f "$work/doc.pdf" "$out"; rm -rf "$work"; return 0; fi
  rm -rf "$work"; return 1
}
_doc_pages(){ pdfinfo "$1" 2>/dev/null | awk '/^Pages:/{print $2; exit}'; }

# _doc_pdf_contest <c> <lang> <out.pdf> — caderno: capa + (PDF custom | enunciado renderizado),
# unidos com pdfunite; capa REGERADA no fim com o total real de páginas.
_doc_pdf_contest(){
  local c="$1" l="$2" out="$3" probs n i skey work parts=() pdf tot=0
  work="$(mktemp -d)"; probs="$(cc_probs_json "$c")"; n="$(jq -r 'length' <<<"$probs")"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  for ((i=0; i<n; i++)); do
    skey="$(jq -r --argjson i "$i" '.[$i].statement_key // ""' <<<"$probs")"
    pdf="$CONTESTSDIR/$c/enunciados/$skey.pdf"
    if [[ -f "$pdf" ]]; then
      cp -f "$pdf" "$work/p$i.pdf"
    else
      # renderiza SÓ este problema (capa fica de fora) e converte
      local h="$work/p$i.html"
      { _doc_html_head "x"; printf '<div class="prob">';
        local letter name f
        letter="$(jq -r --argjson i "$i" '.[$i].letter // ""' <<<"$probs")"
        name="$(jq -r --argjson i "$i" '.[$i].name // ""' <<<"$probs")"
        printf '<h1>%s %s — %s</h1>' "$(_doc_t "$l" problem)" "$(_doc_escs "$letter")" "$(_doc_escs "$name")"
        f="$CONTESTSDIR/$c/enunciados/$skey.html"
        if [[ ! -f "$f" ]]; then
          local jf="$CONTESTSDIR/treino/var/jsons/$skey.json"
          [[ -f "$jf" ]] || jf="$CONTESTSDIR/treino/var/jsons-private/$skey.json"
          [[ -f "$jf" ]] && { jq -r '.statement_html_b64 // ""' "$jf" 2>/dev/null | base64 -d > "$work/s$i.html" 2>/dev/null; [[ -s "$work/s$i.html" ]] && f="$work/s$i.html"; }
        fi
        [[ -f "$f" ]] && sed -n '/<body[^>]*>/,/<\/body>/p' "$f" | sed -e 's|<body[^>]*>||' -e 's|</body>||'
        printf '</div>'; _doc_html_foot; } > "$h"
      _doc_html2pdf "$h" "$work/p$i.pdf" || continue
    fi
    [[ -s "$work/p$i.pdf" ]] && { parts+=( "$work/p$i.pdf" ); tot=$(( tot + $(_doc_pages "$work/p$i.pdf" 2>/dev/null || echo 0) )); }
  done
  # CAPA: PDF enviado pelo admin vence (usado como está); senão gera/renderiza com o total real
  local upl; upl="$(doc_cover_pdf "$c" "$l")"
  if [[ -s "$upl" ]]; then
    cp -f "$upl" "$work/cover.pdf"
  else
    _doc_html_cover "$c" "$l" "$n" "$(( tot + 1 ))" > "$work/cover.html"
    _doc_html2pdf "$work/cover.html" "$work/cover.pdf" || { rm -rf "$work"; return 1; }
  fi
  if (( ${#parts[@]} )); then pdfunite "$work/cover.pdf" "${parts[@]}" "$out" 2>/dev/null || cp -f "$work/cover.pdf" "$out"
  else cp -f "$work/cover.pdf" "$out"; fi
  rm -rf "$work"; [[ -s "$out" ]]
}

# ---------- API interna ---------------------------------------------------------------
# doc_build <c> <tipo> <lang> -> gera html+pdf; ecoa JSON {type,lang,html,pdf,bytes_*}
doc_build(){
  local c="$1" t="$2" l="$3" d; d="$(doc_dir "$c")"
  mkdir -p "$d" 2>/dev/null
  local html="$d/$t.$l.html" pdf="$d/$t.$l.pdf" tmp="$d/.$t.$l.tmp.html"
  case "$t" in
    info-sheet) _doc_html_infosheet "$c" "$l" > "$tmp" ;;
    times)      _doc_html_times "$c" "$l"    > "$tmp" ;;
    contest)    _doc_html_contest "$c" "$l"  > "$tmp" ;;
    *) return 2 ;;
  esac
  [[ -s "$tmp" ]] || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$html"
  if [[ "$t" == contest ]]; then _doc_pdf_contest "$c" "$l" "$pdf.tmp" && mv -f "$pdf.tmp" "$pdf" || rm -f "$pdf.tmp"
  else _doc_html2pdf "$html" "$pdf.tmp" && mv -f "$pdf.tmp" "$pdf" || rm -f "$pdf.tmp"; fi
  jq -cn --arg t "$t" --arg l "$l" \
     --argjson bh "$(stat -c%s "$html" 2>/dev/null || echo 0)" \
     --argjson bp "$(stat -c%s "$pdf" 2>/dev/null || echo 0)" \
     --argjson at "$EPOCHSECONDS" --arg by "${SESSION_LOGIN:-}" \
     '{type:$t, lang:$l, html_bytes:$bh, pdf_bytes:$bp, generated_at:$at, by:$by}'
}

# doc_index <c> -> [{type,lang,html_bytes,pdf_bytes,generated_at,by,published}]
doc_index(){
  local c="$1" d; d="$(doc_dir "$c")"
  local idx="$d/index.json" pub; pub="$(doc_conf_get "$c" | jq -c '.published // []')"
  [[ -s "$idx" ]] || { printf '[]'; return; }
  # a chave é BINDADA antes (`as $k`): o argumento de `index()` avalia contra a ENTRADA do
  # pipe — que aqui é `$p`, o array de publicados —, não contra o elemento do map. Sem o
  # bind dava "Cannot index array with string" e a lista de documentos voltava VAZIA.
  jq -c --argjson p "$pub" 'map((.type + "." + .lang) as $k
     | . + {published: (($p | index($k)) != null)})' "$idx" 2>/dev/null || printf '[]'
}

# doc_index_upsert <c> <entrada-json>
doc_index_upsert(){
  local c="$1" e="$2" d; d="$(doc_dir "$c")"; mkdir -p "$d" 2>/dev/null
  local idx="$d/index.json"; [[ -s "$idx" ]] || printf '[]' > "$idx"
  jq -c --argjson e "$e" '(map(select(.type != $e.type or .lang != $e.lang)) + [$e])
     | sort_by(.type, .lang)' "$idx" > "$idx.tmp" \
    && mv -f "$idx.tmp" "$idx"
}
