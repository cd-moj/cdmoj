// shared/contest-host.js — detecta se estamos num subdomínio de contest
// (<ID>.moj.charge.naquadah.com.br em teste, <ID>.moj.naquadah.com.br em produção)
// e retorna o ID do contest, ou null no site principal / localhost.
export function contestHost() {
  const m = location.hostname.match(/^([a-z0-9][a-z0-9._-]*)\.(?:new)?moj\./i);
  return m ? m[1].toLowerCase() : null;
}
