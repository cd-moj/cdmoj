# POST /contest/admin/jplag-run?contest=<id>  (admin) -> dispara o jplag em background.
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
# admin OU juiz-chefe disparam (pedido do Ribas, 2026-09-14); juiz comum só vê (jplag-results)
is_admin_or_chief || fail 403 "Apenas o admin ou o juiz-chefe" "admin_required"

runner="$_DIR/../../score/jplag-run.sh"
[[ -f "$runner" ]] || fail 500 "runner do jplag ausente" "runner_missing"
jdir="$CONTESTSDIR/$contest/jplag"; mkdir -p "$jdir"
# uma execução por vez: o runner segura jplag/.lock (flock) e apaga os r-*.json na largada —
# dois disparos colidiam. Lock preso = já está rodando: 429, sem mexer no status.
if [[ -e "$jdir/.lock" ]] && ! flock -n "$jdir/.lock" true 2>/dev/null; then
  fail 429 "O jplag já está rodando — espere terminar" "busy"
fi
jq -cn --argjson t "$EPOCHSECONDS" '{running:true, message:"enfileirado…", updated_at:$t}' > "$jdir/status.json" 2>/dev/null

# lança destacado (sobrevive ao fim da CGI). nohup ignora SIGHUP do fcgiwrap.
CONTESTSDIR="$CONTESTSDIR" JPLAG_JAR="${JPLAG_JAR:-}" nohup bash "$runner" "$contest" </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true
audit_log_to "$contest" jplag-run "started"
ok_json '{started:true}'
