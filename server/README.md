# server/ — Backend MOJ (bash, atrás do nginx + fcgiwrap)

Backend **API-first** em bash. O nginx serve `../web/` estático e faz `fastcgi_pass` para o
`fcgiwrap`, que executa o `api/v1/router.sh`.

```
server/
├── api/v1/
│   ├── router.sh        # front-controller único (PATH_INFO + método) → handler
│   ├── lib/             # ~30 libs sourced pelos handlers: common.sh (emit/fail/param),
│   │                    # auth.sh, users.sh (store por-usuário), problems.sh + orgs.sh
│   │                    # (autoria), tl-store.sh, langs.sh, verdict.sh, review.sh,
│   │                    # cohorts.sh, registration.sh, print.sh, contest-{docs,rounds}.sh,
│   │                    # telegram.sh, alerts.sh, ua-gate.sh, webcast.sh …
│   └── handlers/        # auth/ index/ treino/ submission/ contest/ problems/ orgs/
│                        # judge/ ops/ — 1 arquivo por rota (o caminho É o arquivo)
├── daemons/judged.sh    # consome o spool (inotify), enfileira p/ o pull, grava
│                        # veredicto + placar; segura o veredicto no modo manual
├── judge-gw/            # lado SERVIDOR do pull: sched-lib.sh (registro/fila/claim/
│                        # results) + PULL.md (o protocolo) + judge.sh (dev: mock/local)
├── score/               # build.sh + score-common.sh (o placar) + updatescore-<modo>.sh
│                        # + geradores (stats, relatório offline, jplag, webcast, treino)
├── bin/                 # operação: install-nginx.sh, cert-setup.sh, setup.sh, status.sh,
│                        # store-migrate.sh, user-merge.sh, audit-public-index.sh …
├── test/                # smokes (um por assunto) + fixture.sh + jq-portability.sh
└── etc/
    ├── nginx/           # server blocks (web estático + /api/v1 → fcgiwrap)
    └── systemd/         # units bare-metal dos daemons e do bot
```


## Convenções da API

- Auth: header `Authorization: Bearer <token>` (sessões fora do `/tmp` legível).
- Respostas JSON com envelope `{success:true, …}` / `{success:false, error:{message,code}}`
  e **status HTTP corretos** (o corpo é montado ANTES do cabeçalho — ver `CLAUDE.md`).
- Endpoints de histórico/placar retornam **TXT** (eficiente, já é o que o front parseia).
- Horários sempre em **EPOCH**.
- Validar `contest` (regex/whitelist) antes de qualquer `source contests/<id>/conf`.

Rotas: [`../docs/API.md`](../docs/API.md) + `../web/api/openapi.json`. Modos de placar:
[`../docs/SCOREBOARD.md`](../docs/SCOREBOARD.md). Arquitetura: [`../docs/OVERVIEW.md`](../docs/OVERVIEW.md).
