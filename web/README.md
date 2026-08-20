# web/ — Frontend MOJ (JS modular, sem build)

Frontend estático servido **direto pelo nginx**. Sem framework, sem toolchain: **ES modules** +
CSS compartilhado. Cada página consome a API `/api/v1/...` via `shared/api.js`.

```
web/
├── shared/              # o que TODA página usa
│   ├── api.js           # cliente fetch (+ Bearer, tratamento de erro)
│   ├── auth.js          # login/token (localStorage), status
│   ├── i18n.js          # T('pt','en') + i18n-dom.js (data-en no HTML estático)
│   ├── ui.css / ui.js   # identidade visual + el() e helpers de DOM (dom.js)
│   ├── editor.js        # CodeMirror 6 (ESM) — editor embutido
│   ├── contest-config/  # editores de config reusados na criação e no painel
│   └── assets/          # logo_moj.png, flags/*.svg
├── lib/                 # módulos reusados FORA da página (stats-view, charts,
│                        # contest-chrome) — o relatório offline inlina estes
├── index/               # home (notícias, contests, treino, top10)
├── noticias/ · status/  # notícias e a página de saúde da plataforma
├── contests/            # vitrine de contests + inscrição (/contests/inscricao/)
├── problemas/           # AUTORIA: editor de problema, gestão, painel, análise
├── treino/              # busca de problemas, problema/ (enunciado+editor),
│                        # perfil/, cadastro/, stat/
└── contest/             # a prova, por PAPEL
    ├── login/ · (main)  # login full-screen; problemas, submissão, balões
    ├── score/           # placar por modo (icpc/obi/treino/heuristic/outro) + revelação
    ├── judge/ · chief/  # veredicto final; painel do juiz-chefe (Situação, review)
    ├── staff/ · print/  # fila de balões e impressão
    ├── admin/           # painel = shell + <nome>-tab.js (4 grupos de painéis)
    ├── animeitor/       # mesa do TELÃO (fotos, músicas, chaves de webcast)
    ├── ajuda/           # tutoriais por papel (staff, cstaff, judge, cjudge, animeitor)
    ├── allsubmissions/  # admin/chief (completa) + judge/mon (anônima)
    ├── clarification/ · docs/ · badges/ · rounds/ · log/ · jplag/ · backup/
    └── statistics/      # gráficos do contest
```


## Editor

CodeMirror 6 via ESM (sem build). O submit envia base64 do conteúdo do editor **ou** de um arquivo
enviado (upload mantido) + nome/extensão, para `POST /api/v1/submit`.

Referência de UX e contratos: [`../docs/OVERVIEW.md`](../docs/OVERVIEW.md),
[`../docs/API.md`](../docs/API.md) e `../web/api/openapi.json`.
