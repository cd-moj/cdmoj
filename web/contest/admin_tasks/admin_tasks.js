// Consolidado: Tarefas Administrativas virou Central › Regras do painel de admin.
const c = new URLSearchParams(location.search).get('c');
location.replace('/contest/admin/' + (c ? ('?c=' + encodeURIComponent(c)) : '') + '#central/regras');
