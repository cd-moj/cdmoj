# GET/POST /contest/admin/problems?contest=<id>  (admin DO contest)
# GET  -> [{source,problem_id,name,letter,statement_key}] na ordem atual.
# POST {action, ...}: add | remove | reorder | rename. Reescreve PROBS no conf + auditoria.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
source "$_LIBDIR/contest-create.sh"

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  # inclui linguagens e pool de juízes por problema (problem-{langs,judges}.json, id canônico)
  plf="$CONTESTSDIR/$contest/problem-langs.json"; pl='{}'; [[ -f "$plf" ]] && pl="$(jq -c . "$plf" 2>/dev/null)"; jq -e . >/dev/null 2>&1 <<<"$pl" || pl='{}'
  pjf="$CONTESTSDIR/$contest/problem-judges.json"; pj='{}'; [[ -f "$pjf" ]] && pj="$(jq -c . "$pjf" 2>/dev/null)"; jq -e . >/dev/null 2>&1 <<<"$pj" || pj='{}'
  out="$(jq -c --argjson pl "$pl" --argjson pj "$pj" '[ .[] | . as $p
          | ((if (($p.statement_key // "")|test("#")) then $p.statement_key else (($p.problem_id // "")|gsub("/";"#")) end)) as $cid
          | $p + {languages: ($pl[$cid] // []), judges: ($pj[$cid] // [])} ]' <<<"$(cc_probs_json "$contest")")"
  ok_json '{problems:$p}' --argjson p "$out"
  exit 0
fi

require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
action="$(jq -r '.action // empty' <<<"$body")"
cur="$(cc_probs_json "$contest")"
new=""

case "$action" in
  add)
    prob="$(jq -c '.problem // {}' <<<"$body")"
    [[ "$(jq -r '(.problem_id // .bank_id // "")' <<<"$prob")" != "" ]] || fail 422 "Informe problem_id ou bank_id" "prob_missing"
    # problema PRIVADO só entra se o DONO do contest (arquivo owner, escrito na criação) é
    # dono/colaborador dele — mesmo guard do create.sh, com o dono do contest como sujeito
    # (o login .admin do contest é um nome arbitrário; usá-lo daria acesso por homonímia).
    # Vale p/ QUALQUER .source (como no create): a resolução de enunciado usa só a skey, então
    # um source forjado pularia o gate e ainda serviria jsons-private. Contest legado sem
    # owner => só público. Problema fora do índice passa (privados SEMPRE constam do índice
    # de owners). Negado: 404 p/ não vazar a existência.
    cid_can="$(jq -r '(.bank_id // .problem_id // "")' <<<"$prob")"; cid_can="${cid_can//\//#}"
    cowner="$(head -1 "$CONTESTSDIR/$contest/owner" 2>/dev/null)"
    source "$_LIBDIR/problems.sh"
    verdict="$(owners_merged | jq -r --arg id "$cid_can" --arg o "$cowner" '
      ([.problems[]? | select(.id==$id)] | first) as $p
      | if $p == null then "unknown"
        elif ($p.public == true) then "ok"
        elif ($o != "" and ($p.owner == $o or ((($p.collaborators // [])|index($o)) != null))) then "ok"
        else "deny" end' 2>/dev/null)"
    [[ "$verdict" == deny ]] && fail 404 "Problema não encontrado" "notfound"
    new="$(jq -cn --argjson cur "$cur" --argjson p "$prob" '$cur + [$p]')"
    ;;
  remove)
    L="$(jq -r '.letter // empty' <<<"$body")"
    [[ -n "$L" ]] || fail 400 "Informe a letra" "letter_missing"
    new="$(jq -cn --argjson cur "$cur" --arg l "$L" '[ $cur[] | select(.letter != $l) ]')"
    ;;
  rename)
    L="$(jq -r '.letter // empty' <<<"$body")"
    [[ -n "$L" ]] || fail 400 "Informe a letra" "letter_missing"
    new="$(jq -cn --argjson cur "$cur" --argjson b "$body" --arg l "$L" '
      [ $cur[] | if .letter==$l then
          (if ($b|has("name")) then .name=$b.name else . end)
          | (if ($b|has("new_letter")) then .letter=$b.new_letter else . end)
        else . end ]')"
    ;;
  reorder)
    order="$(jq -c '.order // []' <<<"$body")"
    # letra pela posição: A..Z, depois AA,AB,… ([65+key]|implode puro virava lixo com >26)
    new="$(jq -cn --argjson cur "$cur" --argjson order "$order" '
      def letter($i): if $i < 26 then ([65+$i]|implode) else ([65+(($i/26|floor)-1), 65+($i%26)]|implode) end;
      ($cur | map({(.letter): .}) | add) as $by
      | [ $order | to_entries[] | . as $e | ($by[$e.value] // empty) | (.letter = letter($e.key)) ]')"
    ;;
  langs)
    # linguagens permitidas POR problema (ids canônicos minúsculos). Chaveado pelo id
    # canônico 'coleção#problema' (estável a reordenações). Vazio = herda do contest.
    L="$(jq -r '.letter // empty' <<<"$body")"
    [[ -n "$L" ]] || fail 400 "Informe a letra" "letter_missing"
    cid="$(jq -r --arg l "$L" '[.[]|select(.letter==$l)][0]
            | (if ((.statement_key // "")|test("#")) then .statement_key else ((.problem_id // "")|gsub("/";"#")) end) // empty' <<<"$cur")"
    [[ -n "$cid" ]] || fail 404 "Problema não encontrado" "notfound"
    larr="$(jq -c '(.languages // []) | map(ascii_downcase | select(test("^[a-z0-9_+.-]+$"))) | unique' <<<"$body")"
    plf="$CONTESTSDIR/$contest/problem-langs.json"
    base='{}'; [[ -f "$plf" ]] && base="$(cat "$plf" 2>/dev/null)"; jq -e . >/dev/null 2>&1 <<<"$base" || base='{}'
    if [[ "$(jq 'length' <<<"$larr")" -gt 0 ]]; then
      printf '%s' "$base" | jq -c --arg id "$cid" --argjson v "$larr" '.[$id]=$v' > "$plf.tmp" && mv -f "$plf.tmp" "$plf"
    else
      printf '%s' "$base" | jq -c --arg id "$cid" 'del(.[$id])' > "$plf.tmp" && mv -f "$plf.tmp" "$plf"
    fi
    audit_log_to "$contest" problems-langs "letter=$L id=$cid langs=$(jq -r 'join(",")' <<<"$larr")"
    ok_json '{saved:true, problem_id:$id, languages:$v}' --arg id "$cid" --argjson v "$larr"
    exit 0
    ;;
  judges)
    # pool de juízes POR problema (hostnames do registro). Chaveado pelo id canônico
    # 'coleção#problema' (estável a reordenações). Vazio = herda o pool do contest.
    L="$(jq -r '.letter // empty' <<<"$body")"
    [[ -n "$L" ]] || fail 400 "Informe a letra" "letter_missing"
    cid="$(jq -r --arg l "$L" '[.[]|select(.letter==$l)][0]
            | (if ((.statement_key // "")|test("#")) then .statement_key else ((.problem_id // "")|gsub("/";"#")) end) // empty' <<<"$cur")"
    [[ -n "$cid" ]] || fail 404 "Problema não encontrado" "notfound"
    jarr="$(jq -c '(.judges // []) | map(select(type=="string") | select(test("^[A-Za-z0-9._-]+$"))) | unique' <<<"$body")"
    [[ "$jarr" == *..* ]] && fail 422 "hostname inválido" "judges_invalid"
    pjf="$CONTESTSDIR/$contest/problem-judges.json"
    base='{}'; [[ -f "$pjf" ]] && base="$(cat "$pjf" 2>/dev/null)"; jq -e . >/dev/null 2>&1 <<<"$base" || base='{}'
    if [[ "$(jq 'length' <<<"$jarr")" -gt 0 ]]; then
      printf '%s' "$base" | jq -c --arg id "$cid" --argjson v "$jarr" '.[$id]=$v' > "$pjf.tmp" && mv -f "$pjf.tmp" "$pjf"
    else
      printf '%s' "$base" | jq -c --arg id "$cid" 'del(.[$id])' > "$pjf.tmp" && mv -f "$pjf.tmp" "$pjf"
    fi
    audit_log_to "$contest" problems-judges "letter=$L id=$cid judges=$(jq -r 'join(",")' <<<"$jarr")"
    ok_json '{saved:true, problem_id:$id, judges:$v}' --arg id "$cid" --argjson v "$jarr"
    exit 0
    ;;
  statement)
    # enunciado por problema: enviar HTML/PDF (base64), remover, ou "atualizar do banco"
    # (limpa o cache enunciados/<skey>.html e re-indexa o pacote canônico).
    L="$(jq -r '.letter // empty' <<<"$body")"
    [[ -n "$L" ]] || fail 400 "Informe a letra" "letter_missing"
    skey="$(jq -r --arg l "$L" '[.[]|select(.letter==$l)][0].statement_key // empty' <<<"$cur")"
    [[ -n "$skey" ]] || fail 404 "Problema não encontrado" "notfound"
    { [[ "$skey" =~ ^[A-Za-z0-9._#@+-]+$ ]] && [[ "$skey" != *..* ]]; } || fail 422 "chave de enunciado inválida" "skey_invalid"
    cid="$(jq -r --arg l "$L" '[.[]|select(.letter==$l)][0] | (if ((.statement_key//"")|test("#")) then .statement_key else ((.problem_id//"")|gsub("/";"#")) end) // empty' <<<"$cur")"
    edir="$CONTESTSDIR/$contest/enunciados"; mkdir -p "$edir"
    did=""
    hb="$(jq -r '.html_b64 // empty' <<<"$body")"
    if [[ -n "$hb" ]]; then
      printf '%s' "$hb" | base64 -d > "$edir/$skey.html.tmp" 2>/dev/null && mv -f "$edir/$skey.html.tmp" "$edir/$skey.html" \
        || { rm -f "$edir/$skey.html.tmp"; fail 422 "HTML inválido (base64)" "html_b64"; }
      did="html"
    fi
    pb="$(jq -r '.pdf_b64 // empty' <<<"$body")"
    if [[ -n "$pb" ]]; then
      printf '%s' "$pb" | base64 -d > "$edir/$skey.pdf.tmp" 2>/dev/null && mv -f "$edir/$skey.pdf.tmp" "$edir/$skey.pdf" \
        || { rm -f "$edir/$skey.pdf.tmp"; fail 422 "PDF inválido (base64)" "pdf_b64"; }
      did="$did pdf"
    fi
    [[ "$(jq -r '.remove_html // false' <<<"$body")" == true ]] && { rm -f "$edir/$skey.html"; did="$did -html"; }
    [[ "$(jq -r '.remove_pdf  // false' <<<"$body")" == true ]] && { rm -f "$edir/$skey.pdf";  did="$did -pdf"; }
    if [[ "$(jq -r '.refresh // false' <<<"$body")" == true && -n "$cid" ]]; then
      rm -f "$edir/$skey.html"   # remove o cache -> /contest/problems volta a buscar/cachear do banco
      source "$_DIR/../../judge-gw/sched-lib.sh" 2>/dev/null || true
      declare -F idx_request >/dev/null && idx_request "${cid%%#*}" "$cid" "contest-stmt:$SESSION_LOGIN" >/dev/null 2>&1 || true
      did="$did refresh"
    fi
    [[ -n "$did" ]] || fail 422 "Nada a fazer (envie html_b64/pdf_b64, remove_*, ou refresh)" "noop"
    audit_log_to "$contest" problems-statement "letter=$L skey=$skey op=$did"
    ok_json '{saved:true, statement_key:$k, did:$d}' --arg k "$skey" --arg d "$did"
    exit 0
    ;;
  *) fail 400 "action inválida (add|remove|reorder|rename|langs|judges|statement)" "action_invalid" ;;
esac

[[ -n "$new" ]] || fail 422 "Nada a fazer" "noop"
cc_set_probs "$contest" "$new" || fail 422 "Falha ao gravar problemas (dados inválidos?)" "probs_write"
audit_log_to "$contest" "problems-$action" "$(jq -cr '. | del(.problem.statement_b64)' <<<"$body" 2>/dev/null | head -c 300)"
ok_json '{saved:true, problems:$p}' --argjson p "$(cc_probs_json "$contest")"
