# MOJ — Visão geral (comece por aqui)

O **MOJ** (Melhor/Meta Online Judge, `moj.naquadah.com.br`) é um juiz online escrito
em **bash**. Este repositório é a **v2 API-first**: nginx + backend bash (fcgiwrap) +
frontend estático modular, lendo o **mesmo `contests/<id>/`** do sistema legado (nada
de migração de dados; o Apache antigo podia rodar em paralelo).

> Fluxo de submissão/julgamento e como os daemons conversam: ver **[FLOW.md](FLOW.md)**.
> Contrato de rotas: **[API.md](API.md)** (+ `web/api/openapi.json`). Placar: **[SCOREBOARD.md](SCOREBOARD.md)**. Deploy: **[DEPLOY.md](DEPLOY.md)**. Plano original: **[PLAN.md](PLAN.md)**.

## Estrutura

```
moj/
  server/          backend bash sob nginx + fcgiwrap
    api/v1/
      router.sh    front-controller único: PATH_INFO -> handlers/<segmentos>.sh
      lib/         common.sh (resposta/JSON/validação/audit), params.sh, auth.sh, profile.sh, contest-create.sh
      handlers/    auth/ index/ treino/ contest/ submission/ admin/ ops/  (1 arquivo por rota)
    daemons/       judged.sh (consumidor do spool, inotify)
    judge-gw/      judge.sh (judge_run: mock/local/cluster) + result-sink.sh (push) + register.sh (heartbeat)
    score/         build.sh (recalcula placar), jplag-run.sh
    etc/           common.conf, nginx/, systemd/
  web/             frontend vanilla (ES modules, sem build), servido estático
    shared/        api.js auth.js ui.js editor.js charts(/lib) flags.js sonic.js contest-host/guard/shell.js contest-config/
    index/ status/ treino/ contest/    (home, status público, treino livre, ambiente de contest)
  judge/           cluster (master :27000 + workers pos/gpu/cm/hu) + mojtools (sandbox bubblewrap)
  mojinho-bot/     bot do Telegram (vira cliente da API)
  contests/<id>/   DADOS (conf, passwd, controle/history+placar.txt, data/, submissions/, mojlog/, var/, …) — fonte da verdade
  run/             estado de runtime (sessions/, spool/, results/, registry/, sockets)  [não versionado]
  docs/            esta documentação
```

## Camada de API

- **Roteador único** `router.sh`: sanitiza os segmentos (sem traversal), mapeia
  `/a/b/c` → `handlers/a/b/c.sh` e faz `source` do handler (que usa `$REQUEST_METHOD`).
- **Envelope** JSON consistente: `{success:true, …}` ou `{success:false,error:{message,code}}`,
  **sempre com o status HTTP correto** (`fail`/`ok_json` em `lib/common.sh`). Horários em EPOCH.
  Histórico e placar são **TXT** cru (eficiência + é o que o front parseia).
- **Auth** `Authorization: Bearer <token>` → sessões em `run/sessions/` (modo 700), gravadas
  com `printf %q` (o arquivo é *sourced*; nada de injeção). Papéis por sufixo no login:
  `.admin` / `.judge` / `.staff` / `.mon`.
- **Isolamento por subdomínio**: em `<id>.moj.<base>` o nginx injeta `CONTEST_HOST`; o
  `router.sh` só serve aquele contest (`auth`/`contest`/`submit`/`submission`) e o frontend
  redireciona o resto para `/contest/` (`shared/contest-guard.js`).
- **jq para todo JSON**; `contests/<c>/conf` é *sourced* — por isso a criação de contest
  escreve tudo com `printf %q`.

## Frontend

Vanilla ES modules, **sem build**, servido estático. `shared/` concentra o cliente de API
(fetch + Bearer + envelope), auth/token (localStorage), `ui.js` (`el()`, avatares, i18n
pt/en), o editor **CodeMirror 6** (via esm.sh, com fallback textarea), os gráficos SVG
build-free (`/lib/charts.js`), e os **assets offline**: bandeiras locais (`shared/flags/`,
271 países + 27 estados do BR) e GIFs do Sonic (`shared/assets/sonic/`). Editores de
configuração de contest reaproveitáveis em `shared/contest-config/` (cores, países/escolas,
regiões, básico) — os mesmos na criação e no admin do contest.

## O que existe (funcional)

### Home & treino livre
Home com notícias, contests (abertos/por vir/encerrados; abre cada um pelo **subdomínio**),
top10 e destaques; página pública **`/status/`** (health: fila por lista, máquinas
julgando, daemons). Treino livre: busca de problemas, página do problema com enunciado +
**editor CodeMirror** + upload + histórico com polling, stats por usuário (gráficos,
editor favorito, foto, privacidade), **stats por problema** (cache, linguagens, editores,
nuvem de avatares), e **painel admin do treino** (sessões/logs com UA+IP, busca/regex,
bulk logout/lock, notícias, **auditoria**, fila, máquinas).

### Criação de contest (`/treino/criar/`)
Permissão por **lista do admin OU threshold** de problemas resolvidos. Monta usuários
(**compartilhados do treino** ou **próprios**, com colagem fluida + senhas legíveis +
download de credenciais), **admin do contest obrigatório**, problemas do banco / por ID /
sorteio **semiautomático por tag e dificuldade**, configs visuais (cores/Sonic, países/escolas
por regex, regiões), e a opção de **criar vazio**. Template JSON + import de `.tar.gz`.

### Ambiente de contest (`<id>.moj.<base>`)
Login (com gate opcional por substring de **User-Agent**), página principal (problemas +
submissão + editor que o admin pode desligar), **placar** multi-modo (icpc/obi/treino/
heurístico/outro) com bandeiras locais, filtro por país/escola, modo **anônimo** (agregado/
quartis), e nav por papel. Telas internas:

- **`/contest/admin/`** — hub com sub-abas: **Configurações** (tempos, login on/off, abertura,
  freeze, toggles editor/log/código/anônimo, gate de UA), **Problemas** (add/remover/reordenar/
  renomear), **Aparência** (cores/Sonic, países/escolas, regiões, básico), **Usuários** (add/
  reset/remover/**deslogar**/**desabilitar**/**troca de senha geral**), **Log & sessões**
  (sessões com **alerta de UA/IP diferente**, deslogar, filtro/deslogar por UA, log de acessos).
- **`/contest/allsubmissions/`** — todas as submissões (ver código/log, filtrar, marcar
  grupo/todos, **rejulgar em lote**).
- **`/contest/statistics/`** — estatísticas ricas (totais, por problema, quartis, distribuição,
  tentativas, veredicto×problema, balões, linha do tempo).
- **`/contest/clarification/`** — perguntas (por problema/geral); admin/judge/mon respondem
  (pública/privada) e publicam **notícias do contest**.
- **`/contest/judge/`** — veredicto final do juiz. **`/contest/jplag/`** — similaridade das
  soluções aceitas (roda o jar, mostra pares + comparação lado-a-lado).

**Auditoria**: ações administrativas são logadas em `contests/<c>/var/admin-audit.log`
(e `treino/var/admin-audit.log` no treino) — o contest fica auto-contido.

### Juiz & daemons
Submissão **assíncrona** (spool + `inotify`), `judged.sh`, gateway `judge-gw/` com backends
mock/local/cluster, **resultado por push** (`result-sink`) e **registro/heartbeat** de
workers (`register.sh`) substituindo o polling duplo e a lista fixa de portas — detalhes em
**[FLOW.md](FLOW.md)**.

## Testes

Suítes de smoke em `server/test/smoke-*.sh` (cada uma sobe o `router.sh` com `CONTESTSDIR`/
`SESSIONDIR` de fixture e exercita os handlers de ponta a ponta). Rode todas:

```sh
cd server/test && for t in smoke*.sh; do bash "$t"; done
```

## Compilar esta documentação em HTML

```sh
bash docs/build-html.sh     # gera docs/html/*.html + index (usa pandoc)
```
