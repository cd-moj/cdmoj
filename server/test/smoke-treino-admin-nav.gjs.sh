#!/bin/bash
# smoke-treino-admin-nav.gjs.sh — a navegação em GRUPOS do painel do treino (web/treino/admin/nav.js, 16/10/2026).
# Prende: o painel abre em Visão geral › Estatísticas (antes abria em Sessões, com o "todos" à mão); grupo sem painel
# abre o 1º dele; todo id antigo de aba (#sessions, #judges…) resolve pelo ALIAS; chave inválida volta ao padrão;
# as chaves são únicas; e TODA chave do nav.js tem o seu make*() no MAKE do admin.js (e vice-versa).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
W="$ROOT/web"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "treino-admin-nav(gjs): gjs ausente — pulando"; exit 0; }
PASS=0; FAIL=0
check(){ if [[ "$1" == "$2" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $3 (got '$1', want '$2')" >&2; fi; }
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
{ echo "const T=(pt)=>pt;"
  strip "$W/treino/admin/nav.js"
  cat <<'JS'
const r = (h) => resolveHash(h).key;
print('vazio=' + r('') + ' lixo=' + r('#lixo/x') + ' grupo=' + r('#pessoas') + ' painel=' + r('#contests/criar'));
print('alias_sessions=' + r('#sessions') + ' alias_judges=' + r('#judges') + ' alias_stats=' + r('stats'));
const keys = GROUPS().flatMap((g) => g.panels.map((p) => g.id + '/' + p.id));
print('unicas=' + (new Set(keys).size === keys.length) + ' n=' + keys.length);
print('alias_ok=' + Object.values(ALIAS).every((k) => r('#' + k) === k));
print('KEYS ' + keys.join(' '));
JS
} > "$T/n.js"
out="$(timeout 30 gjs "$T/n.js" 2>&1)" || { echo "$out" >&2; exit 1; }
kv(){ sed -n "s/^.*\b$1=\([^ ]*\).*$/\1/p" <<<"$out" | head -1; }
check "$(kv vazio)" visao/estatisticas "sem #: abre em Visão geral › Estatísticas"
check "$(kv lixo)" visao/estatisticas "chave inválida: o padrão"
check "$(kv grupo)" pessoas/geridas "grupo sem painel: o 1º dele"
check "$(kv painel)" contests/criar "grupo/painel direto"
check "$(kv alias_sessions)" pessoas/sessoes "id antigo #sessions"
check "$(kv alias_judges)" visao/maquinas "id antigo #judges"
check "$(kv alias_stats)" visao/estatisticas "id antigo sem #"
check "$(kv unicas)" true "chaves únicas"
check "$(kv alias_ok)" true "todo alvo do ALIAS existe"
nav_keys="$(sed -n 's/^KEYS //p' <<<"$out" | tr ' ' '\n' | sort)"
make_keys="$(sed -n "/^const MAKE = {/,/^};/p" "$W/treino/admin/admin.js" | grep -oE "'[a-z]+/[a-z]+'" | tr -d "'" | sort)"
check "$make_keys" "$nav_keys" "MAKE do admin.js == chaves do nav.js"
echo "treino-admin-nav(gjs): $PASS ok, $FAIL falhas"; [[ $FAIL -eq 0 ]]
