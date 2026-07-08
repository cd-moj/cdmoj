# GET /problems/script-templates   (Bearer)
# TEMPLATES de corretor especial p/ o editor web: lê $MOJTOOLS_DIR/script-templates/<key>/
# ({template.json, files/…}) e devolve cada template com os arquivos NO MESMO SHAPE do campo
# scripts_files do source/edit ([{path,content_b64,exec}|{path,symlink}]) — "aplicar" na UI é
# só preencher a seção de correção especial e salvar. Criar template novo = criar uma pasta
# no mojtools (sem código). Regra de symlink do template: alvo DENTRO de files/ vira entrada
# {path,symlink} (drivers interativos scripts/<lang> -> c); alvo FORA (canônicos do mojtools,
# ex.: compare.sh -> testlib/checker-bridge.sh) tem o CONTEÚDO resolvido (fonte única).
require_method GET
require_auth

TDIR="$MOJTOOLS_DIR/script-templates"
[[ -d "$TDIR" ]] || { emit_json 200 OK; jq -cn '{success:true, templates:[]}'; exit 0; }

D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT
: > "$D/templates.ndjson"

while IFS= read -r tdir; do
  key="$(basename "$tdir")"
  [[ "$key" =~ ^[a-z0-9._-]+$ ]] || continue
  meta='{}'; [[ -f "$tdir/template.json" ]] && meta="$(jq -c . "$tdir/template.json" 2>/dev/null)"; [[ -n "$meta" ]] || meta='{}'
  froot="$tdir/files"; [[ -d "$froot" ]] || continue
  frootr="$(realpath -m "$froot")"
  : > "$D/files.ndjson"
  while IFS= read -r f; do
    rel="${f#"$froot"/}"
    if [[ -L "$f" ]]; then
      tgt="$(readlink "$f")"
      rp="$(realpath -m "$(dirname "$f")/$tgt")"
      if [[ "$rp" == "$frootr" || "$rp" == "$frootr"/* ]]; then
        # symlink interno (ex.: cpp -> c): preserva como symlink
        jq -nc --arg p "$rel" --arg t "$tgt" '{path:$p, symlink:$t}' >> "$D/files.ndjson"
      elif [[ -f "$rp" ]]; then
        # symlink p/ um canônico do mojtools: resolve o CONTEÚDO (nunca vaza symlink externo)
        base64 -w0 < "$rp" > "$D/b64" 2>/dev/null || continue
        x=false; [[ -x "$rp" ]] && x=true
        jq -nc --arg p "$rel" --argjson x "$x" --rawfile c "$D/b64" '{path:$p, content_b64:$c, exec:$x}' >> "$D/files.ndjson"
      fi
    elif [[ -f "$f" ]]; then
      base64 -w0 < "$f" > "$D/b64" 2>/dev/null || continue
      x=false; [[ -x "$f" ]] && x=true
      jq -nc --arg p "$rel" --argjson x "$x" --rawfile c "$D/b64" '{path:$p, content_b64:$c, exec:$x}' >> "$D/files.ndjson"
    fi
  done < <(find "$froot" \( -type f -o -type l \) 2>/dev/null | LC_ALL=C sort)
  jq -nc --arg key "$key" --argjson meta "$meta" --slurpfile files "$D/files.ndjson" \
    '{key:$key, name:($meta.name // $key), description:($meta.description // ""),
      conf_hints:($meta.conf_hints // ""), files:$files}' >> "$D/templates.ndjson"
done < <(find "$TDIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort)

emit_json 200 OK
jq -cn --slurpfile t "$D/templates.ndjson" '{success:true, templates:$t}'
