// shared/zip-read.js — LEITOR de .zip NO NAVEGADOR (09/11/2026, pedido do Emílio: subir as fotos e as músicas do
// telão num pacote só). O zip NUNCA vai ao servidor: a página abre o pacote aqui e cada arquivo segue pela rota de
// sempre, um por POST (a mesma do envio em lote) — o servidor não descompacta nada (zip bomb, `../` no nome).
//
// readZip(file, opts) → [{ name, base, size, blob() }]
//   name = caminho dentro do zip; base = só o nome do arquivo (sem pasta) — é o que vira o login.
//   Pula pastas, `__MACOSX/` e arquivos ocultos (`.DS_Store`, `._foto.jpg` do Mac).
//   Métodos: 0 (guardado) e 8 (deflate, pelo DecompressionStream('deflate-raw') do navegador). Outro método, zip
//   cifrado ou ZIP64 = Error com a mensagem para a pessoa.
//   Tetos (opts): maxEntries (5000), maxEntryBytes (20 MB, o tamanho DESCOMPACTADO declarado), maxTotalBytes (2 GB).
//   O tamanho declarado é conferido de novo depois de descompactar (um zip mentiroso não passa do teto).
import { T } from './i18n.js';

const SIG_EOCD = 0x06054b50, SIG_CEN = 0x02014b50, SIG_LOC = 0x04034b50;

export async function readZip(file, opts = {}) {
  const maxEntries = opts.maxEntries || 5000;
  const maxEntryBytes = opts.maxEntryBytes || 20 * 1024 * 1024;
  const maxTotalBytes = opts.maxTotalBytes || 2 * 1024 * 1024 * 1024;
  const bad = (pt, en, es) => new Error(T(pt, en, es));
  // o fim do arquivo: o registro EOCD (22 bytes + comentário de até 64 KB)
  const tailLen = Math.min(file.size, 22 + 65535);
  const tail = new DataView(await file.slice(file.size - tailLen).arrayBuffer());
  let eocd = -1;
  for (let i = tailLen - 22; i >= 0; i--) { if (tail.getUint32(i, true) === SIG_EOCD) { eocd = i; break; } }
  if (eocd < 0) throw bad('Não é um arquivo .zip válido.', 'This is not a valid .zip file.', 'No es un archivo .zip válido.');
  const count = tail.getUint16(eocd + 10, true);
  const cenSize = tail.getUint32(eocd + 12, true);
  const cenOff = tail.getUint32(eocd + 16, true);
  if (count === 0xffff || cenOff === 0xffffffff) throw bad('Zip grande demais (ZIP64): divida em pacotes menores.', 'Zip too large (ZIP64): split it into smaller packages.', 'Zip demasiado grande (ZIP64): divídelo en paquetes más pequeños.');
  if (count > maxEntries) throw bad(`O zip tem ${count} arquivos; o máximo é ${maxEntries}.`, `The zip has ${count} files; the maximum is ${maxEntries}.`, `El zip tiene ${count} archivos; el máximo es ${maxEntries}.`);
  if (cenOff + cenSize > file.size) throw bad('Zip corrompido (índice).', 'Corrupted zip (index).', 'Zip dañado (índice).');
  const cen = new DataView(await file.slice(cenOff, cenOff + cenSize).arrayBuffer());
  // NOME: o zip marca UTF-8 no bit 11 das flags; sem ele, o do Windows grava na página de código local (CP437/1252) e o
  // UTF-8 estrito falha — aí vai o windows-1252 (o login é ASCII, que as duas leem igual; acento sai legível)
  const utf8 = new TextDecoder('utf-8', { fatal: true }), legacy = new TextDecoder('windows-1252');
  const decName = (u8, flags) => { if (flags & 0x800) return new TextDecoder().decode(u8); try { return utf8.decode(u8); } catch { return legacy.decode(u8); } };
  const out = [];
  let p = 0, total = 0;
  for (let k = 0; k < count; k++) {
    if (p + 46 > cen.byteLength || cen.getUint32(p, true) !== SIG_CEN) throw bad('Zip corrompido (índice).', 'Corrupted zip (index).', 'Zip dañado (índice).');
    const flags = cen.getUint16(p + 8, true), method = cen.getUint16(p + 10, true);
    const csize = cen.getUint32(p + 20, true), usize = cen.getUint32(p + 24, true);
    const nlen = cen.getUint16(p + 28, true), xlen = cen.getUint16(p + 30, true), clen = cen.getUint16(p + 32, true);
    const loc = cen.getUint32(p + 42, true);
    if (p + 46 + nlen > cen.byteLength) throw bad('Zip corrompido (índice).', 'Corrupted zip (index).', 'Zip dañado (índice).');
    const name = decName(new Uint8Array(cen.buffer, cen.byteOffset + p + 46, nlen), flags);
    p += 46 + nlen + xlen + clen;
    const base = name.split('/').pop();
    if (!base || name.endsWith('/') || /(^|\/)__MACOSX\//.test(name) || base.startsWith('.')) continue;
    if (flags & 1) throw bad(`"${name}" está cifrado: o zip não pode ter senha.`, `"${name}" is encrypted: the zip cannot have a password.`, `"${name}" está cifrado: el zip no puede tener contraseña.`);
    if (method !== 0 && method !== 8) throw bad(`"${name}" usa uma compressão que o navegador não abre (método ${method}).`, `"${name}" uses a compression the browser cannot open (method ${method}).`, `"${name}" usa una compresión que el navegador no abre (método ${method}).`);
    if (usize > maxEntryBytes) throw bad(`"${name}" tem ${Math.round(usize / 1048576)} MB; o máximo é ${Math.round(maxEntryBytes / 1048576)} MB.`, `"${name}" has ${Math.round(usize / 1048576)} MB; the maximum is ${Math.round(maxEntryBytes / 1048576)} MB.`, `"${name}" tiene ${Math.round(usize / 1048576)} MB; el máximo es ${Math.round(maxEntryBytes / 1048576)} MB.`);
    total += usize;
    if (total > maxTotalBytes) throw bad('O zip descompactado passa do teto.', 'The unzipped content is over the limit.', 'El contenido descomprimido supera el límite.');
    out.push({ name, base, size: usize, blob: () => entryBlob(file, loc, method, csize, usize, name, bad) });
  }
  return out;
}

async function entryBlob(file, loc, method, csize, usize, name, bad) {
  // TRUNCADO OU CORROMPIDO dá a MESMA mensagem clara (revisão de 10/11/2026): antes o arquivo cortado saía MENOR e
  // calado (o servidor recebia meia foto) e o deflate quebrado subia o TypeError cru do navegador
  const broken = () => bad(`Zip corrompido em "${name}".`, `Corrupted zip at "${name}".`, `Zip dañado en "${name}".`);
  if (loc + 30 > file.size) throw broken();
  const h = new DataView(await file.slice(loc, loc + 30).arrayBuffer());
  if (h.getUint32(0, true) !== SIG_LOC) throw broken();
  const start = loc + 30 + h.getUint16(26, true) + h.getUint16(28, true);
  if (start + csize > file.size) throw broken();
  const raw = file.slice(start, start + csize);
  if (method === 0) { if (csize !== usize) throw broken(); return raw; }
  const ds = raw.stream().pipeThrough(new DecompressionStream('deflate-raw'));
  const r = ds.getReader(); const parts = []; let n = 0;
  for (;;) {
    let step;
    try { step = await r.read(); } catch { throw broken(); }
    const { done, value } = step;
    if (done) break;
    n += value.byteLength;
    if (n > usize) { try { r.cancel(); } catch (e) { /* já parou */ } throw bad(`"${name}" é maior do que o zip declara.`, `"${name}" is larger than the zip declares.`, `"${name}" es más grande de lo que el zip declara.`); }
    parts.push(value);
  }
  if (n !== usize) throw broken();      // descompactou MENOS do que o zip declara
  return new Blob(parts);
}
