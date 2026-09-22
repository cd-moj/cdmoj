#!/usr/bin/env bash
#
# nutella-gen.sh <contest> [outfile] [--reaggregate]
#
# COLETOR do panorama mlinux (nutellaboot): baixa site-images/roster/machines/samples do
# serviço externo, deriva POR MÁQUINA o que aconteceu DURANTE A PROVA (editores abertos,
# memória, swap, load — só dos pontos dentro de [CONTEST_START, CONTEST_END]), agrega POR
# SEDE em somas/contagens e faz os rollups pela MESMA árvore de regions.json do
# placar/estatística (nó casa por regex contra os logins do roster — o idioma do stats-gen).
# Grava ATÔMICO em var/nutella.cache.json + progresso em var/nutella.status.json.
# Ver docs/NUTELLABOOT.md.
#
# O que este coletor sabe que o serviço não sabe — o ELO MÁQUINA↔TIME: o `binding` do
# nutellaboot vem vazio, mas o login do MOJ grava o User-Agent (var/access.log) e o
# navegador do mlinux manda `MLinux/<imagem>/<machine_id>/<boot_id>`; o `machine_id` está no
# `status.hwinfo` da máquina. É esse join (1 jq sobre o access.log) que permite editores ×
# colocação (posição via sc_place_map do placar.txt), uma máquina por time.
#
# Samples: o serviço devolve 400 pontos REAMOSTRADOS sobre o intervalo pedido — SEM
# `since/until` eles se espalham pela vida da máquina (5 dias ⇒ 45 pontos na prova). Aqui
# pedimos `since=<início−1h>&until=<fim+1h>` (~1 ponto/min). O bruto baixado fica em
# var/nutella-raw/ e `--reaggregate` refaz TUDO a partir dele sem rede (mudança de view ou de
# agregado não depende mais do buffer do serviço).
#
# PRIVACIDADE: a saída por sede tem `machines[]` (MAC, time) p/ o painel do admin/staff; o
# relatório offline os remove. Linhas por time (`_rows`) existem só DENTRO deste script —
# viram `rank_ed` (contagens por recorte) e são apagadas antes de gravar.
#
# É um "build" irmão do stats-gen/report-gen: roda standalone (CLI) ou destacado pelo
# handler /contest/nutella (action collect). Tolerante a falha (máquina sem samples entra
# sem série; imagem que falhou fica de fora e é contada em `skipped`).
set -u
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
export CONTESTSDIR

C="${1:-}"; OUT=""; REAGG=0
shift || true
for a in "$@"; do
  case "$a" in --reaggregate) REAGG=1;; *) OUT="$a";; esac
done
[[ -n "$C" ]] || { echo "uso: nutella-gen.sh <contest> [outfile] [--reaggregate]" >&2; exit 1; }
case "$C" in *[!A-Za-z0-9._@#+-]* | "" | *..* ) echo "nutella-gen: invalid contest id" >&2; exit 1;; esac
CDIR="$CONTESTSDIR/$C"
[[ -f "$CDIR/conf" ]] || { echo "nutella-gen: sem conf em $CDIR" >&2; exit 1; }
[[ -n "$OUT" ]] || OUT="$CDIR/var/nutella.cache.json"
STF="$CDIR/var/nutella.status.json"
RAWD="$CDIR/var/nutella-raw"
mkdir -p "$CDIR/var" 2>/dev/null

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIBDIR="$HERE/../api/v1/lib"
source "$_LIBDIR/users.sh"
source "$HERE/score-common.sh"      # sc_place_map: posição no placar geral (a MESMA do relatório)
# standalone: sem lib/common.sh — conf_value mínima se não houver (mesma semântica)
if ! declare -F conf_value >/dev/null 2>&1; then
  conf_value() {
    local f="$CONTESTSDIR/$1/conf" k="$2=" line v
    [[ -r "$f" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" == "$k"* ]] || continue
      v="${line#"$k"}"; v="${v//\'/}"; v="${v//\"/}"; printf '%s' "$v"; return 0
    done < "$f"
    return 0
  }
fi
source "$_LIBDIR/nutella.sh"
mapfile -t CFGIDS < <(nb_images "$C")    # site-images listadas à mão (conf NUTELLABOOT_IMAGES)
if (( ! REAGG )); then
  nb_configured "$C" || { echo "nutella-gen: integração não configurada (sem chave)" >&2; exit 1; }
else
  [[ -d "$RAWD/samples" && -s "$RAWD/images.json" ]] \
    || { echo "nutella-gen: sem bruto em $RAWD p/ --reaggregate (colete primeiro)" >&2; exit 1; }
fi

# uma coleta por vez (a segunda desiste — o status diz que já está rodando)
exec 9>"$CDIR/var/.nutella.lock"
flock -n 9 || { echo "nutella-gen: coleta já em andamento" >&2; exit 0; }

W="$(mktemp -d)" || exit 1
OK=0
finish(){
  local err="${1:-}"
  if (( OK )); then
    jq -cn --argjson t "$EPOCHSECONDS" '{running:false, ok:true, finished_at:$t}' > "$STF" 2>/dev/null
  else
    jq -cn --argjson t "$EPOCHSECONDS" --arg e "${err:-falhou}" \
      '{running:false, ok:false, error:$e, finished_at:$t}' > "$STF" 2>/dev/null
  fi
  rm -rf "$W"
}
trap 'finish "interrompida"' EXIT
prog(){ # <fase> [feitas] [total]
  jq -cn --arg ph "$1" --argjson d "${2:-0}" --argjson t "${3:-0}" --argjson u "$EPOCHSECONDS" \
    '{running:true, phase:$ph, done:$d, total:$t, updated_at:$u}' > "$STF" 2>/dev/null
}

# --- janela: [início−1h, fim+1h] p/ baixar; a PROVA [cs, ce] p/ derivar -----------------
START="$(conf_value "$C" CONTEST_START)"; [[ "$START" =~ ^[0-9]+$ ]] || START=0
END="$(conf_value "$C" CONTEST_END)";     [[ "$END" =~ ^[0-9]+$ ]] || END=0
WSTART=$(( START > 3600 ? START - 3600 : 0 ))
WEND=$(( END + 3600 )); (( WEND > EPOCHSECONDS || END == 0 )) && WEND="$EPOCHSECONDS"
CS="$START"; CE="$END"
(( CS == 0 )) && CS="$WSTART"
(( CE == 0 || CE > EPOCHSECONDS )) && CE="$EPOCHSECONDS"

if (( REAGG )); then
  # --- 1'. bruto → W (sem rede); a janela é a do bruto, não a de agora ------------------
  prog "reagregando do bruto"
  cp -r "$RAWD/." "$W/" 2>/dev/null || { finish "falha ao ler o bruto"; trap - EXIT; exit 1; }
  if [[ -s "$W/meta.json" ]]; then
    _ws="$(jq -r '.ws // empty' "$W/meta.json" 2>/dev/null)"; _we="$(jq -r '.we // empty' "$W/meta.json" 2>/dev/null)"
    [[ "$_ws" =~ ^[0-9]+$ ]] && WSTART="$_ws"; [[ "$_we" =~ ^[0-9]+$ ]] && WEND="$_we"
    (( CE > WEND )) && CE="$WEND"
  fi
else
  BASE="$(nb_url "$C")"
  KEY="$(nb_key "$C")"      # a regra da chave (nb3a_ admin | nb3s_ serviço) mora na lib, num lugar só
  # header via arquivo de config do curl (600 dentro do W 700) — chave nunca em argv. O arquivo
  # (e não o `-K <(…)` do nb_curl) é o que deixa o `xargs -P … sh -c` buscar em paralelo.
  printf 'header = "Authorization: Bearer %s"\n' "$KEY" > "$W/cfg"; chmod 600 "$W/cfg"
  nbget(){ curl -s -m 30 -K "$W/cfg" "$BASE/api/v1/$1"; }   # caminho SEM segredo no argv

  # --- 1. imagens ------------------------------------------------------------------------
  # `/site-images` lista as sedes: com chave ADMIN todas as do serviço, com chave de SERVIÇO (desde
  # 21/09/2026) só as do glob dela. Serviço ANTIGO dava 401 à chave de serviço — aí as sedes vêm de
  # NUTELLABOOT_IMAGES. Com as duas coisas, a lista RESTRINGE a coleta (o serviço hospeda sedes de outros
  # eventos; a interseção com os logins já as descartava, mas cada uma custava 2 requests). Imagem
  # listada à mão que o serviço NÃO devolve (fora do glob da chave, ou não existe) vai p/ `skipped`.
  prog "listando sedes"
  nbget site-images > "$W/images.json" 2>/dev/null
  if jq -e '.images | type == "array"' "$W/images.json" >/dev/null 2>&1; then
    if (( ${#CFGIDS[@]} )); then
      printf '%s\n' "${CFGIDS[@]}" | jq -Rn '[inputs | select(length > 0)]' > "$W/cfgids.json"
      jq -r --slurpfile k "$W/cfgids.json" '$k[0] - [.images[].id] | .[]' "$W/images.json" 2>/dev/null >> "$W/skipped.txt"
      jq -c --slurpfile k "$W/cfgids.json" '.images |= map(select(.id as $i | $k[0] | index($i)))' \
        "$W/images.json" > "$W/images.f.json" 2>/dev/null && mv -f "$W/images.f.json" "$W/images.json"
    elif [[ "$(nb_key_kind "$C")" == service ]]; then
      # chave de SERVIÇO é criada POR EVENTO, com o glob das imagens dele: o que ela lista é a lista do
      # evento — vale como se estivesse em NUTELLABOOT_IMAGES (a sede entra mesmo sem roster/login ainda)
      mapfile -t CFGIDS < <(jq -r '.images[].id' "$W/images.json" 2>/dev/null)
    fi
  elif (( ${#CFGIDS[@]} )); then
    printf '%s\n' "${CFGIDS[@]}" | jq -Rn '{images: [inputs | select(length > 0) | {id: ., fullname: .}]}' > "$W/images.json"
  else
    finish "nutellaboot inacessível, chave inválida ou — com chave de serviço — faltam as site-images do evento"
    trap - EXIT; exit 1
  fi
  mapfile -t IDS < <(jq -r '.images[].id' "$W/images.json")
  prog "baixando roster+máquinas" 0 "${#IDS[@]}"
  # --- 2. roster + machines por imagem (paralelo; id validado — vira nome de arquivo) ----
  printf '%s\n' "${IDS[@]}" | grep -E '^[A-Za-z0-9._-]+$' | \
    xargs -P8 -n1 sh -c '
      curl -s -m 30 -K "$0/cfg" "$1/api/v1/site-images/$2/roster"   > "$0/roster.$2.json" 2>/dev/null
      curl -s -m 60 -K "$0/cfg" "$1/api/v1/site-images/$2/machines" > "$0/machines.$2.json" 2>/dev/null
    ' "$W" "$BASE"
fi
find "$CDIR/users" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort > "$W/logins.txt"
# login -> IMAGEM de onde o time logou (o UA do mlinux diz: `MLinux/<imagem>/…`; último login vence,
# conta de papel fora). É a 2ª fonte de "quem é desta sede", p/ quando o ROSTER do serviço está VAZIO
# — em 21/09/2026 estava vazio em TODAS as imagens, inclusive na do evento da semana, e a regra
# antiga (só roster ∩ logins) terminava em "nenhuma sede casa com os times".
: > "$W/uaimg.tsv"
if [[ -s "$CDIR/var/access.log" ]]; then
  jq -Rrn --argjson b "$WEND" '
    [ inputs | split("\t") | select(length >= 4)
      | (.[0] | tonumber? // 0) as $t | select($t <= $b)
      | .[1] as $lg
      | select(($lg | test("\\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$")) | not)
      | ((.[3] | try @base64d catch "") | capture("MLinux/(?<img>[A-Za-z0-9._-]+)/[0-9a-f]{32}/")? // null) as $m
      | select($m != null) | {t: $t, lg: $lg, img: $m.img} ]
    | sort_by(.t) | reduce .[] as $e ({}; .[$e.lg] = $e.img)
    | to_entries[] | "\(.key)\t\(.value)"' "$CDIR/var/access.log" > "$W/uaimg.tsv" 2>/dev/null || : > "$W/uaimg.tsv"
fi
mapfile -t IDS < <(jq -r '.images[].id' "$W/images.json")
# Sede cujo `machines` NÃO veio (rede, 401/403 do escopo da chave, URL errada) sai da coleta — e, se
# não sobrar nenhuma, a coleta FALHA dizendo isso. Sem esta guarda, uma imagem listada à mão com o
# serviço fora do ar rendia um cache `ok:true` todo zerado (o filtro antigo "roster ∩ logins"
# escondia o caso atrás de "nenhuma sede casa"). Vale também p/ o bruto do --reaggregate.
# A sede que falhou SOZINHA vai p/ `skipped` do cache, e o painel avisa — sumir calada não pode.
_okids=(); NBAD=0
for id in "${IDS[@]}"; do
  if jq -e '.machines | type == "array"' "$W/machines.$id.json" >/dev/null 2>&1; then _okids+=("$id"); else NBAD=$((NBAD + 1)); echo "$id" >> "$W/skipped.txt"; fi
done
if (( ${#IDS[@]} && ! ${#_okids[@]} )); then
  finish "o nutellaboot não devolveu as máquinas de nenhuma sede (URL, chave ou escopo da chave)"; trap - EXIT; exit 1
fi
IDS=("${_okids[@]}")
NIMG="${#IDS[@]}"

# --- 3. relevância + nome da sede --------------------------------------------------------
# TIMES da imagem = (roster ∩ logins do contest) ∪ (logins FORA DE TODO roster que entraram com o UA
# DESTA imagem). O roster MANDA: quem está no roster de uma sede é dela, ainda que tenha logado de
# uma máquina com a imagem de outra (senão o time contaria em duas sedes).
# Imagem RELEVANTE = tem time OU foi listada à mão em NUTELLABOOT_IMAGES (a de teste e as de
# outros eventos caem fora). Nome da sede = .team.region (store) do 1º time que tiver; fallback =
# fullname da imagem. País = bandeira do 1º time que tiver; fallback = 2 letras do id (26brprcu → br).
: > "$W/kept.tsv"    # id \t sede \t país \t fullname
for id in "${IDS[@]}"; do
  [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || continue
  jq -r '.roster[]?.user_id // empty' "$W/roster.$id.json" 2>/dev/null
done | sort -u > "$W/inroster.txt"
for id in "${IDS[@]}"; do
  [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || continue
  { jq -r '.roster[]?.user_id // empty' "$W/roster.$id.json" 2>/dev/null
    awk -F'\t' -v i="$id" '$2 == i { print $1 }' "$W/uaimg.tsv" | sort | comm -23 - "$W/inroster.txt"
  } | sort -u > "$W/rteams.$id.txt"
  comm -12 "$W/logins.txt" "$W/rteams.$id.txt" > "$W/teams.$id.txt"
  _listed=0; for _c in "${CFGIDS[@]}"; do [[ "$_c" == "$id" ]] && _listed=1; done
  [[ -s "$W/teams.$id.txt" || $_listed -eq 1 ]] || continue
  sede=""
  while IFS= read -r lg; do
    sede="$(jq -r '.team.region // empty' "$(account_file "$C" "$lg")" 2>/dev/null)"
    [[ -n "$sede" ]] && break
  done < "$W/teams.$id.txt"
  fullname="$(jq -r --arg i "$id" 'first(.images[] | select(.id == $i) | .fullname) // $i' "$W/images.json")"
  [[ -n "$sede" ]] || sede="$fullname"
  pais=""
  while IFS= read -r lg; do
    pais="$(jq -r '(.team.flag // "") | ascii_downcase | split("-")[0] // ""' "$(account_file "$C" "$lg")" 2>/dev/null)"
    [[ "$pais" =~ ^[a-z]{2}$ ]] && break; pais=""
  done < "$W/teams.$id.txt"
  [[ -n "$pais" ]] || pais="$(printf '%s' "$id" | sed -E 's/^[0-9]+//; s/^(..).*$/\1/')"
  printf '%s\t%s\t%s\t%s\n' "$id" "$sede" "$pais" "$fullname" >> "$W/kept.tsv"
done
NKEPT="$(wc -l < "$W/kept.tsv" | tr -d '[:space:]')"
(( NKEPT > 0 )) || { finish "nenhuma sede do nutellaboot casa com os times deste contest"; trap - EXIT; exit 1; }

# --- 4. samples: UM request POR SEDE (lote NDJSON) ---------------------------------------
# `GET /site-images/{i}/samples?since&until&limit&active_since` devolve uma linha por máquina, no
# mesmo formato da rota individual: `{mac, points, native_points, resampled, interval_s, since,
# until, truncated}`. Era um request POR MÁQUINA (~1.700 numa coleta da Maratona, 1 min 16 s); o
# lote de uma sede de 29 máquinas volta em 0,15 s. `limit=5000` tira a reamostragem da janela da
# prova (o agente manda ~1 ponto/50 s ⇒ ~500 pontos em 7 h), então `resampled:false` e a cadência é
# a do agente (`interval_s`). `active_since` poupa as máquinas que não apareceram na janela.
# Serviço antigo (404 no lote) cai no caminho por máquina — e o bruto por máquina (o da LATAM 2026,
# `samples/<id>.<mac>.json`) continua sendo lido: o `--reaggregate` dele tem de dar o mesmo resultado.
mkdir -p "$W/samples"
if (( ! REAGG )); then
  : > "$W/nolote.txt"
  prog "baixando séries das máquinas (lote por sede)" 0 "$NKEPT"
  # posicionais: $0=W $1=BASE $2=since $3=until, e o xargs acrescenta $4=imagem
  cut -f1 "$W/kept.tsv" | grep -E '^[A-Za-z0-9._-]+$' | xargs -P8 -n1 sh -c '
    code=$(curl -s --compressed -m 180 -K "$0/cfg" -o "$0/samples/$4.ndjson" -w "%{http_code}" \
      "$1/api/v1/site-images/$4/samples?since=$2&until=$3&limit=5000&active_since=$2" 2>/dev/null)
    [ "$code" = 200 ] || { rm -f "$0/samples/$4.ndjson"; echo "$4" >> "$0/nolote.txt"; }
  ' "$W" "$BASE" "$WSTART" "$WEND" 2>/dev/null
  if [[ -s "$W/nolote.txt" ]]; then
    : > "$W/maclist.txt"
    while IFS= read -r id; do
      jq -r --argjson ws "$WSTART" \
        '.machines[]? | select((.last_seen // 0) >= $ws) | .mac' "$W/machines.$id.json" 2>/dev/null \
        | grep -E '^[A-Za-z0-9:-]+$' | sed "s/^/$id /"
    done < "$W/nolote.txt" >> "$W/maclist.txt"
    NSAMP="$(wc -l < "$W/maclist.txt" | tr -d '[:space:]')"
    prog "baixando séries (por máquina — serviço sem a rota de lote)" 0 "$NSAMP"
    # posicionais: $0=W $1=BASE $2=since $3=until, e o xargs acrescenta $4=imagem $5=mac
    xargs -P16 -n2 sh -c '
      curl -s -m 20 -K "$0/cfg" "$1/api/v1/site-images/$4/machines/$5/samples?since=$2&until=$3&limit=5000" \
        > "$0/samples/$4.$5.json" 2>/dev/null || true
    ' "$W" "$BASE" "$WSTART" "$WEND" < "$W/maclist.txt" 2>/dev/null
  fi
fi
prog "agregando" 0 "$NKEPT"

# --- 4b. ELO máquina↔time: access.log (login grava o UA em base64) -----------------------
# UA do mlinux: "Mozilla/5.0 (MLinux/<imagem>/<machine_id>/<boot_id>) …". Um jq p/ o arquivo
# inteiro (@base64d), contas de PAPEL fora, ÚLTIMO login vence. TODO login até o fim da
# janela conta (sessão do MOJ não expira: quem logou às 10h e ficou logado é dono da máquina
# na prova). TRÊS chaves, da mais forte p/ a mais fraca:
#   `a` = MAC — o agente novo (NutellaBoot 3) põe o MAC no FIM do UA (`…/<boot_id>/<mac>`) e ele casa
#         EXATO com o `.mac` da máquina no serviço: sobrevive a reboot e a machine-id clonado;
#   `k` = machine_id/boot_id (agente antigo — em sedes com imagem CLONADA dezenas de máquinas têm o
#         MESMO /etc/machine-id, e só o boot_id as separa; um reboot depois do login perde o elo);
#   `m` = machine_id sozinho (fallback SÓ quando o id é único na frota; ver dupmids).
# Onde o UA não disse nada, vale o `binding` do PRÓPRIO serviço (o MOJ o publica no login — lib/
# nutella-bind.sh — e o staff da sede pode vincular à mão), desde que o time seja da sede.
printf '{"a":{},"k":{},"m":{}}' > "$W/link.json"
if [[ -s "$CDIR/var/access.log" ]]; then
  jq -Rn --argjson b "$WEND" '
    [ inputs | split("\t") | select(length >= 4)
      | (.[0] | tonumber? // 0) as $t
      | select($t <= $b)
      | .[1] as $lg
      | select(($lg | test("\\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$")) | not)
      | ((.[3] | try @base64d catch "") | capture("MLinux/[^/]+/(?<mid>[0-9a-f]{32})/(?<boot>[0-9]+)(/(?<mac>[0-9a-f]{2}([-:][0-9a-f]{2}){5}))?")? // null) as $m
      | select($m != null)
      | {t: $t, lg: $lg, mid: $m.mid, boot: $m.boot, mac: (($m.mac // "") | gsub(":"; "-"))} ]
    | sort_by(.t)
    | { a: (reduce (.[] | select(.mac != "")) as $e ({}; .[$e.mac] = $e.lg)),
        k: (reduce .[] as $e ({}; .[$e.mid + "/" + $e.boot] = $e.lg)),
        m: (reduce .[] as $e ({}; .[$e.mid] = $e.lg)) }' "$CDIR/var/access.log" > "$W/link.json" 2>/dev/null \
    || printf '{"a":{},"k":{},"m":{}}' > "$W/link.json"
  jq -e '.k | type == "object"' "$W/link.json" >/dev/null 2>&1 || printf '{"a":{},"k":{},"m":{}}' > "$W/link.json"
fi
# machine_ids DUPLICADOS na frota mantida (imagem clonada): com eles só o par mid/boot vale
: > "$W/mlist.txt"; while IFS=$'\t' read -r id _r; do printf '%s\n' "$W/machines.$id.json"; done < "$W/kept.tsv" > "$W/mlist.txt"
xargs -a "$W/mlist.txt" jq -c '.machines[]? | .status.hwinfo.machine_id // empty' 2>/dev/null \
  | jq -sc 'group_by(.) | map(select(length > 1) | {key: .[0], value: true}) | from_entries' > "$W/dupmids.json" 2>/dev/null
jq -e 'type == "object"' "$W/dupmids.json" >/dev/null 2>&1 || printf '{}' > "$W/dupmids.json"
# times PRESENTES = logaram alguma vez até o fim da janela (qualquer navegador) — é o
# denominador honesto da cobertura do elo; quem nunca logou é ausente, não "sem vínculo"
printf '{}' > "$W/present.json"
if [[ -s "$CDIR/var/access.log" ]]; then
  jq -Rn --argjson b "$WEND" '
    [ inputs | split("\t") | select(length >= 2) | select((.[0] | tonumber? // 0) <= $b) | .[1] ]
    | unique | map({key: ., value: true}) | from_entries' "$CDIR/var/access.log" > "$W/present.json" 2>/dev/null \
    || printf '{}' > "$W/present.json"
  jq -e 'type == "object"' "$W/present.json" >/dev/null 2>&1 || printf '{}' > "$W/present.json"
fi
# posição no placar geral (login → posição); convidado (guest) não tem. Prefere o placar
# COMPLETO (nunca o congelado) e, com coortes, a visão `all` (mesma escolha do relatório).
printf '{}' > "$W/place.json"
PLF=""
for _f in "$CDIR/var/placar-view-all-full.txt" "$CDIR/var/placar-full.txt" "$CDIR/var/placar.txt"; do
  [[ -s "$_f" ]] && { PLF="$_f"; break; }
done
if [[ -n "$PLF" ]]; then
  sc_place_map "$PLF" 2>/dev/null \
    | jq -Rn '[ inputs | split("\t") | select(length == 2) | {key: .[0], value: (.[1] | tonumber? // null)} | select(.value != null) ] | from_entries' \
    > "$W/place.json" 2>/dev/null || printf '{}' > "$W/place.json"
  [[ -s "$W/place.json" ]] || printf '{}' > "$W/place.json"
fi
# modo da população "máquina de time": vinculadas (ua) quando o elo cobre ≥ 50 % dos times
# das sedes mantidas; senão o proxy do artigo (`used` = algum editor ≥ 60 min na prova).
while IFS=$'\t' read -r id _r; do cat "$W/teams.$id.txt"; done < "$W/kept.tsv" | sort -u > "$W/allteams.txt"
NTEAMS="$(wc -l < "$W/allteams.txt" | tr -d '[:space:]')"; NTEAMS="${NTEAMS:-0}"
# times VINCULADOS = logins do elo que são times das sedes mantidas (o access.log tem o contest
# inteiro; o elo de uma sede sem nutellaboot não conta); PRESENTES = idem p/ quem logou
# (o `binding` do serviço entra na conta: é elo também — o filtro por sede é o do agregador)
NLINK="$( { jq -r '[ (.a // {})[], .k[], .m[] ] | unique | .[]' "$W/link.json" 2>/dev/null
            xargs -a "$W/mlist.txt" jq -r '.machines[]? | .binding | objects | .user_id // empty' 2>/dev/null
          } | sort -u | comm -12 - "$W/allteams.txt" | wc -l | tr -d '[:space:]')"
NLINK="${NLINK//[^0-9]/}"; NLINK="${NLINK:-0}"
NPRES="$(jq -r 'keys[]' "$W/present.json" 2>/dev/null | sort -u | comm -12 - "$W/allteams.txt" | wc -l | tr -d '[:space:]')"
NPRES="${NPRES//[^0-9]/}"; NPRES="${NPRES:-0}"
MODE=proxy; (( NPRES > 0 && NLINK * 2 >= NPRES )) && MODE=ua

# --- 5. agregado POR IMAGEM (um jq por sede: máquinas + séries mergeáveis) ---------------
# Tudo que precisa virar média em rollup é guardado como SOMA+N (merge exato depois).
# Por máquina, dos pontos DENTRO DA PROVA: minutos por editor (cadência mediana × pontos),
# editores "usados" (≥ 60 min), perfil puro (um grupo ≥ 60 % dos pontos; leve exige pesado
# ≤ 10 %), faixa de RAM, memória/swap/load. jq 1.7: valor de objeto SEMPRE entre parênteses.
AGG_JQ='
  def band(m): (if m < 6144 then "<8" elif m < 11264 then "8" elif m < 13312 then "12"
                elif m < 20480 then "16" elif m < 28672 then "24" elif m < 40960 then "32" else ">32" end);
  def grp(e): (if e == "code" then "vscode"
               elif (e == "idea" or e == "clion" or e == "pycharm") then "jetbrains"
               elif e == "codeblocks" then "codeblocks"
               elif (e == "vim" or e == "gedit" or e == "geany" or e == "emacs") then "light"
               else "other" end);
  def pband(m): (if m < 10240 then "8" elif m < 20480 then "16" elif m < 40960 then "32" else ">32" end);
  def cnt(f): (reduce f as $k ({}; .[$k] = ((.[$k] // 0) + 1)));
  def med($a): (($a | sort) as $s | ($s | length) as $n | if $n == 0 then null else $s[($n / 2) | floor] end);
  # derivação de UMA máquina a partir dos seus pontos na prova
  # $iv = `interval_s` do serviço, só quando ele disse `resampled:false` (pontos NATIVOS): aí a
  # cadência é a do agente, medida por quem tem a série inteira. Reamostrado (ou bruto antigo,
  # sem o campo) = a mediana dos deltas do que veio, como sempre.
  def derive($p; $cs; $ce; $iv):
    ($p | length) as $n
    | (if ($iv | type) == "number" and $iv >= 20 and $iv <= 600 then $iv
       elif $n > 1 then ([ range(1; $n) as $i | ($p[$i].t - $p[$i - 1].t) ] | med(.)) else 60 end) as $cad0
    | (if $cad0 == null or $cad0 < 20 then 60 elif $cad0 > 600 then 600 else $cad0 end) as $cad
    | (cnt($p[] | (.ed // [])[])) as $edp
    | ($edp | with_entries(.value = ((.value * $cad / 60) | round))) as $edmin
    | ([ $edmin | to_entries[] | select(.value >= 60) | .key ] | sort) as $eds
    | (cnt($p[] | [ (.ed // [])[] | grp(.) ] | unique | .[])) as $gp
    | ([ $gp | to_entries[] | select(.value >= $n * 0.6) | .key ] ) as $cands
    | ((($gp.jetbrains // 0) + ($gp.codeblocks // 0)) / (if $n > 0 then $n else 1 end)) as $heavy
    | (if $n == 0 or ($eds | length) == 0 then "none"
       elif ($cands | length) == 1 then (if $cands[0] == "light" and $heavy > 0.1 then "mixed" else $cands[0] end)
       elif ($cands | length) == 0 then "mixed" else "mixed" end) as $prof
    | { pts: $n, cad: $cad, ed_min: $edmin, eds: $eds,
        groups: ([ $eds[] | grp(.) ] | unique),
        prof: $prof,
        used: (([ $edmin[] ] | max // 0) >= 10),
        edmax: ([ $edmin[] ] | max // 0),
        mem_sum: ([ $p[] | (.mem // 0) ] | add // 0),
        sw_sum:  ([ $p[] | (.sw // 0) ] | add // 0),
        sw_max:  ([ $p[] | (.sw // 0) ] | max // 0),
        ld_sum:  ([ $p[] | (.ld // 0) ] | add // 0),
        ld_max:  ([ $p[] | (.ld // 0) ] | max // 0),
        mem0: ([ $p[] | select(.t < $cs + 1800) | (.mem // 0) ]),
        mem4: ([ $p[] | select(.t >= $ce - 3600) | (.mem // 0) ]),
        # --- AGENTE NOVO (NutellaBoot 3): tudo OPCIONAL por ponto; máquina com agente antigo sai 0/null.
        # PSI (some avg10 de /proc/pressure) é a medida DIRETA de pressão — swap era só a ponta visível;
        # `oom` é contador desde o boot (reboot zera): soma só os incrementos; `idle` = s de sessão ociosa;
        # `skew` = relógio do servidor − relógio da máquina (série deslocada no tempo da prova).
        psi_mem_sum: ([ $p[] | .psi_mem // empty ] | add // 0),
        psi_cpu_sum: ([ $p[] | .psi_cpu // empty ] | add // 0),
        psi_io_sum:  ([ $p[] | .psi_io // empty ] | add // 0),
        psi_n:   ([ $p[] | select(.psi_mem != null) ] | length),
        psi_max: ([ $p[] | .psi_mem // empty ] | max // 0),
        oom: (([ $p[] | .oom // empty ]) as $o
              | reduce range(1; ($o | length)) as $i (0; . + ([ ($o[$i] - $o[$i - 1]), 0 ] | max))),
        idle_pts: ([ $p[] | select(.idle != null) ] | length),
        idle_hi:  ([ $p[] | select((.idle // 0) > 300) ] | length),
        skew: (med([ $p[] | .skew // empty ])),
        bins: ([ $p[] | { b: (((.t - $cs) / 1800) | floor), mem: (.mem // 0), sw: (.sw // 0), psi: (.psi_mem // null) } ]
               | group_by(.b) | map({ t: (.[0].b * 1800), mem_sum: ([ .[].mem ] | add), mem_n: length,
                                      sw_sum: ([ .[].sw ] | add), sw_n: length,
                                      psi_sum: ([ .[].psi // empty ] | add // 0),
                                      psi_n: ([ .[] | select(.psi != null) ] | length) })) };
  def sum(f): ([ f ] | add // 0);
  ($spf[0]) as $sp
  | ($tf[0]) as $teams
  | ($lk[0]) as $link
  | ($dm[0]) as $dups
  | ($pr[0]) as $present
  | ($pl[0]) as $place
  | ($m[0].machines // []) as $ms
  | [ $ms[] | select((.last_seen // 0) >= $ws) ] as $seen
  | ($sp | map(select((.points // []) | length > 0))) as $series_in
  | (reduce $series_in[] as $s ({}; .[$s.mac] = [ $s.points[] | select(.t >= $cs and .t <= $ce) ])) as $cpts
  | (reduce $series_in[] as $s ({}; .[$s.mac] = (if $s.resampled == false then ($s.interval_s // null) else null end))) as $ivs
  # ---- por máquina + dedupe de time (um time = a máquina com mais pontos na prova) -------
  | ([ $seen[] | . as $x
       | ($x.status.hwinfo.machine_id // "") as $mid
       | (($x.status.hwinfo.boot_id // "") | tostring) as $boot
       | (($x.binding | objects | .user_id) // null) as $bound
       | ((($link.a // {})[(($x.mac // "") | ascii_downcase | gsub(":"; "-"))])
          // (if $mid == "" then null
              else ($link.k[$mid + "/" + $boot]
                    // (if ($dups[$mid] // false) == true then null else ($link.m[$mid] // null) end)) end)
          // (if $bound != null and (($teams | index($bound)) != null) then $bound else null end)) as $team
       | derive(($cpts[$x.mac] // []); $cs; $ce; ($ivs[$x.mac] // null))
         + { mac: $x.mac, online: ($x.online // false),
             model: (((($x.status.hwinfo.product_vendor // "") + " " + ($x.status.hwinfo.product_name // ""))
                      | gsub("^ +| +$"; "")) as $mo | if $mo == "" then null else $mo end),
             # agente novo: `status.agent_version` (camada 2026.09.2) — ou, no agente da 1ª leva, a presença de t_agent
             agent_new: ((($x.status.agent_version // null) != null) or (($x.status.t_agent // null) != null)),
             agent_version: ($x.status.agent_version // null),
             last_boot: ($x.last_boot // $x.status.hwinfo.last_boot // 0),
             processor: ($x.status.hwinfo.processor // "?"),
             cores: ($x.status.hwinfo.cores // 0), mem_mb: ($x.status.hwinfo.memtotal_mb // 0),
             band: (band($x.status.hwinfo.memtotal_mb // 0)),
             editors_time: ($x.status.operations.editors_time // {}),
             fw: ($x.status.operations.firewall // null), sl: ($x.status.operations.screen_lock // null),
             home_pct: ($x.status.sysdisk.home_pct // null), binding: $x.binding,
             team: $team } ]
     | group_by(.team)
     | map(if .[0].team == null then (.[] | . + { chosen: false })
           else (sort_by(-.pts, .mac) | to_entries[] | (.value + { chosen: (.key == 0) })) end)
    ) as $mx
  | ($mx | map(. + { rank: (if .chosen then ($place[.team] // null) else null end) })) as $mx
  # população "máquina de time": no modo ua = a escolhida de cada time + as usadas sem elo
  # (time em navegador não-mlinux ocupou a máquina); no modo proxy = as usadas na prova
  | ([ $mx[] | select(if $mode == "ua" then (.chosen or (.used and .team == null)) else .used end) ]) as $tm
  | {
      id: $id, name: $sede, country: $pais, fullname: $full,
      teams: $teams,
      machines_total: ($ms | length),
      seen: ($seen | length),
      firewall_off: ([ $seen[] | select((.status.operations.firewall // true) == false) ] | length),
      screen_lock: ([ $seen[] | select((.status.operations.screen_lock // false) == true) ] | length),
      alerts: ([ $ms[] | (.alerts // []) | length ] | add // 0),
      alert_kinds: (cnt($ms[] | (.alerts // [])[] | (.kind // "?"))),   # identity.duplicate, usb.storage…
      # SAÚDE na prova — contadores ADITIVOS (o rollup é um madd). `agent_new` diz de quantas máquinas
      # vem o resto: sem isso "0 OOM" seria indistinguível de "ninguém mede OOM".
      health: { agent_new: ([ $mx[] | select(.agent_new) ] | length),
                psi_mem_sum: (sum($tm[].psi_mem_sum)), psi_cpu_sum: (sum($tm[].psi_cpu_sum)),
                psi_io_sum: (sum($tm[].psi_io_sum)), psi_n: (sum($tm[].psi_n)),
                oom_machines: ([ $mx[] | select(.oom > 0) ] | length), oom_kills: (sum($mx[].oom)),
                idle_pts: (sum($tm[].idle_pts)), idle_hi: (sum($tm[].idle_hi)),
                skew_n: ([ $mx[] | select(.skew != null) ] | length),
                skew_bad: ([ $mx[] | select(.skew != null) | select((.skew > 120) or (.skew < -120)) ] | length),
                reboots: ([ $mx[] | select(.last_boot > $cs and .last_boot <= $ce) ] | length) },
      psi_mem_max: ([ $tm[].psi_max ] | max // 0),
      model_tm: (cnt($tm[] | .model // empty)),
      disk_high: ([ $seen[] | select((.status.sysdisk.home_pct // 0) >= 90) ] | length),
      bound: ([ $ms[] | select(.binding != null) ] | length),
      bindings: ([ $ms[] | select(.binding != null) | {mac, team: (.binding | if type == "object" then (.user_id // .team // tostring) else tostring end)} ]),
      pop: { seen: ($seen | length), used: ([ $mx[] | select(.used) ] | length),
             linked: ([ $mx[] | select(.team != null) ] | length),
             chosen: ([ $mx[] | select(.chosen) ] | length),
             ranked: ([ $mx[] | select(.rank != null) ] | length),
             tm: ($tm | length), teams: ($teams | length),
             present: ([ $teams[] | select(($present[.] // false) == true) ] | length) },
      ram_total_mb: (sum($seen[].status.hwinfo.memtotal_mb // 0)),
      cores_total: (sum($seen[].status.hwinfo.cores // 0)),
      ram_sum_tm: (sum($tm[].mem_mb)), ram_n_tm: ($tm | length),
      cpu: (cnt($seen[] | .status.hwinfo.processor // "?")),
      cpu_tm: (cnt($tm[] | .processor)),
      ram_bands_all: (cnt($seen[] | band(.status.hwinfo.memtotal_mb // 0))),
      ram_bands: (cnt($tm[] | .band)),
      editors: (reduce ($seen[] | .status.operations.editors_time // {} | to_entries[] | select(.key != "total")) as $e ({}; .[$e.key] = ((.[$e.key] // 0) + ($e.value // 0)))),
      editors_total_min: (sum($seen[] | .status.operations.editors_time.total // 0)),
      editors_machines: (cnt($seen[] | (.status.operations.editors_time // {} | keys[] | select(. != "total")))),
      ed_min: (reduce ($tm[] | .ed_min | to_entries[]) as $e ({}; .[$e.key] = ((.[$e.key] // 0) + $e.value))),
      ed_min_total: (sum($tm[] | .ed_min | to_entries[] | .value)),
      ed_adopt: (cnt($tm[] | .eds[])),
      ed_groups: (cnt($tm[] | .groups[])),
      ed_count: (cnt($tm[] | (.eds | length) | if . >= 3 then "3+" else tostring end)),
      profiles: (cnt($tm[] | .prof)),
      ld_sum: (sum($tm[].ld_sum)), ld_n: (sum($tm[].pts)), ld_max: ([ $tm[].ld_max ] | max // 0),
      mem_sum: (sum($tm[].mem_sum)), mem_n: (sum($tm[].pts)),
      sw_sum: (sum($tm[].sw_sum)), sw_n: (sum($tm[].pts)),
      pressure: (reduce ($tm[] | select(.pts > 0)) as $x ({};
        ((pband($x.mem_mb)) + "|" + ($x.prof)) as $k
        | .[$k] = { n: (((.[$k] // {}).n // 0) + 1),
                    mem_sum: (((.[$k] // {}).mem_sum // 0) + $x.mem_sum), mem_n: (((.[$k] // {}).mem_n // 0) + $x.pts),
                    sw_sum: (((.[$k] // {}).sw_sum // 0) + $x.sw_sum), sw_n: (((.[$k] // {}).sw_n // 0) + $x.pts),
                    sw_max: ([ ((.[$k] // {}).sw_max // 0), $x.sw_max ] | max),
                    psi_sum: (((.[$k] // {}).psi_sum // 0) + $x.psi_mem_sum), psi_n: (((.[$k] // {}).psi_n // 0) + $x.psi_n),
                    psi_max: ([ ((.[$k] // {}).psi_max // 0), $x.psi_max ] | max),
                    mem0_sum: (((.[$k] // {}).mem0_sum // 0) + ($x.mem0 | add // 0)), mem0_n: (((.[$k] // {}).mem0_n // 0) + ($x.mem0 | length)),
                    mem4_sum: (((.[$k] // {}).mem4_sum // 0) + ($x.mem4 | add // 0)), mem4_n: (((.[$k] // {}).mem4_n // 0) + ($x.mem4 | length)),
                    series: ((((.[$k] // {}).series // []) + $x.bins) | group_by(.t)
                             | map({ t: .[0].t, mem_sum: ([ .[].mem_sum ] | add), mem_n: ([ .[].mem_n ] | add),
                                     sw_sum: ([ .[].sw_sum ] | add), sw_n: ([ .[].sw_n ] | add),
                                     psi_sum: ([ .[].psi_sum // 0 ] | add), psi_n: ([ .[].psi_n // 0 ] | add) })) })),
      _rows: ([ $mx[] | select(.chosen and .rank != null) | { l: .team, pts, rank, eds, band: (pband(.mem_mb)), prof } ]),
      machines: ([ $mx[] | { mac, online, processor, cores, mem_mb, editors_time, fw, sl, home_pct, binding, team, chosen,
                             used, eds, prof, pts, edmax, model, oom, agent_new } ]),
      series: ([ $series_in[] | .mac as $mac | .points[]
                 | select(.t >= $ws and .t <= $we)
                 | {b: ((.t / 600) | floor), mac: $mac, mem: (.mem // 0), ld: (.ld // 0), sw: (.sw // 0), fw: (.fw // 1), ed: (.ed // []), psi: (.psi_mem // null)} ]
               | group_by(.b)
               | map({ t: (.[0].b * 600),
                       act: ([ .[].mac ] | unique | length),
                       mem_sum: ([ .[].mem ] | add // 0), mem_n: length,
                       ld_sum: ([ .[].ld ] | add // 0), ld_n: length,
                       ld_max: ([ .[].ld ] | max // 0),
                       sw_sum: ([ .[].sw ] | add // 0), sw_n: length,
                       psi_sum: ([ .[].psi // empty ] | add // 0), psi_n: ([ .[] | select(.psi != null) ] | length),
                       fw_off: ([ .[] | select(.fw == 0 or .fw == false) | .mac ] | unique | length),
                       ed: (reduce (.[] | {m: .mac, e: .ed[]}) as $x ({}; (($x.e) as $k | .[$k] = ((.[$k] // []) + [$x.m])))
                           | with_entries(.value |= (unique | length))) }))
    }'
while IFS=$'\t' read -r id sede pais fullname; do
  # os DOIS leiautes do bruto: lote por sede (`<id>.ndjson`) e por máquina (`<id>.<mac>.json`, o
  # das coletas anteriores a 21/09/2026). `jq -s` engole valores JSON concatenados, com ou sem \n.
  { cat "$W/samples/$id.ndjson" 2>/dev/null; cat "$W/samples/$id."*.json 2>/dev/null; } > "$W/spl.$id.raw"
  jq -cs '[ .[] | select(type == "object") ]' "$W/spl.$id.raw" > "$W/spl.$id.json" 2>/dev/null \
    || printf '[]' > "$W/spl.$id.json"
  jq -Rcs 'split("\n") | map(select(length > 0))' "$W/teams.$id.txt" > "$W/tf.$id.json"
  jq -cn --arg id "$id" --arg sede "$sede" --arg pais "$pais" --arg full "$fullname" --arg mode "$MODE" \
     --argjson ws "$WSTART" --argjson we "$WEND" --argjson cs "$CS" --argjson ce "$CE" \
     --slurpfile m "$W/machines.$id.json" \
     --slurpfile spf "$W/spl.$id.json" \
     --slurpfile tf "$W/tf.$id.json" \
     --slurpfile lk "$W/link.json" \
     --slurpfile dm "$W/dupmids.json" \
     --slurpfile pr "$W/present.json" \
     --slurpfile pl "$W/place.json" \
     "$AGG_JQ" \
    >> "$W/aggs.jsonl" 2>>"$W/agg.err" || echo "$id" >> "$W/skipped.txt"
done < "$W/kept.tsv"
[[ -s "$W/aggs.jsonl" ]] || { finish "agregação falhou ($(head -c 200 "$W/agg.err" 2>/dev/null))"; trap - EXIT; exit 1; }

# --- 6. nós da árvore (regions.json): imagem pertence ao nó cujo regex casa um login -----
: > "$W/nodemap.tsv"   # id \t nó
if [[ -s "$CDIR/regions.json" ]]; then
  jq -r 'def flat: .[]? | ([(.name // ""), (.regex // "")] | @tsv), ((.subregions // []) | flat); flat' \
      "$CDIR/regions.json" 2>/dev/null > "$W/nodes.tsv"
  while IFS=$'\t' read -r id sede _rest; do
    while IFS=$'\t' read -r nm re; do
      [[ -n "$nm" ]] || continue
      if [[ -n "$re" ]] && grep -qE -- "$re" "$W/teams.$id.txt" 2>/dev/null; then
        printf '%s\t%s\n' "$id" "$nm" >> "$W/nodemap.tsv"
      elif [[ "${nm,,}" == "${sede,,}" ]]; then
        printf '%s\t%s\n' "$id" "$nm" >> "$W/nodemap.tsv"
      fi
    done < "$W/nodes.tsv"
  done < "$W/kept.tsv"
fi
jq -Rcs '[ split("\n")[] | select(length > 0) | split("\t") | {id: .[0], node: .[1]} ]' \
  "$W/nodemap.tsv" > "$W/nodemap.json"

# --- 7. montagem final: rollups (global + by_node) + ranks + rank_ed ---------------------
# Merge é EXATO porque tudo mergeável é soma/contagem (séries por t somam sums e n).
# `rank_ed` = editores × colocação DO RECORTE: as `_rows` (rank, editores, faixa, perfil —
# sem login/MAC) das sedes do nó, re-ranqueadas pela posição global; top 30 / quartil / 10 %.
# As `_rows` morrem aqui (del) — nunca vão ao cache.
jq -cs --argjson ws "$WSTART" --argjson we "$WEND" --argjson cs "$CS" --argjson ce "$CE" \
   --argjson now "$EPOCHSECONDS" --arg mode "$MODE" --argjson nlink "$NLINK" --argjson nteams "$NTEAMS" --argjson npres "$NPRES" \
   --slurpfile nmf "$W/nodemap.json" \
   --rawfile skipped <(cat "$W/skipped.txt" 2>/dev/null || printf '') '
  def madd($a; $b): reduce ($b | to_entries[]) as $e ($a; .[$e.key] = ((.[$e.key] // 0) + $e.value));
  def grp(e): (if e == "code" then "vscode"
               elif (e == "idea" or e == "clion" or e == "pycharm") then "jetbrains"
               elif e == "codeblocks" then "codeblocks"
               elif (e == "vim" or e == "gedit" or e == "geany" or e == "emacs") then "light"
               else "other" end);
  def cnt(f): (reduce f as $k ({}; .[$k] = ((.[$k] // 0) + 1)));
  def rank($list; f):
    ($list | sort_by(-(f)) | map(.id)) as $ord
    | reduce range(0; $ord | length) as $i ({}; .[$ord[$i]] = ($i + 1));
  def merge_series($ss):
    ($ss | add // []) | group_by(.t)
    | map({ t: .[0].t,
            act: ([ .[].act ] | add), mem_sum: ([ .[].mem_sum ] | add), mem_n: ([ .[].mem_n ] | add),
            ld_sum: ([ .[].ld_sum ] | add), ld_n: ([ .[].ld_n ] | add), ld_max: ([ .[].ld_max ] | max),
            sw_sum: ([ .[].sw_sum // 0 ] | add), sw_n: ([ .[].sw_n // 0 ] | add),
            psi_sum: ([ .[].psi_sum // 0 ] | add), psi_n: ([ .[].psi_n // 0 ] | add),
            fw_off: ([ .[].fw_off // 0 ] | add),
            ed: (reduce .[] as $x ({}; madd(.; ($x.ed // {})))) });
  def merge_pseries($ss):
    ($ss | add // []) | group_by(.t)
    | map({ t: .[0].t, mem_sum: ([ .[].mem_sum ] | add), mem_n: ([ .[].mem_n ] | add),
            sw_sum: ([ .[].sw_sum ] | add), sw_n: ([ .[].sw_n ] | add),
            psi_sum: ([ .[].psi_sum // 0 ] | add), psi_n: ([ .[].psi_n // 0 ] | add) });
  def merge_pressure($ps):
    reduce ($ps[] | to_entries[]) as $e ({};
      (.[$e.key] // null) as $c
      | .[$e.key] = (if $c == null then $e.value else
          { n: ($c.n + $e.value.n),
            mem_sum: ($c.mem_sum + $e.value.mem_sum), mem_n: ($c.mem_n + $e.value.mem_n),
            sw_sum: ($c.sw_sum + $e.value.sw_sum), sw_n: ($c.sw_n + $e.value.sw_n),
            sw_max: ([ $c.sw_max, $e.value.sw_max ] | max),
            psi_sum: (($c.psi_sum // 0) + ($e.value.psi_sum // 0)), psi_n: (($c.psi_n // 0) + ($e.value.psi_n // 0)),
            psi_max: ([ ($c.psi_max // 0), ($e.value.psi_max // 0) ] | max),
            mem0_sum: ($c.mem0_sum + $e.value.mem0_sum), mem0_n: ($c.mem0_n + $e.value.mem0_n),
            mem4_sum: ($c.mem4_sum + $e.value.mem4_sum), mem4_n: ($c.mem4_n + $e.value.mem4_n),
            series: (merge_pseries([ $c.series, $e.value.series ])) } end));
  def rcnt($xs): { n: ($xs | length), ed: (cnt($xs[] | .eds[])),
                   grp: (cnt($xs[] | [ .eds[] | grp(.) ] | unique | .[])),
                   prof: (cnt($xs[] | .prof)) };
  def rank_ed($rows0):
    ($rows0 | group_by(.l) | map(max_by(.pts))) as $rows
    | ([ $rows[] | select(.rank != null) ] | sort_by(.rank)) as $r
    | ($r | length) as $n
    | { n: $n, all: (rcnt($r)), top30: (rcnt($r[0:30])),
        q1: (rcnt($r[0:(($n / 4) | ceil)])), p10: (rcnt($r[0:(($n / 10) | ceil)])) };
  def roll($list):
    { sedes: ([ $list[].name ] | unique),
      machines_total: ([ $list[].machines_total ] | add // 0),
      seen: ([ $list[].seen ] | add // 0),
      firewall_off: ([ $list[].firewall_off ] | add // 0),
      screen_lock: ([ $list[].screen_lock ] | add // 0),
      alerts: ([ $list[].alerts ] | add // 0),
      alert_kinds: (reduce $list[] as $s ({}; madd(.; ($s.alert_kinds // {})))),
      health: (reduce $list[] as $s ({}; madd(.; ($s.health // {})))),
      psi_mem_max: ([ $list[].psi_mem_max // 0 ] | max // 0),
      model_tm: (reduce $list[] as $s ({}; madd(.; ($s.model_tm // {})))),
      disk_high: ([ $list[].disk_high ] | add // 0),
      bound: ([ $list[].bound ] | add // 0),
      pop: (reduce $list[] as $s ({}; madd(.; $s.pop))),
      ram_total_mb: ([ $list[].ram_total_mb ] | add // 0),
      cores_total: ([ $list[].cores_total ] | add // 0),
      ram_sum_tm: ([ $list[].ram_sum_tm ] | add // 0), ram_n_tm: ([ $list[].ram_n_tm ] | add // 0),
      ram_avg_sites: (([ $list[] | select(.ram_n_tm > 0) | (.ram_sum_tm / .ram_n_tm) ]) as $a
                      | if ($a | length) > 0 then (($a | add) / ($a | length) | floor) else 0 end),
      cpu: (reduce $list[] as $s ({}; madd(.; $s.cpu))),
      cpu_tm: (reduce $list[] as $s ({}; madd(.; $s.cpu_tm))),
      ram_bands_all: (reduce $list[] as $s ({}; madd(.; $s.ram_bands_all))),
      ram_bands: (reduce $list[] as $s ({}; madd(.; $s.ram_bands))),
      editors: (reduce $list[] as $s ({}; madd(.; $s.editors))),
      editors_total_min: ([ $list[].editors_total_min ] | add // 0),
      editors_machines: (reduce $list[] as $s ({}; madd(.; $s.editors_machines))),
      ed_min: (reduce $list[] as $s ({}; madd(.; $s.ed_min))),
      ed_min_total: ([ $list[].ed_min_total ] | add // 0),
      ed_adopt: (reduce $list[] as $s ({}; madd(.; $s.ed_adopt))),
      ed_groups: (reduce $list[] as $s ({}; madd(.; $s.ed_groups))),
      ed_count: (reduce $list[] as $s ({}; madd(.; $s.ed_count))),
      profiles: (reduce $list[] as $s ({}; madd(.; $s.profiles))),
      ld_sum: ([ $list[].ld_sum ] | add // 0), ld_n: ([ $list[].ld_n ] | add // 0), ld_max: ([ $list[].ld_max ] | max // 0),
      mem_sum: ([ $list[].mem_sum ] | add // 0), mem_n: ([ $list[].mem_n ] | add // 0),
      sw_sum: ([ $list[].sw_sum ] | add // 0), sw_n: ([ $list[].sw_n ] | add // 0),
      pressure: (merge_pressure([ $list[].pressure ])),
      rank_ed: (rank_ed([ $list[]._rows[] ])),
      series: (merge_series([ $list[].series ])) };
  . as $aggs
  | ($nmf[0]) as $nm
  | ($aggs | map({ id, name, country,
                   ram_avg_mb: (if .ram_n_tm > 0 then ((.ram_sum_tm / .ram_n_tm) | floor)
                                elif .seen > 0 then ((.ram_total_mb / .seen) | floor) else 0 end),
                   cores_avg: (if .seen > 0 then ((.cores_total * 10 / .seen | floor) / 10) else 0 end),
                   ed_min_total })) as $metrics
  | (rank($metrics; .ram_avg_mb)) as $rk_ram_g
  | (rank($metrics; .cores_avg)) as $rk_cpu_g
  | (rank($metrics; .ed_min_total)) as $rk_ed_g
  | (reduce ($metrics | group_by(.country))[] as $grp ({};
       . + { ($grp[0].country): { n: ($grp | length),
             ram: (rank($grp; .ram_avg_mb)), cpu: (rank($grp; .cores_avg)),
             ed: (rank($grp; .ed_min_total)) } })) as $rk_pais
  | { version: 2, collected_at: $now,
      window: {start: $ws, end: $we},
      contest: {start: $cs, end: $ce},
      link: { mode: $mode, linked: $nlink, teams: $nteams, present: $npres,
              coverage: (if $npres > 0 then (($nlink * 100 / $npres) | floor) else 0 end) },
      skipped: ($skipped | split("\n") | map(select(length > 0))),
      global: (roll($aggs)),
      by_node: (reduce ([ $nm[].node ] | unique)[] as $node ({};
        . + { ($node): (roll([ $aggs[] | . as $a | select([ $nm[] | select(.node == $node) | .id ] | index($a.id) != null) ])) })),
      sedes: ([ $aggs[] | . as $a
        | ($metrics[] | select(.id == $a.id)) as $mt
        | $a + { ram_avg_mb: $mt.ram_avg_mb, cores_avg: $mt.cores_avg,
                 rank_ed: (rank_ed($a._rows)),
                 ranks: { geral: { ram: $rk_ram_g[$a.id], cpu: $rk_cpu_g[$a.id], ed: $rk_ed_g[$a.id], n: ($metrics | length) },
                          pais: { ram: $rk_pais[$a.country].ram[$a.id], cpu: $rk_pais[$a.country].cpu[$a.id],
                                  ed: $rk_pais[$a.country].ed[$a.id], n: $rk_pais[$a.country].n } } }
        | del(._rows) ]
        | sort_by(.name)) }' \
  "$W/aggs.jsonl" > "$W/final.json" 2>"$W/final.err" \
  || { finish "montagem final falhou ($(head -c 200 "$W/final.err"))"; trap - EXIT; exit 1; }

# --- 8. bruto p/ --reaggregate (só na coleta de verdade) -------------------------------
if (( ! REAGG )); then
  rm -rf "$RAWD.new" "$RAWD.old" 2>/dev/null
  mkdir -p "$RAWD.new/samples"
  cp "$W/images.json" "$RAWD.new/" 2>/dev/null
  for f in "$W"/roster.*.json "$W"/machines.*.json; do [[ -f "$f" ]] && cp "$f" "$RAWD.new/"; done
  cp -r "$W/samples/." "$RAWD.new/samples/" 2>/dev/null
  jq -cn --argjson t "$EPOCHSECONDS" --argjson ws "$WSTART" --argjson we "$WEND" \
    '{fetched_at: $t, ws: $ws, we: $we}' > "$RAWD.new/meta.json"
  [[ -d "$RAWD" ]] && mv "$RAWD" "$RAWD.old"
  mv "$RAWD.new" "$RAWD" && rm -rf "$RAWD.old"
fi

mv -f "$W/final.json" "$OUT"
OK=1
finish
trap - EXIT
exit 0
