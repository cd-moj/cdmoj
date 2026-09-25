#!/bin/bash
# smoke-avatar-lazy.gjs.sh — o avatar (web/shared/ui.js: avatarEl) carrega a foto PREGUIÇOSAMENTE.
#
# XIV Maratona UnB (25/09/2026): a aba Sessões do /treino/admin/ montava um avatar por sessão ativa e o
# avatarEl criava <img> ANSIOSO — 1.215 GET /treino/profile/photo num minuto; o anteparo do nginx (treino
# ≤ 16 conexões) devolveu 429 a 1.040 (imagens quebradas; os demais usuários do treino disputando o mesmo
# anteparo). Aqui, com o avatarEl REAL e um DOM falso que registra a ORDEM dos atributos:
#   · `loading="lazy"` (e `decoding="async"`) vêm ANTES do `src` — com o src primeiro o navegador já
#     começa a baixar, e o lazy chega tarde;
#   · `hasPhoto === false` não cria <img> nenhum (só as iniciais) — é o que evita o 404 por conta sem foto.
# Sem gjs: pula (rc 0).
set -u
command -v gjs >/dev/null 2>&1 || { echo "avatar-lazy: gjs ausente — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
# só as 3 funções do ui.js (o módulo inteiro importa rede/auth); `export` vira declaração comum
fn(){ python3 - "$WEB/shared/ui.js" "$1" <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'^export function %s\(.*?^}\n' % sys.argv[2], s, re.S | re.M)
print(m.group(0).replace('export function', 'function', 1) if m else '')
PY
}
DOMJS="$(sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$WEB/shared/dom.js")"
SRC="$(fn colorFromName)$(fn initialsOf)$(fn avatarEl)"
[[ "$SRC" == *"function avatarEl"* ]] || { echo "FAIL: avatarEl não encontrado em web/shared/ui.js"; exit 1; }
gjs -c "
const ORDER = [];
function FakeNode(tag){ this.tagName=tag; this.nodeType=1; this.children=[]; this.attrs={}; this.order=[]; this.style={}; this.classList={add(){}}; this._ev={}; }
FakeNode.prototype.append=function(){ for (const k of arguments) this.children.push(k); };
FakeNode.prototype.setAttribute=function(k,v){ this.attrs[k]=v; this.order.push(k); };
FakeNode.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
Object.defineProperty(FakeNode.prototype, 'innerHTML', { set(v){ this.children=[]; }, get(){ return ''; } });
Object.defineProperty(FakeNode.prototype, 'textContent', { set(v){ this._text=String(v); }, get(){ return this._text||''; } });
Object.defineProperty(FakeNode.prototype, 'className', { set(v){ this.attrs['class']=v; }, get(){ return this.attrs['class']||''; } });
globalThis.document = { createElement: (t) => new FakeNode(t), createTextNode: (x) => ({nodeType:3, text:String(x)}) };
$DOMJS
$SRC
let pass = 0, fail = 0;
const ck = (msg, ok, dbg) => { if (ok) { print('  ok: ' + msg); pass++; } else { print('  FAIL: ' + msg + ' :: ' + (dbg||'')); fail++; } };
const withPhoto = avatarEl('ana', 'Ana Souza', 28);
const img = withPhoto.children.find(c => c && c.tagName === 'img');
ck('sem hasPhoto: cria o <img> da foto', !!img, JSON.stringify(withPhoto.children.map(c => c && c.tagName)));
if (img) {
  ck('loading=lazy e decoding=async', img.attrs.loading === 'lazy' && img.attrs.decoding === 'async', JSON.stringify(img.attrs));
  const o = img.order;
  ck('loading vem ANTES do src (senão o download já começou)', o.indexOf('loading') >= 0 && o.indexOf('loading') < o.indexOf('src'), o.join(','));
  ck('src = a rota da foto do treino', String(img.attrs.src).includes('/api/v1/treino/profile/photo?user=ana'), img.attrs.src);
}
const noPhoto = avatarEl('bia', 'Bia', 28, false);
ck('hasPhoto === false: nenhum <img> (só as iniciais — sem 404)', !noPhoto.children.some(c => c && c.tagName === 'img'), JSON.stringify(noPhoto.children.map(c => c && (c.tagName || 'texto'))));
print(''); print('RESULT: ' + pass + ' passed, ' + fail + ' failed');
if (fail) imports.system.exit(1);
"
