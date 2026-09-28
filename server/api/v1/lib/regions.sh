# lib/regions.sh — a REGRA ÚNICA de sede (time → sede) sobre o regions.json (28/09/2026).
#
# Até aqui ~30 consumidores casavam time→sede cada um do seu jeito (4 famílias de regra, 3 dialetos de
# regex, maiúsculas às vezes sim, às vezes não; o gate de UA/materialize davam "Brasil" p/ teamsp01 —
# o pai casava antes da folha). Esta lib é a regra; o gêmeo em JS é web/shared/regions-match.js e o
# smoke-regions-match.gjs.sh roda os DOIS sobre as mesmas árvores (as reais de produção inclusive) e
# exige saída idêntica. Mudou a regra aqui? Mude lá no mesmo commit.
#
# A ÁRVORE: regions.json = lista de nós {name, regex?, subregions?, view?}. Achatada em PRÉ-ORDEM; a
# identidade do nó é o ÍNDICE (a Maratona repete nomes: "CE, Crateús" é sede e é folha de recorte).
#   • nó com `view:true` (ou filho de um) é RECORTE: nunca é a sede de ninguém, só um agrupamento;
#   • regex "" ou ausente = nó sem regex (só entra por nome ou como ancestral).
# A SEDE de um login (uma só):
#   1. `.team.region` gravado na conta VENCE — casa o NOME (minúsculas ASCII, sem espaço nas pontas) do
#      1º nó NÃO-recorte em pré-ordem; nome que não existe na árvore vira uma sede SINTÉTICA `orphan`
#      (contest sem regions.json com sedes só gravadas continua funcionando; a prévia lista as órfãs);
#   2. senão, o nó NÃO-recorte MAIS FUNDO cuja regex casa o login (sem diferenciar maiúsculas); empate =
#      o 1º em pré-ordem. Se ele não é folha, o login "parou no pai" (flag p — a prévia mostra);
#   3. senão, sem sede.
# PERTENÇA (quem está "em" cada nó), direto:
#   • a própria sede;
#   • nó comum com o MESMO NOME da sede (árvores que repetem a sede em ramos paralelos SEM `view` — o
#     mdp-teste-2026 tem Brasil › DF, Brasília e também Centro-Oeste › DF, Brasília);
#   • recorte COM regex: a regex casa o login; recorte SEM regex: o nome é o da sede. (Recorte com regex
#     NÃO entra por nome: na LATAM há recortes "Brasil" dentro de "Times femininos" — por nome, todo time
#     com sede "Brasil" entraria.)
#   … e soma dos filhos: quem está num filho está no pai — exceto de recorte p/ nó comum (um time dos
#   "Times femininos" com sede na Bolívia não passa a contar no Brasil por isso). A regex de um nó comum
#   NÃO dá pertença (só decide a sede): quem foi gravado em outro ramo não é puxado de volta.
# REGEX = subconjunto SEGURO, que casa igual em JS, jq (Oniguruma), gawk e PCRE (rg_norm):
#   \d \w \s (e as negações) viram classes; (?: vira (; recusa \b (backspace no gawk!), outros escapes
#   alfanuméricos (\p \k \1 …), (?= (?! (?<, [:classe:], quantificador preguiçoso, { } fora de {m,n},
#   caractere de controle ou não-ASCII (login é ASCII: nunca casaria), hífen AMBÍGUO dentro de [...] (depois
#   de um intervalo ou de \d/\w/\s — o gawk recusa [0-9-z]), && e [ aninhado (o Oniguruma aninha classes);
#   `]` no início de classe vira `\]` (em JS `[]` é classe vazia). O resultado
#   ainda precisa COMPILAR (jq) — senão o gawk abortaria o mapa inteiro. Nó com regex recusada fica SEM
#   regex no mapa e com `err` no nodes.json (a validação do salvar é o F2).
#
# SAÍDAS (cache em var/, reconstruídas quando regions.json, users/ ou algum account.json muda):
#   var/regions-nodes.json  [{i,parent,depth,name,key,regex,err,view,leaf,orphan}] (árvore + órfãs)
#   var/regions-map.tsv     login \t sede(i|-1) \t nós(csv, crescente) \t flag
#                           flag: x = gravada, o = gravada órfã, r = regex numa folha, p = parou no pai,
#                                 - = sem sede
# POPULAÇÃO = os DIRS de users/ (a do placar: participante compartilhado tem dir sem account.json), menos
#   contas de papel. Custo: um jq p/ as contas (xargs), um gawk p/ o casamento — regex compilada UMA vez
#   por nó (laço nó × logins; o jq recompila a cada test: 1,4 s p/ 2000 logins).
#
#   rg_norm_jq                 -> programa jq: def rg_norm (string -> {re, err})
#   rg_flatten <regions.json>  -> nós achatados (JSON, sem órfãs) no stdout
#   rg_map <c>                 -> caminho do regions-map.tsv (reconstrói se velho); 1 se falhar
#   rg_nodes <c>               -> caminho do regions-nodes.json (idem)
#   rg_site_of <c> <login>     -> nome da sede (vazio = sem sede)
#   rg_members <c> <i>         -> logins no nó i (um por linha)

RG_ROLE_RE='\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$'

# o normalizador (jq). Espelho exato: rgNorm em web/shared/regions-match.js.
rg_norm_jq(){ cat <<'JQ'
def rg_key: tostring | ascii_downcase | gsub("[\t\r\n]"; " ") | gsub("^ +| +$"; "");
def rg_norm:
  # bk = o último item DENTRO de [...]: "" início, "c" caractere, "r" intervalo fechado, "k" classe (\d…),
  # "d" hífen de intervalo pendente. Hífen depois de intervalo/classe é ambíguo entre os motores (o gawk
  # recusa [\w-a] e [0-9-z]) — recusado.
  (tostring | explode) as $c | ($c | length) as $n
  | def ch($k): if $k < $n then ([$c[$k]] | implode) else "" end;
    def lit($t): .o += $t | .bk = (if .bk == "d" then "r" else "c" end);
    reduce range(0; $n) as $k ({o: "", br: false, bk: "", esc: false, err: null, skip: 0, q: false};
      if .err != null then .
      elif .skip > 0 then .skip -= 1
      else ch($k) as $x
      | if ($x | test("^[\\x00-\\x1f\\x7f]$")) then .err = "control_char"
        elif ($c[$k] > 126) then .err = "non_ascii"
        elif .esc then
          .esc = false | .q = false
          | if ($x == "d" or $x == "w" or $x == "s") then
              ({d: "0-9", w: "A-Za-z0-9_", s: " \t"}[$x]) as $cls
              | if .br then (if .bk == "d" then .err = "ambiguous_range" else .o += $cls | .bk = "k" end)
                else .o += ("[" + $cls + "]") end
            elif ($x == "D" or $x == "W" or $x == "S") then
              ({D: "0-9", W: "A-Za-z0-9_", S: " \t"}[$x]) as $cls
              | if .br then .err = "negated_class_in_bracket" else .o += ("[^" + $cls + "]") end
            elif ($x == "b" or $x == "B") then .err = "word_boundary"
            elif ($x | test("^[A-Za-z0-9]$")) then .err = "escape"
            elif .br then lit(if ($x == "]" or $x == "\\" or $x == "-" or $x == "^" or $x == "[") then "\\" + $x else $x end)
            elif ($x | test("^[.\\[\\](){}*+?|^$\\\\]$")) then .o += ("\\" + $x)
            else .o += $x end
        elif $x == "\\" then .esc = true
        elif .br then
          if ($x == "]" and .bk == "") then lit("\\]")
          elif $x == "]" then .o += "]" | .br = false
          elif ($x == "^" and .bk == "" and (.o | endswith("["))) then .o += "^"
          elif ($x == "[" and (ch($k + 1) == ":" or ch($k + 1) == "=" or ch($k + 1) == ".")) then .err = "posix_class"
          elif $x == "[" then lit("\\[")
          elif ($x == "&" and ch($k + 1) == "&") then .err = "class_intersection"
          elif $x == "-" then
            if (.bk == "" or ch($k + 1) == "]") then lit("-")
            elif .bk == "c" then .o += "-" | .bk = "d"
            else .err = "ambiguous_range" end
          else lit($x) end
        elif $x == "[" then .o += "[" | .br = true | .bk = "" | .q = false
        elif $x == "(" then
          if ch($k + 1) == "?" then (if ch($k + 2) == ":" then .o += "(" | .skip = 2 | .q = false else .err = "group_ext" end)
          else .o += "(" | .q = false end
        elif ($x == "*" or $x == "+" or $x == "?") then
          if ch($k + 1) == "?" then .err = "lazy" elif .q then .err = "double_quantifier" else .o += $x | .q = true end
        elif $x == "{" then
          (([$c[$k:][]] | implode) as $rest | ($rest | capture("^(?<q>\\{[0-9]+(,[0-9]*)?\\})") | .q) // null) as $q
          | if $q == null then .err = "brace"
            elif ([$q | scan("[0-9]+") | tonumber] | max) > 100 then .err = "brace"          # o gawk estoura em a{99999}
            elif ch($k + ($q | length)) == "?" then .err = "lazy"
            elif .q then .err = "double_quantifier"
            else .o += $q | .skip = (($q | length) - 1) | .q = true end
        elif $x == "}" then .err = "brace"
        else .o += $x | .q = false end
      end)
    | if .err != null then {re: "", err: .err}
      elif .esc then {re: "", err: "trailing_backslash"}
      elif .br then {re: "", err: "unclosed_bracket"}
      else .o as $o | (try (("" | test($o; "i")) | {re: $o, err: null}) catch {re: "", err: "invalid"}) end;
JQ
}

# rg_flatten <regions.json> — pré-ordem; nós de um arquivo ausente/que não é lista = []
rg_flatten(){
  local f="$1"
  [[ -s "$f" ]] || { printf '[]\n'; return 0; }
  jq -c "$(rg_norm_jq)"'
    def flat($p; $d; $v):
      .[]? | select(type == "object") | (($v or (.view == true))) as $vv
      | ({name: ((.name // "") | tostring), rx: ((.regex // "") | tostring), view: $vv, parent: $p, depth: $d}),
        ((.subregions // []) | if type == "array" then flat(-2; $d + 1; $vv) else empty end);
    if type != "array" then []
    else
      # índices e pais: a pré-ordem vem do flat; o pai de cada nó = o último nó de profundidade d-1 antes dele
      [flat(-1; 0; false)]
      | reduce range(0; length) as $k (.; .[$k].i = $k
          | if .[$k].depth > 0 then .[$k].parent = ([range(0; $k) as $j | select(.[$j].depth == (.[$k].depth - 1)) | $j] | last) else . end)
      | . as $all
      | map(. as $nd
          | (if $nd.rx == "" then {re: "", err: null} else ($nd.rx | rg_norm) end) as $r
          | {i, parent, depth, name, key: (.name | rg_key), regex: $r.re, err: $r.err, view,
             leaf: ([$all[] | select(.parent == $nd.i and (.view | not))] | length == 0), orphan: false})
    end' "$f" 2>/dev/null || printf '[]\n'
}

_rg_stale(){  # <c> <arquivo> — 0 se o cache precisa ser refeito
  local d="$CONTESTSDIR/$1" f="$2"
  [[ -s "$f" ]] || return 0
  [[ -e "$d/regions.json" && "$d/regions.json" -nt "$f" ]] && return 0
  [[ ! -e "$d/regions.json" && -e "$d/var/.regions-had-tree" ]] && return 0
  [[ -e "$d/registrations.json" && "$d/registrations.json" -nt "$f" ]] && return 0   # (des)materialize some com account.json
  [[ -d "$d/users" ]] || return 1
  [[ -n "$(find "$d/users" -maxdepth 0 -newer "$f" -print -quit 2>/dev/null)" ]] && return 0
  [[ -n "$(find "$d/users" -mindepth 2 -maxdepth 2 -name account.json -newer "$f" -print -quit 2>/dev/null)" ]] && return 0
  return 1
}

# rg_build <c> — reconstrói var/regions-{nodes.json,map.tsv}. Escrita atômica (tmp + mv): dois builds
# simultâneos produzem o mesmo resultado, o último mv vence.
rg_build(){
  local c="$1" d="$CONTESTSDIR/$1" w rc=0
  command -v gawk >/dev/null 2>&1 || return 1          # `awk` pode ser o mawk na imagem
  mkdir -p "$d/var" 2>/dev/null
  w="$(mktemp -d)" || return 1
  rg_flatten "$d/regions.json" > "$w/base.json"
  if [[ -e "$d/regions.json" ]]; then : > "$d/var/.regions-had-tree"; else rm -f "$d/var/.regions-had-tree"; fi
  # join, NÃO @tsv: o @tsv dobra a barra invertida e estragaria a regex (a chave não tem tab: rg_key)
  jq -r '.[] | [.i, .parent, .depth, (if .view then 1 else 0 end), .key, .regex, (if .leaf then 1 else 0 end)] | map(tostring) | join("\t")' \
    "$w/base.json" > "$w/nodes.tsv"
  # população: os dirs (menos papéis) + a sede GRAVADA de quem tem account.json
  find "$d/users" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | grep -v '^\.' | grep -vE "$RG_ROLE_RE" \
    | LC_ALL=C sort > "$w/dirs"
  find "$d/users" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
    | xargs -0 -r jq -r "$(rg_norm_jq)"' ((.team.region // "") | tostring) as $r
        | [(input_filename | split("/") | .[-2]), ($r | rg_key), ($r | gsub("[\t\n\r]"; " ") | gsub("^ +| +$"; ""))] | join("\t")' \
      2>/dev/null > "$w/explicit"
  : > "$w/synth.tsv"
  gawk -v synthf="$w/synth.tsv" -f <(_rg_gawk) "$w/nodes.tsv" "$w/explicit" "$w/dirs" > "$w/map.tsv" || rc=1
  if (( rc == 0 )); then
    jq -c --rawfile s "$w/synth.tsv" '. + [($s | split("\n")[] | select(length > 0) | split("\t")
          | {i: (.[0] | tonumber), parent: -1, depth: 0, name: .[2], key: .[1], regex: "", err: null,
             view: false, leaf: true, orphan: true})]' "$w/base.json" > "$w/nodes.json" || rc=1
  fi
  if (( rc == 0 )); then
    mv -f "$w/nodes.json" "$d/var/regions-nodes.json" && mv -f "$w/map.tsv" "$d/var/regions-map.tsv" || rc=1
  fi
  rm -rf "$w"; return "$rc"
}

# o casamento. Laço NÓ × logins (e não o contrário): a regex dinâmica do gawk é recompilada quando a
# string muda — iterando logins por dentro, cada regex compila UMA vez.
_rg_gawk(){ cat <<'AWK'
BEGIN { FS = OFS = "\t"; n = 0; nv = 0; u = 0 }                            # IGNORECASE só nos laços de regex: nome compara EXATO (chave já minúscula)
FILENAME == ARGV[1] {                                   # nós: i parent depth view key regex leaf
  n++; I[n] = $1; par[$1] = $2; dep[$1] = $3; vw[$1] = $4; key[$1] = $5; re[$1] = $6; lf[$1] = $7
  if ($4 == 0 && !($5 in byname)) byname[$5] = $1
  if ($4 == 1) { nv++; V[nv] = $1 }
  next }
FILENAME == ARGV[2] { if ($2 != "") { ek[$1] = $2; en[$1] = $3 }; next }   # sede gravada: login key nome
{ u++; L[u] = $1 }                                      # população (dirs)
END {
  ns = 0
  for (k = 1; k <= u; k++) {                            # 1. gravada
    l = L[k]; site[k] = -1; fl[k] = "-"
    if (l in ek) {
      if (ek[l] in byname) { site[k] = byname[ek[l]]; fl[k] = "x" }
      else {
        if (!(ek[l] in syn)) { syn[ek[l]] = n + ns; synname[n + ns] = en[l]; synkey[n + ns] = ek[l]; ns++ }
        site[k] = syn[ek[l]]; fl[k] = "o"
      }
    }
  }
  IGNORECASE = 1
  for (j = 1; j <= n; j++) {                            # 2. regex: o nó mais fundo (pré-ordem desempata)
    i = I[j]; if (vw[i] == 1 || re[i] == "") continue
    r = re[i]; d = dep[i] + 0
    for (k = 1; k <= u; k++) {
      if (fl[k] == "x" || fl[k] == "o") continue
      if ((site[k] < 0 || d > bd[k]) && L[k] ~ r) { site[k] = i; bd[k] = d }
    }
  }
  for (j = 1; j <= nv; j++) { v = V[j]; if (re[v] == "") continue; r = re[v]
    for (k = 1; k <= u; k++) if (L[k] ~ r) own[v, k] = 1 }
  IGNORECASE = 0
  for (k = 1; k <= u; k++) {
    if (fl[k] == "-" && site[k] >= 0) fl[k] = (lf[site[k]] == 1) ? "r" : "p"
    delete mem; delete inv
    s = site[k] + 0; sk = (s < 0) ? "" : ((s >= n) ? synkey[s] : key[s])
    if (s >= n) mem[s] = 1                              # órfã: fora da árvore
    for (j = n; j >= 1; j--) {                          # filhos antes dos pais (pré-ordem ao contrário)
      i = I[j]
      if (!inv[i]) {
        if (vw[i] == 0) inv[i] = (s >= 0 && (i + 0 == s || (sk != "" && key[i] == sk)))
        else inv[i] = (re[i] != "") ? ((i, k) in own) : (sk != "" && key[i] == sk)
      }
      if (inv[i]) { mem[i] = 1; p = par[i] + 0; if (p >= 0 && !(vw[i] == 1 && vw[p] == 0)) inv[p] = 1 }
    }
    cs = ""; m = 0
    for (x in mem) arr[++m] = x + 0
    if (m > 0) { asort(arr); for (x = 1; x <= m; x++) cs = cs (x > 1 ? "," : "") arr[x] }
    delete arr
    print L[k], s, cs, fl[k]
  }
  for (x = n; x < n + ns; x++) print x, synkey[x], synname[x] > synthf
  close(synthf)
}
AWK
}

rg_map(){
  local f="$CONTESTSDIR/$1/var/regions-map.tsv"
  if _rg_stale "$1" "$f"; then rg_build "$1" || return 1; fi
  printf '%s' "$f"
}
rg_nodes(){
  local f="$CONTESTSDIR/$1/var/regions-nodes.json" m
  m="$(rg_map "$1")" || return 1
  printf '%s' "$f"
}
rg_site_of(){  # <c> <login>
  local m n s; m="$(rg_map "$1")" || return 1; n="$CONTESTSDIR/$1/var/regions-nodes.json"
  s="$(gawk -F'\t' -v l="$2" '$1 == l { print $2; exit }' "$m")"
  [[ -n "$s" && "$s" != -1 ]] || return 0
  jq -r --argjson s "$s" '.[$s].name // empty' "$n"
}
rg_members(){  # <c> <i>
  local m; m="$(rg_map "$1")" || return 1
  gawk -F'\t' -v i="$2" '{ n = split($3, a, ","); for (k = 1; k <= n; k++) if (a[k] == i) { print $1; break } }' "$m"
}
