# GET  /contest/admin/report-publish?contest=<c>   (admin DO contest)
#   -> {published, url, at, by, pages, bytes, job:{state,by,started,updated,error?}|null}
# POST {action:"publish"}   destaca score/report-publish.sh (setsid; ~100 s numa prova grande)
#                           -> {started:true, job:{state:"running",…}}; 409 se já há um rodando
# POST {action:"unpublish"} remove contests/<c>/relatorio/ + carimbo + REPORT_PUBLISHED (síncrono)
# POST {action:"publish-round"|"unpublish-round", round:"<slug>"}  rodada ARQUIVADA: liga/desliga o
#   symlink contests/<c>/relatorio-rodadas/<slug> → rounds/<slug>/relatorio (o nginx serve em
#   /relatorio/<c>/rodada/<slug>/); o GET lista `rounds:[{slug,name,kind,public,url}]` (só as
#   arquivadas com relatório). Independe do "publicada p/ os times" do rounds.json.
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

source "$_DIR/lib/users.sh"; source "$_DIR/lib/contest-create.sh"; source "$_DIR/lib/contest-rounds.sh"
_rounds_json(){   # rodadas ARQUIVADAS com relatório: pública = symlink existe (o portão do nginx)
  local rj sl nm kd pub
  rj="$(rd_get "$contest" 2>/dev/null)"; [[ -n "$rj" ]] || rj='{}'
  jq -r '(.rounds // [])[] | select(.state == "archived") | [.slug, (.name // .slug), (.kind // "")] | @tsv' <<<"$rj" 2>/dev/null \
  | while IFS=$'\t' read -r sl nm kd; do
      rd_valid_slug "$sl" || continue
      [[ -s "$CD/rounds/$sl/relatorio/index.html" ]] || continue
      pub=false; [[ -L "$CD/relatorio-rodadas/$sl" && -s "$CD/relatorio-rodadas/$sl/index.html" ]] && pub=true
      jq -cn --arg s "$sl" --arg n "$nm" --arg k "$kd" --argjson p "$pub" --arg u "/relatorio/$contest/rodada/$sl/" \
        '{slug:$s, name:$n, kind:$k, public:$p, url:$u}'
    done | jq -cs '.'
}
_pub_state(){
  local pub=false stamp job rounds
  [[ -s "$CD/relatorio/index.html" && -s "$STAMP" ]] && pub=true
  stamp="$(cat "$STAMP" 2>/dev/null)"; jq -e . >/dev/null 2>&1 <<<"$stamp" || stamp='{}'
  job="$(cat "$ST" 2>/dev/null)"; jq -e . >/dev/null 2>&1 <<<"$job" || job=null
  # job "running" cujo lock já soltou = processo morreu no meio (reboot): não fica preso
  if [[ "$(jq -r '.state // ""' <<<"$job")" == running ]]; then
    if ( exec 9>"$CD/var/.report.lock"; flock -n 9 ) 2>/dev/null; then
      job="$(jq -c '.state="error" | .error="geração interrompida"' <<<"$job")"
    fi
  fi
  rounds="$(_rounds_json)"; [[ -n "$rounds" ]] || rounds='[]'
  ok_json '{published:$p, url:$u, at:($s.at // null), by:($s.by // null), pages:($s.pages // null), bytes:($s.bytes // null), job:$j, rounds:$r}' \
    --argjson p "$pub" --arg u "/relatorio/$contest/" --argjson s "$stamp" --argjson j "$job" --argjson r "$rounds"
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
  publish-round|unpublish-round)
    slug="$(jq -r '.round // empty' <<<"$body" 2>/dev/null)"
    rd_valid_slug "$slug" || fail 400 "round inválido" "round_invalid"
    r="$(rd_round "$contest" "$slug")"; [[ -n "$r" ]] || fail 404 "Rodada não encontrada" "round_notfound"
    [[ "$(jq -r '.state' <<<"$r")" == archived ]] || fail 409 "só rodada arquivada tem relatório publicável" "not_archived"
    if [[ "$action" == publish-round ]]; then
      [[ -s "$CD/rounds/$slug/relatorio/index.html" ]] || fail 404 "Rodada sem relatório arquivado" "no_report"
      bash "$SCOREDIR/report-publish.sh" "$contest" "$SESSION_LOGIN" --round "$slug" >/dev/null 2>&1 || fail 500 "Falha ao publicar a rodada" "round_publish_failed"
      audit_log_to "$contest" report-publish-round "slug=$slug by=$SESSION_LOGIN"
    else
      bash "$SCOREDIR/report-publish.sh" "$contest" "$SESSION_LOGIN" --unround "$slug" >/dev/null 2>&1 || fail 500 "Falha ao despublicar a rodada" "round_unpublish_failed"
      audit_log_to "$contest" report-unpublish-round "slug=$slug by=$SESSION_LOGIN"
    fi
    _pub_state ;;
  *) fail 400 "action inválida (publish|unpublish|publish-round|unpublish-round)" "bad_action" ;;
esac
