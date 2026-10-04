# GET/POST /contest/admin/problems?contest=<id>  (admin DO contest)
# GET  -> {problems:[{source,problem_id,name,letter,statement_key,languages,judges,titles?}], name_lang}
#         na ordem atual. `titles` {pt,en,es} = os títulos do banco quando há MAIS DE UM (enunciado
#         traduzido): as opções de nome da tela. `name_lang` = o idioma do nome padrão (cc_prob_lang).
# POST {action, ...}: add | remove | reorder | rename | apply_titles | langs | judges | statement.
#   add sem `name` = o título do banco no idioma da prova (cc_prob_title). apply_titles {letters?} troca
#   pelo título no idioma da prova o nome que é um título do banco em OUTRO idioma (cc_title_fixes; nome
#   personalizado ou escolhido pelo `rename` nunca). Reescreve PROBS no conf + auditoria.
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
  cur="$(cc_probs_json "$contest")"
  # títulos por idioma (até 200 problemas × 3 títulos: por ARQUIVO, nunca por argv)
  tmf="$(mktemp)" || fail 500 "tmp" "tmp"
  cc_bank_titles "$(jq -c "$CC_PROB_CID_JQ"' [.[] | cid]' <<<"$cur")" > "$tmf"
  jq -e 'type == "object"' "$tmf" >/dev/null 2>&1 || echo '{}' > "$tmf"
  out="$(jq -c --argjson pl "$pl" --argjson pj "$pj" --slurpfile tm "$tmf" "$CC_PROB_CID_JQ"'($tm[0] // {}) as $TM | [ .[] | . as $p
          | ($p | cid) as $cid | ($TM[$cid] // {}) as $x
          | $p + {languages: ($pl[$cid] // []), judges: ($pj[$cid] // [])}
               + (if ([$x[]] | unique | length) > 1 then {titles: $x} else {} end) ]' <<<"$cur")"
  rm -f "$tmf"
  ok_json '{problems:$p, name_lang:$l}' --argjson p "$out" --arg l "$(cc_prob_lang "$contest")"
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
    # letra explícita não pode colidir (sem diferenciar caixa): a letra é a CHAVE de
    # rename/remove/reorder — ver cc_letters_used em lib/contest-create.sh. Sem letra, o
    # cc_build_probs dá a 1ª LIVRE (antes era a da posição e duplicava com lacuna na sequência).
    NLADD="$(jq -r '.letter // empty' <<<"$prob")"
    if [[ -n "$NLADD" ]]; then
      jq -e --arg n "$NLADD" 'any(.[]; ((.letter // "") | ascii_upcase) == ($n | ascii_upcase))' <<<"$cur" >/dev/null 2>&1 \
        && fail 422 "Já existe um problema com esse identificador" "letter_taken"
    fi
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
    # acesso do DONO do contest ao problema privado: dono, colaborador ou MEMBRO da org —
    # o predicado único problems_denied_for (o mesmo do wizard e de Evento › Rodadas)
    denied="$(problems_denied_for "$cowner" "$(jq -cn --arg id "$cid_can" '[$id]')")" \
      || fail 503 "Índice de problemas indisponível" "index_unavailable"
    [[ -n "$denied" ]] && fail 404 "Problema não encontrado" "notfound"
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
    NLCHK="$(jq -r '.new_letter // empty' <<<"$body")"
    if [[ -n "$NLCHK" && "$NLCHK" != "$L" ]]; then
      # sem diferenciar caixa e sem contar a própria entrada ("c" → "C" é legítimo)
      jq -e --arg l "$L" --arg n "$NLCHK" '([ to_entries[] | select(.value.letter == $l) | .key ][0]) as $k
        | any(to_entries[]; .key != $k and ((.value.letter // "") | ascii_upcase) == ($n | ascii_upcase))' <<<"$cur" >/dev/null 2>&1 \
        && fail 422 "Já existe um problema com esse identificador" "letter_taken"
    fi
    # só a PRIMEIRA entrada com a letra: normalmente é a única; num contest que já tem letra repetida
    # (criado antes do conserto da letra livre), é o que permite desfazer a duplicata pela interface
    new="$(jq -cn --argjson cur "$cur" --argjson b "$body" --arg l "$L" '
      ([ $cur | to_entries[] | select(.value.letter == $l) | .key ][0]) as $k
      | [ $cur | to_entries[] | if .key == $k then (.value
            | (if ($b|has("name")) then .name=$b.name else . end)
            | (if ($b|has("new_letter")) then .letter=$b.new_letter else . end))
          else .value end ]')"
    # nome dado pelo `rename` é ESCOLHA do admin: a Central (prob_names) não insiste em trocá-lo pelo título
    # no idioma da prova (cc_title_fixes). Chave = id canônico, que não muda com a letra.
    if jq -e 'has("name")' >/dev/null 2>&1 <<<"$body"; then
      rcid="$(jq -r --arg l "$L" "$CC_PROB_CID_JQ"'[.[] | select(.letter == $l)][0] | cid // empty' <<<"$cur")"
      if [[ -n "$rcid" ]]; then
        kf="$(cc_names_chosen_file "$contest")"; mkdir -p "${kf%/*}" 2>/dev/null
        kb='{}'; [[ -s "$kf" ]] && kb="$(cat "$kf" 2>/dev/null)"; jq -e 'type == "object"' >/dev/null 2>&1 <<<"$kb" || kb='{}'
        jq -c --arg id "$rcid" --arg n "$(jq -r '.name // ""' <<<"$body")" '.[$id] = $n' <<<"$kb" > "$kf.tmp" 2>/dev/null \
          && mv -f "$kf.tmp" "$kf" || rm -f "$kf.tmp"
      fi
    fi
    # a cor do balão é chaveada pela LETRA (balloons.json): a letra renomeada leva a cor junto
    # (COPIA em vez de mover quando a letra velha segue em uso — o caso da duplicata desfeita)
    NL="$(jq -r '.new_letter // empty' <<<"$body")"
    if [[ -n "$NL" && "$NL" != "$L" && -s "$CONTESTSDIR/$contest/balloons.json" ]]; then
      bf="$CONTESTSDIR/$contest/balloons.json"
      still="$(jq -r --arg l "$L" 'any(.[]; .letter == $l)' <<<"$new" 2>/dev/null)"; [[ "$still" == true ]] || still=false
      jq -c --arg o "$L" --arg n "$NL" --argjson keep "$still" \
        'if (has($o) and (has($n)|not)) then (.[$n] = .[$o] | if $keep then . else del(.[$o]) end) else . end' \
        "$bf" > "$bf.tmp" 2>/dev/null && mv -f "$bf.tmp" "$bf" || rm -f "$bf.tmp"
    fi
    ;;
  apply_titles)
    # o botão da Central (prob_names): nome = título do banco em outro idioma ⇒ o título no idioma da prova.
    # `letters` (opcional) restringe; sem nada a trocar = 200 com changed:[] (o clique duplo não é erro).
    fixes="$(cc_title_fixes "$contest")"; [[ -n "$fixes" ]] || fixes='[]'
    only="$(jq -c '.letters // null' <<<"$body")"
    fixes="$(jq -c --argjson o "$only" 'if ($o | type) == "array" then map(select(.letter as $l | $o | index($l))) else . end' <<<"$fixes")"
    if [[ "$(jq 'length' <<<"$fixes")" == 0 ]]; then
      ok_json '{saved:false, changed:[], problems:$p}' --argjson p "$cur"
      exit 0
    fi
    new="$(jq -cn --argjson cur "$cur" --argjson f "$fixes" '
      ($f | map({key:.letter, value:.to}) | from_entries) as $to
      | [ $cur[] | if ($to[.letter] != null) then .name = $to[.letter] else . end ]')"
    cc_set_probs "$contest" "$new" || fail 422 "Falha ao gravar problemas (dados inválidos?)" "probs_write"
    audit_log_to "$contest" problems-apply_titles "$(jq -cr 'map(.letter + "→" + .lang) | join(" ")' <<<"$fixes" | head -c 300)"
    mkdir -p "$CONTESTSDIR/$contest/var" 2>/dev/null; touch "$CONTESTSDIR/$contest/var/.problems-dirty" 2>/dev/null
    ok_json '{saved:true, changed:$f, problems:$p}' --argjson f "$fixes" --argjson p "$(cc_probs_json "$contest")"
    exit 0
    ;;
  reorder)
    order="$(jq -c '.order // []' <<<"$body")"
    # letra repetida na ordem duplicaria a entrada (o $by[...] a acha duas vezes) e sumiria com outra
    odup="$(cc_letters_dup "$(jq -c 'map({letter: .})' <<<"$order" 2>/dev/null)")"
    [[ -z "$odup" ]] || fail 422 "Letra repetida na ordem: $odup" "letter_dup"
    # letra pela posição: A..Z, depois AA,AB,… ([65+key]|implode puro virava lixo com >26).
    # SÓ re-letra quando as letras atuais JÁ são a sequência automática (contest clássico):
    # letra CUSTOMIZADA (W1..W4, Q/R/S…) sobrevive à reordenação — o ↑/↓ da UI apagava os
    # identificadores do aquecimento e não havia como recolocá-los.
    new="$(jq -cn --argjson cur "$cur" --argjson order "$order" '
      def letter($i): if $i < 26 then ([65+$i]|implode) else ([65+(($i/26|floor)-1), 65+($i%26)]|implode) end;
      ($cur | to_entries | all(.value.letter == letter(.key))) as $auto
      | ($cur | map({(.letter): .}) | add) as $by
      | [ $order | to_entries[] | . as $e | ($by[$e.value] // empty)
          | (if $auto then .letter = letter($e.key) else . end) ]')"
    ;;
  langs)
    # linguagens permitidas POR problema (ids canônicos minúsculos). Chaveado pelo id
    # canônico 'coleção#problema' (estável a reordenações). Vazio = herda do contest.
    L="$(jq -r '.letter // empty' <<<"$body")"
    [[ -n "$L" ]] || fail 400 "Informe a letra" "letter_missing"
    cid="$(jq -r --arg l "$L" '[.[]|select(.letter==$l)][0]
            | (if ((.statement_key // "")|test("#")) then .statement_key else ((.problem_id // "")|gsub("/";"#")) end) // empty' <<<"$cur")"
    [[ -n "$cid" ]] || fail 404 "Problema não encontrado" "notfound"
    larr="$(jq -c '(.languages // []) | map(ascii_downcase
            | (if .=="py3" or .=="py2" then "py" else . end)
            | select(test("^[a-z0-9_+.-]+$"))) | unique' <<<"$body")"
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
    # IDIOMA do arquivo (2026-09-15): `lang` pt|en|es (default pt) -> <skey>.html | <skey>.<lang>.html
    source "$_LIBDIR/contest-statement.sh"
    slang="$(jq -r '.lang // "pt"' <<<"$body")"
    stmt_lang_ok "$slang" || fail 400 "lang inválido ($(stmt_langs_all))" "lang_invalid"
    sfx=""; [[ "$slang" != pt ]] && sfx=".$slang"
    did=""
    hb="$(jq -r '.html_b64 // empty' <<<"$body")"
    if [[ -n "$hb" ]]; then
      printf '%s' "$hb" | base64 -d > "$edir/$skey$sfx.html.tmp" 2>/dev/null && mv -f "$edir/$skey$sfx.html.tmp" "$edir/$skey$sfx.html" \
        || { rm -f "$edir/$skey$sfx.html.tmp"; fail 422 "HTML inválido (base64)" "html_b64"; }
      did="html$sfx"
    fi
    pb="$(jq -r '.pdf_b64 // empty' <<<"$body")"
    if [[ -n "$pb" ]]; then
      printf '%s' "$pb" | base64 -d > "$edir/$skey$sfx.pdf.tmp" 2>/dev/null && mv -f "$edir/$skey$sfx.pdf.tmp" "$edir/$skey$sfx.pdf" \
        || { rm -f "$edir/$skey$sfx.pdf.tmp"; fail 422 "PDF inválido (base64)" "pdf_b64"; }
      did="$did pdf$sfx"
    fi
    [[ "$(jq -r '.remove_html // false' <<<"$body")" == true ]] && { rm -f "$edir/$skey$sfx.html"; did="$did -html$sfx"; }
    [[ "$(jq -r '.remove_pdf  // false' <<<"$body")" == true ]] && { rm -f "$edir/$skey$sfx.pdf";  did="$did -pdf$sfx"; }
    if [[ "$(jq -r '.refresh // false' <<<"$body")" == true && -n "$cid" ]]; then
      # remove o cache (PT e TODAS as traduções) -> /contest/problems volta a buscar/cachear do banco
      rm -f "$edir/$skey.html"
      for _l in $(stmt_langs_all); do [[ "$_l" == pt ]] || rm -f "$edir/$skey.$_l.html"; done
      # reindexa NO SERVIDOR (o antigo idx_request enfileirava kind=index p/ o juiz, que responde
      # "legado, nada a fazer" — era no-op e o "refresh" não refrescava nada).
      source "$_DIR/lib/tl-store.sh" 2>/dev/null || true
      declare -F index_problem_bg >/dev/null && index_problem_bg "$cid" 1 >/dev/null 2>&1 || true
      did="$did refresh"
    fi
    [[ -n "$did" ]] || fail 422 "Nada a fazer (envie html_b64/pdf_b64, remove_*, ou refresh)" "noop"
    audit_log_to "$contest" problems-statement "letter=$L skey=$skey lang=$slang op=$did"
    mkdir -p "$CONTESTSDIR/$contest/var" 2>/dev/null; touch "$CONTESTSDIR/$contest/var/.problems-dirty" 2>/dev/null
    ok_json '{saved:true, statement_key:$k, lang:$l, did:$d}' --arg k "$skey" --arg l "$slang" --arg d "$did"
    exit 0
    ;;
  *) fail 400 "action inválida (add|remove|reorder|rename|apply_titles|langs|judges|statement)" "action_invalid" ;;
esac

[[ -n "$new" ]] || fail 422 "Nada a fazer" "noop"
cc_set_probs "$contest" "$new" || fail 422 "Falha ao gravar problemas (dados inválidos?)" "probs_write"
audit_log_to "$contest" "problems-$action" "$(jq -cr '. | del(.problem.statement_b64)' <<<"$body" 2>/dev/null | head -c 300)"
# invalida o cache de /contest/problems NA HORA. O handler também confere as entradas por mtime
# (conf, os dois json, enunciados/) e tem teto de idade, então isto é o caminho rápido, não a
# única garantia — mas é o que faz a mudança do admin aparecer no próximo carregamento do time.
mkdir -p "$CONTESTSDIR/$contest/var" 2>/dev/null; touch "$CONTESTSDIR/$contest/var/.problems-dirty" 2>/dev/null
ok_json '{saved:true, problems:$p}' --argjson p "$(cc_probs_json "$contest")"
