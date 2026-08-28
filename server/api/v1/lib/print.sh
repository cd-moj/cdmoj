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
# do dir cujo login casa o glob (*.staff | *.cstaff).
#
# ⚠ UMA varredura (`find|xargs jq`), NUNCA um jq por conta. A versão anterior era um glob com
# `jq` DENTRO do laço — no mdp-teste-2026 (275 `.staff` + 275 `.cstaff`) isso eram 275 forks só
# no `staff_exists`, que roda em TODA chamada de `/contest/staff/queue`, `/contest/print` e do
# reconcile de balões. Foi a causa dominante do load da manhã de 25/08/2026: a fila a
# **1,26 s/req** (40% de TODO o rt do nginx), que no sábado, com 550 staff polando, saturaria os
# 32 workers do fcgiwrap e derrubaria a API inteira. Medido: 0,95 s → **0,079 s** (12×).
# Quarta instância da classe fork-por-arquivo (index/status, admin/judges, sc_cells…).
# O `sort -z` preserva a ordem alfabética que o glob dava (as listagens de staff/etiquetas
# saem ordenadas por login, como sempre saíram).
_pr_role_accounts() {
  local d="$1" pat="$2"
  [[ -d "$d" ]] || return 0
  find "$d" -mindepth 2 -maxdepth 2 -path "$d/$pat/account.json" -print0 2>/dev/null \
    | sort -z \
    | xargs -0 -r jq -r '[.login//"", .fullname//"",
        (if ((.password//"")|startswith("!")) then "true" else "false" end)] | @tsv' 2>/dev/null
}

# existe ao menos um usuário .staff habilitado (store próprio + fonte compartilhada)?
# SÓ *.staff conta: .cstaff não opera a fila — sem staff de verdade não há impressão p/ aluno.
#
# CACHEADO (`.staff-exists`, receita resp_cache da casa): roda no caminho MAIS polado do dia (a
# fila do staff) e a resposta só muda quando conta de papel nasce/morre. Validade = os `users/`
# como entrada (`-nt`, builtin — criar/remover conta muda o mtime do dir) + teto de 120 s p/ o
# que não mexe no dir (disable edita o account.json NO LUGAR: some do cache em até 2 min, e a
# consequência é só a fila aceitar pedido por esse intervalo). Escrita atômica (tmp+mv): vários
# workers concorrem aqui.
staff_exists() {
  local c="$1" s v rc cf="$CONTESTSDIR/$1/print-requests/.staff-exists"
  s="$(_users_source "$c")"
  if [[ -f "$cf" && ! "$CONTESTSDIR/$c/users" -nt "$cf" ]] \
     && { [[ "$s" == "$c" ]] || [[ ! "$CONTESTSDIR/$s/users" -nt "$cf" ]]; } \
     && [[ -n "$(find "$cf" -newermt '-120 seconds' 2>/dev/null)" ]]; then
    read -r v < "$cf" 2>/dev/null || v=""
    [[ "$v" == 1 ]] && return 0
    [[ "$v" == 0 ]] && return 1
  fi
  rc=1
  if _pr_role_accounts "$CONTESTSDIR/$c/users" '*.staff' | awk -F'\t' '$3=="false"{found=1} END{exit found?0:1}'; then
    rc=0
  elif [[ "$s" != "$c" ]] \
    && _pr_role_accounts "$CONTESTSDIR/$s/users" '*.staff' | awk -F'\t' '$3=="false"{found=1} END{exit found?0:1}'; then
    rc=0
  fi
  mkdir -p "${cf%/*}" 2>/dev/null
  printf '%s\n' "$(( 1 - rc ))" > "$cf.tmp.${BASHPID}" 2>/dev/null && mv -f "$cf.tmp.${BASHPID}" "$cf" 2>/dev/null \
    || rm -f "$cf.tmp.${BASHPID}" 2>/dev/null
  return $rc
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
#
# CACHEADO por (contest, staff): a passada única ainda lê ~3.500 account.json (0,27 s medido) e
# roda em TODA chamada da fila/impressão/reveal de quem tem escopo — com 550 staff polando no
# sábado seriam ~10 req/s só disto. Validade: `staff-filters.json` como ENTRADA (`-nt` —
# editar o escopo no painel vale na hora) + teto de 300 s p/ o que não é arquivo daqui (o
# `.team.region` de uma conta muda sem tocar o filters; sede é configuração de véspera, 5 min
# de atraso não machuca). A VARIANTE é o login (regra da casa: vira nome de arquivo) —
# caractere fora do padrão = não cacheia, nunca "saneia por remoção".
staff_visible_logins() {
  local c="$1" who="$2" f n src loc rc cf=""
  f="$(pr_dir "$c")/staff-filters.json"
  { [[ -f "$f" ]] && jq -e . "$f" >/dev/null 2>&1; } || return 1
  n="$(jq -r --arg s "$who" '(.[$s] // []) | length' "$f" 2>/dev/null)"
  n="${n//[^0-9]/}"; [[ -n "$n" && "$n" -gt 0 ]] || return 1
  if [[ "$who" =~ ^[A-Za-z0-9._-]+$ && "$who" != *..* ]]; then
    cf="$(pr_dir "$c")/.scope-cache/$who"
    if [[ -f "$cf" && ! "$f" -nt "$cf" ]] \
       && [[ -n "$(find "$cf" -newermt '-300 seconds' 2>/dev/null)" ]]; then
      cat "$cf"; return 0
    fi
  fi
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
      | .[].login' 2>/dev/null > "$loc.out"
  rc=$?
  if (( rc == 0 )); then
    # publica no cache (atômico — vários workers concorrem) e ecoa. Lista VAZIA também é
    # resultado válido e cacheável: escopo que não casa ninguém = vê NADA (regra de quem manda
    # é o rc, documentada no CLAUDE.md) — não confundir com o rc=1 lá de cima.
    if [[ -n "$cf" ]]; then
      mkdir -p "${cf%/*}" 2>/dev/null
      cp -f "$loc.out" "$cf.tmp.${BASHPID}" 2>/dev/null && mv -f "$cf.tmp.${BASHPID}" "$cf" 2>/dev/null \
        || rm -f "$cf.tmp.${BASHPID}" 2>/dev/null
    fi
    cat "$loc.out"
  fi
  rm -f "$loc" "$loc.out"; return "$rc"
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

# --- TEXTO -> PDF: o caminho que a sala mais usa (código-fonte) ------------------------------
# _pr_text2pdf <src> <out.pdf> <nome-visível> <workdir> <arquivo-de-erro> -> 0/1
#
# Três coisas, e cada uma existe por causa de um incidente:
#
# 1. **iconv p/ UTF-8.** O paps só lê UTF-8 e ABORTA em byte inválido ("Error while converting
#    input from 'UTF-8' to UTF-8"). Um `.cpp` salvo no Dev-C++/Windows vem em CP1252, e um
#    `// solução` no comentário basta para o time não receber o papel. `-c` descarta o que não
#    converter: perder um acento é melhor que perder a impressão inteira.
# 2. **`nl -ba` numera TODAS as linhas** (inclusive as em branco): quem lê código no papel
#    aponta para o número.
# 3. **paps -> PostScript -> ps2pdf.** ⚠ NADA de `--format=pdf`: a imagem tem **paps 0.6.8**,
#    que não conhece a opção e morre com "Command line error: Unknown option --format=pdf" —
#    e o `2>/dev/null` engolia a mensagem. No DEV o paps é 0.8 e aceita, e foi assim que isto
#    passou pela revisão e chegou à sala em dia de prova (mesma família do jq 1.7 × 1.8: o dev
#    aceita, a imagem recusa). PostScript é o denominador comum de todas as versões.
#
# IDENTIFICAÇÃO EM TODA PÁGINA, em dois lugares porque um só não coube:
#   topo    (paps `--header`)  <data>   <nome-do-arquivo>   Page N
#   rodapé  (selo do qpdf)     <login do time> - <arquivo> - tarefa #N
# Com trinta folhas empilhadas na mesa, e uma delas se soltando da folha de rosto, é isso que
# diz de quem é o papel.
_pr_text2pdf() {  # <src> <out.pdf> <nome-do-arquivo> <rodapé> <workdir> [<err>]
  local src="$1" out="$2" name="$3" foot="$4" work="$5" err="${6:-/dev/null}" enc fr
  # o `--header` do paps imprime O NOME DO ARQUIVO que ele recebeu (não há opção de título
  # nesta versão), então o nome do arquivo numerado é o que aparece no alto de cada página.
  # ⚠ CURTO: a data que o paps escreve à esquerda come metade da linha, a fonte do cabeçalho é
  # FIXA (não acompanha o `--font`) e um título de mais de ~14 caracteres SOBREPÕE a data —
  # medido. Por isso o login do time não cabe aqui: ele vai no rodapé, logo abaixo.
  name="$(basename -- "${name:-arquivo}" | tr -cd 'A-Za-z0-9._-')"; [[ -n "$name" ]] || name=arquivo
  enc="$(file -b --mime-encoding "$src" 2>/dev/null)"
  { case "$enc" in
      utf-8|us-ascii|'') cat "$src" ;;
      *) iconv -c -f "$enc" -t UTF-8 "$src" 2>>"$err" || cat "$src" ;;
    esac
  } | nl -ba -w3 -s' | ' > "$work/$name" 2>>"$err"
  [[ -s "$work/$name" ]] || return 1
  ( cd "$work" && paps --header --paper=a4 --font='Monospace 11' -- "$name" 2>>"$err" ) \
    | ps2pdf - "$out" 2>>"$err"
  [[ -s "$out" ]] || return 1

  # O RODAPÉ é um SELO: uma página A4 TRANSPARENTE (`xc:none`) que o `qpdf --overlay --repeat=1`
  # carimba em TODAS as páginas — o `--repeat` é o ponto, senão só a primeira folha sairia
  # identificada. O selo entra no PDF uma única vez (as páginas referenciam o mesmo XObject),
  # então o custo não cresce com o tamanho da listagem.
  # ⚠ o texto do `-annotate` é INTERPRETADO pelo ImageMagick: `%` é escape de propriedade e
  # `@arquivo` manda LER o arquivo. O nome do arquivo vem do time — saneie antes de anotar.
  # Se magick ou qpdf falharem, fica o PDF sem rodapé: o papel sai correto, só menos
  # identificado — nunca deixar de imprimir por causa do carimbo.
  foot="$(printf '%s' "$foot" | tr -cd 'A-Za-z0-9._ #-' | tr -s ' ' | cut -c1-120)"
  [[ -n "$foot" ]] || return 0
  fr="$(magick -list font 2>/dev/null | awk -F': ' '/Font: DejaVu-Sans$/{print $2; exit}')"
  [[ -n "$fr" ]] || fr="$(magick -list font 2>/dev/null | awk -F': ' '/Font: /{print $2; exit}')"
  local -a st=( magick -size 1240x1754 xc:none -gravity south -pointsize 26 -fill '#333' )
  [[ -n "$fr" ]] && st+=( -font "$fr" )
  st+=( -annotate +0+40 "$foot" -units PixelsPerInch -density 150 "$work/stamp.pdf" )
  "${st[@]}" 2>>"$err" && [[ -s "$work/stamp.pdf" ]] \
    && qpdf "$out" --overlay "$work/stamp.pdf" --repeat=1 -- "$work/stamped.pdf" 2>>"$err" \
    && [[ -s "$work/stamped.pdf" ]] && mv -f "$work/stamped.pdf" "$out"
  [[ -s "$out" ]]
}

# --- render interno: produz <id>.combined.pdf (chamado SOB flock) ---------
# Persiste pages/build_ok no meta. Folha de rosto (capa) sempre é a página 1.
_pr_render() {  # <c> <id> <src> <meta> <cache>
  local c="$1" id="$2" src="$3" meta="$4" cache="$5"
  local work; work="$(mktemp -d)" || return 1
  trap 'rm -rf "$work"' RETURN
  local doc="$work/doc.pdf" docok=0 mime enc fn ext inp errf foot lg sq
  # o stderr das conversões vai para <id>.err quando algo falha — antes ia todo p/ /dev/null,
  # e a única pista de um pedido que não converteu era o "ATENÇÃO" impresso na capa
  errf="${meta%.json}.err"; : > "$errf"
  fn="$(jq -r '.filename // "arquivo"' "$meta" 2>/dev/null)"
  # rodapé das páginas de código: LOGIN do time + arquivo + nº da tarefa (ver _pr_text2pdf).
  # É o que identifica a folha que se separou da capa na mesa da sala.
  lg="$(jq -r '.login // ""' "$meta" 2>/dev/null)"
  sq="$(jq -r '.seq // 0' "$meta" 2>/dev/null)"
  foot="$(printf '%s  -  %s  -  tarefa #%s' "${lg:-?}" "$fn" "${sq:-0}" | tr -d '\n')"

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
      # o caso mais comum da sala: .c .cpp .py .java .kt .txt — ver _pr_text2pdf
      _pr_text2pdf "$src" "$doc" "$fn" "$foot" "$work" "$errf" && docok=1 ;;
    *)
      enc="$(file -b --mime-encoding "$src" 2>/dev/null)"
      if [[ "$enc" != binary ]]; then
        _pr_text2pdf "$src" "$doc" "$fn" "$foot" "$work" "$errf" && docok=1
      else
        # office/desconhecido: dá uma extensão real ao input p/ o soffice reconhecer e
        # prever o nome de saída (sem depender de glob, já que common.sh usa noglob).
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
  # deu certo: o log de erro não serve mais (e não vira lixo permanente no print-requests/)
  (( docok )) && rm -f "$errf"
  [[ -s "$errf" ]] || rm -f "$errf"

  (( built ))
}

# pr_build_pdf <c> <id>  -> ecoa o caminho do combined.pdf (cache); rc!=0 em falha total.
# Build-once: o <id>.src é imutável após o upload, então o cache vale para sempre.
#
# ⚠ ...desde que o build tenha DADO CERTO. Quando a conversão do documento falha, o
# _pr_render publica a CAPA SOZINHA no mesmo cache — e a condição `-nt` não distingue as duas
# coisas: o pedido ficaria imprimindo só a folha de rosto para sempre, mesmo depois de o
# conserto entrar no ar (foi o caso do paps 0.6.8, agosto/2026). Por isso o `build_ok` do meta
# faz parte da validade do cache. Meta antigo, sem o campo, conta como bom — não se refaz a
# base inteira por causa disto.
# E o DEPLOY também invalida: esta lib entra como entrada do cache (`${BASH_SOURCE[0]}`, a
# receita do `resp_cache_fresh` p/ o que não é arquivo de dado). Mudou o desenho do papel —
# rodapé com o login, numeração, capa — e o pedido antigo se refaz sozinho na próxima
# impressão, sem ninguém apagar `.combined.pdf` à mão. Custo: um rebuild por pedido depois de
# um deploy que MEXA nesta lib; impressão é ritmo humano, isso não pesa.
_pr_cache_ok() {  # <cache> <src> <meta>
  [[ -f "$1" && "$1" -nt "$2" && "$1" -nt "${BASH_SOURCE[0]}" ]] || return 1
  # ⚠ `.build_ok // true` NÃO serve: o `//` do jq trata **false como vazio** e devolveria
  # `true` justamente no caso que interessa (ver a armadilha do `//` no CLAUDE.md). O teste
  # de booleano é por igualdade explícita.
  ! jq -e '.build_ok == false' "$3" >/dev/null 2>&1
}

# _pr_render_slot <cmd...> — SEMÁFORO das renderizações de PDF. magick/paps custam SEGUNDOS de
# CPU por folha e são disparados por demanda (busca de PDF frio na fila do staff): numa onda de
# balões — 500 ACs no problema fácil da abertura — cada fetch vira um render e a máquina afunda
# em dezenas de magick simultâneos (medido no teste de 28/08: magick a 3200% de CPU, 60% do
# tempo em sys, API inteira degradada). O teto é PR_RENDER_SLOTS vagas via flock: tenta todas
# sem bloquear; cheias, espera até 60 s na vaga sorteada pelo BASHPID — fila educada em vez do
# 31º magick. Timeout = falha (o chamador já trata render que falha; o cliente tenta de novo).
# Sem ciclo com os locks por-tarefa: quem segura vaga nunca pega outro <id>.lock.
PR_RENDER_SLOTS="${PR_RENDER_SLOTS:-6}"
_pr_render_slot() {
  # ${RUNDIR:-}: esta lib também é sourceada STANDALONE sob set -u (smokes, report-gen)
  local d="${RUNDIR:-/tmp}/locks" i rc fd slot
  mkdir -p "$d" 2>/dev/null
  for ((i=0; i<PR_RENDER_SLOTS; i++)); do
    exec {fd}>"$d/render-$i.lock" || continue
    if flock -n "$fd"; then "$@"; rc=$?; exec {fd}>&-; return "$rc"; fi
    exec {fd}>&-
  done
  slot=$(( BASHPID % PR_RENDER_SLOTS ))
  exec {fd}>"$d/render-$slot.lock" || { "$@"; return $?; }
  if flock -w 60 "$fd"; then "$@"; rc=$?; exec {fd}>&-; return "$rc"; fi
  exec {fd}>&-; return 1
}
pr_build_pdf() {
  local c="$1" id="$2" dir src meta cache
  dir="$(pr_dir "$c")"; src="$dir/$id.src"; meta="$dir/$id.json"; cache="$dir/$id.combined.pdf"
  [[ -f "$src" && -f "$meta" ]] || return 1
  if _pr_cache_ok "$cache" "$src" "$meta"; then printf '%s' "$cache"; return 0; fi
  ( flock -w 30 9 || exit 1
    _pr_cache_ok "$cache" "$src" "$meta" && exit 0          # double-check após o lock
    _pr_render_slot _pr_render "$c" "$id" "$src" "$meta" "$cache" || exit 1
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
  # PRIMEIRO DA SEDE: faixa entre a linha e a assinatura (o espaço livre da folha). Só aparece
  # quando o campo foi DECIDIDO como true — ver pr_reconcile_balloons; a tarefa espera até haver
  # certeza justamente porque este papel é impresso segundos depois e não se desanuncia.
  # ⚠ A ESTRELA É DESENHADA, não escrita: `★` (U+2605) não existe em toda fonte — no dev ele sai
  # como NADA (testado), e a folha é gerada onde estiver. Polígono é a mesma técnica do balão
  # logo acima, e não depende de glifo nenhum.
  # ⚠ O `addcap` compõe um tile de fundo BRANCO, então a faixa é branca com borda forte: fundo
  # colorido seria coberto pelo tile do texto.
  if [[ "$(jq -r '.first_site == true' "$meta" 2>/dev/null)" == true ]]; then
    cov+=( -fill white -stroke '#B8860B' -strokewidth 4 -draw "roundrectangle 80,1330 1160,1452 14,14" )
    cov+=( -fill '#B8860B' -stroke '#7A5C00' -strokewidth 1
           -draw "translate 168,1391 polygon 0.0,-26.0 6.2,-8.5 24.7,-8.0 10.0,3.2 15.3,21.0 0.0,10.5 -15.3,21.0 -10.0,3.2 -24.7,-8.0 -6.2,-8.5" )
    cov+=( -fill none -stroke none )
    addcap 880 56 220 1344 '#7A5C00' "$FB" 800 west "PRIMEIRO DA SEDE"
    addcap 880 32 220 1406 '#7A5C00' "$FR" ''  west "first to solve at this site"
  fi
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
    _pr_render_slot _pr_render_balloon "$c" "$id" "$meta" "$cache" || exit 1
  ) 9>"$dir/$id.lock"
  [[ -f "$cache" ]] && { printf '%s' "$cache"; return 0; }
  return 1
}

# pr_site_first_map <c> — TSV `<sede>\t<probid>\t<menor_ac_epoch>\t<login_do_ac>\t<menor_pendente>`
# (0 onde não há). É o que decide "este balão é o PRIMEIRO daquela cor NA SEDE".
#
# UMA VARREDURA, no molde do staff_visible_logins: `find|xargs jq` sobre os account.json (a sede
# vem de `.team.region`) e sobre os metrics.json (`first_ac_epoch` e `pending_min_epoch`, o campo
# que o placar também usa p/ só pintar a estrela com certeza). Nada de um jq por conta — num
# contest de 2.355 contas isso seriam 4.710 forks.
#
# VISÃO CHEIA de propósito (nunca a `frozen`): o balão é suprimido durante o freeze por outra
# regra (pr_balloon_freeze_gate), e a pergunta aqui é sobre o AC de verdade.
# O `min_by([epoch, login])` dá o DESEMPATE determinístico quando dois times da mesma sede têm o
# mesmo epoch — sem ele sairiam duas estrelas para o mesmo problema na mesma sede.
pr_site_first_map() {
  local c="$1" d
  d="$CONTESTSDIR/$c/users"; [[ -d "$d" ]] || return 0
  { find "$d" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
      | xargs -0 -r jq -c '{k:"r",
          login:(if (.login//"") == "" then (input_filename|split("/")|.[-2]) else .login end),
          region:(.team.region // "")}' 2>/dev/null
    find "$d" -mindepth 2 -maxdepth 2 -name metrics.json -print0 2>/dev/null \
      | xargs -0 -r jq -c '(input_filename|split("/")|.[-2]) as $l
          | (.by_problem // {}) | to_entries[]
          | {k:"m", login:$l, prob:.key,
             fac:(.value.first_ac_epoch // 0),
             pmin:(if (.value|has("pending_min_epoch"))
                   then (.value.pending_min_epoch // 0) else -1 end)}' 2>/dev/null
    true
  } | jq -rs '
      def isrole: test("\\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$");
      (map(select(.k == "r")) | map(select((.login|isrole)|not) | select(.region != ""))) as $R
      | ($R | map({(.login): .region}) | add // {}) as $REG
      | (map(select(.k == "m"))
         # contas de PAPEL não ganham balão nem roubam o primeiro lugar (lista do reconciliador)
         | map(select((.login|isrole)|not))
         | map(. + {region: ($REG[.login] // "")}) | map(select(.region != ""))
         | group_by([.region, .prob])
         | map( (map(select(.fac > 0))) as $acs
              | (map(select(.pmin != 0))) as $pends
              | [ "S", .[0].region, .[0].prob,
                  (if ($acs|length) == 0 then 0 else ($acs|min_by([.fac, .login])|.fac) end),
                  (if ($acs|length) == 0 then "" else ($acs|min_by([.fac, .login])|.login) end),
                  (if ($pends|length) == 0 then 0
                   else ($pends|map(if .pmin < 0 then 1 else .pmin end)|min) end) ] )) as $S
      # duas famílias de linha na MESMA varredura: `R` dá a sede de cada login (o candidato
      # precisa saber a própria), `S` dá o mínimo por (sede, problema).
      | (($R | map(["R", .login, .region])) + $S) | .[] | @tsv' 2>/dev/null
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
  # PISO DE IDADE + ESPERADOR NÃO ESTACIONA (2026-08-27, teste de carga): com veredicto
  # entrando sem parar o `.score-dirty` está SEMPRE mais novo que o stamp — todo load da fila
  # entrava aqui, um varria e os outros ficavam presos no `flock -w 5` segurando um worker cada
  # (fila a p50 de 6 s no teste). Agora: reconcilia no máximo 1×/BALLOON_RECONCILE_FLOOR_S (o
  # balão pode nascer até ~10 s depois do AC — invisível p/ quem atravessa a sala com ele) e
  # quem não pega o lock SEGUE (a fila lista o que está materializado; o próximo poll pega o
  # resto). Mesmo contrato do SCORE_SERVE_FLOOR_S do placar.
  : "${BALLOON_RECONCILE_FLOOR_S:=10}"
  [[ -f "$stamp" ]] && [[ -n "$(find "$stamp" -newermt "-$BALLOON_RECONCILE_FLOOR_S seconds" 2>/dev/null)" ]] && return 0
  ( flock -n 9 || exit 0
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
    # ---- PRIMEIRO DA SEDE ------------------------------------------------------------------
    # O staff precisa saber, ao entregar, se aquele é o primeiro balão daquela cor NA SEDE — e
    # dizer isso exige CERTEZA: se existe run mais antiga da mesma sede, no mesmo problema, ainda
    # não julgada, ela ainda pode virar Accepted e roubar o primeiro lugar. O placar pode ser
    # otimista (é repintado a cada build); o balão NÃO — ele é físico, o staff atravessa a sala e
    # anuncia. E no MODO AUTOMÁTICO a folha é impressa segundos depois de a tarefa nascer, com o
    # PDF cacheado para sempre: "promover depois" mudaria a tela e nunca o papel.
    # Por isso: quando não dá para decidir, a tarefa ESPERA (no `.balloon-hold`) e é reavaliada no
    # próximo reconcile — no máximo BALLOON_FIRST_WAIT_S; passado o prazo ela sai SEM estrela, que
    # é a falha segura (o time recebe o balão; ninguém anuncia um primeiro lugar falso).
    local hold="$dir/.balloon-hold" wait_s _sm=0 _SV=not
    wait_s="$(sed -n 's/^[[:space:]]*BALLOON_FIRST_WAIT_S=//p' "$CONTESTSDIR/$c/conf" 2>/dev/null \
              | tail -1 | tr -cd '0-9')"; wait_s="${wait_s:-90}"
    declare -A SM_AC=() SM_ACL=() SM_PEND=() SM_REG=()
    declare -a HOLD_KEEP=()

    # a varredura (2 × N contas) só acontece se houver candidato — sem AC novo nem tarefa
    # esperando, o reconcile não paga nada por esta feature.
    _site_map_ensure() {
      (( _sm )) && return 0
      _sm=1
      local k f1 f2 f3 f4 f5
      while IFS=$'\t' read -r k f1 f2 f3 f4 f5; do
        case "$k" in
          R) SM_REG[$f1]="$f2" ;;
          S) SM_AC["$f1|$f2"]="$f3"; SM_ACL["$f1|$f2"]="$f4"; SM_PEND["$f1|$f2"]="$f5" ;;
        esac
      done < <(pr_site_first_map "$c")
    }
    # _site_verdict <login> <prob> <epoch> — resultado em $_SV: first | not | hold.
    # ⚠ O resultado sai por VARIÁVEL, não por stdout, DE PROPÓSITO: chamar isto em `$( )`
    # roda num subshell e o `_sm=1` do _site_map_ensure morre com ele — cada candidato paga a
    # varredura de N contas DE NOVO. Foi o wedge de 28/08/2026: um lote de ~500 ACs (rajada de
    # balões do teste de carga) virou ~500 varreduras de 12k contas = HORAS preso no
    # `.balloon.lock`, com a fila materializando 1 balão a cada vários segundos e um core
    # ocupado o tempo todo. Com 1-2 ACs por reconcile o bug era invisível.
    _site_verdict() {
      local l="$1" p="$2" e="$3" reg key ac acl pend
      _site_map_ensure
      _SV=not
      reg="${SM_REG[$l]:-}"
      [[ -n "$reg" ]] || return 0                      # sem sede declarada: sem estrela, sem espera
      key="$reg|$p"
      ac="${SM_AC[$key]:-0}"; acl="${SM_ACL[$key]:-}"; pend="${SM_PEND[$key]:-0}"
      [[ "$ac" =~ ^[0-9]+$ ]] || ac=0; [[ "$pend" =~ ^[0-9]+$ ]] || pend=0
      if (( ac > 0 )); then
        (( ac < e )) && return 0                                          # alguém resolveu antes
        (( ac == e )) && [[ -n "$acl" && "$acl" != "$l" ]] && return 0    # empate: login decide
      fi
      (( pend > 0 && pend <= e )) && { _SV=hold; return 0; }              # a mais antiga ainda na fila
      _SV=first
    }
    # _mk_balloon <login> <prob> <epoch> <first_site:true|false> — cria a tarefa (ou a lápide do
    # freeze). É o ÚNICO ponto que materializa balão: o caminho novo e o da espera passam aqui.
    _mk_balloon() {
      local login="$1" cid="$2" sub_epoch="$3" fs="$4" id short colorhex colorname team univ fullname seq
      id="bln$(printf '%s%s%s' "$c" "$login" "$cid" | md5sum | cut -c1-20)"
      [[ -f "$dir/$id.json" ]] && return 0
      [[ -n "${FROZEN[$id]:-}" ]] && return 0
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
        return 0
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
        --argjson fs "$fs" \
        '{id:$id, seq:$seq, kind:"balloon", login:$login, fullname:$fn, team:$team, univ:$univ,
          problem:$prob, short:$short, color_hex:$ch, color_name:$cn, first_site:$fs,
          time:$time, status:"pending",
          claimed_by:"", claimed_at:0, processed_by:"", processed_at:0, delivered_by:"", delivered_at:0}' \
        > "$dir/$id.json.tmp" && mv -f "$dir/$id.json.tmp" "$dir/$id.json"
      audit_log_to "$c" balloon-task "seq=$seq login=$login problema=$short cor=$colorname first_site=$fs"
    }
    # _bln_try <login> <prob> <epoch> [<desde>] — decide e materializa, ou guarda p/ esperar.
    _bln_try() {
      local login="$1" cid="$2" se="$3" since="${4:-$EPOCHSECONDS}" v
      _site_verdict "$login" "$cid" "$se"; v="$_SV"    # SEM $( ): o memo do mapa vive no pai
      if [[ "$v" == hold ]]; then
        if (( EPOCHSECONDS - since < wait_s )); then
          HOLD_KEEP+=("$(jq -cn --arg l "$login" --arg p "$cid" --argjson se "$se" \
                          --argjson since "$since" '{login:$l, problem:$p, sub_epoch:$se, since:$since}')")
          return 0
        fi
        v=not   # prazo vencido: entrega o balão SEM estrela (nunca inventa um primeiro lugar)
      fi
      [[ "$v" == first ]] && _mk_balloon "$login" "$cid" "$se" true || _mk_balloon "$login" "$cid" "$se" false
    }
    _bln_hold_flush() {
      if (( ${#HOLD_KEEP[@]} )); then printf '%s\n' "${HOLD_KEEP[@]}" > "$hold"; else rm -f "$hold"; fi
    }
    # os que já estavam esperando entram ANTES das linhas novas: a varredura do history é
    # incremental, então sem isto eles sumiriam para sempre.
    if [[ -s "$hold" ]]; then
      local hl hp hse hsince
      while IFS=$'\t' read -r hl hp hse hsince; do
        [[ -n "$hl" && -n "$hp" ]] || continue
        _bln_try "$hl" "$hp" "${hse:-0}" "${hsince:-0}"
      done < <(jq -r '[.login, .problem, (.sub_epoch // 0), (.since // 0)] | @tsv' "$hold" 2>/dev/null)
    fi

    # O sub_epoch é o campo NF-1 e o veredicto PODE conter ':' (5 linhas em produção) — por isso
    # o awk, e não um `read` posicional. emit_history_sorted ordena por sub_epoch, então o `seq`
    # do lote sai cronológico. Veredicto por ÚLTIMO no TSV: no modo heurístico ele contém TAB.
    while IFS=$'\t' read -r sub_epoch login cid verdict; do
      [[ -n "$login" && -n "$cid" ]] || continue
      sub_epoch="${sub_epoch//[^0-9]/}"; sub_epoch="${sub_epoch:-0}"   # nunca deixe (( )) ver lixo
      case "$verdict" in *Accepted*) ;; *) continue;; esac
      case "$verdict" in *" (Ignored)") continue;; esac   # ignorada não conta no placar nem ganha balão
      case "$login" in *.admin|*.judge|*.cjudge|*.staff|*.cstaff|*.mon|*.animeitor) continue;; esac
      _bln_try "$login" "$cid" "$sub_epoch" || true
    done < <(emit_history_stream_since "$c" "$prev" \
               | awk -F: 'NF>=7{ v=$5; for(i=6;i<=NF-2;i++) v=v ":" $i;
                                 print $(NF-1) "\t" $2 "\t" $3 "\t" v }' \
               | sort -n -k1,1)
    # o que ficou esperando decisão volta para o arquivo de espera
    _bln_hold_flush
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
