# GET /contest/problems?contest=<id>   (Bearer)
# Lista de problemas da prova a partir de PROBS (5-tuplas) + enunciados/<key>.{html,pdf}.
# [{short_name, full_name, problem_id, has_statement_html, has_statement_pdf, time_limits, show}]
#
# O ENUNCIADO NÃO VEM AQUI (2026-08-20). Vinha, em base64 — e num contest de PDF isso é 3,8 MB
# crus / 2,5 MB comprimidos POR TIME (base64 de PDF não comprime: o PDF já é comprimido).
# Com 2000 times abrindo a prova no mesmo segundo são ~5 GB de uma vez, para entregar 12
# enunciados dos quais cada time lê um por vez. Hoje a lista diz só QUE EXISTE
# (`has_statement_html`/`has_statement_pdf`) e o corpo sai pelo `/contest/statement`, quando a
# pessoa abre a sanfona ou clica em HTML/PDF — mesma doutrina dos documentos da prova.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

# Gate de visibilidade (forçado pela API): .staff nunca vê enunciados; usuário normal só
# DEPOIS do início (antes disso o front mostra a tela de contagem regressiva). .admin/.judge
# veem sempre. Retorna lista vazia + `locked` p/ o front saber o motivo.
source "$_LIBDIR/contest-gate.sh"
if ! can_see_problems "$contest"; then
  emit_json 200 OK
  jq -cn --arg s "$( { is_staff || is_cstaff; } && echo staff || echo not_started)" '{success:true, problems:[], locked:$s}'
  exit 0
fi

CONTEST_ID="$contest"; PROBS=(); LANGUAGES=""; SHOWTL=""; CONTEST_JUDGES=""
load_contest_conf "$contest"
# tempo-limite por problema (do store run/tl/<id>.json), salvo se o conf ocultar (SHOWTL=0).
source "$_DIR/lib/tl-store.sh"
SHOW_TL=true; [[ "$SHOWTL" == 0 ]] && SHOW_TL=false
# autor do problema: revelado com a prova ENCERRADA (ou sempre p/ quem organiza)
SHOW_AUTHOR=false
{ contest_over_for_all "$contest" || is_admin_or_chief || is_judge; } && SHOW_AUTHOR=true
# ---- CACHE DE RESPOSTA -------------------------------------------------------------------
# Esta rota monta o MESMO payload para todos os times (~77 processos com 12 problemas), e no
# segundo em que a prova abre os 2000 times a pedem juntos. O cache é POR VARIANTE, e a única
# dimensão que muda o corpo é o AUTOR: ele só aparece com a prova encerrada ou p/ quem organiza
# (contest_over_for_all || is_admin_or_chief || is_judge). Se a variante fosse ignorada, um GET
# do juiz encheria o cache com o autor dentro e o competidor o receberia — é o vazamento que o
# smoke-contest-problems-cache.sh existe p/ impedir.
#
# FRESCOR: em vez de confiar em alguém lembrar de invalidar, o cache é comparado com as ENTRADAS
# (`-nt` é builtin do bash: zero processos). Entram o conf (PROBS/LANGUAGES/SHOWTL/CONTEST_JUDGES),
# os dois json de override, o diretório de enunciados, o **`run/tl`** (um juiz reportando TL
# novo faz um `mv` lá dentro, o que mexe no mtime do diretório) e um carimbo explícito que o
# /contest/admin/problems toca. O teto de idade cobre só o que sobra — o `languages` do pacote
# no treino — e por isso é LARGO: era 60 s, o que forçava uma regeração por minuto durante a
# prova inteira; hoje a mudança que importa chega por entrada, não por relógio.
CVAR=noauthor; [[ "$SHOW_AUTHOR" == true ]] && CVAR=author
CDIR="$CONTESTSDIR/$contest/var"; CF="$CDIR/problems-cache.$CVAR.json"
: "${PROBLEMS_CACHE_TTL:=900}"
_cache_fresh(){
  resp_cache_fresh "$CF" "$PROBLEMS_CACHE_TTL" \
    "$CONTESTSDIR/$contest/conf" "$CONTESTSDIR/$contest/problem-langs.json" \
    "$CONTESTSDIR/$contest/problem-judges.json" "$CONTESTSDIR/$contest/enunciados" \
    "$RUNDIR/tl" "$CDIR/.problems-dirty"
}
# O payload é grande (enunciados embutidos: MB) e idêntico p/ todos. Se o nginx comprimir a
# cada resposta, 2000 times no segundo da abertura pagam 2000 compressões do MESMO conteúdo —
# medido: derruba a rota a ~137 req/s. Como o corpo está em cache, guardamos também a versão
# comprimida e a servimos direto; o nginx não recomprime resposta que já vem com
# Content-Encoding. `Vary` é obrigatório: sem ele um intermediário serviria bytes comprimidos
# a um cliente que não os aceita.
_serve_cache(){
  if [[ -s "$CF.gz" && ! "$CF" -nt "$CF.gz" && "${HTTP_ACCEPT_ENCODING:-}" == *gzip* ]]; then
    printf 'Status: 200 OK\r\nContent-Type: application/json; charset=utf-8\r\n'
    printf 'Content-Encoding: gzip\r\nVary: Accept-Encoding\r\n\r\n'
    cat "$CF.gz"
  else
    emit_json 200 OK; printf '%s' "$(<"$CF")"
  fi
}
if _cache_fresh; then _serve_cache; exit 0; fi

# REGERAÇÃO SOB LOCK, SERVINDO O VELHO. Sem isto, no segundo em que o cache vence TODAS as
# requisições em voo regeneram juntas — com 2000 times polando, é a mesma conta paga 2000 vezes
# ao mesmo tempo. Quem pega o lock regenera; quem não pega serve o cache de alguns segundos
# atrás e vai embora (lista de problemas alguns segundos atrasada não é problema; a rota travar
# no meio da prova é). Só quem chega SEM cache nenhum espera de fato.
mkdir -p "$CDIR" 2>/dev/null
if exec 9>>"$CDIR/.problems.lock" 2>/dev/null; then
  if ! flock -n 9 2>/dev/null; then
    [[ -s "$CF" ]] && { _serve_cache; exit 0; }
    flock -w 15 9 2>/dev/null || true         # 1ª geração do contest: espera quem está gerando
    _cache_fresh && { _serve_cache; exit 0; }
  fi
fi

# linguagens permitidas: cadeia em lib/langs.sh (FONTE ÚNICA — o /submit APLICA a mesma
# lista que esta listagem oferece; front filtra o editor e a tabela de TL por ela).
source "$_LIBDIR/langs.sh"
# pool de juízes: override por problema (problem-judges.json) -> pool do contest
# (CONTEST_JUDGES) -> "" (= todos). O TL servido é o MÁX só entre os hosts do pool efetivo.
PJUDGES='{}'; [[ -f "$CONTESTSDIR/$contest/problem-judges.json" ]] && PJUDGES="$(jq -c . "$CONTESTSDIR/$contest/problem-judges.json" 2>/dev/null)"; [[ -n "$PJUDGES" ]] || PJUDGES='{}'

set +o noglob
ENUN="$CONTESTSDIR/$contest/enunciados"

# CHECKSUM DO PACOTE: vem do ÍNDICE de problemas, num jq só p/ a prova inteira — NÃO de reabrir
# o pacote. Quem conhece o problema é a gestão de problemas, e ela já carimba o `tl_checksum`
# (é a mesma comparação-de-dois-checksums-materializados que o `/problems/status` faz, e a mesma
# origem do `time_limits` que o treino serve). Hashear o pacote aqui custava 112,8 MB lidos e
# 1,3 s por regeração — para exibir tempo-limite na tela.
declare -A TLCKS=()
_ids=()
for (( i=0; i<${#PROBS[@]}; i+=5 )); do
  _sid="${PROBS[$((i+4))]}"; [[ "$_sid" == *"#"* ]] || _sid="${PROBS[$((i+1))]//\//#}"
  _ids+=("$_sid")
done
if [[ "$SHOW_TL" == true ]] && (( ${#_ids[@]} )); then
  while IFS=$'\t' read -r _ci _cc; do [[ -n "$_ci" ]] && TLCKS["$_ci"]="$_cc"; done \
    < <(tl_index_checksums "${_ids[@]}")
fi

declare -a ITEMS
for (( i=0; i<${#PROBS[@]}; i+=5 )); do
  FROM="${PROBS[$i]}"
  # id canônico do pacote = 'coleção#problema' (igual ao treino: pkg_path/judge exigem '#').
  # O statement_key (PROBS[i+4]) JÁ é a forma '#' nos contests novos; em contests legados
  # ele é o nome simples (sem coleção), então caímos para converter a barra do problem_id.
  PROBLEMID="${PROBS[$((i+4))]}"
  [[ "$PROBLEMID" == *"#"* ]] || PROBLEMID="${PROBS[$((i+1))]//\//#}"
  FULLNAME="${PROBS[$((i+2))]}"
  SHORTNAME="${PROBS[$((i+3))]}"
  STATEMENT="${PROBS[$((i+4))]}"

  args=(); filt='{short_name:$short, full_name:$full, problem_id:$id, show:true'
  # só a EXISTÊNCIA: o corpo sai pelo /contest/statement (ver o cabeçalho deste arquivo)
  HAS_PDF=false; [[ -f "$ENUN/$STATEMENT.pdf" ]] && HAS_PDF=true
  HAS_HTML=false
  if [[ -f "$ENUN/$STATEMENT.html" ]]; then
    HAS_HTML=true
  else
    # fallback: enunciado gerado DEPOIS (problema privado validado -> jsons-private).
    # Aparece automaticamente assim que o juiz indexa; materializa no contest na 1ª vez, e daí
    # em diante é o arquivo do contest que o /contest/statement serve.
    jf="$CONTESTSDIR/treino/var/jsons/$STATEMENT.json"; [[ -f "$jf" ]] || jf="$CONTESTSDIR/treino/var/jsons-private/$STATEMENT.json"
    if [[ -f "$jf" ]] && jq -e '(.statement_html_b64 // "") != ""' "$jf" >/dev/null 2>&1; then
      if ( mkdir -p "$ENUN" && jq -r '.statement_html_b64 // ""' "$jf" | base64 -d > "$ENUN/$STATEMENT.html.tmp.$$" \
           && mv -f "$ENUN/$STATEMENT.html.tmp.$$" "$ENUN/$STATEMENT.html" ) 2>/dev/null
      then HAS_HTML=true; else rm -f "$ENUN/$STATEMENT.html.tmp.$$" 2>/dev/null; fi
    fi
  fi
  filt+=", has_statement_html:$HAS_HTML, has_statement_pdf:$HAS_PDF"
  # enunciado pode ser uma URL externa
  if [[ "$STATEMENT" == *http* ]]; then
    args+=( --arg url "$STATEMENT" ); filt+=", url:\$url"
  fi
  # tempo-limite por linguagem (máx entre os juízes do POOL EFETIVO — override do problema
  # senão o do contest, senão todos — p/ a versão atual do pacote), salvo se oculto
  pj="$(jq -r --arg id "$PROBLEMID" '(.[$id] // []) | join(" ")' <<<"$PJUDGES" 2>/dev/null)"
  [[ -n "$pj" ]] || pj="$CONTEST_JUDGES"
  # o checksum sai do índice; problema ainda não indexado cai no caminho lento (hashear), que é
  # correto e raro — e é o único caso em que esta rota toca o pacote.
  tl='{}'; [[ "$SHOW_TL" == true ]] && { tl="$(tl_store_served "$PROBLEMID" "$pj" "${TLCKS[$PROBLEMID]:-}" 2>/dev/null)"; [[ -n "$tl" ]] || tl='{}'; }
  # linguagens deste problema: cadeia compartilhada (override do contest -> LANGUAGES ->
  # default do pacote -> todas) — a MESMA que o /submit força (lib/langs.sh).
  plangs="$(effective_problem_langs "$contest" "$PROBLEMID")"; [[ -n "$plangs" ]] || plangs='[]'
  # AUTOR: crédito de quem escreveu o problema. Só DEPOIS do fim (ou p/ admin/juiz): durante
  # a prova o nome do autor é pista (quem conhece o autor deduz o tema/estilo da solução).
  if [[ "$SHOW_AUTHOR" == true ]]; then
    pkg="$(pkg_path "$PROBLEMID")"
    au=""
    [[ -n "$pkg" && -s "$pkg/author" ]] && au="$(grep -v '^[[:space:]]*$' "$pkg/author" 2>/dev/null | paste -sd'|' - | sed 's/|/, /g')"
    [[ -n "$au" ]] && { args+=( --arg au "$au" ); filt+=", author:\$au"; }
  fi
  args+=( --argjson tl "$tl" --argjson plangs "$plangs" ); filt+=", time_limits:\$tl, languages:\$plangs}"

  ITEMS+=( "$(jq -cn --arg id "$PROBLEMID" --arg short "$SHORTNAME" \
      --arg full "$FULLNAME" "${args[@]}" "$filt")" )
done

if (( ${#ITEMS[@]} == 0 )); then
  BODY="$(jq -cn '{success:true, problems:[]}')"
else
  BODY="$(printf '%s\n' "${ITEMS[@]}" | jq -cs '{success:true, problems:.}')"
fi
[[ -n "$BODY" ]] || fail 500 "Falha ao montar a resposta" "build_fail"
# grava por tmp+mv: leitor concorrente nunca vê arquivo pela metade
resp_cache_store "$CF" "$BODY"
# a versão comprimida é gravada DEPOIS da crua: se algo falhar aqui, o pior caso é o nginx
# comprimir como antes — nunca servir .gz de um corpo diferente do .json
printf '%s' "$BODY" | gzip -6 -c > "$CF.gz.tmp.$$" 2>/dev/null && mv -f "$CF.gz.tmp.$$" "$CF.gz" 2>/dev/null || rm -f "$CF.gz.tmp.$$" 2>/dev/null
emit_json 200 OK
printf '%s' "$BODY"
