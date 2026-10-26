#!/bin/bash
# smoke-problem-state.sh — o estado de RUNTIME de um problema no delete e no move (26/10/2026).
# Antes: o delete deixava run/tl/<id>.{json,cks,pkv}, a chave do id nos sumários de TL e de validação, o
# run/calib/<id>/ e as calibrações na fila; o move deixava o `.id` de DENTRO dos jsons movidos com o id antigo (o
# rebuild a frio dos sumários voltava a chavear o problema pelo id velho), os memos e as chaves velhas, e o sumário
# das soluções nunca nascia no id novo. E o bin/problem-state-sweep.sh conserta o que já ficou órfão.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS"' EXIT
source "$HERE/fixture.sh"
: "${MOJTOOLS_DIR:=$(cd "$ROOT/../../mojtools" 2>/dev/null && pwd)}"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$PROBS" TL_STORE_DIR="$RUN/tl" \
       CALIB_DIR="$RUN/calib" CALX_SUM_DIR="$RUN/calib-sum" CAL_SUMMARY="$RUN/calib-summary.json" \
       UPDATESDIR="$RUN/updates" CMDDIR="$RUN/commands" MOJTOOLS_DIR MOJ_JOBS_SYNC=1
mkdir -p "$RUN/tl" "$RUN/calib" "$FIX/treino/var"
NOW="$EPOCHSECONDS"; T="$FIX/treino"
printf 'CONTEST_ID=treino\nCONTEST_END=%s\n' "$((NOW+86400))" > "$T/conf"
echo '{"col":{"members":["autor"],"admins":["autor"],"public_allowed":true,"title":"Col"},
       "dst":{"members":["autor"],"admins":["autor"],"public_allowed":false,"title":"Dst"}}' > "$T/var/orgs.json"
mkpkg(){ local P="$PROBS/col/$1"; mkdir -p "$P/sols/good" "$P/tests/input" "$P/docs"
  printf 'x\n' > "$P/docs/enunciado.md"; printf 'int main(){}\n' > "$P/sols/good/sol.c"; printf '1\n' > "$P/tests/input/t1"
  printf '{"owner":"autor","public":false,"display_title":"%s"}\n' "$1" > "$P/.moj-meta.json"; : > "$P/conf"
  ( cd "$P" && git init -q && git add -A && git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm init ); }
mkpkg pa; mkpkg pb
jq -cn '{problems:[{id:"col#pa",owner:"autor",repo:"col",prob:"pa",title:"pa",public:false,collaborators:[],collections:[]},
                   {id:"col#pb",owner:"autor",repo:"col",prob:"pb",title:"pb",public:false,collaborators:[],collections:[]}]}' \
  > "$T/var/problem-owners.json"
fx_user "$T" autor s autor
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino autor autor "$NOW" > "$SESS/tk-autor"
source "$ROOT/api/v1/lib/common.sh" 2>/dev/null; source "$ROOT/api/v1/lib/tl-store.sh"; source "$ROOT/api/v1/lib/calib-expect.sh"
source "$ROOT/judge-gw/sched-lib.sh"

pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-${BODY:0:300}}"; ((fail++)); fi; }
req(){ OUT="$(PATH_INFO="$2" REQUEST_METHOD="$1" QUERY_STRING="${4:-}" HTTP_AUTHORIZATION="Bearer tk-$3" bash "$ROUTER" <<<"${5:-}" 2>/dev/null)"
  STATUS="$(printf '%s' "$OUT" | sed -n 's/^Status: \([0-9]*\).*/\1/p' | head -1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; DBG=""; }
# todo o estado de runtime de um id: store de TL (+memos), validação, calibração por host + sumário, sumários
# agregados, carimbo fresco e calibrações na fila (pendente, dirigida, marcador em execução)
seed(){ local id="$1"
  tl_store_record juiz1 "$id" abcdef12 '{"c":"0.3","default":"0.3"}' "" '{"c":"1","default":"1"}' moj >/dev/null
  : > "$TL_STORE_DIR/$id.cks"; : > "$TL_STORE_DIR/$id.pkv"
  mkdir -p "$VAL_STORE_DIR"; jq -cn --arg id "$id" '{id:$id, ok:true, at:1}' > "$VAL_STORE_DIR/$id.json"; val_summary_upsert "$id"
  mkdir -p "$CALIB_DIR/$id/r/juiz1"; echo '<html>' > "$CALIB_DIR/$id/r/juiz1/good-sol.c.html"
  jq -cn '{host:"juiz1", checksum:"", sols:[{file:"sol.c",lang:"c",category:"good",verdict:"Accepted,100p",tests:[{name:"t1",code:"AC",time:0.1,tl:5}]}]}' \
    > "$CALIB_DIR/$id/juiz1.json"
  calx_summary_write "$id"
  tl_fresh_set "$id" abcdef12
  cal_request col "$id" autor >/dev/null
  cmd_request juiz2 calibrate autor "$id" >/dev/null
  upd_cmd_mark juiz3 "$id" deadbeef autor
}
queued(){ { find "$UPDATESDIR/pending" "$UPDATESDIR/inprogress" -name '*.json' -exec cat {} + 2>/dev/null
            find "$CMDDIR" -mindepth 2 -name '*.json' -exec cat {} + 2>/dev/null; } \
          | jq -r --arg t "$1" 'select((.target // .id) == $t) | (.kind // .action)' 2>/dev/null | wc -l; }

echo "== delete: nada do id fica para trás =="
seed "col#pb"
ck "estado semeado (sanidade)"                   '[[ -s "$TL_STORE_DIR/col#pb.json" && -d "$CALIB_DIR/col#pb" && -s "$(calx_summary_file "col#pb")" && "$(queued "col#pb")" == 3 ]]'
req POST /problems/delete autor "" '{"id":"col#pb","confirm":"col#pb"}'
ck "delete 200"                                  '[[ "$STATUS" == 200 ]]'
ck "run/tl: json, .cks e .pkv apagados"          '[[ ! -e "$TL_STORE_DIR/col#pb.json" && ! -e "$TL_STORE_DIR/col#pb.cks" && ! -e "$TL_STORE_DIR/col#pb.pkv" ]]'
ck "fora do sumário de TL e do de validação"     '[[ "$(jq -r "has(\"col#pb\")" "$TL_SUMMARY")" == false && "$(jq -r "has(\"col#pb\")" "$VAL_SUMMARY")" == false && ! -e "$VAL_STORE_DIR/col#pb.json" ]]'
ck "run/calib/<id> e o sumário das soluções"    '[[ ! -e "$CALIB_DIR/col#pb" && ! -e "$(calx_summary_file "col#pb")" && "$(jq -r "has(\"col#pb\")" "$CAL_SUMMARY")" == false ]]'
ck "carimbo fresco sem o id"                     '[[ "$(jq -r "has(\"col#pb\")" "$(tl_fresh_file)" 2>/dev/null || echo false)" == false ]]'
ck "nenhuma calibração do id na fila"            '[[ "$(queued "col#pb")" == 0 ]]'

echo "== move: o estado segue o problema, com o .id de dentro reescrito =="
seed "col#pa"
req POST /problems/move autor "" '{"id":"col#pa","to_org":"dst"}'
ck "move 200"                                    '[[ "$STATUS" == 200 ]]'
ck "store de TL no id novo, com .id novo"       '[[ "$(jq -r .id "$TL_STORE_DIR/dst#pa.json")" == "dst#pa" && ! -e "$TL_STORE_DIR/col#pa.json" ]]'
ck "memos .cks/.pkv do id antigo saíram"         '[[ ! -e "$TL_STORE_DIR/col#pa.cks" && ! -e "$TL_STORE_DIR/col#pa.pkv" ]]'
ck "sumário de TL re-chaveado"                   '[[ "$(jq -c "[has(\"col#pa\"), has(\"dst#pa\")]" "$TL_SUMMARY")" == "[false,true]" ]]'
ck "validação no id novo, com .id novo"          '[[ "$(jq -r .id "$VAL_STORE_DIR/dst#pa.json")" == "dst#pa" && "$(jq -c "[has(\"col#pa\"), has(\"dst#pa\")]" "$VAL_SUMMARY")" == "[false,true]" ]]'
ck "calibração por host movida e o sumário das soluções REFEITO no id novo" '[[ -s "$CALIB_DIR/dst#pa/juiz1.json" && ! -e "$CALIB_DIR/col#pa" && -s "$(calx_summary_file "dst#pa")" && ! -e "$(calx_summary_file "col#pa")" && "$(jq -c "[has(\"col#pa\"), has(\"dst#pa\")]" "$CAL_SUMMARY")" == "[false,true]" ]]'
ck "a fila: nada no id antigo, uma calibração pedida no novo" '[[ "$(queued "col#pa")" == 0 && "$(queued "dst#pa")" == 1 ]]'
rm -f "$TL_SUMMARY"; tl_summary_ensure
ck "rebuild a frio do sumário chaveia pelo id NOVO" '[[ "$(jq -c "[has(\"col#pa\"), has(\"dst#pa\")]" "$TL_SUMMARY")" == "[false,true]" ]]'

echo "== bin/problem-state-sweep.sh: o órfão de antes e o .id errado do move antigo =="
mkdir -p "$CALIB_DIR/col#zz"; echo '{}' > "$CALIB_DIR/col#zz/juiz1.json"
jq -cn '{id:"col#zz", checksum:"x", hosts:{}}' > "$TL_STORE_DIR/col#zz.json"; tl_summary_upsert "col#zz"
jq -c '.id = "col#pa"' "$TL_STORE_DIR/dst#pa.json" > "$RUN/x" && mv "$RUN/x" "$TL_STORE_DIR/dst#pa.json"
out="$(bash "$ROOT/bin/problem-state-sweep.sh" 2>/dev/null)"; DBG="$out"
ck "dry-run acusa o órfão e o .id errado"        'grep -qP "^orfao\tcol#zz\t" <<<"$out" && grep -qP "^id-errado\tdst#pa\t" <<<"$out"'
ck "dry-run não mexe"                            '[[ -e "$TL_STORE_DIR/col#zz.json" && -d "$CALIB_DIR/col#zz" ]]'
bash "$ROOT/bin/problem-state-sweep.sh" --apply >/dev/null 2>&1
ck "apply: o órfão some (store, calib, sumário)" '[[ ! -e "$TL_STORE_DIR/col#zz.json" && ! -e "$CALIB_DIR/col#zz" && "$(jq -r "has(\"col#zz\")" "$TL_SUMMARY")" == false ]]'
ck "apply: o .id reescrito; o problema vivo fica" '[[ "$(jq -r .id "$TL_STORE_DIR/dst#pa.json")" == "dst#pa" && -d "$CALIB_DIR/dst#pa" ]]'
out="$(bash "$ROOT/bin/problem-state-sweep.sh" 2>&1 >/dev/null)"; DBG="$out"
ck "2ª rodada: nada a fazer"                     'grep -q "0 órfão(s) · 0 .id errado(s)" <<<"$out"'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
