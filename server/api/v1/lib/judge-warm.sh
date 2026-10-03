# lib/judge-warm.sh — JUIZ QUENTE × FRIO: quais juízes online ainda não calibraram quais problemas de um
# contest, na versão ATUAL do pacote. Alimenta o item "Juízes aquecidos" do preflight
# (handlers/contest/admin/preflight.sh) e o POST /contest/admin/warm-judges (o botão "Aquecer juízes").
#
# POR QUE (XIV Maratona UnB, 25/09/2026): o TL é POR MÁQUINA, e o juiz que nunca calibrou um problema
# baixa e calibra na 1ª submissão dele — SÍNCRONO, sob lock por problema (moj-agent.sh ensure_cached).
# Foram 6 calibrações a frio durante a prova; a 1ª submissão do super-dash no judge-sp1 esperou 7,3 min
# (15:24:44 → 15:32:05) e a 2ª, 188 s no lock. O preflight dizia OK: bastava UM juiz ter o problema.
#
# QUENTE (host, problema) = run/tl/<id>.json tem o host com `pkg_version` IGUAL à versão atual — o memo
# run/tl/<id>.pkv que o pkg_judge_version mantém (package-meta, tl-report, editor). É o teste que o
# agente faz no ensure_cached (versão do cache == a do package-meta, TL reportado), feito do lado do
# servidor e SEM abrir o pacote: rota de contest nunca abre MOJ_PROBLEMS_DIR (fronteira do pacote).
# O inventário do registro (`.problems`) NÃO serve: o agente só o refaz ao re-registrar, não a cada
# calibração — o juiz que calibrou sob demanda continuaria "frio" lá.
# AQUECENDO = há `calibrate` para o par na fila do host (commands/<host>/*.json) ou em execução
# (updates/inprogress/<host>/: o marcador cmd-* da dirigida, ou uma calibração comum do problema).
# FRIO = o resto. Hosts = o pool EFETIVO do problema (problem-judges.json → CONTEST_JUDGES → todos),
# só os ONLINE e não desabilitados no judges-config — juiz offline é outro item do preflight.
# Se o tl_checksum ESTREITO do índice (tl_index_checksums) diverge do run/tl, o pacote mudou desde a
# calibração: todos frios.
# ⚠ LIMITE: o .pkv é a última versão que o SERVIDOR calculou. Pacote editado e nunca mais validado nem
# calibrado deixa o .pkv velho — os juízes da versão velha aparecem quentes e recalibram na 1ª
# submissão, como antes. (Sem .pkv, vale a versão mais recente reportada por algum host.)
#
# Uso: depois de load_contest_conf (lê PROBS e CONTEST_JUDGES do conf) e de sourcear sched-lib.sh e
# tl-store.sh. Todo arquivo grande vai por --slurpfile/--rawfile, nunca por argv.

# jw_online -> JSON [hosts] com heartbeat dentro do REG_TTL e NÃO desabilitados no judges-config.
jw_online(){
  local jc="${JUDGES_CONFIG_FILE:-$CONTESTSDIR/treino/var/judges-config.json}" dis='{}'
  [[ -s "$jc" ]] && dis="$(jq -c 'with_entries(select((.value.disabled // false) == true)) | map_values(true)' "$jc" 2>/dev/null)"
  [[ -n "$dis" ]] || dis='{}'
  # um jq por registro (são poucos): um arquivo corrompido não derruba os outros
  find "$REGISTRYDIR" -maxdepth 1 -name '*.json' -print0 2>/dev/null \
    | xargs -0 -r -n1 jq -c --argjson now "$EPOCHSECONDS" --argjson ttl "${REG_TTL:-30}" \
        'select((.last_seen // 0) >= ($now - $ttl)) | .host' 2>/dev/null \
    | jq -cs --argjson dis "$dis" 'map(select(type == "string" and ($dis[.] | not))) | unique'
}

# _jw_each <filtro> <arquivo…> — UM jq sobre todos; arquivo corrompido (o jq para no meio do stream)
# ⇒ refaz arquivo a arquivo e o ilegível fica de fora.
_jw_each(){
  local flt="$1" out f; shift; (( $# )) || return 0
  if out="$(jq -c "$flt" "$@" 2>/dev/null)"; then [[ -n "$out" ]] && printf '%s\n' "$out"; return 0; fi
  for f in "$@"; do jq -c "$flt" "$f" 2>/dev/null; done
  return 0
}

# jw_matrix <contest> -> {online:[h], problems:[{id,letter,hosts:[{host,state}]}],
#                        counts:{warm,warming,cold}, cold:[{host,id,letter}], warming:[{host,id,letter}]}
jw_matrix(){
  local c="$1" W i id letter pjm f v tlfiles=() ids=()
  W="$(mktemp -d)" || return 1
  pjm="$CONTESTSDIR/$c/problem-judges.json"
  jq -e 'type == "object"' "$pjm" >/dev/null 2>&1 || pjm=/dev/null
  # problemas do contest: id \t letra (o pool de cada um sai do problem-judges.json/CONTEST_JUDGES no jq)
  for ((i = 0; i + 4 < ${#PROBS[@]}; i += 5)); do
    id="${PROBS[i+4]}"; letter="${PROBS[i+3]}"; [[ -n "$id" ]] || continue
    ids+=("$id")
    printf '%s\t%s\n' "$id" "$letter"
    f="$(tl_store_file "$id")"; [[ -s "$f" ]] && tlfiles+=("$f")
    if [[ -s "${f%.json}.pkv" ]]; then
      IFS= read -r v < "${f%.json}.pkv"; v="${v#*$'\t'}"; v="${v//[^0-9a-f]/}"
      [[ -n "$v" ]] && printf '%s\t%s\n' "$id" "$v" >> "$W/pkv"
    fi
  done > "$W/probs"
  : >> "$W/pkv"
  { [[ "$pjm" == /dev/null ]] && echo '{}' || jq -c 'map_values(if type == "array" then join(" ") else "" end)' "$pjm" 2>/dev/null || echo '{}'; } > "$W/pools"
  jw_online > "$W/online"; [[ -s "$W/online" ]] || echo '[]' > "$W/online"
  _jw_each '{id:(input_filename | split("/") | .[-1] | sub("[.]json$"; "")), c:(.checksum // ""),
             h:((.hosts // {}) | map_values({v:(.pkg_version // ""), at:(.at // 0)}))}' "${tlfiles[@]}" > "$W/tl"
  tl_index_checksums "${ids[@]}" > "$W/idx"
  # calibrações na fila ou em execução: {h, id}
  local busyf=()
  mapfile -d '' busyf < <(find "${CMDDIR:-$RUNDIR/commands}" "${UPDATESDIR:-$RUNDIR/updates}/inprogress" \
                            -mindepth 2 -maxdepth 2 -name '*.json' -print0 2>/dev/null)
  _jw_each 'select(((.action // .kind) // "") == "calibrate")
            | {h:(input_filename | split("/") | .[-2]), id:((.id // .target) // "")}' "${busyf[@]}" > "$W/busy"
  jq -n --slurpfile on "$W/online" --slurpfile pools "$W/pools" --slurpfile tl "$W/tl" --slurpfile busy "$W/busy" \
     --rawfile probs "$W/probs" --rawfile pkv "$W/pkv" --rawfile idx "$W/idx" --arg cpool "${CONTEST_JUDGES:-}" '
    def rows($s): $s | split("\n") | map(select(length > 0) | split("\t"));
    ($on[0] // []) as $on
    | ($pools[0] // {}) as $PL
    | (rows($pkv) | map({(.[0]): .[1]}) | add // {}) as $V
    | (rows($idx) | map({(.[0]): (.[1] // "")}) | add // {}) as $N
    | ($tl | map({(.id): .}) | add // {}) as $TL
    | ($busy | map({(.h + "\t" + .id): true}) | add // {}) as $B
    | [ rows($probs)[] as $r
        | $r[0] as $id | ($r[1] // "") as $letter
        | (($PL[$id] // "") | split(" ") | map(select(length > 0))) as $pp
        | (if ($pp | length) > 0 then $pp else ($cpool | split(" ") | map(select(length > 0))) end) as $pool
        | (if ($pool | length) > 0 then [ $on[] | select(. as $h | $pool | index($h)) ] else $on end) as $hosts
        | ($TL[$id] // {c:"", h:{}}) as $t
        | (($V[$id] // "") as $v
           | if $v != "" then $v
             else ([ $t.h[] | select(.v != "") ] | max_by(.at) // {v:""}).v end) as $cur
        | (($N[$id] // "") as $n | ($n != "" and $t.c != "" and $n != $t.c)) as $stale
        | {id:$id, letter:$letter,
           hosts:[ $hosts[] as $h
                   | {host:$h,
                      state:(if ($stale | not) and $cur != "" and (($t.h[$h].v // "") == $cur) then "warm"
                             elif $B[$h + "\t" + $id] then "warming"
                             else "cold" end)} ]} ] as $P
    | def pairs($s): [ $P[] as $p | $p.hosts[] | select(.state == $s) | {host, id:$p.id, letter:$p.letter} ];
      {online:$on, problems:$P,
       counts:{warm:(pairs("warm") | length), warming:(pairs("warming") | length), cold:(pairs("cold") | length)},
       cold:pairs("cold"), warming:pairs("warming")}' 2>/dev/null
  local rc=$?
  rm -rf "$W"
  return $rc
}

# jw_group <matrix-json> <cold|warming> -> "judge-sp1: A, C · goiabada-judge: B" (texto p/ o preflight)
jw_group(){
  jq -r --arg k "$2" '[ .[$k] | group_by(.host)[] | "\(.[0].host): \([.[] | (if .letter != "" then .letter else .id end)] | join(", "))" ]
                      | join(" · ")' <<<"$1" 2>/dev/null
}

# jw_warm <contest> <quem> <arquivo-saida> -> o núcleo do "🔥 Aquecer juízes": manda um `calibrate` DIRIGIDO
# (cmd_request, o mesmo do editor) a cada par juiz×problema FRIO do jw_matrix e escreve em <arquivo-saida> uma linha
# por envio `host \t id \t letra \t cmdid`; no stdout, as contagens de ANTES ({warm,warming,cold}). Sob o flock do
# contest em CMDDIR: dois pedidos não duplicam (o 2º espera e já vê os pares "aquecendo"). rc 2 = outro aquecimento
# em andamento (lock); rc 1 = mapa falhou. Usado pela rota (botão), pelo bin/warm-judges.sh (promoção de rodada e o
# aquecimento automático antes do início, do judged) — uma regra só.
# Requer load_contest_conf (PROBS, CONTEST_JUDGES), sched-lib.sh (cmd_request, CMDDIR) e tl-store.sh.
jw_warm(){
  local c="$1" by="$2" out="$3" wm fd h id letter cid
  : > "$out" || return 1
  mkdir -p "$CMDDIR" 2>/dev/null
  exec {fd}>"$CMDDIR/.warm-$c.lock" 2>/dev/null || return 1
  flock -w 20 "$fd" 2>/dev/null || { eval "exec ${fd}>&-"; return 2; }
  wm="$(jw_matrix "$c")"
  if ! jq -e '.counts' >/dev/null 2>&1 <<<"$wm"; then eval "exec ${fd}>&-"; return 1; fi
  while IFS=$'\t' read -r h id letter; do
    valid_hostname "$h" && valid_id "$id" || continue
    cid="$(cmd_request "$h" calibrate "$by" "$id")" || continue
    [[ -n "$cid" ]] && printf '%s\t%s\t%s\t%s\n' "$h" "$id" "$letter" "$cid" >> "$out"
  done < <(jq -r '.cold[] | [.host, .id, .letter] | @tsv' <<<"$wm")
  eval "exec ${fd}>&-"
  jq -c '.counts' <<<"$wm"
}
