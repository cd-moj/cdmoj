# MOJ — Visão geral (comece por aqui)

O **MOJ** (Melhor/Meta Online Judge, `moj.naquadah.com.br`) é um juiz online escrito
em **bash**. Este repositório é a **v2 API-first**: nginx + backend bash (fcgiwrap) +
frontend estático modular, lendo o **mesmo `contests/<id>/`** do sistema legado (nada
de migração de dados; o Apache antigo podia rodar em paralelo).

> Fluxo de submissão/julgamento e como os daemons conversam: ver **[FLOW.md](FLOW.md)**.
> Contrato de rotas: **[API.md](API.md)** (+ `web/api/openapi.json`). Placar: **[SCOREBOARD.md](SCOREBOARD.md)**. Deploy: **[DEPLOY.md](DEPLOY.md)**. Plano original: **[PLAN.md](PLAN.md)**.

> **Convenção de commit:** mensagens em português, no presente, prefixadas pelo componente
> (ex.: `problemas: …`). O rodapé leva **apenas** `Co-Authored-By:` — **nunca** uma linha
> `Claude-Session:` (é ruído no histórico). Vale também p/ assistentes de IA.

> **Documentação junto com o código (doc atrasada = bug):** ao mudar comportamento ou contrato,
> atualize a doc no **mesmo commit** — rotas/campos em **[API.md](API.md)** _e_ em
> `../web/api/openapi.json` (mantenha os dois em sincronia); arquitetura/fluxo aqui e em
> **[FLOW.md](FLOW.md)**. `bash docs/build-html.sh` refaz o HTML.

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
    score/         build.sh (recalcula placar), stats-gen.sh (gera o cache de estatísticas), jplag-run.sh
    etc/           common.conf, nginx/, systemd/
  web/             frontend vanilla (ES modules, sem build), servido estático
    shared/        api.js auth.js ui.js editor.js charts(/lib) flags.js sonic.js contest-host/guard/shell.js contest-config/
    index/ contests/ status/ treino/ contest/  (home, arquivo de encerrados, status público, treino, contest)
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
quartis), **freeze** (esconde resultados após o horário; `build.sh` gera `placar.txt` público
congelado e `placar-full.txt` completo — `.admin`/`.judge` + allowlist `SCORE_FULL_USERS` veem
o completo), tempo de solução **relativo ao início** (não EPOCH), e nav por papel. Usuários comuns
têm no menu uma página própria de **Backup de arquivos** (`/contest/backup/`) p/ guardar versões de
solução (não polui a home); o admin vê/baixa todos na aba **Backups** (zip por usuário). Quando há
usuário **`.staff`** no contest, os alunos ganham também a página **Impressão** (`/contest/print/`):
enviam um arquivo (PDF/imagem/texto/código) e acompanham o status (pendente→processada→entregue) —
ver **Impressão (`.staff`)** abaixo. Os problemas usam o **id canônico `coleção#problema`** (igual ao
treino — é o que o juiz usa p/ achar o pacote); o editor é o **CodeMirror compartilhado**
(`shared/editor.js`, com tela cheia e nova janela) e a seleção de linguagens é a lista inteira do
MOJ (`shared/languages.js`), reduzida à whitelist do conf `LANGUAGES=` quando definida. O placar
dos contests novos é **materializado a partir do `controle/history`** (`score/dstate.sh`, chamado
pelo `score/build.sh`), já que o pipeline assíncrono não escreve os `.d/<pidx>`. O aluno recebe
**aviso de novidades** (notícias + clarifications respondidas, com badge de não lidas — poll de
`/contest/updates`) e vê o **tempo-limite** por linguagem no detalhe do problema (ocultável pelo
admin). **Acesso por fase+papel (forçado pela API, não só no front)**: `.admin`/`.judge` veem os
problemas e **submetem a qualquer momento** (antes/durante/depois); o usuário normal **só vê os
problemas após o início** (antes disso, ao logar, recebe uma **tela de contagem regressiva**) e
**só submete durante a janela** (`/contest/problems` devolve `locked:"not_started"` e `/submit`
recusa com `403` fora da janela — `contest_not_started`/`contest_ended`); `.staff` não vê problemas
nem submete; `.mon` submete **só na janela** (como o normal) mas fica **fora do placar**. Telas internas:

- **`/contest/admin/`** — hub com sub-abas: **Situação** (painel ao vivo e acionável: logados +
  alerta de multi-sessão, **ações sugeridas**, **saúde por juiz** (online/offline/cache/linguagens),
  fila, pendentes com tempo de espera, **submissões recentes**, **por problema**, métricas avg/p95
  e timeline com picos — `/contest/admin/dashboard`, auto-refresh; downloads CSV em Auditoria/Log),
  **Configurações** (tempos, login on/off, abertura, freeze, toggles editor/log/código/**tempo-limite**/anônimo,
  gate de UA, **linguagens permitidas do contest**),
  **Problemas** (add/remover/reordenar/renomear), **Aparência** (cores/Sonic, países/escolas,
  regiões, básico), **Usuários** (add/reset/remover/**deslogar**/**desabilitar**/**troca de senha
  geral**), **Impressão** (escopo por **regex** de cada `.staff` — semeável das regiões —
  `/contest/admin/staff-filters`), **Log & sessões** (sessões com **alerta de UA/IP diferente**,
  deslogar, filtro/deslogar por UA, log de acessos), **Auditoria** (feed cronológico unificado no
  **instante exato** de cada evento: ações de admin + logins + **submissões** (no sub_epoch) +
  **veredictos** (no finalized_at, com o juiz) — cada submissão gera 2 entradas, submissão e
  correção, p/ o trace completo; `/contest/admin/audit-log`, filtrável + download CSV). **Problemas** também
  edita as **linguagens permitidas por problema** (`problem-langs.json`), que o editor do aluno e a
  tabela de tempo-limite respeitam. **Rejulgar** (aba "todas submissões") agora reconstrói a fonte
  arquivada e re-julga de fato (marca como pendente na Situação). Criação **não sobrescreve** a conta
  admin já existente (senha digitada respeitada; em modo compartilhado o `<login>.admin` existente é
  reutilizado).
- **`/contest/allsubmissions/`** — todas as submissões (ver código/log, filtrar, marcar
  grupo/todos, **rejulgar em lote**).
- **`/contest/statistics/`** — estatísticas ricas (totais, por problema, quartis, distribuição,
  tentativas, veredicto×problema, balões, linha do tempo).
- **`/contest/clarification/`** — perguntas (por problema/geral); admin/judge/mon respondem
  (pública/privada) e publicam **notícias do contest**. O **asker é anônimo** p/ os juízes
  (tratamento isonômico; recuperável só pelo admin via auditoria); responder exige **reserva**
  (`clarification-claim`, TTL 5 min) p/ dois juízes não pegarem a mesma; o juiz manda **aviso
  oficial** (Q+A público, autor oculto) e o **juiz-chefe/admin** editam respostas/notícias já dadas.
- **`/contest/judge/`** — área de **avaliação**. **`/contest/jplag/`** — similaridade das
  soluções aceitas (roda o jar, mostra pares + comparação lado-a-lado).
- **`/contest/chief/`** — **painel do juiz-chefe (`.cjudge`)** e do admin: **Situação** da
  avaliação, **Conflitos** (com alerta vibrante) e a config do veredicto manual (opções + matriz).

### Juiz `.judge`, juiz-chefe `.cjudge` & veredicto manual
**Papéis** (sufixo no login; ver `lib/auth.sh`): `.judge` submete a qualquer hora (fora do
placar/estatísticas), responde clarifications e cria avisos; **`.cjudge`** (juiz-chefe) **herda**
o juiz (`is_judge` vale p/ ele) + extras **escopados** (`is_chief`): editar notícias/respostas já
dadas, ver **Situação** e **Todas Submissões** (mesmas ops do admin), **resolver conflitos** e
editar a config de auto-veredicto — **não** é admin pleno. `.cjudge` está nas quatro listas de
sufixo (auth/score-common/stats-gen/login) p/ ficar fora do placar e isento da janela de login.

**Veredicto manual** (opt-in por contest, `MANUAL_VERDICT`): quando ligado, o **daemon segura** o
veredicto computado p/ revisão humana — grava `contests/<c>/review/<id>.json` e deixa o history
provisório (o aluno segue vendo "julgando"); a exceção é a **matriz `auto-verdicts.json`**
(problema × linguagem × veredicto, editável por admin/chief) que libera combinações automáticas.
Dois `.judge` **pegam** a submissão (máx 2, **1 ativa** por juiz, **TTL 5 min** com **+5**, ou
**desistir**), veem **log + fonte + veredicto computado** e escolhem um veredicto de uma **lista
configurável** (`final-verdicts.json`, `{label,verdict}`; default = as 6: 1-YES…6-Contact staff).
**Dois no mesmo → vai ao aluno**; **diferentes → conflito**, que **só o juiz-chefe resolve** (com
alerta vibrante). A liberação enfileira `setverdict`, consumido pelo daemon e finalizado pelo
**escritor único** (`update_history` + `results/<id>.json`), então o veredicto manual entra no
timeline de auditoria como qualquer outro. **TUDO** é auditado (`clar-*`, `news-edit`, `final-/
auto-verdicts-set`, `review-claim/extend/giveup/vote/agree/conflict/resolve`, `verdict-held/released`).
**Mudou o daemon → reinicie-o** (mantendo `INTAKE_MODE`/`JUDGE_BACKEND`).
- **`/contest/staff/`** — **Impressão (`.staff`)**: o usuário `.staff` opera o balcão de impressão
  de uma sede. Ao logar é **redirecionado** para cá (não acessa a home do contest).
  **Não submete** (sem home de contest nem clarifications); vê o **placar** como
  usuário normal (congela no freeze) e a **fila de tarefas** recebidas, filtrada pela sua lista de
  **regex** (sedes distribuídas; lista vazia = vê tudo; o admin configura na aba **Impressão**).
  Fluxo: **pegar** (claim, evita impressão dupla entre abas) → **imprimir** o PDF gerado pelo
  servidor (`pr_build_pdf` em `lib/print.sh`: capa+documento normalizado em A4 via `paps`/`magick`/
  `libreoffice`+`pdfunite`, build-once com cache; **código sai com linhas numeradas**) → **entregue**.
  A **folha de rosto** (raster, letras garrafais via `caption:` auto-ajustável que sempre cabe) traz
  o **nome do time/participante** (+ universidade) e o login, o **nº sequencial** (conferência), o
  **nº de páginas do documento** (exceto a capa) e um campo **assinatura + hora**. Há **modo automático**: a aba
  reserva, imprime (iframe + `window.print()`) e marca **processada** ao detectar a impressão
  (`onafterprint`); para impressão sem o diálogo do SO, rode o navegador em **kiosk**. **Toda**
  operação é auditada (`print-request`/`-claim`/`-served`/`-processed`/`-delivered`/`-download`,
  `staff-filters`). O admin habilita/desabilita por conf `PRINT` (toggle `allow_print`).

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
