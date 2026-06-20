# server/ — Backend MOJ (bash, atrás do nginx + fcgiwrap)

Backend **API-first** em bash. O nginx serve `../web/` estático e faz `fastcgi_pass` para o
`fcgiwrap`, que executa o `api/v1/router.sh`.

```
server/
├── api/v1/
│   ├── router.sh        # dispatcher único (PATH_INFO + método) → handler
│   ├── lib/             # common.sh, params.sh, auth.sh, json.sh (base reutilizável)
│   └── handlers/        # auth/ index/ treino/ submission/ contest/ admin/ judge/ ops/
├── daemons/             # consumo dos spools via inotify; submit assíncrono; serviços systemd
├── judge-gw/            # gateway p/ o cluster judge/ (julgador.sh, corrige.sh, enviar-*.sh)
├── score/               # updatescore-<modo>.sh + dispatcher por CONTEST_TYPE
└── etc/
    ├── nginx/           # server blocks (web estático + /api/v1 → fcgiwrap)
    └── systemd/         # units dos daemons, master/worker do juiz e do bot
```

## Convenções da API

- Auth: header `Authorization: Bearer <token>` (sessões fora do `/tmp` legível).
- Respostas JSON com envelope `{success, data|error}` e **status HTTP corretos**.
- Endpoints de histórico/placar retornam **TXT** (eficiente, já é o que o front parseia).
- Horários sempre em **EPOCH**.
- Validar `contest` (regex/whitelist) antes de qualquer `source contests/<id>/conf`.

Contrato completo das rotas e modos de placar: [`../docs/PLAN.md`](../docs/PLAN.md).
