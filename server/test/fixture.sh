# test/fixture.sh — helpers de fixture do store por-usuário (source nos smokes).
# Aquecimento AUTOMÁTICO de juízes (promoção de rodada, judged antes do início) DESLIGADO nos testes: o processo
# destacado usaria o run/ da máquina e mandaria calibrações de problemas de fixture aos juízes de verdade. Só o
# smoke-warm-auto.sh o liga (com run/ isolado).
export AUTO_WARM_JUDGES="${AUTO_WARM_JUDGES:-0}"
# fx_user <contestdir> <login> <pass> [fullname] [email] — cria users/<login>/ completo.
fx_user() {
  local cdir="$1" login="$2" pass="$3" name="${4:-$2}" email="${5:-}"
  local d="$cdir/users/$login"
  mkdir -p "$d/submissions" "$d/mojlog" "$d/results"
  jq -cn --arg l "$login" --arg p "$pass" --arg n "$name" --arg e "$email" \
    '{login:$l,password:$p,fullname:$n,email:$e,created_at:0,updated_at:0,status:"active",uname_changes:[]}' \
    > "$d/account.json"
  : > "$d/history"
}

# fx_owners_index <contestsdir> [id ...] — o índice de problemas (owners) FRESCO na fixture, com os ids dados como
# públicos. Sem ele, a 1ª rota que confere acesso a problema (criar/duplicar contest, admin/problems, rodadas)
# REGENERA o índice do banco REAL da máquina (MOJ_PROBLEMS_DIR + MOJTOOLS_DIR padrão do common.conf): nesta máquina
# o teste lia dado de verdade e, num checkout em outro lugar, a regeração falhava e a rota dava 503
# index_unavailable (relato do Alex Orozco na issue #40, 01/10/2026). Id fora do índice não é negado.
fx_owners_index() {
  local d="$1/treino/var"; shift
  mkdir -p "$d"
  printf '%s\n' "$@" | jq -Rnc '{generated_at:(now | floor), problems:[ inputs | select(length > 0)
    | {id:., title:., owner:"fixture", collaborators:[], public:true} ]}' > "$d/problem-owners.json"
}
