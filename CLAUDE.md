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
- **Auth**: `Authorization: Bearer <token>` → sessão em `run/sessions/` (700), gravada com
  `printf %q` (é *sourced*). Papéis por sufixo no login (`.admin/.judge/.cjudge/.staff/.mon`).
  **`.cjudge`** = juiz-chefe: `is_judge` vale p/ ele (herda juiz) + `is_chief`/`is_admin_or_chief`
  p/ os extras escopados (editar notícias/respostas já dadas, Situação, Todas Submissões, resolver
  conflitos, config de auto-veredicto) — **não** é admin pleno. Ao mexer em papel, lembre das
  **quatro** listas de sufixo independentes: `lib/auth.sh`, `score/score-common.sh`,
  `score/stats-gen.sh`, `handlers/auth/login.sh` (+ guard `treino/profile/username.sh`).
- **Veredicto manual** (`MANUAL_VERDICT`, opt-in): o **daemon** (`daemons/judged.sh`) SEGURA o
  veredicto computado (grava `contests/<c>/review/<id>.json`, history fica provisório) salvo o que
  a matriz `auto-verdicts.json` (problema×lang×veredicto) libera; dois `.judge` decidem
  (`handlers/contest/review/*` + `lib/review.sh`, flock + TTL), e o veredicto vai ao aluno pelo
  **escritor único** via o consumidor `setverdict` do daemon. **Mexeu no `judged.sh` → reinicie o
  daemon** (mantendo `INTAKE_MODE`/`JUDGE_BACKEND`); handlers/score são frescos por requisição.
- Clarifications: o **asker é anônimo** p/ os juízes (handler corta `.login`); responder exige
  **reserva** (`clarification-claim`). Sempre auditar (`audit_log_to`) toda ação de juiz/chefe.
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

- `lib/problems.sh` (`apply_problem_fields` / `read_problem_source` / `write_meta`) +
  `lib/git-broker.sh` (commit/push via token efêmero). Handlers em `handlers/problems/`.
- **Pacote canônico**: `docs/enunciado.{md,org,tex}`, `tests/input|output/` (exemplos = `sample*`,
  na ordem), `sols/{good,slow,wrong,pass,upcoming}/`, `conf`, `author`, `tags`, `tests/score`,
  `docs/sample-notes.json` (explicações de exemplo, na ordem), `docs/solucao.md` (editorial — só
  setter, **não** vai ao aluno). Metadados em `.moj-meta.json` (`display_title`, `public`, …).
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
  `web/api/openapi.json` (manter os dois em sincronia); arquitetura/fluxo → `docs/OVERVIEW.md`/`docs/FLOW.md`;
  formato de pacote → `docs/API.md`. `bash docs/build-html.sh` p/ refazer o HTML.
- **Não commitar**: `server/var/news/nova-interface.json` (mod local pré-existente).
