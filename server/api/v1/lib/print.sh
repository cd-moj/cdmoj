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

# existe ao menos um usuário .staff habilitado (passwd próprio + fonte compartilhada)?
staff_exists() {
  local c="$1" f s
  for f in "$CONTESTSDIR/$c/passwd"; do
    [[ -f "$f" ]] && awk -F: '($1 ~ /\.staff$/)&&(substr($2,1,1)!="!"){found=1} END{exit found?0:1}' "$f" && return 0
  done
  s="$(_users_source "$c")"
  [[ "$s" != "$c" && -f "$CONTESTSDIR/$s/passwd" ]] \
    && awk -F: '($1 ~ /\.staff$/)&&(substr($2,1,1)!="!"){found=1} END{exit found?0:1}' "$CONTESTSDIR/$s/passwd" && return 0
  return 1
}

# impressão habilitada pelo admin? (conf PRINT=0 desliga; default ligado)
print_enabled() {
  [[ "$( . "$CONTESTSDIR/$1/conf" 2>/dev/null; printf '%s' "${PRINT:-}")" != 0 ]]
}

# logins .staff (únicos), um por linha: "login\tfullname\tdisabled(true|false)"
pr_staff_logins() {
  local c="$1" s
  { cat "$CONTESTSDIR/$c/passwd" 2>/dev/null
    s="$(_users_source "$c")"; [[ "$s" != "$c" ]] && cat "$CONTESTSDIR/$s/passwd" 2>/dev/null
  } | awk -F: '$1 ~ /\.staff$/ { if (seen[$1]++) next;
        dis=(substr($2,1,1)=="!")?"true":"false"; printf "%s\t%s\t%s\n",$1,$3,dis }'
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

# --- resolução do NOME do time/participante (folha de rosto) ---------------
# Nunca devolve a sigla da universidade — essa vai em pr_resolve_univ. Ordem:
# 1) controle/teams (login:flag:univshort:teamname:univfull) -> teamname (campo 4)
# 2) passwd campo 7 (login:pass:fullname:email:flag:univshort:team:univfull)
# 3) fullname do passwd (campo 3) — em treino individual, é o nome do participante
pr_resolve_team() {  # <c> <login>
  local c="$1" login="$2" tn=""
  local d="$CONTESTSDIR/$c"
  [[ -f "$d/controle/teams" ]] && tn="$(awk -F: -v u="$login" '$1==u{print $4; exit}' "$d/controle/teams")"
  [[ -z "$tn" ]] && tn="$(awk -F: -v u="$login" '$1==u{print $7; exit}' "$d/passwd" 2>/dev/null)"
  [[ -z "$tn" ]] && tn="$(user_fullname "$c" "$login")"
  printf '%s' "$tn"
}

# --- resolução da UNIVERSIDADE/escola (folha de rosto, secundária) ----------
# Preferindo o nome completo; pode ser vazia. Ordem:
# 1) controle/teams: univfull (campo 5) -> univshort (campo 3)
# 2) passwd: univfull (campo 8) -> univshort (campo 6)
# 3) teams-meta.json: school_full -> school (1ª regra cujo regex casa o login)
pr_resolve_univ() {  # <c> <login>
  local c="$1" login="$2" un=""
  local d="$CONTESTSDIR/$c"
  if [[ -f "$d/controle/teams" ]]; then
    un="$(awk -F: -v u="$login" '$1==u{print $5; exit}' "$d/controle/teams")"
    [[ -z "$un" ]] && un="$(awk -F: -v u="$login" '$1==u{print $3; exit}' "$d/controle/teams")"
  fi
  [[ -z "$un" ]] && un="$(awk -F: -v u="$login" '$1==u{print $8; exit}' "$d/passwd" 2>/dev/null)"
  [[ -z "$un" ]] && un="$(awk -F: -v u="$login" '$1==u{print $6; exit}' "$d/passwd" 2>/dev/null)"
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
