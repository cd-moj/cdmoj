#!/bin/bash
# smoke-users-batch.gjs.sh — o CSV de contas com CABEÇALHO (web/shared/users-batch.js, parseRichCsv)
# aceita os nomes de coluna em PT, EN e ES. O caso que importa: o CSV de credenciais que o admin
# BAIXA sai no idioma da interface (downloadCsv) — em espanhol "login,contraseña,nombre,correo" —
# e tem de voltar a ser aceito no upload (antes só PT/EN: o arquivo baixado em ES virava lixo).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
command -v gjs >/dev/null 2>&1 || { echo "SKIP: sem gjs"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
{ echo "let LANG='pt'; function T(pt,en,es){ if(LANG==='es') return es!=null?es:(en!=null?en:pt); return LANG==='en' ? (en!=null?en:pt) : pt; }"
  sed -e '/^import /d' -e 's/^export //' "$ROOT/web/shared/users-batch.js"
  cat <<'EOF'
const ok = (n, c) => print((c ? 'ok' : 'FAIL') + ': ' + n);
const one = (txt) => { const r = parseRichCsv(txt); return r && r[0]; };
let u = one('login,senha,nome,email\nana,s1,Ana,a@x');
ok('PT: login,senha,nome,email', u && u.password === 's1' && u.fullname === 'Ana' && u.email === 'a@x');
u = one('login,password,name,email\nbia,s2,Bia,b@x');
ok('EN: login,password,name,email', u && u.password === 's2' && u.fullname === 'Bia' && u.email === 'b@x');
u = one('login,contraseña,nombre,correo\ncai,s3,Caí,c@x');
ok('ES: login,contraseña,nombre,correo', u && u.password === 's3' && u.fullname === 'Caí' && u.email === 'c@x');
u = one('login,equipo,país,sede,universidad\nd1,Los Primos,ar,Sede Sur,Universidad de Buenos Aires');
ok('ES: equipo/país/sede/universidad', u && u.fullname === 'Los Primos' && u.country === 'ar' && u.region === 'Sede Sur' && u.univ_full === 'Universidad de Buenos Aires');
// o cabeçalho que o downloadCsv escreve em cada idioma volta pelo parseRichCsv
for (const L of ['pt', 'en', 'es']) {
  LANG = L;
  const head = T('login,senha,nome,email', 'login,password,name,email', 'login,contraseña,nombre,correo');
  u = one(head + '\nzz,pw,Zé,z@x');
  ok('ida e volta do CSV baixado em ' + L, u && u.login === 'zz' && u.password === 'pw' && u.fullname === 'Zé' && u.email === 'z@x');
}
ok('sem cabeçalho = null (cai no parseUsers clássico)', parseRichCsv('ana:s1:Ana:a@x') === null);
EOF
} > "$T/t.js"
OUT="$(gjs "$T/t.js" 2>&1)"; echo "$OUT"
pass=$(grep -c '^ok:' <<<"$OUT"); fail=$(grep -c '^FAIL' <<<"$OUT")
[[ "$pass" -eq 8 && "$fail" -eq 0 ]] || fail=$((fail+1))
echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
