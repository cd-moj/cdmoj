// shared/users-batch.js — utilidades de LOTE de usuários, compartilhadas entre a criação de
// contest (web/treino/criar) e a aba Usuários & sessões do admin. Módulo sem side effects
// (o admin não pode importar de criar.js, que é módulo de página).

// parseUsers(text) -> [{login,password,fullname,email}] — aceita, por linha:
//   login:senha:nome:email   |   login,nome,email (ou TAB)   |   Nome Completo (login/senha gerados)
// Logins faltantes viram slug do nome, com unicidade.
const slug = (s) => (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, '').slice(0, 24);

export function parseUsers(text) {
  const out = [];
  (text || '').split(/\r?\n/).forEach((raw) => {
    const line = raw.trim(); if (!line) return;
    if (line.includes(':')) { const p = line.split(':'); out.push({ login: (p[0] || '').trim(), password: (p[1] || '').trim(), fullname: (p[2] || '').trim(), email: (p[3] || '').trim() }); }
    else if (line.includes('\t') || line.includes(',')) { const p = line.split(/[\t,]/).map((s) => s.trim()); out.push({ login: p[0] || '', password: '', fullname: p[1] || '', email: p[2] || '' }); }
    else out.push({ login: '', password: '', fullname: line, email: '' });
  });
  const seen = new Set(out.map((u) => u.login).filter(Boolean));
  out.forEach((u) => {
    if (u.login) return;
    let base = slug(u.fullname) || 'user', cand = base, k = 1;
    while (seen.has(cand)) cand = base + (++k);
    seen.add(cand); u.login = cand;
  });
  return out;
}

// downloadCsv(filename, users) — baixa login,senha,nome,email (senhas só aparecem aqui).
export function downloadCsv(filename, users) {
  const head = 'login,senha,nome,email';
  const esc = (x) => '"' + String(x == null ? '' : x).replace(/"/g, '""') + '"';
  const rows = (users || []).map((u) => [u.login, u.password, u.fullname, u.email].map(esc).join(','));
  const blob = new Blob([head + '\n' + rows.join('\n')], { type: 'text/csv' });
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = filename; a.click(); URL.revokeObjectURL(a.href);
}
