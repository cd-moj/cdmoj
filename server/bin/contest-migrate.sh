#!/usr/bin/env bash
#
# contest-migrate.sh — migra um contest de PROVA/LAB do MOJ ANTIGO (conf com PROBS + passwd +
# controle/history + submissions flat) para um contest NOVO no store por-usuário do newmoj.
#
#   contest-migrate.sh stage   --from <legacy/<id>> --map <tsv> --stage <dir> [--contest-dir <prod/<id>>]
#   contest-migrate.sh verify  --from <legacy/<id>> --stage <dir>
#   contest-migrate.sh install --stage <dir> --contest-dir <prod/<id>>
#   contest-migrate.sh audit   --from <legacy/<id>> --contest-dir <prod/<id>>
#
# É o irmão do treino-migrate.sh, mas p/ o caso FRESH-CREATE (o contest não existe no newmoj)
# e com probid = OFFSET numérico no PROBS (não <repo>#<slug>). Por isso NÃO reusa o
# treino-migrate (que é MERGE em contest vivo): monta tudo num staging descartável e publica
# com UM `mv -T` atômico.
#
# O CERNE — a invariante que apaga células em silêncio: o placar casa a célula por SC_CANON
# (derivado do conf, score-common.sh:60-62) e o metrics indexa por probid do history. Se não
# forem string idêntica, a célula some. Garantia: o conf-PROBS e o history saem da MESMA
# tabela OFF2ID (offset -> id do newmoj). Com [i+4]=id (tem '#'), sc_load usa [i+4] = OFF2ID
# = probid do history -> casam por construção.
#
# Fatos do legado assumidos (medidos nos 41 boaventura):
#   - PROBS 5-tupla: `cdmoj <repo>/<slug> "Titulo" <letra> <slug>.pdf`. [i+1] tem BARRA;
#     [i+4] é PDF (NÃO id — jamais usar como canon). offset p (probid do history) -> PROBS[p+1].
#   - history 7 campos f1:login:probid:LANG:verdict:f6:subid. f1 NÃO é confiável (3 labs com
#     CONTEST_START reeditado pós-prova). f6 = epoch absoluto, autoritativo. subid único.
#   - tempo := f6 (o placar icpc IGNORA o campo tempo — usa first_ac_epoch de sub_epoch).
#   - submissions/ flat `<f6>:<subid>-<login>-<letra>.<ext>` + marcador `accepted` (não-âncora,
#     ignorar) + subdir accepted/. Roteia por f6:subid contra o history. Sem-ext -> <subid>.txt.
#   - passwd login:senha:nome:campo4; campo4 = EMAIL (@) -> .email; SEM telegram. Roles
#     .admin/.mon preservados. owner = lucasboaventura.

set -euo pipefail
export LC_ALL=C

die(){ echo "contest-migrate: $*" >&2; exit 1; }
log(){ echo "  $*" >&2; }
# concatena os history de todos os users de <contest-dir>. `find -exec` tolera ZERO arquivos
# (contest vazio: contas sem history) — o glob `users/*/history` falharia (cat de literal) e,
# com pipefail+set -e, abortaria o verify.
_cathist(){ find "$1/users" -name history -exec cat {} + 2>/dev/null; }

CMD="${1:-}"; shift || true
[[ -n "$CMD" ]] || die "uso: $0 {stage|verify|install|audit} ..."

FROM=""; MAP=""; STAGE=""; CDIR=""; OWNER=""
while (( $# )); do
  case "$1" in
    --from)        FROM="${2:-}"; shift 2 ;;
    --map)         MAP="${2:-}"; shift 2 ;;
    --stage)       STAGE="${2:-}"; shift 2 ;;
    --contest-dir) CDIR="${2:-}"; shift 2 ;;
    --owner)       OWNER="${2:-}"; shift 2 ;;
    *) die "opção desconhecida: $1" ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Resolve os args de caminho para ABSOLUTO enquanto o CWD ainda é o do chamador (o `cd` abaixo
# mudaria a base de um caminho relativo).
_abs(){ [[ -z "$1" || "$1" == /* ]] && { printf '%s' "$1"; return; }; printf '%s/%s' "$PWD" "$1"; }
FROM="$(_abs "$FROM")"; MAP="$(_abs "$MAP")"; STAGE="$(_abs "$STAGE")"; CDIR="$(_abs "$CDIR")"
# Garante um CWD acessível: rodado via `su moj -c ...` o CWD pode ser /root (inacessível ao
# usuário), e aí `find` sai 1 ("Failed to restore initial working directory") — com pipefail+
# set -e isso abortava o verify. Já resolvemos os caminhos p/ absoluto, então mudar de CWD é seguro.
cd "$HERE" 2>/dev/null || cd / 2>/dev/null || true

# lê CONTEST_ID/START/END/NAME/LANGUAGES/PROBS de um conf legado, num SUBSHELL isolado (o
# conf é sourced e PROBS tem nomes com espaço/aspas). Ecoa como TSV chave<TAB>valor + as
# tuplas do PROBS numeradas, p/ o chamador ler sem sourcear no seu próprio ambiente.
_read_conf(){ # <conf>
  ( set +eu +o pipefail   # o conf LEGADO é dado não-confiável. O subshell isola.
    CONTEST_ID=""; CONTEST_NAME=""; CONTEST_START=""; CONTEST_END=""; LANGUAGES=""; SCORETYPE=""; PROBS=()
    # Sourceia com todo `$` ESCAPADO: títulos têm `$k$` (LaTeX) que senão o bash expande (some,
    # e sob `set -u` aborta) — assim `$k$` fica LITERAL, preservando o título. De quebra, bloqueia
    # command substitution (`$(...)`) de um conf legado não-confiável.
    # shellcheck disable=SC1090
    source <(sed 's/\$/\\$/g' "$1") 2>/dev/null
    printf 'ID\t%s\n'    "$CONTEST_ID"
    printf 'NAME\t%s\n'  "$CONTEST_NAME"
    printf 'START\t%s\n' "$CONTEST_START"
    printf 'END\t%s\n'   "$CONTEST_END"
    printf 'LANG\t%s\n'  "$LANGUAGES"
    printf 'SCORETYPE\t%s\n' "$SCORETYPE"
    printf 'NP\t%s\n'    "${#PROBS[@]}"
    local i
    for ((i=0; i<${#PROBS[@]}; i++)); do printf 'P\t%s\t%s\n' "$i" "${PROBS[i]}"; done )
}

# ==========================================================================================
# stage
# ==========================================================================================
do_stage(){
  [[ -n "$FROM" && -n "$MAP" && -n "$STAGE" ]] || die "stage: faltam --from/--map/--stage"
  [[ -f "$FROM/conf" ]]              || die "sem $FROM/conf"
  [[ -f "$FROM/passwd" ]]            || die "sem $FROM/passwd"
  [[ -d "$FROM/submissions" ]]       || log "AVISO: sem submissions/ (contest sem submissões)"
  # history pode FALTAR (contest montado, nunca usado — 0 submissões). Trata como vazio (/dev/null):
  # o passwd cria as contas, a partição/roteamento não produzem nada, e o placar sai vazio.
  local HIST="$FROM/controle/history"
  [[ -f "$HIST" ]] || { HIST=/dev/null; log "AVISO: sem controle/history — contest sem submissões"; }
  [[ -e "$STAGE" ]] && die "staging $STAGE já existe — apague antes (é descartável)"

  local nq
  nq="$(awk -F'\t' '$4=="?"' "$MAP" | wc -l)"
  (( nq == 0 )) || die "$MAP tem $nq linha(s) com confidence='?' — audite antes"
  declare -A PMAP
  local lid pid rest
  while IFS=$'\t' read -r lid pid rest; do
    [[ -z "$lid" || "$lid" == \#* ]] && continue
    PMAP["$lid"]="$pid"
  done < "$MAP"

  # --- conf legado -> variáveis + PROBS
  local TMPD; TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' RETURN
  _read_conf "$FROM/conf" > "$TMPD/conf.tsv"
  local CID CIDLC CNAME CSTART CEND CLANG CSTYPE CTYPE NP
  CID="$(awk -F'\t' '$1=="ID"{print $2}' "$TMPD/conf.tsv")"
  CNAME="$(awk -F'\t' '$1=="NAME"{print $2}' "$TMPD/conf.tsv")"
  CSTART="$(awk -F'\t' '$1=="START"{print $2}' "$TMPD/conf.tsv")"
  CEND="$(awk -F'\t' '$1=="END"{print $2}' "$TMPD/conf.tsv")"
  CLANG="$(awk -F'\t' '$1=="LANG"{print $2}' "$TMPD/conf.tsv")"
  NP="$(awk -F'\t' '$1=="NP"{print $2}' "$TMPD/conf.tsv")"
  # CONTEST_TYPE do newmoj a partir do SCORETYPE legado: OBI (placar por pontos, com créditos
  # parciais) -> obi; qualquer outro valor / ausente -> icpc (prova/lista/absent do MOJ antigo
  # eram todos ICPC-renderizados). O build.sh mapeia CONTEST_TYPE=obi -> updatescore-obi.sh.
  CSTYPE="$(awk -F'\t' '$1=="SCORETYPE"{print $2}' "$TMPD/conf.tsv" | tr '[:upper:]' '[:lower:]')"
  CTYPE=icpc; [[ "$CSTYPE" == obi ]] && CTYPE=obi
  [[ -n "$CID" ]] || die "conf sem CONTEST_ID"
  (( NP % 5 == 0 )) || die "PROBS com tamanho $NP (não múltiplo de 5)"
  # O id do CONTEST no newmoj precisa ser MINÚSCULO: o contest é servido em <id>.<host> e o
  # regex do subdomínio (install-nginx.sh:80, moj-subdomains.conf:17) só casa [a-z0-9][a-z0-9._-]*
  # — e o cc_create:146 impõe o mesmo. O CONTEST_NAME (exibição) e os caminhos-fonte do legado
  # ficam com a caixa original; só o id/diretório vira minúsculo.
  CIDLC="$(printf '%s' "$CID" | tr '[:upper:]' '[:lower:]')"
  [[ "$CIDLC" =~ ^[a-z0-9][a-z0-9._-]{1,62}$ ]] || die "id minúsculo inválido p/ subdomínio: $CIDLC"
  [[ -z "$CDIR" || ! -e "$CDIR" ]] || die "destino $CDIR já existe — este é um create, não merge"

  # PROBS numa array local (índice -> valor)
  declare -A P
  while IFS=$'\t' read -r _ idx val; do P["$idx"]="$val"; done \
    < <(awk -F'\t' '$1=="P"{print}' "$TMPD/conf.tsv")

  # --- OFF2ID: offset -> id do newmoj (a MESMA tabela p/ conf e history) ---------------
  # SEMPRE derivar de [i+1] (barra->hash); NUNCA de [i+4] (é PDF/token). O mapa (PMAP) resolve
  # os 3 casos de [i+1]: barra cdmoj (`repo#slug`), slug-nu cdmoj (`olamundo`→`moj-problems#…`),
  # e external (source spoj-*, `JPNEU`→órfão). Órfão (ausente ou '-' no mapa) mantém o id legado.
  # O source [i] é PRESERVADO no PROBS novo (spoj-br fica spoj-br) — o sc_load ignora [i] e nada
  # re-julga; manter é mais fiel que forçar cdmoj.
  declare -A OFF2ID
  local i reposlug newid norphan=0
  : > "$TMPD/off2id.tsv"; : > "$TMPD/probs_new.tsv"; : > "$TMPD/pdfcopy.tsv"
  for ((i=0; i<NP; i+=5)); do
    reposlug="${P[$((i+1))]//\//#}"
    newid="${PMAP[$reposlug]:-}"
    if [[ -z "$newid" || "$newid" == "-" ]]; then newid="$reposlug"; norphan=$((norphan+1)); fi
    OFF2ID["$i"]="$newid"
    printf '%s\t%s\n' "$i" "$newid" >> "$TMPD/off2id.tsv"
    # tupla do PROBS novo: <source> <newid> <nome> <rótulo> <newid(skey)>
    printf '%s\t%s\t%s\t%s\n' "${P[$i]}" "$newid" "${P[$((i+2))]}" "${P[$((i+3))]}" >> "$TMPD/probs_new.tsv"
    # enunciado: PROBS[i+4] é o statement_key legado (pode faltar a extensão) -> <newid>.<ext>
    printf '%s\t%s\n' "${P[$((i+4))]}" "$newid" >> "$TMPD/pdfcopy.tsv"
  done
  log "problemas: $((NP/5)) ($norphan órfão(s) mantendo id legado); placar=$CTYPE (SCORETYPE legado='${CSTYPE:-<ausente>}')"

  local ROOT="$STAGE/$CIDLC"
  mkdir -p "$ROOT/users" "$ROOT/enunciados" "$ROOT/var"

  # --- conf novo (printf %q; CONTEST_TYPE=icpc + CONTEST_PRIORITY=prova) ----------------
  {
    printf 'CONTEST_ID=%q\n'       "$CIDLC"
    printf 'CONTEST_NAME=%q\n'     "$CNAME"
    printf 'CONTEST_TYPE=%s\n'     "$CTYPE"
    printf 'CONTEST_PRIORITY=prova\n'
    printf 'CONTEST_START=%q\n'    "$CSTART"
    printf 'CONTEST_END=%q\n'      "$CEND"
    [[ -n "$CLANG" ]] && printf 'LANGUAGES=%q\n' "$CLANG"
    # O MOJ ANTIGO penalizava Compilation Error; o newmoj (ICPC moderno) NÃO, por default.
    # P/ o placar migrado bater o que os alunos viram, penalizar CE (PENALTY_CODES_ALL inteiro).
    # Medido no piloto: com ce, 28/29 alunos batem EXATO o controle/SCORE legado; sem ce, 24/29.
    # (O 1 resíduo é quirk do legado — contava submissões PÓS-AC; o newmoj corrige, penalidade menor.)
    printf 'PENALTY_VERDICTS=%q\n' "wa tle mle rte ce"
    # PROBS: um elemento por vez, printf %q (títulos têm espaço/'/')
    printf 'PROBS=('
    while IFS=$'\t' read -r a b c d; do printf ' %q %q %q %q %q' "$a" "$b" "$c" "$d" "$b"; done < "$TMPD/probs_new.tsv"
    printf ' )\n'
  } > "$ROOT/conf"
  printf '%s\n' "${OWNER:-lucasboaventura}" > "$ROOT/owner"

  # --- enunciados (o statement_key legado varia) ----------------------------------------
  # [i+4] pode ser: <slug>.pdf, <slug> sem extensão (arquivo é <slug>.pdf/.html/.txt), token hex,
  # ou `site`/`sitepdf` (SPOJ antigo, SEM arquivo local). O newmoj serve enunciados/<skey>.{pdf,html}.
  # Tenta o nome como está, depois +.pdf/.html/.txt; copia preservando a extensão. `site*` e ausência
  # são esperados (39 contests puro-SPOJ não têm enunciado local) — não são falha.
  local srckey newid npdf=0 nomiss=0 src ext cand
  while IFS=$'\t' read -r srckey newid; do
    [[ "$srckey" == site || "$srckey" == sitepdf || -z "$srckey" ]] && { nomiss=$((nomiss+1)); continue; }
    src=""; ext=""
    for cand in "$srckey" "$srckey.pdf" "$srckey.html" "$srckey.txt"; do
      [[ -f "$FROM/enunciados/$CID/$cand" ]] && { src="$FROM/enunciados/$CID/$cand"; ext="${cand##*.}"; break; }
    done
    if [[ -n "$src" ]]; then
      [[ "$ext" == "$srckey" || -z "$ext" ]] && ext=pdf     # sem extensão detectável -> assume pdf
      [[ "$ext" == txt ]] && ext=html                        # o newmoj serve html/pdf, não txt
      cp -p "$src" "$ROOT/enunciados/$newid.$ext"; npdf=$((npdf+1))
    else nomiss=$((nomiss+1)); fi
  done < "$TMPD/pdfcopy.tsv"
  log "enunciados: $npdf copiados, $nomiss sem arquivo local (site/SPOJ antigo)"

  # --- history -> por usuário (probid via OFF2ID, tempo:=f6, 6 campos, dedup) -----------
  log "particionando o history..."
  LC_ALL=C sort -t: -k2,2 -s "$HIST" \
  | awk -F: -v root="$ROOT" -v mapf="$TMPD/off2id.tsv" '
      BEGIN{ while((getline l < mapf)>0){ i=index(l,"\t"); O[substr(l,1,i-1)]=substr(l,i+1) } }
      { n=NF; key=$(n-1)":"$n; if(key in seen){dup++; next} seen[key]=1;
        login=$2; prob=$3; if(prob in O) prob=O[prob]; else unm++;
        v=$5; for(i=6;i<=n-2;i++) v=v":"$i;
        if(login!=cur){ if(cur!="") close(out); cur=login;
                        system("mkdir -p \"" root "/users/" login "\""); out=root"/users/"login"/history" }
        # tempo := f6 (campo n-1); 6 campos tempo:probid:lang:verdict:sub_epoch:subid
        print $(n-1)":"prob":"$4":"v":"$(n-1)":"$n >> out }
      END{ if(cur!="") close(out); if(dup) printf("dedup: %d\n",dup)>"/dev/stderr"; if(unm) printf("probid sem OFF2ID: %d\n",unm)>"/dev/stderr" }'
  local h
  while IFS= read -r h; do LC_ALL=C sort -t: -k5,5n -s "$h" -o "$h"; done < <(find "$ROOT/users" -name history)
  log "history: $(_cathist "$ROOT" | wc -l) linhas em $(find "$ROOT/users" -name history | wc -l) usuários"

  # --- contas (account.json) ------------------------------------------------------------
  log "gerando account.json..."
  local nacc=0 nbad=0 login pass name f4 email first last
  while IFS=: read -r login pass name f4 _; do
    [[ -z "$login" ]] && continue
    if [[ ! "$login" =~ ^[A-Za-z0-9._@#+-]+$ || "$login" == *".."* || "$login" == -* ]]; then
      echo "  login invalido, pulado: [$login]" >&2; nbad=$((nbad+1)); continue
    fi
    email=""; [[ "$f4" == *"@"* ]] && email="$f4"
    mkdir -p "$ROOT/users/$login"
    first=0; last=0
    if [[ -s "$ROOT/users/$login/history" ]]; then
      first="$(head -1 "$ROOT/users/$login/history" | cut -d: -f5)"
      last="$(tail -1 "$ROOT/users/$login/history" | cut -d: -f5)"
    fi
    ( umask 077
      jq -cn --arg l "$login" --arg p "$pass" --arg n "$name" --arg e "$email" \
             --argjson c "${first:-0}" --argjson u "${last:-0}" \
        '{login:$l, password:$p, fullname:$n, email:$e, created_at:$c, updated_at:$u,
          status:"active", uname_changes:[]}' > "$ROOT/users/$login/account.json" )
    nacc=$((nacc+1))
  done < "$FROM/passwd"
  log "contas: $nacc criadas${nbad:+, $nbad inválidas puladas}"

  # Conta placeholder p/ dir de usuário que veio do HISTORY mas não tem conta no passwd
  # (inconsistência legada: login no history ausente do passwd — ex. `hugo.admin`, um monitor
  # que submeteu; ou `rodolpho.teza` no history vs `rodolpho_teza` no passwd, `.`≠`_`). Sem
  # isto o dir fica sem account.json e `list_users`/placar o ignoram (submissão sumiria). Senha
  # DESATIVADA (prefixo `!` — nunca casa no login); preserva a submissão no registro.
  local ghost gl ngh=0
  while IFS= read -r ghost; do
    gl="$(basename "$ghost")"
    [[ -f "$ROOT/users/$gl/account.json" ]] && continue
    first=0; last=0
    if [[ -s "$ROOT/users/$gl/history" ]]; then
      first="$(head -1 "$ROOT/users/$gl/history" | cut -d: -f5)"
      last="$(tail -1 "$ROOT/users/$gl/history" | cut -d: -f5)"
    fi
    ( umask 077
      jq -cn --arg l "$gl" --argjson c "${first:-0}" --argjson u "${last:-0}" \
        '{login:$l, password:"!", fullname:$l, email:"", created_at:$c, updated_at:$u,
          status:"active", uname_changes:[]}' > "$ROOT/users/$gl/account.json" )
    echo "  conta placeholder (login no history, ausente do passwd): $gl" >&2
    ngh=$((ngh+1))
  done < <(find "$ROOT/users" -mindepth 1 -maxdepth 1 -type d)
  (( ngh )) && log "placeholders: $ngh (login no history sem conta no passwd; senha desativada)"

  # --- submissions (roteia por f6:subid contra o history) -------------------------------
  log "roteando submissions..."
  awk -F: '{ n=NF; print $(n-1)":"$n "\t" $2 }' "$HIST" | LC_ALL=C sort -u > "$TMPD/route.tsv"
  declare -A ROUTE
  local key lg
  while IFS=$'\t' read -r key lg; do ROUTE["$key"]="$lg"; done < "$TMPD/route.tsv"
  local nfile=0 nskip=0 base ext dst sid
  while IFS= read -r base; do
    # âncora: <epoch>:<subid>-  (o marcador `accepted` e não-submissões não casam -> pulam)
    [[ "$base" =~ ^([0-9]+):([0-9a-f]{32}|[0-9a-f-]{36})- ]] || { nskip=$((nskip+1)); continue; }
    key="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
    sid="${BASH_REMATCH[2]}"
    lg="${ROUTE[$key]:-}"
    [[ -z "$lg" ]] && { echo "$base" >> "$ROOT/orphan-submissions.txt"; nskip=$((nskip+1)); continue; }
    ext="${base##*.}"; [[ "$ext" == "$base" || -z "$ext" ]] && ext="txt"
    mkdir -p "$ROOT/users/$lg/submissions"
    cp -p "$FROM/submissions/$base" "$ROOT/users/$lg/submissions/$sid.$ext"
    nfile=$((nfile+1))
  done < <(find "$FROM/submissions" -maxdepth 1 -type f -printf '%f\n')
  log "submissions: $nfile copiadas, $nskip não-âncora/sem-rota ignoradas"

  { echo "# manifesto (contest-migrate stage)"; echo "contest=$CIDLC"; echo "contest_orig=$CID"; echo "from=$FROM"
    echo "problemas=$((NP/5))"; echo "orfaos=$norphan"
    echo "history=$(_cathist "$ROOT" | wc -l)"; echo "contas=$nacc"
    echo "submissions=$nfile"; echo "pdfs=$npdf"
  } > "$ROOT/MANIFEST"
  log "staging pronto: $ROOT"
}

# ==========================================================================================
# verify — no STAGING; nada toca o prod.
# ==========================================================================================
do_verify(){
  [[ -n "$FROM" && -n "$STAGE" ]] || die "verify: faltam --from/--stage"
  local CID CIDLC; CID="$(_read_conf "$FROM/conf" | awk -F'\t' '$1=="ID"{print $2}')"
  CIDLC="$(printf '%s' "$CID" | tr '[:upper:]' '[:lower:]')"
  local ROOT="$STAGE/$CIDLC"
  [[ -f "$ROOT/conf" ]] || die "staging $ROOT sem conf (rode stage antes)"
  local rc=0
  ck(){ if [[ "$2" == "$3" ]]; then echo "  ok   $1: $2"; else echo "  FALHA $1: esperado '$3', veio '$2'"; rc=1; fi }

  echo "=== verificação do staging ($CID) ===" >&2
  local want got HIST="$FROM/controle/history"
  [[ -f "$HIST" ]] || HIST=/dev/null
  # (a) history = subids únicos do legado (dedup por f6:subid)
  want="$(awk -F: '{print $(NF-1)":"$NF}' "$HIST" | LC_ALL=C sort -u | wc -l)"
  got="$(_cathist "$ROOT" | wc -l)"
  ck "history (subids unicos do legado)" "$got" "$want"
  # (b) NF=6
  got="$(_cathist "$ROOT" | awk -F: 'NF!=6' | wc -l)"; ck "history NF!=6" "$got" "0"
  # (c) tempo == sub_epoch
  got="$(_cathist "$ROOT" | awk -F: '$1!=$5' | wc -l)"; ck "tempo != sub_epoch" "$got" "0"
  # (d) TODO probid do history está no SC_CANON do conf novo (senão a célula some do placar)
  # SC_CANON = derivação do sc_load a partir do PROBS do conf novo
  ( PROBS=(); source "$ROOT/conf" 2>/dev/null
    for ((i=0;i<${#PROBS[@]};i+=5)); do c="${PROBS[i+4]:-}"; [[ "$c" == *"#"* ]] || c="${PROBS[i+1]//\//#}"; echo "$c"; done ) \
    | LC_ALL=C sort -u > "$STAGE/.sc_canon.$$"
  _cathist "$ROOT" | awk -F: '{print $2}' | LC_ALL=C sort -u > "$STAGE/.hprobs.$$"
  got="$(comm -23 "$STAGE/.hprobs.$$" "$STAGE/.sc_canon.$$" | wc -l)"
  ck "probid do history fora do SC_CANON" "$got" "0"
  rm -f "$STAGE/.sc_canon.$$" "$STAGE/.hprobs.$$"
  # (e) submissões = subids únicos do history; sem colisão
  got="$(find "$ROOT/users" -path '*/submissions/*' -type f 2>/dev/null | wc -l)"
  ck "submissions copiadas" "$got" "$want"
  got="$(find "$ROOT/users" -path '*/submissions/*' -type f -printf '%f\n' 2>/dev/null | sed 's/\.[^.]*$//' | LC_ALL=C sort | uniq -d | wc -l)"
  ck "subid duplicado no staging" "$got" "0"
  # (f) TODO login válido do passwd tem account.json (cobertura; o total de contas pode ser
  # MAIOR que o passwd por causa dos placeholders de ghost — por isso não é igualdade de contagem)
  local nmiss=0 pl
  while IFS= read -r pl; do [[ -f "$ROOT/users/$pl/account.json" ]] || nmiss=$((nmiss+1)); done \
    < <(awk -F: 'NF>=3 && $1!="" && $1 ~ /^[A-Za-z0-9._@#+-]+$/ && $1 !~ /\.\./ {print $1}' "$FROM/passwd" | LC_ALL=C sort -u)
  ck "logins do passwd sem conta" "$nmiss" "0"
  # (g) todo dir de usuário tem account.json (senão list_users ignora)
  got=0; local d
  for d in "$ROOT"/users/*/; do [[ -f "$d/account.json" ]] || { echo "  sem account.json: $(basename "$d")"; got=$((got+1)); }; done
  ck "dir sem account.json" "$got" "0"
  # (h) arquivos de submissão SEM linha no history = leftovers legados (o aluno submeteu, o
  # history NÃO registrou; conferido: o subid não existe no history sob nenhum f6). O history
  # é a fonte da verdade — esses arquivos não são referenciados por ninguém, então são
  # ignorados (não copiados). INFORMATIVO, não falha: o check (e) já garante que TODA submissão
  # DO HISTORY tem arquivo. Falhar aqui barraria contests sãos por lixo de log antigo.
  got=0; [[ -f "$ROOT/orphan-submissions.txt" ]] && got="$(wc -l < "$ROOT/orphan-submissions.txt")"
  (( got > 0 )) && echo "  info  $got arquivo(s) de submissão sem linha no history (leftover legado, ignorados)"

  echo >&2
  (( rc == 0 )) && echo "VERIFICAÇÃO OK — pode instalar" >&2 || echo "VERIFICAÇÃO FALHOU" >&2
  return $rc
}

# ==========================================================================================
# install — publica com UM mv -T; recomputa metrics/placar.
# ==========================================================================================
do_install(){
  [[ -n "$STAGE" && -n "$CDIR" ]] || die "install: faltam --stage/--contest-dir"
  local ROOT CID
  CID="$(basename "$CDIR")"
  ROOT="$STAGE/$CID"
  [[ -f "$ROOT/MANIFEST" ]] || die "staging $ROOT sem MANIFEST (rode stage antes)"
  [[ -e "$CDIR" ]] && die "destino $CDIR já existe — create não sobrescreve"

  # ownership/modos antes de publicar
  chmod 755 "$ROOT" "$ROOT/users" 2>/dev/null || true
  find "$ROOT/users" -name account.json -exec chmod 600 {} + 2>/dev/null || true
  find "$ROOT/users" -name history -exec chmod 600 {} + 2>/dev/null || true

  mv -T "$ROOT" "$CDIR"
  log "publicado: $CDIR"

  # metrics + placar: o build.sh recomputa todos os metrics quando falta o stamp
  local CONTESTSDIR; CONTESTSDIR="$(dirname "$CDIR")"; export CONTESTSDIR
  rm -f "$CDIR/var/.metrics-stamp" "$CDIR/var/problem-panorama.json" 2>/dev/null || true
  mkdir -p "$CDIR/var"; touch "$CDIR/var/.score-dirty"
  log "rodando build.sh $CID..."
  CONTESTSDIR="$CONTESTSDIR" bash "$HERE/../score/build.sh" "$CID" >&2 || log "AVISO: build.sh falhou (verifique)"
  log "instalado. placar: $CDIR/var/placar.txt"
}

# ==========================================================================================
# audit — o contest instalado vs o legado.
# ==========================================================================================
do_audit(){
  [[ -n "$FROM" && -n "$CDIR" ]] || die "audit: faltam --from/--contest-dir"
  local rc=0
  ck(){ if [[ "$2" == "$3" ]]; then echo "  ok   $1: $2"; else echo "  FALHA $1: esperado '$3', veio '$2'"; rc=1; fi }
  echo "=== auditoria do contest instalado ($(basename "$CDIR")) ===" >&2
  local want got HIST="$FROM/controle/history"
  [[ -f "$HIST" ]] || HIST=/dev/null
  want="$(awk -F: '{print $NF}' "$HIST" | LC_ALL=C sort -u | wc -l)"
  got="$(_cathist "$CDIR" | awk -F: '{print $NF}' | LC_ALL=C sort -u \
        | comm -12 - <(awk -F: '{print $NF}' "$HIST" | LC_ALL=C sort -u) | wc -l)"
  ck "subids do legado presentes" "$got" "$want"
  got="$(_cathist "$CDIR" | awk -F: 'NF!=6' | wc -l)"; ck "history NF!=6" "$got" "0"
  got="$(_cathist "$CDIR" | awk -F: '{print $NF}' | LC_ALL=C sort | uniq -d | wc -l)"; ck "subid duplicado" "$got" "0"
  local d n=0; for d in "$CDIR"/users/*/; do [[ -f "$d/account.json" ]] || n=$((n+1)); done
  ck "conta sem account.json" "$n" "0"
  [[ -f "$CDIR/var/placar.txt" ]] && ck "placar existe (linha 1 = modo)" "$(head -1 "$CDIR/var/placar.txt")" "icpc"
  echo >&2
  (( rc == 0 )) && echo "AUDITORIA OK" >&2 || echo "AUDITORIA FALHOU" >&2
  return $rc
}

case "$CMD" in
  stage)   do_stage ;;
  verify)  do_verify ;;
  install) do_install ;;
  audit)   do_audit ;;
  *) die "comando desconhecido: $CMD (use stage|verify|install|audit)" ;;
esac
