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
# Só contas LOCAIS (28/09/2026): num contest compartilhado, conta de papel do treino não entra mais
# (lib/auth.sh _shared_role_ok) — listá-las aqui mostraria chefes de sede fantasmas no escopo e nas etiquetas.
pr_staff_logins() {
  local c="$1"
  { _pr_role_accounts "$CONTESTSDIR/$c/users" '*.staff'
    _pr_role_accounts "$CONTESTSDIR/$c/users" '*.cstaff'
  } | awk -F'\t' '!seen[$1]++'
}

# logins .cstaff (únicos) — alimenta o seletor "arquivo de uma sede" das etiquetas.
pr_cstaff_logins() {
  local c="$1"
  _pr_role_accounts "$CONTESTSDIR/$c/users" '*.cstaff' | awk -F'\t' '!seen[$1]++'
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
#   "region:<nome>" — o aluno ESTÁ num nó com esse nome, pela regra única de sedes (lib/regions.sh):
#                     a sede dele (gravada ou pela regex) e os ancestrais — `region:Nordeste` cobre as
#                     sedes do Nordeste — e os recortes. Nome sem diferenciar maiúsculas. (Até 28/09/2026
#                     era só "o .team.region gravado é igual": sede derivada pela regex e nó pai não valiam.)
#   qualquer outra   — regex testada no LOGIN do aluno (comportamento clássico).
staff_can_see() {  # <c> <staff_login> <student_login>
  local c="$1" staff="$2" who="$3" f keys
  is_admin && return 0
  f="$(pr_dir "$c")/staff-filters.json"
  [[ -f "$f" ]] || return 0
  declare -F rg_keys_of >/dev/null || source "${_LIBDIR:-${BASH_SOURCE[0]%/*}}/regions.sh"
  keys="$(rg_keys_of "$c" "$who" 2>/dev/null | jq -Rsc 'split("\n") | map(select(length > 0))')"
  [[ -n "$keys" ]] || keys='[]'
  jq -e --arg w "$who" --arg s "$staff" --argjson K "$keys" "$(rg_norm_jq)"'
    ($w|ascii_downcase) as $wl
    | (.[$s] // [])
    | if length==0 then true
      else any(.[]; . as $r
        | if ($r|startswith("region:"))
          then (($r[7:] | rg_key) as $k | ($K | index($k)) != null)
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
  # POPULAÇÃO = quem tem diretório NESTE contest (o login é o nome do DIRETÓRIO — rename é `mv`). A fonte
  # USERS_FROM entra só como tabela de sede (lib/regions.sh: rg_inputs, por caminho) — nunca como
  # população: um escopo com regex de login (`^tg`, `.`) puxaria contas de fora do contest para a lista.
  # Mesma regra que o /contest/badges aprendeu no incidente de 2026-08-18. `region:<nome>` = pertença pela
  # regra ÚNICA de sedes (as chaves dos nós de cada login, num arquivo — nada de mapa em argv).
  declare -F rg_keys_json >/dev/null || source "${_LIBDIR:-${BASH_SOURCE[0]%/*}}/regions.sh"
  loc="$(mktemp)" || return 1
  find "$CONTESTSDIR/$c/users" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null > "$loc"
  rg_keys_json "$c" "$loc.keys" 2>/dev/null || printf '{}' > "$loc.keys"
  jq -rn --slurpfile ff "$f" --arg s "$who" --rawfile loc "$loc" --slurpfile K "$loc.keys" "$(rg_norm_jq)"'
      ($ff[0][$s] // []) as $scope
      | [ $scope[] | select(startswith("region:")) | .[7:] | rg_key ] as $RK
      | [ $scope[] | select(startswith("region:") | not) ] as $RX
      | $loc | split("\n")[] | select(length > 0 and (startswith(".") | not)) | . as $l
      | select(any(($K[0][$l] // [])[]; . as $k | $RK | index($k) != null)
               or any($RX[]; . as $r | (try ($l | ascii_downcase | test($r; "i")) catch false)))' 2>/dev/null > "$loc.out"
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
  rm -f "$loc" "$loc.out" "$loc.keys"; return "$rc"
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

# --- CUSTO DO PAPEL: o ImageMagick desta lib -------------------------------------------------
# Medido no TCP 2026 (cl-tcp, 03/10/2026): cada folha custava ~3,6 s de servidor, e os picos de
# load da prova acompanhavam as rajadas de impressão (21 pedidos num minuto ⇒ load 2,4). Perfil
# de uma folha de código: magick = 2,3 s dos 2,5 s, e quase tudo era `caption:` com CORPO
# AUTOMÁTICO — o IM procura o maior corpo que cabe renderizando o texto várias vezes. Os mais
# caros eram os RÓTULOS FIXOS, iguais em toda folha: "TAREA N.º (verifícala con el sistema)"
# 0,55 s, a linha de páginas 0,50 s, "Firma de quien entregó:" 0,24 s (~1,6 s por folha).
# Três consertos, todos sem mudar um pixel do papel:
#
# 1. **Letreiro cacheado (`_pr_cap_tile`).** Cada `caption:` vira um PNG em
#    $RUNDIR/print-cap/<md5>.png, chave = (caixa, cor, fonte, peso, gravidade, texto, versão do
#    IM); a folha só COMPÕE os PNGs. Rótulo fixo acerta sempre; nome/sede/login do time acertam
#    da 2ª folha dele em diante (o mesmo time imprime várias vezes, e a folha do balão repete os
#    três); a linha de páginas, por N. Fora do print-requests/ de propósito: o arquivamento de
#    rodada MOVE aquele dir (contest-rounds.sh), e a chave é o conteúdo — o tile serve a todo
#    contest. Falhou o tile (disco, permissão) ⇒ o letreiro sai inline como antes: o cache nunca
#    custa uma folha. PR_CAP_CACHE=0 desliga (o smoke compara as duas vias pixel a pixel).
# 2. **Uma thread (`_pr_magick`).** O IM abre até nproc-1 threads OpenMP por comando (Thread=47
#    na produção). Numa folha A4 isso não encurta nada — mesmo tempo de parede, medido — e gasta
#    ~20% a mais de CPU, com rajadas de threads que inflam o load. Só nos renders desta lib (nada
#    de export global: foto de time e logo são de outros handlers). PR_MAGICK_THREADS muda.
# 3. **Fontes resolvidas uma vez por processo (`_pr_fonts_load`).** Eram 5 `magick -list font`
#    por folha (~15 ms cada na produção) — marginal, mas de graça.
_pr_magick() { MAGICK_THREAD_LIMIT="${PR_MAGICK_THREADS:-1}" magick "$@"; }
: "${PR_CAP_CACHE:=1}"
_PR_FONTS_OK=0; _PR_FB=""; _PR_FR=""; _PR_F1=""; _PR_IMV=""
# _pr_fonts_load — preenche _PR_FB (DejaVu-Sans-Bold), _PR_FR (DejaVu-Sans) e _PR_F1 (a 1ª fonte
# que o IM conhece: o reserva de cada um). Chamar no shell CORRENTE, nunca dentro de $(...).
_pr_fonts_load() {
  (( _PR_FONTS_OK )) && return 0
  local l; l="$(magick -list font 2>/dev/null)"
  _PR_FB="$(awk -F': ' '/Font: DejaVu-Sans-Bold$/{print $2; exit}' <<<"$l")"
  _PR_FR="$(awk -F': ' '/Font: DejaVu-Sans$/{print $2; exit}' <<<"$l")"
  _PR_F1="$(awk -F': ' '/Font: /{print $2; exit}' <<<"$l")"
  # a chave do tile leva a versão do IM E os arquivos das duas fontes (caminho:tamanho:mtime): a
  # imagem nova que troca o DejaVu sem trocar o IM não pode servir letreiro velho
  local g; g="$(awk '/Font: DejaVu-Sans(-Bold)?$/{f=1} f && /glyphs:/{print $2; f=0}' <<<"$l")"
  _PR_IMV="$(magick -version 2>/dev/null | head -1) $( [[ -n "$g" ]] && stat -c '%n:%s:%Y' $g 2>/dev/null | tr '\n' ' ')"
  _PR_FONTS_OK=1
}
# _pr_cap_tile <w> <h> <fill> <fonte> <peso> <stroke> <strokewidth> <gravidade> <texto> -> ecoa o
# PNG do letreiro (rc!=0 = sem cache: o chamador faz o letreiro inline). O texto já chega pelo
# cap_esc (o `%` e o `@` do caption); o md5 protege o NOME do arquivo. Escrita tmp+mv: renders
# correm em paralelo (PR_RENDER_SLOTS) e dois podem criar o mesmo tile.
_pr_cap_tile() {
  (( PR_CAP_CACHE )) || return 1
  local d="${RUNDIR:-/tmp}/print-cap" k f t
  k="$(printf '%s\n' "$_PR_IMV" "$@" | md5sum)"; k="${k%% *}"; f="$d/$k.png"
  if [[ ! -s "$f" ]]; then
    mkdir -p "$d" 2>/dev/null || return 1
    t="$(mktemp "$d/.t.XXXXXX" 2>/dev/null)" || return 1
    local -a a=( -size "${1}x${2}" -background white -fill "$3" )
    [[ -n "$4" ]] && a+=( -font "$4" )
    [[ -n "$5" ]] && a+=( -weight "$5" )
    [[ -n "$6" ]] && a+=( -stroke "$6" )
    [[ -n "$7" ]] && a+=( -strokewidth "$7" )
    a+=( -gravity "$8" "caption:$9" )
    if _pr_magick "${a[@]}" "png:$t" 2>/dev/null && [[ -s "$t" ]]; then mv -f "$t" "$f" 2>/dev/null || { rm -f "$t"; return 1; }
    else rm -f "$t"; return 1; fi
    # poda de vez em quando (1 em 256 tiles NOVOS): sobra de tmp e tile de 30+ dias sem recriar
    (( RANDOM % 256 )) || find "$d" -maxdepth 1 \( -name '.t.*' -mmin +60 -o -name '*.png' -mtime +30 \) -delete 2>/dev/null
  fi
  printf '%s' "$f"
}
# _pr_cap_init / _pr_addcap — o `addcap` das folhas (capa e balão). Acumula no array `cov` do
# chamador (escopo dinâmico do bash). ⚠ No IM7 os settings NÃO param nos parênteses: o que um
# letreiro ou um traço define vale para os seguintes. Dois deles mudam o letreiro:
#   - o `-weight` do letreiro anterior (o rótulo regular logo depois do nome do time é feito com
#     o peso 700 em vigor) — só o addcap o define: _pr_cw/_pr_cf = peso/fonte EM VIGOR;
#   - o `-stroke`/`-strokewidth` das LINHAS da folha (`-strokewidth 2 -draw line…`): o corpo
#     automático do caption mede o texto com o traço em vigor, e o "TAREA N.º…" logo abaixo da
#     linha saía em outro corpo (o smoke pegou: 5.455 pixels de diferença só naquela faixa) — só o
#     chamador os define: lidos do próprio `cov` (o último valor de cada um).
# O tile reproduz esse estado; sem isso o PNG cacheado sairia diferente do papel de sempre.
_pr_cap_init() { _pr_cw=""; _pr_cf=""; }
_pr_addcap() { # w h x y fill font weight gravity text
  [[ -n "$6" ]] && _pr_cf="$6"
  [[ -n "$7" ]] && _pr_cw="$7"
  local tile i sk="" sw=""   # `work` = o workdir do chamador (_pr_render/_pr_render_balloon)
  for ((i=${#cov[@]}-2; i>=0; i--)); do
    [[ -z "$sk" && "${cov[i]}" == -stroke ]] && sk="${cov[i+1]}"
    [[ -z "$sw" && "${cov[i]}" == -strokewidth ]] && sw="${cov[i+1]}"
    [[ -n "$sk" && -n "$sw" ]] && break
  done
  # o tile é PRESO no workdir da folha (hardlink; cópia se for outro sistema de arquivos) antes de
  # entrar no comando: a poda de 30 dias pode apagar o do cache entre agora e o magick ler — e capa
  # que falha vira um pedido cacheado SEM folha de rosto. Preso, o arquivo não some no meio.
  local pin="$work/cap-${#cov[@]}.png"
  if tile="$(_pr_cap_tile "$1" "$2" "$5" "$_pr_cf" "$_pr_cw" "$sk" "$sw" "$8" "$9")" \
     && { ln -f "$tile" "$pin" 2>/dev/null || cp -f "$tile" "$pin" 2>/dev/null; }; then
    cov+=( "$pin" -gravity northwest -geometry "+${3}+${4}" -composite )
  else
    cov+=( '(' -size "${1}x${2}" -background white -fill "$5" )
    [[ -n "$_pr_cf" ]] && cov+=( -font "$_pr_cf" )
    [[ -n "$_pr_cw" ]] && cov+=( -weight "$_pr_cw" )
    cov+=( -gravity "$8" "caption:$9" ')' -gravity northwest -geometry "+${3}+${4}" -composite )
  fi
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
  name="$(basename -- "${name:-arquivo}" | tr -cd 'A-Za-z0-9._+-')"; [[ -n "$name" ]] || name=arquivo   # + p/ sol.c++
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
  _pr_fonts_load; fr="${_PR_FR:-$_PR_F1}"
  local -a st=( _pr_magick -size 1240x1754 xc:none -gravity south -pointsize 26 -fill '#333' )
  [[ -n "$fr" ]] && st+=( -font "$fr" )
  st+=( -annotate +0+40 "$foot" -units PixelsPerInch -density 150 "$work/stamp.pdf" )
  "${st[@]}" 2>>"$err" && [[ -s "$work/stamp.pdf" ]] \
    && qpdf "$out" --overlay "$work/stamp.pdf" --repeat=1 -- "$work/stamped.pdf" 2>>"$err" \
    && [[ -s "$work/stamped.pdf" ]] && mv -f "$work/stamped.pdf" "$out"
  [[ -s "$out" ]]
}

# --- IDIOMA DO PAPEL: as folhas (rosto da impressão e entrega de balão) seguem o LOCALE do contest --
# pr_lang <c> -> pt|en|es (ausente/inválido = pt). Lido SEM source e sem depender do common.sh: esta
# lib também é sourceada STANDALONE (smokes, report-gen).
pr_lang() {
  local f="$CONTESTSDIR/$1/conf" line v=""
  if [[ -r "$f" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" == LOCALE=* ]] || continue
      v="${line#LOCALE=}"; v="${v//\'/}"; v="${v//\"/}"; break
    done < "$f"
  fi
  case "$v" in en|es) printf '%s' "$v" ;; *) printf 'pt' ;; esac
}
# _pr_t <lang> <chave> — TODA string impressa sai daqui (molde do _doc_t do contest-docs.sh).
# Espanhol latino-americano neutro (glossário em docs/I18N.md). `%s` = o número de páginas.
# ⚠ `foot` vai ao carimbo do rodapé, que passa pelo filtro ASCII do _pr_text2pdf — sem acento.
_pr_t() {
  local l="$1" k="$2"
  case "$l:$k" in
    pt:team)       printf 'EQUIPE' ;;
    en:team)       printf 'TEAM' ;;
    es:team)       printf 'EQUIPO' ;;
    pt:noteam)     printf '(sem nome de time)' ;;
    en:noteam)     printf '(no team name)' ;;
    es:noteam)     printf '(sin nombre de equipo)' ;;
    pt:login)      printf 'login' ;;
    en:login)      printf 'login' ;;
    es:login)      printf 'usuario' ;;
    pt:taskno)     printf 'TAREFA Nº  (confira com o sistema)' ;;
    en:taskno)     printf 'TASK No.  (check it against the system)' ;;
    es:taskno)     printf 'TAREA N.º  (verifícala con el sistema)' ;;
    pt:pages)      printf '%s página(s)  —  não conte esta folha de rosto' "$3" ;;
    en:pages)      printf '%s page(s)  —  do not count this cover sheet' "$3" ;;
    es:pages)      printf '%s página(s)  —  no cuentes esta portada' "$3" ;;
    pt:convfail)   printf 'ATENÇÃO: não foi possível converter — imprima o anexo cru' ;;
    en:convfail)   printf 'WARNING: could not convert — print the raw attachment' ;;
    es:convfail)   printf 'ATENCIÓN: no se pudo convertir — imprime el archivo original' ;;
    pt:sign)       printf 'Assinatura de quem entregou:' ;;
    en:sign)       printf 'Delivered by (signature):' ;;
    es:sign)       printf 'Firma de quien entregó:' ;;
    pt:when)       printf 'Hora da entrega:' ;;
    en:when)       printf 'Delivery time:' ;;
    es:when)       printf 'Hora de entrega:' ;;
    pt:foot)       printf 'tarefa' ;;
    en:foot)       printf 'task' ;;
    es:foot)       printf 'tarea' ;;
    pt:balloon)    printf 'ENTREGA DE BALÃO' ;;
    en:balloon)    printf 'BALLOON DELIVERY' ;;
    es:balloon)    printf 'ENTREGA DE GLOBO' ;;
    pt:problem)    printf 'PROBLEMA' ;;
    en:problem)    printf 'PROBLEM' ;;
    es:problem)    printf 'PROBLEMA' ;;
    pt:color)      printf 'COR DO BALÃO' ;;
    en:color)      printf 'BALLOON COLOR' ;;
    es:color)      printf 'COLOR DEL GLOBO' ;;
    pt:first)      printf 'PRIMEIRO DA SEDE' ;;
    en:first)      printf 'FIRST AT THIS SITE' ;;
    es:first)      printf 'PRIMERO DE LA SEDE' ;;
    pt:firstsub)   printf 'primeiro time da sede a resolver este problema' ;;
    en:firstsub)   printf 'first team at this site to solve this problem' ;;
    es:firstsub)   printf 'primer equipo de la sede en resolver este problema' ;;
    *)             _pr_t pt "$k" "${3:-}" ;;
  esac
}

# --- render interno: produz <id>.combined.pdf (chamado SOB flock) ---------
# Persiste pages/build_ok no meta. Folha de rosto (capa) sempre é a página 1.
_pr_render() {  # <c> <id> <src> <meta> <cache>
  local c="$1" id="$2" src="$3" meta="$4" cache="$5"
  local work; work="$(mktemp -d)" || return 1
  trap 'rm -rf "$work"' RETURN
  local doc="$work/doc.pdf" docok=0 mime enc fn ext inp errf foot lg sq L
  L="$(pr_lang "$c")"
  # o stderr das conversões vai para <id>.err quando algo falha — antes ia todo p/ /dev/null,
  # e a única pista de um pedido que não converteu era o "ATENÇÃO" impresso na capa
  errf="${meta%.json}.err"; : > "$errf"
  fn="$(jq -r '.filename // "arquivo"' "$meta" 2>/dev/null)"
  # rodapé das páginas de código: LOGIN do time + arquivo + nº da tarefa (ver _pr_text2pdf).
  # É o que identifica a folha que se separou da capa na mesa da sala.
  lg="$(jq -r '.login // ""' "$meta" 2>/dev/null)"
  sq="$(jq -r '.seq // 0' "$meta" 2>/dev/null)"
  foot="$(printf '%s  -  %s  -  %s #%s' "${lg:-?}" "$fn" "$(_pr_t "$L" foot)" "${sq:-0}" | tr -d '\n')"

  mime="$(file -b --mime-type "$src" 2>/dev/null)"
  case "$mime" in
    application/pdf)
      cp "$src" "$doc"
      if pdfinfo "$doc" >/dev/null 2>&1; then docok=1
      elif qpdf --decrypt "$src" "$doc" 2>/dev/null && pdfinfo "$doc" >/dev/null 2>&1; then docok=1
      elif gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -sOutputFile="$doc" "$src" 2>/dev/null && pdfinfo "$doc" >/dev/null 2>&1; then docok=1
      fi ;;
    image/*)
      _pr_magick "$src" -resize 1240x1754\> -background white -gravity center -extent 1240x1754 \
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
  team="$(jq -r '.team // ""' "$meta" 2>/dev/null)"; [[ -n "$team" ]] || team="$(_pr_t "$L" noteam)"
  univ="$(jq -r '.univ // ""' "$meta" 2>/dev/null)"
  login="$(jq -r '.login // ""' "$meta" 2>/dev/null)"
  # caption faz expansão de %; neutraliza e evita leitura de @arquivo (dados do passwd)
  cap_esc(){ local s="${1//%/%%}"; [[ "$s" == @* ]] && s=" $s"; printf '%s' "$s"; }
  team="$(cap_esc "$team")"; univ="$(cap_esc "$univ")"; login="$(cap_esc "$login")"
  if (( docok )); then pagesline="$(_pr_t "$L" pages "$pages")"
  else pagesline="$(_pr_t "$L" convfail)"; fi
  _pr_fonts_load; FB="${_PR_FB:-$_PR_F1}"; FR="${_PR_FR:-$FB}"

  # letreiros cacheados (ver _pr_cap_tile) — a folha só compõe os PNGs
  local -a cov=( _pr_magick -size 1240x1754 xc:white )
  local _pr_cw _pr_cf; _pr_cap_init
  addcap(){ _pr_addcap "$@"; }   # w h x y fill font weight gravity text
  addcap 1080  46  80   78 '#555' "$FR" ''   center "$(_pr_t "$L" team)"
  addcap 1080 210  80  130 black  "$FB" 700  center "$team"
  [[ -n "$univ" ]] && addcap 1080 64 80 352 '#333' "$FR" '' center "$univ"
  addcap 1080  44  80  430 '#555' "$FR" ''   center "$(_pr_t "$L" login)"
  addcap 1080 100  80  478 black  "$FB" 700  center "$login"
  cov+=( -fill none -stroke '#999' -strokewidth 2 -draw "line 80,620 1160,620" -stroke none )
  addcap 1080  56  80  664 '#555' "$FR" ''   center "$(_pr_t "$L" taskno)"
  addcap 1080 220  80  724 black  "$FB" 800  center "$seq"
  addcap 1080  74  80  966 black  "$FR" ''   center "$pagesline"
  cov+=( -fill none -stroke '#999' -strokewidth 2 -draw "line 80,1080 1160,1080" -stroke none )
  addcap  600  46  80 1500 black  "$FR" ''   west   "$(_pr_t "$L" sign)"
  cov+=( -fill none -stroke black -strokewidth 2 -draw "line 80,1600 700,1600" -stroke none )
  addcap  320  46 760 1500 black  "$FR" ''   west   "$(_pr_t "$L" when)"
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
  jq --argjson p "${pages:-0}" --argjson ok "$okjson" --arg l "$L" '.pages=$p | .build_ok=$ok | .sheet_lang=$l' "$meta" \
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
_pr_cache_ok() {  # <cache> <src> <meta> [lang]
  [[ -f "$1" && "$1" -nt "$2" && "$1" -nt "${BASH_SOURCE[0]}" ]] || return 1
  # ⚠ `.build_ok // true` NÃO serve: o `//` do jq trata **false como vazio** e devolveria
  # `true` justamente no caso que interessa (ver a armadilha do `//` no CLAUDE.md). O teste
  # de booleano é por igualdade explícita.
  # O IDIOMA do papel também faz parte da validade: o admin trocou o LOCALE ⇒ a folha de rosto
  # se refaz no idioma novo (meta sem `sheet_lang` = papel de antes do espanhol, era pt).
  ! jq -e --arg l "${4:-pt}" '.build_ok == false or ((.sheet_lang // "pt") != $l)' "$3" >/dev/null 2>&1
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
  local L; L="$(pr_lang "$c")"
  dir="$(pr_dir "$c")"; src="$dir/$id.src"; meta="$dir/$id.json"; cache="$dir/$id.combined.pdf"
  [[ -f "$src" && -f "$meta" ]] || return 1
  if _pr_cache_ok "$cache" "$src" "$meta" "$L"; then printf '%s' "$cache"; return 0; fi
  ( flock -w 30 9 || exit 1
    _pr_cache_ok "$cache" "$src" "$meta" "$L" && exit 0     # double-check após o lock
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

# pr_recolor_pending_balloons <c> : as cores mudaram ⇒ a tarefa de balão AINDA NÃO IMPRESSA (status pending) passa à
# cor nova (meta + PDF em cache apagado: o staff imprime a folha certa). A JÁ IMPRESSA (printed, não entregue) levou
# o papel da cor antiga e não tem conserto — só é contada, p/ a tela avisar. Ecoa "<recoloridas> <impressas_velhas>".
# (auditoria do painel, 03/10/2026: trocar a cor no meio da prova deixava a fila com a cor antiga, calada.)
pr_recolor_pending_balloons() {
  local c="$1" dir id short hex st nhex L n=0 old=0
  dir="$(pr_dir "$c")"; [[ -d "$dir" ]] || { printf '0 0'; return 0; }
  L="$(pr_lang "$c")"
  local -A NEW=()
  while IFS=$'\t' read -r id short hex st; do
    [[ -n "$id" ]] || continue
    [[ -n "${NEW[$short]:-}" ]] || NEW[$short]="$(pr_balloon_color "$c" "$short")"
    nhex="${NEW[$short]}"
    [[ "$nhex" == "$hex" ]] && continue
    if [[ "$st" == pending ]]; then
      local meta="$dir/$id.json" tmp="$dir/$id.json.rc.$BASHPID"
      jq --arg h "$nhex" --arg n "$(pr_color_name "$nhex" "$L")" --arg l "$L" \
         '.color_hex=$h | .color_name=$n | .color_lang=$l' "$meta" > "$tmp" 2>/dev/null \
        && mv -f "$tmp" "$meta" && rm -f "$dir/$id.combined.pdf" && n=$((n+1))
      rm -f "$tmp"
    elif [[ "$st" == printed ]]; then old=$((old+1)); fi
  done < <(find "$dir" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null \
             | xargs -0r jq -r 'select(type == "object" and .kind == "balloon")
                 | [(input_filename | split("/") | last | rtrimstr(".json")), (.short // "?"), (.color_hex // ""), (.status // "pending")]
                 | join("\t")' 2>/dev/null)
  printf '%s %s' "$n" "$old"
}

# pr_color_name <RRGGBB> [lang] : nome da cor por extenso no idioma do contest (pt|en|es; default pt).
# Tabela dos 15 defaults ICPC; fora dela, a cor nomeada mais próxima por distância RGB, com o hex
# entre parênteses. Em pt e es o nome inglês vai junto — o balão físico costuma vir rotulado em
# inglês e o staff casa pelo rótulo.
pr_color_name() {
  local hex L="${2:-pt}"; hex="$(printf '%s' "$1" | tr -cd '0-9A-Fa-f' | tr 'a-f' 'A-F')"; hex="${hex:0:6}"
  case "$L" in en|es) ;; *) L=pt ;; esac
  [[ "${#hex}" -eq 6 ]] || { case "$L" in en) printf 'color' ;; es) printf 'color' ;; *) printf 'cor' ;; esac; return; }
  # hex  pt  en  es  (uma linha por cor; `_` = espaço)
  local tab='FFFFFF branco white blanco
000000 preto black negro
FF0000 vermelho red rojo
800000 vinho maroon vino
FFFF00 amarelo yellow amarillo
008000 verde green verde
0000FF azul blue azul
000080 azul-marinho navy_blue azul_marino
FF00FF rosa pink rosa
800080 roxo purple morado
00FF00 verde-limão lime_green verde_lima
00FFFF azul-claro light_blue celeste
C0C0C0 prata silver plateado
FF8000 laranja orange naranja
A3794D marrom brown marrón'
  local h npt nen nes nm
  while read -r h npt nen nes; do
    [[ "$h" == "$hex" ]] || continue
    nen="${nen//_/ }"; nes="${nes//_/ }"
    case "$L" in en) printf '%s' "$nen" ;; es) printf '%s (%s)' "$nes" "$nen" ;; *) printf '%s (%s)' "$npt" "$nen" ;; esac
    return
  done <<<"$tab"
  local r=$((16#${hex:0:2})) g=$((16#${hex:2:2})) b=$((16#${hex:4:2}))
  local best='' bestd=999999999 hr hg hb d
  while read -r h npt nen nes; do
    [[ -n "$h" ]] || continue
    hr=$((16#${h:0:2})); hg=$((16#${h:2:2})); hb=$((16#${h:4:2}))
    d=$(( (r-hr)*(r-hr) + (g-hg)*(g-hg) + (b-hb)*(b-hb) ))
    case "$L" in en) nm="${nen//_/ }" ;; es) nm="${nes//_/ }" ;; *) nm="$npt" ;; esac
    (( d < bestd )) && { bestd=$d; best="$nm"; }
  done <<<"$tab"
  printf '%s (#%s)' "${best:-cor}" "$hex"
}

# _pr_render_balloon <c> <id> <meta> <cache> : folha A4 da entrega do balão (sob flock do chamador).
_pr_render_balloon() {
  local c="$1" id="$2" meta="$3" cache="$4"
  local work; work="$(mktemp -d)" || return 1
  trap 'rm -rf "$work"' RETURN
  local seq team univ login short colorhex colorname FB FR L
  L="$(pr_lang "$c")"
  seq="$(jq -r '.seq // 0' "$meta")"
  team="$(jq -r '.team // ""' "$meta")"; [[ -n "$team" ]] || team="$(_pr_t "$L" noteam)"
  univ="$(jq -r '.univ // ""' "$meta")"
  login="$(jq -r '.login // ""' "$meta")"
  short="$(jq -r '.short // "?"' "$meta")"
  colorhex="$(jq -r '.color_hex // "CCCCCC"' "$meta")"
  # o nome foi gravado na criação, no idioma do contest daquele momento (`color_lang`; ausente =
  # pt). Trocou o LOCALE depois: o papel usa o nome no idioma novo, a fila mantém o gravado.
  colorname="$(jq -r --arg l "$L" 'if (.color_lang // "pt") == $l then (.color_name // "") else "" end' "$meta")"
  [[ -n "$colorname" ]] || colorname="$(pr_color_name "$colorhex" "$L")"
  cap_esc(){ local s="${1//%/%%}"; [[ "$s" == @* ]] && s=" $s"; printf '%s' "$s"; }
  team="$(cap_esc "$team")"; univ="$(cap_esc "$univ")"; login="$(cap_esc "$login")"; colorname="$(cap_esc "$colorname")"; short="$(cap_esc "$short")"
  _pr_fonts_load; FB="${_PR_FB:-$_PR_F1}"; FR="${_PR_FR:-$FB}"

  local -a cov=( _pr_magick -size 1240x1754 xc:white )
  local _pr_cw _pr_cf; _pr_cap_init
  addcap(){ _pr_addcap "$@"; }   # letreiros cacheados (ver _pr_cap_tile)
  addcap 1080  46  80   66 '#555' "$FR" ''   center "$(_pr_t "$L" balloon)"
  addcap 1080 150  80  120 black  "$FB" 700  center "$team"
  [[ -n "$univ" ]] && addcap 1080 54 80 280 '#333' "$FR" '' center "$univ"
  addcap 1080  40  80  346 '#555' "$FR" ''   center "$(_pr_t "$L" login)"
  addcap 1080  78  80  388 black  "$FB" 700  center "$login"
  cov+=( -fill none -stroke '#999' -strokewidth 2 -draw "line 80,500 1160,500" -stroke none )
  addcap 540  52  80  528 '#555' "$FR" ''   center "$(_pr_t "$L" problem)"
  addcap 540 200  80  590 black  "$FB" 800  center "$short"
  addcap 540  52 620  528 '#555' "$FR" ''   center "$(_pr_t "$L" color)"
  cov+=( -fill "#$colorhex" -stroke '#333' -strokewidth 2 )
  cov+=( -draw "translate 890,690 ellipse 0,0 78,98 0,360" )
  cov+=( -draw "translate 890,690 polygon -12,96 12,96 0,122" )
  cov+=( -fill none -stroke none )
  addcap 540  72 620  812 black  "$FB" 700  center "$colorname"
  cov+=( -fill none -stroke '#999' -strokewidth 2 -draw "line 80,910 1160,910" -stroke none )
  addcap 1080  54  80  956 '#555' "$FR" ''   center "$(_pr_t "$L" taskno)"
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
    addcap 880 56 220 1344 '#7A5C00' "$FB" 800 west "$(_pr_t "$L" first)"
    addcap 880 32 220 1406 '#7A5C00' "$FR" ''  west "$(_pr_t "$L" firstsub)"
  fi
  addcap  600  46  80 1500 black  "$FR" ''   west   "$(_pr_t "$L" sign)"
  cov+=( -fill none -stroke black -strokewidth 2 -draw "line 80,1600 700,1600" -stroke none )
  addcap  320  46 760 1500 black  "$FR" ''   west   "$(_pr_t "$L" when)"
  cov+=( -fill none -stroke black -strokewidth 2 -draw "line 760,1600 1160,1600" -stroke none )
  cov+=( -units PixelsPerInch -density 150 "$work/balloon.pdf" )
  "${cov[@]}" 2>/dev/null && [[ -s "$work/balloon.pdf" ]] || return 1
  mv -f "$work/balloon.pdf" "$cache"
  jq --arg l "$L" '.build_ok=true | .sheet_lang=$l' "$meta" > "$work/m.json" 2>/dev/null && mv -f "$work/m.json" "$meta"
  return 0
}

# pr_build_balloon <c> <id> : ecoa o combined.pdf da folha do balão (build-once; conteúdo imutável —
# salvo o IDIOMA: trocou o LOCALE do contest, a folha se refaz no idioma novo).
_pr_balloon_cache_ok() {  # <cache> <meta> <lang>
  [[ -f "$1" ]] || return 1
  jq -e --arg l "$3" '(.sheet_lang // "pt") == $l' "$2" >/dev/null 2>&1
}
pr_build_balloon() {
  local c="$1" id="$2" dir meta cache L
  L="$(pr_lang "$c")"
  dir="$(pr_dir "$c")"; meta="$dir/$id.json"; cache="$dir/$id.combined.pdf"
  [[ -f "$meta" ]] || return 1
  _pr_balloon_cache_ok "$cache" "$meta" "$L" && { printf '%s' "$cache"; return 0; }
  ( flock -w 30 9 || exit 1
    _pr_balloon_cache_ok "$cache" "$meta" "$L" && exit 0
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
  local c="$1" d s
  d="$CONTESTSDIR/$c/users"; [[ -d "$d" ]] || return 0
  # a sede de cada login pela regra ÚNICA (gravada ou pela regex — antes só a gravada contava)
  declare -F rg_sites_json >/dev/null || source "${_LIBDIR:-${BASH_SOURCE[0]%/*}}/regions.sh"
  s="$(mktemp)" || return 1
  rg_sites_json "$c" "$s" 2>/dev/null || printf '{}' > "$s"
  { jq -c 'to_entries[] | {k:"r", login:.key, region:.value}' "$s" 2>/dev/null
    # desclassificado não leva a ★ de primeiro da sede (linhas `d`, um grep — auditoria 03/10/2026)
    find "$d" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
      | xargs -0 -r grep -lE '"disqualified": *true' 2>/dev/null \
      | awk -F/ '{ printf "{\"k\":\"d\",\"login\":\"%s\"}\n", $(NF-1) }'
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
      (map(select(.k == "d") | {(.login): true}) | add // {}) as $DQ
      | (map(select(.k == "r")) | map(select((.login|isrole)|not) | select(.region != ""))) as $R
      | ($R | map({(.login): .region}) | add // {}) as $REG
      | (map(select(.k == "m"))
         # contas de PAPEL não ganham balão nem roubam o primeiro lugar (lista do reconciliador)
         | map(select((.login|isrole)|not)) | map(select($DQ[.login] | not))
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
  rm -f "$s"
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
    local C_LANG; C_LANG="$(pr_lang "$c")"      # o nome da cor é gravado no idioma do contest
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
        C_NAME[$cid]="$(pr_color_name "${C_HEX[$cid]}" "$C_LANG")"
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
        --arg ch "$colorhex" --arg cn "$colorname" --arg cl "$C_LANG" --argjson time "$EPOCHSECONDS" \
        --argjson fs "$fs" \
        '{id:$id, seq:$seq, kind:"balloon", login:$login, fullname:$fn, team:$team, univ:$univ,
          problem:$prob, short:$short, color_hex:$ch, color_name:$cn, color_lang:$cl, first_site:$fs,
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

    # DESCLASSIFICADO não ganha balão (o placar já o tirava; a fila do staff seguia entregando — auditoria do painel,
    # 03/10/2026). Um grep sobre os account.json, só quando há histórico novo (este bloco já é o caminho raro).
    local -A _DQ=(); local _dqf
    while IFS= read -r _dqf; do _dqf="${_dqf%/account.json}"; _DQ["${_dqf##*/}"]=1
    done < <(find "$CONTESTSDIR/$c/users" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
               | xargs -0 -r grep -lE '"disqualified": *true' 2>/dev/null)
    # O sub_epoch é o campo NF-1 e o veredicto PODE conter ':' (5 linhas em produção) — por isso
    # o awk, e não um `read` posicional. emit_history_sorted ordena por sub_epoch, então o `seq`
    # do lote sai cronológico. Veredicto por ÚLTIMO no TSV: no modo heurístico ele contém TAB.
    while IFS=$'\t' read -r sub_epoch login cid verdict; do
      [[ -n "$login" && -n "$cid" ]] || continue
      sub_epoch="${sub_epoch//[^0-9]/}"; sub_epoch="${sub_epoch:-0}"   # nunca deixe (( )) ver lixo
      # pela CLASSE (prefixo), nunca por substring: o texto do time (`¦…`, configurável) pode
      # conter "Accepted" ("Not Accepted") — o awk abaixo já cortou o `¦…`
      case "$verdict" in Accepted*) ;; *) continue;; esac
      case "$verdict" in *" (Ignored)") continue;; esac   # ignorada não conta no placar nem ganha balão
      case "$login" in *.admin|*.judge|*.cjudge|*.staff|*.cstaff|*.mon|*.animeitor) continue;; esac
      [[ -n "${_DQ[$login]:-}" ]] && continue
      _bln_try "$login" "$cid" "$sub_epoch" || true
    done < <(emit_history_stream_since "$c" "$prev" \
               | awk -F: 'NF>=7{ v=$5; for(i=6;i<=NF-2;i++) v=v ":" $i; sub(/¦.*$/, "", v);
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

# staff_regions <c> — as SEDES (nomes de `.team.region`) do escopo de $SESSION_LOGIN, 1/linha.
# rc=1 = SEM escopo explícito no staff-filters. Quem decide o que "sem escopo" significa é o chamador:
# nas telas de LEITURA ausente = vê tudo; em AÇÃO e em CREDENCIAL (comando do mlinux, link do
# reveleitor do Animeitor) é fail-CLOSED — sem sede definida, nada. Token `region:<sede>` responde
# direto; escopo por regex é resolvido pelos logins visíveis (colhe a sede de cada um).
staff_regions(){
  local c="$1" f="$CONTESTSDIR/$1/print-requests/staff-filters.json" out
  [[ -s "$f" ]] || return 1
  jq -e --arg s "$SESSION_LOGIN" 'has($s) and ((.[$s] // []) | length > 0)' "$f" >/dev/null 2>&1 || return 1
  out="$(jq -r --arg s "$SESSION_LOGIN" \
    '(.[$s] // [])[] | select(startswith("region:")) | .[7:] | gsub("^ +| +$"; "")' "$f" 2>/dev/null)"
  if [[ -n "$out" ]]; then printf '%s\n' "$out"; return 0; fi
  # escopo por regex: resolve os logins visíveis e colhe a SEDE de cada um (regra única: gravada ou pela
  # regex) — um jq só, lendo o mapa de sedes de arquivo (antes: um jq por login e só a sede gravada)
  local logins w
  if logins="$(staff_visible_logins "$c" "$SESSION_LOGIN" 2>/dev/null)"; then
    declare -F rg_sites_json >/dev/null || source "${_LIBDIR:-${BASH_SOURCE[0]%/*}}/regions.sh"
    w="$(mktemp)" || return 1
    rg_sites_json "$c" "$w" 2>/dev/null || printf '{}' > "$w"
    printf '%s\n' "$logins" | jq -Rr --slurpfile S "$w" 'select(length > 0) | $S[0][.] // empty' | sort -u
    rm -f "$w"
    return 0
  fi
  return 1
}
