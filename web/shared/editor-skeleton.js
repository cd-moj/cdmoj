// shared/editor-skeleton.js — o ESQUELETO de código que o editor do aluno mostra ao abrir e ao trocar de
// linguagem. Funções PURAS (sem DOM): treino (web/treino/problema/problema.js) e contest (web/contest/
// contest.js, módulo `esqueletos`) decidem com elas, e o smoke-esqueletos.gjs.sh as exercita.
// Desenho original de Alex Orozco (IFSul, issue #40); aqui ganhou o esqueleto POR CONTEST.
//
// cfg = { templates: {<lang>: '<código>'}, off: ['<lang>'], functionLangs: ['<lang>'] }
//   • functionLangs (o `function_langs` do problema — FUNCTION_LANGS do conf, docs/PACOTE.md): ali o
//     aluno envia SÓ a função; o editor começa VAZIO (o `main` do esqueleto daria CE por main duplicado);
//   • off: linguagem que o admin do contest deixou sem esqueleto (começa vazia);
//   • templates: o esqueleto personalizado do contest; ausente = o PADRÃO, o `template` de
//     shared/languages.js (fonte única do padrão — o servidor guarda só os personalizados).
// Trocar de linguagem só troca o texto enquanto ele é vazio ou um esqueleto INTACTO; código digitado fica.
// O contest recusa enviar o esqueleto intacto (isSkeleton): sem isso a trava de "editor vazio" nunca
// dispararia e um clique acidental mandaria o `main` puro (WA com penalidade).
import { LANGUAGES, langById } from './languages.js';

const norm = (t) => String(t || '').replace(/\r\n/g, '\n').trim();

// o esqueleto que o editor mostra para `langId` ('' = começa vazio)
export function skeletonFor(langId, cfg = {}) {
  if ((cfg.functionLangs || []).includes(langId) || (cfg.off || []).includes(langId)) return '';
  const t = cfg.templates || {};
  if (Object.prototype.hasOwnProperty.call(t, langId)) return String(t[langId] || '');
  return (langById(langId) || {}).template || '';
}

// o texto é um esqueleto INTACTO — o padrão de qualquer linguagem ou um personalizado do contest?
// (vazio não é esqueleto: quem trata o vazio é a trava de "editor vazio")
export function isSkeleton(txt, cfg = {}) {
  const t = norm(txt);
  if (!t) return false;
  if (LANGUAGES.some((l) => l.template && norm(l.template) === t)) return true;
  return Object.values(cfg.templates || {}).some((c) => norm(c) !== '' && norm(c) === t);
}

// o que o editor passa a mostrar ao trocar para `langId`
export function docOnLangChange(cur, langId, cfg = {}) {
  return (!norm(cur) || isSkeleton(cur, cfg)) ? skeletonFor(langId, cfg) : cur;
}

// a configuração do contest como o /contest/userinfo a serve (`code_templates`), mais as linguagens de
// função do problema. Módulo desligado (ou servidor antigo, sem o campo) = null: o editor abre vazio e
// mantém o texto ao trocar de linguagem, como sempre foi.
export function contestSkeletonCfg(codeTemplates, functionLangs) {
  if (!codeTemplates || codeTemplates.on !== true) return null;
  const langs = codeTemplates.langs || {};
  const templates = {}, off = [];
  for (const [id, v] of Object.entries(langs)) {
    if (v && v.mode === 'off') off.push(id);
    else if (v && v.mode === 'custom' && typeof v.code === 'string') templates[id] = v.code;
  }
  return { templates, off, functionLangs: functionLangs || [] };
}
