# lib/classify.sh — o comum da CLASSIFICAÇÃO do lado da API: o handler admin/classify e a criação/export
# de contest (lib/contest-create.sh). Fora do prelúdio: quem precisa o sourceia (só funções + a allowlist).
#
# O CATÁLOGO (server/score/classify-catalog.json) descreve os motores — estágio padrão, próximo estágio,
# rótulos pt/en/es, chip, vias. Quem diz QUAL SCRIPT roda é a allowlist abaixo, em bash: o id do pedido
# só vira caminho de arquivo por ela. O smoke-contest-modules.sh confere que catálogo e allowlist têm os
# mesmos ids. Motor novo = script em score/ + linha aqui + entrada no catálogo + smoke.
declare -gA CL_ENGINES=( [sbc-fase1]="classify-br.sh" [latam-pda]="classify-pda.sh" [latam-mundial]="classify-mundial.sh" [manual]="classify-manual.sh" )
CL_SCORE_DIR="${BASH_SOURCE[0]%/*}/../../../score"
CL_CATALOG="$CL_SCORE_DIR/classify-catalog.json"

# cl_engine <algoritmo> -> nome do script (rc 1 fora da allowlist). A regex vem ANTES do índice: "@"/"*"
# expandiriam o array inteiro.
cl_engine(){ local a="${1:-}"; [[ "$a" =~ ^[a-z0-9-]{1,32}$ ]] || return 1; [[ -n "${CL_ENGINES[$a]:-}" ]] || return 1; printf '%s' "${CL_ENGINES[$a]}"; }
cl_engine_path(){ local s; s="$(cl_engine "$1")" || return 1; printf '%s/%s' "$CL_SCORE_DIR" "$s"; }

# cl_allow_json -> ["sbc-fase1", …] (os ids da allowlist, p/ filtrar o catálogo)
cl_allow_json(){ printf '%s\n' "${!CL_ENGINES[@]}" | jq -Rnc '[inputs | select(length > 0)]'; }

# cl_stage_default <algoritmo> -> o estágio padrão do motor no catálogo (vazio se não há)
cl_stage_default(){ jq -r --arg a "$1" 'first(.engines[] | select(.id == $a) | .stage) // empty' "$CL_CATALOG" 2>/dev/null; }

# cl_check <algoritmo> <config.json> — valida a config pelo `--check` do próprio motor. rc 0 ok; rc 1
# algoritmo fora da allowlist; rc 2 config inválida, com CL_CHECK_ERRORS = array JSON das mensagens.
cl_check(){
  local p e rc
  CL_CHECK_ERRORS='[]'
  p="$(cl_engine_path "$1")" || return 1
  e="$(bash "$p" --check "$2" 2>&1 >/dev/null)"; rc=$?
  (( rc == 0 )) && return 0
  CL_CHECK_ERRORS="$(jq -c '(.errors // []) | map(tostring)' <<<"$e" 2>/dev/null)"
  [[ -n "$CL_CHECK_ERRORS" && "$CL_CHECK_ERRORS" != "[]" ]] || CL_CHECK_ERRORS="$(jq -cn --arg m "${e:0:300}" '[$m]')"
  return 2
}

# CL_JQ — as definições jq da COMPOSIÇÃO de um estágio, a regra ÚNICA de "motor + overrides" (GET, prévia,
# apply e overrides usam as mesmas; report-gen e /contest/classification só leem `teams`, já composto).
#   cl_key      — chave do time: o login, ou "ext:<slug>" p/ time de fora do placar;
#   cl_ovs      — os overrides do estágio; estágio no formato ANTERIOR aos overrides (30/09/2026) tem os
#                 promovidos à mão como times via:"comite" — viram overrides `add` (via manual);
#   cl_result   — a saída do motor guardada no estágio; estágio antigo sem `result` usa os times
#                 automáticos que tem;
#   cl_relation($r) — as linhas do motor ($r = saída; withdrawn marcado) + as manuais (manual:true). Linha do
#                 motor de um time com override add/exclude é DESCARTADA: o motor deveria tê-lo pulado
#                 (preassigned/exclude), mas a composição não depende disso — sem o filtro, o mesmo time
#                 sairia duas vezes e o from_entries do cl_teams escolheria uma calado;
#   cl_engine_cfg($st) — a config que o MOTOR recebe: a do estágio + `exclude` (os overrides exclude) +
#                 `preassigned` (os add: já promovidos, o motor não lhes dá outra vaga);
#   cl_teams($rel; $now) — o mapa `teams` que vai p/ o placar: a relação sem os retirados.
CL_JQ='
def cl_key: if ((.login // "") != "") then .login else ("ext:" + (.ext // "")) end;
def cl_ovs: if has("overrides") then (.overrides // [])
  else ([ (.teams // {}) | to_entries[] | select(.value.via == "comite") ] | to_entries
        | map(.value as $t | {id:("ov-" + ((.key + 1) | tostring)), op:"add", login:$t.key, via:"manual",
              reason:(($t.value.note // "") | if . == "" then "comitê (legado)" else . end),
              by:($t.value.by // ""), at:($t.value.at // 0), legacy:true}))
  end;
def cl_result: .result // {classified: [ (.teams // {}) | to_entries[]
  | select(.value.via != "comite" and (.value.manual != true)) | .value + {login:.key} ]};
def cl_relation($r):
  cl_ovs as $ov
  | ([ $ov[] | select(.op == "withdraw") | {key:cl_key, value:{id, reason, by, at}} ] | from_entries) as $wd
  | ((($r // {}).pre // []) | map({key:.login, value:.}) | from_entries) as $pre
  | [ $ov[] | select(.op == "add" or .op == "exclude") | cl_key ] as $mk
  | [ (($r // {}).classified // [])[] | .login as $l | select(any($mk[]; . == $l) | not)
      | . + (if $wd[$l] then {withdrawn:$wd[$l]} else {} end) ]
    + [ $ov[] | select(.op == "add") | cl_key as $k
        | ({team, univ, school, country, region} | with_entries(select(.value != null)))
          + ($pre[$k] // {})
          + {login:$k, via:(.via // "manual"), manual:true, override:.id, reason, by, at} ];
def cl_engine_cfg($st): ($st | cl_ovs) as $ov
  | . + {exclude: ((.exclude // []) + [ $ov[] | select(.op == "exclude") | {login, reason} ]),
         preassigned: [ $ov[] | select(.op == "add") | {login:cl_key, via:(.via // "manual")}
                        + ({school, country, region} | with_entries(select(.value != null))) ]};
def cl_teams($rel; $now): [ $rel[] | select(.withdrawn == null)
  | {key:.login, value:({via, sede, place, total, detail, team, univ, school, country, region, seq,
                         manual, override} | with_entries(select(.value != null)) | . + {at:$now})} ]
  | from_entries;
'
