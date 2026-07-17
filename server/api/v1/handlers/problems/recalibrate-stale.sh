# POST /problems/recalibrate-stale   (Bearer)   body: {} | {ids:[...]}
# RECALIBRA EM LOTE tudo que "precisa recalibrar" no painel do login (calibrado E checksum do
# pacote divergente do calibrado — mesma conta do /problems/status). Com `ids`, restringe ao
# subconjunto (a web manda o que está vendo; ids são INTERSECTADOS com o conjunto autorizado —
# a fronteira é owners_visible+narrow, nunca o input). Cada enfileiramento usa cal_request, que
# é IDEMPOTENTE e serializado por-problema no claim (lote grande é seguro por construção —
# hardening do incidente 2026-07-15). Resposta: {count, queued:[{id,reqid}]}.
require_method POST
require_auth
source "$_DIR/../../judge-gw/sched-lib.sh"
source "$_DIR/lib/problems.sh"; source "$_DIR/lib/tl-store.sh"

body="$(read_body)"; [[ -n "$body" ]] || body='{}'
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
want="$(jq -c '[.ids[]? | select(type=="string")]' <<<"$body" 2>/dev/null)"; [[ -n "$want" ]] || want='[]'

# fronteira de acesso = a MESMA do painel (owners_visible -> dono/colaborador/membro-da-org)
vis="$(owners_visible)" || fail 503 "Índice de problemas indisponível — tente de novo em instantes" "index_unavailable"
vis="$(jq -c --arg me "$SESSION_LOGIN" --argjson orgs "$(my_orgs_json)" \
   '.problems |= map(select(.owner==$me or ((.collaborators // [])|index($me)|type=="number")
       or (((.repo // (.id|split("#")[0])) as $r | $orgs|index($r))|type=="number")))' <<<"$vis" 2>/dev/null)"
[[ -n "$vis" ]] || fail 503 "Falha ao filtrar o índice" "index_unavailable"

stale="$(mktemp)"
trap 'rm -f "$stale"' EXIT

# checksums calibrados: o SUMÁRIO mantido por evento (mesma fonte do status.sh; interno de run/)
tl_summary_ensure
tlmap="$TL_SUMMARY"

# stale = calibrado E índice tem tl_checksum E difere do calibrado; com `ids`, intersecta
jq -r --slurpfile tm "$tlmap" --argjson want "$want" '
  ($tm[0] // {}) as $t
  | .problems[]
  | select((.tl_checksum // "") != "")
  | . as $p | ($t[$p.id] // {}) as $c
  | select(($c.calibrated // false) and (($c.checksum // "") != "") and ($c.checksum != $p.tl_checksum))
  | select(($want|length)==0 or (($want|index($p.id))|type=="number"))
  | .id' <<<"$vis" 2>/dev/null > "$stale"

queued='[]'
while IFS= read -r pid; do
  [[ -n "$pid" ]] || continue
  org="${pid%%#*}"
  reqid="$(cal_request "$org" "$pid" "$SESSION_LOGIN")"
  [[ -n "$reqid" ]] && queued="$(jq -c --arg i "$pid" --arg r "$reqid" '. + [{id:$i, reqid:$r}]' <<<"$queued")"
done < "$stale"

n="$(jq 'length' <<<"$queued")"
audit_log "recalibrate-stale" "count=$n by=$SESSION_LOGIN"
ok_json '{action:"recalibrate-stale", count:$n, queued:$q}' --argjson n "$n" --argjson q "$queued"
