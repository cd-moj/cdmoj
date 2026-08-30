# GET /contest/round?contest=<c>&round=<slug>[&file=index.html]
# Serve o RELATÓRIO ARQUIVADO de uma rodada (o site estático do report-gen: placar, runs,
# enunciados, clarifications, estatística, tarefas do staff, infra). É a leitura de auditoria
# posterior — inclusive durante a prova oficial, se o admin publicou a rodada.
#
# ACESSO (cortado AQUI, nunca só na UI):
#   admin/juiz/juiz-chefe/staff/cstaff/monitor -> sempre
#   demais logins do contest                   -> só se a rodada estiver PUBLICADA (senão 404)
# O relatório já nasce sem código-fonte, sem log de juiz e sem senha (contrato de privacidade
# do report-gen.sh); o arquivo CRU é outro endpoint, só do admin (/contest/admin/round-archive).
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
source "$_DIR/lib/users.sh"; source "$_DIR/lib/contest-create.sh"
source "$_DIR/lib/contest-rounds.sh"

round="$(param round)"
rd_valid_slug "$round" || fail 400 "round inválido" "round_invalid"
r="$(rd_round "$contest" "$round")"
[[ -n "$r" ]] || fail 404 "Rodada não encontrada" "round_notfound"

priv=false
{ is_admin || is_judge || is_chief || is_staff || is_cstaff || is_mon; } && priv=true
if [[ "$priv" != true ]]; then
  jq -e '.state == "archived" and .published == true' <<<"$r" >/dev/null 2>&1 \
    || fail 404 "Rodada não disponível" "not_published"
fi

# path CONFINADO: só nome de arquivo/subdir simples, e o caminho resolvido tem de ficar dentro
# do diretório do relatório (nada de .. nem symlink apontando p/ fora).
rel="$(param file)"; [[ -n "$rel" ]] || rel=index.html
[[ "$rel" =~ ^[A-Za-z0-9._/-]+$ && "$rel" != *..* && "$rel" != /* ]] \
  || fail 400 "file inválido" "file_invalid"
base="$(rd_archive_dir "$contest" "$round")/relatorio"
[[ -d "$base" ]] || fail 404 "Relatório da rodada não gerado" "no_report"
file="$base/$rel"
real="$(readlink -f "$file" 2>/dev/null)"; rbase="$(readlink -f "$base" 2>/dev/null)"
{ [[ -n "$real" && -n "$rbase" && "$real" == "$rbase"/* && -f "$real" ]]; } \
  || fail 404 "Arquivo não encontrado" "file_notfound"

case "${rel##*.}" in
  html|htm) ct="text/html; charset=utf-8";;
  pdf)      ct="application/pdf";;
  css)      ct="text/css; charset=utf-8";;
  js)       ct="application/javascript; charset=utf-8";;
  json)     ct="application/json";;
  png)      ct="image/png";;
  webp)     ct="image/webp";;   # fotos/<login>.webp do relatório (R5, 2026-08-30)
  jpg|jpeg) ct="image/jpeg";;
  svg)      ct="image/svg+xml";;
  txt)      ct="text/plain; charset=utf-8";;
  *)        ct="application/octet-stream";;
esac
printf 'Status: 200 OK\r\n'
printf 'Content-Type: %s\r\n' "$ct"
printf 'Content-Length: %s\r\n' "$(stat -c%s "$real" 2>/dev/null || echo 0)"
printf '\r\n'
cat "$real"
