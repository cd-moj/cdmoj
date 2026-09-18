#!/bin/bash
# smoke-virtual-board.gjs.sh — DIFERENCIAL do motor do placar virtual (web/shared/virtual-board.js).
# O motor reconstrói o placar no CLIENTE a partir do feed de runs; a regra ICPC mora no servidor
# (metrics_recompute + updatescore-icpc.sh). São duas implementações — o que impede a divergência é
# isto: para o MESMO contest,
#   motor(feed, t=∞)  ==  var/placar.txt               (resultado final)
#   motor(feed, t=T)  ==  placar de uma CÓPIA do contest com o history truncado em T
# linha a linha: ordem (chaves), células (tentativas/minuto/segundo/★), total, penalidade, último AC,
# posição (ranking de competição) e convidado. Fixture com CE não-penalizante, empate, convidado,
# AC duplicado, tentativa DEPOIS do AC e ★ retida por pendente mais antigo.
# E: linha VIRTUAL entra intercalada, não consome posição e ganha a posição que ocuparia.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
command -v gjs >/dev/null 2>&1 || { echo "virtual-board: gjs ausente — pulando"; exit 0; }
FIX="$(mktemp -d)"; RUN="$(mktemp -d)"; W="$(mktemp -d)"; trap 'rm -rf "$FIX" "$RUN" "$W"' EXIT
export CONTESTSDIR="$FIX" RUNDIR="$RUN" SESSIONDIR="$RUN/s"; mkdir -p "$RUN/s"
NOW="$EPOCHSECONDS"; S0=$((NOW-30000)); E0=$((NOW-12000))
T="$FIX/treino"; mkdir -p "$T/var/jsons"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nCONTEST_END=%s\n' "$((NOW+86400))" > "$T/conf"
for p in a b c; do printf '{"id":"org#%s","public":true}' "$p" > "$T/var/jsons/org#$p.json"; done

mkc(){ # <cid> <corte-epoch>
  local C="$FIX/$1" cut="$2"; mkdir -p "$C/var"
  { printf 'CONTEST_ID=%s\nCONTEST_NAME=Dif\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nCONTEST_MODULES=virtual\n' "$1" "$S0" "$E0"
    printf 'PROBS=( x org/a Alfa A org#a x org/b Beta B org#b x org/c Gama C org#c )\n'; } > "$C/conf"
  printf '{"version":1,"cohorts":[{"id":"oficial","name":"Oficiais","default":true,"public":true},{"id":"conv","name":"Conv","regex":"^conv","public":true,"unranked":true,"ranking":true}]}' > "$C/cohorts.json"
  mk(){ local u="$C/users/$1"; mkdir -p "$u"; jq -cn --arg l "$1" --arg n "$2" '{login:$l,password:"x",fullname:$n,status:"active",team:{univ_short:"UNB",flag:"br"}}' > "$u/account.json"; : > "$u/history"; }
  s(){ (( S0 + $4 <= cut )) || return 0; printf '%s:%s:C:%s:%s:%s\n' "$((S0+$4))" "$2" "$3" "$((S0+$4))" "$5" >> "$C/users/$1/history"; }
  mk t1 "Um"; mk t2 "Dois"; mk t3 "Tres"; mk t4 "Quatro"; mk t5 "Zero"; mk conv1 "Convidado"; mk "$1.admin" Adm
  s t1 'org#a' 'Wrong Answer' 300 1;  s t1 'org#a' 'Compilation Error' 400 2; s t1 'org#a' 'Accepted' 1210 3
  s t1 'org#a' 'Wrong Answer' 1500 4                                   # tentativa DEPOIS do AC: não conta
  s t1 'org#b' 'Time Limit Exceeded' 2000 5; s t1 'org#b' 'Accepted' 5000 6
  s t2 'org#a' 'Accepted' 900 7;  s t2 'org#a' 'Accepted' 900 8        # AC duplicado no mesmo segundo
  s t2 'org#b' 'Accepted' 7000 9
  s t3 'org#a' 'Accepted' 2400 10                                      # t3 e t4 EMPATAM (1 problema, min 40)
  s t4 'org#b' 'Accepted' 2430 11
  s t4 'org#c' 'Not Answered Yet' 100 12                               # pendente ANTIGO em C…
  s conv1 'org#c' 'Accepted' 600 13; s conv1 'org#a' 'Accepted' 800 14 # …segura a ★ do C; convidado tem a ★ do A
  s t5 'org#c' 'Runtime Error' 9000 15;  s t5 'org#c' 'Judge Error' 9100 16
}
mkc dfull "$E0"; mkc dmid "$((S0+2420))"
bash "$ROOT/score/build.sh" dmid >/dev/null 2>&1
OUT="$(PATH_INFO=/treino/virtual/feed REQUEST_METHOD=GET QUERY_STRING=contest=dfull bash "$ROUTER" 2>/dev/null)"
printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}' > "$W/feed.json"
jq -e '.success == true' "$W/feed.json" >/dev/null 2>&1 || { echo "FALHOU: feed não veio :: ${OUT:0:200}"; exit 1; }

{ printf 'const FEED = %s;\n' "$(cat "$W/feed.json")"
  printf 'const TXT_FULL = %s;\nconst TXT_MID = %s;\n' "$(jq -Rs . "$FIX/dfull/var/placar.txt")" "$(jq -Rs . "$FIX/dmid/var/placar.txt")"
  sed -e 's/^export //' "$ROOT/../web/shared/virtual-board.js"
  cat <<'JS'
function parseTxt(txt) {                      // leitor mínimo do TXT `icpc s [g]`, colunas PELO NOME
  const L = txt.split('\n').filter(Boolean); const hdr = L[1].split(':').filter((x) => !/^(desc|asc)$/.test(x));
  const ix = (n) => hdr.indexOf(n); const sys = ['flag','username','univ short','team name','univ full','Total','Penalty','LastAC','guest'];
  const probs = hdr.filter((h) => !sys.includes(h));
  return L.slice(2).map((ln) => { const v = ln.split(':'); const o = { u: v[ix('username')], total: v[ix('Total')], pen: v[ix('Penalty')], last: v[ix('LastAC')], guest: ix('guest') >= 0 && v[ix('guest')] === '1', name: v[ix('team name')], flag: v[ix('flag')], cells: {} };
    probs.forEach((p) => { o.cells[p] = v[ix(p)] || ''; }); return o; });
}
function cmp(label, txt, t) {
  const want = parseTxt(txt); const idx = indexFeed(FEED); const got = boardAt(FEED, idx, [], t).teams;
  let bad = [];
  if (want.length !== got.length) bad.push('nº de linhas ' + got.length + ' != ' + want.length);
  const key = (o) => o.total + '|' + (o.pen !== undefined ? o.pen : o.penalty) + '|' + (o.last !== undefined ? o.last : o.lastac);
  if (want.map(key).join(' ') !== got.map(key).join(' ')) bad.push('sequência de chaves: ' + got.map(key).join(' ') + ' != ' + want.map(key).join(' '));
  const G = Object.fromEntries(got.map((g) => [g.username, g]));
  // posição esperada: ranking de competição sobre o TXT, convidado não consome
  let seen = 0, prev = null; want.forEach((w) => { if (w.guest) { w.place = null; return; } seen++; w.place = (prev && key(prev) === key(w)) ? prev.place : seen; prev = w; });
  for (const w of want) { const g = G[w.u]; if (!g) { bad.push('falta ' + w.u); continue; }
    if (g.guest !== w.guest) bad.push(w.u + ' guest');
    if (g.place !== w.place) bad.push(w.u + ' place ' + g.place + ' != ' + w.place);
    if (g.teamName !== w.name || g.flag !== w.flag) bad.push(w.u + ' identidade');
    for (const p of Object.keys(w.cells)) { const m = /^(\d+)\/(\d+)(\*?)$/.exec(w.cells[p]);
      const exp = m ? (m[1] + '/' + Math.floor(Number(m[2]) / 60) + m[3]) : w.cells[p];
      if (g.probs[p] !== exp) bad.push(w.u + ' ' + p + ' "' + g.probs[p] + '" != "' + exp + '"');
      if (m && g.probSecs[p] !== Number(m[2])) bad.push(w.u + ' ' + p + ' seg'); } }
  print(label + '=' + (bad.length ? 'DIFF ' + bad.join('; ') : 'ok'));
}
cmp('final', TXT_FULL, Infinity);
cmp('final_dur', TXT_FULL, FEED.duration);
cmp('mid', TXT_MID, 2420);
// linha VIRTUAL: 2 problemas em 30 e 50 min, 1 erro => 2/100: entre t2 (2/131… ) — confere a posição que OCUPARIA
const idx = indexFeed(FEED);
const V = [{ login: 'ana', name: 'Ana', runs: [[1000, 0, 'N'], [1800, 0, 'Y'], [3000, 1, 'Y']], you: true }];
const b = boardAt(FEED, idx, V, Infinity); const me = myRow(b);
const off = b.teams.filter((x) => !x.guest).map((x) => x.username + '#' + x.place).join(',');
const off0 = boardAt(FEED, idx, [], Infinity).teams.filter((x) => !x.guest).map((x) => x.username + '#' + x.place).join(',');
print('virt_row=' + (me && me.username === '#ana' && me.virtual && me.guest && me.place === null ? 'ok' : 'bad'));
print('virt_pen=' + (me ? me.total + '/' + me.penalty : '?'));
print('virt_noconsume=' + (off === off0 ? 'ok' : 'bad'));
const ahead = b.teams.filter((x) => !x.guest && (Number(x.total) > 2 || (Number(x.total) === 2 && Number(x.penalty) < 100))).length;
print('virt_gplace=' + (me.gplace === ahead + 1 ? 'ok' : 'bad ' + me.gplace + ' != ' + (ahead + 1)));
print('virt_nostar=' + (Object.values(me.probs).some((c) => /\*$/.test(c)) ? 'bad' : 'ok'));
const early = boardAt(FEED, idx, V, 1700); const me2 = myRow(early);
print('virt_t1700=' + (me2.total === '0' && me2.probs.A === '1/-' ? 'ok' : 'bad ' + me2.total + ' ' + me2.probs.A));
print('upto=' + runsUpTo(idx, 900) + ',' + runsUpTo(idx, -1) + ',' + (runsUpTo(idx, 1e9) === FEED.runs.length));
JS
} > "$W/t.js"
out="$(gjs "$W/t.js" 2>&1)" || { echo "$out" >&2; echo "virtual-board: gjs falhou"; exit 1; }
PASS=0; FAIL=0
kv(){ sed -n "s/^$1=//p" <<<"$out" | head -1; }
check(){ if [[ "$(kv "$1")" == "$2" ]]; then PASS=$((PASS+1)); echo "  ok: $3"; else FAIL=$((FAIL+1)); echo "  FALHOU: $3 (got '$(kv "$1")', want '$2')"; fi; }
check final ok          "motor(t=∞) == placar.txt final"
check final_dur ok      "motor(t=duração) == placar.txt final"
check mid ok            "motor(t=2420 s) == placar de history truncado"
check virt_row ok       "linha virtual: guest+virtual, sem posição oficial"
check virt_pen "2/100"  "penalidade da virtual (30 + 50 + 20)"
check virt_noconsume ok "virtual NÃO desloca a numeração oficial"
check virt_gplace ok    "virtual ganha a posição que OCUPARIA"
check virt_nostar ok    "virtual nunca leva ★"
check virt_t1700 ok     "no minuto 28 a virtual ainda não resolveu (1/-)"
check upto "7,0,true"   "runsUpTo (busca binária: 7 runs até o segundo 900)"
grep -q "★\|\*" "$FIX/dfull/var/placar.txt" && echo "  (fixture tem ★ no TXT: $(grep -o '[0-9]*/[0-9]*\*' "$FIX/dfull/var/placar.txt" | tr '\n' ' '))"
echo "RESULT: $PASS passed, $FAIL failed"; (( FAIL == 0 ))
