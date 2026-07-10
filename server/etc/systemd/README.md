# server/etc/systemd/ — units do MOJ (usuário, sem root)

Units **user-level** (`systemctl --user`) para rodar os daemons/serviços do MOJ
sem privilégios de root. Reaproveitam o padrão do `old/fcgiwrap/systemd/` e usam
specifiers do systemd: `%h` (home do usuário) e `%t` (runtime dir,
`$XDG_RUNTIME_DIR`, normalmente `/run/user/<uid>`).

## Units

| unit | papel | estado |
|---|---|---|
| `moj-judged.service` | daemon assíncrono de julgamento (consome o spool, enfileira p/ o pull) | **pronto** |
| `moj-fcgiwrap.service` + `.socket` | API bash atrás do nginx (FastCGI, socket unix) | pronto (usa o fcgiwrap vendado) |
| `moj-bot.service` | bot Telegram como cliente da API | **sample** (script pode não existir ainda) |

> Os juízes são **pull** (repo `judge/`, unit `moj-agent@<cap>.service`): registram capacidade e
> puxam job no heartbeat — não há master/worker/result-sink no lado servidor. O cluster síncrono
> legado (`:27000` + push) foi removido.

## Instalar (usuário comum)

```bash
mkdir -p ~/.config/systemd/user
# linkar (mantém os arquivos versionados no repo; edições se propagam):
ln -sf ~/moj/server/etc/systemd/*.service ~/.config/systemd/user/
ln -sf ~/moj/server/etc/systemd/*.socket  ~/.config/systemd/user/
systemctl --user daemon-reload
```

### Daemon de julgamento

```bash
systemctl --user enable --now moj-judged.service
systemctl --user status moj-judged.service
journalctl --user -u moj-judged -f
```

Em **produção** o daemon roda em modo **pull** (`INTAKE_MODE=queue JUDGE_BACKEND=queue`): ele
**enfileira** cada submissão numa banda de prioridade e os juízes (`moj-agent@`) puxam o job no
heartbeat. Para validar o pipeline localmente sem juízes, use o backend síncrono `mock` (ou `local`,
que precisa de bwrap) com `INTAKE_MODE=legacy`:

```bash
systemctl --user edit moj-judged.service     # cria override.conf
#   [Service]
#   Environment=INTAKE_MODE=legacy
#   Environment=JUDGE_BACKEND=mock
systemctl --user restart moj-judged.service
```

### API via fcgiwrap + socket

```bash
systemctl --user enable --now moj-fcgiwrap.socket   # socket-activation
# o nginx faz:  fastcgi_pass unix:/run/user/<uid>/moj-fcgiwrap.sock;
```

O `fcgiwrap` vendado (`old/fcgiwrap/fcgiwrap`) aceita `-s unix:<sock> -c <n>`;
a unit já passa `-s unix:%t/moj-fcgiwrap.sock -c 8`. Para standalone (sem
socket-activation) basta `enable --now moj-fcgiwrap.service`.

### Juízes (pull)

Os juízes rodam nas máquinas de julgamento pelo unit `moj-agent@<cap>.service` (repo `judge/`,
não este). Eles se registram no `run/registry/` e puxam job no heartbeat — o servidor não abre
conexão de entrada p/ eles. Ver `judge/README.md` e `../../judge-gw/PULL.md`.

## Rodar serviços de usuário sem sessão ativa (lingering)

Para os daemons subirem no boot e seguirem rodando sem login interativo:

```bash
sudo loginctl enable-linger "$USER"   # única coisa que pede root, e é opcional
```

Sem isso, os serviços `--user` vivem enquanto houver sessão do usuário.

## Notas

- `%t` resolve para o runtime dir do usuário — os sockets ficam em
  `/run/user/<uid>/`, fora do `/tmp` público.
- `PrivateTmp=true`/`NoNewPrivileges=true` dão um endurecimento básico sem root.
- Caminhos assumem `~/moj` (este repo). Ajuste `%h/moj` se o deploy diferir.
