#!/bin/bash
# Testa criação de contest: permissão (lista/threshold/deny), criação (banco/por-id/custom),
# validações, template, import de tar, e moderação (listar/remover) do admin.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
T="$FIX/treino"; mkdir -p "$T/var/jsons" "$T/controle"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\n' > "$T/conf"
printf 'boss.admin:p:Boss\nregular:s:Regular User\nnobody:s:No Body\nsolver:s:Sol Ver\nbanned:s:Ban Ned\n' > "$T/passwd"
# sessões
printf 'CONTEST=treino\nLOGIN=boss.admin\nUSERFULLNAME=Boss\nLOGINAT=1\n' > "$SESS/adm"
printf 'CONTEST=treino\nLOGIN=regular\nUSERFULLNAME=Regular User\nLOGINAT=1\n' > "$SESS/reg"
printf 'CONTEST=treino\nLOGIN=nobody\nUSERFULLNAME=No Body\nLOGINAT=1\n' > "$SESS/nob"
printf 'CONTEST=treino\nLOGIN=solver\nUSERFULLNAME=Sol Ver\nLOGINAT=1\n' > "$SESS/sol"
printf 'CONTEST=treino\nLOGIN=banned\nUSERFULLNAME=Ban Ned\nLOGINAT=1\n' > "$SESS/ban"
# histórico: solver resolveu 2 problemas distintos
{ printf '1:solver:prob/a:C:Accepted,100p:1:h1\n'; printf '2:solver:prob/b:C:Accepted,100p:2:h2\n'
  printf '3:solver:prob/a:C:Wrong Answer:3:h3\n'; } > "$T/controle/history"
# banco: um problema com enunciado + dois com coleções (sorteio; sem var/problems.json => exercita o fallback FRIO)
printf '%s' '{"id":"bankprob","title":"Banco Prob","tags":["#x"],"statement_html_b64":"PGgxPm9pPC9oMT4="}' > "$T/var/jsons/bankprob.json"
printf '%s' '{"id":"apc#vet","title":"Vetores","tags":["#vetor"],"collections":["Prova 1","problemas-apc"]}' > "$T/var/jsons/apc#vet.json"
printf '%s' '{"id":"apc#mat","title":"Matrizes","tags":["#matriz"],"collections":["problemas-apc"]}' > "$T/var/jsons/apc#mat.json"
# índice de owners FRESCO na fixture — sem ele, ensure_owners_index regenerava do banco REAL
# da máquina (gen-problem-owners.sh) e o autocomplete respondia com problemas de verdade.
printf '%s' '{"problems":[
 {"id":"bankprob","title":"Banco Prob","owner":"someone","collaborators":[],"public":true},
 {"id":"apc#vet","title":"Vetores","owner":"someone","collaborators":[],"public":true},
 {"id":"apc#mat","title":"Matrizes","owner":"someone","collaborators":[],"public":true}
]}' > "$T/var/problem-owners.json"

NOW="$(date +%s)"; FUT=$(( NOW + 100000 )); PAST=$(( NOW - 100 ))
call(){ # <path> <method> <body> <token> <query>
  OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

echo "== permissão (default: ninguém além de admin) =="
call /treino/contest-create/permission GET '' nob
ck "nobody não pode"        '[[ "$(jq -r .can_create <<<"$BODY")" == false ]]'
call /treino/contest-create/permission GET '' adm
ck "admin pode"             '[[ "$(jq -r .can_create <<<"$BODY")" == true ]]'
ck "admin allowed_modes tem outro" '[[ "$(jq -r ".allowed_modes|index(\"outro\")" <<<"$BODY")" != null ]]'

echo "== admin define permissões (threshold 2, allow regular, deny banned) =="
call /treino/admin/contest-perms POST '{"threshold":2,"allow":["regular"],"deny":["banned"]}' adm
ck "salvou"                 '[[ "$(jq -r .saved <<<"$BODY")" == true ]]'
call /treino/admin/contest-perms GET '' adm
ck "GET reflete threshold"  '[[ "$(jq -r .perms.threshold <<<"$BODY")" == 2 ]]'

echo "== permissão por lista / threshold / deny =="
call /treino/contest-create/permission GET '' reg
ck "regular pode (allow)"   '[[ "$(jq -r .can_create <<<"$BODY")" == true ]]'
call /treino/contest-create/permission GET '' sol
ck "solver pode (threshold)" '[[ "$(jq -r .can_create <<<"$BODY")" == true && "$(jq -r .solved_count <<<"$BODY")" == 2 ]]'
call /treino/contest-create/permission GET '' ban
ck "banned bloqueado (deny)" '[[ "$(jq -r .can_create <<<"$BODY")" == false ]]'
call /treino/contest-create/permission GET '' nob
ck "nobody ainda não pode"  '[[ "$(jq -r .can_create <<<"$BODY")" == false ]]'

echo "== criação (banco + por-id + enunciado custom) =="
SPEC="{\"id\":\"test-create\",\"name\":\"Test Create\",\"mode\":\"icpc\",\"end\":$FUT,\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"B1\",\"letter\":\"A\"},{\"source\":\"cdmoj\",\"problem_id\":\"secret/foo\",\"name\":\"Foo\",\"letter\":\"B\"},{\"problem_id\":\"x/custom\",\"name\":\"Cust\",\"letter\":\"C\",\"statement_b64\":\"PHA+Y3VzdDwvcD4=\"}]}"
call /treino/contest-create/create POST "$SPEC" reg
ck "criou"                  '[[ "$(jq -r .contest_id <<<"$BODY")" == "test-create" ]]'
ck "devolveu senha admin"   '[[ -n "$(jq -r .admin_password <<<"$BODY")" && "$(jq -r .admin_login <<<"$BODY")" == "regular.admin" ]]'
ck "dir criado"             '[[ -d "$FIX/test-create" && -f "$FIX/test-create/conf" ]]'
ck "owner=regular"          '[[ "$(cat "$FIX/test-create/owner")" == regular ]]'
ck "created-by presente"    '[[ -f "$FIX/test-create/created-by" ]]'
ck "passwd tem regular.admin" 'grep -q "^regular.admin:" "$FIX/test-create/passwd"'
ck "conf: tipo icpc, 3 probs" '[[ "$( . "$FIX/test-create/conf"; echo "$CONTEST_TYPE ${#PROBS[@]}" )" == "icpc 15" ]]'
ck "enunciado do banco"     '[[ -f "$FIX/test-create/enunciados/bankprob.html" ]]'
ck "enunciado custom (x#custom)" '[[ -f "$FIX/test-create/enunciados/x#custom.html" ]]'

echo "== validações =="
call /treino/contest-create/create POST "{\"id\":\"treino\",\"name\":\"X\",\"mode\":\"icpc\",\"end\":$FUT,\"problems\":[{\"problem_id\":\"a/b\",\"name\":\"AB\"}]}" reg
ck "id reservado 409"       '[[ "$OUT" == *"Status: 409"* ]]'
call /treino/contest-create/create POST "$SPEC" reg
ck "id duplicado 409"       '[[ "$OUT" == *"Status: 409"* ]]'
call /treino/contest-create/create POST "{\"name\":\"\",\"mode\":\"icpc\",\"end\":$FUT,\"problems\":[{\"problem_id\":\"a/b\",\"name\":\"AB\"}]}" reg
ck "sem nome 422"           '[[ "$OUT" == *"Status: 422"* ]]'
call /treino/contest-create/create POST "{\"name\":\"Y\",\"mode\":\"icpc\",\"end\":$PAST,\"problems\":[{\"problem_id\":\"a/b\",\"name\":\"AB\"}]}" reg
ck "fim no passado 422"     '[[ "$OUT" == *"Status: 422"* ]]'
call /treino/contest-create/create POST "{\"name\":\"Y\",\"mode\":\"zzz\",\"end\":$FUT,\"problems\":[{\"problem_id\":\"a/b\",\"name\":\"AB\"}]}" reg
ck "modo inválido 422"      '[[ "$OUT" == *"Status: 422"* ]]'
call /treino/contest-create/create POST "{\"name\":\"Z\",\"mode\":\"icpc\",\"end\":$FUT,\"problems\":[{\"problem_id\":\"a/b\",\"name\":\"AB\"}]}" nob
ck "não-permitido 403"      '[[ "$OUT" == *"Status: 403"* ]]'

echo "== template =="
call /treino/contest-create/template GET '' reg
ck "template baixa JSON"    '[[ "$OUT" == *"Content-Disposition"* ]] && jq -e .problems <<<"$BODY" >/dev/null'

echo "== busca no banco =="
call /treino/contest-create/problems GET '' reg 'q=banco'
ck "acha bankprob"          '[[ "$(jq -r ".problems[0].id" <<<"$BODY")" == "bankprob" ]]'

echo "== coleções + sorteio por coleção =="
call /treino/contest-create/collections GET '' reg
ck "lista coleções com contagem" '[[ "$(jq -r ".collections[]|select(.collection==\"problemas-apc\").count" <<<"$BODY")" == 2 ]]'
ck "coleção com espaço presente" '[[ "$(jq -r ".collections[]|select(.collection==\"Prova 1\").count" <<<"$BODY")" == 1 ]]'
call /treino/contest-create/collections GET '' nob
ck "collections exige criador 403" '[[ "$OUT" == *"Status: 403"* ]]'
call /treino/contest-create/draw GET '' reg 'collections=%5B%22problemas-apc%22%5D&count=10&seed=7'
ck "draw por coleção: 2 candidatos" '[[ "$(jq -r .candidates <<<"$BODY")" == 2 && "$(jq -r .drawn <<<"$BODY")" == 2 ]]'
ck "draw ecoa collections"  '[[ "$(jq -rc .collections <<<"$BODY")" == "[\"problemas-apc\"]" ]]'
call /treino/contest-create/draw GET '' reg 'collections=%5B%22Prova%201%22%5D&count=10&seed=7'
ck "coleção com espaço: só apc#vet" '[[ "$(jq -r .candidates <<<"$BODY")" == 1 && "$(jq -r ".problems[0].id" <<<"$BODY")" == "apc#vet" ]]'
call /treino/contest-create/draw GET '' reg 'collections=%5B%22problemas-apc%22%5D&tags=%23matriz&count=10&seed=7'
ck "coleção E tag combinadas (AND)" '[[ "$(jq -r .candidates <<<"$BODY")" == 1 && "$(jq -r ".problems[0].id" <<<"$BODY")" == "apc#mat" ]]'
call /treino/contest-create/draw GET '' reg 'collections=notjson&count=10&seed=7'
ck "collections inválido = sem filtro" '[[ "$(jq -r .candidates <<<"$BODY")" == 3 ]]'
call /treino/contest-create/draw GET '' reg 'tags=%23x&count=10&seed=7'
ck "draw só por tag segue ok"  '[[ "$(jq -r .candidates <<<"$BODY")" == 1 && "$(jq -r ".problems[0].id" <<<"$BODY")" == "bankprob" ]]'

echo "== paridade do spec: toggles/priority/langs/pdf =="
PDF64="$(printf '%%PDF-fake' | base64 -w0)"
SPEC2="{\"id\":\"tog-c\",\"name\":\"Toggles\",\"mode\":\"icpc\",\"priority\":\"prova\",\"end\":$FUT,\"languages\":[\"C\",\"CPP\",\"bad lang!\"],\"show_log\":false,\"show_editor\":false,\"show_tl\":false,\"allow_backup\":false,\"allow_print\":false,\"score_anon\":true,\"manual_verdict\":true,\"allow_late\":true,\"login_ua_substring\":\"MOJBOX\",\"score_full_users\":[\"prof\",\"bad user\"],\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"B\",\"letter\":\"A\",\"languages\":[\"C\",\"PY3\"],\"statement_pdf_b64\":\"$PDF64\"}]}"
call /treino/contest-create/create POST "$SPEC2" reg
ck "criou tog-c"            '[[ "$(jq -r .contest_id <<<"$BODY")" == "tog-c" ]]'
CF="$FIX/tog-c/conf"
ck "conf: toggles não-default" 'grep -q "^SHOWLOG=0" "$CF" && grep -q "^SHOWEDITOR=0" "$CF" && grep -q "^SHOWTL=0" "$CF" && grep -q "^BACKUP=0" "$CF" && grep -q "^PRINT=0" "$CF"'
ck "conf: score_anon/manual/late" 'grep -q "^SCORE_ANON=1" "$CF" && grep -q "^MANUAL_VERDICT=1" "$CF" && grep -q "^ALLOWLATEUSER=y" "$CF"'
ck "conf: ua + score_full_users filtrado" '[[ "$( . "$CF"; echo "$LOGIN_UA_SUBSTRING/$SCORE_FULL_USERS" )" == "MOJBOX/prof" ]]'
ck "conf: priority prova"   'grep -q "^CONTEST_PRIORITY=prova" "$CF"'
ck "languages array canônico (filtra inválida)" '[[ "$( . "$CF"; echo "$LANGUAGES" )" == "c cpp" ]]'
ck "problem-langs.json por problema" '[[ "$(jq -rc ".[\"bankprob\"]" "$FIX/tog-c/problem-langs.json")" == "[\"c\",\"py3\"]" ]]'
ck "enunciado PDF gravado"  '[[ -f "$FIX/tog-c/enunciados/bankprob.pdf" ]]'
printf 'CONTEST=tog-c\nLOGIN=boss.admin\nUSERFULLNAME=Boss\nLOGINAT=1\n' > "$SESS/togadm"
call /contest/admin/settings GET '' togadm 'contest=tog-c'
ck "round-trip settings: toggles"  '[[ "$(jq -r ".show_log" <<<"$BODY")" == false && "$(jq -r ".score_anon" <<<"$BODY")" == true && "$(jq -r ".manual_verdict" <<<"$BODY")" == true ]]'
ck "round-trip settings: langs/ua" '[[ "$(jq -rc ".languages" <<<"$BODY")" == "[\"c\",\"cpp\"]" && "$(jq -r ".login_ua_substring" <<<"$BODY")" == "MOJBOX" ]]'
call /treino/contest-create/create POST "{\"name\":\"Sup\",\"mode\":\"icpc\",\"priority\":\"super\",\"end\":$FUT,\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"B\"}]}" reg
ck "priority super só admin 403" '[[ "$OUT" == *"Status: 403"* ]]'
call /treino/contest-create/create POST "{\"id\":\"nolate\",\"name\":\"NoLate\",\"mode\":\"treino\",\"allow_late\":false,\"end\":$FUT,\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"B\"}]}" reg
ck "treino com allow_late:false NÃO liga ALLOWLATEUSER" '! grep -q "^ALLOWLATEUSER" "$FIX/nolate/conf"'

echo "== import de tar.gz =="
TD="$(mktemp -d)"; mkdir -p "$TD/enunciados"; printf '<p>imp</p>' > "$TD/enunciados/imp.html"
printf '%s' "{\"id\":\"imp-contest\",\"name\":\"Imp\",\"mode\":\"treino\",\"end\":$FUT,\"problems\":[{\"problem_id\":\"a/b\",\"name\":\"AB\",\"letter\":\"A\",\"statement_file\":\"imp.html\"}]}" > "$TD/contest.json"
TGZ="$(mktemp).tgz"; tar -czf "$TGZ" -C "$TD" .; B64="$(base64 -w0 "$TGZ")"; rm -rf "$TD" "$TGZ"
call /treino/contest-create/import POST "{\"tar_b64\":\"$B64\"}" reg
ck "import criou"           '[[ "$(jq -r .contest_id <<<"$BODY")" == "imp-contest" ]]'
ck "import: enunciado do tar" '[[ -f "$FIX/imp-contest/enunciados/a#b.html" ]]'

echo "== moderação (admin lista/remove) =="
call /treino/admin/contests GET '' adm
ck "lista criados (>=2)"    '[[ "$(jq -r ".count" <<<"$BODY")" -ge 2 ]]'
call /treino/admin/contest-remove POST '{"contest":"imp-contest"}' adm
ck "removeu"                '[[ "$(jq -r .removed <<<"$BODY")" == true && ! -d "$FIX/imp-contest" ]]'
mkdir -p "$FIX/legacy"; printf 'CONTEST_ID=legacy\n' > "$FIX/legacy/conf"
call /treino/admin/contest-remove POST '{"contest":"legacy"}' adm
ck "não remove legado 403"  '[[ "$OUT" == *"Status: 403"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
