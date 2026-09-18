#!/bin/bash
# TL NÃO PODE SUMIR DO CONTEST DEPOIS DE "EDITEI + RECALIBREI".
# Relato (Daniel Saad, 2026-09-18): `saad-problems#metro` calibrado, a gestão mostrava o TL, e o contest
# não. Causa: o /contest/problems compara o checksum de run/tl com o `tl_checksum` do ÍNDICE DE DONOS
# (rota de contest não abre pacote), e o índice só se refaz em background (30 min+; naquele dia, 80 min).
# Entre a recalibração e o índice alcançar, os dois não batiam ⇒ time_limits:{}. Correção: o
# /judge/tl-report — que JÁ calcula o checksum real do pacote — CARIMBA o valor fresco
# (treino/var/tl-checksum-fresh.json), o carimbo vence o índice, e o problem_commit o apaga.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS"' EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$PROBS" TL_STORE_DIR="$RUN/tl" \
       WORKER_TOKEN_FILE="$RUN/secrets/worker.token" MOJ_JOBS_SYNC=1
mkdir -p "$RUN/tl" "$RUN/secrets" "$FIX/treino/var"; printf 'mojw_segredo' > "$WORKER_TOKEN_FILE"
NOW="$EPOCHSECONDS"; T="$FIX/treino"
printf 'CONTEST_ID=treino\nCONTEST_END=%s\n' "$((NOW+86400))" > "$T/conf"
echo '{"col":{"members":["autor"],"admins":[],"public_allowed":false,"title":"Col"}}' > "$T/var/orgs.json"
for p in pa pb; do P="$PROBS/col/$p"; mkdir -p "$P/sols/good" "$P/tests/input"
  printf 'CALIBRATIONTL=5\n' > "$P/conf"; printf '{"owner":"autor","public":false,"display_title":"%s"}\n' "$p" > "$P/.moj-meta.json"
  printf 'int main(){return 0;}\n' > "$P/sols/good/sol.c"; printf '1\n' > "$P/tests/input/t1"
  ( cd "$P" && git init -q 2>/dev/null && git add -A 2>/dev/null && git -c user.name=t -c user.email=t@t commit -qm init 2>/dev/null ); done
source "$ROOT/api/v1/lib/common.sh" 2>/dev/null; _LIBDIR="$ROOT/api/v1/lib"; source "$_LIBDIR/tl-store.sh"; source "$_LIBDIR/problems.sh"
REAL="$(pkg_tl_checksum "$PROBS/col/pa" 'col#pa')"; REALB="$(pkg_tl_checksum "$PROBS/col/pb" 'col#pb')"
OLD=aaaaaaaaaaaaaaaa
idx(){ # <cks-de-pa> — o índice de donos como o gerador o deixaria
  jq -cn --arg a "$1" --arg b "$REALB" '{problems:[
    {id:"col#pa",owner:"autor",repo:"col",prob:"pa",title:"pa",public:false,collaborators:[],collections:["col"],tl_checksum:$a},
    {id:"col#pb",owner:"autor",repo:"col",prob:"pb",title:"pb",public:false,collaborators:[],collections:["col"],tl_checksum:$b}]}' > "$T/var/problem-owners.json"; }
idx "$OLD"
C="$FIX/ct"; mkdir -p "$C/var" "$C/enunciados"
{ printf 'CONTEST_ID=ct\nCONTEST_NAME=Prova\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-600))" "$((NOW+3600))"
  printf "PROBS=( x col/pa Alfa A 'col#pa' x col/pb Beta B 'col#pb' )\n"; } > "$C/conf"
fx_user "$C" time1 s "Time 1"; printf 'CONTEST=ct\nLOGIN=time1\nUSERFULLNAME=T\nLOGINAT=%s\n' "$NOW" > "$SESS/tk"
tl_store_record juiz1 'col#pb' "$REALB" '{"c":"0.200","default":"0.200"}' >/dev/null

pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:240}"; ((fail++)); fi; }
probs(){ rm -f "$C/var/"problems-cache.* 2>/dev/null; OUT="$(PATH_INFO=/contest/problems REQUEST_METHOD=GET QUERY_STRING=contest=ct HTTP_AUTHORIZATION="Bearer tk" bash "$ROUTER" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
tlof(){ jq -c --arg l "$1" '.problems[]|select(.short_name==$l)|.time_limits' <<<"$BODY"; }
report(){ OUT="$(PATH_INFO=/judge/tl-report REQUEST_METHOD=POST HTTP_AUTHORIZATION="Bearer mojw_segredo" bash "$ROUTER" <<<"$1" 2>/dev/null)"
  RBODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
FRESH="$T/var/tl-checksum-fresh.json"

echo "== o caso do relato: índice com checksum VELHO, juiz reporta a calibração do pacote ATUAL =="
report "$(jq -cn --arg c "$REAL" '{host:"juiz1", id:"col#pa", checksum:$c, tl:{c:"0.100", default:"0.100"}}')"
ck "tl-report gravado"                         '[[ "$(jq -r .recorded <<<"$RBODY")" == true ]]'
probs
ck "contest mostra o TL NA HORA (sem esperar o índice)" '[[ "$(tlof A)" == *"0.100"* ]]'
ck "…e o outro problema segue normal"          '[[ "$(tlof B)" == *"0.200"* ]]'
ck "carimbo gravado só p/ o id reportado"      '[[ "$(jq -c . "$FRESH")" == "{\"col#pa\":\"$REAL\"}" ]]'
M="$(owners_merged)"
ck "owners_merged (Painel) já vê o checksum novo" '[[ "$(jq -r ".problems[]|select(.id==\"col#pa\")|.tl_checksum" <<<"$M")" == "$REAL" ]]'
ck "…sem tocar nos outros campos nem nos outros ids" '[[ "$(jq -r ".problems[]|select(.id==\"col#pb\")|.tl_checksum" <<<"$M")" == "$REALB" && "$(jq -r ".problems|length" <<<"$M")" == 2 && "$(jq -r ".problems[]|select(.id==\"col#pa\")|.owner" <<<"$M")" == autor ]]'

echo "== report OBSOLETO (juiz com pacote velho) não carimba =="
rm -f "$FRESH"
report '{"host":"juiz2","id":"col#pa","checksum":"bbbbbbbbbbbbbbbb","tl":{"c":"9"}}'
ck "stale:true e nenhum carimbo"               '[[ "$(jq -r .stale <<<"$RBODY")" == true && ! -s "$FRESH" ]]'

echo "== o índice ALCANÇA: o carimbo é podado =="
tl_fresh_set 'col#pa' "$REAL"; idx "$REAL"; tl_fresh_prune
ck "carimbo igual ao índice sai"               '[[ "$(jq -c . "$FRESH" 2>/dev/null)" == "{}" || ! -s "$FRESH" ]]'
probs; ck "TL continua (agora pelo índice)"    '[[ "$(tlof A)" == *"0.100"* ]]'

echo "== o PACOTE MUDA: problem_commit apaga o carimbo (volta a valer o índice) =="
idx "$OLD"; tl_fresh_set 'col#pa' "$REAL"; tl_fresh_set 'col#pb' "$REALB"
printf '2\n' > "$PROBS/col/pa/tests/input/t2"; problem_commit "$PROBS/col/pa" autor "edita pa" >/dev/null 2>&1
ck "carimbo de pa apagado, o de pb fica"       '[[ "$(jq -c . "$FRESH")" == "{\"col#pb\":\"$REALB\"}" ]]'

echo "== commit que NÃO toca no que o checksum cobre (enunciado) mantém o carimbo =="
NEWB="$(pkg_tl_checksum "$PROBS/col/pb" 'col#pb')"; tl_fresh_set 'col#pb' "$NEWB"
mkdir -p "$PROBS/col/pb/docs"; printf '# enunciado\n' > "$PROBS/col/pb/docs/enunciado.md"; problem_commit "$PROBS/col/pb" autor "edita enunciado" >/dev/null 2>&1
ck "carimbo de pb sobrevive a edição só de enunciado" '[[ "$(jq -r ".[\"col#pb\"]" "$FRESH")" == "$NEWB" ]]'

echo "== arquivo de carimbos ausente/corrompido não derruba nada =="
printf 'lixo{' > "$FRESH"; probs
ck "contest responde com carimbo corrompido"   '[[ "$OUT" == *"Status: 200"* && "$(tlof B)" == *"0.200"* ]]'
M="$(owners_merged)"; ck "owners_merged responde com carimbo corrompido" '[[ "$(jq -r ".problems|length" <<<"$M")" == 2 ]]'
tl_fresh_set 'col#pa' "$REAL"; ck "set por cima de lixo recomeça limpo" '[[ "$(jq -c . "$FRESH")" == "{\"col#pa\":\"$REAL\"}" ]]'
rm -f "$FRESH"; probs; ck "contest responde sem o arquivo" '[[ "$OUT" == *"Status: 200"* ]]'
echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
