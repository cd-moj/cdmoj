#!/bin/bash
# Testa editor favorito, privacidade/visão pública, ranking de editores e foto.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
T="$FIX/treino"; mkdir -p "$T/var"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\n' > "$T/conf"
fx_user "$T" alice s "Alice"
fx_user "$T" bob s "Bob"
fx_user "$T" carol s "Carol"
jq '.favorite_editor="emacs"' "$T/users/bob/account.json" > "$T/users/bob/account.json.n" && mv "$T/users/bob/account.json.n" "$T/users/bob/account.json"
jq '.public=false | .favorite_editor="vim"' "$T/users/carol/account.json" > "$T/users/carol/account.json.n" && mv "$T/users/carol/account.json.n" "$T/users/carol/account.json"
printf '1700000000:p#a:C:Accepted,100p:1700000000:h1\n' >> "$T/users/carol/history"
printf '1700000001:p#a:C:Accepted,100p:1700000001:h2\n' >> "$T/users/alice/history"
for u in alice carol; do printf 'CONTEST="treino"\nLOGIN="%s"\nUSERFULLNAME="%s"\nLOGINAT=1\n' "$u" "$u" > "$SESS/tok-$u"; done

# call <path> <method> <query> <token|""> [body]
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="$3" \
  HTTP_AUTHORIZATION="${4:+Bearer $4}" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" \
  bash "$ROUTER" <<<"${5:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:140}"; ((fail++)); fi; }

echo "== editor favorito =="
call /treino/profile POST "" tok-alice '{"favorite_editor":"vim"}'
ck "alice set vim"        '[[ "$(jq -r .favorite_editor <<<"$BODY")" == "vim" ]]'
call /treino/profile POST "" tok-alice '{"favorite_editor":"naoexiste"}'
ck "editor inválido 400"  '[[ "$OUT" == *"Status: 400"* ]]'

echo "== privacidade / visão pública =="
call /treino/profile GET "user=alice" ""
ck "alice pública (sem auth)" '[[ "$(jq -r .is_public <<<"$BODY")" == "true" && "$(jq -r .name <<<"$BODY")" == "Alice" ]]'
call /treino/profile GET "user=carol" ""
ck "carol privada -> is_public:false" '[[ "$(jq -r .is_public <<<"$BODY")" == "false" && "$(jq -r .name <<<"$BODY")" == "null" ]]'
call /treino/profile GET "user=carol" tok-carol
ck "carol vê o próprio (privado)" '[[ "$(jq -r .name <<<"$BODY")" == "Carol" ]]'

echo "== history-full respeita privacidade =="
call /treino/history-full GET "user=carol" ""
ck "history privado vazio (sem auth)" '[[ -z "$(echo "$BODY" | tr -d "[:space:]")" ]]'
call /treino/history-full GET "user=carol" tok-carol
ck "history próprio visível"          '[[ "$BODY" == *carol* ]]'
call /treino/history-full GET "user=alice" ""
ck "history público visível"          '[[ "$BODY" == *alice* ]]'

echo "== ranking de editores =="
call /treino/editors GET "" ""
ck "ranking: vim líder (alice+carol=2)" '[[ "$(jq -r ".editors[0].editor" <<<"$BODY")" == "vim" && "$(jq -r ".editors[0].count" <<<"$BODY")" == "2" ]]'
ck "total = 3"                          '[[ "$(jq -r .total <<<"$BODY")" == "3" ]]'

echo "== foto (upload + redimensiona + serve) =="
IMG="$(convert -size 40x60 xc:'#3366cc' png:- 2>/dev/null | base64 -w0)"
call /treino/profile/photo POST "" tok-alice "$(jq -n --arg i "$IMG" '{image_b64:$i}')"
ck "upload ok"            '[[ "$(jq -r .updated <<<"$BODY")" == "true" ]]'
ck "arquivo png existe"   '[[ -f "$T/users/alice/photo.png" ]]'
ck "foto é 100x100"       '[[ "$(identify -format "%wx%h" "$T/users/alice/photo.png" 2>/dev/null)" == "100x100" ]]'
call /treino/profile/photo GET "user=alice" ""
ck "serve png (magic)"    '[[ "$OUT" == *"Content-Type: image/png"* && "$BODY" == *"PNG"* ]]'
call /treino/profile/photo GET "user=carol" ""
ck "foto de privado sem auth -> 404" '[[ "$OUT" == *"Status: 404"* ]]'

echo ""
echo "RESULT: $pass passed, $fail failed"
exit $(( fail>0 ? 1 : 0 ))
