# lib/tl-store.sh — store dos TIME LIMITS reportados pelos juízes (modelo cache).
#
# Cada juiz baixa o pacote do problema p/ um cache local, CALIBRA (roda as soluções
# good) e reporta {id, checksum, tl:{lang:seg}} via /judge/tl-report. Guardamos por id:
# o checksum calibrado + o TL POR HOST. O TL SERVÍVEL (treino/contest) = MÁXIMO entre os
# hosts (conservador: ninguém é pego por um limite menor que o exibido) p/ o checksum
# ATUAL do pacote. Se o problema muda (checksum novo), os TLs antigos são DESCARTADOS —
# voltam a {} até algum juiz recalibrar. Tudo arquivo+jq, atômico (tmp+mv).
: "${RUNDIR:=/home/ribas/moj/run}"
: "${TL_STORE_DIR:=$RUNDIR/tl}"
: "${MOJTOOLS_DIR:=/home/ribas/moj/mojtools}"
: "${MOJ_PROBLEMS_DIR:=/home/ribas/moj/moj-problems}"
: "${CONTESTSDIR:=/home/ribas/moj/contests}"

tl_store_file(){ printf '%s/%s.json' "$TL_STORE_DIR" "$1"; }   # id tem '#', não tem '/': seguro

# pkg_path <id> -> diretório do pacote no store do servidor (ou vazio).
pkg_path(){
  local id="$1" p="$MOJ_PROBLEMS_DIR/${1%%#*}/${1##*#}"
  [[ -d "$p" ]] || p="$MOJ_PROBLEMS_DIR/${id//#//}"
  [[ -d "$p" ]] && printf '%s' "$p"
}
# pkg_tl_checksum <pkgdir> -> checksum dos arquivos que afetam o TL (ou vazio).
pkg_tl_checksum(){ [[ -d "$1" ]] && bash "$MOJTOOLS_DIR/tl-checksum.sh" "$1" 2>/dev/null; }

# tl_store_record <host> <id> <checksum> <tl-json> : funde o TL do host (atômico).
# Se o checksum difere do guardado, ZERA os hosts (versão nova do problema).
tl_store_record(){
  local host="$1" id="$2" cks="$3" tl="$4" f cur tmp
  [[ -n "$host" && -n "$id" && -n "$cks" ]] || return 1
  jq -e . >/dev/null 2>&1 <<<"$tl" || tl='{}'
  mkdir -p "$TL_STORE_DIR" 2>/dev/null; f="$(tl_store_file "$id")"; tmp="$f.tmp.$$"
  cur="$(cat "$f" 2>/dev/null)"; [[ -n "$cur" ]] || cur='{}'
  ( umask 077; jq -n --argjson cur "$cur" --arg id "$id" --arg h "$host" \
      --arg cks "$cks" --argjson tl "$tl" --argjson now "$EPOCHSECONDS" '
      ($cur.checksum // "") as $old
      | (if $old==$cks then ($cur.hosts // {}) else {} end) as $hosts
      | {id:$id, checksum:$cks, updated_at:$now,
         hosts: ($hosts + {($h): {tl:$tl, at:$now}})}
    ' ) > "$tmp" 2>/dev/null && mv -f "$tmp" "$f"
}

# tl_store_served_for <id> <checksum> -> time_limits (MÁX entre hosts) p/ ESSE checksum;
# {} se não houver TL p/ a versão (descartado por mudança ou ainda não calibrado).
tl_store_served_for(){
  local id="$1" cks="$2" f; f="$(tl_store_file "$id")"
  [[ -f "$f" && -n "$cks" ]] || { echo '{}'; return; }
  jq -c --arg cks "$cks" '
    if (.checksum // "") != $cks or ((.hosts // {})|length)==0 then {}
    else [ .hosts[].tl // {} ]
         | reduce (.[]|to_entries[]) as $e ({}; .[$e.key]=([(.[$e.key]//0),($e.value|tonumber? // 0)]|max))
         | with_entries(.value |= tostring)
    end' "$f" 2>/dev/null || echo '{}'
}
# tl_store_served_hosts <id> <checksum> "<h1 h2 …>" -> como tl_store_served_for, mas o MÁX
# é só entre os HOSTS LISTADOS (pool de juízes do contest/problema). Host do pool sem
# calibração é ignorado; nenhum calibrado -> {}. hosts vazio = todos (delega).
tl_store_served_hosts(){
  local id="$1" cks="$2" hosts="$3" f; f="$(tl_store_file "$id")"
  [[ -n "$hosts" ]] || { tl_store_served_for "$id" "$cks"; return; }
  [[ -f "$f" && -n "$cks" ]] || { echo '{}'; return; }
  jq -c --arg cks "$cks" --arg hs "$hosts" '
    ($hs|split(" ")|map(select(length>0))) as $want
    | if (.checksum // "") != $cks then {}
      else [ (.hosts // {}) | to_entries[] | select(.key as $h | $want|index($h)) | .value.tl // {} ]
           | reduce (.[]|to_entries[]) as $e ({}; .[$e.key]=([(.[$e.key]//0),($e.value|tonumber? // 0)]|max))
           | with_entries(.value |= tostring)
      end' "$f" 2>/dev/null || echo '{}'
}
# tl_store_served <id> [hosts] -> time_limits p/ a versão ATUAL do pacote no store do
# servidor; 2º arg opcional restringe ao pool ("h1 h2 …").
tl_store_served(){ tl_store_served_hosts "$1" "$(pkg_tl_checksum "$(pkg_path "$1")")" "${2:-}"; }
# tl_store_get <id> -> store bruto (ou {})
tl_store_get(){ cat "$(tl_store_file "$1")" 2>/dev/null || echo '{}'; }

# index_problem_bg <id> [validate=0|1] — (re)gera o var/jsons NO SERVIDOR, em background
# (HTML via Makefile do repo + time_limits do store). Substitui o índice que rodava no
# juiz (kind=index). validate=1 roda o portão estático antes (best-effort).
index_problem_bg(){
  local id="$1" validate="${2:-0}" pkg; pkg="$(pkg_path "$id")"; [[ -n "$pkg" ]] || return 1
  ( setsid env MOJ_TL_STORE="$TL_STORE_DIR" RUNDIR="$RUNDIR" CONTESTSDIR="$CONTESTSDIR" \
       MOJ_PROBLEMS_DIR="$MOJ_PROBLEMS_DIR" MOJTOOLS_DIR="$MOJTOOLS_DIR" \
       bash -c '
         pkg="$1"; id="$2"; val="$3"
         if [[ "$val" == 1 ]]; then
           # portão estático + index (validate-problem indexa SÓ se passar)
           bash "$MOJTOOLS_DIR/validate-problem.sh" "$pkg" "$id" >/dev/null 2>&1
         else
           # só re-indexa (ex.: time_limits atualizado após um tl-report)
           bash "$MOJTOOLS_DIR/gen-problem-json.sh" "$pkg" "$id" >/dev/null 2>&1
         fi
       ' _ "$pkg" "$id" "$validate" >/dev/null 2>&1 & ) 2>/dev/null
}
