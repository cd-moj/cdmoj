#!/bin/bash
# smoke-editor-conflict.gjs.sh — a caixa de CONFLITO do editor de problemas (web/problemas/editar.js):
# quando o /problems/edit responde 409 `stale_rev`, a tela diz QUEM mudou e QUANDO e oferece
# "Recarregar" (loadSource) e "Salvar por cima" (reenvia com force). Extrai hideConflict/showConflict
# do editar.js e roda num DOM falso (gjs) — o editor inteiro puxa CodeMirror e não cabe aqui.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; WEB="$(cd "$HERE/../../web" && pwd)"
command -v gjs >/dev/null 2>&1 || { echo "editor-conflict: gjs ausente — pulando"; exit 0; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
awk '/^function hideConflict\(\)/,/^async function save\(/' "$WEB/problemas/editar.js" | sed '$d' > "$W/fn.js"
[[ -s "$W/fn.js" ]] || { echo "FALHOU: não achei showConflict/hideConflict no editar.js"; exit 1; }
{ cat <<'JS'
function N(tag) { this.tag = tag; this.kids = []; this.attrs = {}; this.style = {}; this.nodeType = 1; this.parentNode = null; this.on = {}; }
N.prototype.append = function (...k) { k.forEach((x) => { const n = x && x.nodeType ? x : { nodeType: 3, text: String(x) }; n.parentNode = this; this.kids.push(n); }); };
N.prototype.insertBefore = function (n, ref) { n.parentNode = this; const i = this.kids.indexOf(ref); this.kids.splice(i < 0 ? this.kids.length : i, 0, n); };
N.prototype.remove = function () { if (this.parentNode) this.parentNode.kids = this.parentNode.kids.filter((k) => k !== this); this.parentNode = null; };
N.prototype.all = function () { const o = []; this.kids.forEach((k) => { if (k.nodeType === 1) { o.push(k); o.push(...k.all()); } }); return o; };
Object.defineProperty(N.prototype, 'textContent', { get() { return this.kids.map((k) => (k.nodeType === 3 ? k.text : k.textContent)).join(''); } });
const root = new N('body'); const msg = new N('div'); msg.attrs.id = 'msg'; root.append(msg);
const $ = (id) => root.all().find((n) => n.attrs.id === id) || null;
function el(tag, attrs, ...kids) { const n = new N(tag); for (const [k, v] of Object.entries(attrs || {})) { if (k.startsWith('on')) n.on[k.slice(2)] = v; else n.attrs[k] = v; } n.append(...kids.flat().filter((x) => x !== null && x !== undefined && x !== '')); return n; }
function T(pt, en) { return pt; }
let CONFIRM = true; function confirm() { return CONFIRM; }
let ID = 'col#pa', LOADED = 0, MSG = ''; async function loadSource() { LOADED++; hideConflict(); } function setMsg(t) { MSG = t; }
JS
  cat "$W/fn.js"
  cat <<'JS'
(async () => {
  const e = { code: 'stale_rev', data: { changed_by: 'bob', changed_at: 1790000000, current_rev: 'abc' } };
  let retried = 0; const retry = async () => { retried++; };
  showConflict(e, retry);
  const box = $('revConflict');
  print('box=' + !!box);
  print('before_msg=' + (root.kids.indexOf(box) === root.kids.indexOf(msg) - 1));
  print('names_who=' + box.textContent.includes('bob'));
  const btns = box.all().filter((n) => n.tag === 'button');
  print('buttons=' + btns.length);
  showConflict(e, retry); print('single_box=' + (root.all().filter((n) => n.attrs.id === 'revConflict').length === 1));
  CONFIRM = false; await $('revConflict').all().filter((n) => n.tag === 'button')[1].on.click(); print('cancel_keeps=' + (retried === 0 && !!$('revConflict')));
  CONFIRM = true; await $('revConflict').all().filter((n) => n.tag === 'button')[1].on.click(); print('save_over=' + (retried === 1 && !$('revConflict')));
  showConflict(e, retry); await $('revConflict').all().filter((n) => n.tag === 'button')[0].on.click(); print('reload=' + (LOADED === 1 && !$('revConflict')));
})().catch((x) => print('ERRO ' + x + '\n' + x.stack));
JS
} > "$W/t.js"
gjs "$W/t.js" > "$W/out" 2> "$W/err"
pass=0; fail=0; ck(){ if grep -qx "$2=true" "$W/out" || grep -qx "$2=$3" "$W/out"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 ($(grep "^$2=" "$W/out"))"; ((fail++)); fi; }
ck "a caixa aparece no 409"                       box
ck "…logo acima da mensagem do Salvar"            before_msg
ck "…dizendo QUEM mudou"                          names_who
ck "…com os dois botões (Recarregar / Salvar por cima)" buttons 2
ck "nunca duas caixas empilhadas"                 single_box
ck "Salvar por cima pede confirmação (cancelar não reenvia)" cancel_keeps
ck "Salvar por cima confirmado reenvia (force) e some a caixa" save_over
ck "Recarregar chama o loadSource e some a caixa" reload
[[ -s "$W/err" ]] && { echo "  stderr:"; head -5 "$W/err"; }
echo; echo "RESULT: $pass passed, $fail failed"; [[ $fail -eq 0 ]]
