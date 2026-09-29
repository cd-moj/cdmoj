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
#      (contest sem regions.json com sedes só gravadas continua funcionando; a prévia lista as órfãs) —
#      e a órfã fica PENDURADA no nó que a regex daria (gravada "Buenos Aires" + regex do nó Argentina:
#      a sede é Buenos Aires e ela conta na Argentina);
#   2. senão, o nó NÃO-recorte MAIS FUNDO cuja regex casa o login (sem diferenciar maiúsculas); empate =
#      o 1º em pré-ordem. Se ele não é folha, o login "parou no pai" (flag p — a prévia mostra);
#   3. senão, sem sede.
# PERTENÇA (quem está "em" cada nó), direto:
#   • a própria sede (e, se ela é órfã, o nó que a regex daria);
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
# o percurso em PRÉ-ORDEM (o índice de cada nó sai daqui): item que não é objeto é pulado; subregions que
# não é lista também. parent = -2 nos filhos (rg_flatten acerta depois).
def rg_flat($p; $d; $v):
  .[]? | select(type == "object") | (($v or (.view == true))) as $vv
  | ({name: ((.name // "") | tostring), rx: ((.regex // "") | tostring), view: $vv, parent: $p, depth: $d}),
    ((.subregions // []) | if type == "array" then rg_flat(-2; $d + 1; $vv) else empty end);
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
    if type != "array" then []
    else
      # índices e pais: a pré-ordem vem do rg_flat; o pai de cada nó = o último nó de profundidade d-1 antes dele
      [rg_flat(-1; 0; false)]
      | reduce range(0; length) as $k (.; .[$k].i = $k
          | if .[$k].depth > 0 then .[$k].parent = ([range(0; $k) as $j | select(.[$j].depth == (.[$k].depth - 1)) | $j] | last) else . end)
      | . as $all
      | map(. as $nd
          | (if $nd.rx == "" then {re: "", err: null} else ($nd.rx | rg_norm) end) as $r
          | {i, parent, depth, name, key: (.name | rg_key), regex: $r.re, err: $r.err, view,
             leaf: ([$all[] | select(.parent == $nd.i and (.view | not))] | length == 0), orphan: false})
    end' "$f" 2>/dev/null || printf '[]\n'
}

# a IDENTIDADE da árvore e do roster (inode:tamanho:mtime; "-" = não existe). Não basta `-nt`: devolver um
# regions.json com `mv`/`cp -p`/restauração de backup traz o mtime ANTIGO e o cache ficaria com o mapa velho.
_rg_stamp(){ local d="$CONTESTSDIR/$1" f o=""
  for f in regions.json registrations.json; do o+="$(stat -c '%i:%s:%Y' "$d/$f" 2>/dev/null || printf -- '-')|"; done
  printf '%s' "$o"; }
_rg_stale(){  # <c> <arquivo> — 0 se o cache precisa ser refeito
  local d="$CONTESTSDIR/$1" f="$2"
  [[ -s "$f" ]] || return 0
  [[ "$(cat "$d/var/.regions-map.stamp" 2>/dev/null)" == "$(_rg_stamp "$1")" ]] || return 0   # árvore/roster mudou
  [[ -d "$d/users" ]] || return 1
  [[ -n "$(find "$d/users" -maxdepth 0 -newer "$f" -print -quit 2>/dev/null)" ]] && return 0
  [[ -n "$(find "$d/users" -mindepth 2 -maxdepth 2 -name account.json -newer "$f" -print -quit 2>/dev/null)" ]] && return 0
  return 1
}

# rg_inputs <c> <dir> — a população do contest: <dir>/dirs (logins, menos papéis) e <dir>/explicit
# (login \t chave \t nome da sede GRAVADA). join, NÃO @tsv (ver rg_compute). Contest COMPARTILHADO: quem só
# tem dir (sem account.json local) herda a sede gravada da conta na FONTE — consultada por caminho, só p/
# esses logins (nunca varrer o treino).
rg_inputs(){
  local d="$CONTESTSDIR/$1" w="$2" src
  find "$d/users" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | grep -v '^\.' | grep -vE "$RG_ROLE_RE" \
    | LC_ALL=C sort > "$w/dirs"
  local jqp="$(rg_norm_jq)"' ((.team.region // "") | tostring) as $r
        | [(input_filename | split("/") | .[-2]), ($r | rg_key), ($r | gsub("[\t\n\r]"; " ") | gsub("^ +| +$"; ""))] | join("\t")'
  find "$d/users" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
    | xargs -0 -r jq -r "$jqp" 2>/dev/null > "$w/explicit"
  # USERS_FROM lido do conf por sed (como o sc_users): o mapa é o MESMO seja quem for que o reconstrua —
  # a API (com auth.sh) ou o stats-gen/classify (sem) — senão o cache mudaria conforme o último a gravar
  src="$(sed -n 's/^[[:space:]]*USERS_FROM=//p' "$d/conf" 2>/dev/null | tail -1)"; src="${src//\'/}"; src="${src//\"/}"
  [[ -n "$src" && "$src" =~ ^[A-Za-z0-9._-]+$ && "$src" != *..* ]] || src="$1"
  if [[ -n "$src" && "$src" != "$1" && -d "$CONTESTSDIR/$src/users" ]]; then
    while IFS= read -r l; do
      [[ -f "$d/users/$l/account.json" || ! -f "$CONTESTSDIR/$src/users/$l/account.json" ]] || printf '%s\0' "$CONTESTSDIR/$src/users/$l/account.json"
    done < "$w/dirs" | xargs -0 -r jq -r "$jqp" 2>/dev/null | gawk -F'\t' '$2 != ""' >> "$w/explicit"
  fi
}

# rg_compute <tree.json|""> <dirs> <explicit> <out> — o casamento, sem tocar em contest nenhum:
# <out>/nodes.json + <out>/map.tsv. É o que o rg_build grava e o que a PRÉVIA (dry_run) mostra.
rg_compute(){
  local tree="$1" dirs="$2" expl="$3" o="$4" rc=0
  command -v gawk >/dev/null 2>&1 || return 1          # `awk` pode ser o mawk na imagem
  mkdir -p "$o" || return 1
  rg_flatten "$tree" > "$o/base.json"
  # join, NÃO @tsv: o @tsv dobra a barra invertida e estragaria a regex (a chave não tem tab: rg_key)
  jq -r '.[] | [.i, .parent, .depth, (if .view then 1 else 0 end), .key, .regex, (if .leaf then 1 else 0 end)] | map(tostring) | join("\t")' \
    "$o/base.json" > "$o/nodes.tsv"
  : > "$o/synth.tsv"
  gawk -v synthf="$o/synth.tsv" -f <(_rg_gawk) "$o/nodes.tsv" "$expl" "$dirs" > "$o/map.tsv" || rc=1
  (( rc == 0 )) && jq -c --rawfile s "$o/synth.tsv" '. + [($s | split("\n")[] | select(length > 0) | split("\t")
          | {i: (.[0] | tonumber), parent: -1, depth: 0, name: .[2], key: .[1], regex: "", err: null,
             view: false, leaf: true, orphan: true})]' "$o/base.json" > "$o/nodes.json" || rc=1
  return "$rc"
}

# rg_build <c> — reconstrói var/regions-{nodes.json,map.tsv}. Escrita atômica (tmp + mv): dois builds
# simultâneos produzem o mesmo resultado, o último mv vence.
rg_build(){
  local c="$1" d="$CONTESTSDIR/$1" w rc=0
  mkdir -p "$d/var" 2>/dev/null
  w="$(mktemp -d)" || return 1
  local st; st="$(_rg_stamp "$c")"                     # ANTES de ler: mudou durante o build = refaz na próxima
  rg_inputs "$c" "$w"
  rg_compute "$d/regions.json" "$w/dirs" "$w/explicit" "$w/out" || rc=1
  if (( rc == 0 )); then
    mv -f "$w/out/nodes.json" "$d/var/regions-nodes.json" && mv -f "$w/out/map.tsv" "$d/var/regions-map.tsv" \
      && printf '%s' "$st" > "$d/var/.regions-map.stamp" || rc=1
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
      if (fl[k] == "x") continue                          # a órfã (o) também: é onde ela fica pendurada
      if (!((k) in dv) || d > bd[k]) { if (L[k] ~ r) { dv[k] = i; bd[k] = d } }
    }
  }
  for (k = 1; k <= u; k++) if (fl[k] == "-" && (k in dv)) site[k] = dv[k]
  for (j = 1; j <= nv; j++) { v = V[j]; if (re[v] == "") continue; r = re[v]
    for (k = 1; k <= u; k++) if (L[k] ~ r) own[v, k] = 1 }
  IGNORECASE = 0
  for (k = 1; k <= u; k++) {
    if (fl[k] == "-" && site[k] >= 0) fl[k] = (lf[site[k]] == 1) ? "r" : "p"
    delete mem; delete inv
    s = site[k] + 0; sk = (s < 0) ? "" : ((s >= n) ? synkey[s] : key[s])
    a2 = (fl[k] == "o" && (k in dv)) ? dv[k] + 0 : -1; ak = (a2 >= 0) ? key[a2] : ""   # onde a órfã pendura
    if (s >= n) mem[s] = 1                              # órfã: fora da árvore
    for (j = n; j >= 1; j--) {                          # filhos antes dos pais (pré-ordem ao contrário)
      i = I[j]
      if (!inv[i]) {
        if (vw[i] == 0) inv[i] = (s >= 0 && (i + 0 == s || (sk != "" && key[i] == sk))) || (a2 >= 0 && (i + 0 == a2 || key[i] == ak))
        else inv[i] = (re[i] != "") ? ((i, k) in own) : ((sk != "" && key[i] == sk) || (ak != "" && key[i] == ak))
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

# rg_tree_errors <tree.json> — os nós cuja regex saiu do subconjunto seguro: [{i, path, name, regex, err}].
# Vazio = ok (a FORMA é o cc_regions_ok). `path` = os nomes da raiz até o nó ("Brasil › DF").
rg_tree_errors(){
  local f="$1" w; w="$(mktemp)" || return 1
  rg_flatten "$f" > "$w"
  jq -c --slurpfile n "$w" "$(rg_norm_jq)"'
    (if type == "array" then [rg_flat(-1; 0; false) | .rx] else [] end) as $rx | $n[0] as $n
    | [ $n[] | select(.err != null) | . as $x
        | {i, name, regex: $rx[.i], err,
           path: ([ $x | recurse(if .parent >= 0 then $n[.parent] else empty end) | .name ] | reverse | join(" › "))} ]' "$f" 2>/dev/null     || printf '[]
'
  rm -f "$w"
}

# rg_sig <c> — assinatura do regions.json (a trava do salvar: expect_sig ≠ = alguém mudou antes)
rg_sig(){
  local f="$CONTESTSDIR/$1/regions.json"
  if [[ -f "$f" ]]; then sha1sum < "$f" | cut -c1-16; else printf 'none'; fi
}

# rg_summary <nodes.json> <map.tsv> — o resumo da prévia: contagem por flag, membros por nó, órfãs,
# quem parou no pai e quem ficou sem sede (≤ 50 de cada)
rg_summary(){
  jq -c --rawfile m "$2" '
    ($m | split("\n") | map(select(length > 0) | split("\t"))) as $r
    | (reduce $r[] as $x ({}; reduce ($x[2] | split(",")[] | select(length > 0)) as $i (.; .[$i] += 1))) as $cnt
    | {logins: ($r | length),
       counts: {explicit: ([$r[] | select(.[3] == "x")] | length), orphan: ([$r[] | select(.[3] == "o")] | length),
                regex: ([$r[] | select(.[3] == "r")] | length), stopped: ([$r[] | select(.[3] == "p")] | length),
                none: ([$r[] | select(.[3] == "-")] | length)},
       nodes: [ .[] | {i, name, parent, depth, view, orphan, err, members: ($cnt[.i | tostring] // 0)} ],
       orphans: [ .[] | select(.orphan) | .name ],
       stopped: ([ $r[] | select(.[3] == "p") | .[0] ] | .[0:50]),
       none: ([ $r[] | select(.[3] == "-") | .[0] ] | .[0:50])}' "$1"
}

# rg_resolve <c> <in.tsv> <out> — quem RECEBE cada atribuição. Saída separada por \x1f (NÃO tab: o tab é
# espaço p/ o IFS do `read`, e campo vazio — a sede "" que TIRA — sumiria e escorregaria os outros):
#   login ␟ alvo ␟ sede ␟ tipo ␟ erro
#   tipo team = time inscrito (membro de time → o time); individual = inscrito individual (os dois vão no
#   ROSTER: o overlay de inscrição é reescrito a cada materialize); account = tem account.json; overlay =
#   compartilhado que só tem DIR (ganha overlay); erro = login_invalid | role_login | login_not_in_contest.
#   A sede é saneada como o team_fields_json (sem tab/quebra/":", ≤ 120).
rg_resolve(){
  local c="$1" in="$2" out="$3" d="$CONTESTSDIR/$1" w; w="$(mktemp -d)" || return 1
  RG_ROLE_RE="$RG_ROLE_RE" gawk -F'\t' 'BEGIN { OFS = "\t"; role = ENVIRON["RG_ROLE_RE"] }   # ENVIRON: -v/var= processaria o \.
    { l = $1; r = $2; gsub(/[\t\r\n:]/, " ", r); gsub(/^ +| +$/, "", r); r = substr(r, 1, 120)
      e = (l !~ /^[A-Za-z0-9._@#+-]+$/ || index(l, "..")) ? "login_invalid" : ((l ~ role) ? "role_login" : "")
      print l, r, e }' "$in" > "$w/in"
  if [[ -s "$d/registrations.json" ]]; then
    declare -F reg_get >/dev/null || source "${_LIBDIR:-${BASH_SOURCE[0]%/*}}/registration.sh"
    reg_get "$c" | jq -r '(.teams | keys[] | [., ., "team"]), (.entries | to_entries[]
        | if .value.kind == "team" and ((.value.team // "") != "") then [.key, .value.team, "team"]
          elif .value.kind == "individual" then [.key, .key, "individual"] else empty end) | join("\t")' > "$w/roster"
  else : > "$w/roster"; fi
  gawk -F'\t' -v D="$d/users" 'BEGIN { OFS = "\037" }
    FILENAME == ARGV[1] { tgt[$1] = $2; kd[$1] = $3; next }
    { l = $1; r = $2; e = $3
      if (e != "") { print l, "", r, "", e; next }
      if (l in tgt) { print l, tgt[l], r, kd[l], ""; next }
      if ((getline x < (D "/" l "/account.json")) >= 0) { close(D "/" l "/account.json"); print l, l, r, "account", ""; next }
      if (system("test -d \"" D "/" l "\"") == 0) { print l, l, r, "overlay", ""; next }
      print l, "", r, "", "login_not_in_contest" }' "$w/roster" "$w/in" > "$out"
  rm -rf "$w"
}

# rg_assign_many <c> <in.tsv> <res.tsv> — GRAVA as sedes (login \t sede; sede "" = tira). res.tsv: login \t
# alvo \t erro (vazio = ok). O roster muda num jq só e só os afetados são re-materializados; conta = merge.
rg_assign_many(){
  local c="$1" in="$2" res="$3" d="$CONTESTSDIR/$1" w l t r k e
  w="$(mktemp -d)" || return 1
  declare -F account_merge >/dev/null || source "${_LIBDIR:-${BASH_SOURCE[0]%/*}}/users.sh"
  rg_resolve "$c" "$in" "$w/rv"
  : > "$res"
  if gawk -F'\037' '$4 == "team" || $4 == "individual" { f = 1 } END { exit !f }' "$w/rv"; then
    declare -F reg_get >/dev/null || source "${_LIBDIR:-${BASH_SOURCE[0]%/*}}/registration.sh"
    gawk -F'\037' '($4 == "team" || $4 == "individual") { print $2 "\037" $3 "\037" $4 }' "$w/rv" > "$w/roster-upd"
    reg_save "$c" "$(reg_get "$c" | jq -c --rawfile u "$w/roster-upd" '
        reduce ($u | split("\n")[] | select(length > 0) | split("\u001f")) as $x (.;
          if $x[2] == "team" then .teams[$x[0]].region = $x[1] else .entries[$x[0]].region = $x[1] end)')" \
      || { gawk -F'\037' '{ print $1 "\t" $2 "\t" (($4 == "team" || $4 == "individual") ? "save_failed" : $5) }' "$w/rv" > "$res"; rm -rf "$w"; return 1; }
    sort -u "$w/roster-upd" | while IFS=$'\037' read -r t r k; do
      if [[ "$k" == team ]]; then reg_materialize_team "$c" "$t" >/dev/null 2>&1
      else
        reg_materialize_login "$c" "$t" "$(reg_get "$c" | jq -r --arg l "$t" '.entries[$l].cohort // "individual"')" >/dev/null 2>&1
        # conta LOCAL inscrita: o materialize só acrescenta — limpar tem de apagar no account também
        [[ -z "$r" && -f "$d/users/$t/account.json" ]] && account_merge "$c" "$t" 'del(.team.region)'
      fi
    done
  fi
  while IFS=$'\037' read -r l t r k e; do
    if [[ -n "$e" || "$k" == team || "$k" == individual ]]; then printf '%s\t%s\t%s\n' "$l" "$t" "$e" >> "$res"; continue; fi
    if [[ "$k" == overlay ]] && ! shared_overlay_ensure "$c" "$t"; then printf '%s\t\tlogin_not_in_contest\n' "$l" >> "$res"; continue; fi
    if [[ -n "$r" ]]; then account_merge "$c" "$t" '.team = ((.team // {}) + {region: $r}) | .updated_at = $t' --arg r "$r" --argjson t "$EPOCHSECONDS"
    else account_merge "$c" "$t" 'del(.team.region) | .updated_at = $t' --argjson t "$EPOCHSECONDS"; fi \
      && printf '%s\t%s\t\n' "$l" "$t" >> "$res" || printf '%s\t%s\tsave_failed\n' "$l" "$t" >> "$res"
  done < "$w/rv"
  declare -F _score_dirty >/dev/null && _score_dirty "$c"
  rm -rf "$w"
}

# rg_preview <c> <tree.json|""> <assign.tsv|""> <out> — a PRÉVIA sem gravar nada: a árvore proposta (ou a
# atual) + as atribuições propostas sobre a sede gravada de hoje → <out>/{nodes.json,map.tsv}
rg_preview(){
  local c="$1" tree="$2" as="$3" o="$4" w; w="$(mktemp -d)" || return 1
  [[ -n "$tree" ]] || tree="$CONTESTSDIR/$c/regions.json"
  rg_inputs "$c" "$w"
  if [[ -n "$as" && -s "$as" ]]; then
    rg_resolve "$c" "$as" "$w/rv"
    gawk -F'\037' '$5 == "" { print $2 "\t" $3 }' "$w/rv" | jq -Rr "$(rg_norm_jq)"' split("\t") | [.[0], (.[1] // "" | rg_key),
        (.[1] // "" | gsub("[\t\n\r]"; " ") | gsub("^ +| +$"; ""))] | join("\t")' > "$w/ovr"
    gawk -F'\t' 'FILENAME == ARGV[1] { o[$1] = $0; next } !($1 in o) { print } END { for (l in o) { split(o[l], a, "\t"); if (a[2] != "") print o[l] } }' \
      "$w/ovr" "$w/explicit" > "$w/explicit2"
    mv -f "$w/explicit2" "$w/explicit"
  fi
  rg_compute "$tree" "$w/dirs" "$w/explicit" "$o"; local rc=$?
  rm -rf "$w"; return "$rc"
}

# --- p/ os CONSUMIDORES (lidos de arquivo: nada de mapa grande em argv) ---------------------------------
# rg_sites_json <c> <out> — {login: nome da sede} de quem TEM sede (gravada ou pela regex)
rg_sites_json(){
  local m; m="$(rg_map "$1")" || { printf '{}' > "$2"; return 1; }
  jq -Rn --slurpfile n "$CONTESTSDIR/$1/var/regions-nodes.json" '
    [inputs | split("\t") | select((.[1] | tonumber) >= 0) | {key: .[0], value: $n[0][.[1] | tonumber].name}] | from_entries' \
    "$m" > "$2" 2>/dev/null || { printf '{}' > "$2"; return 1; }
}
# rg_keys_json <c> <out> — {login: [chaves dos nós em que está]} (o `region:<nome>` do escopo casa aqui)
rg_keys_json(){
  local m; m="$(rg_map "$1")" || { printf '{}' > "$2"; return 1; }
  jq -Rn --slurpfile n "$CONTESTSDIR/$1/var/regions-nodes.json" '
    [inputs | split("\t") | {key: .[0], value: [.[2] | split(",")[] | select(length > 0) | $n[0][tonumber].key] | unique}] | from_entries' \
    "$m" > "$2" 2>/dev/null || { printf '{}' > "$2"; return 1; }
}
# rg_keys_of <c> <login> — as chaves dos nós em que <login> está, 1/linha
rg_keys_of(){
  local m ns; m="$(rg_map "$1")" || return 1
  ns="$(gawk -F'\t' -v l="$2" '$1 == l { print $3; exit }' "$m")"
  [[ -n "$ns" ]] || return 0
  jq -r --arg ns "$ns" '. as $n | $ns | split(",")[] | $n[tonumber].key' "$CONTESTSDIR/$1/var/regions-nodes.json" | sort -u
}
