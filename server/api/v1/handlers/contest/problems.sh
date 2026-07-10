# GET /contest/problems?contest=<id>   (Bearer)
# Lista de problemas da prova a partir de PROBS (5-tuplas) + enunciados/<key>.{html,pdf}.
# [{short_name, full_name, problem_id, statement_html_b64, statement_pdf_b64, time_limits, show}]
# Espelha old/cdmoj/server/scripts/create-problemsjson.sh (base64 dos enunciados),
# mas SEM escrever no dir do contest (codifica inline).
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
# linguagens permitidas: override por problema (problem-langs.json) -> whitelist do contest
# (LANGUAGES) -> [] (= todas). O front filtra o editor e a tabela de TL por essa lista.
PLANGS='{}'; [[ -f "$CONTESTSDIR/$contest/problem-langs.json" ]] && PLANGS="$(jq -c . "$CONTESTSDIR/$contest/problem-langs.json" 2>/dev/null)"; [[ -n "$PLANGS" ]] || PLANGS='{}'
CLANGS='[]'; [[ -n "$LANGUAGES" ]] && CLANGS="$(printf '%s\n' $LANGUAGES | grep -v '^$' | jq -R . | jq -cs .)"
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
  # linguagens deste problema (cadeia mais-específico-vence): override por-problema-no-contest
  # (problem-langs.json) -> whitelist do contest (LANGUAGES) -> default do PRÓPRIO pacote
  # (jsons/<id>.json .languages, novo último elo — pega o "só-pddl" de um problema sem que o
  # contest precise configurar nada) -> [] (= todas). Não-regressivo: só o 3º elo é novo, e ele
  # só entra quando NEM override NEM whitelist existem (antes daria [] direto).
  plangs="$(jq -c --arg id "$PROBLEMID" '.[$id] // empty' <<<"$PLANGS" 2>/dev/null)"
  if [[ -z "$plangs" || "$plangs" == null ]]; then
    if [[ -n "$CLANGS" && "$CLANGS" != "[]" ]]; then
      plangs="$CLANGS"
    else
      pjf="$CONTESTSDIR/treino/var/jsons/$PROBLEMID.json"; [[ -f "$pjf" ]] || pjf="$CONTESTSDIR/treino/var/jsons-private/$PROBLEMID.json"
      plangs="$(jq -c '.languages // []' "$pjf" 2>/dev/null)"; [[ -n "$plangs" ]] || plangs='[]'
    fi
  fi
  args+=( --argjson tl "$tl" --argjson plangs "$plangs" ); filt+=", time_limits:\$tl, languages:\$plangs}"

  ITEMS+=( "$(jq -cn --arg id "$PROBLEMID" --arg short "$SHORTNAME" \
      --arg full "$FULLNAME" "${args[@]}" "$filt")" )
done

emit_json 200 OK
if (( ${#ITEMS[@]} == 0 )); then
  jq -cn '{success:true, problems:[]}'
else
  printf '%s\n' "${ITEMS[@]}" | jq -cs '{success:true, problems:.}'
fi
