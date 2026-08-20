# GET /contest/problems?contest=<id>   (Bearer)
# Lista de problemas da prova a partir de PROBS (5-tuplas) + enunciados/<key>.{html,pdf}.
# [{short_name, full_name, problem_id, statement_html_b64, statement_pdf_b64, time_limits, show}]
# Codifica os enunciados em base64 inline (SEM escrever no dir do contest).
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
# os dois json de override, o diretório de enunciados e um carimbo explícito que o
# /contest/admin/problems toca. O teto de idade é a rede de segurança para as entradas que NÃO
# dependem deste contest — TL novo reportado por um juiz e o `languages` do pacote no treino.
CVAR=noauthor; [[ "$SHOW_AUTHOR" == true ]] && CVAR=author
CDIR="$CONTESTSDIR/$contest/var"; CF="$CDIR/problems-cache.$CVAR.json"
: "${PROBLEMS_CACHE_TTL:=60}"
_cache_fresh(){
  [[ -s "$CF" ]] || return 1
  local f
  for f in "$CONTESTSDIR/$contest/conf" "$CONTESTSDIR/$contest/problem-langs.json" \
           "$CONTESTSDIR/$contest/problem-judges.json" "$CONTESTSDIR/$contest/enunciados" \
           "$CDIR/.problems-dirty"; do
    [[ -e "$f" && "$f" -nt "$CF" ]] && return 1
  done
  [[ -n "$(find "$CF" -newermt "-$PROBLEMS_CACHE_TTL seconds" 2>/dev/null)" ]] || return 1
  return 0
}
# O payload é grande (enunciados embutidos: MB) e idêntico p/ todos. Se o nginx comprimir a
# cada resposta, 2000 times no segundo da abertura pagam 2000 compressões do MESMO conteúdo —
# medido: derruba a rota a ~137 req/s. Como o corpo está em cache, guardamos também a versão
# comprimida e a servimos direto; o nginx não recomprime resposta que já vem com
# Content-Encoding. `Vary` é obrigatório: sem ele um intermediário serviria bytes comprimidos
# a um cliente que não os aceita.
if _cache_fresh; then
  if [[ -s "$CF.gz" && "${HTTP_ACCEPT_ENCODING:-}" == *gzip* ]]; then
    printf 'Status: 200 OK\r\nContent-Type: application/json; charset=utf-8\r\n'
    printf 'Content-Encoding: gzip\r\nVary: Accept-Encoding\r\n\r\n'
    cat "$CF.gz"
  else
    emit_json 200 OK; printf '%s' "$(<"$CF")"
  fi
  exit 0
fi

# linguagens permitidas: cadeia em lib/langs.sh (FONTE ÚNICA — o /submit APLICA a mesma
# lista que esta listagem oferece; front filtra o editor e a tabela de TL por ela).
source "$_LIBDIR/langs.sh"
# pool de juízes: override por problema (problem-judges.json) -> pool do contest
# (CONTEST_JUDGES) -> "" (= todos). O TL servido é o MÁX só entre os hosts do pool efetivo.
PJUDGES='{}'; [[ -f "$CONTESTSDIR/$contest/problem-judges.json" ]] && PJUDGES="$(jq -c . "$CONTESTSDIR/$contest/problem-judges.json" 2>/dev/null)"; [[ -n "$PJUDGES" ]] || PJUDGES='{}'

set +o noglob
ENUN="$CONTESTSDIR/$contest/enunciados"

declare -a ITEMS
# enunciados grandes (base64, às vezes com imagem embutida) vão p/ o jq via --rawfile, nunca
# como argumento de linha de comando — senão estoura ARG_MAX ("jq: Argument list too long").
TMPD="$(mktemp -d 2>/dev/null)" || TMPD="${TMPDIR:-/tmp}/cprob.$$"; mkdir -p "$TMPD"
trap 'rm -rf "$TMPD"' EXIT
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
  for T in html pdf; do
    src="$ENUN/$STATEMENT.$T"
    if [[ -f "$src" ]]; then
      base64 -w0 < "$src" 2>/dev/null > "$TMPD/$T"
      args+=( --rawfile "$T" "$TMPD/$T" ); filt+=", statement_${T}_b64:\$$T"
    elif [[ "$T" == html ]]; then
      # fallback: enunciado gerado DEPOIS (problema privado validado -> jsons-private).
      # Aparece automaticamente assim que o juiz indexa; cacheia no contest na 1ª vez.
      jf="$CONTESTSDIR/treino/var/jsons/$STATEMENT.json"; [[ -f "$jf" ]] || jf="$CONTESTSDIR/treino/var/jsons-private/$STATEMENT.json"
      if [[ -f "$jf" ]] && jq -e '(.statement_html_b64 // "") != ""' "$jf" >/dev/null 2>&1; then
        jq -r '.statement_html_b64 // ""' "$jf" 2>/dev/null > "$TMPD/html"
        args+=( --rawfile html "$TMPD/html" ); filt+=", statement_html_b64:\$html"
        ( mkdir -p "$ENUN"; base64 -d < "$TMPD/html" > "$ENUN/$STATEMENT.html" ) 2>/dev/null || true
      else
        filt+=", statement_html_b64:null"
      fi
    else
      filt+=", statement_${T}_b64:null"
    fi
  done
  # enunciado pode ser uma URL externa
  if [[ "$STATEMENT" == *http* ]]; then
    args+=( --arg url "$STATEMENT" ); filt+=", url:\$url"
  fi
  # tempo-limite por linguagem (máx entre os juízes do POOL EFETIVO — override do problema
  # senão o do contest, senão todos — p/ a versão atual do pacote), salvo se oculto
  pj="$(jq -r --arg id "$PROBLEMID" '(.[$id] // []) | join(" ")' <<<"$PJUDGES" 2>/dev/null)"
  [[ -n "$pj" ]] || pj="$CONTEST_JUDGES"
  tl='{}'; [[ "$SHOW_TL" == true ]] && { tl="$(tl_store_served "$PROBLEMID" "$pj" 2>/dev/null)"; [[ -n "$tl" ]] || tl='{}'; }
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
mkdir -p "$CDIR" 2>/dev/null
printf '%s' "$BODY" > "$CF.tmp.$$" 2>/dev/null && mv -f "$CF.tmp.$$" "$CF" 2>/dev/null || rm -f "$CF.tmp.$$" 2>/dev/null
# a versão comprimida é gravada DEPOIS da crua: se algo falhar aqui, o pior caso é o nginx
# comprimir como antes — nunca servir .gz de um corpo diferente do .json
printf '%s' "$BODY" | gzip -6 -c > "$CF.gz.tmp.$$" 2>/dev/null && mv -f "$CF.gz.tmp.$$" "$CF.gz" 2>/dev/null || rm -f "$CF.gz.tmp.$$" 2>/dev/null
emit_json 200 OK
printf '%s' "$BODY"
