#!/usr/bin/env bash
#
# treino-migrate.sh — migra o contest "treino" do MOJ ANTIGO (passwd + controle/history +
# submissions/ flat) para o store por-usuário do newmoj, FUNDINDO num contest que já está
# no ar (não pode recriar: o prod já tem contas, orgs.json, índice de telegram etc).
#
#   treino-migrate.sh stage   --from <legacy> --map <tsv> --accounts <tsv> \
#                             --contest-dir <contests/treino do prod> --stage <dir>
#   treino-migrate.sh verify  --from <legacy> --contest-dir <dir> --stage <dir>
#   treino-migrate.sh install --contest-dir <dir> --stage <dir> [--contest treino]
#
# Por que não o store-migrate.sh: ele aborta se o destino existe, faz `mv -T` do contest
# inteiro (apagaria as contas vivas), monta o canon.map do `PROBS` do conf (o treino não tem
# PROBS), muta a origem in-place (não dá p/ reexecutar) e escreve o telegram sem tg_link.
#
# Princípios:
#   - A ORIGEM é read-only. O staging é descartável: se a verificação falhar, apaga e refaz.
#   - `stage` e `verify` NÃO tocam no prod. Só `install` escreve — e a unidade atômica é o
#     DIRETÓRIO do usuário (`mv`), nunca o contest.
#   - Conta que já existe no prod NÃO é recriada: só ganha history/submissions (append).
#
# Fatos do legado que o código assume (todos medidos no backup de 2026-07-16):
#   - history = 7 campos `f1:login:probid:LANG:verdict:f6:subid`, NF=7 em 100% das linhas.
#   - f1 é LIXO em 617 linhas (offset, chega a -166985). f6 é o epoch real e indexa 100%
#     das submissions. Não existe UMA linha com f1 >= 1e9 e f1 != f6 -> `tempo := f6` é
#     lossless e ainda repara as 617. É também o que o escritor vivo faz (judged.sh:436-445:
#     sem CONTEST_START, tempo = sub_epoch; o treino não tem CONTEST_START).
#   - 1 linha duplicada de verdade (mesma f6:subid) -> dedup por essa chave.
#   - submissions/ = `<f6>:<subid>-<login>-<probid>.<ext>`, MAS 145 arquivos têm o probid
#     numérico (`-thgomxs-1000.c`) em vez de `repo#slug`, e `-` ocorre dentro de uuid, login
#     e slug. Por isso o roteamento é pela chave `f6:subid` casada contra o HISTORY, e do
#     nome só se aproveita a extensão. Nunca faça split por `-`.
#   - 140 arquivos terminam em `.` (sem extensão; são os 118 vereditos "Language 'unknown'
#     not availale"). Viram `<subid>.txt`: `resolve_submission` (users.sh) globa `<sid>.*` e
#     um arquivo sem ponto ficaria INACESSÍVEL para sempre.

set -euo pipefail
export LC_ALL=C

die(){ echo "treino-migrate: $*" >&2; exit 1; }
log(){ echo "  $*" >&2; }

CMD="${1:-}"; shift || true
[[ -n "$CMD" ]] || die "uso: $0 {stage|verify|install} ..."

FROM=""; MAP=""; ACCOUNTS=""; CDIR=""; STAGE=""; CONTEST="treino"
while (( $# )); do
  case "$1" in
    --from)        FROM="${2:-}"; shift 2 ;;
    --map)         MAP="${2:-}"; shift 2 ;;
    --accounts)    ACCOUNTS="${2:-}"; shift 2 ;;
    --contest-dir) CDIR="${2:-}"; shift 2 ;;
    --stage)       STAGE="${2:-}"; shift 2 ;;
    --contest)     CONTEST="${2:-}"; shift 2 ;;
    *) die "opção desconhecida: $1" ;;
  esac
done

# ==========================================================================================
# stage
# ==========================================================================================
do_stage(){
  [[ -n "$FROM" && -n "$MAP" && -n "$ACCOUNTS" && -n "$CDIR" && -n "$STAGE" ]] \
    || die "stage: faltam --from/--map/--accounts/--contest-dir/--stage"
  [[ -f "$FROM/passwd" ]]            || die "sem $FROM/passwd"
  [[ -f "$FROM/controle/history" ]]  || die "sem $FROM/controle/history"
  [[ -d "$FROM/submissions" ]]       || die "sem $FROM/submissions"
  [[ -d "$CDIR/users" ]]             || die "sem $CDIR/users (o contest do prod)"
  [[ -e "$STAGE" ]] && die "staging $STAGE já existe — apague antes (é descartável)"

  # --- mapa de problemas. Qualquer '?' = auditoria incompleta -> RECUSA.
  local nq
  nq="$(awk -F'\t' '$4=="?"' "$MAP" | wc -l)"
  (( nq == 0 )) || die "$MAP tem $nq linha(s) com confidence='?' — audite antes (o mapa é o contrato)"
  declare -A PMAP
  local lid pid rest
  while IFS=$'\t' read -r lid pid rest; do
    [[ -z "$lid" || "$lid" == \#* ]] && continue
    PMAP["$lid"]="$pid"
  done < "$MAP"
  log "mapa: ${#PMAP[@]} problemas"

  # --- mapa de contas
  declare -A AMAP
  local ll pl note
  while IFS=$'\t' read -r ll pl note; do
    [[ -z "$ll" || "$ll" == \#* ]] && continue
    AMAP["$ll"]="$pl"
  done < "$ACCOUNTS"
  log "contas remapeadas: ${#AMAP[@]}"

  # --- contas que JÁ existem no prod (não recriar: a senha do prod prevalece)
  declare -A INPROD
  local u
  while IFS= read -r u; do [[ -n "$u" ]] && INPROD["$u"]=1; done < <(ls -1 "$CDIR/users" 2>/dev/null)
  log "contas já no prod: ${#INPROD[@]}"

  mkdir -p "$STAGE"/{users,telegram/by-tgid,telegram/by-login}

  # --- 1) history -> por usuário -------------------------------------------------------
  # Dedup por f6:subid; probid pelo mapa (órfão mantém o id legado); login pelo mapa de
  # contas. Particiona ordenando por login (um fd por vez, como o store-migrate.sh).
  log "particionando o history..."
  local TMPD; TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' RETURN
  {
    printf '%s\n' "${!PMAP[@]}" | while IFS= read -r k; do printf 'P\t%s\t%s\n' "$k" "${PMAP[$k]}"; done
    printf '%s\n' "${!AMAP[@]}" | while IFS= read -r k; do printf 'A\t%s\t%s\n' "$k" "${AMAP[$k]}"; done
  } > "$TMPD/maps.tsv"

  awk -F'\t' 'NR==FNR { if($1=="P") pm[$2]=$3; else if($1=="A") am[$2]=$3; next }
    { n=split($0, f, ":");
      # dedup por f6:subid (a chave real; f1 é lixo em 617 linhas)
      key = f[n-1] ":" f[n];
      if (key in seen) { dup++; next } seen[key]=1;
      login = f[2]; if (login in am) login = am[login];
      prob  = f[3]; if (prob in pm && pm[prob] != "-") prob = pm[prob];
      # verdict = campos 5..n-2 (nunca contém ":", mas parseamos pelas PONTAS mesmo assim)
      v = f[5]; for (i = 6; i <= n-2; i++) v = v ":" f[i];
      # tempo := f6 (NÃO f1)
      printf "%s\t%s:%s:%s:%s:%s:%s\n", login, f[n-1], prob, f[4], v, f[n-1], f[n];
    }
    END { if (dup) printf("dedup: %d linha(s) duplicada(s) descartada(s)\n", dup) > "/dev/stderr" }' \
    "$TMPD/maps.tsv" FS=":" "$FROM/controle/history" \
  | LC_ALL=C sort -t$'\t' -k1,1 -s > "$TMPD/hist.tsv"

  awk -F'\t' -v stage="$STAGE" '
    { if ($1 != cur) { if (cur != "") close(out); cur = $1; out = stage "/users/" cur "/history";
                       system("mkdir -p \"" stage "/users/" cur "\"") }
      print $2 >> out }
    END { if (cur != "") close(out) }' "$TMPD/hist.tsv"

  # ordena cada history por sub_epoch (campo 5)
  local h
  while IFS= read -r h; do
    LC_ALL=C sort -t: -k5,5n -s "$h" -o "$h"
  done < <(find "$STAGE/users" -name history)
  log "history: $(cat "$STAGE"/users/*/history | wc -l) linhas em $(find "$STAGE/users" -name history | wc -l) usuários"

  # --- 2) contas ------------------------------------------------------------------------
  # passwd legado: login:senha:nome:campo4  (campo4 = telegram numérico | email com @ | vazio)
  # Decisão do Ribas: telegram vai p/ var/telegram, email vai p/ .email. NUNCA os dois no
  # .email (foi o que contaminou 826 contas na migração do dev).
  log "gerando account.json..."
  local nnew=0 nmerge=0 ntg=0 nbad=0 ndup=0
  local login pass name f4 target email first last
  declare -A WROTE
  while IFS=: read -r login pass name f4 _; do
    [[ -z "$login" ]] && continue
    # valid_login do store-migrate.sh:59 == o charset do valid_id da API (common.sh) — é o
    # mesmo que o verify_password usa ANTES de montar o caminho. Sem esta trava, 7 passwd do
    # backup (com linhas de conf coladas, tipo LANGUAGES="C") viravam CONTA.
    if [[ ! "$login" =~ ^[A-Za-z0-9._@#+-]+$ || "$login" == *".."* || "$login" == -* ]]; then
      echo "  login invalido, pulado: [$login]" >&2; nbad=$((nbad+1)); continue
    fi
    target="${AMAP[$login]:-$login}"

    # Dois logins legados p/ o MESMO alvo INEXISTENTE no prod: sem isto o 2º sobrescrevia o
    # account.json do 1º e a senha virava a de quem viesse por último na ordem do passwd.
    # (No treino não deu: os 7 alvos já existiam ⇒ caíram no merge. É armadilha p/ os outros.)
    if [[ -z "${INPROD[$target]:-}" && -n "${WROTE[$target]:-}" ]]; then
      echo "  '$login' e '${WROTE[$target]}' apontam p/ '$target' (inexistente no prod): mantendo o 1º" >&2
      ndup=$((ndup+1)); continue
    fi

    # telegram: só campo4 numérico
    if [[ "$f4" =~ ^[0-9]+$ ]]; then
      printf '%s\n' "$f4" > "$STAGE/telegram/by-login/$target"
      printf '%s\t%s\n' "$f4" "$target" >> "$STAGE/telegram/pairs.tsv"
      ntg=$((ntg+1))
    fi
    email=""; [[ "$f4" == *"@"* ]] && email="$f4"

    if [[ -n "${INPROD[$target]:-}" ]]; then nmerge=$((nmerge+1)); continue; fi

    mkdir -p "$STAGE/users/$target"
    # created/updated = 1ª e última submissão (melhor que o 0 fixo do store-migrate.sh)
    first=0; last=0
    if [[ -s "$STAGE/users/$target/history" ]]; then
      first="$(head -1 "$STAGE/users/$target/history" | cut -d: -f5)"
      last="$(tail -1 "$STAGE/users/$target/history" | cut -d: -f5)"
    fi
    ( umask 077
      jq -cn --arg l "$target" --arg p "$pass" --arg n "$name" --arg e "$email" \
             --argjson c "${first:-0}" --argjson u "${last:-0}" \
        '{login:$l, password:$p, fullname:$n, email:$e, created_at:$c, updated_at:$u,
          status:"active", uname_changes:[]}' > "$STAGE/users/$target/account.json" )
    WROTE["$target"]="$login"
    nnew=$((nnew+1))
  done < "$FROM/passwd"
  log "contas: $nnew novas, $nmerge fundidas em conta existente, $ntg telegram"
  (( nbad ))  && log "AVISO: $nbad login(s) invalido(s) pulado(s)"
  (( ndup ))  && log "AVISO: $ndup login(s) colidindo no mesmo alvo (1o venceu)"

  # Diretório de usuário SEM account.json é fantasma: `list_users` (users.sh) só enxerga quem
  # tem account.json, então metrics/placar ignorariam essas submissões — mas o `cat users/*/
  # history` do verify as contaria, fechando a soma e mascarando a perda. Acontece quando o
  # history cita login que não está no passwd (20 contests do backup têm isso).
  local nghost=0 g
  while IFS= read -r g; do
    [[ -f "$STAGE/users/$g/account.json" || -n "${INPROD[$g]:-}" ]] && continue
    echo "  FANTASMA (history sem conta no passwd): $g" >&2
    nghost=$((nghost+1))
  done < <(ls -1 "$STAGE/users" 2>/dev/null)
  (( nghost )) && log "AVISO: $nghost diretorio(s) sem account.json — o verify vai barrar"

  # --- 3) submissions -------------------------------------------------------------------
  # Roteia pela chave f6:subid contra o history (o nome do arquivo NÃO é confiável: 145 têm
  # probid numérico e o '-' ocorre dentro de uuid/login/slug).
  log "roteando submissions..."
  awk -F'\t' 'NR==FNR { if($1=="A") am[$2]=$3; next }
    { n=split($0, f, ":"); login=f[2]; if(login in am) login=am[login];
      print f[n-1] ":" f[n] "\t" login "\t" f[n] }' \
    "$TMPD/maps.tsv" FS=":" "$FROM/controle/history" | LC_ALL=C sort -u > "$TMPD/route.tsv"

  declare -A ROUTE SUBID
  local key lg sid
  while IFS=$'\t' read -r key lg sid; do ROUTE["$key"]="$lg"; SUBID["$key"]="$sid"; done < "$TMPD/route.tsv"

  local nfile=0 nmiss=0 base ext dst
  while IFS= read -r base; do
    # âncora: <epoch>:<md5|uuid>-  (todos os 14.658 casam)
    [[ "$base" =~ ^([0-9]+):([0-9a-f]{32}|[0-9a-f-]{36})- ]] || { nmiss=$((nmiss+1)); continue; }
    key="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
    lg="${ROUTE[$key]:-}"
    [[ -z "$lg" ]] && { nmiss=$((nmiss+1)); echo "$base" >> "$STAGE/orphan-submissions.txt"; continue; }
    sid="${SUBID[$key]}"
    ext="${base##*.}"
    # sem extensão (o legado grava "...#slug.") -> .txt, senão resolve_submission nunca acha
    [[ "$ext" == "$base" || -z "$ext" ]] && ext="txt"
    dst="$STAGE/users/$lg/submissions/$sid.$ext"
    mkdir -p "$STAGE/users/$lg/submissions"
    cp -p "$FROM/submissions/$base" "$dst"
    nfile=$((nfile+1))
  done < <(ls -1 "$FROM/submissions")
  log "submissions: $nfile copiadas, $nmiss sem rota"

  # --- 4) manifesto ---------------------------------------------------------------------
  { echo "# manifesto do staging (gerado por treino-migrate.sh stage)"
    echo "from=$FROM"; echo "map=$MAP"; echo "accounts=$ACCOUNTS"; echo "contest_dir=$CDIR"
    echo "users_novos=$nnew"; echo "users_fundidos=$nmerge"
    echo "history_linhas=$(cat "$STAGE"/users/*/history 2>/dev/null | wc -l)"
    echo "submissions=$nfile"; echo "telegram=$ntg"
  } > "$STAGE/MANIFEST"
  log "staging pronto: $STAGE"
}

# ==========================================================================================
# verify — roda no STAGING; nada aqui toca o prod. Falhou => não instale.
# ==========================================================================================
do_verify(){
  [[ -n "$FROM" && -n "$CDIR" && -n "$STAGE" ]] || die "verify: faltam --from/--contest-dir/--stage"
  local rc=0
  ck(){ if [[ "$2" == "$3" ]]; then echo "  ok   $1: $2"; else echo "  FALHA $1: esperado '$3', veio '$2'"; rc=1; fi }

  echo "=== verificação do staging ===" >&2

  # (a) history: soma == linhas únicas do legado
  local want got
  want="$(cut -d: -f6,7 "$FROM/controle/history" | LC_ALL=C sort -u | wc -l)"
  got="$(cat "$STAGE"/users/*/history 2>/dev/null | wc -l)"
  ck "history (linhas unicas do legado)" "$got" "$want"

  # (b) todo history novo tem 6 campos
  got="$(cat "$STAGE"/users/*/history 2>/dev/null | awk -F: 'NF!=6' | wc -l)"
  ck "history com NF!=6" "$got" "0"

  # (c) campo1 == campo5 (tempo := f6) em todas
  got="$(cat "$STAGE"/users/*/history 2>/dev/null | awk -F: '$1!=$5' | wc -l)"
  ck "history com tempo!=sub_epoch" "$got" "0"

  # (d) submissions: uma por linha de history
  got="$(find "$STAGE/users" -path '*/submissions/*' -type f 2>/dev/null | wc -l)"
  want="$(ls -1 "$FROM/submissions" | wc -l)"
  ck "submissions copiadas" "$got" "$want"

  # (e) nenhum subid colide com o prod (resolve_submission globa users/*/submissions/<sid>.*
  #     — subid repetido entre usuários faria a fonte de um vazar para o outro)
  local a b
  a="$(find "$STAGE/users" -path '*/submissions/*' -type f -printf '%f\n' 2>/dev/null | sed 's/\.[^.]*$//' | LC_ALL=C sort -u)"
  b="$(find "$CDIR/users" -path '*/submissions/*' -type f -printf '%f\n' 2>/dev/null | sed 's/\.[^.]*$//' | LC_ALL=C sort -u)"
  got="$(comm -12 <(printf '%s\n' "$a") <(printf '%s\n' "$b") | wc -l)"
  ck "subid colidindo com o prod" "$got" "0"

  # (f) subid duplicado DENTRO do staging
  got="$(find "$STAGE/users" -path '*/submissions/*' -type f -printf '%f\n' 2>/dev/null | sed 's/\.[^.]*$//' | LC_ALL=C sort | uniq -d | wc -l)"
  ck "subid duplicado no staging" "$got" "0"

  # (g) account.json: nenhum p/ conta que já existe no prod (a senha do prod prevalece)
  local n=0 u
  while IFS= read -r u; do
    [[ -f "$STAGE/users/$u/account.json" ]] && { echo "  FALHA: staging recriaria $u"; n=$((n+1)); }
  done < <(ls -1 "$CDIR/users")
  ck "account.json sobrescrevendo conta viva" "$n" "0"

  # (h) account.json válido e com o login batendo o diretório
  got="$(find "$STAGE/users" -name account.json -print0 2>/dev/null \
        | xargs -0 -r -n 50 jq -r 'select((.login|type)!="string" or (.password|type)!="string") | .login' 2>/dev/null | wc -l)"
  ck "account.json invalido" "$got" "0"

  # (i) telegram: nenhum tgid p/ dois logins (1 Telegram = no máx 1 conta — telegram.sh:8)
  if [[ -f "$STAGE/telegram/pairs.tsv" ]]; then
    got="$(awk -F'\t' '{ if (($1 in m) && m[$1] != $2) bad[$1]=1; m[$1]=$2 }
                       END { print length(bad)+0 }' "$STAGE/telegram/pairs.tsv")"
    ck "tgid apontando p/ 2 logins" "$got" "0"
  fi

  # (j) o vínculo VIVO do ribas.admin tem de sobreviver
  local cur new
  cur="$(cat "$CDIR/var/telegram/by-login/ribas.admin" 2>/dev/null || true)"
  new="$(cat "$STAGE/telegram/by-login/ribas.admin" 2>/dev/null || true)"
  if [[ -n "$cur" ]]; then ck "telegram do ribas.admin preservado" "${new:-$cur}" "$cur"; fi

  # (k) nenhuma submissão sem rota
  got=0; [[ -f "$STAGE/orphan-submissions.txt" ]] && got="$(wc -l < "$STAGE/orphan-submissions.txt")"
  ck "submissions sem rota" "$got" "0"

  # (l) nenhum dir de usuário FANTASMA (sem account.json e sem conta no prod). `list_users` só
  #     vê quem tem account.json ⇒ metrics/placar perderiam essas submissões em silêncio,
  #     enquanto o check (a) — que usa o glob — fecharia a soma e diria OK.
  local nghost=0 g
  while IFS= read -r g; do
    [[ -f "$STAGE/users/$g/account.json" || -d "$CDIR/users/$g" ]] && continue
    echo "  FALHA: dir sem account.json: $g"; nghost=$((nghost+1))
  done < <(ls -1 "$STAGE/users" 2>/dev/null)
  ck "dir de usuario sem account.json" "$nghost" "0"

  # (m) todo login do staging passa o valid_id da API (senão o verify_password nem chega ao
  #     account.json e a conta fica inacessível)
  got="$(ls -1 "$STAGE/users" 2>/dev/null | awk '!/^[A-Za-z0-9._@#+-]+$/ || /\.\./' | wc -l)"
  ck "login invalido p/ a API" "$got" "0"

  echo >&2
  (( rc == 0 )) && echo "VERIFICAÇÃO OK — pode instalar" >&2 || echo "VERIFICAÇÃO FALHOU — NÃO instale" >&2
  return $rc
}

# ==========================================================================================
# install — a única fase que escreve no prod.
# ==========================================================================================
do_install(){
  [[ -n "$CDIR" && -n "$STAGE" ]] || die "install: faltam --contest-dir/--stage"
  [[ -f "$STAGE/MANIFEST" ]] || die "staging sem MANIFEST — rode 'stage' antes"

  local HERE; HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  CONTESTSDIR="$(dirname "$CDIR")"; export CONTESTSDIR
  # shellcheck disable=SC1091
  source "$HERE/../api/v1/lib/telegram.sh"

  local nnew=0 nmerge=0 u
  while IFS= read -r u; do
    if [[ -d "$CDIR/users/$u" ]]; then
      # MERGE: conta viva. Só acrescenta; account.json e senha do prod ficam.
      # Dedup por subid (último campo): sem isto, rodar o install duas vezes DUPLICA o
      # history da conta em silêncio (o ribas.admin ia de 36 p/ 63 linhas).
      if [[ -f "$STAGE/users/$u/history" ]]; then
        local tmp cur_h; tmp="$(mktemp)"
        # Conta viva pode NÃO ter history (quem nunca submeteu): 377 das 936 do treino não têm.
        # awk num arquivo inexistente é erro FATAL (exit 2) e, sob `set -e`, abortaria o
        # install NO MEIO do laço — metade dos usuários já movidos, telegram e stamps por
        # fazer. /dev/null dá o mesmo resultado (nenhum subid conhecido) sem morrer.
        cur_h="$CDIR/users/$u/history"; [[ -f "$cur_h" ]] || cur_h=/dev/null
        # NÃO use NR==FNR aqui: o history do prod é VAZIO em 6 dos 7 alvos de merge, e com o
        # 1º arquivo sem registros o NR==FNR continua verdadeiro no 2º — o awk engoliria o
        # history inteiro como chave "seen" e não sairia NADA (some em silêncio: 86 linhas).
        # FILENAME é a comparação que não depende de o 1º arquivo ter conteúdo.
        awk -F: -v cur="$cur_h" \
            'FILENAME==cur { seen[$NF]=1; next } !($NF in seen)' \
            "$cur_h" "$STAGE/users/$u/history" > "$tmp"
        cat "$tmp" >> "$CDIR/users/$u/history"
        rm -f "$tmp"
        LC_ALL=C sort -t: -k5,5n -s -o "$CDIR/users/$u/history" "$CDIR/users/$u/history"
        chmod 600 "$CDIR/users/$u/history"
      fi
      if [[ -d "$STAGE/users/$u/submissions" ]]; then
        mkdir -p "$CDIR/users/$u/submissions"
        cp -rpn "$STAGE/users/$u/submissions/." "$CDIR/users/$u/submissions/"
      fi
      nmerge=$((nmerge+1))
    else
      # NOVA: `mv` do dir inteiro — atômico no mesmo FS.
      mv -T "$STAGE/users/$u" "$CDIR/users/$u"
      chmod 755 "$CDIR/users/$u"
      [[ -f "$CDIR/users/$u/account.json" ]] && chmod 600 "$CDIR/users/$u/account.json"
      [[ -f "$CDIR/users/$u/history" ]] && chmod 600 "$CDIR/users/$u/history"
      [[ -d "$CDIR/users/$u/submissions" ]] && chmod 755 "$CDIR/users/$u/submissions"
      nnew=$((nnew+1))
    fi
  done < <(ls -1 "$STAGE/users")
  log "instaladas: $nnew novas, $nmerge fundidas"

  # telegram: via tg_link (flock + recusa tgid de OUTRO login). Se já está vinculado ao MESMO
  # login, PULA: o tg_link reescreveria o registro e perderia o @username/linked_at do prod.
  local ntg=0 nskip=0 nconf=0 tgid lg cur
  if [[ -f "$STAGE/telegram/pairs.tsv" ]]; then
    while IFS=$'\t' read -r tgid lg; do
      [[ -z "$tgid" || -z "$lg" ]] && continue
      # `|| true`: tg_login_of_id/tg_id_of_login saem 1 quando não há vínculo (o caso normal
      # aqui) — as libs da API não rodam sob `set -e`, este script roda.
      cur="$(tg_login_of_id "$CONTEST" "$tgid" || true)"
      if [[ "$cur" == "$lg" ]]; then nskip=$((nskip+1)); continue; fi
      if [[ -n "$cur" ]]; then
        echo "  CONFLITO: tgid $tgid já é de '$cur', não de '$lg' — pulado" >&2; nconf=$((nconf+1)); continue
      fi
      # O tg_link só recusa tgid de OUTRO login; o by-login/<login> ele reescreve SEMPRE. Se a
      # conta já tem um telegram VIVO (cadastro web-first no newmoj) e o passwd legado traz um
      # tgid antigo, o vínculo bom seria trocado pelo velho — e a recuperação de senha passaria
      # a mandar a senha por DM p/ o dono do tgid ANTIGO. Vínculo vivo manda.
      local curtg; curtg="$(tg_id_of_login "$CONTEST" "$lg" || true)"
      if [[ -n "$curtg" && "$curtg" != "$tgid" ]]; then
        echo "  CONFLITO: '$lg' já tem o telegram $curtg (vivo); o legado dizia $tgid — preservado o vivo" >&2
        nconf=$((nconf+1)); continue
      fi
      tg_link "$CONTEST" "$tgid" "$lg" "" "passwd-migration" && ntg=$((ntg+1)) || true
    done < "$STAGE/telegram/pairs.tsv"
  fi
  log "telegram: $ntg vinculados, $nskip já vinculados (preservados), $nconf conflitos"

  # metrics + placar + lista: o caminho suportado p/ contest importado/backfill é apagar o
  # stamp — build.sh:93-100 recomputa TODOS os metrics quando ele falta.
  rm -f "$CDIR/var/.metrics-stamp" "$CDIR/var/problem-panorama.json"
  touch "$CDIR/var/.score-dirty" "$CDIR/var/.treino-list-dirty"
  log "stamps invalidados — rode: bash $HERE/../score/build.sh $CONTEST"
}

# ==========================================================================================
# audit — confere o contest JÁ INSTALADO contra o legado.
#
# O `verify` olha o staging; ele não veria um bug do próprio install. E foi o que aconteceu:
# o merge perdia 86 linhas (NR==FNR com arquivo vazio) e o staging estava perfeito. Este
# comando fecha esse buraco: compara o que ESTÁ NO PROD com a fonte.
# ==========================================================================================
do_audit(){
  [[ -n "$FROM" && -n "$CDIR" ]] || die "audit: faltam --from/--contest-dir"
  local rc=0
  ck(){ if [[ "$2" == "$3" ]]; then echo "  ok   $1: $2"; else echo "  FALHA $1: esperado '$3', veio '$2'"; rc=1; fi }

  echo "=== auditoria do contest instalado ===" >&2

  # (a) toda submissão do legado tem de estar no history do prod, pelo subid
  local want got
  want="$(cut -d: -f7 "$FROM/controle/history" | LC_ALL=C sort -u | wc -l)"
  got="$(cat "$CDIR"/users/*/history 2>/dev/null | awk -F: '{print $NF}' | LC_ALL=C sort -u \
        | comm -12 - <(cut -d: -f7 "$FROM/controle/history" | LC_ALL=C sort -u) | wc -l)"
  ck "subids do legado presentes no prod" "$got" "$want"

  # (b) e o arquivo-fonte de cada uma
  got="$(find "$CDIR/users" -path '*/submissions/*' -type f -printf '%f\n' 2>/dev/null \
        | sed 's/\.[^.]*$//' | LC_ALL=C sort -u \
        | comm -12 - <(cut -d: -f7 "$FROM/controle/history" | LC_ALL=C sort -u) | wc -l)"
  ck "fontes do legado presentes no prod" "$got" "$want"

  # (c) nenhuma linha duplicada (subid repetido no mesmo usuário) — pega install rodado 2x
  got="$(cat "$CDIR"/users/*/history 2>/dev/null | awk -F: '{print $NF}' | LC_ALL=C sort | uniq -d | wc -l)"
  ck "subid duplicado no history" "$got" "0"

  # (d) formato
  got="$(cat "$CDIR"/users/*/history 2>/dev/null | awk -F: 'NF!=6' | wc -l)"
  ck "history com NF!=6" "$got" "0"
  got="$(cat "$CDIR"/users/*/history 2>/dev/null | awk -F: '$1!=$5' | wc -l)"
  ck "history com tempo!=sub_epoch" "$got" "0"

  # (e) toda conta do legado existe (com o login remapeado) e a senha bate
  if [[ -n "$ACCOUNTS" ]]; then
    declare -A AM; local ll pl note
    while IFS=$'\t' read -r ll pl note; do [[ -z "$ll" || "$ll" == \#* ]] && continue; AM["$ll"]="$pl"; done < "$ACCOUNTS"
    local nmiss=0 nbad=0 login pass name f4 target
    while IFS=: read -r login pass name f4 _; do
      [[ -z "$login" ]] && continue
      target="${AM[$login]:-$login}"
      [[ -d "$CDIR/users/$target" ]] || { nmiss=$((nmiss+1)); continue; }
      # senha: só p/ quem NÃO foi remapeado (nos merges a senha do prod prevalece, de propósito)
      if [[ -z "${AM[$login]:-}" ]]; then
        [[ "$(jq -r '.password' "$CDIR/users/$target/account.json" 2>/dev/null)" == "$pass" ]] || nbad=$((nbad+1))
      fi
      # NÃO dá p/ auditar "a senha do prod prevaleceu" comparando com a legada: o Ribas REUSOU
      # a senha legada ao criar os `.admin` (edsonalves.admin == matemagica123 == a do passwd
      # legado), então "iguais" não prova sobrescrita — provaria um falso positivo em 2 das 9.
      # Quem garante a invariante é o `verify (g)`, que é exato: o staging não pode conter
      # account.json p/ conta que já existe no destino.
    done < "$FROM/passwd"
    ck "contas do legado ausentes no prod" "$nmiss" "0"
    ck "senhas que nao batem" "$nbad" "0"

    # todo dir de usuário tem account.json (senão list_users o ignora e o placar perde as subs)
    local nghost=0 d
    for d in "$CDIR"/users/*/; do [[ -f "$d/account.json" ]] || { echo "  FALHA: sem account.json: $(basename "$d")"; nghost=$((nghost+1)); }; done
    ck "conta sem account.json" "$nghost" "0"
  fi

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
