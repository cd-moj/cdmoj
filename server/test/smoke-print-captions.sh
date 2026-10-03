#!/bin/bash
# smoke-print-captions.sh — o cache de letreiros da impressão (lib/print.sh, _pr_cap_tile) e o
# magick de UMA thread não mudam UM pixel do papel, e o cache de fato é reaproveitado.
#
#   bash server/test/smoke-print-captions.sh
#
# POR QUE EXISTE: no TCP 2026 (03/10/2026) a folha custava ~3,6 s e quase tudo era `caption:` com
# corpo automático — os rótulos FIXOS ("TAREA N.º (verifícala con el sistema)", a linha de
# páginas, "Firma de quien entregó:") eram ~1,6 s, iguais em toda folha. Agora cada letreiro vira
# um PNG cacheado e a folha só compõe. O risco de um cache assim é o papel mudar sem ninguém ver:
# no IM7 o `-weight` de um letreiro VAZA p/ os seguintes (parênteses não isolam settings), e um
# tile renderizado "limpo" sairia diferente. Por isso a régua aqui é PIXEL A PIXEL contra a via
# inline (PR_CAP_CACHE=0), na capa, na página de código (o selo do rodapé) e na folha do balão.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"          # .../server
FIX="$(mktemp -d)"; trap 'chmod -R u+w "$FIX" 2>/dev/null; rm -rf "$FIX"' EXIT
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; ((fail++)); fi; }
for b in paps ps2pdf pdfinfo pdfunite magick gs iconv nl file md5sum; do
  command -v "$b" >/dev/null 2>&1 || { echo "SKIP: falta '$b' — este teste roda onde a cadeia de"
    echo "      impressão existe (a imagem, ou um dev com paps+ghostscript instalados)."; exit 0; }
done
export CONTESTSDIR="$FIX" RUNDIR="$FIX/run"; mkdir -p "$RUNDIR"
C="$FIX/pr"; D="$C/print-requests"; mkdir -p "$D"
printf 'CONTEST_ID=pr\nLOCALE=es\n' > "$C/conf"
source "$ROOT/api/v1/lib/print.sh" 2>/dev/null
for i in $(seq 1 70); do printf '    s += v[%d] * %d; // soluci\303\263n %d\n' "$i" "$i" "$i"; done > "$FIX/sol.cpp"
mkreq(){ # <id> — pedido de código; nome de time com acento e `%`/`@` (passam pelo cap_esc)
  cp "$FIX/sol.cpp" "$D/$1.src"
  jq -cn --arg id "$1" '{id:$id, seq:42, login:"teamuvm001", team:"Húsares del código 100%", univ:"@Universidad Viña del Mar",
    kind:"print", filename:"sol.cpp", time:100, status:"pending", pages:0}' > "$D/$1.json"
}
mkball(){ # <id> — folha de balão, com a faixa de PRIMEIRO DA SEDE (os letreiros dentro dela)
  jq -cn --arg id "$1" '{id:$id, seq:7, login:"teamuvm001", team:"Húsares del código", univ:"Universidad Viña del Mar",
    kind:"balloon", short:"C", color_hex:"1E90FF", color_name:"azul", color_lang:"es", first_site:true,
    time:100, status:"pending"}' > "$D/$1.json"
}
# pelas portas de verdade (pr_build_pdf/pr_build_balloon): o render roda em subshell sob o flock,
# como na API — chamar o _pr_render direto deixaria o trap RETURN dele vivo neste shell
render(){ pr_build_pdf pr "$1" >/dev/null; }
pdf(){ printf '%s' "$D/$1.combined.pdf"; }
# AE = nº de pixels diferentes entre a página <p> de dois PDFs (rasterizados a 150 dpi)
ae(){ magick compare -metric AE <(magick -density 150 "$1[$3]" png:- 2>/dev/null) <(magick -density 150 "$2[$3]" png:- 2>/dev/null) null: 2>&1 | awk '{print $1+0}'; }
ntiles(){ find "$RUNDIR/print-cap" -maxdepth 1 -name '*.png' 2>/dev/null | wc -l; }

echo "== capa + código: via inline × via tiles =="
PR_CAP_CACHE=0; mkreq inl; render inl
ck "via inline gera a folha (capa + código)" '[[ "$(pdfinfo "$(pdf inl)" | awk "/^Pages/{print \$2}")" == 3 ]]'
ck "via inline não cria tile" '[[ "$(ntiles)" == 0 ]]'
PR_CAP_CACHE=1; mkreq t1; render t1
n1="$(ntiles)"
ck "1ª folha com cache cria os tiles (≥9: rótulos + time)" '(( n1 >= 9 ))'
ck "capa idêntica pixel a pixel (tiles frios)" '[[ "$(ae "$(pdf inl)" "$(pdf t1)" 0)" == 0 ]]'
# (a página de código não entra: o cabeçalho do paps leva a HORA, e duas folhas geradas em segundos
# diferentes diferem ali — o selo do rodapé não passa pelo cache de letreiros)
mkreq t2; render t2
ck "2ª folha do MESMO time reaproveita tudo (nenhum tile novo)" '[[ "$(ntiles)" == "$n1" ]]'
ck "capa idêntica pixel a pixel (tiles quentes)" '[[ "$(ae "$(pdf inl)" "$(pdf t2)" 0)" == 0 ]]'

echo "== balão: via inline × via tiles =="
PR_CAP_CACHE=0; mkball binl; pr_build_balloon pr binl >/dev/null
PR_CAP_CACHE=1; mkball bt;   pr_build_balloon pr bt   >/dev/null
ck "folha do balão sai pelas duas vias" '[[ -s "$(pdf binl)" && -s "$(pdf bt)" ]]'
ck "folha do balão idêntica pixel a pixel (com a faixa de 1º da sede)" '[[ "$(ae "$(pdf binl)" "$(pdf bt)" 0)" == 0 ]]'

echo "== tile apagado do cache (poda) depois de criado: a folha sai igual =="
# a poda pode apagar o tile entre o _pr_cap_tile e o magick ler; a folha o PRENDE no workdir antes.
# Aqui: o cache some INTEIRO no meio do render (o `ln`/`cp` acontece antes do magick).
_orig_tile="$(declare -f _pr_cap_tile)"
eval "${_orig_tile/#_pr_cap_tile/_pr_cap_tile_real}"
_pr_cap_tile(){ local f; f="$(_pr_cap_tile_real "$@")" || return 1; printf '%s' "$f"; }
_pr_magick(){ [[ "${1:-}" == -size && "${2:-}" == 1240x1754 ]] && rm -rf "$RUNDIR/print-cap"; MAGICK_THREAD_LIMIT=1 magick "$@"; }
mkreq gone; render gone
ck "cache apagado logo antes do magick da capa: folha idêntica" '[[ "$(ae "$(pdf inl)" "$(pdf gone)" 0)" == 0 ]]'
eval "$_orig_tile"; unset -f _pr_cap_tile_real
_pr_magick() { MAGICK_THREAD_LIMIT="${PR_MAGICK_THREADS:-1}" magick "$@"; }

echo "== cache indisponível: a folha sai mesmo assim =="
rm -rf "$RUNDIR/print-cap"; chmod a-w "$RUNDIR"
mkreq ro; render ro
ck "RUNDIR sem escrita: folha gerada (letreiros inline)" '[[ -s "$(pdf ro)" ]]'
ck "…e idêntica à via inline" '[[ "$(ae "$(pdf inl)" "$(pdf ro)" 0)" == 0 ]]'
chmod u+w "$RUNDIR"

echo "== uma thread só nos renders da lib =="
magick(){ printf '%s' "${MAGICK_THREAD_LIMIT:-}"; }
ck "_pr_magick roda o IM com MAGICK_THREAD_LIMIT=1" '[[ "$(_pr_magick)" == 1 ]]'
ck "PR_MAGICK_THREADS muda o teto" '[[ "$(PR_MAGICK_THREADS=2 _pr_magick)" == 2 ]]'
ck "nada exportado p/ o resto do processo" '[[ -z "${MAGICK_THREAD_LIMIT:-}" ]]'
unset -f magick

echo
echo "smoke-print-captions: $pass ok, $fail falha(s)"
(( fail == 0 ))
