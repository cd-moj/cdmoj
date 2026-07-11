# MOJ — Manual do administrador (instalação do zero)

Guia **operacional** para subir o MOJ num **servidor limpo** e deixar a plataforma funcional,
incluindo o passo que nenhuma outra doc cobre: **criar o contest `treino` e a primeira conta
`.admin`**. É complementar ao [`DEPLOY.md`](DEPLOY.md) (referência técnica de nginx/podman) —
aqui a ênfase é a **sequência do zero** e o **bootstrap de dados**.

> Leia antes, se quiser contexto: [`OVERVIEW.md`](OVERVIEW.md) (arquitetura), [`FLOW.md`](FLOW.md)
> (caminho de uma submissão), [`API.md`](API.md) (rotas). Lado do juiz: `judge/README.md`.

## Panorama — o que você vai subir

| Peça | O que é | Onde roda |
|---|---|---|
| **nginx** | serve `web/`/`docs/` estático + `fastcgi_pass` `/api/v1` ao socket | **host** (FORA da imagem) |
| **API** | `fcgiwrap` rodando o `router.sh` (API bash) num socket unix | container `moj-api` (ou `start-fcgiwrap.sh`) |
| **judged** | daemon que consome o spool e **enfileira** p/ o pull; grava veredicto + placar | container `moj-judged` (ou `judged.sh`) |
| **juízes** | máquinas de correção que **puxam** job por heartbeat (modelo pull) | repo `judge/` (uma ou mais máquinas) |
| **bot** (opcional) | bot Telegram, cliente da API (cadastro/alertas do treino) | `mojinho-bot/mojinho-api.sh` |

**Workspace multi-repo** (o `/home/ribas/moj` **não** é um repo — junta repos independentes):
o servidor precisa de **`cdmoj/`** (este) + **`mojtools/`** (render/validate/index). `moj-cli/`
é opcional (gera as CLIs servidas). Dados/estado: `contests/`, `moj-problems/`, `run/`.

> **Caminho de instalação.** Os defaults do código apontam p/ `/home/ribas/moj/…`. Este manual usa
> esse caminho. Instalando em outro lugar, ajuste os defaults por env (`CONTESTSDIR`, `RUNDIR`,
> `MOJ_PROBLEMS_DIR`, `MOJTOOLS_DIR`, `NEWSDIR` — ver `server/etc/common.conf`) nos `Environment=`
> dos units / no `ENV`+volumes dos quadlets.

## 1. Pré-requisitos (servidor limpo)

- **SO Linux** com **podman rootless** (caminho recomendado) ou toolchain bare-metal.
- **Pacotes do host** (não há *doctor* no lado servidor — a lista canônica é o
  `deploy/Containerfile`): `bash jq git gawk sed grep findutils coreutils util-linux tar gzip zip
  unzip curl ca-certificates` · `fcgiwrap` (bare-metal usa o ELF vendorizado em `server/bin/fcgiwrap`)
  · `pandoc` (render de enunciado) · `inotify-tools` `socat` (o daemon cai p/ *polling* sem o
  `inotifywait`) · `imagemagick` `ghostscript` `poppler-utils` `qpdf` `paps` `fonts-dejavu-core`
  (etiquetas/balões/PDF). Opcionais: `libreoffice-core/writer/calc` e `default-jre-headless` (jplag).
  No caminho podman **tudo isso já vai dentro da imagem** — o host só precisa de `podman` + `nginx`.
- **Repos** sob um root (ex.: `/home/ribas/moj`):
  ```bash
  git clone <cdjudge-cdmoj>   /home/ribas/moj/cdmoj
  git clone <cdjudge-mojtools> /home/ribas/moj/mojtools
  git clone <cdjudge-moj-cli>  /home/ribas/moj/moj-cli    # opcional (CLIs /moj*)
  ```
- **git safe.directory** (o servidor commita nos repos por-problema de dono "estrangeiro"):
  `git config --system --add safe.directory '*'` (a imagem já faz isso).
- **nginx no host** + **TLS** (o cert vive fora deste repo, no `~/nginx-proxy/`).

## 2. Caminho A — instalação com podman (recomendado)

```bash
cd /home/ribas/moj/cdmoj
make check            # opcional: bash -n + node --check (só sintaxe)
make image            # localhost/moj-server:<data> + tag :prod (contexto = raiz do workspace)
make install-units    # quadlets -> ~/.config/containers/systemd/ ; daemon-reload
```

Antes de subir, **crie os segredos** (a imagem cria `run/secrets/`, mas o token é sempre manual —
ver §7):

```bash
mkdir -p /home/ribas/moj/run/secrets && chmod 700 /home/ribas/moj/run/secrets
TOK="mojw_$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
install -Dm600 <(printf '%s' "$TOK") /home/ribas/moj/run/secrets/worker.token
```

Suba os dois containers (mesma imagem, papéis `api` e `judged`, reinício independente):

```bash
systemctl --user start moj-api moj-judged
loginctl enable-linger "$USER"          # sobrevive ao logout
```

**nginx do host** (fora da imagem): aponte `fastcgi_pass` ao socket exposto pelo volume `run/`,
`root` no `web/`, `SCRIPT_FILENAME` no `router.sh`, e um alias `/docs/`. Os blocos prontos e o
subdomínio de contest estão em **[`DEPLOY.md`](DEPLOY.md)** (§ *nginx*). O essencial:

```nginx
root /home/ribas/moj/cdmoj/web;  index index.html;
location /api/v1/ {
  fastcgi_pass unix:/home/ribas/moj/run/fcgiwrap.sock;   # = /data/run/fcgiwrap.sock no container
  fastcgi_split_path_info ^(/api/v1)(/.*)$;
  fastcgi_param SCRIPT_FILENAME /home/ribas/moj/cdmoj/server/api/v1/router.sh;
  fastcgi_param PATH_INFO $fastcgi_path_info;            # + REQUEST_METHOD, QUERY_STRING, HTTP_AUTHORIZATION…
  include fastcgi_params;
}
location /docs/ { alias /home/ribas/moj/cdmoj/docs/; }
```

Agora faça o **bootstrap do treino + admin (§5)** e valide com `make smoke` (§8).

> **Atualizar depois:** `make deploy` (build local) ou `make deploy FROM=registry`; `make rollback
> PREV=<tag>`; `make status`; `make logs`; `make restart-judged`. Ver `README.md` + o header do `Makefile`.

## 3. Caminho B — bare-metal (alternativa / dev)

```bash
cd /home/ribas/moj/cdmoj
bash server/bin/setup.sh                 # cria run/{sessions(700),spool,results} + NEWSDIR; exec bits; instala CLIs se moj-cli existir
mkdir -p ../run/secrets && chmod 700 ../run/secrets     # setup.sh NÃO cria secrets
TOK="mojw_$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
install -Dm600 <(printf '%s' "$TOK") ../run/secrets/worker.token
bash server/bin/start-fcgiwrap.sh &      # sobe o fcgiwrap em run/fcgiwrap.sock (8 workers)
```

Configure/recarregue o nginx do host (mesmos diretivos da §2) e suba o **daemon** em modo
**produção (pull)**:

```bash
INTAKE_MODE=queue JUDGE_BACKEND=queue bash server/daemons/judged.sh &
```

Em produção prefira os **units systemd de usuário** (`server/etc/systemd/`,
`systemctl --user enable --now moj-fcgiwrap.socket moj-judged.service`) — instruções em
`server/etc/systemd/README.md`. Faça o **bootstrap do treino + admin (§5)** e rode
`bash server/bin/status.sh`.

> **Nota (dev):** `bash server/bin/start-all.sh` encadeia setup+fcgiwrap+nginx+judged, mas com
> `JUDGE_BACKEND=mock` e `INTAKE_MODE=legacy` (julga inline, toda submissão vira `Accepted,100p`)
> — bom p/ testar sem juiz, **não** é produção.

## 4. Segredos (resumo)

Dois tokens **compartilhados** (600, sob `run/secrets/`), nunca versionados, nunca na imagem:

- **`worker.token`** (`mojw_…`) — autentica os **juízes** (`Authorization: Bearer mojw_…`). Gere no
  host da API (§2) e **espelhe o MESMO valor** em cada juiz (`judge/etc/worker.token`). Sem ele os
  endpoints `/judge/*` respondem `503 worker_noconf`.
- **`bot.token`** (`mojb_…`, **só se usar o bot Telegram**):
  ```bash
  printf 'mojb_%s' "$(head -c24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c32)" \
    > /home/ribas/moj/run/secrets/bot.token && chmod 600 /home/ribas/moj/run/secrets/bot.token
  ```
  (O bot ainda precisa do token da API do Telegram em `mojinho-bot/token` e de `mojinho-bot/bot.conf`.)

## 5. ★ Bootstrap do `treino` e da primeira conta `.admin`

**Por que é manual (ovo-e-galinha):** criar um contest pela API exige uma **sessão `.admin` no
treino** (`cc_can_create`), mas numa instalação vazia essa conta ainda não existe. Logo o próprio
`treino` e o **primeiro admin** nascem **à mão no filesystem** — só dois artefatos; todo o resto o
sistema cria sozinho, sob demanda.

### 5.1. Criar o contest `treino`

`treino` é a **hub singleton** (é onde vivem problemas/orgs/coleções/permissões; o id é reservado,
não dá p/ criá-lo pela API). O único artefato é o `conf` (5 linhas):

```bash
mkdir -p /home/ribas/moj/contests/treino
cat > /home/ribas/moj/contests/treino/conf <<'EOF'
CONTEST_ID=treino
CONTEST_NAME="Treino Livre"
CONTEST_TYPE=lista-publica
ALLOWLATEUSER=y
CONTEST_END="$(date --date="next year" +%s)"
EOF
```

- `CONTEST_TYPE=lista-publica` → placar em modo **treino** (mostra detalhe cheio dos veredictos).
- `ALLOWLATEUSER=y` → sem lista fechada de inscritos (o treino é aberto).
- `CONTEST_END="$(date …)"` → fim no futuro (o heredoc é `'EOF'` **entre aspas** de propósito: a
  string é gravada **literal** e o `date` roda a cada leitura do `conf`, mantendo o contest sempre "ativo").

Não crie nada em `var/`: `orgs.json`, `collections.json`, `jsons/`, `placar*.txt` etc. são **todos
criados sob demanda** (ausentes ⇒ vazios). Com zero problemas, a lista do treino simplesmente vem vazia.

### 5.2. Criar a primeira conta `.admin`

No MOJ **não existe flag de admin**: o papel é o **sufixo do login**
(`is_admin(){ [[ "$SESSION_LOGIN" == *.admin ]]; }`). O helper `user_create` **não** valida o
sufixo e grava a **senha em texto puro** — é exatamente o gancho de bootstrap. Rode como o
**usuário do servidor**:

```bash
export CONTESTSDIR=/home/ribas/moj/contests
source /home/ribas/moj/cdmoj/server/api/v1/lib/users.sh
user_create treino ribas.admin "Bruno Ribas" "TROQUE-esta-senha"
```

- O login **tem** que terminar em `.admin` (ex.: `ribas.admin`). A senha **não** pode ser vazia
  nem conter `:` (dois-pontos quebram os TSVs derivados).
- Cria `contests/treino/users/ribas.admin/account.json` (`login`, `password`, `fullname`, …).
  Confira: `jq '{login,status}' /home/ribas/moj/contests/treino/users/ribas.admin/account.json`.
- Idempotente: se já existir, retorna 2 e **não** sobrescreve. Trocar a senha depois:
  `user_set_password treino ribas.admin "nova"` (mesma lib).

### 5.3. Logar

O login persiste a sessão em `run/sessions/` (precisa ser **700** e gravável). Três portas
equivalentes — todas batem em `POST /api/v1/auth/login?contest=treino` com `{username,password}`
(o contest é **query**; o campo é **`username`**):

```bash
# via API (teste local com header Host; troque pelo seu host/porta):
H="Host: moj.charge.naquadah.com.br"; B=http://127.0.0.1:8080
curl -s -H "$H" -X POST -H 'Content-Type: application/json' \
  --data '{"username":"ribas.admin","password":"TROQUE-esta-senha"}' \
  "$B/api/v1/auth/login?contest=treino" | jq -r .token         # -> um token mojs_…
```

- **Web:** `https://<host>/treino/` (formulário de login).
- **CLI:** `MOJ_URL=https://<host> moj login` (contest default `treino`; a CLI vem servida em `/moj`).

> **Gotchas:** `LOGIN_ENABLED=n` só esconde o formulário web — a **API continua autenticando**
> (útil no bootstrap). Se o `conf` tiver `LOGIN_UA_SUBSTRING`, contas `.admin` são **isentas** do
> gate. `SECRET=1` exigiria sessão até p/ endpoints públicos — não use no treino.

### 5.4. Loop fechado — daí em diante é tudo pela sessão `.admin`

Com o `.admin` logado, a API destrava:

- **Criar provas/treinos:** wizard web `/treino/criar/` ou `moj-contest create …` (cada contest já
  nasce com a **sua própria** conta `.admin`).
- **Mais admins/juízes:** `moj-contest users add fulano.admin --pass …` ou
  `POST /api/v1/admin/adduser {contest:"treino",login:"fulano.admin",…}` — ou o **mesmo**
  `user_create` do §5.2. (Sufixos `.judge`/`.cjudge`/`.staff`/`.cstaff`/`.mon` seguem a mesma regra.)
- **Publicar notícias, gerir problemas/orgs/coleções,** etc. — tudo pela UI/CLI autenticada.

## 6. Juízes (máquinas de correção) — resumo

Cada juiz clona **só** `judge/` + `mojtools/` (não o `cdmoj`), instala e sobe o agente pull:

```bash
cd judge
make doctor                                   # confere deps + bwrap real + rootfs (não escreve nada)
make install CAP=pos MOJ_API=https://<host>/api/v1 \
     INSTALL_FLAGS="--token /caminho/worker.token"
```

O `--token` recebe o **mesmo** `worker.token` gerado no §2/§4. O rootfs da jaula é o **padrão**
(`--sysroot pull|tar|build|host`). Detalhes completos (capacidades, multi-slot, C3SL sem podman/root):
**`judge/README.md`** e `server/judge-gw/PULL.md`.

## 7. Operar / atualizar

- **Atualizar:** `make deploy` (build local) · `make deploy FROM=registry` · `make rollback PREV=<tag>`.
- **Estado:** `make status` (compara a revisão da imagem `:prod` com o `HEAD`) · `make logs` ·
  `bash server/bin/status.sh` (bare-metal).
- **Reiniciar só o julgamento:** `make restart-judged`. **Regra:** ao editar `server/daemons/judged.sh`
  reinicie o daemon **preservando** `INTAKE_MODE=queue JUDGE_BACKEND=queue`.
- **Backups:** `server/bin/contest-backup.sh` (e o timer `moj-contest-backup@.timer`).

## 8. Checklist de verificação

```bash
H="Host: <seu-host>"; B=http://127.0.0.1:8080
curl -s -H "$H" $B/api/v1/            # {"success":true,"name":"MOJ API","version":"v1"}
```

- [ ] `/api/v1/` responde o envelope acima; a **home** (`/`) carrega no navegador.
- [ ] **Login `.admin`** funciona (o `curl` do §5.3 devolve um `token`) e a web `/treino/` loga.
- [ ] Fluxo ponta a ponta: use o contest descartável **`zzdemo`** (login `demo`/`demo`) do
      [`DEPLOY.md`](DEPLOY.md) (§ *Sandbox*) — submeter → `judged` → `history` = `Accepted,100p`
      (ou `make smoke`).
- [ ] Um **juiz** aparece online (`/api/v1/judge/list` ou o painel `/treino/admin/`).

## Ponteiros

Arquitetura: [`OVERVIEW.md`](OVERVIEW.md) · Fluxo de submissão: [`FLOW.md`](FLOW.md) · Rotas:
[`API.md`](API.md) · Deploy técnico + nginx/subdomínios: [`DEPLOY.md`](DEPLOY.md) · Units bare-metal:
`server/etc/systemd/README.md` · Juízes: `judge/README.md` · Pull/segredos: `server/judge-gw/PULL.md`.
