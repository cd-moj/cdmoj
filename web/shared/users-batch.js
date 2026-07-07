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

// --- CSV COM CABEÇALHO (carga enriquecida de TIMES) ------------------------------------
// parseRichCsv(text) -> [{login, password?, fullname?, email?, country?, region?,
//                         univ_short?, univ_full?}]  |  null (sem cabeçalho)
// A 1ª linha não-vazia precisa ter a coluna `login` + ao menos outra conhecida; a ordem é
// livre e os nomes aceitam aliases PT/EN (ex.: senha, nome, pais, sede, univ, univ_nome).
// O NOME é campo ÚNICO: `nome`/`time`/`equipe` são a MESMA coluna (fullname) — em contest
// o usuário É o time. Valores com vírgula vão entre aspas ("Univ de Brasília, Darcy").
// Sem cabeçalho, o chamador cai no parseUsers clássico — formatos antigos intactos.
const HEADER_ALIASES = {
  login: 'login', usuario: 'login', username: 'login',
  senha: 'password', password: 'password',
  nome: 'fullname', fullname: 'fullname', name: 'fullname',
  time: 'fullname', team: 'fullname', equipe: 'fullname',
  email: 'email', 'e-mail': 'email',
  pais: 'country', país: 'country', country: 'country', bandeira: 'country', flag: 'country',
  sede: 'region', regiao: 'region', região: 'region', region: 'region', site: 'region',
  univ: 'univ_short', univ_curta: 'univ_short', sigla: 'univ_short', school: 'univ_short', univ_short: 'univ_short',
  univ_nome: 'univ_full', univ_completa: 'univ_full', universidade: 'univ_full', school_full: 'univ_full', univ_full: 'univ_full',
};
function splitCsvLine(line, sep) {
  const out = []; let cur = '', q = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (q) { if (c === '"') { if (line[i + 1] === '"') { cur += '"'; i++; } else q = false; } else cur += c; }
    else if (c === '"') q = true;
    else if (c === sep) { out.push(cur); cur = ''; }
    else cur += c;
  }
  out.push(cur);
  return out.map((s) => s.trim());
}
export function parseRichCsv(text) {
  const lines = (text || '').split(/\r?\n/).filter((l) => l.trim());
  if (!lines.length) return null;
  const head = lines[0];
  const sep = head.includes('\t') ? '\t' : head.includes(';') ? ';' : ',';
  const cols = splitCsvLine(head, sep).map((h) => HEADER_ALIASES[h.toLowerCase().trim()] || null);
  const known = cols.filter(Boolean);
  if (!cols.includes('login') || known.length < 2) return null;   // não é cabeçalho
  return lines.slice(1).map((line) => {
    const vals = splitCsvLine(line, sep), u = {};
    cols.forEach((k, i) => { if (k && vals[i]) u[k] = vals[i]; });
    return u;
  }).filter((u) => u.login);
}

// downloadCsv(filename, users) — baixa login,senha,nome,email (senhas só aparecem aqui).
export function downloadCsv(filename, users) {
  const head = 'login,senha,nome,email';
  const esc = (x) => '"' + String(x == null ? '' : x).replace(/"/g, '""') + '"';
  const rows = (users || []).map((u) => [u.login, u.password, u.fullname, u.email].map(esc).join(','));
  const blob = new Blob([head + '\n' + rows.join('\n')], { type: 'text/csv' });
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = filename; a.click(); URL.revokeObjectURL(a.href);
}
