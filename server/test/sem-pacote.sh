#!/bin/bash
# sem-pacote.sh — INVENTÁRIO da fronteira do repositório de problemas.
#
#   bash server/test/sem-pacote.sh            # os dois modos
#   bash server/test/sem-pacote.sh --dif      # só o diferencial (comportamento)
#   bash server/test/sem-pacote.sh --est      # só a checagem estática (alcançabilidade)
#
# A REGRA: `MOJ_PROBLEMS_DIR` (23 GB, 1402 pacotes) é tocado só pela GESTÃO DE PROBLEMAS
# (handlers/problems/**, handlers/orgs/**), pela COMUNICAÇÃO COM OS JUÍZES (handlers/judge/**) e
# por OPS de admin (handlers/ops/**). Rota de contest e de treino responde do que o servidor JÁ
# CONHECE — índice de donos, json servível, run/tl, os enunciados do próprio contest.
#
# POR QUE ISSO EXISTE: a fronteira sempre foi doutrina da gestão de problemas ("sem hash de pacote
# por request"), mas não estava escrita nem testada — e uma rota de contest a atravessou sem
# ninguém notar. O `/contest/problems` chamava `tl_store_served` → `pkg_tl_checksum` →
# `tl-checksum.sh`, que LÊ O CONTEÚDO de `tests/`: **112,8 MB hasheados por regeração**, em 14
# problemas, só para mostrar tempo-limite na tela. A rota a frio levava **2,0 s**. Foi achado por
# acaso, olhando um cronômetro; este arquivo existe para que o próximo seja achado por um teste.
#
# ⚠ NESTA FASE ELE **RELATA**, NÃO REPROVA (sai 0 mesmo achando resíduo) — a fronteira acabou de
# ser escrita e os seis resíduos conhecidos ainda estão lá, com conserto planejado. Quando a lista
# esvaziar, troque o `exit 0` do fim por `exit $(( ach > 0 ))` e ponha em `make check`.
#
# OS DOIS MODOS SE COMPLETAM, e nenhum basta sozinho:
#   · DIFERENCIAL  — chama as rotas em TRÊS árvores de pacote e acusa onde a resposta MUDA.
#                    Pega acesso via lib (foi assim que o bug nasceu) e enumera os handlers
#                    sozinho, então rota nova entra no teste sem ninguém lembrar. Não pega
#                    leitura que não muda a resposta, nem rota que precise de POST com corpo.
#                    ⚠ A 2ª árvore é **ENVENENADA**, não vazia: com diretório vazio os dois
#                    caminhos degradam para a MESMA resposta de "ausente" (`tl_conf_overrides`
#                    devolve `{}` tanto por não ter override quanto por não ter pacote) e o
#                    teste passa em falso. Com valores DIFERENTES e MARCADOS, qualquer leitura
#                    que influencie a saída aparece — e ainda dá p/ procurar a marca no corpo.
#   · ESTÁTICO     — segue os `source` a partir de cada handler e acusa FUNÇÃO alcançável que
#                    toca o pacote (fecho transitivo: quem chama quem toca, também toca). Pega o
#                    que o diferencial não vê; em compensação é um TETO (a função pode estar num
#                    ramo que aquela rota nunca executa).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"     # …/server
ROUTER="$ROOT/api/v1/router.sh"
MODE="${1:---tudo}"
ach=0

# `nocom` tira as linhas de COMENTÁRIO: sem isso, arquivo que só CITA um gerador em prosa vira
# falso positivo (foi o caso do `score/treino-list-gen.sh`, que fala de `gen-problem-*.sh` nos
# comentários e não abre pacote nenhum). Inventário com ruído é inventário que ninguém lê.
nocom(){ grep -vE '^[[:space:]]*#' "$1" 2>/dev/null; }

# o que significa "encostou no pacote". `pkg_path` entra mesmo só fazendo `stat`: é o portal.
TOKENS='MOJ_PROBLEMS_DIR|pkg_path|pkg_tl_checksum|_tlcks_sig|tl-checksum\.sh|read_problem_source|apply_problem_fields|problem_commit|write_meta|_pkg_canon_modes|render-statement\.sh|gen-problem-json\.sh|gen-problem-owners\.sh|validate-problem\.sh'

# ============================================================================ ESTÁTICO
# Duas classes, porque são problemas DIFERENTES com consertos diferentes:
#   PKG  — abre o pacote (lê `author`, `conf`, `tests/`, `docs/solucao.md`…).
#   SCAN — pode disparar `ensure_owners_index` no ramo SÍNCRONO, que varre a base inteira
#          (23 GB) dentro da requisição. Não lê um pacote: lê TODOS.
estatico() {
  echo "== ESTÁTICO — o que é alcançável a partir de contest/treino =="
  local -A FNBODY=() PKG=() SCAN=()
  local f fn body
  for f in "$ROOT/api/v1/lib/"*.sh; do
    [[ -f "$f" ]] || continue
    while IFS=$'\t' read -r fn body; do
      [[ -n "$fn" ]] && FNBODY["$fn"]="${FNBODY[$fn]:-}${body}"$'\n'
    done < <(awk '
      /^[a-zA-Z_][a-zA-Z0-9_]*\(\)[[:space:]]*\{/ { n=$0; sub(/\(\).*/,"",n); f=n; b=""; next }
      f && /^\}/ { gsub(/\t/," ",b); print f "\t" b; f=""; next }
      f { b = b " " $0 }
    ' <(nocom "$f"))
  done
  # sementes
  for fn in "${!FNBODY[@]}"; do
    [[ "${FNBODY[$fn]}" =~ $TOKENS ]] && PKG["$fn"]=1
  done
  SCAN[ensure_owners_index]=1
  unset 'PKG[ensure_owners_index]'          # ela varre a base; não é leitura de UM pacote
  # fecho transitivo de cada classe
  local -n cls; local mudou g
  for cls in PKG SCAN; do
    mudou=1
    while (( mudou )); do
      mudou=0
      for fn in "${!FNBODY[@]}"; do
        [[ -n "${cls[$fn]:-}" ]] && continue
        for g in "${!cls[@]}"; do
          [[ "${FNBODY[$fn]}" == *"$g"* ]] && { cls["$fn"]=1; mudou=1; break; }
        done
      done
    done
  done
  unset -n cls
  # geradores de placar que abrem o pacote (o handler os chama por CAMINHO, não por função —
  # foi assim que o `contest/admin/report.sh` escapou da 1ª versão deste teste)
  local -a GENS=()
  for f in "$ROOT/score/"*.sh; do
    nocom "$f" | grep -qE "$TOKENS" && GENS+=("$(basename "$f")")
  done
  # quem, de contest/treino, alcança o quê
  local h rel p_hits s_hits
  while IFS= read -r h; do
    rel="${h#"$ROOT"/api/v1/handlers/}"; p_hits=""; s_hits=""
    local corpo; corpo="$(nocom "$h")"
    grep -qE "$TOKENS" <<<"$corpo" && p_hits="direto"
    for g in "${GENS[@]}"; do
      grep -qF "$g" <<<"$corpo" && p_hits="${p_hits:+$p_hits, }$g"
    done
    for fn in "${!PKG[@]}"; do
      grep -qE "(^|[^a-zA-Z0-9_])${fn}([^a-zA-Z0-9_]|$)" <<<"$corpo" \
        && p_hits="${p_hits:+$p_hits, }$fn()"
    done
    for fn in "${!SCAN[@]}"; do
      grep -qE "(^|[^a-zA-Z0-9_])${fn}([^a-zA-Z0-9_]|$)" <<<"$corpo" \
        && s_hits="${s_hits:+$s_hits, }$fn()"
    done
    [[ -n "$p_hits" ]] && { printf '  PKG   %-38s %s\n' "$rel" "$p_hits"; (( ach++ )); }
    [[ -n "$s_hits" ]] && { printf '  SCAN  %-38s %s\n' "$rel" "$s_hits"; (( ach++ )); }
  done < <(find "$ROOT/api/v1/handlers/contest" "$ROOT/api/v1/handlers/treino" -name '*.sh' | sort)
  echo "  (é um TETO: a função pode estar num ramo que aquela rota nunca executa)"
}

# ============================================================================ DIFERENCIAL
diferencial() {
  echo "== DIFERENCIAL — a resposta MUDA quando o repositório de problemas some? =="
  local FIX SESS PKG VENENO
  FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; PKG="$(mktemp -d)"; VENENO="$(mktemp -d)"
  # shellcheck source=/dev/null
  source "$(dirname "$(readlink -f "$0")")/fixture.sh"

  local C="$FIX/sp" T="$FIX/treino"
  mkdir -p "$C/var" "$C/enunciados" "$T/var/jsons" "$T/var/jsons-private" "$FIX/run/tl"
  local T0=$(( $(date +%s) - 7200 ))
  { printf 'CONTEST_ID=sp\nCONTEST_TYPE=icpc\nCONTEST_NAME=Prova\n'
    printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$T0" "$(( T0 + 3600 ))"   # ENCERRADA: mostra autor
    printf 'PROBS=( x col#pa Alfa A col#pa )\n'; } > "$C/conf"
  local u
  for u in sp.admin sp.judge time01; do
    fx_user "$C" "$u" p "Nome $u"
    printf 'CONTEST=sp\nLOGIN=%s\nUSERFULLNAME=X\nLOGINAT=1\n' "$u" > "$SESS/$u"
  done
  fx_user "$T" prof p Prof; printf 'CONTEST=treino\nLOGIN=prof\nUSERFULLNAME=X\nLOGINAT=1\n' > "$SESS/prof"
  printf '<html><body>enunciado</body></html>' > "$C/enunciados/col#pa.html"

  # O PACOTE tem coisas que o materializado NÃO tem — é o que faz a diferença aparecer:
  #   · author com DOIS autores (o índice de donos só guarda a 1ª linha; o json servível junta
  #     todas — por isso o json servível é a fonte certa, e o de donos não serve);
  #   · TLOVERRIDE no conf (não tem espelho materializado nenhum);
  #   · docs/solucao.md (o editorial, excluído do índice por contrato).
  mkdir -p "$PKG/col/pa/docs" "$PKG/col/pa/tests/input" "$PKG/col/pa/sols/good"
  printf 'Ada Lovelace\nGrace Hopper\n' > "$PKG/col/pa/author"
  printf 'TIMELIMIT=1\nTLOVERRIDE[c]=3.5\n'   > "$PKG/col/pa/conf"
  printf '# solução\ntexto secreto do editorial\n' > "$PKG/col/pa/docs/solucao.md"
  printf '1 2\n' > "$PKG/col/pa/tests/input/01"; printf 'int main(){}\n' > "$PKG/col/pa/sols/good/a.c"
  # a árvore ENVENENADA: mesmos ids, valores DIFERENTES e marcados. Qualquer byte destes que
  # apareça numa resposta é leitura de pacote pega em flagrante.
  mkdir -p "$VENENO/col/pa/docs" "$VENENO/col/pa/tests/input" "$VENENO/col/pa/sols/good"
  printf 'NAOPODEAPARECER\nNEMESTE\n'          > "$VENENO/col/pa/author"
  printf 'TIMELIMIT=1\nTLOVERRIDE[c]=99.99\n'  > "$VENENO/col/pa/conf"
  printf 'VAZAMENTO_DE_SOLUCAO\n'              > "$VENENO/col/pa/docs/solucao.md"
  printf '9 9 9\n' > "$VENENO/col/pa/tests/input/01"   # muda o checksum do pacote
  printf 'int main(){return 1;}\n' > "$VENENO/col/pa/sols/good/a.c"
  # o MATERIALIZADO (índice + json servível + TL do juiz), como o servidor de verdade mantém
  jq -cn '{problems:[{id:"col#pa", repo:"col", prob:"pa", owner:"prof", collaborators:[],
           author:"Ada Lovelace", title:"Alfa", public:true, collections:["col"],
           tl_checksum:"cafe1234", good_langs:["c"], html:true}]}' > "$T/var/problem-owners.json"
  jq -cn '{id:"col#pa", title:"Alfa", author:"Ada Lovelace, Grace Hopper",
           time_limits:{c:"3.5", default:"1.0"}, tags:[], collections:["col"],
           languages:[], public:true, statement_html_b64:""}' > "$T/var/jsons/col#pa.json"
  jq -cn '{id:"col#pa", checksum:"cafe1234", updated_at:1,
           hosts:{j1:{tl:{c:"1.0"}, at:1}}}' > "$FIX/run/tl/col#pa.json"

  # chama TODO handler de contest/treino — enumeração automática: rota nova entra sozinha
  chamar() { # <pkgdir> <path_info> <query> <token> <saida>
    env PATH_INFO="$2" REQUEST_METHOD=GET QUERY_STRING="$3" HTTP_AUTHORIZATION="Bearer ${4:-}" \
      CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$FIX/run" MOJ_PROBLEMS_DIR="$1" \
      TL_STORE_DIR="$FIX/run/tl" PROBLEMS_CACHE_TTL=0 \
      bash "$ROUTER" </dev/null > "$5" 2>/dev/null
  }
  # CONTROLE: há rota cuja resposta muda sozinha entre duas chamadas iguais (o `beacon` carimba
  # hora e nonce; painéis carimbam `generated_at`). Sem medir isso primeiro, elas apareceriam
  # como "toca o pacote" e o inventário viraria ruído — que é como um teste deixa de ser lido.
  local h rel path q tok a b c ctrl
  a="$FIX/a.out"; b="$FIX/b.out"; c="$FIX/c.out"; ctrl="$FIX/ctrl.out"
  local ndet=0
  while IFS= read -r h; do
    rel="${h#"$ROOT"/api/v1/handlers/}"; path="/${rel%.sh}"
    case "$path" in /treino/*) q="" ; tok=prof ;; *) q="contest=sp"; tok=sp.admin ;; esac
    [[ "$path" == /treino/* ]] && q="contest=treino"
    limpar() { rm -f "$C/var/problems-cache."* "$C/var/"*-cache.* "$FIX/run/tl/"*.cks 2>/dev/null; }
    limpar; chamar "$PKG"    "$path" "$q" "$tok" "$a"
    limpar; chamar "$PKG"    "$path" "$q" "$tok" "$ctrl"      # controle: MESMA árvore
    if ! cmp -s "$a" "$ctrl"; then
      printf '  %-42s (não determinística — fora do alcance deste teste)\n' "$rel"
      (( ndet++ )); continue
    fi
    limpar; chamar "$VENENO" "$path" "$q" "$tok" "$b"
    limpar; chamar /nao/existe/mesmo "$path" "$q" "$tok" "$c"
    local motivo=""
    cmp -s "$a" "$b"           || motivo="muda com pacote ENVENENADO"
    cmp -s "$a" "$c"           || motivo="${motivo:+$motivo; }muda com pacote AUSENTE"
    grep -qE 'NAOPODEAPARECER|NEMESTE|99\.99|VAZAMENTO_DE_SOLUCAO' "$b" 2>/dev/null \
      && motivo="${motivo:+$motivo; }SERVIU BYTE DO PACOTE"
    if [[ -n "$motivo" ]]; then
      printf '  %-42s %s\n' "$rel" "$motivo"
      diff <(head -c 400 "$a") <(head -c 400 "$b") 2>/dev/null | head -4 | sed 's/^/        /'
      (( ach++ ))
    fi
  done < <(find "$ROOT/api/v1/handlers/contest" "$ROOT/api/v1/handlers/treino" -name '*.sh' | sort)
  echo "  ($ndet rota(s) não determinística(s) puladas; só GET — rota que exige POST com corpo"
  echo "   responde igual nas três árvores e não é coberta)"
  rm -rf "$FIX" "$SESS" "$PKG" "$VENENO"
}

case "$MODE" in
  --est) estatico ;;
  --dif) diferencial ;;
  *)     estatico; echo; diferencial ;;
esac
echo
echo "RESULT: $ach ponto(s) de contato com o repositório de problemas"
echo "(esta fase RELATA e não reprova — ver o cabeçalho do arquivo)"
exit 0
