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

# CACHE por (contest, privilegiado). Esta rota entra em TODO carregamento de página e era a
# mais cara do lote de boot (275 req/s contra ~900 das outras): o rd_sync_active relê o
# rounds.json, re-sourceia o conf e remonta a lista de problemas a cada chamada. Isso pesa
# porque o comportamento real do aluno na contagem regressiva é apertar F5, não esperar.
# Duas variantes só: quem pode gerir vê rodada arquivada NÃO publicada, os demais não —
# ignorar isso vazaria rodada não publicada, então a variante é obrigatória.
# Frescor por comparação com as ENTRADAS (`-nt`, builtin, sem processo): o conf (janela, ROUND,
# PROBS) e o rounds.json. Mais teto de idade curto p/ o que não é arquivo daqui.
RVAR=pub; [[ "$priv" == true ]] && RVAR=priv
RCD="$CONTESTSDIR/$contest/var"; RCF="$RCD/rounds-cache.$RVAR.json"
: "${ROUNDS_CACHE_TTL:=30}"
_rounds_fresh(){
  [[ -s "$RCF" ]] || return 1
  local f
  for f in "$CONTESTSDIR/$contest/conf" "$CONTESTSDIR/$contest/rounds.json"; do
    [[ -e "$f" && "$f" -nt "$RCF" ]] && return 1
  done
  [[ -n "$(find "$RCF" -newermt "-$ROUNDS_CACHE_TTL seconds" 2>/dev/null)" ]] || return 1
  return 0
}
if _rounds_fresh; then emit_json 200 OK; printf '%s' "$(<"$RCF")"; exit 0; fi

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
mkdir -p "$RCD" 2>/dev/null
printf '%s' "$body" > "$RCF.tmp.$$" 2>/dev/null && mv -f "$RCF.tmp.$$" "$RCF" 2>/dev/null || rm -f "$RCF.tmp.$$" 2>/dev/null
emit_json 200 OK; printf '%s' "$body"
