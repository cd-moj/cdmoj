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
#   • `esqueletos` sem o editor segue 422 editor_required (a regra antiga, agora no catálogo);
#   • `virtual` (07/10/2026, o `blablabla` mostrava o botão com problema privado): a elegibilidade entrou no
#     mod_requires_ok — catálogo com o MOTIVO, 422 com `reason`, Central, e a criação o liga DESLIGADO com o motivo
#     (`modules_skipped`); o botão da home (`virtual_url`) e o /contest/virtual do placar só com o PORTÃO passando, e a
#     home acompanha a publicação dos problemas (carimbo .treino-list-dirty);
#   • a home só convida ("Inscreva-se") e a rota do competidor só inscreve com a inscrição EM VIGOR (roster ∧ módulo ∧
#     contas do treino) — o ta_fac_profs_202602 mostrava o botão com o módulo desligado.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
fx_owners_index "$FIX"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$FIX/.run"; mkdir -p "$RUNDIR"
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

echo "== virtual: o portão entrou no mod_requires_ok =="
mkc vt "" ""                                        # col#pa NÃO tem json público no treino (= o blablabla)
call /contest/admin/modules GET '' adm-vt 'contest=vt'
ck "catálogo: virtual requires.ok=false, motivo problems_not_public" '[[ "$(REQ virtual ok)" == false && "$(REQ virtual code)" == virtual_not_eligible && "$(REQ virtual reason)" == problems_not_public ]]'
call /contest/admin/modules POST '{"on":["virtual"]}' adm-vt 'contest=vt'
ck "ligar: 422 virtual_not_eligible com error.reason" '[[ "$OUT" == *"Status: 422"* && "$(J .error.code)" == virtual_not_eligible && "$(J .error.reason)" == problems_not_public ]] && ! grep -q "^CONTEST_MODULES=" "$FIX/vt/conf"'
sed -i 's/^CONTEST_TYPE=icpc/CONTEST_TYPE=obi/' "$FIX/vt/conf"
call /contest/admin/modules GET '' adm-vt 'contest=vt'
ck "modo OBI: motivo type"               '[[ "$(REQ virtual reason)" == type ]]'
sed -i 's/^CONTEST_TYPE=obi/CONTEST_TYPE=icpc/' "$FIX/vt/conf"
printf 'CONTEST_MODULES=virtual\n' >> "$FIX/vt/conf"   # legado: ligado com problema privado
call /contest/admin/preflight GET '' adm-vt 'contest=vt'
ck "Central: modules_requires cita o virtual em pt/en/es" '[[ "$(J ".checks[]|select(.id==\"modules_requires\")|.detail")" == *"virtual: há problema não público"* && "$(J ".checks[]|select(.id==\"modules_requires\")|.detail_en")" == *"virtual: a problem is not public"* && "$(J ".checks[]|select(.id==\"modules_requires\")|.detail_es")" == *"virtual: hay un problema no público"* ]]'
printf '{"id":"col#pa","title":"Alfa","public":true}' > "$T/var/jsons/col#pa.json"
sed -i '/^CONTEST_MODULES=/d' "$FIX/vt/conf"
call /contest/admin/modules POST '{"on":["virtual"]}' adm-vt 'contest=vt'
ck "problema publicado: liga (prova ainda rodando não barra)" '[[ "$(J ".enabled|index(\"virtual\")")" != null ]]'
rm -f "$T/var/jsons/col#pa.json"

echo "== criação: virtual inelegível nasce DESLIGADO, com o motivo =="
SPEC3="{\"id\":\"vir-p\",\"name\":\"V\",\"mode\":\"icpc\",\"end\":$FUT,\"admin\":{\"login\":\"chief\",\"password\":\"sek123\"},\"modules\":{\"virtual\":true},\"problems\":[{\"bank_id\":\"col#pa\",\"name\":\"P1\",\"letter\":\"A\"}]}"
call /treino/contest-create/create POST "$SPEC3"
ck "cria, módulo fora do conf, modules_skipped com código e motivo" '[[ "$(J .contest_id)" == vir-p && "$(J ".modules_skipped[0].id")" == virtual && "$(J ".modules_skipped[0].reason")" == problems_not_public ]] && ! grep -q "virtual" "$FIX/vir-p/conf" && grep -q "modules-skipped" "$FIX/vir-p/var/admin-audit.log"'
SPEC4="${SPEC3//vir-p/vir-ok}"; SPEC4="${SPEC4//col#pa/bankprob}"
call /treino/contest-create/create POST "$SPEC4"
ck "problema público: cria COM o virtual e modules_skipped vazio" '[[ "$(J .contest_id)" == vir-ok && "$(J ".modules_skipped|length")" == 0 ]] && grep -q "^CONTEST_MODULES=virtual" "$FIX/vir-ok/conf"'

echo "== botão Virtual: home e placar só com o portão =="
VE="$FIX/ve"; mkdir -p "$VE/var"
printf 'CONTEST_ID=ve\nCONTEST_NAME=Encerrado\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nUSER_STORE=v2\nPROBS=( x col#pv Beta A col#pv )\nCONTEST_MODULES=virtual\n' $((NOW-7200)) $((NOW-3600)) > "$VE/conf"
call /index/contests GET '' '' 'all=1'
ck "home: contest encerrado com problema privado NÃO tem virtual_url" '[[ "$(J ".closed.items[]|select(.id==\"ve\")|.id")" == ve && "$(J ".closed.items[]|select(.id==\"ve\")|.virtual_url // \"\"")" == "" ]]'
call /contest/virtual GET '' '' 'contest=ve'
ck "placar: /contest/virtual available=false"  '[[ "$(J .available)" == false && "$(J ".url // \"\"")" == "" ]]'
printf '{"id":"col#pv","title":"Beta","public":true}' > "$T/var/jsons/col#pv.json"
touch -d "@$((EPOCHSECONDS+5))" "$T/var/.treino-list-dirty"   # quem publica toca o carimbo (index_problem_bg)
call /index/contests GET '' '' 'all=1'
ck "publicou (carimbo): a home mostra o virtual_url SEM mexer no conf" '[[ "$(J ".closed.items[]|select(.id==\"ve\")|.virtual_url")" == "/treino/virtual/?c=ve" ]]'
call /contest/virtual GET '' '' 'contest=ve'
ck "placar: available=true com a url"        '[[ "$(J .available)" == true && "$(J .url)" == "/treino/virtual/?c=ve" ]]'

echo "== Inscreva-se: só com a inscrição EM VIGOR =="
RG="$FIX/rg"; mkdir -p "$RG/var"
printf 'CONTEST_ID=rg\nCONTEST_NAME=Insc\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nUSER_STORE=v2\nUSERS_FROM=treino\nPROBS=( x bankprob P A bankprob )\n' "$FUT" $((FUT+3600)) > "$RG/conf"
printf '{"version":1,"teams":{},"entries":{}}\n' > "$RG/registrations.json"   # roster GUARDADO, módulo desligado
touch -d "@$((EPOCHSECONDS+10))" "$RG/conf"
call /index/contests GET '' '' 'all=1'
ck "home: módulo desligado ⇒ sem registration (o ta_fac_profs_202602)" '[[ "$(J ".upcoming[]|select(.id==\"rg\")|.id")" == rg && "$(J ".upcoming[]|select(.id==\"rg\")|.registration // \"\"")" == "" ]]'
call /treino/contest-registration GET '' reg 'contest=rg'
ck "rota do competidor: enabled=false"      '[[ "$(J .enabled)" == false ]]'
call /treino/contest-registration POST '{"contest":"rg","action":"register"}' reg
ck "inscrever: 409 registration_off, roster intacto" '[[ "$OUT" == *"Status: 409"* && "$(J .error.code)" == registration_off && "$(jq -c .entries "$RG/registrations.json")" == "{}" ]]'
printf 'CONTEST_MODULES=inscricoes\n' >> "$RG/conf"; touch -d "@$((EPOCHSECONDS+15))" "$RG/conf"
call /index/contests GET '' '' 'all=1'
ck "módulo ligado + contas do treino ⇒ registration volta" '[[ "$(J ".upcoming[]|select(.id==\"rg\")|.registration.url")" == "/contests/inscricao/?c=rg" ]]'
call /treino/contest-registration GET '' reg 'contest=rg'
ck "rota do competidor: enabled=true"       '[[ "$(J .enabled)" == true ]]'
sed -i '/^USERS_FROM=/d' "$RG/conf"; touch -d "@$((EPOCHSECONDS+20))" "$RG/conf"
call /index/contests GET '' '' 'all=1'
ck "sem as contas do treino ⇒ sem registration, mesmo com o módulo" '[[ "$(J ".upcoming[]|select(.id==\"rg\")|.registration // \"\"")" == "" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
