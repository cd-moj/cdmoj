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
- **Auth**: `Authorization: Bearer <token>` → sessão em `run/sessions/` (700), gravada com
  `printf %q` (é *sourced*). Papéis por sufixo no login (`.admin/.judge/.cjudge/.staff/.cstaff/.mon`).
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
  preguiçosos (`contest/score`/`statistics`/`response-stats`/balões) = **`var/.score-dirty`**
  (tocado por `user_history_append/replace`) + `conf`; `var/.metrics-stamp` dispara recompute em
  massa no `build.sh` quando o `conf` muda (ex.: `FREEZE_TIME` editado). **Migração** de contest
  legado (arquivado em `contests-legado/`): `server/bin/store-migrate.sh <c>` (dry-run por padrão).
  Handlers de usuário do admin (`user-add`/`user-disable`/`user-remove`/`users-set-password`)
  escrevem no account.json; remover = `mv` p/ `.removed-users/`. **`.team` agora tem WRITERS
  na API** (antes só o store-migrate): `users-bulk`/`user-add`/`contest-create users[]` aceitam
  `univ_short/univ_full/country/region` (helper `team_fields_json` + `account_team_merge` em
  lib/users.sh — saneiam `:`/tab/newline) e `/contest/admin/teams` (aba 👥 Times) faz set
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
  recuperação por vínculo, `link-start`. O **bot** (`mojinho-bot/mojinho-api.sh`) é transporte fino:
  autentica com **bot-token** `mojb_…` (`lib/bot-auth.sh` `require_bot`, `run/secrets/bot.token`) — não
  loga como `.admin`, sem GODS. **Alertas**: `lib/alerts.sh` + `GET /ops/alerts` (a API avalia com
  histerese/cooldown e enfileira no outbox `run/alerts/`; o bot drena e entrega a `.admin` vinculados
  + grupo). Senha nova **só por DM** (nunca na web).
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
  de juiz também são segurados** (o competidor só vê `Not Answered Yet`); dois `.judge` decidem
  (`handlers/contest/review/*` + `lib/review.sh`, flock + TTL), e o veredicto vai ao aluno pelo
  **escritor único** via o consumidor `setverdict` do daemon. O **voto é permanente e libera o juiz**
  (pega outra na hora); o **alerta de conflito é global** (`web/shared/chief-alert.js`, disparado pelo
  `auth.status` → segue o chief/admin em qualquer página); a aba **Situação** traz estatística por juiz
  (`review/stats`, derivada do `admin-audit.log`). **Mexeu no `judged.sh` → reinicie o
  daemon** (mantendo `INTAKE_MODE`/`JUDGE_BACKEND`); handlers/score são frescos por requisição.
- **Liveness do daemon = `daemon_judged_alive()` (`lib/common.sh`), NUNCA `pgrep` direto.** Em
  produção a API (`moj-api`) e o daemon (`moj-judged`) são containers **separados**: o `pgrep` da API
  jamais vê o processo. O daemon bate um heartbeat em `run/judged.alive` (volume compartilhado) e o
  helper aceita processo local **ou** heartbeat fresco (TTL 120s). Voltar ao `pgrep` = painel dizendo
  "daemon caído" com ele vivo + alertas de `lib/alerts.sh` disparando p/ sempre.
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

- **Painel de status (`GET /problems/status`, aba "Painel" da gestão):** agrega, dos problemas de que
  o login é **dono, colaborador ou membro da org**, validação/calibração/time-limits + estados **"calibrando"**
  (varredura única de `run/updates`+`run/commands` por `kind/action==calibrate` — `calibrating_set`) e
  **"precisa recalibrar"** (checksum calibrado em `run/tl/<id>.json` ≠ `tl_checksum` **carimbado no
  índice** por `mojtools/gen-problem-owners.sh`). A FRONTEIRA de acesso é **`owners_visible`** (extraído
  de `owners_emit` — UMA definição do filtro público∪dono∪colaborador∪membro-da-org; o handler
  ainda estreita a dono/colaborador/membro-da-org). **Sem hash de pacote por request**: staleness é a comparação de dois checksums já
  materializados (o do índice regenera em background, ≤30 min de atraso — o gerador tem cache por
  commit do repo p/ não re-hashear pacote sem mudança; `/problems/tl` dá o valor exato ao vivo p/ 1
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
  (`handlers/contest/problems.sh`: override-no-contest → whitelist do contest → default do
  pacote → todas). **Linguagens EXÓTICAS/custom** (`pddl`, `grepe` do curso de compiladores,
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

## Testar / rodar

- `bash -n server/**/<arquivo>.sh`; `node --check web/**/<arquivo>.js`.
- Round-trip de pacote: `source server/api/v1/lib/problems.sh` e exercite
  `apply_problem_fields`/`read_problem_source` num diretório de scratch (defina `RUNDIR`,
  `TREINO_JSONS`, `MOJ_TL_STORE` para não tocar no real).
- Em dev sem sandbox real (`fbwrap`, no-op do firejail), `validate-problem.sh` **defere** a
  execução das soluções para a calibração no juiz — não é bug.

## Convenções

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
