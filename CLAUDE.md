# cdmoj — plataforma MOJ (server bash + web ESM)

Plataforma do MOJ: **API bash** sob nginx+fcgiwrap (`server/`) + **frontend vanilla ESM
sem build** (`web/`) + documentação (`docs/`). Repo git próprio (`cd-moj/cdmoj`), roda no
host web. Os juízes **não** precisam deste repo. Workspace multi-repo: ver `../CLAUDE.md`.

**Leia primeiro `docs/OVERVIEW.md`** (arquitetura, API, frontend, o que existe) e
`docs/FLOW.md` (o caminho de uma submissão). Rotas: `docs/API.md` + `web/api/openapi.json`.
Deploy: `docs/DEPLOY.md`. Docs em HTML: `bash docs/build-html.sh`.

## Backend (`server/api/v1/`)

- `router.sh` — front-controller único: sanitiza segmentos (sem traversal), mapeia
  `/a/b/c → handlers/a/b/c.sh` e faz `source` do handler. `$_DIR` = raiz `api/v1`.
- Handler típico: `require_method POST`; `require_auth`; `body="$(read_body)"`; valida com
  `jq -e .`; lê com `jq -r`; responde com `emit_json 200 OK` + objeto `jq`, ou
  `fail <http> "<msg>" "<code>"`. Querystring: `param <nome>`. Helpers em `lib/common.sh`.
- **Envelope**: `{success:true,…}` / `{success:false,error:{message,code}}`, sempre com o
  status HTTP correto. EPOCH para tempo.
- **`jq` + ARG_MAX** (ver `../CLAUDE.md`): JSON grande (mapas com milhares de chaves, ex.: o
  `id→sub_epoch` do history em `score/treino-response-gen.sh`) **não** vai por `--argjson` — estoura
  `Argument list too long`. Use `--slurpfile <arquivo>` ou encadeie etapas com pipe.
  **REGRA DERIVADA (paga 2× no jplag): agregado de N arquivos NUNCA entra por `--argjson`.**
  O teto é de **128 KiB POR ARGUMENTO** e todo agregado cresce com o tamanho do evento —
  pares do jplag, times, clarifications, fila de impressão, fila de revisão, backups. Use o
  helper **`ok_json_slurp <filtro> <nome> <json> [args…]`** (`lib/common.sh`; no filtro o
  valor vira `$<nome>[0]`). Sintoma do estouro, antes da blindagem: **200 com corpo vazio** e
  "Resposta inválida do servidor" na tela, sem NADA no log — hoje o `ok_json` monta o corpo
  antes do cabeçalho e uma falha do jq vira `500 build_fail` com o stderr no error.log.
  Teste que fecha a porta: caso *oversized* (>128 KiB) no smoke — ver `smoke-contest-jplag.sh`.
- **Auth**: `Authorization: Bearer <token>` → sessão em `run/sessions/` (700), gravada com
  `printf %q` (é *sourced*). **A sessão vale enquanto a CONTA existir** (`_session_account_alive`
  no `load_session`): sessão do MOJ não expira por tempo, então a conferência do `account.json` é
  o que mata token de conta renomeada/removida (401 `auth_required`). ⚠ O teste tem de ficar no
  `load_session`, que resolve `USERS_FROM` — participante compartilhado tem dir local SEM
  `account.json` de propósito, e um `user_exists` cru no `submit.sh` barraria submissão legítima.
  Espelho disso: **conta renomeada arrasta TODAS as sessões** (`rename_contest_sessions`), não só
  o token da requisição — foi o furo que fez uma sessão velha submeter com o login antigo e
  RECRIAR o diretório do fantasma (`server/bin/user-merge.sh` conserta o resíduo).
  Papéis por sufixo no login (`.admin/.judge/.cjudge/.staff/.cstaff/.mon`).
  **`.cjudge`** = juiz-chefe: `is_judge` vale p/ ele (herda juiz) + `is_chief`/`is_admin_or_chief`
  p/ os extras escopados (editar notícias/respostas já dadas, Situação, Todas Submissões, resolver
  conflitos, config de auto-veredicto) — **não** é admin pleno. **`.cstaff`** = chefe de staff de
  uma sede (`is_cstaff`, **não** herda `is_staff`): VÊ mas não AGE — etiquetas de credenciais com
  senha (o `.staff` perdeu), fila do staff em leitura (ações/PDF 403), placar congelado como
  usuário comum (admin libera o full via `SCORE_FULL_USERS`) e a **cerimônia de revelação POR
  SEDE** (`/contest/score` `&scope=mine`, full só pós `contest_over_for_all`); escopo pelo mesmo
  `staff-filters.json`. Ao mexer em papel, lembre das **quatro** listas de sufixo canônicas —
  `lib/auth.sh`, `score/score-common.sh`, `score/stats-gen.sh`, `handlers/auth/login.sh` (+ guard
  `treino/profile/username.sh`) — **e das réplicas** em `handlers/contest/teams.sh`,
  `handlers/contest/admin/teams.sh`, `lib/telegram.sh`, `daemons/judged.sh` (`should_hold`),
  `lib/print.sh` (`pr_reconcile_balloons`) e `handlers/contest/badges.sh` (regex jq).
  Auto-cadastro **nunca** cria papel por sufixo: use `is_reserved_role_login` (`lib/auth.sh`) —
  já aplicado no signup; o `/admin/adduser` (admin autenticado) **continua** podendo criar
  `.judge`/`.staff`/`.cstaff` de um contest (legítimo).
- **Store por-usuário (`lib/users.sh`)**: cada conta vive em `contests/<c>/users/<login>/`
  (`account.json` autoritativo — inclui perfil `university`/`favorite_editor`/`public`/
  `uname_changes` e time `.team{name,univ_short,univ_full,flag}`; `history` próprio de 6 campos
  `tempo:probid:lang:verdict:sub_epoch:subid`, login implícito; `metrics.json`;
  `submissions/<subid>.<ext>`, `mojlog/<subid>.html`, `results/<subid>.json`, `photo.png` — **sem
  login no nome**). **NÃO existe `passwd`**: auth (`verify_password`), placar (`sc_users`),
  perfis e listagens leem os `account.json` direto (agregações SEMPRE por `find|xargs jq` —
  ARG_MAX); `USERS_FROM=<src>` cai p/ o `users/` do contest-fonte (participante compartilhado tem
  dir local sem `account.json`). **Rename de conta = `mv` do diretório** (`user_rename` +
  telegram index). Leitores agregados usam `emit_user_history`/`emit_history_stream` (formato
  global de 7 campos). **O placar NÃO varre history**: `metrics_recompute` grava em
  `metrics.json` tudo que os geradores precisam por problema (`counted` até o 1º AC — quais
  verdicts contam obedece o `PENALTY_VERDICTS` do conf e o peso é o `PENALTY_MINUTES` do
  gerador icpc, defaults = comportamento clássico, ver `docs/SCOREBOARD.md`;
  `first_ac_epoch`; `pending`; `best_score` NNp; `heur`; visão **`frozen`** pré-`FREEZE_TIME`) e
  `score/build.sh` + `sc_cells` (score-common.sh) leem `users/*/metrics.json` numa passada —
  placar em **`var/placar{,-full,-custom}.txt`** (não mais `controle/`). Staleness dos caches
  preguiçosos (`contest/score`/`statistics`/`response-stats`/balões/home) = **`var/.score-dirty`**
  (tocado por `user_history_append/replace` **e por toda mutação user-visível de conta**:
  `user_rename`, perfil e foto — senão a home/placar serviam handle/nome velhos p/ sempre) + `conf`; `var/.metrics-stamp` dispara recompute em
  massa no `build.sh` quando o `conf` muda (ex.: `FREEZE_TIME` editado). **Migração** de contest
  legado (arquivado em `contests-legado/`): `server/bin/store-migrate.sh <c>` (dry-run por padrão).
  **Do MOJ ANTIGO** (`contests-backup/`) é OUTRO caminho: `treino-map-gen.sh` (mapa auditável
  `<repo>#<slug>`→`<org>#<prob>`; `?` = não auditado e o migrador RECUSA) + `treino-migrate.sh
  {stage|verify|install|audit}`, que **funde** em contest vivo (o store-migrate aborta se o destino
  existe e faz `mv -T`). Regras que valem p/ os outros 1478: **`tempo` := `sub_epoch`** (o campo 1
  do history legado é lixo em 617 linhas); rota de submissão pela chave `sub_epoch:subid` contra o
  **history** (o nome do arquivo mente: 145 têm probid numérico); sem extensão ⇒ grave `<subid>.txt`
  (`resolve_submission` globa `<sid>.*`); e **título igual NÃO prova mesmo problema** — confira o
  enunciado (a agulha tem de sair da ESTÓRIA: "Entrada/Saída" é clichê e casa problema alheio).
  Handlers de usuário do admin (`user-add`/`user-disable`/`user-remove`/`users-set-password`)
  escrevem no account.json; remover = `mv` p/ `.removed-users/`. **`.team` agora tem WRITERS
  na API** (antes só o store-migrate): `users-bulk`/`user-add`/`contest-create users[]` aceitam
  `univ_short/univ_full/country/region` (helper `team_fields_json` + `account_team_merge` em
  lib/users.sh — saneiam `:`/tab/newline) e `/contest/admin/teams` (painel **Pessoas › Times**) faz set
  por-usuário de `fullname` + esses campos (`""` apaga os de `.team`) + **materialize**
  (regex→campos vazios). **O NOME é campo ÚNICO: `fullname` = nome do time** (usuário de
  contest É o time); `.team.name` existe só como LEGADO da migração — os leitores fazem
  `.team.name // .fullname` e a API nunca o escreve.
  `.team.region` = SEDE (texto; casa com o `name` de regions.json): o placar filtra por nome,
  os badges preferem-na à derivação regex e o `staff_can_see` aceita entradas
  **`region:<nome>`** no staff-filters. Assets por-time: `users/<login>/{photo,logo}.png`
  (upload admin `/contest/admin/team-assets`, servidos por `/contest/team-{photo,logo}` com o
  gate do placar; `/contest/teams` = diretório que o placar mescla ANTES do teams-meta).
- **Telegram (overlay só do treino) + alertas**: `lib/telegram.sh` (índice `var/telegram/{by-tgid,by-login}`,
  nonce em `run/telegram/`), cadastro web-first (`handlers/treino/signup/*` + página `web/treino/cadastro/`),
  recuperação por vínculo, `link-start`/`unlink` (a UI é a seção **📨 Telegram** do perfil —
  `web/treino/perfil/`; o `GET /treino/profile` expõe `telegram:{linked,username,linked_at,
  changes_*}`). **Desvincular tem COTA anti conta-descartável**: usuário comum =
  `TELEGRAM_CHANGE_LIMIT` (1)/ano (histórico `telegram_changes` no account.json, 403
  `telegram_limit`); `.admin` livre — o vínculo é a identidade/prova de posse da conta.
  **Troca de handle preserva o sufixo de papel** (`profile/username.sh`: sufixo(novo)==sufixo(atual);
  `.admin` troca p/ `outro.admin`, nunca derruba nem assume papel) **e as ORGs seguem o rename**
  (`orgs_rename_login` em lib/orgs.sh — sem isso a conta renomeada ficava órfã de TODAS as orgs;
  o nome da org e o `owner` histórico dos problemas não mudam: acesso vem da membership)
  **e as SESSÕES também** (`rename_contest_sessions`, resposta `sessions_updated`) **e as
  INSCRIÇÕES** (`reg_rename_login`). Item novo na cascata de rename ⇒ entra aqui, no
  `username.sh` E no `smoke-profile.sh`.
- **Inscrição em contest (`lib/registration.sh`)**: `contests/<c>/registrations.json` — **existir =
  ligado** (doutrina do `cohorts.json`: ausente = comportamento de sempre, custo zero). Vale só p/
  contest com `USERS_FROM` (quem se inscreve é a conta da FONTE, pela página `/contests/inscricao/`
  do site principal — o token é por ORIGEM e o subdomínio do contest não vê a sessão do treino).
  Janela no conf (`REG_OPEN`/`REG_CLOSE`/`REG_LATE_MINUTES`/`REG_TEAM_MAX`/`REG_TEAMS`); atrasado
  cai em coorte `unranked`. **A âncora é a PROVA OFICIAL** (`reg_official_window`: 1ª rodada
  não-arquivada `kind=official` do `rounds.json`), nunca a rodada corrente — o AQUECIMENTO pode
  ficar dias no ar e por DEFAULT só inscrito entra
  em QUALQUER rodada (aquecimento incluso — decisão 2026-08-04); `REG_WARMUP_OPEN=y` no conf é o
  opt-in da porta aberta no warmup, e aí a PROMOÇÃO varre quem não se inscreveu
  (`reg_sweep_unregistered`: sessão + dir vazio, porque sessão não expira sozinha). **Modo de
  participação é DEFINITIVO** p/ o competidor (403 `mode_locked` em cancel/leave/dissolve/troca) —
  o admin muda pelo painel (a lib segue permissiva). Time declara `univ` (SÓ `.team.univ_short` — o RENDERER do placar
  monta o "[SIGLA] Nome"; prefixar o fullname também DUPLICAVA a sigla), `ai` (🤖 no placar via /contest/teams — cuidado: `.ai // null` COME false, use
  `has("ai")`), `flag` e foto (`team-photo`, reprocessada; 📷 já existia). **O INDIVIDUAL declara o
  mesmo** (menos foto): `register {univ?,ai?,flag?}`/`individual-meta` gravam na ENTRY do roster e
  `reg_materialize_login` leva ao `.team` do overlay (a fonte é SEMPRE o roster — o overlay é
  reescrito a cada materialize); admin: ação `individual-meta {login,…}`. **O convite AVISA** (`lib/invite-notify.sh`, 2026-08-06): DM do mojinho na
  hora do `team-invite` + **um** último aviso quando falta ≤`REG_REMIND_LEAD`(24h) p/ fechar
  (varredura `inv_sweep_all` no poll do bot, stamp próprio; `REG_REMIND=n` desliga) + botão 🔔 do
  painel (`invite-remind`/`invite-remind-all`). Contabilidade em `var/invites.json` (**não** no
  roster: `reg_get` normaliza e DESCARTA chave desconhecida) com `dm` (qualquer aviso, dá o
  intervalo mínimo) × `warn` (o automático já disparado, garante "uma vez") — cutucar à mão não
  pode cancelar o aviso da véspera. Texto em HTML ⇒ **escapar `&<>`** de nome de time/contest.
  Idioma: contest `LOCALE=en` manda **EN + PT no mesmo texto** (DM não tem seletor como a web, e
  contest `en` é o que mistura gente de fora com brasileiros); contest pt manda só PT.
  **A porta é a API** (`auth/login.sh`): `LOGIN_ENABLED`/`LOGIN_START_TIME`
  — que eram só desenho de tela — e o roster valem lá; papel nunca é barrado. **TIME = conta local**
  (`users/time-<slug>/`, senha `!<uuid>`) e o membro entra com a credencial DELE: o login faz o
  **alias** (`SESSION_LOGIN` = time, `SESSION_ACTOR` = a pessoa), então placar/balões/impressão não
  mudam. Toda mudança MATERIALIZA o store (overlay `account.json` **sem senha** — `verify_password`
  cai p/ a fonte) e semeia `individual`/`times`; coorte pública com **`ranking:true`** ganha placar
  próprio (`ch_views`/`build.sh`, seletor no `/contest/score/`). O **bot** (`mojinho-bot/mojinho-api.sh`) é transporte fino:
  autentica com **bot-token** `mojb_…` (`lib/bot-auth.sh` `require_bot`, `run/secrets/bot.token`) — não
  loga como `.admin`, sem GODS. Em produção roda **ENJAULADO** (`mojinho-bot/run-caged.sh`: bwrap
  sem /home/workspace/contests/run; segredos só no dir vivo `~/mojinho-live`, nunca no repo). **Alertas**: `lib/alerts.sh` + `GET /ops/alerts` (a API avalia com
  histerese/cooldown e enfileira no outbox `run/alerts/`; o bot drena e entrega a `.admin` vinculados
  + grupo). O outbox tem **TRÊS formatos**: `*.txt` = incidente (destino resolvido no claim = os
  `.admin`), `*-dm-*.json` = **DM dirigida** (`alert_dm`: o produtor resolve o chat; `group:false` p/ não
  copiar no grupo, `loud:true` p/ notificar) e `*-grp-*.json` = **só grupo** (`alert_group`:
  `chats:[]` + `group:true`; o claim SÓ aceita chats vazio quando `group` — DM sem destino segue
  descartada). O claim entrega no máx. `ALERT_CLAIM_MAX`(30) por poll
  (teto do Telegram) — o resto sai no seguinte. No bot, ler `group` com **`.group == false`**: o `//`
  do jq trata `false` como vazio e o grupo receberia a DM de todo mundo.
  Senha nova **só por DM** (nunca na web).
  **Relatório de quartil** (`/relatorio` no bot → `POST /ops/relatorio`; `lib/relatorio.sh` +
  `score/relatorio-gen.sh`): painel de submissões p/ o grupo dos professores; gate = conta
  `.admin` do treino com Telegram vinculado (pelo `telegram_id` — o bot NÃO sabe quem é admin);
  semestre em `contests/treino/var/relatorio.json` (JSON, atômico, nunca *sourced*), cache do
  gerador em `var/relatorio-cache.json`; o envio automático mora no sweep do `GET /ops/alerts`
  (stamp `.relatorio-stamp`, throttle 1 h; quartis já vencidos na config entram pré-marcados).
- **Relatório offline (`server/score/report-gen.sh`)**: é o pacote do evento e usa a
  identidade do site — `web/shared/ui.css` INLINADO, topbar/logo e bandeiras (mesmo SVG do
  placar) como `data:` URI. Roda STANDALONE, então resolve `MOJ_HOME`/`MOJ_WEB`/
  `MOJ_PROBLEMS_DIR` sozinho. Invariantes: **zero `<script src=`, `import `, `fetch(`** e a
  palavra `password` (smoke), e nada de caminho relativo p/ asset — o visualizador de rodadas
  abre as páginas em `iframe srcdoc`. As estatísticas NÃO são reescritas em jq: o relatório
  inlina `web/lib/stats-view.js` + `web/lib/charts.js` + `web/shared/dom.js` (as linhas
  `import`/`export` saem no `sed`) — **o mesmo módulo que a página do admin usa**, senão as
  duas telas divergem. ⚠ Ao criar classe CSS no relatório, cuidado com colisão com o `ui.css`
  (um `.bar{height:14px}` local achatou a topbar inteira: `.bar` é o contêiner dela).
  **É bilíngue como qualquer tela**: `rep_t <chave>` (molde do `_doc_t`) resolve pelo `LOCALE`
  do contest — string nova entra na tabela, e bloco awk/jq recebe o rótulo já traduzido por
  `-v`/`--arg` (nunca literal no meio do programa).
  **Placar do relatório = UM placar por VISÃO de coorte** (`rep_score_boards`, uma `<section
  class="board-view">` por `placar-view-*.txt` que o `build.sh` já gerou; o seletor troca qual
  aparece). NÃO filtre o TXT pronto p/ fabricar placar de coorte: a estrela de first-to-solve é
  mínimo global (`lib/cohorts.sh`). Em placar de coorte a coluna `#` leva a posição na coorte E a
  do geral (`.plg`). Bandeira/universidade/sede/busca são recorte de linhas (`data-*` na `<tr>`,
  script inline **depois** das seções — no parse o `querySelectorAll` ainda estaria vazio) e
  **não renumeram**. A **bandeira entra UMA vez** (classe CSS `.f-<código>` com o `data:` URI;
  um `<img>` por linha levava o index.html a 21 MB — 458 KB de brasão × N linhas × N placares).
  Detalhes em `docs/SCOREBOARD.md`.
- **Placar NUNCA rola para o lado** (contest, revelação e relatório usam o MESMO CSS em
  `ui.css`): `table-layout:fixed` + `<colgroup>` com frações (`score-cols.js` carimba
  `--nprob`; o CSS divide), número da célula em `.pv` com fonte menor, e no celular (≤640px)
  a célula de PROBLEMA vira ✓/✗ com os números no `title` — total e penalidade (também
  `td.cell`) ficam de fora da regra e mantêm o número. Embrulho é `.board-wrap` (sem overflow).
  ⚠ `min()`/`max()` em largura de `<col>` é IGNORADO pelo Firefox — só `calc()` simples.
  **A BARRA DE FILTROS também é a mesma nos dois** (coorte, bandeira, universidade, sede, busca,
  contador, limpar): CSS `.fbar` + `.plg` no `ui.css`, mesmos `id` (`fView`/`fFlag`/`fUniv`/
  `fRegion`/`fQ`/`fCount`), e só a COORTE fala com o servidor (`?view=`, aceito também na URL da
  página) — o resto recorta linhas e **nunca renumera** (o contador é quem denuncia o filtro).
  Detalhes em `docs/SCOREBOARD.md`.
- **Coluna NUMÉRICA em tabela = `class="n"` no `<td>` E no `<th>`** (`ui.css`: alinha à direita,
  `tabular-nums`, largura do conteúdo). Marcar só o `td` foi bug real: com `width:100%` o
  cabeçalho ficava à esquerda e o número a meia tela dele, parecendo pertencer à coluna
  vizinha. Tabela de POUCAS colunas ganha `narrow` (relatório) p/ não esticar — e nela o
  `.n` volta a `width:auto`, senão a porcentagem de célula infla a tabela toda.
- **`el()` mora em `web/shared/dom.js`** (sem dependência de rede) e o `ui.js` re-exporta —
  é o que permite reusar renderizadores no relatório offline. Importar de `/shared/ui.js`
  segue valendo p/ os ~79 arquivos que já faziam isso.
- **Contrato do resultado do juiz**: além do `verdict` de display (com o score embutido, ex.
  `Accepted,100p` — gerado por `mojtools/build-and-test.sh`), o JSON traz **`verdict_canon`**
  (canônico, **sem** score) + `score/score_max/score_kind/correct/total_tests` +
  **`groups`** (subtarefas: `[{earned,max},…]` na ordem do `tests/score`, quando o problema
  pontua por grupos; ausente = sem grupos). Fonte única = `report.env` do mojtools (os dois
  backends, juiz real e `judge-gw` dev, o repassam). O daemon **casa o auto-veredicto pelo
  `verdict_canon`** (não pela string com score) e persiste os campos em `results/<id>.json`,
  servidos por `/submission/summary`. **Política de exibição (fonte única `lib/verdict.sh`)**:
  o competidor recebe **SEMPRE o veredicto canônico** nos endpoints de history (todos os
  modos; pendentes/strings desconhecidas intactos, ` (Ignored)` preservado) e o **detalhe**
  sai só pelo summary, **redigido por modo** (`verdict_detail_level`): treino/lista = tudo
  (resumo de testes); obi/heurístico/outro = score/grupos/heur sem correct/total; icpc/
  ausente = só o canônico (nem o dono vê score). Juiz/admin seguem vendo a string crua
  (allsubmissions/review). **SHOWLOG efetivo (`showlog_effective`, mesma lib)**: o `report.html`
  expõe input+diff de TODOS os testes, então o gate do log/summary usa o valor EFETIVO —
  `SHOWLOG` explícito no conf manda; **ausente = OCULTO em modo icpc** (anti-vazamento de prova)
  e visível nos demais modos. Religar em icpc = o settings POST grava `SHOWLOG=1` explícito.
- **Veredicto manual** (`MANUAL_VERDICT`, opt-in): o **daemon** (`daemons/judged.sh`) SEGURA o
  veredicto computado (grava `contests/<c>/review/<id>.json`, history fica provisório) salvo o que
  a matriz `auto-verdicts.json` (problema×lang×veredicto, casada pelo **canônico**) libera; **erros
  de juiz também são segurados** (o competidor só vê `Not Answered Yet`); **N `.judge` decidem** —
  N = `REVIEW_JUDGES` do conf (1..5, default 2; settings `review_judges`; `rv_quorum` em
  `lib/review.sh` — N votos unânimes liberam, divergência = conflito p/ o chief)
  (`handlers/contest/review/*` + `lib/review.sh`, flock + TTL), e o veredicto vai ao aluno pelo
  **escritor único** via o consumidor `setverdict` do daemon. O **voto é permanente e libera o juiz**
  (pega outra na hora); o **alerta de conflito é global** (`web/shared/chief-alert.js`, disparado pelo
  `auth.status` → segue o chief/admin em qualquer página); o painel **Operação › Situação** traz estatística por juiz
  (`review/stats`, derivada do `admin-audit.log`). **Mexeu no `judged.sh` → reinicie o
  daemon** (mantendo `INTAKE_MODE`/`JUDGE_BACKEND`); handlers/score são frescos por requisição.
- **Liveness do daemon = `daemon_judged_alive()` (`lib/common.sh`), NUNCA `pgrep` direto.** Em
  produção a API (`moj-api`) e o daemon (`moj-judged`) são containers **separados**: o `pgrep` da API
  jamais vê o processo. O daemon bate um heartbeat em `run/judged.alive` (volume compartilhado) e o
  helper aceita processo local **ou** heartbeat fresco (TTL 120s). Voltar ao `pgrep` = painel dizendo
  "daemon caído" com ele vivo + alertas de `lib/alerts.sh` disparando p/ sempre.
- **Log de ATIVIDADE do treino** (`activity_log` em lib/common.sh): eventos de LEITURA
  (`problem-view`/`log-view`/`source-download`) em `var/activity-YYYY-MM.log` (TSV com ip;
  rotação MENSAL pelo nome; separado do admin-audit, que é dominado por tl-report). O feed
  `GET /treino/admin/activity-log` (aba 📜 Atividade) unifica 6 fontes + `format=csv`.
  **Evento novo de leitura ⇒ instrumente com `activity_log`** (login/submit/verdict já são
  deriváveis de access.log/history/results — não duplique).
- Clarifications: o **asker é anônimo** p/ os juízes (handler corta `.login`); responder exige
  **reserva** (`clarification-claim`). Sempre auditar (`audit_log_to`) toda ação de juiz/chefe.
- **Balão** (`.staff`): tarefa **automática** na 1ª solução (`Accepted`) de cada (time, problema),
  na MESMA fila do `.staff` (campo `kind:"balloon"` no `print-requests/<id>.json`, sem `.src`). Gerada
  **preguiçosamente** por `pr_reconcile_balloons` (em `lib/print.sh`) ao carregar `staff/queue` — lê o
  veredicto **final** do history do **store por-usuário** (`emit_history_stream` sobre
  `users/<login>/history`; vale auto+manual), dedup por id determinístico, gateado pelo mtime de
  **`var/.score-dirty`**, **sem mudar o daemon**. Folha via `pr_build_balloon` (cor por `balloons.json`/default ICPC + tabela
  hex→nome). Escopo por `staff_can_see`; auditar `balloon-*`. Balão **não** vai p/ a lista do aluno.
- **Etiquetas de credenciais** (`/contest/badges` + página `web/contest/badges/`, gabaritos Pimaco
  A4): é o **único** endpoint que devolve `.password` numa releitura — gate **admin/`.cstaff`**
  (o `.staff` recebe **403 `cstaff_required`**), GET-only, senha **sempre** presente (o antigo
  toggle `{staff_password}` foi extinto; `print-requests/badges.json` é arquivo morto). Escopo do
  `.cstaff` via `staff-filters.json` (+ a própria conta e as `.staff`/`.cstaff` do MESMO escopo —
  o chefe imprime as credenciais do staff da sede); admin vê tudo ou o arquivo de uma sede via
  `staff=<login .cstaff>`. Contas `.admin/.judge/.cjudge/.mon` nunca entram. Sempre auditado
  (`badges-view`).
- **Gate de navegador POR SEDE** (`lib/ua-gate.sh` + `handlers/contest/admin/ua-gate.sh`, UI na
  seção 🔒 do `web/contest/admin/machines-tab.js` — fica lá, e não em Configurações, porque é ali
  que se vê o **esperado × visto** de cada time; o `armUaGate` antigo, que gravava só
  `login_ua_substring` via `settings`, deixou de existir): a
  imagem de cada sede manda um UA com um pedaço do login do time (`teambrspso001` → `brspso`).
  `ug_expected` resolve na ordem isentos › papel › `by_regex` › `by_region` › `from_login`
  (captura `\1`) › `fallback`/`LOGIN_UA_SUBSTRING` legado; `ug_ok` é o match (substring,
  case-insensitive) e `login.sh`/`logout-mismatch.sh` usam os dois. **`ug_expected_map` é o MESMO
  programa jq em lote** (`UG_JQ`) — o painel **Pessoas › Máquinas & gate** precisa do esperado por time e não pode
  forkar por login; se mudar a ordem, mude nos dois. Armadilhas jq que isto pisou: `first()` de
  stream vazio e **`match()` SEM casamento** devolvem VAZIO, e `vazio as $v | …` anula a
  expressão inteira (use `// null`); `sub()` **não entende `\1`** — as capturas vêm do `match`.
- **Coortes de placar** (`lib/cohorts.sh` + `handlers/contest/admin/cohorts.sh`, UI no painel
  **Pessoas › Coortes** = `web/contest/admin/cohorts-tab.js`): times oficiais ×
  **convidados** (extra-oficiais/"CCL"). Coorte privada não aparece no placar público nem no
  `/contest/teams`; os convidados veem todos; `results_released` libera. O corte **sobe até
  `sc_users`** (`score/score-common.sh`, env `MOJ_COHORTS`) porque a ESTRELA de first-to-solve é
  um mínimo global sobre a lista de times — filtrar o TXT pronto daria estrela errada. `build.sh`
  gera um par de placares por VISÃO; `var/placar[-full].txt` continua sendo a pública. Convidado
  entra intercalado **sem consumir posição** (coluna `guest`, última do TXT, lida por NOME de
  cabeçalho). Privilegiado (statistics/allsubmissions/staff/relatório) **continua vendo tudo** —
  de propósito, documentado. Ver `docs/SCOREBOARD.md`.
  ⚠️ `sc_users` separa campos por **\x01, não TAB**: `IFS=$'\t' read` colapsa runs de tab e
  campo vazio no meio DESLOCA os seguintes (era bug silencioso com bandeira sem `univ_full`).
- **Placar PRÉ-INÍCIO = VITRINE (regra: nunca revelar a quantidade de problemas antes de a
  competição começar).** Antes do `CONTEST_START`, `/contest/score` serve
  `var/placar-prestart.txt` (`build.sh <c> --prestart`; `MOJ_PRESTART=1` zera as tuplas no
  `sc_load` — vale p/ todos os modos): os times da visão pública SEM coluna de problema;
  `is_judge` segue no completo. `/index/contests` emite `problems_count:0` p/ `upcoming` pela
  mesma regra. Teste: `smoke-score-prestart.sh`. Ver `docs/SCOREBOARD.md`.
- **Rodadas do contest** (`lib/contest-rounds.sh` + `handlers/contest/{admin/rounds,rounds,round,
  admin/round-archive}.sh`): **aquecimento → prova oficial NO MESMO contest** (mesma URL, mesmo
  login, config preservada). `rounds.json` é o plano; **a rodada ativa É o `conf`** — não torne
  placar/gate/daemon "conscientes de rodada", a troca é **arquivar + zerar + reapontar** em
  `contests/<c>/rounds/<slug>/` (com o site estático do `report-gen`, servido por
  `/contest/round`). A promoção **recusa** com job em voo/veredicto pendente/review aberto (o
  daemon lê o conf no CONSUMO do spool e o `ingest_result` recria a linha do history), e
  **preserva** `print-requests/staff-filters.json` e os templates de `docs/` enquanto zera
  `.seq`, balões, `time-overrides.json` e `resources.json`. Ao mexer, mantenha a fronteira
  CONFIG × DADO DE RODADA documentada no topo da lib. `CC_KEEP_STATEMENTS=1` (em
  `cc_build_probs`) existe para a troca não re-baixar o enunciado do banco por cima do que o
  admin subiu à mão.
- **Documentos da prova** (`lib/contest-docs.sh` + `handlers/contest/{admin/docs,doc}.sh`, painel
  **Prova › Documentos** do admin e aba 📄 do `.cjudge`): info sheet, caderno (capa + enunciados), folha de
  time limits e **EDITORIAL** (o `docs/solucao.md` do PACOTE de cada problema, via `pkg_path` —
  o campo que nunca vai ao aluno), em **PDF+HTML × pt/en**, tudo derivado do que o contest já tem (conf, `PROBS`,
  `enunciados/`, `run/tl`, `run/registry`) — nada de dado novo. **Gates de FASE no `/contest/doc`**
  (quem não é organização): `contest`/`times` publicados só a partir do INÍCIO (`contest_phase`),
  `editorial` só com `contest_over_for_all` — que também trava o **publish** do editorial; `news:true`
  de caderno/times antes do início = 409 (a notícia anexa o PDF por fora do gate). Teste:
  `smoke-contest-docs.sh`. **PDF só por `soffice --headless
  --convert-to pdf`** (não há LaTeX/wkhtmltopdf/chromium na imagem; `pdfunite`/`pdfinfo` juntam e
  contam). **MATEMÁTICA**: o enunciado vem com MathML (`pandoc --mathml`) e o import HTML do
  Writer NÃO o entende (achatava as fórmulas + duplicava o TeX do `<annotation>`) — por isso o
  enunciado do caderno vai por **`pandoc -f html -t odt` → soffice** (fórmula ODF de verdade;
  a imagem tem `libreoffice-math`), com fallback soffice-HTML + strip de `<annotation>`
  (`_doc_strip_annotation`, aplicado também em `_doc_html2pdf` p/ capa/errata). O ESTILO da rota
  ODT vem do **`etc/caderno-reference.odt`** (`--reference-doc`; ODT ignora CSS): corpo
  JUSTIFICADO + Preformatted Text com fundo/borda (a caixa dos exemplos) — receita de
  regeneração comentada no `contest-docs.sh`. O caderno prefere o **PDF próprio** do problema; a **capa** tem 3 modos (PDF enviado ›
  markdown editado com marcadores `{{…}}` › gerada) e é **regerada no fim** com o total real de
  páginas. **PT/EN é só o chrome** — o MOJ não tem enunciado bilíngue; diga isso na UI, não finja.
  `publish` escreve `resources.json` (seção "Prova") e opcionalmente a notícia com anexo; o gate
  de download é do handler (`/contest/doc`: não publicado ⇒ **404** p/ quem não é admin/chefe).
- **Checklist pré-prova** (`handlers/contest/admin/preflight.sh`): a lista que a **🏁 Central**
  do painel renderiza — `{id, level:ok|warn|fail, label, detail}` + `summary`. Feature de contest
  nova que possa dar errado no dia da prova **ganha uma checagem aqui**, com o `id` no mapa
  `TARGET` do `central-tab.js` (é o botão "resolver →") e uma asserção em
  `server/test/smoke-preflight.sh`. `fail` significa BLOQUEIA a prova — use `warn` p/ escolha
  legítima (isento de gate declarado, coorte privada) e nunca transforme configuração
  deliberada em aviso eterno. Libs pesadas (rodadas) só são `source`adas dentro do `if` que
  precisa delas: o handler roda a cada abertura da Central.
- **FUSO (2026-08-06)**: a imagem é debian-slim **sem TZ** ⇒ o servidor rodava em UTC e TUDO que
  ele escrevia p/ humano saía 3 h adiantado (DM do convite, preflight, caderno, relatório). Hoje
  `lib/common.sh` faz `export TZ="$MOJ_TZ"` (default `America/Sao_Paulo`, em `etc/common.conf`) e
  o que fala DE um contest usa **`fmt_epoch <epoch> <fmt> <contest>`** + **`contest_tz`**
  (`CONTEST_TZ` no conf, validado contra o zoneinfo — nome inválido faria o `date` cair mudo em
  UTC). Epoch nunca muda: o fuso é só renderização. Script standalone (`score/report-gen.sh`) não
  herda o common ⇒ exporta o TZ ele mesmo.
- `contests/<c>/conf` é *sourced* → criação/edição escreve com `printf %q`.
- **ACESSO É RESPONSABILIDADE DA API, NUNCA SÓ DA INTERFACE.** Todo endpoint que devolve
  conteúdo/metadados/**existência** de um recurso CORTA na própria API (`fail 403/404`) quando o
  login não tem permissão. Assuma que clientes (`moj-cli`, `curl`, scripts) vão tentar burlar — a
  trava na UI é só conveniência; a garantia de verdade é sempre o handler. Prefira **404** a 403
  quando revelar a existência já é vazamento.

## Problemas (gestão MOJ-nativa por ORG, keyless — sem Gitea)

**Storage MOJ-nativo (sem Gitea):** cada problema é um **repo git LOCAL** em
`MOJ_PROBLEMS_DIR/<org>/<prob>` — o servidor commita direto (`problem_commit`, flock por-problema) e
indexa inline; sem mirror/push/token/LFS/webhook. O `<org>` do id `<org>#<prob>` é uma **ORG**
(`lib/orgs.sh`, `contests/treino/var/orgs.json`): **membros** escrevem em qualquer problema dela;
**admins** gerem membros + a trava **`public_allowed`** (privada por PADRÃO ⇒ problemas nunca ficam
públicos: anti-vazamento de prova; rebaixar a org despublica em cascata) + **removem a org VAZIA**
(`/orgs/delete`: só admin, org **implícita** e org com problema ⇒ **409**; vazio conferido em disco).
Cada usuário tem a org implícita `<login>` (sempre privada). Migração/cut-over:
`server/bin/migrate-to-orgs.sh`. **Mover** um problema de rascunho entre orgs: `/problems/move`
(muda o id; recusa público/em uso; membro das DUAS orgs) — na web (editor + lista) e no `moj mv`.

**ORG ≠ COLEÇÃO** (ortogonais): a **ORG** é acesso (1 por problema, o prefixo do id). A **COLEÇÃO** é
um **rótulo de agrupamento** (`.moj-meta.json collections[]`, **VÁRIAS por problema**, cross-org) — só
navegação/curadoria, sem acesso. Registro CURADO em `collections.json` (`lib/problems.sh` `coll_*`:
`{name:{owner,created_by,at}}`, nome é TEXTO LIVRE, pode ter espaços); marcar exige que a coleção
exista (`set-collections`/`edit` validam). `/problems/collection*` = coleção-tag; `/orgs/*` = acesso.
O aluno navega por coleção no treino (`web/treino` `?searchcol=`). Semear: `server/bin/seed-collections.sh`.

- **Acesso a problema (helpers centrais em `lib/problems.sh`):** ver **source/pacote/soluções/
  calibração** = só **membro da ORG** (`require_problem_edit` → `org_is_member`,
  **sem atalho de `.admin`**); ver **detalhe/statement** (`get`/`validation`) = membro da org
  **ou** público (`require_problem_view`); **listagens** pré-filtram em `owners_emit` — **membro da
  org VÊ TODOS os problemas dela, inclusive privados** (2026-07-16); problema **privado some** p/
  quem não é membro da org nem colaborador, **inclusive `.admin`**. Não-autorizado: **404**.
  Motivo: provas em elaboração não podem vazar. Testado como não-dono via `moj-cli` (não burlável).

- **Caches de problemas invalidam POR EVENTO, não por TTL** (2026-07-17): a lista do treino
  (`/treino/problems` → `var/problems.json`) é invalidada pelo stamp **`var/.treino-list-dirty`**
  — TODO ponto que cria/remove json servível TOCA o stamp (`index_problem_bg` pós-gen;
  `unindex_problem` em set-public/delete/move/rebaixamento de org; helpers em `lib/tl-store.sh`)
  — e regenera agregando os **sidecars `var/jsons-meta/<id>.json`** (metadados minúsculos,
  derivados do json servível no indexador; nunca slurpar `statement_html_b64` p/ listar). O
  Painel usa os **sumários `run/{tl,validation}-summary.json`** mantidos por upsert nos
  escritores (`tl_store_record`→`tl_summary_upsert`; a validação estática do
  `index_problem_now validate=1`→`val_summary_upsert`; `judge/update-report.sh`); rebuild só a
  frio (`tl_summary_ensure`/`val_summary_ensure`) **e só quando o arquivo NÃO existe** (não há
  TTL — se um escritor esquecer o upsert, o Painel CONGELA até apagarem o sumário; foi o bug dos
  mini-gpt 2026-07-23: validado na CLI, "não validado" na web). Escritor novo de json
  servível/TL/validação ⇒ OBRIGATÓRIO tocar stamp/upsert.
  **Contagens da lista vêm do STORE NOVO** (`server/score/treino-list-gen.sh` agrega
  `users/*/metrics.json` `.solved`/`.attempted`, sobrepondo a base legada `var/json-count/`),
  com refresh LAZY em background via `.score-dirty` + piso 10 min. Mesmo padrão por-evento em
  `/treino/problem-stats` (`.score-dirty`, piso 2 min) e `/index/open_training` (`.score-dirty`
  OU `.treino-list-dirty` — despublicado some da home; piso 5 min). `solvetry` fica por-request
  (lê 1 history; 0,09s).
- **Painel de status (`GET /problems/status`, aba "Painel" da gestão):** agrega, dos problemas de que
  o login é **dono, colaborador ou membro da org**, validação/calibração/time-limits + estados **"calibrando"**
  (varredura única de `run/updates`+`run/commands` por `kind/action==calibrate` — `calibrating_set`) e
  **"precisa recalibrar"** (checksum calibrado em `run/tl/<id>.json` ≠ `tl_checksum` **carimbado no
  índice** por `mojtools/gen-problem-owners.sh`). A FRONTEIRA de acesso é **`owners_visible`** (extraído
  de `owners_emit` — UMA definição do filtro público∪dono∪colaborador∪membro-da-org; o handler
  ainda estreita a dono/colaborador/membro-da-org). **Sem hash de pacote por request**: staleness é a comparação de dois checksums já
  materializados (o do índice regenera em background, ≤30 min de atraso — o gerador tem cache
  assinado por commit do repo + metadata dos arquivos (statsig; só o commit não pega mudança fora
  do git, ex.: normalize de modes) p/ não re-hashear pacote sem mudança; `/problems/tl` dá o valor exato ao vivo p/ 1
  problema — e, quando precisa recalibrar, o **PORQUÊ**: `reason` + `changes`/`changed_files` = os
  commits desde a calibração que tocaram os caminhos do tl-checksum, via git log do repo do problema).
  **Recalibrar em LOTE**: `POST /problems/recalibrate-stale` (mesma fronteira do status; cada item
  via `cal_request`, idempotente + serializado por-problema no claim — lote é seguro); na web é o
  botão "⚙ Recalibrar todos (N)" do Painel, na CLI `moj calibrate --all-stale`. Os **cards
  quantitativos do Painel são clicáveis** (filtram a lista à categoria; de novo = limpa) e o detalhe
  mostra a seção do motivo com link p/ a aba 🕘 Histórico do editor. No `.admin`: **fila de calibração** explícita (`/treino/admin/queue`:
  `calib_pending`/`calib_inflight`/`calib_targeted`, `kind=calibrate` separado de `index`, contadores
  em `sched-lib.sh`) e **contagem de problemas** total/públicos/privados na aba Estatística
  (`/treino/admin/stats`, **só números** — privados contados, nunca listados).

- **Análise dos meus problemas (`GET /problems/my-stats`, aba "Análise"):** panorama de submissões
  dos problemas do login (dono/colaborador/membro da org) agregado em **TODA a plataforma** (treino + as ~174
  turmas): tentativas/acertos/erros/linguagens/usuários/nº de contests/mais popular. Cálculo pesado
  em `server/score/problem-panorama-gen.sh` → cache `contests/treino/var/problem-panorama.json`
  (regen em BACKGROUND quando velho, padrão do índice). **Reconciliação de namespace** (o ponto
  delicado): o history usa `problemas-apc#`/`moj-problems#`/OFFSET legado; o índice usa
  `apc#`/`obi-problems#`/`monitores#` — a ponte é o campo `collections` (aliases derivados por REPO,
  não por problema); legado resolve o offset pela conf (`sc_load`/`{off,raw,dot,hash}`). O handler
  filtra o cache ao dono (`owners_visible`) — **só agregados, sem logins, sem nomes de contests** (só
  `contests_count`; não vaza prova privada). **`public_at`**: `write_meta` carimba a 1ª publicação no
  `.moj-meta.json`; `gen-problem-owners.sh` o leva ao índice (+ seed `public-at-seed.json` do
  `server/bin/backfill-public-at.sh` p/ o histórico) → mapa de calor de entrada de públicos. **Nota:**
  `owners_merged` MESCLA o overlay `authored` sobre a entrada do índice (não substitui) p/ não apagar
  os campos que SÓ o índice calcula: `tl_checksum`/`public_at` (o overlay não os escreve) e **`html`
  (deletado do overlay na mescla)** — o upsert antigo gravava `html:false` fixo e problemas públicos
  ficavam com "sem HTML" eterno no painel. O overlay é **PODADO** (`authored_prune`, chamado pelo
  `ensure_owners_index` com throttle por mtime): entrada já refletida no índice sem divergência nos
  campos de setter sai; divergente/não-indexada fica até o índice alcançar.

- **Histórico git por problema** (`/problems/history` lista/diff, `/problems/download?sha=` versão
  antiga via `git archive`, `/problems/restore` = **commit NOVO por cima** — história nunca é
  reescrita e o `.moj-meta.json` é PRESERVADO no restore, senão um meta antigo republicaria prova
  privada). Gate de SOURCE (membro da org). Web: aba 🕘 Histórico do editor; CLI: `moj log`/`moj
  restore`/`moj download --sha`.
- `lib/problems.sh` (`apply_problem_fields` / `read_problem_source` / `write_meta` / `problem_commit`
  = commit git LOCAL por problema, sem Gitea) + `lib/orgs.sh` (acesso por org). Handlers em
  `handlers/problems/` (+ `handlers/orgs/`).
- **Pacote canônico**: o formato é descrito, por inteiro e num lugar só, em **`docs/PACOTE.md`**
  (arquivos do pacote, `.moj-meta.json`, `.moj-id`, ORG, COLEÇÃO, ciclo validar→calibrar→publicar).
  **Mudou o pacote? Atualize o `docs/PACOTE.md` no MESMO commit** — é a fonte única, e os outros
  repos (`mojtools`, `moj-cli`) apontam p/ ele. Abaixo só o que é consequência NO CÓDIGO do cdmoj:
  **`languages`** = ids de linguagem de submissão permitidos
  (`[]`/ausente = todas as PADRÃO); o `gen-problem-json.sh` o serve no índice do treino, o dropdown
  do treino filtra por ele, e ele é o último elo da cadeia de fallback de linguagem do contest
  (override-no-contest → whitelist do contest → default do pacote → todas). A cadeia tem FONTE
  ÚNICA em **`lib/langs.sh`** (`effective_problem_langs`/`lang_allowed`) e é **FORÇADA no
  `/submit` e no `/contest/offline-submit`** (`400 lang_not_allowed`, extensão canonicalizada
  py3→py/cc→cpp) — a listagem `contest/problems.sh` usa a mesma função; o dropdown é só
  conveniência (2026-07-22; antes era decorativa e trocar a extensão burlava o ban de função). **Linguagens EXÓTICAS/custom** (`pddl`, `grepe` do curso de compiladores,
  `sas`/`l`/`lpp`/`downward`, …) são **opt-in** em `web/shared/languages.js` (flag `optIn`): NÃO
  aparecem no dropdown por padrão — só quando o problema as **declara** em `languages`. Um id
  exótico não-registrado aparece com o próprio id como label (fallback do `langById`). Habilita,
  p.ex., um problema "só-PDDL" ou "só-grepe".
  **Correção especial** opcional em `scripts/` (checker `compare.sh`, `scripts/<lang>/compile.sh`, …;
  ver `mojtools/docs/correcao-especial.md`): round-trip completo via **`scripts_files`**
  (`[{path,content_b64,exec}|{path,symlink}]` — binário e symlink suportados) + **`score_text`**
  (`tests/score` cru) — `read_problem_source` emite, `apply_problem_fields` grava (scripts_files
  presente = SUBSTITUI `scripts/` inteiro; paths validados, confinados; +x preservado). O **editor
  web gere `scripts/`** na sub-aba **"⚙ correção"** da aba **Soluções & Correção** (lista editável
  + seletor de **templates** via `GET /problems/script-templates`, que lê
  `mojtools/script-templates/` — criar template = criar uma pasta lá) e envia `scripts_files` no
  save; a CLI (`moj push/clone`) faz o mesmo round-trip.
  Mexer em `scripts/` muda o tl-checksum ⇒ recalibração.
  **Driver canônico no pacote = STUB, nunca cópia** (ver `mojtools/CLAUDE.md`): o que roda no
  **host** (`compare.sh`, `<lang>/prep.sh`, `summary.sh`) vai como um stub de ~10 linhas que chama o
  do mojtools; só o que entra na **jaula** (`<lang>/{run,compile}.sh`) é cópia. Cada pacote com a sua
  cópia da bridge do checker fez um bug de `bwrap` nascer replicado em 198 pacotes (e **UE em todo
  teste** de quem a usasse). No `script-templates.sh`, o `exec` sai do bit **+x do ALVO** do symlink —
  stub sem +x = todo problema criado pelo editor nasce quebrado.
  O **título de exibição** é o `.moj-meta.json` `display_title` (o `% Título` do enunciado é legado,
  removido no render — o `<h1 class="moj-title">` vem do campo). **`write_meta` sempre popula
  `display_title`**: se o setter não mandar título e o meta ainda não tiver um, deriva do enunciado
  (`%`/`#+title`/`\section`) ou, em último caso, do slug — o editor nunca vem em branco e treino/gestão
  não caem no slug. (Problemas migrados sem esse campo mostravam o id/vazio.)
- **Gravação idempotente**: ao escrever arquivos do pacote use `_putfile` (exatamente 1 `\n` final).
  `jq -r` sempre encerra com `\n`; sem normalizar, cada "Salvar" inchava os arquivos.
- **Renderizar enunciado**: chame `mojtools/render-statement.sh` (via `$MOJTOOLS_DIR`) — é o
  **mesmo** renderer do "Pré-visualizar" e do HTML servido. Não recriar pandoc à parte.

## Frontend (`web/`)

- Vanilla **ES modules, sem build**, servido estático. `shared/` = cliente de API (`api.js`),
  auth/token (`auth.js`), `ui.js` (`el()`, helpers de DOM), editor CodeMirror 6 (`editor.js`, com
  fallback textarea), gráficos SVG, bandeiras/assets offline.
- Editar e recarregar vale na hora (sem bundler). Validar: `node --check web/**/<arquivo>.js`.
- Editor de problema: `web/problemas/editar.{html,js}` (abas; chama `/problems/*`).
- **i18n pt/en (mecanismo ÚNICO, `shared/i18n.js`)**: `T('texto pt','text en')` é o jeito
  canônico de escrever QUALQUER string de exibição no JS; o par do HTML estático é o atributo
  **`data-en`** (+ `data-en-ph`/`-title`/`-html`/`<html data-en-doctitle>`), traduzido por
  `shared/i18n-dom.js` (inclua o `<script>` na página). Um só `LANG` de módulo governa tudo, com
  **precedência**: **LOCALE do contest** (explícito, via `setLang(loc)` sem persist nas páginas de
  contest — `basic.locale` de `/contest/basic`) **> seletor pt/en do usuário** (header do site,
  `setLang(l,{persist:true})`, localStorage `moj_lang`) **> idioma do browser** (`navigator.language`
  não-pt ⇒ en). O seletor vive só no `site-header.js` (páginas públicas); dentro do contest o
  `LOCALE` fixa o idioma. **NÃO** traduzir: **veredictos** (string vem do servidor — só o rótulo à
  volta), enunciados, **títulos de problema/nomes de contest/time**, corpo de notícias, tags.
- **Toda tela/string nova NASCE nos DOIS idiomas** (`T('pt','en')` no JS, `data-en` no HTML) — deixar
  só em PT é **bug**, igual doc atrasada; nunca renderize texto de exibição sem passar pelo `T`/`data-en`.
- ⚠️ **Campo de data/hora: SEMPRE o par `toLocalDT`/`dtToEpoch`** (`shared/contest-config/util.js`),
  NUNCA `toISOString()`. `<input type="datetime-local">` é lido por `Date.parse` em hora **LOCAL**;
  preencher com `toISOString()` (**UTC**) não fecha o ida-e-volta e **cada Salvar empurra o valor
  pelo offset do fuso** (o painel de Inscrições empurrava +3 h por clique, e a janela nascia +3 h
  na tela). O mesmo vale p/ `type="date"`: componentes locais dos dois lados. `toISOString` só em
  coluna de CSV/nome de arquivo, onde UTC é o combinado.
- ⚠️ **`T()` no TOPO do módulo congela o idioma**: o valor é calculado no import, ANTES de
  `initContestShell` aplicar o `LOCALE` do contest (o rótulo sai no idioma do browser). Rótulo de
  aba/estado/tipo tem de ser **fábrica preguiçosa** — `const TABS = () => [...]`, chamada no render
  (padrão em `bank-panel.js:14`, `contest/admin/admin.js`, `audit-tab.js`).
- **Rótulos da NAV do contest são bilíngues no FRONT** (`shared/nav-i18n.js`): o servidor
  (`navbuttons.sh`) manda label PT fixo e a **URL é o identificador estável** — `navLabel(url,label)`
  resolve o par pt/en na renderização (os 4 renderizadores de nav — `contest-shell.js`,
  `lib/contest-chrome.js`, `contest.js`, `score/score.js` — re-pintam no evento `moj:lang`).
  **Botão novo no `navbuttons.sh` ⇒ linha nova no mapa do `nav-i18n.js`** (sem a linha ele cai no
  label PT do servidor — não some, mas vira string só-PT, que é bug). Datas: `toLocaleString()` SEM
  `'pt-BR'` fixo (o formato segue `document.documentElement.lang`, que o `applyHtmlLang` ajusta).
- **Painel de admin do contest = SHELL + módulos.** `web/contest/admin/admin.js` só navega: 4 grupos
  (`central|prova|pessoas|operacao`) × painéis, hash **`#grupo/painel`** e o mapa `ALIAS` com TODOS
  os hashes antigos (link salvo/manual não pode quebrar — ao renomear um painel, ATUALIZE o ALIAS).
  Cada painel é um `web/contest/admin/<nome>-tab.js` exportando `make<Nome>Tab(CONTEST)` →
  **`{panel, load}`** (construído uma vez e escondido: mantém filtros/timers; `load()` roda de novo
  a cada volta ao painel). Helpers compartilhados (CSV, `downloadAuthed`, `fmtS/fmtDate`,
  `field/chk/mkBool`) em **`shared/admin-ui.js`** — não recrie a 4ª cópia. A **Central**
  (`central-tab.js`) renderiza o `preflight` como lista acionável: o mapa `TARGET` (id da checagem →
  `[grupo, painel]`) mora no FRONT, então checagem nova do servidor aparece sozinha e só ganha botão
  quando entrar no mapa. `settings-tab.js` REALOCA os nós vivos do `makeSettingsEditor` em 5
  `<details>` por ÍNDICE — mudou a ordem dos campos no editor? Ajuste o `GROUPS` de lá.

## Testar / rodar

- `bash -n server/**/<arquivo>.sh`; `node --check web/**/<arquivo>.js`.
- Round-trip de pacote: `source server/api/v1/lib/problems.sh` e exercite
  `apply_problem_fields`/`read_problem_source` num diretório de scratch (defina `RUNDIR`,
  `TREINO_JSONS`, `MOJ_TL_STORE` para não tocar no real).
- Em dev sem sandbox real (`fbwrap`, no-op do firejail), `validate-problem.sh` **defere** a
  execução das soluções para a calibração no juiz — não é bug.

## Convenções

- **PRODUÇÃO SÓ RECEBE CÓDIGO VIA GIT**: no servidor e nos juízes, `cdmoj`/`mojtools`/`judge`/
  `moj-cli` mudam SÓ por `git pull` (deploy = pull + `make deploy` + restart). Nunca editar
  código direto na máquina — mod local bloqueia o próximo pull e não tem histórico. Estado
  local legítimo = APENAS config/segredo de runtime (`bot.conf`, `agent.env`, `run/secrets/`,
  `~moj/mojinho-live/`). Vale p/ humanos e agentes.

- Commits em PT, presente, prefixados pelo componente (ex.: `problemas: …`, `score/stats: …`). O rodapé
  leva **só** `Co-Authored-By:` — **nunca** uma linha `Claude-Session:` (ruído no histórico).
- **Documentação junto com o código** (doc atrasada = bug): rota/campo novo → `docs/API.md` **e**
  `web/api/openapi.json` (manter os dois em sincronia); arquitetura/fluxo → `docs/OVERVIEW.md`/`docs/FLOW.md`.
  `bash docs/build-html.sh` p/ refazer o HTML.
- **API mudou ⇒ ressincronizar `web/` E `moj-cli/` no MESMO commit** (não só a doc). Os dois são
  clientes do contrato da API. Antes de fechar, VERIFIQUE de fato: a home carrega, o login funciona,
  `moj login`/`moj whoami` funcionam contra a base real. Regressão de API costuma se manifestar como
  "web não carrega / não loga / 502" — investigue o servidor, não só o cliente.
- **Armadilha `//` do jq com BOOLEANO (vazou prova em elaboração p/ a internet):** o `//` trata
  **`false` como vazio**, igual a `null` — `false // "x"` devolve `"x"`. Então
  `jq -r '.public // "unset"'` **nunca** devolve `"false"`, e a checagem que dependia disso virou
  código morto: **todo problema privado ia parar na lista pública anônima do treino** (com
  enunciado). Para testar bool use **`jq -e '.campo == true'`** (ou `== false`). `// false` como
  *default* é seguro (o fallback é o próprio valor falsy) — o veneno é `//` com um sentinela.
  O portão da lista pública tem teste: `server/test/smoke-public-index.sh`; a rede de segurança é
  `server/bin/audit-public-index.sh`.
- **Armadilha `jq 1.7` (imagem) × `jq 1.8` (dev) — causou outage silencioso da listagem inteira:**
  no **jq 1.7** (Debian, o da imagem de produção) o **valor de um campo de objeto NÃO aceita operador
  binário solto** — `{a: X + Y}`, `{a: .x // 0}`, `{a: .x == 1}`, `{a: .x and .y}` são **erro de
  sintaxe**. O **jq 1.8** (dev) aceita. Escreva SEMPRE com parênteses: `{a: (X + Y)}`. O sintoma em
  produção é cruel: o `2>/dev/null` engole o erro, o jq seguinte recebe stdin vazio, **sai 0 sem
  imprimir nada**, o `|| fallback` não dispara e o cliente recebe **200 com CORPO VAZIO**
  ("Resposta inválida do servidor" na web; `moj ls` mudo). Guard: **`make check-jq`**
  (`server/test/jq-portability.sh` compila os ~900 programas jq com o jq da imagem).
  Corolário: função que alimenta um `| jq` **nunca** pode devolver vazio (ver `owners_merged`).
- **Armadilha `jq -R`/`jq -s` com ENTRADA VAZIA — o board e o Painel ficavam MUDOS (200 + lista
  vazia):** um `jq` que lê do stdin e **não recebe entrada nenhuma** não roda o programa: **não
  imprime nada e SAI 0**. Então `… | jq -Rc '[inputs|…]' || echo '[]'` **não** cai no `|| ` (não houve
  erro!) e devolve **string vazia**. Era o `calibrating_set`: com as filas vazias — o estado NORMAL —
  ele voltava `""`, o `/problems/status` fazia `--argjson CAL ""` (*"invalid JSON text passed to
  --argjson"*), o jq grande morria e o handler caía num fallback `{total:0, problems:[]}`. Conserto:
  **`jq -n`** (roda o programa uma vez mesmo sem entrada) **e** guarda de vazio no chamador
  (`[[ -n "$x" ]] || x='[]'`) antes de todo `--argjson`. Mesma família do `grep -c` abaixo.
- **MONTE O CORPO ANTES DO CABEÇALHO.** Quem faz `emit_json 200 OK` e só depois roda o `jq` que gera
  o corpo **não tem mais como dizer 4xx/5xx** — o único destino de uma falha vira "200 com lista
  vazia", que o cliente lê como *"você não tem nada"*. Calcule em variável/arquivo, cheque o rc, e
  **só então** emita (ver `handlers/problems/status.sh` e `owners_emit`).
- **Armadilha `jq -s A B` com A AUSENTE — DESLOCA as entradas:** se `A` não existe (ou tem 0 byte), o
  jq só reclama no stderr (engolido pelo `2>/dev/null`), **não aborta**, e `.[0]` passa a ser **B**. O
  programa devolve um `{"problems":[]}` **válido** e a guarda `[[ -n "$out" ]]` não dispara. Use
  **`--slurpfile`** (erra se o arquivo não abre) e valide o arquivo antes. Guard:
  `server/test/smoke-owners-index.sh`.
- **Modo de arquivo do PACOTE é canônico (644/755), NUNCA o umask do processo.** O fcgiwrap roda com
  `umask 007` (p/ o socket unix nascer 0770), então tudo que a API gravava saía **660** enquanto o
  mesmo pacote vindo de `moj upload` (tar+rsync) saía **644** — e como o `tl-checksum` inclui o
  **modo** de `scripts/*`, o MESMO conteúdo dava checksum diferente conforme o caminho (⇒ recalibração
  espúria). Toda escrita de pacote passa por **`_pkg_canon_modes`** (`lib/problems.sh`); pacote antigo
  se conserta com `server/bin/normalize-pkg-modes.sh --apply`.
- **Corpo GRANDE (pacote de problema) vai em ARQUIVO, nunca em variável:** use **`read_body_file`** e
  `jq … < "$f"`. Cada `jq … <<<"$body"` é um here-string: o bash **regrava o corpo inteiro** num temp
  e o jq **re-parseia tudo**. O `/problems/edit` fazia isso **36 vezes** (~50 s de CPU e 3,6 GB de
  I/O num pacote de 84 MB) e lia os testes de um **pipe** — e o `read` do bash sobre pipe faz **1
  syscall por byte** (1,74 MB/s medido). Resultado: 504 do nginx aos 120 s **com o pacote pela
  metade**. Padrão certo: 1 passada de jq p/ um manifesto (`@sh` + `eval`), streams **NUL**
  (`--raw-output0`) gravados em ARQUIVO e `while IFS= read -r -d ''` lendo **do arquivo** (fd seekable
  ⇒ o bash lê em bloco). Medido: 244 s ⇒ 9,7 s num pacote de 140 MB.
- **Armadilha `grep -c` (causou outage 502):** `grep -c` IMPRIME a contagem (`0`) **e SAI com código
  1** quando não há match. NUNCA escreva `grep -c … || echo 0` (retorna `"0\n0"` → estoura `(( … ))`
  e **inunda o stderr**; sob fcgiwrap o pipe de stderr enche, a escrita bloqueia e o **worker trava** →
  502 em toda a API). Capture direto (`n="$(grep -c … 2>/dev/null)"`, o exit 1 é inofensivo em `$()`) e
  saneie a dígitos (`n="${n//[^0-9]/}"; n="${n:-0}"`) antes de qualquer aritmética.
- **Formato do pacote de problema = doc obrigatória, e a FONTE ÚNICA é `docs/PACOTE.md`.** QUALQUER
  mudança no pacote (arquivos, campos, `.moj-meta.json`, `conf`, layout de `tests/`/`sols/`, de onde
  vem o **título**, seções obrigatórias do enunciado) atualiza o **`docs/PACOTE.md` no MESMO commit**.
  Se a mudança for de **rota/contrato**, `docs/API.md` + `web/api/openapi.json` também (as rotas ficam
  lá; o formato, não). Os demais repos (`mojtools/README.md`, `moj-cli/README.md`, os `CLAUDE.md`)
  **apontam** p/ o `PACOTE.md` e não redescrevem o formato — não recrie a divergência de 4 cópias que
  gerou o bug do título vazio.
- **Não commitar**: `server/var/news/nova-interface.json` (mod local pré-existente).
