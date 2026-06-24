# Gitea — deploy & operação (store git da gestão de problemas)

O Gitea é o **backend git** da gestão de problemas. Os autores **nunca falam com ele
direto**: só conhecem o **login do MOJ**. A API do MOJ guarda **um token admin** (modo 600)
e provisiona — *lazy* — um usuário Gitea + token HTTPS por login, commitando/pushando **por
baixo** como o autor (`lib/gitea.sh` + `mojtools/git-broker.sh`). Sem chave SSH, sem git na
mão. Isso é a decisão central: **sem chaves, simples para todos**.

```
autor ──(login MOJ)──► API do MOJ ──(token admin, Sudo:)──► Gitea (HTTP) ──► repos git
                          │
                          └─ git-broker.sh: clone/commit --author/push via HTTPS
                             com token efêmero no GIT_ASKPASS (nunca no .git/config)
```

Roda **user-space como `ribas`** (sem root), igual ao resto do MOJ.

---

## 1. O que já está provisionado (dev/local)

| Item | Caminho | Obs |
|---|---|---|
| binário | `run/gitea/gitea` (1.26.4, linux-amd64) | baixado à parte (não versionado) |
| config | `run/gitea/custom/conf/app.ini` | porta **3939**, HTTP, SQLite, registro **desligado**, SSH **desligado** |
| dados | `run/gitea/data/gitea.db` (SQLite) + `run/gitea/repos/` | estado de runtime — **não versionado** |
| porta | `run/gitea/.port` | lido pelos scripts/`lib/gitea.sh` |
| admin | usuário `mojadmin` | criado via CLI |
| **segredo** admin | `run/secrets/gitea-admin.token` (**600**) | cria users/repos, `Sudo:`; **nunca** ecoado |
| **segredo** webhook | `run/secrets/gitea-webhook.secret` (**600**) | HMAC do webhook (Fase 7) |
| tokens por autor | `run/secrets/gitea-user-tokens/<login>` (**600**, dir **700**) | cache; mint via CLI (keyless) |

Tudo sob `run/` é **runtime, fora do repo** (configurável por `RUNDIR`). Os segredos **nunca**
são versionados nem impressos.

### Subir / parar (dev)

```bash
cd /home/ribas/moj
bash cdmoj/server/bin/start-gitea.sh &        # idempotente; não faz nada se já responde
curl -fsS http://127.0.0.1:3939/api/v1/version  # {"version":"1.26.4"}
# parar:
pkill -f 'run/gitea/gitea .* web'
```

`start-all.sh` já sobe o Gitea **antes** do fcgiwrap (se o binário existir).

---

## 2. Provisionar do zero (host novo)

```bash
cd /home/ribas/moj
GHOME=run/gitea; mkdir -p "$GHOME/custom/conf" run/secrets
chmod 700 run/secrets

# 1) binário (escolha a versão; linux-amd64)
curl -fsSL -o "$GHOME/gitea" https://dl.gitea.com/gitea/1.26.4/gitea-1.26.4-linux-amd64
chmod +x "$GHOME/gitea"; echo 3939 > "$GHOME/.port"

# 2) app.ini — gere SECRET_KEY/INTERNAL_TOKEN/JWT_SECRET (NÃO reaproveite os de outro host)
SECRET_KEY=$("$GHOME/gitea" generate secret SECRET_KEY)
INTERNAL_TOKEN=$("$GHOME/gitea" generate secret INTERNAL_TOKEN)
JWT_SECRET=$("$GHOME/gitea" generate secret JWT_SECRET)
cat > "$GHOME/custom/conf/app.ini" <<INI
APP_NAME = MOJ Problemas (Gitea)
RUN_USER = $USER
RUN_MODE = prod
WORK_PATH = $PWD/run/gitea
[server]
PROTOCOL = http
HTTP_ADDR = 127.0.0.1
HTTP_PORT = 3939
DOMAIN = localhost
ROOT_URL = http://localhost:3939/
DISABLE_SSH = true
START_SSH_SERVER = false
LFS_START_SERVER = false
OFFLINE_MODE = true
[database]
DB_TYPE = sqlite3
PATH = $PWD/run/gitea/data/gitea.db
[repository]
ROOT = $PWD/run/gitea/repos
DEFAULT_BRANCH = master
[security]
INSTALL_LOCK = true
SECRET_KEY = $SECRET_KEY
INTERNAL_TOKEN = $INTERNAL_TOKEN
PASSWORD_HASH_ALGO = argon2
[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = false
DEFAULT_KEEP_EMAIL_PRIVATE = true
[log]
ROOT_PATH = $PWD/run/gitea/log
LEVEL = warn
MODE = file
[migrations]
ALLOW_LOCALNETWORKS = true
[oauth2]
JWT_SECRET = $JWT_SECRET
INI

# 3) primeiro start (cria o schema), depois admin + token
bash cdmoj/server/bin/start-gitea.sh & sleep 4
GITEA_WORK_DIR="$PWD/run/gitea" "$GHOME/gitea" -c "$GHOME/custom/conf/app.ini" \
  admin user create --admin --username mojadmin --email moj@localhost \
  --password "$(head -c 18 /dev/urandom | base64 | tr -dc A-Za-z0-9)Aa1." --must-change-password=false

# token admin -> secrets (modo 600). A saída é "...successfully created: <40hex>"
GITEA_WORK_DIR="$PWD/run/gitea" "$GHOME/gitea" -c "$GHOME/custom/conf/app.ini" \
  admin user generate-access-token --username mojadmin --scopes all --token-name moj-admin \
  | grep -oE '[a-f0-9]{40}' > run/secrets/gitea-admin.token
chmod 600 run/secrets/gitea-admin.token
head -c 32 /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 32 > run/secrets/gitea-webhook.secret
chmod 600 run/secrets/gitea-webhook.secret
```

Verificação: `curl -fsS -H "Authorization: token $(cat run/secrets/gitea-admin.token)"
http://127.0.0.1:3939/api/v1/user | jq '{login,is_admin}'` → `{"login":"mojadmin","is_admin":true}`.

> **Por que CLI para os tokens?** A API `/users/{u}/tokens` exige **BasicAuth** (senha) — que
> **não guardamos**. O CLI (`admin user generate-access-token`) opera no DB **sem senha**
> (keyless), rodando como o mesmo usuário do SO. É assim que `gitea_ensure_user_token` mina o
> token de cada autor (cacheado em `run/secrets/gitea-user-tokens/<login>`, 600).

---

## 3. systemd (produção, user service)

```bash
mkdir -p ~/.config/systemd/user
cp /home/ribas/moj/cdmoj/server/etc/systemd/moj-gitea.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now moj-gitea.service
loginctl enable-linger "$USER"     # mantém o serviço vivo sem sessão logada
```

A API do MOJ (`common.conf`) aponta para o Gitea por `GITEA_URL` (default
`http://localhost:3939`) + os caminhos `GITEA_BIN`/`GITEA_CONFIG`/`GITEA_WORK_DIR`.

---

## 4. Reverse proxy & HTTPS (opcional)

O Gitea escuta só em **127.0.0.1:3939** (`HTTP_ADDR=127.0.0.1`, `OFFLINE_MODE=true`). Para
expô-lo (ex. UI web de revisão), faça proxy por `~/nginx-proxy` para um subdomínio dedicado
(ex. `git.moj.<base>`) e ajuste `ROOT_URL`/`DOMAIN`. **Não é necessário** para a operação do
MOJ: a API fala com o Gitea por loopback; os autores nunca o acessam direto.

---

## 5. Onde rodar + ver os pacotes (NFS)

- **Mesmo host da API** (default): simples; o validador/`gen-problem-json.sh` rodam nos juízes,
  que já enxergam os pacotes via **NFS** (`MOJ_PROBLEMS_DIR`, default `/home/ribas/moj/moj-problems`).
- **Box separado** para o Gitea: ok também — só `GITEA_URL` muda. Garanta que **os juízes**
  continuem com o checkout/NFS dos pacotes para validar/calibrar (o Gitea guarda o git; o
  pipeline de validação roda onde os pacotes estão montados).

A migração dos repos do gitolite/sr.ht/gitlab para o Gitea é a **Fase 6** (`mojtools/migrate/*`,
incremental, reversível, um curso por vez).

---

## 5.1 Webhook (push → reindex automático)

Cada repo de problema recebe (automático, no `repo-create`/migração via `gitea_ensure_webhook`)
um **webhook de push** apontando p/ `MOJ_WEBHOOK_URL` (default a URL pública do MOJ), autenticado
por **HMAC** com `gitea-webhook.secret`. Em cada push, o MOJ (`/problems/webhook`) enfileira
`index` dos problemas alterados → 1 juiz valida + reindexa. Requisitos:

- **`MOJ_WEBHOOK_URL`** deve ser alcançável **pelo Gitea** (mesmo host: pode ser a URL pública,
  ou um `http://127.0.0.1:<porta-nginx>/api/v1/problems/webhook` com o vhost certo via `Host`).
- O segredo do webhook é o mesmo `run/secrets/gitea-webhook.secret` (modo 600).
- Confira a entrega em *Settings → Webhooks → Recent Deliveries* do repo no Gitea.

## 6. Backup & restauração

Estado vivo = **SQLite** + **repos** + **segredos**:

```bash
systemctl --user stop moj-gitea.service     # consistência do SQLite
tar czf gitea-backup-$(date +%F).tgz -C /home/ribas/moj \
    run/gitea/data run/gitea/repos run/gitea/custom/conf/app.ini run/secrets
systemctl --user start moj-gitea.service
```

Restaurar = extrair no mesmo layout e subir. **Mantenha `SECRET_KEY`/`INTERNAL_TOKEN` do
`app.ini`** junto do `data/` — sem eles os dados cifrados não abrem.

---

## 7. Segurança (invariantes)

- Segredos **só** em `run/secrets/` modo **600** (dir 700). **Nunca** no `.git/config`, nunca
  ecoados, nunca versionados. O broker injeta o token via `GIT_ASKPASS` (env do filho).
- Tokens por autor têm escopo mínimo (`write:repository`), são **efêmeros/rotacionáveis**
  (`gitea_user_token_clear <login>` força re-mint) e ficam só no cache 600.
- **Registro desligado** (`DISABLE_REGISTRATION=true`): contas nascem só via API admin do MOJ
  (confused-deputy **intencional** — o MOJ é o provedor de identidade).
- **SSH desligado**: todo git é HTTPS por loopback com token. Sem gestão de chaves.
- Webhook (Fase 7) autenticado por HMAC com `gitea-webhook.secret`.
