# GET /submission/summary?contest=<id>&ids=<csv>   (Bearer) -> {"<id>":{verdict,verdict_canon,score,score_max,score_kind,correct,total}}
# Resumo ESTRUTURADO por submissão (de results/<id>.json), p/ montar o "resumo" do treino
# (ex.: "Passou em 4/5 testes (80%)"). Mesmo gate do log: juiz/admin veem tudo; o dono vê o seu
# (salvo SHOWLOG=0); ids de terceiros são apenas OMITIDOS (não 403 — pede-se em lote).
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
  # extrai só os campos do resumo; tolera ausência (submissões antigas) -> null
  jq -c --arg id "$sid" '{ id:$id,
       verdict:(.verdict // null), verdict_canon:(.verdict_canon // null),
       score:(.score // null), score_max:(.score_max // null), score_kind:(.score_kind // null),
       correct:(.correct // null), total:(.total_tests // .total // null) }' "$rf" 2>/dev/null >> "$tmp"
done
shopt -u nullglob

emit_json 200 OK
jq -s 'map({key:.id, value:(del(.id))}) | from_entries' "$tmp" 2>/dev/null || printf '{}\n'
