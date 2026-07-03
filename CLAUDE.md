# cdmoj — plataforma MOJ (server bash + web ESM)

Plataforma do MOJ: **API bash** sob nginx+fcgiwrap (`server/`) + **frontend vanilla ESM
sem build** (`web/`) + documentação (`docs/`). Repo git próprio (`cd-moj/cdmoj`), roda no
host web. Os juízes **não** precisam deste repo. Workspace multi-repo: ver `../CLAUDE.md`.

**Leia primeiro `docs/OVERVIEW.md`** (arquitetura, API, frontend, o que existe) e
`docs/FLOW.md` (o caminho de uma submissão). Rotas: `docs/API.md` + `web/api/openapi.json`.
Deploy: `docs/DEPLOY.md` (+ `docs/DEPLOY-GITEA.md`). Docs em HTML: `bash docs/build-html.sh`.

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
  `printf %q` (é *sourced*). Papéis por sufixo no login (`.admin/.judge/.cjudge/.staff/.mon`).
  **`.cjudge`** = juiz-chefe: `is_judge` vale p/ ele (herda juiz) + `is_chief`/`is_admin_or_chief`
  p/ os extras escopados (editar notícias/respostas já dadas, Situação, Todas Submissões, resolver
  conflitos, config de auto-veredicto) — **não** é admin pleno. Ao mexer em papel, lembre das
  **quatro** listas de sufixo independentes: `lib/auth.sh`, `score/score-common.sh`,
  `score/stats-gen.sh`, `handlers/auth/login.sh` (+ guard `treino/profile/username.sh`).
  Auto-cadastro **nunca** cria papel por sufixo: use `is_reserved_role_login` (`lib/auth.sh`) —
  já aplicado no signup; o `/admin/adduser` (admin autenticado) **continua** podendo criar
  `.judge`/`.staff` de um contest (legítimo).
- **Store por-usuário (`USER_STORE=v2`, `lib/users.sh`)**: contests migrados guardam cada conta em
  `contests/<c>/users/<login>/` (`account.json` autoritativo; `passwd` DERIVADO por `regen_passwd`;
  `history` próprio de 6 campos `tempo:probid:lang:verdict:sub_epoch:subid`, login implícito;
  `metrics.json`; `submissions/<subid>.<ext>`, `mojlog/<subid>.html`, `results/<subid>.json` — **sem
  login no nome**). **Rename de conta = `mv` do diretório** (`user_rename` + telegram index). O
  `controle/history` global some; leitores usam `emit_user_history`/`emit_history_stream`
  (formato global de 7 campos) e os scripts de placar materializam o stream num temp. `store_v2 <c>`
  ramifica write-path (`judged.sh`/`submit.sh`) e leitura. **Migração**: `server/bin/store-migrate.sh
  <c>` (dry-run por padrão; `--apply` seta `USER_STORE=v2`). Competições não-migradas seguem no legado.
- **Telegram (overlay só do treino) + alertas**: `lib/telegram.sh` (índice `var/telegram/{by-tgid,by-login}`,
  nonce em `run/telegram/`), cadastro web-first (`handlers/treino/signup/*` + página `web/treino/cadastro/`),
  recuperação por vínculo, `link-start`. O **bot** (`mojinho-bot/mojinho-api.sh`) é transporte fino:
  autentica com **bot-token** `mojb_…` (`lib/bot-auth.sh` `require_bot`, `run/secrets/bot.token`) — não
  loga como `.admin`, sem GODS. **Alertas**: `lib/alerts.sh` + `GET /ops/alerts` (a API avalia com
  histerese/cooldown e enfileira no outbox `run/alerts/`; o bot drena e entrega a `.admin` vinculados
  + grupo). Senha nova **só por DM** (nunca na web).
- **Contrato do resultado do juiz**: além do `verdict` de display (com o score embutido, ex.
  `Accepted,100p` — gerado por `mojtools/build-and-test.sh`), o JSON traz **`verdict_canon`**
  (canônico, **sem** score) + `score/score_max/score_kind/correct/total_tests`. Fonte única =
  `report.env` do mojtools (os dois backends, juiz real e `judge-gw` dev, o repassam). O daemon
  **casa o auto-veredicto pelo `verdict_canon`** (não pela string com score) e persiste os campos em
  `results/<id>.json`, servidos por `/submission/summary` (linha "resumo" do treino). O competidor
  vê o veredicto **limpo** em placares binários (icpc/treino) — `contest/history` corta o `,Np`;
  OBI/heurístico mantêm o score.
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
- `contests/<c>/conf` é *sourced* → criação/edição escreve com `printf %q`.
- **ACESSO É RESPONSABILIDADE DA API, NUNCA SÓ DA INTERFACE.** Todo endpoint que devolve
  conteúdo/metadados/**existência** de um recurso CORTA na própria API (`fail 403/404`) quando o
  login não tem permissão. Assuma que clientes (`moj-cli`, `curl`, scripts) vão tentar burlar — a
  trava na UI é só conveniência; a garantia de verdade é sempre o handler. Prefira **404** a 403
  quando revelar a existência já é vazamento.

## Problemas (gestão Gitea, keyless)

- **Acesso a problema (helpers centrais em `lib/problems.sh`):** ver **source/pacote/soluções/
  calibração** = só **dono ou colaborador** (`require_problem_edit`, checagem ao vivo no Gitea,
  **sem atalho de `.admin`**); ver **detalhe/statement** (`get`/`validation`) = dono/colaborador
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

- `lib/problems.sh` (`apply_problem_fields` / `read_problem_source` / `write_meta`) +
  `lib/git-broker.sh` (commit/push via token efêmero). Handlers em `handlers/problems/`.
- **Pacote canônico**: `docs/enunciado.{md,org,tex}`, `tests/input|output/` (exemplos = `sample*`,
  na ordem), `sols/{good,slow,wrong,pass,upcoming}/`, `conf`, `author`, `tags`, `tests/score`,
  `docs/sample-notes.json` (explicações de exemplo, na ordem), `docs/solucao.md` (editorial — só
  setter, **não** vai ao aluno). Metadados em `.moj-meta.json` (`display_title`, `public`, …).
  **Correção especial** opcional em `scripts/` (checker `compare.sh`, `scripts/<lang>/compile.sh`, …;
  ver `mojtools/docs/correcao-especial.md`): o editor web **não** a escreve, mas `read_problem_source`
  a **lista** (campo `scripts`, só leitura) e a árvore do pacote a **exibe**.
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
