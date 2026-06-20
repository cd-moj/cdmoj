# docs/ — Documentação do MOJ

- **[`PLAN.md`](PLAN.md)** — plano aprovado da reescrita (arquitetura, contratos de API, modos de
  placar, fases e verificação). É a fonte da verdade da migração.
- **Especificação das telas / API** — `../old/geracao-das-telas-do-moj.txt`: sessão de design com
  181 prompts que define cada página (home, treino, problema, contest, score, admin, juiz) e o
  formato exato de cada JSON/TXT retornado pela API. Base para `web/` e para os handlers de `server/`.

## A documentar aqui (conforme implementação)

- `API.md` — referência das rotas `/api/v1/...` (entrada/saída, auth, exemplos `curl`).
- `SCOREBOARD.md` — formato do TXT de placar e como adicionar um novo modo
  (`updatescore-<modo>.sh` + `score-<modo>.js`).
- `DEPLOY.md` — nginx + fcgiwrap + units systemd (daemons, master/worker do juiz, bot).
