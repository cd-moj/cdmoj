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
# O serviço responde 404 se o time não está no roster da imagem: fica no log como `noroster` (rode o
# `push-roster` e depois o `push-bindings`). O UA pode ser forjado — quem barra isso é o gate de UA
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

# nb_bind_put <contest> <login> <imagem> <mac> <boot> <at> <source> -> status HTTP; mantém o macs.tsv
nb_bind_put(){
  local c="$1" lg="$2" img="$3" mac="$4" boot="$5" at="$6" src="$7" d="$CONTESTSDIR/$1/var" bf r st
  bf="$(mktemp)"
  jq -cn --arg u "$lg" --arg s "$src" --argjson at "$at" --arg b "$boot" \
    '{user_id: $u, source: $s, at: $at} + (if $b == "" then {} else {boot_id: $b} end)' > "$bf"
  r="$(NB_TIMEOUT=8 nb_curl "$c" PUT "/site-images/$img/machines/$mac/binding" "$bf")"; st="$(nb_status "$r")"
  rm -f "$bf"
  if [[ "$st" == 2* ]]; then
    { [[ -s "$d/nutella-macs.tsv" ]] && awk -F'\t' -v m="$mac" '$1 != m' "$d/nutella-macs.tsv"
      printf '%s\t%s\t%s\t%s\t%s\n' "$mac" "$lg" "$img" "$boot" "$at"; } > "$d/.nutella-macs.tmp" 2>/dev/null \
      && mv -f "$d/.nutella-macs.tmp" "$d/nutella-macs.tsv"
  fi
  printf '%s' "${st:-000}"
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
    st="$(nb_bind_put "$c" "$lg" "$img" "$mac" "$boot" "$at" moj-login)"
    case "$st" in
      2*)  _nb_bind_log "$c" "$lg" "$img" "$mac" ok ;;
      404) _nb_bind_log "$c" "$lg" "$img" "$mac" noroster "time fora do roster da imagem" ;;
      000|429|5*)
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
