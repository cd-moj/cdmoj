// Consolidado: Log & sessões virou Pessoas › Sessões do painel de admin.
const c = new URLSearchParams(location.search).get('c');
location.replace('/contest/admin/' + (c ? ('?c=' + encodeURIComponent(c)) : '') + '#pessoas/sessoes');
