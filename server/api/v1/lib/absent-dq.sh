# lib/absent-dq.sh — DESCLASSIFICAR QUEM NÃO LOGOU, em lote (12/11/2026; pedido do Ribas depois da LATAM 2026:
# "um botão pro admin desclassificar todos que não logaram no contest, que faz isso uma vez").
# Regras (decididas com ele):
#   - "não logou" = nenhum login no var/access.log na JANELA da prova E nenhuma submissão (history não vazio). Quem
#     submeteu nunca sai, mesmo sem registro de login (sessão aberta antes da janela, envio offline).
#   - JANELA = de 1 h antes da abertura do login (LOGIN_START_TIME; sem ela, CONTEST_START) até o fim para todas as
#     sedes (contest_end_all) — ou AGORA, se a prova ainda não acabou: o botão vale a qualquer momento. Login de
#     aquecimento (rodada anterior) não conta. Sem CONTEST_START: o log inteiro.
#   - fica de fora quem está num estágio PUBLICADO da classificação (classification.json), quem já está
#     desclassificado e conta de papel.
#   - a desclassificação é a MESMA marca do user-disqualify (.disqualified no account.json: some do placar e da
#     estatística), com .dq_batch=<lote> — o DESFAZER devolve só quem ainda tem a marca daquele lote.
# Estado: var/absent-dq.json {batches:[{id,at,by,window:{from,to},logins:[…],undone_at?,undone_by?}]}.
#
#   adq_window <c>                 -> "from to" (epochs)
#   adq_scan <c> <work>            -> grava <work>/scan.json {window, live, counts, candidates[], kept_classified[], plan_id}
#   adq_apply <c> <work> <by>      -> desclassifica os candidatos do scan; ecoa o id do lote (rc≠0 = falha)
#   adq_undo <c> <lote> <by>       -> devolve o lote; ecoa quantos voltaram (rc 2 = lote inexistente, 3 = já desfeito)
#   adq_batches_json <c>           -> os lotes (mais novos primeiro), sem a lista de logins: {id,at,by,count,undone_at,undone_by}

adq_state_file(){ printf '%s/%s/var/absent-dq.json' "$CONTESTSDIR" "$1"; }

adq_window(){
  local c="$1" ls st end now="$EPOCHSECONDS" from
  ls="$(conf_value "$c" LOGIN_START_TIME)"; ls="${ls//[^0-9]/}"
  st="$(conf_value "$c" CONTEST_START)"; st="${st//[^0-9]/}"
  if [[ -n "$ls" ]] && (( ls > 0 )); then from=$(( ls - 3600 ))
  elif [[ -n "$st" ]] && (( st > 0 )); then from=$(( st - 3600 ))
  else from=0; fi
  (( from < 0 )) && from=0
  end="$(contest_end_all "$c")"; [[ "$end" =~ ^[0-9]+$ ]] || end=0
  (( end > 0 && end < now )) || end=$now
  printf '%s %s' "$from" "$end"
}

adq_scan(){
  local c="$1" w="$2" cdir="$CONTESTSDIR/$1" from to live=false
  read -r from to < <(adq_window "$c")
  local e; e="$(contest_end_all "$c")"; [[ "$e" =~ ^[0-9]+$ ]] || e=0
  (( e == 0 || EPOCHSECONDS <= e )) && live=true
  # população: os diretórios de conta do contest (a fonte USERS_FROM não entra: quem nunca entrou não tem linha)
  find "$cdir/users" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%f\n' 2>/dev/null \
    | grep -vE "$ROLE_RE" | sort > "$w/pop.txt"
  # contas: nome, sigla, sede, já desclassificado — uma varredura (nunca um jq por conta)
  find "$cdir/users" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
    | xargs -0 -r jq -c '{login:(input_filename | split("/") | .[-2]), name:((.team.name // .fullname // "") | tostring),
        univ:((.team.univ_short // "") | tostring), region:((.team.region // "") | tostring), dq:(.disqualified == true)}' \
      2>/dev/null > "$w/acc.ndjson"
  # quem tem submissão (history não vazio) — conservador: qualquer linha do store atual
  find "$cdir/users" -mindepth 2 -maxdepth 2 -name history -size +0 -printf '%h\n' 2>/dev/null | sed 's|.*/||' | sort -u > "$w/subs.txt"
  # logins: o último de cada conta (qualquer hora) e quem logou na janela
  : > "$w/acc-log.tsv"
  [[ -s "$cdir/var/access.log" ]] && awk -F'\t' -v a="$from" -v b="$to" 'NF >= 2 && $1 ~ /^[0-9]+$/ {
      t = $1 + 0; if (t > last[$2]) last[$2] = t; if (t >= a && t <= b) win[$2] = 1 }
    END { for (l in last) print l "\t" last[l] "\t" (l in win ? 1 : 0) }' "$cdir/var/access.log" > "$w/acc-log.tsv"
  # classificados: os times de todo estágio PUBLICADO
  if [[ -s "$cdir/classification.json" ]]; then
    jq -c '[(.stages // [])[] | select(.status == "published") | .id as $s | (.teams // {}) | to_entries[]
             | {login:.key, via:(.value.via // ""), stage:$s}]' "$cdir/classification.json" 2>/dev/null > "$w/cls.json"
  fi
  [[ -s "$w/cls.json" ]] || printf '[]' > "$w/cls.json"
  jq -n --rawfile pop "$w/pop.txt" --rawfile subs "$w/subs.txt" --rawfile al "$w/acc-log.tsv" \
        --slurpfile acc "$w/acc.ndjson" --slurpfile cls "$w/cls.json" \
        --argjson from "$from" --argjson to "$to" --argjson live "$live" '
    def lines($s): $s | split("\n") | map(select(length > 0));
    (lines($pop)) as $P
    | (lines($subs) | map({(.): true}) | add // {}) as $S
    | (lines($al) | map(split("\t")) | map({(.[0]): {last:(.[1] | tonumber), win:(.[2] == "1")}}) | add // {}) as $L
    | ($acc | map({(.login): .}) | add // {}) as $A
    | ($cls[0] | group_by(.login) | map({(.[0].login): .[0]}) | add // {}) as $C
    | [ $P[] | . as $l | ($A[$l] // {login:$l, name:"", univ:"", region:"", dq:false}) + {last_login:($L[$l].last // null)}
        + {logged:($L[$l].win // false), subs:($S[$l] // false), cls:$C[$l]} ] as $T
    | [ $T[] | select((.logged | not) and (.subs | not) and (.dq | not)) ] as $absent
    | [ $absent[] | select(.cls == null) | {login, name, univ, region, last_login} ] as $cand
    | {window:{from:$from, to:$to}, live:$live,
       counts:{teams:($T | length), logged:([$T[] | select(.logged)] | length), with_subs:([$T[] | select(.subs)] | length),
               already_dq:([$T[] | select(.dq)] | length), absent:($absent | length),
               kept_classified:([$absent[] | select(.cls != null)] | length), candidates:($cand | length)},
       candidates:($cand | sort_by(.region, .login)),
       kept_classified:([$absent[] | select(.cls != null) | {login, name, region, via:.cls.via, stage:.cls.stage}] | sort_by(.login)),
       plan_id:null}' > "$w/scan.json" || return 1
  # plan_id = md5 da lista ordenada dos candidatos: mudou a lista entre a prévia e o clique = 409 plan_changed
  local pid; pid="$(jq -r '[.candidates[].login] | sort | join(",")' "$w/scan.json" | md5sum | cut -c1-16)"
  jq --arg p "$pid" '.plan_id = $p' "$w/scan.json" > "$w/scan2.json" && mv -f "$w/scan2.json" "$w/scan.json"
}

_adq_state_write(){  # <c> <json-file>  (atômico; o tmp é resolvido ANTES do comando externo)
  local f t; f="$(adq_state_file "$1")"; t="$f.tmp.${BASHPID}"
  cp -f "$2" "$t" && mv -f "$t" "$f"
}

adq_apply(){
  local c="$1" w="$2" by="$3" id l af t n=0
  id="adq$(printf '%s%s%s' "$c" "$EPOCHSECONDS" "$RANDOM" | md5sum | cut -c1-10)"
  jq -r '.candidates[].login' "$w/scan.json" > "$w/logins.txt"
  while IFS= read -r l; do
    [[ -n "$l" ]] || continue
    valid_id "$l" || continue
    user_exists "$c" "$l" || shared_overlay_ensure "$c" "$l" || continue
    af="$(account_file "$c" "$l")"; t="$af.tmp.${BASHPID}"
    jq -c --arg b "$id" '.disqualified = true | .dq_batch = $b | .updated_at = (now | floor)' "$af" > "$t" 2>/dev/null \
      && [[ -s "$t" ]] && mv -f "$t" "$af" || { rm -f "$t"; continue; }
    audit_log_to "$c" user-disqualify "login=$l undo=false batch=$id"
    printf '%s\n' "$l" >> "$w/done.txt"; n=$((n + 1))
  done < "$w/logins.txt"
  touch "$CONTESTSDIR/$c/var/.score-dirty" 2>/dev/null
  [[ -s "$w/done.txt" ]] || : > "$w/done.txt"
  local sf; sf="$(adq_state_file "$c")"
  { [[ -s "$sf" ]] && jq -e . "$sf" >/dev/null 2>&1 && cat "$sf" || printf '{"batches":[]}'; } > "$w/st0.json"
  jq --arg id "$id" --arg by "$by" --argjson at "$EPOCHSECONDS" --slurpfile s "$w/scan.json" --rawfile d "$w/done.txt" \
    '.batches = ((.batches // []) + [{id:$id, at:$at, by:$by, window:$s[0].window,
                                     logins:($d | split("\n") | map(select(length > 0)))}])' "$w/st0.json" > "$w/st1.json" \
    && _adq_state_write "$c" "$w/st1.json" || return 1
  audit_log_to "$c" absent-disqualify "batch=$id n=$n by=$by"
  printf '%s' "$id"
}

adq_undo(){
  local c="$1" id="$2" by="$3" sf w l af t n=0
  sf="$(adq_state_file "$c")"; [[ -s "$sf" ]] || return 2
  jq -e --arg id "$id" 'any(.batches[]?; .id == $id)' "$sf" >/dev/null 2>&1 || return 2
  jq -e --arg id "$id" 'any(.batches[]?; .id == $id and (.undone_at // 0) > 0)' "$sf" >/dev/null 2>&1 && return 3
  w="$(mktemp -d)" || return 1
  jq -r --arg id "$id" '.batches[] | select(.id == $id) | .logins[]' "$sf" > "$w/logins.txt"
  while IFS= read -r l; do
    valid_id "$l" || continue
    af="$(account_file "$c" "$l")"; [[ -f "$af" ]] || continue
    # só quem AINDA tem a marca deste lote: desclassificado à mão depois (ou já devolvido) fica como está
    jq -e --arg id "$id" '.disqualified == true and .dq_batch == $id' "$af" >/dev/null 2>&1 || continue
    t="$af.tmp.${BASHPID}"
    jq -c 'del(.disqualified, .dq_batch) | .updated_at = (now | floor)' "$af" > "$t" 2>/dev/null \
      && [[ -s "$t" ]] && mv -f "$t" "$af" || { rm -f "$t"; continue; }
    audit_log_to "$c" user-disqualify "login=$l undo=true batch=$id"
    n=$((n + 1))
  done < "$w/logins.txt"
  touch "$CONTESTSDIR/$c/var/.score-dirty" 2>/dev/null
  jq --arg id "$id" --arg by "$by" --argjson at "$EPOCHSECONDS" \
    '.batches |= map(if .id == $id then . + {undone_at:$at, undone_by:$by} else . end)' "$sf" > "$w/st.json" \
    && _adq_state_write "$c" "$w/st.json"
  audit_log_to "$c" absent-disqualify-undo "batch=$id n=$n by=$by"
  rm -rf "$w"
  printf '%s' "$n"
}

adq_batches_json(){
  local sf; sf="$(adq_state_file "$1")"
  [[ -s "$sf" ]] && jq -c '[(.batches // [])[] | {id, at, by, count:(.logins | length), window,
                                undone_at:(.undone_at // null), undone_by:(.undone_by // null)}] | reverse' "$sf" 2>/dev/null \
    || printf '[]'
}
