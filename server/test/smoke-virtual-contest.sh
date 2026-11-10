#!/bin/bash
# VIRTUAL COM CARA DE CONTEST (10/11/2026; relato: "não achei os tempos limites"; decisões do Ribas): o TL por linguagem
# no /treino/virtual/problems, os ARQUIVOS da prova (/docs + /doc: desde a largada, editorial só com a run terminada,
# links externos), os AVISOS e CLARIFICATIONS públicas + notícias no TEMPO RELATIVO (/clarifications + /news-file: o
# servidor corta pelo relógio da run; o que saiu depois do fim só com a run terminada; privada nunca; sem quem
# perguntou) e o FREEZE relativo no feed. A matriz de vazamento das rotas novas mora no smoke-virtual-leak.sh.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_JOBS_SYNC=1 \
       SPOOLDIR="$RUN/spool/submissions" SPOOLDONEDIR="$RUN/spool/submissions-done"
mkdir -p "$SPOOLDIR" "$SPOOLDONEDIR"
NOW="$EPOCHSECONDS"; S0=$((NOW-20000)); E0=$((NOW-10000))     # prova de 10000 s, encerrada

T="$FIX/treino"; mkdir -p "$T/var/jsons"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\nCONTEST_END=%s\n' "$((NOW+86400))" > "$T/conf"
for p in pa pb; do printf '{"id":"col#%s","title":"%s","public":true,"languages":["c","py"],"statement_langs":["pt"]}' "$p" "$p" > "$T/var/jsons/col#$p.json"; done
printf '{"problems":[{"id":"col#pa","owner":"dona","public":true},{"id":"col#pb","owner":"dona","public":true}]}' > "$T/var/problem-owners.json"
for u in ana beto caio x.admin; do fx_user "$T" "$u" s "Nome $u"
  printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino "$u" "$u" "$NOW" > "$SESS/tok-$u"; done

C="$FIX/v1"; mkdir -p "$C/var"
{ printf 'CONTEST_ID=v1\nCONTEST_NAME=%q\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\n' "Prova Um" "$S0" "$E0"
  printf 'CONTEST_MODULES=virtual\nLANGUAGES=%q\nPROBS=( x col/pa Alfa A col#pa x col/pb Beta B col#pb )\n' "c"; } > "$C/conf"
fx_user "$C" t1 s "Time Um"; fx_user "$C" t2 s "Time Dois"; fx_user "$C" v1.admin s "Adm"
printf 'CONTEST=v1\nLOGIN=v1.admin\nUSERFULLNAME=Adm\nLOGINAT=1\n' > "$SESS/tok-adm"
h(){ printf '%s:%s:C:%s:%s:%s\n' "$3" "$2" "$4" "$3" "$5" >> "$C/users/$1/history"; }
h t1 'col#pa' $((S0+600))  'Wrong Answer'       a1; h t1 'col#pa' $((S0+1200)) 'Accepted' a2
h t1 'col#pb' $((S0+3000)) 'Compilation Error'  a3; h t1 'col#pb' $((S0+3600)) 'Accepted' a4
h t2 'col#pa' $((S0+5000)) 'Accepted' b1

call(){ # <tok|-> <rota> <GET|POST> <query> [body]
  local auth=(); [[ "$1" != - ]] && auth=(HTTP_AUTHORIZATION="Bearer tok-$1")
  OUT="$(env "${auth[@]}" PATH_INFO="$2" REQUEST_METHOD="$3" QUERY_STRING="$4" HTTP_ACCEPT_ENCODING="" bash "$ROUTER" <<<"${5:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${OUT:0:300}"; ((fail++)); fi; }
code(){ jq -r '.error.code // empty' <<<"$BODY"; }
st(){ jq -r '.me.state' <<<"$BODY"; }
B64="$(printf 'int main(){return 0;}' | base64 -w0)"
vsub(){ call "$1" /submit POST contest=treino "{\"problem_id\":\"$2\",\"filename\":\"${3:-a.c}\",\"code_b64\":\"$B64\",\"virtual\":\"${4:-v1}\"}"; SID="$(jq -r '.submission_id // empty' <<<"$BODY")"; }
verdict(){ sed -i "s/:Not Answered Yet:\([0-9]*\):$2\$/:$3:\1:$2/" "$T/users/$1/history"; }   # <login> <subid> <veredicto>
# envelhece a run: janela E submissões etiquetadas recuam <s> segundos
# o TL do json público (a mesma fonte do /treino/problem)
for p in pa pb; do jq -c '. + {time_limits:{c:"1",py:"3",default:"1"}, tl_clock:"cpu", wall_tl:8, tl_unified:false}' "$T/var/jsons/col#$p.json" > "$T/var/jsons/x" && mv "$T/var/jsons/x" "$T/var/jsons/col#$p.json"; done
# clarifications: pública respondida aos 1000 s (A) · privada aos 500 · aviso aos 3000 · pública respondida DEPOIS do fim
# · pública sem resposta
mkdir -p "$C/clarifications"
cl(){ printf '%s' "$2" > "$C/clarifications/$1.json"; }
cl c1 "{\"id\":\"c1\",\"time\":$((S0+900)),\"problem\":\"A\",\"login\":\"t1\",\"question\":\"N pode ser 1?\",\"public\":true,\"answer\":\"Sim.\",\"answered_by\":\"juiz\",\"answered_at\":$((S0+1000))}"
cl c2 "{\"id\":\"c2\",\"time\":$((S0+400)),\"problem\":\"B\",\"login\":\"t2\",\"question\":\"SEGREDO privado\",\"public\":false,\"answer\":\"so p/ voce\",\"answered_by\":\"juiz\",\"answered_at\":$((S0+500))}"
cl c3 "{\"id\":\"c3\",\"time\":$((S0+3000)),\"problem\":\"general\",\"login\":\"\",\"question\":\"\",\"public\":true,\"broadcast\":true,\"answer\":\"Aviso: o exemplo 2 do B mudou.\"}"
cl c4 "{\"id\":\"c4\",\"time\":$((S0+9000)),\"problem\":\"B\",\"login\":\"t1\",\"question\":\"Depois?\",\"public\":true,\"answer\":\"Respondida depois do fim.\",\"answered_by\":\"juiz\",\"answered_at\":$((E0+600))}"
cl c5 "{\"id\":\"c5\",\"time\":$((S0+700)),\"problem\":\"A\",\"login\":\"t2\",\"question\":\"Sem resposta\",\"public\":true,\"answer\":\"\",\"answered_by\":\"\",\"answered_at\":0}"
# REVISÃO 10/11/2026: o aviso reeditado vale pelo answered_at (o MAIOR dos dois) · instante ilegível = só no fim
cl c6 "{\"id\":\"c6\",\"time\":$((S0+1500)),\"problem\":\"general\",\"login\":\"\",\"question\":\"\",\"public\":true,\"broadcast\":true,\"answer\":\"Aviso reeditado.\",\"answered_at\":$((S0+3200))}"
cl c7 "{\"id\":\"c7\",\"time\":\"ontem\",\"problem\":\"A\",\"login\":\"t1\",\"question\":\"Lixo?\",\"public\":true,\"answer\":\"Data ilegivel.\",\"answered_at\":\"lixo\"}"
# notícias: antes da prova · aos 2000 s com anexo · depois do fim (com anexo) · aos 1500 s EDITADA aos 3300 s
mkdir -p "$C/news-files/n1" "$C/news-files/n2"; printf 'anexo-n1' > "$C/news-files/n1/folha.txt"; printf 'anexo-n2' > "$C/news-files/n2/fim.txt"
mkdir -p "$C/news-files/n3"; printf 'anexo-n3' > "$C/news-files/n3/ed.txt"
printf '[{"id":"n0","title":"Boas-vindas","text":"leia","date":%s},{"id":"n1","title":"Errata","text":"F","date":%s,"file":{"name":"folha.txt","size":8}},{"id":"n2","title":"Resultado","text":"fim","date":%s,"file":{"name":"fim.txt","size":8}},{"id":"n3","title":"Editada","text":"v2","date":%s,"edited_at":%s,"file":{"name":"ed.txt","size":8}}]' \
  "$((S0-3600))" "$((S0+2000))" "$((E0+100))" "$((S0+1500))" "$((S0+3300))" > "$C/news.json"
# documentos: publicados contest.pt/en, info-sheet.pt, times.pt (SEM pdf), editorial.pt; links do resources.json
mkdir -p "$C/docs"
printf '{"published":["contest.pt","contest.en","info-sheet.pt","times.pt","editorial.pt"]}' > "$C/docs/config.json"
for k in contest.pt contest.en info-sheet.pt editorial.pt; do printf '%%PDF-1.4 %s' "$k" > "$C/docs/$k.uploaded.pdf"; done
printf '%%PDF-1.4 nao publicado' > "$C/docs/contest.es.uploaded.pdf"
printf '[{"label":"Caderno","url":"/api/v1/contest/doc?type=contest","type":"contest","lang":"pt"},{"label":"Site da SBC","url":"https://maratona.sbc.org.br/"},{"label":"interno","url":"/api/v1/contest/news-file?id=n1"}]' > "$C/resources.json"
# freeze preservado pelo Encerrar evento
printf '{"freeze":%s,"cleared_at":%s,"by":"v1.admin"}' "$((S0+8000))" "$E0" > "$C/var/freeze-final.json"
# envelhece a run de <login> em <s> segundos (a janela; não há submissão etiquetada)
agerun(){ local f="$T/users/$1/virtual/v1.json"; jq -c --argjson s "$2" '.start-=$s | .end-=$s' "$f" > "$f.n" && mv "$f.n" "$f"; }

echo "== antes de largar: tudo 403 virtual_not_started =="
for r in clarifications docs news-file doc; do call ana "/treino/virtual/$r" GET "contest=v1&id=n0&type=contest&lang=pt"
  ck "$r antes da largada: 403" '[[ "$(code)" == virtual_not_started ]]'; done

echo "== largou, 2500 s de prova =="
call ana /treino/virtual/run POST "" '{"contest":"v1","action":"start","accept":true}'; agerun ana 2500
call ana /treino/virtual/problems GET contest=v1
ck "problems: TL por linguagem, relógio, parede, TL único" '[[ "$(jq -c ".problems[0] | [.time_limits.c, .time_limits.py, .tl_clock, .wall_tl, .tl_unified]" <<<"$BODY")" == "[\"1\",\"3\",\"cpu\",8,false]" ]]'
call ana /treino/virtual/clarifications GET contest=v1
ck "aos 2500 s: n1 (2000), c1 (1000), n0 (antes = 0), nessa ordem" '[[ "$(jq -r "[.items[] | .id] | join(\",\")" <<<"$BODY")" == "n1,c1,n0" ]]'
ck "…c1 com a letra, a pergunta e a resposta; rel 1000" '[[ "$(jq -c ".items[] | select(.id==\"c1\") | [.kind, .problem, .question, .answer, .rel]" <<<"$BODY")" == "[\"clar\",\"A\",\"N pode ser 1?\",\"Sim.\",1000]" ]]'
ck "…sem login, sem quem respondeu, sem a privada, sem o futuro" '[[ "$BODY" != *t1* && "$BODY" != *juiz* && "$BODY" != *SEGREDO* && "$BODY" != *Aviso* && "$BODY" != *Resultado* && "$BODY" != *"Sem resposta"* ]]'
ck "…e diz o relógio, sem a contagem do que falta" '[[ "$(jq -c "[.elapsed >= 2500 and .elapsed < 2600, .ended]" <<<"$BODY")" == "[true,false]" && "$(jq -r "keys|join(\",\")" <<<"$BODY")" == "contest,elapsed,ended,items,success" ]]'
call ana /treino/virtual/news-file GET "contest=v1&id=n1"
ck "anexo da notícia que já saiu: 200" '[[ "$OUT" == *"Status: 200"* && "$BODY" == anexo-n1 ]]'
call ana /treino/virtual/news-file GET "contest=v1&id=n2"
ck "anexo da notícia depois do fim: 404" '[[ "$OUT" == *"Status: 404"* && "$BODY" != *anexo-n2* ]]'
call ana /treino/virtual/news-file GET "contest=v1&id=../x"; ck "id hostil: 400" '[[ "$(code)" == id_invalid ]]'
call ana /treino/virtual/docs GET contest=v1
ck "docs: caderno (pt,en), ambiente (pt); tempos-limite sem PDF fora; editorial TRANCADO" '[[ "$(jq -c "[.docs[] | [.type, (.langs|join(\"+\")), .locked]]" <<<"$BODY")" == "[[\"contest\",\"pt+en\",false],[\"info-sheet\",\"pt\",false],[\"editorial\",\"\",true]]" ]]'
ck "links com a run RODANDO: nenhum, só links_locked" '[[ "$(jq -c "[.links, .links_locked]" <<<"$BODY")" == "[[],true]" ]]'
call ana /treino/virtual/news-file GET "contest=v1&id=n3"; ck "anexo da notícia EDITADA depois de agora: 404" '[[ "$OUT" == *"Status: 404"* && "$BODY" != *anexo-n3* ]]'
call ana /treino/virtual/doc GET "contest=v1&type=contest&lang=en"; ck "caderno EN: 200 PDF" '[[ "$OUT" == *"Status: 200"* && "$OUT" == *"application/pdf"* && "$BODY" == *contest.en* ]]'
call ana /treino/virtual/doc GET "contest=v1&type=contest&lang=es"; ck "caderno ES NÃO publicado: 404" '[[ "$OUT" == *"Status: 404"* && "$BODY" != *"nao publicado"* ]]'
call ana /treino/virtual/doc GET "contest=v1&type=editorial&lang=pt"; ck "editorial com a run rodando: 404" '[[ "$OUT" == *"Status: 404"* && "$BODY" != *editorial.pt* ]]'
call ana /treino/virtual/doc GET "contest=v1&type=times&lang=pt"; ck "publicado sem PDF: 404" '[[ "$OUT" == *"Status: 404"* ]]'
call ana /treino/virtual/doc GET "contest=v1&type=../conf&lang=pt"; ck "type hostil: 400" '[[ "$(code)" == type_invalid ]]'
call beto /treino/virtual/docs GET contest=v1; ck "outra conta sem run: 403" '[[ "$(code)" == virtual_not_started ]]'

echo "== aos 3500 s o aviso chega =="
agerun ana 1000
call ana /treino/virtual/clarifications GET contest=v1
ck "c3 (aviso aos 3000 s) entra, como notice; c6 pelo answered_at (3200), n3 pelo edited_at (3300)" '[[ "$(jq -r "[.items[] | .id] | join(\",\")" <<<"$BODY")" == "n3,c6,c3,n1,c1,n0" && "$(jq -r ".items[] | select(.id==\"c3\") | .kind" <<<"$BODY")" == notice && "$(jq -r ".items[] | select(.id==\"c6\") | .rel" <<<"$BODY")" == 3200 ]]'
ck "…o instante ilegível (c7) segue de fora" '[[ "$BODY" != *ilegivel* ]]'
call ana /treino/virtual/news-file GET "contest=v1&id=n3"; ck "anexo da editada, agora: 200" '[[ "$BODY" == anexo-n3 ]]'

echo "== terminou: o que saiu depois do fim e o editorial =="
vsub ana 'col#pa'; verdict ana "$SID" 'Accepted'
# a submissão 10 s antes do "encerrar" (a run conta e < end, e o encerrar grava end = agora)
awk -F: -v OFS=: -v id="$SID" '$NF==id{$(NF-1)-=10; $1-=10} 1' "$T/users/ana/history" > "$T/users/ana/history.n" && mv "$T/users/ana/history.n" "$T/users/ana/history"      # encerrar com 0 AC seria desistência (nada a liberar)
call ana /treino/virtual/run POST "" '{"contest":"v1","action":"finish"}'
call ana /treino/virtual/clarifications GET contest=v1
ck "terminada: c4 e n2 (depois do fim) entram; a privada nunca" '[[ "$(jq -r "[.items[] | .id] | sort | join(\",\")" <<<"$BODY")" == "c1,c3,c4,c6,c7,n0,n1,n2,n3" && "$(jq -r .ended <<<"$BODY")" == true && "$BODY" != *SEGREDO* ]]'
ck "…c7 (instante ilegível) sai com rel null e after" '[[ "$(jq -c ".items[] | select(.id==\"c7\") | [.rel, .after]" <<<"$BODY")" == "[null,true]" ]]'
call ana /treino/virtual/news-file GET "contest=v1&id=n2"; ck "anexo de depois do fim: 200" '[[ "$BODY" == anexo-n2 ]]'
call ana /treino/virtual/docs GET contest=v1
ck "links externos: agora sim" '[[ "$(jq -c "[[.links[].url], .links_locked]" <<<"$BODY")" == "[[\"https://maratona.sbc.org.br/\"],false]" ]]'
ck "editorial destrancado" '[[ "$(jq -c ".docs[] | select(.type==\"editorial\") | [.locked, .langs]" <<<"$BODY")" == "[false,[\"pt\"]]" ]]'
call ana /treino/virtual/doc GET "contest=v1&type=editorial&lang=pt"; ck "editorial: 200" '[[ "$OUT" == *"Status: 200"* && "$BODY" == *editorial.pt* ]]'

echo "== tempo esgotado com veredicto PENDENTE (judging): ainda não libera; 0 AC = desistência = nada =="
call beto /treino/virtual/run POST "" '{"contest":"v1","action":"start","accept":true}'; agerun beto 9000
vsub beto 'col#pa'; BS="$SID"; agerun beto 2000          # submissão aos ~9000 s, pendente; o tempo acabou há ~1000 s
awk -F: -v OFS=: -v id="$BS" '$NF==id{$(NF-1)-=2000; $1-=2000} 1' "$T/users/beto/history" > "$T/users/beto/history.n" && mv "$T/users/beto/history.n" "$T/users/beto/history"
call beto /treino/virtual/run GET contest=v1; ck "(a run está em judging)" '[[ "$(st)" == judging ]]'
call beto /treino/virtual/docs GET contest=v1
ck "judging: o editorial segue TRANCADO" '[[ "$(jq -c ".docs[] | select(.type==\"editorial\") | .locked" <<<"$BODY")" == true ]]'
call beto /treino/virtual/clarifications GET contest=v1
ck "judging: a prova inteira (aviso dos 3000 s), mas nada de depois do fim" '[[ "$(jq -r "[.items[] | .id] | sort | join(\",\")" <<<"$BODY")" == "c1,c3,c6,n0,n1,n3" && "$(jq -r .ended <<<"$BODY")" == false ]]'
call beto /treino/virtual/doc GET "contest=v1&type=editorial&lang=pt"; ck "judging: editorial 404" '[[ "$OUT" == *"Status: 404"* ]]'
verdict beto "$BS" 'Wrong Answer'
call beto /treino/virtual/clarifications GET contest=v1; ck "o WA sai: 0 AC = desistida = 403 (pode largar de novo sem ter visto o fim)" '[[ "$(code)" == virtual_not_started ]]'

call caio /treino/virtual/run POST "" '{"contest":"v1","action":"start","accept":true}'; agerun caio 100
call caio /treino/virtual/run POST "" '{"contest":"v1","action":"discard"}'
call caio /treino/virtual/clarifications GET contest=v1; ck "run DESISTIDA não vê nada (pode largar de novo)" '[[ "$(code)" == virtual_not_started ]]'

echo "== feed: o freeze relativo =="
call - /treino/virtual/feed GET contest=v1
ck "freeze_rel = 8000" '[[ "$(jq -r .freeze_rel <<<"$BODY")" == 8000 ]]'
rm -f "$C/var/freeze-final.json"; touch "$C/conf"
call - /treino/virtual/feed GET contest=v1; ck "sem o registro: null" '[[ "$(jq -r .freeze_rel <<<"$BODY")" == null ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
