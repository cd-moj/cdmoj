#!/bin/bash
# smoke-regions-route.sh — GET/POST /contest/admin/regions (a regra única de sedes pela API) e a regex
# conferida no salvar (config.sh e a criação). Afirma:
#   • GET: árvore, sig, resumo (contagens por flag e membros por nó); ?login= diz a sede e os nós;
#   • regex fora do subconjunto seguro = 422 regions_invalid com error.nodes (caminho + código), nada gravado —
#     no /contest/admin/regions, no config.sh e na criação;
#   • dry_run: a prévia com a árvore e as atribuições propostas, SEM gravar árvore nem conta;
#   • expect_sig velho = 409 regions_changed; o certo grava árvore + sedes + REGIONS_MODE e liga `sedes`;
#   • atribuir: conta própria (merge), "" tira, login fora do contest/papel = failed com código;
#   • contest COMPARTILHADO com inscrição: membro de time → o TIME (no roster) e a sede SOBREVIVE a uma
#     mudança no roster (entra outro membro); individual idem; quem só tem dir ganha overlay;
#   • competidor = 403; juiz-chefe lê.
set -u
TD="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; ROOT="$TD/.."; ROUTER="$ROOT/api/v1/router.sh"
source "$TD/fixture.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" SCOREDIR="$ROOT/score"
NOW="$(date +%s)"
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-x}" \
    MOJ_JOBS_SYNC=1 bash "$ROUTER" <<<"${3:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
st(){ sed -n 's/^Status: \([0-9]*\).*/\1/p' <<<"$OUT" | head -1; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: $(st) ${BODY:0:300}"; ((fail++)); fi; }
mkses(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=1\n' "$2" "$3" "$3" > "$SESS/$1"; }

T="$FIX/treino"; mkdir -p "$T/var/jsons"; printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\n' > "$T/conf"
for u in m1 m2 m3 i1 d1 ninguem; do fx_user "$T" "$u" s "Nome $u"; done

echo "== contest de contas próprias =="
C="$FIX/sr"; mkdir -p "$C/users" "$C/var"
printf 'CONTEST_ID=sr\nCONTEST_NAME=Sedes\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-60))" "$((NOW+3600))" > "$C/conf"
for u in a1 a2 b1 sr.admin sr.cjudge; do fx_user "$C" "$u" s "Nome $u"; done
echo '[{"name":"A","regex":"^a"}]' > "$C/regions.json"
mkses adm sr sr.admin; mkses chief sr sr.cjudge; mkses comp sr a1
call /contest/admin/regions GET '' adm 'contest=sr'
SIG="$(J .sig)"
ck "GET: árvore, sig, resumo (2 pela regex, 1 sem sede)" '[[ "$(st)" == 200 && "$(J .tree[0].name)" == A && -n "$SIG" && "$(J .summary.counts.regex)" == 2 && "$(J .summary.counts.none)" == 1 && "$(J ".summary.nodes[0].members")" == 2 ]]'
call /contest/admin/regions GET '' adm 'contest=sr&login=a2'
ck "GET ?login=a2: sede A (r), nós [A]" '[[ "$(J .site.name)" == A && "$(J .flag)" == r && "$(J "[.nodes[].name] | join(\",\")")" == A ]]'
call /contest/admin/regions GET '' adm 'contest=sr&login=zz'; ck "GET ?login= de quem não está: 404" '[[ "$(st)" == 404 ]]'
call /contest/admin/regions GET '' chief 'contest=sr'; ck "juiz-chefe lê" '[[ "$(st)" == 200 ]]'
call /contest/admin/regions GET '' comp 'contest=sr'; ck "competidor: 403" '[[ "$(st)" == 403 ]]'
call /contest/admin/regions POST '{"tree":[]}' chief 'contest=sr'; ck "juiz-chefe não grava: 403" '[[ "$(st)" == 403 ]]'

T0="$(md5sum < "$C/regions.json")"
call /contest/admin/regions POST '{"tree":[{"name":"A","regex":"^a","subregions":[{"name":"A1","regex":"\\bx"}]}]}' adm 'contest=sr'
ck "regex fora do subconjunto: 422 regions_invalid com o caminho e o código; nada gravado" '[[ "$(st)" == 422 && "$(J .error.code)" == regions_invalid && "$(J ".error.nodes[0].path")" == "A › A1" && "$(J ".error.nodes[0].err")" == word_boundary && "$(md5sum < "$C/regions.json")" == "$T0" ]]'
call /contest/admin/regions POST '{"tree":{"name":"x"}}' adm 'contest=sr'; ck "forma errada: 422" '[[ "$(st)" == 422 ]]'

A0="$(md5sum < "$C/users/a2/account.json")"
call /contest/admin/regions POST '{"dry_run":true,"tree":[{"name":"A","regex":"^a"},{"name":"B","regex":"^b"}],"assign":[{"login":"a2","region":"B"},{"login":"zz","region":"B"}]}' adm 'contest=sr'
ck "dry_run: a prévia conta B com b1 (regex) + a2 (gravada); zz em failed" '[[ "$(st)" == 200 && "$(J .dry_run)" == true && "$(J "[.summary.nodes[] | select(.name == \"B\") | .members][0]")" == 2 && "$(J ".failed[0].code")" == login_not_in_contest ]]'
ck "…e NADA foi gravado (árvore e conta)" '[[ "$(md5sum < "$C/regions.json")" == "$T0" && "$(md5sum < "$C/users/a2/account.json")" == "$A0" ]]'

call /contest/admin/regions POST '{"expect_sig":"velho","tree":[{"name":"A","regex":"^a"}]}' adm 'contest=sr'
ck "expect_sig velho: 409 regions_changed com o sig atual" '[[ "$(st)" == 409 && "$(J .error.code)" == regions_changed && "$(J .error.sig)" == "$SIG" ]]'
call /contest/admin/regions POST "{\"expect_sig\":\"$SIG\",\"mode\":\"rules\",\"tree\":[{\"name\":\"A\",\"regex\":\"^a\"},{\"name\":\"B\",\"regex\":\"^b\"}],\"assign\":[{\"login\":\"a2\",\"region\":\"b\"},{\"login\":\"sr.cjudge\",\"region\":\"A\"},{\"login\":\"zz\",\"region\":\"A\"}]}" adm 'contest=sr'
ck "grava: árvore nova, a2 → B (gravada, caixa não importa), REGIONS_MODE=rules" '[[ "$(st)" == 200 && "$(J .saved)" == true && "$(jq length "$C/regions.json")" == 2 && "$(jq -r .team.region "$C/users/a2/account.json")" == b && "$(grep -c "^REGIONS_MODE=rules" "$C/conf")" == 1 ]]'
ck "failed: conta de papel (role_login) e quem não está (login_not_in_contest)" '[[ "$(J "[.failed[] | .code] | sort | join(\",\")")" == "login_not_in_contest,role_login" && "$(J ".assigned[0].login")" == a2 ]]'
ck "módulo sedes ligado; sig novo; resumo: a2 gravada (x)" '[[ "$(J .sig)" != "$SIG" && "$(J .summary.counts.explicit)" == 1 ]] && grep -q sedes "$C/var/modules" 2>/dev/null || grep -rq sedes "$C/conf" "$C/var/" 2>/dev/null'
call /contest/admin/regions GET '' adm 'contest=sr&login=a2'; ck "a2 agora em B (x)" '[[ "$(J .site.name)" == B && "$(J .flag)" == x ]]'
call /contest/admin/regions POST '{"assign":[{"login":"a2","region":""}]}' adm 'contest=sr'
ck "\"\" tira a sede gravada: a2 volta p/ A pela regex" '[[ "$(jq -r ".team.region // \"-\"" "$C/users/a2/account.json")" == - ]] && call /contest/admin/regions GET "" adm "contest=sr&login=a2" && [[ "$(J .site.name)" == A && "$(J .flag)" == r ]]'

echo "== Central: checagem regions =="
call /contest/admin/preflight GET '' adm 'contest=sr'
ck "Central: sedes ok (todos os times com sede), pt/en/es" '[[ "$(J ".checks[] | select(.id == \"regions\") | .level")" == ok && -n "$(J ".checks[] | select(.id == \"regions\") | .detail_es")" ]]'
fx_user "$C" zz9 s "Nome zz9" >/dev/null
call /contest/admin/preflight GET '' adm 'contest=sr'
ck "Central: time sem sede vira aviso (1 de 4)" '[[ "$(J ".checks[] | select(.id == \"regions\") | .level")" == warn && "$(J ".checks[] | select(.id == \"regions\") | .detail")" == *"1 de 4 time(s) sem sede"* ]]'

echo "== config.sh e criação também conferem a regex =="
call /contest/admin/config POST '{"regions":[{"name":"X","regex":"(?=x)"}]}' adm 'contest=sr'
ck "config.sh: 422 regions_invalid com error.nodes (group_ext)" '[[ "$(st)" == 422 && "$(J ".error.nodes[0].err")" == group_ext && "$(jq length "$C/regions.json")" == 2 ]]'

echo "== compartilhado com inscrição: o roster guarda a sede =="
S="$FIX/sh"; mkdir -p "$S/users" "$S/var"
printf 'CONTEST_ID=sh\nCONTEST_NAME=Sh\nCONTEST_TYPE=icpc\nUSERS_FROM=treino\nCONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW+3600))" "$((NOW+7200))" > "$S/conf"
fx_user "$S" sh.admin s Admin; mkses sadm sh sh.admin
echo '[{"name":"Norte","regex":"^zz"},{"name":"Sul"},{"name":"Leste"}]' > "$S/regions.json"
call /contest/admin/registrations POST '{"action":"enable"}' sadm 'contest=sh'
call /contest/admin/registrations POST '{"action":"team-add","name":"Time X","members":["m1","m2"]}' sadm 'contest=sh'
TX="$(jq -r '.teams | keys[0]' "$S/registrations.json")"
call /contest/admin/registrations POST '{"action":"add","login":"i1"}' sadm 'contest=sh'
mkdir -p "$S/users/d1"
ck "(fixture: time $TX e individual i1 inscritos, d1 só com dir)" '[[ -n "$TX" && -f "$S/users/$TX/account.json" && -f "$S/users/i1/account.json" && ! -f "$S/users/d1/account.json" ]]'
call /contest/admin/regions POST '{"assign":[{"login":"m1","region":"Sul"},{"login":"i1","region":"Leste"},{"login":"d1","region":"Norte"},{"login":"ninguem","region":"Sul"}]}' sadm 'contest=sh'
ck "membro m1 → o TIME ($TX); i1; d1; ninguem (nunca entrou) = login_not_in_contest" '[[ "$(st)" == 200 && "$(J ".assigned[] | select(.login == \"m1\") | .target")" == "$TX" && "$(J ".failed[0].login")" == ninguem && "$(J ".failed[0].code")" == login_not_in_contest ]]'
ck "o roster guarda: teams[$TX].region = Sul, entries[i1].region = Leste" '[[ "$(jq -r --arg t "$TX" ".teams[\$t].region" "$S/registrations.json")" == Sul && "$(jq -r ".entries.i1.region" "$S/registrations.json")" == Leste ]]'
ck "o materialize leva ao account: time → Sul, i1 → Leste; d1 ganhou overlay com Norte" '[[ "$(jq -r .team.region "$S/users/$TX/account.json")" == Sul && "$(jq -r .team.region "$S/users/i1/account.json")" == Leste && "$(jq -r .team.region "$S/users/d1/account.json")" == Norte && "$(jq -r ".password // \"\"" "$S/users/d1/account.json")" == "" ]]'
call /contest/admin/registrations POST "{\"action\":\"team-rm\",\"team\":\"$TX\"}" sadm 'contest=sh' >/dev/null
call /contest/admin/registrations POST '{"action":"team-add","name":"Time X","members":["m1","m2","m3"]}' sadm 'contest=sh'
TX2="$(jq -r '.teams | keys[0]' "$S/registrations.json")"
call /contest/admin/regions POST '{"assign":[{"login":"m3","region":"Sul"}]}' sadm 'contest=sh'
call /contest/admin/registrations POST '{"action":"materialize"}' sadm 'contest=sh'
ck "roster muda (re-materializa tudo): a sede do time e a do individual SOBREVIVEM" '[[ "$(jq -r .team.region "$S/users/$TX2/account.json")" == Sul && "$(jq -r .team.region "$S/users/i1/account.json")" == Leste ]]'
call /contest/admin/regions GET '' sadm 'contest=sh&login=i1'; ck "GET ?login=i1 → Leste (x, nó sem regex)" '[[ "$(J .site.name)" == Leste && "$(J .flag)" == x ]]'
call /contest/admin/regions POST '{"assign":[{"login":"i1","region":""}]}' sadm 'contest=sh'
ck "\"\" no inscrito limpa o roster e o overlay" '[[ "$(jq -r ".entries.i1.region" "$S/registrations.json")" == "" && "$(jq -r ".team.region // \"-\"" "$S/users/i1/account.json")" == - ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail > 0 ? 1 : 0 ))
