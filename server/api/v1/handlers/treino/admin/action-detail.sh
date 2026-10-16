# GET /treino/admin/action-detail?f=<epoch>-<ação>-<pid>.json  (.admin do treino)
# O DETALHE de uma ação de vários alvos (lib/admin-bulk.sh): quem foi afetado e quem ficou de fora (e porquê). O
# audit leva só a linha curta com o nome deste arquivo; a aba Auditoria do painel abre o detalhe por aqui.
require_method GET
require_treino_admin
f="$(param f)"
[[ "$f" =~ ^[0-9]+-[a-z-]+-[0-9]+\.json$ ]] || fail 400 "Nome de detalhe inválido" "bad_name"
p="$CONTESTSDIR/treino/var/admin-actions/$f"
[[ -f "$p" ]] || fail 404 "Detalhe não encontrado" "notfound"
jq -e . "$p" >/dev/null 2>&1 || fail 500 "Detalhe ilegível" "bad_detail"
ok_json_slurp '{detail:$d[0]}' d "$(cat "$p")"
