# GET /contest/rounds?contest=<c>   (Bearer)
# Rodadas do contest que ESTE login pode ver: a ativa (nome/janela, p/ o front avisar "aquecimento")
# e as ARQUIVADAS que estão publicadas — papel privilegiado vê todas as arquivadas.
# O conteúdo em si sai por /contest/round (site estático do relatório da rodada).
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
source "$_DIR/lib/users.sh"; source "$_DIR/lib/contest-create.sh"
source "$_DIR/lib/contest-rounds.sh"

priv=false
{ is_admin || is_judge || is_chief || is_staff || is_cstaff || is_mon; } && priv=true

j="$(rd_sync_active "$contest")"; [[ -n "$j" ]] || fail 500 "Falha ao ler as rodadas" "rounds_read"
body="$(jq -cn --argjson j "$j" --argjson priv "$priv" '
  ($j.rounds // []) as $R
  | {success:true, active:($j.active // ""), can_manage:$priv,
     rounds: [ $R[]
       | select(.state == "active" or (.state == "archived" and ($priv or (.published == true))))
       | {slug, name, kind, state, start, end,
          published:(.published // false), stats:(.stats // null),
          has_report:(.state == "archived")} ]}')"
[[ -n "$body" ]] || fail 500 "Falha ao montar a resposta" "build_fail"
emit_json 200 OK; printf '%s\n' "$body"
