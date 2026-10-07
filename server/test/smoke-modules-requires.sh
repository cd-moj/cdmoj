#!/bin/bash
# smoke-modules-requires.sh — PRÉ-REQUISITOS de módulo (lib/modules.sh mod_requires_ok, 07/10/2026). Relato do Daniel
# Valle: `inscricoes` ligado num contest com 135 contas PRÓPRIAS ⇒ "só inscrito entra" barrava todo aluno (e a conta dele),
# e a inscrição — que usa as contas do Treino Livre — não tinha como incluí-los. Afirma:
#   • ligar `inscricoes` sem USERS_FROM = 422 requires_shared_users por TODO caminho: painel Módulos, ações do painel de
#     Inscrições que criam o roster (enable/window/add/team-add) e a criação por spec; com as contas do treino, liga;
#   • o catálogo (GET) diz o que falta (`requires`) p/ a tela travar a caixa;
#   • quem JÁ estava assim (legado): o login de conta própria NÃO é barrado (a regra não vale sem as contas do treino),
#     a Central avisa (modules_requires, pt/en/es), "ligar de novo" não trava o POST e desligar pode;
#   • o aviso "desligado com dados" não manda religar o que não pode ligar;
#   • `esqueletos` sem o editor segue 422 editor_required (a regra antiga, agora no catálogo).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
fx_owners_index "$FIX"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS"
NOW=$EPOCHSECONDS; FUT=$((NOW+100000))
T="$FIX/treino"; mkdir -p "$T/var/jsons"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\n' > "$T/conf"
fx_user "$T" regular s "Regular" >/dev/null; fx_user "$T" ana s Ana >/dev/null
printf '{"threshold":0,"allow":["regular"],"deny":[]}' > "$T/var/contest-perms.json"
printf '%s' '{"id":"bankprob","title":"Banco Prob","tags":["#x"],"statement_html_b64":"PGgxPm9pPC9oMT4="}' > "$T/var/jsons/bankprob.json"
printf 'CONTEST=treino\nLOGIN=regular\nUSERFULLNAME=Regular\nLOGINAT=1\n' > "$SESS/reg"
mkc(){ # <id> <USERS_FROM|""> <CONTEST_MODULES|"">
  local C="$FIX/$1"; mkdir -p "$C/var"
  { printf 'CONTEST_ID=%s\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nUSER_STORE=v2\nPROBS=( x col#pa Alfa A col#pa )\n' "$1" $((NOW-60)) "$FUT"
    [[ -n "$2" ]] && printf 'USERS_FROM=%s\n' "$2"; [[ -n "$3" ]] && printf 'CONTEST_MODULES=%s\n' "$3"; } > "$C/conf"
  fx_user "$C" "$1.admin" p Admin >/dev/null
  printf 'CONTEST=%s\nLOGIN=%s.admin\nLOGINAT=1\n' "$1" "$1" > "$SESS/adm-$1"
}
mkc lc "" ""; fx_user "$FIX/lc" aluno1 s1 "Aluno 1" >/dev/null           # contas PRÓPRIAS
mkc sc treino ""                                                          # contas do treino
mkc lg "" "inscricoes"; fx_user "$FIX/lg" aluno1 s1 "Aluno 1" >/dev/null  # LEGADO: ligado sem as contas do treino…
printf '{"version":1,"teams":{},"entries":{}}\n' > "$FIX/lg/registrations.json"   # …e com roster (o caso do Daniel)
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-reg}" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }
REQ(){ J ".modules[]|select(.id==\"$1\")|.requires.$2"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:240}"; ((fail++)); fi; }

echo "== contas PRÓPRIAS: inscricoes não liga =="
call /contest/admin/modules GET '' adm-lc 'contest=lc'
ck "catálogo: inscricoes requires.ok=false com o código" '[[ "$(REQ inscricoes ok)" == false && "$(REQ inscricoes code)" == requires_shared_users && "$(REQ sedes ok)" == true ]]'
call /contest/admin/modules POST '{"on":["inscricoes"]}' adm-lc 'contest=lc'
ck "painel Módulos: 422 requires_shared_users, conf intacto" '[[ "$OUT" == *"Status: 422"* && "$(J .error.code)" == requires_shared_users && "$(J .error.message)" == *"Treino Livre"* ]] && ! grep -q "^CONTEST_MODULES=" "$FIX/lc/conf"'
for a in enable window add team-add; do
  call /contest/admin/registrations POST "{\"action\":\"$a\",\"login\":\"ana\",\"name\":\"X\"}" adm-lc 'contest=lc'
  ck "painel Inscrições ($a): 422, sem roster criado" '[[ "$(J .error.code)" == requires_shared_users && ! -e "$FIX/lc/registrations.json" ]]'
done
call /contest/admin/registrations POST '{"action":"disable"}' adm-lc 'contest=lc'
ck "desligar segue livre (não é 422)" '[[ "$(J .error.code)" != requires_shared_users ]]'

echo "== contas do TREINO: liga =="
call /contest/admin/modules GET '' adm-sc 'contest=sc'
ck "catálogo: inscricoes requires.ok=true" '[[ "$(REQ inscricoes ok)" == true ]]'
call /contest/admin/modules POST '{"on":["inscricoes"]}' adm-sc 'contest=sc'
ck "liga normalmente"                   '[[ "$(J ".enabled|index(\"inscricoes\")")" != null ]]'

echo "== criação por spec =="
SPEC="{\"id\":\"own-i\",\"name\":\"Own\",\"mode\":\"icpc\",\"end\":$FUT,\"admin\":{\"login\":\"chief\",\"password\":\"sek123\"},\"users\":[{\"login\":\"u1\"}],\"modules\":{\"inscricoes\":true},\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"P1\",\"letter\":\"A\"}]}"
call /treino/contest-create/create POST "$SPEC"
ck "contas próprias + inscricoes = 422, nada criado" '[[ "$(J .error.code)" == requires_shared_users && ! -e "$FIX/own-i" ]]'
SPEC2="{\"id\":\"shr-i\",\"name\":\"Shared\",\"mode\":\"icpc\",\"end\":$FUT,\"users_from\":\"treino\",\"modules\":{\"inscricoes\":{\"window\":{\"teams\":false}}},\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"P1\",\"letter\":\"A\"}]}"
call /treino/contest-create/create POST "$SPEC2"
ck "contas do treino + inscricoes = cria com o módulo" '[[ "$(J .contest_id)" == shr-i ]] && grep -q "inscricoes" "$FIX/shr-i/conf"'

echo "== LEGADO (ligado sem as contas do treino, com roster) =="
OUT="$(PATH_INFO=/auth/login REQUEST_METHOD=POST QUERY_STRING="contest=lg" bash "$ROUTER" <<<'{"username":"aluno1","password":"s1"}' 2>&1)"
ck "conta própria ENTRA (a regra \"só inscrito\" não vale sem as contas do treino)" '[[ "$OUT" == *"\"logged_in\":true"* ]]'
call /contest/admin/preflight GET '' adm-lg 'contest=lg'
ck "Central avisa: modules_requires warn em pt/en/es" '[[ "$(J ".checks[]|select(.id==\"modules_requires\")|.level")" == warn && "$(J ".checks[]|select(.id==\"modules_requires\")|.detail")" == *"contas do Treino Livre"* && "$(J ".checks[]|select(.id==\"modules_requires\")|.detail_en")" == *"Free Training"* && "$(J ".checks[]|select(.id==\"modules_requires\")|.detail_es")" == *"Entrenamiento Libre"* ]]'
call /contest/admin/modules POST '{"on":["inscricoes"]}' adm-lg 'contest=lg'
ck "\"ligar\" o que já estava ligado não trava o POST" '[[ "$(J ".enabled|index(\"inscricoes\")")" != null ]]'
call /contest/admin/modules POST '{"off":["inscricoes"]}' adm-lg 'contest=lg'
ck "desligar pode"                      '[[ "$(J ".enabled|index(\"inscricoes\")")" == null ]]'
call /contest/admin/preflight GET '' adm-lg 'contest=lg'
ck "desligado: sem modules_requires e o \"desligado com dados\" NÃO manda religar a inscrição" '[[ -z "$(J ".checks[]|select(.id==\"modules_requires\")|.id")" && "$(J ".checks[]|select(.id==\"modules\")|.detail")" != *inscricoes* ]]'

echo "== esqueletos sem o editor (regra antiga, agora no catálogo) =="
printf 'SHOWEDITOR=0\n' >> "$FIX/lc/conf"
call /contest/admin/modules POST '{"on":["esqueletos"]}' adm-lc 'contest=lc'
ck "422 editor_required"                '[[ "$(J .error.code)" == editor_required ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
