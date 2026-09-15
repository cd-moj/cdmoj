# lib/contest-docs.sh — DOCUMENTOS DA PROVA (info sheet, caderno, folha de time limits).
#
# Gera HTML + PDF, em pt/en/es, a partir do que o contest já tem: conf (nome/datas/limites/
# linguagens), PROBS (letra/nome/enunciado), enunciados/<key>.{html,pdf}, run/tl (time limits)
# e o registry dos juízes (versões de compilador). Nada aqui inventa dado novo.
#
# PDF: `soffice --headless --convert-to pdf` é o ÚNICO engine da imagem (não há LaTeX,
# wkhtmltopdf nem chromium) — o mesmo caminho que a fila de impressão já usa (lib/print.sh).
# Caderno com PDF custom de problema: junta com `pdfunite` e a CAPA é regerada no fim com o
# total real de páginas (pdfinfo).
#
# Idioma: PT/EN/ES vale para o CHROME do documento (capa, títulos, tabelas, info sheet) — a
# tabela é o `_doc_t`. O corpo do ENUNCIADO sai no idioma em que foi escrito: o MOJ não traduz
# enunciado (para isso existe o PDF ENVIADO, abaixo).
#
# PDF ENVIADO: o admin pode subir o documento PRONTO de um tipo+idioma
# (docs/<tipo>.<lang>.uploaded.pdf). Ele VENCE o gerado em tudo que é servido (doc_pdf_served) e
# o gerado continua no disco — voltar atrás é apagar o enviado.
#
# Layout em disco:
#   contests/<c>/docs/config.json            {caderno_version, cover_note, errata,
#                                             editorial_note, published:[…]}
#   contests/<c>/docs/info-sheet.<lang>.md   template editável (default: server/etc/)
#   contests/<c>/docs/<tipo>.<lang>.{html,pdf}
#   contests/<c>/docs/<tipo>.<lang>.uploaded.pdf   PDF pronto enviado pelo admin (vence)
#   contests/<c>/docs/index.json             [{type,lang,fmt,bytes,generated_at,by}]
: "${DOC_TYPES:=info-sheet contest times editorial}"
# cadeia de linguagens permitidas (folha de time limits) — fonte única, a MESMA do /submit
declare -F effective_problem_langs >/dev/null || source "$_DIR/lib/langs.sh" 2>/dev/null || true
# pkg_path (editorial lê docs/solucao.md do PACOTE do problema)
declare -F pkg_path >/dev/null || source "$_DIR/lib/tl-store.sh" 2>/dev/null || true

doc_dir(){ printf '%s/%s/docs' "$CONTESTSDIR" "$1"; }
doc_file(){ printf '%s/%s.%s.%s' "$(doc_dir "$1")" "$2" "$3" "$4"; }   # <c> <tipo> <lang> <fmt>

# --- PDF ENVIADO (documento pronto, feito fora do MOJ) ----------------------------------
# doc_upload_pdf <c> <tipo> <lang> -> caminho do arquivo enviado (exista ou não)
doc_upload_pdf(){ printf '%s/%s.%s.uploaded.pdf' "$(doc_dir "$1")" "$2" "$3"; }
doc_has_upload(){ [[ -s "$(doc_upload_pdf "$1" "$2" "$3")" ]]; }
# doc_pdf_served <c> <tipo> <lang> -> QUAL pdf o mundo vê: o enviado vence o gerado.
# Ecoa vazio quando não há nenhum (o chamador decide o 404).
doc_pdf_served(){
  local u g; u="$(doc_upload_pdf "$1" "$2" "$3")"; g="$(doc_file "$1" "$2" "$3" pdf)"
  [[ -s "$u" ]] && { printf '%s' "$u"; return 0; }
  [[ -s "$g" ]] && { printf '%s' "$g"; return 0; }
  printf ''
}

_doc_esc(){ sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
_doc_escs(){ printf '%s' "${1:-}" | _doc_esc; }

# IDIOMAS dos documentos: pt/en/es. É separado do LOCALE do contest (que veste a INTERFACE e
# segue pt|en) — aqui o idioma é PARÂMETRO: cada documento é gerado em cada idioma pedido.
: "${DOC_LANGS:=pt en es}"
# teto do PDF que o admin SOBE (capa e documento pronto). O nginx do subdomínio corta antes,
# mas aqui a recusa tem código e mensagem do MOJ em vez de um 413 cru do nginx.
: "${DOC_PDF_MAX_MB:=60}"
doc_lang_ok(){ case " $DOC_LANGS " in *" $1 "*) return 0;; *) return 1;; esac; }

# _doc_t <lang> <chave> -> rótulo traduzido (chrome do documento).
# ⚠ TODA string do documento entra AQUI — ternário `[[ $l == pt ]] && … || …` espalhado pelo
# arquivo foi o que travou o espanhol por tanto tempo. Idioma sem entrada cai na chave crua.
_doc_t(){
  local l="$1" k="$2"
  case "$l:$k" in
    pt:problem) printf 'Problema';;      en:problem) printf 'Problem';;      es:problem) printf 'Problema';;
    pt:name)    printf 'Nome';;          en:name)    printf 'Name';;         es:name)    printf 'Nombre';;
    pt:tl)      printf 'Tempo limite por teste';; en:tl) printf 'Time limit per test';; es:tl) printf 'Límite de tiempo por prueba';;
    pt:langs)   printf 'Linguagens aceitas';;     en:langs) printf 'Accepted languages';; es:langs) printf 'Lenguajes aceptados';;
    pt:times_title) printf 'Limites de tempo da prova';; en:times_title) printf 'Time Limits for the Contest Session';; es:times_title) printf 'Límites de tiempo de la competencia';;
    pt:errata)  printf 'Errata';;        en:errata)  printf 'Errata';;       es:errata)  printf 'Fe de erratas';;
    pt:seconds) printf 'Tempos em segundos.';;    en:seconds) printf 'Times are given in seconds.';; es:seconds) printf 'Tiempos en segundos.';;
    pt:session) printf 'Caderno de Problemas';;   en:session) printf 'Contest Session';; es:session) printf 'Cuadernillo de Problemas';;
    pt:contains) printf 'Este caderno contém';;   en:contains) printf 'This problem set contains';; es:contains) printf 'Este cuadernillo contiene';;
    pt:problems_w) printf 'problemas';;  en:problems_w) printf 'problems';;  es:problems_w) printf 'problemas';;
    pt:pages) printf 'páginas numeradas de 1 a';; en:pages) printf 'pages are numbered from 1 to';; es:pages) printf 'páginas numeradas de 1 a';;
    pt:general) printf 'Informações gerais';;     en:general) printf 'General information';; es:general) printf 'Información general';;
    pt:sites) printf 'Sedes participantes';;      en:sites) printf 'Participating sites';; es:sites) printf 'Sedes participantes';;
    pt:author) printf 'Autor';;          en:author)  printf 'Author';;       es:author)  printf 'Autor';;
    pt:editorial) printf 'Editorial';;   en:editorial) printf 'Editorial';;  es:editorial) printf 'Editorial';;
    pt:no_solution) printf 'solução indisponível no pacote deste problema';;
    en:no_solution) printf 'no solution write-up in this problem'\''s package';;
    es:no_solution) printf 'solución no disponible en el paquete de este problema';;
    # chaves que ANTES eram ternário solto no meio do código (é o que sangrava num 3º idioma)
    # (2026-09-14: era "Testing environment"; o nome agora remete ao sistema de julgamento)
    pt:env_title) printf 'Ambiente de julgamento e submissão';; en:env_title) printf 'Judging environment and submission system';; es:env_title) printf 'Entorno de evaluación y envío';;
    pt:tl_same) printf 'Os limites de tempo não dependem da linguagem de programação.';;
    en:tl_same) printf 'Time limits do not depend on the programming language.';;
    es:tl_same) printf 'Los límites de tiempo no dependen del lenguaje de programación.';;
    pt:tl_per_lang) printf 'O limite de tempo depende da linguagem: uma coluna por linguagem.';;
    en:tl_per_lang) printf 'The time limit depends on the language: one column per language.';;
    es:tl_per_lang) printf 'El límite de tiempo depende del lenguaje: una columna por lenguaje.';;
    pt:ed_index) printf 'Problemas deste editorial';; en:ed_index) printf 'Problems in this editorial';; es:ed_index) printf 'Problemas de este editorial';;
    pt:none_w) printf 'nenhum';;          en:none_w) printf 'none';;            es:none_w) printf 'ninguno';;
    pt:all_langs) printf 'todas as linguagens da plataforma';; en:all_langs) printf 'all platform languages';; es:all_langs) printf 'todos los lenguajes de la plataforma';;
    pt:file_ext)  printf 'Extensão do arquivo';;     en:file_ext)  printf 'File extension';;      es:file_ext)  printf 'Extensión del archivo';;
    pt:no_versions) printf 'nenhum juiz reportou versões ainda';; en:no_versions) printf 'no judge reported versions yet';; es:no_versions) printf 'ningún juez ha reportado versiones todavía';;
    pt:no_statement) printf 'enunciado indisponível';; en:no_statement) printf 'statement unavailable';; es:no_statement) printf 'enunciado no disponible';;
    pt:news_doc) printf 'Documento da prova disponível para download.';;
    en:news_doc) printf 'Contest document available for download.';;
    es:news_doc) printf 'Documento de la competencia disponible para descargar.';;
    *) printf '%s' "$k";;
  esac
}

# _doc_month <lang> <1..12> — nome do mês SEM depender de locale instalado (a imagem é slim:
# `LC_ALL=pt_BR.UTF-8` já era aposta, e es_ES não existe lá).
_doc_month(){
  local l="$1" m="$2"
  case "$l" in
    en) set -- January February March April May June July August September October November December;;
    es) set -- enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre;;
    *)  set -- janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro;;
  esac
  m="${m#0}"; [[ "$m" =~ ^[0-9]+$ ]] && (( m >= 1 && m <= 12 )) || return 0
  eval "printf '%s' \"\${$m}\""
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

# _doc_label <tipo> <lang> -> rótulo do documento na seção "Prova" do contest.
_doc_label(){
  case "$1" in
    info-sheet) _doc_t "$2" env_title;;
    times)      _doc_t "$2" times_title;;
    editorial)  _doc_t "$2" editorial;;
    *)          _doc_t "$2" session;;
  esac
}
_doc_url(){ printf '/api/v1/contest/doc?contest=%s&type=%s&lang=%s&fmt=pdf' "$1" "$2" "$3"; }

# doc_publish <c> <tipo> <lang> — marca como publicado (config.json) e insere na seção "Prova"
# (resources.json, lido por /contest/resources). IDEMPOTENTE. Não valida fase nem geração: o
# gate (403 do editorial antes do fim, 409 not_generated) é do CHAMADOR — mas a regra de ONDE
# grava mora AQUI, para o painel de documentos e o "encerrar evento" não divergirem.
doc_publish(){
  local c="$1" t="$2" l="$3" d cfg res
  d="$(doc_dir "$c")"; mkdir -p "$d" 2>/dev/null
  cfg="$(doc_conf_get "$c" | jq -c --arg k "$t.$l" '.published = ((.published // []) + [$k] | unique)')" || return 1
  printf '%s\n' "$cfg" > "$d/config.json.tmp" && mv -f "$d/config.json.tmp" "$d/config.json" || return 1
  res="$CONTESTSDIR/$c/resources.json"; [[ -s "$res" ]] || printf '[]' > "$res"
  # `type`/`lang` são o que deixa a aba Contest juntar "Caderno: PT | EN | ES" numa linha só
  # (antes era um bullet por idioma). A URL NÃO muda: é ela que o doc_unpublish casa.
  jq -c --arg lb "$(_doc_label "$t" "$l") ($l)" --arg u "$(_doc_url "$c" "$t" "$l")" \
     --arg ty "$t" --arg lg "$l" \
     '(map(select(.url != $u))) + [{label:$lb, url:$u, type:$ty, lang:$lg}]' "$res" > "$res.tmp" && mv -f "$res.tmp" "$res"
}

# doc_unpublish <c> <tipo> <lang> — o inverso (tira do config.json e da seção "Prova").
doc_unpublish(){
  local c="$1" t="$2" l="$3" d cfg res
  d="$(doc_dir "$c")"; mkdir -p "$d" 2>/dev/null
  cfg="$(doc_conf_get "$c" | jq -c --arg k "$t.$l" '.published = ((.published // []) | map(select(. != $k)))')" || return 1
  printf '%s\n' "$cfg" > "$d/config.json.tmp" && mv -f "$d/config.json.tmp" "$d/config.json" || return 1
  res="$CONTESTSDIR/$c/resources.json"; [[ -s "$res" ]] || printf '[]' > "$res"
  jq -c --arg u "$(_doc_url "$c" "$t" "$l")" 'map(select(.url != $u))' "$res" > "$res.tmp" && mv -f "$res.tmp" "$res"
}

# doc_pending <c> -> linhas "tipo\tlang" dos documentos GERADOS que ainda não foram publicados
# (é o que o "encerrar evento" libera de uma vez).
doc_pending(){
  local c="$1" pub t l
  pub="$(doc_conf_get "$c" | jq -c '.published // []')"; [[ -n "$pub" ]] || pub='[]'
  for t in $DOC_TYPES; do for l in $DOC_LANGS; do
    [[ -n "$(doc_pdf_served "$c" "$t" "$l")" || -s "$(doc_file "$c" "$t" "$l" html)" ]] || continue
    jq -e --arg k "$t.$l" 'index($k) != null' <<<"$pub" >/dev/null 2>&1 && continue
    printf '%s\t%s\n' "$t" "$l"
  done; done
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
  # CPEN/CPENV = penalidade ICPC (minutos e códigos que penalizam; "__unset" = default da
  # plataforma) e CFSIZE = teto de saída do programa (ULIMITS[-f], KB) — a folha de ambiente
  # publica os três (2026-09-14, padrão da folha da SBC).
  CPEN=""; CPENV=""; CFSIZE=""
  _kv="$( declare -A ULIMITS 2>/dev/null || true
    . "$CONTESTSDIR/$c/conf" 2>/dev/null
    printf 'CNAME=%q CDATE=%q CLANGS=%q CMEM=%q CSTACK=%q CPEN=%q CPENV=%q CFSIZE=%q' \
      "${CONTEST_NAME:-$c}" "${CONTEST_START:-0}" "${LANGUAGES:-}" \
      "${MEMLIMITMB:-1024}" "${ULIMITS[-s]:-131072}" \
      "${PENALTY_MINUTES:-20}" "${PENALTY_VERDICTS-__unset}" "${ULIMITS[-f]:-256000}" )"
  [[ -n "$_kv" ]] && eval "$_kv"
  [[ -n "$CNAME" ]] || CNAME="$c"
  [[ "$CPEN" =~ ^[0-9]+$ ]] || CPEN=20
  [[ "$CFSIZE" =~ ^[0-9]+$ ]] || CFSIZE=256000
  declare -F penalty_code_canon >/dev/null || source "$_DIR/lib/verdict.sh"
  [[ "$CPENV" == "__unset" ]] && CPENV="$PENALTY_CODES_DEFAULT"
}

# _doc_penalty_exceptions <lang> -> nomes dos veredictos que NÃO contam penalidade (de
# PENALTY_VERDICTS × o universo fixo PENALTY_CODES_ALL), separados por vírgula; vazio = "nenhum".
_doc_penalty_exceptions(){
  local l="$1" code out=""
  for code in $PENALTY_CODES_ALL; do
    [[ " $CPENV " == *" $code "* ]] && continue
    out+="${out:+, }$(penalty_code_canon "$code")"
  done
  printf '%s' "${out:-$(_doc_t "$l" none_w)}"
}
# _doc_verdicts_html -> <ul> com os veredictos que o competidor pode receber (o provisório +
# as 6 classes canônicas de lib/verdict.sh — os nomes são os do MOJ, não se traduzem)
_doc_verdicts_html(){
  local v out='<ul><li>Not Answered Yet</li>'
  local IFS='|'; for v in $VERDICT_CLASSES; do out+="<li>$(_doc_escs "$v")</li>"; done
  printf '%s</ul>' "$out"
}
# _doc_os -> SO das máquinas de julgamento (campo `os` do registry, reportado pelo agente a
# partir do /etc/os-release da ROOTFS — judge/agent/inventory.sh); vazio = juiz antigo.
_doc_os(){
  find "${REGISTRYDIR:-$RUNDIR/registry}" -maxdepth 1 -name '*.json' -exec cat {} + 2>/dev/null \
    | jq -rs '[ .[] | (.os // "") | select(type == "string" and . != "") ] | unique | join(" / ")' 2>/dev/null
}
# _doc_lang_blocks <langs> — filtro dos blocos condicionais do template:
#   {{#LANG c cpp}} … {{/LANG}}  fica só se ALGUMA das linguagens listadas está na whitelist do
# contest (LANGUAGES vazio = todas as da plataforma = todos os blocos ficam). É o que deixa a
# seção "Compilação e execução" ter uma subseção por linguagem sem inventar seção p/ linguagem
# que ninguém pode usar. Marcadores sempre sozinhos na linha.
_doc_lang_blocks(){
  awk -v keep="$1" '
    BEGIN{ n=split(keep,K," "); for(i=1;i<=n;i++) KP[K[i]]=1; all=(n==0); skip=0 }
    /^[ \t]*\{\{#LANG[ \t]/ { s=$0; sub(/^[ \t]*\{\{#LANG[ \t]+/,"",s); sub(/[ \t]*\}\}.*$/,"",s)
      m=split(s,L," "); ok=all; for(i=1;i<=m;i++) if(L[i] in KP) ok=1; skip=!ok; next }
    /^[ \t]*\{\{\/LANG\}\}/ { skip=0; next }
    !skip { print }'
}

_doc_date(){  # <epoch> <lang> [contest] — data da prova NO FUSO DELA
  # sem o fuso do contest, uma prova que começa depois das 21h (BRT) saía no documento com a
  # data do DIA SEGUINTE (o servidor renderiza em UTC por padrão).
  local e="${1:-0}" l="$2" c3="${3:-}" tz=""
  [[ "$e" =~ ^[0-9]+$ && "$e" -gt 0 ]] || { printf '—'; return; }
  [[ -n "$c3" ]] && tz="$(contest_tz "$c3")"
  # nome do mês vem da tabela (_doc_month), não do locale: a imagem slim não tem pt_BR nem es_ES
  local d m y
  d="$(TZ="${tz:-$TZ}" date -d "@$e" '+%d')"; m="$(TZ="${tz:-$TZ}" date -d "@$e" '+%m')"
  y="$(TZ="${tz:-$TZ}" date -d "@$e" '+%Y')"
  case "$l" in
    en) printf '%s %s, %s' "$(_doc_month en "$m")" "${d#0}" "$y";;
    es) printf '%s de %s de %s' "${d#0}" "$(_doc_month es "$m")" "$y";;
    *)  printf '%s de %s de %s' "${d#0}" "$(_doc_month pt "$m")" "$y";;
  esac
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

# _doc_lang_short <id> -> nome curto p/ cabeçalho de coluna (a versão longa é _doc_lang_name)
_doc_lang_short(){ case "$1" in py) printf 'Python';; sh) printf 'Shell';; *) _doc_lang_name "$1";; esac; }

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
    printf '%s: %s\n' "$(_doc_lang_name "$k")" "$v"
  done <<<"$tmp"
}

# _doc_langs_table <c> <lang> -> tabela HTML das linguagens aceitas no contest
_doc_langs_table(){
  local c="$1" l="$2" langs
  langs="$( . "$CONTESTSDIR/$c/conf" 2>/dev/null; printf '%s' "${LANGUAGES:-}" )"
  [[ -n "$langs" ]] || { printf '<p>%s: %s.</p>' "$(_doc_t "$l" langs)" "$(_doc_t "$l" all_langs)"; return; }
  printf '<table class="doc-tbl"><thead><tr><th %s>%s</th><th %s>%s</th></tr></thead><tbody>' \
    "$_DOC_TH_RULE" "$(_doc_t "$l" langs)" "$_DOC_TH_RULE" "$(_doc_t "$l" file_ext)"
  local x arr=() i st
  for x in $langs; do arr+=( "$x" ); done
  for i in "${!arr[@]}"; do
    st="$_DOC_TD"; (( i == ${#arr[@]} - 1 )) && st="$_DOC_TD_LAST"
    # C++ aceita quatro extensões (2026-09-14): a folha diz ao time o que pode mandar
    local _exts=".${arr[$i]}"; [[ "${arr[$i]}" == cpp ]] && _exts=".cpp, .cc, .cxx, .c++"
    printf '<tr><td %s>%s</td><td %s><code>%s</code></td></tr>' \
      "$st" "$(_doc_escs "$(_doc_lang_name "${arr[$i]}")")" "$st" "$(_doc_escs "$_exts")"
  done
  printf '</tbody></table>'
}

# _doc_tl_matrix <c> -> JSON [{letter,name,tl:{<lang>:<segundos>}}] — o mesmo recorte de
# doc_tl_rows (só as linguagens permitidas no problema), mas com o mapa POR LINGUAGEM inteiro:
# é o que deixa a tabela decidir entre "um número" e "uma coluna por linguagem".
_doc_tl_matrix(){
  local c="$1" probs n i letter name pid tl allow out='[]'
  probs="$(cc_probs_json "$c")"
  n="$(jq -r 'length' <<<"$probs" 2>/dev/null)"; [[ "$n" =~ ^[0-9]+$ ]] || n=0
  for ((i=0; i<n; i++)); do
    letter="$(jq -r --argjson i "$i" '.[$i].letter // ""' <<<"$probs")"
    name="$(jq -r --argjson i "$i" '.[$i].name // ""' <<<"$probs")"
    pid="$(jq -r --argjson i "$i" '.[$i].statement_key // .[$i].problem_id // ""' <<<"$probs")"
    tl="$(tl_store_served "$pid" "$(_doc_pool "$c" "$pid")" 2>/dev/null)"; [[ -n "$tl" ]] || tl='{}'
    allow="[]"; declare -F effective_problem_langs >/dev/null && allow="$(effective_problem_langs "$c" "$pid" 2>/dev/null)"
    [[ -n "$allow" ]] || allow='[]'
    out="$(jq -c --arg L "$letter" --arg N "$name" --argjson allow "$allow" --argjson tl "$tl" '
      . + [{letter:$L, name:$N,
            tl: ($tl | to_entries | map(select(.key != "default"))
                 | map(.key as $k | select(($allow|length) == 0 or (($allow|index($k)) != null)))
                 | map({key, value:(.value|tonumber|(.*1000|round)/1000)}) | from_entries)}]' <<<"$out" 2>/dev/null)" || out='[]'
  done
  printf '%s' "${out:-[]}"
}

# _doc_tl_table <c> <lang> -> tabela HTML letra|nome|TL (+ nota de rodapé). Se TODO problema
# tem um TL só (igual em todas as linguagens permitidas), sai UMA coluna e a nota "não depende
# da linguagem" (padrão da folha da SBC); senão sai UMA COLUNA POR LINGUAGEM (ordem de LANGUAGES
# do contest) com "—" onde não se aplica, e a nota diz isso (2026-09-14).
# FILETES DA TABELA (booktabs) — INLINE, de propósito: o importador de HTML do LibreOffice
# IGNORA borda de tabela/célula vinda de CSS (testado: só o atributo `style=` na própria célula
# rende). O `contest-doc.css` mantém as mesmas regras para quem abre o HTML no navegador.
_DOC_TH_RULE='style="border-top:1.1pt solid #000;border-bottom:.6pt solid #000;padding:.3em .9em .3em 0;text-align:left"'
_DOC_TD_LAST='style="border-bottom:1.1pt solid #000;padding:.3em .9em .3em 0"'
_DOC_TD='style="padding:.3em .9em .3em 0"'

_doc_tl_table(){
  local c="$1" l="$2" m langs
  m="$(_doc_tl_matrix "$c")"
  langs="$( . "$CONTESTSDIR/$c/conf" 2>/dev/null; printf '%s' "${LANGUAGES:-}" )"
  # a tabela inteira sai do jq (@html escapa nome de problema — nunca conteúdo de usuário como
  # FORMATO do printf); o filete de baixo vai na ÚLTIMA linha (o importador do Writer ignora
  # tr:last-child) e as bordas são INLINE (ver _DOC_TH_RULE)
  # cabeçalho por linguagem com o nome de exibição CURTO (C, C++, Java, Python…), não o id
  local names='{}' x
  for x in $(jq -r '[.[] | .tl | keys[]] | unique | .[]' <<<"${m:-[]}" 2>/dev/null); do
    names="$(jq -c --arg k "$x" --arg v "$(_doc_lang_short "$x")" '.[$k]=$v' <<<"$names")"
  done
  jq -r --arg th "$_DOC_TH_RULE" --arg td "$_DOC_TD" --arg tdl "$_DOC_TD_LAST" \
     --arg h_prob "$(_doc_t "$l" problem)" --arg h_name "$(_doc_t "$l" name)" --arg h_tl "$(_doc_t "$l" tl)" \
     --arg n_same "$(_doc_t "$l" tl_same)" --arg n_lang "$(_doc_t "$l" tl_per_lang)" \
     --arg order "$langs" --argjson names "$names" '
    def cell(v): if v == null then "—" else (v|tostring) end;
    (map(.tl | [.[]] | unique | length) | any(. > 1)) as $per_lang
    | (($order | split(" ") | map(select(. != ""))) as $o
       | ([.[] | .tl | keys[]] | unique) as $all
       | ($o | map(select(. as $x | ($all | index($x)) != null))) + ($all | map(select(. as $x | ($o | index($x)) == null)))) as $cols
    | (length) as $n
    | "<table class=\"doc-tbl\"><thead><tr><th \($th)>\($h_prob)</th><th \($th)>\($h_name)</th>"
      + (if $per_lang then ($cols | map("<th class=\"c\" \($th)>\(($names[.] // .)|@html)</th>") | join(""))
         else "<th class=\"c\" \($th)>\($h_tl)*</th>" end)
      + "</tr></thead><tbody>"
      + ([to_entries[] | (if .key == $n - 1 then $tdl else $td end) as $st | .value
          | "<tr><td class=\"c\" \($st)>\(.letter|@html)</td><td \($st)>\(.name|@html)</td>"
            + (if $per_lang then ([. as $r | $cols[] | "<td class=\"c\" \($st)>\(cell($r.tl[.]))</td>"] | join(""))
               else "<td class=\"c\" \($st)>\(cell(.tl | [.[]] | first))</td>" end)
            + "</tr>"] | join(""))
      + "</tbody></table>"
      + (if $n > 0 then "<p class=\"foot\">* \(if $per_lang then $n_lang else $n_same end)</p>" else "" end)' <<<"${m:-[]}" 2>/dev/null
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
  # marcadores -> conteúdo gerado (tabelas entram como HTML puro depois do pandoc). Os blocos
  # {{#LANG …}} são filtrados ANTES pela whitelist do contest (_doc_lang_blocks). Números:
  # SOURCE_MAX = SUBMIT_MAX_KB (submit.sh), OUTPUT_MAX = ULIMITS[-f] do conf (ou o default do
  # build-and-test), COMPILE_TL = COMPILETL do build-and-test (30 s), MEMLIMIT_MB/STACK_KB = o
  # que o juiz passa em -Xmx/-Xss (lang/java|kt/run.sh).
  local osname; osname="$(_doc_os)"; [[ -n "$osname" ]] || osname="GNU/Linux"
  _doc_lang_blocks "$CLANGS" < "$tpl" \
    | sed -e "s|{{CONTEST_NAME}}|$(_doc_escs "$CNAME")|g" \
      -e "s|{{DATE}}|$(_doc_date "$CDATE" "$l" "$c")|g" \
      -e "s|{{MEMLIMIT_MB}}|${CMEM:-1024}|g" \
      -e "s|{{MEMLIMIT}}|${CMEM:-1024} MB|g" \
      -e "s|{{STACK_KB}}|${CSTACK:-131072}|g" \
      -e "s|{{STACK}}|$(( ${CSTACK:-131072} / 1024 )) MB|g" \
      -e "s|{{OS}}|$(_doc_escs "$osname")|g" \
      -e "s|{{SOURCE_MAX}}|${SUBMIT_MAX_KB:-1024} KB|g" \
      -e "s|{{OUTPUT_MAX}}|$(( ${CFSIZE:-256000} / 1024 )) MB|g" \
      -e "s|{{COMPILE_TL}}|${DOC_COMPILE_TL:-30}|g" \
      -e "s|{{PENALTY}}|${CPEN:-20}|g" \
      -e "s|{{PENALTY_EXCEPTIONS}}|$(_doc_escs "$(_doc_penalty_exceptions "$l")")|g" \
      > "$tmp"
  local body; body="$(render_markdown_html < "$tmp" 2>/dev/null)"
  rm -f "$tmp"
  local tc; tc="$(_doc_toolchain "$c")"
  local tchtml="<ul>"; while IFS= read -r line; do [[ -n "$line" ]] && tchtml+="<li>$(_doc_escs "$line")</li>"; done <<<"$tc"; tchtml+="</ul>"
  [[ -n "$tc" ]] || tchtml="<p><i>$(_doc_t "$l" no_versions)</i></p>"
  _doc_html_head "$CNAME — info sheet"
  # bloco de título centrado (o \maketitle do LaTeX) — a classe é o que o CSS usa p/ centrar
  printf '<h1 class="title">%s</h1><div class="sub">%s</div>\n' "$(_doc_escs "$CNAME")" "$(_doc_date "$CDATE" "$l" "$c")"
  # substitui os marcadores de BLOCO que sobraram no HTML renderizado
  printf '%s' "$body" \
    | sed -e "s|{{TOOLCHAIN}}|$(printf '%s' "$tchtml" | sed 's/[&|]/\\&/g')|" \
          -e "s|{{LANGS_TABLE}}|$(_doc_langs_table "$c" "$l" | sed 's/[&|]/\\&/g')|" \
          -e "s|{{TL_TABLE}}|$(_doc_tl_table "$c" "$l" | sed 's/[&|]/\\&/g')|" \
          -e "s|{{VERDICTS}}|$(_doc_verdicts_html | sed 's/[&|]/\\&/g')|"
  _doc_html_foot
}

# _doc_html_times <c> <lang>
_doc_html_times(){
  local c="$1" l="$2" cfg errata
  _doc_meta "$c"; cfg="$(doc_conf_get "$c")"; errata="$(jq -r '.errata // ""' <<<"$cfg")"
  _doc_html_head "$CNAME — time limits"
  # bloco de título centrado (o \maketitle do LaTeX) — a classe é o que o CSS usa p/ centrar
  printf '<h1 class="title">%s</h1><div class="sub">%s</div>\n' "$(_doc_escs "$CNAME")" "$(_doc_date "$CDATE" "$l" "$c")"
  printf '<h2 class="center">%s</h2>\n' "$(_doc_t "$l" times_title)"
  _doc_tl_table "$c" "$l"          # (traz a nota "* …" sobre linguagem)
  printf '<p class="foot">%s</p>\n' "$(_doc_t "$l" seconds)"
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
        -e "s|{{DATE}}|$(_doc_date "$CDATE" "$l" "$c")|g" \
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
  printf '<div class="cover"><h1>%s</h1><div class="sub">%s</div>\n' "$(_doc_escs "$CNAME")" "$(_doc_date "$CDATE" "$l" "$c")"
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
      # só o miolo do <body>, sem o h1 do próprio enunciado (o cabeçalho já é nosso)
      _doc_body_inner "$f"
    else
      printf '<p><i>%s</i></p>' "$(_doc_t "$l" no_statement)"
    fi
    printf '</div>\n'
  done
  _doc_html_foot
}

# _doc_html_editorial <c> <lang> — EDITORIAL da prova: a SOLUÇÃO de cada problema, lida do
# docs/solucao.md do PACOTE (campo `editorial_md` da API de problemas — por contrato NUNCA
# vai ao aluno; o gen-problem-json o ignora). Conteúdo mais sensível que o caderno: o
# publish exige contest_over_for_all (handler) e o download idem p/ quem não é organização.
# UM PROBLEMA POR PÁGINA (pedido do Ribas, 2026-09-14): (1) a página 1 é uma CAPA (título, data,
# nota e o índice letra · nome); (2) cada problema abre com <h1 style="page-break-before:always">
# — o estilo INLINE é o que o importador de HTML do Writer honra (a regra `.prob{…}` do CSS em
# div ele ignora), e na rota ODT o Heading 1 do reference.odt já quebra; (3) os títulos de
# DENTRO do solucao.md são rebaixados um nível (_doc_demote_headings): sem isso um `# Ideia` do
# autor virava Heading 1 e abria página própria no meio da solução.
_doc_demote_headings(){
  python3 -c '
import re,sys
s=sys.stdin.read()
for n in (5,4,3,2,1):
    s=re.sub(r"<(/?)h%d\b" % n, lambda m: "<%sh%d" % (m.group(1), n+1), s, flags=re.I)
sys.stdout.write(s)' 2>/dev/null || cat
}
_doc_html_editorial(){
  local c="$1" l="$2" probs n i letter name skey pkg note
  _doc_meta "$c"
  probs="$(cc_probs_json "$c")"; n="$(jq -r 'length' <<<"$probs")"; [[ "$n" =~ ^[0-9]+$ ]] || n=0
  _doc_html_head "$(_doc_t "$l" editorial) — $CNAME"
  # capa: título + data + nota + índice
  printf '<div class="cover"><h1 class="title">%s — %s</h1><div class="sub">%s</div>\n' \
    "$(_doc_t "$l" editorial)" "$(_doc_escs "$CNAME")" "$(_doc_date "$CDATE" "$l" "$c")"
  note="$(doc_conf_get "$c" | jq -r '.editorial_note // ""')"
  if [[ -n "$note" ]]; then
    printf '<div class="note">'; printf '%s' "$note" | render_markdown_html; printf '</div>\n'
  fi
  printf '<h2 class="center">%s</h2>\n' "$(_doc_t "$l" ed_index)"
  jq -r --arg th "$_DOC_TH_RULE" --arg td "$_DOC_TD" --arg tdl "$_DOC_TD_LAST" \
     --arg h_prob "$(_doc_t "$l" problem)" --arg h_name "$(_doc_t "$l" name)" '
    (length) as $n
    | "<table class=\"doc-tbl\"><thead><tr><th \($th)>\($h_prob)</th><th \($th)>\($h_name)</th></tr></thead><tbody>"
      + ([to_entries[] | (if .key == $n - 1 then $tdl else $td end) as $st | .value
          | "<tr><td class=\"c\" \($st)>\(.letter // "" | @html)</td><td \($st)>\(.name // "" | @html)</td></tr>"] | join(""))
      + "</tbody></table>"' <<<"$probs" 2>/dev/null
  printf '</div>\n'
  for ((i=0; i<n; i++)); do
    letter="$(jq -r --argjson i "$i" '.[$i].letter // ""' <<<"$probs")"
    name="$(jq -r --argjson i "$i" '.[$i].name // ""' <<<"$probs")"
    skey="$(jq -r --argjson i "$i" '.[$i].statement_key // ""' <<<"$probs")"
    printf '<div class="prob"><h1 style="page-break-before:always">%s %s — %s</h1>\n' "$(_doc_t "$l" problem)" "$(_doc_escs "$letter")" "$(_doc_escs "$name")"
    pkg=""; declare -F pkg_path >/dev/null && pkg="$(pkg_path "$skey" 2>/dev/null)"
    if [[ -n "$pkg" && -s "$pkg/docs/solucao.md" ]]; then
      render_markdown_html < "$pkg/docs/solucao.md" | _doc_demote_headings
    else
      printf '<p><i>%s</i></p>' "$(_doc_t "$l" no_solution)"
    fi
    printf '</div>\n'
  done
  _doc_html_foot
}

# ---------- PDF ----------------------------------------------------------------------
# _doc_strip_annotation — remove os <annotation> (o TeX cru que o pandoc --mathml duplica
# dentro de cada <math>): o import HTML do LibreOffice descarta MathML achatando os nós de
# texto, e sem o strip cada fórmula saía DUAS vezes ("2≤n≤10⁵2 \leq n \leq 10^5").
_doc_strip_annotation(){
  python3 -c 'import re,sys; sys.stdout.write(re.sub(r"<annotation[^>]*>.*?</annotation>", "", sys.stdin.read(), flags=re.S))' 2>/dev/null || cat
}

# _doc_html2pdf <html-file> <pdf-out> -> 0/1 (soffice; único engine da imagem)
_doc_html2pdf(){
  local src="$1" out="$2" work; work="$(mktemp -d)"
  _doc_strip_annotation < "$src" > "$work/doc.html"
  [[ -s "$work/doc.html" ]] || cp -f "$src" "$work/doc.html"
  soffice --headless -env:UserInstallation="file://$work/lo" --convert-to pdf \
          --outdir "$work" "$work/doc.html" >/dev/null 2>&1
  if [[ -s "$work/doc.pdf" ]]; then mv -f "$work/doc.pdf" "$out"; rm -rf "$work"; return 0; fi
  rm -rf "$work"; return 1
}
_doc_pages(){ pdfinfo "$1" 2>/dev/null | awk '/^Pages:/{print $2; exit}'; }

# _doc_html2pdf_odt <html-file> <pdf-out> -> 0/1 — ROTA PREFERIDA p/ conteúdo com MathML:
# pandoc html→odt + soffice odt→pdf. O import HTML do Writer NÃO entende MathML (achatava
# as fórmulas); via ODT elas viram fórmulas ODF de verdade — exige o libreoffice-math da
# imagem. O ESTILO vem do reference-doc etc/caderno-reference.odt (ODT ignora CSS): Text
# Body JUSTIFICADO + Preformatted Text com fundo/borda (a caixa dos exemplos). Receita p/
# regenerar: `pandoc --print-default-data-file reference.odt`, retocar no styles.xml os
# estilos Text_20_body (fo:text-align=justify) e Preformatted_20_Text
# (fo:background-color/fo:padding/fo:border) e rezipar com o mimetype PRIMEIRO (zip -0).
# O html de entrada NÃO deve ter <title> (o pandoc o promoveria a título órfão no topo).
_doc_html2pdf_odt(){
  local src="$1" out="$2" work rf refodt=()
  command -v pandoc >/dev/null 2>&1 || return 1
  work="$(mktemp -d)"
  rf="$_DIR/../../etc/caderno-reference.odt"; [[ -f "$rf" ]] || rf="$_DIR/etc/caderno-reference.odt"
  [[ -f "$rf" ]] && refodt=( --reference-doc="$rf" )
  if pandoc -f html -t odt "${refodt[@]}" "$src" -o "$work/doc.odt" 2>/dev/null; then
    soffice --headless -env:UserInstallation="file://$work/lo" --convert-to pdf \
            --outdir "$work" "$work/doc.odt" >/dev/null 2>&1
    [[ -s "$work/doc.pdf" ]] && { mv -f "$work/doc.pdf" "$out"; rm -rf "$work"; return 0; }
  fi
  rm -rf "$work"; return 1
}

# _doc_pdf_contest <c> <lang> <out.pdf> — caderno: capa + (PDF custom | enunciado renderizado),
# unidos com pdfunite; capa REGERADA no fim com o total real de páginas.
# _doc_body_inner <arquivo-html> -> só o miolo do <body>, sem o título do próprio enunciado.
# Duas armadilhas que apareceram no PDF: (1) enunciado gerado em UMA LINHA fazia o `sed` de
# faixa devolver o <head> junto — e o pandoc promovia o <title> a um título gigante no topo da
# página; (2) o <h1 class="moj-title"> do enunciado é escondido por CSS na rota HTML, mas a rota
# ODT IGNORA CSS e o nome do problema saía DUAS vezes ("Problema A — Soma" + "Soma").
_doc_body_inner(){
  sed -n '/<body[^>]*>/,/<\/body>/p' "$1" \
    | sed -e 's|.*<body[^>]*>||' -e 's|</body>.*||' \
    | python3 -c 'import re,sys; sys.stdout.write(re.sub(r"<h1[^>]*class=\"[^\"]*moj-title[^\"]*\"[^>]*>.*?</h1>", "", sys.stdin.read(), flags=re.S|re.I))' 2>/dev/null \
    || sed -n '/<body[^>]*>/,/<\/body>/p' "$1" | sed -e 's|.*<body[^>]*>||' -e 's|</body>.*||'
}

# CADERNO. Quando NENHUM problema tem PDF próprio, os enunciados viram UM ODT só — é o que dá
# NUMERAÇÃO CONTÍNUA (antes cada problema era um PDF e a página voltava a "1" em cada um, com a
# capa anunciando "páginas numeradas de 1 a N" que não existia). A quebra entre problemas vem do
# `fo:break-before="page"` do Heading 1 no caderno-reference.odt. Com PDF próprio no meio, não há
# como renumerar (não temos pdftk/cpdf na imagem): volta ao caminho por-problema.
_doc_pdf_contest(){
  local c="$1" l="$2" out="$3" probs n i skey work parts=() pdf tot=0 custom=""
  work="$(mktemp -d)"; probs="$(cc_probs_json "$c")"; n="$(jq -r 'length' <<<"$probs")"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  for ((i=0; i<n; i++)); do
    skey="$(jq -r --argjson i "$i" '.[$i].statement_key // ""' <<<"$probs")"
    [[ -f "$CONTESTSDIR/$c/enunciados/$skey.pdf" ]] && { custom=1; break; }
  done
  if [[ -z "$custom" && "$n" -gt 0 ]]; then
    # --- caminho normal: um ODT com todos os enunciados (numeração contínua) ---
    local allf="$work/all.html" letter name f bodyf
    { printf '<!DOCTYPE html><html><head><meta charset="utf-8"></head><body>'
      for ((i=0; i<n; i++)); do
        skey="$(jq -r --argjson i "$i" '.[$i].statement_key // ""' <<<"$probs")"
        letter="$(jq -r --argjson i "$i" '.[$i].letter // ""' <<<"$probs")"
        name="$(jq -r --argjson i "$i" '.[$i].name // ""' <<<"$probs")"
        f="$CONTESTSDIR/$c/enunciados/$skey.html"
        if [[ ! -f "$f" ]]; then
          local jf="$CONTESTSDIR/treino/var/jsons/$skey.json"
          [[ -f "$jf" ]] || jf="$CONTESTSDIR/treino/var/jsons-private/$skey.json"
          [[ -f "$jf" ]] && { jq -r '.statement_html_b64 // ""' "$jf" 2>/dev/null | base64 -d > "$work/s$i.html" 2>/dev/null; [[ -s "$work/s$i.html" ]] && f="$work/s$i.html"; }
        fi
        printf '<h1>%s %s — %s</h1>' "$(_doc_t "$l" problem)" "$(_doc_escs "$letter")" "$(_doc_escs "$name")"
        if [[ -f "$f" ]]; then _doc_body_inner "$f"; else printf '<p><i>%s</i></p>' "$(_doc_t "$l" no_statement)"; fi
      done
      printf '</body></html>'; } > "$allf"
    if _doc_html2pdf_odt "$allf" "$work/body.pdf" && [[ -s "$work/body.pdf" ]]; then
      parts=( "$work/body.pdf" ); tot="$(_doc_pages "$work/body.pdf" 2>/dev/null || echo 0)"
      n="$n"   # (mantém a contagem de problemas para a capa)
    else
      custom=1   # pandoc indisponível/falhou: cai no caminho por-problema (com fallback soffice)
    fi
  fi
  # --- caminho por-problema (só quando há PDF próprio de enunciado, ou o pandoc falhou) ---
  [[ -n "$custom" ]] && for ((i=0; i<n; i++)); do
    skey="$(jq -r --argjson i "$i" '.[$i].statement_key // ""' <<<"$probs")"
    pdf="$CONTESTSDIR/$c/enunciados/$skey.pdf"
    if [[ -f "$pdf" ]]; then
      cp -f "$pdf" "$work/p$i.pdf"
    else
      # renderiza SÓ este problema (capa fica de fora) e converte
      local letter name f bodyf="$work/b$i.html" okpdf=""
      letter="$(jq -r --argjson i "$i" '.[$i].letter // ""' <<<"$probs")"
      name="$(jq -r --argjson i "$i" '.[$i].name // ""' <<<"$probs")"
      f="$CONTESTSDIR/$c/enunciados/$skey.html"
      if [[ ! -f "$f" ]]; then
        local jf="$CONTESTSDIR/treino/var/jsons/$skey.json"
        [[ -f "$jf" ]] || jf="$CONTESTSDIR/treino/var/jsons-private/$skey.json"
        [[ -f "$jf" ]] && { jq -r '.statement_html_b64 // ""' "$jf" 2>/dev/null | base64 -d > "$work/s$i.html" 2>/dev/null; [[ -s "$work/s$i.html" ]] && f="$work/s$i.html"; }
      fi
      # miolo do <body> do enunciado (HTML standalone com <head> próprio)
      if [[ -f "$f" ]]; then
        _doc_body_inner "$f" > "$bodyf"
      else
        printf '<p><i>%s</i></p>' "$(_doc_t "$l" no_statement)" > "$bodyf"
      fi
      # rota preferida: pandoc→odt→pdf (MathML vira fórmula ODF; ver _doc_html2pdf_odt)
      { printf '<!DOCTYPE html><html><head><meta charset="utf-8"></head><body>'
        printf '<h1>%s %s — %s</h1>' "$(_doc_t "$l" problem)" "$(_doc_escs "$letter")" "$(_doc_escs "$name")"
        cat "$bodyf"; printf '</body></html>'; } > "$work/o$i.html"
      _doc_html2pdf_odt "$work/o$i.html" "$work/p$i.pdf" && okpdf=1
      # FALLBACK (sem pandoc / pandoc falhou): soffice direto no HTML — o strip de
      # <annotation> do _doc_html2pdf ao menos evita o TeX duplicado.
      if [[ -z "$okpdf" ]]; then
        local h="$work/p$i.html"
        { _doc_html_head "x"; printf '<div class="prob">';
          printf '<h1>%s %s — %s</h1>' "$(_doc_t "$l" problem)" "$(_doc_escs "$letter")" "$(_doc_escs "$name")"
          cat "$bodyf"
          printf '</div>'; _doc_html_foot; } > "$h"
        _doc_html2pdf "$h" "$work/p$i.pdf" || continue
      fi
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
    editorial)  _doc_html_editorial "$c" "$l" > "$tmp" ;;
    *) return 2 ;;
  esac
  [[ -s "$tmp" ]] || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$html"
  if [[ "$t" == contest ]]; then _doc_pdf_contest "$c" "$l" "$pdf.tmp" && mv -f "$pdf.tmp" "$pdf" || rm -f "$pdf.tmp"
  elif [[ "$t" == editorial ]]; then
    # um documento só, pela rota ODT (as soluções têm math); miolo sem <title>
    local mini="$d/.$t.$l.odtin.html"
    { printf '<!DOCTYPE html><html><head><meta charset="utf-8"></head><body>'
      sed -n '/<body[^>]*>/,/<\/body>/p' "$html" | sed -e 's|.*<body[^>]*>||' -e 's|</body>.*||'
      printf '</body></html>'; } > "$mini"
    _doc_html2pdf_odt "$mini" "$pdf.tmp" || _doc_html2pdf "$html" "$pdf.tmp" || true
    rm -f "$mini"
    if [[ -s "$pdf.tmp" ]]; then mv -f "$pdf.tmp" "$pdf"; else rm -f "$pdf.tmp"; fi
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
  # SEM index.json (contest que nunca gerou nada) a lista parte de [] e SEGUE p/ a varredura
  # dos PDFs enviados — o early-return que havia aqui deixava o enviado invisível e a UI sem o
  # botão "publicar" ("tenho de gerar a versão do moj antes", relato do Ribas, 2026-09-14).
  # a chave é BINDADA antes (`as $k`): o argumento de `index()` avalia contra a ENTRADA do
  # pipe — que aqui é `$p`, o array de publicados —, não contra o elemento do map. Sem o
  # bind dava "Cannot index array with string" e a lista de documentos voltava VAZIA.
  # o PDF ENVIADO não passa pelo index.json (não é "gerado"): entra aqui, por par tipo+idioma,
  # lido do disco — é o que a UI usa p/ mostrar "enviado" e o botão de voltar ao gerado.
  local upl='[]' t l f
  for t in $DOC_TYPES; do for l in $DOC_LANGS; do
    f="$(doc_upload_pdf "$c" "$t" "$l")"; [[ -s "$f" ]] || continue
    upl="$(jq -c --arg t "$t" --arg l "$l" --argjson b "$(stat -c%s "$f" 2>/dev/null || echo 0)" \
            --argjson at "$(stat -c%Y "$f" 2>/dev/null || echo 0)" \
            '. + [{type:$t, lang:$l, bytes:$b, at:$at}]' <<<"$upl")"
  done; done
  jq -c --argjson p "$pub" --argjson u "$upl" '
      ($u | map({(.type + "." + .lang): .}) | add // {}) as $U
      | map((.type + "." + .lang) as $k
            | . + {published: (($p | index($k)) != null),
                   uploaded: ($U[$k] != null),
                   uploaded_bytes: ($U[$k].bytes // 0), uploaded_at: ($U[$k].at // 0)})
      # par que SÓ tem PDF enviado (nunca foi gerado) também precisa aparecer na lista
      | . as $rows
      | $rows + ($u | map(select(. as $x | ($rows | any(.type == $x.type and .lang == $x.lang)) | not))
                    # ⚠ chave BINDADA antes: o argumento de index() avalia contra a ENTRADA do
                    # pipe ($p, um array), não contra o elemento — sem isto o jq morre e a
                    # listagem inteira volta VAZIA (a mesma pegadinha do bloco acima)
                    | map((.type + "." + .lang) as $k
                          | {type, lang, html_bytes:0, pdf_bytes:0, generated_at:0, by:"",
                             published: (($p | index($k)) != null),
                             uploaded:true, uploaded_bytes:.bytes, uploaded_at:.at}))' \
     <<<"$( [[ -s "$idx" ]] && cat "$idx" || printf '[]' )" 2>/dev/null || printf '[]'
}

# doc_index_upsert <c> <entrada-json>
doc_index_upsert(){
  local c="$1" e="$2" d; d="$(doc_dir "$c")"; mkdir -p "$d" 2>/dev/null
  local idx="$d/index.json"; [[ -s "$idx" ]] || printf '[]' > "$idx"
  jq -c --argjson e "$e" '(map(select(.type != $e.type or .lang != $e.lang)) + [$e])
     | sort_by(.type, .lang)' "$idx" > "$idx.tmp" \
    && mv -f "$idx.tmp" "$idx"
}
