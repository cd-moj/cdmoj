// Consolidado: Log & sessões virou uma aba do hub de administração.
const c = new URLSearchParams(location.search).get('c');
location.replace('/contest/admin/' + (c ? ('?c=' + encodeURIComponent(c)) : '') + '#log');
