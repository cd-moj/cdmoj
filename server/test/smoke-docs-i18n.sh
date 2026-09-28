#!/bin/bash
# smoke-docs-i18n.sh — a documentação de USUÁRIO em pt · en · es (docs/I18N.md, seção "Documentação").
# O PT (docs/<DOC>.md) é a fonte; a tradução (docs/en|es/<DOC>.md) vai no MESMO commit que muda o PT.
# Este teste é a porta. Ele reprova se:
#   1. falta docs/en ou docs/es de um doc da lista (docs/i18n.sh DOCS_I18N), ou há tradução fora dela;
#   2. o CARIMBO da tradução (1ª linha, blob do git do PT) ≠ o blob atual do PT — tradução ATRASADA
#      (a mensagem diz o comando: bash docs/i18n.sh diff <DOC>);
#   3. a ESTRUTURA diverge: títulos por nível, blocos de código, tabelas, imagens;
#   4. um COMANDO diverge: bloco bash/sh/console/conf/json igual ao PT tirando só os comentários
#      (`(^|\s)#…` — nunca `#…` cru: `col#pa`, `<org>#<prob>` são ids, não comentário);
#   5. link relativo que não resolve, ou /docs/X.html de doc que não existe;
#   6. o espanhol tem marca de português FORA de código (bloco e `em linha`, onde o PT é legítimo:
#      saída da CLI, nome de exemplo) — mesma heurística do i18n-coverage.sh;
#   7. o DOCS_I18N do docs/i18n.sh ≠ o do web/shared/i18n.js.
# E prova a si mesmo numa árvore sintética: os casos que TÊM de reprovar e os que NÃO podem.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: sem python3"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: sem git"; exit 0; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; [[ -n "${3:-}" ]] && printf '%s\n' "$3" | head -30 | sed 's/^/        /'; ((fail++)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

cat > "$T/check.py" <<'PY'
import os, re, subprocess, sys
docs, i18njs = sys.argv[1], sys.argv[2]

def sh_list(path):
    s = open(path, encoding='utf-8').read()
    m = re.search(r'^DOCS_I18N=\(([^)]*)\)', s, re.M)
    return m.group(1).split() if m else None

def js_list(path):
    s = open(path, encoding='utf-8').read()
    m = re.search(r'export const DOCS_I18N = \[([^\]]*)\]', s)
    return re.findall(r"'([^']+)'", m.group(1)) if m else None

def blob(p):
    return subprocess.run(['git', '-C', os.path.dirname(p) or '.', 'hash-object', p],
                          capture_output=True, text=True).stdout.strip()

FENCE = re.compile(r'^(\s*)(```+|~~~+)\s*([\w+-]*)')
CMDL = {'bash', 'sh', 'shell', 'console', 'conf', 'json', 'ini', 'toml', 'yaml'}

def parse(path):
    """títulos por nível, blocos [(lang, texto)], nº de tabelas, imagens, links, texto fora de código"""
    lines = open(path, encoding='utf-8').read().split('\n')
    heads, blocks, tables, prose = {}, [], 0, []
    i, n = 0, len(lines)
    while i < n:
        l = lines[i]
        m = FENCE.match(l)
        if m:
            mark, lang, buf = m.group(2), (m.group(3) or '').lower(), []
            i += 1
            while i < n and not lines[i].strip().startswith(mark[:3]):
                buf.append(lines[i]); i += 1
            blocks.append((lang, '\n'.join(buf)))
            i += 1
            continue
        h = re.match(r'^(#{1,6})\s', l)
        if h:
            heads[len(h.group(1))] = heads.get(len(h.group(1)), 0) + 1
        if re.match(r'^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$', l) and '|' in l:
            tables += 1
        prose.append(l)
        i += 1
    text = '\n'.join(prose)
    imgs = sorted(re.findall(r'!\[[^\]]*\]\(([^)\s]+)', text))
    links = re.findall(r'(?<!!)\[[^\]]*\]\(([^)\s]+)', text)
    return heads, blocks, tables, imgs, links, text

def strip_comments(t):
    out = []
    for l in t.split('\n'):
        l = re.sub(r'(^|\s)#.*$', r'\1', l).rstrip()
        out.append(l)
    return '\n'.join(x for x in out if x.strip())

PT = re.compile(r"[ãõçÃÕÇ]|\b(não|você|vocês|também|então|até|já|mais|uma|seu|sua|sem|quando|ainda|usuário|senha|arquivo|equipe|placar|submissão|submissões|balão|balões|prova)\b|ções\b|ção\b", re.I)
ALLOW = re.compile(r"Maratona SBC de Programação|Sociedade Brasileira de Computação|Olimpíada Brasileira de Informática|Programação|\bOBI\b|moj\.naquadah|conceição", re.I)

errs = []
lst = sh_list(os.path.join(docs, 'i18n.sh'))
jl = js_list(i18njs)
if lst is None: errs.append('docs/i18n.sh sem DOCS_I18N=(…)')
if jl is None: errs.append('web/shared/i18n.js sem export const DOCS_I18N = […]')
lst = lst or []
if jl is not None and sorted(jl) != sorted(lst):
    errs.append('7: DOCS_I18N difere: docs/i18n.sh=%s × web/shared/i18n.js=%s' % (sorted(lst), sorted(jl)))
for lang in ('en', 'es'):
    d = os.path.join(docs, lang)
    if os.path.isdir(d):
        for f in sorted(os.listdir(d)):
            if f.endswith('.md') and f[:-3] not in lst:
                errs.append('1: %s/%s está fora da lista DOCS_I18N (docs/i18n.sh)' % (lang, f))
for doc in lst:
    src = os.path.join(docs, doc + '.md')
    if not os.path.isfile(src):
        errs.append('1: %s.md (PT) não existe' % doc); continue
    b = blob(src)
    h0, bl0, tb0, im0, _, _ = parse(src)
    cmd0 = [strip_comments(t) for (lg, t) in bl0 if lg in CMDL]
    for lang in ('en', 'es'):
        f = os.path.join(docs, lang, doc + '.md')
        tag = '%s/%s.md' % (lang, doc)
        if not os.path.isfile(f):
            errs.append('1: falta %s' % tag); continue
        first = open(f, encoding='utf-8').readline()
        m = re.match(r'^<!-- i18n-source: (\S+)\.md blob:([0-9a-f]+) -->$', first.strip())
        if not m or m.group(1) != doc:
            errs.append('2: %s sem carimbo na 1ª linha (bash docs/i18n.sh stamp %s)' % (tag, doc))
        elif m.group(2) != b:
            errs.append('2: %s ATRASADO — o PT mudou desde a tradução. Veja: bash docs/i18n.sh diff %s' % (tag, doc))
        h1, bl1, tb1, im1, ln1, prose = parse(f)
        if h1 != h0: errs.append('3: %s títulos por nível %s × PT %s' % (tag, dict(sorted(h1.items())), dict(sorted(h0.items()))))
        if len(bl1) != len(bl0): errs.append('3: %s tem %d blocos de código × PT %d' % (tag, len(bl1), len(bl0)))
        if tb1 != tb0: errs.append('3: %s tem %d tabelas × PT %d' % (tag, tb1, tb0))
        if im1 != im0: errs.append('3: %s imagens %s × PT %s' % (tag, im1, im0))
        cmd1 = [strip_comments(t) for (lg, t) in bl1 if lg in CMDL]
        if len(cmd1) != len(cmd0):
            errs.append('4: %s tem %d blocos de comando × PT %d' % (tag, len(cmd1), len(cmd0)))
        else:
            for k, (a, c) in enumerate(zip(cmd0, cmd1)):
                if a != c:
                    d1 = [x for x in c.split('\n') if x not in a.split('\n')][:2]
                    errs.append('4: %s bloco de comando #%d difere do PT (só comentário se traduz): %s' % (tag, k + 1, d1))
        for t in ln1:
            p = t.split('#')[0].split('?')[0]
            if not p or re.match(r'^[a-z]+:', p) or p.startswith('//'):
                continue
            mm = re.match(r'^/docs/([^/]+)\.html$', p)
            if mm:
                if not os.path.isfile(os.path.join(docs, mm.group(1) + '.md')):
                    errs.append('5: %s link %s: doc inexistente' % (tag, t))
                continue
            if p.startswith('/'):
                continue
            if p.endswith('.md'):
                base = os.path.join(docs, lang) if not p.startswith('../') else docs
                name = os.path.basename(p)
                if not (os.path.isfile(os.path.join(base, name)) or os.path.isfile(os.path.join(docs, name))):
                    errs.append('5: %s link relativo %s não resolve' % (tag, t))
        if lang == 'es':
            plain = re.sub(r'`[^`\n]*`', ' ', prose)
            plain = re.sub(r'<!--.*?-->', ' ', plain, flags=re.S)
            plain = re.sub(r'\]\([^)]*\)', ']', plain)
            for ln_no, line in enumerate(plain.split('\n')):
                x = ALLOW.sub(' ', line)
                mm = PT.search(x)
                if mm:
                    errs.append('6: %s tem marca de português fora de código: «%s» em: %s' % (tag, mm.group(0), line.strip()[:90]))
                    break
print('\n'.join(errs))
sys.exit(1 if errs else 0)
PY

echo "== a documentação traduzida do repositório =="
OUTR="$(cd "$ROOT" && python3 "$T/check.py" "$ROOT/docs" "$ROOT/web/shared/i18n.js" 2>&1)"; rc=$?
N="$(bash "$ROOT/docs/i18n.sh" list | grep -c .)"
ck "docs traduzidos em dia, com a mesma estrutura do PT ($N na lista)" '[[ $rc == 0 ]]' "$OUTR"

echo "== o próprio lint, numa árvore sintética =="
F="$T/f"; mkdir -p "$F/docs/en" "$F/docs/es" "$F/web"
git -C "$F" init -q 2>/dev/null
cp "$ROOT/docs/i18n.sh" "$F/docs/i18n.sh"
sed -i 's/^DOCS_I18N=(.*)$/DOCS_I18N=(GUIA)/' "$F/docs/i18n.sh"
printf "export const DOCS_I18N = ['GUIA'];\n" > "$F/web/i18n.js"
cat > "$F/docs/GUIA.md" <<'MD'
# Guia

Texto em português, com `saída da CLI` e o link [outro](OUTRO.md).

## Passo

```bash
moj-contest -c prova docs set errata="**C**: onde se lê"   # comentário em português
PROBS=( x col#pa 'Soma Simples' A col#pa )
```

| a | b |
|---|---|
| 1 | 2 |

![](figura.png)
MD
printf '# Outro\n' > "$F/docs/OUTRO.md"
mk(){ # <lang> <título> <passo> <comentário> <frase>
  cat > "$F/docs/$1/GUIA.md" <<MD
# $2

> The CLI speaks Portuguese.

$5, with \`saída da CLI\` and the link [other](OUTRO.md).

## $3

\`\`\`bash
moj-contest -c prova docs set errata="**C**: onde se lê"   # $4
PROBS=( x col#pa 'Soma Simples' A col#pa )
\`\`\`

| a | b |
|---|---|
| 1 | 2 |

![](figura.png)
MD
}
mk en Guide Step "comment in English" "Text in English"
mk es Guía Paso "comentario en español" "Texto en español"
bash "$F/docs/i18n.sh" stamp GUIA >/dev/null
# como na vida real: PT e tradução carimbada no MESMO commit (o blob do carimbo passa a existir no git)
(cd "$F" && git add -A >/dev/null && git -c user.email=t@t -c user.name=t commit -qm base >/dev/null)
chk(){ (cd "$F" && python3 "$T/check.py" "$F/docs" "$F/web/i18n.js" 2>&1); }
O="$(chk)"; r=$?
ck "sintética em dia: passa (col#pa no comando, PT em \`código\`, blockquote da nota)" '[[ $r == 0 ]]' "$O"

cp "$F/docs/GUIA.md" "$T/guia.bak"; printf '\nLinha nova no PT.\n' >> "$F/docs/GUIA.md"
O="$(chk)"; r=$?
ck "PT mudou ⇒ ATRASADO, com o comando do diff" '[[ $r != 0 && "$O" == *"ATRASADO"*"bash docs/i18n.sh diff GUIA"* ]]' "$O"
D="$(cd "$F" && bash docs/i18n.sh diff GUIA 2>&1)"
ck "i18n.sh diff mostra a linha nova do PT" 'grep -q "^+Linha nova no PT." <<<"$D"' "$D"
cp "$T/guia.bak" "$F/docs/GUIA.md"

cp "$F/docs/es/GUIA.md" "$T/es.bak"
sed -i 's/Texto en español/Texto en español que não passa/' "$F/docs/es/GUIA.md"
O="$(chk)"; r=$?; ck "\"não\" no espanhol fora de código ⇒ reprova" '[[ $r != 0 && "$O" == *"6: es/GUIA.md"* ]]' "$O"
cp "$T/es.bak" "$F/docs/es/GUIA.md"

sed -i 's/col#pa/col#pb/' "$F/docs/en/GUIA.md"
O="$(chk)"; r=$?; ck "comando alterado na tradução ⇒ reprova" '[[ $r != 0 && "$O" == *"4: en/GUIA.md"* ]]' "$O"
sed -i 's/col#pb/col#pa/' "$F/docs/en/GUIA.md"

sed -i '/^## Step$/d' "$F/docs/en/GUIA.md"
O="$(chk)"; r=$?; ck "título faltando ⇒ reprova (paridade)" '[[ $r != 0 && "$O" == *"3: en/GUIA.md títulos"* ]]' "$O"
mk en Guide Step "comment in English" "Text in English"; bash "$F/docs/i18n.sh" stamp GUIA en >/dev/null

printf "export const DOCS_I18N = [];\n" > "$F/web/i18n.js"
O="$(chk)"; r=$?; ck "lista JS ≠ lista do i18n.sh ⇒ reprova" '[[ $r != 0 && "$O" == *"7: DOCS_I18N difere"* ]]' "$O"
printf "export const DOCS_I18N = ['GUIA'];\n" > "$F/web/i18n.js"

sed -i 's/(OUTRO.md)/(SUMIU.md)/' "$F/docs/es/GUIA.md"
O="$(chk)"; r=$?; ck "link relativo que não resolve ⇒ reprova" '[[ $r != 0 && "$O" == *"5: es/GUIA.md"* ]]' "$O"
cp "$T/es.bak" "$F/docs/es/GUIA.md"
O="$(chk)"; r=$?; ck "de volta ao estado bom: passa" '[[ $r == 0 ]]' "$O"

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
