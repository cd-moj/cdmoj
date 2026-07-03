# GET /treino/contest-create/mine  (auth treino, pode criar) -> contests CRIADOS POR MIM
# (owner == login; exige created-by = criado pela interface). Admin do treino tem a lista
# completa em /treino/admin/contests — aqui é só o recorte do criador (duplicar/exportar).
require_method GET
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
set +o noglob; shopt -s nullglob
arr=()
for d in "$CONTESTSDIR"/*/created-by; do
  cdir="${d%/created-by}"; cid="${cdir##*/}"
  owner="$(head -1 "$cdir/owner" 2>/dev/null)"
  [[ -n "$owner" && "$owner" == "$SESSION_LOGIN" ]] || continue
  IFS=$'\t' read -r _o at _m < "$d" 2>/dev/null; [[ "$at" =~ ^[0-9]+$ ]] || at=0
  line="$(
    CONTEST_NAME=""; CONTEST_TYPE=""; CONTEST_START=0; CONTEST_END=0; PROBS=()
    . "$cdir/conf" 2>/dev/null
    jq -cn --arg id "$cid" --arg nm "${CONTEST_NAME:-$cid}" --arg m "${CONTEST_TYPE:-}" \
       --argjson at "$at" --argjson st "${CONTEST_START:-0}" --argjson en "${CONTEST_END:-0}" \
       --argjson np "$(( ${#PROBS[@]} / 5 ))" \
       '{id:$id, name:$nm, mode:$m, created_at:$at, start:$st, end:$en, problems_count:$np}'
  )"
  [[ -n "$line" ]] && arr+=("$line")
done
shopt -u nullglob
list='[]'
((${#arr[@]})) && list="$(printf '%s\n' "${arr[@]}" | jq -cs 'sort_by(-.created_at)')"
ok_json '{contests:$l, total:($l|length)}' --argjson l "$list"
