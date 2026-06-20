# MOJ — Mega atualização do sistema WEB (API-first + nginx + UI nova)

## Context

O MOJ (Maratona/Meta Online Judge, `moj.naquadah.com.br`) hoje roda como **Apache + CGI em bash**: a CGI recebe o POST, escreve um arquivo num diretório de spool e **fica travada** (`while [[ -e $arquivo ]]; do sleep 1`) até um **daemon que faz polling de 3s** (`ls | wc -l`) consumir o arquivo. O `julgador.sh` despacha para o juiz local (JSON-over-TCP via `nc` para `localhost:40000`, que roda `mojtools`/bubblewrap) ou juízes externos (spoj/uri), grava o resultado de volta como arquivo e recalcula o placar. O frontend é HTML com CSS+JS **embutido e duplicado**; a interface `/new` (treino livre) já é parcialmente API mas está "porca" (header `{"Bearer":...}` fora do padrão, sessões no `/tmp` legível por todos, `lista.json` estático, **sem editor de código**, só upload).

Há um **refactor parcial** (`cdmoj/server/api` com `common.sh`/`params.sh`/jq/Bearer) e um **protótipo completo** (`prototipo-nem-tudo-funcional/`) com renderizadores modulares de placar (`score-icpc.js`, `score-obi.js`) que leem um TXT cujo modo vem na 1ª linha. O arquivo `geracao-das-telas-do-moj.txt` (181 prompts) é a **especificação** de cada tela e de cada contrato de API.

**Objetivo:** sistema **API-first** com **separação clara server/frontend**, servido por **nginx**, UI nova/limpa/moderna com **editor embutido**, **múltiplos modos de placar fáceis de modelar** (ICPC, OBI, treino, heurístico/FLIA, custom), e **daemons repensados** (assíncrono, sem polling travado) — **sem quebrar os contests atuais**, migrando a estrutura aos poucos. Os dados em disco (`contests/<id>/...`) permanecem **inalterados**, lidos igualmente pelo sistema antigo e pelo novo.

Dois subsistemas adicionais entram no escopo: o **cluster de juiz distribuído** (`judge/` — um master/escalonador em `:27000` com fila por diretórios de prioridade que despacha para workers em máquinas separadas, especializados `pos`/`gpu`/`cm`/`hu`; hoje toda a comunicação é **polling sobre `nc`**, com **polling duplo** no retorno do resultado), que deve ter a comunicação repensada para ser **mais eficiente (orientada a evento/push)**; e o **bot do Telegram `mojinho`** (`mojinho-bot/`), hoje acoplado por arquivos de spool e `nc` direto aos juízes, que deve ser **integrado como cliente da API/daemon novo**.

## Decisões (confirmadas com o usuário)

1. **Frontend:** JS puro modular (ES modules + CSS compartilhado), **sem build**, servido estático pelo nginx. Reaproveita os renderizadores do protótipo.
2. **Editor:** **CodeMirror 6** (via ESM, sem build) com highlight das linguagens do MOJ, **mantendo** a opção de upload de arquivo. Submissão envia base64 do conteúdo (editor ou arquivo) + nome/extensão.
3. **Daemons:** **evolutivo** — `inotifywait` no lugar do polling de 3s; **submit assíncrono** (retorna `id`/`queued` na hora, front faz polling do status). Mantém spool em arquivos, bash e os adapters de juiz externo.
4. **Estrutura:** **novo tree limpo** `server/` (backend) + `web/` (frontend estático), consolidando o melhor de `cdmoj`, `/new` e protótipos. Roda em paralelo ao Apache; `contests/` permanece a fonte de dados.

## Arquitetura-alvo

```
moj/
  server/                      # BACKEND web (bash, atrás do fcgiwrap)
    api/v1/                     # rotas limpas, versionadas
      router.sh                # dispatcher único por PATH_INFO + método (evolui o cdmoj 'julgador')
      lib/  common.sh params.sh auth.sh json.sh   # base reutilizável (de cdmoj/server/api)
      handlers/  auth/ index/ treino/ contest/ submission/ admin/ judge/
    daemons/                   # inotify-driven (evolui executar-julgador.sh)
    judge-gw/                   # gateway p/ o escalonador: julgador.sh + corrige.sh + enviar-*.sh
    score/                     # updatescore-<modo>.sh (dispatcher por CONTEST_TYPE)
    etc/  nginx/ systemd/      # configs (nginx + fcgiwrap.service/socket de fcgiwrap/)
  web/                         # FRONTEND estático (nginx serve direto)
    shared/  api.js auth.js i18n.js ui.css editor.js(CodeMirror)
    index/   home (notícias, contests, treino, top10)
    treino/  busca + problema (CodeMirror) + stat do usuário
    contest/ login, main, score (renderizadores por modo), allsubmissions, judge, statistics
  judge/                       # CLUSTER DE JUIZ (máquinas separadas) — repensar comunicação
    sistema_escalonador/        # master :27000 (escalonador.sh + job-receiveitor-master.sh)
    judge/                      # workers :41000-44000 (pos/gpu/cm/hu) + root-daemon + mojtools
  mojinho-bot/                 # bot Telegram → vira cliente da API (systemd), token só no arquivo
  contests/<id>/               # DADOS — inalterado (conf, controle/, data/, submissions/, ...)
  old/                         # arquivo do legado/referência (ver old/README.md)
```

> **Reorganização (já aplicada):** o material legado/referência foi movido para `old/`. As
> referências deste plano a `cdmoj/`, `moj-prod/`, `prototipo-nem-tudo-funcional/` e `fcgiwrap/`
> (ex.: na seção *Arquivos críticos*) agora vivem sob `old/` (ex.: `old/cdmoj/...`,
> `old/moj-prod/...`). Permanecem no topo: `contests/`, `judge/`, `mojinho-bot/`, `mojtools/`,
> além dos novos `server/`, `web/`, `docs/`.

**nginx** serve `web/` estático e faz `fastcgi_pass unix:/run/fcgiwrap.sock` para `/api/v1/...` (bash). O `fcgiwrap` já existe com socket systemd em `fcgiwrap/systemd/` — basta habilitar. Substitui o `cdmoj/server/apache/moj.conf` (traduzir `ScriptAlias`/PATH_INFO para `location /api/v1/ { include fastcgi_params; fastcgi_param SCRIPT_FILENAME .../router.sh; }`). Apache atual continua no ar em paralelo (mesmo `contests/`), migrando página a página.

## Camada de API (v1) — contrato

Padronizar: **`Authorization: Bearer <token>`** (corrige o bug `{"Bearer":...}` em `new/treino/problem/index.html`); respostas JSON com envelope consistente (`{success, data|error}`) **e status HTTP corretos** (`failandexit` de `common.sh` hoje sempre devolve 200); horários sempre em **EPOCH**. Endpoints TXT (histórico, placar) ficam como TXT por eficiência e por já serem o que o front parseia — documentados como parte do contrato. Sessões saem do `/tmp` legível para um diretório próprio (modo 700) por instância.

Rotas (derivadas do design log + `prototipo`/`new`; reusam a lógica de `cdmoj/server/api/old/*` e `new/api/*`):

- **auth:** `POST /auth/login` {username,password,contest} → {token,logged_in,username,name}; `GET /auth/status` (Bearer) → {logged_in,login,name,...}
- **index (home):** `GET /index/news`; `GET /index/contests?page=N` (open/upcoming/closed, passados paginados); `GET /index/open_training` (top10, últimos resolvidos, mais resolvidos da semana)
- **treino:** `GET /treino/problems` (lista: id,title,tags,solved_count,attempted_count — substitui `lista.json` estático, gerado por `create-problemsjson.sh`); `GET /treino/problem?id=` (id,title,statement_html_b64,time_limits,tags); `GET /treino/solvetry?user=` (solved[],attempted[]); `GET /treino/history?id=` e `GET /treino/history-full?user=` (TXT 7 campos: `min:user:probid:lang:verdict:epoch:subid`)
- **submission (assíncrono):** `POST /submit?contest=` {problem_id,filename,code_b64} (Bearer) → **{submission_id,status:"queued"}** (não bloqueia); `GET /submission/source?...` e `GET /submission/log?...` (Bearer)
- **contest:** `GET /contest/basic?contest=` (name,id,start,end,**login_start_time**,locale — para countdown); `GET /contest/userinfo` (Bearer: team,país,univ,show_log); `GET /contest/navbuttons` (Bearer: lista [{label,url}] por papel — `.admin`/`.judge`/`.staff` no username); `GET /contest/problems` (Bearer: [{short_name,full_name,statement_html_b64,statement_pdf_b64,time_limits,problem_id}]); `GET /contest/news` e `/contest/resources` (opcionais — se vazio, oculta seção); `GET /contest/history` (Bearer: TXT); `GET /contest/balloons` (JSON A→cor); `GET /contest/regions` (JSON regiões/sub/subsub para filtro)
- **score:** `GET /contest/score?contest=` → **TXT, 1ª linha = modo** (`icpc`/`obi`/`outro`)
- **admin/judge:** `GET /contest/allsubmissions` (admin: TXT 9 campos); `GET /contest/final-verdicts` (judge: JSON); `POST /contest/set-verdict` (judge: {contest,problem_id,verdict,username}); `POST /contest/rejudge` (admin: {ids[]})
- **ops/admin (usadas pelo bot e pela área admin — substituem comandos via spool e `nc` do mojinho):** `POST /admin/adduser` {contest,login,fullname,email?}; `POST /admin/passwd` {contest,login,oldpass,newpass}; `POST /admin/contest/extend` {contest,end_epoch}; `POST /admin/synctreino`; `POST /admin/rejudge` {ids[]|contest,problem}; `GET /ops/queue` (tamanho da fila por contest — hoje `/onqueue`); `GET /ops/judges` (status/specs das máquinas — hoje `reportmachine`); `GET /ops/problemtl?problem=` (time limits dos juízes); `POST /ops/updateproblemset` {repo}. Estas falam com o escalonador pelo gateway `judge-gw/`.

## Modelo de modos de placar (o "fácil de modelar")

`CONTEST_TYPE` (ou `SCORE_MODE`) vira **campo de 1ª classe** no `conf` do contest. O backend tem **um gerador por modo** e um dispatcher; o placar é **um único TXT com o modo na 1ª linha**; o frontend tem **um renderizador JS por modo**, escolhido pela mesma string. **Adicionar um modo = um `updatescore-<modo>.sh` + um `score-<modo>.js`.**

Formato do TXT (do design log):
```
icpc
desc:asc:flag:username:univ short:team name:univ full:A:B:C:D:E:F:Total
1:1:BR:br-df-alfa:UNB:ALFA:Universidade de Brasília:1/30:2/40:1/55::3/68::15
```
- 1ª linha = modo; 2ª = cabeçalho com marcadores `asc`/`desc` (ordenação) + colunas; já vem **ordenado**.
- Células ICPC: vazio=não tentou; `tentativas/minutos`=resolveu (pinta cor do balão); `tentativas/-`=tentou e não resolveu.
- **obi:** célula = pontos do problema (0–100). **outro/custom:** 2ª linha = nomes de colunas arbitrários (se houver `flag`, renderiza bandeira). Campos `univ short`/`univ full` opcionais (parser ajusta posições se ausentes).

Modos a entregar: **icpc**, **obi**, **treino** (resolvidos/tentativas, sem penalidade), **heuristic/flia** (score + score ajustado — veredictos `Accepted, Score N, Score Ajustado M`), **custom/outro**. Reusar `moj-prod/moj/scripts/updatescore.sh` (ICPC, `PENALTYCOST=20`), `updatescore-obi.sh` (parciais), `cdmoj/server/scripts/updatedotscore.sh`. Balões (mapa A–O→cor), regiões e *freeze time* como JSON/config opcionais por contest.

## Frontend (web/)

Consolidar **design log (spec) + protótipo (impl parcial) + `/new` (produção)** numa base modular: `shared/` com cliente de API (fetch + Bearer + tratamento de erro), auth/token (localStorage), i18n (pt/en — design log pede inglês em contests internacionais), `ui.css` com a identidade visual já desenhada (azul, balões sofisticados, seções com limites claros). Páginas:

- **Home** (`index/`): banner/logo "Melhor Online Judge", link de Documentação, menu que rola para seções, notícias, contests (abertos/por vir/encerrados paginados, busca fuzzy local), treino em destaque, top10.
- **Treino — busca** (`treino/`): lista via API, busca fuzzy local + filtro por tags (tags borradas com cache), paginação local, filtros resolvidos/tentados (só logado), dificuldade por taxa de acerto.
- **Treino — problema** (`treino/problema`): enunciado base64 HTML integrado (não-iframe, com `contest-statement.css`), time limits por linguagem, **editor CodeMirror + upload**, histórico (TXT) com cores por veredicto e polling 5–10s enquanto houver `Not answered yet`/`on queue`/`running`, tags como links `?searchtag=`.
- **Treino — stat do usuário** (`treino/stat`): history-full (TXT), gráficos (submissões/dia, veredictos, linguagens, tags).
- **Contest** (`contest/`): login full-screen por subdomínio com countdown até `login_start_time` (fade-in, bandeiras dos países); página principal (topbar com nome do contest/countdown/logout/BETA, navbuttons por papel, userinfo, news/resources opcionais, problemas como lista expansível com form de submissão ao lado + balões coloridos ao acertar, **editor CodeMirror**, tabela de submissões ordenável/filtrável por problema com polling); **score** (renderizador por modo, filtro por região com ranking relativo, refresh 30–60s com animação de subida, busca fuzzy); **allsubmissions** (admin: agrupar por user/problema, baixar fonte/log, multiseleção→rejulgar, filtro por veredicto); **judge** (escolher veredicto final, `final-verdicts` JSON, enviar); **statistics** (pizzas/barras por problema/linguagem/tempo, filtro por região).

## Daemons (evolutivo)

- **Submit assíncrono:** o handler de `/submit` enfileira no spool com o esquema atual (`$CONTEST:$AGORA:$ID:$LOGIN:submit:$PROBID:$FILETYPE`) e **retorna na hora** `{submission_id,status:"queued"}` — elimina o bloqueio síncrono da CGI (`submete.sh`). O front já faz polling de `history`.
- **inotify:** `executar-julgador.sh` e `executar-corretor.sh` passam de `sleep 3`/`ls|wc -l` para `inotifywait -m -e create,moved_to $SPOOL`. Mantém a arquitetura de 2 estágios (julgador → enviaroj → corretor → adapters `enviar-*.sh` → juiz local mojtools/`:40000` ou spoj/uri → `corrigido` de volta).
- **Manutenção:** quebrar o dispatcher gigante `julgador.sh` (submit/corrigido/login/rejulgar/newcontest/adduser/passwd/answer/jplag) em handlers por comando em `server/judge/handlers/`. Rodar daemons como **serviços systemd** (padrão do `fcgiwrap.service`).
- **Robustez mínima:** escrita atômica (`mv` em vez de `sed -i` direto onde houver corrida) e validação do id de contest (regex/whitelist) antes de qualquer `source .../$CONTEST/conf` (evita path traversal / execução arbitrária).

## Sistema de juiz distribuído (`judge/`) — repensar a comunicação

Hoje são 3 camadas, **todas baseadas em polling sobre `nc`**: daemon web (`corrige.sh`/`enviar-newcdmoj.sh`) → **master/escalonador** (`:27000`, `tcpserver`; fila por **diretórios de prioridade** `000-super`→`080-lista-publica` + `intermed`; loop de 0.5s; `islocked` em ~10 workers fixos em `MOJPORTS`; atribuição gulosa 2-passos com afinidade `contest_servers`) → **workers** (`:41000-44000`, especializados `pos`/`gpu`/`cm`/`hu`; spin em `/dev/shm/moj-queue`; `mojtools/build-and-test.sh` sob `flock`). O resultado volta por **polling duplo** (web→master→worker a cada 0.5s, até 24h).

**Manter** (é elegante, observável e bash-nativo): o **escalonador por diretórios de prioridade**, o sandbox `mojtools` (bubblewrap) e o `build-and-test.sh`, e o spool de jobs em arquivos. **Mudar a comunicação para ser orientada a evento (push), não polling:**

1. **Resultado por push (maior ganho):** o worker, ao terminar, **empurra** o veredicto para o master (1 callback `nc`/escrita num diretório do master observado por `inotifywait`), e o master empurra para o gateway web escrevendo direto o arquivo `corrigido` no spool de resultados (consumido por `inotify`). Elimina o polling duplo de 0.5s/24h. O front, do lado web, já vira assíncrono (faz polling do **status na API do MOJ**, não no juiz).
2. **inotify no lugar dos spin-loops:** `root-daemon` observa `/dev/shm/moj-queue` por `inotifywait`; o escalonador reage a novos arquivos nas filas de prioridade e a eventos de "worker livre".
3. **Registro + heartbeat de worker (em vez de `MOJPORTS` fixo):** cada worker se registra no master ao subir, informando **classe/capacidade** (`pos`/`gpu`/`cm`/`hu`) e envia heartbeat/estado livre-ocupado. O master mantém um *free-set* vivo — acaba o poll-storm de `islocked` e a edição manual de portas. Afinidade `contest_servers`/`executar_em` vira **match por capacidade** (substitui o hack de 2 passos).
4. **Higiene de estado:** um único **jobid de correlação ponta a ponta** (hoje muda em cada etapa, dificultando trace); rotacionar/arquivar `enviado/` (cresce sem limite, `find` O(n)); logs com o jobid correlacionado.
5. **Transporte:** o modelo push remove ~todas as conexões de polling; mantém `tcpserver`/`nc` para o request/response que sobra (dispatch de `run`). Cross-host master↔worker pode usar multiplexação SSH (ControlMaster) se quiser conexão persistente; mesma-máquina web↔master pode usar unix socket. (Sem introduzir DB/broker — fica fiel a bash+arquivos.)
6. **Integração com os daemons novos:** o caminho vira API `/submit` → enfileira em `submissions-enviaroj` (inotify) → adapter manda `run` ao master (jobid) → push de volta → daemon inotify grava veredicto nos dados do contest + recalcula placar. Unifica com a fase de daemons assíncronos.

## mojinho-bot (`mojinho-bot/`) — integração no sistema novo

O bot (long-polling Telegram em bash) hoje acopla no MOJ de 3 jeitos: **(a)** escreve arquivos de comando no spool que `julgador.sh` consome (`/participar`→adduser, `/trocarsenha`→passwd, `/alteravigenciacontest`, `/synctreino`, `/rejulgar*`); **(b)** lê diretórios de dados (`/getcode` em `contests/*/submissions/`, `/getlog` em `mojlog/` + `nc` ao juiz `getresultfull`); **(c)** fala direto com os juízes por `nc` (`/onqueue`, `/problemtl`, `/listjudgesmachine`, `/updateproblemset`).

**Integração:** transformar o bot em **cliente fino da API** (vira o "frontend Telegram"): cada ação MOJ acima passa a ser uma chamada às rotas **ops/admin** e **submission** já definidas (adduser/passwd/extend/synctreino/rejudge; source/log; queue/judges/problemtl/updateproblemset). Some o acoplamento por spool e o `nc` direto aos juízes. Rodar como **serviço systemd** ao lado dos daemons. **Manter local** o que é diversão/local: `/cantar` (+ `musica.*`), `/amigod`, `/help`. **Higiene:** token só no arquivo `token` (hoje está hardcoded no script), checagem de admin (lista GODS) reusada, logs de auditoria (`log-getcode/getlog/cantar`) mantidos. Reaproveita `palavras-para-senha` para senhas legíveis (a API de adduser pode gerá-las ou o bot envia a senha).

## Migração / não-quebrar

- nginx + `web/` + `/api/v1` sobem **ao lado** do Apache atual; ambos leem o **mesmo `contests/<id>/`** → sem migração de dados.
- A nova API lê os mesmos `conf`, `controle/$LOGIN.d/$PROBID`, `data/$LOGIN`, `controle/history`. `CONTEST_TYPE` ganha **default** (`icpc`) para contests antigos sem o campo → placar atual continua funcionando.
- Migrar por página: treino (já é o caminho padrão) primeiro, contests depois. Desligar o Apache só no fim.

## Fases (prioridade — começa pelo que o usuário pediu: comunicação WEB↔server via API)

1. **API v1 + nginx/fcgiwrap + auth** (prioridade #1): `server/api/v1/router.sh` + `lib/` (de `cdmoj/.../common.sh`,`params.sh`), handlers de auth/index/treino/submission reescritos limpos; `Authorization: Bearer` padronizado; envelope+status HTTP; sessões fora do `/tmp` público; config nginx + habilitar `fcgiwrap`. Validar com `curl`.
2. **Frontend treino** (`web/shared/` + home + busca + problema c/ **CodeMirror** + stat). Substitui `/new` inline.
3. **Daemons assíncronos + comunicação do juiz**: submit não-bloqueante; `inotifywait` nos spools; systemd; split dos handlers; e **redesenho da comunicação do `judge/`** (resultado por push, inotify nos workers, registro/heartbeat de worker, jobid de correlação) mantendo o escalonador por prioridade e o `mojtools`.
4. **Contests multi-modo** (login/main/score com renderizadores `icpc`/`obi`/`treino`/`heuristic`/`outro`; `score/updatescore-<modo>.sh` + dispatcher por `CONTEST_TYPE`; balões/regiões/freeze).
5. **Admin/judge/statistics + ops** (rotas `ops/*` e `admin/*`) **+ i18n (pt/en) + docs** da API e do formato de placar.
6. **mojinho-bot como cliente da API**: trocar spool/`nc` direto pelas rotas `ops/admin`/`submission`; rodar via systemd; token fora do script; manter `/cantar`/`/amigod`/`/help` locais.

## Arquivos críticos (criar/modificar — padrões, não exaustivo)

- **Reaproveitar como base:** `cdmoj/server/api/common.sh`, `params.sh`, `cdmoj/server/api/old/{auth,index,submission,open-training*}/*.sh`, `moj-prod/html/moj.naquadah.com.br/new/api/*`.
- **Daemons web/gateway (evoluir):** `moj-prod/moj/daemons/executar-{julgador,corretor}.sh`, `moj-prod/moj/judge/{julgador,corrige}.sh`, `moj-prod/moj/scripts/enviar-*.sh`.
- **Cluster de juiz (repensar comunicação — push/inotify/heartbeat):** `judge/sistema_escalonador/{escalonador.sh,job-receiveitor-master.sh,lancar-master.sh}` (master/`:27000`), `judge/judge/{job-receiveitor,root-daemon}{,-cm,-gpu,-hu}.sh` + `lancar-juizes.sh` + `update-problems.sh` (workers). Manter o sandbox: `mojtools/{cage-run.sh,build-and-test.sh}`, `mojtools/lang/<lang>/{compile,run}.sh`.
- **mojinho-bot (→ cliente da API + systemd):** `mojinho-bot/mojinho.sh` (trocar spool/`nc` por chamadas `ops/admin`/`submission`; token só de `mojinho-bot/token`); manter `musica.*`, `palavras-para-senha`, logs de auditoria.
- **Placar (evoluir/dispatcher):** `moj-prod/moj/scripts/updatescore.sh`, `updatescore-obi.sh`, `cdmoj/server/scripts/updatedotscore.sh`.
- **Renderizadores (polir e integrar):** `prototipo-nem-tudo-funcional/contest/score/{score-icpc.js,score-obi.js,main.js,nav.js}`, `prototipo-nem-tudo-funcional/{index.html,treino/,contest/}`.
- **nginx/fcgiwrap:** `cdmoj/server/apache/moj.conf` (traduzir p/ nginx), `fcgiwrap/systemd/fcgiwrap.{socket,service}`.
- **Substituir:** `moj-prod/html/moj.naquadah.com.br/cgi-bin/submete.sh` (→ submit assíncrono via API), e as páginas inline de `new/` (→ `web/` modular).

## Verificação (ponta a ponta)

1. **API isolada (Fase 1):** subir nginx+fcgiwrap locais; `curl` no fluxo `login → token → status → /treino/problems → /treino/problem?id=X → POST /submit → poll /treino/history` (confere envelope JSON, status HTTP, `Authorization: Bearer`, `{submission_id,status:"queued"}` imediato).
2. **Frontend treino (Fase 2):** abrir a home e a página de problema no navegador; logar; escrever no **CodeMirror** e submeter; ver a tabela de submissões atualizar via polling até o veredicto; testar também o upload.
3. **Daemons + juiz (Fase 3):** submeter e confirmar que a requisição **não trava** (retorna `jobid`); `inotifywait` dispara o julgamento; o worker **empurra** o veredicto (sem polling duplo) e o daemon grava o `corrigido` + recalcula placar; subir um worker e ver o **registro/heartbeat** aparecer no master sem editar `MOJPORTS`; medir a latência ponta a ponta (deve cair vs. os ~17s do exemplo com polling). Daemons e master/worker sobem como systemd.
4. **Multi-modo (Fase 4):** renderizar **um contest real existente** (`contests/bcr-eda2-2025_1-redencao`) na nova página de contest/score lendo o **mesmo `contests/<id>/`**; renderizar ICPC e OBI a partir de `placar.txt`/`placar-obi.txt` do protótipo; trocar `CONTEST_TYPE` e ver o renderizador certo.
5. **Bot (Fase 6):** pelo Telegram, `/participar` e `/trocarsenha` criam/alteram usuário **via API** (não mais via spool); `/getcode`/`/getlog` baixam pelo `source`/`log`; `/onqueue`/`/listjudgesmachine` leem das rotas `ops/*`; `/cantar` continua local.
6. **Não-quebrar:** confirmar que o site Apache antigo continua servindo os mesmos contests em paralelo durante toda a migração.
