# lib/ua-gate.sh — GATE DE NAVEGADOR POR SEDE.
#
# A máquina de prova de cada sede roda uma imagem cujo User-Agent carrega um pedaço do PRÓPRIO
# login do time: `teambrspso001` (Brasil/BR, São Paulo/SP, sede Sorocaba/SO) roda numa imagem
# cujo UA contém `brspso`. Uma substring única para todo o contest (o antigo
# `LOGIN_UA_SUBSTRING`) não dá conta disso, e alguns times precisam ficar ISENTOS (máquina
# reserva, time que chegou de outro jeito).
#
#   contests/<c>/ua-gate.json   (ausente ⇒ cai no LOGIN_UA_SUBSTRING de sempre)
#   { "mode": "enforce",                                  // enforce | off
#     "single_session": true,                             // login em outra máquina derruba a anterior
#     "from_login": {"regex":"^team([a-z]{6})[0-9]{3}$", "expect":"\\1"},
#     "by_region":  {"Sorocaba":"brspso", "Campinas":"brspcp"},
#     "by_regex":   [{"regex":"^conv","expect":"convidado"}],
#     "exempt":     ["^ccl", "time-reserva-07"],
#     "fallback":   "" }
#
# ORDEM DE RESOLUÇÃO (ua_expected):
#   1. `exempt` casa o login (regex, case-insensitive)          -> sem gate
#   2. conta de papel (.admin/.judge/.cjudge/.staff/.cstaff/.mon) -> sem gate (precisa entrar
#      para configurar; é a mesma isenção de sempre)
#   3. `by_regex` (1ª que casa)                                  -> o `expect` dela
#   4. `by_region` pela SEDE do time (`.team.region`; sem ela, derivada de regions.json)
#   5. `from_login` (captura no login + substituição no `expect`) -> o esperado por sede "de graça"
#   6. `fallback` (ou o legado LOGIN_UA_SUBSTRING)
#   7. nada casa                                                 -> sem gate
#
# O match é SUBSTRING case-insensitive (UA de imagem é estável; ser tolerante aqui evita barrar
# time por causa de maiúscula). `mode:off` responde sempre "sem gate" — o painel de Máquinas
# continua mostrando quem estaria fora do padrão.

ug_file(){ printf '%s/%s/ua-gate.json' "$CONTESTSDIR" "$1"; }

# ug_get <c> -> o JSON normalizado (defaults coerentes quando não existe)
ug_get(){
  local f; f="$(ug_file "$1")"
  if [[ -s "$f" ]] && jq -e . "$f" >/dev/null 2>&1; then
    jq -c '{mode:(if .mode == "off" then "off" else "enforce" end),
            from_login:(if (.from_login.regex // "") != "" then
                          {regex:(.from_login.regex), expect:((.from_login.expect // "\\1"))}
                        else null end),
            by_region:(.by_region // {}),
            by_regex:[ (.by_regex // [])[] | select((.regex // "") != "" and (.expect // "") != "")
                       | {regex, expect} ],
            exempt:[ (.exempt // [])[] | tostring | select(length > 0) ],
            fallback:((.fallback // "") | tostring),
            single_session:(if .single_session == false then false else true end)}' "$f" 2>/dev/null \
      || printf '{"mode":"enforce","from_login":null,"by_region":{},"by_regex":[],"exempt":[],"fallback":"","single_session":true}'
  else printf '{"mode":"enforce","from_login":null,"by_region":{},"by_regex":[],"exempt":[],"fallback":"","single_session":true}'; fi
}
# single_session (default true): com o gate ligado p/ um login, um login NOVO em outra máquina
# revoga a sessão anterior dele (lib/session-index.sh). `false` desliga só isso, mantendo o gate.
ug_save(){ local f; f="$(ug_file "$1")"; printf '%s\n' "$2" > "$f.tmp" && mv -f "$f.tmp" "$f"; }

# ug_legacy <c> -> LOGIN_UA_SUBSTRING do conf (lido por grep: o caminho de auth nunca sourceia
# o conf, que roda command substitution). Mesmo idioma de handlers/auth/login.sh.
ug_legacy(){
  local v
  v="$(grep -m1 '^LOGIN_UA_SUBSTRING=' "$CONTESTSDIR/$1/conf" 2>/dev/null | cut -d= -f2-)"
  v="${v%\'}"; v="${v#\'}"; v="${v%\"}"; v="${v#\"}"
  printf '%s' "$v"
}

# ug_region_of <c> <login> -> sede do time: `.team.region` explícita, senão derivada pelo regex
# de regions.json (a mesma derivação de handlers/contest/badges.sh)
ug_region_of(){
  local c="$1" l="$2" r
  r="$(jq -r '.team.region // ""' "$CONTESTSDIR/$c/users/$l/account.json" 2>/dev/null)"
  [[ -n "$r" ]] && { printf '%s' "$r"; return 0; }
  [[ -s "$CONTESTSDIR/$c/regions.json" ]] || return 0
  jq -r --arg l "$l" '
    [.. | objects | select((.regex // "") != "")]
    | first(.[] | .regex as $rr | select(try ($l|test($rr;"i")) catch false) | (.name // $rr)) // ""' \
    "$CONTESTSDIR/$c/regions.json" 2>/dev/null
}

# ug_expected <c> <login> -> a substring de UA esperada ("" = sem gate para este login)
ug_expected(){
  local c="$1" l="$2" g reg out
  [[ -n "$l" ]] || return 0
  g="$(ug_get "$c")"
  [[ "$(jq -r '.mode' <<<"$g")" == off ]] && return 0
  # 1. isento? (regex bindado antes do test — armadilha de contexto de args do jq)
  jq -e --arg l "$l" 'any(.exempt[]; . as $rr | (try ($l|test($rr;"i")) catch false))' \
    <<<"$g" >/dev/null 2>&1 && return 0
  # 2. conta de papel: sempre entra (é quem configura o gate)
  case "$l" in *.admin|*.judge|*.cjudge|*.staff|*.cstaff|*.mon|*.animeitor) return 0;; esac
  # 3./5. by_regex e from_login resolvem no mesmo jq
  out="$(jq -r --arg l "$l" '
    # `// null` é obrigatório: `first()` de stream VAZIO é vazio, e `vazio as $v | …` faz a
    # expressão inteira não produzir NADA (o esperado saía sempre "" quando nenhuma by_regex
    # casava). Mesma armadilha do `first(...) // …` no resto do repo.
    ((first(.by_regex[] | .regex as $rr | select(try ($l|test($rr;"i")) catch false) | .expect)) // null) as $byrx
    | if $byrx != null then $byrx
      else
        (if .from_login == null then ""
         else ((.from_login.regex) as $rr | (.from_login.expect) as $ex
               # `sub` do jq NÃO entende \1: as capturas vêm do `match` e a substituição de
               # \1,\2,… no template é feita aqui — assim o admin escreve o \1 de sempre.
               | (((try ($l | match($rr; "i")) catch null)) // null) as $m
               | if $m == null then ""
                 else ([$m.captures[]?.string // ""]) as $g
                      | reduce range(0; ($g | length)) as $i ($ex;
                          gsub("[\\\\]" + (($i + 1) | tostring); ($g[$i] // "")))
                 end)
         end)
      end' <<<"$g")"
  # 4. by_region tem precedência sobre o from_login (imagem da sede fora do padrão)
  reg="$(ug_region_of "$c" "$l")"
  if [[ -n "$reg" ]]; then
    local byreg
    byreg="$(jq -r --arg r "$reg" '(.by_region[$r] // "")' <<<"$g")"
    [[ -n "$byreg" ]] && { printf '%s' "$byreg"; return 0; }
  fi
  [[ -n "$out" ]] && { printf '%s' "$out"; return 0; }
  # 6. fallback do arquivo, senão o legado do conf
  out="$(jq -r '.fallback' <<<"$g")"
  [[ -n "$out" ]] || out="$(ug_legacy "$c")"
  printf '%s' "$out"
}

# ug_ok <c> <login> <ua> -> 0 se pode entrar (sem gate, ou o UA contém o esperado)
ug_ok(){
  local exp; exp="$(ug_expected "$1" "$2")"
  [[ -n "$exp" ]] || return 0
  local ua="${3:-}"
  [[ "${ua,,}" == *"${exp,,}"* ]]
}

# ---------- resolvedor em LOTE (mesma ordem do ug_expected, num jq só) -----------------------
# UG_JQ define `ug_expect($g; $l; $reg)`: o esperado para o login $l cuja sede é $reg, segundo o
# gate $g. É a MESMA lógica do ug_expected — vive aqui uma vez só para os dois caminhos (o
# individual, no login, e o em lote, no painel de Máquinas, que não pode forkar por time).
UG_JQ='
  def ug_expect($g; $l; $reg):
    if ($g.mode == "off") then ""
    elif any($g.exempt[]; . as $rr | (try ($l|test($rr;"i")) catch false)) then ""
    elif ($l | test("\\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$")) then ""
    else
      (((first($g.by_regex[] | .regex as $rr
                | select(try ($l|test($rr;"i")) catch false) | .expect)) // null) as $byrx
       | (if $reg != "" then ($g.by_region[$reg] // "") else "" end) as $byreg
       | (if $g.from_login == null then ""
          else (($g.from_login.regex) as $rr | ($g.from_login.expect) as $ex
                # match SEM casamento devolve VAZIO (não erro): sem o `// null`, o
                # `vazio as $m` anularia a expressão inteira (era o que sumia com o by_regex).
                | (((try ($l | match($rr; "i")) catch null)) // null) as $m
                | if $m == null then ""
                  else ([$m.captures[]?.string // ""]) as $c
                       | reduce range(0; ($c|length)) as $i ($ex;
                           gsub("[\\\\]" + (($i+1)|tostring); ($c[$i] // "")))
                  end)
          end) as $fromlogin
       | if $byrx != null and $byrx != "" then $byrx
         elif $byreg != "" then $byreg
         elif $fromlogin != "" then $fromlogin
         else ($g.fallback // "") end)
    end;
'

# ug_expected_map <c> <logins-json> [<regions-map-json>] -> {login: esperado}
# `logins-json` = ["login", …]; `regions-map-json` = {"login":"sede"} (opcional — sem ele a sede
# de cada login é lida do account.json numa passada).
ug_expected_map(){
  local c="$1" logins="$2" regmap="${3:-}"
  [[ -n "$logins" && "$logins" != '[]' ]] || { printf '{}'; return 0; }
  if [[ -z "$regmap" || "$regmap" == null ]]; then
    regmap="$( { find "$CONTESTSDIR/$c/users" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
        | xargs -0 -r jq -c '{key:(.login // ""), value:((.team.region) // "")}'; } \
        | jq -cs 'from_entries' 2>/dev/null)"
    [[ -n "$regmap" ]] || regmap='{}'
  fi
  # o `fallback` do lote já vem resolvido com o legado do conf, senão o resultado divergiria
  # do caminho individual (que consulta o LOGIN_UA_SUBSTRING no fim)
  local g; g="$(jq -c --arg lg "$(ug_legacy "$c")" \
      '.fallback = (if (.fallback // "") != "" then .fallback else $lg end)' <<<"$(ug_get "$c")")"
  jq -cn --argjson g "$g" --argjson ls "$logins" --argjson rm "$regmap" \
    "$UG_JQ"' [ $ls[] | {key:., value: ug_expect($g; .; ($rm[.] // "")) } ] | from_entries'
}
