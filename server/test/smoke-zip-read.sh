#!/bin/bash
# smoke-zip-read.sh — o LEITOR de .zip do navegador (web/shared/zip-read.js, 09/11/2026: o lote do telão aceita
# pacote .zip; o zip é aberto NA PÁGINA e cada arquivo segue pela rota de sempre — o servidor não descompacta).
# Roda o módulo REAL no Node (Blob/File/DecompressionStream nativos), com o i18n trocado por um T que devolve o PT.
#   · deflate e guardado, em pasta; `base` = só o nome; pasta, __MACOSX/ e oculto (.DS_Store) ficam de fora;
#   · o conteúdo descompactado bate byte a byte;
#   · zip cifrado, método desconhecido, arquivo acima do teto, mais arquivos que o teto e "não é zip" = erro claro;
#   · zip que MENTE o tamanho (declara pouco e descompacta muito) para no teto declarado.
# Sem node (ou node sem DecompressionStream): pula (rc 0).
set -u
command -v node >/dev/null 2>&1 || { echo "zip-read: node ausente — pulando"; exit 0; }
node -e 'process.exit(typeof DecompressionStream === "function" && typeof File === "function" ? 0 : 1)' 2>/dev/null \
  || { echo "zip-read: node sem DecompressionStream/File — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
cp "$WEB/shared/zip-read.js" "$W/zip-read.mjs"
sed -i "s#from './i18n.js'#from './i18n.mjs'#" "$W/zip-read.mjs"
printf 'export const T = (pt) => pt;\n' > "$W/i18n.mjs"

python3 - "$W" <<'PY'
import sys, zipfile, struct
W = sys.argv[1]
big = b'A' * 300000
z = zipfile.ZipFile(W + '/ok.zip', 'w')
z.writestr('team01.png', b'\x89PNG' + b'x' * 1000, compress_type=zipfile.ZIP_DEFLATED)
z.writestr('fotos/team03.JPG', b'jpgdata', compress_type=zipfile.ZIP_STORED)
z.writestr('musicas/team02.mp3', big, compress_type=zipfile.ZIP_DEFLATED)
z.writestr('__MACOSX/._team01.png', 'x'); z.writestr('.DS_Store', 'x'); z.writestr('fotos/.oculto', 'x')
z.writestr(zipfile.ZipInfo('fotos/'), '')
z.close()
z = zipfile.ZipFile(W + '/big.zip', 'w'); z.writestr('team01.mp3', b'B' * (3 * 1024 * 1024), compress_type=zipfile.ZIP_DEFLATED); z.close()
z = zipfile.ZipFile(W + '/many.zip', 'w')
for i in range(12): z.writestr('t%02d.png' % i, 'x')
z.close()
# cifrado: liga o bit 0 das flags no índice
d = bytearray(open(W + '/ok.zip', 'rb').read())
i = d.find(b'PK\x01\x02'); d[i + 8] |= 1
open(W + '/enc.zip', 'wb').write(d)
# método 12 (bzip2) no índice
d = bytearray(open(W + '/ok.zip', 'rb').read())
i = d.find(b'PK\x01\x02'); d[i + 10:i + 12] = struct.pack('<H', 12)
open(W + '/bz.zip', 'wb').write(d)
# MENTIROSO: declara 10 bytes descompactados, mas o deflate solta 2 MB
z = zipfile.ZipFile(W + '/liar.zip', 'w'); z.writestr('team01.mp3', b'C' * (2 * 1024 * 1024), compress_type=zipfile.ZIP_DEFLATED); z.close()
d = bytearray(open(W + '/liar.zip', 'rb').read())
i = d.find(b'PK\x01\x02'); d[i + 24:i + 28] = struct.pack('<I', 10)
open(W + '/liar.zip', 'wb').write(d)
open(W + '/not.zip', 'wb').write(b'isto nao e um zip' * 10)
open(W + '/big.bin', 'wb').write(big)
PY

cat > "$W/t.mjs" <<'JS'
import { readZip } from './zip-read.mjs';
import { readFileSync } from 'node:fs';
const W = process.argv[2];
let pass = 0, fail = 0;
const ck = (m, c, d) => { if (c) { pass++; console.log('  ok: ' + m); } else { fail++; console.log('  FAIL: ' + m + (d ? ' :: ' + d : '')); } };
const F = (n) => new File([readFileSync(W + '/' + n)], n);
const err = async (n, opts) => { try { await readZip(F(n), opts); return ''; } catch (e) { return e.message; } };
const es = await readZip(F('ok.zip'));
ck('3 arquivos (pasta, __MACOSX e ocultos fora)', es.length === 3, es.map((e) => e.name).join(','));
ck('base = só o nome do arquivo', es.map((e) => e.base).sort().join(',') === 'team01.png,team02.mp3,team03.JPG');
const mp3 = es.find((e) => e.base === 'team02.mp3');
const got = Buffer.from(await (await mp3.blob()).arrayBuffer());
ck('deflate descompacta byte a byte (300 KB)', got.equals(readFileSync(W + '/big.bin')));
ck('guardado (método 0) também', Buffer.from(await (await es.find((e) => e.base === 'team03.JPG').blob()).arrayBuffer()).toString() === 'jpgdata');
ck('não é zip = erro', (await err('not.zip')).includes('Não é um arquivo .zip'));
ck('cifrado = erro', (await err('enc.zip')).includes('cifrado'));
ck('método desconhecido = erro', (await err('bz.zip')).includes('método 12'));
ck('arquivo acima do teto = erro', (await err('big.zip', { maxEntryBytes: 1024 * 1024 })).includes('o máximo é 1 MB'));
ck('mais arquivos que o teto = erro', (await err('many.zip', { maxEntries: 10 })).includes('o máximo é 10'));
const liar = await readZip(F('liar.zip'));
let le = ''; try { await liar[0].blob(); } catch (e) { le = e.message; }
ck('zip que mente o tamanho para no declarado', le.includes('maior do que o zip declara'), le);
console.log(`\nRESULT: ${pass} passed, ${fail} failed`); process.exit(fail ? 1 : 0);
JS
cd "$W" && node "$W/t.mjs" "$W"
