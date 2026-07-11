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
- Clarifications: o **asker é anônimo** p/ os juízes (handler corta `.login`); responder exige
  **reserva** (`clarification-claim`). Sempre auditar (`audit_log_to`) toda ação de juiz/chefe.
- **Balão** (`.staff`): tarefa **automática** na 1ª solução (`Accepted`) de cada (time, problema),
  na MESMA fila do `.staff` (campo `kind:"balloon"` no `print-requests/<id>.json`, sem `.src`). Gerada
  **preguiçosamente** por `pr_reconcile_balloons` (em `lib/print.sh`) ao carregar `staff/queue` — lê o
  veredicto **final** do `controle/history` (vale auto+manual), dedup por id determinístico, **sem
  mudar o daemon**. Folha via `pr_build_balloon` (cor por `balloons.json`/default ICPC + tabela
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
  **ou** público (`require_problem_view`); **listagens** pré-filtram em `owners_emit` (problema
  **privado some** p/ quem não é dono/colaborador, **inclusive `.admin`**). Não-autorizado: **404**.
  Motivo: provas em elaboração não podem vazar. Testado como não-dono via `moj-cli` (não burlável).

- **Painel de status (`GET /problems/status`, aba "Painel" da gestão):** agrega, dos problemas de que
  o login é **dono ou colaborador**, validação/calibração/time-limits + estados **"calibrando"**
  (varredura única de `run/updates`+`run/commands` por `kind/action==calibrate` — `calibrating_set`) e
  **"precisa recalibrar"** (checksum calibrado em `run/tl/<id>.json` ≠ `tl_checksum` **carimbado no
  índice** por `mojtools/gen-problem-owners.sh`). A FRONTEIRA de acesso é **`owners_visible`** (extraído
  de `owners_emit` — UMA definição do filtro público∪dono∪colaborador; o handler ainda estreita a
  dono/colaborador). **Sem hash de pacote por request**: staleness é a comparação de dois checksums já
  materializados (o do índice regenera em background, ≤30 min de atraso — o gerador tem cache por
  commit do repo p/ não re-hashear pacote sem mudança; `/problems/tl` dá o valor exato ao vivo p/ 1
  problema). No `.admin`: **fila de calibração** explícita (`/treino/admin/queue`:
  `calib_pending`/`calib_inflight`/`calib_targeted`, `kind=calibrate` separado de `index`, contadores
  em `sched-lib.sh`) e **contagem de problemas** total/públicos/privados na aba Estatística
  (`/treino/admin/stats`, **só números** — privados contados, nunca listados).

- **Análise dos meus problemas (`GET /problems/my-stats`, aba "Análise"):** panorama de submissões
  dos problemas do login (dono/colaborador) agregado em **TODA a plataforma** (treino + as ~174
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
  `tl_checksum`/`public_at` — sem isso, problemas no overlay perdiam esses campos.

- `lib/problems.sh` (`apply_problem_fields` / `read_problem_source` / `write_meta` / `problem_commit`
  = commit git LOCAL por problema, sem Gitea) + `lib/orgs.sh` (acesso por org). Handlers em
  `handlers/problems/` (+ `handlers/orgs/`).
- **Pacote canônico**: `docs/enunciado.{md,org,tex}`, `tests/input|output/` (exemplos = `sample*`,
  na ordem), `sols/{good,slow,wrong,pass,upcoming}/`, `conf`, `author`, `tags`, `tests/score`,
  `docs/sample-notes.json` (explicações de exemplo, na ordem), `docs/solucao.md` (editorial — só
  setter, **não** vai ao aluno). Metadados em `.moj-meta.json` (`display_title`, `public`,
  `collections`, `languages`, …). **`languages`** = ids de linguagem de submissão permitidos
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
  auth/token (`auth.js`), `ui.js` (`el()`, i18n pt/en), editor CodeMirror 6 (`editor.js`, com
  fallback textarea), gráficos SVG, bandeiras/assets offline.
- Editar e recarregar vale na hora (sem bundler). Validar: `node --check web/**/<arquivo>.js`.
- Editor de problema: `web/problemas/editar.{html,js}` (abas; chama `/problems/*`).

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
- **Armadilha `grep -c` (causou outage 502):** `grep -c` IMPRIME a contagem (`0`) **e SAI com código
  1** quando não há match. NUNCA escreva `grep -c … || echo 0` (retorna `"0\n0"` → estoura `(( … ))`
  e **inunda o stderr**; sob fcgiwrap o pipe de stderr enche, a escrita bloqueia e o **worker trava** →
  502 em toda a API). Capture direto (`n="$(grep -c … 2>/dev/null)"`, o exit 1 é inofensivo em `$()`) e
  saneie a dígitos (`n="${n//[^0-9]/}"; n="${n:-0}"`) antes de qualquer aritmética.
- **Formato do pacote de problema = doc obrigatória.** QUALQUER mudança no pacote (arquivos, campos,
  `.moj-meta.json`, `conf`, layout de `tests/`/`sols/`, de onde vem o **título**, seções obrigatórias
  do enunciado) exige atualizar **no mesmo commit** TODAS as fontes que o descrevem — e elas vivem em
  **repos diferentes**: `docs/API.md` (bloco `source`/`create`/`edit`), a seção **Pacote canônico**
  deste `CLAUDE.md`, `moj-cli/README.md` ("Pacote do problema") e `mojtools/CLAUDE.md` (render/gen-json).
  Divergência entre elas foi o que gerou o bug do título vazio; mantê-las em sincronia é parte da mudança.
- **Não commitar**: `server/var/news/nova-interface.json` (mod local pré-existente).
