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

# ============ SUMÁRIOS AGREGADOS (mantidos POR EVENTO, não por TTL) ==================
# O Painel (/problems/status) precisava de run/tl/<id>.json + run/validation/<id>.json de
# TODOS os ids visíveis — eram ~2·N forks de `cat` POR REQUEST (4s p/ um admin com ~900).
# Agora cada ESCRITOR (tl_store_record; judge/update-report) mantém um mapa agregado
# id→entrada em run/{tl,validation}-summary.json (upsert de 1 chave sob flock; rebuild só
# a frio). Chave órfã (problema deletado) é inócua: os leitores só consultam ids do índice
# visível. Os sumários são arquivos INTERNOS de run/ (nunca servidos crus).
TL_SUMMARY="$RUNDIR/tl-summary.json"
VAL_SUMMARY="$RUNDIR/validation-summary.json"
VAL_STORE_DIR="$RUNDIR/validation"
# projeções (as MESMAS do antigo tlmap/valmap do status.sh — a resposta não muda)
_TL_SUM_PROG='{
   calibrated:(((.hosts // {})|length)>0),
   at:(.updated_at // null), checksum:(.checksum // ""),
   tl:([.hosts[].tl // {}]
       | reduce (.[]|to_entries[]) as $e ({};
           ($e.key | if .=="py3" or .=="py2" then "py" else . end) as $k
           | .[$k]=([(.[$k]//0),($e.value|tonumber? // 0)]|max))
       | with_entries(.value|=tostring)) }'
_VAL_SUM_PROG='{ok:.ok, checks:(.checks // []), at:(.at // null),
   render_warnings:(.render_warnings // "")}'

_summary_rebuild(){  # <dir> <prog> <out> — chamar SOB o flock do chamador; tmp+mv atômico
  local dir="$1" prog="$2" out="$3" tmp="$3.tmp.$$"
  find "$dir" -maxdepth 1 -name '*.json' -exec cat {} + 2>/dev/null \
    | jq -sc "map(select(.id != null) | {key:.id, value:$prog}) | from_entries" > "$tmp" 2>/dev/null
  [[ -s "$tmp" ]] || echo '{}' > "$tmp"
  jq -e . "$tmp" >/dev/null 2>&1 && mv -f "$tmp" "$out" || rm -f "$tmp"
}
_summary_upsert(){   # <id> <src-file> <prog> <out> — funde 1 chave (entrada pequena; mapa via arquivo)
  local id="$1" src="$2" prog="$3" out="$4"
  ( flock 9
    if [[ ! -s "$out" ]]; then _summary_rebuild "$(dirname "$src")" "$prog" "$out"; exit 0; fi
    local entry tmp="$out.tmp.$$"
    entry="$(jq -c "$prog" "$src" 2>/dev/null)"; [[ -n "$entry" ]] || entry='null'
    jq -c --arg id "$id" --argjson e "$entry" '.[$id] = $e' "$out" > "$tmp" 2>/dev/null \
      && [[ -s "$tmp" ]] && mv -f "$tmp" "$out" || rm -f "$tmp"
  ) 9>>"$out.lock"
}
_summary_ensure(){   # <dir> <prog> <out> — leitor: rebuild a frio (1×), depois só stat
  [[ -s "$3" ]] && return 0
  ( flock 9; [[ -s "$3" ]] || _summary_rebuild "$1" "$2" "$3" ) 9>>"$3.lock"
}
tl_summary_upsert(){  _summary_upsert "$1" "$(tl_store_file "$1")" "$_TL_SUM_PROG" "$TL_SUMMARY"; }
tl_summary_ensure(){  _summary_ensure "$TL_STORE_DIR" "$_TL_SUM_PROG" "$TL_SUMMARY"; }
val_summary_upsert(){ _summary_upsert "$1" "$VAL_STORE_DIR/$1.json" "$_VAL_SUM_PROG" "$VAL_SUMMARY"; }
val_summary_ensure(){ _summary_ensure "$VAL_STORE_DIR" "$_VAL_SUM_PROG" "$VAL_SUMMARY"; }

# ===== invalidação POR EVENTO da lista do treino (/treino/problems) ==================
# TODO ponto que cria/remove um json servível de var/jsons TOCA o stamp — o cache
# var/problems.json passa a invalidar ao EVENTO (problema entra/sai), não por relógio.
treino_list_dirty(){ mkdir -p "$CONTESTSDIR/treino/var" 2>/dev/null
  touch "$CONTESTSDIR/treino/var/.treino-list-dirty" 2>/dev/null; }
# unindex_problem <id> — tira da lista servível do treino (json + sidecar de metadados) e invalida
unindex_problem(){
  rm -f "$CONTESTSDIR/treino/var/jsons/$1.json" \
        "$CONTESTSDIR/treino/var/jsons-meta/$1.json" 2>/dev/null
  treino_list_dirty
}

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
# Chaves py3/py2 são LEGADAS (python unificado em 'py'): normaliza na gravação —
# cobre agente com mojtools antigo ainda reportando py3.
tl_store_record(){
  local host="$1" id="$2" cks="$3" tl="$4" f cur tmp
  [[ -n "$host" && -n "$id" && -n "$cks" ]] || return 1
  jq -e . >/dev/null 2>&1 <<<"$tl" || tl='{}'
  mkdir -p "$TL_STORE_DIR" 2>/dev/null; f="$(tl_store_file "$id")"; tmp="$f.tmp.$$"
  cur="$(cat "$f" 2>/dev/null)"; [[ -n "$cur" ]] || cur='{}'
  ( umask 077; jq -n --argjson cur "$cur" --arg id "$id" --arg h "$host" \
      --arg cks "$cks" --argjson tl "$tl" --argjson now "$EPOCHSECONDS" '
      ($tl | reduce to_entries[] as $e ({};
         ($e.key | if .=="py3" or .=="py2" then "py" else . end) as $k
         | .[$k] = (if has($k) and ((.[$k]|tonumber? // 0) >= ($e.value|tonumber? // 0))
                    then .[$k] else $e.value end))) as $ntl
      | ($cur.checksum // "") as $old
      | (if $old==$cks then ($cur.hosts // {}) else {} end) as $hosts
      | {id:$id, checksum:$cks, updated_at:$now,
         hosts: ($hosts + {($h): {tl:$ntl, at:$now}})}
    ' ) > "$tmp" 2>/dev/null && mv -f "$tmp" "$f" || return 1
  tl_summary_upsert "$id"   # sumário do Painel segue o evento (nunca TTL)
}

# tl_store_served_for <id> <checksum> -> time_limits (MÁX entre hosts) p/ ESSE checksum;
# {} se não houver TL p/ a versão (descartado por mudança ou ainda não calibrado).
# Chaves py3/py2 legadas (stores calibrados antes da unificação) fundem em 'py' por MAX.
tl_store_served_for(){
  local id="$1" cks="$2" f; f="$(tl_store_file "$id")"
  [[ -f "$f" && -n "$cks" ]] || { echo '{}'; return; }
  jq -c --arg cks "$cks" '
    if (.checksum // "") != $cks or ((.hosts // {})|length)==0 then {}
    else [ .hosts[].tl // {} ]
         | reduce (.[]|to_entries[]) as $e ({};
             ($e.key | if .=="py3" or .=="py2" then "py" else . end) as $k
             | .[$k]=([(.[$k]//0),($e.value|tonumber? // 0)]|max))
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
           | reduce (.[]|to_entries[]) as $e ({};
               ($e.key | if .=="py3" or .=="py2" then "py" else . end) as $k
               | .[$k]=([(.[$k]//0),($e.value|tonumber? // 0)]|max))
           | with_entries(.value |= tostring)
      end' "$f" 2>/dev/null || echo '{}'
}
# tl_store_served <id> [hosts] -> time_limits p/ a versão ATUAL do pacote no store do
# servidor; 2º arg opcional restringe ao pool ("h1 h2 …").
tl_store_served(){ tl_store_served_hosts "$1" "$(pkg_tl_checksum "$(pkg_path "$1")")" "${2:-}"; }
# tl_store_get <id> -> store bruto (ou {})
tl_store_get(){ cat "$(tl_store_file "$1")" 2>/dev/null || echo '{}'; }

# _index_force_priv <id> <pkg> -> ecoa 0|1.
# TRAVA DA ORG NO INDEXADOR (2ª camada anti-vazamento de prova). O `public` do .moj-meta.json só é
# escrito pelo /problems/set-public, que checa `org_public_allowed`. Mas QUALQUER reindexação
# (tl-report de calibração, /problems/validate, set-collections…) chega aqui, e antes ela publicava
# sem consultar a trava: bastava um meta errado (import legado, org rebaixada, bug) p/ a prova ir
# parar na lista pública. Org que NEGA público => o gerador nunca gera índice público.
#
# CUIDADO — a trava é fail-closed, mas só p/ org REGISTRADA. Org desconhecida (problema legado, de
# antes das orgs) NÃO força privado: senão um orgs.json ausente/incompleto (perda, migração pela
# metade) DESPUBLICARIA a base inteira, em silêncio, um problema por tl-report. Nesse caso quem
# decide é a camada 1 (o `public:true` do meta, que só o set-public escreve).
_index_force_priv(){
  local id="$1" pkg="$2" org="${1%%#*}" orgs="$CONTESTSDIR/treino/var/orgs.json"
  if [[ -f "$orgs" ]] && jq -e --arg n "$org" 'has($n) and (.[$n].public_allowed != true)' \
        "$orgs" >/dev/null 2>&1; then
    # Anomalia: pacote se diz PÚBLICO numa org que não permite (meta de fora / org rebaixada
    # sem cascata). Vai ao audit quando disponível (no bg standalone, silencioso).
    if jq -e '.public == true' "$pkg/.moj-meta.json" >/dev/null 2>&1 \
       && declare -F audit_log >/dev/null 2>&1; then
      audit_log "index-org-lock" "id=$id: meta diz public:true mas a org '$org' não permite — índice mantido PRIVADO"
    fi
    echo 1
  else echo 0; fi
}

# index_problem_now <id> [validate=0|1] — (re)gera o var/jsons SÍNCRONO no servidor +
# SIDECAR de metadados (a lista /treino/problems agrega só isto — nunca o statement) +
# stamp de invalidação por evento. validate=1 roda o portão estático antes (indexa só se
# passar). Use direto em BULK SEQUENCIAL (ex.: coll_bulk_retag: N setsids paralelos de
# gen-problem-json eram uma tempestade de pandoc); p/ 1 problema num request, index_problem_bg.
index_problem_now(){
  local id="$1" validate="${2:-0}" pkg fp
  pkg="$(pkg_path "$id")"; [[ -n "$pkg" ]] || return 1
  fp="$(_index_force_priv "$id" "$pkg")"
  if [[ "$validate" == 1 ]]; then
    MOJ_TL_STORE="$TL_STORE_DIR" MOJ_FORCE_PRIVATE="$fp" RUNDIR="$RUNDIR" \
    CONTESTSDIR="$CONTESTSDIR" MOJ_PROBLEMS_DIR="$MOJ_PROBLEMS_DIR" \
      bash "$MOJTOOLS_DIR/validate-problem.sh" "$pkg" "$id" >/dev/null 2>&1
    # validate-problem.sh escreve run/validation/<id>.json, mas NÃO conhece o sumário do Painel.
    # Sem este upsert, o /problems/status (lê run/validation-summary.json) fica em "não validado"
    # p/ SEMPRE — o moj check (lê o json por-problema) diz validado e a web não. É o análogo do
    # tl_store_record→tl_summary_upsert; sem ele a validação era o único evento que não propagava.
    [[ -f "$RUNDIR/validation/$id.json" ]] && val_summary_upsert "$id" 2>/dev/null || true
  else
    MOJ_TL_STORE="$TL_STORE_DIR" MOJ_FORCE_PRIVATE="$fp" RUNDIR="$RUNDIR" \
    CONTESTSDIR="$CONTESTSDIR" MOJ_PROBLEMS_DIR="$MOJ_PROBLEMS_DIR" \
      bash "$MOJTOOLS_DIR/gen-problem-json.sh" "$pkg" "$id" >/dev/null 2>&1
  fi
  local jd="$CONTESTSDIR/treino/var/jsons/$id.json"
  local md="$CONTESTSDIR/treino/var/jsons-meta/$id.json"
  if [[ -f "$jd" ]]; then
    mkdir -p "${md%/*}" 2>/dev/null
    jq -c '{id, title, public, tags:(.tags // []), collections:(.collections // [])}' \
      "$jd" > "$md.tmp" 2>/dev/null && mv -f "$md.tmp" "$md" || rm -f "$md.tmp"
  else
    rm -f "$md" 2>/dev/null   # o gerador decidiu privado/inválido: sai da lista junto
  fi
  treino_list_dirty
}

# index_problem_bg <id> [validate=0|1] — index_problem_now DESTACADO em background (setsid;
# o filho re-source-a esta lib — os defaults `: "${VAR:=…}"` aceitam o env injetado).
index_problem_bg(){
  local id="$1" validate="${2:-0}" lib
  lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ( setsid env RUNDIR="$RUNDIR" TL_STORE_DIR="$TL_STORE_DIR" CONTESTSDIR="$CONTESTSDIR" \
       MOJ_PROBLEMS_DIR="$MOJ_PROBLEMS_DIR" MOJTOOLS_DIR="$MOJTOOLS_DIR" \
       bash -c 'source "$1/tl-store.sh" && index_problem_now "$2" "$3"' \
       _ "$lib" "$id" "$validate" >/dev/null 2>&1 & ) 2>/dev/null
}
