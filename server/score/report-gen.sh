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
# É um "build" irmão de build.sh/stats-gen.sh: roda standalone (CLI) ou pelo handler.
set -u
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
export CONTESTSDIR

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../api/v1/lib/users.sh"
source "$HERE/../api/v1/lib/verdict.sh"
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
CNAME="${CONTEST_NAME:-$C}"
NOW="$EPOCHSECONDS"

# --- probmeta: letra/nome/skey + as 4 grafias do probid no history (off/raw/dot/hash) ---
: > "$W/probs.tsv"
for (( i=0; i<${#PROBS[@]}; i+=5 )); do
  praw="${PROBS[$((i+1))]}"; pfull="${PROBS[$((i+2))]}"; pshort="${PROBS[$((i+3))]}"; pskey="${PROBS[$((i+4))]}"
  phash="$pskey"; [[ "$phash" == *"#"* ]] || phash="${praw//\//#}"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$pshort" "$pfull" "$pskey" "$i" "$praw" "${praw/\//.}" "$phash"
done >> "$W/probs.tsv"

# --- identidade dos times (SÓ fullname/team/univ/flag — nunca password/email) ---------
# login \t team-name \t univ_short \t univ_full \t flag ; USERS_FROM cobre compartilhados.
ACCT_JQ='[.login//"", ((.team.name // .fullname // "")|gsub("[:\t\n]";" ")),
          ((.team.univ_short//"")|gsub("[:\t\n]";" ")), ((.team.univ_full//"")|gsub("[:\t\n]";" ")),
          ((.team.flag//"")|gsub("[:\t\n]";""))] | @tsv'
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

# escape/format: definidos ANTES das bandeiras — rep_flag usa esc() no alt/title.
esc(){ printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"; }
fmt_dt(){ (( ${1:-0} > 0 )) && date -d "@$1" '+%d/%m/%Y %H:%M' 2>/dev/null || printf '—'; }

# --- bandeiras: MESMA regra do site (web/shared/flags.js), SVG local -> data URI ------
# Era emoji de indicador regional: não renderiza no Windows nem em servidor sem Noto Color
# Emoji, e — pior — só casava 2 letras, então os códigos de ESTADO ("br-rj", que é o que a
# maioria dos times usa) saíam como TEXTO CRU no placar. Agora resolve o mesmo arquivo que o
# placar ao vivo usa e embute como data URI (obrigatório: o visualizador de rodadas abre as
# páginas em iframe srcdoc, onde caminho relativo não resolve). Só os códigos USADOS entram.
rep_flag(){   # <código> -> <img …> (vazio se o código não for reconhecível)
  local c="${1,,}" f=""
  [[ "$c" =~ ^br[-_]([a-z]{2})$ ]] && f="$MOJ_WEB/shared/flags/br/${BASH_REMATCH[1]}.svg"
  [[ -z "$f" && "$c" =~ ^[a-z]{2}$ ]] && f="$MOJ_WEB/shared/flags/country/$c.svg"
  [[ -n "$f" && -s "$f" ]] || { printf '%s' ""; return; }
  # nome p/ o title/alt: no index.json o estado é indexado SEM o prefixo ("sc", não "br-sc"),
  # e os dois arrays entram CONCATENADOS (`first(A, B|filtro)` filtraria só o B — a vírgula
  # é mais frouxa que o pipe e o primeiro ramo passava direto).
  local key="$c" name b64
  [[ "$c" =~ ^br[-_]([a-z]{2})$ ]] && key="${BASH_REMATCH[1]}"
  name="$(jq -r --arg c "$key" 'first((((.countries//[]) + (.br_states//[]))[]) | select((.code|ascii_downcase)==$c) | .name) // empty' \
          "$MOJ_WEB/shared/flags/index.json" 2>/dev/null)"
  [[ -n "$name" ]] || name="$1"
  b64="$(base64 -w0 < "$f" 2>/dev/null)" || return
  printf '<img class="flag-mini" src="data:image/svg+xml;base64,%s" alt="%s" title="%s">' \
    "$b64" "$(esc "$name")" "$(esc "$name")"
}
awk -F'\t' '$5!=""{print $5}' "$W/names.tsv" | sort -u | while IFS= read -r fcode; do
  printf '%s\t%s\n' "$fcode" "$(rep_flag "$fcode")"
done > "$W/flags.tsv"

# logo do MOJ (1,4 KB) embutido — mesma imagem da topbar do site
LOGO_IMG=""
if [[ -s "$MOJ_WEB/shared/assets/logo_moj.svg" ]]; then
  LOGO_IMG="<img src=\"data:image/svg+xml;base64,$(base64 -w0 < "$MOJ_WEB/shared/assets/logo_moj.svg")\" alt=\"MOJ\">"
fi

# --- cores de balão (balloons.json: short -> RRGGBB) + luminância p/ cor do texto -----
: > "$W/balloons.tsv"
if [[ -f "$CDIR/balloons.json" ]] && jq -e . "$CDIR/balloons.json" >/dev/null 2>&1; then
  jq -r 'to_entries[] | [.key, (.value | if type=="object" then (.hex//"") else tostring end)] | @tsv' \
      "$CDIR/balloons.json" 2>/dev/null \
  | while IFS=$'\t' read -r bk bv; do
      bv="${bv#\#}"; bv="$(printf '%s' "$bv" | tr -cd '0-9A-Fa-f' | tr 'a-f' 'A-F')"
      [[ ${#bv} -eq 6 ]] || continue
      r=$((16#${bv:0:2})); g=$((16#${bv:2:2})); b=$((16#${bv:4:2}))
      dark=0; (( (299*r + 587*g + 114*b) / 1000 < 128 )) && dark=1
      printf '%s\t%s\t%s\n' "$bk" "$bv" "$dark"
    done >> "$W/balloons.tsv"
fi

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
.tblwrap{overflow-x:auto}
table.score td.cell{text-align:center;white-space:nowrap;min-width:52px}
table.score th.prob{text-align:center}
td.place{text-align:right;font-weight:800;color:var(--blue-dark);width:2.4em}
td.team .u{color:var(--muted);font-size:.8em}
td.c-try{background:var(--err-bg);color:var(--err);text-align:center}
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
.flag-mini{height:18px;vertical-align:middle;border-radius:2px;box-shadow:0 0 1px rgba(0,0,0,.45)}
input.filter{padding:.45rem .7rem;border:1px solid #c8cfd9;border-radius:10px;margin:0 0 .7rem;width:280px;max-width:100%}
footer{color:var(--muted);font-size:.78rem;margin:2rem 0 .6rem}
.note{color:var(--muted);font-size:.85rem;margin:.4rem 0}
CSSEOF
}

rep_head(){ # <título> <id-da-aba-ativa>
  local title="$1" active="$2" tabs t fn id label
  tabs=""
  for t in "index.html:index:🏆 Placar" "runs.html:runs:📨 Runs" \
           "clarifications.html:clar:💬 Clarifications" "statistics.html:stats:📊 Estatísticas" \
           "documentos.html:docs:📄 Documentos" \
           "staff-tasks.html:staff:🖨️ Tarefas do staff" "infra.html:infra:⚙️ Infra"; do
    IFS=: read -r fn id label <<< "$t"
    [[ "$id" == docs && ! -f "$OUTD/documentos.html" && "$active" != docs ]] && continue
    tabs+="<a href=\"$fn\"$([[ "$id" == "$active" ]] && printf ' class="on"')>$label</a>"
  done
  [[ -f "$OUTD/score-frozen.html" || "$active" == frozen ]] && \
    tabs+="<a href=\"score-frozen.html\"$([[ "$active" == frozen ]] && printf ' class="on"')>❄ Placar congelado</a>"
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
<span class="rep-sub">relatório da competição</span>
</div></header>
<nav class="repnav"><div class="wrap">$tabs</div></nav>
<div class="wrap">
<h2>$(esc "$title")</h2>
EOF
}

rep_foot(){
  cat <<EOF
<footer>Gerado em $(fmt_dt "$NOW") pelo MOJ — moj.naquadah.com.br</footer>
</div>
</body>
</html>
EOF
}

# --- placar TXT -> tabela HTML (icpc/obi/generic) --------------------------------------
# Espelha os parsers do web (score-icpc.js / score-obi.js / score-generic.js): linha 1 =
# modo; linha 2 = cabeçalho COM marcadores iniciais desc/asc (as linhas de dados NÃO têm
# os marcadores — alinham 1:1 com o cabeçalho já sem eles); células icpc: vazio | t/m |
# t/m* (first to solve) | t/-.
rep_score_html(){ # <placar.txt>
  local f="$1"
  [[ -s "$f" ]] || { printf '<p class="note">Sem placar gerado.</p>\n'; return; }
  awk -F: -v MODE="$MODE" -v BF="$W/balloons.tsv" -v FF="$W/flags.tsv" '
    function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
    function esc(s){ gsub(/&/,"\\&amp;",s); gsub(/</,"\\&lt;",s); gsub(/>/,"\\&gt;",s); gsub(/"/,"\\&quot;",s); return s }
    function issys(h){ return (h=="flag"||h=="username"||h=="univ short"||h=="team name"||h=="univ full"||h=="total"||h=="penalty"||h=="lastac"||h=="guest") }
    # fimg[] já vem pronto (<img> com o SVG em data URI, montado em rep_flag); código sem
    # bandeira conhecida vira texto discreto em vez de sumir.
    function flag_html(v){ if(v=="")return ""; if(v in fimg) return fimg[v]; return "<span class=\"small muted\" title=\"" esc(v) "\">" esc(v) "</span>" }
    function team_html(us,tn,uf,un,g,  lbl){
      lbl=""; if(us!="") lbl="[" esc(us) "] ";
      lbl=lbl esc(tn!=""?tn:un)
      if(un!="") lbl=lbl " <span class=\"u\">[" esc(un) "]</span>"
      if(g) lbl=lbl " <span class=\"pill\" title=\"Time convidado (extra-oficial): não entra na classificação\">convidado</span>"
      return "<td class=\"team\" title=\"" esc(uf!=""?uf:us) "\">" lbl "</td>"
    }
    BEGIN{
      while ((getline l < BF) > 0) { n=split(l,a,"\t"); if(n>=3){ bhex[a[1]]=a[2]; bdark[a[1]]=a[3] } }
      close(BF)
      while ((getline l < FF) > 0) { n=split(l,a,"\t"); if(n>=2){ fimg[a[1]]=a[2] } }
      close(FF)
    }
    NR==1{ next }
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
      printf "<div class=\"tblwrap\"><table class=\"score\">\n<thead><tr><th>#</th>"
      if (MODE=="icpc" || MODE=="obi") {
        if(iflag) printf "<th></th>"
        printf "<th>Equipe</th>"
        for(k=1;k<=np;k++){
          sty=""
          if (pname[k] in bhex) sty=" style=\"border-bottom:4px solid #" bhex[pname[k]] "\""
          printf "<th class=\"prob\"%s>%s</th>", sty, esc(pname[k])
        }
        printf "<th>Total</th>"
        if (MODE=="icpc" && ipen) printf "<th>Penal.</th>"
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
          if (nseen>0 && tot==prevtot && pen==prevpen && lac==prevlac) place=prevplace
          else { nseen++; place=nseen }
          prevtot=tot; prevpen=pen; prevlac=lac; prevplace=place; pnum=place
        }
      } else if (!isguest) { nseen++; pnum=nseen }
      printf "<tr%s><td class=\"place\">%s</td>", (isguest?" class=\"guest-row\"":""), (isguest?"–":pnum "")
      if (MODE=="icpc" || MODE=="obi") {
        if(iflag) printf "<td>%s</td>", flag_html(trim($(iflag)))
        printf "%s", team_html((ius?trim($(ius)):""), (iteam?trim($(iteam)):""), (iuf?trim($(iuf)):""), (iuser?trim($(iuser)):""), isguest)
        for(k=1;k<=np;k++){
          v=trim($(pcol[k]))
          if (MODE=="icpc") {
            if (v ~ /^[0-9]+\/[0-9]+\/?\*?$/) {
              fts=(v ~ /\*$/); shown=v; if(fts) sub(/\*$/,"",shown)
              if (pname[k] in bhex) sty="background:#" bhex[pname[k]] ";color:" (bdark[pname[k]]==1?"#fff":"#222")
              else sty="background:#e2ffe9;color:#222"
              sty=sty ";font-weight:700"; if(fts) sty=sty ";box-shadow:inset 0 0 0 2px currentColor"
              printf "<td class=\"cell\" style=\"%s\"%s>%s%s</td>", sty, (fts?" title=\"First to solve\"":""), (fts?"&#9733; ":""), esc(shown)
            } else if (v ~ /^[0-9]+\/-/) printf "<td class=\"cell c-try\">%s</td>", esc(v)
            else printf "<td class=\"cell\">%s</td>", esc(v)
          } else {   # obi: pontos
            if (v!="" && v+0>0) printf "<td class=\"cell\" style=\"background:#dde9ff;color:#1346aa;font-weight:700\">%s</td>", esc(v)
            else if (v=="0")    printf "<td class=\"cell\" style=\"background:#fbe7e9;color:#c4314b;font-weight:700\">%s</td>", esc(v)
            else printf "<td class=\"cell\"></td>"
          }
        }
        printf "<td class=\"cell\"><b>%s</b></td>", esc(itot? trim($(itot)) : "")
        if (MODE=="icpc" && ipen) printf "<td class=\"cell\">%s</td>", esc(trim($(ipen)))
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
    if ($2 ~ /\.(admin|judge|cjudge|staff|cstaff|mon)$/ || $2=="admin") next   # cstaff INCLUÍDO: não casa \.staff$
    login=$2; prob=$3; lang=$4
    v=$5; for(i=6;i<=NF-2;i++) v=v":"$i
    se=$(NF-1)+0; sid=$NF
    letter=(prob in L)? L[prob] : prob
    printf "%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", se, login, letter, lang, canon(v), sid, tname[login], tus[login], tuf[login]
  }' "$W/hist.txt" | sort -n -k1,1 > "$W/runs.tsv"
RUNS_N="$(wc -l < "$W/runs.tsv" | tr -d '[:space:]')"
TEAMS_N="$(awk -F'\t' '$1!~/\.(admin|judge|cjudge|staff|cstaff|mon)$/ && $1!="admin" && $1!=""' "$W/names.tsv" | sort -u | wc -l | tr -d '[:space:]')"

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
OPEN_TXT="$CDIR/var/placar.txt"; FROZEN_NOTE=""
if (( FREEZE > 0 )) && [[ -f "$CDIR/var/placar-full.txt" ]]; then
  OPEN_TXT="$CDIR/var/placar-full.txt"
  fmin=$(( (FREEZE - START) / 60 ))
  {
    rep_head "Placar congelado" frozen
    printf '<p class="note">Visão CONGELADA aos %s min (%s) — é o placar que o público viu durante a prova. O placar final aberto está na aba <a href="index.html">Placar</a>.</p>\n' "$fmin" "$(fmt_dt "$FREEZE")"
    rep_score_html "$CDIR/var/placar.txt"
    rep_foot
  } > "$OUTD/score-frozen.html"
  FROZEN_NOTE="<p class=\"note\">O placar abaixo está ABERTO (sem congelamento). A visão congelada aos ${fmin} min está em <a href=\"score-frozen.html\">Placar congelado</a>.</p>"
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
      rep_head "Documentos da prova" docs
      printf '<p class="note">Os documentos publicados aos times, como foram entregues. Abra o arquivo <b>extraído</b> do pacote (dentro do visualizador de rodadas os links relativos não abrem).</p>\n'
      printf '<div class="tblwrap"><table class="moj">\n<thead><tr><th>Documento</th><th>Idioma</th><th>Arquivo</th><th>Tamanho</th></tr></thead>\n<tbody>\n'
      while IFS=$'\t' read -r dt dl fmt sz; do
        case "$dt" in
          contest)    lbl="📕 Caderno de problemas";;
          times)      lbl="⏱ Limites de tempo";;
          info-sheet) lbl="ℹ️ Informações do ambiente";;
          editorial)  lbl="📝 Editorial (soluções)";;
          *)          lbl="$dt";;
        esac
        printf '<tr><td>%s</td><td>%s</td><td><a href="documentos/%s.%s.%s">%s</a></td><td>%s KB</td></tr>\n' \
          "$(esc "$lbl")" "$dl" "$dt" "$dl" "$fmt" "${fmt^^}" "$(( (sz + 1023) / 1024 ))"
      done < "$W/docs.tsv"
      printf '</tbody></table></div>\n'
      rep_foot
    } > "$OUTD/documentos.html"
  fi

# --- index.html ------------------------------------------------------------------------
mode_label(){ case "$1" in icpc) echo "ICPC";; obi) echo "OBI (pontos)";; heuristic) echo "Heurístico";; treino) echo "Lista/treino";; *) echo "Custom";; esac; }
dur_label(){ local s=$1; (( s<=0 )) && { printf '—'; return; }; printf '%dh%02d' $((s/3600)) $(( (s%3600)/60 )); }
{
  rep_head "Placar e informações" index
  printf '<div class="info"><dl>\n'
  printf '<dt>Competição</dt><dd>%s</dd>\n' "$(esc "$CNAME")"
  printf '<dt>Início</dt><dd>%s</dd>\n' "$(fmt_dt "$START")"
  printf '<dt>Término</dt><dd>%s</dd>\n' "$(fmt_dt "$END")"
  printf '<dt>Duração</dt><dd>%s</dd>\n' "$(dur_label $((END-START)))"
  printf '<dt>Modo</dt><dd>%s</dd>\n' "$(mode_label "$MODE")"
  [[ "$MODE" == icpc ]] && printf '<dt>Penalidade</dt><dd>%s min por tentativa rejeitada</dd>\n' "${PENALTY_MINUTES:-20}"
  if (( FREEZE > 0 )); then
    printf '<dt>Congelamento</dt><dd>%s (aos %s min)</dd>\n' "$(fmt_dt "$FREEZE")" "$(( (FREEZE-START)/60 ))"
  else
    printf '<dt>Congelamento</dt><dd>sem congelamento</dd>\n'
  fi
  printf '<dt>Times</dt><dd>%s</dd>\n' "$TEAMS_N"
  printf '<dt>Submissões</dt><dd>%s (<a href="runs.html">runs</a>)</dd>\n' "$RUNS_N"
  printf '</dl></div>\n'

  printf '<h2>Problemas</h2>\n<div class="tblwrap"><table class="moj">\n<thead><tr><th>Letra</th><th>Problema</th><th>Autor</th><th>Enunciado</th></tr></thead>\n<tbody>\n'
  while IFS=$'\t' read -r Ls pfull hh hp url pauthor; do
    [[ "$url" == - ]] && url=""; [[ "$pauthor" == - ]] && pauthor=""
    links=""
    [[ "$hh" == 1 ]] && links+="<a href=\"statements/$Ls.html\">HTML</a> "
    [[ "$hp" == 1 ]] && links+="<a href=\"statements/$Ls.pdf\">PDF</a> "
    [[ -n "$url" ]] && links+="<a href=\"$(esc "$url")\">link externo</a> "
    [[ -n "$links" ]] || links="—"
    printf '<tr><td><b>%s</b></td><td>%s</td><td>%s</td><td>%s</td></tr>\n' \
      "$(esc "$Ls")" "$(esc "$pfull")" "$([[ -n "$pauthor" ]] && esc "$pauthor" || printf '—')" "$links"
  done < "$W/stmt.tsv"
  printf '</tbody></table></div>\n'

  printf '<h2>Placar final (aberto)</h2>\n'
  printf '%s\n' "$FROZEN_NOTE"
  rep_score_html "$OPEN_TXT"
  rep_foot
} > "$OUTD/index.html"

fi

# --- runs.html ---------------------------------------------------------------------------
{
  rep_head "Runs — todas as submissões" runs
  printf '<p class="note">Todas as submissões da prova (sem código-fonte e sem logs do juiz; veredicto canônico). Clique num cabeçalho para ordenar.</p>\n'
  printf '<input class="filter" id="fq" type="search" placeholder="filtrar por time, login, problema…">\n'
  printf '<div class="tblwrap"><table id="runs">\n<thead><tr><th>#</th><th>Min</th><th>Hora</th><th>Time</th><th>Univ</th><th>Prob</th><th>Ling</th><th>Veredicto</th></tr></thead>\n<tbody>\n'
  awk -F'\t' -v START="$START" '
    function esc(s){ gsub(/&/,"\\&amp;",s); gsub(/</,"\\&lt;",s); gsub(/>/,"\\&gt;",s); gsub(/"/,"\\&quot;",s); return s }
    {
      se=$1+0; login=$2; letter=$3; lang=$4; v=$5; sid=$6; tn=$7; us=$8; uf=$9
      mn=(START>0)? int((se-START)/60) : ""
      hora=strftime("%d/%m %H:%M:%S", se)
      cls="v-rej"
      if (v ~ /^Accepted/) cls="v-ac"
      else if (v ~ /^(Not Answered Yet|On queue|Running)/) cls="v-pend"
      team=(tn!="")? tn : login
      lbl=esc(team) " <span class=\"u\">[" esc(login) "]</span>"
      univ=(us!="")? us : uf
      printf "<tr><td class=\"place\" title=\"%s\">%d</td><td>%s</td><td>%s</td><td class=\"team\">%s</td><td>%s</td><td><b>%s</b></td><td>%s</td><td class=\"%s\">%s</td></tr>\n", \
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
  rep_head "Clarifications" clar
  printf '<p class="note">Perguntas e respostas da prova. Quem perguntou e quem respondeu ficam anônimos.</p>\n'
  ncl=0
  if [[ -d "$CDIR/clarifications" ]]; then
    find "$CDIR/clarifications" -maxdepth 1 -name '*.json' -print0 2>/dev/null \
      | xargs -0 -r jq -c 'del(.login, .answered_by, .answer_claim)' 2>/dev/null \
      | jq -rs --argjson start "$START" 'sort_by(.time) | .[] |
          (if .broadcast==true then "<span class=\"badge org\">Aviso da organização</span>"
           elif .public==true then "<span class=\"badge pub\">Pública</span>"
           else "<span class=\"badge priv\">Privada</span>" end) as $b
          | ((.problem // "general") | if .=="general" then "Geral" else . end) as $p
          | ((.time // 0) | strflocaltime("%d/%m %H:%M")) as $h
          | (if $start>0 and (.time//0)>0 then " (min \(((.time - $start)/60)|floor))" else "" end) as $mn
          | "<div class=\"qa\"><div class=\"meta\"><b>\($p|@html)</b> · \($h)\($mn) · \($b)</div>"
            + "<div class=\"q\">\((.question // "")|@html)</div>"
            + (if ((.answer // "")|length) > 0
               then "<div class=\"a\">\(.answer|@html)</div>"
               else "<div class=\"a\" style=\"border-left-color:#c99\">— sem resposta —</div>" end)
            + "</div>"'
    ncl="$(find "$CDIR/clarifications" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d '[:space:]')"
  fi
  [[ "${ncl:-0}" == 0 ]] && printf '<p class="note">Nenhuma clarification registrada.</p>\n'
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
  local f
  printf '<script>\n'
  printf 'const LANG=%s;\nfunction T(pt,en){return LANG==="en"?en:pt}\n' "$([[ "${LOCALE:-pt}" == en ]] && printf '"en"' || printf '"pt"')"
  for f in "$MOJ_WEB/shared/dom.js" "$MOJ_WEB/lib/charts.js" "$MOJ_WEB/lib/stats-view.js"; do
    [[ -s "$f" ]] || return 1
    sed -E '/^import /d; s/^export (function|const|let|class) /\1 /; /^export \{/d' "$f"
  done
  printf 'const STATS=\n'
  cat "$1"
  printf ';\ntry{ statsSections(STATS).forEach(function(s){ document.getElementById("stats").append(s) }) }\n'
  printf 'catch(e){ document.getElementById("stats").innerHTML = "<p class=\\"note\\">"+String(e)+"</p>" }\n'
  printf '</script>\n'
}

{
  rep_head "Estatísticas" stats
  SJ="$CDIR/var/statistics.cache.json"
  if [[ -s "$SJ" ]]; then
    printf '<div id="stats"></div>\n'
    rep_stats_bundle "$SJ" || printf '<p class="note">Sem os módulos de gráfico (web/ ausente).</p>\n'
    printf '<noscript>\n'
    jq -r '
      def pct: (.*1000|floor)/10;
      "<div class=\"cards\">"
      + "<div class=\"card\"><div class=\"n\">\(.totals.submissions)</div><div class=\"l\">submissões</div></div>"
      + "<div class=\"card\"><div class=\"n\">\(.totals.accepted)</div><div class=\"l\">aceitas</div></div>"
      + "<div class=\"card\"><div class=\"n\">\(.totals.users)</div><div class=\"l\">times ativos</div></div>"
      + "<div class=\"card\"><div class=\"n\">\(.totals.problems_solved)</div><div class=\"l\">problemas resolvidos</div></div>"
      + "</div>"
      + "<h2>Por problema</h2><div class=\"tblwrap\"><table><thead><tr><th>Prob</th><th>Nome</th><th>Subs</th><th>Times</th><th>Resolveram</th><th>Aceitação</th><th>1º a resolver</th><th>Minuto</th></tr></thead><tbody>"
      + ([ .problems[] | "<tr><td><b>\(.short_name|@html)</b></td><td>\(.full_name|@html)</td><td>\(.submissions)</td><td>\(.attempted)</td><td>\(.solved)</td><td>\(.accept_rate|pct)%</td><td>\(.first_solver|@html)</td><td>\(if .first_minute<0 then "—" else (.first_minute|tostring) end)</td></tr>" ] | join(""))
      + "</tbody></table></div>"
      + "<h2>Por linguagem</h2><div class=\"tblwrap\"><table><thead><tr><th>Linguagem</th><th>Subs</th><th>Aceitas</th><th>Times que resolveram</th></tr></thead><tbody>"
      + ([ .languages[] | "<tr><td>\(.lang|@html)</td><td>\(.submissions)</td><td>\(.accepted)</td><td>\(.solvers)</td></tr>" ] | join(""))
      + "</tbody></table></div>"
      + "<h2>Por veredicto</h2><div class=\"tblwrap\"><table><thead><tr><th>Veredicto</th><th>Ocorrências</th></tr></thead><tbody>"
      + ([ .verdicts[] | "<tr><td>\(.verdict|@html)</td><td>\(.count)</td></tr>" ] | join(""))
      + "</tbody></table></div>"
      + (([ .timeline[].submissions ] | max // 0) as $mx
         | "<h2>Linha do tempo (janelas de 10 min)</h2><div class=\"tblwrap\"><table><thead><tr><th>Min</th><th>Submissões</th><th style=\"width:50%\"></th></tr></thead><tbody>"
         + ([ .timeline[] | "<tr><td>\(.minute)</td><td>\(.submissions) (\(.accepted) AC)</td><td><span class=\"tbar\" style=\"width:\(if $mx>0 then (.submissions*100/$mx) else 0 end)%\"></span><span class=\"tbar ac\" style=\"width:\(if $mx>0 then (.accepted*100/$mx) else 0 end)%\"></span></td></tr>" ] | join(""))
         + "</tbody></table></div>")
      + "<h2>Distribuição de problemas resolvidos</h2><div class=\"tblwrap\"><table><thead><tr><th>Resolveu</th><th>Times</th></tr></thead><tbody>"
      + ([ .problems_solved_dist[]? | "<tr><td>\(.solved)</td><td>\(.users)</td></tr>" ] | join(""))
      + "</tbody></table></div>"
    ' "$SJ" 2>/dev/null || printf '<p class="note">Falha ao renderizar as estatísticas.</p>\n'
    printf '</noscript>\n'
  else
    printf '<p class="note">Sem estatísticas geradas.</p>\n'
  fi
  rep_foot
} > "$OUTD/statistics.html"

# --- staff-tasks.html ---------------------------------------------------------------------
{
  rep_head "Tarefas do staff" staff
  printf '<p class="note">Fila atendida pelo staff durante a prova: impressões (🖨️, só METADADOS — o arquivo enviado não é publicado) e balões (🎈).</p>\n'
  PRD="$CDIR/print-requests"
  nst=0
  if [[ -d "$PRD" ]]; then
    printf '<div class="tblwrap"><table>\n<thead><tr><th>Nº</th><th>Tipo</th><th>Hora</th><th>Time</th><th>Univ</th><th>Detalhe</th><th>Status</th><th>Atendimento</th></tr></thead>\n<tbody>\n'
    find "$PRD" -maxdepth 1 -name '*.json' ! -name badges.json ! -name staff-filters.json -print0 2>/dev/null \
      | xargs -0 -r jq -c 'select((.seq? // null) != null)' 2>/dev/null \
      | jq -rs 'sort_by(.seq) | .[] |
          ((.kind // "print")) as $k
          | ((.time // 0) | strflocaltime("%d/%m %H:%M")) as $h
          | (if $k=="balloon"
             then "🎈 <span class=\"swatch\" style=\"background:#\(.color_hex // "CCCCCC")\"></span> \((.color_name // "")|@html) — problema <b>\((.short // "")|@html)</b>"
             else "🖨️ \((.filename // "")|@html) (\(.size // 0) bytes\(if (.pages // 0) > 0 then ", \(.pages) pág." else "" end))" end) as $det
          | (if .status=="delivered" then "<span class=\"badge st-delivered\">entregue</span>"
             elif .status=="printed" then "<span class=\"badge st-printed\">processada</span>"
             else "<span class=\"badge st-pending\">pendente</span>" end) as $st
          | ((if (.processed_at // 0) > 0 then "processada \((.processed_at)|strflocaltime("%H:%M")) por \((.processed_by // "")|@html)" else "" end)
             + (if (.delivered_at // 0) > 0 then " · entregue \((.delivered_at)|strflocaltime("%H:%M")) por \((.delivered_by // "")|@html)" else "" end)) as $att
          | "<tr><td class=\"place\">\(.seq)</td><td>\(if $k=="balloon" then "balão" else "impressão" end)</td><td>\($h)</td>"
            + "<td class=\"team\">\((.fullname // .team // "")|@html) <span class=\"u\">[\((.login // "")|@html)]</span></td>"
            + "<td>\((.univ // "")|@html)</td><td>\($det)</td><td>\($st)</td><td class=\"meta\">\(if ($att|length)>0 then $att else "—" end)</td></tr>"'
    printf '</tbody></table></div>\n'
    nst="$(find "$PRD" -maxdepth 1 -name '*.json' ! -name badges.json ! -name staff-filters.json 2>/dev/null | wc -l | tr -d '[:space:]')"
  fi
  [[ "${nst:-0}" == 0 ]] && printf '<p class="note">Nenhuma tarefa registrada.</p>\n'
  rep_foot
} > "$OUTD/staff-tasks.html"

# --- infra.html (dados da aba Situação, janela = prova inteira) -----------------------------
{
  rep_head "Infraestrutura de julgamento" infra
  printf '<p class="note">Snapshot no momento da geração do relatório (%s) + métricas de resposta da prova inteira.</p>\n' "$(fmt_dt "$NOW")"

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
  awk -F'\t' '
    { w[NR]=$1+0; s+=$1 }
    END{
      n=NR
      if(n==0){ printf "<div class=\"cards\"><div class=\"card\"><div class=\"n\">0</div><div class=\"l\">respostas medidas</div></div></div>\n"; exit }
      p50=w[int((n-1)*0.5)+1]; p95=w[int((n-1)*0.95)+1]
      printf "<div class=\"cards\">"
      printf "<div class=\"card\"><div class=\"n\">%d</div><div class=\"l\">respostas medidas</div></div>", n
      printf "<div class=\"card\"><div class=\"n\">%ds</div><div class=\"l\">espera média</div></div>", s/n
      printf "<div class=\"card\"><div class=\"n\">%ds</div><div class=\"l\">mediana (p50)</div></div>", p50
      printf "<div class=\"card\"><div class=\"n\">%ds</div><div class=\"l\">p95</div></div>", p95
      printf "<div class=\"card\"><div class=\"n\">%ds</div><div class=\"l\">máxima</div></div>", w[n]
      printf "</div>\n"
    }' "$W/waits.tsv"
  printf '<p class="note">Cobertura: %s de %s submissões com tempo de resposta registrado.</p>\n' "$RJOIN" "$RTOT"

  printf '<h2>Espera média por problema</h2>\n<div class="tblwrap"><table><thead><tr><th>Prob</th><th>Julgadas</th><th>Espera média</th><th>Máxima</th></tr></thead><tbody>\n'
  awk -F'\t' '{ c[$2]++; s[$2]+=$1; if($1+0>mx[$2]) mx[$2]=$1+0 }
    END{ for(p in c) printf "%s\t%d\t%d\t%d\n", p, c[p], s[p]/c[p], mx[p] }' "$W/waits.tsv" \
    | sort | awk -F'\t' '{ printf "<tr><td><b>%s</b></td><td>%s</td><td>%ss</td><td>%ss</td></tr>\n", $1, $2, $3, $4 }'
  printf '</tbody></table></div>\n'

  printf '<h2>Julgamentos por juiz</h2>\n<div class="tblwrap"><table><thead><tr><th>Juiz (host)</th><th>Julgamentos</th><th>Duração média do julgamento</th></tr></thead><tbody>\n'
  awk -F'\t' '$3!=""{ c[$3]++; s[$3]+=$4 } END{ for(h in c) printf "<tr><td>%s</td><td>%d</td><td>%.1fs</td></tr>\n", h, c[h], s[h]/c[h] }' "$W/waits.tsv" | sort
  printf '</tbody></table></div>\n'

  printf '<h2>Espera ao longo da prova (janelas de 10 min)</h2>\n<div class="tblwrap"><table><thead><tr><th>Min</th><th>Julgadas</th><th>Espera média</th><th style="width:45%%"></th></tr></thead><tbody>\n'
  awk -F'\t' -v START="$START" '
    { b=int((($5+0)-START)/600); if(b<0)b=0; c[b]++; s[b]+=$1; if(b>mb)mb=b }
    END{
      mxa=0; for(i=0;i<=mb;i++) if(c[i] && s[i]/c[i]>mxa) mxa=s[i]/c[i]
      for(i=0;i<=mb;i++) if(c[i]) printf "<tr><td>%d</td><td>%d</td><td>%ds</td><td><span class=\"tbar\" style=\"width:%d%%\"></span></td></tr>\n", i*10, c[i], s[i]/c[i], (mxa>0? int(s[i]/c[i]*100/mxa) : 0)
    }' "$W/waits.tsv"
  printf '</tbody></table></div>\n'

  # snapshot do cluster (registry) — pode estar vazio/for a do ar após a prova
  printf '<h2>Juízes registrados (snapshot)</h2>\n'
  if source "$HERE/../judge-gw/sched-lib.sh" 2>/dev/null && [[ -d "${REGISTRYDIR:-}" ]]; then
    qd="$(find "${QUEUEDIR:-/nonexistent}" -mindepth 2 -maxdepth 2 -name '*.json' 2>/dev/null | wc -l | tr -d '[:space:]')"
    printf '<p class="note">Fila no momento da geração: %s job(s) aguardando.</p>\n' "${qd:-0}"
    printf '<div class="tblwrap"><table><thead><tr><th>Host</th><th>Estado</th><th>Online</th><th>Último heartbeat</th><th>Linguagens</th><th>Problemas em cache</th></tr></thead><tbody>\n'
    find "$REGISTRYDIR" -maxdepth 1 -name '*.json' 2>/dev/null | sort | while IFS= read -r jf; do
      jq -r --argjson now "$NOW" --argjson ttl "${REG_TTL:-30}" '
        "<tr><td>\(.host // "?" | @html)</td><td>\(.state // "?" | @html)</td>"
        + "<td>\(if ((.last_seen//0) >= ($now - $ttl)) then "✅" else "—" end)</td>"
        + "<td>\(if (.last_seen//0) > 0 then ((.last_seen)|strflocaltime("%d/%m %H:%M:%S")) else "—" end)</td>"
        + "<td>\((.langs // []) | join(", ") | @html)</td>"
        + "<td>\(.problems_count // ((.problems//{})|length))</td></tr>"' "$jf" 2>/dev/null
    done
    printf '</tbody></table></div>\n'
  else
    printf '<p class="note">Sem registro de juízes disponível no momento da geração.</p>\n'
  fi
  rep_foot
} > "$OUTD/infra.html"

echo "$OUTD"
