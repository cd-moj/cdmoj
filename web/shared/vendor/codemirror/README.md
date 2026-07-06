# vendor/codemirror — CodeMirror 6 vendorizado (offline / LAN isolada)

`cm-bundle.js` é um bundle **ESM único, minificado**, com tudo que `shared/editor.js`
usa — o contest roda em rede isolada, então NADA pode vir de CDN (antes vinha de esm.sh).
Licença: MIT (CodeMirror, Marijn Haverbeke e contribuidores).

Conteúdo (exports): `EditorView`, `basicSetup` (codemirror@6.0.1); `StreamLanguage`
(@codemirror/language@6.10.1); `cpp` (lang-cpp@6.0.1), `python` (lang-python@6.1.6),
`java` (lang-java@6.0.1), `rust` (lang-rust@6.0.1), `go` (lang-go@6.0.1),
`javascript` (lang-javascript@6.2.2), `markdown` (lang-markdown@6.2.5); e os modos
legacy `csharp`/`kotlin`/`haskell`/`oCaml`/`pascal`/`shell`/`apl`/`gas`
(@codemirror/legacy-modes@6.4.0).

## Reconstruir (só ao atualizar versão)

```sh
mkdir /tmp/cmbuild && cd /tmp/cmbuild && npm init -y
npm install codemirror@6.0.1 @codemirror/language@6.10.1 @codemirror/legacy-modes@6.4.0 \
  @codemirror/lang-cpp@6.0.1 @codemirror/lang-python@6.1.6 @codemirror/lang-java@6.0.1 \
  @codemirror/lang-rust@6.0.1 @codemirror/lang-go@6.0.1 @codemirror/lang-javascript@6.2.2 \
  @codemirror/lang-markdown@6.2.5 esbuild
# entry.js = re-exports (a lista de exports acima; ver o cabeçalho do editor.js)
npx esbuild entry.js --bundle --format=esm --minify --legal-comments=none \
  --outfile=<cdmoj>/web/shared/vendor/codemirror/cm-bundle.js
```

Depois: `cp cm-bundle.js /tmp/x.mjs && node --check /tmp/x.mjs` e teste o editor na web
(realce em C/C++/Python + um legacy, ex. Pascal) com a rede externa bloqueada.
