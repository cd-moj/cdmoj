# MOJ — Deploy & teste (nginx + fcgiwrap + daemons)

São **duas formas**, e elas diferem **só no nginx** (o resto — imagem, quadlets, socket, dados — é igual):

| | **Produção** (máquina dedicada) | **Dev** (máquina de quem programa) |
|---|---|---|
| nginx | do **sistema** (root), **80/443**, TLS — `server/bin/install-nginx.sh` | **user-space**, como o próprio usuário, **8080/8443** — `~/nginx-proxy/` |
| API + judged | containers rootless (quadlets) da imagem podman | idem, ou os scripts à mão |
| dono dos dados | um usuário de serviço (ex.: `moj`) | o seu usuário (`ribas`) |

**Instalação do zero, passo a passo (inclui o bootstrap do `treino` + 1º `.admin`): [`ADMIN.md`](ADMIN.md).**

## Componentes

| Componente | O que é | Como sobe |
|---|---|---|
| **nginx** (`~/nginx-proxy`) | serve `web/` estático + proxy `/api/v1` → fcgiwrap | `~/nginx-proxy/proxy.sh reload` |
| **fcgiwrap** | roda o `router.sh` (API bash) num socket unix | `server/bin/start-fcgiwrap.sh` |
| **judged** (daemon) | consome o spool e **enfileira** p/ o pull (dev: julga inline mock/local), grava veredicto + placar | `server/daemons/judged.sh` |
| **juiz (agente pull)** | máquinas de julgamento: registram capacidade + puxam jobs | repo **judge** separado — ver `judge/README.md` (bring-up por máquina) e `server/judge-gw/PULL.md` |
| **mojinho-bot** | bot Telegram (cliente da API) | **produção: `mojinho-bot/run-caged.sh`** — jaula bwrap sem acesso a workspace/contests/run/moj-problems (segredos no dir vivo `~/mojinho-live`); unit user `server/etc/systemd/moj-bot.service`. Debug: `mojinho-bot/mojinho-api.sh` direto. Ver `mojinho-bot/README.md` |

> **Storage de problemas (MOJ-nativo):** cada problema é um repo git LOCAL em
> `MOJ_PROBLEMS_DIR/<org>/<prob>` — o servidor commita direto e indexa inline; acesso por ORG
> (`contests/treino/var/orgs.json`). Não há serviço externo/LFS/webhook. Cut-over histórico:
> `server/bin/migrate-to-orgs.sh`.

## Deploy com imagem podman (produção)

A plataforma empacota numa imagem OCI (`deploy/Containerfile`, base `debian:trixie-slim`) com
**todas** as dependências dentro. O **nginx do host segue FORA da imagem** (serve `web/`/`docs/`
e faz `fastcgi_pass` ao socket); a imagem é a **API** (fcgiwrap + `router.sh`) + o **daemon**.
Dois containers da mesma imagem (papéis `api` e `judged`) sobem por **quadlets** rootless.

```bash
cd <raiz-do-workspace>/cdmoj
make image            # localhost/moj-server:<data> + tag :prod  (WITH_OFFICE/WITH_JPLAG=1)
make install-units    # quadlets -> ~/.config/containers/systemd/ (substitui @WORKROOT@); daemon-reload
sudo loginctl enable-linger "$USER"          # SEM isto os serviços --user não sobem nem sobrevivem
systemctl --user start moj-api moj-judged    # (NÃO é `enable`: unit de quadlet é gerada)
sudo bash server/bin/install-nginx.sh --workroot <raiz> --names "<host>"   # nginx do host (abaixo)
make smoke
```

- **Volumes (`:z`, SHARED):** `run/`, `contests/`, `moj-problems/`, `server/var/news` → `/data/…`.
  Estado e segredos NUNCA entram na imagem (ver `deploy/.containerignore`). Rootless: container-root
  ↔ o usuário do host (não defina `USER` nem `--userns=keep-id`).
- **Raiz do workspace:** os quadlets são **templates** (`@WORKROOT@`) e o `make install-units`
  substitui pelo caminho absoluto de `$(WORKROOT)` (default `..`). Copiar o arquivo cru p/
  `~/.config/containers/systemd/` deixa o placeholder literal e o container não sobe.
- **`loginctl enable-linger`:** sem ele não há sessão/bus do usuário — `systemctl --user` falha e
  nada sobe no boot. É o passo que mais trava instalação nova.
- **`systemctl --user enable moj-api` NÃO funciona** (`Unit … is transient or generated`): quem cria
  a unit é o **gerador do quadlet**, e o `[Install] WantedBy=default.target` do `.container` já a
  coloca no `default.target` — com o linger ligado, ela sobe no boot. Use só `start`/`restart`/`status`.
- **O `SCRIPT_FILENAME` do nginx é o caminho DENTRO da imagem**
  (`/opt/moj/cdmoj/server/api/v1/router.sh`): quem executa o script é o fcgiwrap, que roda no
  container. Apontar p/ o caminho do host = "script não encontrado" (o `install-nginx.sh` já usa o
  certo; bare-metal usa `--bare-metal`).
- **Socket:** `run/fcgiwrap.sock` nasce **0770 do dono** (umask 007 no `moj-entrypoint`) — quem for
  falar com ele (o nginx) precisa estar no **grupo do dono**.
- **Atualizar:** `make deploy` (build local) ou `make deploy FROM=registry` (pull de
  `ghcr.io/cd-moj/moj-server`); ambos re-tagueiam `:prod` e reiniciam. Rollback: `make rollback PREV=<tag>`.
- **Reiniciar SEM PERDER FILA:** a fila inteira é arquivo no volume `run/` compartilhado —
  `systemctl --user restart moj-api moj-judged` em qualquer ordem não perde nada; juízes
  reiniciam por `moj judges restart <host>` (sem SSH) ou `make restart` no juiz, e o trabalho
  em voo re-enfileira na hora (register `boot:true`). Receita completa e TTLs:
  `server/judge-gw/PULL.md` §"Reiniciar SEM PERDER FILA".
- **SELinux:** se o host prod estiver *enforcing*, os `:z` bastam; opcionalmente fixe o rótulo com
  `semanage fcontext -a -t container_file_t '<raiz>/(run|contests|moj-problems)(/.*)?' && restorecon -R`.
  (Ubuntu usa AppArmor: os `:z` viram no-op, sem problema.)

## nginx do sistema (produção: root, 80/443)

Na máquina dedicada o nginx é o **do sistema**: serve `web/` estático e passa `/api/v1` ao socket do
fcgiwrap. Um script versionado monta tudo (idempotente):

```bash
# 1ª passada: HTTP-only — sobe e valida a API antes de existir certificado
sudo bash server/bin/install-nginx.sh --workroot /home/moj/moj --names "moj.naquadah.com.br"
# depois de emitir o cert (abaixo): mesma linha + --cert  => 80→443 + TLS
sudo bash server/bin/install-nginx.sh --workroot /home/moj/moj --names "moj.naquadah.com.br" \
     --cert moj.naquadah.com.br
```

Ele gera `/etc/nginx/snippets/moj-app.conf` + `/etc/nginx/conf.d/moj.conf` a partir dos templates
`server/etc/nginx/moj-app.conf.in` e `moj-prod{,-http}.conf.in`, e resolve as **duas armadilhas** que
o dev não tem (lá o nginx roda como o **mesmo** usuário do MOJ):

1. **Permissão.** Os workers (`www-data`) precisam (a) **atravessar** a raiz do workspace e ler
   `cdmoj/web/`, e (b) **conectar** no socket unix. O socket nasce **0770 do dono**, então o script
   põe o `www-data` no **grupo do dono** (`usermod -aG moj www-data`; o nginx chama `initgroups()`,
   e por isso é preciso **restart**, não só reload). Sem isso: 403 no estático e **EACCES no socket
   → 502 em toda a API**.
2. **`default_server` da distro.** O `sites-enabled/default` captura o `:80`; o script o desabilita.

**Subdomínio de contest sem duplicar server block:** um `map $host $moj_contest_host` extrai o `<id>`
de `<id>.<host>` e o injeta em `CONTEST_HOST`; no site principal ele vem **vazio**, e o `router.sh`
trata vazio como ausente — então **um** server block serve os dois. O isolamento continua sendo da
API (o nginx só transporta o id).

## TLS e renovação (Let's Encrypt)

```bash
sudo bash server/bin/cert-setup.sh --email <você@dominio> --credentials ~/digitalocean.ini \
     --cert-name moj.naquadah.com.br -d moj.naquadah.com.br -d '*.moj.naquadah.com.br'
```

- **DNS-01 por padrão** (plugin `dns-digitalocean`): é o único desafio que emite **wildcard**, e
  wildcard é o que os subdomínios de contest exigem. Ele também **não precisa** que o DNS já aponte
  p/ a máquina (só cria um TXT `_acme-challenge` temporário) — dá p/ emitir o certificado do domínio
  final **antes do cutover**. `--webroot` troca p/ http-01 (aí **sem** wildcard).
- **A renovação é automática e NÃO é deste script:** quem renova é o `certbot.timer` do systemd
  (2×/dia, já habilitado pelo pacote). O script garante o que falta p/ ela funcionar sozinha: a
  credencial de DNS em `/etc/letsencrypt/` (600) e o **hook de deploy**
  `/etc/letsencrypt/renewal-hooks/deploy/10-reload-nginx.sh` (o nginx só passa a servir o cert novo
  depois de um `reload`). Confira com `certbot renew --dry-run` e `certbot certificates`.

## Bring-up (dev/local)

```bash
cd /home/ribas/moj
bash server/bin/setup.sh                 # cria run/, vendora fcgiwrap, copia notícias
bash server/bin/start-fcgiwrap.sh &       # sobe o fcgiwrap em run/fcgiwrap.sock
# moj.conf já está em ~/nginx-proxy/conf.d/ :
~/nginx-proxy/proxy.sh test && ~/nginx-proxy/proxy.sh reload
# daemon de julgamento (mock = não precisa de juiz nem de bubblewrap):
JUDGE_BACKEND=mock bash server/daemons/judged.sh &     # ou --once para processar 1 e sair
```

Em **produção** o caminho é a imagem podman + quadlets (acima). Os units de `server/etc/systemd/` são
a alternativa **bare-metal** — atenção: o `moj-fcgiwrap.socket` abre o socket em `%t`
(`/run/user/<uid>/`), então o `fastcgi_pass` do nginx tem de apontar p/ **esse** caminho (ou use o
`start-fcgiwrap.sh`, que abre em `run/fcgiwrap.sock`, o que os vhosts assumem).

## nginx user-space (dev) — `~/nginx-proxy/conf.d/moj.conf`

> Este é o modelo **de dev** (nginx como o próprio usuário, em 8080/8443, porque usuário sem
> privilégio não abre porta <1024). Em **produção** use o nginx do sistema (seção acima).

Server block para `moj.charge.naquadah.com.br` (coberto pelo cert wildcard `*.charge.naquadah.com.br`):
- `root /home/ribas/moj/cdmoj/web` + `index index.html` → frontend estático.
- `location /api/v1/` → `fastcgi_pass unix:/home/ribas/moj/run/fcgiwrap.sock`, com `SCRIPT_FILENAME=server/api/v1/router.sh` e `PATH_INFO` via `fastcgi_split_path_info`.
- `location /docs/` → serve esta documentação.

> **Nota:** o `fcgiwrap` vendorizado (`server/bin/fcgiwrap`) é o binário padrão (aceita `SCRIPT_FILENAME`). Na imagem podman usa-se o pacote `fcgiwrap` da distro.

### Subdomínio de contest — `~/nginx-proxy/conf.d/moj-subdomains.conf`

Cada contest é acessado por `<id>.moj.<base>` (ex.: `<id>.moj.charge.naquadah.com.br`). Um
server block com `server_name` **regex** captura o id e o injeta no backend:

```nginx
server_name  ~^(?<contestid>[a-z0-9][a-z0-9._-]*)\.moj\.charge\.naquadah\.com\.br$;
# ... mesmo root web/ + location /api/v1 do moj.conf, mais:
fastcgi_param  CONTEST_HOST  $contestid;   # o router.sh impõe o isolamento
```

O `server_name` exato `moj.charge…` (em `moj.conf`) tem precedência para o site principal;
o regex pega só `<algo>.moj.charge…`. Cópia versionada em `server/etc/nginx/moj-subdomains.conf`.
Recarregar: `cd ~/nginx-proxy && ./proxy.sh test && ./proxy.sh reload`.

> **Cert (HTTPS):** um wildcard cobre **um nível** só — `*.charge.naquadah.com.br` serve
> `moj.charge…` mas **não** `<id>.moj.charge…` (dois níveis). Para HTTPS nos subdomínios de contest o
> cert precisa incluir `*.<host-do-site>` (ex.: `*.moj.naquadah.com.br`) — é o que o
> `server/bin/cert-setup.sh` emite (DNS-01). Em HTTP e via header `Host:` nos testes já funciona sem cert.

## Documentação servida (`/docs/`)

O `/docs/` serve o **HTML renderizado** de `docs/html/` (artefato por-checkout, gitignorado —
`bash docs/build-html.sh`, precisa de pandoc no host). O `make image`/`deploy` regenera via o
alvo `docs-html` (sem pandoc: avisa e segue; o autoindex do nginx é o fallback). `/docs` sem
barra redireciona.

## CLIs servidas (`/moj`, `/moj-contest` e `/moj-judges`)

`web/moj*` são **artefatos de distribuição** (1 arquivo, com a lib comum embutida) gerados
de `moj-cli/` — **nunca** copie o script do repo direto (ele sourceia `lib/core.sh` e
quebraria fora do repo). **A sincronização é AUTOMÁTICA no deploy**: `make image`/`make
deploy` roda o alvo `cli-dist`, que regenera via `../moj-cli/mkdist.sh` e copia p/ `web/`
o que divergir (sem `../moj-cli` no checkout, avisa e segue). Para regenerar na mão (dev):

```bash
bash /home/ribas/moj/moj-cli/mkdist.sh
install -m755 /home/ribas/moj/moj-cli/dist/moj /home/ribas/moj/moj-cli/dist/moj-contest \
  /home/ribas/moj/moj-cli/dist/moj-judges /home/ribas/moj/cdmoj/web/
install -m644 /home/ribas/moj/moj-cli/dist/moj.build /home/ribas/moj/cdmoj/web/
```

O `mkdist.sh` **carimba o build** (`MOJ_CLI_BUILD=<git-short>-<data>`) dentro de cada artefato e
gera `dist/moj.build` (1 linha com o mesmo carimbo), servido como **`/moj.build`** — é com ele
que `moj version`/`moj doctor` detectam CLI desatualizada e `moj update` se atualiza. O
`cli-dist` copia os 4 arquivos.

## Como acessar / testar

O proxy escuta em **8080 (HTTP)** e **8443 (HTTPS)**. Se o DNS de `moj.charge.naquadah.com.br` apontar para a máquina, acesse `https://moj.charge.naquadah.com.br:8443/`. Para testar local sem DNS, use o header Host:

```bash
H="Host: moj.charge.naquadah.com.br"; B=http://127.0.0.1:8080
curl -s -H "$H" $B/api/v1/                         # {"success":true,"name":"MOJ API","version":"v1"}
curl -s -H "$H" $B/api/v1/treino/problems | jq length   # 736
```

No navegador (com DNS ou um entry em /etc/hosts apontando o domínio p/ a máquina):
- `/` — página inicial (notícias, contests, treino, top10).
- `/treino/` — busca de problemas (fuzzy, tags, dificuldade).
- `/treino/problema/?id=<id>` — enunciado + **editor CodeMirror** + upload + histórico.
- `/contest/?c=<contestId>` — login/prova do contest; `/contest/score/?c=<contestId>` — placar.

### Sandbox de teste do fluxo completo (sem poluir dados reais)

Existe um contest descartável **`zzdemo`** (login `demo` / senha `demo`). Fluxo assíncrono ponta a ponta:

```bash
H="Host: moj.charge.naquadah.com.br"; B=http://127.0.0.1:8080
TOK=$(curl -s -H "$H" -X POST -H 'Content-Type: application/json' \
   --data '{"username":"demo","password":"demo"}' "$B/api/v1/auth/login?contest=zzdemo" | jq -r .token)
curl -s -H "$H" -H "Authorization: Bearer $TOK" -X POST -H 'Content-Type: application/json' \
   --data '{"problem_id":"0","filename":"sol.c","code_b64":"aW50IG1haW4oKXtyZXR1cm4gMDt9"}' \
   "$B/api/v1/submit?contest=zzdemo"                       # -> {submission_id, status:"queued"}
JUDGE_BACKEND=mock bash server/daemons/judged.sh --once    # mock-julga
curl -s -H "$H" -H "Authorization: Bearer $TOK" "$B/api/v1/contest/history?contest=zzdemo"  # -> Accepted,100p
```

> Para ver o veredicto aparecer no navegador (treino ou contest), deixe `judged.sh` rodando. Com `JUDGE_BACKEND=mock` toda submissão vira `Accepted,100p` (bom p/ demo, mas grava no histórico do contest submetido — prefira `zzdemo`). `JUDGE_BACKEND=local` usa `mojtools` (bubblewrap) com pacotes de problema locais. Em produção o daemon roda `INTAKE_MODE=queue JUDGE_BACKEND=queue` (pull): enfileira e os juízes (`judge/`) puxam o job.
