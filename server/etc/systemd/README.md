# server/etc/systemd/ — units do MOJ (usuário, sem root)

Units **user-level** (`systemctl --user`) para rodar os daemons/serviços do MOJ
sem privilégios de root. Reaproveitam o padrão do `old/fcgiwrap/systemd/` e usam
specifiers do systemd: `%h` (home do usuário) e `%t` (runtime dir,
`$XDG_RUNTIME_DIR`, normalmente `/run/user/<uid>`).

## Units

| unit | papel | estado |
|---|---|---|
| `moj-judged.service` | daemon assíncrono de julgamento (consome o spool) | **pronto** |
| `moj-result-sink.service` | recebe veredictos por PUSH do cluster | **pronto** |
| `moj-fcgiwrap.service` + `.socket` | API bash atrás do nginx (FastCGI, socket unix) | pronto (usa o fcgiwrap vendado) |
| `moj-master.service` | master/escalonador do juiz (`:27000`) | **sample** (roda os scripts vivos do cluster) |
| `moj-worker@.service` | worker do juiz; instância = `cap:port` | **sample/template** |
| `moj-bot.service` | bot Telegram como cliente da API | **sample** (script pode não existir ainda) |

## Instalar (usuário comum)

```bash
mkdir -p ~/.config/systemd/user
# linkar (mantém os arquivos versionados no repo; edições se propagam):
ln -sf ~/moj/server/etc/systemd/*.service ~/.config/systemd/user/
ln -sf ~/moj/server/etc/systemd/*.socket  ~/.config/systemd/user/
systemctl --user daemon-reload
```

### Daemon de julgamento (mock, p/ validar o pipeline sem cluster)

```bash
systemctl --user enable --now moj-judged.service
systemctl --user status moj-judged.service
journalctl --user -u moj-judged -f
```

Trocar o backend depois (`local`/`cluster`) editando `Environment=JUDGE_BACKEND=`
na unit (ou com um drop-in):

```bash
systemctl --user edit moj-judged.service     # cria override.conf
#   [Service]
#   Environment=JUDGE_BACKEND=cluster
#   Environment=JUDGE_MASTER=localhost:27000
#   Environment=RESULT_SINK=localhost:28000
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

### Sink de resultado (push do cluster)

```bash
systemctl --user enable --now moj-result-sink.service   # escuta :28000
```

### Master e workers (sample — cluster)

```bash
systemctl --user start moj-master.service
# workers por instância "capability:porta":
systemctl --user start 'moj-worker@pos:41050.service'
systemctl --user start 'moj-worker@gpu:42000.service'
```

> As units de master/worker rodam os scripts VIVOS de `judge/` e são **samples**:
> ajuste o listener (`tcpserver` vs `socat`/`ncat`) ao que existir no host e veja
> `../../judge-gw/README.md` p/ a migração incremental (push + registro).

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
