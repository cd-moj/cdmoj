# GET /contest/classification?contest=<id> — classificação p/ próximas fases, SÓ o publicado.
# Mesmo gate do placar (contest secreto exige sessão); competidor consome p/ o chip ↑BR.
# resp: {stages:[{id,name,venue,when,teams:{login:{via,sede}}}]} — vazio se nada publicado;
# nunca expõe config/notas/quem aplicou (isso é do admin/classify).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_not_secret_or_auth "$contest"
CF="$CONTESTSDIR/$contest/classification.json"
if [[ ! -s "$CF" ]]; then ok_json '{stages:[]}'; exit 0; fi
# ADMIN do contest enxerga também os RASCUNHOS (marcados draft:true — o placar rende o
# chip esmaecido "(rascunho)"): é a pré-visualização de como fica antes do Publicar.
# Sessão OPCIONAL, molde do /contest/score — anônimo/competidor segue só com published.
adm=false
load_session 2>/dev/null && [[ "$SESSION_CONTEST" == "$contest" ]] && is_admin && adm=true
out="$(jq -c --argjson adm "$adm" '{stages:[ (.stages // [])[]
  | select(.status == "published" or $adm)
  | {id, name:(.name // ""), venue:(.venue // ""), when:(.when // ""),
     teams:((.teams // {}) | with_entries(.value |= {via:(.via // ""), sede:(.sede // "")}))}
    + (if .status != "published" then {draft:true} else {} end) ]}' \
  "$CF" 2>/dev/null)"
[[ -n "$out" ]] || out='{"stages":[]}'
ok_json_slurp '$f[0]' f "$out"
