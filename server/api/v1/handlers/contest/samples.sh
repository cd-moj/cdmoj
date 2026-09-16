# GET /contest/samples?contest=<id>&problem=<letra|problem_id>   (Bearer)
# Os EXEMPLOS do enunciado como dado: {success, problem, problem_id, samples:[{name,input,output}]}.
# É o que alimenta o botão "⬇ Exemplos" da sanfona e o `moj-comp samples`/`fetch` (2026-09-16).
#
# ANTI-VAZAMENTO DE TESTE SECRETO (pedido do Ribas) — três travas, todas aqui ou no gerador:
#   1. A ÚNICA fonte é o json servível do banco (`cs_bank_json` → `.samples`). Esta rota NUNCA abre
#      MOJ_PROBLEMS_DIR/tests/ (fronteira do pacote, CLAUDE.md). Contest cujo enunciado foi enviado à
#      mão não tem json ⇒ `samples:[]` (200) — nunca "vai ao pacote buscar".
#   2. O campo `samples` é gerado por `stmt_sample_names` (mojtools/statement-langs.sh), a MESMA seleção
#      que o HTML do enunciado mostra — por construção o dado exposto é o que o time já lê; nome que não
#      é `sample*` (ou não está no arquivo `samples`) jamais entra.
#   3. O GATE é o do enunciado (`can_see_problems` ⇒ 404: .staff/.cstaff/.animeitor nunca, competidor só
#      depois do início); a chave sai do PROBS do conf, nunca do parâmetro; problema fora do conf = 404.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

source "$_LIBDIR/contest-gate.sh"
can_see_problems "$contest" || fail 404 "Not found" "samples_notfound"

ref="$(param problem)"
[[ -n "$ref" ]] || fail 400 "Missing problem" "problem_missing"
source "$_LIBDIR/contest-statement.sh"

CONTEST_ID="$contest"; PROBS=()
load_contest_conf "$contest"
STATEMENT=""; SHORT=""; PID=""
for (( i=0; i<${#PROBS[@]}; i+=5 )); do
  pid="${PROBS[$((i+4))]}"
  [[ "$pid" == *"#"* ]] || pid="${PROBS[$((i+1))]//\//#}"
  if [[ "$ref" == "${PROBS[$((i+3))]}" || "$ref" == "$pid" ]]; then
    STATEMENT="${PROBS[$((i+4))]}"; SHORT="${PROBS[$((i+3))]}"; PID="$pid"; break
  fi
done
[[ -n "$STATEMENT" ]] || fail 404 "Not found" "samples_notfound"

# só o que o json servível já tem; nada de pacote. `map({name,input,output})` = nenhum campo a mais.
if bf="$(cs_bank_json "$STATEMENT" 2>/dev/null)"; then
  out="$(jq -c --arg sn "$SHORT" --arg pid "$PID" \
    '{success:true, problem:$sn, problem_id:$pid,
      samples:((.samples // []) | map(select(type=="object"))
               | map(if .too_big == true then {name:(.name // ""), size:(.size // 0), too_big:true}
                     else {name:(.name // ""), input:(.input // ""), output:(.output // "")} end))}' "$bf" 2>/dev/null)"
fi
[[ -n "${out:-}" ]] || out="$(jq -cn --arg sn "$SHORT" --arg pid "$PID" '{success:true, problem:$sn, problem_id:$pid, samples:[]}')"
printf 'Status: 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: private, max-age=60\r\n\r\n%s\n' "$out"
