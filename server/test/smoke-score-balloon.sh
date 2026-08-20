#!/bin/bash
# Balão × visibilidade: o problema A é BRANCO na paleta padrão, e branco sobre o fundo branco
# do placar é o mesmo pixel (1,00:1) — "resolveu" sumia. Cobre o modo de pintura da célula
# (`balloon_style`: icon = neutro + ponto da cor · fill = cor no fundo + contorno), o contrato
# do /contest/basic e do settings, e o gêmeo em awk do relatório nos DOIS modos.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; EXT="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$EXT"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"

C="$FIX/bs"; mkdir -p "$C/var" "$C/enunciados" "$C/print-requests"
T0=$(( $(date +%s) - 7200 )); TE=$(( T0 + 18000 ))
# SEM balloons.json de propósito: é o caso de TODO contest (medido em produção — de 1482, um
# só tem o arquivo). A paleta padrão entrega A=FFFFFF.
{ printf 'CONTEST_ID=bs\nCONTEST_TYPE=icpc\nCONTEST_NAME=Prova\\ Balao\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$T0" "$TE"
  printf "PROBS=( x col#pa Alfa A col#pa x col#pb Beta B col#pb )\n"; } > "$C/conf"
fx_user "$C" bs.admin p "Admin"; fx_user "$C" alice a "Time Alice"; fx_user "$C" bob b "Time Bob"
# DOIS solvers do mesmo problema: o 1º é first-to-solve (o anel do ★ vence, de propósito) e o
# 2º é o acerto comum — é ele que exercita o contorno da cor no modo 'fill'
printf '10:col#pa:C:Accepted,100p:%s:sA1\n' "$(( T0 + 600 ))" > "$C/users/alice/history"
printf '20:col#pa:C:Accepted,100p:%s:sB1\n' "$(( T0 + 1200 ))" > "$C/users/bob/history"
printf 'CONTEST=bs\nLOGIN=bs.admin\nUSERFULLNAME=Admin\nLOGINAT=1\n' > "$SESS/adm"
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-contest=bs}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" MOJ_PROBLEMS_DIR="$FIX/probs" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

echo "== o modo chega às telas pelo /contest/basic =="
call /contest/basic GET '' '' 'contest=bs'
ck "padrão é 'icon' (o legível)"     '[[ "$(jq -r .balloon_style <<<"$BODY")" == icon ]]'
ck "e é público (sem sessão)"        '[[ "$(jq -r .success <<<"$BODY")" == true ]]'

echo "== o admin escolhe =="
call /contest/admin/settings GET '' adm 'contest=bs'
ck "settings expõe o modo"           '[[ "$(jq -r .balloon_style <<<"$BODY")" == icon ]]'
call /contest/admin/settings POST '{"balloon_style":"xis"}' adm 'contest=bs'
ck "valor inválido recusado (422)"   '[[ "$OUT" == *"Status: 422"* && "$(jq -r .error.code <<<"$BODY")" == balloon_style_invalid ]]'
call /contest/admin/settings POST '{"balloon_style":"fill"}' adm 'contest=bs'
ck "grava fill no conf"              'grep -q "^SCORE_BALLOON_STYLE=fill" "$C/conf"'
call /contest/basic GET '' '' 'contest=bs'
ck "basic passa a dizer fill"        '[[ "$(jq -r .balloon_style <<<"$BODY")" == fill ]]'
call /contest/admin/settings POST '{"balloon_style":"icon"}' adm 'contest=bs'
ck "voltar ao padrão LIMPA o conf"   '! grep -q "^SCORE_BALLOON_STYLE=" "$C/conf"'

echo "== o contorno: a conta do bash é a mesma do JS (gêmeos) =="
# bl_edge vive no report-gen.sh; o gêmeo é balloonEdge() em web/contest/score/score-colors.js
eval "$(sed -n '/^bl_edge()/,/^}/p' "$ROOT/score/report-gen.sh")"
ck "branco vira cinza visível"       '[[ "$(bl_edge FFFFFF)" == 8*  ]]'
ck "preto NÃO muda (já contrasta)"   '[[ "$(bl_edge 000000)" == 000000 ]]'
ck "amarelo escurece"                '[[ "$(bl_edge FFFF00)" == 999900 ]]'
ck "verde-limão escurece o bastante" '[[ "$(bl_edge 00FF00)" == 00A800 ]]'

echo "== relatório: os dois modos (gêmeo em awk) =="
# o corpo é BINÁRIO: command substitution come byte nulo, então grava em arquivo e conta os
# bytes do cabeçalho CGI (mesma receita do smoke-contest-report.sh)
callf(){ PATH_INFO="$1" REQUEST_METHOD=GET QUERY_STRING="$3" HTTP_AUTHORIZATION="Bearer $2" \
  CONTESTSDIR="$FIX" SESSIONDIR="$SESS" MOJ_PROBLEMS_DIR="$FIX/probs" bash "$ROUTER" </dev/null > "$4" 2>/dev/null; }
gen(){ rm -rf "${EXT:?}"/*; callf /contest/admin/report adm 'contest=bs' "$FIX/resp.bin"
  local off=0 hline
  while IFS= read -r hline; do off=$(( off + ${#hline} + 1 ))
    [[ "$hline" == $'\r' || -z "$hline" ]] && break
  done < <(LC_ALL=C head -c 1000 "$FIX/resp.bin")
  tail -c +$(( off + 1 )) "$FIX/resp.bin" > "$FIX/rel.tar.gz"
  tar -xzf "$FIX/rel.tar.gz" -C "$EXT" 2>/dev/null; }
gen
R="$EXT/relatorio-bs"
ck "icon: célula neutra"             'grep -q "cell ok\" style=\"background:#e2ffe9" "$R/index.html"'
ck "icon: ponto com a cor BRANCA"    'grep -q -- "--bdot:#FFFFFF" "$R/index.html"'
ck "icon: e o contorno do ponto"     'grep -qE -- "--bdot-edge:#8[0-9A-F]{5}" "$R/index.html"'
ck "cabeçalho: balão, não barra"     'grep -q "th class=\"prob\"><svg class=\"balloon-svg\"" "$R/index.html" && ! grep -q "border-bottom:4px solid" "$R/index.html"'
call /contest/admin/settings POST '{"balloon_style":"fill"}' adm 'contest=bs'
gen
ck "fill: célula com a cor do balão" 'grep -q "cell ok\" style=\"background:#FFFFFF" "$R/index.html"'
ck "fill: com o contorno (não some)" 'grep -qE "background:#FFFFFF;color:#222;box-shadow:inset 0 0 0 1px #8[0-9A-F]{5}" "$R/index.html"'
ck "fill: o anel do ★ ainda vence"   'grep -q "box-shadow:inset 0 0 0 2px currentColor" "$R/index.html"'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
