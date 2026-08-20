# server/etc/systemd/ — units do MOJ (usuário, sem root)

Units **user-level** (`systemctl --user`) para rodar os daemons/serviços do MOJ
sem privilégios de root. Usam specifiers do systemd: `%h` (home do usuário) e
`%t` (runtime dir, `$XDG_RUNTIME_DIR`, normalmente `/run/user/<uid>`).

## Units

| unit | papel | estado |
|---|---|---|
| `moj-judged.service` | daemon assíncrono de julgamento (consome o spool, enfileira p/ o pull) | **pronto** |
| `moj-fcgiwrap.service` + `.socket` | API bash atrás do nginx (FastCGI, socket unix) | pronto (usa o fcgiwrap vendado) |
| `moj-bot.service` | bot Telegram (mojinho) como cliente da API — em produção roda ENJAULADO (`mojinho-bot/run-caged.sh`) | **em produção** |
| `moj-contest-backup@.service` + `.timer` | snapshot do contest `%i` a cada 5 min — **plano de desastre para o dia da prova** | pronto (ligar só no dia) |

> Os juízes são **pull** (repo `judge/`, unit `moj-agent@<cap>.service`): registram capacidade e
> puxam job no heartbeat. O modelo síncrono antigo foi removido — nada de julgamento fica
> escutando no lado servidor.

## Instalar (usuário comum)

```bash
mkdir -p ~/.config/systemd/user
# linkar (mantém os arquivos versionados no repo; edições se propagam):
ln -sf ~/moj/cdmoj/server/etc/systemd/*.service ~/.config/systemd/user/
ln -sf ~/moj/cdmoj/server/etc/systemd/*.socket  ~/.config/systemd/user/
ln -sf ~/moj/cdmoj/server/etc/systemd/*.timer   ~/.config/systemd/user/
systemctl --user daemon-reload
```

⚠️ **`enable`, não só `start`**: unit de usuário iniciada com `start` **não volta no reboot**.
Foi assim que o bot ficou fora do ar depois de um boot (04/08/2026) — use sempre
`systemctl --user enable --now <unit>`.

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

O `fcgiwrap` vendado (`server/bin/fcgiwrap`, ou o da distro/imagem) aceita
`-s unix:<sock> -c <n>`; a unit já passa `-s unix:%t/moj-fcgiwrap.sock -c 8`
(o nginx deve apontar o `fastcgi_pass` p/ o mesmo socket). Para standalone (sem
socket-activation) basta `enable --now moj-fcgiwrap.service`.

### Backup do contest (dia da prova)

O `moj-contest-backup@<contest>.timer` tira um snapshot do contest a cada 5 min
(`server/bin/contest-backup.sh`; destino em `MOJ_BACKUP_DEST`, default `/var/backups/moj` —
**aponte para outro disco/máquina**). É plano de desastre, então liga-se **no dia** e desliga-se
depois:

```bash
systemctl --user enable --now  moj-contest-backup@<contest>.timer   # antes da prova
systemctl --user disable --now moj-contest-backup@<contest>.timer   # depois
systemctl --user list-timers 'moj-contest-backup@*'                 # conferir
```

### Juízes (pull)

Os juízes rodam nas máquinas de julgamento pelo unit `moj-agent@<cap>.service` (repo `judge/`,
não este). Eles se registram no `run/registry/` e puxam job no heartbeat — o servidor não abre
conexão de entrada p/ eles. Ver `judge/README.md` e `../../judge-gw/PULL.md`.

## Rodar serviços de usuário sem sessão ativa (lingering)

Para os daemons subirem no boot e seguirem rodando sem login interativo:

```bash
sudo loginctl enable-linger "$USER"   # a única coisa que pede root — e num SERVIDOR é obrigatória
```

Sem linger os serviços `--user` vivem só enquanto houver sessão do usuário: eles **caem no logout
e não sobem no boot**. Numa máquina de verdade isso não é opção — e num JUIZ é pior ainda, porque
o limite **duro** de memória da jaula vem de `systemd-run --user --scope -p MemoryMax`, que precisa
do user manager vivo (ver `judge/README.md`).

## Notas

- `%t` resolve para o runtime dir do usuário — os sockets ficam em
  `/run/user/<uid>/`, fora do `/tmp` público.
- `PrivateTmp=true`/`NoNewPrivileges=true` dão um endurecimento básico sem root.
- Os units assumem o workspace em `~/moj` e **este repo em `~/moj/cdmoj`** (é o que o `%h/moj/cdmoj/…`
  dos `ExecStart` diz). Deploy em outro lugar ⇒ ajuste os caminhos nos units.
- Em **produção** o caminho recomendado NÃO é este: a API e o daemon rodam por **quadlets podman**
  (`make install-units`), e estes units são a alternativa **bare-metal** — ver `docs/DEPLOY.md`.
