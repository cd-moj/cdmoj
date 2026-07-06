// shared/contest-config/settings-editor.js — editor das CONFIGURAÇÕES do contest (toggles do
// /contest/admin/settings + linguagens + gate de UA + placar completo), compartilhado entre a
// aba Configurações do admin e o passo "Opções" do wizard de criação (paridade real: é o MESMO
// editor). mode:'admin' inclui nome/início/fim; mode:'create' os omite (ficam no passo Dados)
// e acrescenta a PRIORIDADE de julgamento ('super' só aparece p/ admin do treino).
// Sem botão de salvar próprio — quem monta decide o que fazer com getValue().
import { el } from '/shared/ui.js';
import { makeLangPicker } from './lang-picker.js';
import { toLocalDT, dtToEpoch } from './util.js';

const field = (l, inp) => el('div', { class: 'field' }, el('label', {}, l), inp);
const chk = (l, c) => el('div', { class: 'field' }, el('label', { style: 'font-weight:400' }, c, ' ' + l));
const mkBool = (v) => { const c = el('input', { type: 'checkbox' }); c.checked = !!v; return c; };
const PRIORITY_LABEL = {
  'lista-publica': 'Lista pública (padrão)', 'lista-privada': 'Lista privada',
  prova: 'Prova (julga antes das listas)', super: 'Super (admin; fura toda fila)',
};

const PENALTY_OPTS = [
  ['wa', 'Wrong Answer'], ['tle', 'Time Limit Exceeded'], ['mle', 'Memory Limit Exceeded'],
  ['rte', 'Runtime Error'], ['ce', 'Compilation Error'],
];
const PENALTY_DEFAULT = ['wa', 'tle', 'mle', 'rte'];

// contestMode: modo do placar ('icpc'|'obi'|…) — a seção de penalidade só existe no icpc.
// O wizard permite voltar e trocar o modo: use setContestMode() no remount.
export function makeSettingsEditor({ value = {}, mode = 'admin', isAdmin = false, contestMode = '' } = {}) {
  const s = value || {};
  const isCreate = mode === 'create';
  const name = el('input', { value: s.name || '' });
  const start = el('input', { type: 'datetime-local', value: s.start ? toLocalDT(s.start) : '' });
  const end = el('input', { type: 'datetime-local', value: s.end ? toLocalDT(s.end) : '' });
  const loginStart = el('input', { type: 'datetime-local', value: s.login_start ? toLocalDT(s.login_start) : '' });
  const freeze = el('input', { type: 'datetime-local', value: s.freeze ? toLocalDT(s.freeze) : '' });
  const locale = el('select', {}, el('option', { value: 'pt' }, 'Português'), el('option', { value: 'en' }, 'English'));
  locale.value = s.locale || 'pt';
  const prios = ['lista-publica', 'lista-privada', 'prova', ...(isAdmin ? ['super'] : [])];
  const priority = el('select', {}, ...prios.map((p) => el('option', { value: p }, PRIORITY_LABEL[p] || p)));
  priority.value = prios.includes(s.priority) ? s.priority : 'lista-publica';
  const loginEnabled = mkBool(s.login_enabled !== false), showCode = mkBool(s.show_code ?? s.showcode),
    showLog = mkBool(s.show_log !== false), showEditor = mkBool(s.show_editor !== false),
    allowLate = mkBool(s.allow_late), scoreAnon = mkBool(s.score_anon),
    showTL = mkBool(s.show_tl !== false), allowBackup = mkBool(s.allow_backup !== false),
    allowPrint = mkBool(s.allow_print !== false), manualVerdict = mkBool(s.manual_verdict === true),
    secret = mkBool(s.secret === true);
  const ua = el('input', { value: s.login_ua_substring || '', placeholder: 'substring do UA (vazio = sem gate)' });
  const penMin = el('input', { type: 'number', min: '0', step: '1', style: 'max-width:100px',
    value: String(Number.isInteger(s.penalty_minutes) ? s.penalty_minutes : 20) });
  const pvSel = new Set(Array.isArray(s.penalty_verdicts) ? s.penalty_verdicts : PENALTY_DEFAULT);
  const penChecks = PENALTY_OPTS.map(([code, label]) => ({ code, box: mkBool(pvSel.has(code)), label }));
  const langs = makeLangPicker(s.languages || []);
  const fullUsers = el('input', { value: (s.score_full_users || []).join(' '), placeholder: 'logins (espaço) — além de .admin/.judge/.cjudge', style: 'width:100%' });

  let cmode = contestMode;
  const penaltySec = el('div', {},
    el('h3', { style: 'margin:1rem 0 .3rem' }, '⏱ Penalidade (placar ICPC)'),
    field('Minutos somados por tentativa não aceita antes do Accepted', penMin),
    el('p', { class: 'muted small' }, 'Verdicts que contam penalidade (Judge Error e submissões pendentes nunca contam):'),
    ...penChecks.map((p) => chk(p.label, p.box)));
  const syncPen = () => { penaltySec.style.display = cmode === 'icpc' ? '' : 'none'; };
  syncPen();

  const box = el('div', {});
  if (!isCreate) {
    box.append(field('Nome', name),
      el('div', { class: 'grid2' }, field('Início', start), field('Fim', end)));
  }
  box.append(
    el('div', { class: 'grid2' }, field('Abertura do login (tela de espera)', loginStart), field('Freeze do placar', freeze)),
    isCreate ? el('div', { class: 'grid2' }, field('Idioma', locale), field('Prioridade no julgamento', priority)) : field('Idioma', locale),
    chk('Login habilitado', loginEnabled),
    chk('Permitir auto-cadastro de novos usuários (late users)', allowLate),
    chk('Mostrar o código das submissões (a todos)', showCode),
    chk('Usuário pode ver o log de julgamento', showLog),
    chk('Editor de código no browser disponível', showEditor),
    chk('Mostrar o tempo-limite dos problemas aos usuários', showTL),
    chk('Permitir backup de arquivos pelos usuários', allowBackup),
    chk('Permitir pedidos de impressão pelos usuários (.staff)', allowPrint),
    chk('Veredicto manual (2 juízes decidem; daemon segura o veredicto)', manualVerdict),
    chk('Placar anônimo (esconde desempenho individual)', scoreAnon),
    chk('🕵️ SUPER SECRETO — fora da home/arquivo/status; placar e visual exigem login (a tela de login continua funcionando p/ quem tem o link)', secret),
    field('Gate de login por substring de UA (só não-privilegiados)', ua),
    penaltySec,
    el('h3', { style: 'margin:1rem 0 .3rem' }, '💻 Linguagens permitidas no contest'),
    el('p', { class: 'muted small' }, 'Marque as permitidas. Nenhuma marcada = todas. (Pode ser refinado por problema na aba Problemas.)'),
    langs.el,
    el('h3', { style: 'margin:1rem 0 .3rem' }, '👁️ Placar completo (sem freeze)'),
    el('p', { class: 'muted small' }, 'Quem vê o placar real mesmo durante o freeze: .admin, .judge e .cjudge (juiz-chefe) sempre; some outros logins aqui.'),
    fullUsers);

  function getValue() {
    return {
      ...(isCreate ? { priority: priority.value } : {
        name: name.value.trim() || undefined,
        ...(start.value ? { start: dtToEpoch(start.value) } : {}),
        ...(end.value ? { end: dtToEpoch(end.value) } : {}),
      }),
      ...(loginStart.value ? { login_start: dtToEpoch(loginStart.value) } : {}),
      ...(freeze.value ? { freeze: dtToEpoch(freeze.value) } : {}),
      locale: locale.value, login_enabled: loginEnabled.checked,
      show_code: showCode.checked, show_log: showLog.checked, show_editor: showEditor.checked,
      allow_late: allowLate.checked, score_anon: scoreAnon.checked, show_tl: showTL.checked,
      allow_backup: allowBackup.checked, allow_print: allowPrint.checked,
      manual_verdict: manualVerdict.checked, secret: secret.checked, login_ua_substring: ua.value,
      languages: langs.get(),
      score_full_users: fullUsers.value.trim() ? fullUsers.value.trim().split(/\s+/) : [],
      ...(cmode === 'icpc' ? {
        penalty_minutes: penMin.value.trim() === '' ? 20 : Math.max(0, parseInt(penMin.value, 10) || 0),
        penalty_verdicts: penChecks.filter((p) => p.box.checked).map((p) => p.code),
      } : {}),
    };
  }
  return { el: box, getValue, setContestMode: (m) => { cmode = m; syncPen(); } };
}
