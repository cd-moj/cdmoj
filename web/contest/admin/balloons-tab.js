// contest/admin/balloons-tab.js — "Prova › Balões": cor de cada letra.
// O staff imprime a folha do balão com a cor desenhada (lib/print.sh); sem balloons.json vale a paleta
// padrão do ICPC (A–O; depois do O, cinza). Salva só a chave `colors` do POST /contest/admin/config (o
// handler é por-chave), que também passa à cor nova as tarefas de balão ainda não impressas.
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { makeColorsEditor } from '/shared/contest-config/index.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;

// o que a troca de cor fez com a fila do staff: as não impressas mudam; as JÁ impressas saíram na cor antiga
export function recolorNote(r) {
  if (!r) return '';
  let m = '';
  if (r.balloons_recolored) m += T(` — ${r.balloons_recolored} tarefa(s) de balão pendente(s) passaram à cor nova`, ` — ${r.balloons_recolored} pending balloon task(s) moved to the new colour`, ` — ${r.balloons_recolored} tarea(s) de globo pendiente(s) pasaron al color nuevo`);
  if (r.balloons_printed_old) m += T(` — atenção: ${r.balloons_printed_old} folha(s) de balão JÁ impressa(s) com a cor antiga (não entregues): confira com o staff`, ` — warning: ${r.balloons_printed_old} balloon sheet(s) ALREADY printed with the old colour (not delivered): check with the staff`, ` — atención: ${r.balloons_printed_old} hoja(s) de globo YA impresa(s) con el color anterior (no entregadas): verifícalo con el staff`);
  return m;
}

export function makeBalloonsTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', { class: 'section' });
  async function load() {
    panel.innerHTML = '';
    panel.append(el('h2', {}, T('🎈 Balões', '🎈 Balloons', '🎈 Globos')),
      el('p', { class: 'small muted' },
        T('Uma cor por letra: é o que sai desenhado na folha do balão que o staff entrega. Sem cores personalizadas vale a paleta padrão do ICPC (A a O; depois do O, cinza). Mudar uma cor atualiza as tarefas de balão ainda não impressas.',
          'One colour per letter: it is what gets drawn on the balloon sheet the staff delivers. With no custom colours, the default ICPC palette applies (A to O; after O, grey). Changing a colour updates the balloon tasks not yet printed.',
          'Un color por letra: es lo que se dibuja en la hoja de globo que entrega el staff. Sin colores personalizados se usa la paleta predeterminada del ICPC (A a O; después de la O, gris). Cambiar un color actualiza las tareas de globo todavía no impresas.')),
      el('p', { class: 'small muted' },
        T('Estas são as cores da rodada no ar. Para dar cores próprias a outra rodada, use Evento › Rodadas.',
          'These are the colours of the live round. To give another round its own colours, use Event › Rounds.',
          'Estos son los colores de la ronda en vivo. Para darle colores propios a otra ronda, usa Evento › Rondas.')));
    let cfg;
    try { cfg = await apiGet('/contest/admin/config?contest=' + enc(CONTEST), G); }
    catch (e) { panel.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ', 'Error: ') + (e.message || T('erro', 'error', 'error')))); return; }
    if (!(cfg.letters || []).length) {
      panel.append(el('div', { class: 'muted' }, T('O contest ainda não tem problemas — adicione em Prova › Problemas.', 'The contest has no problems yet — add them in Contest › Problems.', 'La competencia todavía no tiene problemas — agrégalos en Competencia › Problemas.')));
      return;
    }
    const ed = makeColorsEditor({ letters: cfg.letters || [], initial: cfg.colors || {} });
    const msg = el('div', { class: 'small' });
    const save = el('button', { class: 'btn' }, T('Salvar cores', 'Save colours', 'Guardar colores'));
    save.addEventListener('click', async () => {
      save.disabled = true; msg.className = 'small'; msg.textContent = T('Salvando…', 'Saving…', 'Guardando…');
      try {
        const r = await apiPost('/contest/admin/config?contest=' + enc(CONTEST), { colors: ed.getValue() }, G);
        msg.textContent = T('✓ salvo', '✓ saved', '✓ guardado') + recolorNote(r);
        if (r && r.balloons_printed_old) msg.className = 'small error-box';
      }
      catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed', 'fallido'); }
      save.disabled = false;
    });
    // voltar ao padrão = apagar o balloons.json (colors:null); o {} do editor não apaga mais nada
    const reset = el('button', { class: 'btn ghost danger', title: T('apaga as cores personalizadas e desliga o Sonic', 'deletes the custom colours and turns Sonic off', 'elimina los colores personalizados y desactiva el modo Sonic'), onclick: async () => {
      if (!confirm(T('Voltar às cores padrão? As cores personalizadas são apagadas e o modo Sonic desligado.', 'Back to the default colours? Custom colours are deleted and Sonic mode is turned off.', '¿Volver a los colores predeterminados? Los colores personalizados se eliminan y el modo Sonic se desactiva.'))) return;
      msg.className = 'small'; msg.textContent = '…';
      try {
        const r = await apiPost('/contest/admin/config?contest=' + enc(CONTEST), { colors: null }, G); await load();
        const m = recolorNote(r); if (m) panel.append(el('div', { class: 'small' + (r.balloons_printed_old ? ' error-box' : '') }, T('✓ cores padrão', '✓ default colours', '✓ colores predeterminados') + m));
      }
      catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed', 'fallido'); }
    } }, T('↺ Cores padrão', '↺ Default colours', '↺ Colores predeterminados'));
    panel.append(ed.el, el('div', { class: 'row', style: 'margin-top:.7rem;gap:.6rem' }, save, reset, msg));
  }
  return { panel, load };
}
