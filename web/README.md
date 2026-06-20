# web/ — Frontend MOJ (JS modular, sem build)

Frontend estático servido **direto pelo nginx**. Sem framework, sem toolchain: **ES modules** +
CSS compartilhado. Cada página consome a API `/api/v1/...` via `shared/api.js`.

```
web/
├── shared/
│   ├── api.js           # cliente fetch (+ Bearer, tratamento de erro)
│   ├── auth.js          # login/token (localStorage), status
│   ├── i18n.js          # pt/en
│   ├── ui.css           # identidade visual (azul, balões, seções)
│   ├── editor.js        # CodeMirror 6 (ESM) — editor embutido
│   └── assets/          # logo_moj.png, flags/*.svg
├── index/               # home (notícias, contests, treino, top10)
├── treino/
│   ├── (busca)          # lista/busca fuzzy + filtro por tags
│   ├── problema/        # enunciado + editor CodeMirror + upload + histórico (polling)
│   └── stat/            # estatísticas do usuário (gráficos)
└── contest/
    ├── login/           # login full-screen, countdown, bandeiras
    ├── (main)           # problemas, submissão, balões, tabela de submissões
    ├── score/           # renderizadores por modo (icpc/obi/treino/heuristic/outro)
    ├── allsubmissions/  # admin
    ├── judge/           # veredicto final
    └── statistics/      # gráficos do contest
```

## Editor

CodeMirror 6 via ESM (sem build). O submit envia base64 do conteúdo do editor **ou** de um arquivo
enviado (upload mantido) + nome/extensão, para `POST /api/v1/submit`.

Referência de UX e contratos: [`../docs/PLAN.md`](../docs/PLAN.md) e a spec de design em
`../old/geracao-das-telas-do-moj.txt`.
