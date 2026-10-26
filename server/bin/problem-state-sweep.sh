#!/usr/bin/env bash
# problem-state-sweep.sh [--apply] [-q]
# Limpa o estado de runtime de problema que FICOU ÓRFÃO (26/10/2026): até então o delete deixava run/tl/<id>.*,
# a chave do id nos sumários (tl/validação) e o run/calib/<id>/, e o move deixava o `.id` de dentro dos jsons
# movidos com o id antigo (o rebuild a frio dos sumários voltava a chavear pelo id velho). Os handlers novos não
# deixam mais (tl_state_drop/move, calib_state_drop/move, sched_calib_drop); isto conserta o que já existe.
#
# Órfão = o PACOTE não existe mais (pkg_path vazio) — não "fora do índice": problema privado não está no índice
# público. Coleta ids de run/tl, run/validation, run/calib, run/calib-sum, dos três sumários agregados, do carimbo
# fresco e das calibrações na fila. Também acusa `.id` que não bate com o nome do arquivo (tl e validação).
# Sem --apply é DRY-RUN: só conta e lista. Com --apply remove pelas MESMAS funções dos handlers e reescreve o `.id`.
# Saída: TSV `tipo<TAB>id<TAB>detalhe` no stdout; resumo no stderr.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_DIR="$HERE/../api/v1"
source "$_DIR/lib/common.sh"; source "$_DIR/lib/tl-store.sh"; source "$_DIR/lib/calib-expect.sh"
source "$_DIR/../../judge-gw/sched-lib.sh"
set +o noglob   # o prelúdio da API desliga o glob; a varredura precisa dele
APPLY=0; QUIET=0
while (( $# )); do
  case "$1" in
    --apply) APPLY=1;; -q) QUIET=1;;
    -h|--help) sed -n 2,13p "$0"; exit 0;;
    *) echo "opção desconhecida: $1" >&2; exit 2;;
  esac; shift
done
export SESSION_LOGIN="bin/problem-state-sweep"
: "${UPDATESDIR:=$RUNDIR/updates}"; : "${CMDDIR:=$RUNDIR/commands}"

declare -A IDS=()
add(){ [[ -n "$1" ]] && IDS["$1"]=1; return 0; }
for f in "$TL_STORE_DIR"/*.json "$TL_STORE_DIR"/*.cks "$TL_STORE_DIR"/*.pkv "$TL_STORE_DIR"/*.lock; do
  [[ -e "$f" ]] || continue; b="${f##*/}"; add "${b%.*}"
done
for f in "$VAL_STORE_DIR"/*.json "$CALX_SUM_DIR"/*.json; do [[ -e "$f" ]] || continue; b="${f##*/}"; add "${b%.json}"; done
for d in "$CALIB_DIR"/*/; do [[ -d "$d" ]] || continue; d="${d%/}"; add "${d##*/}"; done
for s in "$TL_SUMMARY" "$VAL_SUMMARY" "$CAL_SUMMARY" "$(tl_fresh_file)"; do
  [[ -s "$s" ]] || continue
  while IFS= read -r k; do add "$k"; done < <(jq -r 'keys[]?' "$s" 2>/dev/null)
done
while IFS= read -r k; do add "$k"; done < <(
  { find "$UPDATESDIR/pending" "$UPDATESDIR/inprogress" -name '*.json' -exec cat {} + 2>/dev/null
    find "$CMDDIR" -mindepth 2 -maxdepth 2 -name '*.json' -exec cat {} + 2>/dev/null; } \
  | jq -r 'select(.kind == "calibrate" or .action == "calibrate") | (.target // .id // empty)' 2>/dev/null)

norph=0; nid=0; nfix=0
for id in "${!IDS[@]}"; do
  valid_id "$id" || continue
  if [[ -z "$(pkg_path "$id")" ]]; then
    norph=$((norph+1))
    what=""
    [[ -e "$(tl_store_file "$id")" ]] && what+=" tl"
    [[ -e "$TL_STORE_DIR/$id.cks" || -e "$TL_STORE_DIR/$id.pkv" ]] && what+=" memo"
    [[ -e "$VAL_STORE_DIR/$id.json" ]] && what+=" validacao"
    [[ -d "$CALIB_DIR/$id" ]] && what+=" calib"
    [[ -e "$(calx_summary_file "$id")" ]] && what+=" calib-sum"
    printf 'orfao\t%s\t%s\n' "$id" "${what# }"
    if (( APPLY )); then
      tl_state_drop "$id"; calib_state_drop "$id"; sched_calib_drop "$id" inprogress >/dev/null
      rm -f "$TL_STORE_DIR/$id.lock" "$CALX_SUM_DIR/$id.lock" 2>/dev/null
    fi
    continue
  fi
  # `.id` de dentro × nome do arquivo (o move antigo não reescrevia)
  for f in "$(tl_store_file "$id")" "$VAL_STORE_DIR/$id.json"; do
    [[ -s "$f" ]] || continue
    in="$(jq -r '.id // empty' "$f" 2>/dev/null)"
    [[ -z "$in" || "$in" == "$id" ]] && continue
    nid=$((nid+1)); printf 'id-errado\t%s\t%s diz %s\n' "$id" "${f##*/}" "$in"
    if (( APPLY )); then
      t="$f.tmp.$$"
      jq -c --arg id "$id" '.id = $id' "$f" > "$t" 2>/dev/null && [[ -s "$t" ]] && mv -f "$t" "$f" && nfix=$((nfix+1)) || rm -f "$t"
      _summary_drop "$TL_SUMMARY" "$in"; _summary_drop "$VAL_SUMMARY" "$in"
      [[ "$f" == "$VAL_STORE_DIR/"* ]] && val_summary_upsert "$id" || tl_summary_upsert "$id"
    fi
  done
done
(( QUIET )) || echo "problem-state-sweep: ${#IDS[@]} id(s) com estado · $norph órfão(s) · $nid .id errado(s)$( (( APPLY )) && echo " · APLICADO ($nfix .id reescritos)" || echo " · dry-run (use --apply)")" >&2
(( APPLY )) && audit_log "problem-state-sweep" "ids=${#IDS[@]} orfaos=$norph id_errado=$nid"
exit 0
