# GET /submission/info?contest=<c>&id=<id>   (Bearer: juiz — .judge, .cjudge, admin)
# A PÁGINA DA SUBMISSÃO do juiz (/contest/run/; 09/11/2026 — pedidos do Roberto e do Paulo: link de verdade, id
# encontrável, código e report na tela). Uma submissão, tudo o que o juiz precisa para julgar:
#   {id, round, sub_epoch, minute, problem_id, letter, title, lang, verdict, verdict_canon, score, score_max,
#    score_kind, correct, total_tests, tests[{name,code,time,tl}], host, duration_s, finalized_at, pending,
#    has_source, has_log, review:{status, votes_n, computed_verdict, conflict, votes?} | null,
#    anonymous, login?, team?, univ?}
# `id`: os 32 hex (ou o uuid legado) — ou um PREFIXO de 8 a 31 hex (o que a lista mostra): 0 = 404, mais de uma
# submissão = 409 `ambiguous` com até 10 ids, uma = ela.
# ANONIMATO, a regra do allsubmissions/review: admin e juiz-chefe veem QUEM enviou (login, time, universidade); o
# juiz puro julga sem saber (os campos nem saem daqui — o results JSON também traz o login e é filtrado).
# Pendente (sem results JSON): sai do history (veredicto "Not Answered Yet", sem testes). Rodada ARQUIVADA
# (aquecimento promovido): a mesma busca do log/código (`resolve_submission … rounds`); o minuto é o da rodada.
# Auditado em activity (run-view), como o source-download.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_judge || fail 403 "Só juízes" "judge_required"

q="$(param id)"
[[ "$q" =~ ^[0-9a-f]{8,32}$ || "$q" =~ ^[0-9a-f-]{36}$ ]] || fail 400 "id inválido (8 a 32 caracteres hex)" "id_invalid"
cdir="$CONTESTSDIR/$contest"

set +o noglob; shopt -s nullglob
sid="$q"
if (( ${#q} < 32 )); then
  # PREFIXO: um glob por padrão (nunca um por conta); ids distintos pelo nome do arquivo
  declare -A SEEN=()
  for f in "$cdir"/users/*/results/"$q"*.json "$cdir"/users/*/submissions/"$q"* \
           "$cdir"/rounds/*/users/*/results/"$q"*.json "$cdir"/rounds/*/users/*/submissions/"$q"*; do
    b="${f##*/}"; b="${b%%.*}"
    [[ "$b" =~ ^[0-9a-f]{32}$ ]] && SEEN[$b]=1
  done
  n="${#SEEN[@]}"
  (( n > 0 )) || { shopt -u nullglob; fail 404 "Nenhuma submissão com esse id" "notfound"; }
  if (( n > 1 )); then
    ids="$(printf '%s\n' "${!SEEN[@]}" | sort | head -10 | jq -Rsc 'split("\n") | map(select(length > 0))')"
    shopt -u nullglob
    FAIL_EXTRA="$(jq -cn --argjson i "$ids" --argjson n "$n" '{ids:$i, matches:$n}')" \
      fail 409 "Mais de uma submissão começa com $q — digite mais caracteres" "ambiguous"
  fi
  sid="${!SEEN[*]}"
fi
resolve_submission "$contest" "$sid" rounds
shopt -u nullglob
owner="$SUB_OWNER"
[[ -n "$owner" ]] || fail 404 "Submissão não encontrada" "notfound"

# a base do dono: a do store atual, ou a da rodada arquivada
base="$(users_dir "$contest")"; start_f=""
if [[ -n "${SUB_ROUND:-}" ]]; then base="$cdir/rounds/$SUB_ROUND/users"; start_f="$cdir/rounds/$SUB_ROUND/meta.json"; fi
# linha do history: tempo:prob:lang:veredicto:sub_epoch:id — o VEREDICTO pode ter ':' (e o `¦texto`): ele é o
# meio da linha, $4..$(NF-2)
hl="$(awk -F: -v id="$sid" '$NF == id { v = $4; for (i = 5; i <= NF - 2; i++) v = v ":" $i
      printf "%s\t%s\t%s\t%s\n", $2, $3, $(NF-1), v; exit }' "$base/$owner/history" 2>/dev/null)"
IFS=$'\t' read -r h_prob h_lang h_sub h_verd <<<"$hl"
h_sub="${h_sub//[^0-9]/}"

# minuto da prova (da rodada, se arquivada)
st=0
if [[ -n "$start_f" ]]; then st="$(jq -r '.start // 0' "$start_f" 2>/dev/null)"
else st="$(conf_value "$contest" CONTEST_START)"; fi
st="${st//[^0-9]/}"; st="${st:-0}"

# letra e título do problema (PROBS do conf: 5 campos por problema)
pid="$(jq -r '.problem_id // empty' "${SUB_RESULT:-/dev/null}" 2>/dev/null)"; [[ -n "$pid" ]] || pid="$h_prob"
letter=""; title=""
if [[ -n "$pid" ]]; then
  IFS=$'\t' read -r letter title < <( PROBS=(); source "$cdir/conf" 2>/dev/null
    for ((i = 0; i < ${#PROBS[@]}; i += 5)); do
      canon="${PROBS[i+4]:-}"; [[ "$canon" == *"#"* ]] || canon="${PROBS[i+1]//\//#}"
      [[ "$canon" == "$pid" ]] && { printf '%s\t%s\n' "${PROBS[i+3]:-}" "${PROBS[i+2]:-}"; break; }
    done )
fi

full=false; is_admin_or_chief && full=true
# identidade SÓ p/ admin/chefe (a regra do allsubmissions); o nome do time sai do account.json do dono
team=""; univ=""
if [[ "$full" == true ]]; then
  acct="$base/$owner/account.json"; [[ -f "$acct" ]] || acct="$(users_dir "$contest")/$owner/account.json"
  team="$(jq -r '.team.name // .fullname // ""' "$acct" 2>/dev/null)"
  univ="$(jq -r '.team.univ_short // .team.univ_full // ""' "$acct" 2>/dev/null)"
fi

# revisão manual (MANUAL_VERDICT): o estado; os votos só p/ o chefe (a regra do review/list.sh)
rvf="$cdir/review/$sid.json"; [[ -f "$rvf" ]] || rvf=/dev/null
chief=false; is_admin_or_chief && chief=true

res="${SUB_RESULT:-/dev/null}"; [[ -n "$SUB_RESULT" && -f "$SUB_RESULT" ]] || res=/dev/null
activity_log run-view "c=$contest sid=$sid"
jq -n --slurpfile r <(cat "$res" 2>/dev/null || true) --slurpfile rv <(cat "$rvf" 2>/dev/null || true) \
  --arg id "$sid" --arg round "${SUB_ROUND:-}" --arg sub "${h_sub:-0}" --argjson st "$st" \
  --arg pid "$pid" --arg letter "$letter" --arg title "$title" --arg hlang "$h_lang" --arg hverd "$h_verd" \
  --argjson full "$full" --argjson chief "$chief" --arg login "$owner" --arg team "$team" --arg univ "$univ" \
  --argjson hs "$([[ -n "$SUB_SRC" && -f "$SUB_SRC" ]] && echo true || echo false)" \
  --argjson hl "$([[ -n "$SUB_LOG" && -f "$SUB_LOG" ]] && echo true || echo false)" '
  ($r[0] // {}) as $R | ($rv[0] // null) as $V | ($sub | tonumber? // 0) as $se
  | {success: true, id: $id, round: (if $round == "" then null else $round end),
     sub_epoch: $se, minute: (if $st > 0 and $se >= $st then (($se - $st) / 60 | floor) else null end),
     problem_id: $pid, letter: $letter, title: $title,
     lang: ($R.lang // $hlang),
     verdict: ($R.verdict // ($hverd | sub("¦.*$"; ""))),
     verdict_canon: ($R.verdict_canon // null),
     score: ($R.score // null), score_max: ($R.score_max // null), score_kind: ($R.score_kind // null),
     correct: ($R.correct // null), total_tests: ($R.total_tests // null),
     tests: [ ($R.tests // [])[] | {name, code, time, tl} ],
     host: ($R.host // null), duration_s: ($R.duration_s // null), finalized_at: ($R.finalized_at // null),
     pending: ($R == {}),
     has_source: $hs, has_log: $hl,
     review: (if $V == null then null else
       {status: ($V.status // "open"), votes_n: (($V.votes // []) | length), computed_verdict: ($V.computed_verdict // null),
        conflict: ($V.conflict // false)} + (if $chief then {votes: ($V.votes // [])} else {} end) end),
     anonymous: ($full | not)}
  + (if $full then {login: $login, team: $team, univ: $univ} else {} end)' \
  | { r="$(cat)"; [[ -n "$r" ]] || fail 500 "Falha ao montar a submissão" "build_fail"; emit_json 200 OK; printf '%s\n' "$r"; }
