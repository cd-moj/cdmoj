#!/bin/bash
# ENTRAR NUM CONTEST: a tela de login é a RAIZ `/contest/?c=<id>` — `/contest/login/` NUNCA existiu.
# Cinco páginas (admin, jplag, clarifications, docs, rodadas) apontavam p/ lá: quem criava um contest
# pelo wizard clicava em "Login do contest" e levava 404, sem caminho para o painel (relato do Arthur
# Botelho, 2026-09-20). Este teste fecha a porta: nenhum arquivo do web/ pode citar a rota morta, e a
# volta pós-login (`?next=`) só aceita caminho do próprio site dentro de /contest/.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"; W="$ROOT/web"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "contest-login-link: gjs ausente — pulando"; exit 0; }
PASS=0; FAIL=0
ck(){ if eval "$2"; then echo "  ok: $1"; PASS=$((PASS+1)); else echo "  FALHOU: $1"; FAIL=$((FAIL+1)); fi; }
chk(){ if [[ "$1" == "$2" ]]; then echo "  ok: $3"; PASS=$((PASS+1)); else echo "  FALHOU: $3 (got '$1', want '$2')"; FAIL=$((FAIL+1)); fi; }

echo "== a rota morta não é citada em lugar nenhum do web/ =="
HITS="$(grep -rl "contest/login/" "$W" 2>/dev/null | grep -v "/moj[-.]" | grep -v "contest-guard.js" | tr '\n' ' ')"
ck "nenhuma página aponta p/ /contest/login/ ($HITS)" '[[ -z "$HITS" ]]'
for f in contest/admin/admin.js contest/jplag/jplag.js contest/clarification/clarification.js contest/docs/docs.js contest/rounds/rounds.js; do
  ck "$f usa contestLoginHref" 'grep -q "contestLoginHref(CONTEST" "$W/$f" && grep -q "shared/contest-guard.js" "$W/$f"'
done

echo "== safeNext (extraída do contest.js real) =="
{ sed -n '/^export function safeNext(/,/^}/p' "$W/contest/contest.js" | sed 's/^export //'
  sed -n '/^export function contestLoginHref(/,/^}/p' "$W/shared/contest-guard.js" | sed 's/^export //'
  cat <<'JS'
const cases = [['/contest/admin/?c=x','/contest/admin/?c=x'], ['/contest/','/contest/'],
  ['//evil.com/x',''], ['http://evil/x',''], ['javascript:alert(1)',''], ['/contest/../treino/',''],
  ['/treino/admin/',''], ['',''], ['contest/admin/',''], ['/contest/admin/?c=a&b=1','/contest/admin/?c=a&b=1']];
print('next=' + cases.map(([i,o]) => (safeNext(i) === o ? 'ok' : 'BAD(' + i + '->' + safeNext(i) + ')')).join(','));
print('href=' + contestLoginHref('c1', '/contest/admin/?c=c1'));
print('href_sem_next=' + contestLoginHref('a b'));
JS
} > "$T/t.js"
out="$(gjs "$T/t.js" 2>&1)" || { echo "$out" >&2; echo "contest-login-link: gjs falhou"; exit 1; }
kv(){ sed -n "s/^$1=//p" <<<"$out" | head -1; }
ck "safeNext aceita /contest/… e recusa host externo, esquema, .. e outras áreas" '[[ "$(kv next)" != *BAD* ]]'
chk "$(kv href)" "/contest/?c=c1&next=%2Fcontest%2Fadmin%2F%3Fc%3Dc1" "href do login com next escapado"
chk "$(kv href_sem_next)" "/contest/?c=a%20b" "href sem next (id escapado)"
echo; echo "RESULT: $PASS passed, $FAIL failed"; (( FAIL == 0 ))
