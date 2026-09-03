#!/usr/bin/env bash
#
# report-publish.sh <contest> <by>              publica o relatório estático (histórico)
# report-publish.sh <contest> <by> --unpublish  despublica
#
# PUBLICAR = gerar o site do report-gen em contests/<c>/relatorio.tmp/, trocar ATOMICAMENTE
# por contests/<c>/relatorio/ (o que o nginx serve em /relatorio/<c>/), carimbar
# var/report-published.json {at,by,pages,bytes} e gravar REPORT_PUBLISHED=<epoch> no conf —
# é o conf (mtime) que invalida o cache do /index/contests, e é dele que a home e o
# /contests/ tiram o `report_url`. Standalone (molde do report-gen): o handler
# admin/report-publish o DESTACA (setsid) porque a geração leva ~100 s numa prova grande;
# o progresso vai em var/report-publish.status.json {state:running|done|error,…}.
# Um por vez: flock em var/.report.lock (o mesmo do download tar.gz).
set -u
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
SELF="$(readlink -f "$0")"; HERE="$(dirname "$SELF")"
C="${1:-}"; BY="${2:-}"; MODE="${3:-}"
case "$C" in *[!A-Za-z0-9._-]*|""|*..*) echo "report-publish: contest inválido" >&2; exit 1;; esac
CD="$CONTESTSDIR/$C"; [[ -d "$CD" && -f "$CD/conf" ]] || { echo "report-publish: contest não existe" >&2; exit 1; }
mkdir -p "$CD/var" 2>/dev/null
ST="$CD/var/report-publish.status.json"; STAMP="$CD/var/report-published.json"; DST="$CD/relatorio"; TMP="$CD/relatorio.tmp"
START="$EPOCHSECONDS"
status(){ jq -cn --arg s "$1" --arg by "$BY" --arg e "${2:-}" --argjson t "$EPOCHSECONDS" --argjson st "$START" \
            '{state:$s, by:$by, started:$st, updated:$t} + (if $e != "" then {error:$e} else {} end)' > "$ST.tmp.$$" 2>/dev/null \
          && mv -f "$ST.tmp.$$" "$ST"; }
# conf: mesmo idioma do cc_set_conf_var/cc_del_conf_var (linha KEY=%q, reescrita atômica)
conf_set(){ local tmp; tmp="$(mktemp "$CD/conf.XXXXXX")" || return 1
  grep -v "^$1=" "$CD/conf" > "$tmp"; printf '%s=%q\n' "$1" "$2" >> "$tmp"; cat "$tmp" > "$CD/conf" && rm -f "$tmp"; }
conf_del(){ local tmp; tmp="$(mktemp "$CD/conf.XXXXXX")" || return 1
  grep -v "^$1=" "$CD/conf" > "$tmp"; cat "$tmp" > "$CD/conf" && rm -f "$tmp"; }

if [[ "$MODE" == --unpublish ]]; then
  rm -rf "$DST" "$DST.old" "$TMP"; rm -f "$STAMP"; conf_del REPORT_PUBLISHED
  status done; exit 0
fi

exec 9>"$CD/var/.report.lock"
flock -n 9 || { status error "já existe uma geração em andamento"; exit 3; }
status running
rm -rf "$TMP"
if ! bash "$HERE/report-gen.sh" "$C" "$TMP" >/dev/null 2>"$CD/var/report-gen.err"; then
  status error "report-gen falhou: $(head -c 300 "$CD/var/report-gen.err" 2>/dev/null)"; rm -rf "$TMP"; exit 2
fi
rm -f "$CD/var/report-gen.err"
[[ -s "$TMP/index.html" ]] || { status error "relatório sem index.html"; rm -rf "$TMP"; exit 2; }
pages="$(find "$TMP" -name '*.html' | wc -l | tr -d '[:space:]')"
bytes="$(du -sb "$TMP" 2>/dev/null | cut -f1)"; [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
# troca atômica: quem estiver lendo o site antigo termina a página; o novo entra inteiro
rm -rf "$DST.old"; [[ -d "$DST" ]] && mv "$DST" "$DST.old"
mv "$TMP" "$DST"; rm -rf "$DST.old"
jq -cn --argjson at "$EPOCHSECONDS" --arg by "$BY" --argjson p "$pages" --argjson b "$bytes" \
  '{at:$at, by:$by, pages:$p, bytes:$b}' > "$STAMP.tmp.$$" && mv -f "$STAMP.tmp.$$" "$STAMP"
conf_set REPORT_PUBLISHED "$EPOCHSECONDS"
status done
exit 0
