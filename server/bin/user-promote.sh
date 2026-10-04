#!/bin/bash
# user-promote.sh <login> <login-com-papel> [--apply] [--message-file <arq-html>]
# PROMOVE uma conta do treino a um PAPEL (ex.: idlechara → idlechara.admin). O papel vem do SUFIXO do login, e a
# troca pelo próprio usuário (/treino/profile/username) proíbe ganhar sufixo de propósito (escalação) — então
# promover é ato do admin da plataforma, por aqui. É a MESMA cascata da troca de login (lib/rename-cascade.sh):
# conta, Telegram, orgs, inscrições, contests compartilhados, virtuais, posse (problemas, contests, coleções,
# permissão de criar contest) e as sessões abertas (seguem logadas, já com o papel). A senha não muda; a troca
# NÃO conta no limite anual do usuário; fica no audit do treino (`user-promote`) e em `.promoted` na conta.
# DRY-RUN por padrão (diz o que mudaria). --message-file: depois de promover, manda o arquivo (HTML do Telegram)
# por DM do mojinho ao Telegram VINCULADO à conta (fila de alertas, alert_dm) — sem vínculo, avisa e não manda.
# Recusa: conta inexistente, login novo já existe, novo sem sufixo de papel ou igual ao velho, ou submissão
# pendente (no treino ou num contest compartilhado). Primeiro caso: Eri (TCP 2026), 04/10/2026.
# Em produção (rodando o checkout do HOST, sem imagem nova — owner-rename síncrono, o container é descartável):
#   podman run --rm --entrypoint bash -e MOJ_JOBS_SYNC=1 -v /home/moj/moj/cdmoj:/src:ro,z \
#     -v /home/moj/moj/contests:/data/contests:z -v /home/moj/moj/run:/data/run:z \
#     -v /home/moj/moj/moj-problems:/data/moj-problems:z localhost/moj-server:prod /src/server/bin/user-promote.sh …
set -u
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; _DIR="$HERE/../api/v1"; _LIBDIR="$_DIR/lib"
source "$_LIBDIR/sources.sh" >/dev/null 2>&1 || { source "$_LIBDIR/common.sh"; source "$_LIBDIR/auth.sh"; source "$_LIBDIR/users.sh"; }
source "$_LIBDIR/telegram.sh" 2>/dev/null; source "$_LIBDIR/alerts.sh" 2>/dev/null
source "$_LIBDIR/rename-cascade.sh"
set +o noglob
OLD=""; NEW=""; APPLY=0; MSG=""
while (( $# )); do
  case "$1" in
    --apply) APPLY=1;; --message-file) MSG="${2:-}"; shift;;
    -h|--help) sed -n 2,17p "$0"; exit 0;;
    -*) echo "opção desconhecida: $1" >&2; exit 2;;
    *) if [[ -z "$OLD" ]]; then OLD="$1"; elif [[ -z "$NEW" ]]; then NEW="$1"; else echo "argumento a mais: $1" >&2; exit 2; fi;;
  esac; shift
done
[[ -n "$OLD" && -n "$NEW" ]] || { echo "uso: $0 <login> <login-com-papel> [--apply] [--message-file <arq>]" >&2; exit 2; }
_role(){ case "$1" in *.admin) echo admin;; *.cjudge) echo cjudge;; *.judge) echo judge;; *.cstaff) echo cstaff;;
  *.staff) echo staff;; *.mon) echo mon;; *.animeitor) echo animeitor;; *) echo "";; esac; }
[[ "$NEW" =~ ^[A-Za-z0-9._-]{2,40}$ ]] && valid_id "$NEW" || { echo "RECUSADO: login novo inválido: $NEW" >&2; exit 2; }
[[ -n "$(_role "$NEW")" ]] || { echo "RECUSADO: '$NEW' não tem sufixo de papel (.admin, .judge, …) — troca comum de handle é pelo perfil" >&2; exit 2; }
[[ "$(_role "$NEW")" != "$(_role "$OLD")" ]] || { echo "RECUSADO: '$OLD' já tem o papel $(_role "$OLD")" >&2; exit 2; }
user_exists treino "$OLD" || { echo "RECUSADO: a conta '$OLD' não existe no treino" >&2; exit 1; }
user_exists treino "$NEW" && { echo "RECUSADO: '$NEW' já existe no treino" >&2; exit 1; }
if [[ -n "$MSG" ]]; then [[ -s "$MSG" ]] || { echo "RECUSADO: --message-file vazio ou inexistente: $MSG" >&2; exit 2; }; fi

tg="$(tg_id_of_login treino "$OLD" 2>/dev/null)"
echo "conta:     $OLD → $NEW  ($(account_field treino "$OLD" '.fullname // ""'))"
echo "telegram:  ${tg:-SEM vínculo}"
echo "posse:     $(owner_rename_report "$OLD" 2>/dev/null)"
(( APPLY )) || { echo "(dry-run — nada foi alterado; repita com --apply)"; exit 0; }

T="$CONTESTSDIR/treino"; mkdir -p "$T/var"
exec 9>"$T/var/profile.lock" || { echo "sem lock" >&2; exit 1; }
flock -w 30 9 || { echo "RECUSADO: o lock de perfil está ocupado" >&2; exit 1; }
user_exists treino "$NEW" && { echo "RECUSADO: '$NEW' já existe no treino" >&2; exit 1; }
hf="$(user_hist_file treino "$OLD")"
if { [[ -f "$hf" ]] && grep -qE ':(Not Answered Yet|[Oo]n queue|[Rr]unning):' "$hf"; } || shared_pending_for treino "$OLD"; then
  echo "RECUSADO: '$OLD' tem submissão pendente de julgamento — espere o veredicto" >&2; exit 1
fi
nsess="$(treino_rename_cascade "$OLD" "$NEW")" || { echo "FALHOU: o mv da conta não aconteceu (nada mudou)" >&2; exit 1; }
account_merge treino "$NEW" '.promoted = ((.promoted // []) + [{at:$t, from:$o, by:"bin/user-promote"}])' \
  --argjson t "$EPOCHSECONDS" --arg o "$OLD"
flock -u 9
SESSION_LOGIN="bin/user-promote" audit_log_to treino user-promote "from=$OLD to=$NEW sessions=${nsess:-0}"
echo "promovido: $NEW  (sessões que seguiram: ${nsess:-0})"
echo "restou apontando p/ '$OLD': $(owner_rename_report "$OLD" 2>/dev/null)"
if [[ -n "$MSG" ]]; then
  tg="$(tg_id_of_login treino "$NEW" 2>/dev/null)"
  if [[ -z "$tg" ]]; then echo "AVISO: '$NEW' sem Telegram vinculado — a mensagem NÃO foi enviada" >&2; exit 3; fi
  id="$(alert_dm "$(cat "$MSG")" "$tg")" || { echo "AVISO: não consegui pôr a mensagem na fila do mojinho" >&2; exit 3; }
  SESSION_LOGIN="bin/user-promote" audit_log_to treino user-promote-dm "to=$NEW outbox=$id"
  echo "mensagem na fila do mojinho: $id (Telegram $tg)"
fi
