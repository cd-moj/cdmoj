#!/bin/bash
# jq-portability.sh — compila TODO programa jq do servidor e acusa erro de SINTAXE.
#
#   bash server/test/jq-portability.sh [dir]     (default: server/)
#   make check-jq                                 (roda DENTRO da imagem = o jq de PRODUÇÃO)
#
# POR QUE ISSO EXISTE: o jq da imagem (Debian, **1.7**) é mais estrito que o do dev (**1.8**).
# No 1.7, valor de campo de objeto NÃO aceita operador binário solto:
#     {a: X + Y}   {a: .x // 0}   {a: .x == 1}   {a: .x and .y}    -> ERRO DE SINTAXE
#     {a: (X + Y)} {a: (.x // 0)} {a: (.x == 1)} {a: (.x and .y)}  -> ok em qualquer versão
# O 1.8 aceita as duas formas — então dá p/ escrever, testar no dev e SÓ QUEBRAR EM PRODUÇÃO.
# E quebra calada: o `2>/dev/null` engole o erro, o jq seguinte recebe stdin vazio, sai 0 sem
# imprimir nada, o `|| fallback` do handler não dispara e o cliente recebe **200 com corpo vazio**
# ("Resposta inválida do servidor"). Foi assim que TODA a listagem (problemas/orgs/coleções) caiu.
#
# Falsos-positivos conhecidos (ignorados por --skip-undefined, o default): programas montados por
# concatenação com uma variável de shell (ex.: "$VERDICT_CANON_JQ"'…') — extraímos só a 2ª metade,
# então funções definidas na 1ª aparecem como "não definidas". Isso é erro de COMPILAÇÃO, não de
# sintaxe: filtramos pela mensagem.
set -uo pipefail
DIR="${1:-server}"
command -v jq >/dev/null || { echo "jq-portability: sem jq no PATH" >&2; exit 2; }

# Extrai os programas jq (strings single-quoted que seguem uma invocação de `jq`, podendo ser
# multi-linha) e separa por \x01. Puro awk: roda dentro da imagem (que não tem python3).
extract() {
  awk 'BEGIN{ RS="\x02" }                 # slurp o arquivo inteiro
  {
    s=$0; n=length(s); i=1
    while (i<=n) {
      p = index(substr(s,i), "jq"); if (p==0) break
      pos = i+p-1
      before = (pos>1) ? substr(s,pos-1,1) : " "
      after  = substr(s,pos+2,1)
      if (before ~ /[A-Za-z0-9_.\/-]/ || after ~ /[A-Za-z0-9_]/) { i = pos+2; continue }
      rest = substr(s,pos); nl = index(rest,"\n"); if (nl==0) nl = length(rest)+1
      q = index(substr(rest,1,nl-1), "\047"); if (q==0) { i = pos+2; continue }   # \047 = aspa simples
      start = pos + q
      endq = index(substr(s,start), "\047"); if (endq==0) break
      prog = substr(s,start,endq-1)
      if (prog ~ /[.|{[(]/ && length(prog) > 2) printf "%s\x01", prog
      i = start + endq
    }
  }' "$1"
}

bad=0; noise=0; total=0
while IFS= read -r -d '' f; do
  while IFS= read -r -d $'\x01' prog; do
    [[ -n "${prog// }" ]] || continue
    total=$((total+1))
    # declara todo $var referenciado (senão "não definido" vira erro de compilação = ruído)
    args=()
    while read -r v; do [[ -n "$v" ]] && args+=(--arg "$v" x); done < <(
      grep -oE '\$[a-zA-Z_][a-zA-Z0-9_]*' <<<"$prog" | sed 's/^\$//' | grep -vxE 'ENV|__loc__' | sort -u)
    err="$(echo null | jq "${args[@]}" "$prog" 2>&1 >/dev/null)"
    grep -q "syntax error" <<<"$err" || continue
    # A incompatibilidade 1.7 x 1.8 é UMA: valor de campo de objeto com operador binário solto —
    # e ela sempre reclama "expecting '}'". Qualquer outro erro de sintaxe é o EXTRATOR daqui que
    # pegou lixo (jq com programa sem aspas dentro de string do shell, programa montado por
    # concatenação, etc.) — vira AVISO, não falha, senão o guard fica inútil de tão barulhento.
    if grep -q "expecting '}'" <<<"$err"; then
      bad=$((bad+1))
      echo "FAIL $f"
      grep -oE "unexpected [^,]*" <<<"$err" | head -1 | sed 's/^/     /'
      printf '     %s…\n' "$(tr '\n' ' ' <<<"$prog" | cut -c1-90)"
    else
      noise=$((noise+1))
      [[ -n "${VERBOSE:-}" ]] && echo "  (não-extraível: $f)"
    fi
  done < <(extract "$f")
done < <(find "$DIR" -name '*.sh' -print0 | sort -z)

echo "jq $(jq --version): $total programas · $bad INCOMPATÍVEL(EIS) · $noise não-extraível(eis) (VERBOSE=1 p/ ver)"
[[ $bad -eq 0 ]]
