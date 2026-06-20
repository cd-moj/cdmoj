# POST /admin/synctreino   (Bearer, admin)
# Dispara a sincronização do treino livre: grava um arquivo de comando no spool
# p/ o daemon consumir (substitui o /synctreino do mojinho-bot).
require_method POST
require_admin   # require_auth + checa .admin no login

AGORA="$EPOCHSECONDS"
ID="$(printf '%s%s%s' "$SESSION_LOGIN" "$AGORA" "$RANDOM" | md5sum | cut -d' ' -f1)"
mkdir -p "$SPOOLDIR"
spoolname="treino:$AGORA:$ID:$SESSION_LOGIN:synctreino:"
: > "$SPOOLDIR/$spoolname"

ok_json '{action:"synctreino", id:$id, status:"queued"}' --arg id "$ID"
