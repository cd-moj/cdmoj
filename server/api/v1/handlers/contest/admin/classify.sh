# /contest/admin/classify?contest=<id>  (admin DO contest) — classificação p/ as PRÓXIMAS FASES
# (docs/CLASSIFICACAO.md). Um contest pode ter VÁRIOS estágios: `final-br` e `pda` no contest da 1ª
# fase/regional, `mundial` no do Campeonato. Cada estágio tem o seu MOTOR (catálogo
# score/classify-catalog.json + allowlist CL_ENGINES em lib/classify.sh).
#
# GET  -> {stages:[estágio + relation], algorithms:[catálogo], vias:{via:{pt,en,es,short}}, manual_vias}
# POST {action, stage?, …}. `stage` padrão: o do motor em preview/apply; `final-br` nas demais.
#   preview  {config}                  -> roda o motor COM os overrides do estágio, SEM gravar
#   apply    {config, name?, venue?, when?, chip?, force?} -> grava o estágio como RASCUNHO. Estágio
#                                         de OUTRO motor = 409 stage_algorithm_mismatch (force:true troca)
#   publish|unpublish                  -> draft<->published (só o publicado aparece no placar)
#   delete                             -> apaga um estágio em RASCUNHO (o publicado: despublique antes)
# OVERRIDE MANUAL (salvaguarda contra erro de execução e caso de borda; motivo OBRIGATÓRIO, interno — só
# o painel o mostra). Ficam em `overrides[]`, SEPARADOS do cálculo, e sobrevivem a um novo apply:
#   exclude  {login, reason}           -> tira o time do CÁLCULO e recalcula: o próximo herda a vaga
#   withdraw {login|ext, reason}       -> tira da lista SEM recalcular: a vaga fica vaga
#   add      {login | ext+team, reason, via?, univ?, school?, country?, region?} -> promove à mão (via
#                                         manual|lista|reserva); p/ o motor, conta como já promovido
#   override_undo {id}                 -> desfaz um override
# Motor `manual` (catálogo reason_optional/manual_slots): TODA promoção é um `add` — motivo opcional, no máximo
#   config.slots promovidos (409 slots_full); o result traz o `ranking` (o placar) p/ o painel.
#   promote_next {reason}              -> o 1º da LISTA DE ESPERA (recalculada contra o estágio atual) vira um
#                                         add via "lista" (motor com waitlist no catálogo; 409 waitlist_empty).
#                                         add via "reserva" além das vagas de reserva do motor = 409 reserve_full
# Todo override vai ao audit (classify-override).
#
# O estágio guarda: config, result (a saída PURA do motor), overrides, e `teams` = a COMPOSIÇÃO (motor −
# retirados + manuais), que é o que o placar, o relatório e o /contest/classification leem. A regra da
# composição é ÚNICA: CL_JQ em lib/classify.sh.
source "$_DIR/lib/classify.sh"
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
CF="$CONTESTSDIR/$contest/classification.json"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
cl_allow_json > "$W/allow.json"

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  [[ -s "$CF" ]] && cp "$CF" "$W/cf.json" || printf '{"stages":[]}' > "$W/cf.json"
  # sementes (config oficial de cada motor, p/ o editor JSON do painel): {id: config}
  printf '{}' > "$W/seeds.json"
  while IFS=$'\t' read -r sid sfile; do
    [[ "$sfile" =~ ^[a-z0-9.-]+\.json$ && -s "$CL_SCORE_DIR/classify-seeds/$sfile" ]] || continue
    jq -c --arg i "$sid" --slurpfile s "$CL_SCORE_DIR/classify-seeds/$sfile" '. + {($i): $s[0]}' "$W/seeds.json" > "$W/seeds.tmp" \
      && mv -f "$W/seeds.tmp" "$W/seeds.json"
  done < <(jq -r '.engines[] | select(.seed != null) | [.id, .seed] | join("\t")' "$CL_CATALOG" 2>/dev/null)
  jq -c --slurpfile a "$W/allow.json" --slurpfile c "$CL_CATALOG" --slurpfile sd "$W/seeds.json" "$CL_JQ"'
    {stages: [ (.stages // [])[] | . + {overrides: cl_ovs} | . + {relation: cl_relation(cl_result)} ],
     algorithms: [ $c[0].engines[] | select(.id as $i | $a[0] | index($i)) | . + (if $sd[0][.id] then {seed:$sd[0][.id]} else {} end) ],
     vias: $c[0].vias, manual_vias: $c[0].manual_vias}' "$W/cf.json" > "$W/get.json" 2>"$W/err" \
    || fail 500 "Falha ao ler a classificação: $(head -c 200 "$W/err")" "read_fail"
  ok_json_slurp '$f[0]' f "$(cat "$W/get.json")"
  exit 0
fi

require_method POST
BF="$(read_body_file)"; mv -f "$BF" "$W/body.json"; BF="$W/body.json"
jq -e 'type == "object"' "$BF" >/dev/null 2>&1 || fail 400 "JSON inválido" "bad_json"
action="$(jq -r '.action // ""' "$BF")"
stage="$(jq -r '.stage // ""' "$BF")"
force="$(jq -r 'if .force == true then 1 else 0 end' "$BF")"
[[ -z "$stage" || "$stage" =~ ^[a-z0-9-]{1,32}$ ]] || fail 400 "stage inválido" "stage_invalid"

# --- placar CONGELADO (auditoria do painel, 03/10/2026; decisão do Ribas: recusar até liberar) --------------
# O motor lê o placar COMPLETO (placar-full) e a rota pública /contest/classification serve o estágio publicado a
# QUALQUER UM (o chip 🎓 aparece no placar congelado): publicar — ou recalcular um estágio já publicado — com o
# freeze valendo mostrava o resultado antes da revelação. Antes do fim geral + 1 min (freeze_release_at): 409
# freeze_locked, sem saída. Depois, com o placar AINDA congelado (cerimônia por fazer): 409 board_frozen, e
# `force_frozen:true` publica mesmo assim (a tela pergunta). `release_at` vai no erro p/ a tela mostrar a hora.
_frozen_guard(){
  local fz at; fz="$(conf_value "$contest" FREEZE_TIME)"; fz="${fz//[^0-9]/}"
  [[ -n "$fz" ]] && (( fz > 0 )) || return 0
  source "$_LIBDIR/contest-gate.sh"
  at="$(freeze_release_at "$contest")"
  if ! freeze_release_ok "$contest"; then
    FAIL_EXTRA="$(jq -cn --argjson a "${at:-0}" '{release_at:$a}')" \
      fail 409 "Com o placar congelado a classificação só pode ser publicada a partir de $(fmt_epoch "$at" '%d/%m %H:%M' "$contest") (fim da prova para todas as sedes + 1 min): ela é calculada pelo placar completo" "freeze_locked"
  fi
  [[ "$(jq -r '.force_frozen // false' "$BF")" == true ]] && return 0
  FAIL_EXTRA='{"can_force":true}' \
    fail 409 "O placar ainda está congelado: publicar agora mostra o resultado antes da revelação. Descongele (Central › Encerrar evento) ou confirme para publicar mesmo assim" "board_frozen"
}

# --- arquivo de estágios (sempre sob a trava nas escritas) ------------------------------------------
_lock(){ [[ -n "${CL_LOCKED:-}" ]] && return 0
  mkdir -p "$CONTESTSDIR/$contest/var"; exec 7>"$CONTESTSDIR/$contest/var/.classify.lock"
  flock -w 20 7 || fail 409 "Classificação ocupada — tente de novo" "busy"; CL_LOCKED=1; }
# _stage_get <id> > arquivo — o estágio (ou vazio + rc 1 se não existe)
_stage_get(){ [[ -s "$CF" ]] || return 1; jq -ce --arg s "$1" 'first((.stages // [])[] | select(.id == $s)) // empty' "$CF" 2>/dev/null; }
# _stage_put <arquivo-do-estágio> — substitui (ou acrescenta) o estágio; tmp+mv
_stage_put(){
  local cur="$W/cf-cur.json" tmp="$CF.tmp.${BASHPID}"
  [[ -s "$CF" ]] && cp "$CF" "$cur" || printf '{"version":1,"stages":[]}' > "$cur"
  jq -c --slurpfile n "$1" '.version = (.version // 1)
    | .stages = ((.stages // []) | if any(.[]; .id == $n[0].id) then map(if .id == $n[0].id then $n[0] else . end) else . + [$n[0]] end)' \
    "$cur" > "$tmp" 2>/dev/null
  [[ -s "$tmp" ]] || { rm -f "$tmp"; fail 500 "Falha ao gravar" "write_fail"; }
  mv -f "$tmp" "$CF"
}
# _run_engine <alg> <config> <estágio> <saída> [waitlist] — roda o motor com os overrides do estágio
# (cl_engine_cfg: exclude + preassigned). Com `waitlist`, roda o modo --waitlist contra o ESTADO do estágio
# (os times compostos contam como promovidos; os retirados ficam de fora). Os rc do motor viram 422:
# 2 config_invalid (com errors), 3 engine_refused (o motor diz qual time/código), resto engine_failed.
_run_engine(){
  local p rc mode=()
  p="$(cl_engine_path "$1")" || fail 422 "Algoritmo de classificação desconhecido: $1" "algorithm_invalid"
  jq -c --slurpfile st "$3" "$CL_JQ"'cl_engine_cfg($st[0])' "$2" > "$W/ecfg.json" 2>/dev/null \
    || fail 422 "Config inválida" "config_invalid"
  if [[ "${5:-}" == waitlist ]]; then
    mode=(--waitlist)
    jq -c --slurpfile st "$3" '. + {waitlist_state: ($st[0] | {
        promoted: [ (.teams // {}) | to_entries[] | {key:.key} + (.value | {school, country, region} | with_entries(select(.value != null))) ],
        skip: [ (.overrides // [])[] | select(.op == "withdraw" and (.login // "") != "") | .login ] })}' \
      "$W/ecfg.json" > "$W/ecfg2.json" && mv -f "$W/ecfg2.json" "$W/ecfg.json"
  fi
  bash "$p" "${mode[@]}" "$contest" "$W/ecfg.json" "$4" 2>"$W/eerr"; rc=$?
  case "$rc" in
    0) [[ -s "$4" ]] || fail 422 "Motor não produziu saída" "engine_failed";;
    2) FAIL_EXTRA="$(jq -c '{errors:((.errors // []) | map(tostring))}' "$W/eerr" 2>/dev/null)" \
         fail 422 "Config inválida: $(jq -r '(.errors // []) | join("; ")' "$W/eerr" 2>/dev/null | head -c 300)" "config_invalid";;
    3) fail 422 "O motor recusou os dados: $(head -c 400 "$W/eerr")" "engine_refused";;
    *) fail 422 "Motor falhou: $(head -c 200 "$W/eerr")" "engine_failed";;
  esac
}
# _compose <estágio> <saída-do-motor|""> <extra-jq-obj-file|""> > novo estágio — overrides + teams + rótulos
_compose(){
  local res="$2" extra="${3:-}"
  [[ -n "$res" ]] || { res="$W/nores.json"; printf 'null' > "$res"; }
  [[ -n "$extra" ]] || { extra="$W/noextra.json"; printf '{}' > "$extra"; }
  jq -c --slurpfile r "$res" --slurpfile x "$extra" --slurpfile c "$CL_CATALOG" --argjson now "$EPOCHSECONDS" "$CL_JQ"'
    . + $x[0]
    | . + {overrides: cl_ovs}
    | . + {result: (if $r[0] != null then $r[0] else cl_result end)}
    | (.config.algorithm // "") as $alg | .id as $sid
    | (first($c[0].engines[] | select(.id == $alg)) // first($c[0].engines[] | select(.stage == $sid)) // {}) as $E
    | . + {teams: cl_teams(cl_relation(.result); $now)}
    | (((.result.via_order // $E.vias // []) + [ .teams[] | .via ] + $c[0].manual_vias)
       | reduce .[] as $v ([]; if any(.[]; . == $v) then . else . + [$v] end)) as $order
    | . + {via_order: $order,
           labels: (($c[0].vias + (.result.labels // {})) | with_entries(select(.key as $k | $order | any(.[]; . == $k)))),
           chip: (.chip // $E.defaults.chip // .name // .id)}' "$1"
}
_need_reason(){ # [optional] — motivo (texto, ≤ 500) em REASON; obrigatório, salvo `optional` (motor manual)
  REASON="$(jq -r '((.reason // .note // "") | tostring | gsub("^\\s+|\\s+$"; ""))' "$BF")"
  [[ -n "$REASON" || "${1:-}" == optional ]] || fail 422 "Motivo obrigatório" "reason_required"
  (( ${#REASON} <= 500 )) || fail 422 "Motivo longo demais (máx. 500)" "reason_too_long"
}

# promote_next: o 1º da LISTA DE ESPERA, recalculada contra o estágio ATUAL (os times compostos contam como
# promovidos; os retirados ficam de fora), vira um override `add` via "lista" — o mesmo caminho do add abaixo.
if [[ "$action" == promote_next ]]; then
  stage="${stage:-final-br}"
  _lock
  _stage_get "$stage" > "$W/st.json" || fail 404 "Estágio não existe: $stage" "no_stage"
  alg="$(jq -r '.config.algorithm // ""' "$W/st.json")"
  jq -e --arg a "$alg" 'any(.engines[]; .id == $a and .waitlist == true)' "$CL_CATALOG" >/dev/null 2>&1 \
    || fail 409 "O motor deste estágio não tem lista de espera" "waitlist_unsupported"
  _need_reason
  jq -c '.config' "$W/st.json" > "$W/cfg.json"
  _run_engine "$alg" "$W/cfg.json" "$W/st.json" "$W/wl.json" waitlist
  nxt="$(jq -r '.waitlist[0].login // ""' "$W/wl.json")"
  [[ -n "$nxt" ]] || fail 409 "A lista de espera está vazia" "waitlist_empty"
  ff="$(jq -r '.force_frozen == true' "$BF")"   # o add abaixo passa pela trava do placar congelado: leva a confirmação junto
  jq -c --arg l "$nxt" --arg s "$stage" --arg r "$REASON" --argjson ff "$ff" \
    '{action:"add", stage:$s, login:$l, via:"lista", reason:$r, force_frozen:$ff}' <<<'{}' > "$BF"
  action=add
fi

case "$action" in
  preview|apply)
    jq -c '.config // {}' "$BF" > "$W/cfg.json"
    jq -e 'type == "object"' "$W/cfg.json" >/dev/null 2>&1 || fail 422 "config tem de ser um objeto" "config_invalid"
    alg="$(jq -r '.algorithm // ""' "$W/cfg.json")"
    if [[ -z "$alg" && -n "$stage" ]]; then alg="$(_stage_get "$stage" | jq -r '.config.algorithm // ""' 2>/dev/null)"; fi
    alg="${alg:-sbc-fase1}"
    cl_engine "$alg" >/dev/null || fail 422 "Algoritmo de classificação desconhecido: $alg" "algorithm_invalid"
    [[ -n "$stage" ]] || stage="$(cl_stage_default "$alg")"; stage="${stage:-final-br}"
    jq -c --arg a "$alg" '. + {algorithm:$a} | del(.preassigned)' "$W/cfg.json" > "$W/cfg2.json" && mv -f "$W/cfg2.json" "$W/cfg.json"
    [[ "$action" == apply ]] && _lock
    _stage_get "$stage" > "$W/st.json" || jq -cn --arg s "$stage" '{id:$s, status:"draft", teams:{}}' > "$W/st.json"
    # recalcular um estágio PUBLICADO muda o que todo mundo vê: com o placar congelado, a mesma trava do publicar
    [[ "$action" == apply && "$(jq -r '.status // ""' "$W/st.json")" == published ]] && _frozen_guard
    old="$(jq -r '.config.algorithm // ""' "$W/st.json")"
    if [[ "$action" == apply && -n "$old" && "$old" != "$alg" && "$force" != 1 ]]; then
      FAIL_EXTRA="$(jq -cn --arg o "$old" --arg n "$alg" '{stage_algorithm:$o, requested:$n}')" \
        fail 409 "O estágio $stage é do motor $old — confirme para trocar" "stage_algorithm_mismatch"
    fi
    _run_engine "$alg" "$W/cfg.json" "$W/st.json" "$W/out.json"
    if [[ "$action" == preview ]]; then
      jq -c --slurpfile r "$W/out.json" "$CL_JQ"'{preview:$r[0], stage:.id, overrides:cl_ovs, relation:cl_relation($r[0])}' \
        "$W/st.json" > "$W/resp.json" || fail 500 "Falha ao montar a prévia" "build_fail"
      ok_json_slurp '$f[0]' f "$(cat "$W/resp.json")"
      exit 0
    fi
    # apply: nome/local/quando/chip — o do pedido › o do estágio › o padrão do motor no catálogo
    jq -c --slurpfile c "$CL_CATALOG" --slurpfile st "$W/st.json" --slurpfile cfg "$W/cfg.json" --arg a "$alg" --arg who "$SESSION_LOGIN" \
        --argjson now "$EPOCHSECONDS" '
      def nz: if . == "" then null else . end;
      (first($c[0].engines[] | select(.id == $a)) // {}) as $E
      | {config: $cfg[0], applied_at: $now, applied_by: $who,
         name: ((.name | nz) // $st[0].name // $E.defaults.name // $st[0].id),
         venue: ((.venue | nz) // $st[0].venue // $E.defaults.venue // ""),
         when: ((.when | nz) // $st[0].when // $E.defaults.when // ""),
         chip: ((.chip | nz) // $st[0].chip // $E.defaults.chip // null),
         next_stage: ($st[0].next_stage // $E.next_stage // null)}
      | with_entries(select(.value != null))' "$BF" > "$W/extra.json"
    _compose "$W/st.json" "$W/out.json" "$W/extra.json" > "$W/new.json" || fail 500 "Falha ao compor o estágio" "write_fail"
    jq -c --slurpfile r "$W/out.json" '. + {region: ($r[0].region // .region)} | if .region == null then del(.region) else . end' \
      "$W/new.json" > "$W/new2.json" && mv -f "$W/new2.json" "$W/new.json"
    _stage_put "$W/new.json"
    mod_enable "$contest" classificacao
    audit_log_to "$contest" classify "apply stage=$stage alg=$alg n=$(jq -r '.teams | length' "$W/new.json") by=$SESSION_LOGIN"
    ok_json_slurp '{applied:true, stage:$s, result:$f[0]}' f "$(cat "$W/out.json")" --arg s "$stage"
    ;;
  publish|unpublish|delete)
    stage="${stage:-final-br}"
    _lock
    _stage_get "$stage" > "$W/st.json" || fail 404 "Estágio não existe: $stage" "no_stage"
    if [[ "$action" == delete ]]; then
      [[ "$(jq -r '.status' "$W/st.json")" != published ]] || fail 409 "Despublique o estágio antes de apagar" "stage_published"
      tmp="$CF.tmp.${BASHPID}"
      jq -c --arg s "$stage" '.stages = [ (.stages // [])[] | select(.id != $s) ]' "$CF" > "$tmp" 2>/dev/null && [[ -s "$tmp" ]] \
        || { rm -f "$tmp"; fail 500 "Falha ao gravar" "write_fail"; }
      mv -f "$tmp" "$CF"
      audit_log_to "$contest" classify "delete stage=$stage by=$SESSION_LOGIN"
      ok_json '{deleted:$s}' --arg s "$stage"
      exit 0
    fi
    st=published; [[ "$action" == unpublish ]] && st=draft
    [[ "$action" == publish ]] && _frozen_guard
    jq -c --arg st "$st" --argjson now "$EPOCHSECONDS" '. + {status:$st} + (if $st == "published" then {published_at:$now} else {} end)' \
      "$W/st.json" > "$W/new.json"
    _stage_put "$W/new.json"
    audit_log_to "$contest" classify "$action stage=$stage by=$SESSION_LOGIN"
    ok_json '{status:$st, stage:$s}' --arg st "$st" --arg s "$stage"
    ;;
  exclude|withdraw|add|override_undo)
    stage="${stage:-final-br}"
    _lock
    exists=1
    _stage_get "$stage" > "$W/st.json" || { exists=0; jq -cn --arg s "$stage" '{id:$s, status:"draft", teams:{}}' > "$W/st.json"; }
    [[ "$exists" == 1 || "$action" == add || "$action" == exclude ]] || fail 404 "Estágio não existe: $stage" "no_stage"
    [[ "$(jq -r '.status // ""' "$W/st.json")" == published ]] && _frozen_guard
    jq -c "$CL_JQ"'cl_ovs' "$W/st.json" > "$W/ovs.json"
    rerun=1     # withdraw (e desfazer um withdraw) NÃO recalcula: compõe sobre a saída guardada
    if [[ "$action" == override_undo ]]; then
      oid="$(jq -r '.id // ""' "$BF")"
      [[ "$oid" =~ ^ov-[0-9]{1,6}$ ]] || fail 400 "id de override inválido" "override_invalid"
      jq -ce --arg i "$oid" 'first(.[] | select(.id == $i)) // empty' "$W/ovs.json" > "$W/ov.json" \
        || fail 404 "Override não encontrado: $oid" "override_notfound"
      [[ "$(jq -r '.op' "$W/ov.json")" == withdraw ]] && rerun=0
      jq -c --arg i "$oid" 'map(select(.id != $i))' "$W/ovs.json" > "$W/ovs2.json"
      key="$(jq -r 'if (.login // "") != "" then .login else "ext:" + (.ext // "") end' "$W/ov.json")"
      REASON="$(jq -r '.reason // ""' "$W/ov.json")"
    else
      # motor manual (catálogo reason_optional): a PROMOÇÃO é o próprio cálculo e o motivo é opcional
      ralg="$(jq -r '.config.algorithm // ""' "$W/st.json")"
      if [[ "$action" == add ]] && jq -e --arg a "$ralg" 'any(.engines[]; .id == $a and .reason_optional == true)' "$CL_CATALOG" >/dev/null 2>&1; then
        _need_reason optional
      else _need_reason; fi
      login="$(jq -r '.login // ""' "$BF")"; ext="$(jq -r '.ext // ""' "$BF")"
      [[ -n "$login" && -n "$ext" ]] && fail 400 "Use login OU ext" "login_invalid"
      if [[ -n "$ext" ]]; then
        [[ "$action" == exclude ]] && fail 400 "exclude só vale p/ time do placar (login)" "login_invalid"
        [[ "$ext" =~ ^[a-z0-9][a-z0-9-]{0,47}$ ]] || fail 400 "ext inválido (minúsculas, dígitos e -)" "ext_invalid"
        key="ext:$ext"
      else
        valid_id "$login" || fail 400 "login inválido" "login_invalid"
        key="$login"
      fi
      # um override ativo por time: desfaça o anterior antes
      oex="$(jq -r --arg k "$key" 'first(.[] | select((if (.login // "") != "" then .login else "ext:" + (.ext // "") end) == $k) | .id) // ""' "$W/ovs.json")"
      [[ -z "$oex" ]] || FAIL_EXTRA="$(jq -cn --arg i "$oex" '{override:$i}')" fail 409 "Já existe um override p/ $key ($oex) — desfaça-o antes" "override_exists"
      intm="$(jq -r --arg k "$key" "$CL_JQ"'cl_relation(cl_result) | map(select(.login == $k and .withdrawn == null)) | if length > 0 then "1" else "0" end' "$W/st.json")"
      teamj='{}'
      case "$action" in
        exclude)
          user_exists "$contest" "$login" || fail 404 "Time não encontrado" "notfound";;
        withdraw)
          [[ "$intm" == 1 ]] || fail 404 "$key não está na lista deste estágio" "not_classified"
          rerun=0;;
        add)
          [[ "$intm" == 0 ]] || fail 409 "$key já está na lista deste estágio" "already_classified"
          via="$(jq -r '.via // "manual"' "$BF")"
          jq -e --arg v "$via" '.manual_vias | index($v)' "$CL_CATALOG" >/dev/null 2>&1 \
            || fail 422 "via inválida p/ promoção manual: $via" "via_invalid"
          # motor manual: no máximo `slots` promovidos (o admin aumenta o número p/ promover mais)
          if jq -e --arg a "$ralg" 'any(.engines[]; .id == $a and .manual_slots == true)' "$CL_CATALOG" >/dev/null 2>&1; then
            jq -e "$CL_JQ"'(.config.slots // null) as $n | $n == null or ([ cl_ovs[] | select(.op == "add") ] | length) < $n' \
              "$W/st.json" >/dev/null 2>&1 \
              || FAIL_EXTRA="$(jq -c '{slots:(.config.slots)}' "$W/st.json")" fail 409 "As $(jq -r '.config.slots' "$W/st.json") vagas desta etapa já foram preenchidas — aumente o número para promover mais" "slots_full"
          fi
          # reserva: no máximo as vagas que o motor reportou (result.reserve.slots)
          if [[ "$via" == reserva ]]; then
            jq -e "$CL_JQ"'(.result.reserve.slots // null) as $n | $n == null or ([ cl_ovs[] | select(.op == "add" and .via == "reserva") ] | length) < $n' \
              "$W/st.json" >/dev/null 2>&1 || fail 409 "As vagas de reserva deste estágio já foram usadas" "reserve_full"
          fi
          if [[ -n "$ext" ]]; then
            jq -e '((.team // "") | tostring | length) > 0' "$BF" >/dev/null || fail 422 "Time de fora do placar precisa de nome (team)" "team_required"
            teamj="$(jq -c '{team, univ, school, country, region} | with_entries(select(.value != null) | .value |= (tostring | .[0:120]))' "$BF")"
          else
            user_exists "$contest" "$login" || fail 404 "Time não encontrado" "notfound"
            teamj="$(jq -c '{team:(.fullname // .team.name // ""), univ:(.team.univ_short // "")} | with_entries(select(.value != ""))' \
              "$(account_file "$contest" "$login")" 2>/dev/null)"
            [[ -n "$teamj" ]] || teamj='{}'
          fi
          teamj="$(jq -c --arg v "$via" '. + {via:$v}' <<<"$teamj")";;
      esac
      seq="$(jq -r '((.ov_seq // 0) | tonumber? // 0)' "$W/st.json")"
      seq="$(jq -r --argjson s "$seq" '[$s, (.[] | .id | ltrimstr("ov-") | tonumber? // 0)] | max' "$W/ovs.json")"
      oid="ov-$(( seq + 1 ))"
      jq -c --arg i "$oid" --arg op "$action" --arg l "$login" --arg e "$ext" --arg r "$REASON" --arg who "$SESSION_LOGIN" \
          --argjson now "$EPOCHSECONDS" --argjson t "$teamj" \
        '. + [ {id:$i, op:$op, reason:$r, by:$who, at:$now} + (if $e != "" then {ext:$e} else {login:$l} end) + $t ]' \
        "$W/ovs.json" > "$W/ovs2.json"
      jq -c --argjson s "$(( seq + 1 ))" '. + {ov_seq:$s}' "$W/st.json" > "$W/st2.json" && mv -f "$W/st2.json" "$W/st.json"
    fi
    jq -c --slurpfile o "$W/ovs2.json" '. + {overrides:$o[0]}' "$W/st.json" > "$W/st2.json" && mv -f "$W/st2.json" "$W/st.json"
    alg="$(jq -r '.config.algorithm // ""' "$W/st.json")"
    res=""
    if [[ "$rerun" == 1 && -n "$alg" ]]; then
      jq -c '.config' "$W/st.json" > "$W/cfg.json"
      _run_engine "$alg" "$W/cfg.json" "$W/st.json" "$W/out.json"
      res="$W/out.json"
    fi
    _compose "$W/st.json" "$res" > "$W/new.json" || fail 500 "Falha ao compor o estágio" "write_fail"
    _stage_put "$W/new.json"
    mod_enable "$contest" classificacao
    audit_log_to "$contest" classify-override "$action stage=$stage key=$key id=${oid} reason=${REASON:0:200} by=$SESSION_LOGIN"
    ok_json_slurp '{stage:$s, override:$o, overrides:$f[0].overrides, total:($f[0].teams | length)}' f "$(cat "$W/new.json")" \
      --arg s "$stage" --arg o "$oid"
    ;;
  *) fail 400 "action deve ser preview|apply|publish|unpublish|delete|exclude|withdraw|add|override_undo|promote_next" "action_invalid";;
esac
