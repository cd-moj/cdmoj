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
  KEY="$(grep -aoE 'nb3a_[A-Za-z0-9]+' "$(nb_keyfile "$C")" 2>/dev/null | head -n1)"
  # header via arquivo de config do curl (600 dentro do W 700) — chave nunca em argv
  printf 'header = "Authorization: Bearer %s"\n' "$KEY" > "$W/cfg"; chmod 600 "$W/cfg"
  nbget(){ curl -s -m 30 -K "$W/cfg" "$BASE/api/v1/$1"; }   # caminho SEM segredo no argv

  # --- 1. imagens ------------------------------------------------------------------------
  prog "listando sedes"
  nbget site-images > "$W/images.json" 2>/dev/null
  jq -e '.images | type == "array"' "$W/images.json" >/dev/null 2>&1 \
    || { finish "nutellaboot inacessível ou chave inválida"; trap - EXIT; exit 1; }
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
mapfile -t IDS < <(jq -r '.images[].id' "$W/images.json")
NIMG="${#IDS[@]}"

# --- 3. relevância + nome da sede --------------------------------------------------------
# Imagem RELEVANTE = roster ∩ logins do contest (a de teste e as de outros eventos caem
# fora). Nome da sede = .team.region (store) do 1º login do roster que tiver; fallback =
# fullname da imagem. País = 2 letras do id (26brprcu → br).
: > "$W/kept.tsv"    # id \t sede \t país \t fullname
for id in "${IDS[@]}"; do
  [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || continue
  jq -r '.roster[]?.user_id // empty' "$W/roster.$id.json" 2>/dev/null | sort > "$W/rteams.$id.txt"
  comm -12 "$W/logins.txt" "$W/rteams.$id.txt" > "$W/teams.$id.txt"
  [[ -s "$W/teams.$id.txt" ]] || continue
  sede=""
  while IFS= read -r lg; do
    sede="$(jq -r '.team.region // empty' "$(account_file "$C" "$lg")" 2>/dev/null)"
    [[ -n "$sede" ]] && break
  done < "$W/teams.$id.txt"
  fullname="$(jq -r --arg i "$id" 'first(.images[] | select(.id == $i) | .fullname) // $i' "$W/images.json")"
  [[ -n "$sede" ]] || sede="$fullname"
  pais="$(printf '%s' "$id" | sed -E 's/^[0-9]+//; s/^(..).*$/\1/')"
  printf '%s\t%s\t%s\t%s\n' "$id" "$sede" "$pais" "$fullname" >> "$W/kept.tsv"
done
NKEPT="$(wc -l < "$W/kept.tsv" | tr -d '[:space:]')"
(( NKEPT > 0 )) || { finish "nenhuma sede do nutellaboot casa com os times deste contest"; trap - EXIT; exit 1; }

# --- 4. samples (a parte pesada: uma request por máquina VISTA na janela) ----------------
# `since/until` = a janela: o serviço reamostra 400 pontos DENTRO dela (~1/min na prova).
mkdir -p "$W/samples"
if (( ! REAGG )); then
  : > "$W/maclist.txt"
  while IFS=$'\t' read -r id _rest; do
    jq -r --argjson ws "$WSTART" \
      '.machines[]? | select((.last_seen // 0) >= $ws) | .mac' "$W/machines.$id.json" 2>/dev/null \
      | grep -E '^[A-Za-z0-9:-]+$' | sed "s/^/$id /"
  done < "$W/kept.tsv" >> "$W/maclist.txt"
  NSAMP="$(wc -l < "$W/maclist.txt" | tr -d '[:space:]')"
  prog "baixando séries das máquinas" 0 "$NSAMP"
  # posicionais: $0=W $1=BASE $2=since $3=until, e o xargs acrescenta $4=imagem $5=mac
  xargs -P16 -n2 sh -c '
    curl -s -m 20 -K "$0/cfg" "$1/api/v1/site-images/$4/machines/$5/samples?since=$2&until=$3" \
      > "$0/samples/$4.$5.json" 2>/dev/null || true
  ' "$W" "$BASE" "$WSTART" "$WEND" < "$W/maclist.txt" 2>/dev/null
fi
prog "agregando" 0 "$NKEPT"

# --- 4b. ELO máquina↔time: access.log (login grava o UA em base64) -----------------------
# UA do mlinux: "Mozilla/5.0 (MLinux/<imagem>/<machine_id>/<boot_id>) …". Um jq p/ o arquivo
# inteiro (@base64d), janela = a da coleta, contas de PAPEL fora, ÚLTIMO login da máquina
# vence. Saída: {"<machine_id>": "<login>"}.
printf '{}' > "$W/link.json"
if [[ -s "$CDIR/var/access.log" ]]; then
  jq -Rn --argjson a "$WSTART" --argjson b "$WEND" '
    [ inputs | split("\t") | select(length >= 4)
      | (.[0] | tonumber? // 0) as $t
      | select($t >= $a and $t <= $b)
      | .[1] as $lg
      | select(($lg | test("\\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$")) | not)
      | ((.[3] | try @base64d catch "") | capture("MLinux/[^/]+/(?<mid>[0-9a-f]{32})/")? // null) as $m
      | select($m != null)
      | {t: $t, lg: $lg, mid: $m.mid} ]
    | sort_by(.t)
    | reduce .[] as $e ({}; .[$e.mid] = $e.lg)' "$CDIR/var/access.log" > "$W/link.json" 2>/dev/null \
    || printf '{}' > "$W/link.json"
  [[ -s "$W/link.json" ]] || printf '{}' > "$W/link.json"
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
# inteiro; o elo de uma sede sem nutellaboot não conta)
NLINK="$(jq -r '[ .[] ] | unique | .[]' "$W/link.json" 2>/dev/null | sort -u | comm -12 - "$W/allteams.txt" | wc -l | tr -d '[:space:]')"
NLINK="${NLINK//[^0-9]/}"; NLINK="${NLINK:-0}"
MODE=proxy; (( NTEAMS > 0 && NLINK * 2 >= NTEAMS )) && MODE=ua

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
  def derive($p; $cs; $ce):
    ($p | length) as $n
    | (if $n > 1 then ([ range(1; $n) as $i | ($p[$i].t - $p[$i - 1].t) ] | med(.)) else 60 end) as $cad0
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
        bins: ([ $p[] | { b: (((.t - $cs) / 1800) | floor), mem: (.mem // 0), sw: (.sw // 0) } ]
               | group_by(.b) | map({ t: (.[0].b * 1800), mem_sum: ([ .[].mem ] | add), mem_n: length,
                                      sw_sum: ([ .[].sw ] | add), sw_n: length })) };
  def sum(f): ([ f ] | add // 0);
  ($spf[0]) as $sp
  | ($tf[0]) as $teams
  | ($lk[0]) as $link
  | ($pl[0]) as $place
  | ($m[0].machines // []) as $ms
  | [ $ms[] | select((.last_seen // 0) >= $ws) ] as $seen
  | ($sp | map(select((.points // []) | length > 0))) as $series_in
  | (reduce $series_in[] as $s ({}; .[$s.mac] = [ $s.points[] | select(.t >= $cs and .t <= $ce) ])) as $cpts
  # ---- por máquina + dedupe de time (um time = a máquina com mais pontos na prova) -------
  | ([ $seen[] | . as $x
       | ($x.status.hwinfo.machine_id // "") as $mid
       | (if $mid != "" then ($link[$mid] // null) else null end) as $team
       | derive(($cpts[$x.mac] // []); $cs; $ce)
         + { mac: $x.mac, online: ($x.online // false),
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
      disk_high: ([ $seen[] | select((.status.sysdisk.home_pct // 0) >= 90) ] | length),
      bound: ([ $ms[] | select(.binding != null) ] | length),
      bindings: ([ $ms[] | select(.binding != null) | {mac, team: (.binding | if type == "object" then (.user_id // .team // tostring) else tostring end)} ]),
      pop: { seen: ($seen | length), used: ([ $mx[] | select(.used) ] | length),
             linked: ([ $mx[] | select(.team != null) ] | length),
             chosen: ([ $mx[] | select(.chosen) ] | length),
             ranked: ([ $mx[] | select(.rank != null) ] | length),
             tm: ($tm | length), teams: ($teams | length) },
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
                    mem0_sum: (((.[$k] // {}).mem0_sum // 0) + ($x.mem0 | add // 0)), mem0_n: (((.[$k] // {}).mem0_n // 0) + ($x.mem0 | length)),
                    mem4_sum: (((.[$k] // {}).mem4_sum // 0) + ($x.mem4 | add // 0)), mem4_n: (((.[$k] // {}).mem4_n // 0) + ($x.mem4 | length)),
                    series: ((((.[$k] // {}).series // []) + $x.bins) | group_by(.t)
                             | map({ t: .[0].t, mem_sum: ([ .[].mem_sum ] | add), mem_n: ([ .[].mem_n ] | add),
                                     sw_sum: ([ .[].sw_sum ] | add), sw_n: ([ .[].sw_n ] | add) })) })),
      _rows: ([ $mx[] | select(.chosen and .rank != null) | { l: .team, pts, rank, eds, band: (pband(.mem_mb)), prof } ]),
      machines: ([ $mx[] | { mac, online, processor, cores, mem_mb, editors_time, fw, sl, home_pct, binding, team, chosen,
                             used, eds, prof, pts, edmax } ]),
      series: ([ $series_in[] | .mac as $mac | .points[]
                 | select(.t >= $ws and .t <= $we)
                 | {b: ((.t / 600) | floor), mac: $mac, mem: (.mem // 0), ld: (.ld // 0), sw: (.sw // 0), fw: (.fw // 1), ed: (.ed // [])} ]
               | group_by(.b)
               | map({ t: (.[0].b * 600),
                       act: ([ .[].mac ] | unique | length),
                       mem_sum: ([ .[].mem ] | add // 0), mem_n: length,
                       ld_sum: ([ .[].ld ] | add // 0), ld_n: length,
                       ld_max: ([ .[].ld ] | max // 0),
                       sw_sum: ([ .[].sw ] | add // 0), sw_n: length,
                       fw_off: ([ .[] | select(.fw == 0 or .fw == false) | .mac ] | unique | length),
                       ed: (reduce (.[] | {m: .mac, e: .ed[]}) as $x ({}; (($x.e) as $k | .[$k] = ((.[$k] // []) + [$x.m])))
                           | with_entries(.value |= (unique | length))) }))
    }'
while IFS=$'\t' read -r id sede pais fullname; do
  cat "$W/samples/$id."*.json > "$W/spl.$id.raw" 2>/dev/null || : > "$W/spl.$id.raw"
  jq -cs '[ .[] | select(type == "object") ]' "$W/spl.$id.raw" > "$W/spl.$id.json" 2>/dev/null \
    || printf '[]' > "$W/spl.$id.json"
  jq -Rcs 'split("\n") | map(select(length > 0))' "$W/teams.$id.txt" > "$W/tf.$id.json"
  jq -cn --arg id "$id" --arg sede "$sede" --arg pais "$pais" --arg full "$fullname" --arg mode "$MODE" \
     --argjson ws "$WSTART" --argjson we "$WEND" --argjson cs "$CS" --argjson ce "$CE" \
     --slurpfile m "$W/machines.$id.json" \
     --slurpfile spf "$W/spl.$id.json" \
     --slurpfile tf "$W/tf.$id.json" \
     --slurpfile lk "$W/link.json" \
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
   --argjson now "$EPOCHSECONDS" --arg mode "$MODE" --argjson nlink "$NLINK" --argjson nteams "$NTEAMS" \
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
            fw_off: ([ .[].fw_off // 0 ] | add),
            ed: (reduce .[] as $x ({}; madd(.; ($x.ed // {})))) });
  def merge_pseries($ss):
    ($ss | add // []) | group_by(.t)
    | map({ t: .[0].t, mem_sum: ([ .[].mem_sum ] | add), mem_n: ([ .[].mem_n ] | add),
            sw_sum: ([ .[].sw_sum ] | add), sw_n: ([ .[].sw_n ] | add) });
  def merge_pressure($ps):
    reduce ($ps[] | to_entries[]) as $e ({};
      (.[$e.key] // null) as $c
      | .[$e.key] = (if $c == null then $e.value else
          { n: ($c.n + $e.value.n),
            mem_sum: ($c.mem_sum + $e.value.mem_sum), mem_n: ($c.mem_n + $e.value.mem_n),
            sw_sum: ($c.sw_sum + $e.value.sw_sum), sw_n: ($c.sw_n + $e.value.sw_n),
            sw_max: ([ $c.sw_max, $e.value.sw_max ] | max),
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
      link: { mode: $mode, linked: $nlink, teams: $nteams,
              coverage: (if $nteams > 0 then (($nlink * 100 / $nteams) | floor) else 0 end) },
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
