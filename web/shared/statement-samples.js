// shared/statement-samples.js — os EXEMPLOS do enunciado, do lado do leitor (2026-09-16):
//   • decorateSamples(root): um botão "Copiar" em cada bloco de entrada/saída dos exemplos
//     (`.moj-exemplo > h3 + pre`, o markup ÚNICO de mojtools/statement-langs.sh). Idempotente —
//     as telas re-injetam o enunciado (troca de idioma, preview) e nunca podem duplicar botão.
//   • samplesZip(files): ZIP store-only feito à mão (não há lib de zip vendorizada) — UM download
//     com todos os exemplos, em vez de N downloads que disparam o aviso do navegador.
//   • downloadSamplesZip(samples, prefix, zipName): monta <prefix>/<name>.in|.out e baixa.
//   • SAMPLES_TAB_SCRIPT: a versão inline do "Copiar" p/ a aba blob: do contest (documento sem módulos).
// O `<pre>` é escapado no servidor ⇒ textContent devolve os bytes; o `$(…)` do bash comeu o `\n`
// final do arquivo, então o texto copiado/baixado ganha a quebra final de volta (o juiz lê arquivo
// com quebra no fim).
import { el } from '/shared/dom.js';
import { T } from '/shared/i18n.js';

export const sampleText = (pre) => { const t = pre.textContent || ''; return t && !t.endsWith('\n') ? t + '\n' : t; };

function selectNode(node) {
  try { const sel = window.getSelection(); const r = document.createRange(); r.selectNodeContents(node); sel.removeAllRanges(); sel.addRange(r); } catch { /* sem seleção */ }
}
export async function copyBlock(pre, btn) {
  const before = btn.textContent;
  try {
    if (!navigator.clipboard || !navigator.clipboard.writeText) throw new Error('no clipboard');
    await navigator.clipboard.writeText(sampleText(pre));
    btn.textContent = T('✓ copiado', '✓ copied'); btn.classList.add('ok');
  } catch {
    // http / permissão negada / blob: seleciona o bloco p/ o Ctrl+C da pessoa
    selectNode(pre); btn.textContent = T('selecionado — Ctrl+C', 'selected — Ctrl+C');
  }
  setTimeout(() => { btn.textContent = before; btn.classList.remove('ok'); }, 1500);
}
// decorateSamples(root) -> nº de botões criados nesta chamada (0 se já decorado / sem exemplos)
export function decorateSamples(root) {
  if (!root || !root.querySelectorAll) return 0;
  let n = 0;
  root.querySelectorAll('.moj-exemplo').forEach((ex) => {
    const kids = [...ex.children];
    for (let i = 0; i + 1 < kids.length; i++) {
      const h = kids[i], pre = kids[i + 1];
      if (!/^H[34]$/.test(h.tagName || '') || (pre.tagName || '') !== 'PRE' || h.dataset.copyReady) continue;
      h.dataset.copyReady = '1'; h.classList.add('sample-head');
      const btn = el('button', { type: 'button', class: 'sample-copy', title: T('Copiar este bloco', 'Copy this block') }, T('Copiar', 'Copy'));
      btn.dataset.copy = '1';
      btn.addEventListener('click', (e) => { e.preventDefault(); e.stopPropagation(); copyBlock(pre, btn); });
      h.append(btn); n++;
    }
  });
  return n;
}
// a mesma coisa, inline, p/ o documento blob: da aba "HTML" do contest (sem módulos ESM lá dentro).
// Delegação em .sample-copy; o texto do botão já foi posto pelo decorateSamples no DOM serializado.
export const SAMPLES_TAB_SCRIPT = `(function(){
  document.addEventListener('click', async function(e){
    var b = e.target && e.target.closest ? e.target.closest('button.sample-copy') : null; if (!b) return;
    e.preventDefault(); var pre = b.parentElement && b.parentElement.nextElementSibling; if (!pre || pre.tagName !== 'PRE') return;
    var t = pre.textContent || ''; if (t && t.slice(-1) !== '\\n') t += '\\n'; var before = b.textContent;
    try { if (!navigator.clipboard) throw 0; await navigator.clipboard.writeText(t); b.textContent = '\\u2713'; }
    catch (_) { try { var s = window.getSelection(), r = document.createRange(); r.selectNodeContents(pre); s.removeAllRanges(); s.addRange(r); } catch (__) {} b.textContent = 'Ctrl+C'; }
    setTimeout(function(){ b.textContent = before; }, 1500);
  });
})();`;

// ---- ZIP store-only ---------------------------------------------------------------------------
const CRC_TABLE = (() => { const t = new Uint32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1); t[n] = c >>> 0; } return t; })();
export function crc32(bytes) { let c = 0xFFFFFFFF; for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; }
// samplesZip([{name, text}]) -> Uint8Array (ZIP sem compressão; nomes em UTF-8, flag 0x0800)
export function samplesZip(files) {
  const enc = new TextEncoder(); const parts = []; const central = []; let offset = 0;
  const u16 = (v) => [v & 0xFF, (v >>> 8) & 0xFF]; const u32 = (v) => [v & 0xFF, (v >>> 8) & 0xFF, (v >>> 16) & 0xFF, (v >>> 24) & 0xFF];
  files.forEach((f) => {
    const name = enc.encode(f.name), data = typeof f.text === 'string' ? enc.encode(f.text) : f.text; const crc = crc32(data);
    const local = new Uint8Array([...u32(0x04034b50), ...u16(20), ...u16(0x0800), ...u16(0), ...u16(0), ...u16(0), ...u32(crc), ...u32(data.length), ...u32(data.length), ...u16(name.length), ...u16(0), ...name]);
    parts.push(local, data);
    central.push(new Uint8Array([...u32(0x02014b50), ...u16(20), ...u16(20), ...u16(0x0800), ...u16(0), ...u16(0), ...u16(0), ...u32(crc), ...u32(data.length), ...u32(data.length), ...u16(name.length), ...u16(0), ...u16(0), ...u16(0), ...u16(0), ...u32(0), ...u32(offset), ...name]));
    offset += local.length + data.length;
  });
  const cdSize = central.reduce((a, c) => a + c.length, 0);
  const end = new Uint8Array([...u32(0x06054b50), ...u16(0), ...u16(0), ...u16(files.length), ...u16(files.length), ...u32(cdSize), ...u32(offset), ...u16(0)]);
  const total = offset + cdSize + end.length; const out = new Uint8Array(total); let p = 0;
  [...parts, ...central, end].forEach((c) => { out.set(c, p); p += c.length; });
  return out;
}
export function downloadBlob(blob, filename) {
  const url = URL.createObjectURL(blob);
  const a = el('a', { href: url, download: filename }); document.body.append(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60000);
}
// downloadSamplesZip(samples, prefix, zipName): samples = [{name,input,output}] (da API);
// arquivos <prefix>/<name>.in e .out, com a quebra final garantida. Devolve o nº de exemplos.
export const downloadableSamples = (samples) => (Array.isArray(samples) ? samples.filter((s) => s && !s.too_big) : []);
export function downloadSamplesZip(samples, prefix, zipName) {
  const nl = (t) => (t && !t.endsWith('\n') ? t + '\n' : (t || ''));
  const safe = (s) => String(s || 'sample').replace(/[^A-Za-z0-9._-]/g, '_');
  const files = [];
  // too_big (2026-09-16): o servidor não manda os bytes de um exemplo acima do teto — sai do zip
  (samples || []).filter((s) => s && !s.too_big).forEach((s) => { files.push({ name: `${prefix}/${safe(s.name)}.in`, text: nl(s.input) }, { name: `${prefix}/${safe(s.name)}.out`, text: nl(s.output) }); });
  if (!files.length) return 0;
  downloadBlob(new Blob([samplesZip(files)], { type: 'application/zip' }), zipName);
  return files.length / 2;
}
