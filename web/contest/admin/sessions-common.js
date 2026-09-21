// contest/admin/sessions-common.js — o que Pessoas › Sessões e Máquinas › Anomalias têm em comum:
// os tipos de anomalia (rótulos/dicas), a pílula de severidade, a chave de máquina legível e a
// ação "deslogar time". Nada de DOM de painel aqui — cada painel monta o seu esqueleto.
import { el } from '/shared/ui.js';
import { apiPost } from '/shared/api.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;
export const REFRESH_MS = 30000;

// rótulos por tipo: fábrica preguiçosa (T() no topo congelaria o idioma antes do LOCALE)
export const KINDS = () => ({
  multi_session: { icon: '👥', label: T('2 sessões vivas', '2 live sessions'),
    hint: T('o mesmo time com sessão aberta em duas máquinas diferentes', 'the same team with a session open on two different machines') },
  machine_shared: { icon: '🖥️', label: T('máquina compartilhada', 'shared machine'),
    hint: T('dois ou mais times fizeram login na mesma máquina durante a prova', 'two or more teams logged in on the same machine during the contest') },
  sub_other_machine: { icon: '📤', label: T('submissão de outra máquina', 'submission from another machine'),
    hint: T('a submissão veio de uma máquina diferente da que fez o login (sessão levada para outra máquina)', 'the submission came from a machine other than the one that logged in (session carried to another machine)') },
  ua_mismatch: { icon: '🧭', label: T('UA fora da sede', 'UA off-site'),
    hint: T('sessão viva cujo navegador não é o da imagem da sede (entrou antes do gate ou por isenção)', 'live session whose browser is not the site image (logged in before the gate or by exemption)') },
  site_short: { icon: '🏫', label: T('sede sem máquina por time', 'site short of machines'),
    hint: T('na última coleta do nutellaboot a sede tem mais times presentes do que máquinas vistas', 'in the last nutellaboot collection the site has more present teams than machines seen') },
  switched: { icon: '🔁', label: T('trocou de máquina', 'switched machine'),
    hint: T('o time fez login em mais de uma máquina durante a prova (normal quando a máquina falha)', 'the team logged in on more than one machine during the contest (normal when a machine fails)') },
  session_event: { icon: '🧾', label: T('sessão derrubada', 'session ended'),
    hint: T('revogação pela sessão única, deslogar do admin ou deslogar UA divergente', 'revocation by single-session, admin logout or mismatched-UA logout') },
  site_lock: { icon: '🔒', label: T('trava de sede', 'site lock'),
    hint: T('IP da sede preso a este contest (reivindicação no login) ou pedido daquele IP a outro alvo bloqueado (403 site_locked)', 'site IP pinned to this contest (claim at login) or a request from that IP to another target blocked (403 site_locked)') },
});
export const SEV = () => ({ bad: T('grave', 'severe'), warn: T('atenção', 'attention'), info: T('info', 'info') });
export const sevPill = (s) => el('span', { class: 'pill ' + (s === 'bad' ? 'bad' : s === 'warn' ? 'warn' : '') }, SEV()[s] || s);
// chave de máquina legível: m:<mid>/<boot> -> "mid…/boot"; ip:x -> "ip x"
export const mk = (k) => {
  if (!k) return '—';
  // `m:<mid>` sem boot = máquina de identidade ESTÁVEL (agente novo do mlinux: o id vem do MAC)
  if (k.startsWith('m:')) { const [mid, boot] = k.slice(2).split('/'); return el('code', { title: k }, (mid || '').slice(0, 8) + '…' + (boot ? '/' + boot : '')); }
  if (k.startsWith('ip:')) return el('code', { title: k }, 'ip ' + k.slice(3));
  return el('code', {}, k);
};
export const mkText = (k) => (k || '').split(' → ').map((x) => x.startsWith('m:') ? x.slice(2, 10) + '…' + (x.split('/')[1] ? '/' + x.split('/')[1] : '') : x.replace(/^ip:/, 'ip ')).join(' → ');

// makeLogoutUser(CONTEST, G, reload) -> async (login) — confirma, chama logout-user e recarrega
export function makeLogoutUser(CONTEST, G, reload) {
  return async (login) => {
    if (!confirm(T(`Deslogar ${login} (todas as sessões)?`, `Log out ${login} (all sessions)?`))) return;
    try { await apiPost('/contest/admin/logout-user?contest=' + enc(CONTEST), { login }, G); await reload(); }
    catch (e) { alert(e.message || T('falha', 'failed')); }
  };
}
