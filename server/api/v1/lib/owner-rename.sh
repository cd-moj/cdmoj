# lib/owner-rename.sh — A POSSE SEGUE O RENAME DA CONTA. (2026-09-18)
#
# A troca de username (treino/profile/username.sh) é um `mv` do diretório do usuário + uma CASCATA:
# orgs, sessões, inscrições, virtuais… Faltava a POSSE: o login também é gravado como DONO de problema
# (`.moj-meta.json .owner` ⇒ índice de donos + overlay), de CONTEST (`contests/<c>/owner`), de COLEÇÃO
# (`collections.json`) e nas permissões de criar contest (`contest-perms.json`). Relato do Daniel Saad:
# trocou `daniel.saad.admin` → `danielsaad.admin` e 201 problemas + 87 contests ficaram com o dono
# antigo — sumiram de "Meus" (que filtra por dono) e só apareciam no Painel (que vai pela org).
#
# ⚠ NÃO É SÓ COSMÉTICO: `owner` CONCEDE ACESSO (owners_visible, problems_denied_for — e por eles o gate
# do /submit do treino). Dono apontando p/ um login que deixou de existir é posse SOLTA: quem viesse a
# ter aquele login herdaria os privados. Com a posse seguindo o rename, nada fica para trás.
#
# Duas metades:
#   owner_rename_fast  <old> <new>          síncrono e barato — índice de donos, overlay, contests,
#                                           coleções, permissões. O efeito ("Meus", acesso) é IMEDIATO.
#   owner_rename_metas <old> <new> [login]  pesado — reescreve o `.moj-meta.json` de cada pacote e
#                                           commita (um git commit por problema). RETOMÁVEL: relê o meta
#                                           sob o lock do problema e pula o que já trocou. É o que torna
#                                           a troca DURÁVEL (o índice é regenerado a partir dos metas).
#   owner_rename_bg    <old> <new> [login]  a metade pesada destacada (molde do coll_bulk_retag_bg).
#   owner_rename_report <login>             só leitura: o que ainda aponta p/ o login (dry-run da bin/).
# Ferramenta p/ consertar o passado: server/bin/owner-rename.sh (dry-run por padrão).

declare -F write_meta >/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/problems.sh"
: "${CONTEST_PERMS:=$CONTESTSDIR/treino/var/contest-perms.json}"

_or_ok(){ [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._@+-]{0,63}$ && "$2" =~ ^[A-Za-z0-9][A-Za-z0-9._@+-]{0,63}$ && "$1" != "$2" ]]; }
# _or_json_edit <arquivo> <programa-jq> — reescreve um JSON (stdin, nunca argv) com $o/$n; atômico
_or_json_edit(){
  local f="$1" prog="$2" t; [[ -s "$f" ]] || return 0
  grep -qF "\"$OR_OLD\"" "$f" 2>/dev/null || return 0          # nada a fazer: não toca no arquivo (mtime)
  t="$f.tmp.$BASHPID"
  ( flock -w 10 9 2>/dev/null
    jq --arg o "$OR_OLD" --arg n "$OR_NEW" "$prog" < "$f" > "$t" 2>/dev/null && [[ -s "$t" ]] \
      && jq -e . "$t" >/dev/null 2>&1 && mv -f "$t" "$f" || rm -f "$t"
  ) 9>"$f.orlock"
  rm -f "$f.orlock" 2>/dev/null
}

owner_rename_fast(){
  local OR_OLD="$1" OR_NEW="$2" of n=0; _or_ok "$OR_OLD" "$OR_NEW" || return 1
  # índice de donos e overlay: dono e colaborador (o índice será regenerado dos metas; o patch é p/ valer JÁ)
  _or_json_edit "$OWNERS_INDEX" '.problems |= map((if .owner == $o then .owner = $n else . end)
      | (if ((.collaborators // [])|index($o)) != null then .collaborators = ((.collaborators|map(if . == $o then $n else . end))|unique) else . end))'
  _or_json_edit "$AUTHORED_INDEX" 'map_values((if .owner == $o then .owner = $n else . end)
      | (if ((.collaborators // [])|index($o)) != null then .collaborators = ((.collaborators|map(if . == $o then $n else . end))|unique) else . end))'
  # coleções: dono e criador
  _or_json_edit "$COLL_REGISTRY" 'map_values((if .owner == $o then .owner = $n else . end) | (if .created_by == $o then .created_by = $n else . end))'
  # quem pode criar contest: listas + a trilha (chave = login; `by` = quem liberou)
  _or_json_edit "$CONTEST_PERMS" '
      def ren: map(if . == $o then $n else . end) | unique;
      def renk: with_entries((if .key == $o then .key = $n else . end) | (if (.value|type) == "object" and .value.by == $o then .value.by = $n else . end));
      (if has("allow") then .allow |= ren else . end) | (if has("deny") then .deny |= ren else . end)
      | (if has("allow_meta") then .allow_meta |= renk else . end) | (if has("deny_meta") then .deny_meta |= renk else . end)'
  # contests: o arquivo `owner` (1ª linha = login). `find`, não glob — a API roda noglob.
  while IFS= read -r -d '' of; do
    [[ "$(head -1 "$of" 2>/dev/null)" == "$OR_OLD" ]] || continue
    printf '%s\n' "$OR_NEW" > "$of.tmp.$BASHPID" && mv -f "$of.tmp.$BASHPID" "$of" && n=$((n+1))
  done < <(find "$CONTESTSDIR" -mindepth 2 -maxdepth 2 -name owner -type f -print0 2>/dev/null)
  declare -F treino_list_dirty >/dev/null && treino_list_dirty
  printf '%s' "$n"
}

# metas: um pacote por vez, sob o MESMO lock por-problema do problem_commit (não aninhar o commit no lock)
owner_rename_metas(){
  local OR_OLD="$1" OR_NEW="$2" login="${3:-$2}" meta pdir org lk rc n=0; _or_ok "$OR_OLD" "$OR_NEW" || return 1
  while IFS= read -r -d '' meta; do
    grep -qF "\"$OR_OLD\"" "$meta" 2>/dev/null || continue
    pdir="${meta%/.moj-meta.json}"; org="${pdir%/*}"; org="${org##*/}"
    mkdir -p "${RUNDIR:-/home/ribas/moj/run}/locks" 2>/dev/null
    lk="${RUNDIR:-/home/ribas/moj/run}/locks/$(printf '%s' "$pdir" | md5sum 2>/dev/null | cut -c1-24).lock"
    rc=0
    ( flock 9 2>/dev/null
      [[ "$(jq -r '.owner // empty' "$meta" 2>/dev/null)" == "$OR_OLD" ]] || exit 3     # já trocado (retomada)
      write_meta "$pdir" "$OR_NEW" "$org"
    ) 9>"$lk" || rc=$?
    [[ $rc -eq 0 ]] || continue
    problem_commit "$pdir" "$login" "dono: $OR_OLD -> $OR_NEW (troca de username)" >/dev/null 2>&1
    n=$((n+1))
  done < <(find "$MOJ_PROBLEMS_DIR" -mindepth 3 -maxdepth 3 -name .moj-meta.json -print0 2>/dev/null)
  printf '%s' "$n"
}

owner_rename_bg(){
  local lib; lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; _or_ok "$1" "$2" || return 1
  if [[ "${MOJ_JOBS_SYNC:-0}" == 1 ]]; then owner_rename_metas "$1" "$2" "${3:-$2}" >/dev/null; return 0; fi
  # redirects no SETSID (não dentro do bash -c): senão o filho herda o socket do CGI e o cliente espera
  ( setsid env RUNDIR="$RUNDIR" CONTESTSDIR="$CONTESTSDIR" MOJ_PROBLEMS_DIR="$MOJ_PROBLEMS_DIR" MOJTOOLS_DIR="${MOJTOOLS_DIR:-}" \
      bash -c 'source "$1/common.sh" 2>/dev/null; source "$1/problems.sh" && source "$1/owner-rename.sh"
               n="$(owner_rename_metas "$2" "$3" "$4")"
               declare -F audit_log >/dev/null 2>&1 && audit_log "owner-rename-done" "from=$2 to=$3 metas=$n"' \
      _ "$lib" "$1" "$2" "${3:-$2}" </dev/null >/dev/null 2>&1 & ) 2>/dev/null
  return 0
}

# só leitura: o que AINDA aponta p/ <login> — {problems_index, problems_meta, contests, collections, perms}
owner_rename_report(){
  local l="$1" pi pm c co pe
  pi="$(jq --arg o "$l" '[.problems[]|select(.owner==$o or (((.collaborators//[])|index($o))!=null))]|length' "$OWNERS_INDEX" 2>/dev/null)"
  pm="$(find "$MOJ_PROBLEMS_DIR" -mindepth 3 -maxdepth 3 -name .moj-meta.json -print0 2>/dev/null | xargs -0 -r grep -lF "\"$l\"" 2>/dev/null | wc -l)"
  c="$(find "$CONTESTSDIR" -mindepth 2 -maxdepth 2 -name owner -type f -print0 2>/dev/null | xargs -0 -r grep -lx -- "$l" 2>/dev/null | wc -l)"
  co="$(jq --arg o "$l" '[to_entries[]|select(.value.owner==$o or .value.created_by==$o)]|length' "$COLL_REGISTRY" 2>/dev/null)"
  pe="$(grep -cF "\"$l\"" "$CONTEST_PERMS" 2>/dev/null)"
  jq -cn --arg l "$l" --argjson pi "${pi:-0}" --argjson pm "${pm:-0}" --argjson c "${c:-0}" --argjson co "${co:-0}" --argjson pe "${pe:-0}" \
    '{login:$l, problems_index:$pi, problems_meta:$pm, contests:$c, collections:$co, perms_lines:$pe}'
}
