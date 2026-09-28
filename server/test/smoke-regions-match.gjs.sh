#!/bin/bash
# smoke-regions-match.gjs.sh — a regra ÚNICA de sede tem DOIS corpos: server/api/v1/lib/regions.sh (jq +
# gawk) e web/shared/regions-match.js (JS). Este teste roda os dois sobre as MESMAS árvores e populações e
# exige saída IDÊNTICA (nós achatados + login → sede/nós/flag). Afirma também, por nome:
#   • teamsp01 cai em "SP, Capital" (a folha), não em "Brasil" (o pai casava antes — bug do gate de UA,
#     do materialize e das etiquetas até 28/09/2026); login em MAIÚSCULAS casa igual;
#   • quem casa o pai e nenhuma folha "para no pai" (flag p); a sede gravada vence (x), com nome em outra
#     caixa/espaços; nome gravado fora da árvore vira sede órfã (o), UMA por nome;
#   • recorte com regex só entra pela regex (os "Brasil" dentro de "Times femininos" não puxam o Brasil
#     inteiro); recorte sem regex entra pelo nome da sede; recorte pai soma os filhos;
#   • contas de papel ficam fora; participante só com dir (compartilhado) entra;
#   • o normalizador de regex dá o mesmo {re, err} nos dois lados numa lista adversarial.
# MOJ_REGIONS_EXTRA=<dir com *.json> acrescenta árvores reais (ex.: as de produção) sem versioná-las.
set -u
command -v gjs >/dev/null 2>&1 || { echo "regions-match: gjs ausente — pulando"; exit 0; }
command -v gawk >/dev/null 2>&1 || { echo "regions-match: gawk ausente — FALHA"; exit 1; }
TD="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; ROOT="$TD/.."; WEB="$ROOT/../web"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export CONTESTSDIR="$T/contests"; mkdir -p "$CONTESTSDIR" "$T/cases"
source "$ROOT/api/v1/lib/regions.sh"
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 ${3:-}"; ((fail++)); fi; }

# case <nome> <árvore JSON | "-" = sem regions.json>; população em $T/cases/<nome>/users.tsv (login \t sede gravada)
mkcase(){ mkdir -p "$T/cases/$1"; [[ "$2" == - ]] || printf '%s' "$2" | jq -c . > "$T/cases/$1/tree.json"; : > "$T/cases/$1/users.tsv"; }
u(){ printf '%s\t%s\n' "$2" "${3:-}" >> "$T/cases/$1/users.tsv"; }

mkcase classify '[
  {"name":"Brasil","regex":"^team","subregions":[
    {"name":"Sudeste","regex":"^team(sp|rj)","subregions":[{"name":"SP, Capital","regex":"^teamsp"},{"name":"RJ, Rio","regex":"^teamrj"}]},
    {"name":"Norte","regex":"^team(am|ac)","subregions":[{"name":"AM, Manaus","regex":"^teamam"},{"name":"AC, Rio Branco","regex":"^teamac"}]},
    {"name":"Supersede Norte","regex":"^team(am|ac)","view":true,"subregions":[{"name":"AM, Manaus","regex":"^teamam"},{"name":"AC, Rio Branco","regex":"^teamac"}]}]},
  {"name":"Times femininos","regex":"^(teamsp03|teamam01|teamsp05|teamrj03)","view":true,"subregions":[
    {"name":"3 competidoras","regex":"^(teamsp03)","view":true,"subregions":[{"name":"Brasil","regex":"^(teamsp03)"}]},
    {"name":"2 competidoras","regex":"^(teamam01|teamsp05)","view":true,"subregions":[{"name":"Brasil","regex":"^(teamam01|teamsp05)"}]},
    {"name":"1 competidora","regex":"^(teamrj03)","view":true,"subregions":[{"name":"Brasil","regex":"^(teamrj03)"}]}]}]'
for l in teamsp01 teamsp03 teamsp05 teamrj01 teamrj03 teamam01 teamac01 teampe01 TEAMSP09 outro01; do u classify $l; done
u classify x-rio '  rj, RIO '; u classify x-br 'Brasil'; u classify x-orf 'Atlântida'; u classify x-orf2 'ATLÂNTIDA'
u classify x-orf3 'atlântida '; u classify x-view '3 competidoras'

mkcase admintree '[{"name":"Brasil","regex":"^br-","subregions":[{"name":"DF","regex":"^br-df-"},{"name":"GO"}]},
  {"name":"Femininos","view":true,"subregions":[{"name":"F3","regex":"^f3"}]}]'
for l in br-df-01 br-go-01 f3-01 zz; do u admintree $l; done
u admintree go-x 'go'; u admintree fem-x 'Femininos'; u admintree f3-df 'DF'

mkcase enrolled '[{"name":"Pais","regex":"^u-","subregions":[{"name":"Sede A","regex":"^u-"}]},{"name":"Recorte X","regex":"^u-","view":true}]'
for l in u-1 u-2 v-1; do u enrolled $l; done

mkcase animeitor '[{"name":"Brasil","subregions":[{"name":"Brasília"},{"name":"Goiânia"}]},{"name":"México","regex":"^teammx","subregions":[{"name":"CDMX","regex":"^teammx"}]}]'
u animeitor teammx01; u animeitor b1 'Brasília'; u animeitor b2 'goiânia'; u animeitor b3 'brasil'; u animeitor nada

mkcase notree -
u notree a 'Sede 1'; u notree b 'sede 1 '; u notree c 'Sede 2'; u notree d

mkcase badregex '[{"name":"Dig","regex":"^d\\d{2}$"},{"name":"NC","regex":"^(?:nc|NC)_"},{"name":"Cls","regex":"[]x]$"},
  {"name":"WB","regex":"\\bwb"},{"name":"LA","regex":"(?=la)la"},{"name":"DQ","regex":"a**"},{"name":"Open","regex":"(op"},
  {"name":"Empty","regex":""},{"name":"Bool","regex":false},{"name":7,"regex":"^seven"},"lixo",[1,2],{"subregions":"nao-lista"}]'
for l in d12 d123 nc_1 NC_2 abx wb1 la1 aaa op seven1; do u badregex $l; done; u badregex wbx 'WB'

# formato mdp-teste-2026: ramos PARALELOS sem `view` que repetem as sedes (Centro-Oeste › DF de novo) e
# um nó comum (Femininas) filho de país com um recorte dentro
mkcase paralelo '[{"name":"Brasil","regex":"^br","subregions":[{"name":"DF, Brasília","regex":"^brdf"},{"name":"GO, Goiânia","regex":"^brgo"},
    {"name":"Fem","view":true,"regex":"^br(df|go)1$"}]},
  {"name":"Centro-Oeste","regex":"^br(df|go)","subregions":[{"name":"DF, Brasília","regex":"^brdf"},{"name":"GO, Goiânia","regex":"^brgo"}]},
  {"name":"Bolivia","regex":"^bo"}]'
for l in brdf1 brdf2 brgo1 bo1; do u paralelo $l; done; u paralelo gx 'go, goiânia'; u paralelo bx 'Bolivia'

# formato "LATAM": 3 países → supersedes (regex com alternância) → sedes; recortes que REPETEM nomes de sede
# (Supersede) e "Times femininos" com folhas "Brasil"; logins em 3 variantes de caixa
latam="$(jq -nc '
  def sede($p): {name: ($p | ascii_upcase), regex: ("^team" + $p + "[0-9]")};
  [ ["br","bo","mx"][] as $c
    | {name: ({"br":"Brasil","bo":"Bolivia","mx":"Mexico"}[$c]), regex: ("^team" + $c),
       subregions: [ ["n","s"][] as $s
         | {name: ("Super " + $c + $s), regex: ("^team" + $c + $s + "(aa|bb|cc)[0-9]"),
            subregions: [ ["aa","bb","cc"][] | sede($c + $s + .) ]} ]} ]
  + [ {name: "Supersede BR-N", view: true, regex: "^teambrn(aa|bb)[0-9]",
       subregions: [ sede("brnaa"), sede("brnbb") ]},
      {name: "Times femininos", view: true, regex: "^(teambrnaa1|teambosbb2|teammxncc1)$",
       subregions: [ {name: "3 competidoras", view: true, regex: "^(teambrnaa1)$", subregions: [{name: "Brasil", regex: "^(teambrnaa1)$"}]},
                     {name: "2 competidoras", view: true, subregions: [{name: "Bolivia", regex: "^teambosbb2$"}, {name: "BRSAA"}]} ]} ]')"
mkcase latamlike "$latam"
for c in br bo mx; do for s in n s; do for x in aa bb cc; do for k in 1 2; do u latamlike "team$c$s$x$k"; done; done; done; done
u latamlike TEAMBRNAA3; u latamlike TeamMxScc9; u latamlike teambrx1; u latamlike teambrsdd1; u latamlike teambr
u latamlike expl-1 'brsaa'; u latamlike expl-2 'Super brn'

# árvores reais (fora do repositório): população gerada dos prefixos team…/ccl… das regex, 3 sufixos, 2 caixas
if [[ -n "${MOJ_REGIONS_EXTRA:-}" && -d "$MOJ_REGIONS_EXTRA" ]]; then
  for f in "$MOJ_REGIONS_EXTRA"/*.json; do
    [[ -f "$f" ]] || continue; nm="real-$(basename "$f" .json)"; mkcase "$nm" "$(cat "$f")"
    jq -r '[.. | objects | .regex? // empty | strings] | map(scan("(team[a-z]+|ccl[a-z]+[0-9]*)")[]) | unique[]' "$f" \
      | while read -r p; do for s in 001 002 017; do u "$nm" "$p$s"; done; u "$nm" "${p^^}9"; done
    u "$nm" expl-a 'Brasil'; u "$nm" expl-b 'nao existe'
  done
fi

# ---- servidor: um contest por caso (dirs + account.json com a sede gravada + contas de papel) --------------
srv_out(){ local c="$1" d="$CONTESTSDIR/$1"
  mkdir -p "$d/users"; [[ -f "$T/cases/$c/tree.json" ]] && cp "$T/cases/$c/tree.json" "$d/regions.json"
  while IFS=$'\t' read -r l r; do
    mkdir -p "$d/users/$l"; : > "$d/users/$l/history"
    [[ -n "$r" ]] && jq -cn --arg l "$l" --arg r "$r" '{login:$l, team:{region:$r}}' > "$d/users/$l/account.json"
  done < "$T/cases/$c/users.tsv"
  mkdir -p "$d/users/$c.admin" "$d/users/juiz.judge"; echo '{"team":{"region":"Brasil"}}' > "$d/users/$c.admin/account.json"
  rg_build "$c" || { echo "BUILD FAIL $c"; return; }
  printf '=== %s\n' "$c"; printf 'N %s\n' "$(jq -c . "$d/var/regions-nodes.json")"; cat "$d/var/regions-map.tsv"; }

# ---- JS: os mesmos casos embutidos ------------------------------------------------------------------------
JS="$T/run.js"
{ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$WEB/shared/regions-match.js"
  printf 'const CASES=%s;\n' "$(for c in $(ls "$T/cases"); do
      jq -nc --arg n "$c" --rawfile us "$T/cases/$c/users.tsv" \
        --argjson t "$( [[ -f "$T/cases/$c/tree.json" ]] && cat "$T/cases/$c/tree.json" || echo null)" \
        '{name:$n, tree:$t, users:[$us | split("\n")[] | select(length > 0) | split("\t") | {login:.[0], region:(.[1] // "")}]}'
    done | jq -cs .)"
  cat <<'EOF'
for (const c of CASES) {
  const res = rgAssign(c.tree, c.users);
  print('=== ' + c.name); print('N ' + JSON.stringify(res.nodes)); const t = rgMapTsv(res); if (t) print(t.replace(/\n$/, ''));
}
EOF
} > "$JS"

echo "== servidor × JS: mesmos nós e mesmo login → sede/nós/flag =="
for c in $(ls "$T/cases"); do srv_out "$c"; done | while IFS= read -r l; do [[ "$l" == N\ * ]] && l="N $(jq -c . <<<"${l#N }")"; printf '%s\n' "$l"; done > "$T/srv.txt"
gjs "$JS" 2>"$T/gjs.err" | while IFS= read -r l; do [[ "$l" == N\ * ]] && l="N $(jq -c . <<<"${l#N }")"; printf '%s\n' "$l"; done > "$T/js.txt"
ncases="$(grep -c '^=== ' "$T/srv.txt")"
ck "os $ncases casos rodaram nos dois lados ($(ls "$T/cases" | tr '\n' ' '))" '[[ "$ncases" == "$(ls "$T/cases" | wc -l)" && "$(grep -c "^=== " "$T/js.txt")" == "$ncases" && ! -s "$T/gjs.err" ]]' "$(head -3 "$T/gjs.err")"
ck "saída IDÊNTICA ($(wc -l < "$T/srv.txt") linhas)" 'diff -q "$T/srv.txt" "$T/js.txt" >/dev/null' "$(diff "$T/srv.txt" "$T/js.txt" | head -8)"

# ---- afirmações por nome (sobre a saída do servidor) --------------------------------------------------------
N(){ jq -r --argjson i "$2" '.[$i].name // "-"' "$CONTESTSDIR/$1/var/regions-nodes.json"; }
row(){ gawk -F'\t' -v l="$2" '$1 == l' "$CONTESTSDIR/$1/var/regions-map.tsv"; }
site(){ local s; s="$(row "$1" "$2" | cut -f2)"; [[ -n "$s" && "$s" != -1 ]] && N "$1" "$s" || echo "-"; }
flag(){ row "$1" "$2" | cut -f4; }
innames(){ local c="$1" i; for i in $(row "$c" "$2" | cut -f3 | tr ',' ' '); do N "$c" "$i"; done | tr '\n' '|'; }
echo "== a regra, por nome =="
ck "teamsp01 → SP, Capital (a folha, não o pai Brasil)" '[[ "$(site classify teamsp01)" == "SP, Capital" && "$(flag classify teamsp01)" == r ]]'
ck "TEAMSP09 (maiúsculas) → SP, Capital" '[[ "$(site classify TEAMSP09)" == "SP, Capital" ]]'
ck "teampe01 casa Brasil e nenhuma folha: para no pai (p)" '[[ "$(site classify teampe01)" == Brasil && "$(flag classify teampe01)" == p ]]'
ck "pertença de teamsp01 = sede + ancestrais (SP, Capital|Sudeste|Brasil), sem recorte" '[[ "$(innames classify teamsp01)" == "Brasil|Sudeste|SP, Capital|" ]]'
ck "teamsp03: Times femininos › 3 competidoras › Brasil(recorte), e NÃO no 2/1 competidora" '[[ "$(innames classify teamsp03)" == "Brasil|Sudeste|SP, Capital|Times femininos|3 competidoras|Brasil|" ]]'
ck "teamam01: Supersede Norte (recorte que repete nomes) + Times femininos › 2 competidoras" '[[ "$(innames classify teamam01)" == "Brasil|Norte|AM, Manaus|Supersede Norte|AM, Manaus|Times femininos|2 competidoras|Brasil|" ]]'
ck "sede gravada vence, caixa/espaços não importam: \"  rj, RIO \" → RJ, Rio (x)" '[[ "$(site classify x-rio)" == "RJ, Rio" && "$(flag classify x-rio)" == x ]]'
ck "gravada = nó interno (Brasil): fica nele (x), sem recorte \"Brasil\" dos femininos" '[[ "$(innames classify x-br)" == "Brasil|" ]]'
ck "órfã: Atlântida e \"atlântida \" = UMA sede órfã (o); ATLÂNTIDA (maiúscula não-ASCII) é outra" '[[ "$(row classify x-orf | cut -f2)" == "$(row classify x-orf3 | cut -f2)" && "$(row classify x-orf2 | cut -f2)" != "$(row classify x-orf | cut -f2)" && "$(flag classify x-orf)" == o && "$(jq "[.[] | select(.orphan)] | length" "$CONTESTSDIR/classify/var/regions-nodes.json")" == 3 ]]'
ck "nome de RECORTE gravado não é sede: vira órfã, e o recorte com regex não a puxa" '[[ "$(flag classify x-view)" == o && "$(innames classify x-view)" == "3 competidoras|" ]]'
ck "sem sede: outro01 (-)" '[[ "$(flag classify outro01)" == - && "$(row classify outro01 | cut -f3)" == "" ]]'
ck "contas de papel fora do mapa" '! grep -qE "^(classify\.admin|juiz\.judge)	" "$CONTESTSDIR/classify/var/regions-map.tsv"'
ck "recorte SEM regex entra pelo nome: fem-x (gravada Femininos → órfã) está no recorte Femininos" '[[ "$(innames admintree fem-x)" == "Femininos|Femininos|" ]]'
ck "recorte pai soma o filho com regex: f3-01 em F3 e Femininos, sem sede" '[[ "$(innames admintree f3-01)" == "Femininos|F3|" && "$(flag admintree f3-01)" == - ]]'
ck "nó sem regex só por nome: go-x → GO (x); br-go-01 para em Brasil (p)" '[[ "$(site admintree go-x)" == GO && "$(site admintree br-go-01)" == Brasil && "$(flag admintree br-go-01)" == p ]]'
ck "sem regions.json: só as gravadas, uma órfã por nome (Sede 1 = sede 1)" '[[ "$(row notree a | cut -f2)" == "$(row notree b | cut -f2)" && "$(site notree c)" == "Sede 2" && "$(flag notree d)" == - ]]'
ck "animeitor: Brasília/goiânia gravadas casam os nós sem regex; teammx01 → CDMX" '[[ "$(site animeitor b1)" == Brasília && "$(site animeitor b2)" == Goiânia && "$(site animeitor teammx01)" == CDMX && "$(site animeitor b3)" == Brasil ]]'
ck "regex normalizada: \\d{2} casa d12 e não d123; (?: vira (; []x] casa abx" '[[ "$(site badregex d12)" == Dig && "$(site badregex d123)" == - && "$(site badregex NC_2)" == NC && "$(site badregex abx)" == Cls ]]'
ck "regex recusada (\\b, (?=, a**, (op) fica sem regex, com err; só entra por nome" '[[ "$(jq -c "[.[] | select(.err != null) | .err]" "$CONTESTSDIR/badregex/var/regions-nodes.json")" == "[\"word_boundary\",\"group_ext\",\"double_quantifier\",\"invalid\"]" && "$(site badregex wb1)" == - && "$(site badregex wbx)" == WB ]]'
ck "nó com name numérico/lixo na lista não derruba o mapa (7 → \"7\")" '[[ "$(site badregex seven1)" == 7 ]]'
ck "paralelo sem view: DF, Brasília (1ª em pré-ordem) é a sede; a cópia em Centro-Oeste e o Centro-Oeste também a contêm" '[[ "$(site paralelo brdf2)" == "DF, Brasília" && "$(innames paralelo brdf2)" == "Brasil|DF, Brasília|Centro-Oeste|DF, Brasília|" ]]'
ck "paralelo: sede gravada (gx) também soma no ramo paralelo; Bolivia não" '[[ "$(innames paralelo gx)" == "Brasil|GO, Goiânia|Centro-Oeste|GO, Goiânia|" && "$(innames paralelo bx)" == "Bolivia|" ]]'
ck "paralelo: recorte Fem dentro do Brasil NÃO sobe p/ o pai comum além do que já era (brgo1 no Fem)" '[[ "$(innames paralelo brgo1)" == "Brasil|GO, Goiânia|Fem|Centro-Oeste|GO, Goiânia|" ]]'
ck "latam: maiúsculas, folha mais funda, recorte que repete nome" '[[ "$(site latamlike TEAMBRNAA3)" == BRNAA && "$(site latamlike TeamMxScc9)" == MXSCC && "$(innames latamlike teambrnaa1)" == "Brasil|Super brn|BRNAA|Supersede BR-N|BRNAA|Times femininos|3 competidoras|Brasil|" ]]'
ck "latam: 2 competidoras (recorte sem regex) soma o filho por regex E o filho sem regex pelo nome (brsaa gravada)" '[[ "$(innames latamlike teambosbb2)" == *"2 competidoras|Bolivia|"* && "$(innames latamlike expl-1)" == *"2 competidoras|BRSAA|"* ]]'
ck "latam: teambrx1 casa só o país (p); teambr (sem dígito) idem" '[[ "$(site latamlike teambrx1)" == Brasil && "$(flag latamlike teambrx1)" == p ]]'

echo "== o normalizador: mesmo {re, err} nos dois lados =="
RX=( '^br-' '\d+' '^(?:ab|cd)\d{2,3}$' '[\d_]x' '[]a]' '[^]a]' 'a\b' '\1' '(?=x)' '(?<n>x)' '[[:alpha:]]' 'a*?' 'a{2}?' 'x{' 'x}'
     'a{,3}' '\.\-\/\_' '[a\-z\]]' '(a' 'a{2,1}' 'ab\' '[ab' '^TeamBR[0-9]' '\D\W' '[\D]' 'a**' 'a{2}{3}' 'a+?' '[a[b]'
     '[a&&b]' '[\[x]' '^\d+-\w' 'a|*' ')' '^*' '$+' '(|a)' '()' 'a||b' '[z-a]' '[a-]' '[-a]' '[\w-a]' '[0-9-z]' 'á+' '\é'
     '^(teambrdfdf|teambrgogo)[0-9]' '[[]' '[]]' '[^]' '\p{L}' '\x41' 'A' '\s\S' '.*' '(?i)ab' '\Qa\E' '\z' 'a$b^'
     '{1}' 'a{0}' 'a{1,}' 'a{99999}' '[\^x]' '[x^]' '\(\)' '\{' '\}' '\|' '\*' '\?' '\+' '\$' '\^' '\/' '\\' )
printf '%s\n' "${RX[@]}" > "$T/rx.txt"
jq -Rr "$(rg_norm_jq)"' rg_norm | "\(.re)\t\(.err)"' "$T/rx.txt" > "$T/rx.srv" 2>&1
{ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$WEB/shared/regions-match.js"
  printf 'const RX=%s;\n' "$(jq -Rsc 'split("\n") | map(select(length > 0))' "$T/rx.txt")"
  echo 'for (const r of RX) { const o = rgNorm(r); print(o.re + "\t" + o.err); }'; } > "$T/rx.js"
gjs "$T/rx.js" > "$T/rx.js.out" 2>&1
ck "${#RX[@]} regex adversariais: {re, err} idênticos" 'diff -q "$T/rx.srv" "$T/rx.js.out" >/dev/null' "$(paste "$T/rx.txt" "$T/rx.srv" "$T/rx.js.out" | gawk -F'\t' '$2 != $4 || $3 != $5' | head -8)"
# e o que passou casa IGUAL no gawk e no JS (o mapa usa gawk): cada regex aceita × um punhado de strings
printf '%s\n' ab cd12 abc 'a-b' ']' '^' '[' x '0' 'Ab' TEAMBR1 teambr1 aaa 'a b' '' é > "$T/str.txt"
paste "$T/rx.txt" "$T/rx.srv" | gawk -F'\t' '$3 == "null" && $2 != "" { print $2 }' > "$T/ok.rx"
gawk 'BEGIN { IGNORECASE = 1 } FILENAME == ARGV[1] { R[++n] = $0; next } { S[++m] = $0 } END { for (i = 1; i <= n; i++) { o = ""; for (j = 1; j <= m; j++) o = o ((S[j] ~ R[i]) ? 1 : 0); print o } }' "$T/ok.rx" "$T/str.txt" > "$T/m.gawk" 2>&1
{ printf 'const R=%s, S=%s;\n' "$(jq -Rsc 'split("\n") | map(select(length > 0))' "$T/ok.rx")" "$(jq -Rsc 'split("\n")[:-1]' "$T/str.txt")"
  echo 'for (const r of R) { const x = new RegExp(r, "i"); print(S.map((s) => (x.test(s) ? 1 : 0)).join("")); }'; } > "$T/m.js"
gjs "$T/m.js" > "$T/m.jsout" 2>&1
ck "as $(wc -l < "$T/ok.rx") aceitas casam igual no gawk e no JS ($(wc -l < "$T/str.txt") strings cada)" 'diff -q "$T/m.gawk" "$T/m.jsout" >/dev/null' "$(paste "$T/ok.rx" "$T/m.gawk" "$T/m.jsout" | gawk -F'\t' '$2 != $3' | head -5)"

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail > 0 ? 1 : 0 ))
