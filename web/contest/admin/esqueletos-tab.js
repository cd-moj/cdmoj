// Painel Prova › Esqueletos (módulo `esqueletos`) — o esqueleto de código que o editor embutido mostra ao time,
// por linguagem: o PADRÃO (o mesmo do treino, web/shared/languages.js — fonte única), um PERSONALIZADO deste
// contest ou VAZIO. Rota: /contest/admin/esqueletos (o servidor guarda só o que difere do padrão). O módulo
// exige o editor embutido; problema de submissão de função abre vazio sozinho (function_langs). A regra que o
// editor do time aplica é a de web/shared/editor-skeleton.js.
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { T } from '/shared/i18n.js';
import { createEditor } from '/shared/editor.js';
import { LANGUAGES, DEFAULT_SUBMIT_LANGUAGES, langById } from '/shared/languages.js';
import { swapIf, sigOf } from '/shared/admin-ui.js';
import { esqErrorText } from './modules.js';

const enc = encodeURIComponent;
const norm = (t) => String(t || '').replace(/\r\n/g, '\n').trim();
// o editor envia o arquivo como solution.java: classe PÚBLICA com outro nome = o javac recusa (CE)
const JAVA_PUBLIC = /public\s+(final\s+)?class/;

export function makeEsqueletosTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div');
  const head = el('div', { class: 'section' });
  const listBox = el('div', { class: 'section' });
  panel.append(head, listBox);

  // as linguagens que este contest oferece: a união das linguagens dos problemas (problema sem lista = as
  // padrão) + as que já têm configuração (p/ poderem voltar ao padrão)
  function contestLangs(problems, cfg) {
    const ids = new Set();
    (problems || []).forEach((p) => {
      const l = Array.isArray(p.languages) ? p.languages : [];
      (l.length ? l : DEFAULT_SUBMIT_LANGUAGES.map((x) => x.id)).forEach((id) => ids.add(id));
    });
    if (!ids.size) DEFAULT_SUBMIT_LANGUAGES.forEach((x) => ids.add(x.id));
    Object.keys(cfg || {}).forEach((id) => ids.add(id));
    const order = LANGUAGES.map((l) => l.id);
    return [...ids].sort((a, b) => ((order.indexOf(a) + 1) || 999) - ((order.indexOf(b) + 1) || 999) || a.localeCompare(b));
  }

  function langRow(id, cur, fnProbs, reload) {
    const L = langById(id), def = L.template || '';
    const mode0 = cur ? cur.mode : 'default';
    const sel = el('select', {},
      el('option', { value: 'default' }, T('padrão do MOJ', 'MOJ default', 'predeterminado del MOJ')),
      el('option', { value: 'custom' }, T('personalizado', 'custom', 'personalizado')),
      el('option', { value: 'off' }, T('sem esqueleto (abre vazio)', 'no skeleton (opens empty)', 'sin esqueleto (abre vacío)')));
    sel.value = mode0;
    const body = el('div', { style: 'margin-top:.4rem' });
    const warn = el('div', { class: 'small', style: 'color:#b8860b' });
    const msg = el('span', { class: 'small muted' });
    const save = el('button', { class: 'btn' }, T('Salvar', 'Save', 'Guardar'));
    let ed = null;
    const checkJava = () => {
      warn.textContent = (id === 'java' && ed && JAVA_PUBLIC.test(ed.getValue()))
        ? T('⚠ O editor envia o arquivo como solution.java: uma classe pública com outro nome dá Compilation Error para todos. Tire o public da classe.', '⚠ The editor sends the file as solution.java: a public class with another name gives Compilation Error to everyone. Remove public from the class.', '⚠ El editor envía el archivo como solution.java: una clase pública con otro nombre da Compilation Error a todos. Quita el public de la clase.')
        : '';
    };
    async function paint() {
      body.innerHTML = ''; ed = null; warn.textContent = '';
      if (sel.value === 'custom') {
        const mount = el('div', { class: 'editor-box', style: 'min-height:12rem' });
        body.append(mount, warn);
        ed = await createEditor(mount, { doc: cur && cur.mode === 'custom' ? cur.code : def, cm: L.cm, tab: 'indent' });
        mount.addEventListener('keyup', checkJava); checkJava();
      } else if (sel.value === 'default') {
        body.append(def
          ? el('pre', { class: 'small', style: 'margin:0;max-height:14rem;overflow:auto' }, def)
          : el('p', { class: 'small muted' }, T('Esta linguagem não tem esqueleto padrão: o editor abre vazio.', 'This language has no default skeleton: the editor opens empty.', 'Este lenguaje no tiene esqueleto predeterminado: el editor abre vacío.')));
      } else {
        body.append(el('p', { class: 'small muted' }, T('O editor abre vazio nesta linguagem.', 'The editor opens empty in this language.', 'El editor abre vacío en este lenguaje.')));
      }
    }
    sel.addEventListener('change', paint);
    save.addEventListener('click', async () => {
      let p;
      if (sel.value === 'custom') {
        const code = ed ? ed.getValue() : '';
        // igual ao padrão = padrão (o servidor guarda só o que difere)
        p = norm(code) === norm(def) ? { action: 'reset', lang: id } : { action: 'set', lang: id, code };
      } else p = { action: sel.value === 'off' ? 'off' : 'reset', lang: id };
      save.disabled = true; msg.textContent = T('salvando…', 'saving…', 'guardando…');
      try {
        await apiPost('/contest/admin/esqueletos?contest=' + enc(CONTEST), p, G);
        msg.textContent = T('salvo', 'saved', 'guardado'); reload();
      } catch (e) { msg.textContent = esqErrorText(e); }
      save.disabled = false;
    });
    const fn = fnProbs.filter((x) => x.langs.includes(id)).map((x) => x.letter);
    const state = { default: T('padrão', 'default', 'predeterminado'), custom: T('personalizado', 'custom', 'personalizado'), off: T('vazio', 'empty', 'vacío') }[mode0];
    const det = el('details', {},
      el('summary', {}, el('b', {}, L.label || id), ' — ', el('span', { class: 'small muted' }, state),
        fn.length ? el('span', { class: 'small muted' }, ' · ' + T('função em ', 'function in ', 'función en ') + fn.join(', ') + T(' (abre vazio)', ' (opens empty)', ' (abre vacío)')) : ''),
      el('div', { class: 'row', style: 'gap:.5rem;align-items:center;margin-top:.4rem' }, sel, save, msg), body);
    det.addEventListener('toggle', () => { if (det.open && !body.childNodes.length) paint(); });
    return det;
  }

  async function load() {
    let d, probs = [];
    try { d = await apiGet('/contest/admin/esqueletos?contest=' + enc(CONTEST), G); } catch (e) {
      head.innerHTML = ''; head.append(el('p', { class: 'error-box' }, esqErrorText(e))); return;
    }
    try { probs = (await apiGet('/contest/problems?contest=' + enc(CONTEST), G)).problems || []; } catch { /* sem a lista: as padrão */ }
    const fnProbs = probs.filter((p) => (p.function_langs || []).length).map((p) => ({ letter: p.short_name || p.problem_id, langs: p.function_langs }));
    swapIf(head, sigOf(d.module_on, d.editor_on, d.score_mode, fnProbs), () => el('div', {},
      el('h2', {}, T('📝 Esqueletos de código', '📝 Code skeletons', '📝 Esqueletos de código')),
      el('p', { class: 'muted' }, T(
        'O editor de código do time abre com o esqueleto da linguagem. Por linguagem, escolha o padrão do MOJ (o mesmo do treino), um esqueleto personalizado deste contest, ou nenhum. Trocar de linguagem só troca o texto enquanto ele ainda é o esqueleto intacto. Enviar o esqueleto sem mudar nada é recusado na tela; a trava de editor vazio continua valendo.',
        'The team code editor opens with the language skeleton. For each language, choose the MOJ default (the same as in training), a custom skeleton for this contest, or none. Changing the language only replaces the text while it is still the untouched skeleton. Submitting the skeleton without changes is refused on screen; the empty-editor check still applies.',
        'El editor de código del equipo abre con el esqueleto del lenguaje. Para cada lenguaje, elige el predeterminado del MOJ (el mismo del entrenamiento), un esqueleto personalizado de esta competencia, o ninguno. Cambiar de lenguaje solo reemplaza el texto mientras todavía es el esqueleto intacto. Enviar el esqueleto sin cambios se rechaza en pantalla; la verificación de editor vacío sigue valiendo.')),
      !d.editor_on ? el('p', { class: 'error-box' }, T('O editor de código no browser está desligado: o time não vê esqueleto nenhum. Ligue-o em Central › Regras.', 'The in-browser code editor is off: teams see no skeleton. Turn it on in Home › Rules.', 'El editor de código en el navegador está desactivado: los equipos no ven ningún esqueleto. Actívalo en Central › Reglas.')) : '',
      d.score_mode === 'icpc' ? el('p', { class: 'small', style: 'color:#b8860b' }, T('Contest em modo ICPC: na maratona o time costuma esperar o editor vazio.', 'Contest in ICPC mode: in a programming marathon teams usually expect an empty editor.', 'Competencia en modo ICPC: en una maratón los equipos suelen esperar el editor vacío.')) : '',
      fnProbs.length ? el('p', { class: 'small muted' }, T('Problemas de submissão de função abrem vazios nas linguagens do driver: ', 'Function-submission problems open empty in the driver languages: ', 'Los problemas de envío de función abren vacíos en los lenguajes del driver: ')
        + fnProbs.map((x) => x.letter + ' (' + x.langs.join(', ') + ')').join(' · ')) : ''));
    const langs = contestLangs(probs, d.langs);
    swapIf(listBox, sigOf(d.langs, langs, fnProbs), () => el('div', {},
      el('h3', { style: 'margin-top:0' }, T('Por linguagem', 'By language', 'Por lenguaje')),
      ...langs.map((id) => langRow(id, (d.langs || {})[id], fnProbs, load))));
  }

  return { panel, load };
}
