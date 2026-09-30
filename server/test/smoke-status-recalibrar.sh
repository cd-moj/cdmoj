#!/bin/bash
# smoke-status-recalibrar.sh — o card "precisa recalibrar" do Painel, pela ROTA (GET /problems/status).
#
# A regra: checksum calibrado (run/tl) ≠ tl_checksum do índice de donos ⇒ precisa recalibrar — SALVO
# quando a calibração é mais nova que o índice (o índice se refaz em background; o checksum de lá é
# sabidamente velho). A data do índice é o `generated_at` do problem-owners.json, e o owners_merged o
# perdia na mescla: $idx_at = 0, toda calibração "mais nova", o card zerado para sempre (PR #41; morto
# desde 28/07). O smoke-owners-index.sh prende o campo na lib; este prende a CONTA na rota.
#   PATH=<dir-do-jq-1.7>:$PATH bash server/test/smoke-status-recalibrar.sh
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS"' EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$PROBS" TL_STORE_DIR="$RUN/tl" \
       CALIB_DIR="$RUN/calib" MOJ_JOBS_SYNC=1
mkdir -p "$RUN/tl" "$RUN/calib" "$FIX/treino/var"
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${ROW:-}" | head -c 400; echo; ((fail++)); fi; }
echo "jq: $(jq --version)"

NOW="$EPOCHSECONDS"; T="$FIX/treino"
printf 'CONTEST_ID=treino\nCONTEST_END=%s\n' "$((NOW+86400))" > "$T/conf"
echo '{"col":{"members":["autor"],"admins":[],"public_allowed":true,"title":"Col"}}' > "$T/var/orgs.json"
fx_user "$T" autor s "Autor"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino autor Autor "$NOW" > "$SESS/aut"
for p in pa pb; do mkdir -p "$PROBS/col/$p"; printf '{"owner":"autor","public":false,"display_title":"%s"}\n' "$p" > "$PROBS/col/$p/.moj-meta.json"; done
_LIBDIR="$ROOT/api/v1/lib"; source "$ROOT/api/v1/lib/common.sh" 2>/dev/null; source "$_LIBDIR/tl-store.sh"
# calibração de agora: pa com o checksum VELHO (o pacote foi editado depois), pb com o atual
tl_store_record juiz1 'col#pa' "cks-velho" '{"c":"1.000","default":"1.000"}' >/dev/null
tl_store_record juiz1 'col#pb' "cks-pb"    '{"c":"1.000","default":"1.000"}' >/dev/null
AT="$(jq -r '.["col#pa"].at // 0' "$RUN/tl-summary.json" 2>/dev/null)"
[[ "$AT" =~ ^[0-9]+$ && "$AT" -gt 0 ]] || { echo "SETUP FAIL: tl-summary sem .at"; exit 1; }
# índice gerado em <gen>, com o checksum ATUAL do pacote (pa = cks-novo ≠ o calibrado)
index(){ jq -cn --argjson g "$1" '{generated_at:$g, problems:[
   {id:"col#pa",owner:"autor",repo:"col",prob:"pa",title:"PA",public:false,collaborators:[],collections:[],tl_checksum:"cks-novo"},
   {id:"col#pb",owner:"autor",repo:"col",prob:"pb",title:"PB",public:false,collaborators:[],collections:[],tl_checksum:"cks-pb"}]}' \
   > "$T/var/problem-owners.json"; }
status(){ BODY="$(PATH_INFO=/problems/status REQUEST_METHOD=GET QUERY_STRING= HTTP_AUTHORIZATION="Bearer aut" \
    bash "$ROUTER" 2>/dev/null | awk 'f{print} /^\r?$/{f=1}')"
  ROW="$(jq -c '[.counts.needs_recalibration, (.problems|map(select(.needs_recalibration))|map(.id))]' <<<"$BODY" 2>/dev/null)"; }

echo "== índice MAIS NOVO que a calibração: o pacote mudou depois de calibrar =="
index "$((AT+60))"; status
ck "pa precisa recalibrar (e só ele): card = 1"   '[[ "$ROW" == "[1,[\"col#pa\"]]" ]]'
ck "o botão Recalibrar todos tem o que mostrar (attention_ids)" '[[ "$(jq -c ".attention_ids // [] | index(\"col#pa\") != null" <<<"$BODY")" == true ]]'
ck "pb (checksum igual) não precisa"              '[[ "$(jq -r ".problems[]|select(.id==\"col#pb\")|.needs_recalibration" <<<"$BODY")" == false ]]'

echo "== calibração MAIS NOVA que o índice: o checksum do índice é sabidamente velho =="
index "$((AT-60))"; status
ck "nada precisa recalibrar (a guarda)"           '[[ "$ROW" == "[0,[]]" ]]'

echo "== índice sem generated_at (gerador antigo): a guarda vale como antes =="
jq 'del(.generated_at)' "$T/var/problem-owners.json" > "$T/var/o.tmp" && mv "$T/var/o.tmp" "$T/var/problem-owners.json"; status
ck "sem data do índice, nenhum stale"             '[[ "$ROW" == "[0,[]]" ]]'

echo "== com o overlay authored (o caso normal em produção) =="
index "$((AT+60))"
printf '{"col#pb":{"id":"col#pb","owner":"autor","repo":"col","prob":"pb","title":"PB","public":false}}\n' > "$T/var/authored.json"
status
ck "a mescla com overlay mantém a data: card = 1" '[[ "$ROW" == "[1,[\"col#pa\"]]" ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
