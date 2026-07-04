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
  contests/<id>/   DADOS (conf, users/<login>/ (account.json+history+metrics+submissions), var/placar.txt, …) — fonte da verdade
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
regiões, básico, **settings/toggles** (`settings-editor.js`), **seletor de linguagens**
(`lang-picker.js`) e o **painel de busca+sorteio do banco** por coleção/tag/dificuldade
(`bank-panel.js`)) — os mesmos na criação e no admin do contest.

## O que existe (funcional)

### Home & treino livre
Home com notícias, contests (abertos/por vir/encerrados; abre cada um pelo **subdomínio**),
top10 e destaques; página pública **`/status/`** (health: fila por lista, máquinas
julgando, daemons). Treino livre: busca de problemas, página do problema com enunciado +
**editor CodeMirror** + upload + histórico com polling (cada submissão julgada mostra um **resumo**
abaixo do veredicto — "Passou em X/Y testes (Z%)" ou pontos, via `/submission/summary`), stats por usuário (gráficos,
editor favorito, foto, privacidade), **stats por problema** (cache, linguagens, editores,
nuvem de avatares), e **painel admin do treino** (sessões/logs com UA+IP, busca/regex,
bulk logout/lock, notícias, **auditoria**, máquinas, e — em abas com **índice/TOC** — **Fila &
tempo de resposta** (contadores de submissão + calibração, **o que cada máquina roda agora**
(calibração vs submissão), tempo de veredito e **mapas de calor de volume** de submissões e
calibrações) e **Estatísticas** (usuários, sessões, **problemas: total/públicos/privados**, quebra
**por autor**, **mapa de calor de entrada de públicos** e atividade diária). Fontes:
`/treino/admin/{queue,judges,response-stats,calib-activity,stats}`.

### Gestão de problemas (MOJ-nativo por org, keyless) & painel de status
Autoria/edição em `/problemas/` (storage: repo git LOCAL por problema em `<org>/<prob>`, sem Gitea;
acesso por **ORG** — membros escrevem, a trava `public_allowed` barra vazamento; só o login do MOJ). A aba **Painel**
(`GET /problems/status`) dá a visão agregada dos problemas de que o login é **dono ou colaborador**:
quantos/quais **calibrando**, **validados**, **calibrados**, **precisam recalibrar** (time-limit
desatualizado após mudança no pacote) e **com erro**, mais a **planilha de time-limits**. O acesso é
cortado na API (`owners_visible`): problema privado de terceiro **não** aparece. Staleness vem do
checksum do pacote **carimbado no índice de donos** (barato; ≤30 min de atraso); `/problems/tl`
recomputa na hora p/ 1 problema. A aba **Análise** (`GET /problems/my-stats`) dá o **panorama de
submissões** dos seus problemas agregado em **toda a plataforma** (treino + as turmas): tentativas,
acertos, erros mais comuns, linguagens, nº de contests e o **mais popular** — cache precomputado que
reconcilia o namespace do history (`problemas-apc#…`) com o índice de donos (`apc#…`) via `collections`;
só agregados (sem logins, sem nomes de contests) — não vaza prova privada.

### Store por-usuário, cadastro por Telegram e alertas
Todo contest guarda **um diretório por conta** (`contests/<c>/users/<login>/`: `account.json` +
`history`/`metrics.json`/submissões/logs/results/`photo.png` próprios). **Não existe `passwd`**:
auth (`verify_password`), placar (`sc_users`), perfis e listagens leem os `account.json` direto
(`USERS_FROM=<src>` cai para o `users/` do contest-fonte — participantes compartilhados têm dir
local sem `account.json`). Perfil (universidade/editor/privacidade) e metadados de time
(`.team{name,univ_short,univ_full,flag}`) vivem no próprio `account.json`. Ganhos: **trocar de
username = `mv` do diretório** e a maioria dos scripts de conta/julgamento só muda o caminho
(`lib/users.sh`, `emit_history_stream`). Os handlers de usuário do **admin do contest**
(`user-add`/`user-disable`/`user-remove`/`users-set-password`) escrevem no `account.json` (fonte
da verdade); remover = `mv` do diretório p/ `.removed-users/` (submissões preservadas).
Migração: `server/bin/store-migrate.sh <c>` (dry-run; `--apply`). O **treino** ganha um overlay de
**Telegram** (`lib/telegram.sh`): cadastro **web-first** (`/treino/cadastro/`) confirmado por deep-link
no bot, **1 Telegram = 1 conta** (anti-duplicata), recuperação de senha pelo vínculo, e senha entregue
**só por DM**. O **mojinho-bot** virou transporte fino (bot-token `mojb_`, sem `.admin`/GODS) e entrega
**alertas** de incidente que a **API** decide (`lib/alerts.sh` + `GET /ops/alerts`: juiz offline+fila,
fila grande, daemon caído, com histerese/cooldown) aos `.admin` com Telegram vinculado + grupo.

### Criação de contest (`/treino/criar/`) — wizard multi-etapa
Permissão por **lista do admin OU threshold** de problemas resolvidos. **Wizard em 8 passos**
(shell `criar.js` + `steps/*.js`; um objeto `draft` único — ir-e-voltar não perde nada):
**0 Começar** (em branco / **template salvo** / **duplicar contest meu** / importar `.tar.gz` /
baixar template JSON / salvar template de contest existente), **1 Dados** (nome/id/modo/datas),
**2 Problemas** (painel compartilhado de busca+sorteio por **coleção**/tag/dificuldade, add por
ID, enunciado custom HTML **e PDF** por problema), **3 Usuários** (compartilhados do treino ou
próprios, com colagem fluida + senhas legíveis + CSV), **4 Admin** (obrigatório), **5 Opções**
(o MESMO `settings-editor` da aba Configurações do admin — paridade total, + **prioridade** de
julgamento), **6 Visual** (cores/Sonic, países/escolas, regiões), **7 Revisão** (resumo +
validações + **Criar/Criar vazio** + **salvar como template**). Templates nomeados ficam no
servidor por criador (`/treino/contest-create/templates`); duplicar/exportar usam
`/treino/contest-create/{mine,export,duplicate}` (só dono/admin — 404 p/ terceiros).

### Ambiente de contest (`<id>.moj.<base>`)
Login (com gate opcional por substring de **User-Agent**), página principal (problemas +
submissão + editor que o admin pode desligar), **placar** multi-modo (icpc/obi/treino/
heurístico/outro) com bandeiras locais, filtro por país/escola, modo **anônimo** (agregado/
quartis), **freeze** (esconde resultados após o horário; `build.sh` gera `placar.txt` público
congelado e `placar-full.txt` completo — `.admin`/`.judge`/`.cjudge` + allowlist `SCORE_FULL_USERS` veem
o completo), tempo de solução **relativo ao início** (não EPOCH), e nav por papel. Contest **🕵️ SUPER
SECRETO** (conf `SECRET=1`, marcável na criação e no admin): **fora** das listagens públicas (home,
arquivo `/contests/`, `/status/`) e o **placar deixa de ser público** — `score`/`balloons`/`regions`/
`teams-meta` exigem sessão **daquele** contest (401 `secret_login_required`). A **tela de login/
countdown continua funcionando** p/ quem tem o link (`/contest/basic` segue público). Desmarcar exige
digitar o id. Usuários comuns
têm no menu uma página própria de **Backup de arquivos** (`/contest/backup/`) p/ guardar versões de
solução (não polui a home); o admin vê/baixa todos na aba **Backups** (zip por usuário). Quando há
usuário **`.staff`** no contest, os alunos ganham também a página **Impressão** (`/contest/print/`):
enviam um arquivo (PDF/imagem/texto/código) e acompanham o status (pendente→processada→entregue) —
ver **Impressão (`.staff`)** abaixo. Os problemas usam o **id canônico `coleção#problema`** (igual ao
treino — é o que o juiz usa p/ achar o pacote); o editor é o **CodeMirror compartilhado**
(`shared/editor.js`, com tela cheia e nova janela) e a seleção de linguagens é a lista inteira do
MOJ (`shared/languages.js`), reduzida à whitelist do conf `LANGUAGES=` quando definida. O placar
é **gerado de `users/*/metrics.json`** (mantidos incrementais pelo daemon; `score/build.sh` +
`sc_cells` — ver `SCOREBOARD.md`), sem varrer history. O aluno recebe
**aviso de novidades** (notícias + clarifications respondidas, com badge de não lidas — poll de
`/contest/updates`) e vê o **tempo-limite** por linguagem no detalhe do problema (ocultável pelo
admin). **Acesso por fase+papel (forçado pela API, não só no front)**: `.admin`/`.judge` veem os
problemas e **submetem a qualquer momento** (antes/durante/depois); o usuário normal **só vê os
problemas após o início** (antes disso, ao logar, recebe uma **tela de contagem regressiva**) e
**só submete durante a janela** (`/contest/problems` devolve `locked:"not_started"` e `/submit`
recusa com `403` fora da janela — `contest_not_started`/`contest_ended`); `.staff` não vê problemas
nem submete; `.mon` submete **só na janela** (como o normal) mas fica **fora do placar**. Telas internas:

- **`/contest/admin/`** — hub com **8 sub-abas** (abas antigas viram alias: `#staff`→Tarefas,
  `#log`/`#backups`→Usuários & sessões):
  **Situação** (painel ao vivo e acionável: logados + alerta de multi-sessão, **ações sugeridas**,
  **saúde por juiz** (online/offline/cache/linguagens), fila, pendentes com tempo de espera,
  **submissões recentes**, **por problema**, métricas avg/p95, timeline com picos e **cards de
  tarefas do staff** (impressões/balões pendentes) — `/contest/admin/dashboard`, auto-refresh);
  **Configurações** (tempos, login on/off, abertura, freeze, toggles editor/log/código/**tempo-limite**/anônimo/
  **🕵️ SUPER SECRETO**, gate de UA, **linguagens permitidas do contest** — o MESMO `settings-editor` do wizard;
  desmarcar o secreto exige **digitar o id**);
  **Problemas** (busca no banco **público + os privados do dono do contest** com badges, sorteio
  por coleção/tag/dificuldade, add/remover/reordenar/renomear — **sem** "add por id");
  **Aparência** (cores/Sonic, **países/escolas com preview de matches + import/export JSON +
  template dos sem match**, regiões, básico);
  **Usuários & sessões** (add/reset/remover/**deslogar**/**desabilitar**/**troca de senha geral**,
  **filtros** (busca + ativos/desabilitados/privilegiados, teto de 300 p/ contest 1000+) e
  **carga em lote** (colar/arquivo → `POST /contest/admin/users-bulk`, skip/update, CSV das
  credenciais — subir competidores depois de criar o contest só com contas administrativas)
  + sessões com **alerta de UA/IP diferente**, deslogar por UA, log de acessos + **backups** dos
  usuários);
  **Tarefas do staff** (`web/contest/admin/tasks.js` — panorama e AÇÃO: resumo em cards, a fila
  completa de **impressão + balões** de `/contest/staff/queue` com filtros/idade/CSV, o admin
  pode abrir o PDF e marcar processada/entregue, **desempenho por staff** e o **escopo por regex**
  de cada `.staff` — semeável das regiões — `/contest/admin/staff-filters`);
  **Tarefas do judge** (`shared/review-board.js` — o MESMO board da Situação do chief: cards da
  correção manual, a **fila completa** com filtros/idade/quem pegou/**votos** (o `review/list` só
  manda os votos p/ admin/chefe — anti-anchoring p/ o juiz comum), ação **Decidir/Resolver** =
  `review/resolve`, o override auditado que libera o veredicto ao aluno na hora, desempenho por
  juiz e a config de opções/matriz no fim); **Auditoria** (feed cronológico unificado no **instante exato** de cada
  evento: ações de admin + logins + **submissões** (no sub_epoch) + **veredictos** (no
  finalized_at, com o juiz) — cada submissão gera 2 entradas, submissão e correção, p/ o trace
  completo; `/contest/admin/audit-log`, filtrável + download CSV). **Problemas** também
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
  avaliação usa o **mesmo board** da aba "Tarefas do judge" do admin (`shared/review-board.js`:
  cards, fila completa com idade/quem pegou/votos, ação Decidir/Resolver e desempenho por juiz,
  via `review/{list,stats,resolve}`), **Conflitos** e a config do veredicto manual (opções +
  matriz). O **alerta de conflito** (banner + bip) é **global** (`shared/chief-alert.js`): segue o
  chief/admin em **qualquer página** do contest e abre a fila já filtrada em conflitos.

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
(problema × linguagem × veredicto, editável por admin/chief) que libera combinações automáticas. O
casamento da matriz é pelo **veredicto canônico** (`verdict_canon`, **sem** o sufixo de score `,Np`
que o juiz embute), e **erros de juiz** (`Judge Error`/`No_Servers`) **também são segurados** — o
competidor vê só `Not Answered Yet` (nenhuma mensagem de erro vaza); o juiz vê o erro no painel e
re-julga.
Dois `.judge` **pegam** a submissão (máx 2, **1 ativa** por juiz, **TTL 5 min** com **+5**, ou
**desistir**), veem **log + fonte + veredicto computado** (a tela **não recarrega** enquanto se avalia)
e escolhem um veredicto de uma **lista configurável** (`final-verdicts.json`, `{label,verdict}`;
default = as 6: 1-YES…6-Contact staff). O **voto é permanente e libera o juiz** na hora (ele já pode
pegar outra submissão). **Dois no mesmo → vai ao aluno**; **diferentes → conflito**, que **só o
juiz-chefe resolve** (avisado pelo **alerta global** de conflito em qualquer página). A liberação enfileira `setverdict`, consumido pelo daemon e finalizado pelo
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
  - **Balões** 🎈: na **mesma fila** do `.staff`, o sistema gera automaticamente uma **tarefa de
    balão** quando um time **resolve** um problema (veredicto `Accepted`) — **1 por (time, problema)**
    na 1ª solução. Geração **preguiçosa** ao carregar a fila (`pr_reconcile_balloons` varre o
    `controle/history`, dedup por id determinístico, gateado por mtime, sob flock) — **sem mexer no
    daemon**; como lê o veredicto **final** do history, no **modo manual** o balão só nasce depois que
    os `.judge` decidem o `Accepted`. Só o `.staff` que **enxerga aquele time** (mesmo escopo regex)
    recebe. A **folha do balão** (1 página, `pr_build_balloon`, **sem `.src`**) traz time + universidade
    + **login**, o **problema** (letra), a **cor** do balão **desenhada** + o **nome por extenso**
    (PT + inglês padrão ICPC, ex.: "rosa (pink)", "azul-claro (light blue)"; cor por `balloons.json`/
    default ICPC A–O, com tabela hex→nome + cor mais próxima no custom), o **nº da
    tarefa** (`seq`) e **assinatura + hora**. Reusa o fluxo pegar→imprimir→entregar e é auditado
    (`balloon-task`/`-claim`/`-processed`/`-served`/`-delivered`). Balão **não** aparece p/ o aluno.

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
