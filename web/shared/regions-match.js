// shared/regions-match.js — a REGRA ÚNICA de sede (time → sede), gêmea de server/api/v1/lib/regions.sh.
// A regra está descrita lá (cabeçalho). Este arquivo existe para a interface calcular o MESMO que o
// servidor (prévia do painel de sedes, filtros do placar) sem reimplementar nada; o
// server/test/smoke-regions-match.gjs.sh roda os dois sobre as mesmas árvores e exige saída idêntica.
// Mudou a regra lá? Mude aqui no mesmo commit.
//
//   rgKey(s)            nome → chave (minúsculas ASCII, sem espaço nas pontas)
//   rgNorm(re)          {re, err}: o subconjunto seguro (casa igual em JS, jq, gawk e PCRE)
//   rgFlatten(tree)     nós em pré-ordem [{i,parent,depth,name,key,regex,err,view,leaf,orphan}]
//   rgAssign(tree, users[{login, region}])
//                       {nodes (+ órfãs), rows:[{login, site, nodes:[i…], flag}]} — flag x|o|r|p|-
//   rgMapTsv(res)       as linhas "login\tsede\tnós\tflag" (o var/regions-map.tsv do servidor)

// minúsculas SÓ ASCII (o jq só tem ascii_downcase): "GOIÂNIA" ≠ "Goiânia" — a prévia mostra a órfã
const clean = (s) => String(s == null ? '' : s).replace(/[\t\r\n]/g, ' ').replace(/^ +| +$/g, '');
export const rgKey = (s) => clean(String(s == null ? '' : s).replace(/[A-Z]/g, (c) => c.toLowerCase()));

const CLS = { d: '0-9', w: 'A-Za-z0-9_', s: ' \t' };

export function rgNorm(src) {
  // bk = o último item dentro de [...]: '' início, 'c' caractere, 'r' intervalo fechado, 'k' classe, 'd' hífen pendente
  const s = String(src == null ? '' : src);
  const n = s.length;
  const ch = (k) => (k < n ? s[k] : '');
  let o = '', br = false, bk = '', esc = false, q = false;
  const lit = (t) => { o += t; bk = bk === 'd' ? 'r' : 'c'; };
  const bad = (err) => ({ re: '', err });
  for (let k = 0; k < n; k++) {
    const x = s[k];
    if (/[\x00-\x1f\x7f]/.test(x)) return bad('control_char');
    if (x.charCodeAt(0) > 126) return bad('non_ascii');
    if (esc) {
      esc = false; q = false;
      if (x === 'd' || x === 'w' || x === 's') {
        if (br) { if (bk === 'd') return bad('ambiguous_range'); o += CLS[x]; bk = 'k'; } else o += '[' + CLS[x] + ']';
      } else if (x === 'D' || x === 'W' || x === 'S') { if (br) return bad('negated_class_in_bracket'); o += '[^' + CLS[x.toLowerCase()] + ']'; }
      else if (x === 'b' || x === 'B') return bad('word_boundary');
      else if (/^[A-Za-z0-9]$/.test(x)) return bad('escape');
      else if (br) lit((x === ']' || x === '\\' || x === '-' || x === '^' || x === '[') ? '\\' + x : x);
      else if (/^[.[\](){}*+?|^$\\]$/.test(x)) o += '\\' + x;
      else o += x;
      continue;
    }
    if (x === '\\') { esc = true; continue; }
    if (br) {
      if (x === ']' && bk === '') lit('\\]');
      else if (x === ']') { o += ']'; br = false; }
      else if (x === '^' && bk === '' && o.endsWith('[')) o += '^';
      else if (x === '[' && (ch(k + 1) === ':' || ch(k + 1) === '=' || ch(k + 1) === '.')) return bad('posix_class');
      else if (x === '[') lit('\\[');
      else if (x === '&' && ch(k + 1) === '&') return bad('class_intersection');
      else if (x === '-') {
        if (bk === '' || ch(k + 1) === ']') lit('-');
        else if (bk === 'c') { o += '-'; bk = 'd'; }
        else return bad('ambiguous_range');
      } else lit(x);
      continue;
    }
    if (x === '[') { o += '['; br = true; bk = ''; q = false; }
    else if (x === '(') {
      if (ch(k + 1) === '?') { if (ch(k + 2) === ':') { o += '('; k += 2; q = false; } else return bad('group_ext'); }
      else { o += '('; q = false; }
    } else if (x === '*' || x === '+' || x === '?') {
      if (ch(k + 1) === '?') return bad('lazy');
      if (q) return bad('double_quantifier');
      o += x; q = true;
    } else if (x === '{') {
      const m = /^\{[0-9]+(,[0-9]*)?\}/.exec(s.slice(k));
      if (!m) return bad('brace');
      if (Math.max(...m[0].match(/[0-9]+/g).map(Number)) > 100) return bad('brace');   // o gawk estoura em a{99999}
      if (ch(k + m[0].length) === '?') return bad('lazy');
      if (q) return bad('double_quantifier');
      o += m[0]; k += m[0].length - 1; q = true;
    } else if (x === '}') return bad('brace');
    else { o += x; q = false; }
  }
  if (esc) return bad('trailing_backslash');
  if (br) return bad('unclosed_bracket');
  try { new RegExp(o, 'i'); } catch { return bad('invalid'); }
  return { re: o, err: null };
}

const str = (v) => (v == null || v === false ? '' : String(v));

export function rgFlatten(tree) {
  const out = [];
  const walk = (arr, parent, depth, v) => {
    if (!Array.isArray(arr)) return;
    for (const nd of arr) {
      if (!nd || typeof nd !== 'object' || Array.isArray(nd)) continue;
      const view = v || nd.view === true;
      const i = out.length;
      out.push({ i, parent, depth, name: str(nd.name), rx: str(nd.regex), view });
      if (Array.isArray(nd.subregions)) walk(nd.subregions, i, depth + 1, view);
    }
  };
  walk(Array.isArray(tree) ? tree : [], -1, 0, false);
  return out.map((nd) => {
    const r = nd.rx === '' ? { re: '', err: null } : rgNorm(nd.rx);
    return { i: nd.i, parent: nd.parent, depth: nd.depth, name: nd.name, key: rgKey(nd.name), regex: r.re, err: r.err,
      view: nd.view, leaf: !out.some((c) => c.parent === nd.i && !c.view), orphan: false };
  });
}

// users: [{login, region}] — a população (o chamador tira as contas de papel). Ordem = a do servidor
// (logins em ordem de bytes), que decide o índice das sedes órfãs.
export function rgAssign(tree, users) {
  const nodes = rgFlatten(tree);
  const n = nodes.length;
  const byName = new Map();
  for (const nd of nodes) if (!nd.view && !byName.has(nd.key)) byName.set(nd.key, nd.i);
  const us = [...(users || [])].map((u) => ({ login: String(u.login), region: u.region }))
    .sort((a, b) => (a.login < b.login ? -1 : a.login > b.login ? 1 : 0));
  const syn = new Map();
  const rows = us.map((u) => {
    const ek = rgKey(u.region);
    if (ek !== '') {
      if (byName.has(ek)) return { login: u.login, site: byName.get(ek), flag: 'x' };
      if (!syn.has(ek)) {
        const i = n + syn.size;
        syn.set(ek, i);
        nodes.push({ i, parent: -1, depth: 0, name: clean(u.region), key: ek,
          regex: '', err: null, view: false, leaf: true, orphan: true });
      }
      return { login: u.login, site: syn.get(ek), flag: 'o' };
    }
    return { login: u.login, site: -1, flag: '-' };
  });
  const rx = nodes.slice(0, n).map((nd) => (nd.regex ? new RegExp(nd.regex, 'i') : null));
  const bd = new Array(rows.length).fill(-1);
  const dv = new Array(rows.length).fill(-1);         // o nó que a regex daria (a órfã pendura nele)
  for (let j = 0; j < n; j++) {                       // o nó mais fundo; pré-ordem desempata
    const nd = nodes[j];
    if (nd.view || !rx[j]) continue;
    rows.forEach((r, k) => {
      if (r.flag === 'x') return;
      if ((dv[k] < 0 || nd.depth > bd[k]) && rx[j].test(r.login)) { dv[k] = nd.i; bd[k] = nd.depth; }
    });
  }
  rows.forEach((r, k) => { if (r.flag === '-' && dv[k] >= 0) r.site = dv[k]; });
  rows.forEach((r, k) => {
    if (r.flag === '-' && r.site >= 0) r.flag = nodes[r.site].leaf ? 'r' : 'p';
    const mem = new Set();
    const s = r.site;
    const sk = s >= 0 ? nodes[s].key : '';
    const a2 = r.flag === 'o' ? dv[k] : -1;
    const ak = a2 >= 0 ? nodes[a2].key : '';
    if (s >= n) mem.add(s);                           // órfã: fora da árvore
    const inv = {};
    for (let j = n - 1; j >= 0; j--) {                // filhos antes dos pais (pré-ordem ao contrário)
      const nd = nodes[j];
      if (!inv[j]) {
        inv[j] = nd.view ? (nd.regex ? rx[j].test(r.login) : ((sk !== '' && nd.key === sk) || (ak !== '' && nd.key === ak)))
          : ((s >= 0 && (j === s || (sk !== '' && nd.key === sk))) || (a2 >= 0 && (j === a2 || nd.key === ak)));
      }
      if (inv[j]) { mem.add(j); const p = nd.parent; if (p >= 0 && !(nd.view && !nodes[p].view)) inv[p] = true; }
    }
    r.nodes = [...mem].sort((a, b) => a - b);
  });
  return { nodes, rows };
}

export const rgMapTsv = (res) => res.rows.map((r) => [r.login, r.site, r.nodes.join(','), r.flag].join('\t')).join('\n') + (res.rows.length ? '\n' : '');
