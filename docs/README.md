# docs/ — Documentação do MOJ

Índice da documentação da versão **API-first** do MOJ. Para ler em HTML (com TOC e
navegação), rode `bash docs/build-html.sh` e abra `docs/html/index.html`.

> **Mantenha em dia (doc atrasada = bug):** toda mudança de comportamento ou contrato
> atualiza a doc no **mesmo commit** — rotas/campos em [API.md](API.md) **e** em
> `../web/api/openapi.json` (os dois em sincronia); arquitetura/fluxo em
> [OVERVIEW.md](OVERVIEW.md)/[FLOW.md](FLOW.md); regras de trabalho nos `CLAUDE.md`.

- **[OVERVIEW.md](OVERVIEW.md)** — **comece aqui.** Visão geral: arquitetura, estrutura
  do repositório, camada de API, frontend e tudo o que existe (treino, criação de contest,
  ambiente de contest, juiz/daemons).
- **[FLOW.md](FLOW.md)** — fluxo de comunicação: como uma submissão viaja do browser ao
  placar, o spool, o daemon `judged`, o gateway de juiz (mock/local/cluster), resultado por
  push (`result-sink`), heartbeat de workers (`register`) e o cluster `:27000`.
- **[API.md](API.md)** — referência das rotas `/api/v1/...` (entrada/saída, auth, papéis).
  Versão de máquina: `../web/api/openapi.json` (servida em `/api/` na web).
- **[SCOREBOARD.md](SCOREBOARD.md)** — formato do TXT de placar e como adicionar um modo
  (`updatescore-<modo>.sh` + `score-<modo>.js`).
- **[DEPLOY.md](DEPLOY.md)** — nginx + fcgiwrap + units systemd (daemons, master/worker do
  juiz, bot) e o subdomínio de contest.
- **[PLAN.md](PLAN.md)** — plano original aprovado da reescrita (arquitetura, contratos,
  modos de placar, fases). Referência histórica da migração.

> A especificação de design original (telas/contratos) foi a base histórica para `web/` e os
> handlers de `server/`; hoje o contrato vivo é `docs/API.md` + `web/api/openapi.json`.

## Compilar em HTML

```sh
bash docs/build-html.sh     # -> docs/html/*.html + index.html  (usa pandoc)
```
