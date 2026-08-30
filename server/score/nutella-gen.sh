#!/usr/bin/env bash
#
# nutella-gen.sh <contest> [outfile]
#
# COLETOR do panorama mlinux (nutellaboot): baixa site-images/roster/machines/samples do
# serviço externo, agrega POR SEDE (specs, editores, estado, série temporal em janelas de
# 10 min) e faz os rollups pela MESMA árvore de regions.json do placar/estatística (nó
# casa por regex contra os logins do roster — o idioma do stats-gen). Grava ATÔMICO em
# var/nutella.cache.json + progresso em var/nutella.status.json. Ver docs/NUTELLABOOT.md.
#
# É um "build" irmão do stats-gen/report-gen: roda standalone (CLI) ou destacado pelo
# handler /contest/nutella (action collect). Coleta ~2.6k requests de samples em -P16;
# tolerante a falha (máquina sem samples entra sem série; imagem que falhou fica de fora
# e é contada em `skipped`).
set -u
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
export CONTESTSDIR

C="${1:-}"; OUT="${2:-}"
[[ -n "$C" ]] || { echo "uso: nutella-gen.sh <contest> [outfile]" >&2; exit 1; }
case "$C" in *[!A-Za-z0-9._@#+-]* | "" | *..* ) echo "nutella-gen: invalid contest id" >&2; exit 1;; esac
CDIR="$CONTESTSDIR/$C"
[[ -f "$CDIR/conf" ]] || { echo "nutella-gen: sem conf em $CDIR" >&2; exit 1; }
[[ -n "$OUT" ]] || OUT="$CDIR/var/nutella.cache.json"
STF="$CDIR/var/nutella.status.json"
mkdir -p "$CDIR/var" 2>/dev/null

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIBDIR="$HERE/../api/v1/lib"
source "$_LIBDIR/users.sh"
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
nb_configured "$C" || { echo "nutella-gen: integração não configurada (sem chave)" >&2; exit 1; }

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

BASE="$(nb_url "$C")"
KEY="$(grep -aoE 'nb3a_[A-Za-z0-9]+' "$(nb_keyfile "$C")" 2>/dev/null | head -n1)"
# header via arquivo de config do curl (600 dentro do W 700) — chave nunca em argv
printf 'header = "Authorization: Bearer %s"\n' "$KEY" > "$W/cfg"; chmod 600 "$W/cfg"
nbget(){ curl -s -m 30 -K "$W/cfg" "$BASE/api/v1/$1"; }   # caminho SEM segredo no argv

START="$(conf_value "$C" CONTEST_START)"; [[ "$START" =~ ^[0-9]+$ ]] || START=0
END="$(conf_value "$C" CONTEST_END)";     [[ "$END" =~ ^[0-9]+$ ]] || END=0
WSTART=$(( START > 3600 ? START - 3600 : 0 ))
WEND=$(( END + 3600 )); (( WEND > EPOCHSECONDS || END == 0 )) && WEND="$EPOCHSECONDS"

# --- 1. imagens + logins do contest ------------------------------------------------------
prog "listando sedes"
nbget site-images > "$W/images.json" 2>/dev/null
jq -e '.images | type == "array"' "$W/images.json" >/dev/null 2>&1 \
  || { finish "nutellaboot inacessível ou chave inválida"; trap - EXIT; exit 1; }
find "$CDIR/users" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort > "$W/logins.txt"

mapfile -t IDS < <(jq -r '.images[].id' "$W/images.json")
NIMG="${#IDS[@]}"
prog "baixando roster+máquinas" 0 "$NIMG"

# --- 2. roster + machines por imagem (paralelo; id validado — vira nome de arquivo) ------
printf '%s\n' "${IDS[@]}" | grep -E '^[A-Za-z0-9._-]+$' | \
  xargs -P8 -n1 sh -c '
    curl -s -m 30 -K "$0/cfg" "$1/api/v1/site-images/$2/roster"   > "$0/roster.$2.json" 2>/dev/null
    curl -s -m 60 -K "$0/cfg" "$1/api/v1/site-images/$2/machines" > "$0/machines.$2.json" 2>/dev/null
  ' "$W" "$BASE"

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
mkdir -p "$W/samples"
: > "$W/maclist.txt"
while IFS=$'\t' read -r id _rest; do
  jq -r --argjson ws "$WSTART" \
    '.machines[]? | select((.last_seen // 0) >= $ws) | .mac' "$W/machines.$id.json" 2>/dev/null \
    | grep -E '^[A-Za-z0-9:-]+$' | sed "s/^/$id /"
done < "$W/kept.tsv" >> "$W/maclist.txt"
NSAMP="$(wc -l < "$W/maclist.txt" | tr -d '[:space:]')"
prog "baixando séries das máquinas" 0 "$NSAMP"
xargs -P16 -n2 sh -c '
  curl -s -m 20 -K "$0/cfg" "$1/api/v1/site-images/$2/machines/$3/samples" \
    > "$0/samples/$2.$3.json" 2>/dev/null || true
' "$W" "$BASE" < "$W/maclist.txt"
prog "agregando" 0 "$NKEPT"

# --- 5. agregado POR IMAGEM (um jq por sede: máquinas + séries mergeáveis) ---------------
# Tudo que precisa virar média em rollup é guardado como SOMA+N (merge exato depois).
AGG_JQ='
  def bucket(m): (if m >= 28672 then ">32" elif m >= 24576 then "32" elif m >= 12288 then "16"
                  elif m >= 6144 then "8" else "<8" end);
  ($spf[0]) as $sp
  | ($tf[0]) as $teams
  | ($m[0].machines // []) as $ms
  | [ $ms[] | select((.last_seen // 0) >= $ws) ] as $seen
  | ($sp | map(select((.points // []) | length > 0))) as $series_in
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
      ram_total_mb: ([ $seen[].status.hwinfo.memtotal_mb // 0 ] | add // 0),
      cores_total: ([ $seen[].status.hwinfo.cores // 0 ] | add // 0),
      cpu: (reduce ($seen[] | .status.hwinfo.processor // "?") as $p ({}; .[$p] = ((.[$p] // 0) + 1))),
      ram_buckets: (reduce ($seen[] | .status.hwinfo.memtotal_mb // 0) as $mb ({}; (bucket($mb)) as $b | .[$b] = ((.[$b] // 0) + 1))),
      editors: (reduce ($seen[] | .status.operations.editors_time // {} | to_entries[] | select(.key != "total")) as $e ({}; .[$e.key] = ((.[$e.key] // 0) + ($e.value // 0)))),
      editors_total_min: ([ $seen[] | .status.operations.editors_time.total // 0 ] | add // 0),
      editors_machines: (reduce ($seen[] | (.status.operations.editors_time // {} | keys[] | select(. != "total"))) as $k ({}; .[$k] = ((.[$k] // 0) + 1))),
      machines: ([ $seen[] | {mac, online, processor: (.status.hwinfo.processor // "?"),
                   cores: (.status.hwinfo.cores // 0), mem_mb: (.status.hwinfo.memtotal_mb // 0),
                   editors_time: (.status.operations.editors_time // {}),
                   fw: (.status.operations.firewall // null), sl: (.status.operations.screen_lock // null),
                   home_pct: (.status.sysdisk.home_pct // null), binding} ]),
      series: ([ $series_in[] | .mac as $mac | .points[]
                 | select(.t >= $ws and .t <= $we)
                 | {b: ((.t / 600) | floor), mac: $mac, mem: (.mem // 0), ld: (.ld // 0), ed: (.ed // [])} ]
               | group_by(.b)
               | map({ t: (.[0].b * 600),
                       act: ([ .[].mac ] | unique | length),
                       mem_sum: ([ .[].mem ] | add // 0), mem_n: length,
                       ld_sum: ([ .[].ld ] | add // 0), ld_n: length,
                       ld_max: ([ .[].ld ] | max // 0),
                       ed: (reduce (.[] | {m: .mac, e: .ed[]}) as $x ({}; (($x.e) as $k | .[$k] = ((.[$k] // []) + [$x.m])))
                           | with_entries(.value |= (unique | length))) }))
    }'
while IFS=$'\t' read -r id sede pais fullname; do
  cat "$W/samples/$id."*.json > "$W/spl.$id.raw" 2>/dev/null || : > "$W/spl.$id.raw"
  jq -cs '[ .[] | select(type == "object") ]' "$W/spl.$id.raw" > "$W/spl.$id.json" 2>/dev/null \
    || printf '[]' > "$W/spl.$id.json"
  jq -cn --arg id "$id" --arg sede "$sede" --arg pais "$pais" --arg full "$fullname" \
     --argjson ws "$WSTART" --argjson we "$WEND" \
     --slurpfile m "$W/machines.$id.json" \
     --slurpfile spf "$W/spl.$id.json" \
     --slurpfile tf <(jq -Rcs 'split("\n") | map(select(length > 0))' "$W/teams.$id.txt") \
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

# --- 7. montagem final: rollups (global + by_node) + ranks -------------------------------
# Merge é EXATO porque tudo mergeável é soma/contagem (séries por t somam sums e n).
jq -cs --argjson ws "$WSTART" --argjson we "$WEND" --argjson now "$EPOCHSECONDS" \
   --slurpfile nmf "$W/nodemap.json" \
   --rawfile skipped <(cat "$W/skipped.txt" 2>/dev/null || printf '') '
  def madd($a; $b): reduce ($b | to_entries[]) as $e ($a; .[$e.key] = ((.[$e.key] // 0) + $e.value));
  def rank($list; f):
    ($list | sort_by(-(f)) | map(.id)) as $ord
    | reduce range(0; $ord | length) as $i ({}; .[$ord[$i]] = ($i + 1));
  def merge_series($ss):
    ($ss | add // []) | group_by(.t)
    | map({ t: .[0].t,
            act: ([ .[].act ] | add), mem_sum: ([ .[].mem_sum ] | add), mem_n: ([ .[].mem_n ] | add),
            ld_sum: ([ .[].ld_sum ] | add), ld_n: ([ .[].ld_n ] | add), ld_max: ([ .[].ld_max ] | max),
            ed: (reduce .[] as $x ({}; madd(.; ($x.ed // {})))) });
  def roll($list):
    { sedes: ([ $list[].name ] | unique),
      machines_total: ([ $list[].machines_total ] | add // 0),
      seen: ([ $list[].seen ] | add // 0),
      firewall_off: ([ $list[].firewall_off ] | add // 0),
      screen_lock: ([ $list[].screen_lock ] | add // 0),
      alerts: ([ $list[].alerts ] | add // 0),
      disk_high: ([ $list[].disk_high ] | add // 0),
      bound: ([ $list[].bound ] | add // 0),
      ram_total_mb: ([ $list[].ram_total_mb ] | add // 0),
      cores_total: ([ $list[].cores_total ] | add // 0),
      cpu: (reduce $list[] as $s ({}; madd(.; $s.cpu))),
      ram_buckets: (reduce $list[] as $s ({}; madd(.; $s.ram_buckets))),
      editors: (reduce $list[] as $s ({}; madd(.; $s.editors))),
      editors_total_min: ([ $list[].editors_total_min ] | add // 0),
      editors_machines: (reduce $list[] as $s ({}; madd(.; $s.editors_machines))),
      series: (merge_series([ $list[].series ])) };
  . as $aggs
  | ($nmf[0]) as $nm
  | ($aggs | map({ id, name, country,
                   ram_avg_mb: (if .seen > 0 then ((.ram_total_mb / .seen) | floor) else 0 end),
                   cores_avg: (if .seen > 0 then ((.cores_total * 10 / .seen | floor) / 10) else 0 end),
                   editors_total_min })) as $metrics
  | (rank($metrics; .ram_avg_mb)) as $rk_ram_g
  | (rank($metrics; .cores_avg)) as $rk_cpu_g
  | (rank($metrics; .editors_total_min)) as $rk_ed_g
  | (reduce ($metrics | group_by(.country))[] as $grp ({};
       . + { ($grp[0].country): { n: ($grp | length),
             ram: (rank($grp; .ram_avg_mb)), cpu: (rank($grp; .cores_avg)),
             ed: (rank($grp; .editors_total_min)) } })) as $rk_pais
  | { collected_at: $now,
      window: {start: $ws, end: $we},
      skipped: ($skipped | split("\n") | map(select(length > 0))),
      global: (roll($aggs)),
      by_node: (reduce ([ $nm[].node ] | unique)[] as $node ({};
        . + { ($node): (roll([ $aggs[] | . as $a | select([ $nm[] | select(.node == $node) | .id ] | index($a.id) != null) ])) })),
      sedes: ([ $aggs[] | . as $a
        | ($metrics[] | select(.id == $a.id)) as $mt
        | $a + { ram_avg_mb: $mt.ram_avg_mb, cores_avg: $mt.cores_avg,
                 ranks: { geral: { ram: $rk_ram_g[$a.id], cpu: $rk_cpu_g[$a.id], ed: $rk_ed_g[$a.id], n: ($metrics | length) },
                          pais: { ram: $rk_pais[$a.country].ram[$a.id], cpu: $rk_pais[$a.country].cpu[$a.id],
                                  ed: $rk_pais[$a.country].ed[$a.id], n: $rk_pais[$a.country].n } } } ]
        | sort_by(.name)) }' \
  "$W/aggs.jsonl" > "$W/final.json" 2>"$W/final.err" \
  || { finish "montagem final falhou ($(head -c 200 "$W/final.err"))"; trap - EXIT; exit 1; }

mv -f "$W/final.json" "$OUT"
OK=1
finish
trap - EXIT
exit 0
