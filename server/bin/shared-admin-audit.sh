#!/bin/bash
# shared-admin-audit.sh [--apply] — antes/depois do CORTE DE PAPÉIS em contest compartilhado (28/09/2026).
#
# Num contest com USERS_FROM (usuários do Treino Livre) a senha pode ser conferida no treino; até o corte,
# QUALQUER conta de papel do treino (.admin/.judge/.staff…) entrava com esse papel em todo contest
# compartilhado. O corte (lib/auth.sh _shared_role_ok) deixa entrar pela fonte só o admin DONO
# (SHARED_ADMIN no conf, ou o derivado do `owner`) e os SUPERADMINS. Este script mostra, por contest:
#   • dono, o `.admin` do treino liberado e se ele existe;
#   • os `.admin` LOCAIS com senha (continuam valendo);
#   • se sobra ALGUM admin alcançável depois do corte (⚠ quando não);
#   • as sessões de PAPEL vivas que o corte derruba (conta do treino sem conta local e sem liberação).
# DRY-RUN por padrão. --apply grava SHARED_ADMIN=<derivado> onde o admin reusado é o do dono e ainda não
# está gravado (a derivação já vale sem isso; gravar tira a dependência do arquivo `owner`).
# Em produção roda DENTRO do container: podman exec systemd-moj-api bash /opt/moj/cdmoj/server/bin/shared-admin-audit.sh
set -u
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; _DIR="$HERE/../api/v1"; _LIBDIR="$_DIR/lib"
source "$_LIBDIR/sources.sh" >/dev/null 2>&1 || { source "$_LIBDIR/common.sh"; source "$_LIBDIR/auth.sh"; }
declare -F _shared_role_ok >/dev/null || source "$_LIBDIR/auth.sh"
declare -F cc_set_conf_var >/dev/null || source "$_LIBDIR/contest-create.sh"
APPLY=0; [[ "${1:-}" == --apply ]] && APPLY=1
: "${SESSIONDIR:?SESSIONDIR indefinido}"

n=0; bad=0
while IFS= read -r -d '' cf; do
  c="${cf%/conf}"; c="${c##*/}"
  src="$(_users_source "$c")"; [[ "$src" != "$c" ]] || continue
  n=$((n+1))
  owner=""; [[ -r "$CONTESTSDIR/$c/owner" ]] && IFS= read -r owner < "$CONTESTSDIR/$c/owner"
  sa="$(conf_value "$c" SHARED_ADMIN)"; lib="$(shared_admin_login "$c")"
  lib_src=nao; [[ -n "$lib" && -f "$CONTESTSDIR/$src/users/$lib/account.json" ]] && lib_src=sim
  locais=""
  while IFS= read -r -d '' a; do
    l="${a%/account.json}"; l="${l##*/}"
    [[ -n "$(jq -r '.password // empty' "$a" 2>/dev/null)" && "$(jq -r '.password // ""' "$a")" != '!'* ]] && locais+="$l "
  done < <(find "$CONTESTSDIR/$c/users" -mindepth 2 -maxdepth 2 -path '*.admin/account.json' -print0 2>/dev/null)
  alcanca=nao; { [[ -n "$locais" ]] || [[ "$lib_src" == sim ]]; } && alcanca=sim
  # sessões de papel vivas deste contest que o corte derruba
  cortadas=""
  while IFS= read -r s; do
    l="$(grep -m1 '^LOGIN=' "$s" 2>/dev/null)"; l="${l#LOGIN=}"; l="${l//\'/}"
    is_reserved_role_login "$l" || continue
    [[ -f "$CONTESTSDIR/$c/users/$l/account.json" ]] && continue
    _shared_role_ok "$c" "$l" || cortadas+="$l "
  done < <(find "$SESSIONDIR" -maxdepth 1 -type f -print0 2>/dev/null | xargs -0 -r grep -lxF -- "CONTEST=$c" 2>/dev/null)
  printf '%s\n  dono=%s  liberado_do_treino=%s (existe no treino: %s)%s\n  admins locais com senha: %s\n  admin alcançável depois do corte: %s\n  sessões de papel que o corte derruba: %s\n' \
    "$c" "${owner:-?}" "${lib:-?}" "$lib_src" "${sa:+  [SHARED_ADMIN gravado]}" "${locais:-nenhum}" "$alcanca" "${cortadas:-nenhuma}"
  if [[ "$alcanca" != sim ]]; then
    bad=$((bad+1))
    echo "  ⚠ SEM ADMIN depois do corte: crie um .admin LOCAL (Pessoas › Contas no painel de outro admin, ou"
    echo "    moj-contest -c $c users add ${lib:-<dono>.admin} --password …) antes do deploy do corte."
  fi
  if (( APPLY )) && [[ -z "$sa" && "$lib_src" == sim && -z "$locais" ]]; then
    cc_set_conf_var "$c" SHARED_ADMIN "$lib" && echo "  ✓ SHARED_ADMIN=$lib gravado"
  fi
done < <(find "$CONTESTSDIR" -mindepth 2 -maxdepth 2 -name conf -type f -print0 2>/dev/null)
echo "---"; echo "contests compartilhados: $n; sem admin alcançável: $bad"
(( APPLY )) || echo "(dry-run — nada foi alterado; --apply grava SHARED_ADMIN onde o admin do treino é o do dono)"
(( bad == 0 ))
