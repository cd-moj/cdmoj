# GET /treino/virtual/docs?contest=<cid>   (Bearer do TREINO)
# OS ARQUIVOS DA PROVA no virtual (10/11/2026; decisão do Ribas): os documentos PUBLICADOS do contest (caderno, ambiente
# de julgamento, tempos-limite — `docs/config.json` `.published`, só os que têm PDF servido) a partir da LARGADA, e o
# EDITORIAL só com a run terminada (antes ele sai como `locked`, sem idiomas: o time sabe que existe e quando abre).
# Mais os links EXTERNOS do resources.json (http/https; arquivo interno do contest pede login dele) — SÓ com a run
# terminada (revisão de 10/11/2026): o link não tem data e aponta p/ o ESTADO ATUAL de fora (placar final, vídeo das
# soluções); rodando sai só `links_locked:true` quando existe algum. O download é o
# /treino/virtual/doc, com a MESMA regra. Run não largada = 403 `virtual_not_started`.
require_method GET
require_auth_contest treino
source "$_LIBDIR/virtual.sh"
source "$_LIBDIR/contest-docs.sh"
cid="$(param contest)"; vr_gate "$cid"
vr_clock "$SESSION_LOGIN" "$cid" || fail 403 "Comece a participação virtual para ver os arquivos" "virtual_not_started"
pub="$(doc_conf_get "$cid" | jq -r '(.published // [])[] | strings' 2>/dev/null)"
rows=""
for ty in contest info-sheet times editorial; do
  for l in $DOC_LANGS; do
    grep -qxF "$ty.$l" <<<"$pub" || continue
    [[ -n "$(doc_pdf_served "$cid" "$ty" "$l")" ]] || continue
    rows+="$ty"$'\t'"$l"$'\n'
  done
done
links='[]'
f="$CONTESTSDIR/$cid/resources.json"
if [[ -s "$f" ]]; then
  links="$(jq -c '[ .[]? | objects | select(((.type // "") | length) == 0)
                    | select((.url // "" | tostring) | test("^https?://"))
                    | {label:(.label // .url | tostring), url:(.url | tostring)} ]' "$f" 2>/dev/null)"
  [[ -n "$links" ]] || links='[]'
fi
nlinks="$(jq 'length' <<<"$links")"; (( VR_ENDED )) || links='[]'
ok_json '{contest:$c, ended:$ended, links_locked:(($ended | not) and $nl > 0),
          docs: ($rows | split("\n") | map(select(length > 0) | split("\t") | {type:.[0], lang:.[1]})
                 | group_by(.type) | map({type:.[0].type, langs:map(.lang)})
                 | map(if .type == "editorial" and ($ended | not) then {type, locked:true, langs:[]} else . + {locked:false} end)
                 | sort_by({contest:0, "info-sheet":1, times:2, editorial:3}[.type])),
          links:$links}' \
  --arg c "$VR_CID" --arg rows "$rows" --argjson links "$links" --argjson nl "${nlinks:-0}" --argjson ended "$( (( VR_ENDED )) && echo true || echo false )"
