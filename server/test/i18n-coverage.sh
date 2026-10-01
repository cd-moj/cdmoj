#!/bin/bash
# i18n-coverage.sh — a interface é TRILÍNGUE (pt/en/es; docs/I18N.md) e este teste é a porta:
#   1. toda chamada T(…) do web/ tem 3 argumentos (pt, en, es) — lido pelo AST (gjs), não por regex:
#      template com ${T('a','b')} dentro, chamada multilinha e concatenação enganam grep;
#   2. todo data-en[-html|-ph|-title|-doctitle] do HTML tem o data-es correspondente NA MESMA TAG;
#   3. o espanhol não traz marca de português (ã, õ, ç, "não", "você", "-ção"…) — o sintoma de
#      tradução esquecida ou colada do PT;
#   4. os textos que o servidor manda à Central (checklist, encerrar evento, bloqueios de rodada)
#      só usam os helpers trilíngues (add3/_add com 3 idiomas) — o antigo `add` só-PT sumiu;
#   5. link para doc TRADUZIDO (docs/i18n.sh) abre no idioma da tela: data-en-href/data-es-href no
#      HTML, docHref() no JS — link novo não nasce só-PT.
# Roda sem subir nada. Precisa de gjs e python3 (os outros *.gjs.sh já precisam).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; [[ -n "${3:-}" ]] && printf '%s\n' "$3" | head -20 | sed 's/^/        /'; ((fail++)); fi; }
command -v gjs >/dev/null 2>&1 || { echo "SKIP: sem gjs"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: sem python3"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$ROOT" || exit 1
git ls-files 'web/*.js' 'web/**/*.js' | grep -v '^web/shared/vendor/' | sort -u > "$T/js.txt"
git ls-files 'web/*.html' 'web/**/*.html' | grep -v '^web/shared/vendor/' | sort -u > "$T/html.txt"

# --- 1+3 (JS): cada T(…) pelo AST ------------------------------------------------------------
cat > "$T/t.js" <<'EOF'
const GLib = imports.gi.GLib;
const bad = [], es = [];
function walk(n, f, src) {
  if (!n || typeof n !== 'object') return;
  if (Array.isArray(n)) { for (const x of n) walk(x, f, src); return; }
  if (n.type === 'CallExpression' && n.callee && n.callee.type === 'Identifier' && n.callee.name === 'T') {
    if (n.arguments.length !== 3) bad.push(f + ':' + n.loc.start.line + ' (' + n.arguments.length + ' args)');
    else {
      const a = n.arguments[2];
      if (a.type === 'Literal' && typeof a.value === 'string') es.push({ w: f + ':' + a.loc.start.line, s: a.value });
      else if (a.type === 'TemplateLiteral') es.push({ w: f + ':' + a.loc.start.line, s: a.elements.filter(e => e.type === 'Literal').map(e => e.value).join(' ') });
    }
  }
  for (const k in n) if (k !== 'loc') walk(n[k], f, src);
}
const [, list] = GLib.file_get_contents(ARGV[0]);
for (const f of new TextDecoder().decode(list).split('\n').filter(Boolean)) {
  const [, b] = GLib.file_get_contents(f); const src = new TextDecoder().decode(b);
  try { walk(Reflect.parse(src, { target: 'module' }), f, src); } catch (e) { bad.push(f + ': SINTAXE ' + e.message); }
}
print(JSON.stringify({ bad, es }));
EOF
gjs "$T/t.js" "$T/js.txt" > "$T/js.json" 2>"$T/js.err"
ck "extrator AST rodou" '[[ -s "$T/js.json" ]]' "$(cat "$T/js.err")"
BAD="$(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["bad"]))' "$T/js.json" 2>/dev/null)"
ck "toda chamada T(…) do web/ tem 3 argumentos (pt, en, es)" '[[ -z "$BAD" ]]' "$BAD"

# marca de português no espanhol. O PT de verdade tem ã/õ/ç e estas palavras; o espanhol, não.
# Nome próprio brasileiro legítimo num texto em espanhol entra na allowlist (com o porquê).
cat > "$T/pt.py" <<'EOF'
import json, re, sys
PT = re.compile(r"[ãõçÃÕÇ]|\b(não|você|vocês|também|então|até|já|mais|uma|seu|sua|sem|quando|ainda|usuário|senha|arquivo|equipe|placar|submissão|submissões|balão|balões|prova)\b|ções\b|ção\b", re.I)
ALLOW = re.compile(r"nota-sem-traducao|\blogin[:,]senha[:,]nome\b|Maratona SBC de Programação|Sociedade Brasileira de Computação|Olimpíada Brasileira de Informática|Programação|\bOBI\b|moj\.naquadah|conceição|priority=prova\b", re.I)   # priority=prova: valor do comando, não texto
out = []
for w, s in json.load(open(sys.argv[1])):
    t = ALLOW.sub('', s)
    m = PT.search(t)
    if m: out.append(f"{w}: '{m.group(0)}' em: {s[:90]}")
print("\n".join(out))
EOF
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); json.dump([[x["w"],x["s"]] for x in d["es"]], open(sys.argv[2],"w"))' "$T/js.json" "$T/es-js.json"
PTJS="$(python3 "$T/pt.py" "$T/es-js.json")"
ck "o 3º argumento (es) não tem marca de português" '[[ -z "$PTJS" ]]' "$PTJS"

# --- 2+3 (HTML): data-es na MESMA tag de cada data-en ------------------------------------------
cat > "$T/h.py" <<'EOF'
import sys, json
from html.parser import HTMLParser
miss, es = [], []
class P(HTMLParser):
    def __init__(s, f): super().__init__(convert_charrefs=True); s.f = f
    def handle_starttag(s, tag, attrs):
        d = dict(attrs)
        for k, v in d.items():
            if k.startswith('data-en'):
                ek = 'data-es' + k[len('data-en'):]
                if ek not in d: miss.append(f"{s.f}:{s.getpos()[0]} <{tag} {k}> sem {ek}")
            if k.startswith('data-es') and v: es.append([f"{s.f}:{s.getpos()[0]}", v])
for f in open(sys.argv[1]).read().split():
    p = P(f); p.feed(open(f, encoding='utf-8').read()); p.close()
json.dump({'miss': miss, 'es': es}, open(sys.argv[2], 'w'), ensure_ascii=False)
EOF
python3 "$T/h.py" "$T/html.txt" "$T/h.json"
MISS="$(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["miss"]))' "$T/h.json")"
ck "todo data-en* do HTML tem o data-es* na mesma tag" '[[ -z "$MISS" ]]' "$MISS"
python3 -c 'import json,sys; json.dump(json.load(open(sys.argv[1]))["es"], open(sys.argv[2],"w"))' "$T/h.json" "$T/es-h.json"
PTH="$(python3 "$T/pt.py" "$T/es-h.json")"
ck "data-es* não tem marca de português" '[[ -z "$PTH" ]]' "$PTH"

# --- 5: link para doc TRADUZIDO (docs/i18n.sh DOCS_I18N) abre no idioma da tela ---------------------
# HTML: <a href="/docs/X.html"> leva data-en-href="/docs/en/X.html" data-es-href="/docs/es/X.html";
# JS: nunca a string '/docs/X.html' crua — docHref('X') (web/shared/i18n.js)
DOCSL="$(bash "$ROOT/docs/i18n.sh" list 2>/dev/null | tr '\n' ' ')"
cat > "$T/dl.py" <<'EOF'
import sys, re
from html.parser import HTMLParser
docs = set(sys.argv[2].split()); bad = []
class P(HTMLParser):
    def __init__(s, f): super().__init__(convert_charrefs=True); s.f = f
    def handle_starttag(s, tag, attrs):
        d = dict(attrs); m = re.match(r'^/docs/([^/?#]+)\.html(.*)$', d.get('href') or '')
        if tag != 'a' or not m or m.group(1) not in docs: return
        x, rest = m.group(1), m.group(2)
        for l in ('en', 'es'):
            if d.get('data-%s-href' % l) != '/docs/%s/%s.html%s' % (l, x, rest):
                bad.append('%s:%d <a href="/docs/%s.html"> sem data-%s-href="/docs/%s/%s.html"' % (s.f, s.getpos()[0], x, l, l, x))
for f in open(sys.argv[1]).read().split():
    p = P(f); p.feed(open(f, encoding='utf-8').read()); p.close()
print('\n'.join(bad))
EOF
DL="$(python3 "$T/dl.py" "$T/html.txt" "$DOCSL")"
ck "link HTML p/ doc traduzido leva data-en-href/data-es-href" '[[ -z "$DL" ]]' "$DL"
DJ=""; for x in $DOCSL; do DJ+="$(grep -nE "['\"\`]/docs/$x\.html" $(cat "$T/js.txt") 2>/dev/null)"; done
ck "JS não cita /docs/<traduzido>.html cru (use docHref)" '[[ -z "$DJ" ]]' "$DJ"

# --- 4: servidor → Central (texto que vira tela) ------------------------------------------------
A="$ROOT/server/api/v1"
OLD="$(grep -nE '^\s*(add|add2) [a-z_]+ ' "$A/handlers/contest/admin/preflight.sh" "$A/handlers/contest/admin/finish.sh" 2>/dev/null; grep -nE '(^|[;&|{]\s*|\s)(add|add2) [a-z_]+ (ok|warn|fail|"\$)' "$A/handlers/contest/admin/preflight.sh" "$A/handlers/contest/admin/finish.sh" 2>/dev/null)"
ck "preflight/finish só usam add3 (pt+en+es)" '[[ -z "$OLD" ]]' "$OLD"
R1="$(grep -nE '_add [a-z_]+ "[^"]*"\s*$' "$A/lib/contest-rounds.sh" 2>/dev/null)"
ck "bloqueios de rodada levam detail pt+en+es" '[[ -z "$R1" ]]' "$R1"

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
