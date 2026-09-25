# lib/review-rules.sh — O QUE VAI PARA REVISÃO no veredicto manual (contests/<c>/auto-verdicts.json).
# Fonte ÚNICA da regra: o daemon (judged.sh → should_hold), a API (/contest/auto-verdicts: a tela, a
# prévia e o "liberar") e — espelhada em Python, com teste diferencial — o ingestor de emergência
# (daemons/ingest-drain.py). Mexeu aqui, mexa lá (smoke-review-rules.sh compara os dois).
#
# v2 (25/09/2026; pedidos do Vinícius — "opt-out do automático" — e do Daniel Saad — "título, não id"):
# OPT-OUT. Com MANUAL_VERDICT=1, tudo sai AUTOMÁTICO, menos o que a tabela manda para revisão:
#   {"version":2,
#    "review":{"<cid>":["Time Limit Exceeded", …]},        # a grade problema × classe (o que REVISAR)
#    "langs":[{"lang":"py", "problem":"*"|"<cid>", "verdicts":[…], "to":"review"|"auto"}]}   # exceções
# Decisão p/ (cid, linguagem, classe canônica):
#   1. classe fora das 6 (Judge Error, vocabulário legado) → REVISÃO: erro do juiz nunca vaza;
#   2. exceção de linguagem que casa (linguagem canônica + classe + problema ou "*"): a do PROBLEMA
#      vence a de "*"; no mesmo nível, se alguma diz revisão, REVISÃO; senão o `to` decide;
#   3. senão, a grade: classe listada em review[cid] → REVISÃO; não listada → AUTOMÁTICO.
#   Arquivo AUSENTE = v2 vazio = tudo automático. Arquivo ILEGÍVEL = tudo em REVISÃO (na dúvida, segura).
# v1 (o formato anterior, sem "version"): OPT-IN — {"<cid>":{"<lang>|*":[classes AUTOMÁTICAS]}}; o que
# não está listado vai para revisão. Arquivo v1 vale como sempre valeu até alguém salvar pela tela nova,
# que grava o v2 equivalente (rr_view converte). Os dois contests que usaram a matriz até hoje
# (icpc-latam-br-fp-2026 e xiv-maratona-unb) seguem idênticos.
#
# `cid` aceita as duas grafias do id ('col#p' e 'col/p', como o v1 aceitava).

RR_CLASSES="Accepted|Wrong Answer|Time Limit Exceeded|Memory Limit Exceeded|Runtime Error|Compilation Error"
rr_class_ok(){ case "$1" in Accepted|"Wrong Answer"|"Time Limit Exceeded"|"Memory Limit Exceeded"|"Runtime Error"|"Compilation Error") return 0;; esac; return 1; }

# defs jq compartilhadas (prefixe o programa com "$RR_JQ_DEFS")
RR_JQ_DEFS='
def rr_classes: ["Accepted","Wrong Answer","Time Limit Exceeded","Memory Limit Exceeded","Runtime Error","Compilation Error"];
def rr_lang: ascii_downcase | if . == "py2" or . == "py3" then "py" elif . == "cc" or . == "cxx" or . == "c++" or . == "hpp" then "cpp" elif . == "h" then "c" else . end;   # = _lang_canon
def rr_cid2: gsub("/"; "#");
def rr_v2: type == "object" and (((.version // 1) | tonumber? // 1) >= 2);
# rr_hold($cid; $lang; $v): true = vai para REVISÃO (o input é o arquivo de regras)
def rr_hold($cid; $lang; $v):
  . as $r
  | if (($r | type) != "object") then true
    elif ($r | rr_v2) then
      if (rr_classes | index($v)) == null then true
      else
        ($cid | rr_cid2) as $c2 | ($lang | rr_lang) as $l
        | [ ($r.langs // [])[]? | select(type == "object")
            | select(((.lang // "") | tostring | rr_lang) == $l
                     and (((.verdicts // []) | if type == "array" then . else [] end | index($v)) != null)
                     and ((.problem // "*") as $p | $p == $cid or $p == $c2 or $p == "*")) ] as $m
        | [ $m[] | select((.problem // "*") != "*") ] as $sp
        | (if ($sp | length) > 0 then $sp else $m end) as $w
        | if ($w | length) > 0 then any($w[]; (.to // "review") != "auto")
          else ((((($r.review // {})[$cid]) // (($r.review // {})[$c2]) // []) | if type == "array" then . else [] end | index($v)) != null)
          end
      end
    else
      (($r[$cid] // $r[$cid | rr_cid2] // {}) as $m
       | ((($m[$lang | ascii_downcase] // []) + ($m["*"] // [])) | index($v)) == null)
    end;
# rr_view($cids): as regras no formato v2 da TELA (v1 convertido: o complemento do automático),
# só com problemas do contest e as 6 classes
def rr_view($cids):
  . as $r
  | if ($r | rr_v2) then
      {review: ([ $cids[] as $c | {key:$c, value:[ ((($r.review // {})[$c] // ($r.review // {})[$c | rr_cid2]) // [])[]?
                                                    | select(. as $x | rr_classes | index($x)) ] | unique} ] | from_entries),
       langs: [ ($r.langs // [])[]? | select(type == "object")
                | {lang:((.lang // "") | tostring | rr_lang), problem:(.problem // "*"),
                   verdicts:[ (.verdicts // [])[]? | select(. as $x | rr_classes | index($x)) ] | unique,
                   to:(if .to == "auto" then "auto" else "review" end)}
                | select(.lang != "" and (.verdicts | length) > 0 and (.problem == "*" or (.problem as $p | $cids | index($p)))) ]}
    elif ($r | type) == "object" then
      {review: ([ $cids[] as $c | (($r[$c] // $r[$c | rr_cid2] // {}) | if type == "object" then . else {} end) as $m
                  | ($m["*"] // []) as $star
                  | {key:$c, value:[ rr_classes[] | select(. as $x | ($star | index($x)) == null) ]} ] | from_entries),
       langs: [ $cids[] as $c | (($r[$c] // $r[$c | rr_cid2] // {}) | if type == "object" then . else {} end) as $m
                | ($m["*"] // []) as $star
                | $m | to_entries[] | select(.key != "*")
                | {lang:(.key | rr_lang), problem:$c, to:"auto",
                   verdicts:[ (.value // [])[]? | select(. as $x | (rr_classes | index($x)) != null and ($star | index($x)) == null) ] | unique}
                | select((.verdicts | length) > 0) ]}
    else {review:{}, langs:[]} end;
'

# rr_state <contest> -> missing | invalid | v1 | v2
rr_state(){
  local f="$CONTESTSDIR/$1/auto-verdicts.json"
  [[ -e "$f" ]] || { printf missing; return; }
  jq -e 'type == "object"' "$f" >/dev/null 2>&1 || { printf invalid; return; }
  jq -e "$RR_JQ_DEFS rr_v2" "$f" >/dev/null 2>&1 && printf v2 || printf v1
}

# rr_file_hold <contest> <cid> <lang> <classe-canônica> -> 0 = vai para REVISÃO; 1 = sai automático.
# Só "false" do jq libera: erro/arquivo ilegível/saída vazia seguram (na dúvida, um humano olha).
rr_file_hold(){
  local f="$CONTESTSDIR/$1/auto-verdicts.json" out
  if [[ ! -e "$f" ]]; then rr_class_ok "$4" && return 1; return 0; fi
  out="$(jq -r --arg c "$2" --arg l "$3" --arg v "$4" "$RR_JQ_DEFS rr_hold(\$c; \$l; \$v)" "$f" 2>/dev/null)"
  [[ "$out" == false ]] && return 1
  return 0
}

# rr_releasable <contest> <regras-v2-arquivo> -> ids (1/linha) dos itens da fila de revisão ABERTOS, sem
# voto e sem conflito, que estas regras mandariam AUTOMÁTICOS. É o critério do rv_release_uncontested
# (desligar o manual) restrito ao que a regra nova solta. UM jq sobre a fila; item ilegível fica de fora.
rr_releasable(){
  local c="$1" rf="$2" dir="$CONTESTSDIR/$1/review" out files=() f
  [[ -d "$dir" ]] || return 0
  mapfile -d '' files < <(find "$dir" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null)
  (( ${#files[@]} )) || return 0
  local prog="$RR_JQ_DEFS"'
    ($R[0]) as $rules
    | select(type == "object" and (.status // "open") != "released" and ((.votes // []) | length) == 0 and (.conflict != true))
    # bind ANTES: argumento de função jq avalia contra o INPUT dela ($rules), não contra o item
    | ((.problem_id // "") | tostring) as $p | ((.lang // "") | tostring) as $l
    | ((.computed_verdict // "") | tostring | split(",")[0] | split("¦")[0]) as $v
    | select(($rules | rr_hold($p; $l; $v)) == false)
    | .id // empty'
  if out="$(jq -r --slurpfile R "$rf" "$prog" "${files[@]}" 2>/dev/null)"; then
    [[ -n "$out" ]] && printf '%s\n' "$out"; return 0
  fi
  for f in "${files[@]}"; do jq -r --slurpfile R "$rf" "$prog" "$f" 2>/dev/null; done
  return 0
}
