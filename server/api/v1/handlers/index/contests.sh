# GET /index/contests?page=N[&all=1]
# Varre contests/*/conf e classifica por CONTEST_START/END vs agora:
#   open (start<=now<end), upcoming (start>now), closed (end<=now; paginado 20/pág;
#   all=1 devolve TODOS — usado pela página de arquivo /contests/).
# -> {success:true, open:[...], upcoming:[...], closed:{items,page,per_page,total}}
#
# ARQUITETURA (não regredir — este handler JÁ quebrou dos dois jeitos clássicos):
#  - NADA de JSON grande por --argjson: com 781 contests o array dos encerrados cruzou o
#    MAX_ARG_STRLEN (128 KiB POR argumento) e o jq morria "Argument list too long". O scan
#    emite 1 linha TSV (separador \x1f — título é texto de usuário) num TEMP FILE e o
#    envelope sai de UM jq lendo o arquivo; por argv só escalares (page/per_page/all).
#  - CORPO ANTES DO HEADER: o emit_json 200 no topo transformava a falha do jq em 200 com
#    corpo VAZIO ("Não foi possível carregar os contests." na UI). Agora falha = 500 honesto.
#  - Sem jq POR contest (eram 781 forks ≈ 4s de resposta) — só o subshell do source (barato
#    e load-bearing: isola as variáveis do conf de cada contest).
#  - ...mas 1482 subshells não são baratos: **1.455 ms**, medidos, contra 52 ms p/ ler os mesmos
#    confs sem subshell. Era o custo INTEIRO da rota (2,2 s) — na PÁGINA INICIAL, anônima, a cada
#    visita. Por isso o resultado do laço (o TSV) é CACHEADO, e o cache é invalidado por EVENTO,
#    não por relógio: `find -newer` acha em UM processo qualquer `conf` mais novo que o cache, e o
#    mtime de `contests/` pega contest criado/removido. Para isso o TSV teve de ficar
#    INDEPENDENTE DO RELÓGIO — a classificação aberto/por vir/encerrado, o `problems_count` que
#    o pré-início esconde e a inscrição sem prazo do aquecimento passaram todos p/ o jq, que já
#    roda a cada requisição. Sem isso, cache e relógio brigam e um dos dois perde calado.
set +o noglob
# reg_official_window: a data que ancora a inscrição é a da PROVA, não a da rodada corrente
source "$_DIR/lib/registration.sh"

PAGE="$(param page)"; [[ "$PAGE" =~ ^[0-9]+$ ]] || PAGE=1
(( PAGE < 1 )) && PAGE=1
PERPAGE=20
ALL="$(param all)"; ALLMODE=0
case "$ALL" in 1|true|all) ALLMODE=1;; esac
NOW="$EPOCHSECONDS"
US=$'\x1f'

# ---- CACHE DO TSV -------------------------------------------------------------------------
# Frescor por EVENTO: (a) `contests/` mais novo que o cache = contest criado ou removido (teste
# builtin); (b) algum `conf` mais novo = contest editado — UM `find` com `-print -quit`, que sai
# no primeiro achado. Nada de teto de idade: o TSV não depende mais da hora.
TSVC="$RUNDIR/index-contests.tsv"
_tsv_fresco(){
  [[ -s "$TSVC" ]] || return 1
  [[ "$CONTESTSDIR" -nt "$TSVC" ]] && return 1
  [[ -z "$(find "$CONTESTSDIR" -maxdepth 2 -name conf -newer "$TSVC" -print -quit 2>/dev/null)" ]]
}
if _tsv_fresco; then
  TSV="$TSVC"
else

TSV="$(mktemp)" || fail 500 "Falha ao criar temporário" "tmp_failed"
trap 'rm -f "$TSV"' EXIT

# 1 linha por contest, SEM NADA QUE DEPENDA DA HORA (ver o cabeçalho):
#   start \x1f id \x1f título \x1f end \x1f nprobs \x1f reg \x1f ro \x1f rc \x1f rl \x1f warmup \x1f início-oficial
for d in "$CONTESTSDIR"/*/; do
  c="${d%/}"; id="${c##*/}"
  [[ "$id" == treino ]] && continue
  [[ -f "$c/conf" ]] || continue
  (
    CONTEST_START=""; CONTEST_END=""; CONTEST_NAME=""; SECRET=""; PROBS=()
    REG_OPEN=""; REG_CLOSE=""; REG_LATE_MINUTES=""; ROUND_KIND=""
    source "$c/conf" 2>/dev/null
    [[ "$SECRET" == 1 ]] && exit 0   # SUPER SECRETO: fora de abertos/por vir/encerrados
    [[ "$CONTEST_START" =~ ^[0-9]+$ && "$CONTEST_END" =~ ^[0-9]+$ ]] || exit 0
    t="${CONTEST_NAME//$'\x1f'/ }"; t="${t//$'\n'/ }"; t="${t//$'\t'/ }"
    # INSCRIÇÃO (roster existe = ligada): manda as DATAS, não o estado — quem decide "aberta
    # / atrasada / fechada" é o relógio do cliente, sem duplicar a regra do lib/registration.sh
    reg=0; ro=0; rc=0; rl=0; warm=0; osec=0
    if [[ -s "$c/registrations.json" ]]; then
      reg=1
      # a âncora é o início da PROVA OFICIAL, não o da rodada corrente: o aquecimento pode ficar
      # dias no ar (lib/registration.sh `reg_official_window` — mesma regra do resto do sistema).
      # O fork extra só acontece p/ contest COM inscrição (raro), nunca no caminho comum.
      IFS=$'\x09' read -r _os _oe _or < <(reg_official_window "$id")
      [[ "$_os" =~ ^[0-9]+$ ]] || _os="$CONTEST_START"
      osec="$_os"; [[ "${ROUND_KIND:-}" == warmup ]] && warm=1
      [[ "$REG_OPEN" =~ ^[0-9]+$ ]] && ro="$REG_OPEN"
      if [[ "$REG_CLOSE" =~ ^[0-9]+$ ]]; then rc="$REG_CLOSE"; else rc="$_os"; fi
      if [[ "$REG_LATE_MINUTES" =~ ^[0-9]+$ ]] && (( REG_LATE_MINUTES > 0 )); then
        rl=$(( _os + REG_LATE_MINUTES * 60 )); (( rl < rc )) && rl=$rc
      fi
      # (a inscrição sem prazo do aquecimento no ar depende da HORA — resolvida no jq)
    fi
    np=$(( ${#PROBS[@]} / 5 ))
    printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\n' \
      "$CONTEST_START" "$id" "$t" "$CONTEST_END" "$np" \
      "$reg" "$ro" "$rc" "$rl" "$warm" "$osec"
  )
done | sort -t"$US" -k1,1rn > "$TSV"
mkdir -p "${TSVC%/*}" 2>/dev/null
cp -f "$TSV" "$TSVC.tmp.${BASHPID}" 2>/dev/null && mv -f "$TSVC.tmp.${BASHPID}" "$TSVC" 2>/dev/null \
  || rm -f "$TSVC.tmp.${BASHPID}" 2>/dev/null
fi

# O jq faz TUDO que depende da hora (ver o cabeçalho): a classificação, o problems_count que o
# pré-início esconde e a inscrição sem prazo do aquecimento. Assim o TSV cacheado nunca envelhece.
body="$(jq -R -s -c \
  --argjson page "$PAGE" --argjson pp "$PERPAGE" --argjson all "$ALLMODE" --argjson now "$NOW" '
  split("\n")
  | map(select(length>0) | split("\u001f") | select(length>=11)
      | (.[0]|tonumber? // 0) as $start | (.[3]|tonumber? // 0) as $end
      | (if   $end   <= $now then "e"
         elif $start >  $now then "u"
         else "r" end) as $st
      | ((.[9] // "0") == "1" and ((.[10] // "0")|tonumber? // 0) > 0
         and ((.[10] // "0")|tonumber? // 0) <= $now) as $warm_aberto
      | { st:$st,
          # jq 1.7 (o da imagem) EXIGE parênteses em volta do valor quando ele é uma
          # expressão composta ({…} + (…)): sem eles é "syntax error, unexpected else"
          obj: ({ id:(.[1]), title:(.[2]),
                start_time:$start, end_time:$end,
                # contest AINDA NÃO COMEÇADO não revela a quantidade de problemas (mesma regra
                # do placar pré-início): o card da home mostra 0 e o front oculta o trecho.
                problems_count:(if $st == "u" then 0 else (.[4]|tonumber? // 0) end),
                url:("/contest/?c=" + .[1]), scoreboard_url:("/contest/score/?c=" + .[1]) }
             + (if (.[5] // "0") == "1"
                then { registration: { opens_at:((.[6] // "0")|tonumber? // 0),
                                       # aquecimento no ar sem prova planejada: sem prazo
                                       closes_at:(if $warm_aberto then 0 else ((.[7] // "0")|tonumber? // 0) end),
                                       late_until:(if $warm_aberto then 0 else ((.[8] // "0")|tonumber? // 0) end),
                                       url:("/contests/inscricao/?c=" + .[1]) } }
                else {} end)) })
  | (map(select(.st=="r") | .obj)) as $open
  | (map(select(.st=="u") | .obj)) as $up
  | (map(select(.st=="e") | .obj)) as $closed
  | ($closed|length) as $total
  | (if $all==1 then $closed
     else $closed[(($page-1)*$pp) : (($page-1)*$pp + $pp)] end) as $items
  | {success:true, open:$open, upcoming:$up,
     closed:{ items:$items,
              page:(if $all==1 then 1 else $page end),
              per_page:(if $all==1 then $total else $pp end),
              total:$total }}' < "$TSV" 2>/dev/null)"

[[ -n "$body" ]] || fail 500 "Falha ao montar a lista de contests" "contests_render_failed"
emit_json 200 OK
printf '%s\n' "$body"
