# mojinho-bot — bot do Telegram do MOJ (cliente da API)

Este diretório tem **dois** bots:

| arquivo | papel |
|---|---|
| `mojinho.sh` | bot **original** (referência). Acopla ao MOJ pelo **spool** (escreve arquivos de comando) e fala `nc` direto com os juízes. **Não é mais usado**; mantido como referência histórica. |
| `mojinho-api.sh` | bot **novo**. É um **cliente fino da API REST v1** do MOJ: cada ação administrativa vira uma chamada HTTP (`curl` + header `Host`). Sem spool, sem `nc`. É o que roda em produção. |

## O que mudou (API client vs spool/nc)

- **Sem escrita no spool / sem `nc`.** Antes o bot criava arquivos em
  `~moj/work/submissions/...` e abria sockets para os juízes. Agora ele
  **chama a API** (`POST/GET http://127.0.0.1:8080/api/v1/...`) com o header
  `Host: moj.charge.naquadah.com.br` (o nginx roteia por Host).
- **Token do Telegram só do arquivo.** O token **não** está mais hardcoded no
  script; é lido **exclusivamente** de `./token`.
- **Config externa.** Endpoint da API, host, base pública (links), credenciais
  de admin e a lista de GODS vêm de `./bot.conf` (veja `bot.conf.sample`).
- **Autenticação por sessão.** O bot obtém um **token de admin** logando uma vez
  (`POST /auth/login?contest=<contest>` com um usuário `*.admin`), cacheia esse
  token e o reusa como `Authorization: Bearer ...`. Em `401`, faz **re-login**
  automático e repete a chamada.
- **JSON com `jq`.** O bot novo usa `jq` (o original usava `jshon`, que não está
  instalado neste host). A API também é toda `jq`.
- **Continuam locais (sem API):** `/cantar` (sorteia um `musica.*`), `/amigod`,
  `/help`. Os **logs de auditoria** (`log-getcode.txt`, `log-getlog.txt`,
  `log-cantar.txt`) também continuam locais.

## Configuração

### 1. Token do Telegram — `./token`

O bot lê o token **apenas** deste arquivo. O parser pega a primeira linha que
casa com o formato de token (`<digitos>:<resto>`), então linhas de lixo/comentário
são ignoradas. Proteja o arquivo:

```bash
chmod 600 token
```

### 2. `./bot.conf` (a partir do sample)

```bash
cp bot.conf.sample bot.conf
chmod 600 bot.conf       # contém a senha do admin
$EDITOR bot.conf
```

Variáveis (defaults entre parênteses; o `bot.conf` sobrescreve):

| variável | descrição |
|---|---|
| `MOJ_API` (`http://127.0.0.1:8080/api/v1`) | base da API REST (o bot roda no servidor) |
| `MOJ_HOST` (`moj.charge.naquadah.com.br`) | header `Host:` enviado à API (o nginx roteia por Host) |
| `MOJ_WEB` (`https://moj.charge.naquadah.com.br`) | base pública usada **só** nos links das respostas |
| `MOJ_ADMIN_CONTEST` (`treino`) | contest do usuário `*.admin` usado no login |
| `MOJ_ADMIN_USER` | login do admin do bot (**precisa terminar em `.admin`**) |
| `MOJ_ADMIN_PASS` | senha desse admin |
| `GODS[<username>]=true` | usuários do Telegram autorizados aos comandos administrativos |

> **Credenciais de admin do bot:** crie um usuário `*.admin` no `passwd` do
> contest `MOJ_ADMIN_CONTEST` (ex.: `bot.admin`). A API trata `login == *.admin`
> como admin (ver `is_admin` em `server/api/v1/lib/auth.sh`). Esse é o usuário
> cujas credenciais vão em `MOJ_ADMIN_USER`/`MOJ_ADMIN_PASS`. Mantenha-as **só**
> no `bot.conf` (modo `600`), nunca no `.sample` nem no script.

## Como rodar

### Direto (debug)

```bash
cd ~/moj/mojinho-bot
bash mojinho-api.sh
```

### Como serviço (systemd, sem root)

A unit **`moj-bot.service`** está em `server/etc/systemd/` (é um *sample* —
ajuste o `ExecStart` para `mojinho-api.sh`). Instalação no nível do usuário
(`systemctl --user`), conforme `server/etc/systemd/README.md`:

```bash
mkdir -p ~/.config/systemd/user
ln -sf ~/moj/server/etc/systemd/moj-bot.service ~/.config/systemd/user/
# garanta que o ExecStart aponte para mojinho-api.sh:
#   ExecStart=/bin/bash %h/moj/mojinho-bot/mojinho-api.sh
systemctl --user daemon-reload
systemctl --user enable --now moj-bot.service
journalctl --user -u moj-bot -f
```

> Para o serviço subir no boot sem sessão interativa:
> `sudo loginctl enable-linger "$USER"` (única coisa que pede root; opcional).

## Mapa comando → endpoint da API

| comando do Telegram | método + endpoint | corpo / query | observações |
|---|---|---|---|
| `/participar CONTEST [SIGLA]` | `POST /admin/adduser` | `{contest,login,fullname,email}` | `login` = username do Telegram; `email` carrega o `chat_id`. Responde login + **senha gerada** + URL. `409` → "já participa"; `404` → contest inválido. |
| `/trocarsenha CONTEST` | `POST /admin/passwd` | `{contest,login,newpass}` | gera nova senha (`palavras-para-senha` + número) e troca. Só em chat privado. |
| `/alteravigenciacontest CONTEST EPOCH` | `POST /admin/contest/extend` | `{contest,end_epoch}` | estende a vigência. **GOD**. |
| `/synctreino` | `POST /admin/synctreino` | — | enfileira a sincronização do treino livre. **GOD**. |
| `/rejulgarsubmissao CONTEST ID [ID2 …]` | `POST /admin/rejudge` | `{contest,ids:[…]}` | IDs no formato `TIME:HASH`. **GOD**. |
| `/rejulgarcontestproblem CONTEST PROBLEM` | `POST /admin/rejudge` | `{contest,problem}` | rejulga um problema inteiro. **GOD**. |
| `/getcode CONTEST TIME:HASH` | `GET /submission/source` | `?contest=&time=&id=` | separa `TIME:HASH` em `time` (epoch) + `id` (32-hex); envia o fonte como **documento**. |
| `/getlog CONTEST TIME:HASH` | `GET /submission/log` | `?contest=&time=&id=` | idem; envia o log (gzip) como **documento**. |
| `/onqueue` | `GET /ops/queue` | — | total + por-contest. **GOD**. |
| `/listjudgesmachine` | `GET /ops/judges` | — | status/specs das máquinas (best-effort). **GOD**. |
| `/problemtl PROBLEM [PROBLEM2 …]` | `GET /ops/problemtl` | `?problem=<p>` | time limits do problema nos juízes. **GOD**. |
| `/updateproblemset REPO` | `POST /ops/updateproblemset` | `{repo}` | pede aos juízes para atualizar o problemset. **GOD**. |

### Comandos **locais** (sem API)

| comando | o que faz |
|---|---|
| `/cantar` | sorteia um `musica.*` e canta; registra em `log-cantar.txt` |
| `/amigod` | responde se o usuário é GOD |
| `/help` | lista os comandos (e os de GOD, se aplicável) |

### Autenticação (resumo do fluxo)

1. `moj_token()` garante um token: se não houver, chama `moj_login()`.
2. `moj_login()` faz `POST /auth/login?contest=$MOJ_ADMIN_CONTEST` com
   `{username:$MOJ_ADMIN_USER, password:$MOJ_ADMIN_PASS}` e guarda `.token`.
3. `api()` chama a API com `Host: $MOJ_HOST` + `Authorization: Bearer <token>`.
   Em `401`, refaz o login **uma vez** e repete.

## Diferenças de formato (atenção ao migrar comandos)

- **`getcode`/`getlog` agora exigem o CONTEST** e separam o hash antigo
  (`TIME:HASH`) em `time` + `id` (a API recebe os dois separados).
- **`rejulgarsubmissao`/`rejulgarcontestproblem` agora exigem o CONTEST**
  (a API enfileira por contest).
- Respostas da API seguem o envelope `{"success":true, …}` (ok) ou
  `{"success":false,"error":{"message","code"}}` (erro); o status HTTP vem no
  header `Status:` (o bot lê via `curl -w 'HTTP %{http_code}'`).

## Dependências

`bash`, `curl`, `jq`. (O bot original também usava `jshon`, que **não** está
instalado neste host — por isso o bot novo é todo `jq`.)
