#!/bin/bash
# smoke-alerts-jq.sh — o aviso de ERRO DE JQ (lib/alerts.sh, _alert_jq_errors; 20/11/2026). O embrulho do jq
# (lib/jq-safe.sh) grava cada falha em run/jq-errors/AAAA-MM-DD.log; aqui o alerta do mojinho as conta. Afirma:
#   • erro novo ⇒ UM aviso (incidente .txt no outbox) com o total e as origens mais frequentes (classe, quem chamou, rota);
#   • dentro do ALERT_JQ_COOLDOWN não repete — e o que chegou no meio sai SOMADO no aviso seguinte (nada se perde);
#   • `argv-convertido` (o embrulho salvou um argumento grande) não avisa; sem linha nova, nada;
#   • virada do dia: termina o arquivo de ontem (do offset) e lê o de hoje inteiro;
#   • texto do log com < > & sai escapado (o aviso é HTML do Telegram) — e os dois escapes (_alert_html, ab_html), que no
#     bash 5.2 trocavam `<` por `<lt;` (o & cru da substituição vira o texto casado).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
RUN="$(mktemp -d)"; trap 'rm -rf "$RUN"' EXIT
export RUNDIR="$RUN" REGISTRYDIR="$RUN/registry" QUEUEDIR="$RUN/queue" SPOOLDIR="$RUN/spool/submissions" \
       ALERT_EVAL_THROTTLE=0 CONTESTSDIR="$RUN/contests" JQ_SAFE_LOG="$RUN/jq-teste.log"
mkdir -p "$REGISTRYDIR" "$QUEUEDIR" "$SPOOLDIR" "$CONTESTSDIR" "$RUN/jq-errors"
source "$ROOT/api/v1/lib/common.sh" 2>/dev/null
source "$ROOT/api/v1/lib/alerts.sh"
set +o noglob
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:0:400}"; ((fail++)); fi; }
printf -v TODAY '%(%Y-%m-%d)T' -1; L="$RUN/jq-errors/$TODAY.log"
line(){ # <classe> <origem> <rota> [n]
  local i; for ((i = 0; i < ${4:-1}; i++)); do
    printf '%s\t5\t%s\t%s\t%s outro.sh:1:main\targ:x=3B\t.a\n' "$EPOCHSECONDS" "$1" "$3" "$2" >> "$L"; done; }
msg(){ cat "$RUN"/alerts/outbox/*-jq_errors-*.txt 2>/dev/null; }
clear_out(){ rm -f "$RUN"/alerts/outbox/*; }

echo "== erro novo avisa, com total e origens =="
line execucao status.sh:65:_reg_slow /index/status 5; line uso config.sh:21:source /contest/admin/config 2
line argv-convertido contest-create.sh:481:cc_create /treino/contest-create/create 3
alerts_evaluate; DBG="$(msg)"
ck "um aviso com o total (7; a conversão não conta)"     '[[ "$DBG" == *"<b>7</b> erro(s) de jq"* && "$(ls "$RUN"/alerts/outbox/*-jq_errors-* | wc -l)" == 1 ]]'
ck "…a origem mais frequente primeiro, com a rota"       '[[ "$DBG" == *"<code>execucao</code> em <code>status.sh:65:_reg_slow</code> (<code>/index/status</code>) ×5"* ]]'
ck "…e a segunda"                                         '[[ "$DBG" == *"<code>uso</code> em <code>config.sh:21:source</code> (<code>/contest/admin/config</code>) ×2"* ]]'
ck "…e onde está o log"                                   '[[ "$DBG" == *"run/jq-errors/$TODAY.log"* ]]'

echo "== cooldown: não repete, e o do meio sai somado depois =="
clear_out; line execucao judge-warm.sh:46:_jw_each /contest/admin/preflight 4
alerts_evaluate; DBG="$(ls "$RUN/alerts/outbox")"
ck "dentro do cooldown: nenhum aviso"                    '[[ -z "$(msg)" ]]'
ALERT_JQ_COOLDOWN=0 alerts_evaluate; DBG="$(msg)"
ck "passado o cooldown: as 4 do meio, somadas"           '[[ "$DBG" == *"<b>4</b> erro(s) de jq"* && "$DBG" == *"_jw_each"* ]]'
clear_out; ALERT_JQ_COOLDOWN=0 alerts_evaluate; DBG="$(ls "$RUN/alerts/outbox")"
ck "sem linha nova: nada"                                 '[[ -z "$(msg)" ]]'
line argv-convertido contest-create.sh:748:cc_modules_spec /treino/contest-create/export 2
ALERT_JQ_COOLDOWN=0 alerts_evaluate; DBG="$(ls "$RUN/alerts/outbox")"
ck "só conversão de argumento grande: nada"              '[[ -z "$(msg)" ]]'

echo "== virada do dia =="
clear_out; Y="$RUN/jq-errors/2000-01-01.log"; cp "$L" "$Y"; sz="$(stat -c %s "$Y")"
printf '%s %s %s\n' "$Y" "$sz" 0 > "$RUN/alerts/jq-errors.state"
printf '%s\t3\tcompilacao\t/x\tontem.sh:9:f\t\t1 +\n' "$EPOCHSECONDS" >> "$Y"
: > "$L"; line execucao hoje.sh:1:g '/y <z> & w' 1
ALERT_JQ_COOLDOWN=0 alerts_evaluate; DBG="$(msg)"
ck "termina o arquivo de ontem (só o que veio depois do offset) e lê o de hoje" '[[ "$DBG" == *"<b>2</b> erro(s) de jq"* && "$DBG" == *"ontem.sh:9:f"* && "$DBG" == *"hoje.sh:1:g"* ]]'
ck "texto do log escapado (HTML do Telegram)"            '[[ "$DBG" == *"/y &lt;z&gt; &amp; w"* ]]'
ck "o estado passa a apontar o arquivo de hoje"           '[[ "$(cut -d" " -f1 "$RUN/alerts/jq-errors.state")" == "$L" ]]'

echo "== os escapes de HTML do Telegram (bash 5.2: o & cru da substituição vira o casamento) =="
source "$ROOT/api/v1/lib/admin-bulk.sh" 2>/dev/null
DBG="$(_alert_html 'a<b>c&d') | $(ab_html 'x<script>&y')"
ck "_alert_html e ab_html escapam < > & de verdade"    '[[ "$DBG" == "a&lt;b&gt;c&amp;d | x&lt;script&gt;&amp;y" ]]'

echo "== sem o diretório: nada, sem erro =="
rm -rf "$RUN/jq-errors" "$RUN/alerts"; DBG="$(alerts_evaluate 2>&1)"
ck "sem run/jq-errors: nenhum aviso e nenhum erro"       '[[ -z "$DBG" && -z "$(msg)" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
