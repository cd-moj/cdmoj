# GET /submission/log?contest=<id>&id=<hash>[&time=<epoch>]   (Bearer) -> HTML
# Report do julgamento (report.html auto-contido), localizado pelo HASH
# (mojlog/*<hash>*). Se não houver report (ex.: submissão mock), responde uma nota
# amigável. Visível se dono/admin/judge/SHOWCODE.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

sid="$(param id)"
[[ -n "$sid" ]] || fail 400 "Missing submission id" "id_missing"
[[ "$sid" =~ ^[0-9a-f]{32}$ || "$sid" =~ ^[0-9a-f-]{36}$ ]] \
  || fail 400 "Invalid submission id" "id_invalid"

set +o noglob; shopt -s nullglob
resolve_submission "$contest" "$sid"     # store-v2 ou legado
owner="$SUB_OWNER"
SHOWCODE=0
load_contest_conf "$contest"
# juiz/admin sempre veem; dono vê conforme o SHOWLOG efetivo (showlog_effective em
# lib/verdict.sh: explícito manda; ausente = oculto em modo icpc — o report expõe os testes).
if ! is_judge; then
  if [[ -n "$owner" && "$owner" != "$SESSION_LOGIN" && "${SHOWCODE:-0}" != 1 ]]; then
    shopt -u nullglob; fail 403 "Log not visible" "log_forbidden"
  fi
  if [[ "$(showlog_effective "$contest")" == 0 ]]; then
    shopt -u nullglob; fail 403 "Log oculto pelo admin do contest" "log_hidden"
  fi
fi

shopt -u nullglob
activity_log log-view "c=$contest sid=$sid owner=${owner:-?}"
# mojlog em repouso é .html.gz (2026-09-16): com Accept-Encoding gzip vai como está (o nginx não
# recomprime resposta que já traz Content-Encoding — molde de contest/problems.sh); sem Accept,
# descomprime. Report ausente com results/<id>.json presente = removido pela política de retenção.
if [[ -n "$SUB_LOG" && -f "$SUB_LOG" ]]; then
  if [[ "$SUB_LOG" == *.gz ]]; then
    if [[ "${HTTP_ACCEPT_ENCODING:-}" == *gzip* ]]; then
      printf 'Status: 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Encoding: gzip\r\nVary: Accept-Encoding\r\n\r\n'
      cat "$SUB_LOG"
    else emit_html; gzip -dc "$SUB_LOG"; fi
  else emit_html; cat "$SUB_LOG"; fi
else
  emit_html
  if [[ -n "$SUB_RESULT" && -f "$SUB_RESULT" ]]; then
    printf '<!doctype html><meta charset="utf-8"><p style="font:16px sans-serif;color:#64748b;padding:1rem">Report removido pela política de retenção do MOJ; o veredicto e o código-fonte continuam disponíveis. / Report removed by the MOJ retention policy; the verdict and the source code remain available.</p>\n'
  else
    printf '<!doctype html><meta charset="utf-8"><p style="font:16px sans-serif;color:#64748b;padding:1rem">Report indisponível para esta submissão. / Report unavailable for this submission.</p>\n'
  fi
fi
