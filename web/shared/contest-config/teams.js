// shared/contest-config/teams.js — editor de regras país/escola (teams-meta).
// Regra: regex no login -> país (bandeira local) + escola (sigla/nome) + logo opcional (data-URL, offline).
import { el } from '/shared/ui.js';
import { flagManifest, flagEl } from '/shared/flags.js';

export async function makeTeamsEditor(opts = {}) {
  const mani = await flagManifest();
  const OPTIONS = [{ code: '', name: '— país / estado —' },
    ...(mani.countries || []).map((c) => ({ code: c.code.toUpperCase(), name: c.name })),
    ...(mani.br_states || []).map((s) => ({ code: 'BR-' + s.code.toUpperCase(), name: 'BR · ' + s.name }))];
  let rules = (opts.initial || []).map((r) => ({ ...r }));
  const list = el('div', {});

  function rowEl(r, i) {
    const regex = el('input', { value: r.regex || '', placeholder: 'regex no login (ex.: ^br-df-)', style: 'flex:1' });
    regex.addEventListener('input', () => { r.regex = regex.value; });
    const country = el('select', {}, ...OPTIONS.map((o) => el('option', { value: o.code }, o.name)));
    country.value = (r.country || '').toUpperCase();
    const flagPrev = el('span', {});
    const updFlag = () => { flagPrev.innerHTML = ''; const f = flagEl(country.value, { height: 16 }); if (f) flagPrev.append(f); };
    country.addEventListener('change', () => { r.country = country.value; updFlag(); }); updFlag();
    const school = el('input', { value: r.school || '', placeholder: 'sigla (UnB)', style: 'width:100px' });
    school.addEventListener('input', () => { r.school = school.value; });
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
  function render() {
    list.innerHTML = '';
    if (!rules.length) list.append(el('p', { class: 'muted small' }, 'Nenhuma regra. As bandeiras de país/estado são locais (offline); o logo da escola você envia (fica embutido).'));
    rules.forEach((r, i) => list.append(rowEl(r, i)));
  }
  render();
  const panel = el('div', {}, list,
    el('button', { class: 'btn ghost', onclick: () => { rules.push({ regex: '', country: '', school: '', school_full: '', logo: '' }); render(); } }, '+ regra'));
  return {
    el: panel,
    getValue() {
      return rules.filter((r) => r.regex && r.regex.trim()).map((r) => ({
        regex: r.regex.trim(),
        country: r.country || undefined, school: r.school || undefined,
        school_full: r.school_full || undefined, logo: r.logo || undefined,
      }));
    },
  };
}
