#!/usr/bin/env bash
# tl-class-backfill.sh [--apply] [-q]
# Carimba a CLASSE DE HARDWARE dos juízes (hosts[h].class) nos stores de TL que são de antes dela (26/10/2026).
# O claim põe no job o TL da classe (o máx entre os juízes idênticos — judge-gw/sched-lib.sh `_TLCLASS_DEF`), e ele
# só conhece os hosts carimbados. O tl-report carimba a partir de agora, e o re-report do boot de cada agente
# carimba o cache inteiro dele; isto serve p/ carimbar sem reiniciar os juízes.
# A classe vem do registro do juiz (`hwclass`, run/registry/<host>.json, register.sh). Host sem registro ou com
# registro de agente antigo (sem `hwclass`) fica sem classe. Host já carimbado não muda.
# Sem --apply é DRY-RUN: só conta e lista. Com --apply grava sob o lock do id (o mesmo do tl_store_record).
# Saída: TSV `id<TAB>host<TAB>classe` no stdout; resumo no stderr.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_DIR="$HERE/../api/v1"
source "$_DIR/lib/common.sh"; source "$_DIR/lib/tl-store.sh"
source "$_DIR/../../judge-gw/sched-lib.sh"
set +o noglob   # o prelúdio da API desliga o glob; a varredura precisa dele
APPLY=0; QUIET=0
while (( $# )); do
  case "$1" in
    --apply) APPLY=1;; -q) QUIET=1;;
    -h|--help) sed -n 2,11p "$0"; exit 0;;
    *) echo "opção desconhecida: $1" >&2; exit 2;;
  esac; shift
done
export SESSION_LOGIN="bin/tl-class-backfill"

# as classes do parque: {host: hwclass} dos registros (um jq só)
CLS="$(mktemp)"; trap 'rm -f "$CLS"' EXIT
{ for r in "$REGISTRYDIR"/*.json; do [[ -f "$r" ]] && cat "$r"; done; } \
  | jq -s -c 'map(select((.host // "") != "" and (.hwclass // "") != "") | {(.host): .hwclass}) | add // {}' > "$CLS" 2>/dev/null
[[ -s "$CLS" ]] || echo '{}' > "$CLS"

# _bf_one <id> : carimba os hosts sem classe do store (chamada sob o lock do id)
_bf_one(){
  local f tmp; f="$(tl_store_file "$1")"; tmp="$f.tmp.${BASHPID}"
  jq -c --slurpfile c "$CLS" '($c[0] // {}) as $cl
    | .hosts |= ((. // {}) | with_entries(if (.value.class // "") == "" and ($cl[.key] // "") != ""
                                          then .value.class = $cl[.key] else . end))' "$f" > "$tmp" 2>/dev/null \
    && [[ -s "$tmp" ]] && mv -f "$tmp" "$f" || { rm -f "$tmp"; return 1; }
}

nstore=0; nhost=0; nfix=0
for f in "$TL_STORE_DIR"/*.json; do
  [[ -f "$f" ]] || continue
  id="${f##*/}"; id="${id%.json}"
  valid_id "$id" || continue
  nstore=$((nstore+1))
  pend="$(jq -r --slurpfile c "$CLS" '($c[0] // {}) as $cl | (.hosts // {}) | to_entries[]
           | select((.value.class // "") == "" and ($cl[.key] // "") != "") | "\(.key)\t\($cl[.key])"' "$f" 2>/dev/null)"
  [[ -n "$pend" ]] || continue
  while IFS=$'\t' read -r h c; do printf '%s\t%s\t%s\n' "$id" "$h" "$c"; nhost=$((nhost+1)); done <<<"$pend"
  if (( APPLY )); then _tl_locked "$id" _bf_one "$id" && nfix=$((nfix+1)); fi
done
(( QUIET )) || echo "tl-class-backfill: $nstore store(s) · $nhost host(s) sem classe com registro$( (( APPLY )) && echo " · APLICADO em $nfix store(s)" || echo " · dry-run (use --apply)")" >&2
(( APPLY )) && audit_log "tl-class-backfill" "stores=$nstore hosts=$nhost aplicados=$nfix"
exit 0
