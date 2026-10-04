#!/bin/bash
# smoke-score-anon.gjs.sh — os DOIS produtores do agregado do placar anônimo concordam (03/10/2026): o servidor
# (score/build.sh › gen_anon, o que vai a quem não é da organização) e o `aggregateOf` do score.js (o "Anônimo" local
# da organização). Monta um placar de verdade pelo build.sh, compara os dois e renderiza o agregado do servidor com o
# `renderAnon` (DOM falso). Sem gjs: pula (rc 0).
set -u
command -v gjs >/dev/null 2>&1 || { echo "score-anon: gjs ausente — pulando"; exit 0; }
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; WEB="$ROOT/../web"
F="$(mktemp -d)"; trap 'rm -rf "$F"' EXIT
C="$F/an"; mkdir -p "$C/var"; NOW=$(date +%s); T0=$((NOW-7200))
{ printf 'CONTEST_ID=an\nCONTEST_TYPE=icpc\nCONTEST_NAME=Anon\nSCORE_ANON=1\nCONTEST_START=%s\nCONTEST_END=%s\n' "$T0" "$((NOW+3600))"
  printf 'PROBS=( x col#pa Alfa A col#pa x col#pb Beta B col#pb x col#pc Gama C col#pc )\n'; } > "$C/conf"
mk(){ mkdir -p "$C/users/$1"; jq -cn --arg l "$1" '{login:$l,fullname:("Time "+$l),password:"x",team:{univ_short:"U",univ_full:"Univ",flag:"br"}}' > "$C/users/$1/account.json"; : > "$C/users/$1/history"; }
for u in ta tb tc td te; do mk "$u"; done
ac(){ printf '%s:%s:C:Accepted:%s:%s\n' "$2" "$3" "$2" "$4" >> "$C/users/$1/history"; }
ac ta $((T0+600)) 'col#pa' i1; ac ta $((T0+900)) 'col#pb' i2; ac ta $((T0+1200)) 'col#pc' i3
ac tb $((T0+700)) 'col#pa' i4; ac tb $((T0+800)) 'col#pc' i5
ac tc $((T0+650)) 'col#pa' i6
printf '%s:col#pb:C:Wrong Answer:%s:i7\n' $((T0+500)) $((T0+500)) >> "$C/users/td/history"
( cd "$ROOT/score" && CONTESTSDIR="$F" bash build.sh an >/dev/null 2>&1 )
[[ -s "$C/var/placar-anon.json" ]] || { echo "FAIL: build.sh não gerou o placar-anon.json"; exit 1; }
SRC="$(python3 - "$WEB/contest/score/score.js" <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
out = []
for name in ('aggregateOf', 'renderAnon'):
    m = re.search(r'^export function ' + name + r'\(.*?^}\n', s, re.S | re.M)
    out.append(m.group(0).replace('export function', 'function', 1) if m else '')
print('\n'.join(out))
PY
)"
PSRC="$(sed -e 's/^export //' -e '/^import /d' "$WEB/contest/score/score-icpc.js")"
gjs -c "
const T = (pt) => pt;
function el(tag, attrs, ...kids) { const n = { tag, kids: [], text: '', append(...k) { k.forEach((x) => { if (x != null) this.kids.push(x); }); } };
  n.append(...kids); return n; }
const flat = (n) => (n == null ? '' : typeof n === 'string' || typeof n === 'number' ? String(n) : (n.kids || []).map(flat).join(' ') + (n.innerHTML || ''));
const BOX = { innerHTML: '', kids: [], append(...k) { k.forEach((x) => this.kids.push(x)); } };
const document = { getElementById: () => BOX };
$PSRC
$SRC
const txt = $(jq -Rs . "$C/var/placar.txt");
const lines = txt.split('\n'); const mode = lines[0].trim().split(/\s+/);
const parsed = parseICPC(lines.slice(1).filter(Boolean), {}, mode.includes('s'), mode.includes('g'));
const srv = $(cat "$C/var/placar-anon.json");
const cli = aggregateOf(parsed);
let pass = 0, fail = 0; const ck = (lbl, ok) => { if (ok) { print('  ok: ' + lbl); pass++; } else { print('  FAIL: ' + lbl); fail++; } };
const J = (x) => JSON.stringify(x);
for (const k of ['n', 'supported', 'problems', 'per_problem', 'dist', 'q'])
  ck('servidor == cliente em ' + k + ' (' + J(srv[k]) + ')', J(srv[k]) === J(cli[k]));
renderAnon(srv);
const shown = BOX.kids.map(flat).join(' ');
ck('renderAnon(do servidor) mostra participantes e o resolvedores por problema', /participantes/.test(shown) && /Resolvedores/.test(shown));
ck('…e nenhum login/nome', !/Time t|\bta\b|\btb\b/.test(shown));
print('RESULT: ' + pass + ' passed, ' + fail + ' failed');
if (fail) imports.system.exit(1);
"
