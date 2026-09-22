# lib/nutella-bind.sh — publica no NutellaBoot o elo máquina↔time que o LOGIN revela.
#
# O agente novo do mlinux (NutellaBoot 3) põe o MAC no fim do User-Agent:
#   Mozilla/5.0 (MLinux/<imagem>/<machine_id>/<boot_id>/<mac>) …
# Então o login de um time DIZ em que máquina ele está. O serviço aceita receber isso —
# `PUT /site-images/{i}/machines/{mac}/binding {user_id, source, at, boot_id}` — e passa a mostrar o
# time na tela de bloqueio da máquina e no painel da sede; o coletor (score/nutella-gen.sh) lê o
# `binding` de volta onde o UA não disse nada.
#
# CUSTO ZERO NO LOGIN: a largada de uma prova são ~2.000 logins em minutos. O login só ACRESCENTA
# uma linha numa fila (printf, builtin) e — no máximo a cada NB_BIND_EVERY s — larga um drenador
# DESTACADO (molde owner_rename_bg: redirects no setsid, senão o filho herda o socket do CGI e o
# cliente espera). Quem fala com o serviço é o drenador, nunca o worker do login.
#
#   var/nutella-bind.queue   epoch \t login \t imagem \t mac \t boot_id [\t tentativa]
#   var/nutella-bind.log     epoch \t login \t imagem \t mac \t status \t detalhe   (ok|noroster|image_unknown|retry|http <n>)
#   var/nutella-macs.tsv     mac \t login \t imagem \t boot_id \t epoch               (último elo PUBLICADO por máquina)
#   var/.nutella-bind.stamp  epoch da última passada · var/.nutella-bind.lock  flock do drenador
#
# NÃO PERDE ENTRADA: o drenador grava o carimbo no INÍCIO de cada passada e só sai se a fila estiver
# vazia DEPOIS de dormir NB_BIND_EVERY s. Logo: login antes da checagem ⇒ o drenador vê a linha;
# login depois ⇒ o carimbo já tem ≥ NB_BIND_EVERY s ⇒ esse login larga outro drenador, que ESPERA o
# lock (flock -w) em vez de desistir.
#
# LIMITES: só módulo `maquinas` ligado + chave configurada; conta de PAPEL nunca; `NUTELLA_BIND=0` no
# conf desliga; a imagem do UA tem de ser uma sede DO CONTEST (NUTELLABOOT_IMAGES ∪ sedes da última
# coleta) — o UA é entrada do cliente, e a chave de administração alcança sedes de OUTROS eventos.
# O serviço responde 404 `user_not_in_roster` se o time não está no roster da imagem: fica no log como
# `noroster` (rode o `push-roster` e depois o `push-bindings`) — OU, com `NUTELLA_BIND_ROSTER=1` no conf, o
# binding vai com `create_roster_entry` (nome/universidade/país do account.json) e o serviço cria a entrada
# marcada `source:"binding"` (um roster oficial enviado depois a sobrescreve). Opt-in: o `user_id` nasce de
# um User-Agent, entrada do cliente. 429 respeita o `Retry-After` do serviço. O UA pode ser forjado — quem barra isso é o gate de UA
# por sede; o binding é informação p/ o staff, não controle de acesso.
NB_BIND_EVERY="${NB_BIND_EVERY:-10}"
NB_BIND_UA_RE='MLinux/([A-Za-z0-9._-]{1,64})/[0-9a-f]{32}/([0-9]{1,20})/([0-9a-f]{2}([-:][0-9a-f]{2}){5})([^0-9a-f:-]|$)'

# nb_bind_enqueue <contest> <login> — chamado pelo login. Sem fork até decidir largar o drenador.
nb_bind_enqueue(){
  local c="$1" l="$2" ua="${HTTP_USER_AGENT:-}" img boot mac d v last=0
  [[ "$ua" =~ $NB_BIND_UA_RE ]] || return 0
  img="${BASH_REMATCH[1]}"; boot="${BASH_REMATCH[2]}"; mac="${BASH_REMATCH[3]//:/-}"
  is_reserved_role_login "$l" && return 0
  d="$CONTESTSDIR/$c"
  [[ -s "$d/secrets/nutellaboot.key" ]] || return 0
  v="$(conf_value "$c" NUTELLA_BIND)"; [[ "$v" == 0 ]] && return 0
  v=",$(conf_value "$c" CONTEST_MODULES),"; v="${v//\\/}"; [[ "$v" == *",maquinas,"* ]] || return 0
  printf '%s\t%s\t%s\t%s\t%s\n' "$EPOCHSECONDS" "$l" "$img" "$mac" "$boot" >> "$d/var/nutella-bind.queue" 2>/dev/null || return 0
  if [[ "${MOJ_JOBS_SYNC:-0}" == 1 ]]; then nb_bind_drain "$c"; return 0; fi
  [[ -r "$d/var/.nutella-bind.stamp" ]] && read -r last < "$d/var/.nutella-bind.stamp" 2>/dev/null
  [[ "$last" =~ ^[0-9]+$ ]] || last=0
  (( EPOCHSECONDS - last >= NB_BIND_EVERY )) || return 0
  printf '%s\n' "$EPOCHSECONDS" > "$d/var/.nutella-bind.stamp" 2>/dev/null
  nb_bind_drain_bg "$c"
}

nb_bind_drain_bg(){
  local lib; lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # redirects no SETSID (não dentro do bash -c): senão o filho herda o socket do CGI e o cliente espera
  ( setsid env RUNDIR="${RUNDIR:-}" CONTESTSDIR="$CONTESTSDIR" SESSIONDIR="${SESSIONDIR:-}" NB_BIND_EVERY="$NB_BIND_EVERY" \
      bash -c 'source "$1/common.sh" 2>/dev/null; source "$1/nutella.sh" && source "$1/nutella-bind.sh" && nb_bind_drain "$2"' \
      _ "$lib" "$1" </dev/null >/dev/null 2>&1 & ) 2>/dev/null
  return 0
}

# nb_bind_drain <contest> — UM drenador por contest (flock). Sai quando a fila fica vazia.
nb_bind_drain(){
  local c="$1" d="$CONTESTSDIR/$1/var" fd n=0
  declare -F nb_curl >/dev/null 2>&1 || source "$(dirname "${BASH_SOURCE[0]}")/nutella.sh"
  exec {fd}>"$d/.nutella-bind.lock" 2>/dev/null || return 0
  flock -w 5 "$fd" 2>/dev/null || { exec {fd}>&-; return 0; }
  while :; do
    printf '%s\n' "$EPOCHSECONDS" > "$d/.nutella-bind.stamp" 2>/dev/null
    [[ -s "$d/nutella-bind.queue" ]] && _nb_bind_pass "$c"
    [[ "${MOJ_JOBS_SYNC:-0}" == 1 ]] && break
    # teto de vida (1 h de fila que não esvazia): sai SEM carimbo, p/ o próximo login largar outro
    (( ++n >= 360 )) && { rm -f "$d/.nutella-bind.stamp"; break; }
    sleep "$NB_BIND_EVERY"
    [[ -s "$d/nutella-bind.queue" ]] || break
  done
  exec {fd}>&-
}

# imagens em que ESTE contest pode vincular: a lista do conf ∪ as sedes da última coleta
_nb_bind_images(){
  { nb_images "$1"; jq -r '.sedes[]?.id // empty' "$CONTESTSDIR/$1/var/nutella.cache.json" 2>/dev/null; } | sort -u
}

_nb_bind_log(){ printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$EPOCHSECONDS" "$2" "$3" "$4" "$5" "${6:-}" >> "$CONTESTSDIR/$1/var/nutella-bind.log" 2>/dev/null; }

# _nb_roster_entry <contest> <login> -> JSON da entrada de roster (o mesmo shape do push-roster) ou vazio
_nb_roster_entry(){
  local af; af="$(account_file "$1" "$2")"; [[ -f "$af" ]] || return 0
  jq -c --arg l "$2" '{name: ((.team.name // .fullname // $l) | tostring),
    display_name: (((.team.univ_short // "") | if . == "" then "" else "[" + . + "] " end) + ((.team.name // .fullname // $l) | tostring)),
    organization: {id: "", name: (.team.univ_full // .team.univ_short // "")},
    country: ((.team.flag // "") | ascii_upcase | (split("-") | .[0]))}' "$af" 2>/dev/null
}
# nb_bind_put <contest> <login> <imagem> <mac> <boot> <at> <source> -> imprime "status \t code \t retry-after";
# mantém o macs.tsv. (Impresso, não em variável: o chamador roda isto por `$(…)`, um SUBSHELL, e uma
# variável global morreria lá.) `code` = user_not_in_roster | image_not_found | invalid_mac … (vazio no
# serviço antigo); retry-after = o cabeçalho de um 429.
nb_bind_put(){
  local c="$1" lg="$2" img="$3" mac="$4" boot="$5" at="$6" src="$7" d="$CONTESTSDIR/$1/var" bf r st re='null'
  bf="$(mktemp)"
  [[ "$(conf_value "$c" NUTELLA_BIND_ROSTER)" == 1 ]] && re="$(_nb_roster_entry "$c" "$lg")"; [[ -n "$re" ]] || re='null'
  jq -cn --arg u "$lg" --arg s "$src" --argjson at "$at" --arg b "$boot" --argjson re "$re" \
    '{user_id: $u, source: $s, at: $at} + (if $b == "" then {} else {boot_id: $b} end)
     + (if $re == null then {} else {create_roster_entry: $re} end)' > "$bf"
  r="$(NB_TIMEOUT=8 NB_HEADERS=1 nb_curl "$c" PUT "/site-images/$img/machines/$mac/binding" "$bf")"; st="$(nb_status "$r")"
  local code ra; code="$(nb_code "$r")"; ra="$(nb_retry_after "$r")"
  rm -f "$bf"
  if [[ "$st" == 2* ]]; then
    { [[ -s "$d/nutella-macs.tsv" ]] && awk -F'\t' -v m="$mac" '$1 != m' "$d/nutella-macs.tsv"
      printf '%s\t%s\t%s\t%s\t%s\n' "$mac" "$lg" "$img" "$boot" "$at"; } > "$d/.nutella-macs.tmp" 2>/dev/null \
      && mv -f "$d/.nutella-macs.tmp" "$d/nutella-macs.tsv"
  fi
  printf '%s\t%s\t%s' "${st:-000}" "$code" "$ra"
}

_nb_bind_pass(){
  local c="$1" d="$CONTESTSDIR/$1/var" w allowed at lg img mac boot try st
  w="$d/.nutella-bind.work"
  mv -f "$d/nutella-bind.queue" "$w" 2>/dev/null || return 0
  sleep 0.2                                 # quem já tinha aberto a fila p/ acrescentar termina de escrever
  allowed="$(_nb_bind_images "$c")"
  # o ÚLTIMO login de cada máquina é o que vale (a fila de uma largada tem o mesmo time várias vezes)
  sort -t$'\t' -k1,1n "$w" | awk -F'\t' 'NF >= 5 { last[$4] = $0 } END { for (m in last) print last[m] }' > "$w.u"
  while IFS=$'\t' read -r at lg img mac boot try; do
    [[ "$at" =~ ^[0-9]+$ && "$img" =~ ^[A-Za-z0-9._-]{1,64}$ && "$mac" =~ ^[0-9a-f]{2}(-[0-9a-f]{2}){5}$ && "$boot" =~ ^[0-9]{1,20}$ ]] || continue
    valid_id "$lg" || continue
    # já publicado igual (mesmo time, mesmo boot)? — re-login não vira request
    [[ -s "$d/nutella-macs.tsv" ]] && awk -F'\t' -v m="$mac" -v l="$lg" -v b="$boot" '$1 == m && $2 == l && $4 == b { f = 1 } END { exit !f }' "$d/nutella-macs.tsv" && continue
    if ! grep -qxF -- "$img" <<<"$allowed"; then _nb_bind_log "$c" "$lg" "$img" "$mac" image_unknown "imagem fora das sedes do contest"; continue; fi
    IFS=$'\t' read -r st NB_BIND_CODE NB_BIND_RETRY < <(nb_bind_put "$c" "$lg" "$img" "$mac" "$boot" "$at" moj-login)
    case "$st" in
      2*)  _nb_bind_log "$c" "$lg" "$img" "$mac" ok ;;
      404) # só `user_not_in_roster` é "time fora do roster"; imagem/máquina inexistente é erro de verdade
           # (serviço antigo, sem `code`: continua valendo o 404 = noroster)
           if [[ -z "$NB_BIND_CODE" || "$NB_BIND_CODE" == user_not_in_roster ]]; then _nb_bind_log "$c" "$lg" "$img" "$mac" noroster "time fora do roster da imagem"
           else _nb_bind_log "$c" "$lg" "$img" "$mac" "http 404" "$NB_BIND_CODE"; fi ;;
      000|429|5*)
           [[ "$st" == 429 && "$NB_BIND_RETRY" =~ ^[0-9]+$ ]] && sleep "$(( NB_BIND_RETRY > 30 ? 30 : NB_BIND_RETRY ))"
           try="${try:-0}"; [[ "$try" =~ ^[0-9]+$ ]] || try=0
           if (( try < 3 )); then
             printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$at" "$lg" "$img" "$mac" "$boot" "$((try + 1))" >> "$d/nutella-bind.queue"
             _nb_bind_log "$c" "$lg" "$img" "$mac" retry "http $st"
           else _nb_bind_log "$c" "$lg" "$img" "$mac" "http $st" "desistiu após 3 tentativas"; fi ;;
      *)   _nb_bind_log "$c" "$lg" "$img" "$mac" "http $st" ;;
    esac
  done < "$w.u"
  rm -f "$w" "$w.u"
}

# nb_bind_batch <contest> <tsv: at login imagem mac boot> -> rc 0 e imprime {sent, bound, failed, noroster};
# rc 1 = a rota de lote não existe (serviço antigo): o chamador cai na fila de sempre.
# `PUT /site-images/{i}/bindings {bindings:[…], create_roster_entry?}` (até 1000 por request; resultado por
# item, sempre 200). É o caminho do `push-bindings` (replay do access.log: ~2.000 logins da largada em
# 2-3 requests por sede, em vez de 2.000 PUTs serializados no drenador).
nb_bind_batch(){
  local c="$1" tsv="$2" d="$CONTESTSDIR/$1/var" allowed img W r st sent=0 bound=0 failed=0 nor=0 re=0
  W="$(mktemp -d)" || return 1
  allowed="$(_nb_bind_images "$c")"
  [[ "$(conf_value "$c" NUTELLA_BIND_ROSTER)" == 1 ]] && re=1
  # último login de cada MAC, dedup contra o já publicado (mesmo time e boot), imagem tem de ser sede do contest
  sort -t$'\t' -k1,1n "$tsv" | awk -F'\t' 'NF >= 5 { last[$4] = $0 } END { for (m in last) print last[m] }' \
    | awk -F'\t' -v M="$d/nutella-macs.tsv" 'BEGIN{ while ((getline l < M) > 0) { split(l, a, "\t"); K[a[1]] = a[2] "\t" a[4] } }
        !(($4 in K) && K[$4] == $2 "\t" $5)' > "$W/todo.tsv"
  while IFS=$'\t' read -r at lg img mac boot; do
    [[ "$img" =~ ^[A-Za-z0-9._-]{1,64}$ && "$mac" =~ ^[0-9a-f]{2}(-[0-9a-f]{2}){5}$ && "$at" =~ ^[0-9]+$ ]] || continue
    valid_id "$lg" || continue
    if ! grep -qxF -- "$img" <<<"$allowed"; then _nb_bind_log "$c" "$lg" "$img" "$mac" image_unknown "imagem fora das sedes do contest"; continue; fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$at" "$lg" "$img" "$mac" "$boot" >> "$W/$img.tsv"
  done < "$W/todo.tsv"
  # (find, não glob: os handlers rodam com `set -o noglob` e "$W"/*.tsv chegaria aqui literal — img='*')
  while IFS= read -r f; do
    [[ "$f" == "$W/todo.tsv" ]] && continue; img="$(basename "$f" .tsv)"
    split -l 1000 -d -a 3 "$f" "$W/chunk.$img."
    while IFS= read -r ch; do
      : > "$ch.roster"
      if (( re )); then while IFS=$'\t' read -r _ lg _ _ _; do printf '%s\t%s\n' "$lg" "$(_nb_roster_entry "$c" "$lg")"; done < "$ch" > "$ch.roster"; fi
      jq -Rcn --rawfile ros "$ch.roster" '
        ($ros | split("\n") | map(select(length > 0) | split("\t") | select(length == 2 and .[1] != "") | {key: .[0], value: (.[1] | fromjson? // null)}) | from_entries) as $R
        | {bindings: [ inputs | split("\t") | select(length == 5)
            | {mac: .[3], user_id: .[1], source: "moj-login", at: (.[0] | tonumber)} + (if .[4] == "" then {} else {boot_id: .[4]} end)
              + (if ($R[.[1]] // null) != null then {create_roster_entry: $R[.[1]]} else {} end) ]}' "$ch" > "$ch.json"
      r="$(NB_TIMEOUT=60 nb_curl "$c" PUT "/site-images/$img/bindings" "$ch.json")"; st="$(nb_status "$r")"
      if [[ "$st" == 404 || "$st" == 405 ]]; then rm -rf "$W"; return 1; fi         # serviço sem a rota de lote
      if [[ "$st" != 200 ]]; then failed=$(( failed + $(wc -l < "$ch") )); _nb_bind_log "$c" "-" "$img" "-" "http $st" "lote de $(wc -l < "$ch") vínculos recusado: $(nb_code "$r")"; continue; fi
      sent=$(( sent + $(wc -l < "$ch") ))
      nb_body "$r" > "$ch.resp"
      # resultado por item: ok → macs.tsv + log; user_not_in_roster → noroster; resto → erro com o code
      while IFS=$'\t' read -r mac ok code; do
        local line; line="$(awk -F'\t' -v m="$mac" '$4 == m { print; exit }' "$ch")"; [[ -n "$line" ]] || continue
        IFS=$'\t' read -r at lg _ _ boot <<<"$line"
        if [[ "$ok" == true ]]; then
          bound=$((bound+1)); _nb_bind_log "$c" "$lg" "$img" "$mac" ok
          { [[ -s "$d/nutella-macs.tsv" ]] && awk -F'\t' -v m="$mac" '$1 != m' "$d/nutella-macs.tsv"; printf '%s\t%s\t%s\t%s\t%s\n' "$mac" "$lg" "$img" "$boot" "$at"; } > "$d/.nutella-macs.tmp" && mv -f "$d/.nutella-macs.tmp" "$d/nutella-macs.tsv"
        elif [[ "$code" == user_not_in_roster ]]; then nor=$((nor+1)); _nb_bind_log "$c" "$lg" "$img" "$mac" noroster "time fora do roster da imagem"
        else failed=$((failed+1)); _nb_bind_log "$c" "$lg" "$img" "$mac" "http item" "${code:-?}"; fi
      done < <(jq -r '(.results // [])[] | [(.mac // ""), (.ok // false | tostring), (.code // "")] | @tsv' "$ch.resp" 2>/dev/null)
    done < <(find "$W" -maxdepth 1 -name "chunk.$img.*" ! -name '*.json' ! -name '*.resp' ! -name '*.roster' | sort)
  done < <(find "$W" -maxdepth 1 -name '*.tsv' | sort)
  rm -rf "$W"
  jq -cn --argjson s "$sent" --argjson b "$bound" --argjson f "$failed" --argjson n "$nor" '{sent:$s, bound:$b, failed:$f, noroster:$n}'
}
