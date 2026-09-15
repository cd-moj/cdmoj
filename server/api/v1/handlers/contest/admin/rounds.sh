# GET/POST /contest/admin/rounds?contest=<c>
# RODADAS do contest (aquecimento → prova oficial no MESMO contest). Motor: lib/contest-rounds.sh.
# Leitura: admin OU juiz-chefe. Escrita/promoção: só admin (a promoção arquiva e zera o placar).
#
# GET  -> {active, rounds:[{slug,name,kind,start,end,freeze,state,published,problems,stats?}],
#          next, promote_ready:{ok, blockers:[{code,detail}]}}
# POST {action}:
#   add      {slug,name?,kind?,start,end,freeze?}   — cria rodada PLANEJADA
#   set      {slug,new_slug?,name?,start?,end?,freeze?,kind?,colors?} — edita/renomeia (a ATIVA
#              vai direto p/ o conf). colors = cores de balão DA RODADA (formato do balloons.json;
#              null remove; {} não mexe; ausente na rodada = herda as cores em vigor ao promover)
#   problems {slug, problems:[{bank_id|problem_id,name?,letter?}]} — só o que o DONO do contest
#              pode usar (público, dono, colaborador ou membro da org: problems_denied_for)
#   remove   {slug}            — só rodada planejada (arquivada é auditoria, nunca some)
#   publish  {slug, on:bool}   — arquivo da rodada visível p/ os times
#   promote  {to?, force?}     — arquiva a ativa e coloca a próxima no ar
require_auth_contest "$(param contest)"
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
source "$_DIR/lib/users.sh"; source "$_DIR/lib/contest-create.sh"
source "$_DIR/lib/contest-gate.sh"; source "$_DIR/lib/print.sh"
source "$_DIR/lib/contest-rounds.sh"

if [[ "$REQUEST_METHOD" == GET ]]; then
  is_admin_or_chief || fail 403 "Apenas o admin ou o juiz-chefe" "admin_required"
  j="$(rd_sync_active "$contest")"; [[ -n "$j" ]] || fail 500 "Falha ao ler as rodadas" "rounds_read"
  rd_save "$contest" "$j"                       # persiste o espelho conf→json
  bl="$(rd_promote_blockers "$contest")"; [[ -n "$bl" ]] || bl='[]'
  body="$(jq -cn --argjson j "$j" --argjson bl "$bl" --arg next "$(rd_next "$contest")" '
    {success:true, active:($j.active // ""), rounds:($j.rounds // []), next:$next,
     promote_ready:{ok:(($bl|length) == 0), blockers:$bl}}')"
  [[ -n "$body" ]] || fail 500 "Falha ao montar a resposta" "build_fail"
  emit_json 200 OK; printf '%s\n' "$body"; exit 0
fi

require_method POST
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
bodyf="$(read_body_file)"
jq -e . "$bodyf" >/dev/null 2>&1 || fail 400 "JSON inválido" "bad_json"
action="$(jq -r '.action // ""' "$bodyf")"
slug="$(jq -r '.slug // ""' "$bodyf")"

j="$(rd_sync_active "$contest")"; [[ -n "$j" ]] || fail 500 "Falha ao ler as rodadas" "rounds_read"

case "$action" in
  add)
    rd_valid_slug "$slug" || fail 422 "slug inválido (a-z, 0-9, - e _; até 32)" "slug_invalid"
    jq -e --arg s "$slug" '(.rounds // []) | map(.slug) | index($s) != null' <<<"$j" >/dev/null 2>&1 \
      && fail 409 "já existe uma rodada '$slug'" "slug_taken"
    (( $(jq '(.rounds // []) | length' <<<"$j") < 12 )) || fail 422 "máximo de 12 rodadas" "too_many"
    st="$(jq -r '.start // 0' "$bodyf")"; en="$(jq -r '.end // 0' "$bodyf")"
    fz="$(jq -r '.freeze // 0' "$bodyf")"
    for v in "$st" "$en" "$fz"; do [[ "$v" =~ ^[0-9]+$ ]] || fail 422 "datas em epoch" "epoch_invalid"; done
    (( en > st )) || fail 422 "o fim deve ser depois do início" "end_before_start"
    { (( fz == 0 )) || { (( fz > st )) && (( fz < en )); }; } || fail 422 "o freeze deve cair dentro da janela" "freeze_outside"
    nm="$(jq -r '.name // ""' "$bodyf")"; [[ -n "$nm" ]] || nm="$slug"
    kd="$(jq -r '.kind // "official"' "$bodyf")"
    case "$kd" in warmup|official|extra) ;; *) fail 422 "kind deve ser warmup|official|extra" "kind_invalid";; esac
    j="$(jq -c --arg s "$slug" --arg n "$nm" --arg k "$kd" --argjson st "$st" --argjson en "$en" --argjson fz "$fz" \
        '.rounds = ((.rounds // []) + [{slug:$s, name:$n, kind:$k, start:$st, end:$en, freeze:$fz,
                                        state:"pending", published:false, problems:[]}])' <<<"$j")"
    rd_save "$contest" "$j"
    mod_enable "$contest" rodadas
    audit_log_to "$contest" round-add "slug=$slug kind=$kd start=$st end=$en"
    ok_json '{saved:true, rounds:$r}' --argjson r "$(jq -c '.rounds' <<<"$j")"
    ;;
  set)
    rd_valid_slug "$slug" || fail 422 "slug inválido" "slug_invalid"
    cur="$(jq -c --arg s "$slug" '(.rounds // [])[] | select(.slug == $s)' <<<"$j")"
    [[ -n "$cur" ]] || fail 404 "rodada não encontrada" "round_notfound"
    [[ "$(jq -r '.state' <<<"$cur")" == archived ]] && fail 409 "rodada arquivada não muda (é auditoria)" "round_archived"
    for k in start end freeze; do
      jq -e --arg k "$k" 'has($k)' "$bodyf" >/dev/null 2>&1 || continue
      v="$(jq -r --arg k "$k" '.[$k]' "$bodyf")"
      [[ "$v" =~ ^[0-9]+$ ]] || fail 422 "$k em epoch" "epoch_invalid"
      cur="$(jq -c --arg k "$k" --argjson v "$v" '.[$k]=$v' <<<"$cur")"
    done
    (( $(jq -r '.end' <<<"$cur") > $(jq -r '.start' <<<"$cur") )) || fail 422 "o fim deve ser depois do início" "end_before_start"
    fz="$(jq -r '.freeze // 0' <<<"$cur")"
    { (( fz == 0 )) || { (( fz > $(jq -r '.start' <<<"$cur") )) && (( fz < $(jq -r '.end' <<<"$cur") )); }; } \
      || fail 422 "o freeze deve cair dentro da janela" "freeze_outside"
    # renomear (o contest nasce com a rodada corrente chamada "oficial"; quem vai rodar
    # aquecimento primeiro precisa rebatizá-la). Arquivada não muda — o dir rounds/<slug> já existe.
    if jq -e 'has("new_slug")' "$bodyf" >/dev/null 2>&1; then
      ns="$(jq -r '.new_slug' "$bodyf")"
      rd_valid_slug "$ns" || fail 422 "new_slug inválido" "slug_invalid"
      if [[ "$ns" != "$slug" ]]; then
        jq -e --arg s "$ns" '(.rounds // []) | map(.slug) | index($s) != null' <<<"$j" >/dev/null 2>&1 \
          && fail 409 "já existe uma rodada '$ns'" "slug_taken"
        cur="$(jq -c --arg s "$ns" '.slug=$s' <<<"$cur")"
        j="$(jq -c --arg o "$slug" --arg s "$ns" \
             '(if .active == $o then .active = $s else . end)
              | .rounds = [ .rounds[] | if .slug == $o then (.slug = $s) else . end ]' <<<"$j")"
        rd_save "$contest" "$j"; slug="$ns"
      fi
    fi
    for k in name kind; do
      jq -e --arg k "$k" 'has($k)' "$bodyf" >/dev/null 2>&1 || continue
      v="$(jq -r --arg k "$k" '.[$k]' "$bodyf")"
      [[ "$k" == kind ]] && { case "$v" in warmup|official|extra) ;; *) fail 422 "kind inválido" "kind_invalid";; esac; }
      cur="$(jq -c --arg k "$k" --arg v "$v" '.[$k]=$v' <<<"$cur")"
    done
    # cores de balão POR RODADA (2026-09-14): objeto = grava na rodada (letra -> RRGGBB, enableSonic);
    # null = a rodada volta a herdar as cores em vigor; {} = o editor não mexeu. Na rodada ATIVA o
    # rd_apply_obj abaixo grava o balloons.json na hora (é o mesmo que Evento › Balões).
    if jq -e 'has("colors")' "$bodyf" >/dev/null 2>&1; then
      cl="$(jq -c '.colors' "$bodyf")"
      if [[ "$cl" == null ]]; then cur="$(jq -c 'del(.colors)' <<<"$cur")"
      elif [[ "$(jq 'if type=="object" then length else -1 end' <<<"$cl")" -gt 0 ]]; then
        jq -e 'to_entries | all(.[]; (.key == "enableSonic" and (.value|type) == "boolean")
                 or ((.key|test("^[A-Z][A-Z0-9]{0,2}$")) and ((.value|type) == "string") and (.value|test("^[0-9A-Fa-f]{6}$"))))'           <<<"$cl" >/dev/null 2>&1 || fail 422 "colors: chaves = letras (RRGGBB) e enableSonic (bool)" "colors_invalid"
        cur="$(jq -c --argjson cl "$cl" '.colors=$cl' <<<"$cur")"
      elif [[ "$cl" != '{}' ]]; then fail 422 "colors deve ser objeto ou null" "colors_invalid"; fi
    fi
    # a rodada ATIVA vive no conf: mexer no freeze dela é o 5º caminho de descongelar — mesma
    # guarda dos outros quatro (fim geral + 1 min), ANTES de gravar qualquer coisa
    if [[ "$(jq -r '.active' <<<"$j")" == "$slug" ]]; then
      declare -F freeze_change_guard >/dev/null || source "$_LIBDIR/contest-gate.sh"
      freeze_change_guard "$contest" "$fz"
    fi
    j="$(jq -c --arg s "$slug" --argjson r "$cur" '.rounds = [ .rounds[] | if .slug == $s then $r else . end ]' <<<"$j")"
    rd_save "$contest" "$j"
    # a rodada ATIVA vive no conf: aplica na hora, a partir do OBJETO editado (passar pelo slug
    # releria via rd_sync_active, que re-espelha a janela do conf por cima — edição no-op)
    [[ "$(jq -r '.active' <<<"$j")" == "$slug" ]] && { rd_apply_obj "$contest" "$cur" || fail 500 "Falha ao gravar no conf" "conf_write"; }
    mod_enable "$contest" rodadas
    audit_log_to "$contest" round-set "slug=$slug"
    ok_json '{saved:true, round:$r}' --argjson r "$cur"
    ;;
  problems)
    rd_valid_slug "$slug" || fail 422 "slug inválido" "slug_invalid"
    cur="$(jq -c --arg s "$slug" '(.rounds // [])[] | select(.slug == $s)' <<<"$j")"
    [[ -n "$cur" ]] || fail 404 "rodada não encontrada" "round_notfound"
    [[ "$(jq -r '.state' <<<"$cur")" == archived ]] && fail 409 "rodada arquivada não muda" "round_archived"
    probs="$(jq -c '.problems // []' "$bodyf")"
    jq -e 'type == "array"' <<<"$probs" >/dev/null 2>&1 || fail 422 "problems deve ser array" "problems_invalid"
    (( $(jq 'length' <<<"$probs") <= 200 )) || fail 422 "máximo de 200 problemas" "too_many"
    # guarda de problema PRIVADO: a MESMA de Prova › Problemas e do wizard (problems_denied_for):
    # público, ou o DONO do contest é dono/colaborador/membro da org. Vale igual p/ rodada ativa e
    # planejada (a planejada só tem esta porta). Negado: 404 SEM a lista — a existência de um
    # privado alheio não vaza (o bank já listou o que é adicionável; id digitado = "não encontrado").
    source "$_DIR/lib/problems.sh"
    pids="$(jq -c '[ .[] | (.bank_id // .problem_id // "") | gsub("/";"#") | select(. != "") ]' <<<"$probs")"
    if [[ "$pids" != '[]' ]]; then
      owner="$(head -1 "$CONTESTSDIR/$contest/owner" 2>/dev/null)"
      denied="$(problems_denied_for "${owner:-}" "$pids")" || fail 503 "Índice de problemas indisponível" "index_unavailable"
      [[ -n "$denied" ]] && fail 404 "Problema não encontrado ou sem acesso ($(wc -w <<<"$denied") id(s))" "problem_denied"
    fi
    j="$(jq -c --arg s "$slug" --argjson p "$probs" \
        '.rounds = [ .rounds[] | if .slug == $s then (. + {problems:$p}) else . end ]' <<<"$j")"
    rd_save "$contest" "$j"
    cur="$(jq -c --argjson p "$probs" '. + {problems:$p}' <<<"$cur")"
    [[ "$(jq -r '.active' <<<"$j")" == "$slug" ]] && { rd_apply_obj "$contest" "$cur" || fail 422 "Falha ao gravar PROBS" "probs_write"; }
    mod_enable "$contest" rodadas
    audit_log_to "$contest" round-problems "slug=$slug n=$(jq 'length' <<<"$probs")"
    ok_json '{saved:true, n:$n}' --argjson n "$(jq 'length' <<<"$probs")"
    ;;
  remove)
    rd_valid_slug "$slug" || fail 422 "slug inválido" "slug_invalid"
    cur="$(jq -c --arg s "$slug" '(.rounds // [])[] | select(.slug == $s)' <<<"$j")"
    [[ -n "$cur" ]] || fail 404 "rodada não encontrada" "round_notfound"
    [[ "$(jq -r '.state' <<<"$cur")" == pending ]] || fail 409 "só rodada planejada pode ser removida" "not_pending"
    j="$(jq -c --arg s "$slug" '.rounds = [ .rounds[] | select(.slug != $s) ]' <<<"$j")"
    rd_save "$contest" "$j"
    audit_log_to "$contest" round-remove "slug=$slug"
    ok_json '{removed:true}'
    ;;
  publish)
    rd_valid_slug "$slug" || fail 422 "slug inválido" "slug_invalid"
    cur="$(jq -c --arg s "$slug" '(.rounds // [])[] | select(.slug == $s)' <<<"$j")"
    [[ -n "$cur" ]] || fail 404 "rodada não encontrada" "round_notfound"
    [[ "$(jq -r '.state' <<<"$cur")" == archived ]] || fail 409 "só rodada arquivada é publicável" "not_archived"
    on=true; jq -e '.on == false' "$bodyf" >/dev/null 2>&1 && on=false
    # COORTES: o relatório da rodada traz o placar ABERTO com todos os times. Publicá-lo para os
    # times antes de liberar os resultados entregaria os convidados de graça.
    if [[ "$on" == true ]]; then
      source "$_DIR/lib/cohorts.sh"
      if ch_enabled "$contest" && ! ch_released "$contest"; then
        fail 409 "o contest tem coorte de convidados e os resultados não foram liberados — o relatório da rodada mostra todos os times" "cohorts_not_released"
      fi
    fi
    j="$(jq -c --arg s "$slug" --argjson on "$on" \
        '.rounds = [ .rounds[] | if .slug == $s then (. + {published:$on}) else . end ]' <<<"$j")"
    rd_save "$contest" "$j"
    audit_log_to "$contest" round-publish "slug=$slug on=$on"
    ok_json '{published:$on}' --argjson on "$on"
    ;;
  promote)
    to="$(jq -r '.to // ""' "$bodyf")"; [[ -n "$to" ]] || to="$(rd_next "$contest")"
    [[ -n "$to" ]] || fail 409 "crie a próxima rodada antes de promover" "no_next_round"
    rd_valid_slug "$to" || fail 422 "slug inválido" "slug_invalid"
    [[ "$(jq -r --arg s "$to" '(.rounds // [])[] | select(.slug == $s) | .state' <<<"$j")" == pending ]] \
      || fail 409 "a rodada '$to' não está planejada" "not_pending"
    force=false; jq -e '.force == true' "$bodyf" >/dev/null 2>&1 && force=true
    bl="$(rd_promote_blockers "$contest")"; [[ -n "$bl" ]] || bl='[]'
    # `force` ignora tudo menos o que tornaria a promoção INCORRETA (sem rodada planejada) ou
    # descongelaria o placar antes da hora (freeze_locked: fim geral + 1 min, 2026-09-14).
    # `shared_users` saiu da lista: contest com USERS_FROM promove normalmente — o arquivamento
    # só mexe nos diretórios LOCAIS (ver lib/contest-rounds.sh).
    hard="$(jq -c '[ .[] | select(.code == "no_next_round" or .code == "freeze_locked" or .code == "problem_denied") ]' <<<"$bl")"
    if [[ "$force" == true ]]; then blk="$hard"; else blk="$bl"; fi
    if [[ "$(jq 'length' <<<"$blk")" != 0 ]]; then
      emit_json 409 Conflict
      jq -cn --argjson bl "$blk" '{success:false, error:{message:"A rodada não está pronta para ser promovida", code:"not_ready"}, blockers:$bl}'
      exit 0
    fi
    mkdir -p "$CONTESTSDIR/$contest/var" 2>/dev/null
    exec 9>"$CONTESTSDIR/$contest/var/.round.lock"
    flock -n 9 || fail 429 "Promoção já em andamento" "busy"
    res="$(rd_promote "$contest" "$to" "${SESSION_LOGIN:-}")"; rc=$?
    case "$rc" in
      0) ;;
      2) fail 409 "já existe arquivo da rodada atual — nada foi alterado" "archive_exists";;
      *) fail 500 "Falha ao promover a rodada (nada foi perdido: confira o arquivo em rounds/)" "promote_failed";;
    esac
    [[ -n "$res" ]] || fail 500 "Falha ao promover a rodada" "promote_failed"
    # INSCRIÇÃO: no aquecimento a porta fica aberta (reg_gate_active), então a rodada que entra —
    # se não for outro aquecimento — precisa varrer quem entrou sem se inscrever: sessão não
    # expira (a aba aberta entraria na prova) e o dir vazio sujaria o placar novo.
    source "$_DIR/lib/registration.sh"
    swept=""
    if reg_enabled "$contest" && [[ "$(reg_round_kind "$contest")" != warmup ]]; then
      swept="$(reg_sweep_unregistered "$contest")"
      IFS=$'\t' read -r _sw_s _sw_d <<<"$swept"
      (( ${_sw_s:-0} + ${_sw_d:-0} > 0 )) \
        && audit_log_to "$contest" round-promote-sweep "sessoes=${_sw_s:-0} dirs=${_sw_d:-0}"
    fi
    audit_log_to "$contest" "round-promote$([[ "$force" == true ]] && printf -- -forced)" \
      "from=$(jq -r '.from' <<<"$res") to=$(jq -r '.to' <<<"$res") users=$(jq -r '.archived.users' <<<"$res") subs=$(jq -r '.archived.submissions' <<<"$res")"
    ok_json '$r + {promoted:true} + (if $sw == "" then {} else {swept:{sessions:($sw|split("\t")[0]|tonumber? // 0), dirs:($sw|split("\t")[1]|tonumber? // 0)}} end)' \
      --argjson r "$res" --arg sw "$swept"
    ;;
  *) fail 400 "action inválida" "action_invalid";;
esac
