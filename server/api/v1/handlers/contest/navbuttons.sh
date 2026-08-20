# GET /contest/navbuttons?contest=<id>   (Bearer)
# Botões de navegação por papel (substring no login). URLs em caminhos completos
# (/contest/...); '/' e '/logout' são especiais (ver shared/contest-shell.js navHref).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
source "$_LIBDIR/print.sh"

# CACHE POR PAPEL: os botões mudam por PAPEL (telão, chefe de sede, staff, admin, chefe, juiz,
# monitor, competidor) e por mais nada de pessoal. A variante é regra de segurança — servir a nav
# de um admin a um competidor mostraria caminhos que ele não deve nem saber que existem.
# A CADEIA ABAIXO DEFINE OS DOIS (rótulo do cache e corpo) na MESMA ordem, de propósito: papel
# resolvido num lugar e corpo montado noutro é como as duas listas nascem divergentes.
source "$_LIBDIR/contest-gate.sh"
if   is_animeitor; then NBROLE=animeitor
elif is_cstaff;    then NBROLE=cstaff
elif is_staff;     then NBROLE=staff
elif is_admin;     then NBROLE=admin
elif is_chief;     then NBROLE=chief
elif is_judge;     then NBROLE=judge
elif is_mon;       then NBROLE=mon
else                    NBROLE=time; fi
# O cstaff ganha o botão da cerimônia quando a prova acaba p/ TODAS as sedes, e o competidor perde
# a impressão quando o staff some: as duas dependem do RELÓGIO/do disco, então o TTL é curto.
NBF="$CONTESTSDIR/$contest/var/nav-cache.$NBROLE.json"
if resp_cache_fresh "$NBF" "${NAV_CACHE_TTL:-20}" "$CONTESTSDIR/$contest/conf" \
     "$CONTESTSDIR/$contest/users" "$CONTESTSDIR/$contest/time-overrides.json"; then
  emit_json 200 OK; printf '%s' "$(<"$NBF")"; exit 0
fi

case "$NBROLE" in
animeitor)
  # .animeitor (telão): NÃO submete e não vê enunciado. Vê o placar (SEMPRE descongelado — é ele
  # que conduz a revelação), as estatísticas, e a página dele: fotos dos times + as chaves do
  # webcast que alimentam o sistema Animeitor.
  buttons='[{label:"Score", url:"/contest/score/"},
            {label:"🎥 Animeitor", url:"/contest/animeitor/"},
            {label:"📊 Estatísticas", url:"/contest/statistics/"},
            {label:"🏆 Revelação", url:"/contest/score/reveal.html"}]' ;;
cstaff)
  # .cstaff (chefe de sede): NÃO submete. Vê o placar (congelado, como usuário normal), a
  # fila de impressão em modo leitura, as ETIQUETAS de credenciais da sede e o TELÃO com as
  # fotos/músicas DA SEDE dele (o mesmo recorte do staff-filters; ele não gere chaves de webcast
  # nem o padrão do contest). O botão da cerimônia (🏆) só aparece quando o contest terminou p/
  # TODAS as sedes — mesmo gate que libera o placar full na API (a UI é só conveniência).
  buttons='[{label:"Score", url:"/contest/score/"},
            {label:"🖨️ Impressão", url:"/contest/staff/"},
            {label:"🏷️ Etiquetas", url:"/contest/badges/"},
            {label:"🎥 Animeitor", url:"/contest/animeitor/"},
            {label:"📄 Documentos", url:"/contest/docs/"},
            {label:"🔁 Rodadas", url:"/contest/rounds/"}]'
  if contest_over_for_all "$contest"; then
    buttons="$buttons + [{label:\"🏆 Revelação\", url:\"/contest/score/reveal.html\"}]"
  fi ;;
staff)
  # .staff: NÃO submete (sem Contest/Clarification). Vê o placar (congela no freeze, como
  # usuário normal), a área de tarefas de impressão recebidas e o TELÃO da sede dele em modo
  # SOMENTE LEITURA (olha e ouve foto/música do escopo; não sobe, não baixa pacote). Etiquetas de
  # credenciais são do .cstaff/admin — o .staff não as vê.
  buttons='[{label:"Score", url:"/contest/score/"},
            {label:"🖨️ Impressão", url:"/contest/staff/"},
            {label:"🎥 Animeitor", url:"/contest/animeitor/"},
            {label:"📄 Documentos", url:"/contest/docs/"},
            {label:"🔁 Rodadas", url:"/contest/rounds/"}]' ;;
*)
  # base comum a usuário/monitor/judge/chefe/admin
  buttons='[{label:"Contest", url:"/"},
            {label:"Score", url:"/contest/score/"},
            {label:"Clarification", url:"/contest/clarification/"}]'
  case "$NBROLE" in
  admin)
    buttons="$buttons + [
      {label:\"⚙ Administração\",  url:\"/contest/admin/\"},
      {label:\"Todas Submissões\", url:\"/contest/allsubmissions/\"},
      {label:\"Estatísticas\",     url:\"/contest/statistics/\"},
      {label:\"jplag\",            url:\"/contest/jplag/\"},
      {label:\"🔁 Rodadas\",        url:\"/contest/rounds/\"}]" ;;
  chief)
    buttons="$buttons + [
      {label:\"⚖️ Avaliar\",        url:\"/contest/judge/\"},
      {label:\"👑 Juiz-chefe\",     url:\"/contest/chief/\"},
      {label:\"🔁 Rodadas\",        url:\"/contest/rounds/\"},
      {label:\"Todas Submissões\",  url:\"/contest/allsubmissions/\"},
      {label:\"Estatísticas\",      url:\"/contest/statistics/\"}]" ;;
  judge)
    # juiz puro avalia pela página Avaliar; "Todas Submissões" vem ANÔNIMA (sem user/team)
    buttons="$buttons + [
      {label:\"⚖️ Avaliar\",            url:\"/contest/judge/\"},
      {label:\"Todas Submissões\",     url:\"/contest/allsubmissions/\"},
      {label:\"Estatísticas\",         url:\"/contest/statistics/\"}]" ;;
  mon)
    buttons="$buttons + [
      {label:\"Todas Submissões\", url:\"/contest/allsubmissions/\"},
      {label:\"Estatísticas\",     url:\"/contest/statistics/\"}]" ;;
  *)
    # usuário comum (não-privilegiado): página de backup só se o admin não desabilitou (BACKUP!=0)
    if [[ "$(. "$CONTESTSDIR/$contest/conf" 2>/dev/null; printf '%s' "${BACKUP:-}")" != 0 ]]; then
      buttons="$buttons + [{label:\"💾 Backup\", url:\"/contest/backup/\"}]"
    fi
    # página de impressão só quando há staff no contest E a impressão está habilitada
    if staff_exists "$contest" && print_enabled "$contest"; then
      buttons="$buttons + [{label:\"🖨️ Impressão\", url:\"/contest/print/\"}]"
    fi ;;
  esac ;;
esac

buttons="$buttons + [{label:\"Logout\", url:\"/logout\"}]"
# corpo ANTES do cabeçalho (regra da casa): falha do jq ainda pode virar 500, não 200 vazio
NBODY="$(jq -cn "{success:true, buttons:($buttons)}")" || fail 500 "Falha ao montar a resposta" "build_fail"
[[ -n "$NBODY" ]] || fail 500 "Falha ao montar a resposta" "build_fail"
resp_cache_store "$NBF" "$NBODY"
emit_json 200 OK; printf '%s' "$NBODY"
