#!/bin/bash
# smoke-judge-package-cache.sh — GET /judge/package serve o .tar.gz de um CACHE (run/pkgcache), não
# monta o tar a cada download.
#
# XIV Maratona UnB (25/09/2026): o `tar -czf` a cada download custou 5,7 s de CPU p/ um pacote de 27 MB,
# por juiz e por cache frio — a 1ª submissão do problema naquele juiz esperava isso. Prende:
#   · a resposta é um tar.gz válido, com Content-Length certo, sem .git/tl/tl.*;
#   · a 2ª chamada NÃO roda tar (um `tar` falso no PATH conta) e devolve os MESMOS bytes;
#   · mudar só o ENUNCIADO (fora da pkg_version) gera tar NOVO com o conteúdo novo — a chave cobre tudo
#     que vai no tar — e fica UM arquivo de cache por problema;
#   · ids que o saneamento colidiria (`a#b_c` × `a_b#c`) não se misturam;
#   · cache sem escrita ⇒ o caminho antigo, em fluxo: o juiz nunca fica sem pacote.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"; SHIM="$(mktemp -d)"; W="$(mktemp -d)"
trap 'chmod -R u+w "$RUN" 2>/dev/null; rm -rf "$FIX" "$SESS" "$RUN" "$PROBS" "$SHIM" "$W"' EXIT
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$PROBS" TL_STORE_DIR="$RUN/tl" CALIB_DIR="$RUN/calib"
mkdir -p "$RUN/tl" "$RUN/calib" "$RUN/secrets" "$FIX/treino/var"; printf 'mojw_smoketest' > "$RUN/secrets/worker.token"
echo '{"col":{"members":["autor"],"admins":[],"public_allowed":true},"a":{"members":["autor"]},"a_b":{"members":["autor"]}}' > "$FIX/treino/var/orgs.json"
mkpkg(){ local P="$PROBS/$1"; mkdir -p "$P/sols/good" "$P/tests/input" "$P/docs" "$P/.git" "$P/tl"
  printf 'CALIBRATIONTL=5\n' > "$P/conf"; printf '{"owner":"autor","public":true}\n' > "$P/.moj-meta.json"
  printf 'int main(){return 0;}\n' > "$P/sols/good/sol.c"; printf '1\n' > "$P/tests/input/t1"
  printf '%s\n' "$2" > "$P/docs/enunciado.md"; printf 'x\n' > "$P/.git/HEAD"; printf '{}\n' > "$P/tl/host.json"; printf 'y\n' > "$P/tl.old"; }
mkpkg col/pa "Enunciado versão 1"; mkpkg a/b_c "sou a#b_c"; mkpkg a_b/c "sou a_b#c"
REALTAR="$(command -v tar)"; printf '#!/bin/bash\necho x >> "%s/n"\nexec "%s" "$@"\n' "$SHIM" "$REALTAR" > "$SHIM/tar"; chmod +x "$SHIM/tar"
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-}"; ((fail++)); fi; }
# get <id-urlencoded> <saída> — resposta CRUA em arquivo (o corpo é binário: $(…) comeria os NUL);
# separa cabeçalho (até a 1ª linha vazia) e corpo; conta os tar rodados
get(){ : > "$SHIM/n"
  PATH="$SHIM:$PATH" PATH_INFO=/judge/package REQUEST_METHOD=GET QUERY_STRING="id=$1" HTTP_AUTHORIZATION="Bearer mojw_smoketest" \
    bash "$ROUTER" </dev/null > "$W/raw" 2>/dev/null
  python3 - "$W/raw" "$2" <<'PY'
import sys
raw = open(sys.argv[1], 'rb').read(); i = raw.find(b'\r\n\r\n')
open(sys.argv[2] + '.h', 'wb').write(raw[:i]); open(sys.argv[2], 'wb').write(raw[i + 4:])
PY
  NTAR="$(wc -l < "$SHIM/n")"; }
hdr(){ grep -i "^$2:" "$1.h" | head -1 | cut -d: -f2- | tr -d ' \r'; }

echo "== 1ª chamada: monta e guarda =="
get 'col%23pa' "$W/b1"
DBG="$(cat "$W/b1.h" | tr '\r\n' '  ')"
ck "200, gzip, Content-Length = o corpo" '[[ "$(head -1 "$W/b1.h")" == *"200"* && "$(hdr "$W/b1" Content-Length)" == "$(stat -c%s "$W/b1")" ]]'
LST="$(tar -tzf "$W/b1" 2>/dev/null | sort | tr '\n' ' ')"; DBG="$LST"
ck "tar.gz válido com o pacote e SEM .git/tl/tl.*" '[[ "$LST" == *"pa/docs/enunciado.md"* && "$LST" == *"pa/sols/good/sol.c"* && "$LST" != *".git"* && "$LST" != *"pa/tl/"* && "$LST" != *"tl.old"* ]]'
ck "um arquivo no cache" '[[ "$(find "$RUN/pkgcache" -name "*.tar.gz" | wc -l)" == 1 ]]'

echo "== 2ª chamada: do cache =="
get 'col%23pa' "$W/b2"; DBG="tar rodou $NTAR vez(es)"
ck "NÃO roda tar (era 5,7 s p/ 27 MB) e devolve os MESMOS bytes" '[[ "$NTAR" == 0 ]] && cmp -s "$W/b1" "$W/b2"'

echo "== mudou só o ENUNCIADO (fora da pkg_version): tar novo =="
sleep 1; printf 'Enunciado versão 2\n' > "$PROBS/col/pa/docs/enunciado.md"
get 'col%23pa' "$W/b3"
TXT="$(tar -xzOf "$W/b3" pa/docs/enunciado.md 2>/dev/null)"; DBG="tar=$NTAR txt=$TXT"
ck "o tar novo traz o enunciado novo (a chave cobre tudo que vai no tar)" '[[ "$NTAR" -ge 1 && "$TXT" == "Enunciado versão 2" ]]'
ck "…e fica UM arquivo de cache por problema (a versão velha saiu)" '[[ "$(find "$RUN/pkgcache" -name "*.tar.gz" | wc -l)" == 1 ]]'

echo "== ids que o saneamento colidiria não se misturam =="
get 'a%23b_c' "$W/x1"; get 'a_b%23c' "$W/x2"
T1="$(tar -xzOf "$W/x1" b_c/docs/enunciado.md 2>/dev/null)"; T2="$(tar -xzOf "$W/x2" c/docs/enunciado.md 2>/dev/null)"; DBG="$T1 | $T2"
ck "a#b_c e a_b#c: cada um o seu pacote" '[[ "$T1" == "sou a#b_c" && "$T2" == "sou a_b#c" ]]'

echo "== cache sem escrita: o caminho antigo, em fluxo =="
rm -f "$RUN/pkgcache/"*; chmod 555 "$RUN/pkgcache"
get 'col%23pa' "$W/b4"; chmod 755 "$RUN/pkgcache"
LST="$(tar -tzf "$W/b4" 2>/dev/null | tr '\n' ' ')"; DBG="$LST"
ck "sem cache ainda entrega o pacote (tar em fluxo)" '[[ "$LST" == *"pa/docs/enunciado.md"* ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
