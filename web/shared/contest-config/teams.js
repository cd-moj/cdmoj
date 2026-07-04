// shared/contest-config/teams.js — editor de regras país/escola (teams-meta).
// Regra: regex no login -> país (bandeira local) + escola (sigla/nome) + logo opcional (data-URL, offline).
// Ferramentas p/ contest grande: PREVIEW DE MATCHES (mesma semântica do placar: RegExp(regex,'i'),
// a 1ª regra que casa vence — score.js applyTeamsMeta), IMPORTAR JSON pronto (substituir ou
// acrescentar), EXPORTAR as regras e baixar um TEMPLATE (^login$ dos SEM match) p/ completar
// via script e re-importar. `opts.logins` (opcional) alimenta o preview.
import { el } from '/shared/ui.js';
import { flagManifest, flagEl } from '/shared/flags.js';

const safeRe = (rx) => { try { return new RegExp(rx, 'i'); } catch { return null; } };
const reEscape = (s) => String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
function downloadJson(filename, obj) {
  const blob = new Blob([JSON.stringify(obj, null, 2) + '\n'], { type: 'application/json;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = el('a', { href: url, download: filename }); document.body.append(a); a.click();
  setTimeout(() => { a.remove(); URL.revokeObjectURL(url); }, 0);
}

export async function makeTeamsEditor(opts = {}) {
  const mani = await flagManifest();
  const OPTIONS = [{ code: '', name: '— país / estado —' },
    ...(mani.countries || []).map((c) => ({ code: c.code.toUpperCase(), name: c.name })),
    ...(mani.br_states || []).map((s) => ({ code: 'BR-' + s.code.toUpperCase(), name: 'BR · ' + s.name }))];
  let rules = (opts.initial || []).map((r) => ({ ...r }));
  const logins = (opts.logins || []).filter(Boolean);
  const list = el('div', {});
  const matchBox = el('div', {});

  function rowEl(r, i) {
    const regex = el('input', { value: r.regex || '', placeholder: 'regex no login (ex.: ^br-df-)', style: 'flex:1' });
    regex.addEventListener('input', () => { r.regex = regex.value; });
    regex.addEventListener('change', renderMatches);
    const country = el('select', {}, ...OPTIONS.map((o) => el('option', { value: o.code }, o.name)));
    country.value = (r.country || '').toUpperCase();
    const flagPrev = el('span', {});
    const updFlag = () => { flagPrev.innerHTML = ''; const f = flagEl(country.value, { height: 16 }); if (f) flagPrev.append(f); };
    country.addEventListener('change', () => { r.country = country.value; updFlag(); renderMatches(); }); updFlag();
    const school = el('input', { value: r.school || '', placeholder: 'sigla (UnB)', style: 'width:100px' });
    school.addEventListener('input', () => { r.school = school.value; });
    school.addEventListener('change', renderMatches);
    const schoolFull = el('input', { value: r.school_full || '', placeholder: 'nome completo da escola (opcional)', style: 'flex:1' });
    schoolFull.addEventListener('input', () => { r.school_full = schoolFull.value; });
    const logoPrev = el('span', {});
    const showLogo = () => { logoPrev.innerHTML = ''; if (r.logo) { const img = document.createElement('img'); img.src = r.logo; img.style.cssText = 'height:18px;vertical-align:middle;border-radius:2px'; logoPrev.append(img); } };
    const logoInp = el('input', { type: 'file', accept: 'image/*', style: 'display:none' });
    logoInp.addEventListener('change', () => { const f = logoInp.files[0]; if (!f) return; const rd = new FileReader(); rd.onload = () => { r.logo = rd.result; showLogo(); }; rd.readAsDataURL(f); });
    showLogo();
    const rm = el('button', { class: 'btn danger', onclick: () => { rules.splice(i, 1); render(); } }, '✕');
    return el('div', { style: 'border:1px solid #e3e9f2;border-radius:8px;padding:.5rem;margin:.4rem 0;background:#fafcff' },
      el('div', { class: 'row' }, el('span', { class: 'small muted' }, 'login casa:'), regex),
      el('div', { class: 'row' }, country, flagPrev, school,
        el('span', { class: 'small muted' }, 'logo:'), logoPrev,
        el('button', { class: 'btn ghost', onclick: () => logoInp.click() }, 'enviar'),
        el('button', { class: 'btn ghost', onclick: () => { r.logo = ''; showLogo(); } }, '✕'), logoInp),
      el('div', { class: 'row' }, schoolFull, rm));
  }

  function currentRules() {
    return rules.filter((r) => r.regex && r.regex.trim()).map((r) => ({
      regex: r.regex.trim(),
      country: r.country || undefined, school: r.school || undefined,
      school_full: r.school_full || undefined, logo: r.logo || undefined,
    }));
  }

  // --- matches: 1ª regra que casa vence (exatamente como o placar aplica) ---
  function matchRows() {
    const compiled = currentRules().map((r) => ({ r, re: safeRe(r.regex) }));
    return logins.map((u) => ({ login: u, rule: (compiled.find((c) => c.re && c.re.test(u)) || {}).r || null }));
  }
  function unmatchedLogins() { return matchRows().filter((x) => !x.rule).map((x) => x.login); }

  function renderMatches() {
    matchBox.innerHTML = '';
    matchBox.append(el('h4', { style: 'margin:.8rem 0 .2rem' }, '🔎 Matches (quem casa com o quê)'));
    if (!logins.length) {
      matchBox.append(el('p', { class: 'muted small' }, 'Sem logins para testar aqui (usuários compartilhados/ainda não criados). As regras valem do mesmo jeito — o placar aplica no login de quem aparecer.'));
      return;
    }
    const rows = matchRows();
    const un = rows.filter((x) => !x.rule);
    const bad = currentRules().filter((r) => !safeRe(r.regex));
    if (bad.length) matchBox.append(el('div', { class: 'small error-box', style: 'margin:.2rem 0' },
      '⚠ regex inválida (ignorada pelo placar): ' + bad.map((r) => r.regex).join(' · ')));
    matchBox.append(el('div', { class: 'small', style: 'margin:.2rem 0' },
      el('b', {}, String(rows.length - un.length)), ' de ' + rows.length + ' logins casam · ',
      el('b', { style: un.length ? 'color:#b8860b' : '' }, String(un.length)), ' sem match'));
    const tb = el('tbody');
    rows.forEach((x) => {
      const flag = x.rule && x.rule.country ? flagEl(x.rule.country, { height: 14 }) : null;
      tb.append(el('tr', {},
        el('td', { class: 'small', style: 'font-family:var(--mono,monospace)' }, x.login),
        el('td', { class: 'small', style: 'font-family:var(--mono,monospace)' }, x.rule ? x.rule.regex : el('span', { style: 'color:#b8860b' }, '— sem match —')),
        el('td', {}, flag || '', x.rule && x.rule.country ? ' ' + x.rule.country : ''),
        el('td', { class: 'small' }, x.rule ? (x.rule.school || '') : '')));
    });
    matchBox.append(el('div', { class: 'chart-wrap', style: 'max-height:260px; overflow:auto' },
      el('table', { class: 'moj' }, el('thead', {}, el('tr', {},
        el('th', {}, 'Login'), el('th', {}, 'Regra (1ª que casa vence)'), el('th', {}, 'País'), el('th', {}, 'Escola'))), tb)));
  }

  // --- importar / exportar / template ---
  const impMode = el('select', {}, el('option', { value: 'replace' }, 'substituir as regras'),
    el('option', { value: 'append' }, 'acrescentar às regras'));
  const impMsg = el('div', { class: 'small' });
  const impInp = el('input', { type: 'file', accept: '.json,application/json', style: 'display:none' });
  impInp.addEventListener('change', () => {
    const f = impInp.files[0]; if (!f) return;
    const rd = new FileReader();
    rd.onload = () => {
      try {
        let arr = JSON.parse(rd.result);
        if (arr && Array.isArray(arr.rules)) arr = arr.rules;   // aceita o teams-meta.json cru
        if (!Array.isArray(arr)) throw new Error('esperado um array de regras');
        const clean = arr
          .filter((r) => r && typeof r.regex === 'string' && r.regex.trim())
          .map((r) => ({ regex: r.regex.trim(), country: r.country || '', school: r.school || '', school_full: r.school_full || '', logo: r.logo || '' }));
        if (!clean.length) throw new Error('nenhuma regra válida no arquivo');
        const invalid = clean.filter((r) => !safeRe(r.regex)).length;
        rules = (impMode.value === 'append' ? rules.concat(clean) : clean);
        render();
        impMsg.className = 'small';
        impMsg.textContent = '✓ ' + clean.length + ' regra(s) importadas (' + (impMode.value === 'append' ? 'acrescentadas' : 'substituíram as anteriores') + ')'
          + (invalid ? ' — ⚠ ' + invalid + ' com regex inválida' : '') + '. Salve para aplicar.';
      } catch (e) { impMsg.className = 'small error-box'; impMsg.textContent = 'Import falhou: ' + (e.message || 'JSON inválido'); }
      impInp.value = '';
    };
    rd.readAsText(f);
  });
  const tools = el('div', { style: 'margin-top:.6rem' },
    el('h4', { style: 'margin:.8rem 0 .2rem' }, '📦 Importar / exportar (p/ scripts em contest grande)'),
    el('div', { class: 'row', style: 'flex-wrap:wrap; gap:.4rem' },
      el('button', { class: 'btn ghost', onclick: () => impInp.click() }, '⬆ Importar JSON'), impMode, impInp,
      el('button', { class: 'btn ghost', onclick: () => downloadJson('teams-meta-regras.json', currentRules()) }, '⬇ Exportar regras'),
      el('button', { class: 'btn ghost', title: 'JSON com uma regra ^login$ vazia por login SEM match — complete via script e importe de volta', onclick: () => {
        const un = unmatchedLogins();
        if (!un.length) { impMsg.className = 'small'; impMsg.textContent = logins.length ? 'todos os logins já casam 🎉' : 'sem logins p/ gerar o template.'; return; }
        downloadJson('teams-meta-template.json', un.map((u) => ({ regex: '^' + reEscape(u) + '$', country: '', school: '', school_full: '' })));
      } }, '⬇ Template dos sem match')),
    impMsg);

  function render() {
    list.innerHTML = '';
    if (!rules.length) list.append(el('p', { class: 'muted small' }, 'Nenhuma regra. As bandeiras de país/estado são locais (offline); o logo da escola você envia (fica embutido).'));
    rules.forEach((r, i) => list.append(rowEl(r, i)));
    renderMatches();
  }
  render();
  const panel = el('div', {}, list,
    el('button', { class: 'btn ghost', onclick: () => { rules.push({ regex: '', country: '', school: '', school_full: '', logo: '' }); render(); } }, '+ regra'),
    matchBox, tools);
  return { el: panel, getValue: currentRules };
}
