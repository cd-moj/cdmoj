# POST /admin/synctreino   (Bearer, SUPER-ADMIN do treino)
# Dispara a sincronização do treino livre: grava um arquivo de comando no spool
# p/ o daemon consumir (substitui o /synctreino do mojinho-bot).
require_method POST
# AÇÃO DE PLATAFORMA (re-sync do acervo do treino INTEIRO): mesma classe/nível das /ops de escrita
# (judge-cache, judge-reset, calib-cancel, updateproblemset) — `require_treino_superadmin`.
require_treino_superadmin

AGORA="$EPOCHSECONDS"
ID="$(printf '%s%s%s' "$SESSION_LOGIN" "$AGORA" "$RANDOM" | md5sum | cut -d' ' -f1)"
mkdir -p "$SPOOLDIR"
spoolname="treino:$AGORA:$ID:$SESSION_LOGIN:synctreino:"
: > "$SPOOLDIR/$spoolname"

ok_json '{action:"synctreino", id:$id, status:"queued"}' --arg id "$ID"
