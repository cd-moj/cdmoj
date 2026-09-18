#!/bin/bash
# owner-rename.sh <login-antigo> <login-novo> [--apply]
# Conserta a POSSE que ficou no login antigo depois de uma troca de username feita ANTES de a cascata
# do rename levar a posse (lib/owner-rename.sh, 2026-09-18): dono de problema (.moj-meta.json + índice
# + overlay), de contest (contests/<c>/owner), de coleção e as permissões de criar contest.
# DRY-RUN por padrão: mostra o que aponta p/ o login antigo e sai. Com --apply, troca.
# Recusa se o login NOVO não existe no treino, ou se o ANTIGO ainda existe (aí não é rename: é outra conta).
# Em produção roda DENTRO do container:  podman exec systemd-moj-api bash /opt/moj/cdmoj/server/bin/owner-rename.sh …
set -u
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; _DIR="$HERE/../api/v1"; _LIBDIR="$_DIR/lib"
source "$_LIBDIR/sources.sh" >/dev/null 2>&1 || source "$_LIBDIR/common.sh"
source "$_LIBDIR/problems.sh"; source "$_LIBDIR/tl-store.sh" 2>/dev/null; source "$_LIBDIR/owner-rename.sh"
OLD="${1:-}"; NEW="${2:-}"; APPLY=0; [[ "${3:-}" == --apply ]] && APPLY=1
[[ -n "$OLD" && -n "$NEW" ]] || { echo "uso: $0 <login-antigo> <login-novo> [--apply]" >&2; exit 2; }
_or_ok "$OLD" "$NEW" || { echo "logins inválidos (ou iguais)" >&2; exit 2; }
[[ -d "$CONTESTSDIR/treino/users/$NEW" ]] || { echo "RECUSADO: a conta '$NEW' não existe no treino" >&2; exit 1; }
[[ -d "$CONTESTSDIR/treino/users/$OLD" ]] && { echo "RECUSADO: a conta '$OLD' AINDA existe — isto não é um rename; posse entre contas diferentes não se transfere por aqui" >&2; exit 1; }
echo "aponta p/ '$OLD' hoje:   $(owner_rename_report "$OLD")"
echo "aponta p/ '$NEW' hoje:   $(owner_rename_report "$NEW")"
(( APPLY )) || { echo "(dry-run — nada foi alterado; repita com --apply)"; exit 0; }
c="$(owner_rename_fast "$OLD" "$NEW")";  echo "índice/overlay/coleções/permissões trocados; contests: $c"
m="$(owner_rename_metas "$OLD" "$NEW" "$NEW")"; echo "metas de pacote reescritos e commitados: $m"
declare -F audit_log >/dev/null 2>&1 && SESSION_LOGIN="${SESSION_LOGIN:-owner-rename.sh}" audit_log "owner-rename" "from=$OLD to=$NEW contests=$c metas=$m (bin)"
echo "restou apontando p/ '$OLD': $(owner_rename_report "$OLD")"
