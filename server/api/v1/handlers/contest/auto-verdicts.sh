# GET/POST /contest/auto-verdicts?contest=<id>
# O QUE VAI PARA REVISÃO no veredicto manual (contests/<c>/auto-verdicts.json; regra e formatos em
# lib/review-rules.sh). v2 = OPT-OUT: com MANUAL_VERDICT=1 tudo sai automático, menos a grade
# problema × classe marcada p/ revisão e as exceções por linguagem; erro do juiz sempre vai p/ revisão.
# O arquivo v1 (opt-in, o formato anterior) vale como sempre até alguém salvar pela tela nova.
#   GET  (Bearer, judge) -> {version:2, state:missing|invalid|v1|v2, rules:{review,langs} (v1 convertido),
#                            items:[{id,letter,title}], verdicts:[6 classes], langs:[do contest],
#                            manual_verdict, releasable, problems:[cid] (legado), matrix (legado: o v1 cru)}
#   POST (admin OU juiz-chefe):
#     {rules:{review:{cid:[classe…]}, langs:[{lang,problem,verdicts,to}]}} -> grava v2 -> {saved, rules, releasable}
#     {action:"release"} -> libera, com o veredicto COMPUTADO, os itens da fila de revisão sem voto e sem
#                          conflito que as regras atuais mandam automáticos -> {released, left}
#     {matrix:{…}} (cliente antigo) -> grava v1 como antes -> {saved, matrix}
# `releasable` = quantos itens retidos (sem voto/conflito) as regras atuais soltariam — a tela oferece
# o botão "liberar" em vez de liberar sozinha (decisão do Ribas, 25/09/2026).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
source "$_LIBDIR/review-rules.sh"
f="$CONTESTSDIR/$contest/auto-verdicts.json"

# problemas do contest (subshell: não vaza PROBS p/ o handler): cid \t letra \t título
items_tsv="$( ( PROBS=(); source "$CONTESTSDIR/$contest/conf" 2>/dev/null
  for ((i=0; i<${#PROBS[@]}; i+=5)); do
    c="${PROBS[i+4]:-}"; [[ "$c" == *"#"* ]] || c="${PROBS[i+1]//\//#}"
    [[ -n "$c" ]] && printf '%s\t%s\t%s\n' "$c" "${PROBS[i+3]:-}" "${PROBS[i+2]:-}"
  done ) )"
# na ORDEM da prova (letras), sem repetir id (unique_by reordenaria)
items_json="$(jq -Rsc 'split("\n") | map(select(length > 0) | split("\t") | {id:.[0], letter:(.[1] // ""), title:(.[2] // "")})
                       | reduce .[] as $x ([]; if any(.[]; .id == $x.id) then . else . + [$x] end)' <<<"$items_tsv")"
[[ -n "$items_json" ]] || items_json='[]'
cids_json="$(jq -c 'map(.id)' <<<"$items_json")"

# regras atuais na visão v2 (arquivo ausente/ilegível = vazio; o `state` conta qual dos dois)
state="$(rr_state "$contest")"
rules_view(){ # <arquivo-de-regras> -> {review, langs}
  if [[ -s "$1" ]] && jq -e 'type == "object"' "$1" >/dev/null 2>&1; then
    jq -c --argjson cids "$cids_json" "$RR_JQ_DEFS rr_view(\$cids)" "$1" 2>/dev/null || echo '{"review":{},"langs":[]}'
  else echo '{"review":{},"langs":[]}'; fi
}
# releasable contra um arquivo de regras (ausente = v2 vazio = tudo automático)
count_releasable(){ # <arquivo-de-regras|""> -> n
  local rf="$1" tmp="" n
  if [[ -z "$rf" || ! -e "$rf" ]]; then tmp="$(mktemp)"; echo '{"version":2}' > "$tmp"; rf="$tmp"; fi
  n="$(rr_releasable "$contest" "$rf" | grep -c .)"; [[ -n "$tmp" ]] && rm -f "$tmp"
  n="${n//[^0-9]/}"; printf '%s' "${n:-0}"
}

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  is_judge || fail 403 "Judge only" "judge_required"
  source "$_LIBDIR/langs.sh"
  mv=false; [[ "$(conf_value "$contest" MANUAL_VERDICT)" == 1 ]] && mv=true
  langs="$( ( LANGUAGES=""; source "$CONTESTSDIR/$contest/conf" 2>/dev/null
              for l in ${LANGUAGES:-$PLATFORM_LANGS}; do lang_canon_ext "$l"; echo; done ) | grep -v '^$' | sort -u | jq -R . | jq -cs .)"
  [[ -n "$langs" ]] || langs='[]'
  rel=0; [[ "$state" != invalid ]] && rel="$(count_releasable "$f")"
  legacy='{}'; [[ "$state" == v1 ]] && legacy="$(jq -c . "$f")"
  ok_json '{version:2, state:$st, rules:$r, items:$it, problems:$cids, verdicts:($cls | split("|")),
            langs:$langs, manual_verdict:$mv, releasable:$rel, matrix:$legacy}' \
    --arg st "$state" --argjson r "$(rules_view "$f")" --argjson it "$items_json" --argjson cids "$cids_json" \
    --arg cls "$RR_CLASSES" --argjson langs "$langs" --argjson mv "$mv" --argjson rel "$rel" --argjson legacy "$legacy"
  exit 0
fi

require_method POST
is_admin_or_chief || fail 403 "Apenas admin ou juiz-chefe" "config_forbidden"
body="$(read_body)"
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
mkdir -p "$CONTESTSDIR/$contest"

# --- liberar o que as regras atuais soltam (sem voto e sem conflito) -------------------------------
if [[ "$(jq -r '.action // ""' <<<"$body")" == release ]]; then
  [[ "$state" == invalid ]] && fail 409 "O arquivo de regras está ilegível — salve a tabela de novo antes de liberar" "rules_invalid"
  source "$_LIBDIR/review.sh"
  tmp=""; rf="$f"; [[ -e "$rf" ]] || { tmp="$(mktemp)"; echo '{"version":2}' > "$tmp"; rf="$tmp"; }
  dir="$(rv_dir "$contest")"; n=0
  exec 9>"$(rv_lock "$contest")"; flock -w 10 9 || fail 409 "A fila de revisão está ocupada — tente de novo" "review_busy"
  # recalcula SOB o lock: um voto que chegou entre a tela e o clique tira o item da lista
  while IFS= read -r id; do
    valid_id "$id" || continue
    it="$dir/$id.json"; [[ -f "$it" ]] || continue
    IFS=$'\x01' read -r login prob verdict < <(jq -j '[(.login // ""), (.problem_id // ""), (.computed_verdict // "")] | join("\u0001")' "$it" 2>/dev/null)
    [[ -n "$verdict" ]] || continue
    rv_emit_setverdict "$contest" "$id" "$login" "$prob" "$verdict"
    jq -c --arg v "$verdict" --arg by "$SESSION_LOGIN" --argjson at "$EPOCHSECONDS" \
      '.status="released" | .released_verdict=$v | .released_by=$by | .released_at=$at' "$it" > "$it.tmp" 2>/dev/null \
      && mv -f "$it.tmp" "$it"
    n=$((n+1))
  done < <(rr_releasable "$contest" "$rf")
  exec 9>&-
  [[ -n "$tmp" ]] && rm -f "$tmp"
  # o que segue aberto na fila (com voto, em conflito, ou que as regras mandam revisar)
  left="$(find "$dir" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null \
          | xargs -0 -r jq -r 'select(type == "object" and (.status // "open") != "released") | .id // "x"' 2>/dev/null | grep -c .)"
  left="${left//[^0-9]/}"; left="${left:-0}"
  audit_log_to "$contest" review-auto-release "liberadas=$n restantes=$left by=$SESSION_LOGIN"
  ok_json '{released:$n, left:$l}' --argjson n "$n" --argjson l "$left"
  exit 0
fi

# --- cliente antigo: matriz v1 (opt-in), como antes ------------------------------------------------
if jq -e 'has("matrix") and (has("rules") | not)' >/dev/null 2>&1 <<<"$body"; then
  jq -e '(.matrix // {}) | type=="object"' >/dev/null 2>&1 <<<"$body" || fail 422 "matrix inválida" "matrix_invalid"
  clean="$(jq -c --argjson cids "$cids_json" '
    (.matrix // {}) | to_entries
    | map(select(.key as $k | $cids | index($k)))
    | map({ key:.key, value:(
        (.value // {}) | to_entries
        | map(select(.key | test("^[a-z0-9_+.*-]+$")))
        | map({ key:.key, value:((.value // []) | map(tostring | select(test("^[^:\n\t\r]{1,60}$"))) | unique) })
        | map(select((.value|length) > 0)) | from_entries) })
    | map(select((.value | length) > 0)) | from_entries' <<<"$body")"
  [[ -n "$clean" ]] || clean='{}'
  printf '%s' "$clean" > "$f.tmp" && mv -f "$f.tmp" "$f"
  audit_log_to "$contest" auto-verdicts-set "v1 problemas=$(jq 'keys|length' <<<"$clean")"
  ok_json '{saved:true, matrix:$m}' --argjson m "$clean"
  exit 0
fi

# --- v2: a grade + as exceções --------------------------------------------------------------------
jq -e '(.rules // null) | type == "object"' >/dev/null 2>&1 <<<"$body" || fail 422 "rules inválido" "rules_invalid"
# saneia: só problemas do contest, só as 6 classes, linguagem canônica, to ∈ {review, auto}; o
# `rr_view` já faz tudo isso (é a MESMA projeção que a tela recebe no GET)
clean="$(jq -c --argjson cids "$cids_json" "$RR_JQ_DEFS
  (.rules | {version:2, review:(.review // {}), langs:(.langs // [])}) | rr_view(\$cids)
  | {version:2, review:(.review | with_entries(select((.value | length) > 0))), langs}" <<<"$body" 2>/dev/null)"
jq -e '.version == 2' >/dev/null 2>&1 <<<"$clean" || fail 422 "rules inválido" "rules_invalid"
# a linguagem da exceção tem de ser um id seguro (vai p/ comparação e p/ a tela)
jq -e '[.langs[].lang | test("^[a-z0-9_+.-]{1,20}$")] | all' >/dev/null 2>&1 <<<"$clean" || fail 422 "linguagem inválida" "lang_invalid"
clean="$(jq -c --arg by "$SESSION_LOGIN" --argjson at "$EPOCHSECONDS" '. + {updated_by:$by, updated_at:$at}' <<<"$clean")"
printf '%s' "$clean" > "$f.tmp" && mv -f "$f.tmp" "$f" || fail 500 "Falha ao gravar" "write_failed"
audit_log_to "$contest" auto-verdicts-set "v2 revisao=$(jq '[.review[] | length] | add // 0' <<<"$clean") excecoes=$(jq '.langs | length' <<<"$clean")"
ok_json '{saved:true, rules:$r, releasable:$rel}' \
  --argjson r "$(jq -c '{review, langs}' <<<"$clean")" --argjson rel "$(count_releasable "$f")"
