# POST /problems/set-public   (Bearer)   body: {id, public:bool}
# Marca/desmarca o problema como público (.moj-meta.json). Público => VALIDA (portão + índice, no
# servidor; só entra no treino se passar) E CALIBRA (juiz roda as good, reporta TL). Privado => sai do
# treino na HORA. Atualiza o espelho p/ o editor refletir o estado certo. AÇÃO EXPLÍCITA (nunca no save).
require_method POST
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"; source "$MOJTOOLS_DIR/git-broker.sh"
source "$_DIR/../../judge-gw/sched-lib.sh"; source "$_DIR/lib/tl-store.sh"   # cal_request + index_problem_bg

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
pub="$(jq -r 'if .public==true then "true" elif .public==false then "false" else "" end' <<<"$body")"
[[ -n "$pub" ]] || fail 400 "Missing public (bool)" "public_missing"
repo="${id%%#*}"; prob="${id##*#}"
owner="$(problem_owner "$id")"; [[ -n "$owner" ]] || fail 404 "Problema não está no Gitea" "not_gitea"
gitea_can_write "$owner" "$repo" "$SESSION_LOGIN" || fail 403 "Sem permissão" "forbidden"

tmp="$(git_broker_open "$SESSION_LOGIN" "$owner" "$repo")" || fail 502 "Falha ao abrir o repositório" "git_open"
trap 'rm -rf "$tmp"' EXIT
wt="$tmp/wt"; [[ -d "$wt/$prob" ]] || fail 404 "Problema não existe" "prob_missing"
write_meta "$wt/$prob" "$owner" "$repo" "$pub" "" ""
# tornar público: tira o PUBLIC=no legado do conf (senão o gerador do treino ignora)
if [[ "$pub" == "true" && -f "$wt/$prob/conf" ]]; then
  sed -i -E '/^[[:space:]]*PUBLIC[[:space:]]*=[[:space:]]*no[[:space:]]*$/d' "$wt/$prob/conf" 2>/dev/null || true
fi
git_broker_commit_push "$SESSION_LOGIN" "$owner" "$repo" "$wt" "set public=$pub ($prob)" >/dev/null \
  || fail 502 "Falha ao enviar (push)" "git_push"

authored_patch "$id" '.public=($p=="true")' --arg p "$pub"
ensure_repo_materialized "$repo" "$SESSION_LOGIN"   # espelho em dia -> o editor lê o public CERTO na hora
reqid=""
if [[ "$pub" == "true" ]]; then
  # TORNAR PÚBLICO = fluxo completo, sem pular etapas: VALIDA (portão + índice, no servidor) E pede
  # CALIBRAÇÃO a um juiz (garante time-limit p/ os alunos). Antes o idx_request legado era no-op (só
  # empilhava marcador kind=index) -> problema saía público SEM validar (bug do moj-cli publish).
  index_problem_bg "$id" 1
  reqid="$(cal_request "$repo" "$id" "$SESSION_LOGIN")"
else
  # DESPUBLICAR: sai do treino livre NA HORA (índice servível + cache de 5min), não fica vazando
  rm -f "$CONTESTSDIR/treino/var/jsons/$id.json" "$CONTESTSDIR/treino/var/problems.json" 2>/dev/null
fi
audit_log "set-public" "id=$id public=$pub reqid=$reqid"
ok_json '{action:"set-public", id:$id, public:($p=="true"), reqid:$r}' \
  --arg id "$id" --arg p "$pub" --arg r "$reqid"
