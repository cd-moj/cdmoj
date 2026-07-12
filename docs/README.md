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
- **[FLOW.md](FLOW.md)** — fluxo de comunicação: como uma submissão viaja do browser ao placar —
  spool, daemon `judged`, a fila/claim **pull** (`sched-lib.sh`), os juízes puxando por heartbeat
  e o placar.
- **[API.md](API.md)** — referência das rotas `/api/v1/...` (entrada/saída, auth, papéis).
  Versão de máquina: `../web/api/openapi.json` (servida em `/api/` na web).
- **[PACOTE.md](PACOTE.md)** — **fonte única do formato do pacote de problema**: o que é cada arquivo
  (enunciado, `tests/`, `sols/`, `scripts/`, `conf`), os metadados (`.moj-meta.json` e `.moj-id`), o
  que são **orgs** (acesso) e **coleções** (agrupamento), e o ciclo validar → calibrar → publicar.
  O roteiro prático de montar um pacote fica no `README.md` do **mojtools**.
- **[SCOREBOARD.md](SCOREBOARD.md)** — formato do TXT de placar e como adicionar um modo
  (`updatescore-<modo>.sh` + `score-<modo>.js`).
- **[DEPLOY.md](DEPLOY.md)** — nginx + fcgiwrap + units systemd (daemon `judged`, bot) + juízes
  **pull** e o subdomínio de contest.
- **[ADMIN.md](ADMIN.md)** — manual do administrador: instalação **do zero** num servidor limpo
  (podman/bare-metal), segredos e o **bootstrap do `treino` + primeira conta `.admin`**.
- **[PLAN.md](PLAN.md)** — plano original aprovado da reescrita (arquitetura, contratos,
  modos de placar, fases). Referência histórica da migração.

> A especificação de design original (telas/contratos) foi a base histórica para `web/` e os
> handlers de `server/`; hoje o contrato vivo é `docs/API.md` + `web/api/openapi.json`.

## Manuais de usuário

Voltados ao usuário final, em português simples e sem travessão:

- **[MANUAL-TREINO.md](MANUAL-TREINO.md)**: o aluno no Treino Livre (cadastro por Telegram, busca, enviar solução, perfil, estatísticas).
- **[MANUAL-CONTEST.md](MANUAL-CONTEST.md)**: o competidor num contest (entrar, enviar, placar, clarifications, impressão, backup).
- **[MANUAL-LINGUAGENS.md](MANUAL-LINGUAGENS.md)**: como enviar em cada linguagem e como funciona a entrada/saída, com exemplos reais.
- **[MANUAL-STAFF.md](MANUAL-STAFF.md)**: a equipe de sala (`.staff` e `.cstaff`): fila de impressão, balões, etiquetas, revelação por sede.
- **[MANUAL-JUIZ.md](MANUAL-JUIZ.md)**: os juízes (`.judge` e `.cjudge`): fila de avaliação, votos, conflitos, painel do chefe.

## Compilar em HTML

```sh
bash docs/build-html.sh     # -> docs/html/*.html + index.html  (usa pandoc)
```
