# GET  /contest/admin/report-publish?contest=<c>   (admin DO contest)
#   -> {published, url, at, by, pages, bytes, job:{state,by,started,updated,error?}|null}
# POST {action:"publish"}   destaca score/report-publish.sh (setsid; ~100 s numa prova grande)
#                           -> {started:true, job:{state:"running",…}}; 409 se já há um rodando
# POST {action:"unpublish"} remove contests/<c>/relatorio/ + carimbo + REPORT_PUBLISHED (síncrono)
#
# PUBLICAR = deixar o relatório estático (o MESMO tar.gz do /contest/admin/report) acessível a
# qualquer pessoa em /relatorio/<c>/ (nginx serve contests/<c>/relatorio/ por alias) e listado
# na home e no /contests/ (report_url) — o histórico do evento. É ato explícito do admin: o
# relatório nasce sem código-fonte, sem log de juiz, sem senha, mas mostra nomes de times, runs
# e clarifications anônimas — publique quando "tudo foi publicado". MOJ_JOBS_SYNC=1 (testes)
# roda o job inline em vez de destacar.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
CD="$CONTESTSDIR/$contest"; STAMP="$CD/var/report-published.json"; ST="$CD/var/report-publish.status.json"

_pub_state(){
  local pub=false stamp job
  [[ -s "$CD/relatorio/index.html" && -s "$STAMP" ]] && pub=true
  stamp="$(cat "$STAMP" 2>/dev/null)"; jq -e . >/dev/null 2>&1 <<<"$stamp" || stamp='{}'
  job="$(cat "$ST" 2>/dev/null)"; jq -e . >/dev/null 2>&1 <<<"$job" || job=null
  # job "running" cujo lock já soltou = processo morreu no meio (reboot): não fica preso
  if [[ "$(jq -r '.state // ""' <<<"$job")" == running ]]; then
    if ( exec 9>"$CD/var/.report.lock"; flock -n 9 ) 2>/dev/null; then
      job="$(jq -c '.state="error" | .error="geração interrompida"' <<<"$job")"
    fi
  fi
  ok_json '{published:$p, url:$u, at:($s.at // null), by:($s.by // null), pages:($s.pages // null), bytes:($s.bytes // null), job:$j}' \
    --argjson p "$pub" --arg u "/relatorio/$contest/" --argjson s "$stamp" --argjson j "$job"
}

if [[ "$REQUEST_METHOD" == GET ]]; then _pub_state; exit 0; fi
require_method POST
body="$(read_body)"; action="$(jq -r '.action // empty' <<<"$body" 2>/dev/null)"
case "$action" in
  publish)
    if [[ -s "$ST" && "$(jq -r '.state // ""' "$ST" 2>/dev/null)" == running ]] \
       && ! ( exec 9>"$CD/var/.report.lock"; flock -n 9 ) 2>/dev/null; then
      fail 409 "Relatório já está sendo gerado" "busy"
    fi
    # balões em dia ANTES do snapshot (mesma reconciliação preguiçosa do download tar.gz)
    source "$_LIBDIR/print.sh"; pr_reconcile_balloons "$contest" || true
    audit_log_to "$contest" report-publish "start by=$SESSION_LOGIN"
    if [[ "${MOJ_JOBS_SYNC:-}" == 1 ]]; then
      bash "$SCOREDIR/report-publish.sh" "$contest" "$SESSION_LOGIN" >/dev/null 2>&1 || true
    else
      # fds dentro do parêntese (lição do setsid sob CGI): o filho não pode herdar o socket
      ( setsid bash -c 'bash "$1" "$2" "$3"' _ "$SCOREDIR/report-publish.sh" "$contest" "$SESSION_LOGIN" \
          </dev/null >/dev/null 2>&1 & ) 2>/dev/null
      sleep 0.2
    fi
    _pub_state ;;
  unpublish)
    bash "$SCOREDIR/report-publish.sh" "$contest" "$SESSION_LOGIN" --unpublish >/dev/null 2>&1 \
      || fail 500 "Falha ao despublicar" "unpublish_failed"
    audit_log_to "$contest" report-unpublish "by=$SESSION_LOGIN"
    _pub_state ;;
  *) fail 400 "action inválida (publish|unpublish)" "bad_action" ;;
esac
