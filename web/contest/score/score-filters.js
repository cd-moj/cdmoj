// contest/score/score-filters.js — a LÓGICA dos filtros do placar, sem estado e sem DOM de página:
// enriquecer os times (diretório /contest/teams + regras do teams-meta) e casar bandeira/sede/escola.
// Fonte ÚNICA de dois consumidores: o placar ao vivo (score.js) e a Participação Virtual
// (treino/virtual/virtual.js) — o filtro do virtual é o MESMO do placar oficial. O gêmeo inevitável
// é o script inline do relatório offline (score/report-gen.sh). Tudo aqui recebe o estado por
// parâmetro; quem guarda "qual filtro está ativo" é a página.
import { flagName } from '/shared/flags.js';
import { rgAssign } from '/shared/regions-match.js';

export function safeRe(rx) { try { return new RegExp(rx, 'i'); } catch { return null; } }
export const eqi = (a, b) => String(a || '').toLowerCase() === String(b || '').toLowerCase();

// EXPLÍCITO primeiro (/contest/teams — o `.team` por-usuário + assets): preenche o que o TXT não
// trouxe, marca a sede (t._region, filtro por nome), brasão, 📷 (has_photo) e 🤖 (ai).
export function applyTeamsDir(p, teamsDir, CONTEST) {
  if (!p || !(p.mode === 'icpc' || p.mode === 'obi')) return;
  let anyFlag = false;
  p.teams.forEach(t => {
    // o TXT do placar já traz bandeira e sigla: quem não está no diretório (time removido do
    // store, vindo de USERS_FROM…) precisa entrar nos filtros do mesmo jeito.
    if (!t._country && t.flag) { t._country = t.flag; t.flagTitle = t.flagTitle || flagName(t.flag); }
    if (!t._school && t.univShort) t._school = t.univShort;
    const d = teamsDir[t.username || ''];
    if (!d) return;
    if (d.flag) {
      if (!t.flag) { t.flag = d.flag; anyFlag = true; }
      t._country = d.flag;
      t.flagTitle = flagName(d.flag);
    }
    if (d.univ_short && !t.univShort) t.univShort = d.univ_short;
    if (d.univ_full && !t.univFull) t.univFull = d.univ_full;
    if (d.region) t._region = d.region;
    t._school = t._school || t.univShort || '';
    if (d.has_logo && !t.schoolLogo) {
      t.schoolLogo = '/api/v1/contest/team-logo?contest=' + encodeURIComponent(CONTEST) + '&user=' + encodeURIComponent(t.username || '');
    }
    if (d.has_photo) {
      t.photoUrl = '/api/v1/contest/team-photo?contest=' + encodeURIComponent(CONTEST) + '&user=' + encodeURIComponent(t.username || '');
    }
    if (d.ai) t.aiDeclared = true;
  });
  if (anyFlag && p.mode === 'obi') p.hasFlag = true;
}

// regras por regex do teams-meta: FALLBACK — a bandeira do próprio time vence (issue #21)
export function applyTeamsMeta(p, teamsMeta) {
  if (!p || !(p.mode === 'icpc' || p.mode === 'obi') || !teamsMeta || !teamsMeta.length) return;
  let anyFlag = false;
  const compiled = teamsMeta.map(r => ({ ...r, _re: safeRe(r.regex || '') }));
  p.teams.forEach(t => {
    const u = t.username || '';
    t._country = t._country || ''; t._school = t._school || t.univShort || '';
    const rule = compiled.find(r => r._re && r._re.test(u));
    if (!rule) return;
    // a regra é FALLBACK: a bandeira do próprio time (TXT/diretório) vence — a regra da sede
    // "CA" (Central America no nome da sede, Canadá na ISO) punha "Canada" no tooltip de times
    // com bandeira CR/GT/SV/NI (issue #21, LATAM 2026)
    if (rule.country && !t.flag) {
      t.flag = rule.country; anyFlag = true;
      t._country = rule.country;
      t.flagTitle = flagName(rule.country);
    }
    if (rule.school && !t.univShort) t.univShort = rule.school;
    if (rule.school_full && !t.univFull) t.univFull = rule.school_full;
    if (rule.logo && !t.schoolLogo) t.schoolLogo = rule.logo;   // brasão por-time (teamsDir) vence
    t._school = rule.school || t.univShort || '';
  });
  if (anyFlag && p.mode === 'obi') p.hasFlag = true;
}

// SEDES pela regra ÚNICA (web/shared/regions-match.js, gêmeo de server/api/v1/lib/regions.sh): a sede
// gravada (t._region, do /contest/teams) vence, senão a regex mais funda; pai = soma dos filhos; recorte
// entra pela regex. Calculado UMA vez por (árvore, times) — 2000 times × 200 nós é caro p/ refazer a cada
// renderização. Cada opção leva `_mem` (os logins do nó).
const _rgMemo = new WeakMap();
function regionIndex(regions, teams) {
  const tl = teams || [];
  const sig = tl.length + '|' + tl.map((t) => (t.username || '') + ':' + (t._region || '')).join(',');
  const hit = regions && typeof regions === 'object' ? _rgMemo.get(regions) : null;
  if (hit && hit.sig === sig) return hit.res;
  const res = rgAssign(Array.isArray(regions) ? regions : [], tl.map((t) => ({ login: t.username || '', region: t._region || '' })));
  const mem = res.nodes.map(() => new Set());
  res.rows.forEach((r) => r.nodes.forEach((i) => mem[i].add(r.login)));
  const out = { nodes: res.nodes, mem };
  if (regions && typeof regions === 'object') _rgMemo.set(regions, { sig, res: out });
  return out;
}
// t está na sede ativa? Opção de regionOptions (com _mem) = pela pertença. Sede guardada antes (sem _mem:
// localStorage de antes de 28/09/2026 ou opção que sumiu) = o casamento antigo (nome gravado OU regex).
export function regionMatch(t, activeRegion) {
  if (!activeRegion) return true;
  if (activeRegion._mem instanceof Set) return activeRegion._mem.has(t.username || '');
  if (activeRegion.regex) { const re = safeRe(activeRegion.regex); if (re && re.test(t.username || '')) return true; }
  if (activeRegion.name && (t._region || '') &&
      String(t._region).toLowerCase() === String(activeRegion.name).toLowerCase()) return true;
  return false;
}
// a opção de regionOptions que corresponde a uma sede guardada ({name, regex}) — mesmo nome e regex,
// senão o 1º nó com o nome (a regex guardada pode ser a crua, e a opção traz a normalizada)
export function regionResolve(rops, saved) {
  if (!saved || !Array.isArray(rops)) return null;
  const nm = String(saved.name || '').toLowerCase();
  return rops.find((o) => String(o.name || '').toLowerCase() === nm && (o.regex || '') === (saved.regex || ''))
    || rops.find((o) => nm && String(o.name || '').toLowerCase() === nm) || null;
}
// Bandeira casa por HIERARQUIA: valor sem hífen é PAÍS e agrega os estados (br casa br E br-*);
// com hífen (br-pr) é exato. Casamento ESTRITO: quem não tem o dado NÃO casa.
export function countryMatch(t, activeCountry) {
  if (!activeCountry) return true;
  const c = String(t._country || '').toLowerCase();
  if (!c) return false;
  if (activeCountry.includes('-')) return c === activeCountry;
  return c === activeCountry || c.startsWith(activeCountry + '-');
}
// predicado de LINHA dos três filtros (null = nenhum ativo)
export function rowFilter(f) {
  if (!f || (!f.region && !f.country && !f.school)) return null;
  return (t) => regionMatch(t, f.region) && countryMatch(t, f.country) && (!f.school || eqi(t._school, f.school));
}
// sedes p/ o <select>: a ÁRVORE do regions.json (achatada em pré-ordem, subregião indentada) + as sedes
// gravadas nos times que não estão nela (as órfãs, no fim) — cada uma com os logins que estão nela (_mem)
export function regionOptions(regions, teams) {
  const ix = regionIndex(regions, teams);
  return ix.nodes.filter((nd) => nd.name)
    .map((nd) => ({ name: nd.name, regex: nd.regex, depth: nd.depth, i: nd.i, view: nd.view, orphan: nd.orphan, _mem: ix.mem[nd.i] }));
}
