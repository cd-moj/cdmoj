#!/bin/bash
# smoke-roles-registry.sh — o REGISTRO ÚNICO dos papéis (server/etc/roles.tsv, 09/11/2026) e a GUARDA contra réplica.
#   · lib/roles.sh: role_of / is_reserved_role_login / role_class / role_scoped / role_can / ROLE_RE (grep, awk, jq);
#   · os is_* do auth.sh batem com o registro (is_judge = julgar: judge, cjudge, admin);
#   · web/shared/roles.js é o que o server/bin/roles-gen.sh gera AGORA (ninguém editou à mão nem esqueceu de gerar);
#   · o porteiro lê o mesmo registro (ROLE_SUFFIX, role_of, role_can) e a cadeia do navbuttons.sh dá o mesmo `nav`;
#   · INVENTÁRIO: nenhuma linha de código (server/, web/; fora testes, docs e o próprio registro) escreve à mão uma
#     lista com 3+ sufixos de papel — `*.admin|*.judge|…`, `\.(admin|judge|…)`, `endswith((".staff", …))`. É assim
#     que a lista de 7 sufixos virou 76 cópias divergentes. Use ROLE_RE / role_* / roles.js. Comentário não conta.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 ${3:-}"; ((fail++)); fi; }

echo "== lib/roles.sh =="
source "$ROOT/server/api/v1/lib/roles.sh"
ck "11 papéis no registro"                      '(( ${#ROLE_SUFFIXES[@]} == 11 ))'
ck "role_of"                                    '[[ "$(role_of a.cstaff)" == cstaff && -z "$(role_of time1)" && -z "$(role_of x.adminx)" && -z "$(role_of admin)" ]]'
ck "classe: org × sala × time"                  '[[ "$(role_class p.diretor) $(role_class p.foto) $(role_class p)" == "org sala time" ]]'
ck "escopo: staff/cstaff/foto/musica/sistemas/diretor" '[[ "$(role_glob_scoped | tr "\n" " ")" == "*.staff *.cstaff *.foto *.musica *.sistemas *.diretor " ]]'
ck "role_can: admin pode tudo; foto só foto"    'role_can qualquer a.admin && role_can foto a.foto && ! role_can musica a.foto && ! role_can foto a.staff'
ck "ROLE_RE no grep"                            '[[ "$(printf "%s\n" a.mon b.monx c d.sistemas | grep -cE "$ROLE_RE")" == 2 ]]'
ck "ROLE_RE no awk -v (sem o escape virar curinga)" '[[ "$(printf "%s\n" a.mon bxmon | awk -v re="$ROLE_RE" "\$0 ~ re" | wc -l)" == 1 ]]'
ck "ROLE_RE no jq"                              '[[ "$(jq -rn --arg re "$ROLE_RE" "[\"a.foto\",\"afoto\",\"a.fotos\"] | map(select(test(\$re))) | length")" == 1 ]]'

ck "registro AUSENTE: sourcear falha (não vira \"ninguém tem papel\")" \
   '! MOJ_ROLES_TSV=/nao/existe bash -c "source \"$ROOT/server/api/v1/lib/roles.sh\"; echo segue" 2>/dev/null | grep -q segue'
ck "registro VAZIO: idem" '! MOJ_ROLES_TSV=/dev/null bash -c "source \"$ROOT/server/api/v1/lib/roles.sh\"; echo segue" 2>/dev/null | grep -q segue'
# linha malformada é FATAL nos três leitores; CRLF é tolerado
RT="$(mktemp -d)"; trap 'rm -rf "$RT"' EXIT
sed 's/$/\r/' "$ROOT/server/etc/roles.tsv" > "$RT/crlf.tsv"
{ cat "$ROOT/server/etc/roles.tsv"; printf 'quebrado\tquebrado\tsalao\tsim\tfoto\n'; } > "$RT/bad.tsv"
ck "CRLF: a última capacidade vale (role_can maquinas a.sistemas)" \
   'MOJ_ROLES_TSV="$RT/crlf.tsv" bash -c "source \"$ROOT/server/api/v1/lib/roles.sh\"; role_can maquinas a.sistemas && role_can placar_recorte a.diretor"'
ck "linha malformada (classe errada): sourcear falha" \
   '! MOJ_ROLES_TSV="$RT/bad.tsv" bash -c "source \"$ROOT/server/api/v1/lib/roles.sh\"; echo segue" 2>/dev/null | grep -q segue'
ck "porteiro: CRLF carrega; malformado e vazio abortam" \
   'MOJ_ROLES_TSV="$RT/crlf.tsv" python3 -c "import runpy,sys; sys.argv=[\"p\",\"--selftest\"]; g=runpy.run_path(\"$ROOT/server/porteiro/moj-porteiro.py\", run_name=\"porteiro_t\"); assert g[\"ROLE_BY\"][\"sistemas\"][\"can\"] == [\"maquinas\"]" 2>/dev/null \
    && ! MOJ_ROLES_TSV="$RT/bad.tsv" python3 -c "import runpy; runpy.run_path(\"$ROOT/server/porteiro/moj-porteiro.py\", run_name=\"porteiro_t\")" 2>/dev/null \
    && ! MOJ_ROLES_TSV=/dev/null python3 -c "import runpy; runpy.run_path(\"$ROOT/server/porteiro/moj-porteiro.py\", run_name=\"porteiro_t\")" 2>/dev/null'
ck "ingest-drain: registro vazio aborta" \
   '! MOJ_ROLES_TSV=/dev/null python3 -c "import runpy; runpy.run_path(\"$ROOT/server/daemons/ingest-drain.py\", run_name=\"ingest_t\")" 2>/dev/null'

echo "== os is_* do auth.sh =="
source "$ROOT/server/api/v1/lib/auth.sh" 2>/dev/null
j(){ bash -c "source '$ROOT/server/api/v1/lib/auth.sh' 2>/dev/null; SESSION_LOGIN='$1'; is_judge" && echo s || echo n; }
ck "is_judge = judge, cjudge, admin"             '[[ "$(j a.judge)$(j a.cjudge)$(j a.admin)$(j a.mon)$(j a.diretor)$(j t)" == "sssnnn" ]]'

echo "== web/shared/roles.js =="
ck "roles.js = o que o roles-gen.sh gera agora (rode: bash server/bin/roles-gen.sh)" \
   'diff -q <(bash "$ROOT/server/bin/roles-gen.sh" --stdout) "$ROOT/web/shared/roles.js" >/dev/null'

echo "== porteiro =="
PY="$(MOJ_HOME="$ROOT" python3 - "$ROOT/server/porteiro/moj-porteiro.py" <<'PYEOF' 2>&1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("p", sys.argv[1]); m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(",".join(r["suffix"] for r in m.ROLES))
print(m.role_of("x.cjudge"), m.role_of("x.diretor"), m.role_of("t1"), m.is_judge("x.admin"), m.is_judge("x.mon"),
      m.is_priv_rounds("x.staff"), m.is_priv_rounds("x.diretor"))
PYEOF
)"
ck "o porteiro lê o mesmo registro"             '[[ "$(head -1 <<<"$PY")" == "$(IFS=,; echo "${ROLE_SUFFIXES[*]}")" ]]' "$PY"
ck "role_of/is_judge/rodadas iguais ao bash"    '[[ "$(sed -n 2p <<<"$PY")" == "chief diretor time True False True False" ]]' "$PY"
NB="$(grep -oE 'NBROLE=[a-z]+' "$ROOT/server/api/v1/handlers/contest/navbuttons.sh" | cut -d= -f2 | sort -u | tr '\n' ' ')"
WANT="$( { for s in "${ROLE_SUFFIXES[@]}"; do echo "${ROLE_NAV[$s]}"; done; echo time; } | sort -u | tr '\n' ' ')"
ck "navbuttons cobre todo papel do registro (+ time)" '[[ "$NB" == "$WANT" ]]' "navbuttons: $NB | registro: $WANT"

echo "== inventário: lista de sufixos escrita à mão fora do registro =="
VIOL="$(python3 - "$ROOT" <<'PYEOF'
import os, re, sys
root = sys.argv[1]
names = "admin|judge|cjudge|staff|cstaff|mon|animeitor|foto|musica|sistemas|diretor"
dotted = re.compile(r'(?:\*\.|\\\\?\.|\[\.\]|["\']\.)(' + names + r')\b')
group = re.compile(r'\((?:\?:)?((?:' + names + r')(?:\|(?:' + names + r')){2,})\)')
skip_files = {"server/etc/roles.tsv", "server/api/v1/lib/roles.sh", "web/shared/roles.js", "server/bin/roles-gen.sh"}
out = []
for base in ("server", "web"):
    for dp, dn, fn in os.walk(os.path.join(root, base)):
        rel = os.path.relpath(dp, root)
        if rel.startswith(("server/test", "web/api")) or "/node_modules" in rel:
            continue
        for f in fn:
            if not f.endswith((".sh", ".py", ".js", ".mjs", ".conf", ".jq")) and "." in f:
                continue
            p = os.path.join(dp, f); r = os.path.relpath(p, root)
            if r in skip_files:
                continue
            try:
                lines = open(p, encoding="utf-8", errors="replace").read().split("\n")
            except OSError:
                continue
            for i, ln in enumerate(lines, 1):
                s = ln.strip()
                if s.startswith(("#", "//", "/*")) or re.match(r"\*(\s|/|$)", s):
                    continue
                code = re.sub(r'\s#\s.*$', '', ln) if r.endswith((".sh", ".py")) else re.sub(r'\s//\s.*$', '', ln)
                found = set(dotted.findall(code))
                for g in group.findall(code):
                    found |= set(g.split("|"))
                if len(found) >= 3:
                    out.append(f"{r}:{i}: {s[:120]}")
print("\n".join(out))
PYEOF
)"
n="$(grep -c . <<<"$VIOL")"
ck "nenhuma lista de sufixos à mão ($n)"        '[[ -z "$VIOL" ]]' $'\n'"$VIOL"

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
