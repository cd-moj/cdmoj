# lib/review.sh — fila de revisão de veredicto manual (.judge). Sourced pelos handlers
# contest/review/*. Os itens são contests/<c>/review/<id>.json, criados pelo DAEMON quando o
# contest está em MANUAL_VERDICT e o (problema,lang,veredicto) não está na matriz auto.
# Espelha o padrão de claim/flock do lib/print.sh. TTL configurável (REVIEW_TTL, 5 min).

# OPÇÕES DE VEREDICTO (final-verdicts.json) = [{label, verdict, team?}] — label = o que o JUIZ
# escolhe; verdict = CLASSE canônica (uma das 6 de lib/verdict.sh: pontua/penaliza/colore);
# team = texto que o TIME vê (ausente = a própria classe). Compat com arquivo antigo: verdict fora
# das 6 (ex.: "Contact staff", "Presentation Error") vira {verdict:"Wrong Answer", team:<antigo>}.
# A string gravada no history é `classe¦team` (rv_canon_verdict) — ver lib/verdict.sh.
RV_DEFAULT_OPTS='[{"label":"1 - YES","verdict":"Accepted"},{"label":"2 - NO - Compilation error","verdict":"Compilation Error"},{"label":"3 - NO - Runtime error","verdict":"Runtime Error"},{"label":"4 - NO - Time limit exceeded","verdict":"Time Limit Exceeded"},{"label":"5 - NO - Wrong answer","verdict":"Wrong Answer"},{"label":"6 - NO - Contact staff","verdict":"Wrong Answer","team":"Contact staff"}]'

rv_ttl() { printf '%s' "${REVIEW_TTL:-300}"; }
rv_dir() { printf '%s' "$CONTESTSDIR/$1/review"; }
rv_lock() { local d; d="$(rv_dir "$1")"; mkdir -p "$d"; printf '%s' "$d/.lock"; }

# rv_scan <dir> <filtro-jq> [args do jq…] — aplica o filtro a CADA review/*.json num `jq` SÓ e imprime o
# resultado de cada arquivo (uma linha por resultado; `select` que não casa não imprime nada).
# POR QUE (XIV Maratona UnB, 25/09/2026): as rotas da fila rodavam UM jq (+ subshells) POR ARQUIVO — o
# `review/list` gastava ~15 ms por arquivo a cada chamada, crescendo a prova inteira (0,86 s com 57
# arquivos, 1,13 s com 81; a tela de cada juiz pede a cada 6–9 s: ~63% de um núcleo só nesta rota com
# 53 times). Com o `find -print0 | xargs -0` a lista de arquivos nunca estoura o ARG_MAX (o xargs parte).
# ⚠ O jq trata os arquivos como UM FLUXO: um arquivo truncado contamina o seguinte e a leitura inteira
# falha. Os escritores são atômicos (tmp + mv), então isso é raro — mas, se acontecer, refaz ARQUIVO A
# ARQUIVO (o caminho antigo, lento): um arquivo ruim some da resposta, nunca a derruba.
rv_scan() {
  local dir="$1" flt="$2" out rc f; shift 2
  [[ -d "$dir" ]] || return 0
  out="$(set -o pipefail; find "$dir" -maxdepth 1 -name '*.json' -print0 2>/dev/null \
         | xargs -0 -r jq -c "$@" "$flt" 2>/dev/null)"; rc=$?
  if (( rc == 0 )); then [[ -n "$out" ]] && printf '%s\n' "$out"; return 0; fi
  # caminho lento: fica assim até o arquivo ruim ser consertado — avisa no error.log p/ alguém ver
  printf 'rv_scan: leitura única falhou em %s (arquivo corrompido?) — lendo arquivo a arquivo\n' "$dir" >&2
  while IFS= read -r -d '' f; do jq -c "$@" "$flt" "$f" 2>/dev/null || printf 'rv_scan: ilegível: %s\n' "$f" >&2; done \
    < <(find "$dir" -maxdepth 1 -name '*.json' -print0 2>/dev/null)
  return 0
}

# opções de veredicto configuradas — sempre normalizadas a {label, verdict(classe), team}
rv_options() {
  local c="$1" f="$CONTESTSDIR/$1/final-verdicts.json" raw="$RV_DEFAULT_OPTS"
  { [[ -f "$f" ]] && jq -e . "$f" >/dev/null 2>&1; } && raw="$(cat "$f")"
  jq -c --arg cls "$VERDICT_CLASSES" '($cls | split("|")) as $C
    | map(if type=="string" then {label:., verdict:.} else . end)
    | map({label:((.label // .verdict // "")|tostring), verdict:((.verdict // .label // "")|tostring), team:((.team // "")|tostring)})
    | map(.verdict as $v | if ($C | index($v)) == null then {label, verdict:"Wrong Answer", team:(if .team != "" then .team else $v end)} else . end)
    | map(if .verdict == "Accepted" then .team = "" else . end)' <<<"$raw"
}

# rv_canon_verdict <c> <label> : resolve um label da lista p/ a string do history —
# `<classe>` ou `<classe>¦<texto do time>`. Aceita também a própria classe (ou uma string já
# no formato classe¦texto que esteja na lista). Falha (rc 1) se não casar nenhuma.
rv_canon_verdict() {
  local c="$1" label="$2" v
  v="$(rv_options "$c" | jq -r --arg l "$label" '
    def hist: if (.team // "") != "" and .team != .verdict then (.verdict + "¦" + .team) else .verdict end;
    (map(select(.label==$l))[0] | select(. != null) | hist)
    // (map(select(hist==$l))[0] | select(. != null) | hist)
    // (map(select(.verdict==$l))[0] | select(. != null) | .verdict) // empty')"
  [[ -n "$v" ]] || return 1
  printf '%s' "$v"
}

# rv_active_claim_by <c> <login> : ecoa o id de um item NÃO liberado onde <login> é avaliador
# não-expirado (p/ impedir que o juiz pegue duas ao mesmo tempo). Vazio se nenhum.
rv_active_claim_by() {
  # o id da avaliação ABERTA de `who` (claim não expirado, fora de released/agreed), ou nada. Uma passada
  # só (rv_scan) — era um jq por arquivo, e o `review/list` a chama a cada atualização da tela do juiz.
  local c="$1" who="$2" out; out="$(rv_scan "$(rv_dir "$c")" \
    'select(((.status // "open")|IN("released","agreed")|not) and any((.claimants // [])[]; .by==$w and ((.expires_at//0)>$now))) | input_filename' \
    -r --arg w "$who" --argjson now "$EPOCHSECONDS")"
  out="${out%%$'\n'*}"; [[ -n "$out" ]] || return 0
  out="${out##*/}"; printf '%s\n' "${out%.json}"
}

# rv_emit_setverdict <c> <id> <login> <cid> <verdict> : enfileira o spool 'setverdict' (mesmo
# formato do set-verdict.sh, INCLUINDO o id real) p/ o daemon finalizar pelo escritor único.
rv_emit_setverdict() {
  local c="$1" id="$2" login="$3" prob="$4" verdict="$5"
  local sid; sid="$(printf '%s%s%s%s' "$c" "$EPOCHSECONDS" "$id" "$RANDOM" | md5sum | cut -c1-32)"
  mkdir -p "$SPOOLDIR"
  local _sd; _sd="$(spool_shard_dir "$login")"   # shard do ALUNO dono da submissão (K=1 ⇒ raiz)
  local tmp="$_sd/.in.sv.$sid"
  jq -cn --arg c "$c" --arg j "${SESSION_LOGIN:-judge}" --arg p "$prob" --arg v "$verdict" \
    --arg u "$login" --arg id "$id" --argjson t "$EPOCHSECONDS" \
    '{action:"set-verdict", contest:$c, judge:$j, problem_id:$p, verdict:$v, username:$u, time:$t, id:$id}' \
    > "$tmp" && mv -f "$tmp" "$_sd/$c:$EPOCHSECONDS:$sid:${SESSION_LOGIN:-judge}:setverdict:$prob"
}

# rv_expire_filter : filtro jq que descarta claimants/votos expirados (now > expires_at) e os
# votos de quem não é mais avaliador. NÃO recalcula status (cada handler faz após sua transição).
# Uso: jq --argjson now N "$(rv_expire_filter)" file
rv_expire_filter() {
  cat <<'JQ'
    .claimants = [ (.claimants // [])[] | select((.expires_at//0) > $now) ]
JQ
}

# rv_quorum <contest> — quantos juízes VALIDAM cada veredicto (decisão do admin:
# conf REVIEW_JUDGES, 1..5; default 2). 1 = revisão simples (um voto decide).
rv_quorum() {
  local q; q="$(grep -m1 '^REVIEW_JUDGES=' "$CONTESTSDIR/$1/conf" 2>/dev/null | cut -d= -f2- | tr -dc 0-9)"
  [[ "$q" =~ ^[1-5]$ ]] || q=2
  printf '%s' "$q"
}
# rv_quorum_file <review-item-file> — idem, derivando o contest do caminho do item
rv_quorum_file() { local d="${1%/review/*}"; rv_quorum "${d##*/}"; }

# rv_recompute : recalcula status/conflict a partir dos VOTOS (permanentes) + claimants ATIVOS.
# Votar encerra a tarefa do juiz (sai dos claimants), mas o voto fica. O QUÓRUM é o $q do jq
# (rv_quorum; default 2): q votos UNÂNIMES -> agreed; q votos com divergência -> conflict;
# 1..q-1 votos -> voting (aguarda os próximos juízes); senão claimed/open. (released fixo.)
rv_recompute() {
  cat <<'JQ'
    if (.status // "open") == "released" then .
    else
      (.votes // []) as $v | ($v | map(.verdict) | unique) as $vv
      | if ($v|length) >= $q then (if ($vv|length)==1 then (.status="agreed" | .conflict=false) else (.status="conflict" | .conflict=true) end)
        elif ($v|length) >= 1 then (.status="voting" | .conflict=false)
        elif ((.claimants // [])|length) >= 1 then (.status="claimed" | .conflict=false)
        else (.status="open" | .conflict=false) end
    end
JQ
}

# rv_snapshot <file> : ecoa o item com claimants/votos expirados + status recalculado (sem gravar).
rv_snapshot() {
  jq -c --argjson now "$EPOCHSECONDS" --argjson q "$(rv_quorum_file "$1")" "$(rv_expire_filter)
| $(rv_recompute)" "$1" 2>/dev/null
}

# rv_apply <file> <transição-jq> [args-jq...] : expira → aplica a transição → recalcula → grava
# atômico (chamador SEGURA o flock). Ecoa o novo json. $now é injetado (--argjson now).
rv_apply() {
  local f="$1" trans="$2"; shift 2
  local out
  out="$(jq -c --argjson now "$EPOCHSECONDS" --argjson q "$(rv_quorum_file "$f")" "$@" "$(rv_expire_filter)
| ( $trans )
| $(rv_recompute)" "$f" 2>/dev/null)" || return 1
  [[ -n "$out" ]] || return 1
  printf '%s' "$out" > "$f.tmp" && mv -f "$f.tmp" "$f"
  printf '%s' "$out"
}

# rv_release_uncontested <contest> <by> — varre a fila de revisão e LIBERA, com o veredicto
# COMPUTADO, todo item que ninguém contestou (sem voto e sem conflito). Ecoa "<liberados>
# <restantes>".
#
# Existe por causa de um buraco real: desligar o MANUAL_VERDICT com a fila cheia deixava as
# sobras seguradas PARA SEMPRE — o juiz comum passa a ver "este contest não usa veredicto
# manual" e não consegue votar, e o competidor fica em "Not Answered Yet" sem que ninguém
# perceba. Desligar o manual é dizer "daqui p/ frente vale o veredicto da máquina"; o que
# ninguém contestou segue essa mesma regra.
#
# O que NÃO é liberado (de propósito): item com QUALQUER voto ou em CONFLITO — ali um humano
# já discordou da máquina, e soltar o computado por cima seria passar por cima dele. Esses
# ficam p/ o juiz-chefe decidir (o painel dele continua funcionando com o manual desligado),
# e o chamador informa quantos sobraram.
rv_release_uncontested() {
  local c="$1" by="${2:-system}" dir f id snap n=0 left=0
  dir="$(rv_dir "$c")"; [[ -d "$dir" ]] || { printf '0 0'; return 0; }
  exec 9>"$(rv_lock "$c")"; flock -w 10 9 || { printf '0 0'; return 1; }
  local now="$EPOCHSECONDS"
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    snap="$(cat "$f" 2>/dev/null)"; [[ -n "$snap" ]] || continue
    jq -e '.status == "released"' >/dev/null 2>&1 <<<"$snap" && continue
    if jq -e '((.votes // []) | length) == 0 and (.conflict != true)' >/dev/null 2>&1 <<<"$snap"; then
      id="$(jq -r '.id // empty' <<<"$snap")"
      local login prob verdict
      login="$(jq -r '.login // ""' <<<"$snap")"
      prob="$(jq -r '.problem_id // ""' <<<"$snap")"
      verdict="$(jq -r '.computed_verdict // ""' <<<"$snap")"
      [[ -n "$id" && -n "$verdict" ]] || { left=$((left+1)); continue; }
      rv_emit_setverdict "$c" "$id" "$login" "$prob" "$verdict"
      jq -c --arg v "$verdict" --arg by "$by" --argjson at "$now" \
        '.status="released" | .released_verdict=$v | .released_by=$by | .released_at=$at' \
        "$f" > "$f.tmp" 2>/dev/null && mv -f "$f.tmp" "$f"
      n=$((n+1))
    else
      left=$((left+1))
    fi
  done < <(find "$dir" -maxdepth 1 -name '*.json' -type f 2>/dev/null)
  exec 9>&-
  printf '%s %s' "$n" "$left"
}
