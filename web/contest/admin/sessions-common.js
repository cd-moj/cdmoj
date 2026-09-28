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
  multi_session: { icon: '👥', label: T('2 sessões vivas', '2 live sessions', '2 sesiones activas'),
    hint: T('o mesmo time com sessão aberta em duas máquinas diferentes', 'the same team with a session open on two different machines', 'el mismo equipo con una sesión abierta en dos máquinas diferentes') },
  machine_shared: { icon: '🖥️', label: T('máquina compartilhada', 'shared machine', 'máquina compartida'),
    hint: T('dois ou mais times fizeram login na mesma máquina durante a prova', 'two or more teams logged in on the same machine during the contest', 'dos o más equipos iniciaron sesión en la misma máquina durante la competencia') },
  sub_other_machine: { icon: '📤', label: T('submissão de outra máquina', 'submission from another machine', 'envío desde otra máquina'),
    hint: T('a submissão veio de uma máquina diferente da que fez o login (sessão levada para outra máquina)', 'the submission came from a machine other than the one that logged in (session carried to another machine)', 'el envío vino de una máquina distinta de la que inició sesión (sesión llevada a otra máquina)') },
  ua_mismatch: { icon: '🧭', label: T('UA fora da sede', 'UA off-site', 'UA fuera de la sede'),
    hint: T('sessão viva cujo navegador não é o da imagem da sede (entrou antes do gate ou por isenção)', 'live session whose browser is not the site image (logged in before the gate or by exemption)', 'sesión activa cuyo navegador no es el de la imagen de la sede (inició sesión antes del control de acceso o por excepción)') },
  site_short: { icon: '🏫', label: T('sede sem máquina por time', 'site short of machines', 'sede con pocas máquinas'),
    hint: T('na última coleta do nutellaboot a sede tem mais times presentes do que máquinas vistas', 'in the last nutellaboot collection the site has more present teams than machines seen', 'en la última recolección de nutellaboot la sede tiene más equipos presentes que máquinas vistas') },
  switched: { icon: '🔁', label: T('trocou de máquina', 'switched machine', 'cambió de máquina'),
    hint: T('o time fez login em mais de uma máquina durante a prova (normal quando a máquina falha)', 'the team logged in on more than one machine during the contest (normal when a machine fails)', 'el equipo inició sesión en más de una máquina durante la competencia (normal cuando una máquina falla)') },
  session_event: { icon: '🧾', label: T('sessão derrubada', 'session ended', 'sesión finalizada'),
    hint: T('revogação pela sessão única, deslogar do admin ou deslogar UA divergente', 'revocation by single-session, admin logout or mismatched-UA logout', 'revocación por sesión única, cierre de sesión del admin o cierre de sesión por UA distinta') },
  site_lock: { icon: '🔒', label: T('trava de sede', 'site lock', 'bloqueo de sede'),
    hint: T('IP da sede preso a este contest (reivindicação no login) ou pedido daquele IP a outro alvo bloqueado (403 site_locked)', 'site IP pinned to this contest (claim at login) or a request from that IP to another target blocked (403 site_locked)', 'IP de la sede fijada a esta competencia (reclamada al iniciar sesión) o una solicitud de esa IP a otro destino bloqueada (403 site_locked)') },
  machine_event: { icon: '🖥', label: T('evento da máquina', 'machine event', 'evento de máquina'),
    hint: T('a máquina do mlinux reiniciou, parou de reportar ou voltou (avisado pelo nutellaboot). Ao lado, o time que estava nela.', 'the mlinux machine rebooted, stopped reporting or came back (reported by nutellaboot). Next to it, the team that was on it.', 'la máquina mlinux se reinició, dejó de reportar o volvió (informado por nutellaboot). Al lado, el equipo que estaba en ella.') },
  machine_alert: { icon: '🔌', label: T('alerta da máquina', 'machine alert', 'alerta de máquina'),
    hint: T('alerta que o agente do mlinux levantou na máquina e o nutellaboot avisou: pendrive, celular ou rede por USB, identidade repetida. Fica aberto até alguém dispensar no nutellaboot.', 'alert raised by the mlinux agent on the machine and reported by nutellaboot: USB storage, phone or USB network, duplicate identity. It stays open until someone dismisses it in nutellaboot.', 'alerta generada por el agente de mlinux en la máquina e informada por nutellaboot: almacenamiento USB, teléfono o red por USB, identidad duplicada. Queda abierta hasta que alguien la descarte en nutellaboot.') },
});
export const SEV = () => ({ bad: T('grave', 'severe', 'grave'), warn: T('atenção', 'attention', 'atención'), info: T('info', 'info', 'info') });
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
    if (!confirm(T(`Deslogar ${login} (todas as sessões)?`, `Log out ${login} (all sessions)?`, `¿Cerrar sesión de ${login} (todas las sesiones)?`))) return;
    try { await apiPost('/contest/admin/logout-user?contest=' + enc(CONTEST), { login }, G); await reload(); }
    catch (e) { alert(e.message || T('falha', 'failed', 'fallido')); }
  };
}
