# MOJ — Deploy & teste (nginx + fcgiwrap + daemons)

Tudo roda **user-space como `ribas`** (sem root), reaproveitando o `~/nginx-proxy/`.

## Componentes

| Componente | O que é | Como sobe |
|---|---|---|
| **nginx** (`~/nginx-proxy`) | serve `web/` estático + proxy `/api/v1` → fcgiwrap | `~/nginx-proxy/proxy.sh reload` |
| **fcgiwrap** | roda o `router.sh` (API bash) num socket unix | `server/bin/start-fcgiwrap.sh` |
| **judged** (daemon) | consome o spool e **enfileira** p/ o pull (dev: julga inline mock/local), grava veredicto + placar | `server/daemons/judged.sh` |
| **juiz (agente pull)** | máquinas de julgamento: registram capacidade + puxam jobs | repo **judge** separado — ver `judge/README.md` (bring-up por máquina) e `server/judge-gw/PULL.md` |
| **mojinho-bot** | bot Telegram (cliente da API) | `mojinho-bot/mojinho-api.sh` |

> **Storage de problemas (MOJ-nativo):** cada problema é um repo git LOCAL em
> `MOJ_PROBLEMS_DIR/<org>/<prob>` — o servidor commita direto e indexa inline; acesso por ORG
> (`contests/treino/var/orgs.json`). Não há serviço externo/LFS/webhook. Cut-over histórico:
> `server/bin/migrate-to-orgs.sh`.

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

Em produção, use os units systemd de `server/etc/systemd/` (`systemctl --user enable --now moj-fcgiwrap.socket moj-judged.service …`).

## nginx — `~/nginx-proxy/conf.d/moj.conf`

Server block para `moj.charge.naquadah.com.br` (coberto pelo cert wildcard `*.charge.naquadah.com.br`):
- `root /home/ribas/moj/cdmoj/web` + `index index.html` → frontend estático.
- `location /api/v1/` → `fastcgi_pass unix:/home/ribas/moj/run/fcgiwrap.sock`, com `SCRIPT_FILENAME=server/api/v1/router.sh` e `PATH_INFO` via `fastcgi_split_path_info`.
- `location /docs/` → serve esta documentação.

> **Nota:** o `fcgiwrap` vendorizado (`old/fcgiwrap/`) estava com um patch hardcoded do cdmoj antigo (ignorava `SCRIPT_FILENAME`). Foi restaurado ao padrão e recompilado em `server/bin/fcgiwrap`.

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

> **Cert (HTTPS):** o wildcard atual é `*.charge.naquadah.com.br` (um nível) — cobre
> `moj.charge…` mas **não** `<id>.moj.charge…` (dois níveis). Para HTTPS nos subdomínios,
> reemita o cert incluindo `*.moj.naquadah.com.br` (produção) / `*.moj.charge.naquadah.com.br`
> (teste). Em HTTP (8080) e via header `Host:` nos testes já funciona.

## CLIs servidas (`/moj` e `/moj-contest`)

`web/moj` e `web/moj-contest` são **artefatos de distribuição** (1 arquivo, com a lib comum
embutida) gerados de `moj-cli/` — **nunca** copie o script do repo direto (ele sourceia
`lib/core.sh` e quebraria fora do repo). Ao mudar o `moj-cli`, regenere e instale:

```bash
bash /home/ribas/moj/moj-cli/mkdist.sh
install -m755 /home/ribas/moj/moj-cli/dist/moj /home/ribas/moj/moj-cli/dist/moj-contest \
  /home/ribas/moj/moj-cli/dist/moj-judges /home/ribas/moj/cdmoj/web/
```

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
