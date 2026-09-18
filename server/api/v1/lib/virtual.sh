# lib/virtual.sh — PARTICIPAÇÃO VIRTUAL: refazer um contest ENCERRADO a partir da conta do treino,
# com os times oficiais como "fantasmas" no tempo do participante. (2026-09-18)
#
# MODELO: a submissão virtual É uma submissão normal do TREINO, etiquetada — spool, judged, mojlog
# e perfil não sabem do virtual. Esta camada só guarda a JANELA e a lista de subids, e DERIVA o
# resultado do history do treino. O placar é montado no CLIENTE (web/shared/virtual-board.js) a
# partir de um feed estático do contest. NADA é escrito em contests/<c>/users/: o virtual é
# invisível p/ sc_users, estatística, relatório, webcast e rodadas (doutrina de contest-rounds.sh:
# não tornar o caminho quente ciente de janela).
#
# ARMAZENAMENTO
#   contests/treino/users/<login>/virtual/<cid>.json   estado (autoritativo; anda com o rename)
#   contests/treino/users/<login>/virtual/<cid>.subs   subids etiquetados (um por linha)
#   contests/<cid>/virtual/runs/<login>.json           snapshot publicado ao FINALIZAR
#   contests/<cid>/var/virtual-feed.json(.gz)          feed dos fantasmas (cache)
#   contests/<cid>/var/virtual-board.json              agregado dos snapshots (cache)
#
# ⚠ BLINDAGEM (pedido do Ribas: "muito cuidado para não vazar prova"). O portão `vr_load` é ÚNICO,
# FAIL-CLOSED e roda a CADA requisição, ANTES de qualquer leitura de cache:
#   módulo `virtual` ligado ∧ não treino ∧ não SECRET ∧ icpc ∧ terminou PARA TODOS ∧ placar
#   descongelado ∧ TODO problema PÚBLICO no treino (var/jsons/<id>.json com public != false).
# Falhou qualquer coisa — inclusive conf ilegível — a rota responde 404 `virtual_unavailable`,
# IDÊNTICO a contest inexistente (não confirma existência, fase, título nem nº de problemas), e os
# caches do virtual daquele contest são APAGADOS. Nada aqui lê jsons-private/ nem MOJ_PROBLEMS_DIR:
# virtual de problema privado não existe.

source "$_LIBDIR/modules.sh"
source "$_LIBDIR/contest-gate.sh"
source "$_LIBDIR/verdict.sh"

: "${VR_GRACE_S:=900}"            # desistência livre nos primeiros 15 min
: "${VR_MAX_DISCARDS:=2}"         # desistências que DEVOLVEM a tentativa; a largada seguinte é definitiva
: "${VR_SCHEDULE_MAX_S:=604800}"  # agendar até 7 dias à frente
: "${VR_PENDING_MAX_S:=3600}"     # pendente há mais que isto depois do fim não segura a finalização
: "${VR_FRIENDS_MAX:=100}"         # teto da lista de "escolhidos" (virtuais que sempre aparecem)
: "${SCOREDIR:=$_LIBDIR/../../../score}"

vr_cid_ok(){ [[ "$1" =~ ^[a-z0-9][a-z0-9_-]{0,63}$ && "$1" != treino ]]; }

# _vr_conf_dump <cid> — subshell: sourceia o conf SEM contaminar o processo do handler (o /submit
# chama isto com o conf de OUTRO contest carregado). Linha 1 = campos \x01; demais = problemas.
_vr_conf_dump(){
  ( CONTEST_START=0; CONTEST_END=0; CONTEST_TYPE=icpc; FREEZE_TIME=0; SECRET=0; CONTEST_NAME=""
    PENALTY_MINUTES=20; PROBS=()
    source "$CONTESTSDIR/$1/conf" >/dev/null 2>&1 || exit 1
    printf '%s\001%s\001%s\001%s\001%s\001%s\001%s\n' "${CONTEST_START//[!0-9]/}" "${CONTEST_END//[!0-9]/}" \
      "${CONTEST_TYPE:-icpc}" "${FREEZE_TIME//[!0-9]/}" "${SECRET:-0}" "${PENALTY_MINUTES//[!0-9]/}" "${CONTEST_NAME//$'\n'/ }"
    local i canon
    for (( i=0; i+3 < ${#PROBS[@]}; i+=5 )); do
      canon="${PROBS[i+4]:-}"; [[ "$canon" == *"#"* ]] || canon="${PROBS[i+1]//\//#}"   # = SC_CANON
      printf '%s\001%s\001%s\n' "${PROBS[i+3]:-}" "$canon" "${PROBS[i+2]:-}"
    done )
}

_vr_purge_cache(){ rm -f "$CONTESTSDIR/$1/var/virtual-feed.json" "$CONTESTSDIR/$1/var/virtual-feed.json.gz" \
                         "$CONTESTSDIR/$1/var/virtual-board.json" 2>/dev/null; }

# vr_load <cid> — O PORTÃO. rc 0 = elegível e VR_* preenchidos; rc 1 = não (VR_REASON diz por quê —
# p/ o DONO no painel; o público nunca vê o motivo). Não roda em subshell: preenche globais.
vr_load(){
  local cid="$1" dump hdr i n type fz secret
  VR_REASON=""; VR_CID=""; VR_START=0; VR_END=0; VR_DUR=0; VR_PEN=20; VR_TITLE=""
  VR_SHORT=(); VR_CANON=(); VR_NAME=(); VR_NPRIV=0
  vr_cid_ok "$cid" || { VR_REASON=no_contest; return 1; }
  [[ -r "$CONTESTSDIR/$cid/conf" ]] || { VR_REASON=no_contest; return 1; }
  # VR_IGNORE="module_off running frozen": modo do PAINEL ("dá p/ ligar?") — ignora o que o tempo
  # resolve sozinho; nunca usado por rota que serve dado. Motivo ignorado não purga cache nem barra.
  _vr_reject(){ [[ " ${VR_IGNORE:-} " == *" $1 "* ]] && return 0; VR_REASON="$1"; _vr_purge_cache "$cid"; return 1; }
  mod_on "$cid" virtual || { _vr_reject module_off || return 1; }
  dump="$(_vr_conf_dump "$cid")" && [[ -n "$dump" ]] || { _vr_reject conf_unreadable || return 1; }
  mapfile -t _vr_lines <<<"$dump"
  IFS=$'\001' read -r VR_START VR_END type fz secret VR_PEN VR_TITLE <<<"${_vr_lines[0]}"
  [[ "$secret" == 1 ]] && { _vr_reject secret || return 1; }
  [[ "${type:-icpc}" == icpc ]] || { _vr_reject type || return 1; }
  [[ "$VR_START" =~ ^[0-9]+$ && "$VR_END" =~ ^[0-9]+$ ]] && (( VR_START > 0 && VR_END > VR_START )) \
    || { _vr_reject window || return 1; }
  contest_over_for_all "$cid" || { _vr_reject running || return 1; }
  [[ -n "$fz" ]] && (( fz > 0 )) && { _vr_reject frozen || return 1; }
  n=$(( ${#_vr_lines[@]} - 1 )); (( n > 0 )) || { _vr_reject no_problems || return 1; }
  local files=() s c nm
  for (( i=1; i<=n; i++ )); do
    IFS=$'\001' read -r s c nm <<<"${_vr_lines[i]}"
    valid_id "$c" || { _vr_reject problem_invalid || return 1; }
    VR_SHORT+=("$s"); VR_CANON+=("$c"); VR_NAME+=("$nm")
    if [[ -f "$CONTESTSDIR/treino/var/jsons/$c.json" ]]; then files+=("$CONTESTSDIR/treino/var/jsons/$c.json")
    else (( VR_NPRIV++ )); fi
  done
  # público de VERDADE: estar em var/jsons/ não basta (3ª camada, como em handlers/treino/problem.sh)
  if (( VR_NPRIV == 0 )); then
    VR_NPRIV="$(jq -n '[inputs | select(.public == false)] | length' "${files[@]}" 2>/dev/null)" || VR_NPRIV=-1
    [[ "$VR_NPRIV" =~ ^[0-9]+$ ]] || VR_NPRIV=-1
  fi
  (( VR_NPRIV == 0 )) || { _vr_reject problems_not_public || return 1; }
  VR_DUR=$(( VR_END - VR_START )); VR_PEN="${VR_PEN:-20}"; VR_CID="$cid"
  return 0
}
# vr_gate <cid> — p/ handlers públicos: 404 uniforme. O corpo NÃO depende do motivo.
vr_gate(){ vr_load "$1" || fail 404 "Not found" "virtual_unavailable"; }

vr_pidx(){ local i; for i in "${!VR_CANON[@]}"; do [[ "${VR_CANON[i]}" == "$1" ]] && { printf '%s' "$i"; return 0; }; done; return 1; }
vr_problems_json(){
  local i; for i in "${!VR_CANON[@]}"; do
    printf '%s\001%s\001%s\n' "${VR_SHORT[i]}" "${VR_CANON[i]}" "${VR_NAME[i]}"
  done | jq -Rc 'split("\u0001") | {letter:.[0], id:.[1], name:.[2]}' | jq -cs .
}

# ---- classificador de veredicto: Y aceito · N conta tentativa · X não conta · ? pendente --------
# ⚠ ESPELHO do `counts`/`ac`/`prov` de metrics_recompute (lib/users.sh). Não dá p/ extrair de lá
# sem mexer no caminho quente; a paridade é garantida pelo teste diferencial
# (smoke-virtual-board.gjs.sh: motor em t=∞ == var/placar.txt, com CE não-penalizante na fixture).
vr_deny(){   # <cid> — códigos canônicos que NÃO penalizam, separados por TAB (= users.sh)
  local pv code deny=""
  if grep -q '^PENALTY_VERDICTS=' "$CONTESTSDIR/$1/conf" 2>/dev/null; then
    pv="$(conf_value "$1" PENALTY_VERDICTS)"; pv="${pv//[!a-z ]/}"
  else pv="$PENALTY_CODES_DEFAULT"; fi
  for code in $PENALTY_CODES_ALL; do
    [[ " $pv " == *" $code "* ]] || deny+="${deny:+$'\t'}$(penalty_code_canon "$code")"
  done
  printf '%s' "$deny"
}
VR_FLAG_JQ="$VERDICT_CANON_JQ"'
def vrflag($deny):
  (split("¦")[0]) as $v
  | if ($v|test("Not Answered Yet|On queue|Running"; "i")) then "?"
    elif ($v|test(" \\(Ignored\\)$")) or ($v|startswith("Judge Error")) or ($v|test("^No_?Servers")) then "X"
    elif ($v|startswith("Accepted")) then "Y"
    elif ((($deny|index("Compilation Error")) != null) and ($v|startswith("Compilation Error"))) then "X"
    elif (($v|vcanon) as $cv | ($deny|index($cv)) != null) then "X"
    else "N" end;'

# ---- estado da run ---------------------------------------------------------------------------
vr_dir(){   printf '%s/treino/users/%s/virtual' "$CONTESTSDIR" "$1"; }
vr_file(){  printf '%s/treino/users/%s/virtual/%s.json' "$CONTESTSDIR" "$1" "$2"; }
vr_subs(){  printf '%s/treino/users/%s/virtual/%s.subs' "$CONTESTSDIR" "$1" "$2"; }
vr_snap(){  printf '%s/%s/virtual/runs/%s.json' "$CONTESTSDIR" "$2" "$1"; }   # <login> <cid>
_vr_write(){ local f="$1" t; t="$f.tmp.$BASHPID"; cat > "$t" && mv -f "$t" "$f"; }   # BASHPID resolvido ANTES do redirect
vr_lock(){ mkdir -p "$(vr_dir "$1")" || return 1; exec 8>"$(vr_dir "$1")/.lock" && flock -w 10 8; }
vr_unlock(){ exec 8>&- 2>/dev/null; }

# vr_my_runs <login> <cid> <start> <end> -> [[sec,pidx,flag,verdict,subid,lang]] (ordem de envio)
# history do treino ∩ subids etiquetados ∩ janela ∩ problemas do contest. Entradas por ARQUIVO.
vr_my_runs(){
  local login="$1" cid="$2" st="$3" en="$4" hf sf
  hf="$CONTESTSDIR/treino/users/$login/history"; sf="$(vr_subs "$login" "$cid")"
  [[ -s "$hf" && -s "$sf" ]] || { printf '[]'; return 0; }
  local pj="$sf.pj.$BASHPID"
  printf '%s\n' "${VR_CANON[@]}" | jq -Rc . | jq -cs . > "$pj"
  jq -R -s -c --rawfile subs "$sf" --slurpfile pj "$pj" --arg denyraw "$(vr_deny "$cid")" \
     --argjson st "$st" --argjson en "$en" "$VR_FLAG_JQ"'
    ($denyraw|split("\t")|map(select(length>0))) as $deny
    | ($subs|split("\n")|map(select(length>0))|map({key:., value:1})|from_entries) as $tag
    | ($pj[0]|to_entries|map({key:.value, value:.key})|from_entries) as $pi
    | split("\n") | map(select(length>0) | split(":"))
    | map({p:.[1], lang:.[2], id:.[-1], e:((.[-2]|tonumber?) // 0), v:(.[3:-2]|join(":"))})
    | map(select($tag[.id] and ($pi[.p] != null) and .e >= $st and .e < $en))
    | sort_by(.e)
    | map([.e - $st, $pi[.p], (.v|vrflag($deny)), (.v|split("¦")[0]), .id, .lang])' "$hf" 2>/dev/null \
    || printf '[]'
  rm -f "$pj"
}
# vr_summary <runs-json> <pen> -> {solved, penalty, ac, pending}  (regra ICPC, minutos truncados)
vr_summary(){
  jq -c --argjson pen "$2" '
    group_by(.[1]) | map(
      (map(select(.[2]=="Y"))|.[0]) as $ac
      | {ac: ($ac != null),
         pen: (if $ac == null then 0 else
                 (($ac[0]/60|floor) + $pen * (map(select(.[2]=="N" and .[0] <= $ac[0]))|length)) end)})
    | {solved: (map(select(.ac))|length), penalty: (map(.pen)|add // 0)}' <<<"$1" \
  | jq -c --argjson r "$1" '. + {ac: .solved, pending: ($r|map(select(.[2]=="?"))|length)}'
}

# vr_effective <state-json> -> scheduled|running|judging|finished|discarded|none
vr_effective(){
  local j="$1" st s e
  [[ -n "$j" ]] || { printf none; return; }
  IFS=$'\t' read -r st s e < <(jq -r '[.state, .start, .end]|@tsv' <<<"$j")
  case "$st" in finished|discarded) printf '%s' "$st"; return;; esac
  if   (( EPOCHSECONDS < s )); then printf scheduled
  elif (( EPOCHSECONDS < e )); then printf running
  else printf judging; fi
}
vr_state(){ local f; f="$(vr_file "$1" "$2")"; [[ -s "$f" ]] && jq -c . "$f" 2>/dev/null; }

# vr_can_discard <state-json> <ac> -> rc 0 se o botão Desistir vale AGORA
# regra (Ribas, 2026-09-18): rodando ∧ não é a largada definitiva ∧ (decorrido ≤ 15 min OU 0 AC)
vr_can_discard(){
  local j="$1" ac="$2" s fin
  [[ "$(vr_effective "$j")" == running ]] || return 1
  IFS=$'\t' read -r s fin < <(jq -r '[.start, (.final // false)]|@tsv' <<<"$j")
  [[ "$fin" == true ]] && return 1
  (( EPOCHSECONDS - s <= VR_GRACE_S || ac == 0 ))
}

# _vr_discard <login> <cid> <state-json> <count:0|1> — descarta; os subs saem da etiqueta (seguem
# sendo submissões normais do treino). count=1 gasta uma das VR_MAX_DISCARDS.
_vr_discard(){
  local login="$1" cid="$2" j="$3" cnt="$4" sf n
  sf="$(vr_subs "$login" "$cid")"
  n="$(jq -r '(.discards // 0)' <<<"$j")"
  [[ -f "$sf" ]] && mv -f "$sf" "$sf.d$(( n + cnt )).$EPOCHSECONDS" 2>/dev/null
  jq -c --argjson c "$cnt" --argjson now "$EPOCHSECONDS" \
    '.state="discarded" | .discards=((.discards // 0)+$c) | .discarded_at=$now' <<<"$j" \
    | _vr_write "$(vr_file "$login" "$cid")"
}

# vr_refresh <login> <cid> — transições PREGUIÇOSAS (chamada com vr_load feito e sob vr_lock):
#   fim passado ∧ sem pendente: 0 AC e não-definitiva => descarte automático (conta);
#                               senão => snapshot publicado + finished.
vr_refresh(){
  local login="$1" cid="$2" j runs sum st en ac pend fin
  j="$(vr_state "$login" "$cid")"; [[ -n "$j" ]] || return 0
  [[ "$(vr_effective "$j")" == judging ]] || return 0
  IFS=$'\t' read -r st en fin < <(jq -r '[.start, .end, (.final // false)]|@tsv' <<<"$j")
  runs="$(vr_my_runs "$login" "$cid" "$st" "$en")"
  sum="$(vr_summary "$runs" "$VR_PEN")"; ac="$(jq -r .ac <<<"$sum")"; pend="$(jq -r .pending <<<"$sum")"
  (( pend > 0 && EPOCHSECONDS < en + VR_PENDING_MAX_S )) && return 0
  if (( ac == 0 )) && [[ "$fin" != true ]]; then _vr_discard "$login" "$cid" "$j" 1; return 0; fi
  local af name flag univ
  af="$CONTESTSDIR/treino/users/$login/account.json"
  mkdir -p "$CONTESTSDIR/$cid/virtual/runs" || return 1
  jq -c --arg login "$login" --argjson st "$st" --argjson en "$en" --argjson sum "$sum" \
        --argjson now "$EPOCHSECONDS" --slurpfile acc "$af" --argjson off "$(jq -c '.official // false' <<<"$j")" '
      {version:1, login:$login, name:($acc[0].fullname // $login),
       univ:($acc[0].univ_short // $acc[0].team.univ_short // ""), flag:($acc[0].flag // $acc[0].team.flag // ""),
       start:$st, used:($en-$st), solved:$sum.solved, penalty:$sum.penalty, official:$off, finished_at:$now,
       runs: map([.[0], .[1], (if .[2]=="?" then "X" else .[2] end)])}' <<<"$runs" \
    | _vr_write "$(vr_snap "$login" "$cid")" || return 1
  jq -c --argjson sum "$sum" --argjson now "$EPOCHSECONDS" \
    '.state="finished" | .finished_at=$now | .result={solved:$sum.solved, penalty:$sum.penalty}' <<<"$j" \
    | _vr_write "$(vr_file "$login" "$cid")"
}

# ---- feed dos fantasmas ------------------------------------------------------------------------
# Times = as LINHAS do placar público final (var/placar.txt): coorte pública, desclassificados e
# papéis JÁ filtrados pelo gerador — mesmo truque do webcast-gen. Runs = history ∩ esses times ∩
# problemas do conf. Só roda com o portão aberto (placar descongelado ⇒ placar.txt é o completo).
vr_feed_file(){ printf '%s/%s/var/virtual-feed.json' "$CONTESTSDIR" "$1"; }
vr_feed_fresh(){
  local f; f="$(vr_feed_file "$1")"; local d="$CONTESTSDIR/$1"
  [[ -s "$f" && -s "$f.gz" ]] || return 1
  [[ "$d/conf" -nt "$f" || "$d/var/.score-dirty" -nt "$f" || "$d/var/placar.txt" -nt "$f" ]] && return 1
  # o FORMATO do feed mora nesta lib: deploy que a muda invalida os feeds antigos (e cohorts.json é entrada)
  [[ "${BASH_SOURCE[0]}" -nt "$f" || "$d/cohorts.json" -nt "$f" ]] && return 1
  return 0
}
vr_feed_build(){
  local cid="$1" d="$CONTESTSDIR/$1" f w ft
  f="$(vr_feed_file "$cid")"; ft="$f.tmp.$BASHPID"; mkdir -p "$d/var" || return 1
  exec 7>"$d/var/.virtual-feed.lock" && flock -w 30 7 || return 1
  if vr_feed_fresh "$cid"; then exec 7>&-; return 0; fi
  vr_load "$cid" || { exec 7>&-; return 1; }        # re-checa o portão DENTRO do lock
  source "$_LIBDIR/users.sh" 2>/dev/null
  if [[ ! -s "$d/var/placar.txt" || "$d/var/.score-dirty" -nt "$d/var/placar.txt" \
        || "$d/cohorts.json" -nt "$d/var/placar.txt" || "$d/conf" -nt "$d/var/placar.txt" ]]; then
    bash "$SCOREDIR/build.sh" "$cid" >/dev/null 2>&1
  fi
  [[ -s "$d/var/placar.txt" ]] || { exec 7>&-; return 1; }
  w="$(mktemp -d)" || { exec 7>&-; return 1; }
  # times: colunas PELO NOME do cabeçalho (linha 2), sem os marcadores desc/asc
  awk -F: 'NR==2{ k=0; for(i=1;i<=NF;i++){ if($i=="desc"||$i=="asc") continue; k++; H[$i]=k } next }
           NR>2 && NF { g=(("guest" in H) ? $(H["guest"]) : "");
             printf "%s\001%s\001%s\001%s\001%s\001%s\n", $(H["username"]), $(H["flag"]), $(H["univ short"]), $(H["team name"]), $(H["univ full"]), g }' \
    "$d/var/placar.txt" > "$w/teams"
  # COORTE por time (7º campo) + `views` — p/ o filtro "Placar:" da página, igual ao do placar oficial.
  # Só entra o que JÁ é público: os times são os do placar público, e uma coorte só vira opção se
  # algum desses times pertence a ela (nome de coorte privada nunca sai daqui). A coorte vem do
  # MESMO sc_users que o gerador do placar usa (campo .team.cohort › regex › default).
  printf '{}' > "$w/coh.json"; printf '[]' > "$w/views.json"
  source "$_LIBDIR/cohorts.sh" 2>/dev/null
  if declare -F ch_enabled >/dev/null && ch_enabled "$cid"; then
    ( source "$SCOREDIR/score-common.sh" && sc_load "$cid" >/dev/null 2>&1 \
        && MOJ_COHORTS="$(ch_cohorts_of_view "$cid" public)" sc_users ) 2>/dev/null \
      | awk -F'\001' 'NF>=7 && $7!="" {print $1 "\001" $7}' \
      | jq -Rn '[inputs | split("\u0001") | {key:.[0], value:.[1]}] | from_entries' > "$w/coh.json" 2>/dev/null \
      || printf '{}' > "$w/coh.json"
    ch_get "$cid" | jq -c --slurpfile m "$w/coh.json" '($m[0]|[.[]]|unique) as $used
        | [.cohorts[] | select(.id as $i | $used|index($i)) | {id, name:(.name // .id), unranked:(.unranked == true)}]' \
      > "$w/views.json" 2>/dev/null || printf '[]' > "$w/views.json"
  fi
  jq -Rc --slurpfile m "$w/coh.json" 'split("\u0001") | [.[0], .[1], .[2], .[3], .[4], (.[5]=="1"), ($m[0][.[0]] // "")]' "$w/teams" \
    | jq -cs . > "$w/teams.json"
  printf '%s\n' "${VR_CANON[@]}" | jq -Rc . | jq -cs . > "$w/pj.json"
  vr_problems_json > "$w/problems.json"
  emit_history_stream "$cid" > "$w/hist" 2>/dev/null
  # `-n` + `inputs`: os mapas login→índice e probid→índice são montados UMA vez. Com `jq -R` puro o
  # programa roda POR LINHA e refazia os mapas a cada run — 2000 times × 24 mil runs = 1 min 45 s
  # (medido); assim são ~2 s. O veredicto é classificado uma vez por TEXTO distinto (memo `$fl`).
  jq -R -n -c --slurpfile teams "$w/teams.json" --slurpfile pj "$w/pj.json" --arg denyraw "$(vr_deny "$cid")" \
     --argjson st "$VR_START" "$VR_FLAG_JQ"'
     ($denyraw|split("\t")|map(select(length>0))) as $deny
     | ($teams[0]|to_entries|map({key:.value[0], value:.key})|from_entries) as $ti
     | ($pj[0]|to_entries|map({key:.value, value:.key})|from_entries) as $pi
     | [inputs | select(length>0) | split(":")
        | {l:.[1], p:.[2], e:((.[-2]|tonumber?) // 0), v:(.[4:-2]|join(":"))}
        | select(($ti[.l] != null) and ($pi[.p] != null))] as $rows
     | ($rows|map(.v)|unique|map({key:., value:(.|vrflag($deny))})|from_entries) as $fl
     | $rows | map([([.e - $st, 0]|max), $ti[.l], $pi[.p], $fl[.v]]) | sort_by(.[0])' "$w/hist" \
    > "$w/runs.json" || { rm -rf "$w"; exec 7>&-; return 1; }
  jq -cn --arg c "$cid" --arg t "$VR_TITLE" --argjson dur "$VR_DUR" --argjson pen "$VR_PEN" \
     --slurpfile teams "$w/teams.json" --slurpfile runs "$w/runs.json" --slurpfile probs "$w/problems.json" \
     --slurpfile views "$w/views.json" \
     '{success:true, version:2, contest:$c, title:$t, duration:$dur, penalty_minutes:$pen,
       problems:($probs[0]|map({letter, name})), views:(if ($views[0]|length) > 1 then $views[0] else [] end),
       teams:$teams[0], runs:$runs[0]}' > "$ft" \
    && gzip -9 -c "$ft" > "$ft.gz" && mv -f "$ft" "$f" && mv -f "$ft.gz" "$f.gz"
  local rc=$?; rm -rf "$w" "$ft" "$ft.gz"; exec 7>&-; return $rc
}

# vr_board_json <cid> -> [snapshots publicados] (removidos pela moderação ficam de fora)
vr_board_json(){
  local cid="$1" d="$CONTESTSDIR/$1/virtual/runs" f="$CONTESTSDIR/$1/var/virtual-board.json"
  [[ -d "$d" ]] || { printf '[]'; return 0; }
  local bt="$f.tmp.$BASHPID"
  if [[ ! -s "$f" || "$d" -nt "$f" ]]; then
    mkdir -p "$CONTESTSDIR/$cid/var"
    find "$d" -maxdepth 1 -name '*.json' -print0 2>/dev/null | xargs -0 -r cat 2>/dev/null \
      | jq -cs 'map(select(.removed != true)) | sort_by(-.solved, .penalty)' > "$bt" \
      && mv -f "$bt" "$f" || { rm -f "$bt"; printf '[]'; return 0; }
  fi
  cat "$f"
}

# ---- "MEUS ESCOLHIDOS": virtuais que a pessoa quer ver SEMPRE no placar (amigos) ------------------
# UMA lista por conta, p/ todos os contests: treino/users/<login>/virtual/_friends.json. O `_` inicial
# garante que o arquivo NUNCA colide com o estado de um contest (vr_cid_ok exige [a-z0-9] no 1º
# caractere) e que o vr_rename_login o pula; mora no dir do usuário ⇒ acompanha o rename do dono.
# Não se confere se a conta escolhida EXISTE: seria oráculo de existência, e login que não existe
# simplesmente nunca casa com linha nenhuma do placar.
vr_friends_file(){ printf '%s/treino/users/%s/virtual/_friends.json' "$CONTESTSDIR" "$1"; }
vr_friends_get(){   # <login> -> ["a","b"]
  local f; f="$(vr_friends_file "$1")"
  [[ -s "$f" ]] && jq -c '(.logins // []) | map(select(type=="string"))' "$f" 2>/dev/null || printf '[]'
}
# vr_friends_set <login> <lista-json> — grava (chamar sob vr_lock). Tira o próprio login e duplicatas.
vr_friends_set(){
  local login="$1" list="$2"
  mkdir -p "$(vr_dir "$login")" || return 1
  jq -c --arg me "$login" --argjson now "$EPOCHSECONDS" \
    '{version:1, logins:(map(select(. != $me)) | unique), updated_at:$now}' <<<"$list" \
    | _vr_write "$(vr_friends_file "$login")"
}

# vr_rename_login <old> <new> — chamado DEPOIS do mv do dir do usuário: os snapshots seguem o login
vr_rename_login(){
  local old="$1" new="$2" sf cid snap
  # `find`, não glob: a API roda com `noglob` (o `*.json` ficaria literal e nada seria movido)
  while IFS= read -r -d '' sf; do
    cid="$(basename "$sf" .json)"; vr_cid_ok "$cid" || continue
    snap="$CONTESTSDIR/$cid/virtual/runs/$old.json"
    [[ -f "$snap" ]] || continue
    jq -c --arg n "$new" '.login=$n' "$snap" > "$CONTESTSDIR/$cid/virtual/runs/$new.json.tmp" \
      && mv -f "$CONTESTSDIR/$cid/virtual/runs/$new.json.tmp" "$CONTESTSDIR/$cid/virtual/runs/$new.json" \
      && rm -f "$snap"
    touch "$CONTESTSDIR/$cid/virtual/runs" 2>/dev/null
  done < <(find "$CONTESTSDIR/treino/users/$new/virtual" -maxdepth 1 -name '*.json' -print0 2>/dev/null)
  # quem tinha <old> entre os ESCOLHIDOS passa a ter <new>: uma varredura só, e só no rename
  # (`find`, não glob — noglob; `grep -lF` com as aspas do JSON p/ não casar prefixo de outro login)
  local ff ft
  while IFS= read -r -d '' ff; do
    grep -qF "\"$old\"" "$ff" 2>/dev/null || continue
    ft="$ff.tmp.$BASHPID"
    jq -c --arg o "$old" --arg n "$new" '.logins = ((.logins // []) | map(if . == $o then $n else . end) | unique)' "$ff" > "$ft" 2>/dev/null \
      && mv -f "$ft" "$ff" || rm -f "$ft"
  done < <(find "$CONTESTSDIR/treino/users" -mindepth 3 -maxdepth 3 -path '*/virtual/_friends.json' -print0 2>/dev/null)
  return 0
}

# vr_me_json <login> <cid> — o estado da run DESTE login, já com as transições preguiçosas aplicadas
# (chamar com vr_load feito). É o `me` do /info e o corpo do /run.
vr_me_json(){
  local login="$1" cid="$2" j eff runs='[]' sum='{"solved":0,"penalty":0,"ac":0,"pending":0}' st en cd=false
  vr_lock "$login" || return 1
  vr_refresh "$login" "$cid"
  j="$(vr_state "$login" "$cid")"; eff="$(vr_effective "$j")"
  vr_unlock
  local off=false; [[ -s "$CONTESTSDIR/$cid/users/$login/history" ]] && off=true
  if [[ "$eff" == none ]]; then
    jq -cn --argjson now "$EPOCHSECONDS" --argjson max "$VR_MAX_DISCARDS" --argjson off "$off" \
      '{state:"none", discards:0, discards_left:$max, final:false, official:$off, runs:[], solved:0, penalty:0, now:$now}'
    return 0
  fi
  case "$eff" in running|judging|finished)
    IFS=$'\t' read -r st en < <(jq -r '[.start, .end]|@tsv' <<<"$j")
    runs="$(vr_my_runs "$login" "$cid" "$st" "$en")"; sum="$(vr_summary "$runs" "$VR_PEN")" ;;
  esac
  vr_can_discard "$j" "$(jq -r .ac <<<"$sum")" && cd=true
  jq -c --arg eff "$eff" --argjson runs "$runs" --argjson sum "$sum" --argjson cd "$cd" \
        --argjson now "$EPOCHSECONDS" --argjson max "$VR_MAX_DISCARDS" --argjson grace "$VR_GRACE_S" '
    {state:$eff, start, end, duration, starts:(.starts // 1), discards:(.discards // 0),
     discards_left:([$max - (.discards // 0), 0]|max), final:(.final // false), official:(.official // false),
     can_discard:$cd, grace_s:$grace, result:(.result // null),
     runs:$runs, solved:$sum.solved, penalty:$sum.penalty, pending:$sum.pending, now:$now}' <<<"$j"
}
