#!/bin/bash
# FILA DE CALIBRAÇÃO — o que aparece nas telas enquanto um juiz calibra.
#
# A calibração GENÉRICA (`{id}`) vira um update: fica em run/updates/{pending,inprogress} e as três
# telas a mostram do pedido até o fim. A DIRIGIDA (`{id, hosts:[…]}`) vira um COMANDO por host, e o
# comando SOME do diretório ao ser entregue no heartbeat: dali em diante o servidor não sabia mais
# que aquele juiz estava calibrando — Painel sem "calibrando…", `calib_targeted` de volta a 0,
# `moj judges show` dizendo "rodando: nada", por minutos (relato do Ribas, 20/09/2026).
# Agora a entrega deixa um MARCADOR `cmd-<cmdid>.json` em inprogress/<host>/. Ele é DISPLAY-ONLY:
# não serializa, não dedupa, não volta p/ a fila e não é re-carimbado pelo heartbeat.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"
RUN="$(mktemp -d)"; trap 'rm -rf "$RUN"' EXIT
export RUNDIR="$RUN" UPDATESDIR="$RUN/updates" CMDDIR="$RUN/commands" REGISTRYDIR="$RUN/registry"
mkdir -p "$UPDATESDIR/pending" "$UPDATESDIR/inprogress" "$CMDDIR" "$REGISTRYDIR"
source "$ROOT/judge-gw/sched-lib.sh" 2>/dev/null
source "$ROOT/api/v1/lib/problems.sh" 2>/dev/null   # calibrating_set (o que o Painel lista)

pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-}"; ((fail++)); fi; }
mark_count(){ find "$UPDATESDIR/inprogress" -mindepth 2 -name 'cmd-*.json' 2>/dev/null | wc -l; }
# juiz vivo p/ o upd_reconcile (reg_live_hosts lê o registry)
live_host(){ printf '{"host":"%s","last_seen":%s,"langs":[],"free_slots":1,"total_slots":1}\n' "$1" "$EPOCHSECONDS" > "$REGISTRYDIR/$1.json"; }
live_host juiz1

echo "== comando DIRIGIDO: antes de entregar já aparece (era o único instante visível) =="
cid="$(cmd_request juiz1 calibrate autor 'col#pa')"
ck "cmd_request devolve cmdid"        '[[ "$cid" =~ ^[0-9a-f]{12}$ ]]'
ck "contador de dirigidas = 1"        '[[ "$(cmd_action_count calibrate)" == 1 ]]'
DBG="$(calibrating_set)"; ck "Painel lista o problema"  '[[ "$(calibrating_set)" == *"col#pa"* ]]'

echo "== ENTREGA (heartbeat): o comando some, o MARCADOR fica =="
out="$(cmd_claim juiz1)"
ck "o juiz recebeu o comando"         '[[ "$(jq -r .action <<<"$out")" == calibrate && "$(jq -r .id <<<"$out")" == "col#pa" ]]'
ck "fila de dirigidas esvaziou"       '[[ "$(cmd_action_count calibrate)" == 0 ]]'
ck "marcador criado"                  '[[ "$(mark_count)" == 1 ]]'
DBG="$(calibrating_set)"; ck "Painel CONTINUA listando (era aqui que sumia)" '[[ "$(calibrating_set)" == *"col#pa"* ]]'
ck "contador de em-execução conta"    '[[ "$(upd_inprogress_kind_count calibrate)" == 1 ]]'
ck "marcador tem o formato de update" '[[ "$(jq -r ".kind" "$(find "$UPDATESDIR/inprogress" -name "cmd-*.json"|head -1)")" == calibrate \
                                          && "$(jq -r ".target" "$(find "$UPDATESDIR/inprogress" -name "cmd-*.json"|head -1)")" == "col#pa" \
                                          && "$(jq -r ".claimed_at" "$(find "$UPDATESDIR/inprogress" -name "cmd-*.json"|head -1)")" =~ ^[0-9]+$ ]]'

echo "== é DISPLAY-ONLY: não dedupa nem serializa o caminho genérico =="
ck "cal_request NÃO responde 'já existe'" '[[ -z "$(upd_find_calibrate "col#pa")" ]]'
r="$(cal_request col 'col#pa' autor)"
ck "genérica p/ o mesmo problema é criada" '[[ -n "$r" && "$(upd_pending_kind_count calibrate)" == 1 ]]'
got="$(upd_claim juiz1)"
ck "e É reivindicável (marcador não trava)" '[[ "$(jq -r ".target" <<<"$got")" == "col#pa" ]]'
upd_done juiz1 "$r"

echo "== o heartbeat NÃO rejuvenesce o marcador (órfão tem de poder morrer) =="
mf="$(find "$UPDATESDIR/inprogress" -name 'cmd-*.json' | head -1)"
touch -d '@1000000000' "$mf"; upd_touch_host juiz1
ck "mtime do marcador intacto"        '[[ "$(stat -c %Y "$mf")" == 1000000000 ]]'

echo "== vencido, o marcador É APAGADO (nunca volta p/ pending como fantasma) =="
rm -f "$UPDATESDIR/.reconcile-stamp"; upd_reconcile
ck "marcador sumiu"                   '[[ "$(mark_count)" == 0 ]]'
ck "e NÃO virou calibração pendente"  '[[ "$(upd_pending_kind_count calibrate)" == 0 ]]'

echo "== caso feliz: o juiz reporta -> o marcador sai na hora =="
cid2="$(cmd_request juiz1 calibrate autor 'col#pb')"; cmd_claim juiz1 >/dev/null
ck "marcador do pb criado"            '[[ "$(mark_count)" == 1 ]]'
upd_cmd_clear juiz1 'col#outro'
ck "outro problema não apaga o meu"   '[[ "$(mark_count)" == 1 ]]'
upd_cmd_clear juiz1 'col#pb'
ck "reportou: marcador removido"      '[[ "$(mark_count)" == 0 ]]'
DBG="$(calibrating_set)"; ck "Painel vazio de novo" '[[ "$(calibrating_set)" == "[]" ]]'

echo "== comando que NÃO é calibrate (clearcache) não deixa marcador =="
cmd_request juiz1 clearcache autor >/dev/null; cmd_claim juiz1 >/dev/null
ck "sem marcador"                     '[[ "$(mark_count)" == 0 ]]'

echo "== calibrating_for: o DETALHE que a tela do autor mostra (onde e desde quando) =="
rm -rf "$UPDATESDIR/pending" "$UPDATESDIR/inprogress" "$CMDDIR"; mkdir -p "$UPDATESDIR/pending" "$UPDATESDIR/inprogress" "$CMDDIR"
source "$ROOT/api/v1/lib/problems.sh" 2>/dev/null
ck "nada em voo => []"                 '[[ "$(calibrating_for "col#pa")" == "[]" ]]'
r="$(cal_request col "col#pa" autor)"
DBG="$(calibrating_for "col#pa")"
ck "pendente aparece como queued"      '[[ "$(jq -r ".[0].state" <<<"$(calibrating_for "col#pa")")" == queued ]]'
ck "pendente ainda não tem host"       '[[ "$(jq -r ".[0].host" <<<"$(calibrating_for "col#pa")")" == "" ]]'
upd_claim juiz1 >/dev/null
ck "reivindicada: host + running"      '[[ "$(jq -r ".[0].host" <<<"$(calibrating_for "col#pa")")" == juiz1                                           && "$(jq -r ".[0].state" <<<"$(calibrating_for "col#pa")")" == running ]]'
ck "o campo since é epoch"                 '[[ "$(jq -r ".[0].since" <<<"$(calibrating_for "col#pa")")" =~ ^[0-9]{9,} ]]'
ck "outro problema não aparece"        '[[ "$(calibrating_for "col#outro")" == "[]" ]]'
upd_done juiz1 "$r"
ck "terminou => []"                    '[[ "$(calibrating_for "col#pa")" == "[]" ]]'
# a DIRIGIDA entra pelo marcador (o comando some do diretório quando é entregue)
cid3="$(cmd_request juiz1 calibrate autor 'col#pa')"
ck "dirigida na fila aparece"          '[[ "$(jq -r ".[0].host" <<<"$(calibrating_for "col#pa")")" == juiz1 ]]'
cmd_claim juiz1 >/dev/null
ck "dirigida ENTREGUE continua visível" '[[ "$(jq -r ".[0].state" <<<"$(calibrating_for "col#pa")")" == running ]]'
upd_cmd_clear juiz1 'col#pa'
ck "reportou => []"                    '[[ "$(calibrating_for "col#pa")" == "[]" ]]'

echo "== dedup: contra o PENDENTE sim; contra o que JÁ RODA, não =="
rm -rf "$UPDATESDIR/pending" "$UPDATESDIR/inprogress"; mkdir -p "$UPDATESDIR/pending" "$UPDATESDIR/inprogress"
a="$(cal_request col "col#pa" autor)"
b="$(cal_request col "col#pa" autor)"
ck "2 cliques seguidos = 1 job"        '[[ "$a" == "$b" && "$(upd_pending_kind_count calibrate)" == 1 ]]'
upd_claim juiz1 >/dev/null              # agora está EM EXECUÇÃO (pegou a versão de então)
ck "fila vazia, 1 em execução"         '[[ "$(upd_pending_kind_count calibrate)" == 0 && "$(upd_inprogress_kind_count calibrate)" == 1 ]]'
c="$(cal_request col "col#pa" autor)"   # o autor salvou de novo e pediu outra
ck "pedido novo ENTRA (versão nova)"   '[[ "$c" != "$a" && "$(upd_pending_kind_count calibrate)" == 1 ]]'
d="$(cal_request col "col#pa" autor)"
ck "e o clique seguinte dedupa"        '[[ "$d" == "$c" && "$(upd_pending_kind_count calibrate)" == 1 ]]'

echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
