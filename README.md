# MOJ — Melhor Online Judge

Sistema de correção automática de algoritmos (`moj.naquadah.com.br`). Este repositório está em
**migração** para uma arquitetura **API-first** (nginx + backend bash + frontend estático modular),
com placares multi-modo e um cluster de juiz distribuído. O plano completo está em
[`docs/PLAN.md`](docs/PLAN.md).

## Layout

```
moj/
├── server/        # BACKEND web (bash, atrás do nginx + fcgiwrap)
│   ├── api/v1/    #   API versionada: router.sh + lib/ + handlers/
│   ├── daemons/   #   daemons (submit assíncrono, inotify)
│   ├── judge-gw/  #   gateway para o escalonador (julgador/corrige/enviar-*)
│   ├── score/     #   geradores de placar por modo (updatescore-<modo>.sh)
│   └── etc/       #   configs (nginx/, systemd/)
├── web/           # FRONTEND estático (JS modular, sem build — nginx serve direto)
│   ├── shared/    #   api.js, auth.js, i18n.js, ui.css, editor.js (CodeMirror) + assets/
│   ├── index/     #   home
│   ├── treino/    #   busca, problema (editor), stat do usuário
│   └── contest/   #   login, score, allsubmissions, judge, statistics
├── judge/         # CLUSTER DE JUIZ distribuído (master/escalonador + workers)
├── mojinho-bot/   # Bot do Telegram (será integrado como cliente da API)
├── mojtools/      # Engine de execução/sandbox (bubblewrap) — não mexer por ora
├── contests/      # DADOS dos contests (fonte da verdade — inalterado na migração)
├── docs/          # PLAN.md (plano aprovado) + documentação da API/placar
└── old/           # ARQUIVO do sistema legado/referência (ver old/README.md)
```

## Princípios da migração

- **Não quebrar** os contests atuais: o sistema novo lê o mesmo `contests/<id>/` do antigo.
- **Bash + arquivos** sempre que possível; mudar de linguagem só quando necessário.
- **Tudo via API**: as interfaces consomem rotas `/api/v1/...` (sem CGI acoplado ao HTML).
- Evolução **incremental**, página a página; o Apache antigo roda em paralelo até o fim.

## Status

Em implementação. Fases e prioridades em [`docs/PLAN.md`](docs/PLAN.md) (a Fase 1 é a camada de API).
