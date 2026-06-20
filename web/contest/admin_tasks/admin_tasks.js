// Consolidado: Tarefas Administrativas virou a aba "Configurações"/"Problemas" do hub.
const c = new URLSearchParams(location.search).get('c');
location.replace('/contest/admin/' + (c ? ('?c=' + encodeURIComponent(c)) : '') + '#settings');
