#!/bin/bash
# smoke-upload-stale.sh — `moj upload` NÃO pode manter um arquivo VELHO no servidor quando o novo tem
# o MESMO tamanho e o MESMO mtime (o tar preserva mtime; o quick-check do rsync pulava sem comparar
# conteúdo). Caso real de julho/2026: tests/output/x "3000" → "1234" (4 bytes, mtime 2019) ficou velho
# e a referência dava WA. Também confere que arquivo removido do pacote SOME (--delete) e que o
# .moj-meta.json do servidor sobrevive.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"; W="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS" "$W"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$PROBS" MOJ_JOBS_SYNC=1
mkdir -p "$FIX/treino/var"
command -v rsync >/dev/null 2>&1 || { echo "SKIP: sem rsync (o caminho tar apaga tudo antes e não tem o problema)"; exit 0; }
NOW="$EPOCHSECONDS"
fx_user "$FIX/treino" alice s "Alice"
echo '{"threshold":0,"allow":["alice"],"deny":[]}' > "$FIX/treino/var/contest-perms.json"
echo '{"col":{"members":["alice"],"admins":["alice"],"created_by":"alice","title":"Col","public_allowed":false}}' > "$FIX/treino/var/orgs.json"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino alice Alice "$NOW" > "$SESS/ali"
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" HTTP_AUTHORIZATION="Bearer $3" bash "$ROUTER" <<<"${4:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }

# pacote NO SERVIDOR: output velho "3000" (4 bytes) com mtime de 2019 + um arquivo que vai sumir
P="$PROBS/col/pa"; mkdir -p "$P/docs" "$P/tests/input" "$P/tests/output" "$P/sols/good"
printf 'Leia N.\n\n## Entrada\n\nx\n\n## Saída\n\ny\n' > "$P/docs/enunciado.md"
printf '3\n' > "$P/tests/input/x"; printf '3000' > "$P/tests/output/x"; printf 'velho\n' > "$P/tests/input/apagar"; printf 'v\n' > "$P/tests/output/apagar"
printf 'int main(){return 0;}\n' > "$P/sols/good/a.c"; printf 'Autor\n' > "$P/author"
printf '{"owner":"alice","public":false,"display_title":"PA do servidor"}' > "$P/.moj-meta.json"
touch -d '2019-05-05 05:05:05' "$P/tests/output/x" "$P/tests/input/x"
( cd "$P" && git init -q . && git add -A . && git -c user.name=t -c user.email=t@t commit -qm init ) 2>/dev/null

# pacote DO AUTOR: mesmo output com conteúdo NOVO "1234" (4 bytes) e o MESMO mtime; sem o "apagar"
C="$W/pa"; mkdir -p "$C/docs" "$C/tests/input" "$C/tests/output" "$C/sols/good"
cp "$P/docs/enunciado.md" "$C/docs/"; cp "$P/sols/good/a.c" "$C/sols/good/"; cp "$P/author" "$C/"
printf '3\n' > "$C/tests/input/x"; printf '1234' > "$C/tests/output/x"
touch -d '2019-05-05 05:05:05' "$C/tests/output/x" "$C/tests/input/x"
TAR="$( (cd "$W" && tar -cf - pa) | base64 -w0 )"

echo "== upload com output de mesmo tamanho e mesmo mtime, conteúdo novo =="
call /problems/upload POST ali "{\"id\":\"col#pa\",\"tar_b64\":\"$TAR\"}"
ck "upload 200"                                 '[[ "$OUT" == *"Status: 200"* ]]'
ck "tests/output/x passou a ter o conteúdo NOVO (1234)" '[[ "$(cat "$P/tests/output/x")" == 1234 ]]'
ck "arquivo removido no pacote do autor sumiu do servidor (--delete)" '[[ ! -e "$P/tests/input/apagar" && ! -e "$P/tests/output/apagar" ]]'
ck ".moj-meta.json do servidor sobreviveu"      '[[ "$(jq -r .display_title "$P/.moj-meta.json")" == "PA do servidor" ]]'
ck ".git do servidor sobreviveu"                '[[ -d "$P/.git" ]]'
echo; echo "RESULT: $pass passed, $fail failed"; [[ $fail -eq 0 ]]
