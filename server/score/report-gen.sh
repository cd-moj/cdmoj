#!/usr/bin/env bash
#
# report-gen.sh <contest> <outdir>
#
# Gera o SITE ESTÁTICO do relatório final da prova (o admin baixa como tar.gz em
# GET /contest/admin/report): páginas autocontidas — CSS/JS inline, ZERO fetch/ESM/
# recurso externo — navegáveis via file:// ou qualquer web server estático, nos moldes
# do relatório BOCA (SCORE/RUNS/TASKS/CLARIFICATIONS/STATISTICS):
#
#   index.html            placar ABERTO (sem freeze) + info do contest + links dos enunciados
#   score-frozen.html     visão congelada (só quando FREEZE_TIME>0; o que o público viu)
#   runs.html             todas as submissões (metadados; veredicto CANÔNICO)
#   statements/<L>.html   enunciados (pandoc --embed-resources, já autocontidos) + <L>.pdf
#   clarifications.html   perguntas e respostas (asker ANÔNIMO)
#   statistics.html       estatísticas agregadas (statistics.cache.json renderizado)
#   staff-tasks.html      tarefas do .staff (impressão + balões; só metadados/status)
#   infra.html            situação: juízes, tempos de resposta, fila, timeline
#
# PRIVACIDADE — o que NUNCA entra no relatório:
#   - users/<l>/submissions/ (código-fonte) e mojlog/ (report do juiz expõe testes);
#   - de results/<id>.json: tests[], report_html, tl_used — só AGREGADOS (host só agregado
#     na infra);
#   - account.json: password, email, uname_changes (só fullname/team/univ/flag);
#   - clarifications: .login do asker, .answered_by, .answer_claim;
#   - print-requests: <id>.src (código de aluno!), *.combined.pdf, badges.json,
#     staff-filters.json;
#   - backups/, var/*audit*, access.log, conf cru, sessões/tokens;
#   - veredicto sempre CANÔNICO (sem ",100p" embutido) — não vaza score em prova icpc.
#
# FOTO DE TIME ENTRA (R5, 2026-08-30): mídia de time é PÚBLICA (decisão de 2026-08-24 — ela
# existe p/ o telão) e o relatório é o retrato do evento. Vai como MINIATURA em
# fotos/<login>.webp (arquivo relativo, nunca data:URI por linha — não dedupa, incidente dos
# 21MB) e o 📷 só é rendido no placar ABERTO — score-frozen.html sai SEM foto.
#
# É um "build" irmão de build.sh/stats-gen.sh: roda standalone (CLI) ou pelo handler.
set -u
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
export CONTESTSDIR

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../api/v1/lib/users.sh"
source "$HERE/../api/v1/lib/verdict.sh"
# COORTES: o relatório serve UM placar por visão (o build.sh já gerou cada TXT com a posição e a
# estrela certas dentro dela) — filtrar o TXT pronto daria estrela errada, ver lib/cohorts.sh.
# A lib é pura (jq + $CONTESTSDIR), então dá para sourcear standalone.
source "$HERE/../api/v1/lib/cohorts.sh"
# roda STANDALONE (CLI e handler): nada de lib/common.sh, então os caminhos do checkout e do
# store de problemas se auto-resolvem a partir daqui (server/score) — o relatório precisa do
# web/ (ui.css, bandeiras, logo, módulos de gráfico) e do pacote (autor do problema).
: "${MOJ_HOME:=$(cd "$HERE/../.." && pwd)}"
: "${MOJ_WEB:=$MOJ_HOME/web}"
: "${MOJ_PROBLEMS_DIR:=$MOJ_HOME/../moj-problems}"

C="${1:-}"; OUTD="${2:-}"
[[ -n "$C" && -n "$OUTD" ]] || { echo "uso: report-gen.sh <contest> <outdir>" >&2; exit 1; }
case "$C" in *[!A-Za-z0-9._@#+-]* | "" | *..* ) echo "report-gen: invalid contest id" >&2; exit 1;; esac
CDIR="$CONTESTSDIR/$C"
[[ -f "$CDIR/conf" ]] || { echo "report-gen: sem conf em $CDIR" >&2; exit 1; }

mkdir -p "$OUTD/statements" || { echo "report-gen: não criei $OUTD" >&2; exit 1; }
W="$(mktemp -d)" || exit 1
trap 'rm -rf "$W"' EXIT

# --- frescor dos artefatos derivados (placar + estatísticas) ------------------
bash "$HERE/build.sh" "$C" >/dev/null 2>&1 || true
bash "$HERE/stats-gen.sh" "$C" "$CDIR/var/statistics.cache.json" 2>/dev/null || true

# --- conf (mesmo padrão do stats-gen: o gerador roda fora do contexto de handler) ---
PROBS=(); CONTEST_NAME=""; CONTEST_START=""; CONTEST_END=""; FREEZE_TIME=""; CONTEST_TZ=""
PENALTY_MINUTES=""
set +o noglob; shopt -s nullglob
# shellcheck disable=SC1090
source "$CDIR/conf" 2>/dev/null || true
# FUSO: o relatório é lido por gente. Rodando standalone (CLI) o processo herda o UTC da imagem
# e TODA hora do relatório sairia adiantada — inclusive o `strftime` do awk e o `strflocaltime`
# do jq lá embaixo, que leem o TZ do processo. CONTEST_TZ manda; senão MOJ_TZ.
: "${MOJ_TZ:=America/Sao_Paulo}"
_tz="${CONTEST_TZ:-$MOJ_TZ}"; [[ -f "/usr/share/zoneinfo/$_tz" ]] || _tz="$MOJ_TZ"
export TZ="$_tz"
MODE="$(contest_score_mode "$C")"
START="${CONTEST_START:-0}"; [[ "$START" =~ ^[0-9]+$ ]] || START=0
END="${CONTEST_END:-0}";     [[ "$END"   =~ ^[0-9]+$ ]] || END=0
FREEZE="${FREEZE_TIME:-0}";  [[ "$FREEZE" =~ ^[0-9]+$ ]] || FREEZE=0
# como pintar a célula resolvida — o MESMO modo do placar ao vivo (/contest/basic balloon_style),
# p/ o relatório não contar uma história diferente do que as pessoas viram na prova
BSTYLE="${SCORE_BALLOON_STYLE:-icon}"; [[ "$BSTYLE" == fill ]] || BSTYLE=icon
CNAME="${CONTEST_NAME:-$C}"
NOW="$EPOCHSECONDS"

# --- idioma do relatório: o LOCALE do contest ------------------------------------------
# Rodamos provas com times de fora; o relatório é o documento que sobra do evento, então
# nasce nos DOIS idiomas como qualquer tela (regra do CLAUDE.md). Mesma mecânica do
# lib/contest-docs.sh (_doc_t): uma tabela de chaves, nada de string solta no meio do HTML.
# Blocos awk/jq recebem os rótulos já traduzidos por -v/--arg.
LOC="${LOCALE:-pt}"; [[ "$LOC" == en ]] || LOC=pt
rep_t(){ case "$LOC:$1" in
  # chrome
  pt:tab_score) printf '🏆 Placar';;              en:tab_score) printf '🏆 Scoreboard';;
  pt:tab_runs) printf '📨 Runs';;                 en:tab_runs) printf '📨 Runs';;
  pt:tab_clar) printf '💬 Clarifications';;       en:tab_clar) printf '💬 Clarifications';;
  pt:tab_stats) printf '📊 Estatísticas';;        en:tab_stats) printf '📊 Statistics';;
  pt:tab_docs) printf '📄 Documentos';;           en:tab_docs) printf '📄 Documents';;
  pt:tab_mlinux) printf '🖥 Máquinas';;           en:tab_mlinux) printf '🖥 Machines';;
  pt:page_mlinux) printf 'Máquinas mlinux (nutellaboot)';; en:page_mlinux) printf 'mlinux machines (nutellaboot)';;
  pt:ml_all) printf '— geral —';;                 en:ml_all) printf '— overall —';;
  pt:ml_sel) printf 'Recorte:';;                  en:ml_sel) printf 'Selection:';;
  pt:ml_note) printf 'Coletado do nutellaboot em %s — specs, editores e comportamento das máquinas das sedes durante a prova.' "$2";;
  en:ml_note) printf 'Collected from nutellaboot at %s — specs, editors and machine behaviour across sites during the contest.' "$2";;
  pt:tab_staff) printf '🖨️ Tarefas do staff';;    en:tab_staff) printf '🖨️ Staff tasks';;
  pt:tab_infra) printf '⚙️ Infra';;               en:tab_infra) printf '⚙️ Infra';;
  pt:tab_frozen) printf '❄ Placar congelado';;    en:tab_frozen) printf '❄ Frozen scoreboard';;
  pt:subtitle) printf 'relatório da competição';; en:subtitle) printf 'contest report';;
  pt:footer) printf 'Gerado em';;                 en:footer) printf 'Generated on';;
  pt:by_moj) printf 'pelo MOJ';;                  en:by_moj) printf 'by MOJ';;
  # index
  pt:page_index) printf 'Placar e informações';;  en:page_index) printf 'Scoreboard and info';;
  pt:contest) printf 'Competição';;               en:contest) printf 'Contest';;
  pt:start) printf 'Início';;                     en:start) printf 'Start';;
  pt:end) printf 'Término';;                      en:end) printf 'End';;
  pt:duration) printf 'Duração';;                 en:duration) printf 'Duration';;
  pt:mode) printf 'Modo';;                        en:mode) printf 'Mode';;
  pt:penalty) printf 'Penalidade';;               en:penalty) printf 'Penalty';;
  pt:penalty_val) printf 'min por tentativa rejeitada';; en:penalty_val) printf 'min per rejected attempt';;
  pt:freeze) printf 'Congelamento';;              en:freeze) printf 'Freeze';;
  pt:freeze_none) printf 'sem congelamento';;     en:freeze_none) printf 'no freeze';;
  pt:freeze_at) printf 'aos';;                    en:freeze_at) printf 'at';;
  pt:min_w) printf 'min';;                        en:min_w) printf 'min';;
  pt:teams) printf 'Times';;                      en:teams) printf 'Teams';;
  pt:subs) printf 'Submissões';;                  en:subs) printf 'Submissions';;
  pt:problems) printf 'Problemas';;               en:problems) printf 'Problems';;
  pt:letter) printf 'Letra';;                     en:letter) printf 'Letter';;
  pt:problem) printf 'Problema';;                 en:problem) printf 'Problem';;
  pt:author) printf 'Autor';;                     en:author) printf 'Author';;
  pt:statement) printf 'Enunciado';;              en:statement) printf 'Statement';;
  pt:ext_link) printf 'link externo';;            en:ext_link) printf 'external link';;
  pt:final_score) printf 'Placar final (aberto)';; en:final_score) printf 'Final scoreboard (open)';;
  pt:no_score) printf 'Sem placar gerado.';;      en:no_score) printf 'No scoreboard generated.';;
  pt:frozen_title) printf 'Placar congelado';;    en:frozen_title) printf 'Frozen scoreboard';;
  pt:frozen_note) printf 'Visão CONGELADA aos %s min (%s) — é o placar que o público viu durante a prova. O placar final aberto está na aba' "$2" "$3";;
  en:frozen_note) printf 'FROZEN view at %s min (%s) — this is what the public saw during the contest. The final open scoreboard is in the tab' "$2" "$3";;
  pt:open_note) printf 'O placar abaixo está ABERTO (sem congelamento). A visão congelada aos %s min está em' "$2";;
  en:open_note) printf 'The scoreboard below is OPEN (no freeze). The frozen view at %s min is in' "$2";;
  pt:team_col) printf 'Equipe';;                  en:team_col) printf 'Team';;
  pt:total) printf 'Total';;                      en:total) printf 'Total';;
  pt:pen_col) printf 'Penal.';;                   en:pen_col) printf 'Pen.';;
  pt:guest) printf 'convidado';;                  en:guest) printf 'guest';;
  pt:guest_title) printf 'Time convidado (extra-oficial): não entra na classificação';;
  en:guest_title) printf 'Guest team (unofficial): not in the official ranking';;
  pt:fts) printf 'Primeiro a resolver';;          en:fts) printf 'First to solve';;
  pt:mode_icpc) printf 'ICPC';;                   en:mode_icpc) printf 'ICPC';;
  pt:mode_obi) printf 'OBI (pontos)';;            en:mode_obi) printf 'OBI (points)';;
  pt:mode_heur) printf 'Heurístico';;             en:mode_heur) printf 'Heuristic';;
  pt:mode_list) printf 'Lista/treino';;           en:mode_list) printf 'List/practice';;
  pt:mode_custom) printf 'Custom';;               en:mode_custom) printf 'Custom';;
  # runs
  pt:page_runs) printf 'Runs — todas as submissões';; en:page_runs) printf 'Runs — all submissions';;
  pt:filter_ph) printf 'filtrar por time, login, problema…';; en:filter_ph) printf 'filter by team, login, problem…';;
  pt:hour) printf 'Hora';;                        en:hour) printf 'Time';;
  pt:team) printf 'Time';;                        en:team) printf 'Team';;
  pt:univ) printf 'Univ';;                        en:univ) printf 'Univ';;
  pt:prob) printf 'Prob';;                        en:prob) printf 'Prob';;
  pt:lang) printf 'Ling';;                        en:lang) printf 'Lang';;
  pt:verdict) printf 'Veredicto';;                en:verdict) printf 'Verdict';;
  pt:minute) printf 'Min';;                       en:minute) printf 'Min';;
  # clarifications
  pt:page_clar) printf 'Clarifications';;         en:page_clar) printf 'Clarifications';;
  pt:notice) printf 'Aviso da organização';;      en:notice) printf 'Announcement';;
  pt:public) printf 'Pública';;                   en:public) printf 'Public';;
  pt:private) printf 'Privada';;                  en:private) printf 'Private';;
  pt:none_clar) printf 'Nenhuma clarification registrada.';; en:none_clar) printf 'No clarifications.';;
  # estatísticas (noscript)
  pt:page_stats) printf 'Estatísticas';;          en:page_stats) printf 'Statistics';;
  pt:no_charts) printf 'Sem os módulos de gráfico (web/ ausente).';; en:no_charts) printf 'Chart modules missing (no web/).';;
  pt:by_problem) printf 'Por problema';;          en:by_problem) printf 'By problem';;
  pt:by_lang) printf 'Por linguagem';;            en:by_lang) printf 'By language';;
  pt:by_verdict) printf 'Por veredicto';;         en:by_verdict) printf 'By verdict';;
  pt:timeline) printf 'Linha do tempo (janelas de 10 min)';; en:timeline) printf 'Timeline (10-min windows)';;
  pt:dist) printf 'Distribuição de problemas resolvidos';; en:dist) printf 'Distribution of problems solved';;
  pt:name_w) printf 'Nome';;                      en:name_w) printf 'Name';;
  pt:accepted) printf 'Aceitas';;                 en:accepted) printf 'Accepted';;
  pt:solved_col) printf 'Resolveram';;            en:solved_col) printf 'Solved';;
  pt:rate) printf 'Aceitação';;                   en:rate) printf 'Accept rate';;
  pt:first_solve) printf '1º a resolver';;        en:first_solve) printf 'First to solve';;
  pt:solvers) printf 'Times que resolveram';;     en:solvers) printf 'Teams that solved';;
  pt:occurrences) printf 'Ocorrências';;          en:occurrences) printf 'Count';;
  pt:solved_w) printf 'Resolveu';;                en:solved_w) printf 'Solved';;
  pt:stats_fail) printf 'Falha ao renderizar as estatísticas.';; en:stats_fail) printf 'Failed to render the statistics.';;
  pt:stats_none) printf 'Sem estatísticas geradas.';; en:stats_none) printf 'No statistics generated.';;
  # staff
  pt:page_staff) printf 'Tarefas do staff';;      en:page_staff) printf 'Staff tasks';;
  pt:type) printf 'Tipo';;                        en:type) printf 'Type';;
  pt:detail) printf 'Detalhe';;                   en:detail) printf 'Detail';;
  pt:status) printf 'Status';;                    en:status) printf 'Status';;
  pt:service) printf 'Atendimento';;              en:service) printf 'Handling';;
  pt:balloon) printf 'balão';;                    en:balloon) printf 'balloon';;
  pt:printing) printf 'impressão';;               en:printing) printf 'printing';;
  pt:pages_sfx) printf 'pág.';;                   en:pages_sfx) printf 'pages';;
  pt:none_tasks) printf 'Nenhuma tarefa registrada.';; en:none_tasks) printf 'No tasks recorded.';;
  # infra
  pt:page_infra) printf 'Infra';;                 en:page_infra) printf 'Infra';;
  pt:snapshot) printf 'Snapshot no momento da geração do relatório (%s) + métricas de resposta da prova inteira.' "$2";;
  en:snapshot) printf 'Snapshot taken when the report was generated (%s) + response metrics for the whole contest.' "$2";;
  pt:avg_wait) printf 'espera média';;            en:avg_wait) printf 'average wait';;
  pt:max_w) printf 'máxima';;                     en:max_w) printf 'max';;
  pt:coverage) printf 'Cobertura: %s de %s submissões com tempo de resposta registrado.' "$2" "$3";;
  en:coverage) printf 'Coverage: %s of %s submissions with a recorded response time.' "$2" "$3";;
  pt:wait_by_prob) printf 'Espera média por problema';; en:wait_by_prob) printf 'Average wait per problem';;
  pt:judged) printf 'Julgadas';;                  en:judged) printf 'Judged';;
  pt:by_judge) printf 'Julgamentos por juiz';;    en:by_judge) printf 'Judgements per judge';;
  pt:judge_host) printf 'Juiz (host)';;           en:judge_host) printf 'Judge (host)';;
  pt:judgements) printf 'Julgamentos';;           en:judgements) printf 'Judgements';;
  pt:avg_dur) printf 'Duração média do julgamento';; en:avg_dur) printf 'Average judging time';;
  pt:registered) printf 'Juízes registrados (snapshot)';; en:registered) printf 'Registered judges (snapshot)';;
  pt:queue_now) printf 'Fila no momento da geração: %s job(s) aguardando.' "$2";;
  en:queue_now) printf 'Queue when generated: %s job(s) waiting.' "$2";;
  pt:host) printf 'Host';;                        en:host) printf 'Host';;
  pt:state) printf 'Estado';;                     en:state) printf 'State';;
  pt:online) printf 'Online';;                    en:online) printf 'Online';;
  pt:last_hb) printf 'Último heartbeat';;         en:last_hb) printf 'Last heartbeat';;
  pt:langs) printf 'Linguagens';;                 en:langs) printf 'Languages';;
  pt:cached) printf 'Problemas em cache';;        en:cached) printf 'Cached problems';;
  # documentos
  pt:page_docs) printf 'Documentos da prova';;    en:page_docs) printf 'Contest documents';;
  pt:docs_note) printf 'Os documentos publicados aos times, como foram entregues. Abra o arquivo <b>extraído</b> do pacote (dentro do visualizador de rodadas os links relativos não abrem).';;
  en:docs_note) printf 'The documents published to the teams, as delivered. Open the <b>extracted</b> package (relative links do not open inside the rounds viewer).';;
  pt:doc_col) printf 'Documento';;                en:doc_col) printf 'Document';;
  pt:lang_col) printf 'Idioma';;                  en:lang_col) printf 'Language';;
  pt:file) printf 'Arquivo';;                     en:file) printf 'File';;
  pt:size) printf 'Tamanho';;                     en:size) printf 'Size';;
  pt:doc_contest) printf '📕 Caderno de problemas';; en:doc_contest) printf '📕 Problem set';;
  pt:doc_times) printf '⏱ Limites de tempo';;     en:doc_times) printf '⏱ Time limits';;
  pt:doc_info) printf 'ℹ️ Informações do ambiente';; en:doc_info) printf 'ℹ️ Testing environment';;
  pt:doc_editorial) printf '📝 Editorial (soluções)';; en:doc_editorial) printf '📝 Editorial (solutions)';;
  # filtros do placar (coorte, bandeira, universidade, sede, busca)
  pt:f_board) printf 'Placar:';;                  en:f_board) printf 'Board:';;
  pt:f_flag) printf 'Bandeira:';;                 en:f_flag) printf 'Flag:';;
  pt:f_flag_all) printf 'todas';;                 en:f_flag_all) printf 'all';;
  pt:f_univ) printf 'Universidade:';;             en:f_univ) printf 'University:';;
  pt:f_univ_all) printf 'todas';;                 en:f_univ_all) printf 'all';;
  pt:f_region) printf 'Sede:';;                   en:f_region) printf 'Site:';;
  pt:f_region_all) printf 'todas';;               en:f_region_all) printf 'all';;
  pt:f_search) printf 'buscar time, universidade, login…';; en:f_search) printf 'search team, university, login…';;
  pt:f_clear) printf 'limpar filtros';;           en:f_clear) printf 'clear filters';;
  # o %s daqui é TEMPLATE para o JS (vai em data-tpl): printf '%s' p/ o printf não comê-los
  pt:f_count) printf '%s' 'Mostrando %s de %s times';; en:f_count) printf '%s' 'Showing %s of %s teams';;
  pt:f_none) printf 'Nenhum time casa com o filtro.';; en:f_none) printf 'No team matches the filter.';;
  # renumeração do recorte + estrela relativa (R1/R6, 2026-08-30) e 📷 (R4/R5)
  pt:f_slice_note) printf '· ★ = 1º do recorte';; en:f_slice_note) printf '· ★ = 1st in selection';;
  pt:f_slice_t) printf 'Posição no placar completo (sem o filtro)';; en:f_slice_t) printf 'Position in the full scoreboard (without the filter)';;
  pt:fts_sel) printf 'Primeiro a resolver no recorte';; en:fts_sel) printf 'First to solve in the selection';;
  pt:photo_t) printf 'Ver a foto do time';;       en:photo_t) printf 'View team photo';;
  pt:st_country) printf 'País:';;                 en:st_country) printf 'Country:';;
  pt:st_all) printf 'todos';;                     en:st_all) printf 'all';;
  # %s do JS (vão em data-*): printf '%s' p/ não comê-los
  pt:st_sel) printf '%s' 'Recorte: %s — %s de %s participantes';; en:st_sel) printf '%s' 'Selection: %s — %s of %s participants';;
  pt:st_glob) printf '%s' '%s participantes';;    en:st_glob) printf '%s' '%s participants';;
  pt:view_public) printf 'Geral (todos)';;        en:view_public) printf 'Overall (everyone)';;
  pt:view_all) printf 'Todos, com convidados';;   en:view_all) printf 'Everyone, incl. guests';;
  pt:view_of) printf 'Visão da coorte %s' "$2";;  en:view_of) printf 'As seen by cohort %s' "$2";;
  pt:gen_place) printf 'Geral';;                  en:gen_place) printf 'Overall';;
  pt:gen_place_t) printf 'Posição no placar geral';; en:gen_place_t) printf 'Position in the overall scoreboard';;
  pt:cohort_note) printf 'Placar da coorte <b>%s</b>: a posição grande é dentro dela; o número menor, cinza, é a posição no placar geral.' "$2";;
  en:cohort_note) printf 'Cohort <b>%s</b> scoreboard: the large number is the position within it; the smaller grey one is the position in the overall scoreboard.' "$2";;
  *) printf '%s' "$1";;
esac; }

# --- probmeta: letra/nome/skey + as 4 grafias do probid no history (off/raw/dot/hash) ---
: > "$W/probs.tsv"
for (( i=0; i<${#PROBS[@]}; i+=5 )); do
  praw="${PROBS[$((i+1))]}"; pfull="${PROBS[$((i+2))]}"; pshort="${PROBS[$((i+3))]}"; pskey="${PROBS[$((i+4))]}"
  phash="$pskey"; [[ "$phash" == *"#"* ]] || phash="${praw//\//#}"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$pshort" "$pfull" "$pskey" "$i" "$praw" "${praw/\//.}" "$phash"
done >> "$W/probs.tsv"

# --- identidade dos times (SÓ fullname/team/univ/flag/sede — nunca password/email) -----
# login \t team-name \t univ_short \t univ_full \t flag \t sede ; USERS_FROM cobre compartilhados.
# A SEDE (.team.region) entra como 6º campo (leitores antigos usam 1-5): é o que alimenta o
# filtro por sede do placar — o TXT do placar não tem essa coluna.
ACCT_JQ='[.login//"", ((.team.name // .fullname // "")|gsub("[:\t\n]";" ")),
          ((.team.univ_short//"")|gsub("[:\t\n]";" ")), ((.team.univ_full//"")|gsub("[:\t\n]";" ")),
          ((.team.flag//"")|gsub("[:\t\n]";"")), ((.team.region//"")|gsub("[:\t\n]";" "))] | @tsv'
{
  find "$CDIR/users" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
    | xargs -0 -r jq -r "$ACCT_JQ" 2>/dev/null
  usrc="$(sed -n 's/^[[:space:]]*USERS_FROM=//p' "$CDIR/conf" 2>/dev/null | tail -1)"
  usrc="${usrc//\'/}"; usrc="${usrc//\"/}"
  if [[ -n "$usrc" && "$usrc" != *[!A-Za-z0-9._-]* && -d "$CONTESTSDIR/$usrc/users" ]]; then
    for ud in "$CDIR/users"/*/; do
      lg="${ud%/}"; lg="${lg##*/}"
      [[ -f "$ud/account.json" ]] && continue
      [[ -f "$CONTESTSDIR/$usrc/users/$lg/account.json" ]] \
        && jq -r "$ACCT_JQ" "$CONTESTSDIR/$usrc/users/$lg/account.json" 2>/dev/null
    done
  fi
} > "$W/names.tsv"

# --- fotos dos times: MINIATURAS em fotos/<login>.webp (R5, 2026-08-30) -----------------
# tp_thumb gera/cacheia a thumb 320px (~7KB) no store; aqui só copiamos. Login validado
# (vira nome de arquivo) e cap de 300KB: em dev sem `convert` o tp_thumb degrada p/ a foto
# CHEIA — o cap impede o pacote de inchar. photos.tsv alimenta o 📷 do rep_score_html.
source "$HERE/../api/v1/lib/team-photo.sh"
: > "$W/photos.tsv"
mkdir -p "$OUTD/fotos"
while IFS=$'\t' read -r _lg _rest; do
  [[ -n "$_lg" && "$_lg" != *[!A-Za-z0-9._@-]* ]] || continue
  _th="$(tp_thumb "$C" "$_lg" 2>/dev/null)"
  [[ -s "$_th" ]] || continue
  _sz="$(stat -c%s "$_th" 2>/dev/null)"; [[ "$_sz" =~ ^[0-9]+$ ]] && (( _sz <= 307200 )) || continue
  cp -f "$_th" "$OUTD/fotos/$_lg.webp" 2>/dev/null || continue
  printf '%s\n' "$_lg"
done < "$W/names.tsv" > "$W/photos.tsv"
rmdir "$OUTD/fotos" 2>/dev/null || true   # sem foto nenhuma = sem diretório

# escape/format: definidos ANTES das bandeiras — rep_flag usa esc() no alt/title.
esc(){ printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"; }
# data no formato do idioma do relatório (dd/mm em pt, yyyy-mm-dd em en)
fmt_dt(){ (( ${1:-0} > 0 )) && date -d "@$1" "+$([[ "${LOC:-pt}" == en ]] && printf '%%Y-%%m-%%d %%H:%%M' || printf '%%d/%%m/%%Y %%H:%%M')" 2>/dev/null || printf '—'; }

# --- bandeiras: MESMA regra do site (web/shared/flags.js), SVG local -> data URI ------
# Era emoji de indicador regional: não renderiza no Windows nem em servidor sem Noto Color
# Emoji, e — pior — só casava 2 letras, então os códigos de ESTADO ("br-rj", que é o que a
# maioria dos times usa) saíam como TEXTO CRU no placar. Agora resolve o mesmo arquivo que o
# placar ao vivo usa e embute como data URI (obrigatório: o visualizador de rodadas abre as
# páginas em iframe srcdoc, onde caminho relativo não resolve). Só os códigos USADOS entram.
rep_flag_file(){  # <código> -> caminho do SVG (vazio se não houver)
  local c="${1,,}" f=""
  c="${c//_/-}"
  [[ "$c" =~ ^br-([a-z]{2})$ ]] && f="$MOJ_WEB/shared/flags/br/${BASH_REMATCH[1]}.svg"
  [[ -z "$f" && "$c" =~ ^[a-z]{2}$ ]] && f="$MOJ_WEB/shared/flags/country/$c.svg"
  # subdivisão fora do BR (gb-eng, es-ct, sh-ac…) mora no cache de países com o código inteiro
  [[ -z "$f" && "$c" =~ ^[a-z]{2}-[a-z]{2,3}$ ]] && f="$MOJ_WEB/shared/flags/country/$c.svg"
  [[ -n "$f" && -s "$f" ]] && printf '%s' "$f"
}
# nome legível do código. Duas armadilhas: no index.json o estado é indexado SEM o prefixo
# ("sc", não "br-sc") e o array certo depende do FORMATO do código — procurar nos dois
# concatenados faz "br-sc" virar Seychelles (país sc) em vez de Santa Catarina.
# Vale para o alt/title da bandeira E para o rótulo do filtro por bandeira (fonte única).
rep_flag_name(){  # <código> -> nome (cai no próprio código quando não está no índice)
  local c="${1,,}" key arr=".countries" name
  c="${c//_/-}"; key="$c"
  [[ "$c" =~ ^br-([a-z]{2})$ ]] && { key="${BASH_REMATCH[1]}"; arr=".br_states"; }
  name="$(jq -r --arg c "$key" "first(($arr // [])[] | select((.code|ascii_downcase)==\$c) | .name) // empty" \
          "$MOJ_WEB/shared/flags/index.json" 2>/dev/null)"
  printf '%s' "${name:-$1}"
}
rep_flag_slug(){ local c="${1,,}"; c="${c//_/-}"; printf '%s' "${c//[^a-z0-9-]/}"; }
# A bandeira entra UMA vez, como classe CSS. Era um <img> com o SVG em data URI POR LINHA: com
# 3 placares (um por coorte) o index.html do esquenta foi a 21 MB — 20,8 MB de base64, sendo 19
# imagens distintas repetidas 177 vezes (um brasão de estado tem 458 KB). Agora a linha só
# aponta para a classe e o dado mora no <style> da página. `background-size:contain` cuida da
# proporção (a caixa é fixa), então nada de calcular largura por bandeira.
rep_flag(){   # <código> -> <span …> (vazio se o código não for reconhecível)
  local name
  [[ -n "$(rep_flag_file "$1")" ]] || { printf '%s' ""; return; }
  name="$(rep_flag_name "$1")"
  printf '<span class="flag-mini f-%s" role="img" aria-label="%s" title="%s"></span>' \
    "$(rep_flag_slug "$1")" "$(esc "$name")" "$(esc "$name")"
}
rep_flag_css(){ [[ -s "$W/flags.css" ]] && { printf '<style>\n'; cat "$W/flags.css"; printf '</style>\n'; }; return 0; }
# os códigos vêm das CONTAS e também dos próprios placares: time que saiu do store (ou veio de
# USERS_FROM) continua no placar.txt, e sem a segunda fonte a bandeira dele virava texto cru.
# O glob pega TODOS os placares (inclusive os placar-view-<coorte>.txt), porque o relatório
# publica um placar por visão — coorte privada só aparece lá.
{ awk -F'\t' '$5!=""{print $5}' "$W/names.tsv"
  for _pt in "$CDIR"/var/placar*.txt; do
    [[ -s "$_pt" ]] || continue
    awk -F: 'NR==2{ s=1; while (s<=NF && tolower($s) ~ /^(desc|asc)$/) s++
                    for(i=s;i<=NF;i++) if (tolower($i)=="flag") { fi=i-s+1; break }; next }
             fi && NR>2 { split($0,a,":"); if (a[fi]!="") print a[fi] }' "$_pt"
  done
} | sort -u | { : > "$W/flags.css"
  while IFS= read -r fcode; do
    [[ -n "$fcode" ]] || continue
    printf '%s\t%s\t%s\n' "$fcode" "$(rep_flag_name "$fcode")" "$(rep_flag "$fcode")"
    _ff="$(rep_flag_file "$fcode")"; [[ -n "$_ff" ]] || continue
    printf '.f-%s{background-image:url("data:image/svg+xml;base64,%s")}\n' \
      "$(rep_flag_slug "$fcode")" "$(base64 -w0 < "$_ff" 2>/dev/null)" >> "$W/flags.css"
  done
} > "$W/flags.tsv"
# entradas de PAÍS p/ os estados usados (2026-08-30): só o NOME (data-cname do filtro
# hierárquico) — SEM embutir o SVG do país, que nenhuma linha usa quando ninguém tem a
# bandeira crua (o smoke conta os SVGs embutidos: um por código USADO).
awk -F'\t' 'match($1, /-/){ print substr($1, 1, RSTART-1) }' "$W/flags.tsv" | sort -u \
  | while IFS= read -r _cc; do
      [[ -n "$_cc" ]] || continue
      grep -q "^${_cc}	" "$W/flags.tsv" || printf '%s\t%s\t\n' "$_cc" "$(rep_flag_name "$_cc")"
    done >> "$W/flags.tsv"

# logo do MOJ (1,4 KB) embutido — mesma imagem da topbar do site
LOGO_IMG=""
if [[ -s "$MOJ_WEB/shared/assets/logo_moj.svg" ]]; then
  LOGO_IMG="<img src=\"data:image/svg+xml;base64,$(base64 -w0 < "$MOJ_WEB/shared/assets/logo_moj.svg")\" alt=\"MOJ\">"
fi

# --- cores de balão + luminância (cor do texto) + CONTORNO (o balão claro não some) ------
# A paleta PADRÃO ICPC entra mesmo SEM balloons.json — é o que a API já faz
# (handlers/contest/balloons.sh devolve o default sempre, o arquivo só sobrepõe chaves). Antes
# o relatório só lia cores se o arquivo existisse, então o MESMO evento tinha placar colorido
# ao vivo e relatório todo verde. GÊMEO de web/contest/score/score-colors.js — mudou lá, mude aqui.
: > "$W/balloons.tsv"
# bl_edge <RRGGBB> -> a própria cor escurecida ATÉ cruzar 3:1 contra o branco (WCAG 1.4.11).
# Escurecer por fator fixo não serve: o verde-limão 00FF00 parava em 2,29:1.
bl_edge() {
  local r=$((16#${1:0:2})) g=$((16#${1:2:2})) b=$((16#${1:4:2})) k=78 i er eg eb lr lg lb L
  for (( i=0; i<12 && k>20; i++ )); do
    er=$(( r*k/100 )); eg=$(( g*k/100 )); eb=$(( b*k/100 ))
    # luminância relativa aproximada em milésimos (a curva sRGB via awk seria fork por cor)
    L=$(awk -v r="$er" -v g="$eg" -v b="$eb" 'function f(c){c/=255; return c<=0.03928? c/12.92 : ((c+0.055)/1.055)^2.4}
        BEGIN{printf "%d", 1000*(0.2126*f(r)+0.7152*f(g)+0.0722*f(b))}')
    (( (1050*1000) / (L + 50) >= 3000 )) && break
    k=$(( k - 6 ))
  done
  printf '%02X%02X%02X' $(( r*k/100 )) $(( g*k/100 )) $(( b*k/100 ))
}
{ # default ICPC A–O primeiro; o balloons.json do contest sobrescreve depois (última linha vence
  # no awk, que faz bhex[k]=... na ordem de leitura)
  printf 'A\tFFFFFF\nB\t000000\nC\tFF0000\nD\t800000\nE\tFFFF00\nF\t008000\nG\t0000FF\nH\t000080\n'
  printf 'I\tFF00FF\nJ\t800080\nK\t00FF00\nL\t00FFFF\nM\tC0C0C0\nN\tFF8000\nO\tA3794D\n'
  if [[ -f "$CDIR/balloons.json" ]] && jq -e . "$CDIR/balloons.json" >/dev/null 2>&1; then
    jq -r 'to_entries[] | [.key, (.value | if type=="object" then (.hex//"") else tostring end)] | @tsv' \
        "$CDIR/balloons.json" 2>/dev/null
  fi
} | while IFS=$'\t' read -r bk bv; do
      bv="${bv#\#}"; bv="$(printf '%s' "$bv" | tr -cd '0-9A-Fa-f' | tr 'a-f' 'A-F')"
      [[ ${#bv} -eq 6 ]] || continue          # ignora chave que não é cor (ex.: enableSonic)
      r=$((16#${bv:0:2})); g=$((16#${bv:2:2})); b=$((16#${bv:4:2}))
      dark=0; (( (299*r + 587*g + 114*b) / 1000 < 128 )) && dark=1
      printf '%s\t%s\t%s\t%s\n' "$bk" "$bv" "$dark" "$(bl_edge "$bv")"
    done >> "$W/balloons.tsv"

# --- HTML compartilhado --------------------------------------------------------------

# CSS: o MESMO do site (web/shared/ui.css) inlinado + os <style> locais do placar e das
# estatísticas + o pouco que é exclusivo do relatório. Antes o relatório tinha paleta própria
# (#1d2b45/#ffb74d) e não parecia MOJ. ui.css não tem @font-face nem URL externa (as fontes
# são stacks do sistema), então inlinar é offline-safe.
rep_css(){
  printf ':root{color-scheme:light}\n'
  cat "$MOJ_WEB/shared/ui.css" 2>/dev/null
  # locais do placar (web/contest/score/index.html) e das estatísticas (…/statistics/index.html)
  sed -n '/<style>/,/<\/style>/p' "$MOJ_WEB/contest/score/index.html" 2>/dev/null | sed '/<\/\?style>/d'
  sed -n '/<style>/,/<\/style>/p' "$MOJ_WEB/contest/statistics/index.html" 2>/dev/null | sed '/<\/\?style>/d'
  cat <<'CSSEOF'
/* exclusivos do relatório offline */
body{background:var(--blue-bg)}
/* o relatório é DOCUMENTO, não app: nem o cabeçalho nem a barra de abas grudam no topo
   (duas faixas sticky em top:0 se atropelavam no headless e no PDF de impressão). */
.topbar{position:static}
.topbar .bar{padding:.8rem 1.2rem;gap:.5rem}
.topbar .rep-sub{opacity:.85;font-size:.85rem}
.wrap{max-width:var(--page-max);margin:0 auto;padding:1.1rem 1.2rem 2.5rem}
.repnav{background:#fff;border-bottom:1px solid var(--line);position:static}
.repnav .wrap{display:flex;flex-wrap:wrap;gap:.15rem;padding:0 1.2rem}
.repnav a{color:var(--muted);text-decoration:none;padding:.6rem .85rem;font-size:.92rem;font-weight:600;border-bottom:3px solid transparent}
.repnav a:hover{color:var(--blue-dark);background:var(--blue-soft)}
.repnav a.on{color:var(--blue-dark);border-bottom-color:var(--accent)}
h2{font-size:1.25rem;color:var(--blue-dark);margin:1.4rem 0 .6rem}
table{width:100%}
/* tabela de POUCAS colunas não estica: com width:100% a coluna de rótulo engolia o vão e os
   números ficavam a meia tela do próprio cabeçalho. `narrow` deixa as colunas do tamanho do
   conteúdo (com um piso p/ não virar tabelinha perdida no meio do card). */
table.moj.narrow{width:auto;min-width:min(100%,34rem)}
/* o width:1% das colunas numéricas (que no modo esticado empurra o número p/ a direita)
   FORÇA a tabela de largura automática a crescer — porcentagem de célula resolve contra a
   largura da tabela. Em `narrow` a coluna volta a ser do tamanho do conteúdo. */
table.moj.narrow th.n, table.moj.narrow td.n{width:auto}
.tblwrap{overflow-x:auto}
/* o placar (largura por colgroup, quebra de linha, marca no celular) vem do ui.css inlinado:
   aqui NÃO pode voltar `white-space:nowrap` nem `min-width` — era o que forçava a rolagem. */
td.place{text-align:right}
tr.guest-row td{background:#fbfbfd;color:var(--muted)}
.v-ac{color:var(--ok);font-weight:700}
.v-rej{color:var(--err)}
.v-pend{color:var(--muted);font-style:italic}
.badge{display:inline-block;border-radius:999px;padding:1px 9px;font-size:.75rem;background:var(--blue-soft);color:var(--blue-dark)}
.badge.pub{background:var(--ok-bg);color:var(--ok)}.badge.priv{background:var(--err-bg);color:var(--err)}
.badge.org,.badge.st-printed{background:var(--warn-bg);color:var(--warn)}
.badge.st-pending{background:var(--err-bg);color:var(--err)}
.badge.st-delivered{background:var(--ok-bg);color:var(--ok)}
.cards{display:flex;flex-wrap:wrap;gap:.6rem;margin:.6rem 0}
.card{background:var(--card);border:1px solid var(--line);border-radius:var(--radius);padding:.7rem 1.1rem;min-width:140px;box-shadow:var(--shadow-sm)}
.card .n{font-size:1.6rem;font-weight:800;color:var(--blue-dark)}
.card .l{font-size:.78rem;color:var(--muted)}
.info{background:var(--card);border:1px solid var(--line);border-radius:var(--radius);padding:.3rem 1.1rem .9rem;margin:.7rem 0;box-shadow:var(--shadow-sm)}
.info dl{display:grid;grid-template-columns:max-content 1fr;gap:4px 14px;margin:.6rem 0 0}
.info dt{color:var(--muted);font-size:.85rem}.info dd{margin:0;font-size:.92rem}
/* barrinha da linha do tempo do <noscript>. NÃO pode se chamar .bar: essa classe é a do
   CONTEINER da topbar no ui.css e o height:14px daqui achatava o cabeçalho inteiro. */
.tbar{background:var(--blue-soft);height:14px;display:inline-block;vertical-align:middle;border-radius:3px}
.tbar.ac{background:#bfe8cd}
.qa{background:var(--card);border:1px solid var(--line);border-radius:var(--radius);padding:.7rem 1.1rem;margin:.7rem 0;box-shadow:var(--shadow-sm)}
.qa .q{white-space:pre-wrap;margin:.4rem 0}
.qa .a{white-space:pre-wrap;margin:.4rem 0;padding:.5rem .7rem;background:var(--ok-bg);border-left:3px solid var(--ok);border-radius:6px}
.qa .meta{color:var(--muted);font-size:.8rem}
.swatch{display:inline-block;width:.9em;height:.9em;border-radius:50%;border:1px solid #9993;vertical-align:-.1em}
/* bandeira = caixa fixa + imagem no CSS (uma vez por código, ver rep_flag): `contain` mantém a
   proporção de qualquer bandeira dentro dela. */
span.flag-mini{display:inline-block;width:27px;height:18px;max-width:100%;
  background-repeat:no-repeat;background-position:center;background-size:contain;
  vertical-align:middle;border-radius:2px;box-shadow:0 0 1px rgba(0,0,0,.45)}
/* o tier de celular do ui.css manda `height:auto` na bandeira — regra pensada p/ <img>, que tem
   proporção própria; num <span> ela zeraria a altura. */
@media (max-width:640px){ table.score span.flag-mini{height:14px !important;width:100%} }
.flag-mini{height:18px;vertical-align:middle;border-radius:2px;box-shadow:0 0 1px rgba(0,0,0,.45)}
input.filter{padding:.45rem .7rem;border:1px solid #c8cfd9;border-radius:10px;margin:0 0 .7rem;width:280px;max-width:100%}
footer{color:var(--muted);font-size:.78rem;margin:2rem 0 .6rem}
.note{color:var(--muted);font-size:.85rem;margin:.4rem 0}
/* a barra de filtros (.fbar) e a posição geral (.plg) moram no ui.css inlinado acima: são as
   MESMAS do placar ao vivo — os dois filtram o mesmo placar. */
CSSEOF
}

rep_head(){ # <título> <id-da-aba-ativa>
  local title="$1" active="$2" tabs t fn id label
  tabs=""
  for t in "index.html:index:$(rep_t tab_score)" "runs.html:runs:$(rep_t tab_runs)" \
           "clarifications.html:clar:$(rep_t tab_clar)" "statistics.html:stats:$(rep_t tab_stats)" \
           "mlinux.html:mlinux:$(rep_t tab_mlinux)" \
           "documentos.html:docs:$(rep_t tab_docs)" \
           "staff-tasks.html:staff:$(rep_t tab_staff)" "infra.html:infra:$(rep_t tab_infra)"; do
    IFS=: read -r fn id label <<< "$t"
    [[ "$id" == docs && ! -f "$OUTD/documentos.html" && "$active" != docs ]] && continue
    # a aba mlinux é CONDICIONAL: só quando a integração nutellaboot foi coletada
    [[ "$id" == mlinux && ! -f "$OUTD/mlinux.html" && "$active" != mlinux ]] && continue
    tabs+="<a href=\"$fn\"$([[ "$id" == "$active" ]] && printf ' class="on"')>$label</a>"
  done
  [[ -f "$OUTD/score-frozen.html" || "$active" == frozen ]] && \
    tabs+="<a href=\"score-frozen.html\"$([[ "$active" == frozen ]] && printf ' class="on"')>$(rep_t tab_frozen)</a>"
  cat <<EOF
<!DOCTYPE html>
<html lang="$([[ "${LOCALE:-pt}" == en ]] && printf 'en' || printf 'pt-BR')">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$(esc "$title") — $(esc "$CNAME")</title>
<style>
$(rep_css)
</style>
</head>
<body>
<header class="topbar"><div class="bar">
<span class="brand">$LOGO_IMG MOJ</span>
<span class="contest-topbar-title">$(esc "$CNAME")</span>
<span class="spacer"></span>
<span class="rep-sub">$(rep_t subtitle)</span>
</div></header>
<nav class="repnav"><div class="wrap">$tabs</div></nav>
<div class="wrap">
<h2>$(esc "$title")</h2>
EOF
}

rep_foot(){
  cat <<EOF
<footer>$(rep_t footer) $(fmt_dt "$NOW") $(rep_t by_moj) — moj.naquadah.com.br</footer>
</div>
</body>
</html>
EOF
}

# --- placar TXT -> tabela HTML (icpc/obi/generic) --------------------------------------
# Espelha os parsers do web (score-icpc.js / score-obi.js / score-generic.js): linha 1 =
# modo (pode trazer a flag `s` = célula icpc em SEGUNDOS, R6 — exibimos floor(seg/60) e
# gravamos o segundo exato em data-sec p/ a estrela do recorte do rep_filter_js; sem a
# flag, minutos = legado); linha 2 = cabeçalho COM marcadores iniciais desc/asc (as linhas
# de dados NÃO têm os marcadores — alinham 1:1 com o cabeçalho já sem eles); células icpc:
# vazio | t/tempo | t/tempo* (first to solve) | t/-.
# Cada <tr> leva data-place (posição original; vazio = convidado) e data-tie (chave de
# empate) — é com eles que o rep_filter_js RENUMERA o recorte (R1). PHF = photos.tsv: 📷
# relativo em fotos/<login>.webp, passado SÓ p/ o placar aberto (freeze não mostra foto).
rep_score_html(){ # <placar.txt> [genplace.tsv] [photos.tsv]
  local f="$1" gp="${2:-}" ph="${3:-}"
  [[ -s "$f" ]] || { printf '<p class="note">%s</p>\n' "$(rep_t no_score)"; return; }
  [[ -n "$gp" && -s "$gp" ]] || gp=/dev/null
  [[ -n "$ph" && -s "$ph" ]] || ph=/dev/null
  awk -F: -v MODE="$MODE" -v BSTYLE="$BSTYLE" -v BF="$W/balloons.tsv" -v FF="$W/flags.tsv" -v NF_="$W/names.tsv" \
      -v GP="$gp" -v PHF="$ph" -v T_GEN="$(rep_t gen_place)" -v T_GENT="$(rep_t gen_place_t)" \
      -v T_TEAM="$(rep_t team_col)" -v T_TOTAL="$(rep_t total)" -v T_PEN="$(rep_t pen_col)" \
      -v T_GUEST="$(rep_t guest)" -v T_GUESTT="$(rep_t guest_title)" -v T_FTS="$(rep_t fts)" \
      -v T_PHOTO="$(rep_t photo_t)" '
    function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
    function esc(s){ gsub(/&/,"\\&amp;",s); gsub(/</,"\\&lt;",s); gsub(/>/,"\\&gt;",s); gsub(/"/,"\\&quot;",s); return s }
    function issys(h){ return (h=="flag"||h=="username"||h=="univ short"||h=="team name"||h=="univ full"||h=="total"||h=="penalty"||h=="lastac"||h=="guest") }
    # bsvg(): gêmeo do balloonSVG (score-colors.js). O cabeçalho marcava a coluna com uma barra
    # de 4px na cor: branco sobre --blue-soft era invisível, então o problema A não tinha
    # indicação de cor NENHUMA no relatório. O balão tem contorno e resolve.
    function bsvg(c){ return "<svg class=\"balloon-svg\" viewBox=\"0 0 42 47\" aria-hidden=\"true\">" \
      "<ellipse cx=\"21\" cy=\"21\" rx=\"18\" ry=\"18\" fill=\"" c "\" stroke=\"#b2b2b2\" stroke-width=\"2\"/>" \
      "<ellipse cx=\"16\" cy=\"14\" rx=\"5\" ry=\"5.1\" fill=\"#fff\" fill-opacity=\".48\"/>" \
      "<polygon points=\"18,36 24,36 21,46\" fill=\"" c "\" stroke=\"#b2b2b2\" stroke-width=\"1.4\" stroke-linejoin=\"round\"/>" \
      "</svg>" }
    # fimg[] já vem pronto (<img> com o SVG em data URI, montado em rep_flag); código sem
    # bandeira conhecida vira texto discreto em vez de sumir.
    function flag_html(v){ if(v=="")return ""; if(v in fimg) return fimg[v]; return "<span class=\"small muted\" title=\"" esc(v) "\">" esc(v) "</span>" }
    function team_html(us,tn,uf,un,g,  lbl){
      lbl=""; if(us!="") lbl="[" esc(us) "] ";
      lbl=lbl esc(tn!=""?tn:un)
      # 📷 relativo (fotos/<login>.webp) — só quem está no photos.tsv; o visualizador de
      # rodadas intercepta o <a href> e abre via blob, e em file:// o relativo resolve
      if(un in pho) lbl=lbl " <a class=\"tphoto\" href=\"fotos/" un ".webp\" title=\"" esc(T_PHOTO) "\" style=\"text-decoration:none\">&#128247;</a>"
      if(g) lbl=lbl " <span class=\"pill\" title=\"" esc(T_GUESTT) "\">" esc(T_GUEST) "</span>"
      # o LOGIN saiu da célula (era o que mais gastava largura) e vive no title, junto da
      # universidade — a coluna do time agora divide espaço com todas as de problema.
      ttl = (uf!=""?uf:us)
      if(un!="") ttl = (ttl!="" ? ttl " · " un : un)
      return "<td class=\"team\" title=\"" esc(ttl) "\">" lbl "</td>"
    }
    BEGIN{
      while ((getline l < BF) > 0) { n=split(l,a,"\t"); if(n>=3){ bhex[a[1]]=a[2]; bdark[a[1]]=a[3]; if(n>=4) bedge[a[1]]=a[4] } }
      close(BF)
      # fotos: login por linha (já validado e copiado p/ fotos/ pelo gerador)
      while ((getline l < PHF) > 0) { if(l!="") pho[l]=1 }
      close(PHF)
      # flags.tsv: código \t nome legível \t <img>. O nome alimenta o rótulo do filtro por
      # bandeira (data-fname) — é a MESMA resolução do alt/title (rep_flag_name).
      while ((getline l < FF) > 0) { n=split(l,a,"\t"); if(n>=3){ fimg[a[1]]=a[3]; fnm[tolower(a[1])]=a[2] } }
      close(FF)
      # sede (.team.region) só existe na conta, não no TXT do placar: 6º campo do names.tsv.
      while ((getline l < NF_) > 0) { n=split(l,a,"\t"); if(n>=6 && a[1]!="") reg[a[1]]=a[6] }
      close(NF_)
      # posição no placar GERAL, por login (vazio = este É o placar geral)
      while ((getline l < GP) > 0) { n=split(l,a,"\t"); if(n>=2 && a[1]!=""){ gpl[a[1]]=a[2]; hasgp=1 } }
      close(GP)
    }
    NR==1{ nw=split($0, MW, /[ \t]+/); for(wi=2; wi<=nw; wi++) if(MW[wi]=="s") SECS=1; next }
    NR==2{
      n=split($0, H, ":"); s=1
      while (s<=n) { h=trim(tolower(H[s])); if (h=="desc"||h=="asc") s++; else break }
      ncol=0; for(i=s;i<=n;i++){ ncol++; hdr[ncol]=H[i] }
      iflag=iuser=ius=iteam=iuf=itot=ipen=ilast=iguest=0
      for(i=1;i<=ncol;i++){ h=trim(tolower(hdr[i]))
        if(h=="flag")iflag=i; else if(h=="username")iuser=i; else if(h=="univ short")ius=i
        else if(h=="team name")iteam=i; else if(h=="univ full")iuf=i; else if(h=="total")itot=i
        else if(h=="penalty")ipen=i; else if(h=="lastac")ilast=i; else if(h=="guest")iguest=i }
      probend=(itot? itot-1 : ncol); np=0
      for(i=1;i<=probend;i++){ h=trim(tolower(hdr[i])); if(!issys(h)){ np++; pcol[np]=i; pname[np]=trim(hdr[i]) } }
      # placar NÃO rola para o lado: largura por <colgroup> + table-layout:fixed (a conta das
      # frações mora no ui.css, que este relatório inlina). --nprob diz o cenário.
      vars = "--nprob:" (np?np:1)
      if(!iflag) vars = vars ";--w-flag:0%"
      if(!(MODE=="icpc" && ipen)) vars = vars ";--w-pen:0%"
      # a classe de MODO acompanha o placar ao vivo: é ela que escopa ao ICPC o ✓/✗ do celular
      # (no OBI a célula é a NOTA — ver ui.css, que este relatório inlina)
      printf "<div class=\"board-wrap\"><table class=\"score m-%s\" style=\"%s\">\n", (MODE=="icpc"?"icpc":(MODE=="obi"?"obi":"generic")), vars
      printf "<colgroup><col class=\"c-place\">"
      if(iflag) printf "<col class=\"c-flag\">"
      printf "<col class=\"c-team\">"
      for(k=1;k<=np;k++) printf "<col class=\"c-prob\">"
      if (MODE=="icpc" || MODE=="obi") printf "<col class=\"c-total\">"
      if (MODE=="icpc" && ipen) printf "<col class=\"c-pen\">"
      printf "</colgroup>\n"
      # em placar de COORTE a coluna # leva dois números: a posição na coorte (grande) e a do
      # placar geral (pequena, cinza) — sem coluna nova, senão o placar voltaria a não caber.
      printf "<thead><tr><th>#%s</th>", (hasgp? "<span class=\"plg\">" esc(T_GEN) "</span>" : "")
      if (MODE=="icpc" || MODE=="obi") {
        if(iflag) printf "<th></th>"
        printf "<th>%s</th>", T_TEAM
        for(k=1;k<=np;k++){
          ic=""
          if (pname[k] in bhex) ic=bsvg("#" bhex[pname[k]]) " "
          printf "<th class=\"prob\">%s%s</th>", ic, esc(pname[k])
        }
        printf "<th>%s</th>", T_TOTAL
        if (MODE=="icpc" && ipen) printf "<th>%s</th>", T_PEN
      } else {
        for(i=1;i<=ncol;i++) printf "<th>%s</th>", esc(trim(hdr[i])=="flag" ? "" : hdr[i])
      }
      printf "</tr></thead>\n<tbody>\n"
      next
    }
    NF==0{ next }
    {
      rr++
      # COLOCAÇÃO igual à do placar ao vivo (score-icpc.js:62-68): empate real exige os TRÊS
      # critérios (resolvidos + penalidade + minuto do último AC) — antes empatava só por
      # total e a classificação do relatório divergia da oficial. E CONVIDADO não consome
      # posição: aparece na linha do desempenho dele, com "–" no lugar do número.
      guest=(iguest ? trim($(iguest)) : "")
      isguest=(guest!="" && guest!="0" && tolower(guest)!="false" && tolower(guest)!="no")
      pnum=""
      if (MODE=="icpc") {
        tot=(itot? trim($(itot)) : ""); pen=(ipen? trim($(ipen)) : ""); lac=(ilast? trim($(ilast)) : "")
        if (!isguest) {
          # ranking de COMPETIÇÃO (2026-08-31): empatado compartilha a posição e CONSOME —
          # N empatados em P ⇒ o próximo é P+N (a numeração era densa: P+1)
          nseen++
          if (nseen>1 && tot==prevtot && pen==prevpen && lac==prevlac) place=prevplace
          else place=nseen
          prevtot=tot; prevpen=pen; prevlac=lac; prevplace=place; pnum=place
        }
      } else if (!isguest) { nseen++; pnum=nseen }
      # DADOS DO FILTRO na própria linha (o script do relatório não tem de onde buscar nada:
      # sem fetch, sem import). data-search cobre o login, que saiu do texto visível.
      fcode=(iflag? tolower(trim($(iflag))) : "")
      un=(iuser? trim($(iuser)) : ""); us=(ius? trim($(ius)) : ""); uf=(iuf? trim($(iuf)) : "")
      tn=(iteam? trim($(iteam)) : "")
      rg=(un in reg ? reg[un] : "")
      attrs=(isguest? " class=\"guest-row\"" : "")
      if(fcode!="") {
        cc=fcode; sub(/-.*$/,"",cc)   # país = prefixo (br-rj → br); filtro hierárquico
        attrs=attrs " data-flag=\"" esc(fcode) "\" data-fname=\"" esc(fcode in fnm ? fnm[fcode] : toupper(fcode)) "\""
        attrs=attrs " data-country=\"" esc(cc) "\" data-cname=\"" esc(cc in fnm ? fnm[cc] : toupper(cc)) "\""
      }
      if(us!="")    attrs=attrs " data-univ=\"" esc(us) "\""
      if(uf!="")    attrs=attrs " data-ufull=\"" esc(uf) "\""
      if(rg!="")    attrs=attrs " data-region=\"" esc(rg) "\""
      attrs=attrs " data-search=\"" esc(tolower(tn " " us " " uf " " un)) "\""
      # renumeração do recorte (R1): posição original + chave de empate (a MESMA regra do
      # pnum acima) — o rep_filter_js renumera os visíveis e restaura ao limpar
      attrs=attrs " data-place=\"" (isguest? "" : pnum) "\""
      if (MODE=="icpc" && !isguest) attrs=attrs " data-tie=\"" esc(tot "|" pen "|" lac) "\""
      gtxt=""
      if (hasgp && !isguest && (un in gpl)) gtxt="<span class=\"plg\" title=\"" esc(T_GENT) "\">" esc(gpl[un]) "</span>"
      printf "<tr%s><td class=\"place\">%s%s</td>", attrs, (isguest?"–":pnum ""), gtxt
      if (MODE=="icpc" || MODE=="obi") {
        if(iflag) printf "<td>%s</td>", flag_html(trim($(iflag)))
        printf "%s", team_html((ius?trim($(ius)):""), (iteam?trim($(iteam)):""), (iuf?trim($(iuf)):""), (iuser?trim($(iuser)):""), isguest)
        for(k=1;k<=np;k++){
          v=trim($(pcol[k]))
          if (MODE=="icpc") {
            if (v ~ /^[0-9]+\/[0-9]+\/?\*?$/) {
              fts=(v ~ /\*$/); shown=v; if(fts) sub(/\*$/,"",shown)
              # unidade da célula: segundos com a flag `s` (exibe floor/60); minutos no legado.
              # data-sec = segundo exato — é dele que o rep_filter_js tira a ★ do recorte.
              split(shown, tv_, "/"); sec = (SECS ? tv_[2]+0 : (tv_[2]+0)*60)
              shown = tv_[1] "/" int(sec/60)
              # gêmeo de paintSolvedCell (web/contest/score/score-colors.js): 'icon' = fundo
              # neutro + ponto da cor; 'fill' = cor no fundo + contorno derivado.
              dot=""
              if (BSTYLE=="fill" && (pname[k] in bhex)) {
                sty="background:#" bhex[pname[k]] ";color:" (bdark[pname[k]]==1?"#fff":"#222")
                if(!fts && (pname[k] in bedge)) sty=sty ";box-shadow:inset 0 0 0 1px #" bedge[pname[k]]
              } else {
                sty="background:#e2ffe9;color:#222"
                if (pname[k] in bhex)
                  dot="<span class=\"bdot\" style=\"--bdot:#" bhex[pname[k]] ";--bdot-edge:#" (pname[k] in bedge ? bedge[pname[k]] : "8A8A8A") "\"></span>"
              }
              sty=sty ";font-weight:700"; if(fts) sty=sty ";box-shadow:inset 0 0 0 2px currentColor"
              # a ★ global leva a classe gfts: com filtro ativo o rep_filter_js a esconde e
              # pinta a rfts do recorte (o anel inline continua marcando o FTS global)
              printf "<td class=\"cell ok\" data-sec=\"%d\" style=\"%s\"%s>%s%s<span class=\"pv\">%s</span></td>", sec, sty, (fts?" title=\"" esc(T_FTS) "\"":""), (fts?"<span class=\"fts gfts\">&#9733;</span>":""), dot, esc(shown)
            } else if (v ~ /^[0-9]+\/-/) printf "<td class=\"cell c-try\"><span class=\"pv\">%s</span></td>", esc(v)
            else printf "<td class=\"cell\">%s</td>", esc(v)
          } else {   # obi: pontos
            if (v!="" && v+0>0) printf "<td class=\"cell ok\" style=\"background:#dde9ff;color:#1346aa;font-weight:700\"><span class=\"pv\">%s</span></td>", esc(v)
            else if (v=="0")    printf "<td class=\"cell c-try\" style=\"background:#fbe7e9;color:#c4314b;font-weight:700\"><span class=\"pv\">%s</span></td>", esc(v)
            else printf "<td class=\"cell\"></td>"
          }
        }
        printf "<td class=\"cell tot\"><b>%s</b></td>", esc(itot? trim($(itot)) : "")
        if (MODE=="icpc" && ipen) printf "<td class=\"cell pen\"><span class=\"pv\">%s</span></td>", esc(trim($(ipen)))
      } else {       # generic: colunas livres do cabeçalho
        for(i=1;i<=ncol;i++){
          v=trim($(i))
          if (i==iflag) printf "<td>%s</td>", flag_html(v)
          else printf "<td>%s</td>", esc(v)
        }
      }
      printf "</tr>\n"
    }
    END{ printf "</tbody></table></div>\n" }
  ' "$f"
}

# --- placares por VISÃO de coorte + barra de filtros ------------------------------------
# O contest pode ter coortes (individual × times, oficiais × convidados/CCL). O build.sh já
# gera UM TXT por visão, com posição e ESTRELA corretas dentro dela — por isso o seletor de
# coorte TROCA de placar (como o `?view=` da página ao vivo) em vez de esconder linhas: a
# estrela de first-to-solve é mínimo global e filtrar o TXT pronto mostraria a estrela errada
# (a armadilha está documentada em lib/cohorts.sh). Bandeira/universidade/sede/busca, sim,
# são recorte de linhas do placar exibido — e vão em `data-*` na <tr>.

# rep_view_label <id> -> rótulo da visão (nome da coorte é conteúdo do usuário: não traduz).
# Visão de coorte PÚBLICA com ranking = o placar paralelo dela (só ela) ⇒ o nome basta.
# Visão de coorte PRIVADA = o que ELA vê (as públicas + ela) ⇒ tem de dizer "visão de".
rep_view_label(){
  local nm
  case "$1" in
    public) rep_t view_public;;
    all)    rep_t view_all;;
    *) nm="$(jq -r --arg i "$1" 'first(.cohorts[] | select(.id == $i) | .name) // $i' \
              <<<"$(ch_get "$C")" 2>/dev/null)"; [[ -n "$nm" ]] || nm="$1"
       if jq -e --arg i "$1" 'any(.cohorts[]; .id == $i and .public == false)' \
            <<<"$(ch_get "$C")" >/dev/null 2>&1
       then rep_t view_of "$nm"; else printf '%s' "$nm"; fi;;
  esac
}

# rep_place_map <placar.txt> -> "login \t posição" (só quem tem posição; convidado não tem)
# ⚠ MESMA regra de empate do rep_score_html (resolvidos + penalidade + minuto do último AC):
# se mudar lá, mude aqui — é o número que aparece como "posição no placar geral".
rep_place_map(){
  awk -F: '
    function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
    NR==1{ next }
    NR==2{ n=split($0,H,":"); s=1
      while (s<=n) { h=trim(tolower(H[s])); if (h=="desc"||h=="asc") s++; else break }
      ncol=0; for(i=s;i<=n;i++){ ncol++; hdr[ncol]=H[i] }
      for(i=1;i<=ncol;i++){ h=trim(tolower(hdr[i]))
        if(h=="username")iuser=i; else if(h=="total")itot=i; else if(h=="penalty")ipen=i
        else if(h=="lastac")ilast=i; else if(h=="guest")iguest=i }
      next }
    NF==0{ next }
    {
      g=(iguest? trim($(iguest)) : "")
      if (g!="" && g!="0" && tolower(g)!="false" && tolower(g)!="no") next
      tot=(itot? trim($(itot)) : ""); pen=(ipen? trim($(ipen)) : ""); lac=(ilast? trim($(ilast)) : "")
      if (n_>0 && tot==pt_ && pen==pp_ && lac==pl_) place=pc_
      else { n_++; place=n_ }
      pt_=tot; pp_=pen; pl_=lac; pc_=place
      if (iuser && trim($(iuser))!="") printf "%s\t%s\n", trim($(iuser)), place
    }' "$1"
}

# rep_score_boards <open|frozen> — a barra de filtros + um <section> por visão
rep_score_boards(){
  local kind="$1" v lbl f ck gen genf n=0 cj phf=""
  # 📷 SÓ no placar aberto (R4/R5): o congelado não mostra foto — não denuncia presença
  [[ "$kind" == open && -s "$W/photos.tsv" ]] && phf="$W/photos.tsv"
  local -a ids=() labels=() files=() cks=() have=() cand=()
  mapfile -t have < <(ch_views "$C" 2>/dev/null)
  # ORDEM do seletor (e da dedupe): pública › placares paralelos › todos › visão de coorte
  # privada. `all` tem de vir ANTES da visão privada: quando a coorte privada vê todo mundo os
  # dois placares são idênticos, e o rótulo que fica é o do primeiro — "Todos, com convidados"
  # descreve melhor do que "Visão da coorte X".
  cj="$(ch_get "$C" 2>/dev/null)"
  cand=( public )
  mapfile -t -O "${#cand[@]}" cand < <(jq -r '.cohorts[]|select(.public and .ranking)|.id' <<<"$cj" 2>/dev/null)
  cand+=( all )
  mapfile -t -O "${#cand[@]}" cand < <(jq -r '.cohorts[]|select(.public == false)|.id' <<<"$cj" 2>/dev/null)
  for v in "${cand[@]}"; do
    [[ -n "$v" ]] || continue
    printf '%s\n' "${have[@]+"${have[@]}"}" | grep -qxF "$v" || continue
    if [[ "$kind" == open ]] && (( FREEZE > 0 )); then
      f="$(ch_view_file "$C" "$v" full)"; [[ -s "$f" ]] || f="$(ch_view_file "$C" "$v")"
    else
      f="$(ch_view_file "$C" "$v")"
    fi
    [[ -s "$f" ]] || continue
    # placares idênticos (no esquenta `public` e `all` são a mesma coisa, porque toda coorte é
    # pública) apareceriam duas vezes no seletor: dedup por conteúdo.
    ck="$(cksum < "$f")"
    printf '%s\n' "${cks[@]+"${cks[@]}"}" | grep -qxF "$ck" && continue
    ids+=("$v"); labels+=("$(rep_view_label "$v")"); files+=("$f"); cks+=("$ck")
    n=$((n+1))
  done

  (( n > 0 )) || { rep_score_html ""; return; }

  # placar GERAL = a visão `all` quando existir (é a que tem todo mundo), senão a pública.
  # É dele que sai a "posição geral" mostrada nos placares de coorte.
  gen=0; for ((i=0;i<n;i++)); do [[ "${ids[$i]}" == all ]] && gen=$i; done
  genf="$W/genplace.tsv"; rep_place_map "${files[$gen]}" > "$genf" 2>/dev/null || : > "$genf"

  # as bandeiras usadas vão no <style> só das páginas que têm placar (o rep_css é comum às 7)
  rep_flag_css
  rep_filter_bar ids labels
  for ((i=0;i<n;i++)); do
    printf '<section class="board-view" data-view="%s" data-label="%s"%s>\n' \
      "$(esc "${ids[$i]}")" "$(esc "${labels[$i]}")" "$([[ $i -eq 0 ]] || printf ' hidden')"
    if (( n > 1 )); then
      printf '<h3>%s</h3>\n' "$(esc "${labels[$i]}")"
      [[ "${ids[$i]}" == public || "${ids[$i]}" == all ]] \
        || printf '<p class="note">%s</p>\n' "$(rep_t cohort_note "${labels[$i]}")"
    fi
    # a segunda posição só entra quando INFORMA algo: no placar geral (e em qualquer visão cuja
    # classificação seja a mesma dele, como a pública quando não há coorte privada) seria uma
    # coluna repetindo o número ao lado.
    if (( i == gen )); then rep_score_html "${files[$i]}" "" "$phf"
    else
      rep_place_map "${files[$i]}" > "$W/vplace.tsv" 2>/dev/null || : > "$W/vplace.tsv"
      if cmp -s "$W/vplace.tsv" "$genf"; then rep_score_html "${files[$i]}" "" "$phf"
      else rep_score_html "${files[$i]}" "$genf" "$phf"; fi
    fi
    printf '</section>\n'
  done
  rep_filter_js
}

# rep_filter_bar <nome-do-array-de-ids> <nome-do-array-de-rótulos>
# Sem fetch/import/src (invariante do relatório): as opções de bandeira/universidade/sede são
# montadas pelo próprio script a partir dos data-* das linhas do placar VISÍVEL — igual ao
# placar ao vivo, que monta as opções a partir dos times presentes.
rep_filter_bar(){
  local -n _ids="$1" _lbls="$2"
  local i
  # com filtro ativo (classe flt na section) a ★ GLOBAL some e a do recorte (rfts) entra —
  # o rep_filter_js pinta; os textos do JS vão em data-* (o heredoc dele é quoted)
  printf '<style>.board-view.flt span.fts.gfts{display:none}</style>\n'
  printf '<div class="fbar" id="fbar" data-tpl="%s" data-slice-t="%s" data-fts-sel="%s" data-slice-note="%s">\n' \
    "$(esc "$(rep_t f_count)")" "$(esc "$(rep_t f_slice_t)")" "$(esc "$(rep_t fts_sel)")" "$(esc "$(rep_t f_slice_note)")"
  if (( ${#_ids[@]} > 1 )); then
    printf '<label>%s <select id="fView">' "$(esc "$(rep_t f_board)")"
    for i in "${!_ids[@]}"; do
      printf '<option value="%s">%s</option>' "$(esc "${_ids[$i]}")" "$(esc "${_lbls[$i]}")"
    done
    printf '</select></label>\n'
  fi
  printf '<label>%s <select id="fFlag"><option value="">%s</option></select></label>\n' \
    "$(esc "$(rep_t f_flag)")" "$(esc "$(rep_t f_flag_all)")"
  printf '<label>%s <select id="fUniv"><option value="">%s</option></select></label>\n' \
    "$(esc "$(rep_t f_univ)")" "$(esc "$(rep_t f_univ_all)")"
  printf '<label>%s <select id="fRegion"><option value="">%s</option></select></label>\n' \
    "$(esc "$(rep_t f_region)")" "$(esc "$(rep_t f_region_all)")"
  printf '<input class="filter" id="fQ" type="search" placeholder="%s">\n' "$(esc "$(rep_t f_search)")"
  printf '<button type="button" id="fClear">%s</button>\n' "$(esc "$(rep_t f_clear)")"
  printf '<span class="fcount" id="fCount"></span>\n</div>\n'
  # sem JS: a barra não serve p/ nada e os placares escondidos têm de aparecer (cada um tem <h3>)
  printf '<noscript><style>.fbar{display:none}.board-view[hidden]{display:block}</style></noscript>\n'
}

# rep_filter_js — vai DEPOIS dos placares: script inline roda na hora em que é parseado, e antes
# das <section> existirem o querySelectorAll voltava vazio (a barra ficava decorativa).
rep_filter_js(){
  cat <<'FBAREOF'
<script>
(function(){
  var bar=document.getElementById('fbar'); if(!bar) return;
  var boards=[].slice.call(document.querySelectorAll('.board-view')); if(!boards.length) return;
  var selV=document.getElementById('fView'), selF=document.getElementById('fFlag'),
      selU=document.getElementById('fUniv'), selR=document.getElementById('fRegion'),
      q=document.getElementById('fQ'), cnt=document.getElementById('fCount'),
      tpl=bar.getAttribute('data-tpl')||'%s/%s';
  function board(){ for(var i=0;i<boards.length;i++) if(!boards[i].hidden) return boards[i]; return boards[0]; }
  function rows(b){ var t=b&&b.querySelector('table.score'); return (t&&t.tBodies[0])?[].slice.call(t.tBodies[0].rows):[]; }
  function fill(sel,attr,label){
    if(!sel) return;
    var cur=sel.value, seen={}, opts=[];
    rows(board()).forEach(function(r){
      var v=r.getAttribute(attr); if(!v||seen[v]) return; seen[v]=1;
      opts.push([v,label(r,v)]);
    });
    opts.sort(function(a,b){ return String(a[1]).localeCompare(String(b[1])) });
    while(sel.options.length>1) sel.remove(1);
    opts.forEach(function(o){ var e=document.createElement('option'); e.value=o[0]; e.textContent=o[1]; sel.add(e) });
    sel.value = seen[cur] ? cur : '';
    if(sel.parentNode) sel.parentNode.style.display = opts.length ? '' : 'none';
  }
  // bandeira HIERÁRQUICA (2026-08-30): país primeiro (agrega estados no casamento),
  // estados indentados abaixo — mesma regra do placar ao vivo e do by_country das stats
  function fillFlag(){
    if(!selF) return;
    var cur=selF.value, byC={}, cn={}, sn={};
    rows(board()).forEach(function(r){
      var c=r.getAttribute('data-country'), f=r.getAttribute('data-flag');
      if(!c) return;
      cn[c]=r.getAttribute('data-cname')||c.toUpperCase();
      if(!byC[c]) byC[c]={};
      if(f&&f!==c){ byC[c][f]=1; sn[f]=r.getAttribute('data-fname')||f; }
    });
    var opts=[];
    Object.keys(byC).sort(function(a,b){ return String(cn[a]).localeCompare(String(cn[b])) }).forEach(function(c){
      opts.push([c,cn[c]]);
      Object.keys(byC[c]).sort(function(a,b){ return String(sn[a]).localeCompare(String(sn[b])) }).forEach(function(f){
        opts.push([f,'  '+sn[f]]);
      });
    });
    while(selF.options.length>1) selF.remove(1);
    var seen={};
    opts.forEach(function(o){ seen[o[0]]=1; var e=document.createElement('option'); e.value=o[0]; e.textContent=o[1]; selF.add(e) });
    selF.value = seen[cur]?cur:'';
    if(selF.parentNode) selF.parentNode.style.display = opts.length?'':'none';
  }
  function refill(){
    fillFlag();
    fill(selU,'data-univ',function(r,v){ var f=r.getAttribute('data-ufull'); return f?(v+' — '+f):v });
    fill(selR,'data-region',function(r,v){ return v });
  }
  // Filtro ativo RENUMERA o recorte (R1, 2026-08-30) e re-estrela por data-sec (R6) —
  // tudo idempotente: cada apply() restaura o DOM original antes de reaplicar.
  var sliceT=bar.getAttribute('data-slice-t')||'', ftsSel=bar.getAttribute('data-fts-sel')||'',
      sliceNote=bar.getAttribute('data-slice-note')||'';
  function apply(){
    var f=selF?selF.value:'', u=selU?selU.value:'', g=selR?selR.value:'',
        s=(q?q.value:'').trim().toLowerCase(), tot=0, vis=0;
    var b=board(), rs=rows(b), act=!!(f||u||g||s), visRows=[];
    // restaura a passada anterior
    rs.forEach(function(r){ if(r._pl!=null){ r.cells[0].innerHTML=r._pl; r._pl=null; } });
    [].slice.call(b.querySelectorAll('span.rfts')).forEach(function(x){ x.remove(); });
    b.classList.remove('flt');
    rs.forEach(function(r){
      tot++;
      // bandeira: valor sem hífen é PAÍS (casa por data-country, que agrega os estados);
      // com hífen é estado exato (data-flag)
      var okF=!f || (f.indexOf('-')>=0 ? r.getAttribute('data-flag')===f
                                       : r.getAttribute('data-country')===f);
      var ok=okF && (!u||r.getAttribute('data-univ')===u)
          && (!g||r.getAttribute('data-region')===g)
          && (!s||(r.getAttribute('data-search')||'').indexOf(s)>=0);
      r.style.display=ok?'':'none'; if(ok){ vis++; visRows.push(r); }
    });
    var icpc = !!b.querySelector('table.score.m-icpc');
    if(act){
      b.classList.add('flt');
      // renumera: mesma regra de empate do gerador (data-tie); convidado (data-place vazio)
      // mantém o "–"; o número original vai p/ o .plg
      var sp=0, cur=0, ptie=null;
      visRows.forEach(function(r){
        var op=r.getAttribute('data-place'); if(!op) return;
        var tie=r.getAttribute('data-tie')||'';
        sp++;                                       // ranking de competição: todo visível consome
        if(!(ptie!==null && tie!=='' && tie===ptie)) cur=sp;
        ptie=tie;
        var td=r.cells[0]; if(r._pl==null) r._pl=td.innerHTML;
        td.textContent=String(cur);
        var sm=document.createElement('span'); sm.className='plg'; sm.title=sliceT;
        sm.textContent=op; td.appendChild(sm);
      });
      // ★ do recorte: menor data-sec por COLUNA entre os visíveis (segundos exatos com a
      // flag `s` do TXT; min*60 no legado — empate de minuto pode dar mais de uma ★)
      if(icpc){
        var best={};
        visRows.forEach(function(r){ [].slice.call(r.cells).forEach(function(td,ci){
          var sv=td.getAttribute('data-sec'); if(sv===null) return;
          sv=+sv; if(!(ci in best)||sv<best[ci]) best[ci]=sv; }); });
        visRows.forEach(function(r){ [].slice.call(r.cells).forEach(function(td,ci){
          var sv=td.getAttribute('data-sec'); if(sv===null) return;
          if(+sv===best[ci]){ var st=document.createElement('span'); st.className='fts rfts';
            st.title=ftsSel; st.textContent='★'; td.insertBefore(st, td.firstChild); }
        }); });
      }
    }
    if(cnt) cnt.textContent=tpl.replace('%s',vis).replace('%s',tot)+(act&&icpc?' '+sliceNote:'');
  }
  if(selV) selV.addEventListener('change',function(){
    boards.forEach(function(b){ b.hidden = b.getAttribute('data-view')!==selV.value });
    refill(); apply();
  });
  [selF,selU,selR].forEach(function(s){ if(s) s.addEventListener('change',apply) });
  if(q) q.addEventListener('input',apply);
  var clr=document.getElementById('fClear');
  if(clr) clr.addEventListener('click',function(){
    [selF,selU,selR].forEach(function(s){ if(s) s.value='' }); if(q) q.value=''; apply();
  });
  refill(); apply();
})();
</script>
FBAREOF
}

# --- histórico de runs (TSV intermediário: epoch login letter lang verdict subid team us uf) ---
emit_history_stream "$C" > "$W/hist.txt"
awk -F: -v NAMES="$W/names.tsv" -v PROBS="$W/probs.tsv" "$VERDICT_CANON_AWK"'
  BEGIN{
    while ((getline l < NAMES) > 0) { n=split(l,a,"\t"); if(n>=1 && !(a[1] in tname)){ tname[a[1]]=a[2]; tus[a[1]]=a[3]; tuf[a[1]]=a[4] } }
    close(NAMES)
    while ((getline l < PROBS) > 0) { n=split(l,a,"\t"); if(n>=7){ L[a[4]]=a[1]; L[a[5]]=a[1]; L[a[6]]=a[1]; L[a[7]]=a[1] } }
    close(PROBS)
  }
  NF>=6 {
    if ($2 ~ /\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$/ || $2=="admin") next   # cstaff INCLUÍDO: não casa \.staff$
    login=$2; prob=$3; lang=$4
    v=$5; for(i=6;i<=NF-2;i++) v=v":"$i
    se=$(NF-1)+0; sid=$NF
    letter=(prob in L)? L[prob] : prob
    printf "%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", se, login, letter, lang, canon(v), sid, tname[login], tus[login], tuf[login]
  }' "$W/hist.txt" | sort -n -k1,1 > "$W/runs.tsv"
RUNS_N="$(wc -l < "$W/runs.tsv" | tr -d '[:space:]')"
TEAMS_N="$(awk -F'\t' '$1!~/\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$/ && $1!="admin" && $1!=""' "$W/names.tsv" | sort -u | wc -l | tr -d '[:space:]')"

# --- autor do problema (o crédito de quem escreveu) ------------------------------------
# Fonte canônica: o arquivo `author` do PACOTE (texto livre, um autor por linha, já é nome de
# exibição — não é login). Fallback: o `.author` do JSON do banco, a mesma cadeia que o
# enunciado usa logo abaixo. Snapshot na geração: pacote editado depois não reescreve o
# relatório de uma prova que já aconteceu.
rep_author(){   # <statement_key>
  local skey="$1" pkg a=""
  pkg="$MOJ_PROBLEMS_DIR/${skey%%#*}/${skey##*#}"
  [[ -d "$pkg" ]] || pkg="$MOJ_PROBLEMS_DIR/${skey//#//}"
  if [[ -s "$pkg/author" ]]; then
    a="$(grep -v '^[[:space:]]*$' "$pkg/author" 2>/dev/null | paste -sd'|' - | sed 's/|/, /g')"
  fi
  if [[ -z "$a" ]]; then
    local jf="$CONTESTSDIR/treino/var/jsons/$skey.json"
    [[ -f "$jf" ]] || jf="$CONTESTSDIR/treino/var/jsons-private/$skey.json"
    [[ -f "$jf" ]] && a="$(jq -r '.author // ""' "$jf" 2>/dev/null)"
  fi
  printf '%s' "${a//[$'\t\n']/ }"
}

# --- enunciados: copia p/ statements/<LETRA>.{html,pdf} (com fallback do banco) --------
# stmt.tsv: letter \t fullname \t has_html(0/1) \t has_pdf(0/1) \t url \t autor
: > "$W/stmt.tsv"
while IFS=$'\t' read -r pshort pfull pskey _off _raw _dot _hash; do
  Lsafe="$(printf '%s' "$pshort" | tr -cd 'A-Za-z0-9._-')"; [[ -n "$Lsafe" ]] || Lsafe="p$_off"
  hh=0; hp=0; url=""; pauthor="$(rep_author "$pskey")"
  if [[ "$pskey" == *http* ]]; then
    url="$pskey"
  else
    if [[ -f "$CDIR/enunciados/$pskey.html" ]]; then
      cp -f "$CDIR/enunciados/$pskey.html" "$OUTD/statements/$Lsafe.html" && hh=1
    else
      # fallback: banco do treino (mesma cadeia do handler contest/problems.sh)
      jf="$CONTESTSDIR/treino/var/jsons/$pskey.json"
      [[ -f "$jf" ]] || jf="$CONTESTSDIR/treino/var/jsons-private/$pskey.json"
      if [[ -f "$jf" ]] && jq -e '(.statement_html_b64 // "") != ""' "$jf" >/dev/null 2>&1; then
        jq -r '.statement_html_b64 // ""' "$jf" 2>/dev/null | base64 -d > "$OUTD/statements/$Lsafe.html" 2>/dev/null && hh=1
      fi
    fi
    [[ -f "$CDIR/enunciados/$pskey.pdf" ]] && cp -f "$CDIR/enunciados/$pskey.pdf" "$OUTD/statements/$Lsafe.pdf" && hp=1
  fi
  # ⚠ campo vazio NO MEIO da linha some no `IFS=$'\t' read`: TAB é whitespace, então dois
  # seguidos contam como UM separador (foi assim que o autor sumiu quando a url é vazia —
  # o caso normal). Sentinela "-" em quem pode ser vazio; o leitor desfaz.
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$Lsafe" "$pfull" "$hh" "$hp" "${url:--}" "${pauthor:--}"
done < "$W/probs.tsv" >> "$W/stmt.tsv"

# --- placares: aberto (index) + congelado (se houver freeze) ---------------------------
FROZEN_NOTE=""
if (( FREEZE > 0 )) && [[ -f "$CDIR/var/placar-full.txt" ]]; then
  fmin=$(( (FREEZE - START) / 60 ))
  {
    rep_head "$(rep_t frozen_title)" frozen
    printf '<p class="note">%s <a href="index.html">%s</a>.</p>\n' \
      "$(rep_t frozen_note "$fmin" "$(fmt_dt "$FREEZE")")" "$(rep_t tab_score)"
    rep_score_boards frozen
    rep_foot
  } > "$OUTD/score-frozen.html"
  FROZEN_NOTE="<p class=\"note\">$(rep_t open_note "$fmin") <a href=\"score-frozen.html\">$(rep_t frozen_title)</a>.</p>"
fi

# --- documentos.html: os documentos PUBLICADOS da prova, dentro do pacote ---------------
# "Disponibilizar tudo depois" só funciona se o caderno, a folha de time limits, o info
# sheet e o editorial viajarem junto com o relatório. Entram só os PUBLICADOS (o que os
# times viram) — rascunho gerado e não publicado não vaza aqui.
DOCS_JSON="$CDIR/docs/config.json"
if [[ -s "$DOCS_JSON" ]] && jq -e '(.published // []) | length > 0' "$DOCS_JSON" >/dev/null 2>&1; then
  mkdir -p "$OUTD/documentos"
  : > "$W/docs.tsv"
  while IFS= read -r key; do
    [[ "$key" =~ ^([a-z-]+)\.(pt|en)$ ]] || continue
    dt="${BASH_REMATCH[1]}"; dl="${BASH_REMATCH[2]}"
    for fmt in pdf html; do
      src="$CDIR/docs/$dt.$dl.$fmt"
      [[ -s "$src" ]] || continue
      cp -f "$src" "$OUTD/documentos/$dt.$dl.$fmt" 2>/dev/null || continue
      printf '%s\t%s\t%s\t%s\n' "$dt" "$dl" "$fmt" "$(stat -c%s "$src" 2>/dev/null || echo 0)" >> "$W/docs.tsv"
    done
  done < <(jq -r '(.published // [])[]' "$DOCS_JSON" 2>/dev/null)
  if [[ -s "$W/docs.tsv" ]]; then
    {
      rep_head "$(rep_t page_docs)" docs
      printf '<p class="note">%s</p>\n' "$(rep_t docs_note)"
      printf '<div class="tblwrap"><table class="moj narrow">\n<thead><tr><th>%s</th><th>%s</th><th>%s</th><th class="n">%s</th></tr></thead>\n<tbody>\n' \
        "$(rep_t doc_col)" "$(rep_t lang_col)" "$(rep_t file)" "$(rep_t size)"
      while IFS=$'\t' read -r dt dl fmt sz; do
        case "$dt" in
          contest)    lbl="$(rep_t doc_contest)";;
          times)      lbl="$(rep_t doc_times)";;
          info-sheet) lbl="$(rep_t doc_info)";;
          editorial)  lbl="$(rep_t doc_editorial)";;
          *)          lbl="$dt";;
        esac
        printf '<tr><td>%s</td><td>%s</td><td><a href="documentos/%s.%s.%s">%s</a></td><td class="n">%s KB</td></tr>\n' \
          "$(esc "$lbl")" "$dl" "$dt" "$dl" "$fmt" "${fmt^^}" "$(( (sz + 1023) / 1024 ))"
      done < "$W/docs.tsv"
      printf '</tbody></table></div>\n'
      rep_foot
    } > "$OUTD/documentos.html"
  fi
fi

# --- mlinux.html (nutellaboot) — SÓ quando a integração foi coletada ---------------------
# Gerada AQUI, antes das outras páginas, pelo mesmo motivo do documentos.html: a aba só
# entra na nav das páginas escritas DEPOIS de o arquivo existir. Mesma doutrina do
# statistics.html: inlina dom.js + charts.js + mlinux-view.js (a MESMA view do painel) com
# os dados como literal. PRIVACIDADE: as listas por máquina (MAC) e os bindings ficam FORA
# do relatório — só agregados, ranks e séries por sede/nó.
NBC="$CDIR/var/nutella.cache.json"
if [[ -s "$NBC" ]] && jq -e '.global' "$NBC" >/dev/null 2>&1; then
  rt_ml='[]'
  if [[ -s "$CDIR/regions.json" ]]; then
    rt_ml="$(jq -c 'def strip: map({name: (.name // ""), subregions: ((.subregions // []) | strip)}); strip' \
             "$CDIR/regions.json" 2>/dev/null)"
    [[ -n "$rt_ml" ]] || rt_ml='[]'
  fi
  {
    rep_head "$(rep_t page_mlinux)" mlinux
    printf '<p class="note">%s</p>\n' "$(esc "$(rep_t ml_note "$(fmt_dt "$(jq -r '.collected_at // 0' "$NBC")")")")"
    printf '<div class="fbar"><label>%s <select id="mlSel"></select></label></div>\n' "$(esc "$(rep_t ml_sel)")"
    printf '<div id="ml"></div>\n'
    printf '<script>\n'
    printf 'const LANG=%s;\nfunction T(pt,en){return LANG==="en"?en:pt}\n' \
      "$([[ "${LOCALE:-pt}" == en ]] && printf '"en"' || printf '"pt"')"
    for _mlf in "$MOJ_WEB/shared/dom.js" "$MOJ_WEB/lib/charts.js" "$MOJ_WEB/lib/mlinux-view.js"; do
      [[ -s "$_mlf" ]] || continue
      sed -E '/^import /d; s/^export (function|const|let|class) /\1 /; /^export \{/d' "$_mlf"
    done
    printf 'const NBDATA=\n'
    jq 'del(.sedes[].machines, .sedes[].bindings)' "$NBC"
    printf ';\nconst RTREE=%s;\n' "$rt_ml"
    cat <<'MLEOF'
(function(){
  var host=document.getElementById('ml'), sel=document.getElementById('mlSel');
  var st=document.createElement('style'); st.textContent=MLINUX_CSS; document.head.appendChild(st);
  var d=NBDATA, have=d.by_node||{}, sedeSet={};
  (d.sedes||[]).forEach(function(s){ sedeSet[s.name.toLowerCase()]=1; });
  // seletor = a ÁRVORE de regions.json (ordem/indentação do placar), só nós com dado;
  // sedes fora da árvore no fim, ordenadas — o MESMO idioma do painel (mlinux-tab.js)
  var opts=[], seen={};
  function walk(list, depth){ (list||[]).forEach(function(r){
    if(r.name){ var lo=r.name.toLowerCase();
      if(sedeSet[lo]){ opts.push({kind:'s', key:r.name, depth:depth}); seen[lo]=1; }
      else if(Object.prototype.hasOwnProperty.call(have, r.name)){ opts.push({kind:'n', key:r.name, depth:depth}); seen[lo]=1; } }
    if(r.subregions && r.subregions.length) walk(r.subregions, depth+1); }); }
  walk(RTREE, 0);
  (d.sedes||[]).map(function(s){return s.name}).sort().forEach(function(n){
    if(!seen[n.toLowerCase()]) opts.push({kind:'s', key:n, depth:0}); });
  var o0=document.createElement('option'); o0.value='g|'; o0.textContent=T('— geral —','— overall —'); sel.add(o0);
  opts.forEach(function(o){ var e=document.createElement('option'); e.value=o.kind+'|'+o.key;
    e.textContent=new Array(o.depth+1).join('  ')+o.key; sel.add(e); });
  function agg(){ var v=sel.value.split('|'), kind=v[0], key=v.slice(1).join('|');
    if(kind==='n') return have[key]||d.global;
    if(kind==='s'){ var s=(d.sedes||[]).filter(function(x){return x.name===key})[0]; return s||d.global; }
    return d.global; }
  function render(){ host.innerHTML='';
    try{ mlinuxSections(agg(), {window:d.window}).forEach(function(x){ host.append(x) }); }
    catch(e){ host.innerHTML='<p class="note">'+String(e)+'</p>'; } }
  sel.addEventListener('change', render); render();
})();
MLEOF
    printf '</script>\n'
    rep_foot
  } > "$OUTD/mlinux.html"
fi
# ⚠ o fi acima fecha ANTES da página seguinte — sem nutellaboot o relatório segue inteiro

# --- index.html ------------------------------------------------------------------------
# ⚠ FORA do if dos documentos: com o `fi` no fim deste bloco (era o caso), contest SEM
# documento publicado saía com relatório sem a página do placar.
mode_label(){ case "$1" in icpc) rep_t mode_icpc;; obi) rep_t mode_obi;; heuristic) rep_t mode_heur;; treino) rep_t mode_list;; *) rep_t mode_custom;; esac; }
dur_label(){ local s=$1; (( s<=0 )) && { printf '—'; return; }; printf '%dh%02d' $((s/3600)) $(( (s%3600)/60 )); }
{
  rep_head "$(rep_t page_index)" index
  printf '<div class="info"><dl>\n'
  printf '<dt>%s</dt><dd>%s</dd>\n' "$(rep_t contest)" "$(esc "$CNAME")"
  printf '<dt>%s</dt><dd>%s</dd>\n' "$(rep_t start)" "$(fmt_dt "$START")"
  printf '<dt>%s</dt><dd>%s</dd>\n' "$(rep_t end)" "$(fmt_dt "$END")"
  printf '<dt>%s</dt><dd>%s</dd>\n' "$(rep_t duration)" "$(dur_label $((END-START)))"
  printf '<dt>%s</dt><dd>%s</dd>\n' "$(rep_t mode)" "$(mode_label "$MODE")"
  [[ "$MODE" == icpc ]] && printf '<dt>%s</dt><dd>%s %s</dd>\n' "$(rep_t penalty)" "${PENALTY_MINUTES:-20}" "$(rep_t penalty_val)"
  if (( FREEZE > 0 )); then
    printf '<dt>%s</dt><dd>%s (%s %s min)</dd>\n' "$(rep_t freeze)" "$(fmt_dt "$FREEZE")" "$(rep_t freeze_at)" "$(( (FREEZE-START)/60 ))"
  else
    printf '<dt>%s</dt><dd>%s</dd>\n' "$(rep_t freeze)" "$(rep_t freeze_none)"
  fi
  printf '<dt>%s</dt><dd>%s</dd>\n' "$(rep_t teams)" "$TEAMS_N"
  printf '<dt>%s</dt><dd>%s (<a href="runs.html">runs</a>)</dd>\n' "$(rep_t subs)" "$RUNS_N"
  printf '</dl></div>\n'

  printf '<h2>%s</h2>\n<div class="tblwrap"><table class="moj">\n<thead><tr><th>%s</th><th>%s</th><th>%s</th><th>%s</th></tr></thead>\n<tbody>\n' \
    "$(rep_t problems)" "$(rep_t letter)" "$(rep_t problem)" "$(rep_t author)" "$(rep_t statement)"
  while IFS=$'\t' read -r Ls pfull hh hp url pauthor; do
    [[ "$url" == - ]] && url=""; [[ "$pauthor" == - ]] && pauthor=""
    links=""
    [[ "$hh" == 1 ]] && links+="<a href=\"statements/$Ls.html\">HTML</a> "
    [[ "$hp" == 1 ]] && links+="<a href=\"statements/$Ls.pdf\">PDF</a> "
    [[ -n "$url" ]] && links+="<a href=\"$(esc "$url")\">$(rep_t ext_link)</a> "
    [[ -n "$links" ]] || links="—"
    printf '<tr><td><b>%s</b></td><td>%s</td><td>%s</td><td>%s</td></tr>\n' \
      "$(esc "$Ls")" "$(esc "$pfull")" "$([[ -n "$pauthor" ]] && esc "$pauthor" || printf '—')" "$links"
  done < "$W/stmt.tsv"
  printf '</tbody></table></div>\n'

  printf '<h2>%s</h2>\n' "$(rep_t final_score)"
  printf '%s\n' "$FROZEN_NOTE"
  rep_score_boards open
  rep_foot
} > "$OUTD/index.html"

# --- runs.html ---------------------------------------------------------------------------
{
  rep_head "$(rep_t page_runs)" runs
  printf '<p class="note">%s</p>\n' "$([[ "$LOC" == en ]] && printf 'All submissions (no source code, no judge logs; canonical verdict). Click a header to sort.' || printf 'Todas as submissões da prova (sem código-fonte e sem logs do juiz; veredicto canônico). Clique num cabeçalho para ordenar.')"
  printf '<input class="filter" id="fq" type="search" placeholder="%s">\n' "$(rep_t filter_ph)"
  printf '<div class="tblwrap"><table class="moj" id="runs">\n<thead><tr><th class="n">#</th><th class="n">%s</th><th>%s</th><th>%s</th><th>%s</th><th>%s</th><th>%s</th><th>%s</th></tr></thead>\n<tbody>\n' \
    "$(rep_t minute)" "$(rep_t hour)" "$(rep_t team)" "$(rep_t univ)" "$(rep_t prob)" "$(rep_t lang)" "$(rep_t verdict)"
  awk -F'\t' -v START="$START" -v DTFMT="$([[ "$LOC" == en ]] && printf '%%m-%%d %%H:%%M:%%S' || printf '%%d/%%m %%H:%%M:%%S')" '
    function esc(s){ gsub(/&/,"\\&amp;",s); gsub(/</,"\\&lt;",s); gsub(/>/,"\\&gt;",s); gsub(/"/,"\\&quot;",s); return s }
    {
      se=$1+0; login=$2; letter=$3; lang=$4; v=$5; sid=$6; tn=$7; us=$8; uf=$9
      mn=(START>0)? int((se-START)/60) : ""
      hora=strftime(DTFMT, se)
      cls="v-rej"
      if (v ~ /^Accepted/) cls="v-ac"
      else if (v ~ /^(Not Answered Yet|On queue|Running)/) cls="v-pend"
      team=(tn!="")? tn : login
      lbl=esc(team) " <span class=\"u\">[" esc(login) "]</span>"
      univ=(us!="")? us : uf
      printf "<tr><td class=\"place\" title=\"%s\">%d</td><td class=\"n\">%s</td><td>%s</td><td class=\"team\">%s</td><td>%s</td><td><b>%s</b></td><td>%s</td><td class=\"%s\">%s</td></tr>\n", \
        esc(sid), NR, mn, hora, lbl, esc(univ), esc(letter), esc(lang), cls, esc(v)
    }' "$W/runs.tsv"
  printf '</tbody></table></div>\n'
  cat <<'EOF'
<script>
(function(){
  var t=document.getElementById('runs'); if(!t) return;
  var q=document.getElementById('fq');
  if(q) q.addEventListener('input',function(){
    var v=q.value.toLowerCase();
    Array.prototype.forEach.call(t.tBodies[0].rows,function(r){
      r.style.display=r.textContent.toLowerCase().indexOf(v)>=0?'':'none';});});
  Array.prototype.forEach.call(t.tHead.rows[0].cells,function(th,i){
    th.style.cursor='pointer';
    th.addEventListener('click',function(){
      var tb=t.tBodies[0], rows=Array.prototype.slice.call(tb.rows);
      var dir=th.dataset.d==='a'?-1:1; th.dataset.d=dir>0?'a':'d';
      rows.sort(function(a,b){
        var x=a.cells[i].textContent,y=b.cells[i].textContent;
        var nx=parseFloat(x),ny=parseFloat(y);
        if(!isNaN(nx)&&!isNaN(ny))return dir*(nx-ny);
        return dir*x.localeCompare(y);});
      rows.forEach(function(r){tb.appendChild(r);});});});
})();
</script>
EOF
  rep_foot
} > "$OUTD/runs.html"

# --- clarifications.html -----------------------------------------------------------------
{
  rep_head "$(rep_t page_clar)" clar
  printf '<p class="note">%s</p>\n' "$([[ "$LOC" == en ]] && printf 'Questions and answers. Who asked and who answered stay anonymous.' || printf 'Perguntas e respostas da prova. Quem perguntou e quem respondeu ficam anônimos.')"
  ncl=0
  if [[ -d "$CDIR/clarifications" ]]; then
    find "$CDIR/clarifications" -maxdepth 1 -name '*.json' -print0 2>/dev/null \
      | xargs -0 -r jq -c 'del(.login, .answered_by, .answer_claim)' 2>/dev/null \
      | jq -rs --argjson start "$START" --arg t_notice "$(rep_t notice)" --arg t_pub "$(rep_t public)" \
             --arg t_priv "$(rep_t private)" --arg t_gen "$([[ "$LOC" == en ]] && printf 'General' || printf 'Geral')" \
             --arg t_noans "$([[ "$LOC" == en ]] && printf '— no answer —' || printf '— sem resposta —')" \
             --arg dtfmt "$([[ "$LOC" == en ]] && printf '%%m-%%d %%H:%%M' || printf '%%d/%%m %%H:%%M')" 'sort_by(.time) | .[] |
          (if .broadcast==true then "<span class=\"badge org\">" + $t_notice + "</span>"
           elif .public==true then "<span class=\"badge pub\">" + $t_pub + "</span>"
           else "<span class=\"badge priv\">" + $t_priv + "</span>" end) as $b
          | ((.problem // "general") | if .=="general" then $t_gen else . end) as $p
          | ((.time // 0) | strflocaltime($dtfmt)) as $h
          | (if $start>0 and (.time//0)>0 then " (min \(((.time - $start)/60)|floor))" else "" end) as $mn
          | "<div class=\"qa\"><div class=\"meta\"><b>\($p|@html)</b> · \($h)\($mn) · \($b)</div>"
            + "<div class=\"q\">\((.question // "")|@html)</div>"
            + (if ((.answer // "")|length) > 0
               then "<div class=\"a\">\(.answer|@html)</div>"
               else "<div class=\"a\" style=\"border-left-color:#c99\">" + $t_noans + "</div>" end)
            + "</div>"'
    ncl="$(find "$CDIR/clarifications" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d '[:space:]')"
  fi
  [[ "${ncl:-0}" == 0 ]] && printf '<p class="note">%s</p>\n' "$(rep_t none_clar)"
  rep_foot
} > "$OUTD/clarifications.html"

# --- statistics.html ---------------------------------------------------------------------
# MESMAS seções do painel do admin: o módulo web/lib/stats-view.js (que a página
# /contest/statistics/ usa) é INLINADO aqui junto do dom.js e do charts.js, com o
# statistics.cache.json embutido como literal. Sem fetch, sem ESM, sem arquivo externo — as
# linhas `import`/`export` são removidas na hora da inlinagem (o smoke proíbe as duas no
# relatório) e o T() do prelúdio fixa o idioma no LOCALE do contest.
# O <noscript> mantém as tabelas antigas: o relatório é um arquivo de ARQUIVO MORTO e tem
# de continuar legível se alguém abrir sem JS.
rep_stats_bundle(){
  local f cn rt
  # rótulo de país p/ o select (mesma resolução da bandeira do placar); cai no código
  cn="$(jq -r '(.by_country // {}) | keys[]' "$1" 2>/dev/null | while IFS= read -r _cc; do
          printf '%s\t%s\n' "$_cc" "$(rep_flag_name "$_cc")"
        done | jq -Rn '[inputs | split("\t") | select(length >= 1) | {key:.[0], value:(.[1] // "")}] | from_entries')"
  [[ -n "$cn" ]] || cn='{}'
  # árvore de regions.json achatada [{n,d}] na ORDEM do documento — o select de Sede da
  # estatística espelha o do placar (país › região/supersede › sede, indentado)
  rt='[]'
  if [[ -s "$CDIR/regions.json" ]]; then
    rt="$(jq -c 'def flat($d): .[]? | {n:(.name // ""), d:$d}, ((.subregions // []) | flat($d+1));
                 [flat(0)] | map(select(.n != ""))' "$CDIR/regions.json" 2>/dev/null)"
    [[ -n "$rt" ]] || rt='[]'
  fi
  # barra de recorte (R2, 2026-08-30): Sede × País, mutuamente exclusivos — o cache já traz
  # by_region/by_country prontos (mesmo shape do global) e o JS só escolhe o sub-objeto.
  # Sem dimensão nenhuma (cache antigo/contest sem .team) o JS esconde a barra.
  printf '<div class="fbar" id="sbar" hidden data-sel="%s" data-glob="%s">\n' \
    "$(esc "$(rep_t st_sel)")" "$(esc "$(rep_t st_glob)")"
  printf '<label>%s <select id="sRegion"><option value="">%s</option></select></label>\n' \
    "$(esc "$(rep_t f_region)")" "$(esc "$(rep_t f_region_all)")"
  printf '<label>%s <select id="sFlag"><option value="">%s</option></select></label>\n' \
    "$(esc "$(rep_t st_country)")" "$(esc "$(rep_t st_all)")"
  printf '<span class="fcount" id="sCount"></span>\n</div>\n'
  printf '<div id="stats"></div>\n'
  printf '<script>\n'
  printf 'const LANG=%s;\nfunction T(pt,en){return LANG==="en"?en:pt}\n' "$([[ "${LOCALE:-pt}" == en ]] && printf '"en"' || printf '"pt"')"
  for f in "$MOJ_WEB/shared/dom.js" "$MOJ_WEB/lib/charts.js" "$MOJ_WEB/lib/stats-view.js"; do
    [[ -s "$f" ]] || return 1
    sed -E '/^import /d; s/^export (function|const|let|class) /\1 /; /^export \{/d' "$f"
  done
  printf 'const STATS=\n'
  cat "$1"
  printf ';\nconst CNAMES=%s;\nconst RTREE=%s;\n' "$cn" "$rt"
  cat <<'STEOF'
(function(){
  var host=document.getElementById('stats'); if(!host) return;
  function render(s){
    host.innerHTML='';
    try{ statsSections(s).forEach(function(x){ host.append(x) }) }
    catch(e){ host.innerHTML='<p class="note">'+String(e)+'</p>' }
  }
  var bar=document.getElementById('sbar'), selR=document.getElementById('sRegion'),
      selC=document.getElementById('sFlag'), cnt=document.getElementById('sCount');
  // Sede = a ÁRVORE do regions.json (ordem e indentação do seletor do placar), só os nós
  // com recorte computado; sedes fora da árvore entram no fim, ordenadas
  var have=STATS.by_region||{}, regs=[], seenR={};
  RTREE.forEach(function(t){
    if(t.n && Object.prototype.hasOwnProperty.call(have,t.n)){ regs.push(t); seenR[t.n.toLowerCase()]=1; }
  });
  Object.keys(have).sort(function(a,b){ return a.localeCompare(b) }).forEach(function(n){
    if(!seenR[n.toLowerCase()]) regs.push({n:n,d:0});
  });
  var ctys=Object.keys(STATS.by_country||{}).sort(function(a,b){
    return String(CNAMES[a]||a).localeCompare(String(CNAMES[b]||b)) });
  if(!bar || (!regs.length && !ctys.length)){ render(STATS); return; }
  bar.hidden=false;
  regs.forEach(function(r){ var o=document.createElement('option'); o.value=r.n;
    o.textContent=new Array((r.d||0)+1).join('  ')+r.n; selR.add(o) });
  ctys.forEach(function(c){ var o=document.createElement('option'); o.value=c;
    o.textContent=CNAMES[c]||c.toUpperCase(); selC.add(o) });
  if(selR.options.length<2) selR.parentNode.style.display='none';
  if(selC.options.length<2) selC.parentNode.style.display='none';
  function pick(){
    if(selR.value) return {s:(STATS.by_region||{})[selR.value]||STATS, nm:selR.value};
    if(selC.value) return {s:(STATS.by_country||{})[selC.value]||STATS, nm:(CNAMES[selC.value]||selC.value.toUpperCase())};
    return {s:STATS, nm:''};
  }
  function upd(){
    var p=pick(); render(p.s);
    if(!cnt) return;
    if(p.nm){ cnt.textContent=(bar.getAttribute('data-sel')||'%s %s %s')
        .replace('%s',p.nm).replace('%s',p.s.totals.users).replace('%s',STATS.totals.users); }
    else cnt.textContent=(bar.getAttribute('data-glob')||'%s').replace('%s',STATS.totals.users);
  }
  // mutuamente exclusivos: escolher um zera o outro (o recorte é UM, nunca a interseção)
  selR.addEventListener('change',function(){ if(selR.value) selC.value=''; upd() });
  selC.addEventListener('change',function(){ if(selC.value) selR.value=''; upd() });
  upd();
})();
STEOF
  printf '</script>\n'
}

{
  rep_head "$(rep_t page_stats)" stats
  SJ="$CDIR/var/statistics.cache.json"
  if [[ -s "$SJ" ]]; then
    # o rep_stats_bundle imprime a barra de recorte + o <div id="stats"> + o script
    rep_stats_bundle "$SJ" || printf '<p class="note">%s</p>\n' "$(rep_t no_charts)"
    printf '<noscript>\n'
    jq -r --arg t_subs "$(rep_t subs)" --arg t_acc "$(rep_t accepted)" --arg t_teams "$(rep_t teams)" \
          --arg t_solvedp "$([[ "$LOC" == en ]] && printf 'problems solved' || printf 'problemas resolvidos')" \
          --arg t_byprob "$(rep_t by_problem)" --arg t_prob "$(rep_t prob)" --arg t_name "$(rep_t name_w)" \
          --arg t_solvedc "$(rep_t solved_col)" --arg t_rate "$(rep_t rate)" --arg t_first "$(rep_t first_solve)" \
          --arg t_min "$(rep_t minute)" --arg t_bylang "$(rep_t by_lang)" --arg t_lang "$(rep_t by_lang)" \
          --arg t_langc "$([[ "$LOC" == en ]] && printf 'Language' || printf 'Linguagem')" \
          --arg t_solvers "$(rep_t solvers)" --arg t_byverd "$(rep_t by_verdict)" --arg t_verd "$(rep_t verdict)" \
          --arg t_occ "$(rep_t occurrences)" --arg t_tl "$(rep_t timeline)" --arg t_dist "$(rep_t dist)" \
          --arg t_solvedw "$(rep_t solved_w)" '
      def pct: (.*1000|floor)/10;
      "<div class=\"cards\">"
      + "<div class=\"card\"><div class=\"n\">\(.totals.submissions)</div><div class=\"l\">" + $t_subs + "</div></div>"
      + "<div class=\"card\"><div class=\"n\">\(.totals.accepted)</div><div class=\"l\">" + $t_acc + "</div></div>"
      + "<div class=\"card\"><div class=\"n\">\(.totals.users)</div><div class=\"l\">" + $t_teams + "</div></div>"
      + "<div class=\"card\"><div class=\"n\">\(.totals.problems_solved)</div><div class=\"l\">" + $t_solvedp + "</div></div>"
      + "</div>"
      + "<h2>" + $t_byprob + "</h2><div class=\"tblwrap\"><table class=\"moj\"><thead><tr><th>" + $t_prob + "</th><th>" + $t_name + "</th><th class=\"n\">Subs</th><th class=\"n\">" + $t_teams + "</th><th class=\"n\">" + $t_solvedc + "</th><th class=\"n\">" + $t_rate + "</th><th>" + $t_first + "</th><th class=\"n\">" + $t_min + "</th></tr></thead><tbody>"
      + ([ .problems[] | "<tr><td><b>\(.short_name|@html)</b></td><td>\(.full_name|@html)</td><td class=\"n\">\(.submissions)</td><td class=\"n\">\(.attempted)</td><td class=\"n\">\(.solved)</td><td class=\"n\">\(.accept_rate|pct)%</td><td>\(((.first_solver_name // "") | if .=="" then (.first_solver // "") else . end)|@html)\(if ((.first_solver_name // "")|length)>0 then " (\(.first_solver|@html))" else "" end)</td><td class=\"n\">\(if .first_minute<0 then "—" else (.first_minute|tostring) end)</td></tr>" ] | join(""))
      + "</tbody></table></div>"
      + "<h2>" + $t_bylang + "</h2><div class=\"tblwrap\"><table class=\"moj narrow\"><thead><tr><th>" + $t_langc + "</th><th class=\"n\">Subs</th><th class=\"n\">" + $t_acc + "</th><th class=\"n\">" + $t_solvers + "</th></tr></thead><tbody>"
      + ([ .languages[] | "<tr><td>\(.lang|@html)</td><td class=\"n\">\(.submissions)</td><td class=\"n\">\(.accepted)</td><td class=\"n\">\(.solvers)</td></tr>" ] | join(""))
      + "</tbody></table></div>"
      + "<h2>" + $t_byverd + "</h2><div class=\"tblwrap\"><table class=\"moj narrow\"><thead><tr><th>" + $t_verd + "</th><th class=\"n\">" + $t_occ + "</th></tr></thead><tbody>"
      + ([ .verdicts[] | "<tr><td>\(.verdict|@html)</td><td class=\"n\">\(.count)</td></tr>" ] | join(""))
      + "</tbody></table></div>"
      + (([ .timeline[].submissions ] | max // 0) as $mx
         | "<h2>" + $t_tl + "</h2><div class=\"tblwrap\"><table class=\"moj\"><thead><tr><th class=\"n\">" + $t_min + "</th><th class=\"n\">" + $t_subs + "</th><th style=\"width:50%\"></th></tr></thead><tbody>"
         + ([ .timeline[] | "<tr><td class=\"n\">\(.minute)</td><td class=\"n\">\(.submissions) (\(.accepted) AC)</td><td><span class=\"tbar\" style=\"width:\(if $mx>0 then (.submissions*100/$mx) else 0 end)%\"></span><span class=\"tbar ac\" style=\"width:\(if $mx>0 then (.accepted*100/$mx) else 0 end)%\"></span></td></tr>" ] | join(""))
         + "</tbody></table></div>")
      + "<h2>" + $t_dist + "</h2><div class=\"tblwrap\"><table class=\"moj narrow\"><thead><tr><th class=\"n\">" + $t_solvedw + "</th><th class=\"n\">" + $t_teams + "</th></tr></thead><tbody>"
      + ([ .problems_solved_dist[]? | "<tr><td class=\"n\">\(.solved)</td><td class=\"n\">\(.users)</td></tr>" ] | join(""))
      + "</tbody></table></div>"
    ' "$SJ" 2>/dev/null || printf '<p class="note">%s</p>\n' "$(rep_t stats_fail)"
    printf '</noscript>\n'
  else
    printf '<p class="note">%s</p>\n' "$(rep_t stats_none)"
  fi
  rep_foot
} > "$OUTD/statistics.html"

# --- staff-tasks.html ---------------------------------------------------------------------
{
  rep_head "$(rep_t page_staff)" staff
  printf '<p class="note">%s</p>\n' "$([[ "$LOC" == en ]] && printf 'Queue handled by the staff during the contest: printing (🖨️, METADATA only — the uploaded file is not published) and balloons (🎈).' || printf 'Fila atendida pelo staff durante a prova: impressões (🖨️, só METADADOS — o arquivo enviado não é publicado) e balões (🎈).')"
  PRD="$CDIR/print-requests"
  nst=0
  if [[ -d "$PRD" ]]; then
    printf '<div class="tblwrap"><table class="moj">\n<thead><tr><th class="n">#</th><th>%s</th><th>%s</th><th>%s</th><th>%s</th><th>%s</th><th>%s</th><th>%s</th></tr></thead>\n<tbody>\n' \
      "$(rep_t type)" "$(rep_t hour)" "$(rep_t team)" "$(rep_t univ)" "$(rep_t detail)" "$(rep_t status)" "$(rep_t service)"
    find "$PRD" -maxdepth 1 -name '*.json' ! -name badges.json ! -name staff-filters.json -print0 2>/dev/null \
      | xargs -0 -r jq -c 'select((.seq? // null) != null)' 2>/dev/null \
      | jq -rs --arg t_balloon "$(rep_t balloon)" --arg t_print "$(rep_t printing)" --arg t_pages "$(rep_t pages_sfx)" \
             --arg t_prob "$([[ "$LOC" == en ]] && printf 'problem' || printf 'problema')" \
             --arg t_deliv "$([[ "$LOC" == en ]] && printf 'delivered' || printf 'entregue')" \
             --arg t_proc "$([[ "$LOC" == en ]] && printf 'processed' || printf 'processada')" \
             --arg t_pend "$([[ "$LOC" == en ]] && printf 'pending' || printf 'pendente')" \
             --arg t_by "$([[ "$LOC" == en ]] && printf 'by' || printf 'por')" \
             --arg dtfmt "$([[ "$LOC" == en ]] && printf '%%m-%%d %%H:%%M' || printf '%%d/%%m %%H:%%M')" 'sort_by(.seq) | .[] |
          ((.kind // "print")) as $k
          | ((.time // 0) | strflocaltime($dtfmt)) as $h
          | (if $k=="balloon"
             then "🎈 <span class=\"swatch\" style=\"background:#\(.color_hex // "CCCCCC")\"></span> \((.color_name // "")|@html) — " + $t_prob + " <b>\((.short // "")|@html)</b>"
             else "🖨️ \((.filename // "")|@html) (\(.size // 0) bytes\(if (.pages // 0) > 0 then ", \(.pages) " + $t_pages else "" end))" end) as $det
          | (if .status=="delivered" then "<span class=\"badge st-delivered\">" + $t_deliv + "</span>"
             elif .status=="printed" then "<span class=\"badge st-printed\">" + $t_proc + "</span>"
             else "<span class=\"badge st-pending\">" + $t_pend + "</span>" end) as $st
          | ((if (.processed_at // 0) > 0 then $t_proc + " \((.processed_at)|strflocaltime("%H:%M")) " + $t_by + " \((.processed_by // "")|@html)" else "" end)
             + (if (.delivered_at // 0) > 0 then " · " + $t_deliv + " \((.delivered_at)|strflocaltime("%H:%M")) " + $t_by + " \((.delivered_by // "")|@html)" else "" end)) as $att
          | "<tr><td class=\"place\">\(.seq)</td><td>\(if $k=="balloon" then $t_balloon else $t_print end)</td><td>\($h)</td>"
            + "<td class=\"team\">\((.fullname // .team // "")|@html) <span class=\"u\">[\((.login // "")|@html)]</span></td>"
            + "<td>\((.univ // "")|@html)</td><td>\($det)</td><td>\($st)</td><td class=\"meta\">\(if ($att|length)>0 then $att else "—" end)</td></tr>"'
    printf '</tbody></table></div>\n'
    nst="$(find "$PRD" -maxdepth 1 -name '*.json' ! -name badges.json ! -name staff-filters.json 2>/dev/null | wc -l | tr -d '[:space:]')"
  fi
  [[ "${nst:-0}" == 0 ]] && printf '<p class="note">%s</p>\n' "$(rep_t none_tasks)"
  rep_foot
} > "$OUTD/staff-tasks.html"

# --- infra.html (dados da aba Situação, janela = prova inteira) -----------------------------
{
  rep_head "$([[ "$LOC" == en ]] && printf 'Judging infrastructure' || printf 'Infraestrutura de julgamento')" infra
  printf '<p class="note">%s</p>\n' "$(rep_t snapshot "$(fmt_dt "$NOW")")"

  # métricas de resposta: espera = finalized_at - sub_epoch (results por-usuário)
  find "$CDIR/users" -mindepth 3 -maxdepth 3 -path '*/results/*.json' -print0 2>/dev/null \
    | xargs -0 -r jq -r '[(.id // ""), (.finalized_at // 0), (.duration_s // 0), (.host // "")] | @tsv' 2>/dev/null \
    > "$W/results.tsv"
  awk -F'\t' -v RES="$W/results.tsv" -v OUTW="$W/waits.tsv" '
    BEGIN{ while ((getline l < RES) > 0) { n=split(l,a,"\t"); if(n>=4 && a[1]!=""){ fin[a[1]]=a[2]+0; dur[a[1]]=a[3]+0; hst[a[1]]=a[4] } } close(RES) }
    {
      se=$1+0; letter=$3; sid=$6; total++
      if (sid in fin && fin[sid]>0 && fin[sid]>=se) {
        w=fin[sid]-se; joined++
        printf "%d\t%s\t%s\t%d\t%d\n", w, letter, hst[sid], dur[sid], se > OUTW
      }
    }
    END{ printf "%d\t%d\n", total+0, joined+0 }
  ' "$W/runs.tsv" > "$W/cover.tsv"
  read -r RTOT RJOIN < "$W/cover.tsv" || { RTOT=0; RJOIN=0; }
  touch "$W/waits.tsv"

  sort -n -k1,1 "$W/waits.tsv" -o "$W/waits.tsv"
  awk -F'\t' -v T_MEAS="$([[ "$LOC" == en ]] && printf 'measured responses' || printf 'respostas medidas')" \
      -v T_AVG="$(rep_t avg_wait)" -v T_MED="$([[ "$LOC" == en ]] && printf 'median' || printf 'mediana')" \
      -v T_MAX="$(rep_t max_w)" '
    { w[NR]=$1+0; s+=$1 }
    END{
      n=NR
      if(n==0){ printf "<div class=\"cards\"><div class=\"card\"><div class=\"n\">0</div><div class=\"l\">%s</div></div></div>\n", T_MEAS; exit }
      p50=w[int((n-1)*0.5)+1]; p95=w[int((n-1)*0.95)+1]
      printf "<div class=\"cards\">"
      printf "<div class=\"card\"><div class=\"n\">%d</div><div class=\"l\">%s</div></div>", n, T_MEAS
      printf "<div class=\"card\"><div class=\"n\">%ds</div><div class=\"l\">%s</div></div>", s/n, T_AVG
      printf "<div class=\"card\"><div class=\"n\">%ds</div><div class=\"l\">%s (p50)</div></div>", p50, T_MED
      printf "<div class=\"card\"><div class=\"n\">%ds</div><div class=\"l\">p95</div></div>", p95
      printf "<div class=\"card\"><div class=\"n\">%ds</div><div class=\"l\">%s</div></div>", w[n], T_MAX
      printf "</div>\n"
    }' "$W/waits.tsv"
  printf '<p class="note">%s</p>\n' "$(rep_t coverage "$RJOIN" "$RTOT")"

  printf '<h2>%s</h2>\n<div class="tblwrap"><table class="moj narrow"><thead><tr><th>%s</th><th class="n">%s</th><th class="n">%s</th><th class="n">%s</th></tr></thead><tbody>\n' \
    "$(rep_t wait_by_prob)" "$(rep_t prob)" "$(rep_t judged)" "$(rep_t avg_wait)" "$(rep_t max_w)"
  awk -F'\t' '{ c[$2]++; s[$2]+=$1; if($1+0>mx[$2]) mx[$2]=$1+0 }
    END{ for(p in c) printf "%s\t%d\t%d\t%d\n", p, c[p], s[p]/c[p], mx[p] }' "$W/waits.tsv" \
    | sort | awk -F'\t' '{ printf "<tr><td><b>%s</b></td><td class=\"n\">%s</td><td class=\"n\">%ss</td><td class=\"n\">%ss</td></tr>\n", $1, $2, $3, $4 }'
  printf '</tbody></table></div>\n'

  printf '<h2>%s</h2>\n<div class="tblwrap"><table class="moj narrow"><thead><tr><th>%s</th><th class="n">%s</th><th class="n">%s</th></tr></thead><tbody>\n' \
    "$(rep_t by_judge)" "$(rep_t judge_host)" "$(rep_t judgements)" "$(rep_t avg_dur)"
  awk -F'\t' '$3!=""{ c[$3]++; s[$3]+=$4 } END{ for(h in c) printf "<tr><td>%s</td><td class=\"n\">%d</td><td class=\"n\">%.1fs</td></tr>\n", h, c[h], s[h]/c[h] }' "$W/waits.tsv" | sort
  printf '</tbody></table></div>\n'

  printf '<h2>%s</h2>\n<div class="tblwrap"><table class="moj"><thead><tr><th class="n">%s</th><th class="n">%s</th><th class="n">%s</th><th style="width:45%%"></th></tr></thead><tbody>\n' \
    "$([[ "$LOC" == en ]] && printf 'Wait over the contest (10-min windows)' || printf 'Espera ao longo da prova (janelas de 10 min)')" \
    "$(rep_t minute)" "$(rep_t judged)" "$(rep_t avg_wait)"
  awk -F'\t' -v START="$START" -v DTFMT="$([[ "$LOC" == en ]] && printf '%%m-%%d %%H:%%M:%%S' || printf '%%d/%%m %%H:%%M:%%S')" '
    { b=int((($5+0)-START)/600); if(b<0)b=0; c[b]++; s[b]+=$1; if(b>mb)mb=b }
    END{
      mxa=0; for(i=0;i<=mb;i++) if(c[i] && s[i]/c[i]>mxa) mxa=s[i]/c[i]
      for(i=0;i<=mb;i++) if(c[i]) printf "<tr><td class=\"n\">%d</td><td class=\"n\">%d</td><td class=\"n\">%ds</td><td><span class=\"tbar\" style=\"width:%d%%\"></span></td></tr>\n", i*10, c[i], s[i]/c[i], (mxa>0? int(s[i]/c[i]*100/mxa) : 0)
    }' "$W/waits.tsv"
  printf '</tbody></table></div>\n'

  # snapshot do cluster (registry) — pode estar vazio/for a do ar após a prova
  printf '<h2>%s</h2>\n' "$(rep_t registered)"
  if source "$HERE/../judge-gw/sched-lib.sh" 2>/dev/null && [[ -d "${REGISTRYDIR:-}" ]]; then
    qd="$(find "${QUEUEDIR:-/nonexistent}" -mindepth 2 -maxdepth 2 -name '*.json' 2>/dev/null | wc -l | tr -d '[:space:]')"
    printf '<p class="note">%s</p>\n' "$(rep_t queue_now "${qd:-0}")"
    printf '<div class="tblwrap"><table class="moj"><thead><tr><th>%s</th><th>%s</th><th>%s</th><th>%s</th><th>%s</th><th class="n">%s</th></tr></thead><tbody>\n' \
      "$(rep_t host)" "$(rep_t state)" "$(rep_t online)" "$(rep_t last_hb)" "$(rep_t langs)" "$(rep_t cached)"   # cached = numérico (th.n abaixo)
    find "$REGISTRYDIR" -maxdepth 1 -name '*.json' 2>/dev/null | sort | while IFS= read -r jf; do
      jq -r --argjson now "$NOW" --argjson ttl "${REG_TTL:-30}" \
         --arg dtfmt "$([[ "$LOC" == en ]] && printf '%%m-%%d %%H:%%M:%%S' || printf '%%d/%%m %%H:%%M:%%S')" '
        "<tr><td>\(.host // "?" | @html)</td><td>\(.state // "?" | @html)</td>"
        + "<td>\(if ((.last_seen//0) >= ($now - $ttl)) then "✅" else "—" end)</td>"
        + "<td>\(if (.last_seen//0) > 0 then ((.last_seen)|strflocaltime($dtfmt)) else "—" end)</td>"
        + "<td>\((.langs // []) | join(", ") | @html)</td>"
        + "<td class=\"n\">\(.problems_count // ((.problems//{})|length))</td></tr>"' "$jf" 2>/dev/null
    done
    printf '</tbody></table></div>\n'
  else
    printf '<p class="note">%s</p>\n' "$([[ "$LOC" == en ]] && printf 'No judge registry available when the report was generated.' || printf 'Sem registro de juízes disponível no momento da geração.')"
  fi
  rep_foot
} > "$OUTD/infra.html"

echo "$OUTD"
