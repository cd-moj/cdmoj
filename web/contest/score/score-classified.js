// Classificação PUBLICADA p/ as próximas fases → o que o placar mostra (um chip por ESTÁGIO: o time que vai à
// Final Brasileira E à PDA mostra os dois). O texto vem do servidor (/contest/classification): `chip` e os
// rótulos de via (`labels`, pt/en/es, do catálogo score/classify-catalog.json) — nada de mapa fixo aqui.
// Times de fora do placar (chave `ext:`) não chegam pela rota; o filtro abaixo é a 2ª trava. Puro: testado
// por smoke-score-classified.gjs.sh.
import { T } from '/shared/i18n.js';

// pickLabel({pt,en,es}|texto) — o rótulo no idioma da interface (es ausente cai no en, en no pt)
export function pickLabel(o) {
  if (o == null) return '';
  if (typeof o !== 'object') return String(o);
  return T(o.pt || '', o.en || o.pt || '', o.es || o.en || o.pt || '');
}

// classifiedMap(resp) -> {login: [{id, chip, via, sede, draft, stage}]} | null
//   via   = o rótulo CURTO da via (short), ou o id cru se o estágio não traz rótulo — nunca some;
//   stage = "Nome, Local — quando" (o tooltip).
export function classifiedMap(resp) {
  const out = {};
  const stages = resp && Array.isArray(resp.stages) ? resp.stages : [];
  stages.forEach((st) => {
    const labels = st.labels || {};
    const stage = [st.name, st.venue].filter(Boolean).join(', ') + (st.when ? ' — ' + st.when : '');
    Object.entries(st.teams || {}).forEach(([lg, v]) => {
      if (lg.startsWith('ext:')) return;
      const L = labels[v.via];
      const via = L ? pickLabel(L.short || L) : String(v.via || '');
      (out[lg] = out[lg] || []).push({ id: st.id, chip: String(st.chip || st.name || st.id || ''), via,
        sede: v.sede || '', draft: !!st.draft, stage });
    });
  });
  return Object.keys(out).length ? out : null;
}
