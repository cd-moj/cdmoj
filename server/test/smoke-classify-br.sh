#!/bin/bash
# smoke-classify-br.sh — motor das regras da Final Brasileira (classify-br.sh). Cobre:
#   r0: campeão de sede com 2 problemas ELEGÍVEL; 2 problemas sem ser campeão NÃO
#       (inclusive na regra 4 — feminina inelegível fica de fora e a vaga sobra);
#   r1: ≤2 por escola (o 3º da mesma escola pula p/ o próximo elegível);
#   r2 sede normal: escola com time na r1 BLOQUEADA; ≤1 por escola nesta regra;
#   r2 supersede: ≤1 por sede membra + resolve o pai certo (nó regional ≠ supersede);
#   r4: ignora limite de escola e não repete classificado; convidado não consome nada.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
export CONTESTSDIR="$FIX"
C="$FIX/cb"; mkdir -p "$C/var" "$C/enunciados"
NOW=$(date +%s); T0=$(( NOW - 7200 ))
{ printf 'CONTEST_ID=cb\nCONTEST_TYPE=icpc\nCONTEST_NAME=Classify\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$T0" "$(( NOW + 3600 ))"
  printf 'PROBS=( x col#p1 P1 A col#p1 x col#p2 P2 B col#p2 x col#p3 P3 C col#p3 x col#p4 P4 D col#p4 x col#p5 P5 E col#p5 )\n'
} > "$C/conf"
jq -cn '{version:1, results_released:true, cohorts:[
  {id:"oficial", name:"Oficiais", regex:"", public:true, unranked:false, ranking:false, default:true},
  {id:"conv", name:"Convidados", regex:"^teamspg", public:false, unranked:true, ranking:false, default:false, sees:["oficial","conv"]}]}' \
  > "$C/cohorts.json"

jq -n '[
  {name:"Brasil", regex:"^team", subregions:[
    {name:"Sudeste", regex:"^team(sp|rj)", subregions:[
      {name:"SP, Capital", regex:"^teamsp"},
      {name:"RJ, Rio", regex:"^teamrj"}]},
    {name:"Norte", regex:"^team(am|ac)", subregions:[
      {name:"AM, Manaus", regex:"^teamam"},
      {name:"AC, Rio Branco", regex:"^teamac"}]},
    {name:"Supersede Norte", regex:"^team(am|ac)", view:true, subregions:[
      {name:"AM, Manaus", regex:"^teamam"},
      {name:"AC, Rio Branco", regex:"^teamac"}]}]},
  {name:"Times femininos", regex:"^(teamsp03|teamam01|teamsp05|teamrj03)", view:true, subregions:[
    {name:"3 competidoras", regex:"^(teamsp03)", view:true,
     subregions:[{name:"Brasil", regex:"^(teamsp03)"}]},
    {name:"2 competidoras", regex:"^(teamam01|teamsp05)", view:true,
     subregions:[{name:"Brasil", regex:"^(teamam01|teamsp05)"}]},
    {name:"1 competidora", regex:"^(teamrj03)", view:true,
     subregions:[{name:"Brasil", regex:"^(teamrj03)"}]}]}]' > "$C/regions.json"

# times pelo STORE REAL (history -> build.sh -> placar), como em produção.
# mkteam <login> <univ> <nome> <min,min,...> : 1 AC por problema (col#p1..pk) nos minutos dados
mkteam(){
  local login="$1" univ="$2" name="$3" mins="$4"
  mkdir -p "$C/users/$login"
  jq -cn --arg l "$login" --arg u "$univ" --arg n "$name" \
    '{login:$l, fullname:$n, password:"x", team:{univ_short:$u, univ_full:("Univ "+$u), flag:"br", region:""}}' \
    > "$C/users/$login/account.json"
  : > "$C/users/$login/history"
  local i=0 m se
  for m in ${mins//,/ }; do
    i=$((i+1)); se=$(( T0 + m*60 ))
    printf '%s:col#p%d:C:Accepted:%s:id%s%d\n' "$se" "$i" "$se" "$login" "$i" >> "$C/users/$login/history"
  done
}
mkteam teamspg  GUEST   "Convidado"           "1,1,1,1,1"   # convidado (coorte conv)
mkteam teamsp01 USP     "USP Alfa"            "1,2,3,4,5"   # 5 probs pen15
mkteam teamsp02 USP     "USP Beta"            "2,3,4,5,6"   # 5 probs pen20
mkteam teamsp03 USP     "USP Gama Fem3"       "1,2,3,4"     # 4 pen10 (3ª da USP: fora da r1)
mkteam teamrj01 UFRJ    "UFRJ Alfa"           "2,3,4,5"     # 4 pen14 (r1 #3)
mkteam teamsp04 UNICAMP "UNICAMP Alfa"        "3,4,5,6"     # 4 pen18 (r2 SP)
mkteam teamsp05 UNICAMP "UNICAMP Beta Fem2"   "4,5,6,7"     # 4 pen22 (r4 f2)
mkteam teamsp06 MACK    "MACK Alfa"           "1,2,3"       # 3 pen6  (r2 SP 2ª vaga)
mkteam teamrj02 UFF     "UFF Alfa"            "3,4,5"       # 3 pen12 (r2 RJ)
mkteam teamam01 UFAM    "UFAM Alfa Fem2"      "4,5,6"       # 3 pen15 (r2 supersede)
mkteam teamam02 UFAM    "UFAM Beta"           "5,6,7"       # 3 pen18 (fora: sede AM usada)
mkteam teamac01 CACO    "CACO Campeao"        "1,2"         # 2 pen3  campeão AC (r2 supersede)
mkteam teamrj03 PUC     "PUC Fem1 NaoCampeao" "2,3"         # 2 pen5  (fora: r0)

( cd "$ROOT/score" && CONTESTSDIR="$FIX" bash build.sh cb >/dev/null 2>&1 )
[[ -s "$C/var/placar-full.txt" || -s "$C/var/placar.txt" ]] || { echo "build.sh não gerou placar"; exit 1; }

jq -n '{region:"Brasil", r1:3, r4:{f3:1,f2:1,f1:1},
        sedes:{"SP, Capital":2, "RJ, Rio":1},
        supersedes:{"Supersede Norte":2}}' > "$FIX/cfg.json"

OUT="$FIX/out.json"
bash "$ROOT/score/classify-br.sh" cb "$FIX/cfg.json" "$OUT" || { echo "motor falhou"; exit 1; }

PASS=0; FAIL=0
ck(){ if jq -e "$1" "$OUT" >/dev/null 2>&1; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $2  [$1]" >&2; fi }
via(){ jq -r --arg l "$1" '.classified[] | select(.login==$l) | .via' "$OUT"; }

ck '.total == 10' "total de classificados = 10 (veio $(jq -r .total "$OUT"))"
ck '[.warnings[]? | select(.code == "sede_missing" or .code == "supersede_missing")] | length == 0' "config com sedes que existem: sem aviso de sede ausente"
# região que NÃO existe no regions.json: erro de config (rc 2), nunca classificação vazia calada (auditoria, 03/10/2026)
jq '.region = "Brasl"' "$FIX/cfg.json" > "$FIX/cfg-bad.json"
bash "$ROOT/score/classify-br.sh" cb "$FIX/cfg-bad.json" "$FIX/out-bad.json" 2>"$FIX/err-bad"; rcb=$?
[[ "$rcb" == 2 ]] && grep -q 'Brasl' "$FIX/err-bad" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU: região inexistente devia dar rc 2 (deu $rcb)"; }
# sede/supersede com vaga que não existe na árvore: aviso (a vaga não vai a ninguém)
jq '.sedes["XX, Lugar Nenhum"] = 1 | .supersedes["Supersede Fantasma"] = 1' "$FIX/cfg.json" > "$FIX/cfg-miss.json"
bash "$ROOT/score/classify-br.sh" cb "$FIX/cfg-miss.json" "$FIX/out-miss.json" 2>/dev/null
jq -e '([.warnings[] | select(.code == "sede_missing") | .data.sites[]] == ["XX, Lugar Nenhum"]) and ([.warnings[] | select(.code == "supersede_missing") | .data.sites[]] == ["Supersede Fantasma"])' \
  "$FIX/out-miss.json" >/dev/null 2>&1 && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU: aviso de sede/supersede inexistente"; }
[[ "$(via teamsp01)" == regra1 ]] && ok=1 || ok=0; (( ok )) && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU sp01 regra1"; }
[[ "$(via teamsp02)" == regra1 ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU sp02 regra1"; }
[[ "$(via teamrj01)" == regra1 ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU rj01 regra1 (cap USP devia pular sp03)"; }
[[ "$(via teamsp03)" == regra4 ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU sp03 regra4-f3 (USP bloqueada na r2, fem ignora escola)"; }
[[ "$(via teamsp04)" == regra2 ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU sp04 regra2 sede SP"; }
[[ "$(via teamsp05)" == regra4 ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU sp05 regra4-f2 (UNICAMP já tinha r2; fem ignora)"; }
[[ "$(via teamsp06)" == regra2 ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU sp06 regra2 sede SP 2ª vaga"; }
[[ "$(via teamrj02)" == regra2 ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU rj02 regra2 sede RJ"; }
[[ "$(via teamam01)" == regra2 ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU am01 regra2 supersede"; }
[[ "$(via teamac01)" == regra2 ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU ac01 campeão-com-2 na supersede (1/sede membra)"; }
ck '([.classified[] | select(.login=="teamam02")] | length) == 0' "am02 FORA (sede AM já usada na supersede)"
ck '([.classified[] | select(.login=="teamrj03")] | length) == 0' "rj03 FORA (2 problemas sem ser campeão — r0 vale na r4)"
ck '([.classified[] | select(.login=="teamspg")] | length) == 0' "convidado fora"
ck '.unused.regra1 == 0 and .unused.regra2 == 0 and .unused.regra4 == 1' "unused {r1:0,r2:0,r4:1 (f1 sem elegível)}"
ck '(.classified[] | select(.login=="teamac01") | .detail) | test("Supersede Norte")' "detail da supersede"

# ---- parte 2: RELATÓRIO (chip ↑BR no placar + página classificados.html) ----------------
# classification.json no shape do apply (published) a partir da saída do motor
jq -c '{version:1, stages:[{id:"final-br", status:"published",
  name:"Final Brasileira", venue:"Uberlândia", when:"novembro/2026", region:.region,
  teams:(.classified | map({key:.login, value:{via, sede, place, total, detail}}) | from_entries)}]}' \
  "$OUT" > "$C/classification.json"
REP="$FIX/rep"
bash "$ROOT/score/report-gen.sh" cb "$REP" >/dev/null 2>&1 || { echo "report-gen falhou"; exit 1; }
rk(){ if grep -q "$1" "$2" 2>/dev/null; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $3" >&2; fi }
rk 'class="qual-row"' "$REP/index.html" "linha destacada no placar do relatório"
rk '&#127891;' "$REP/index.html" "pill 🎓 no placar do relatório"
rk 'qual-sub' "$REP/index.html" "sub-linha PDA-style no relatório"
rk 'classificados.html' "$REP/index.html" "aba Classificados na nav"
[[ -s "$REP/classificados.html" ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU: classificados.html ausente" >&2; }
rk 'Regra 1' "$REP/classificados.html" "seção regra 1"
rk 'Supersede Norte' "$REP/classificados.html" "detalhe da supersede na página"
rk 'Uberl' "$REP/classificados.html" "nome/venue do stage na nota"
# rascunho NÃO vaza: com status draft, nem chip nem página
jq -c '.stages[0].status="draft"' "$C/classification.json" > "$C/cl.tmp" && mv "$C/cl.tmp" "$C/classification.json"
REP2="$FIX/rep2"
bash "$ROOT/score/report-gen.sh" cb "$REP2" >/dev/null 2>&1
grep -q 'class="qual-row"' "$REP2/index.html" 2>/dev/null && { FAIL=$((FAIL+1)); echo "FALHOU: marcação vazou com stage em RASCUNHO" >&2; } || PASS=$((PASS+1))
[[ -f "$REP2/classificados.html" ]] && { FAIL=$((FAIL+1)); echo "FALHOU: página vazou em rascunho" >&2; } || PASS=$((PASS+1))

# ---- parte 3: /contest/classification — rascunho SÓ p/ o admin (marcado draft) ----------
ROUTER="$ROOT/api/v1/router.sh"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
mkdir -p "$C/users/cb.admin"
jq -cn '{login:"cb.admin", fullname:"Admin", password:"x"}' > "$C/users/cb.admin/account.json"
NOWE=$(date +%s)
mktok(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' cb "$1" "$1" "$NOWE" > "$SESS/$2"; }
mktok cb.admin t-adm; mktok teamsp01 t-team
callc(){ PATH_INFO=/contest/classification REQUEST_METHOD=GET QUERY_STRING="contest=cb" \
    HTTP_AUTHORIZATION="${1:+Bearer $1}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" 2>/dev/null | awk 'f{print} /^\r?$/{f=1}'; }
# estado atual do fixture: stage em DRAFT (parte 2 terminou assim)
B_ANON="$(callc "")"; B_TEAM="$(callc t-team)"; B_ADM="$(callc t-adm)"
jq -e '.stages == []' <<<"$B_ANON" >/dev/null && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU: anônimo viu rascunho" >&2; }
jq -e '.stages == []' <<<"$B_TEAM" >/dev/null && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU: competidor viu rascunho" >&2; }
jq -e '.stages[0].draft == true and (.stages[0].teams | length) == 10' <<<"$B_ADM" >/dev/null \
  && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU: admin não viu o rascunho marcado ($B_ADM)" >&2; }
# publicado: todos veem, SEM flag draft
jq -c '.stages[0].status="published"' "$C/classification.json" > "$C/cl.tmp" && mv "$C/cl.tmp" "$C/classification.json"
B_ANON2="$(callc "")"
jq -e '(.stages[0].draft // false) == false and (.stages[0].teams | length) == 10' <<<"$B_ANON2" >/dev/null \
  && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU: publicado não chegou ao anônimo" >&2; }

# ---- parte 4: placar SEM coluna guest (sem coorte unranked) -----------------------------------
# Regressão de 30/09/2026: o motor contava as colunas do FIM (`$NF` = guest). Sem coorte unranked a coluna
# não existe: `$NF` virava o LastAC (time com LastAC=1 era tomado por convidado e SUMIA) e o "Total" vinha
# de uma célula de problema. Agora o placar sai pelo cabeçalho (sc_board_rows).
C2="$FIX/cb2"; mkdir -p "$C2/var" "$C2/enunciados"
{ printf 'CONTEST_ID=cb2\nCONTEST_TYPE=icpc\nCONTEST_NAME=Classify2\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$T0" "$(( NOW + 3600 ))"
  printf 'PROBS=( x col#p1 P1 A col#p1 x col#p2 P2 B col#p2 x col#p3 P3 C col#p3 x col#p4 P4 D col#p4 x col#p5 P5 E col#p5 )\n'
} > "$C2/conf"
jq -n '[{name:"Brasil", regex:"^team", subregions:[{name:"SP, Capital", regex:"^teamsp"}]},
        {name:"Times femininos", regex:"^(teamsp0)", view:true, subregions:[
          {name:"2 competidoras", regex:"^(teamsp0)", view:true}]}]' > "$C2/regions.json"
C_SAVE="$C"; C="$C2"
mkteam teamsp01 USP  "USP Um"   "1,1,1"     # 3 problemas, LastAC = 1 (o antigo o tomava por convidado)
mkteam teamsp02 FATEC "FATEC Um" "2,3,4"    # 3 problemas
C="$C_SAVE"
( cd "$ROOT/score" && CONTESTSDIR="$FIX" bash build.sh cb2 >/dev/null 2>&1 )
B2="$C2/var/placar.txt"; [[ -s "$C2/var/placar-full.txt" ]] && B2="$C2/var/placar-full.txt"
grep -q ':guest' "$B2" && { FAIL=$((FAIL+1)); echo "FALHOU: fixture tinha coluna guest (devia não ter)" >&2; } || PASS=$((PASS+1))
jq -n '{region:"Brasil", r1:2, r4:{f3:0,f2:0,f1:0}, sedes:{}, supersedes:{}}' > "$FIX/cfg2.json"
OUT2="$FIX/out2.json"
bash "$ROOT/score/classify-br.sh" cb2 "$FIX/cfg2.json" "$OUT2" 2>/dev/null || { echo "motor falhou (cb2)"; exit 1; }
ck2(){ if jq -e "$1" "$OUT2" >/dev/null 2>&1; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $2  [$1]" >&2; fi }
ck2 '.total == 2 and ([.classified[].via] | unique) == ["regra1"]' "sem coluna guest: os dois na regra 1 (veio $(jq -c '[.classified[]|{login,via,total}]' "$OUT2"))"
ck2 '(.classified[] | select(.login=="teamsp01") | .total) == 3' "teamsp01 (LastAC=1) com total 3"
ck2 '[.warnings[] | select(.code=="female_prefix_match") | .data.logins[]] | sort == ["teamsp01","teamsp02"]' "aviso: lista feminina casando por PREFIXO (^(teamsp0))"

# ---- parte 5: handler admin/classify — apply, overrides, estágios -----------------------------------
# o mesmo contest cb (estágio final-br publicado no shape ANTIGO: sem config/result/overrides) + um estágio
# "legado" com um promovido via:"comite" (vira override add na leitura).
jq -c '.stages += [{id:"legado", status:"draft", name:"Legado", teams:{teamam02:{via:"comite", note:"regra 3", at:1, by:"cb.admin"}}}]' \
  "$C/classification.json" > "$C/cl.tmp" && mv "$C/cl.tmp" "$C/classification.json"
mkdir -p "$C/users/cb.admin"
calla(){ OUT="$(PATH_INFO=/contest/admin/classify REQUEST_METHOD="$1" QUERY_STRING="contest=cb" HTTP_AUTHORIZATION="Bearer ${3:-t-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${2:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
hk(){ if jq -e "$1" <<<"$BODY" >/dev/null 2>&1; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $2  [${BODY:0:300}]" >&2; fi }
fk(){ if jq -e "$1" "$C/classification.json" >/dev/null 2>&1; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $2" >&2; fi }
stv(){ jq -r --arg l "$1" '(.stages[] | select(.id=="final-br") | .teams[$l].via) // "-"' "$C/classification.json"; }
eqk(){ if [[ "$1" == "$2" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $3 (veio '$1', esperado '$2')" >&2; fi }
CFGJ="$(cat "$FIX/cfg.json")"

calla GET
hk '(.algorithms[0].id == "sbc-fase1") and (.vias.regra1.pt | test("Regra 1")) and (.manual_vias | index("manual"))' "GET: catálogo + rótulos das vias"
hk '(.stages[] | select(.id=="legado") | .overrides[0] | .op == "add" and .login == "teamam02" and .reason == "regra 3")' "GET: comitê antigo lido como override add"
hk '(.stages[] | select(.id=="legado") | .relation[0] | .manual == true and .via == "manual")' "GET: relação marca o manual"
calla GET '' t-team
[[ "$OUT" == *"Status: 403"* ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU: competidor no admin/classify" >&2; }

calla POST "$(jq -cn --argjson c "$CFGJ" '{action:"preview", config:$c}')"
hk '.stage == "final-br" and (.relation | length) == 10 and .preview.total == 10' "preview: estágio padrão do motor + relação"
calla POST "$(jq -cn --argjson c "$CFGJ" '{action:"apply", config:($c + {r1:"x"})}')"
hk '.error.code == "config_invalid" and (.error.errors | any(test("r1")))' "config inválida = 422 config_invalid com errors"
calla POST "$(jq -cn --argjson c "$CFGJ" '{action:"preview", config:($c + {algorithm:"pda-2030"})}')"
hk '.error.code == "algorithm_invalid"' "algoritmo fora da allowlist = 422"
calla POST "$(jq -cn --argjson c "$CFGJ" '{action:"apply", config:$c, name:""}')"
hk '.applied == true and .stage == "final-br"' "apply no estágio antigo"
fk '.stages[] | select(.id=="final-br") | .chip == "Final BR" and .name == "Final Brasileira" and .config.algorithm == "sbc-fase1" and (.teams | length) == 10 and (.result.classified | length) == 10 and .via_order[0] == "regra1" and (.labels.regra2.es | test("sede"))' "apply grava chip/config/result/rótulos (nome vazio = padrão)"

# withdraw: sai SEM recalcular — a vaga fica vaga
calla POST '{"action":"withdraw","login":"teamrj02"}'
hk '.error.code == "reason_required"' "withdraw sem motivo = 422"
calla POST '{"action":"withdraw","login":"teamrj02","reason":"desistiu"}'
hk '.override == "ov-1" and .total == 9' "withdraw: 9 times"
eqk "$(stv teamrj02)" "-" "withdraw tira o rj02"
calla POST '{"action":"withdraw","login":"teamrj02","reason":"de novo"}'
hk '.error.code == "override_exists" and .error.override == "ov-1"' "um override por time"
calla POST '{"action":"withdraw","login":"teamrj03","reason":"x"}'
hk '.error.code == "not_classified"' "withdraw de quem não está = 404"
# exclude: sai do CÁLCULO — o próximo herda (UNICAMP deixa de estar bloqueada: sp05 pega a vaga da sede SP)
calla POST '{"action":"exclude","login":"teamsp04","reason":"time inelegível"}'
hk '.override == "ov-2"' "exclude"
eqk "$(stv teamsp04)" "-" "exclude tira o sp04"
eqk "$(stv teamsp05)" "regra2" "o próximo herda a vaga (sp05 na regra 2)"
eqk "$(stv teamrj02)" "-" "o withdraw sobrevive ao recálculo"
# add: promove à mão e conta como já promovido (am02 nunca ganha a vaga da supersede do am01)
calla POST '{"action":"add","login":"teamsp01","reason":"x"}'
hk '.error.code == "already_classified"' "add de quem já está = 409"
calla POST '{"action":"add","login":"teamam02","reason":"regra 3: sede sem time"}'
hk '.override == "ov-3"' "add"
calla POST '{"action":"exclude","login":"teamam01","reason":"dado errado"}'
eqk "$(stv teamam02)" "manual" "o promovido à mão não ganha 2ª vaga quando a do am01 abre"
fk '[.stages[] | select(.id=="final-br") | .teams | to_entries[] | select(.key=="teamam02")] | length == 1' "uma linha só p/ o am02"
calla POST '{"action":"add","ext":"lugia-usb","team":"Lugia","univ":"USB","reason":"pendente de 2026"}'
hk '.override == "ov-5"' "add de time externo"
fk '.stages[] | select(.id=="final-br") | .teams["ext:lugia-usb"] | .via == "manual" and .team == "Lugia"' "time externo na lista (chave ext:)"
# re-apply: overrides sobrevivem
calla POST "$(jq -cn --argjson c "$CFGJ" '{action:"apply", config:$c}')"
fk '.stages[] | select(.id=="final-br") | (.overrides | length) == 5 and (.teams.teamrj02 == null) and (.teams.teamsp04 == null) and .teams.teamam02.via == "manual"' "re-apply mantém os 5 overrides"
# desfazer
calla POST '{"action":"override_undo","id":"ov-1"}'
eqk "$(stv teamrj02)" "regra2" "undo do withdraw devolve o rj02"
calla POST '{"action":"override_undo","id":"ov-2"}'
eqk "$(stv teamsp04)" "regra2" "undo do exclude devolve o sp04"
calla POST '{"action":"override_undo","id":"ov-99"}'
hk '.error.code == "override_notfound"' "undo de id inexistente = 404"
grep -q 'classify-override	exclude stage=final-br key=teamsp04 id=ov-2 reason=time inelegível' "$C/var/admin-audit.log" \
  && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU: audit classify-override" >&2; }
# público: só via/sede, sem ext:, com chip e rótulos
B_PUB="$(callc "")"
jq -e '.stages[] | select(.id=="final-br") | .chip == "Final BR" and (.teams | has("ext:lugia-usb") | not) and (.teams.teamam02 | keys) == ["sede","via"] and (.labels.manual.short.pt == "comitê")' <<<"$B_PUB" >/dev/null \
  && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU: público (chip, ext filtrado, só via/sede) :: ${B_PUB:0:300}" >&2; }
jq -e '[.. | .reason? // empty] | length == 0' <<<"$B_PUB" >/dev/null && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU: motivo vazou no público" >&2; }
# estágios: 404, apagar rascunho, publicado não se apaga
calla POST '{"action":"publish","stage":"nao-existe"}'
hk '.error.code == "no_stage"' "publish de estágio inexistente = 404 no_stage"
calla POST '{"action":"delete","stage":"final-br"}'
hk '.error.code == "stage_published"' "publicado não se apaga"
calla POST '{"action":"delete","stage":"legado"}'
fk '[.stages[] | select(.id=="legado")] | length == 0' "rascunho apagado"

# PLACAR CONGELADO (auditoria do painel, 03/10/2026): o motor lê o placar completo e o público vê o estágio
# publicado — publicar/recalcular um publicado com o freeze valendo vazaria o resultado antes da revelação
cp "$C/conf" "$FIX/conf.bak"
printf 'FREEZE_TIME=%s\n' "$T0" >> "$C/conf"
calla POST "$(jq -cn --argjson c "$CFGJ" '{action:"apply", config:$c}')"
hk '.error.code == "freeze_locked" and (.error.release_at > 0)' "congelado e antes do fim+1min: recalcular o PUBLICADO = 409 freeze_locked"
calla POST '{"action":"withdraw","login":"teamrj03","reason":"x"}'
hk '.error.code == "freeze_locked"' "…override no publicado também"
calla POST '{"action":"unpublish","stage":"final-br"}'
hk '.status == "draft"' "despublicar é livre"
calla POST '{"action":"publish","stage":"final-br"}'
hk '.error.code == "freeze_locked"' "publicar congelado antes do fim+1min = 409 freeze_locked (sem saída)"
calla POST '{"action":"publish","stage":"final-br","force_frozen":true}'
hk '.error.code == "freeze_locked"' "…nem com force_frozen"
calla POST "$(jq -cn --argjson c "$CFGJ" '{action:"apply", config:$c}')"
hk '.applied == true' "rascunho segue recalculável com o freeze (ninguém vê)"
sed -i "s/^CONTEST_END=.*/CONTEST_END=$((NOW - 120))/" "$C/conf"
calla POST '{"action":"publish","stage":"final-br"}'
hk '.error.code == "board_frozen" and .error.can_force == true' "depois do fim+1min com o placar AINDA congelado = 409 board_frozen (pede confirmação)"
calla POST '{"action":"publish","stage":"final-br","force_frozen":true}'
hk '.status == "published"' "…e com force_frozen publica"
cp "$FIX/conf.bak" "$C/conf"
calla POST '{"action":"unpublish","stage":"final-br"}'; calla POST '{"action":"publish","stage":"final-br"}'
hk '.status == "published"' "sem freeze: publica direto (como antes)"

# a composição não depende do motor pular o time: linha do motor de quem tem override add/exclude é descartada
CLJQ="$(_DIR="$ROOT/api/v1" bash -c 'source "$_DIR/lib/classify.sh"; printf "%s" "$CL_JQ"')"
rel="$(jq -c "$CLJQ"'cl_relation(.result) | map(.login + ":" + .via + (if .manual then ":m" else "" end))' <<<'{"result":{"classified":[
  {"login":"a","via":"regra1"},{"login":"b","via":"regra1"},{"login":"c","via":"regra2"}]},
  "overrides":[{"id":"ov-1","op":"add","login":"a","reason":"x"},{"id":"ov-2","op":"exclude","login":"c","reason":"y"}]}')"
eqk "$rel" '["b:regra1","a:manual:m"]' "composição: motor que não pulou o add/exclude não duplica o time"

# ---- parte 6: relatório com DOIS estágios publicados (um chip por estágio; via sem rótulo; ext: só na página)
jq -c '.stages += [{id:"pda", status:"published", name:"Campeonato LATAM", chip:"PDA", via_order:["p1"],
  labels:{p1:{pt:"Passo 1 — desempenho", en:"Step 1", es:"Paso 1", short:{pt:"passo 1", en:"step 1", es:"paso 1"}}},
  teams:{teamsp01:{via:"p1", place:1}, teamsp02:{via:"viaNova", place:2}}}]' "$C/classification.json" > "$C/cl.tmp" \
  && mv "$C/cl.tmp" "$C/classification.json"
REP3="$FIX/rep3"
bash "$ROOT/score/report-gen.sh" cb "$REP3" >/dev/null 2>&1 || { echo "report-gen falhou (parte 6)"; exit 1; }
row="$(grep -o '<tr[^>]*data-login="teamsp01"[^>]*>.*' "$REP3/index.html" | head -1)"
[[ "$(grep -o 'class="qual-chip"' <<<"$row" | wc -l)" == 2 && "$row" == *"Final BR"* && "$row" == *"PDA"* ]] \
  && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU: dois chips (Final BR + PDA) na linha do sp01" >&2; }
rk '<h2>&#127891; PDA</h2>' "$REP3/classificados.html" "seção do estágio PDA"
rk 'Passo 1 — desempenho' "$REP3/classificados.html" "rótulo da via gravado no estágio"
rk '<h3>viaNova — 1</h3>' "$REP3/classificados.html" "via sem rótulo aparece pelo id"
rk 'Lugia' "$REP3/classificados.html" "time externo (ext:) na página"
grep -q 'Lugia' "$REP3/index.html" && { FAIL=$((FAIL+1)); echo "FALHOU: time externo no placar" >&2; } || PASS=$((PASS+1))
grep -q 'comitê (regra 3)\|↑BR' "$REP3/classificados.html" && { FAIL=$((FAIL+1)); echo "FALHOU: texto antigo (↑BR) na página" >&2; } || PASS=$((PASS+1))

echo "smoke-classify-br: PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
