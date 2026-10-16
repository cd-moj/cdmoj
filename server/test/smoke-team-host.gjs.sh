#!/bin/bash
# smoke-team-host.gjs.sh — O ENDEREÇO DO CONTEST no front (web/shared/contest-host.js), 16/10/2026: time só entra pelo
# subdomínio do contest (a API recusa fora dele, lib/team-host.sh) e a página de contest aberta no site principal pula
# p/ o subdomínio. Prende:
#   · subdomainRedirect: só no site principal moj.*, só /contest… (fora os tutoriais /contest/ajuda/), só com `c` que
#     vira subdomínio (≠ treino); caminho, query e hash inteiros; porta do dev preservada;
#   · contestOrigin/baseOrigin/contestHostOf nos hosts reais (produção, dev com porta, subdomínio, IP, localhost);
#   · a regra do id é a MESMA do servidor (th_subdomainable);
#   · os links de contest do site (card da home, inscrição) e o login usam o helper.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"; W="$ROOT/web"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "team-host(gjs): gjs ausente — pulando"; exit 0; }
PASS=0; FAIL=0
chk(){ if [[ "$1" == "$2" ]]; then echo "  ok: $3"; PASS=$((PASS+1)); else echo "  FALHOU: $3 (got '$1', want '$2')"; FAIL=$((FAIL+1)); fi; }
ck(){ if eval "$2"; then echo "  ok: $1"; PASS=$((PASS+1)); else echo "  FALHOU: $1"; FAIL=$((FAIL+1)); fi; }

{ sed -E 's/^export (function|const) /\1 /' "$W/shared/contest-host.js"
  cat <<'JS'
// URLSearchParams mínimo (o gjs não tem): só o get
if (typeof URLSearchParams === 'undefined') {
  globalThis.URLSearchParams = function (s) { const m = {}; String(s || '').replace(/^\?/, '').split('&').forEach((kv) => {
    if (!kv) return; const i = kv.indexOf('='); const k = decodeURIComponent(i < 0 ? kv : kv.slice(0, i)); if (!(k in m)) m[k] = i < 0 ? '' : decodeURIComponent(kv.slice(i + 1)); });
    this.get = (k) => (k in m ? m[k] : null); };
}
const L = (u) => { const m = u.match(/^(https?:)\/\/([^/:]+)(:\d+)?([^?#]*)(\?[^#]*)?(#.*)?$/);
  return { protocol: m[1], hostname: m[2], host: m[2] + (m[3] || ''), pathname: m[4] || '/', search: m[5] || '', hash: m[6] || '' }; };
const R = (u) => subdomainRedirect(L(u)) || '-';
print('r1=' + R('https://moj.naquadah.com.br/contest/?c=fac_daniel_2026_2'));
print('r2=' + R('https://moj.naquadah.com.br/contest/score/?c=pv&view=x#top'));
print('r3=' + R('https://moj.charge.naquadah.com.br:8443/contest/admin/?c=pv&next=%2Fcontest%2F'));
print('r4=' + R('https://pv.moj.naquadah.com.br/contest/?c=pv'));
print('r5=' + R('https://177.70.23.195/contest/?c=pv'));
print('r6=' + R('http://localhost:8080/contest/?c=pv'));
print('r7=' + R('https://moj.naquadah.com.br/contests/inscricao/?c=pv'));
print('r8=' + R('https://moj.naquadah.com.br/contest/'));
print('r9=' + R('https://moj.naquadah.com.br/contest/?c=treino'));
print('r10=' + R('https://moj.naquadah.com.br/contest/?c=a.b'));
print('r11=' + R('https://moj.naquadah.com.br/contest/?c=PV'));
print('r12=' + R('https://moj.naquadah.com.br/contest/ajuda/time/?c=pv'));
print('r13=' + R('https://moj.naquadah.com.br/treino/?c=pv'));
print('o1=' + (contestOrigin('pv', L('https://moj.naquadah.com.br/')) || '-'));
print('o2=' + (contestOrigin('pv', L('https://ou.moj.naquadah.com.br/contest/')) || '-'));
print('o3=' + (contestOrigin('pv', L('https://177.70.23.195/')) || '-'));
print('o4=' + (contestOrigin('treino', L('https://moj.naquadah.com.br/')) || '-'));
print('b1=' + baseOrigin(L('https://pv.moj.charge.naquadah.com.br:8443/contest/')));
print('b2=' + baseOrigin(L('https://moj.naquadah.com.br/x')));
print('b3=' + baseOrigin(L('https://177.70.23.195/contest/')));
print('h1=' + contestHostOf('fac_daniel_2026_2.moj.naquadah.com.br') + ' h2=' + contestHostOf('moj.naquadah.com.br') + ' h3=' + contestHostOf('177.70.23.195'));
print('sub=' + ['pv', 'fac_daniel_2026_2', 'a-b', 'a.b', 'PV', '_x', 'x'.repeat(64)].map((x) => (SUBDOMAINABLE.test(x) ? 1 : 0)).join(''));
JS
} > "$T/h.js"
out="$(timeout 30 gjs "$T/h.js" 2>&1)" || { echo "$out"; echo "team-host(gjs): gjs falhou"; exit 1; }
kv(){ sed -n "s/^$1=//p" <<<"$out" | head -1; }
echo "== subdomainRedirect =="
chk "$(kv r1)" "https://fac_daniel_2026_2.moj.naquadah.com.br/contest/?c=fac_daniel_2026_2" "site principal → subdomínio (id com _)"
chk "$(kv r2)" "https://pv.moj.naquadah.com.br/contest/score/?c=pv&view=x#top" "caminho, query e hash inteiros"
chk "$(kv r3)" "https://pv.moj.charge.naquadah.com.br:8443/contest/admin/?c=pv&next=%2Fcontest%2F" "dev com porta; o next= segue"
chk "$(kv r4)" "-" "já no subdomínio: fica"
chk "$(kv r5)" "-" "IP: não há como derivar (a API mostra o endereço)"
chk "$(kv r6)" "-" "localhost: fica"
chk "$(kv r7)" "-" "inscrição (/contests/) fica no site principal"
chk "$(kv r8)" "-" "sem c: fica"
chk "$(kv r9)" "-" "c=treino: fica"
chk "$(kv r10)" "-" "id que não vira subdomínio (a.b): fica"
chk "$(kv r11)" "-" "id em maiúscula: fica (o servidor também o isenta)"
chk "$(kv r12)" "-" "tutoriais /contest/ajuda/: ficam"
chk "$(kv r13)" "-" "fora de /contest: fica"
echo "== contestOrigin / baseOrigin / contestHostOf =="
chk "$(kv o1)" "https://pv.moj.naquadah.com.br" "contestOrigin no site principal"
chk "$(kv o2)" "https://pv.moj.naquadah.com.br" "contestOrigin a partir do subdomínio de outro contest"
chk "$(kv o3)" "-" "contestOrigin no IP: vazio (link no ?c=)"
chk "$(kv o4)" "-" "treino: sem subdomínio"
chk "$(kv b1)" "https://moj.charge.naquadah.com.br:8443" "baseOrigin do subdomínio (dev com porta)"
chk "$(kv b2)" "https://moj.naquadah.com.br" "baseOrigin no site principal"
chk "$(kv b3)" "https://177.70.23.195" "baseOrigin no IP"
chk "$(kv h1)" "fac_daniel_2026_2 h2=null h3=null" "contestHostOf"
chk "$(kv sub)" "1110000" "SUBDOMAINABLE = th_subdomainable do servidor"
echo "== a mesma regra nas duas pontas e os usuários do helper =="
ck "regex do id igual no servidor (lib/team-host.sh)" 'grep -qF "^[a-z0-9][a-z0-9_-]{0,62}\$" "$ROOT/server/api/v1/lib/team-host.sh" && grep -qF "/^[a-z0-9][a-z0-9_-]{0,62}\$/" "$W/shared/contest-host.js"'
ck "contest-guard.js redireciona pelo helper" 'grep -q "subdomainRedirect(location)" "$W/shared/contest-guard.js"'
ck "card da home e inscrição usam contestOrigin" 'grep -q "contestOrigin(id)" "$W/shared/contest-card.js" && grep -q "contestOrigin(TARGET)" "$W/contests/inscricao/inscricao.js"'
ck "login do contest mostra o endereço no host_required" 'grep -q "code === .host_required." "$W/contest/contest.js" && grep -q "e.code === .host_required." "$W/shared/auth.js"'
echo "team-host(gjs): $PASS ok, $FAIL falhas"; [[ $FAIL -eq 0 ]]
