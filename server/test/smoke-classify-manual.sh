#!/bin/bash
# smoke-classify-manual.sh — motor `manual` (score/classify-manual.sh): TODA promoção à mão (seletiva de universidade).
# O motor só devolve o placar (ranking, sem convidados nem excluídos, com teto); o handler aceita o `add` SEM motivo
# nesse motor, recusa passar de `slots` (409 slots_full), o desfazer libera a vaga, o "atualizar placar" (re-apply)
# mantém as promoções, e a próxima fase (nome/chip) chega ao placar público.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
export CONTESTSDIR="$FIX"
ENG="$ROOT/score/classify-manual.sh"
C="$FIX/sel"; mkdir -p "$C/var" "$C/enunciados"
NOW=$(date +%s); T0=$(( NOW - 7200 ))
{ printf 'CONTEST_ID=sel\nCONTEST_TYPE=icpc\nCONTEST_NAME=Seletiva\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$T0" "$(( NOW + 3600 ))"
  printf 'PROBS=( x col#p1 P1 A col#p1 x col#p2 P2 B col#p2 x col#p3 P3 C col#p3 )\n'
} > "$C/conf"
mkteam(){ local login="$1" mins="$2"; mkdir -p "$C/users/$login"
  jq -cn --arg l "$login" '{login:$l, fullname:("Time " + $l), password:"x", team:{univ_short:"UNB"}}' > "$C/users/$login/account.json"
  : > "$C/users/$login/history"; local i=0 m se
  for m in ${mins//,/ }; do i=$((i+1)); se=$(( T0 + m*60 ))
    printf '%s:col#p%d:C:Accepted:%s:id%s%d\n' "$se" "$i" "$se" "$login" "$i" >> "$C/users/$login/history"; done; }
mkteam alfa "1,2,3"; mkteam beta "2,3"; mkteam gama "4,5"; mkteam delta "9"; mkteam eps ""
( cd "$ROOT/score" && CONTESTSDIR="$FIX" bash build.sh sel >/dev/null 2>&1 )
[[ -s "$C/var/placar.txt" ]] || { echo "build.sh não gerou placar"; exit 1; }

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
bad(){ FAIL=$((FAIL+1)); echo "FALHOU: $*" >&2; }
eqk(){ [[ "$1" == "$2" ]] && ok || bad "$3 (veio '$1', esperado '$2')"; }

echo '{"algorithm":"manual"}' > "$FIX/k.json"
bash "$ENG" --check "$FIX/k.json" 2>"$FIX/k.err"; eqk "$?" "2" "--check: sem slots"
grep -q 'slots' "$FIX/k.err" && ok || bad "--check diz o campo"
echo '{"algorithm":"manual","slots":2}' > "$FIX/cfg.json"
bash "$ENG" sel "$FIX/cfg.json" "$FIX/o.json" || { echo "motor falhou"; exit 1; }
eqk "$(jq -r '[.ranking[].login] | join(",")' "$FIX/o.json")" "alfa,beta,gama,delta,eps" "ranking = o placar, na ordem"
eqk "$(jq -r '"\(.total) \(.classified | length) \(.slots) \(.ranking[0].place) \(.ranking[0].total) \(.ranking[0].univ)"' "$FIX/o.json")" "0 0 2 1 3 UNB" "nada é automático; linha com posição, total e escola"
jq '. + {exclude:["beta"], ranking_limit:2}' "$FIX/cfg.json" > "$FIX/c2.json"; bash "$ENG" sel "$FIX/c2.json" "$FIX/o2.json"
eqk "$(jq -r '[.ranking[].login] | join(",")' "$FIX/o2.json"),$(jq -r '[.warnings[].code] | join(",")' "$FIX/o2.json")" "alfa,gama,ranking_truncated" "exclude e teto do ranking (com aviso)"

ROUTER="$ROOT/api/v1/router.sh"
mkdir -p "$C/users/sel.admin"; jq -cn '{login:"sel.admin", fullname:"Admin", password:"x"}' > "$C/users/sel.admin/account.json"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' sel sel.admin Admin "$NOW" > "$SESS/t-adm"
calla(){ OUT="$(PATH_INFO=/contest/admin/classify REQUEST_METHOD="$1" QUERY_STRING="contest=sel" HTTP_AUTHORIZATION="Bearer t-adm" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${2:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }
stj(){ jq -r "first(.stages[] | select(.id == \"seletiva\")) | $1" "$C/classification.json"; }
calla GET
eqk "$(J '.algorithms[] | select(.id=="manual") | "\(.stage) \(.reason_optional) \(.form)"')" "proxima-fase true manual" "catálogo: motor manual"
calla POST '{"action":"apply","stage":"seletiva","config":{"algorithm":"manual","slots":2},"name":"Maratona SBC — 1ª fase","chip":"SBC"}'
eqk "$(J '.applied')" "true" "apply cria a etapa"
eqk "$(J '.result.labels.manual.en')" "Promoted by the organizers" "rótulo da via no motor manual (pt/en/es)"
eqk "$(stj '"\(.name)|\(.chip)|\(.teams | length)|\(.result.ranking | length)"')" "Maratona SBC — 1ª fase|SBC|0|5" "próxima fase, chip, nenhum promovido, placar no result"
calla POST '{"action":"add","stage":"seletiva","login":"beta"}'
eqk "$(J '.override')" "ov-1" "promover SEM motivo (motor manual)"
calla POST '{"action":"add","stage":"seletiva","login":"delta","reason":"melhor calouro"}'
eqk "$(J '.override')" "ov-2" "promover com motivo"
calla POST '{"action":"add","stage":"seletiva","login":"alfa"}'
eqk "$(J '"\(.error.code) \(.error.slots)"')" "slots_full 2" "passar das vagas = 409 slots_full"
calla POST '{"action":"exclude","stage":"seletiva","login":"gama"}'
eqk "$(J '.error.code')" "reason_required" "fora o add, o motivo segue obrigatório"
calla POST '{"action":"override_undo","stage":"seletiva","id":"ov-1"}'
calla POST '{"action":"add","stage":"seletiva","login":"alfa"}'
eqk "$(stj '[.teams | keys[]] | sort | join(",")')" "alfa,delta" "desfazer libera a vaga"
eqk "$(stj '.overrides[] | select(.login=="delta") | .reason')" "melhor calouro" "motivo guardado (interno)"
calla POST '{"action":"apply","stage":"seletiva","config":{"algorithm":"manual","slots":2}}'
eqk "$(stj '"\(.teams | length)|\(.name)"')" "2|Maratona SBC — 1ª fase" "atualizar o placar (re-apply) mantém promoções e a próxima fase"
# auditoria do painel (03/10/2026): baixar as vagas abaixo dos promovidos = 409 (era "Promovidos 2 de 1")
calla POST '{"action":"apply","stage":"seletiva","config":{"algorithm":"manual","slots":1}}'
eqk "$(J '"\(.error.code) \(.error.promoted)"')" "slots_below_promoted 2" "vagas abaixo dos promovidos = 409 slots_below_promoted"
eqk "$(stj '.config.slots')" "2" "…e nada gravado"
# nome/local/quando ENVIADOS vazios apagam (nome volta ao padrão do motor); ausentes mantêm
calla POST '{"action":"apply","stage":"seletiva","config":{"algorithm":"manual","slots":2},"venue":"Brasília","when":"novembro"}'
eqk "$(stj '"\(.venue)|\(.when)"')" "Brasília|novembro" "local e quando gravados"
calla POST '{"action":"apply","stage":"seletiva","config":{"algorithm":"manual","slots":2},"name":"","venue":"","when":""}'
eqk "$(stj '"\(.name != "Maratona SBC — 1ª fase")|\(.venue)|\(.when)"')" "true||" "enviados vazios: nome volta ao padrão, local/quando limpos"
calla POST '{"action":"apply","stage":"seletiva","config":{"algorithm":"manual","slots":2},"name":"Maratona SBC — 1ª fase"}'
calla POST '{"action":"publish","stage":"seletiva"}'
PUB="$(PATH_INFO=/contest/classification REQUEST_METHOD=GET QUERY_STRING="contest=sel" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" 2>/dev/null | awk 'f{print} /^\r?$/{f=1}')"
eqk "$(jq -r '.stages[0] | "\(.chip) \(.teams | keys | join(",")) \(.teams.alfa.via) \(.labels.manual.short.pt)"' <<<"$PUB")" "SBC alfa,delta manual escolha da organização" "placar público: chip da próxima fase e a via \"escolha da organização\""
jq -e '[.. | .reason? // empty] | length == 0' <<<"$PUB" >/dev/null && ok || bad "motivo vazou no público"

# ---- VIAS COM RÓTULO (09/11/2026, finais LATAM: o motivo público das 80 vagas era "organizers' choice") ----------------
# motor: sem `labels` sai IGUAL a antes; com `labels`, os rótulos da config entram e o via_order segue a ordem dela
eqk "$(jq -c '{labels: (.labels | keys), via_order}' "$FIX/o.json")" '{"labels":["manual"],"via_order":["manual"]}' "sem labels: só a via manual (como antes)"
LBL='{"country-part":{"pt":"Participação do país","en":"Country participation","es":"Participación del país","short":{"pt":"país","en":"country","es":"país"}},"pend":"Pendente"}'
jq --argjson l "$LBL" '. + {labels:$l}' "$FIX/cfg.json" > "$FIX/c3.json"; bash "$ENG" sel "$FIX/c3.json" "$FIX/o3.json"
eqk "$(jq -c '.via_order' "$FIX/o3.json")" '["manual","country-part","pend"]' "com labels: via_order = manual + as da config, na ordem"
eqk "$(jq -r '"\(.labels["country-part"].short.en)|\(.labels.pend)|\(.labels.manual.short.en)"' "$FIX/o3.json")" "country|Pendente|organizers' choice" "com labels: os da config + o manual"
for bad in '{"p1":"x"}' '{"comite":"x"}' '{"Maiusc":"x"}' '{"z":null}' '{"z":{"pt":1}}'; do
  jq --argjson l "$bad" '. + {labels:$l}' "$FIX/cfg.json" > "$FIX/k3.json"
  bash "$ENG" --check "$FIX/k3.json" 2>/dev/null; eqk "$?" 2 "--check recusa labels $bad"
done
# handler: num estágio do motor manual o add aceita manual_vias + vias do catálogo (sem comite) + as da config.labels
calla POST "$(jq -cn --argjson l "$LBL" '{action:"apply", stage:"vagas", config:{algorithm:"manual", slots:5, labels:$l}, name:"Final"}')"
eqk "$(J '.applied')" "true" "apply com labels"
calla POST '{"action":"add","stage":"vagas","login":"alfa","via":"p1"}';           eqk "$(J '.override')" "ov-1" "add com via do catálogo (p1)"
calla POST '{"action":"add","stage":"vagas","login":"beta","via":"country-part"}'; eqk "$(J '.override')" "ov-2" "add com via da config (country-part)"
calla POST '{"action":"add","stage":"vagas","login":"gama","via":"zzz"}';          eqk "$(J '.error.code')" "via_invalid" "via desconhecida = 422 via_invalid"
calla POST '{"action":"add","stage":"vagas","login":"gama","via":"comite"}';       eqk "$(J '.error.code')" "via_invalid" "comite (marcador legado) = 422 via_invalid"
vst(){ jq -r "first(.stages[] | select(.id == \"vagas\")) | $1" "$C/classification.json"; }
eqk "$(vst '"\(.teams.alfa.via)|\(.teams.beta.via)|\(.labels.p1.short.pt)|\(.labels["country-part"].short.pt)"')" \
  "p1|country-part|$(jq -r '.vias.p1.short.pt' "$ROOT/score/classify-catalog.json")|país" "estágio: vias dos times e os rótulos (catálogo + config)"
# relabel: troca SÓ a via (id, motivo, autor e data ficam), com a mesma validação; vai ao audit com via=antiga→nova
AT1="$(vst '.overrides[] | select(.id=="ov-1") | .at')"
calla POST '{"action":"relabel","stage":"vagas","id":"ov-1","via":"p2"}'
eqk "$(J '.override')" "ov-1" "relabel responde o mesmo id"
eqk "$(vst '.overrides[] | select(.id=="ov-1") | "\(.via)|\(.at)|\(.login)|\(.op)"')" "p2|$AT1|alfa|add" "relabel: via nova, mesma data, mesmo time"
eqk "$(vst '"\(.teams.alfa.via)|\(.labels.p2.short.pt != null)|\(.overrides | length)"')" "p2|true|2" "relabel: time com a via nova, rótulo dela, nenhum override novo"
tail -1 "$C/var/admin-audit.log" | grep -q "relabel stage=vagas key=alfa id=ov-1 via=p1→p2" && ok || bad "relabel no audit com via=antiga→nova"
calla POST '{"action":"relabel","stage":"vagas","id":"ov-1","via":"zzz"}';   eqk "$(J '.error.code')" "via_invalid" "relabel com via desconhecida = 422"
calla POST '{"action":"relabel","stage":"vagas","id":"ov-9","via":"p1"}';    eqk "$(J '.error.code')" "override_notfound" "relabel de id inexistente = 404"
calla POST '{"action":"exclude","stage":"vagas","login":"gama","reason":"teste"}'
calla POST '{"action":"relabel","stage":"vagas","id":"ov-3","via":"p1"}';    eqk "$(J '.error.code')" "override_not_add" "relabel de um exclude = 409 override_not_add"
# outros motores: só as manual_vias
jq -c '.stages += [{id:"brx", status:"draft", config:{algorithm:"sbc-fase1"}, teams:{}, overrides:[]}]' "$C/classification.json" > "$FIX/cf2" && mv "$FIX/cf2" "$C/classification.json"
calla POST '{"action":"add","stage":"brx","login":"gama","via":"p1","reason":"x"}'; eqk "$(J '.error.code')" "via_invalid" "motor não-manual: via do catálogo segue recusada no add"
# público: o rótulo de cada via (o short do catálogo e o da config), nunca o motivo
calla POST '{"action":"publish","stage":"vagas"}'
PUB2="$(PATH_INFO=/contest/classification REQUEST_METHOD=GET QUERY_STRING="contest=sel" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" 2>/dev/null | awk 'f{print} /^\r?$/{f=1}')"
eqk "$(jq -r 'first(.stages[] | select(.id=="vagas")) | "\(.teams.alfa.via)|\(.labels.p2.short.pt != null)|\(.labels["country-part"].short.en)"' <<<"$PUB2")" "p2|true|country" "público: vias e rótulos do catálogo e da config"
# relatório (classificados.html): o short certo de cada time
if ( cd "$ROOT/score" && CONTESTSDIR="$FIX" bash report-gen.sh sel "$FIX/rep" >/dev/null 2>&1 ) && [[ -s "$FIX/rep/classificados.html" ]]; then
  grep -q "país" "$FIX/rep/classificados.html" && grep -qF "$(jq -r '.vias.p2.short.pt' "$ROOT/score/classify-catalog.json")" "$FIX/rep/classificados.html" && ok \
    || bad "classificados.html sem o rótulo da via (config/catálogo)"
else bad "report-gen não gerou classificados.html no fixture"; fi

echo "smoke-classify-manual: PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
