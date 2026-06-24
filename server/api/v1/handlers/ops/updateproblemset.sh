# POST /ops/updateproblemset   (Bearer, admin)   body: {repo} | {repo, all:true}
# Modelo cache: NÃO clona nada nos juízes. Atualiza o store do servidor (git pull
# best-effort, se for um checkout) e enfileira CALIBRAÇÃO p/ os problemas NOVOS ou
# ALTERADOS — aqueles cujo checksum (arquivos que afetam o TL) difere do TL já guardado.
# Cada juiz livre baixa o pacote, calibra e reporta o TL via /judge/tl-report.
# {all:true} recalibra TODOS os problemas do diretório.
require_method POST
require_admin
source "$_DIR/../../judge-gw/sched-lib.sh"
source "$_DIR/lib/tl-store.sh"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
repo="$(jq -r '.repo // empty' <<<"$body")"
[[ -n "$repo" ]] || fail 400 "Missing repo" "repo_missing"
[[ "$repo" =~ ^[a-z0-9][a-z0-9._-]{1,63}$ ]] || fail 400 "repo inválido" "repo_invalid"
all="$(jq -r 'if .all==true then 1 else 0 end' <<<"$body")"
repodir="$MOJ_PROBLEMS_DIR/$repo"
[[ -d "$repodir" ]] || fail 404 "Diretório não existe no store do servidor" "repo_missing"

# store do servidor fresco (o juiz não clona mais). Best-effort: se houver remote/chave.
[[ -d "$repodir/.git" ]] && ( cd "$repodir" && git pull --recurse-submodules ) >/dev/null 2>&1 || true

queued=0; skipped=0
while IFS= read -r pdir; do
  prob="$(basename "$pdir")"; id="$repo#$prob"
  [[ -f "$pdir/conf" || -d "$pdir/tests" ]] || continue      # só diretórios de problema
  cur="$(pkg_tl_checksum "$pdir")"; [[ -n "$cur" ]] || { skipped=$((skipped+1)); continue; }
  if [[ "$all" != 1 ]]; then
    stored="$(jq -r '.checksum // ""' "$(tl_store_file "$id")" 2>/dev/null)"
    [[ "$stored" == "$cur" ]] && { skipped=$((skipped+1)); continue; }   # já calibrado p/ esta versão
  fi
  cal_request "$repo" "$id" "$SESSION_LOGIN" >/dev/null; queued=$((queued+1))
done < <(find "$repodir" -mindepth 1 -maxdepth 1 -type d -not -name '.*' 2>/dev/null | sort)

audit_log "updateproblemset" "repo=$repo queued=$queued skipped=$skipped all=$all"
ok_json '{action:"updateproblemset", repo:$r, queued:$q, skipped:$s, status:"queued"}' \
  --arg r "$repo" --argjson q "$queued" --argjson s "$skipped"
