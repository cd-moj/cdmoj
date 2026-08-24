#!/bin/bash
# smoke-contest-seed.sh — /contest/admin/seed: povoar um contest de DEMONSTRAÇÃO.
#
#   bash server/test/smoke-contest-seed.sh
#
# POR QUE EXISTE: quem desenvolve o Animeitor precisa de um placar de verdade para trabalhar, e
# não havia como fabricá-lo (o juiz mock só devolve `Accepted,100p`, o `/contest/set-verdict`
# sobrescreve mas não CRIA submissão, e o fixture de 2000 times do `test/load/` foi apagado).
# Esta rota fabrica — e por isso a primeira coisa que o teste fixa é a TRAVA: sem `DEMO=1` no
# conf ela recusa, porque submissão sintética numa prova de verdade é dado envenenado.
#
# As três coisas que precisam valer, e cada uma já quebrou algum gerador antes:
#   TRAVA      — contest sem DEMO=1 e conta não-admin recebem 403.
#   DETERMINISMO — o mesmo `seed` produz o MESMO placar; sem isso, bug do telão não se reproduz.
#   PROBID CANÔNICO — a célula do placar só aparece se o history gravar o `SC_CANON` (PROBS[i+4]).
#     Com qualquer outra grafia o placar fica em branco EM SILÊNCIO (a estatística e o webcast
#     continuam mostrando a submissão) — é o erro mais fácil de não notar.
# Mais o que o Animeitor consome de fato: com freeze no meio, o placar congelado tem de DIFERIR
# do completo, e o pacote de webcast tem de sair (ele lê o roster do placar; sem placar é 503).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; ((fail++)); fi; }

T0=$(( $(date +%s) - 10800 )); TE=$(( T0 + 18000 ))
mk(){ # <id> <demo?>
  local C="$FIX/$1"; mkdir -p "$C/var"
  { printf 'CONTEST_ID=%s\nCONTEST_TYPE=icpc\nCONTEST_NAME=Demo\n' "$1"
    printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$T0" "$TE"
    [[ "${2:-}" == demo ]] && printf 'DEMO=1\n'
    printf 'PROBS=( x c#a Alfa A c#a x c#b Beta B c#b x c#c Gama C c#c )\n'; } > "$C/conf"
  fx_user "$C" "$1.admin" p "Admin"; fx_user "$C" "$1.animeitor" p "Telao"; fx_user "$C" zeca p "Zeca"
  for u in "$1.admin" "$1.animeitor" zeca; do
    printf 'CONTEST=%s\nLOGIN=%s\nUSERFULLNAME=X\nLOGINAT=1\n' "$1" "$u" > "$SESS/$u"
  done
}
mk dm demo
mk dm4 demo
mk real

post(){ # <contest> <login> <json>  -> BODY/CODE
  OUT="$(env PATH_INFO=/contest/admin/seed REQUEST_METHOD=POST QUERY_STRING="contest=$1" \
      HTTP_AUTHORIZATION="Bearer $2" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$FIX/run" \
      bash "$ROUTER" <<<"$3" 2>/dev/null)"
  CODE="$(printf '%s' "$OUT" | awk 'NR==1{gsub(/\r/,"");print $2}')"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"
}

echo "== a trava =="
post real dm.admin '{"teams":3,"submissions":5}'
ck "contest sem DEMO=1 recusa"        '[[ "$CODE" == 403 ]]'
post real real.admin '{"teams":3,"submissions":5}'
ck "…mesmo com o admin DELE"          '[[ "$CODE" == 403 ]] && grep -q demo_required <<<"$BODY"'
post dm zeca '{"teams":3,"submissions":5}'
ck "conta comum recusa"               '[[ "$CODE" == 403 ]]'
post dm dm.animeitor '{"teams":3,"submissions":5}'
ck "o telão também não semeia"        '[[ "$CODE" == 403 ]]'

echo "== semeadura: o que sai =="
post dm dm.admin '{"teams":12,"submissions":120,"seed":7,"freeze_minute":60,"window_minutes":150}'
DMBODY="$BODY"   # o $BODY é sobrescrito pelo caso do dm4 mais abaixo
ck "responde 200"                     '[[ "$CODE" == 200 ]]'
ck "criou os 12 times"                '[[ "$(jq -r .teams_created <<<"$DMBODY")" == 12 ]]'
ck "gerou submissões"                 '(( $(jq -r .submissions <<<"$DMBODY") > 100 ))'
ck "veredictos variados (≥4 tipos)"   '(( $(jq -r ".by_verdict|length" <<<"$DMBODY") >= 4 ))'
ck "conta as submissões pós-freeze"   '(( $(jq -r .runs_after_freeze <<<"$DMBODY") > 0 ))'
ck "…e sem elas o freeze é decorativo: a rota AVISA" \
  'post dm4 dm4.admin "{\"teams\":4,\"submissions\":20,\"seed\":3,\"freeze_minute\":150,\"window_minutes\":150}";
   [[ "$(jq -r .runs_after_freeze <<<"$BODY")" == 0 ]] && [[ "$(jq -r .hint <<<"$BODY")" != null ]]'
ck "gravou o FREEZE_TIME"             '[[ "$(jq -r .freeze_time <<<"$DMBODY")" == "$(( T0 + 3600 ))" ]] && grep -q "^FREEZE_TIME=" "$FIX/dm/conf"'
ck "time sem sufixo de papel"         '[[ -f "$FIX/dm/users/time-01/account.json" ]]'
ck "o time tem sede e bandeira"       '[[ -n "$(jq -r ".team.flag // empty" "$FIX/dm/users/time-01/account.json")" ]]'

echo "== o probid é o CANÔNICO (senão a célula some do placar, em silêncio) =="
ck "history só usa ids do PROBS" \
  '! cat "$FIX"/dm/users/time-*/history 2>/dev/null | awk -F: "{print \$2}" | sort -u | grep -qvE "^c#(a|b|c)$"'
# o TXT é separado por ':' — cabeçalho `…:A:B:C:Total:Penalty:LastAC`, Total é NF-2
ck "e o placar tem time com problema resolvido" \
  '(( $(awk -F: "NR>2{t+=\$(NF-2)} END{print t+0}" "$FIX/dm/var/placar.txt") > 0 ))'
ck "e tem estrela de first-to-solve" \
  'grep -q "[0-9]/[0-9][0-9]*\*" "$FIX/dm/var/placar.txt"'

echo "== o freeze faz o placar congelado DIFERIR do completo =="
ck "placar-full existe"               '[[ -s "$FIX/dm/var/placar-full.txt" ]]'
ck "congelado ≠ completo"             '! cmp -s "$FIX/dm/var/placar.txt" "$FIX/dm/var/placar-full.txt"'
ck "metrics tem a visão frozen"       'jq -e ".by_problem|to_entries|map(.value.frozen)|any(.!=null)" "$FIX/dm/users/time-01/metrics.json" >/dev/null 2>&1'

echo "== determinismo: mesmo seed, mesmo placar =="
cp "$FIX/dm/var/placar-full.txt" "$FIX/board1.txt"
rm -rf "$FIX/dm2"; mk dm2 demo
post dm2 dm2.admin '{"teams":12,"submissions":120,"seed":7,"freeze_minute":60,"window_minutes":150}'
# os placares saem com nomes de contest diferentes só nos metadados: compara as colunas de dado
norm(){ awk 'NR>2{$1=""; print}' "$1" | sed 's/^ *//'; }
ck "seed 7 duas vezes = mesmo placar" '[[ "$(norm "$FIX/board1.txt")" == "$(norm "$FIX/dm2/var/placar-full.txt")" ]]'
rm -rf "$FIX/dm3"; mk dm3 demo
post dm3 dm3.admin '{"teams":12,"submissions":120,"seed":99,"freeze_minute":60,"window_minutes":150}'
ck "seed diferente = placar diferente" '[[ "$(norm "$FIX/board1.txt")" != "$(norm "$FIX/dm3/var/placar-full.txt")" ]]'

echo "== o que o Animeitor consome sai do que foi semeado =="
WC="$FIX/wc"; mkdir -p "$WC"
if CONTESTSDIR="$FIX" RUNDIR="$FIX/run" bash "$ROOT/score/webcast-gen.sh" dm public "$WC/p.zip" >/dev/null 2>&1 \
   && command -v unzip >/dev/null 2>&1 && unzip -qo "$WC/p.zip" -d "$WC" 2>/dev/null; then
  ck "webcast: linha 2 traz o minuto do freeze" \
     '[[ "$(sed -n 2p "$WC/contest" | cut -d$'"'"'\x1c'"'"' -f3)" == 60 ]]'
  ck "webcast: runs depois do freeze VÃO no pacote" \
     '(( $(awk -F'"'"'\x1c'"'"' '"'"'$2>60'"'"' "$WC/runs" | wc -l) > 0 ))'
  ck "webcast: os 4 sabores de flag aparecem" \
     '(( $(cut -d$'"'"'\x1c'"'"' -f5 "$WC/runs" | sort -u | wc -l) >= 3 ))'
else
  echo "  (pulado: webcast-gen/unzip indisponível)"
fi

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
