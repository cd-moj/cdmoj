# GET /problems/history?id=<id>[&limit=N][&sha=<sha>]   (Bearer)
# HISTÓRICO GIT do problema (cada problema é um repo git local; todo save/upload é um commit
# autorado pelo login — problem_commit). Sem `sha`: lista os commits (sha, epoch, autor,
# assunto, ±arquivos/inserções/remoções). Com `sha`: o `git show -p` daquele commit
# (diff_b64; limitado a ~400KB com flag truncated). Expõe conteúdo de soluções/testes ⇒
# gate de SOURCE: só MEMBRO da org (require_problem_edit; 404 senão).
require_method GET
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"

id="$(param id)"; [[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
repo="${id%%#*}"; prob="${id##*#}"; [[ "$prob" != "$id" ]] || fail 400 "Id sem '#'" "id_invalid"
require_problem_edit "$id"
pdir="$MOJ_PROBLEMS_DIR/$repo/$prob"
[[ -d "$pdir" ]] || fail 404 "Problema não encontrado" "not_found"

US=$'\x1f'   # separador de campos (assunto pode conter tab; \x1f não ocorre em texto normal)

sha="$(param sha)"
if [[ -n "$sha" ]]; then
  # ---- modo DIFF (git show -p de UM commit) ----
  # sha validado por REGEX antes de tocar o git (nunca começa com '-'; não vira flag)
  [[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || fail 400 "sha inválido" "sha_invalid"
  git -C "$pdir" cat-file -e "$sha^{commit}" 2>/dev/null || fail 404 "Commit não encontrado" "sha_unknown"
  meta="$(git -C "$pdir" log -1 --format='%H%x1f%at%x1f%an%x1f%s' "$sha" -- 2>/dev/null | tr -d '\r')"
  [[ -n "$meta" ]] || fail 404 "Commit não encontrado" "sha_unknown"
  # o diff vai p/ ARQUIVO e entra no jq por --rawfile (nunca por argv — ARG_MAX)
  df="$(mktemp)"; db="$(mktemp)"; trap 'rm -f "$df" "$df.full" "$db"' EXIT
  git -C "$pdir" show "$sha" -- > "$df.full" 2>/dev/null || : > "$df.full"
  head -c 400000 "$df.full" > "$df"
  truncated=false; [[ "$(wc -c < "$df.full")" -gt 400000 ]] && truncated=true
  base64 -w0 < "$df" > "$db"
  body="$(jq -cn --arg m "$meta" --rawfile d "$db" --argjson tr "$truncated" '
    ($m | split("\u001f")) as $f
    | {success:true, sha:($f[0] // ""), at:($f[1]|tonumber? // 0), author:($f[2] // ""),
       subject:($f[3] // ""), truncated:$tr, diff_b64:$d}')"
  [[ -n "$body" ]] || fail 500 "Falha ao montar o diff" "diff_fail"
  emit_json 200 OK; printf '%s' "$body"
  exit 0
fi

# ---- modo LISTA ----
limit="$(param limit)"; [[ "$limit" =~ ^[0-9]+$ ]] || limit=50; (( limit > 200 )) && limit=200
tsv="$(mktemp)"; trap 'rm -f "$tsv"' EXIT
# a linha de shortstat (opcional) vem DEPOIS de cada commit; o awk casa os pares. Separador US
# injetado por -v (mawk não entende \x1f em literais); commit sem mudança não emite shortstat.
git -C "$pdir" log --format='C%x1f%H%x1f%at%x1f%an%x1f%s' --shortstat -n "$limit" -- 2>/dev/null \
  | tr -d '\r' \
  | awk -v US="$US" '
      BEGIN { FS = US }
      function flush(){ if (sha != "") print sha US at US an US subj US f US ins US del }
      $1 == "C" { flush(); sha=$2; at=$3; an=$4; subj=$5; f=0; ins=0; del=0; next }
      /file[s]? changed/ {
        if (match($0, /[0-9]+ file/))      { f   = substr($0, RSTART, RLENGTH)+0 }
        if (match($0, /[0-9]+ insertion/)) { ins = substr($0, RSTART, RLENGTH)+0 }
        if (match($0, /[0-9]+ deletion/))  { del = substr($0, RSTART, RLENGTH)+0 }
      }
      END { flush() }' > "$tsv"
body="$(jq -R -s -c --arg id "$id" '
  {success:true, id:$id,
   commits: (split("\n") | map(select(length>0) | split("\u001f")
     | {sha:(.[0] // ""), at:(.[1]|tonumber? // 0), author:(.[2] // ""), subject:(.[3] // ""),
        files:(.[4]|tonumber? // 0), insertions:(.[5]|tonumber? // 0), deletions:(.[6]|tonumber? // 0)}))}' \
  < "$tsv" 2>/dev/null)"
[[ -n "$body" ]] || fail 500 "Falha ao montar o histórico" "history_fail"
emit_json 200 OK; printf '%s' "$body"
