# lib/print.sh — pedidos de impressão (.staff) do modo contest.
# Sourced pelos handlers contest/print*, contest/staff/* e contest/admin/staff-filters.sh
# (o router já carregou common.sh/auth.sh, então valid_id/is_admin/is_staff/is_cstaff/
# audit_log_to/user_fullname/_users_source estão disponíveis).
#
# Modelo de dados em contests/<c>/print-requests/:
#   .seq/.seqlock        contador monotônico + flock
#   <id>.json            metadados/estado (pending|printed|delivered)
#   <id>.src             arquivo cru enviado pelo aluno
#   <id>.combined.pdf    cache: folha de rosto + documento normalizado
#   <id>.lock            flock de build + transições de estado
#   staff-filters.json   { "<login .staff|.cstaff>": ["region:<nome>"|regex,...] }
#                        (vazio/ausente = vê tudo; escopa fila, etiquetas e cerimônia)

# --- localização / flags --------------------------------------------------
pr_dir() { printf '%s' "$CONTESTSDIR/$1/print-requests"; }

# _pr_role_accounts <usersdir> <glob> — TSV "login\tfullname\tdisabled" das contas de papel
# do dir cujo login casa o glob (*.staff | *.cstaff). Subshell: nullglob + noglob off (o
# common.sh liga noglob) p/ o glob expandir; $pat fica sem aspas de propósito.
_pr_role_accounts() {
  local d="$1" pat="$2" af
  ( set +o noglob 2>/dev/null; shopt -s nullglob
    for af in "$d"/$pat/account.json; do
      jq -r '[.login//"", .fullname//"",
              (if ((.password//"")|startswith("!")) then "true" else "false" end)] | @tsv' \
        "$af" 2>/dev/null
    done )
}

# existe ao menos um usuário .staff habilitado (store próprio + fonte compartilhada)?
# SÓ *.staff conta: .cstaff não opera a fila — sem staff de verdade não há impressão p/ aluno.
staff_exists() {
  local c="$1" s
  _pr_role_accounts "$CONTESTSDIR/$c/users" '*.staff' | awk -F'\t' '$3=="false"{found=1} END{exit found?0:1}' && return 0
  s="$(_users_source "$c")"
  [[ "$s" != "$c" ]] \
    && _pr_role_accounts "$CONTESTSDIR/$s/users" '*.staff' | awk -F'\t' '$3=="false"{found=1} END{exit found?0:1}' && return 0
  return 1
}

# impressão habilitada pelo admin? (conf PRINT=0 desliga; default ligado)
print_enabled() {
  [[ "$( . "$CONTESTSDIR/$1/conf" 2>/dev/null; printf '%s' "${PRINT:-}")" != 0 ]]
}

# logins .staff ∪ .cstaff (únicos), um por linha: "login\tfullname\tdisabled(true|false)".
# É a lista de CHAVES válidas do staff-filters — o admin escopa os dois papéis por aqui.
pr_staff_logins() {
  local c="$1" s
  { _pr_role_accounts "$CONTESTSDIR/$c/users" '*.staff'
    _pr_role_accounts "$CONTESTSDIR/$c/users" '*.cstaff'
    s="$(_users_source "$c")"
    [[ "$s" != "$c" ]] && { _pr_role_accounts "$CONTESTSDIR/$s/users" '*.staff'
                            _pr_role_accounts "$CONTESTSDIR/$s/users" '*.cstaff'; }
  } | awk -F'\t' '!seen[$1]++'
}

# logins .cstaff (únicos) — alimenta o seletor "arquivo de uma sede" das etiquetas.
pr_cstaff_logins() {
  local c="$1" s
  { _pr_role_accounts "$CONTESTSDIR/$c/users" '*.cstaff'
    s="$(_users_source "$c")"; [[ "$s" != "$c" ]] && _pr_role_accounts "$CONTESTSDIR/$s/users" '*.cstaff'
  } | awk -F'\t' '!seen[$1]++'
}

# --- contador sequencial (monotônico, sob flock) --------------------------
pr_next_seq() {
  local c="$1" dir; dir="$(pr_dir "$c")"; mkdir -p "$dir"
  ( flock 9
    local n; n="$(cat "$dir/.seq" 2>/dev/null || echo 0)"
    [[ "$n" =~ ^[0-9]+$ ]] || n=0
    n=$((n+1)); printf '%s' "$n" > "$dir/.seq"; printf '%s' "$n"
  ) 9>"$dir/.seqlock"
}

# --- escopo: este staff/cstaff pode ver as tarefas deste aluno? ------------
# Keyed pelo LOGIN (vale igual p/ .staff e .cstaff). admin vê tudo; lista vazia/ausente
# = vê tudo; senão cada entrada é:
#   "region:<nome>" — casa com o `.team.region` do account.json do aluno (igualdade,
#                     case-insensitive) — o jeito "por sede" sem regex;
#   qualquer outra   — regex testada no LOGIN do aluno (comportamento clássico).
staff_can_see() {  # <c> <staff_login> <student_login>
  local c="$1" staff="$2" who="$3" f reg
  is_admin && return 0
  f="$(pr_dir "$c")/staff-filters.json"
  [[ -f "$f" ]] || return 0
  reg="$(_pr_acct "$c" "$who" '.team.region')"
  jq -e --arg w "$who" --arg s "$staff" --arg reg "$reg" '
    ($w|ascii_downcase) as $wl
    | ($reg|ascii_downcase) as $rg
    | (.[$s] // [])
    | if length==0 then true
      else any(.[]; . as $r
        | if ($r|startswith("region:"))
          then ($rg != "" and (($r[7:] | ascii_downcase | gsub("^ +| +$"; "")) == $rg))
          else (try ($wl|test($r;"i")) catch false) end)
      end
  ' "$f" >/dev/null 2>&1
}

# staff_visible_logins <c> <login> — ecoa (1/linha) os logins de aluno que <login> enxerga,
# pela MESMA semântica de staff_can_see, materializada numa ÚNICA passada (contas por
# find|xargs jq — sem N execuções de jq nem --argjson gigante; filtros por --slurpfile).
# rc=1 = sem filtro p/ este login (escopo vazio/ausente = vê tudo — o chamador NÃO filtra).
staff_visible_logins() {
  local c="$1" who="$2" f n src loc rc
  f="$(pr_dir "$c")/staff-filters.json"
  { [[ -f "$f" ]] && jq -e . "$f" >/dev/null 2>&1; } || return 1
  n="$(jq -r --arg s "$who" '(.[$s] // []) | length' "$f" 2>/dev/null)"
  n="${n//[^0-9]/}"; [[ -n "$n" && "$n" -gt 0 ]] || return 1
  src="$(_users_source "$c")"
  # POPULAÇÃO = quem tem diretório NESTE contest. A fonte USERS_FROM entra só como tabela de
  # região (participante compartilhado sem account.json local) — nunca como população: um escopo
  # com regex de login (`^tg`, `.`) puxaria contas de fora do contest para a lista. Mesma regra
  # que o /contest/badges aprendeu no incidente de 2026-08-18.
  loc="$(mktemp)" || return 1
  find "$CONTESTSDIR/$c/users" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null > "$loc"
  # o login é IMPLÍCITO no nome do diretório (rename de conta é `mv`): o campo .login é só uma
  # cópia e pode faltar (conta escrita à mão, store migrado). Sem o fallback pelo caminho, a
  # conta sumia da lista — e "lista vazia" viraria escopo que não casa ninguém.
  { find "$CONTESTSDIR/$c/users" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
      | xargs -0 -r jq -c '{login:(if (.login//"") == "" then (input_filename|split("/")|.[-2]) else .login end),
                            region:(.team.region//""), prio:0}' 2>/dev/null
    if [[ "$src" != "$c" ]]; then
      find "$CONTESTSDIR/$src/users" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
        | xargs -0 -r jq -c '{login:(if (.login//"") == "" then (input_filename|split("/")|.[-2]) else .login end),
                              region:(.team.region//""), prio:1}' 2>/dev/null
    fi
    true
  } | jq -rs --slurpfile ff "$f" --arg s "$who" --rawfile loc "$loc" '
      ($ff[0][$s] // []) as $scope
      | ($loc | split("\n") | map(select(length > 0)) | map({(.): true}) | add // {}) as $LOC
      | map(select(.login != "")) | group_by(.login) | map(min_by(.prio))
      | map(select($LOC[.login]))                       # só quem é DESTE contest
      | map(select(. as $u | any($scope[]; . as $r
          | if ($r|startswith("region:"))
            then (($u.region // "") != ""
                  and ((($u.region)|ascii_downcase) == ($r[7:] | ascii_downcase | gsub("^ +| +$"; ""))))
            else (try ($u.login | ascii_downcase | test($r;"i")) catch false) end)))
      | .[].login' 2>/dev/null
  rc=$?; rm -f "$loc"; return "$rc"
}

# pr_filter_board <c> <login> — filtra um placar TXT (stdin→stdout) às linhas cujo username
# é visível a <login> (staff_visible_logins). Linha 1 (modo) e linha 2 (header) passam
# INTACTAS. A coluna username dos DADOS é derivada do header descontando as colunas-marcador
# de ordenação iniciais (desc/asc), que as linhas de dados NÃO têm (header icpc =
# desc:asc:flag:username:… ; dado = flag:login:…). Header sem "username" = não filtra.
pr_filter_board() {
  local c="$1" who="$2" vis
  vis="$(mktemp)" || { cat; return 0; }
  if ! staff_visible_logins "$c" "$who" > "$vis"; then
    rm -f "$vis"; cat; return 0
  fi
  awk -F: -v VF="$vis" '
    NR==1 { print; next }
    NR==2 { print
            m=0; while (m<NF && (tolower($(m+1))=="desc" || tolower($(m+1))=="asc")) m++
            ucol=0; for (i=m+1; i<=NF; i++) if (tolower($i)=="username") { ucol=i-m; break }
            while ((getline l < VF) > 0) if (l != "") V[l]=1
            close(VF); next }
    { u=$ucol; if (ucol==0 || (u in V)) print }'
  rm -f "$vis"
}

# _pr_acct <c> <login> <jq-path> — campo do account.json (local, senão USERS_FROM).
_pr_acct() {
  local c="$1" login="$2" v
  v="$(jq -r "$3 // empty" "$CONTESTSDIR/$c/users/$login/account.json" 2>/dev/null)"
  if [[ -z "$v" ]]; then
    local s; s="$(_users_source "$c")"
    [[ "$s" != "$c" ]] && v="$(jq -r "$3 // empty" "$CONTESTSDIR/$s/users/$login/account.json" 2>/dev/null)"
  fi
  printf '%s' "$v"
}

# --- resolução do NOME do time/participante (folha de rosto) ---------------
# Nunca devolve a sigla da universidade — essa vai em pr_resolve_univ. Ordem:
# 1) account.json .team.name  2) fullname — em treino individual, é o participante
pr_resolve_team() {  # <c> <login>
  local c="$1" login="$2" tn=""
  tn="$(_pr_acct "$c" "$login" '.team.name')"
  [[ -z "$tn" ]] && tn="$(user_fullname "$c" "$login")"
  printf '%s' "$tn"
}

# --- resolução da UNIVERSIDADE/escola (folha de rosto, secundária) ----------
# Preferindo o nome completo; pode ser vazia. Ordem:
# 1) account.json: .team.univ_full -> .team.univ_short
# 2) teams-meta.json: school_full -> school (1ª regra cujo regex casa o login)
pr_resolve_univ() {  # <c> <login>
  local c="$1" login="$2" un=""
  local d="$CONTESTSDIR/$c"
  un="$(_pr_acct "$c" "$login" '.team.univ_full')"
  [[ -z "$un" ]] && un="$(_pr_acct "$c" "$login" '.team.univ_short')"
  if [[ -z "$un" && -f "$d/teams-meta.json" ]]; then
    un="$(jq -r --arg w "$login" '
      ((.rules // (if type=="array" then . else [] end))
       | map(. as $r | select(($r.regex // "") != "" and ($w | test($r.regex))))
       | (.[0].school_full // .[0].school // "")) // ""' "$d/teams-meta.json" 2>/dev/null)"
    [[ "$un" == null ]] && un=""
  fi
  printf '%s' "$un"
}

# --- render interno: produz <id>.combined.pdf (chamado SOB flock) ---------
# Persiste pages/build_ok no meta. Folha de rosto (capa) sempre é a página 1.
_pr_render() {  # <c> <id> <src> <meta> <cache>
  local c="$1" id="$2" src="$3" meta="$4" cache="$5"
  local work; work="$(mktemp -d)" || return 1
  trap 'rm -rf "$work"' RETURN
  local doc="$work/doc.pdf" docok=0 mime enc fn ext inp

  mime="$(file -b --mime-type "$src" 2>/dev/null)"
  case "$mime" in
    application/pdf)
      cp "$src" "$doc"
      if pdfinfo "$doc" >/dev/null 2>&1; then docok=1
      elif qpdf --decrypt "$src" "$doc" 2>/dev/null && pdfinfo "$doc" >/dev/null 2>&1; then docok=1
      elif gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -sOutputFile="$doc" "$src" 2>/dev/null && pdfinfo "$doc" >/dev/null 2>&1; then docok=1
      fi ;;
    image/*)
      magick "$src" -resize 1240x1754\> -background white -gravity center -extent 1240x1754 \
        -units PixelsPerInch -density 150 "$doc" 2>/dev/null && [[ -s "$doc" ]] && docok=1 ;;
    text/*)
      # código/texto: numera TODAS as linhas (inclui em branco) antes de renderizar
      nl -ba -w3 -s' | ' "$src" | paps --format=pdf --paper=a4 --font='Monospace 11' > "$doc" 2>/dev/null && [[ -s "$doc" ]] && docok=1 ;;
    *)
      enc="$(file -b --mime-encoding "$src" 2>/dev/null)"
      if [[ "$enc" != binary ]]; then
        nl -ba -w3 -s' | ' "$src" | paps --format=pdf --paper=a4 --font='Monospace 11' > "$doc" 2>/dev/null && [[ -s "$doc" ]] && docok=1
      else
        # office/desconhecido: dá uma extensão real ao input p/ o soffice reconhecer e
        # prever o nome de saída (sem depender de glob, já que common.sh usa noglob).
        fn="$(jq -r '.filename // "arquivo"' "$meta" 2>/dev/null)"
        ext="${fn##*.}"; ext="$(printf '%s' "$ext" | tr -cd 'A-Za-z0-9')"; [[ -n "$ext" && "$ext" != "$fn" ]] || ext=bin
        inp="$work/input.$ext"; cp "$src" "$inp"
        soffice --headless -env:UserInstallation="file://$work/lo" --convert-to pdf --outdir "$work" "$inp" >/dev/null 2>&1
        [[ -f "$work/input.pdf" ]] && mv -f "$work/input.pdf" "$doc" && [[ -s "$doc" ]] && docok=1
      fi ;;
  esac

  local pages=0
  if (( docok )); then
    pages="$(pdfinfo "$doc" 2>/dev/null | awk '/^Pages:/{print $2; exit}')"
    [[ "$pages" =~ ^[0-9]+$ ]] || { pages=0; docok=0; }
  fi

  # --- folha de rosto: blocos `caption:` auto-ajustáveis (letras garrafais que SEMPRE
  # cabem na página — caption escolhe o maior corpo que encaixa na caixa, quebrando linha
  # se o nome do time for longo). Fontes DejaVu (acentos garantidos). ---
  local seq team univ login pagesline FB FR
  seq="$(jq -r '.seq // 0' "$meta" 2>/dev/null)"
  team="$(jq -r '.team // ""' "$meta" 2>/dev/null)"; [[ -n "$team" ]] || team="(sem nome de time)"
  univ="$(jq -r '.univ // ""' "$meta" 2>/dev/null)"
  login="$(jq -r '.login // ""' "$meta" 2>/dev/null)"
  # caption faz expansão de %; neutraliza e evita leitura de @arquivo (dados do passwd)
  cap_esc(){ local s="${1//%/%%}"; [[ "$s" == @* ]] && s=" $s"; printf '%s' "$s"; }
  team="$(cap_esc "$team")"; univ="$(cap_esc "$univ")"; login="$(cap_esc "$login")"
  if (( docok )); then pagesline="$pages página(s)  —  não conte esta folha de rosto"
  else pagesline="ATENÇÃO: não foi possível converter — imprima o anexo cru"; fi
  FB="$(magick -list font 2>/dev/null | awk -F': ' '/Font: DejaVu-Sans-Bold$/{print $2; exit}')"
  [[ -n "$FB" ]] || FB="$(magick -list font 2>/dev/null | awk -F': ' '/Font: /{print $2; exit}')"
  FR="$(magick -list font 2>/dev/null | awk -F': ' '/Font: DejaVu-Sans$/{print $2; exit}')"
  [[ -n "$FR" ]] || FR="$FB"

  local -a cov=( magick -size 1240x1754 xc:white )
  addcap(){ # w h x y fill font weight gravity text
    cov+=( '(' -size "${1}x${2}" -background white -fill "$5" )
    [[ -n "$6" ]] && cov+=( -font "$6" )
    [[ -n "$7" ]] && cov+=( -weight "$7" )
    cov+=( -gravity "$8" "caption:$9" ')' -gravity northwest -geometry "+${3}+${4}" -composite )
  }
  addcap 1080  46  80   78 '#555' "$FR" ''   center "EQUIPE  /  TEAM"
  addcap 1080 210  80  130 black  "$FB" 700  center "$team"
  [[ -n "$univ" ]] && addcap 1080 64 80 352 '#333' "$FR" '' center "$univ"
  addcap 1080  44  80  430 '#555' "$FR" ''   center "login"
  addcap 1080 100  80  478 black  "$FB" 700  center "$login"
  cov+=( -fill none -stroke '#999' -strokewidth 2 -draw "line 80,620 1160,620" -stroke none )
  addcap 1080  56  80  664 '#555' "$FR" ''   center "TAREFA Nº  (confira com o sistema)"
  addcap 1080 220  80  724 black  "$FB" 800  center "$seq"
  addcap 1080  74  80  966 black  "$FR" ''   center "$pagesline"
  cov+=( -fill none -stroke '#999' -strokewidth 2 -draw "line 80,1080 1160,1080" -stroke none )
  addcap  600  46  80 1500 black  "$FR" ''   west   "Assinatura de quem entregou:"
  cov+=( -fill none -stroke black -strokewidth 2 -draw "line 80,1600 700,1600" -stroke none )
  addcap  320  46 760 1500 black  "$FR" ''   west   "Hora da entrega:"
  cov+=( -fill none -stroke black -strokewidth 2 -draw "line 760,1600 1160,1600" -stroke none )
  cov+=( -units PixelsPerInch -density 150 "$work/cover.pdf" )
  local covok=0
  "${cov[@]}" 2>/dev/null && [[ -s "$work/cover.pdf" ]] && covok=1

  # --- combina e publica no cache (atômico) ---
  local built=0
  if (( covok && docok )); then
    pdfunite "$work/cover.pdf" "$doc" "$work/combined.pdf" 2>/dev/null && mv -f "$work/combined.pdf" "$cache" && built=1
  elif (( covok )); then
    mv -f "$work/cover.pdf" "$cache" && built=1            # fallback: só a capa (com aviso)
  elif (( docok )); then
    mv -f "$doc" "$cache" && built=1                        # capa falhou: serve o doc puro
  fi

  # --- persiste pages/build_ok no meta (sob o mesmo flock do chamador) ---
  local okjson; okjson="$([[ $docok -eq 1 ]] && echo true || echo false)"
  jq --argjson p "${pages:-0}" --argjson ok "$okjson" '.pages=$p | .build_ok=$ok' "$meta" \
    > "$work/meta.json" 2>/dev/null && mv -f "$work/meta.json" "$meta"

  (( built ))
}

# pr_build_pdf <c> <id>  -> ecoa o caminho do combined.pdf (cache); rc!=0 em falha total.
# Build-once: o <id>.src é imutável após o upload, então o cache vale para sempre.
pr_build_pdf() {
  local c="$1" id="$2" dir src meta cache
  dir="$(pr_dir "$c")"; src="$dir/$id.src"; meta="$dir/$id.json"; cache="$dir/$id.combined.pdf"
  [[ -f "$src" && -f "$meta" ]] || return 1
  if [[ -f "$cache" && "$cache" -nt "$src" ]]; then printf '%s' "$cache"; return 0; fi
  ( flock -w 30 9 || exit 1
    [[ -f "$cache" && "$cache" -nt "$src" ]] && exit 0      # double-check após o lock
    _pr_render "$c" "$id" "$src" "$meta" "$cache" || exit 1
  ) 9>"$dir/$id.lock"
  [[ -f "$cache" ]] && { printf '%s' "$cache"; return 0; }
  return 1
}

# ===== BALÃO (.staff): tarefa de entrega de balão no veredicto Accepted ======================

# pr_short_of <c> <cid> : ecoa a letra/short do problema cujo id canônico é <cid> (history campo-3).
pr_short_of() {
  local c="$1" cid="$2"
  ( PROBS=(); source "$CONTESTSDIR/$c/conf" 2>/dev/null
    local i n=${#PROBS[@]} canon
    for ((i=0; i<n; i+=5)); do
      canon="${PROBS[i+4]:-}"; [[ "$canon" == *"#"* ]] || canon="${PROBS[i+1]//\//#}"
      [[ "$canon" == "$cid" ]] && { printf '%s' "${PROBS[i+3]:-$((i/5))}"; exit 0; }
    done )
}

# pr_balloon_color <c> <short> : ecoa "RRGGBB" (balloons.json vence; senão default ICPC A–O).
pr_balloon_color() {
  local c="$1" short="$2" col="" f="$CONTESTSDIR/$1/balloons.json"
  { [[ -f "$f" ]] && jq -e . "$f" >/dev/null 2>&1; } && col="$(jq -r --arg k "$short" '.[$k] // empty' "$f" 2>/dev/null)"
  if [[ -z "$col" ]]; then
    case "$short" in
      A) col=FFFFFF;; B) col=000000;; C) col=FF0000;; D) col=800000;; E) col=FFFF00;;
      F) col=008000;; G) col=0000FF;; H) col=000080;; I) col=FF00FF;; J) col=800080;;
      K) col=00FF00;; L) col=00FFFF;; M) col=C0C0C0;; N) col=FF8000;; O) col=A3794D;;
      *) col=CCCCCC;;
    esac
  fi
  col="$(printf '%s' "$col" | tr -cd '0-9A-Fa-f' | tr 'a-f' 'A-F')"; col="${col:0:6}"
  [[ "${#col}" -eq 6 ]] || col=CCCCCC
  printf '%s' "$col"
}

# pr_color_name <RRGGBB> : nome da cor por extenso em PT (tabela dos 15 defaults; fora dela, a cor
# nomeada mais próxima por distância RGB, com o hex entre parênteses).
pr_color_name() {
  local hex; hex="$(printf '%s' "$1" | tr -cd '0-9A-Fa-f' | tr 'a-f' 'A-F')"; hex="${hex:0:6}"
  [[ "${#hex}" -eq 6 ]] || { printf 'cor'; return; }
  # nomes ICPC padrão (PT + inglês p/ o staff casar com o balão físico, geralmente rotulado em inglês)
  case "$hex" in
    FFFFFF) printf 'branco (white)'; return;;        000000) printf 'preto (black)'; return;;
    FF0000) printf 'vermelho (red)'; return;;        800000) printf 'vinho (maroon)'; return;;
    FFFF00) printf 'amarelo (yellow)'; return;;      008000) printf 'verde (green)'; return;;
    0000FF) printf 'azul (blue)'; return;;           000080) printf 'azul-marinho (navy blue)'; return;;
    FF00FF) printf 'rosa (pink)'; return;;           800080) printf 'roxo (purple)'; return;;
    00FF00) printf 'verde-limão (lime green)'; return;;  00FFFF) printf 'azul-claro (light blue)'; return;;
    C0C0C0) printf 'prata (silver)'; return;;        FF8000) printf 'laranja (orange)'; return;;
    A3794D) printf 'marrom (brown)'; return;;
  esac
  local r=$((16#${hex:0:2})) g=$((16#${hex:2:2})) b=$((16#${hex:4:2}))
  local best='cor' bestd=999999999 h name hr hg hb d
  while read -r h name; do
    [[ -n "$h" ]] || continue
    hr=$((16#${h:0:2})); hg=$((16#${h:2:2})); hb=$((16#${h:4:2}))
    d=$(( (r-hr)*(r-hr) + (g-hg)*(g-hg) + (b-hb)*(b-hb) ))
    (( d < bestd )) && { bestd=$d; best="$name"; }
  done <<'NAMES'
FFFFFF branco
000000 preto
FF0000 vermelho
800000 vinho
FFFF00 amarelo
008000 verde
0000FF azul
000080 azul-marinho
FF00FF rosa
800080 roxo
00FF00 verde-limão
00FFFF azul-claro
C0C0C0 prata
FF8000 laranja
A3794D marrom
NAMES
  printf '%s (#%s)' "$best" "$hex"
}

# _pr_render_balloon <c> <id> <meta> <cache> : folha A4 da entrega do balão (sob flock do chamador).
_pr_render_balloon() {
  local c="$1" id="$2" meta="$3" cache="$4"
  local work; work="$(mktemp -d)" || return 1
  trap 'rm -rf "$work"' RETURN
  local seq team univ login short colorhex colorname FB FR
  seq="$(jq -r '.seq // 0' "$meta")"
  team="$(jq -r '.team // ""' "$meta")"; [[ -n "$team" ]] || team="(sem nome de time)"
  univ="$(jq -r '.univ // ""' "$meta")"
  login="$(jq -r '.login // ""' "$meta")"
  short="$(jq -r '.short // "?"' "$meta")"
  colorhex="$(jq -r '.color_hex // "CCCCCC"' "$meta")"
  colorname="$(jq -r '.color_name // ""' "$meta")"; [[ -n "$colorname" ]] || colorname="$(pr_color_name "$colorhex")"
  cap_esc(){ local s="${1//%/%%}"; [[ "$s" == @* ]] && s=" $s"; printf '%s' "$s"; }
  team="$(cap_esc "$team")"; univ="$(cap_esc "$univ")"; login="$(cap_esc "$login")"; colorname="$(cap_esc "$colorname")"; short="$(cap_esc "$short")"
  FB="$(magick -list font 2>/dev/null | awk -F': ' '/Font: DejaVu-Sans-Bold$/{print $2; exit}')"
  [[ -n "$FB" ]] || FB="$(magick -list font 2>/dev/null | awk -F': ' '/Font: /{print $2; exit}')"
  FR="$(magick -list font 2>/dev/null | awk -F': ' '/Font: DejaVu-Sans$/{print $2; exit}')"; [[ -n "$FR" ]] || FR="$FB"

  local -a cov=( magick -size 1240x1754 xc:white )
  addcap(){ cov+=( '(' -size "${1}x${2}" -background white -fill "$5" ); [[ -n "$6" ]] && cov+=( -font "$6" ); [[ -n "$7" ]] && cov+=( -weight "$7" ); cov+=( -gravity "$8" "caption:$9" ')' -gravity northwest -geometry "+${3}+${4}" -composite ); }
  addcap 1080  46  80   66 '#555' "$FR" ''   center "ENTREGA DE BALÃO  /  BALLOON"
  addcap 1080 150  80  120 black  "$FB" 700  center "$team"
  [[ -n "$univ" ]] && addcap 1080 54 80 280 '#333' "$FR" '' center "$univ"
  addcap 1080  40  80  346 '#555' "$FR" ''   center "login"
  addcap 1080  78  80  388 black  "$FB" 700  center "$login"
  cov+=( -fill none -stroke '#999' -strokewidth 2 -draw "line 80,500 1160,500" -stroke none )
  addcap 540  52  80  528 '#555' "$FR" ''   center "PROBLEMA"
  addcap 540 200  80  590 black  "$FB" 800  center "$short"
  addcap 540  52 620  528 '#555' "$FR" ''   center "COR DO BALÃO"
  cov+=( -fill "#$colorhex" -stroke '#333' -strokewidth 2 )
  cov+=( -draw "translate 890,690 ellipse 0,0 78,98 0,360" )
  cov+=( -draw "translate 890,690 polygon -12,96 12,96 0,122" )
  cov+=( -fill none -stroke none )
  addcap 540  72 620  812 black  "$FB" 700  center "$colorname"
  cov+=( -fill none -stroke '#999' -strokewidth 2 -draw "line 80,910 1160,910" -stroke none )
  addcap 1080  54  80  956 '#555' "$FR" ''   center "TAREFA Nº  (confira com o sistema)"
  addcap 1080 200  80 1016 black  "$FB" 800  center "$seq"
  cov+=( -fill none -stroke '#999' -strokewidth 2 -draw "line 80,1300 1160,1300" -stroke none )
  addcap  600  46  80 1500 black  "$FR" ''   west   "Assinatura de quem entregou:"
  cov+=( -fill none -stroke black -strokewidth 2 -draw "line 80,1600 700,1600" -stroke none )
  addcap  320  46 760 1500 black  "$FR" ''   west   "Hora da entrega:"
  cov+=( -fill none -stroke black -strokewidth 2 -draw "line 760,1600 1160,1600" -stroke none )
  cov+=( -units PixelsPerInch -density 150 "$work/balloon.pdf" )
  "${cov[@]}" 2>/dev/null && [[ -s "$work/balloon.pdf" ]] || return 1
  mv -f "$work/balloon.pdf" "$cache"
  jq '.build_ok=true' "$meta" > "$work/m.json" 2>/dev/null && mv -f "$work/m.json" "$meta"
  return 0
}

# pr_build_balloon <c> <id> : ecoa o combined.pdf da folha do balão (build-once; conteúdo imutável).
pr_build_balloon() {
  local c="$1" id="$2" dir meta cache
  dir="$(pr_dir "$c")"; meta="$dir/$id.json"; cache="$dir/$id.combined.pdf"
  [[ -f "$meta" ]] || return 1
  [[ -f "$cache" ]] && { printf '%s' "$cache"; return 0; }
  ( flock -w 30 9 || exit 1
    [[ -f "$cache" ]] && exit 0
    _pr_render_balloon "$c" "$id" "$meta" "$cache" || exit 1
  ) 9>"$dir/$id.lock"
  [[ -f "$cache" ]] && { printf '%s' "$cache"; return 0; }
  return 1
}

# pr_balloon_freeze_gate <c> -> ecoa "<freeze_time> <permitido>" (0 0 = sem freeze / sem gate).
# BALÃO NÃO SE ENTREGA COM O PLACAR CONGELADO: o balão anda pela sala, então entregá-lo durante
# o freeze conta ao público o que o placar está escondendo — o vazamento é FÍSICO, não de rota.
# `BALLOONS_DURING_FREEZE=1` no conf é o opt-in explícito do admin p/ o comportamento clássico.
# O conf é *sourced* em toda parte, mas AQUI não: leitura por sed/grep (é código do autor e isto
# roda dentro de um laço) — mesma receita de metrics_recompute (lib/users.sh).
pr_balloon_freeze_gate() {
  local cf="$CONTESTSDIR/$1/conf" fz allow=0
  fz="$(sed -n 's/^[[:space:]]*FREEZE_TIME=//p' "$cf" 2>/dev/null | tail -1 | tr -cd '0-9')"
  grep -qE '^[[:space:]]*BALLOONS_DURING_FREEZE=1?\b' "$cf" 2>/dev/null && allow=1
  printf '%s %s' "${fz:-0}" "$allow"
}

# pr_reconcile_balloons <c> : gera (preguiçosamente) as tarefas de balão pendentes — 1 por (login,
# problema) na 1ª solução. Idempotente (id determinístico), sob flock, gateado pelo mtime de
# var/.score-dirty (tocado a cada escrita de history — substitui o extinto controle/history).
# Lê o veredicto FINAL do stream — vale p/ auto E manual. Auditado.
#
# FREEZE: AC com `sub_epoch >= FREEZE_TIME` NÃO vira tarefa, e a supressão é REGISTRADA em
# `.balloon-frozen` (JSONL, sob este mesmo flock). A lápide é o que faz o "nunca" ser nunca:
# sem ela, o `finish.sh` zera o FREEZE_TIME no encerrar-evento, o gate desliga e todos os
# suprimidos nasceriam de uma vez — bem na geração do relatório final. Só o admin desfaz, e
# desfaz de propósito (settings: ligar a permissão apaga as lápides e o stamp).
# A chave é o `sub_epoch` da SUBMISSÃO, nunca o instante do veredicto: em MANUAL_VERDICT o
# balão nasce quando os .judge decidem, e um AC enviado ANTES do freeze e julgado DEPOIS
# seria retido por engano. É a mesma semântica do placar (`.ac and .sub_epoch < $freeze`).
pr_reconcile_balloons() {
  local c="$1" dir hist stamp
  staff_exists "$c" || return 0
  dir="$(pr_dir "$c")"; hist="$CONTESTSDIR/$c/var/.score-dirty"
  [[ -e "$hist" ]] || return 0                     # sem submissão desde o cut-over: nada a fazer
  mkdir -p "$dir"; stamp="$dir/.balloon-stamp"
  [[ -f "$stamp" && ! "$hist" -nt "$stamp" ]] && return 0
  ( flock -w 5 9 || exit 0
    [[ -f "$stamp" && ! "$hist" -nt "$stamp" ]] && exit 0
    # o carimbo ANTERIOR vira a referência da varredura incremental; o novo é gravado ANTES de
    # varrer (de propósito: escrita que aconteça DURANTE a varredura fica p/ a próxima, e o
    # filtro -newer do stream a pega, porque o novo carimbo é do instante pré-varredura).
    local prev="$dir/.balloon-prev"
    if [[ -f "$stamp" ]]; then touch -r "$stamp" "$prev"; else rm -f "$prev"; fi
    touch -r "$hist" "$stamp"
    local sub_epoch login cid verdict id short colorhex colorname team univ fullname seq
    local fz allow held _l
    # caches: sem eles o laço refazia POR LINHA o que só depende do problema (letra/cor) ou do
    # time (nome/universidade) — 9 forks por balão. Com eles são 12 problemas e N times, uma vez.
    declare -A C_SHORT=() C_HEX=() C_NAME=() C_TEAM=() C_UNIV=() C_FULL=()
    read -r fz allow < <(pr_balloon_freeze_gate "$c")
    declare -A FROZEN=()                           # lápides já registradas (id -> 1)
    held="$dir/.balloon-frozen"
    [[ -f "$held" ]] && while IFS= read -r _l; do
      _l="${_l#*\"id\":\"}"; _l="${_l%%\"*}"; [[ -n "$_l" ]] && FROZEN[$_l]=1
    done < "$held"
    # O sub_epoch é o campo NF-1 e o veredicto PODE conter ':' (5 linhas em produção) — por isso
    # o awk, e não um `read` posicional. emit_history_sorted ordena por sub_epoch, então o `seq`
    # do lote sai cronológico. Veredicto por ÚLTIMO no TSV: no modo heurístico ele contém TAB.
    while IFS=$'\t' read -r sub_epoch login cid verdict; do
      [[ -n "$login" && -n "$cid" ]] || continue
      sub_epoch="${sub_epoch//[^0-9]/}"; sub_epoch="${sub_epoch:-0}"   # nunca deixe (( )) ver lixo
      case "$verdict" in *Accepted*) ;; *) continue;; esac
      case "$verdict" in *" (Ignored)") continue;; esac   # ignorada não conta no placar nem ganha balão
      case "$login" in *.admin|*.judge|*.cjudge|*.staff|*.cstaff|*.mon|*.animeitor) continue;; esac
      id="bln$(printf '%s%s%s' "$c" "$login" "$cid" | md5sum | cut -c1-20)"
      [[ -f "$dir/$id.json" ]] && continue
      [[ -n "${FROZEN[$id]:-}" ]] && continue
      if [[ -z "${C_SHORT[$cid]+x}" ]]; then
        C_SHORT[$cid]="$(pr_short_of "$c" "$cid")"; [[ -n "${C_SHORT[$cid]}" ]] || C_SHORT[$cid]="?"
        C_HEX[$cid]="$(pr_balloon_color "$c" "${C_SHORT[$cid]}")"
        C_NAME[$cid]="$(pr_color_name "${C_HEX[$cid]}")"
      fi
      short="${C_SHORT[$cid]}"
      if (( fz > 0 )) && [[ "$allow" != 1 ]] && (( ${sub_epoch:-0} >= fz )); then
        jq -cn --arg id "$id" --arg login "$login" --arg prob "$cid" --arg short "$short" \
          --argjson se "${sub_epoch:-0}" --argjson fz "$fz" --argjson at "$EPOCHSECONDS" \
          '{id:$id, login:$login, problem:$prob, short:$short, sub_epoch:$se,
            freeze_time:$fz, at:$at}' >> "$held"
        FROZEN[$id]=1
        audit_log_to "$c" balloon-frozen "login=$login problema=$short sub_epoch=$sub_epoch freeze=$fz"
        continue
      fi
      colorhex="${C_HEX[$cid]}"; colorname="${C_NAME[$cid]}"
      if [[ -z "${C_TEAM[$login]+x}" ]]; then
        C_TEAM[$login]="$(pr_resolve_team "$c" "$login")"
        C_UNIV[$login]="$(pr_resolve_univ "$c" "$login")"
        C_FULL[$login]="$(user_fullname "$c" "$login")"; [[ -n "${C_FULL[$login]}" ]] || C_FULL[$login]="$login"
      fi
      team="${C_TEAM[$login]}"; univ="${C_UNIV[$login]}"; fullname="${C_FULL[$login]}"
      seq="$(pr_next_seq "$c")"
      jq -cn --arg id "$id" --argjson seq "$seq" --arg login "$login" --arg fn "$fullname" \
        --arg team "$team" --arg univ "$univ" --arg prob "$cid" --arg short "$short" \
        --arg ch "$colorhex" --arg cn "$colorname" --argjson time "$EPOCHSECONDS" \
        '{id:$id, seq:$seq, kind:"balloon", login:$login, fullname:$fn, team:$team, univ:$univ,
          problem:$prob, short:$short, color_hex:$ch, color_name:$cn, time:$time, status:"pending",
          claimed_by:"", claimed_at:0, processed_by:"", processed_at:0, delivered_by:"", delivered_at:0}' \
        > "$dir/$id.json.tmp" && mv -f "$dir/$id.json.tmp" "$dir/$id.json"
      audit_log_to "$c" balloon-task "seq=$seq login=$login problema=$short cor=$colorname"
    done < <(emit_history_stream_since "$c" "$prev" \
               | awk -F: 'NF>=7{ v=$5; for(i=6;i<=NF-2;i++) v=v ":" $i;
                                 print $(NF-1) "\t" $2 "\t" $3 "\t" v }' \
               | sort -n -k1,1)
  ) 9>"$dir/.balloon.lock"
}

# pr_balloons_frozen_count <c> — quantos balões a regra do freeze suprimiu (0 se nenhum).
pr_balloons_frozen_count() {
  local f; f="$(pr_dir "$1")/.balloon-frozen"
  [[ -f "$f" ]] || { printf '0'; return 0; }
  local n; n="$(grep -c '"id"' "$f" 2>/dev/null)"; printf '%s' "${n//[^0-9]/}"
}

# pr_balloons_release_frozen <c> <by> — o admin ligou a entrega durante o freeze: apaga as
# lápides e o stamp p/ o próximo reconcile materializar TUDO que estava retido (o id é
# determinístico, então re-executar não duplica). Ecoa quantos foram liberados.
pr_balloons_release_frozen() {
  local c="$1" by="$2" dir n
  dir="$(pr_dir "$c")"; n="$(pr_balloons_frozen_count "$c")"
  (( ${n:-0} > 0 )) || { printf '0'; return 0; }
  ( flock -w 5 9 || exit 0
    rm -f "$dir/.balloon-frozen" "$dir/.balloon-stamp"
  ) 9>"$dir/.balloon.lock"
  audit_log_to "$c" balloon-freeze-release "liberados=$n by=$by"
  printf '%s' "$n"
}
