# POST /judge/result   (Bearer mojw_<token>)
# O worker devolve o resultado do julgamento. Para o judged.sh seguir sendo o ÚNICO
# escritor do history, gravamos o payload num arquivo de spool "result" que o daemon
# ingere (instala report.html, escreve results/<id>.json, atualiza history/data/placar).
# body: {host, id, contest, problem_id, login, lang, verdict, score, correct,
#        total_tests, duration_s, tl_used, tests:[{name,verdict,code,time,tl}], report_html_b64}
require_method POST
require_worker
source "$_DIR/../../judge-gw/sched-lib.sh"

# dieta 2026-08-30: o corpo carrega o report_html_b64 INTEIRO — em variável, cada
# `<<<"$body"` o regrava num temp e re-parseia (eram 5 parses; doutrina do read_body_file).
# Agora: corpo em ARQUIVO + UMA extração (validação inclusa: JSON ruim quebra o próprio jq).
bf="$(read_body_file)"
_ext="$(jq -j '[ (.id // ""), (.host // ""), (.contest // ""), (.problem_id // "") ]
               | join("\u0001")' "$bf" 2>/dev/null)" \
  || { rm -f "$bf"; fail 400 "Invalid JSON body" "bad_json"; }
IFS=$'\x01' read -r id host contest problem <<<"$_ext"
[[ -n "$id" && -n "$host" && -n "$contest" ]] || { rm -f "$bf"; fail 400 "Missing id/host/contest" "result_incomplete"; }
valid_id "$id"        || fail 400 "Invalid id" "id_invalid"
valid_hostname "$host"|| fail 400 "Invalid host" "host_invalid"
valid_id "$contest"   || fail 400 "Invalid contest" "contest_invalid"

# remove o job reivindicado (idempotente) e marca o worker livre p/ o próximo beat
q_done "$host" "$id"
reg_touch_state "$host" free 2>/dev/null || true

# grava o payload no spool p/ o judged.sh finalizar (escritor único do history).
# nome: <contest>:<epoch>:<id>:<host>:result:<problem>  (.in.* = escrita atômica)
AGORA="$EPOCHSECONDS"
spoolname="$contest:$AGORA:$id:$host:result:$problem"
mkdir -p "$SPOOLDIR" 2>/dev/null
tmp="$SPOOLDIR/.in.result.$id.${BASHPID}"
# o corpo já está em arquivo: cp + mv atômico (fs diferentes); o jq -e de validação
# virou parte da extração acima
cp -f "$bf" "$tmp" && mv -f "$tmp" "$SPOOLDIR/$spoolname"
rm -f "$bf"

ok_json '{id:$i, accepted:true}' --arg i "$id"
