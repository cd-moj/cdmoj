# lib/print.sh — pedidos de impressão (.staff) do modo contest.
# Sourced pelos handlers contest/print*, contest/staff/* e contest/admin/staff-filters.sh
# (o router já carregou common.sh/auth.sh, então valid_id/is_admin/is_staff/audit_log_to/
# user_fullname/_users_source estão disponíveis).
#
# Modelo de dados em contests/<c>/print-requests/:
#   .seq/.seqlock        contador monotônico + flock
#   <id>.json            metadados/estado (pending|printed|delivered)
#   <id>.src             arquivo cru enviado pelo aluno
#   <id>.combined.pdf    cache: folha de rosto + documento normalizado
#   <id>.lock            flock de build + transições de estado
#   staff-filters.json   { "<staff_login>": [regex,...] }  (vazio/ausente = vê tudo)

# --- localização / flags --------------------------------------------------
pr_dir() { printf '%s' "$CONTESTSDIR/$1/print-requests"; }

# _pr_staff_accounts <usersdir> — TSV "login\tfullname\tdisabled" dos .staff do dir.
_pr_staff_accounts() {
  local d="$1" af
  ( set +o noglob 2>/dev/null; shopt -s nullglob
    for af in "$d"/*.staff/account.json; do
      jq -r '[.login//"", .fullname//"",
              (if ((.password//"")|startswith("!")) then "true" else "false" end)] | @tsv' \
        "$af" 2>/dev/null
    done )
}

# existe ao menos um usuário .staff habilitado (store próprio + fonte compartilhada)?
staff_exists() {
  local c="$1" s
  _pr_staff_accounts "$CONTESTSDIR/$c/users" | awk -F'\t' '$3=="false"{found=1} END{exit found?0:1}' && return 0
  s="$(_users_source "$c")"
  [[ "$s" != "$c" ]] \
    && _pr_staff_accounts "$CONTESTSDIR/$s/users" | awk -F'\t' '$3=="false"{found=1} END{exit found?0:1}' && return 0
  return 1
}

# impressão habilitada pelo admin? (conf PRINT=0 desliga; default ligado)
print_enabled() {
  [[ "$( . "$CONTESTSDIR/$1/conf" 2>/dev/null; printf '%s' "${PRINT:-}")" != 0 ]]
}

# logins .staff (únicos), um por linha: "login\tfullname\tdisabled(true|false)"
pr_staff_logins() {
  local c="$1" s
  { _pr_staff_accounts "$CONTESTSDIR/$c/users"
    s="$(_users_source "$c")"; [[ "$s" != "$c" ]] && _pr_staff_accounts "$CONTESTSDIR/$s/users"
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

# --- escopo: este staff pode ver as tarefas deste aluno? ------------------
# admin vê tudo; lista de regex vazia/ausente = vê tudo; senão casa por regex (i).
staff_can_see() {  # <c> <staff_login> <student_login>
  local c="$1" staff="$2" who="$3" f
  is_admin && return 0
  f="$(pr_dir "$c")/staff-filters.json"
  [[ -f "$f" ]] || return 0
  jq -e --arg w "$who" --arg s "$staff" '
    ($w|ascii_downcase) as $wl
    | (.[$s] // [])
    | if length==0 then true else any(.[]; . as $r | ($wl|test($r;"i"))) end
  ' "$f" >/dev/null 2>&1
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

# pr_reconcile_balloons <c> : gera (preguiçosamente) as tarefas de balão pendentes — 1 por (login,
# problema) na 1ª solução. Idempotente (id determinístico), sob flock, gateado pelo mtime de
# var/.score-dirty (tocado a cada escrita de history — substitui o extinto controle/history).
# Lê o veredicto FINAL do stream (campo-5 ~ Accepted) — vale p/ auto E manual. Auditado.
pr_reconcile_balloons() {
  local c="$1" dir hist stamp
  staff_exists "$c" || return 0
  dir="$(pr_dir "$c")"; hist="$CONTESTSDIR/$c/var/.score-dirty"
  [[ -e "$hist" ]] || return 0                     # sem submissão desde o cut-over: nada a fazer
  mkdir -p "$dir"; stamp="$dir/.balloon-stamp"
  [[ -f "$stamp" && ! "$hist" -nt "$stamp" ]] && return 0
  ( flock -w 5 9 || exit 0
    [[ -f "$stamp" && ! "$hist" -nt "$stamp" ]] && exit 0
    touch -r "$hist" "$stamp"                      # carimba o mtime do marcador ANTES de varrer
    local _t login cid _lang verdict id short colorhex colorname team univ fullname seq
    while IFS=: read -r _t login cid _lang verdict _rest; do
      [[ -n "$login" && -n "$cid" ]] || continue
      case "$verdict" in *Accepted*) ;; *) continue;; esac
      case "$login" in *.admin|*.judge|*.cjudge|*.staff|*.mon) continue;; esac
      id="bln$(printf '%s%s%s' "$c" "$login" "$cid" | md5sum | cut -c1-20)"
      [[ -f "$dir/$id.json" ]] && continue
      short="$(pr_short_of "$c" "$cid")"; [[ -n "$short" ]] || short="?"
      colorhex="$(pr_balloon_color "$c" "$short")"; colorname="$(pr_color_name "$colorhex")"
      team="$(pr_resolve_team "$c" "$login")"; univ="$(pr_resolve_univ "$c" "$login")"
      fullname="$(user_fullname "$c" "$login")"; [[ -n "$fullname" ]] || fullname="$login"
      seq="$(pr_next_seq "$c")"
      jq -cn --arg id "$id" --argjson seq "$seq" --arg login "$login" --arg fn "$fullname" \
        --arg team "$team" --arg univ "$univ" --arg prob "$cid" --arg short "$short" \
        --arg ch "$colorhex" --arg cn "$colorname" --argjson time "$EPOCHSECONDS" \
        '{id:$id, seq:$seq, kind:"balloon", login:$login, fullname:$fn, team:$team, univ:$univ,
          problem:$prob, short:$short, color_hex:$ch, color_name:$cn, time:$time, status:"pending",
          claimed_by:"", claimed_at:0, processed_by:"", processed_at:0, delivered_by:"", delivered_at:0}' \
        > "$dir/$id.json.tmp" && mv -f "$dir/$id.json.tmp" "$dir/$id.json"
      audit_log_to "$c" balloon-task "seq=$seq login=$login problema=$short cor=$colorname"
    done < <(emit_history_stream "$c")
  ) 9>"$dir/.balloon.lock"
}
