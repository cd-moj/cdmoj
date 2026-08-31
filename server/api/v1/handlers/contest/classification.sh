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
out="$(jq -c '{stages:[ (.stages // [])[] | select(.status == "published")
  | {id, name:(.name // ""), venue:(.venue // ""), when:(.when // ""),
     teams:((.teams // {}) | with_entries(.value |= {via:(.via // ""), sede:(.sede // "")}))} ]}' \
  "$CF" 2>/dev/null)"
[[ -n "$out" ]] || out='{"stages":[]}'
ok_json_slurp '$f[0]' f "$out"
