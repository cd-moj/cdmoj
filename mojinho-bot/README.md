# mojinho-bot — bot do Telegram do MOJ (transporte fino da API)

`mojinho-api.sh` é um **cliente fino** da API v1: a API é dona de toda a lógica, estado e
política; o bot só recebe updates do Telegram, repassa comandos à API e entrega mensagens/DMs
e o **outbox de alertas**. (O `mojinho.sh` legado — que escrevia no spool e falava `nc` com os
juízes, com token e GODS embutidos — está **gitignorado** e não é mais usado.)

## O modelo (o que mudou)

- **Sem `.admin`, sem GODS.** O bot autentica na API com um **token dedicado** `mojb_…`
  (`Authorization: Bearer mojb_…`, verificado por `require_bot`), guardado em
  `run/secrets/bot.token`. Não loga mais como usuário `.admin`.
- **Identidade Telegram = 1 conta.** Toda ação é ancorada no `telegram_id` (imutável): cadastrar,
  vincular e recuperar senha. Trocar de @username não cria conta nova.
- **Senha só por DM.** A API gera a senha e o bot a entrega no privado (posse do Telegram = prova).
- **Alertas.** A API decide o quê/quando alertar (juiz offline+fila, fila grande, daemon caído,
  com histerese/cooldown); o bot só drena `GET /ops/alerts` a cada volta do loop e envia.

## Configuração

1. **Token do Telegram** — só no arquivo `./token` (gitignorado). Uma linha `NNNN:AAAA…`.
2. **`./bot.conf`** — copie de `bot.conf.sample` (`chmod 600`, não comite). Define `MOJ_API`,
   `MOJ_HOST`, `MOJ_WEB`, `MOJ_CONTEST`, `BOT_TOKEN_FILE` (ou `BOT_TOKEN`), `ALERT_GROUP_CHAT`,
   `ALERT_POLL_SECS`.
3. **Token do bot p/ a API** — gere `run/secrets/bot.token`:
   ```
   printf 'mojb_%s' "$(head -c24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c32)" \
     > run/secrets/bot.token && chmod 600 run/secrets/bot.token
   ```
4. **`TELEGRAM_BOT_USERNAME`** (em `server/etc/common.conf`) = @username do bot, usado pela API
   p/ montar o deep-link do cadastro (`t.me/<bot>?start=<nonce>`). Produção: `mojinho_bot`.

## Comandos → endpoint

| Comando | Endpoint (bot-token, salvo `/status`) | O quê |
|---|---|---|
| `/start <nonce>` | `POST /treino/signup/verify` | confirma cadastro/vínculo iniciado na página (deep-link) |
| `/start` (sem nonce) | — | boas-vindas + link do cadastro |
| `/participar` | `POST /treino/signup/telegram` | cria+vincula a conta no treino (bot-first, idempotente) |
| `/trocarsenha` | `POST /treino/recover-password` | recupera a senha pelo vínculo Telegram |
| `/status` | `GET /index/status` (público) | saúde do MOJ (juízes/fila) |
| `/help`, `/cantar` | — | locais |

Comandos administrativos antigos (`rejulgar*`, `onqueue`, `listjudges`, `problemtl`,
`updateproblemset`, `alteravigencia`, `synctreino`, `getcode`, `getlog`) **saíram do bot** — use o
painel admin da web ou o `moj-cli`. O bot ficou restrito ao que é ancorado no Telegram do usuário.

## Loop de alertas

O loop faz long-poll curto de `getUpdates` (`timeout=ALERT_POLL_SECS`) e, a cada volta, chama
`deliver_alerts` → `GET /ops/alerts` → envia cada `item.text` para `item.chats` (DMs dos `.admin`
vinculados) **+** `ALERT_GROUP_CHAT`. Os `.admin` recebem DM só depois de vincularem o Telegram via
**Perfil → vincular Telegram** (deep-link de `POST /treino/telegram/link-start`).

## Rodar

Direto (debug): `bash mojinho-api.sh`. Serviço: `server/etc/systemd/moj-bot.service`
(`ExecStart=/bin/bash %h/moj/cdmoj/mojinho-bot/mojinho-api.sh`), `systemctl --user restart moj-bot`.

## Dependências
`bash`, `curl`, `jq`.
