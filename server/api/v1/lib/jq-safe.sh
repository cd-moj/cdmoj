#!/bin/bash
# lib/jq-safe.sh — o EMBRULHO do jq da casa (20/11/2026; pedido do Ribas: "evitar que o jq morra por argmax ou outro erro
# silenciosamente, tratar melhor o jq como um todo"). Define a FUNÇÃO `jq`, que vence o binário em todo shell que fez
# `source` deste arquivo (e nos subshells dele: `$(…)`, pipelines). Carregado por lib/common.sh, lib/users.sh,
# judge-gw/sched-lib.sh e pelos scripts avulsos de score/ e daemons/ — entra ANTES de qualquer jq.
#
# 1. ARG_MAX. O Linux recusa o exec com UM argumento acima de 128 KiB (MAX_ARG_STRLEN) ou com o argv inteiro acima do
#    ARG_MAX; o bash diz "Argument list too long" (rc 126), o jq nem roda, o `>` deixa o arquivo VAZIO e o `$(…)` vira
#    vazio. Foram cinco incidentes (o último: os brasões do teams-meta.json, 19/11/2026). Aqui, o valor de `--arg`/
#    `--argjson` acima de JQ_SAFE_MAX bytes (64 KiB) vira ARQUIVO sem o chamador saber: `--arg n v` → `--rawfile n f`
#    (o mesmo texto) e `--argjson n v` → `--slurpfile __jqsN f` + `($__jqsN[0]) as $n | ` na frente do programa (com
#    `-f prog`, num programa temporário). Caminho normal: só mede o tamanho dos argumentos — nenhum processo a mais.
#    O que não dá p/ converter com segurança (`--args`/`--jsonargs`, `-L`, `--`, programa com `import`/`include`)
#    segue como antes e a falha vai ao log.
# 2. ERRO CALADO. O jq que falha (rc 2: uso, `--argjson` inválido, arquivo; 3: compilação; 5: execução/entrada; 126/127)
#    vira UMA LINHA no log `$JQ_SAFE_LOG` (padrão `$RUNDIR/jq-errors/AAAA-MM-DD.log`, TSV: epoch, rc, classe, rota, quem
#    chamou, programa), MESMO com o `2>/dev/null` do chamador. As classes esperadas ficam de fora (ver _jq_safe_class).
#    Nunca escreve no stdout nem no stderr (quem chama captura os dois); o rc volta intacto; log que não se grava é
#    ignorado. Os valores dos argumentos NUNCA vão ao log (podem ser senha, código de aluno) — só nomes e tamanhos.
# JQ_SAFE=0 no ambiente desliga as duas coisas (a função vira o jq cru). Teste: server/test/smoke-jq-safe.sh.
[[ -n "${_JQ_SAFE_LOADED:-}" ]] && return 0
_JQ_SAFE_LOADED=1
: "${JQ_SAFE_MAX:=65536}"

# _jq_safe_bytes <var> <texto> — tamanho em BYTES (o ${#x} conta caracteres no locale UTF-8 do dev)
_jq_safe_bytes(){ local LC_ALL=C; printf -v "$1" '%s' "${#2}"; }

# _jq_safe_logpath <var> — o arquivo do dia (vazio = sem log)
_jq_safe_logpath(){
  local d
  if [[ -n "${JQ_SAFE_LOG+x}" ]]; then printf -v "$1" '%s' "$JQ_SAFE_LOG"; return; fi
  [[ -n "${RUNDIR:-}" ]] || { printf -v "$1" ''; return; }
  printf -v d '%(%Y-%m-%d)T' -1
  printf -v "$1" '%s' "$RUNDIR/jq-errors/$d.log"
}

# _jq_safe_note <rc> <classe> <args…> — uma linha no log; nunca falha, nunca escreve no stdout/stderr
_jq_safe_note(){
  local rc="$1" cls="$2"; shift 2
  local lf; _jq_safe_logpath lf; [[ -n "$lf" ]] || return 0
  local prog="" a i=0 skip=0 names="" b who="" k route="${PATH_INFO:-${0##*/}}"
  local -a v=("$@")
  for ((i = 0; i < ${#v[@]}; i++)); do
    a="${v[i]}"
    if (( skip )); then skip=$((skip - 1)); continue; fi
    case "$a" in
      --arg|--argjson) _jq_safe_bytes b "${v[i+2]:-}"; names+="${a#--}:${v[i+1]:-}=${b}B "; skip=2;;
      --slurpfile|--rawfile|--argfile) names+="${a#--}:${v[i+1]:-}=arquivo "; skip=2;;
      --indent|-L|--library-path|-f|--from-file) skip=1;;
      -*) ;;
      *) [[ -z "$prog" ]] && prog="$a";;
    esac
  done
  for ((k = 2; k < ${#BASH_SOURCE[@]} && k < 6; k++)); do
    case "${BASH_SOURCE[k]##*/}" in jq-safe.sh) continue;; esac
    who+="${BASH_SOURCE[k]##*/}:${BASH_LINENO[k-1]}:${FUNCNAME[k]:-main} "
  done
  prog="${prog//[$'\t\n\r']/ }"; prog="${prog:0:160}"
  { [[ -d "${lf%/*}" ]] || mkdir -p "${lf%/*}"; } 2>/dev/null
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$EPOCHSECONDS" "$rc" "$cls" "$route" "${who% }" "${names% }" "$prog" \
    >> "$lf" 2>/dev/null
  return 0
}

# _jq_safe_class <rc> <stdout-descartado 0|1> <args…> — a classe da falha; vazio = ESPERADA (não vai ao log). Calibrado
# pela suíte inteira com o log ligado (20/11/2026: 1.259 linhas, nenhuma de bug):
#   · rc 2 com um arquivo de ENTRADA que não existe (o `jq … "$f" 2>/dev/null || padrão` é idioma da casa);
#   · TESTE: stdout em /dev/null (com ou sem `-e`) — só o rc importa, quem chama pergunta "é válido?" e trata as duas
#     respostas (rc 5 = a entrada não é JSON / a regex não compila; rc 2 = o --argjson testado não é JSON);
#   · `JQ_SAFE_EXPECT=1 jq …` — a chamada se declara validação de entrada de USUÁRIO que usa a saída (o rc≠0 vira 422);
#   · morte por SINAL (rc > 128, menos 126/127): o 141 é o SIGPIPE de `jq … | head`, normal.
_jq_safe_class(){
  local rc="$1" dnull="$2"; shift 2
  local a i=0 skip=0 seen=0 missing=0 rest=0
  local -a v=("$@")
  for ((i = 0; i < ${#v[@]}; i++)); do
    a="${v[i]}"
    if (( skip )); then skip=$((skip - 1)); continue; fi
    if (( rest )); then continue; fi
    case "$a" in
      --arg|--argjson|--slurpfile|--rawfile|--argfile) skip=2;;
      --indent|-L|--library-path) skip=1;;
      -f|--from-file) skip=1; seen=1;;
      --args|--jsonargs) rest=1;;
      -*) ;;
      *) if (( ! seen )); then seen=1; else [[ -e "$a" ]] || missing=1; fi;;
    esac
  done
  if (( dnull )) && [[ "$rc" == 5 || "$rc" == 2 ]]; then return 0; fi
  if [[ "${JQ_SAFE_EXPECT:-}" == 1 ]] && [[ "$rc" == 5 || "$rc" == 2 ]]; then return 0; fi
  if (( rc > 128 )); then return 0; fi
  case "$rc" in
    2) if (( missing )); then return 0; fi; printf 'uso';;          # --argjson inválido, opção, --slurpfile/--rawfile ausente
    3) printf 'compilacao';;
    5) printf 'execucao';;
    126) printf 'argv';;
    127) printf 'sem-jq';;
    *) printf 'rc%s' "$rc";;
  esac
}

# _jq_safe_big <args…> — 0 se algum argumento passa do teto (ou o argv inteiro passa de 1 MiB)
_jq_safe_big(){
  local a n tot=0
  for a in "$@"; do
    n=${#a}
    if (( n * 4 < JQ_SAFE_MAX )); then tot=$((tot + n)); continue; fi
    _jq_safe_bytes n "$a"
    if (( n >= JQ_SAFE_MAX )); then return 0; fi
    tot=$((tot + n))
  done
  (( tot >= 1048576 ))
}

# _jq_safe_run <args…> — converte os valores grandes em arquivo e roda; rc do jq (ou 126 se não deu p/ converter)
_jq_safe_run(){
  local d a i=0 nv=0 prog_i=-1 pf_i=-1 bad="" n lim="$JQ_SAFE_MAX" pre="" tot=0
  local -a v=("$@") out=()
  for a in "$@"; do tot=$((tot + ${#a})); done
  if (( tot >= 1048576 )); then lim=8192; fi     # argv inteiro grande: converte também os médios
  d="$(mktemp -d "${TMPDIR:-/tmp}/jqsafe.XXXXXX" 2>/dev/null)" || { command jq "$@"; return; }
  for ((i = 0; i < ${#v[@]}; i++)); do
    a="${v[i]}"
    case "$a" in
      --arg|--argjson)
        _jq_safe_bytes n "${v[i+2]:-}"
        if (( n >= lim )); then
          printf '%s' "${v[i+2]}" > "$d/a$nv"
          if [[ "$a" == --arg ]]; then out+=(--rawfile "${v[i+1]}" "$d/a$nv")
          else out+=(--slurpfile "__jqs$nv" "$d/a$nv"); pre+="(\$__jqs$nv[0]) as \$${v[i+1]} | "; fi
          nv=$((nv + 1))
        else out+=("$a" "${v[i+1]}" "${v[i+2]}"); fi
        i=$((i + 2));;
      --slurpfile|--rawfile|--argfile) out+=("$a" "${v[i+1]}" "${v[i+2]}"); i=$((i + 2));;
      --indent) out+=("$a" "${v[i+1]}"); i=$((i + 1));;
      -f|--from-file) out+=("$a" "${v[i+1]}"); pf_i=$(( ${#out[@]} - 1 )); prog_i=-2; i=$((i + 1));;
      -L|--library-path|--args|--jsonargs|--) bad="$a"; break;;
      -*) out+=("$a");;
      *) out+=("$a"); if (( prog_i == -1 )); then prog_i=$(( ${#out[@]} - 1 )); fi;;
    esac
  done
  if [[ -z "$bad" && -n "$pre" ]]; then
    if (( pf_i >= 0 )); then
      { printf '%s' "$pre"; cat -- "${out[pf_i]}"; } > "$d/prog.jq" 2>/dev/null && out[pf_i]="$d/prog.jq" || bad=-f
    elif (( prog_i >= 0 )); then
      [[ "${out[prog_i]}" =~ ^[[:space:]]*(import|include)[[:space:]] ]] && bad=import || out[prog_i]="$pre${out[prog_i]}"
    else bad=sem-programa; fi
  fi
  local rc
  if [[ -n "$bad" ]]; then command jq "$@"; rc=$?; _jq_safe_note "$rc" "argv-nao-convertido:$bad" "$@"
  else command jq "${out[@]}"; rc=$?; _jq_safe_note "$rc" "argv-convertido" "$@"; fi
  rm -rf -- "$d" 2>/dev/null
  return "$rc"
}

jq(){
  [[ "${JQ_SAFE:-1}" == 0 ]] && { command jq "$@"; return; }
  local rc c
  if _jq_safe_big "$@"; then _jq_safe_run "$@"; rc=$?
  else command jq "$@"; rc=$?; fi
  case "$rc" in
    0|1|4) ;;
    *) local dn=0; [[ /dev/fd/1 -ef /dev/null ]] && dn=1     # medido AQUI: dentro do $(…) o stdout é o pipe
       c="$(_jq_safe_class "$rc" "$dn" "$@")"; [[ -n "$c" ]] && _jq_safe_note "$rc" "$c" "$@";;
  esac
  return "$rc"
}
