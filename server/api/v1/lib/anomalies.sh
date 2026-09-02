# lib/anomalies.sh — MOTOR de anomalias de uso de máquina DURANTE a prova (painel Pessoas ›
# Sessões & anomalias; rota GET /contest/admin/anomalies). Só faz sentido com o gate de UA
# ligado: sem ele o navegador não identifica a máquina e nada disto vale (gate.active:false).
#
# Entradas (todas append-only, do próprio contest, recortadas pela janela da rodada):
#   var/access.log         epoch \t login \t ip \t ua_b64            (login.sh)
#   var/submit-origin.log  epoch \t subid \t login \t ip \t ua_b64 \t sess_ip \t sess_ua_b64 \t sess_mkey \t tok8
#   var/session-events.log epoch \t login \t evento \t old_key \t new_key \t tok8 [\t quem]
#   sessões VIVAS do contest (índice lib/session-index.sh; sem índice, varredura que o semeia)
#   ua-gate.json (esperado por time, em lote) · var/nutella.cache.json (sedes × máquinas)
# Cada entrada vira UM arquivo NDJSON por awk (nada de jq por linha) e UM jq monta tudo
# (--slurpfile p/ os agregados — nunca --argjson; valores de objeto entre parênteses, jq 1.7).
#
# CHAVE DE MÁQUINA (`mkey`, o MESMO da lib/session-index.sh): UA do mlinux
# `MLinux/<img>/<machine_id>/<boot_id>` ⇒ "m:<mid>/<boot>" (o boot_id separa machine_id
# CLONADO); senão "ip:<ip>". Mesmo mid com boot diferente = a mesma máquina reiniciada (info).
# ⚠ Só a chave "m:" identifica uma MÁQUINA. "ip:" numa sede atrás de NAT é a sede inteira
# (na LATAM, 300 times mexicanos com Chrome caíam numa "máquina compartilhada" só): as
# anomalias de máquina (multi_session, machine_shared, sub_other_machine, switched) só olham
# chaves "m:"; login sem chave do mlinux só aparece em ua_mismatch e na lista de sessões.
#
# TIPOS (kind → severidade):
#   multi_session     bad   login com 2+ sessões vivas em chaves diferentes (com sessão única
#                           ligada só acontece por token copiado, ou gate desligado na hora)
#   machine_shared    warn  chave com login de 2+ times DURANTE a prova; bad se ambos vivos nela
#   sub_other_machine bad   submissão cuja requisição veio de chave ≠ da sessão (mid diferente);
#                     info  mesmo mid, boot diferente (reboot)
#   ua_mismatch       warn  sessão viva cujo UA não casa o esperado da sede (sinal do logout-mismatch)
#   site_short        warn  sede com mais times presentes que máquinas vistas (cache do nutellaboot)
#   switched          info  time que logou em 2+ máquinas durante a prova
#   session_event     info  revoke / logout / mismatch-logout (a trilha da sessão única)
# Requer: lib/common.sh, lib/auth.sh, lib/session-index.sh, lib/users.sh, lib/ua-gate.sh,
# lib/contest-rounds.sh (rd_round/rd_active) já sourceados pelo handler.

# an_build <contest> <round-slug|""> <outfile> -> escreve o JSON (sem envelope) em <outfile>
an_build(){
  local c="$1" s="${2:-}" out="$3" cdir="$CONTESTSDIR/$1"
  local r cs ce ws
  [[ -n "$s" ]] || s="$(rd_active "$c")"
  r="$(rd_round "$c" "$s")"; [[ -n "$r" ]] || r='{}'
  cs="$(jq -r '.start // 0' <<<"$r")"; ce="$(jq -r '.end // 0' <<<"$r")"
  [[ "$cs" =~ ^[0-9]+$ ]] || cs=0; [[ "$ce" =~ ^[0-9]+$ ]] || ce=0
  (( ce > 0 && ce < EPOCHSECONDS )) || ce=$EPOCHSECONDS
  ws=$(( cs > 21600 ? cs - 21600 : 0 ))          # logins da manhã contam p/ "máquina do time"

  local W; W="$(mktemp -d)" || return 1
  # --- access.log → NDJSON (janela ampla; `in` = dentro da prova) ---------------------------
  : > "$W/acc.json"
  [[ -s "$cdir/var/access.log" ]] && awk -F'\t' -v a="$ws" -v b="$ce" 'NF>=4 && $1+0>=a && $1+0<=b {
      gsub(/["\\]/,"",$2); gsub(/["\\]/,"",$3); gsub(/["\\]/,"",$4)
      printf "{\"t\":%d,\"login\":\"%s\",\"ip\":\"%s\",\"ua64\":\"%s\"}\n", $1, $2, $3, $4 }' \
    "$cdir/var/access.log" > "$W/acc.json"
  # --- submit-origin.log → NDJSON (só a prova) ----------------------------------------------
  : > "$W/sub.json"
  [[ -s "$cdir/var/submit-origin.log" ]] && awk -F'\t' -v a="$cs" -v b="$ce" 'NF>=9 && $1+0>=a && $1+0<=b {
      for(i=2;i<=9;i++) gsub(/["\\]/,"",$i)
      printf "{\"t\":%d,\"id\":\"%s\",\"login\":\"%s\",\"ip\":\"%s\",\"ua64\":\"%s\",\"sip\":\"%s\",\"sua64\":\"%s\",\"smkey\":\"%s\",\"tok8\":\"%s\"}\n", $1,$2,$3,$4,$5,$6,$7,$8,$9 }' \
    "$cdir/var/submit-origin.log" > "$W/sub.json"
  # --- session-events.log → NDJSON ----------------------------------------------------------
  : > "$W/ev.json"
  [[ -s "$cdir/var/session-events.log" ]] && awk -F'\t' -v a="$ws" -v b="$ce" 'NF>=6 && $1+0>=a && $1+0<=b {
      for(i=2;i<=7;i++) gsub(/["\\]/,"",$i)
      printf "{\"t\":%d,\"login\":\"%s\",\"event\":\"%s\",\"old\":\"%s\",\"new\":\"%s\",\"tok8\":\"%s\",\"who\":\"%s\"}\n", $1,$2,$3,$4,$5,$6,$7 }' \
    "$cdir/var/session-events.log" > "$W/ev.json"
  # --- sessões VIVAS do contest -------------------------------------------------------------
  # Pelo índice (barato: só os tokens deste contest). Sem índice semeado: varredura completa,
  # que semeia (só apêndice, flock -n) — a mesma doutrina do sessions.sh.
  : > "$W/sess.txt"
  local f t CONTEST LOGIN IP UA_B64 LOGINAT MKEY
  if sess_index_seeded "$c"; then
    local idxd; idxd="$(_sidx_dir "$c")"
    ( set +o noglob; shopt -s nullglob
      for f in "$idxd"/*; do
        [[ -f "$f" && "$f" != *.lock ]] || continue
        while IFS= read -r t; do
          [[ -n "$t" ]] && valid_id "$t" && [[ -f "$SESSIONDIR/$t" ]] || continue
          CONTEST=""; LOGIN=""; IP=""; UA_B64=""; LOGINAT=""; MKEY=""; source "$SESSIONDIR/$t" 2>/dev/null
          [[ "$CONTEST" == "$c" && "$LOGIN" == "${f##*/}" ]] || continue
          printf '%s\x01%s\x01%s\x01%s\x01%s\x01%s\n' "$LOGIN" "${t:0:8}" "$IP" "$UA_B64" "${LOGINAT:-0}" "$MKEY"
        done < "$f"
      done ) | sort -u > "$W/sess.txt"
  else
    local sd sfd seed=0; sd="$(_sidx_dir "$c")"; mkdir -p "$sd" 2>/dev/null; chmod 700 "$sd" 2>/dev/null
    if exec {sfd}>"$sd/.seed.lock" 2>/dev/null && flock -n "$sfd" 2>/dev/null; then seed=1; fi
    ( set +o noglob; shopt -s nullglob
      for f in "$SESSIONDIR"/*; do
        [[ -f "$f" ]] || continue
        CONTEST=""; LOGIN=""; IP=""; UA_B64=""; LOGINAT=""; MKEY=""; source "$f" 2>/dev/null
        [[ "$CONTEST" == "$c" && -n "$LOGIN" ]] || continue
        (( seed )) && valid_id "$LOGIN" && printf '%s\n' "${f##*/}" >> "$sd/$LOGIN" 2>/dev/null
        t="${f##*/}"
        printf '%s\x01%s\x01%s\x01%s\x01%s\x01%s\n' "$LOGIN" "${t:0:8}" "$IP" "$UA_B64" "${LOGINAT:-0}" "$MKEY"
      done ) > "$W/sess.txt"
    (( seed )) && : > "$sd/.seeded"
    [[ -n "${sfd:-}" ]] && eval "exec ${sfd}>&-"
  fi
  jq -Rc 'split("\u0001") | select(length >= 6)
          | {login:.[0], tok8:.[1], ip:.[2], ua64:.[3], at:(.[4]|tonumber? // 0), mkey:.[5]}' \
    "$W/sess.txt" > "$W/sess.json" 2>/dev/null || : > "$W/sess.json"
  # --- identidade dos times (UMA varredura, molde do rd_machines) ---------------------------
  find "$(users_dir "$c")" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
    | xargs -0 -r jq -c '((input_filename | split("/"))[-2]) as $l
        | {key:$l, value:{name:(.fullname // .team.name // $l), region:((.team.region) // "")}}' 2>/dev/null \
    | jq -cs 'from_entries' > "$W/users.json"
  [[ -s "$W/users.json" ]] || printf '{}' > "$W/users.json"
  # --- gate: modo + esperado por login (lote) -----------------------------------------------
  local gj mode single; gj="$(ug_get "$c")"
  mode="$(jq -r '.mode' <<<"$gj")"; single="$(jq -r '.single_session' <<<"$gj")"
  printf '{}' > "$W/exp.json"
  if [[ "$mode" == enforce ]]; then
    jq -sc '[ .[].login ] | unique' "$W/acc.json" "$W/sess.json" 2>/dev/null > "$W/logins.json" || printf '[]' > "$W/logins.json"
    ug_expected_map "$c" "$(cat "$W/logins.json")" \
      "$(jq -c 'with_entries(.value |= .region)' "$W/users.json" 2>/dev/null || echo '{}')" > "$W/exp.json" 2>/dev/null \
      || printf '{}' > "$W/exp.json"
    [[ -s "$W/exp.json" ]] || printf '{}' > "$W/exp.json"
  fi
  # --- nutellaboot (sedes × máquinas), se houver coleta ----------------------------------------
  printf 'null' > "$W/nut.json"
  [[ -s "$cdir/var/nutella.cache.json" ]] && jq -c '{collected_at, sedes: [ .sedes[]? | {name, machines_total, seen, teams:(.pop.teams // (.teams|length)), present:(.pop.present // null)} ]}' \
    "$cdir/var/nutella.cache.json" > "$W/nut.json" 2>/dev/null

  # --- o jq único ----------------------------------------------------------------------------
  jq -n --slurpfile acc "$W/acc.json" --slurpfile sess "$W/sess.json" --slurpfile sub "$W/sub.json" \
        --slurpfile ev "$W/ev.json" --slurpfile users "$W/users.json" --slurpfile exp "$W/exp.json" \
        --slurpfile nut "$W/nut.json" \
        --arg mode "$mode" --arg single "$single" --arg round "$s" \
        --argjson cs "$cs" --argjson ce "$ce" --argjson ws "$ws" --argjson now "$EPOCHSECONDS" '
    def role($l): ($l | test("\\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$"));
    def mkey($ip; $ua):
      ((($ua | capture("MLinux/[^/]+/(?<mid>[0-9a-f]{32})/(?<boot>[0-9]+)")) // null) as $m
       | if $m != null then ("m:" + $m.mid + "/" + $m.boot) else ("ip:" + $ip) end);
    def mid($k): (if (($k // "") | startswith("m:")) then ($k[2:] | split("/")[0]) else null end);
    def ism($k): (($k // "") | startswith("m:"));
    def short($ua): ($ua | if length > 60 then (.[0:57] + "…") else . end);
    ($users[0] // {}) as $U
    | ($exp[0] // {}) as $E
    | ($nut[0] // null) as $N
    | ([ $acc[].ua64, $sess[].ua64, $sub[].ua64, $sub[].sua64 ] | map(select(. != null and . != "")) | unique
       | map({key:., value:(try (. | @base64d) catch "?")}) | from_entries) as $DEC
    | ([ $acc[] | select(role(.login) | not)
         | . + {ua:($DEC[.ua64] // ""), key:(mkey(.ip; ($DEC[.ua64] // ""))), in:(.t >= $cs)} ]) as $A
    | ([ $sess[] | select(role(.login) | not)
         | . + {ua:($DEC[.ua64] // ""), key:(if (.mkey // "") != "" then .mkey else (mkey(.ip; ($DEC[.ua64] // ""))) end)} ]) as $S
    | ([ $sub[] | . + {ua:($DEC[.ua64] // ""), key:(mkey(.ip; ($DEC[.ua64] // "")))}
         | . + {skey:(if (.smkey // "") != "" then .smkey
                      elif (.sua64 // "") != "" then (mkey(.sip; ($DEC[.sua64] // ""))) else "" end)} ]) as $B
    | (($mode == "enforce") and (([ $E | to_entries[] | select((.value // "") != "") ] | length) > 0)) as $active
    | def nm($l): (($U[$l] // {}).name // $l);
      def rg($l): (($U[$l] // {}).region // "");
    # --- máquinas por login (toda a janela) e sessões por login ----------------------------
    ($A | group_by(.login) | map({ key: .[0].login,
        value: (group_by(.key) | map({key: .[0].key, first: (map(.t) | min), last: (map(.t) | max),
                                      n: length, in: ([ .[] | select(.in) ] | length)})
                | sort_by(.first)) }) | from_entries) as $MACH
    | ($S | group_by(.login) | map({key: .[0].login, value: (map({key, ip, ua: (short(.ua)), at, tok8}) | sort_by(.at))}) | from_entries) as $SESS
    | ([ $S[] | select(ism(.key)) | .key ] | unique) as $LIVEKEYS
    | ($S | map(select(ism(.key))) | group_by(.key) | map({key: .[0].key, value: (map(.login) | unique)}) | from_entries) as $LIVEBY
    # --- anomalias -------------------------------------------------------------------------
    | ([ $SESS | to_entries[] | select((.value | map(select(ism(.key)) | .key) | unique | length) > 1)
         | {kind:"multi_session", severity:"bad", at:(.value | map(.at) | max), login:.key, name:(nm(.key)), region:(rg(.key)),
            machine:(.value | map(select(ism(.key)) | .key) | unique | join(" · ")),
            detail:{keys:(.value | map(select(ism(.key)) | .key) | unique), sessions:(.value | length)}} ]) as $MS
    | ([ $A[] | select(.in and ism(.key)) ] | group_by(.key)
       | map(select((map(.login) | unique | length) > 1))
       | map(. as $g | ($g | map(.login) | unique) as $ls
             | (([ $ls[] | . as $l | select((($LIVEBY[$g[0].key] // []) | index($l)) != null) ] | length) >= 2) as $both
             | {kind:"machine_shared", severity:(if $both then "bad" else "warn" end), at:($g | map(.t) | max),
                login:($ls | join(", ")), name:($ls | map(nm(.)) | join(", ")), region:(rg($ls[0])), machine:$g[0].key,
                detail:{logins:($ls | map(. as $l | {login:., name:(nm(.)), first:([ $g[] | select(.login == $l) | .t ] | min),
                                                      last:([ $g[] | select(.login == $l) | .t ] | max), n:([ $g[] | select(.login == $l) ] | length),
                                                      live:((($LIVEBY[$g[0].key] // []) | index($l)) != null)})),
                        live_both:$both}})) as $SH
    | ([ $B[] | select((.skey // "") != "" and .key != .skey and ism(.key) and ism(.skey))
         | (mid(.key) != null and mid(.key) == mid(.skey)) as $reboot
         | {kind:"sub_other_machine", severity:(if $reboot then "info" else "bad" end), at:.t, login:.login, name:(nm(.login)), region:(rg(.login)),
            machine:.key, detail:{subid:.id, session_key:.skey, request_key:.key, reboot:$reboot, tok8:.tok8}} ]) as $SO
    | ([ $S[] | ($E[.login] // "") as $e | select($e != "" and (((.ua | ascii_downcase) | contains($e | ascii_downcase)) | not))
         | {kind:"ua_mismatch", severity:"warn", at:.at, login:.login, name:(nm(.login)), region:(rg(.login)), machine:.key,
            detail:{expected:$e, ua:(short(.ua)), tok8:.tok8}} ]) as $UM
    | ([ $MACH | to_entries[] | select(([ .value[] | select(.in > 0 and ism(.key)) ] | length) > 1) | .key as $tl
         | {kind:"switched", severity:"info", at:([ .value[] | select(.in > 0 and ism(.key)) | .first ] | max), login:$tl, name:(nm($tl)), region:(rg($tl)),
            machine:([ .value[] | select(.in > 0 and ism(.key)) | .key ] | join(" → ")),
            detail:{machines:([ .value[] | select(.in > 0 and ism(.key)) ]),
                    revoked:([ $ev[] | select(.login == $tl and .event == "revoke") ] | length)}} ]) as $SW
    | ([ ($N.sedes // [])[] | select(((.present // 0) > .seen) or ((.teams // 0) > .machines_total))
         | {kind:"site_short", severity:"warn", at:($N.collected_at // 0), login:"", name:.name, region:.name, machine:"",
            detail:{teams:.teams, present:.present, machines_total:.machines_total, seen:.seen}} ]) as $SS
    | ([ $ev[] | {kind:"session_event", severity:"info", at:.t, login:.login, name:(nm(.login)), region:(rg(.login)),
                  machine:(if .event == "revoke" then (.old + " → " + .new) else .old end),
                  detail:{event:.event, old:.old, new:.new, tok8:.tok8, who:.who}} ]) as $EV
    | (if $active then ($MS + $SH + $SO + $UM + $SW + $SS) else [] end) as $AN
    | (($AN | map(.login) | map(split(", ")[]) | unique) + ($SESS | keys)) as $TL
    # --- última submissão por login ----------------------------------------------------------
    | ($B | group_by(.login) | map({key: .[0].login, value: (max_by(.t))}) | from_entries) as $LASTSUB
    | {
        gate: {mode:$mode, single_session:($single == "true"), active:$active},
        round: $round, window: {start:$cs, end:$ce, since:$ws}, computed_at: $now,
        # contagens saem de $AN: com o gate inativo tudo zera (as sessões e a trilha ficam)
        counts: { sessions: ($S | length), teams_live: ($SESS | length),
                  multi_session: ([ $AN[] | select(.kind == "multi_session") ] | length),
                  machine_shared: ([ $AN[] | select(.kind == "machine_shared") ] | length),
                  sub_other_machine: ([ $AN[] | select(.kind == "sub_other_machine" and .severity == "bad") ] | length),
                  reboot: ([ $AN[] | select(.kind == "sub_other_machine" and .severity == "info") ] | length),
                  ua_mismatch: ([ $AN[] | select(.kind == "ua_mismatch") ] | length),
                  site_short: ([ $AN[] | select(.kind == "site_short") ] | length),
                  switched: ([ $AN[] | select(.kind == "switched") ] | length),
                  revoked: ([ $ev[] | select(.event == "revoke") ] | length), events: ($ev | length) },
        anomalies: ($AN | sort_by(-.at)),
        events: ($EV | sort_by(-.at) | .[0:500]),
        teams: ([ $TL | unique[] | select(. != "" and (role(.) | not)) | . as $l
                  | ($LASTSUB[$l] // null) as $ls
                  | ([ ($MACH[$l] // [])[] | select(.in > 0) | .key ] | last) as $curkey
                  | { login:$l, name:(nm($l)), region:(rg($l)),
                      sessions:($SESS[$l] // []), machines:($MACH[$l] // []),
                      last_sub:(if $ls == null then null else
                                 {at:$ls.t, key:$ls.key, same_as_session:(($ls.skey // "") == "" or $ls.key == $ls.skey),
                                  same_as_login_machine:($curkey == null or $ls.key == $curkey)} end),
                      flags:([ $AN[] | select((.login | split(", ")) | index($l) != null) | .kind ] | unique) } ]
                | sort_by(-(.flags | length), .login)),
        # ⚠ arg de função jq avalia contra o INPUT: `$LIVEKEYS | index(.[0].key)` leria `.key` de
        # uma string — a chave é bindada ANTES (armadilha documentada no repo)
        machines: ($A | map(select(ism(.key))) | group_by(.key) | map(.[0].key as $k
                    | {key:$k, logins:(group_by(.login) | map({login:.[0].login, first:(map(.t)|min), last:(map(.t)|max), n:length, in:([ .[] | select(.in) ] | length)})),
                       shared:(([ .[] | select(.in) | .login ] | unique | length) > 1),
                       live:(($LIVEKEYS | index($k)) != null)}) | map(select(.shared or .live))),
        sites: ($SS | map(.detail + {name:.name})),
        nutella_at: ($N.collected_at // null)
      }' > "$out" 2>"$W/err" || { cat "$W/err" >&2; [[ -n "${AN_KEEP_W:-}" ]] && echo "W=$W" >&2 || rm -rf "$W"; return 1; }
  [[ -n "${AN_KEEP_W:-}" ]] && echo "W=$W" >&2 || rm -rf "$W"
  return 0
}
