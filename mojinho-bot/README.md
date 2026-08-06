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
vinculados) **+** `ALERT_GROUP_CHAT`.

O item traz dois campos que mudam a entrega — a API decide, o bot obedece:

| Campo | Efeito |
|---|---|
| `group:false` | mensagem **dirigida a uma pessoa** (ex.: convite de time pendente): NÃO copiar no `ALERT_GROUP_CHAT`. ⚠️ Ler com `.group == false` — `.group // true` daria `true` para `false` (o `//` do jq trata `false` como vazio) e o grupo receberia a DM de todo mundo. |
| `loud:true` | entregar **com notificação** (`disable_notification:false`). O default do `tg_send` é silencioso: alerta de operação não acorda ninguém; lembrete de inscrição precisa ser visto. |

A API entrega no máximo `ALERT_CLAIM_MAX` (30) itens por poll e o bot dá `sleep 0.05` entre envios
— o Telegram corta acima de ~30 msg/s. O que sobra sai no poll seguinte (~25 s).

Os `.admin` recebem DM só depois de vincularem o Telegram na
seção **📨 Telegram** do perfil (`/treino/perfil/` → botão "🔗 Vincular Telegram", deep-link de
`POST /treino/telegram/link-start`; desfazer = `POST /treino/telegram/unlink`).

## Rodar

Direto (debug): `bash mojinho-api.sh`. **Produção: enjaulado** (abaixo) via
`server/etc/systemd/moj-bot.service` (`ExecStart=/bin/bash %h/moj/cdmoj/mojinho-bot/run-caged.sh`):

```
cp server/etc/systemd/moj-bot.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now moj-bot      # ⚠ ENABLE, não só start
systemctl --user is-enabled moj-bot        # tem de dizer "enabled"
```

⚠ **`start` sozinho NÃO volta no reboot** — unit comum de usuário precisa do symlink de
`enable` (quadlet é ativado pelo generator, unit comum não). Foi assim que o bot ficou fora
depois do reboot de 2026-08-04. A queda fica visível na página **`/status/`** (linha "🤖 bot
de alertas", via `run/alerts/bot.alive` tocado a cada poll) e, quando o bot volta, os `.admin`
recebem uma DM com o período fora do ar (condição `bot_gone` em `lib/alerts.sh`).

## Rodando enjaulado (produção — `run-caged.sh`)

`run-caged.sh` lança o bot numa jaula **bwrap** de mount-namespace mínimo: o bot NÃO enxerga
`/home`, o workspace, `contests/`, `run/` nem `moj-problems/` — só `/usr` (+`/bin` etc. RO), um
`/etc` mínimo (DNS+TLS), `/proc`, `/dev`, `/tmp` efêmero e `/bot` (tmpfs) com o código RO e os
segredos RO. O único arquivo gravável é o `mojinho-offset` (estado do `getUpdates`, persistido
fora). A rede é compartilhada (Telegram + API no loopback). Unshares: tudo MENOS `net`.

1. **Dir vivo** (default `$HOME/mojinho-live`, 700 — fora do checkout; override `MOJINHO_LIVE`):
   - `token` (600) — o token do Telegram (uma linha `NNNN:AAAA…`);
   - `bot.conf` (600) — copie de `bot.conf.sample`; em produção use
     `MOJ_API=http://127.0.0.1/api/v1` + `MOJ_HOST`/`MOJ_WEB` do vhost real e **`BOT_TOKEN=mojb_…`
     direto** (o mesmo valor de `run/secrets/bot.token`) — assim a jaula não monta nada de `run/`;
   - `mojinho-offset` — criado sozinho se faltar;
   - `hosts` (opcional) — substitui o `/etc/hosts` da jaula; ponha
     `127.0.0.1 <vhost-da-api>` p/ a API resolver ao loopback com TLS válido
     (hairpin NAT do host costuma não voltar — foi o caso do newmoj).
2. **Host Ubuntu ≥ 24.04**: `apt install bubblewrap` e libere userns **só p/ o bwrap** com o
   perfil AppArmor (mesma receita da máquina de juiz, `judge/README.md`):
   ```
   # /etc/apparmor.d/bwrap
   abi <abi/4.0>,
   include <tunables/global>
   profile bwrap /usr/bin/bwrap flags=(unconfined) {
     userns,
     include if exists <local/bwrap>
   }
   ```
   `apparmor_parser -r /etc/apparmor.d/bwrap`. O script valida tudo isso e aborta com
   mensagem clara (inclusive se o `bwrap` for o `fbwrap` no-op do firejail).
3. `bash run-caged.sh` (ou pela unit systemd). Nenhum segredo passa por argv/env do host
   (`--clearenv`; token só via arquivo montado RO).

## Dependências
`bash`, `curl`, `jq` (+ `bubblewrap` p/ a jaula).
