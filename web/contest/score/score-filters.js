// contest/score/score-filters.js — a LÓGICA dos filtros do placar, sem estado e sem DOM de página:
// enriquecer os times (diretório /contest/teams + regras do teams-meta) e casar bandeira/sede/escola.
// Fonte ÚNICA de dois consumidores: o placar ao vivo (score.js) e a Participação Virtual
// (treino/virtual/virtual.js) — o filtro do virtual é o MESMO do placar oficial. O gêmeo inevitável
// é o script inline do relatório offline (score/report-gen.sh). Tudo aqui recebe o estado por
// parâmetro; quem guarda "qual filtro está ativo" é a página.
import { flagName } from '/shared/flags.js';

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

// t casa com a sede ativa? Por NOME (t._region == sede explícita do time) OU pelo regex no login.
export function regionMatch(t, activeRegion) {
  if (!activeRegion) return true;
  if (activeRegion.regex) { const re = safeRe(activeRegion.regex); if (re && re.test(t.username || '')) return true; }
  if (activeRegion.name && (t._region || '') &&
      String(t._region).toLowerCase() === String(activeRegion.name).toLowerCase()) return true;
  return false;
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
// sedes p/ o <select>: a ÁRVORE do regions.json (achatada, subregião indentada) + as sedes que
// aparecem nos times e não estão lá.
export function regionOptions(regions, teams) {
  const out = [];
  const walk = (list, depth) => (list || []).forEach(r => {
    if (r.regex || r.name) out.push({ name: r.name || '', regex: r.regex || '', depth });
    if (Array.isArray(r.subregions) && r.subregions.length) walk(r.subregions, depth + 1);
  });
  walk(regions, 0);
  const seen = new Set(out.map(o => (o.name || '').toLowerCase()));
  (teams || []).forEach(t => {
    const n = t._region || ''; if (!n || seen.has(n.toLowerCase())) return;
    seen.add(n.toLowerCase()); out.push({ name: n, regex: '', depth: 0 });
  });
  return out;
}
