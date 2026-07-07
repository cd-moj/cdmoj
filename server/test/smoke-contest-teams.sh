#!/bin/bash
# TIMES por-usuário (carga única enriquecida): o NOME é campo ÚNICO (fullname = nome do
# time); users-bulk com country/region/univ* grava o `.team` do account.json (que o placar
# TXT reflete — coluna team = fullname via fallback); /contest/teams serve o diretório p/
# o placar; admin/teams set (fullname + campos) + materialize; team-assets (foto/brasão) +
# rotas team-photo/team-logo (gate do placar: SECRETO exige sessão); staff-filters com
# region:<nome> -> staff_can_see; badges preferem .team.region; users_from -> 409.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX"
NOW="$EPOCHSECONDS"
PNG1='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='

C="$FIX/tm"; mkdir -p "$C/var"
{ printf 'CONTEST_ID=tm\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nUSER_STORE=v2\n' $((NOW-100)) $((NOW+7200))
  printf "PROBS=(f0 col/pa 'Prob A' A 'col#pa')\n"; } > "$C/conf"
fx_user "$C" tm.admin p "Admin"
fx_user "$C" sede1.staff s "Balcao 1"
printf '[{"name":"Norte","regex":"^nunca-casa-"},{"name":"Sul","regex":"^tb-nao-"}]\n' > "$C/regions.json"
printf '{"rules":[{"regex":"^mat-","country":"AR","school":"UBA","school_full":"Universidad de Buenos Aires"}]}\n' > "$C/teams-meta.json"

mktok(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' tm "$1" "$1" "$NOW" > "$SESS/$2"; }
mktok tm.admin t-adm; mktok sede1.staff t-stf

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${4:-}" \
    HTTP_AUTHORIZATION="${3:+Bearer $3}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${5:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${OUT:0:220}"; ((fail++)); fi; }

echo "== users-bulk com campos de time (carga única; nome = fullname, campo ÚNICO) =="
call /contest/admin/users-bulk POST t-adm 'contest=tm' '{"users":[
  {"login":"alfa","password":"x","fullname":"Time Alfa","country":"BR-DF","region":"Norte","univ_short":"UnB","univ_full":"Universidade de Brasília"},
  {"login":"beta","password":"y","fullname":"Time Beta","country":"BR-SP","region":"Sul"},
  {"login":"mat-gama","password":"z","fullname":"Time Gama"}]}'
ck "3 criados"                 '[[ "$(jq -r .counts.created <<<"$BODY")" == 3 ]]'
ck ".team gravado (alfa), SEM name" '[[ "$(jq -r .team.flag "$C/users/alfa/account.json")" == "BR-DF" && "$(jq -r .team.region "$C/users/alfa/account.json")" == "Norte" && "$(jq -r '"'"'.team|has("name")'"'"' "$C/users/alfa/account.json")" == "false" ]]'
ck "sem team quando não veio (gama)" '[[ "$(jq -r '"'"'has("team")'"'"' "$C/users/mat-gama/account.json")" == "false" ]]'
# update mescla só o presente (não apaga o resto; linha parcial NÃO clobbera o nome)
call /contest/admin/users-bulk POST t-adm 'contest=tm' '{"users":[{"login":"alfa","region":"Sul"}],"on_existing":"update"}'
ck "update mescla região"      '[[ "$(jq -r .team.region "$C/users/alfa/account.json")" == "Sul" && "$(jq -r .team.flag "$C/users/alfa/account.json")" == "BR-DF" ]]'
ck "update parcial preserva o nome" '[[ "$(jq -r .fullname "$C/users/alfa/account.json")" == "Time Alfa" ]]'
call /contest/admin/teams POST t-adm 'contest=tm' '{"set":{"alfa":{"region":"Norte"}}}'   # volta pela ferramenta certa

echo "== placar TXT reflete flag/univ do .team e o NOME (fullname) na coluna team =="
bash "$ROOT/score/build.sh" tm >/dev/null 2>&1
ck "linha da alfa: BR-DF:UnB:Time Alfa" 'grep -q "^BR-DF:alfa:UnB:Time Alfa:Universidade de Brasília:" "$C/var/placar.txt"'

echo "== GET /contest/teams (diretório p/ o placar) =="
call /contest/teams GET '' 'contest=tm'
ck "público, com alfa"         '[[ "$(jq -r .teams.alfa.flag <<<"$BODY")" == "BR-DF" && "$(jq -r .teams.alfa.region <<<"$BODY")" == "Norte" ]]'
ck "privilegiados fora"        '[[ "$(jq -r '"'"'.teams | has("tm.admin")'"'"' <<<"$BODY")" == "false" ]]'
ck "sem foto ainda"            '[[ "$(jq -r .teams.alfa.has_photo <<<"$BODY")" == "false" ]]'

echo "== admin/teams set (fullname = nome único) + materialize =="
call /contest/admin/teams POST t-adm 'contest=tm' '{"set":{"beta":{"fullname":"Beta Renomeado","univ_short":"USP"},"naoexiste":{"region":"X"}}}'
ck "set salva 1, pula 1"       '[[ "$(jq -r .saved <<<"$BODY")" == 1 && "$(jq -r .skipped[0] <<<"$BODY")" == "naoexiste" ]]'
ck "fullname trocado + univ setada" '[[ "$(jq -r .fullname "$C/users/beta/account.json")" == "Beta Renomeado" && "$(jq -r .team.univ_short "$C/users/beta/account.json")" == "USP" ]]'
call /contest/admin/teams POST t-adm 'contest=tm' '{"set":{"beta":{"fullname":"","univ_short":"USP2"}}}'
ck "fullname vazio é ignorado (nome não fica em branco)" '[[ "$(jq -r .fullname "$C/users/beta/account.json")" == "Beta Renomeado" && "$(jq -r .team.univ_short "$C/users/beta/account.json")" == "USP2" ]]'
call /contest/admin/teams POST t-adm 'contest=tm' '{"action":"materialize"}'
ck "materialize preenche gama (teams-meta ^mat-)" '[[ "$(jq -r .filled[\"mat-gama\"].flag <<<"$BODY")" == "AR" && "$(jq -r .team.univ_short "$C/users/mat-gama/account.json")" == "UBA" ]]'
ck "materialize não sobrescreve alfa" '[[ "$(jq -r .team.flag "$C/users/alfa/account.json")" == "BR-DF" ]]'

echo "== team-assets (foto/brasão) + rotas de leitura =="
call /contest/admin/team-assets POST t-adm 'contest=tm' "{\"kind\":\"photo\",\"filename\":\"ZETA.jpg\",\"file_b64\":\"$PNG1\"}"
ck "upload por nome sem usuário -> 404" '[[ "$OUT" == *"Status: 404"* ]]'
call /contest/admin/team-assets POST t-adm 'contest=tm' "{\"kind\":\"photo\",\"filename\":\"Alfa.png\",\"file_b64\":\"$PNG1\"}"
ck "upload case-insensitive casa alfa" '[[ "$(jq -r .login <<<"$BODY")" == "alfa" && -s "$C/users/alfa/photo.png" ]]'
call /contest/admin/team-assets POST t-adm 'contest=tm' "{\"kind\":\"logo\",\"filename\":\"beta.png\",\"file_b64\":\"$PNG1\"}"
ck "brasão da beta salvo"      '[[ -s "$C/users/beta/logo.png" ]]'
call /contest/team-photo GET '' 'contest=tm&user=alfa'
ck "team-photo serve PNG"      '[[ "$OUT" == *"image/png"* ]]'
call /contest/team-logo GET '' 'contest=tm&user=alfa'
ck "sem brasão -> 404"         '[[ "$OUT" == *"Status: 404"* ]]'
call /contest/teams GET '' 'contest=tm'
ck "has_photo/has_logo refletem" '[[ "$(jq -r .teams.alfa.has_photo <<<"$BODY")" == "true" && "$(jq -r .teams.beta.has_logo <<<"$BODY")" == "true" ]]'
call /contest/admin/team-assets POST t-adm 'contest=tm' '{"action":"delete","kind":"photo","login":"alfa"}'
ck "delete remove"             '[[ ! -e "$C/users/alfa/photo.png" ]]'

echo "== staff por sede (region:<nome>) =="
call /contest/admin/staff-filters POST t-adm 'contest=tm' '{"filters":{"sede1.staff":["region:Norte"]}}'
ck "filtro salvo"              '[[ "$(jq -r .saved <<<"$BODY")" == "true" ]]'
ck "staff vê aluno da sede"    '(cd "$ROOT/api/v1" && CONTESTSDIR="$FIX" bash -c "source lib/common.sh; source lib/auth.sh; source lib/users.sh; source lib/print.sh; SESSION_LOGIN=sede1.staff; staff_can_see tm sede1.staff alfa")'
ck "staff NÃO vê fora da sede" '! (cd "$ROOT/api/v1" && CONTESTSDIR="$FIX" bash -c "source lib/common.sh; source lib/auth.sh; source lib/users.sh; source lib/print.sh; SESSION_LOGIN=sede1.staff; staff_can_see tm sede1.staff beta")'

echo "== badges preferem .team.region =="
call /contest/badges GET t-adm 'contest=tm'
ck "região da alfa = Norte (explícita)" '[[ "$(jq -r '"'"'.users[]|select(.login=="alfa")|.region'"'"' <<<"$BODY")" == "Norte" ]]'

echo "== gate secreto nas rotas de foto =="
printf 'SECRET=1\n' >> "$C/conf"
call /contest/team-photo GET '' 'contest=tm&user=beta'
ck "secreto sem sessão -> 401" '[[ "$OUT" == *"Status: 401"* ]]'
call /contest/teams GET '' 'contest=tm'
ck "teams secreto sem sessão -> 401" '[[ "$OUT" == *"Status: 401"* ]]'
sed -i '/^SECRET=1$/d' "$C/conf"

echo "== users_from -> 409 =="
C2="$FIX/tm2"; mkdir -p "$C2/var" "$C2/users"
printf 'CONTEST_ID=tm2\nCONTEST_TYPE=icpc\nUSERS_FROM=tm\nUSER_STORE=v2\n' > "$C2/conf"
mkdir -p "$C2/users/tm2.admin"; cp "$C/users/tm.admin/account.json" "$C2/users/tm2.admin/account.json" 2>/dev/null || true
fx_user "$C2" tm2.admin p "Admin2"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' tm2 tm2.admin Admin2 "$NOW" > "$SESS/t-adm2"
call /contest/admin/teams POST t-adm2 'contest=tm2' '{"action":"materialize"}'
ck "admin/teams compartilhado -> 409" '[[ "$OUT" == *"Status: 409"* && "$(jq -r .error.code <<<"$BODY")" == "shared_users" ]]'
call /contest/admin/team-assets POST t-adm2 'contest=tm2' "{\"kind\":\"photo\",\"filename\":\"x.png\",\"file_b64\":\"$PNG1\"}"
ck "team-assets compartilhado -> 409" '[[ "$OUT" == *"Status: 409"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
