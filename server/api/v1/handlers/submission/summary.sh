# GET /submission/summary?contest=<id>&ids=<csv>   (Bearer)
#   -> {"<id>":{verdict,verdict_canon,score,score_max,score_kind,correct,total,groups,heur_score?,heur_adjusted?}}
# Resumo ESTRUTURADO por submissão (de results/<id>.json), p/ a linha de detalhe sob o
# veredicto canônico (ex.: "Passou em 4/5 testes (80%)", "30/100 pontos · Grupo 1: 30/30…").
# REDIGIDO pelo modo do contest (lib/verdict.sh, verdict_detail_level): full (treino) = tudo;
# score (obi/heurístico/outro) = canônico + score/grupos/heur SEM correct/total; none (icpc) =
# só o canônico — anti-leak, nem o dono recebe score. Juiz/admin: sempre full com verdict cru.
# Mesmo gate do log: o dono vê o seu (salvo SHOWLOG=0); ids de terceiros são apenas OMITIDOS
# (não 403 — pede-se em lote). Fallbacks p/ results antigos: verdict_canon derivado da string;
# groups derivado da cauda legada "Pontos | 30 | 0 |" (sem max).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

idsraw="$(param ids)"
[[ -n "$idsraw" ]] || fail 400 "Missing ids" "ids_missing"

SHOWCODE=0; SHOWLOG=""
load_contest_conf "$contest"
isjudge=0; is_judge && isjudge=1
# SHOWLOG=0 esconde o detalhe do julgamento do não-juiz; o resumo (nº de testes) segue essa trava.
hidden=0; [[ "$isjudge" == 0 && "$SHOWLOG" == 0 ]] && hidden=1
# nível de detalhe pelo modo do contest (lib/verdict.sh); juiz/admin veem tudo
lvl="$(verdict_detail_level "$(contest_score_mode "$contest")")"
[[ "$isjudge" == 1 ]] && lvl=full

cdir="$CONTESTSDIR/$contest"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
set +o noglob; shopt -s nullglob

# até 1000 ids; cada um casa md5(32) ou uuid(36). Dono vem da fonte arquivada (submissions/*<id>*).
n=0
IFS=',' read -ra IDS <<< "$idsraw"
for sid in "${IDS[@]}"; do
  sid="${sid//[[:space:]]/}"
  [[ "$sid" =~ ^[0-9a-f]{32}$ || "$sid" =~ ^[0-9a-f-]{36}$ ]] || continue
  (( n++ >= 1000 )) && break
  resolve_submission "$contest" "$sid"   # store-v2 ou legado
  rf="$SUB_RESULT"
  [[ -n "$rf" && -f "$rf" ]] || continue
  if [[ "$isjudge" == 0 ]]; then
    (( hidden )) && continue
    [[ "$SUB_OWNER" == "$SESSION_LOGIN" || "${SHOWCODE:-0}" == 1 ]] || continue
  fi
  # extrai os campos do resumo redigidos por $lvl; tolera ausência (submissões antigas) -> null.
  # $vc = canônico (fallback: derivado da string); $g = grupos (fallback: cauda "Pontos | … |");
  # $heur = Score/Score Ajustado da string (MESMAS regexes do metrics_recompute em lib/users.sh).
  jq -c --arg id "$sid" --arg lvl "$lvl" "$VERDICT_CANON_JQ"'
    (.verdict // null) as $vraw
    | (.verdict_canon // ($vraw | vcanon)) as $vc
    | (.groups // (
        if (($vraw // "") | test("Pontos \\|"))
        then ($vraw | capture("Pontos \\|(?<t>( *-?[0-9]+ *\\|)*)").t
              | split("|") | map(gsub("[[:space:]]"; "") | select(length > 0) | tonumber)
              | map({earned:(if . < 0 then null else . end), max:null}))
        else null end)) as $g
    | (if $vraw != null and ($vraw | test("Score[ \t]+-?[0-9]+")) then
         {heur_score: ($vraw | capture("Score[ \t]+(?<n>-?[0-9]+)").n | tonumber)}
         + (if ($vraw | test("Score Ajustado[ \t]+-?[0-9]+(\\.[0-9]+)?")) then
              {heur_adjusted: ($vraw | capture("Score Ajustado[ \t]+(?<n>-?[0-9]+(\\.[0-9]+)?)").n | tonumber)}
            else {} end)
       else {} end) as $heur
    | if $lvl == "full" then
        { id:$id, verdict:$vraw, verdict_canon:$vc,
          score:(.score // null), score_max:(.score_max // null), score_kind:(.score_kind // null),
          correct:(.correct // null), total:(.total_tests // .total // null), groups:$g } + $heur
      elif $lvl == "score" then
        { id:$id, verdict:$vc, verdict_canon:$vc,
          score:(.score // null), score_max:(.score_max // null), score_kind:(.score_kind // null),
          correct:null, total:null, groups:$g } + $heur
      else
        { id:$id, verdict:$vc, verdict_canon:$vc,
          score:null, score_max:null, score_kind:null, correct:null, total:null, groups:null }
      end' "$rf" 2>/dev/null >> "$tmp"
done
shopt -u nullglob

emit_json 200 OK
jq -s 'map({key:.id, value:(del(.id))}) | from_entries' "$tmp" 2>/dev/null || printf '{}\n'
