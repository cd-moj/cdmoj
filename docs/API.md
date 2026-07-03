# MOJ — API v1 (referência)

Base: `/api/v1`. Roteador único: `server/api/v1/router.sh` → `handlers/<rota>.sh`.
Auth: `Authorization: Bearer <token>`. Respostas JSON com envelope `{success:true, …}` ou
`{success:false, error:{message,code}}` + status HTTP correto. Histórico e placar são **TXT** cru.
Horários em **EPOCH**. IDs validados contra path-traversal.

## Auth
| Rota | Método | Auth | I/O |
|---|---|---|---|
| `/auth/login?contest=<c>` | POST | — | body `{username,password}` → `{token,logged_in,username,name,contest}` |
| `/auth/status?contest=<c>` | GET | Bearer | `{logged_in,login,name,contest,is_admin,is_judge,is_staff,is_chief}` (`.cjudge` = juiz-chefe → `is_judge:true,is_chief:true`) |
| `/auth/logout` | POST | Bearer | `{logged_out:true}` |

## Index (home)
| Rota | I/O |
|---|---|
| `/index/news` | `{news:[{id,title,date,summary,url}]}` |
| `/index/contests?page=N` | `{open:[…],upcoming:[…],closed:{items:[…],page,per_page,total}}` (cada item `{id,title,start_time,end_time,problems_count,url,scoreboard_url}`). Encerrados paginados (20/pág); **`?all=1`** devolve todos (usado pela página de arquivo `/contests/`). |
| `/index/open_training` | `{top_users:[…],recent_solved:[…],most_solved_week:[…],most_solved_prev_week:[{problem_id,problem_title,solved_count,url}],most_used_editor_prev_week:{top:{editor,count}\|null,total,ranking:[{editor,count}]}}` (`prev_week`=resolvedores distintos por problema; `editor`=mais usado nas aceitas da semana passada, `web` ou editor declarado) |

## Treino
| Rota | Auth | I/O |
|---|---|---|
| `/treino/problems` | — | array `[{id,title,tags,collections,solved_count,attempted_count}]` (`collections` = `.moj-meta.json` do pacote, um problema pode estar em várias; contagens de `var/json-count/<arquivo>` casadas por nome de arquivo; cache 5 min em `var/problems.json`) |
| `/treino/problem?id=<id>` | — | `{id,title,author,statement_html_b64,time_limits,tags,collections}` (`author` = arquivo `author` do pacote, verbatim; vários autores juntados por `, `; vazio se ausente; `collections` = coleções do `.moj-meta.json`) |
| `/treino/solvetry?user=<u>` | opc | `{solved:[ids],attempted:[ids]}` |
| `/treino/history?id=<id>` | Bearer | TXT 7 campos `tempo:user:probid:lang:verdito:epoch:subid` |
| `/treino/history-full?user=<u>` | opc | TXT 7 campos (todo o histórico) |
| `/treino/profile` | Bearer | GET: perfil + cota de username · POST `{name?,university?}` |
| `/treino/profile/password` | Bearer | POST `{old_password,new_password}` |
| `/treino/profile/username` | Bearer | POST `{new_username}` — **máx. 2/ano**, cascata nos arquivos de controle |
| `/treino/profile?user=<u>` | opc | GET visão pública (respeita privacidade); POST aceita também `favorite_editor`, `profile_public` |
| `/treino/profile/photo?user=<u>` | opc/Bearer | GET serve png 100×100 · POST `{image_b64}` (redimensiona) |
| `/treino/editors` | — | ranking dos editores favoritos declarados `{editors:[{editor,count}],total}` |
| `/treino/problem-stats?id=<p>` | — | estatísticas do problema (métricas, veredictos, por-linguagem c/ solvers distintos, editores, avatares públicos) — **cacheado** (TTL `PROBLEM_STATS_TTL_MIN`) |

## Treino — cadastro & vínculo Telegram (overlay do treino)
Cadastro **web-first** verificado pelo Telegram (1 Telegram = 1 conta; anti-duplicata). Os endpoints
`verify`/`telegram`/`recover-password` são autenticados pelo **token do bot** (`Authorization: Bearer
mojb_…`, `require_bot`, segredo em `run/secrets/bot.token`) — o bot **não** loga como `.admin`.

| Rota | Auth | I/O |
|---|---|---|
| `/treino/signup/start` | público (POST) | `{login?,fullname,university?}` → `{nonce, deep_link, expires_at}`. Valida o login (bloqueia sufixo de papel) e cria um nonce (TTL 15 min). **Não cria conta.** |
| `/treino/signup/status?nonce=` | público (GET) | `{status: pending\|created\|already_linked\|linked\|expired, login?}` — **nunca** devolve a senha |
| `/treino/signup/verify` | **bot** (POST) | `{nonce,telegram_id,telegram_username?,first_name?,last_name?}` → consome o nonce (uso único), anti-duplicata, cria+vincula (`created`) ou vincula conta logada (`linked`); devolve `{status,login,password?}` (senha só p/ DM) |
| `/treino/signup/telegram` | **bot** (POST) | bot-first (`/participar`): `{telegram_id,…}` → cria+vincula ancorado no `telegram_id` (idempotente) ou `already_linked` |
| `/treino/recover-password` | **bot** (POST) | `{telegram_id}` → resolve o login pelo vínculo, gera nova senha → `{status:ok\|not_linked,login?,password?}` |
| `/treino/telegram/link-start` | Bearer | conta logada gera nonce `purpose:link` p/ vincular o próprio Telegram (ex.: `.admin` receber alertas) → `{nonce,deep_link,expires_at}` |

## Treino — painel admin (`.admin`, Bearer)
Acesso registra **IP** (`X-Forwarded-For`/`REMOTE_ADDR`) e **User-Agent** na sessão e em `var/access.log`.

| Rota | Método | Ação |
|---|---|---|
| `/treino/admin/sessions` | GET | sessões ativas `{count,sessions:[{login,name,ip,user_agent,login_at}]}` |
| `/treino/admin/access-log?day=YYYY-MM-DD` | GET | log de acessos (filtra por dia) |
| `/treino/admin/queue` | GET | pendentes por lista + **calibração** `{total_pending,spool_queued,calib_pending,calib_inflight,calib_targeted,lists:[{contest,name,pending}]}` (`calib_pending` = fila de calibração `kind=calibrate`, separada de `index`; `calib_targeted` = recalibrações direcionadas por host) |
| `/treino/admin/judges` | GET | máquinas de juiz (modelo pull) `{online,busy,machines:[{host,online,busy,langs,cage_root,cache,tl,current,queued_calibrate,report}]}` — `current` = job em execução `{kind:"submission"\|"calibrate"\|"index"\|"unknown_busy",problem_id,…}` ou `null`; `queued_calibrate` = calibrações direcionadas na fila do host |
| `/treino/admin/stats` | GET | `{users,active_sessions,problems:{total,public,private},by_author:[{author,owner,total,public,private}],problems_public_by_day:[{day,count}],logins_per_day,submissions_per_day}` — contagens da plataforma (privados contados, **não listados**); `problems_public_by_day` alimenta o mapa de calor de entrada de públicos (data aproximada; ver `public_at`) |
| `/treino/admin/response-stats` | GET | tempo de resposta + **volume** (cacheado): `{coverage, overall, per_day, by_dow_hour, subs_per_day:[{day,count}], subs_by_dow_hour:[{dow,hour,n}]}`. Tempo só de submissões com `finalized_at`; **volume** conta TODAS as linhas do history. EPOCH/UTC |
| `/treino/admin/calib-activity` | GET | volume de **calibrações** no tempo (cacheado; do log `run/updates/log`): `{calib_per_day:[{day,count}],calib_by_dow_hour:[{dow,hour,n}],total}`. `run/` pode rotacionar → histórico parcial |
| `/treino/admin/logout-user` | POST | `{login}` ou `{logins:[…]}` → remove as sessões (um ou vários) |
| `/treino/admin/lock-user` | POST | `{login}` ou `{logins:[…]}` → **trava** (troca a senha por aleatória) + desloga |
| `/treino/admin/logout-ip` | POST | `{ip}` → encerra todas as sessões daquele IP (IPv4/IPv6) |

## Gestão de problemas (Bearer)
Backend = **Gitea** (store git), mas o autor só usa o **login do MOJ** (sem chave/git — ver
`docs/DEPLOY-GITEA.md`). Listagens leem o índice de donos `contests/treino/var/problem-owners.json`
(gerado por `mojtools/gen-problem-owners.sh`; regen em background, TTL `PROBLEM_OWNERS_TTL_MIN`).
Gitea é a **fonte única**: todo problema tem `owner` (login). Problema sem dono (legado não-migrado)
é **ignorado** no índice; `/mine` = `owner==login` (sem casamento difuso). Não há mais "legado".

> **Controle de acesso — garantido na API, NUNCA só na interface.** Ver o **source/pacote/soluções/
> calibração** de um problema é só p/ **dono ou colaborador** (`require_problem_edit`) — **sem atalho de
> `.admin`**. Ver o **detalhe/statement** (`get`/`validation`) é dono/colaborador **ou** se o problema é
> **público** (`require_problem_view`). Problema **PRIVADO não é nem LISTADO** p/ quem não é dono/colaborador
> (as listagens pré-filtram em `owners_emit`), **inclusive p/ `.admin`** — provas em elaboração não podem
> vazar. Não-autorizado recebe **404** (não revela a existência). Helpers centrais em `lib/problems.sh`;
> `moj-cli`/curl batem na mesma API e não burlam.

| Rota | Método | I/O |
|---|---|---|
| `/problems/mine` | GET | `{problems:[{id,title,author,owner,collections,public,html,claimed}]}` — `claimed=true` se `owner==login`, senão "provável" (nome casa) |
| `/problems/shared` | GET | problemas onde o login é **colaborador** (não dono) |
| `/problems/public` | GET | problemas **públicos** (no treino livre) — visão de gestão (dono/autor) |
| `/problems/collection?name=<c>` | GET | problemas da coleção (curso/diretório, ex.: `obi-problems`) |
| `/problems/collections` | GET | `{collections:[{name,count,public,owner,mine,can_manage}]}` — **coleções = TAGS curadas** (do registro), com contagem visível. Coleção (agrupamento, m:n) ≠ **ORG** (acesso, 1:1 — ver `/orgs/*`) |
| `/problems/collection` | GET `?name` | problemas de uma coleção (filtra pela tag `collections`) |
| `/problems/get?id=<id>` | GET | detalhe: índice + `validation` (relatório do portão) + `statement_html_b64`/`tags`/`time_limits` |
| `/problems/validation?id=<id>` | GET | último relatório de validação `{checks:[{name,ok,detail}],html_built,render_warnings,ok}` |
| `/problems/status` | GET | **painel** dos problemas do login (dono+colaborador; privado de terceiro **não** aparece — `owners_visible`): `{total,counts:{validated,…,needs_recalibration,good_sol_no_tl,public_unvalidated,needs_review,errors},calibrating_ids,attention_ids,problems:[{id,title,owner,author,public,validated,calibrated,being_calibrated,stale,needs_recalibration,good_sol_no_tl,good_sol_missing_langs,public_unvalidated,error,needs_review,review_reasons,time_limits,updated_at}]}`. `good_sol_no_tl` = tem solução good sem TL (linguagem suportada que falhou em TODOS os juízes); `needs_review` = precisa revisão (erro / good sem TL / público não validado ou não calibrado). `stale`/`needs_recalibration` do checksum do índice (≤30 min); **sem hash de pacote por request** |
| `/problems/tl?id=<id>` | GET | time limits **ao vivo** (recomputa o checksum agora) + stale/needs_recalibration exatos: `{problem,checksum,time_limits,calibrated_checksum,hosts,updated_at,calibrated,stale,needs_recalibration}`. Acesso: dono/colaborador **ou** público (`require_problem_view`; **404** senão). Versão não-admin do `/ops/problemtl` |
| `/problems/calib?id=<id>` | GET | calibração por juiz (dono/colaborador): `{id,checksum,good_langs,missing_langs,hosts:[{host,tl,missing,at,log,reports}]}`. `missing_langs` = linguagens good sem TL em **nenhum** host (solução good falhou em TODAS as máquinas); `hosts[].missing` = faltantes naquele juiz |
| `/problems/my-stats` | GET | **análise** dos problemas do login (dono+colaborador) agregada em TODA a plataforma (treino + turmas; cache precomputado). `{totals:{owned,with_activity,attempts,accepts,solvers},overall_verdicts:[{verdict,count}],overall_languages:[{lang,submissions,accepted}],most_popular:{id,title,attempts},problems:[{id,title,attempts,accepts,wrong,acceptance_rate,distinct_users,solvers,contests_count,verdicts,languages,first,last}]}`. Só os problemas do login; **sem logins, sem nomes de contests** (só `contests_count`) — não vaza prova privada |
| `/problems/publish` | POST `{id}` | enfileira **validação + index** (1 juiz pega no heartbeat; portão: HTML compila + seções `## Entrada`/`## Saída` + exemplos + `good` aceita) |
| `/problems/request-calibration` | POST `{id}` | enfileira **calibração** (juiz roda `calibreitor.sh`, gera `tl.<host>`) |

### Autoria (escrita keyless — git escondido, commit autorado pelo login via `git-broker.sh`)
| Rota | Método | I/O |
|---|---|---|
| `/problems/repos` | GET | diretórios do autor (dono/colaborador) `{repos:[{repo,owner,collaborators,collections,mine}]}` |
| `/problems/repo-create` | POST `{repo, collections?}` | cria o **diretório** (repo Gitea no namespace do login; provisiona usuário lazy) |
| `/problems/source?id=<id>` | GET | **source** editável `{editable,title,enunciado_md,enunciado_format,author,tags,conf_text,public,collections,examples,tests,sols{good,slow,wrong,pass,upcoming},score,editorial_md,scripts}` **SÓ dono/colaborador** (`require_problem_edit`); não-autorizado recebe **404** (sem read-only, sem atalho de `.admin`). Cada `examples[i]` traz `explanation` (opcional); `editorial_md` = resolução só p/ setter; `scripts` = caminhos relativos de `scripts/` (correção especial), **só leitura** (não escrito por create/edit; exibido na árvore do pacote) |
| `/problems/preview` | POST `{enunciado_md, enunciado_format?, examples?, title?}` | **pré-visualização** HTML (= o renderizador único `render-statement.sh`, idêntico ao servido) — injeta o **título** (h1) e os exemplos (cada um com `explanation` opcional) → `{html_b64}` |
| `/problems/download?id=<id>` | GET | baixa o **pacote** `.tar.gz` (inclui soluções → exige escrita/admin); stream binário |
| `/problems/upload` | POST `{id\|repo,prob, tar_b64}` | sobe um pacote (`.tar`/`.tar.gz`/`.tar.bz2`/`.tar.zst`/`.zip`) e **substitui tudo** (commit+push) — máquinas sem git / offline |
| `/problems/export?id=<id>` | GET | baixa o problema como **pacote ICPC/Kattis** (2025-09) `.tar.gz` (problem.yaml+statement+data+submissions); inclui soluções → exige escrita/admin (`mojtools/kattis/export.sh`) |
| `/problems/import` | POST `{repo, prob?, tar_b64}` | **importa** um pacote ICPC/Kattis (`mojtools/kattis/import.sh`) → cria um problema MOJ julgável (checker custom via bridge); exige permissão de criação. Round-trip sem perda via `.kattis.json` |

> `source`/`create`/`edit` cobrem o pacote inteiro: `title` (vem do **campo**, não de `% Título`
> no texto — o render injeta o h1), `enunciado_md`, `conf_text` (TL/ulimits/STOPWHEN/…, ver
> `saad-problems/README.org`), `examples` (sample; cada um aceita `explanation` opcional →
> `docs/sample-notes.json`, mostrada após o exemplo), `tests` (ocultos), `sols` por categoria
> `{good,wrong,slow,pass,upcoming}` (cada `[{filename,code}]`), `score` (grupos de pontuação;
> cada grupo tem `{name,weight,glob}` e o `glob` pode ser uma **lista `", "`-separada** de padrões,
> ex.: `g2_*, g3_*`) e
> `editorial_md` (resolução em markdown → `docs/solucao.md`, **só p/ setter**, não vai ao aluno).
| `/problems/create` | POST `{repo,prob,enunciado_md?,author?,tags?,examples?,good_sol?,title?,...}` | cria problema novo; commit+push; `{id,sha}` |
| `/problems/edit` | POST `{id, ...campos}` | edita (só campos presentes); commit+push autorado |
| `/problems/delete` | POST `{id, confirm}` | **REMOVE** o problema (git rm da subpasta + push) e do treino. **Destrutivo**: `confirm` tem de repetir EXATAMENTE o `id`. Dono/colaborador ou admin |
| `/problems/set-public` | POST `{id, public:bool}` | público **on** => **valida + calibra** (`index_problem_bg` no servidor + `cal_request` a um juiz; só entra no treino se o portão passar) e grava `public` no `.moj-meta.json`; **off** => sai do treino na hora. (Antes o `idx_request` legado era no-op → problema saía público sem validar.) |
| `/problems/set-collections` | POST `{id, collections:[...]}` | define as coleções (tags) do problema no `.moj-meta.json`; **valida contra o registro** (curada: a coleção tem de existir) |
| `/problems/move` | POST `{id, to_org}` | move um problema de **rascunho** p/ outra org (muda o id `<org>#<prob>`); **bloqueia se público/em uso** (senão órfãoria o histórico); exige ser membro das DUAS orgs |
| `/problems/repo-collaborators` | GET `?repo` / POST `{repo,add?,remove?}` | **compartilha** o diretório (colaborador Gitea; só o dono gerencia) |
| `/problems/collection-create` | POST `{name}` | cria uma **coleção** (TAG) no registro curado. Nome é **TEXTO LIVRE** (pode ter espaços/acentos — é só rótulo). Exige permissão de criação; criador = dono. (NÃO é org: acesso é por org) |
| `/problems/collection-rename` | POST `{name, to}` | renomeia a coleção (registro + a tag em TODOS os problemas; só dono ou `.admin`) |
| `/problems/collection-delete` | POST `{name}` | exclui a coleção (tira a tag de todos os problemas + remove do registro; só dono ou `.admin`) |

> **Quem pode criar** (problemas/pastas/coleções) = mesma regra de criar contest
> (`cc_can_create`: `.admin` ou allowlist ou ≥ N resolvidos, menos a denylist) — gerida em
> `/treino/admin/contest-perms`. `create`/`repo-create`/`collection-create`/`upload`-novo exigem isso;
> editar/compartilhar problema existente continua por colaborador (`gitea_can_write`).

### Orgs (novo modelo MOJ-nativo, em construção — Fase 1)

Migração em curso: o storage vai de "repo Gitea agrega N problemas" para **repo git local por problema**
(`MOJ_PROBLEMS_DIR/<org>/<prob>`), e o acesso passa a ser por **ORG** (o `<org>` do id `<org>#<prob>`):
quem é **membro** escreve em qualquer problema da org; a org tem uma **trava de público**
(`public_allowed`, privada por PADRÃO → problemas nunca ficam públicos: anti-vazamento de prova), e só
**admin** da org a muda. Cada usuário tem uma org **implícita** `<login>` (sempre privada). Registro:
`contests/treino/var/orgs.json` (`lib/orgs.sh`).

| Rota | Método | Descrição |
|---|---|---|
| `/orgs/list` | GET | orgs de que o login é membro (inclui a **implícita**, criada aqui): `{orgs:[{name,title,members,admins,public_allowed,implicit,count,public,mine,can_manage}]}`. Não lista org alheia |
| `/orgs/get` | GET `?name` | detalhe de 1 org; só membro/admin ou `.admin` global, senão **404** (não vaza existência) |
| `/orgs/create` | POST `{name,members?,admins?,title?,public_allowed?}` | cria org; o criador vira membro+admin (exige `cc_can_create`, a regra de criar contest) |
| `/orgs/members` | GET `?name` / POST `{name,add?,remove?,admins_add?,admins_remove?}` | só admin da org (ou `.admin`) gerencia; criador blindado; org implícita não tem gestão |
| `/orgs/set-public-allowed` | POST `{name,public_allowed:bool}` | liga/desliga a trava (só admin da org; implícita ⇒ **409**). **Desligar DESPUBLICA em cascata** os problemas públicos da org (tira do treino) — resposta traz `unpublished` |
| `/orgs/delete` | POST `{name}` | remove uma org **VAZIA** (sem problemas — conferido em disco); só admin da org (ou `.admin`); org **implícita** ⇒ **409** `implicit_org`; org com problema ⇒ **409** `org_not_empty` |

O CLI **`moj`** (`web/moj`, servido em `GET /moj`; fonte em `moj-cli/`) usa essas rotas para
autoria **sem git/sem chave**: `moj new/clone/push/publish/share/org/mv`. Storage MOJ-nativo: o
servidor commita no repo git LOCAL de cada problema (`MOJ_PROBLEMS_DIR/<org>/<prob>`), sem Gitea.

> Permissão de escrita = **membro da ORG** do problema (`org_is_member`; sem atalho de `.admin`).
> Visibilidade imediata via overlay `contests/treino/var/authored.json` (mesclado ao índice). Público
> só se a org permitir (`public_allowed`) — camada anti-vazamento de prova.

## Submissão (assíncrona)
| Rota | Método | Auth | I/O |
|---|---|---|---|
| `/submit?contest=<c>` | POST | Bearer | body `{problem_id,filename,code_b64,source?}` (`source`=`web`\|`file`) → `{submission_id,status:"queued"}` (não bloqueia). Registra o editor em `var/editor-log` p/ o card "editor da semana". **Gate por fase+papel (forçado pela API)**: `.admin`/`.judge` submetem sempre; `.staff` **nunca** (`403 submit_forbidden`); usuário normal **e `.mon`** só **durante** a janela (`403 contest_not_started` antes do início, `403 contest_ended` após o fim) — o `.mon` submete mas fica **fora do placar**. |
| `/submission/source?contest=<c>&id=<subid>` | GET | Bearer | código-fonte (texto) |
| `/submission/log?contest=<c>&id=<subid>` | GET | Bearer | log do julgamento (texto) |
| `/submission/summary?contest=<c>&ids=<csv>` | GET | Bearer | resumo ESTRUTURADO em lote (p/ a linha "resumo" do treino), de `results/<id>.json`: `{ "<id>":{verdict,verdict_canon,score,score_max,score_kind,correct,total} }`. **Mesmo gate do log** (dono/admin/juiz; respeita `SHOWLOG=0`); ids de terceiros são **omitidos** (não 403). `score_kind` ∈ `tests\|points`. Até 1000 ids; ausentes/antigos saem com campos `null` (degrada p/ o sufixo do veredicto) |

## Contest
| Rota | Auth | I/O |
|---|---|---|
| `/contest/basic?contest=<c>` | — | `{contest_id,contest_name,start_time,end_time,login_start_time,locale,login_enabled,freeze_time,score_anon,languages[]}` (`languages` = whitelist do conf `LANGUAGES=`; `[]` = todas) |
| `/contest/userinfo?contest=<c>` | Bearer | `{login,name, …team/país/univ/show_log opcionais}` |
| `/contest/navbuttons?contest=<c>` | Bearer | botões por papel (`.admin`/`.judge`/`.staff`) |
| `/contest/problems?contest=<c>` | Bearer | `{problems:[{short_name,full_name,problem_id,statement_html_b64,statement_pdf_b64,time_limits,languages}]}` (`problem_id` = forma canônica `coleção#problema`, igual ao treino — é o que o juiz usa p/ achar o pacote; `time_limits` = `{lang:seg}` do store, `{}` se o conf ocultar via `SHOWTL=0`; `languages` = ids permitidos do problema: override por problema → whitelist do contest → `[]` (=todas)). **Gate de visibilidade (forçado pela API)**: `.admin`/`.judge` veem sempre; `.staff` **nunca**; usuário normal **só após o início** — antes disso retorna `{problems:[], locked:"not_started"}` (`.staff` → `locked:"staff"`), e o front mostra a tela de contagem regressiva. |
| `/contest/news` · `/contest/resources` | Bearer | seções opcionais (vazias = ocultar). Notícia pode ter anexo `{file:{name,size}}` |
| `/contest/news-file?contest=<c>&id=<news_id>` | GET | Bearer | baixa o **anexo** da notícia (octet-stream, Content-Disposition) |
| `/contest/backup?contest=<c>` | GET/POST | Bearer | **backup de arquivos do usuário** (versões de solução; não é submissão). GET = lista os próprios `{backups:[{id,name,size,time}]}`; POST `{filename,file_b64}` = guarda; POST `{action:remove,id}` = remove. Guardado em `backups/<login>/<id>`(+`.meta`), máx 10MB. **Toda operação é auditada** (`backup-upload`/`backup-delete` no `var/admin-audit.log`). Se o admin desabilitar (`allow_backup=false` → conf `BACKUP=0`), a API **rejeita** toda operação do usuário (`403 backup_disabled`) e o botão some do menu; o admin ainda recupera os já existentes |
| `/contest/backup-file?contest=<c>&id=<id>[&login=<l>]` | GET | Bearer | baixa um backup (próprio; com `login` só admin baixa de qualquer usuário). **Auditado** (`backup-download owner=…`) |
| `/contest/print?contest=<c>` | GET/POST | Bearer | **pedido de impressão** (existe quando há usuário `.staff`). GET = lista os próprios `{requests:[{id,seq,filename,mime,size,time,status,pages,…}], staff_exists, allow_print}`; POST `{filename,file_b64}` = cria pedido (gera nº `seq` monotônico) → `{id,seq,status:"pending"}`. Aceita PDF/imagem/texto/código, máx 10MB. **Rejeita** se não houver staff (`403 print_unavailable`) ou se o admin desabilitar (`allow_print=false`→conf `PRINT=0`, `403 print_disabled`). **Auditado** (`print-request`) |
| `/contest/print-file?contest=<c>&id=<id>` | GET | Bearer | baixa o arquivo **cru** de um pedido (dono sempre; admin sempre; `.staff` só dentro do seu escopo). **Auditado** (`print-download`) |
| `/contest/staff/queue?contest=<c>` | GET | Bearer (`.staff`/admin) | fila de tarefas do staff (impressão **+ balões**) visíveis a este staff (escopo por regex; admin vê tudo) `{requests:[{id,seq,kind,login,fullname,team,univ,short,color_hex,color_name,filename,mime,…,status,claimed_by,…}]}` (pendentes primeiro). **Ao carregar, reconcilia os balões pendentes** (1 por (time, problema) na 1ª solução — varre o `controle/history` por veredicto `Accepted`, dedup por id determinístico, gera `balloon-task`). `kind` ∈ `print\|balloon` |
| `/contest/staff/print-action?contest=<c>` | POST | Bearer (`.staff`/admin) | `{id,action:claim\|processed\|delivered,mode?}` — máquina de estado sob flock (vale p/ impressão e balão). Escopo-checado (`403 out_of_scope`). **Auditado** com prefixo do kind (`print-*` ou `balloon-claim`/`balloon-processed`/`balloon-delivered`) |
| `/contest/staff/print-pdf?contest=<c>&id=<id>` | GET | Bearer (`.staff`/admin) | gera (build-once, cache) e serve **inline** o PDF. `kind=print` → **folha de rosto** (time/univ/login/seq/páginas/assinatura) + documento A4 (código numerado). `kind=balloon` → **folha do balão** (1 página, sem `.src`): time, universidade, **login**, **problema** (letra), **cor do balão** desenhada + **nome por extenso**, **nº da tarefa** (`seq`), assinatura+hora. Escopo-checado. **Auditado** (`print-served`/`balloon-served`) |
| `/contest/updates?contest=<c>&news_since=&clar_since=` | Bearer | resumo leve p/ polling de notificações: `{news:{last,count,unread}, clar:{last,count,unread}}` (clar = respondidas visíveis ao usuário; `unread` = date/answered_at > since) |
| `/contest/history?contest=<c>` | Bearer | TXT (submissões do usuário). Em placares **binários** (icpc/treino/ausente) o **sufixo de score** do veredicto (`,Np`) é **cortado** na resposta (o competidor não vê quão perto ficou); placares com pontos parciais (`obi`/`heurístico`/`outro`) **mantêm** o score. O history em disco não muda |
| `/contest/balloons?contest=<c>` | Bearer | mapa letra/short→cor (default ICPC A–O) |
| `/contest/regions?contest=<c>` | Bearer | regiões p/ filtro do placar |
| `/contest/teams-meta?contest=<c>` | — | regras regex→{country,school,school_full} `{rules:[…]}` — placar resolve bandeira/escola e filtra por país/escola (bandeiras locais em `/shared/flags/`) |

### Admin do contest (logado como `.admin` daquele contest)
| Rota | Método | I/O |
|---|---|---|
| `/contest/admin/config?contest=<c>` | GET | `{name,mode,start,end,letters[],colors,regions,teams_meta,basic:{locale,login_start,login_enabled,freeze}}` |
| `/contest/admin/config?contest=<c>` | POST | `{colors?,regions?,teams_meta?,basic?}` → grava `balloons.json`/`regions.json`/`teams-meta.json` + vars `basic` no conf (vazio = reseta) |
| `/contest/admin/users?contest=<c>` | GET | `{users:[{login,fullname,email,admin}],shared}` (sem senha) |
| `/contest/admin/user-add?contest=<c>` | POST | `{login,password?,fullname?,email?}` → adiciona/reseta, devolve a credencial |
| `/contest/admin/user-remove?contest=<c>` | POST | `{login}` → remove (não pode remover a si mesmo) |

> Reusa os editores de `web/shared/contest-config/` (os mesmos da criação). Bandeiras **locais/offline** em `/shared/flags/` (271 países + 27 estados); GIFs do Sonic em `/shared/assets/sonic/`. `USERS_FROM=<contest>` no conf faz o login cair no `passwd` compartilhado (ex.: treino), mantendo o `.admin` próprio.
| `/contest/score?contest=<c>` | (Bearer opcional) | **TXT** (1ª linha = modo) — ver `SCOREBOARD.md`. Cache preguiçoso: (re)gera `placar.txt` (público, **com freeze**) e `placar-full.txt` (completo, **sem freeze**) se `history`/`conf` mudou. **Privilegiados** (`.admin`/`.judge` + allowlist `SCORE_FULL_USERS`) com token recebem o completo; demais, o público. |

## Admin / Judge / Ops (Bearer + papel)
| Rota | Método | Papel | Ação |
|---|---|---|---|
| `/contest/allsubmissions?contest=<c>` | GET | admin/chief | TXT 9 campos |
| `/contest/final-verdicts?contest=<c>` | GET/POST | GET=judge; POST=admin/chief | **opções de veredicto manual** (configuráveis). GET → `{verdicts:[labels], options:[{label,verdict}]}`; POST `{options:[{label,verdict}]}` (verdict canônico, sem `:`; o "YES" deve começar com `Accepted` p/ o placar). Default = as 6 (1-YES…6-Contact staff). Auditado (`final-verdicts-set`) |
| `/contest/auto-verdicts?contest=<c>` | GET/POST | GET=judge; POST=admin/chief | **matriz de veredicto automático** `{ "<cid>": { "<lang\|*>": ["<verdict>"] } }` (problema × linguagem × veredicto). GET → `{matrix,problems,verdicts}`; POST `{matrix}` (cids validados; lang minúsculo ou `*`). Auditado (`auto-verdicts-set`) |
| `/contest/review/list?contest=<c>` | GET | judge | fila de revisão manual `{manual, options, items:[{id,login,problem_id,lang,computed_verdict,status,conflict,claimants:[{by,elapsed_s,expires_in_s}],votes_n,my_vote,votes(só chief)}], counts:{not_evaluated,being_evaluated,awaiting_second,conflicts}, my_active}` |
| `/contest/review/claim?contest=<c>` | POST | judge | `{id,action:claim\|extend\|giveup}` — máx 2 avaliadores, **1 ativa por juiz** (`409 already_evaluating`/`slots_full`), TTL 5 min (`extend`=+5). Rejeita quem já votou (`already_voted`). Auditado (`review-claim/extend/giveup`) |
| `/contest/review/vote?contest=<c>` | POST | judge | `{id,label}` — registra o voto (**permanente**) e **libera o juiz** (sai dos avaliadores → pode pegar outra); rejeita voto repetido (`already_voted`). **2 iguais → libera ao aluno** (enfileira `setverdict`, `review-agree`); **2 diferentes → `conflict`** (`review-conflict`) |
| `/contest/review/resolve?contest=<c>` | POST | admin/chief | `{id,verdict}` — o juiz-chefe resolve o conflito; libera ao aluno. Auditado (`review-resolve`) |
| `/contest/review/conflicts?contest=<c>` | GET | admin/chief | sumário dos conflitos `{conflicts:[{id,login,problem_id,lang,sub_epoch,computed_verdict,votes:[{by,label,verdict}]}], n, options}` (`lang`/`sub_epoch` p/ abrir **log + código** na resolução) — `n` alimenta o **alerta global** de conflito (banner + bip) que segue o chief/admin em **qualquer página** (`shared/chief-alert.js`, disparado via `auth.status`) |
| `/contest/review/stats?contest=<c>` | GET | admin/chief | estatística por `.judge` (do `admin-audit.log`) `{judges:[{judge,votes,avg_response_s,timed,agreements,conflicts}], total:{votes,avg_response_s}}` — nº de veredictos, **tempo médio** claim→voto, concordâncias e conflitos; alimenta a aba **Situação** do juiz-chefe |
| `/contest/set-verdict` | POST | judge | `{contest,problem_id,verdict,username}` — override direto (modo legado/auto-resposta); agora **consumido pelo daemon** (`setverdict`) e finalizado pelo escritor único |
| `/contest/rejudge` | POST | admin/chief | `{ids:[…]}` — marca cada submissão como pendente e RE-JULGA (o daemon reconstrói a fonte arquivada + metadados do history) |
| `/admin/adduser` | POST | admin | `{contest,login,fullname,email?,password?}` (gera senha) |
| `/admin/passwd` | POST | admin | `{contest,login,newpass}` |
| `/admin/contest/extend` | POST | admin | `{contest,end_epoch}` |
| `/admin/synctreino` | POST | admin | sincroniza treino |
| `/admin/rejudge` | POST | admin | `{ids:[…]}` ou `{contest,problem}` |
| `/ops/queue` | GET | admin | tamanho da fila por contest |
| `/ops/judges` | GET | admin | status das máquinas de juiz |
| `/ops/problemtl?problem=<p>` | GET | admin | time limits do problema |
| `/ops/updateproblemset` | POST | admin | `{repo}` |
| `/ops/alerts` | GET | **bot** | avalia incidentes (juiz offline+fila, fila grande, daemon caído) com histerese/cooldown e **drena o outbox**: `{items:[{id,text,chats:[<chat_id>…]}]}`. O bot só entrega (+ grupo). Estado em `run/alerts/`; sem cron (o poll do bot é o relógio) |

> As rotas `admin/*` e `ops/*` (exceto `ops/alerts`, que usa **bot-token**) são consumidas pelo painel
> admin e pelo **moj-cli**. O **mojinho-bot** hoje é transporte fino: usa só `treino/signup/*`,
> `treino/recover-password` e `ops/alerts` (todos **bot-token** `mojb_…`), + `/index/status` (público).

## Status do sistema (público)
| Rota | Método | Auth | I/O |
|---|---|---|---|
| `/index/status` | GET | — | health: `{queue:{total_pending,spool_queued,lists[]}, judge:{master_up,busy,machines_online,machines_total,workers_registered}, daemons:{judged,result_sink}}` (cache 20s) — base da página `/status/` |

## Criação de contest (treino)
Permissão: usuários `.admin` sempre podem; demais por **lista do admin OU threshold** de problemas resolvidos no treino (com denylist). O contest entra **no ar imediatamente**. Problemas vêm do banco público (`bank_id`), por ID (`source`+`problem_id`, p/ não-públicos) e/ou com enunciado custom — manualmente ou **sorteados por tag/dificuldade**. Usuários: **compartilhados do treino** (`users_from=treino`; login pela conta do treino, via fallback de `verify_password`) ou **próprios** (`users[]`, senhas geradas se em branco). O **admin do contest é sempre criado** (sufixo `.admin` garantido). Pode-se **criar vazio** (`allow_empty`) e configurar depois.
| Rota | Método | Auth | I/O |
|---|---|---|---|
| `/treino/contest-create/permission` | GET | Bearer | `{can_create,is_admin,reason,solved_count,threshold,in_allow,in_deny,allowed_modes,login,name}` |
| `/treino/contest-create/problems?q=&limit=` | GET | Bearer+criador | **autocomplete** dos problemas que o criador pode usar: públicos **+ os privados a que tem acesso** (dono/colaborador) `{problems:[{id,title,tags,access:mine\|shared\|public,private}],mine,shared,total}`. Privados primeiro; statement vem de `var/jsons-private/`. `/create` recusa problema privado sem acesso (`problem_denied`) e **auto-valida** (enfileira `index`) os privados sem enunciado pronto — o contest mostra o enunciado assim que o juiz indexa (`contest/problems` faz fallback p/ `jsons-private` e cacheia) |
| `/treino/contest-create/tags` | GET | Bearer+criador | tags do banco com contagem `{tags:[{tag,count}],total}` |
| `/treino/contest-create/draw?tags=&count=&match=any\|all&difficulty=any\|easy\|medium\|hard\|known&seed=` | GET | Bearer+criador | sorteia problemas por tag/dificuldade, reproduzível por seed `{problems[],candidates,drawn,seed}` |
| `/treino/contest-create/genpass?n=` | GET | Bearer+criador | N senhas legíveis (palavras-para-senha) `{passwords[]}` |
| `/treino/contest-create/create` | POST | Bearer+criador | `{id?,name,mode,start?,end,languages?,showcode?,allow_empty?, admin:{login?,password?,fullname?}, (users_from? \| users:[{login,password?,fullname?,email?}]), problems:[…], colors?:{A:"RRGGBB",…,enableSonic?}, regions?:[…], teams_meta?:[{regex,country,school?,school_full?}]}` → `{contest_id,admin_login,admin_reused,admin_password,users[],users_from,url,scoreboard_url}` (admin **não** é sobrescrito: senha digitada é respeitada; em modo compartilhado, se o `<login>.admin` já existe na fonte `users_from` ele é **reutilizado** — `admin_reused:true`, `admin_password:null`) |
| `/treino/contest-create/template` | GET | Bearer+criador | baixa template JSON do contest |
| `/treino/contest-create/import` | POST | Bearer+criador | `{tar_b64}` (.tar.gz com `contest.json` + `enunciados/`) → cria |
| `/treino/admin/contest-perms` | GET/POST | admin | lê/define `{threshold,allow[],deny[]}` |
| `/treino/admin/contests` | GET | admin | contests criados pela interface |
| `/treino/admin/contest-remove` | POST | admin | `{contest}` → move p/ lixeira (só os criados pela interface) |

> Ações auditadas (em `treino/var/admin-audit.log`): `contest-create`, `contest-perms`, `contest-remove` — além de `news-*`, `logout-*`, `lock-user`.

## Ambiente de contest (subdomínio + admin do contest)
Acessado por `<id>.moj.<base>` (subdomínio): o nginx injeta `CONTEST_HOST`; a API só serve aquele contest (`auth`/`contest`/`submit`/`submission`) e o frontend redireciona o resto para `/contest/`. Login com gate opcional por substring de User-Agent (`LOGIN_UA_SUBSTRING`, só não-privilegiados). Papéis: `.admin`/`.judge`/`.cjudge` (juiz-chefe, herda juiz)/`.staff`/`.mon`.

| Rota | Método | Papel | I/O |
|---|---|---|---|
| `/contest/admin/sessions?contest=<c>` | GET | admin | sessões ativas + alerta de UA/IP diferentes |
| `/contest/admin/access-log?contest=<c>&day=` | GET | admin | log de acessos (epoch/login/ip/UA) + alertas |
| `/contest/admin/audit-log?contest=<c>&since=&action=&user=&limit=` | GET | admin | **feed unificado** (trace no instante exato de cada evento) `{events:[{time,who,kind,action,details}],count}`. 4 fontes: `admin` (`var/admin-audit.log`), `login` (`var/access.log`), `submit` (1 por submissão, no `sub_epoch` do `controle/history`), `verdict` (1 por correção, no `finalized_at` do `results/<id>.json` — traz o juiz). **Cada submissão gera 2 entradas**: a submissão (quando o aluno enviou) e o veredicto (quando o juiz respondeu); pendente = só a submissão |
| `/contest/admin/dashboard?contest=<c>` | GET | admin | **situação ao vivo**: `{judges:{online,busy,total,queue_depth,assigned}, submissions:{total,pending,pending_list[],max_wait_s,response:{avg_s,max_s,p50_s,p95_s},timeline[]}}` (janela = últimas N submissões) |
| `/contest/admin/settings?contest=<c>` | GET/POST | admin | tempos, login on/off, abertura, **freeze**, locale, toggles `show_code/show_log/show_editor/show_tl/allow_late/score_anon/allow_backup/allow_print/manual_verdict`, `login_ua_substring`, `languages[]` (whitelist do contest), `score_full_users[]` (logins que veem o placar completo além de `.admin`/`.judge`). `manual_verdict` (opt-in, default OFF) liga o **veredicto manual**: o daemon SEGURA o veredicto computado p/ revisão de 2 juízes (exceto o que a matriz `auto-verdicts` libera) |
| `/contest/admin/problems?contest=<c>` | GET/POST | admin | GET inclui `languages` por problema; `{action:add\|remove\|reorder\|rename}` (reescreve PROBS), `{action:langs,letter,languages[]}` (whitelist por problema em `problem-langs.json`) ou `{action:statement,letter, html_b64?\|pdf_b64?\|remove_html?\|remove_pdf?\|refresh?}` (enunciado por problema em `enunciados/<skey>.{html,pdf}`; `refresh` re-indexa do banco) |
| `/contest/statistics?contest=<c>` | GET | admin/judge/mon | totais, por-problema (`first_minute` **relativo** ao início + `first_seconds` p/ desempate), por-linguagem, veredictos, linha do tempo. Tempo = `sub_epoch - CONTEST_START` (não EPOCH). **Só usuários normais** (descarta `.admin/.judge/.staff/.mon`). Cache em `var/statistics.cache.json` (`server/score/stats-gen.sh`), invalidado por `history`/`conf`. |
| `/contest/clarifications?contest=<c>` | GET | Bearer | role-aware (admin/judge/mon = todas; demais = próprias + públicas, **sem `answered_by`**). **O asker (`.login`) NUNCA é exposto** — nem aos juízes (tratamento isonômico; recuperável só pelo admin via auditoria `clarification-ask`). Privilegiado recebe `answer_claim` (reserva) e `is_chief` |
| `/contest/clarification-ask?contest=<c>` | POST | Bearer | `{problem?,question}` |
| `/contest/clarification-claim?contest=<c>` | POST | admin/judge/mon | `{id,action:claim\|release}` — **reserva p/ responder** (dois juízes não pegam a mesma; TTL 5 min, expira na leitura). Auditado (`clar-claim`/`clar-release`) |
| `/contest/clarification-answer?contest=<c>` | POST | admin/judge/mon | `{id,answer,public?}` — sob `flock` + reserva; **já respondida só o juiz-chefe/admin edita** (`409 already_answered`); abertas exigem a reserva (`409 clar_claimed`). Auditado (`edited=`) |
| `/contest/clarification-broadcast?contest=<c>` | POST | admin/judge/mon | **aviso oficial** `{problem?,question,answer}` — Q+A público já respondido, **autor oculto** (`login:""`, `broadcast:true`; UI mostra "Organização"). Auditado |
| `/contest/admin/news?contest=<c>` | POST | admin/judge/mon (**`edit` só admin/chief**) | `{action:add\|remove\|edit,…}` notícias do contest; `add` aceita anexo `{filename,file_b64}` (em `news-files/<id>/`); `edit {id,title,text}` (notícia já enviada). Auditado (`news-add/remove/edit`) |
| `/contest/admin/backups?contest=<c>[&user=&q=]` | GET | admin | lista TODOS os backups (filtra por login/nome) `{backups:[{login,id,name,size,time}],users:[{login,count,bytes}]}` |
| `/contest/admin/backup-zip?contest=<c>&login=<l>` | GET | admin | baixa um **zip** com todos os backups do usuário (nomes originais, prefixados por data) |
| `/contest/admin/staff-filters?contest=<c>` | GET/POST | admin | escopo dos usuários `.staff` por **regex** no login do aluno (sedes distribuídas). GET → `{staff:[{login,fullname,disabled}], filters:{login:[regex]}, regions:[{name,regex}]}` (regions p/ semear). POST `{filters:{login:[regex]}}` (chaves = `.staff` existentes; vazio = vê tudo) → grava `print-requests/staff-filters.json`. **Auditado** (`staff-filters`) |
| `/contest/admin/jplag-run?contest=<c>` | POST | admin | dispara o jplag (background) |
| `/contest/admin/jplag-results?contest=<c>` | GET | admin | `{status, results:[{problem,lang,pairs:[{a,b,similarity}]}]}` |
| `/contest/admin/jplag-match?contest=<c>&run=&i=` | GET | admin | HTML lado-a-lado da comparação |
| `/contest/userinfo?contest=<c>` | GET | Bearer | + `show_editor/show_log/show_code/is_mon/is_chief` |
| `/contest/admin/logout-user?contest=<c>` | POST | admin | `{login}` → encerra sessões do usuário |
| `/contest/admin/user-disable?contest=<c>` | POST | admin | `{login}` → bloqueia (senha `!…`) + desloga (reabilita via user-add) |
| `/contest/admin/users-set-password?contest=<c>` | POST | admin | `{password,include_disabled?}` → senha única p/ todos os não-privilegiados (prova) |
| `/contest/admin/logout-mismatch?contest=<c>` | POST | admin | desloga sessões cujo UA ≠ `LOGIN_UA_SUBSTRING` |

> **Tela única** `/contest/admin/` (hub com sub-abas: Configurações, Problemas, Aparência, Usuários, Log & sessões); `/contest/{admin_tasks,log}/` redirecionam para ela. Placar: `score_anon` no conf → modo anônimo (agregado/quartis, sem nomes); home abre contests pelo subdomínio.
> Auditado em `contests/<c>/var/admin-audit.log`: `settings`, `problems-*`, `clarification-answer`, `clar-claim`, `clar-release`, `clarification-broadcast`, `news-*`, `jplag-run`, `logout-user`, `user-disable`, `users-set-password`, `logout-mismatch`.
