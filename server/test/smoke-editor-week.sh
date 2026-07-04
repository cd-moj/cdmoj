#!/bin/bash
# Item 2: submit grava o editor por submissão (web vs editor declarado) em var/editor-log;
# /index/open_training agrega "most_used_editor_prev_week" na janela da semana passada
# (só submissões ACEITAS, casadas por subid).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; SPOOL="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$SPOOL"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
T="$FIX/treino"; mkdir -p "$T/var"
printf 'CONTEST_ID=treino\nUSER_STORE=v2\n' > "$T/conf"
fx_user "$T" ribas x "Ribas"
fx_user "$T" alice x "Alice"
jq '.favorite_editor="vim"' "$T/users/ribas/account.json" > "$T/users/ribas/account.json.n" && mv "$T/users/ribas/account.json.n" "$T/users/ribas/account.json"
printf 'CONTEST=treino\nLOGIN=ribas\nLOGINAT=1\n' > "$SESS/tok"

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-tok}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SPOOLDIR="$SPOOL" bash "$ROUTER" <<<"${3:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:160}"; ((fail++)); fi; }

echo "== submit grava editor-log (web / arquivo->declarado / heurística) =="
call /submit POST '{"problem_id":"p1","filename":"solution.c","code_b64":"YWJj","source":"web"}' tok 'contest=treino'
ck "submit 200" '[[ "$OUT" == *"Status: 200"* ]]'
call /submit POST '{"problem_id":"p1","filename":"ac.c","code_b64":"YWJj","source":"file"}' tok 'contest=treino'
call /submit POST '{"problem_id":"p1","filename":"solution.py","code_b64":"YWJj"}' tok 'contest=treino'
ck "editor-log com 3 linhas" '[[ "$(wc -l < "$T/var/editor-log")" == 3 ]]'
ck "editores = web,vim,web" '[[ "$(awk -F: "{print \$4}" "$T/var/editor-log" | paste -sd,)" == "web,vim,web" ]]'

echo "== open_training: most_used_editor_prev_week =="
LW=$(date -d 'last-sunday' +%s); PREV=$((LW-3*86400)); THIS=$((LW+3600))
{ printf '10:p#a:C:Accepted,100p:%s:s1\n' "$PREV"
  printf '10:p#b:PY:Accepted,100p:%s:s3\n' "$PREV"; } > "$T/users/alice/history"
{ printf '10:p#a:C:Accepted,100p:%s:s2\n' "$PREV"
  printf '10:p#c:C:Accepted,100p:%s:s4\n' "$THIS"; } >> "$T/users/ribas/history"   # s4 = esta semana
{ printf '%s:s1:alice:web\n' "$PREV"; printf '%s:s2:ribas:vim\n' "$PREV"
  printf '%s:s3:alice:web\n' "$PREV"; printf '%s:s4:ribas:vscode\n' "$THIS"; } > "$T/var/editor-log"
call /index/open_training GET '' '' ''
ck "tem o campo most_used_editor_prev_week" '[[ "$(jq -r "has(\"most_used_editor_prev_week\")" <<<"$BODY")" == true ]]'
ck "top = web com 2 aceitas" '[[ "$(jq -r ".most_used_editor_prev_week.top.editor" <<<"$BODY")" == web && "$(jq -r ".most_used_editor_prev_week.top.count" <<<"$BODY")" == 2 ]]'
ck "total = 3 (s4 desta semana fora)" '[[ "$(jq -r ".most_used_editor_prev_week.total" <<<"$BODY")" == 3 ]]'
ck "ranking = vim,web" '[[ "$(jq -r ".most_used_editor_prev_week.ranking | map(.editor) | sort | join(\",\")" <<<"$BODY")" == "vim,web" ]]'

echo "== /treino/editor-stats: editores DECLARADOS (perfis) =="
jq '.favorite_editor="vscode"' "$T/users/alice/account.json" > "$T/users/alice/account.json.n" && mv "$T/users/alice/account.json.n" "$T/users/alice/account.json"
fx_user "$T" bob x "Bob"; jq '.favorite_editor="vscode"' "$T/users/bob/account.json" > "$T/users/bob/account.json.n" && mv "$T/users/bob/account.json.n" "$T/users/bob/account.json"
fx_user "$T" carol x "Carol"; jq '.university="X"' "$T/users/carol/account.json" > "$T/users/carol/account.json.n" && mv "$T/users/carol/account.json.n" "$T/users/carol/account.json"   # sem editor
# account do ribas (favorite_editor=vim) já existe do setup
rm -f "$T/var/editor-stats.cache.json"
call /treino/editor-stats GET '' '' ''
ck "declared=3 (vscode x2 + vim x1; carol sem editor fora)" '[[ "$(jq -r .declared <<<"$BODY")" == 3 ]]'
ck "vscode no topo com 2" '[[ "$(jq -r ".ranking[0].editor" <<<"$BODY")" == vscode && "$(jq -r ".ranking[0].count" <<<"$BODY")" == 2 ]]'
ck "ranking = vim,vscode (distintos)" '[[ "$(jq -r ".ranking | map(.editor) | sort | join(\",\")" <<<"$BODY")" == "vim,vscode" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
