// treino/ajuda/ajuda.js — "Como enviar uma solução": tabela de linguagens + template de código.
//
// A tabela é GERADA de shared/languages.js (a MESMA lista que o dropdown de submissão usa), e o
// esqueleto mostrado é o MESMO campo `template` que o editor insere. Linguagem nova em
// languages.js aparece aqui sozinha: não há lista duplicada p/ envelhecer.
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { contestHost } from '/shared/contest-host.js';
import { LANGUAGES, DEFAULT_SUBMIT_LANGUAGES, langById } from '/shared/languages.js';
import { EXEMPLOS } from './exemplos.js';

// Observação por linguagem (3ª coluna). Chaveada pelo id; linguagem sem entrada fica com a célula
// vazia (nunca quebra). Montada dentro da função p/ o T() ler o idioma no momento do render.
const notas = () => ({
  c:     T('gcc, com -O2 -static. É a linguagem padrão.', 'gcc, with -O2 -static. This is the default language.', 'gcc, con -O2 -static. Es el lenguaje predeterminado.'),
  cpp:   T('g++ -O2 -static, padrão gnu++20. #include <bits/stdc++.h> funciona.', 'g++ -O2 -static, gnu++20 standard. #include <bits/stdc++.h> works.', 'g++ -O2 -static, estándar gnu++20. #include <bits/stdc++.h> funciona.'),
  py:    T('Roda em pypy3 (não é o CPython). Erro de sintaxe vira Compilation Error.', 'Runs on pypy3 (not CPython). A syntax error becomes a Compilation Error.', 'Se ejecuta en pypy3 (no es CPython). Un error de sintaxis se convierte en Compilation Error.'),
  java:  T('Deixe a classe sem public (veja o aviso mais abaixo).', 'Keep the class without public (see the warning below).', 'Deja la clase sin public (mira el aviso más abajo).'),
  kt:    T('Leia com readLine() a cada linha, dentro de fun main().', 'Read with readLine() per line, inside fun main().', 'Lee con readLine() por línea, dentro de fun main().'),
  rs:    T('Compilador rustc.', 'The rustc compiler.', 'El compilador rustc.'),
  go:    T('Compilado com gccgo. Precisa de package main e func main().', 'Compiled with gccgo. Needs package main and func main().', 'Compilado con gccgo. Necesita package main y func main().'),
  js:    T('Executado com node.', 'Executed with node.', 'Ejecutado con node.'),
  hs:    T('Compilador GHC.', 'The GHC compiler.', 'El compilador GHC.'),
  ml:    T('OCaml. Leia com read_int() ou read_line().', 'OCaml. Read with read_int() or read_line().', 'OCaml. Lee con read_int() o read_line().'),
  pas:   T('Free Pascal (fpc). Leia com readln e escreva com writeln.', 'Free Pascal (fpc). Read with readln, write with writeln.', 'Free Pascal (fpc). Lee con readln y escribe con writeln.'),
  pl:    T('É PROLOG, não Perl. SWI-Prolog, e você define um predicado main.', 'This is PROLOG, not Perl. SWI-Prolog, and you define a main predicate.', 'Es PROLOG, no Perl. SWI-Prolog, y defines un predicado main.'),
  cs:    T('C# com Mono. Leia com Console.ReadLine().', 'C# on Mono. Read with Console.ReadLine().', 'C# con Mono. Lee con Console.ReadLine().'),
  sh:    T('bash.', 'bash.', 'bash.'),
  apl:   T('Dyalog APL.', 'Dyalog APL.', 'Dyalog APL.'),
  spim:  T('Assembly MIPS, no simulador spim.', 'MIPS assembly, on the spim simulator.', 'Ensamblador MIPS, en el simulador spim.'),
  riscv: T('Assembly RISC-V, no simulador rars.', 'RISC-V assembly, on the rars simulator.', 'Ensamblador RISC-V, en el simulador rars.'),
});

function renderTabela() {
  const nota = notas();
  const tb = el('table', { class: 'moj' },
    el('thead', {}, el('tr', {},
      el('th', { style: 'width:5.5rem' }, T('id (extensão)', 'id (extension)', 'id (extensión)')),
      el('th', { style: 'width:9rem' }, T('Linguagem', 'Language', 'Lenguaje')),
      el('th', {}, T('Observação', 'Notes', 'Observaciones')))),
    el('tbody', {}, ...DEFAULT_SUBMIT_LANGUAGES.map((l) => el('tr', {},
      el('td', {}, el('code', {}, l.id), ...((l.exts || []).length > 1
        ? [el('div', { class: 'small muted' }, (l.exts || []).map((e) => '.' + e).join(', '))] : [])),
      el('td', {}, l.label),
      el('td', {}, nota[l.id] || '')))));
  document.getElementById('langTable').append(tb);

  const exoticas = LANGUAGES.filter((l) => l.optIn);
  if (exoticas.length) {
    const n = document.getElementById('exoticNote');
    n.append(
      T('Existem ainda linguagens exóticas (', 'There are also exotic languages (', 'También existen lenguajes exóticos ('),
      ...exoticas.flatMap((l, i) => [i ? ', ' : '', el('code', {}, l.id)]),
      T('), que só aparecem no menu quando o problema as exige. Você não as encontra no dia a dia: elas servem a disciplinas específicas.',
        '), which only show up in the dropdown when a problem requires them. You will not run into them day to day: they serve specific courses.',
        '), que solo aparecen en el menú cuando el problema los exige. No los encontrarás en el día a día: sirven para cursos específicos.'));
  }
}

// bloco de código com cabeçalho + botão de copiar
function bloco(titulo, codigo, vazio) {
  const pre = el('pre', { class: 'code' }, el('code', {}, codigo));
  const btn = el('button', { class: 'btn ghost', type: 'button' }, T('Copiar', 'Copy', 'Copiar'));
  btn.addEventListener('click', async () => {
    const antes = btn.textContent;
    try {
      await navigator.clipboard.writeText(codigo);
      btn.textContent = T('Copiado!', 'Copied!', '¡Copiado!');
    } catch {
      // sem permissão de clipboard (http, ou o browser recusou): seleciona p/ o Ctrl+C do usuário
      const sel = window.getSelection();
      const r = document.createRange();
      r.selectNodeContents(pre);
      sel.removeAllRanges(); sel.addRange(r);
      btn.textContent = T('Selecionado, use Ctrl+C', 'Selected, press Ctrl+C', 'Seleccionado, usa Ctrl+C');
    }
    setTimeout(() => { btn.textContent = antes; }, 2000);
  });
  return el('div', {},
    el('div', { class: 'code-head' }, el('h4', {}, titulo), codigo ? btn : null),
    codigo ? pre : el('p', { class: 'small muted', style: 'margin:0' }, vazio));
}

function renderTemplates() {
  const host = document.getElementById('tpl');
  const sel = el('select', {}, ...DEFAULT_SUBMIT_LANGUAGES.map((l) => el('option', { value: l.id }, l.label)));
  const panes = el('div', {});

  const pinta = () => {
    const l = langById(sel.value);
    const exemplo = EXEMPLOS[l.id] || '';
    panes.innerHTML = '';
    panes.append(
      bloco(T('Esqueleto que o editor te dá', 'The skeleton the editor gives you', 'El esqueleto que te da el editor'), (l.template || '').trimEnd(),
            T('Esta linguagem não tem esqueleto: o editor abre vazio.', 'This language has no skeleton: the editor opens empty.', 'Este lenguaje no tiene esqueleto: el editor se abre vacío.')),
      bloco(T('Solução completa do problema acima', 'Complete solution to the problem above', 'Solución completa del problema anterior'), exemplo.trimEnd(),
            T('Ainda não há uma solução pronta nesta linguagem. Comece pelo esqueleto acima e siga a dica da tabela de linguagens.',
              'There is no ready-made solution in this language yet. Start from the skeleton above and follow the hint in the language table.',
              'Todavía no hay una solución lista en este lenguaje. Empieza por el esqueleto anterior y sigue la pista de la tabla de lenguajes.')));
  };
  sel.addEventListener('change', pinta);

  host.append(
    el('div', { class: 'lang-pick' }, el('label', {}, T('Linguagem: ', 'Language: ', 'Lenguaje: ')), sel),
    panes);
  pinta();
}

// Cabeçalho: site x contest. Esta página é a ÚNICA fora de /contest/ que o contest-guard deixa
// abrir num subdomínio de prova (o competidor precisa dela). Lá dentro ela veste o topbar do
// contest e obedece o LOCALE da prova — e por isso o header é resolvido ANTES do render: o T()
// lê o idioma na hora em que a tabela e os blocos de código são construídos.
async function mountHeader() {
  const cid = contestHost();
  if (!cid) {
    document.getElementById('contestHeader').remove();
    document.getElementById('contestNavWrap').remove();
    await import('/shared/site-header.js');   // auto-monta no #siteHeader
    return;
  }
  document.getElementById('siteHeader').remove();
  document.getElementById('contestHeader').classList.remove('hidden');
  document.getElementById('contestNavWrap').classList.remove('hidden');
  const { initContestShell } = await import('/shared/contest-shell.js');
  try { await initContestShell(cid); } catch { /* sem nav/countdown: a instrução é o que importa */ }
}

await mountHeader();
renderTabela();
renderTemplates();
