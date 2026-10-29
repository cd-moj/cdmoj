#!/bin/bash
# smoke-cross-contest-identity.sh — AUTORIA é atividade do TREINO (28/10/2026). Garante que uma sessão de OUTRO
# contest não alcança o acervo do treino, E que a gestão de org/coleção dentro do próprio treino segue as regras:
#   - o `<criador>.admin` LOCAL de um contest qualquer (sufixo de papel — isento do host-lock) NÃO gere org do
#     treino (POST /orgs/create) nem lê/edita/baixa problema PRIVADO (/problems/source, /problems/edit,
#     /problems/download), nem dispara /admin/synctreino ou lê /judge/list;
#   - um `.admin` COMUM do treino (não super) não gere org alheia nem implícita — a gestão real
#     (org_can_manage/coll_can_manage) é dono OU superadmin NUMA SESSÃO DO TREINO, e a flag can_manage da UI usa
#     o mesmo predicado;
#   - org IMPLÍCITA nunca aceita "gestão" por /orgs/create, nem do SUPERADMIN;
#   - a recusa cross-contest deixa trilha no audit, com teto.
# Controles (não podem quebrar): o AUTOR real e o SUPERADMIN do treino seguem funcionando.
# Choke: o router corta os segmentos problems/orgs a quem não é sessão do treino; a lib tem a trava
# gêmea (is_platform_superadmin em org_can_manage/coll_can_manage e na flag can_manage; is_platform_admin só em
# checks de VISIBILIDADE). Roda com TEAM_HOST_LOCK=1 (= produção).
#
# MESMO LOGIN em outro contest (um time com o login de um autor do treino): com a trava de host valendo, o th_guard
# o barra (host_required), e pelo próprio subdomínio o contest_isolated corta /problems|/orgs. Com a trava
# afrouxada — `$RUNDIR/team-host-lock` = observe|0 (sem restart), TEAM_HOST_LOCK=observe/0 no env, ou contest com id
# que não vira subdomínio — o corte `author_treino_only` do router é o que vale. O caso abaixo afrouxa a trava pelo
# arquivo e confere o 403. Sem CONTEST_HOST: pelo subdomínio quem responde é o contest_isolated.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"; SPOOL="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS" "$SPOOL"' EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$PROBS" SPOOLDIR="$SPOOL" \
       TL_STORE_DIR="$RUN/tl" CALIB_DIR="$RUN/calib" MOJ_JOBS_SYNC=1 TEAM_HOST_LOCK=1
mkdir -p "$RUN/tl" "$RUN/calib" "$FIX/treino/var"
NOW="$EPOCHSECONDS"; T="$FIX/treino"
printf 'CONTEST_ID=treino\nCONTEST_END=%s\nSUPERADMINS=boss.admin\n' "$((NOW+86400))" > "$T/conf"
# treino: org "orgpriv" (membro/admin = prof), problema PRIVADO orgpriv#priv
# org "curso": teach.admin e boss.admin são só MEMBROS (admin = prof) — confere a flag can_manage da UI
echo '{"orgpriv":{"members":["prof"],"admins":["prof"],"public_allowed":false,"title":"V"},
       "curso":{"members":["prof","teach.admin","boss.admin"],"admins":["prof"],"public_allowed":false,"title":"C"}}' > "$T/var/orgs.json"
echo '{"colprof":{"owner":"prof","created_by":"prof","at":1}}' > "$T/var/collections.json"   # coleção de OUTRO autor
P="$PROBS/orgpriv/priv"; mkdir -p "$P/sols/good" "$P/tests/input" "$P/docs"
printf 'segredo\n' > "$P/docs/enunciado.md"; printf 'int main(){}\n' > "$P/sols/good/sol.c"; printf '1\n' > "$P/tests/input/t1"
printf '{"owner":"prof","public":false,"display_title":"Priv"}\n' > "$P/.moj-meta.json"
( cd "$P" && git init -q && git add -A && git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm init )
jq -cn '{problems:[{id:"orgpriv#priv",owner:"prof",repo:"orgpriv",prob:"priv",title:"Priv",public:false,collaborators:[],collections:[]}]}' > "$T/var/problem-owners.json"
fx_user "$T" prof sx "Prof"
fx_user "$T" boss.admin  sx "Boss"   # SUPERADMIN do treino (controle positivo — único caminho legítimo
                                     # de atalho global, ver SUPERADMINS acima)
fx_user "$T" teach.admin sx "Teach"  # .admin COMUM do treino: NÃO deve gerir org/coleção alheia
# outro contest, contas PRÓPRIAS
A="$FIX/ext"; mkdir -p "$A/var"; printf 'CONTEST_ID=ext\nCONTEST_END=%s\n' "$((NOW+86400))" > "$A/conf"
fx_user "$A" ext.admin sx "Ext"   # .admin LOCAL de outro contest (sufixo de papel — isento do host-lock)
fx_user "$A" prof      sx "Outro"   # TIME de outro contest com o login de um autor do treino
sess(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' "$1" "$2" "$2" "$NOW" > "$SESS/tk-$3"; }
sess treino prof        prof
sess treino boss.admin  boss
sess treino teach.admin teach
sess ext    ext.admin   ext
sess ext    prof        hom
req(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="${2:-GET}" QUERY_STRING="${3:-}" HTTP_AUTHORIZATION="Bearer tk-$4" bash "$ROUTER" <<<"${5:-}" 2>/dev/null)"
  STATUS="$(printf '%s' "$OUT" | sed -n 's/^Status: \([0-9]*\).*/\1/p' | head -1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: status=$STATUS ${BODY:0:160}"; ((fail++)); fi; }
AUDIT="$T/var/admin-audit.log"
title_now(){ jq -r '.display_title // ""' "$P/.moj-meta.json"; }
commits_now(){ ( cd "$P" && git log --oneline | wc -l ); }
audit_n(){ local n; n="$(grep -c "$1" "$AUDIT" 2>/dev/null)"; printf '%s' "${n:-0}"; }   # grep -c já imprime "0"; sem fallback que duplicaria a linha
C0="$(commits_now)"

echo "== controles: treino segue funcionando =="
req /problems/source GET "id=orgpriv%23priv" prof
ck "autor real (treino) lê a própria fonte"       '[[ "$STATUS" == 200 ]]'
req /problems/edit POST "" prof '{"id":"orgpriv#priv","title":"Novo Titulo"}'
ck "autor real (treino) edita (título aplicado)"  '[[ "$STATUS" == 200 && "$(title_now)" == "Novo Titulo" ]]'
C1="$(commits_now)"; ck "…e o commit do autor aconteceu" '[[ "$C1" -gt "$C0" ]]'

echo "== .admin LOCAL de outro contest (sufixo de papel, isento do host-lock): BARRADO =="
req /orgs/create POST "" ext '{"name":"orgpriv"}'
ck "POST /orgs/create = 403 author_treino_only"   '[[ "$STATUS" == 403 ]] && grep -q author_treino_only <<<"$BODY"'
M="$(jq -r ".orgpriv.members|join(\",\")" "$T/var/orgs.json" 2>/dev/null)"
ck "a org do treino NÃO ganhou ext.admin"         '[[ ",$M," != *",ext.admin,"* ]]'
req /problems/source GET "id=orgpriv%23priv" ext
ck "GET /problems/source privado = 403 author_treino_only" '[[ "$STATUS" == 403 ]] && grep -q author_treino_only <<<"$BODY"'
req /problems/edit POST "" ext '{"id":"orgpriv#priv","title":"outro"}'
ck "POST /problems/edit privado = 403, SEM efeito" '[[ "$STATUS" == 403 ]] && [[ "$(title_now)" == "Novo Titulo" ]] && [[ "$(commits_now)" == "$C1" ]]'
req /problems/download GET "id=orgpriv%23priv" ext
ck "GET /problems/download privado = 403"         '[[ "$STATUS" == 403 ]]'
req /admin/synctreino POST "contest=ext" ext '{}'
ck "POST /admin/synctreino (.admin local) = 403"  '[[ "$STATUS" == 403 ]]'
req /judge/list GET "" ext
ck "GET /judge/list (.admin local) = 403"         '[[ "$STATUS" == 403 ]]'

echo "== MESMO LOGIN em outro contest, com a trava de host afrouxada =="
req /problems/source GET "id=orgpriv%23priv" hom
ck "trava valendo: o th_guard barra antes (host_required)" '[[ "$STATUS" == 403 ]] && grep -q host_required <<<"$BODY"'
echo observe > "$RUN/team-host-lock"
req /problems/source GET "id=orgpriv%23priv" hom
ck "trava em observe: GET /problems/source = 403 author_treino_only" '[[ "$STATUS" == 403 ]] && grep -q author_treino_only <<<"$BODY"'
req /orgs/create POST "" hom '{"name":"orgpriv"}'
ck "trava em observe: POST /orgs/create = 403 author_treino_only" '[[ "$STATUS" == 403 ]] && grep -q author_treino_only <<<"$BODY"'
rm -f "$RUN/team-host-lock"

echo "== .admin COMUM do treino (não super): NÃO gere org/coleção alheia =="
req /orgs/create POST "" teach '{"name":"orgpriv"}'
ck "POST /orgs/create (org alheia, .admin comum) != 200" '[[ "$STATUS" != 200 ]]'
M="$(jq -r ".orgpriv.members|join(\",\")" "$T/var/orgs.json" 2>/dev/null)"
ck "a org 'orgpriv' NÃO ganhou teach.admin"        '[[ ",$M," != *",teach.admin,"* ]]'
req /problems/source GET "id=orgpriv%23priv" teach
ck "…e por isso GET /problems/source privado = 404" '[[ "$STATUS" == 404 ]]'
req /admin/synctreino POST "contest=treino" teach '{}'
ck "POST /admin/synctreino (.admin comum) = 403"  '[[ "$STATUS" == 403 ]]'
req /judge/list GET "" teach
ck "GET /judge/list (.admin comum do treino) = 200 (só visibilidade, não gestão)" '[[ "$STATUS" == 200 ]]'
# a FLAG da UI segue o portão: sem isto a tela oferecia "gerenciar" e a API dava 403
req /orgs/list GET "" teach
ck "GET /orgs/list: can_manage=false na org de que ele é só membro" '[[ "$(jq -r ".orgs[]|select(.name==\"curso\")|.can_manage" <<<"$BODY")" == false ]]'
req /orgs/members POST "" teach '{"name":"curso","add":["boss.admin"]}'
ck "…e o portão concorda (POST /orgs/members = 403)" '[[ "$STATUS" == 403 ]]'
req /problems/collections GET "" teach
ck "GET /problems/collections: can_manage=false na coleção alheia" '[[ "$(jq -r ".collections[]|select(.name==\"colprof\")|.can_manage" <<<"$BODY")" == false ]]'

echo "== org IMPLÍCITA: ninguém 'gere' por /orgs/create — nem o SUPERADMIN =="
req /orgs/list GET "" prof   # garante a implícita "prof" existe (ensure_implicit_org)
req /orgs/create POST "" boss '{"name":"prof"}'
ck "SUPERADMIN em org implícita alheia = 409 implicit" '[[ "$STATUS" == 409 ]] && grep -q "\"implicit\"" <<<"$BODY"'
M="$(jq -r '.prof.members|join(",")' "$T/var/orgs.json" 2>/dev/null)"
ck "a implícita 'prof' NÃO ganhou boss.admin"     '[[ ",$M," != *",boss.admin,"* ]]'

echo "== plataforma: o SUPERADMIN do treino segue podendo tudo isto =="
req /orgs/create POST "" boss '{"name":"orgpriv"}'
ck "SUPERADMIN gere org alheia (200 — é a definição de super)" '[[ "$STATUS" == 200 ]]'
req /admin/synctreino POST "contest=treino" boss '{}'
ck "SUPERADMIN dispara synctreino (200)"          '[[ "$STATUS" == 200 ]]'
req /judge/list GET "" boss
ck "SUPERADMIN lê /judge/list (200)"              '[[ "$STATUS" == 200 ]]'
req /orgs/list GET "" boss
ck "SUPERADMIN: can_manage=true na org de que é só membro" '[[ "$(jq -r ".orgs[]|select(.name==\"curso\")|.can_manage" <<<"$BODY")" == true ]]'
req /problems/collections GET "" boss
ck "SUPERADMIN: can_manage=true na coleção alheia" '[[ "$(jq -r ".collections[]|select(.name==\"colprof\")|.can_manage" <<<"$BODY")" == true ]]'
req /problems/collections GET "" prof
ck "o DONO: can_manage=true na própria coleção"   '[[ "$(jq -r ".collections[]|select(.name==\"colprof\")|.can_manage" <<<"$BODY")" == true ]]'

echo "== trava de LIB: o NOME de super numa sessão de outro contest não concede gestão =="
# O router já corta essa sessão em /problems|/orgs; isto prende a trava gêmea (defesa em profundidade): um
# admin de contest batiza a conta local como quiser, e o superadmin_login só confere o nome.
lib_manage(){ ( _DIR="$ROOT/api/v1"; source "$_DIR/lib/sources.sh" 2>/dev/null; source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"
  SESSION_CONTEST="$1"; SESSION_LOGIN="$2"; org_can_manage orgpriv "$2" && coll_can_manage colprof "$2" ) >/dev/null 2>&1; }
ck "boss.admin em sessão do TREINO: gere (org e coleção)"   'lib_manage treino boss.admin'
ck "boss.admin em sessão do contest ext: NÃO gere"          '! lib_manage ext boss.admin'

echo "== trilha (teto de 5 min por login+rota — não enche o audit com rajada) =="
N0="$(audit_n author-treino-block)"
req /problems/source GET "id=orgpriv%23priv" ext   # repete o 403 de cima, mesmo login+rota
N1="$(audit_n author-treino-block)"
ck "a 1ª recusa já tinha deixado linha(s)"        '[[ "$N0" -ge 1 ]]'
ck "a repetição dentro de 5 min NÃO soma outra"   '[[ "$N1" == "$N0" ]]'
ck "a linha identifica login e contest de origem" 'grep -q $'"'"'ext.admin\tauthor-treino-block\tcontest=ext'"'"' "$AUDIT"'

echo "== rastreabilidade: leitura de conteúdo de autoria deixa trilha; sessão de outro contest se identifica =="
ACT="$(ls "$T"/var/activity-*.log 2>/dev/null | head -1)"
ck "GET /problems/source do autor → activity_log pkg-source" '[[ -n "$ACT" ]] && grep -qP "\tprof\tpkg-source\tid=orgpriv#priv\t" "$ACT"'
req /problems/test GET "id=orgpriv%23priv&name=t1" prof
ck "GET /problems/test do autor → activity_log pkg-test" '[[ "$STATUS" == 200 ]] && grep -qP "\tprof\tpkg-test\tid=orgpriv#priv name=t1\t" "$ACT"'
ck "…e a recusa (403) NÃO vira leitura"               '! grep -qP "\text.admin\tpkg-source\t" "$ACT"'
lib_log(){ ( _DIR="$ROOT/api/v1"; source "$_DIR/lib/sources.sh" 2>/dev/null
  SESSION_CONTEST="$1"; SESSION_LOGIN="$2"; audit_log "teste-sess" "x=1"; activity_log "teste-sess" "y=2" ) >/dev/null 2>&1; }
lib_log ext ext.admin; lib_log treino prof
ACT="$(ls "$T"/var/activity-*.log 2>/dev/null | head -1)"
ck "audit_log de sessão de OUTRO contest ganha sess=<contest>" 'grep -qP "\text.admin\tteste-sess\tx=1 sess=ext$" "$AUDIT"'
ck "activity_log idem"                                 'grep -qP "\text.admin\tteste-sess\ty=2 sess=ext\t" "$ACT"'
ck "sessão do treino: formato de sempre (sem sess=)"   'grep -qP "\tprof\tteste-sess\tx=1$" "$AUDIT"'
( _DIR="$ROOT/api/v1"; source "$_DIR/lib/sources.sh" 2>/dev/null
  SESSION_CONTEST=ext; SESSION_LOGIN=ext.admin; audit_log_to treino "teste-to" "z=3" ) >/dev/null 2>&1
ck "audit_log_to no log de OUTRO contest também ganha sess=" 'grep -qP "\text.admin\tteste-to\tz=3 sess=ext$" "$AUDIT"'

echo "== feeds do painel: o .admin comum vê só o que pode abrir =="
# linhas que citam o problema de outros jeitos: a submissão do membro da org (kind=submit, sem `id=`), o move
# (from=/to=), o id com `:` no fim; e o delete, cujo id já saiu do índice
printf '%s:orgpriv#priv:C:Accepted,100p:%s:s9\n' "$NOW" "$NOW" >> "$T/users/prof/history"
printf '%s\tprof\tmove\tfrom=orgpriv#velho to=orgpriv#priv by=prof\n' "$NOW" >> "$AUDIT"
printf '%s\tprof\tindex-org-lock\tid=orgpriv#priv: ocupado\n' "$NOW" >> "$AUDIT"
printf '%s\tprof\tdelete\tid=sumiu#x by=prof\n' "$NOW" >> "$AUDIT"
printf '%s\tprof\torg-delete\tname=orgsumida by=prof\n' "$NOW" >> "$AUDIT"
req /treino/admin/activity-log GET "limit=5000" teach
ck ".admin comum: feed 200"                                   '[[ "$STATUS" == 200 ]]'
ck "…sem linha do problema privado alheio (id=orgpriv#priv)"  '! grep -q "orgpriv#priv" <<<"$BODY"'
ck "…sem linha de org de que ele não é membro (org-* orgpriv)" '[[ "$(jq "[.events[]|select((.action|test(\"^org-\")) and (.details|test(\"name=orgpriv( |$)\")))]|length" <<<"$BODY")" == 0 ]]'
ck "…e o resto segue no feed (não filtra demais)"            'grep -q "teste-sess" <<<"$BODY"'
req /treino/admin/activity-log GET "limit=5000&format=csv" teach
ck "…o CSV filtra igual"                                      '! grep -q "orgpriv#priv" <<<"$BODY"'
# a tentativa de login RECUSADA no treino entra no feed (kind=login, ação login-refused, motivo e navegador)
printf '%s\tprof\t7.7.7.7\t%s\tbad_creds\t401\n' "$NOW" "$(printf 'Navegador X' | base64 -w0)" >> "$T/var/login-refused.log"
req /treino/admin/activity-log GET "limit=5000&kinds=login" teach
ck "login recusado no feed do treino (kind login, motivo + navegador, IP)" '[[ "$(jq -c "[.events[]|select(.action==\"login-refused\")|{who,kind,details,ip}]" <<<"$BODY")" == "[{\"who\":\"prof\",\"kind\":\"login\",\"details\":\"bad_creds · Navegador X\",\"ip\":\"7.7.7.7\"}]" ]]'
req /treino/admin/activity-log GET "limit=5000" boss
ck "o SUPERADMIN vê a leitura do privado e a org"             'grep -q "pkg-source" <<<"$BODY" && grep -q "orgpriv#priv" <<<"$BODY" && grep -q "name=orgpriv" <<<"$BODY"'
ck "…e a submissão, o move, o id com : e o delete"            '[[ "$(jq "[.events[]|select(.kind==\"submit\" and (.details|test(\"orgpriv#priv\")))]|length" <<<"$BODY")" -ge 1 ]] && grep -q "orgpriv#velho" <<<"$BODY" && grep -q "sumiu#x" <<<"$BODY"'
req /treino/admin/activity-log GET "limit=5000" teach
ck ".admin comum: nem a submissão, nem o move, nem o delete"   '! grep -q "orgpriv#" <<<"$BODY" && ! grep -q "sumiu#x" <<<"$BODY"'
ck "…nem o org-delete (a org já saiu do registro)"            '! grep -q "orgsumida" <<<"$BODY"'
# o /treino/admin/audit-log segue a mesma regra
req /treino/admin/audit-log GET "" teach
ck "/treino/admin/audit-log (.admin comum): 200 e sem o privado/org/delete" '[[ "$STATUS" == 200 ]] && ! grep -q "orgpriv#" <<<"$BODY" && ! grep -q "sumiu#x" <<<"$BODY" && [[ "$(jq "[.entries[]|select((.action|test(\"^org-\")) and (.details|test(\"name=orgpriv( |$)\")))]|length" <<<"$BODY")" == 0 ]]'
ck "…e o resto segue no audit"                                 'grep -q "teste-sess" <<<"$BODY"'
req /treino/admin/audit-log GET "" boss
ck "/treino/admin/audit-log (SUPERADMIN): vê tudo"            'grep -q "orgpriv#priv" <<<"$BODY" && grep -q "sumiu#x" <<<"$BODY" && grep -q "orgsumida" <<<"$BODY"'
# índice ilegível: o feed segue no ar — some toda linha que cita problema ou org, o resto fica
hid_all(){ ( _DIR="$ROOT/api/v1"; source "$_DIR/lib/sources.sh" 2>/dev/null; source "$_DIR/lib/admin-feed.sh"
  source "$_DIR/lib/problems.sh"; owners_merged(){ return 1; }
  SESSION_CONTEST=treino; SESSION_LOGIN=teach.admin; f="$(mktemp)"; feed_hidden_file "$f"; cat "$f"; rm -f "$f" ) 2>/dev/null; }
H="$(hid_all)"
ck "índice ilegível ⇒ conjunto {all:true}"                      '[[ "$(jq -c . <<<"$H")" == "{\"all\":true}" ]]'
FV="$( _DIR="$ROOT/api/v1"; source "$_DIR/lib/admin-feed.sh"; jq -c --argjson H "$H" "$FEED_VISIBLE_DEF"' [ ({action:"login",details:"x"}, {action:"upload",details:"id=a#b"}, {action:"org-create",details:"name=z"}) | feed_visible($H) ]' <<<null )"
ck "…e nesse modo: login fica, linha com problema e org-* saem" '[[ "$FV" == "[true,false,false]" ]]'

echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
