# MOJ — API v1 (referência)

Base: `/api/v1`. Roteador único: `server/api/v1/router.sh` → `handlers/<rota>.sh`.
Auth: `Authorization: Bearer <token>`. Respostas JSON com envelope `{success:true, …}` ou
`{success:false, error:{message,code}}` + status HTTP correto. Histórico e placar são **TXT** cru.
Horários em **EPOCH**. IDs validados contra path-traversal.

## Auth
| Rota | Método | Auth | I/O |
|---|---|---|---|
| `/auth/login?contest=<c>` | POST | — | body `{username,password}` → `{token,logged_in,username,name,contest}` |
| `/auth/status?contest=<c>` | GET | Bearer | `{logged_in,login,name,contest,is_admin,is_judge,is_staff}` |
| `/auth/logout` | POST | Bearer | `{logged_out:true}` |

## Index (home)
| Rota | I/O |
|---|---|
| `/index/news` | `{news:[{id,title,date,summary,url}]}` |
| `/index/contests?page=N` | `{open:[…],upcoming:[…],closed:{items:[…],page,per_page,total}}` (cada item `{id,title,start_time,end_time,problems_count,url,scoreboard_url}`). Encerrados paginados (20/pág); **`?all=1`** devolve todos (usado pela página de arquivo `/contests/`). |
| `/index/open_training` | `{top_users:[{username,name,solved_count}],recent_solved:[{problem_id,problem_title,user,solved_at,url}],most_solved_week:[…],most_solved_prev_week:[{problem_id,problem_title,solved_count,url}]}` (`prev_week` = resolvedores distintos por problema na semana passada) |

## Treino
| Rota | Auth | I/O |
|---|---|---|
| `/treino/problems` | — | array `[{id,title,tags,solved_count,attempted_count}]` (contagens de `var/json-count/<arquivo>` casadas por nome de arquivo; cache 5 min em `var/problems.json`) |
| `/treino/problem?id=<id>` | — | `{id,title,statement_html_b64,time_limits,tags}` |
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

## Treino — painel admin (`.admin`, Bearer)
Acesso registra **IP** (`X-Forwarded-For`/`REMOTE_ADDR`) e **User-Agent** na sessão e em `var/access.log`.

| Rota | Método | Ação |
|---|---|---|
| `/treino/admin/sessions` | GET | sessões ativas `{count,sessions:[{login,name,ip,user_agent,login_at}]}` |
| `/treino/admin/access-log?day=YYYY-MM-DD` | GET | log de acessos (filtra por dia) |
| `/treino/admin/queue` | GET | pendentes por lista `{total_pending,spool_queued,lists:[{contest,name,pending}]}` |
| `/treino/admin/judges` | GET | estado do juiz via `:27000` `{online,busy,master,configured_workers,configured_count}` |
| `/treino/admin/stats` | GET | `{users,active_sessions,logins_per_day,submissions_per_day}` |
| `/treino/admin/logout-user` | POST | `{login}` ou `{logins:[…]}` → remove as sessões (um ou vários) |
| `/treino/admin/lock-user` | POST | `{login}` ou `{logins:[…]}` → **trava** (troca a senha por aleatória) + desloga |
| `/treino/admin/logout-ip` | POST | `{ip}` → encerra todas as sessões daquele IP (IPv4/IPv6) |

## Gestão de problemas (Bearer)
Backend = **Gitea** (store git), mas o autor só usa o **login do MOJ** (sem chave/git — ver
`docs/DEPLOY-GITEA.md`). Listagens leem o índice de donos `contests/treino/var/problem-owners.json`
(gerado por `mojtools/gen-problem-owners.sh`; regen em background, TTL `PROBLEM_OWNERS_TTL_MIN`).
Pré-migração `owner` é `null` e `author` é texto livre — `/mine` faz casamento difuso pelo nome.

| Rota | Método | I/O |
|---|---|---|
| `/problems/mine` | GET | `{problems:[{id,title,author,owner,collections,public,html,claimed}]}` — `claimed=true` se `owner==login`, senão "provável" (nome casa) |
| `/problems/shared` | GET | problemas onde o login é **colaborador** (não dono) |
| `/problems/public` | GET | problemas **públicos** (no treino livre) — visão de gestão (dono/autor) |
| `/problems/collection?name=<c>` | GET | problemas da coleção (curso/diretório, ex.: `obi-problems`) |
| `/problems/collections` | GET | `{collections:[{name,count,public}]}` — coleções com contagem total/pública |
| `/problems/get?id=<id>` | GET | detalhe: índice + `validation` (relatório do portão) + `statement_html_b64`/`tags`/`time_limits` |
| `/problems/validation?id=<id>` | GET | último relatório de validação `{checks:[{name,ok,detail}],html_built,render_warnings,ok}` |
| `/problems/publish` | POST `{id}` | enfileira **validação + index** (1 juiz pega no heartbeat; portão: HTML compila + exemplos + `good` aceita) |
| `/problems/request-calibration` | POST `{id}` | enfileira **calibração** (juiz roda `calibreitor.sh`, gera `tl.<host>`) |

### Autoria (escrita keyless — git escondido, commit autorado pelo login via `git-broker.sh`)
| Rota | Método | I/O |
|---|---|---|
| `/problems/repos` | GET | diretórios do autor (dono/colaborador) `{repos:[{repo,owner,collaborators,collections,mine}]}` |
| `/problems/repo-create` | POST `{repo, collections?}` | cria o **diretório** (repo Gitea no namespace do login; provisiona usuário lazy) |
| `/problems/source?id=<id>` | GET | **source** editável `{editable,enunciado_md,author,tags,conf_text,public,collections,examples,tests,sols.good}` (Gitea=editável; legado=read-only) |
| `/problems/preview` | POST `{enunciado_md, examples?}` | **pré-visualização** HTML do enunciado — mesmo pandoc do build (`-f markdown --mathml -s`, injeta exemplos) → `{html_b64}` |
| `/problems/download?id=<id>` | GET | baixa o **pacote** `.tar.gz` (inclui soluções → exige escrita/admin); stream binário |
| `/problems/upload` | POST `{id\|repo,prob, tar_b64}` | sobe um pacote (`.tar`/`.tar.gz`/`.tar.bz2`/`.tar.zst`/`.zip`) e **substitui tudo** (commit+push) — máquinas sem git / offline |

> `source`/`create`/`edit` cobrem o pacote inteiro: `enunciado_md`, `conf_text` (TL/ulimits/
> STOPWHEN/…, ver `saad-problems/README.org`), `examples` (sample), `tests` (ocultos) e `sols`
> por categoria `{good,wrong,slow,pass,upcoming}` (cada `[{filename,code}]`).
| `/problems/create` | POST `{repo,prob,enunciado_md?,author?,tags?,examples?,good_sol?,title?,...}` | cria problema novo; commit+push; `{id,sha}` |
| `/problems/edit` | POST `{id, ...campos}` | edita (só campos presentes); commit+push autorado |
| `/problems/set-public` | POST `{id, public:bool}` | marca público no `.moj-meta.json` (+ enfileira validação se `true`) |
| `/problems/set-collections` | POST `{id, collections:[...]}` | define coleções no `.moj-meta.json` |
| `/problems/repo-collaborators` | GET `?repo` / POST `{repo,add?,remove?}` | **compartilha** o diretório (colaborador Gitea; só o dono gerencia) |
| `/problems/collection-create` | POST `{name, members?, admins?, title?}` | cria uma **coleção** (competição/curso) com **setters** e co-**admins** (exige permissão de criação) |
| `/problems/collection-members` | GET `?name` / POST `{name,add?,remove?,admins_add?,admins_remove?}` | dono **ou co-admin** gerencia setters E admins; propaga acesso aos repos com problema na coleção |

> **Quem pode criar** (problemas/pastas/coleções) = mesma regra de criar contest
> (`cc_can_create`: `.admin` ou allowlist ou ≥ N resolvidos, menos a denylist) — gerida em
> `/treino/admin/contest-perms`. `create`/`repo-create`/`collection-create`/`upload`-novo exigem isso;
> editar/compartilhar problema existente continua por colaborador (`gitea_can_write`).
| `/problems/git-credential` | POST `{repo}` | credencial HTTPS efêmera p/ o **modo git** do CLI (`{url,username,token}`); só quem pode escrever; não persistir |
| `/problems/webhook` | POST | **Gitea → MOJ** (sem Bearer; HMAC `X-Gitea-Signature`). Em cada push, enfileira `index` dos problemas alterados e registra o diretório. Webhook criado automático no `repo-create`/migração; URL em `MOJ_WEBHOOK_URL` |

O CLI **`moj`** (`web/moj`, servido em `GET /moj`; fonte em `moj-cli/`) usa essas rotas para
autoria **sem git/sem chave**: `moj new/clone/push/publish/share`. `git-credential` é só p/ o modo
git avançado.

> Permissão de escrita = dono **ou** colaborador no Gitea (`gitea_can_write`). Visibilidade imediata
> via overlay `contests/treino/var/authored.json` (mesclado ao índice). Segredos só server-side
> (modo 600); nada de chave SSH/git para o autor.

## Submissão (assíncrona)
| Rota | Método | Auth | I/O |
|---|---|---|---|
| `/submit?contest=<c>` | POST | Bearer | body `{problem_id,filename,code_b64}` → `{submission_id,status:"queued"}` (não bloqueia) |
| `/submission/source?contest=<c>&id=<subid>` | GET | Bearer | código-fonte (texto) |
| `/submission/log?contest=<c>&id=<subid>` | GET | Bearer | log do julgamento (texto) |

## Contest
| Rota | Auth | I/O |
|---|---|---|
| `/contest/basic?contest=<c>` | — | `{contest_id,contest_name,start_time,end_time,login_start_time,locale}` |
| `/contest/userinfo?contest=<c>` | Bearer | `{login,name, …team/país/univ/show_log opcionais}` |
| `/contest/navbuttons?contest=<c>` | Bearer | botões por papel (`.admin`/`.judge`/`.staff`) |
| `/contest/problems?contest=<c>` | Bearer | `{problems:[{short_name,full_name,problem_id,statement_html_b64,statement_pdf_b64,time_limits}]}` |
| `/contest/news` · `/contest/resources` | Bearer | seções opcionais (vazias = ocultar) |
| `/contest/history?contest=<c>` | Bearer | TXT (submissões do usuário) |
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
| `/contest/score?contest=<c>` | — | **TXT** (1ª linha = modo) — ver `SCOREBOARD.md`. Cache preguiçoso: (re)gera `placar.txt` se a fonte (`history`/`conf`) mudou ou se nunca foi montado (cobre contests importados). |

## Admin / Judge / Ops (Bearer + papel)
| Rota | Método | Papel | Ação |
|---|---|---|---|
| `/contest/allsubmissions?contest=<c>` | GET | admin | TXT 9 campos |
| `/contest/final-verdicts?contest=<c>` | GET | judge | lista de veredictos finais |
| `/contest/set-verdict` | POST | judge | `{contest,problem_id,verdict,username}` |
| `/contest/rejudge` | POST | admin | `{ids:[…]}` |
| `/admin/adduser` | POST | admin | `{contest,login,fullname,email?,password?}` (gera senha) |
| `/admin/passwd` | POST | admin | `{contest,login,newpass}` |
| `/admin/contest/extend` | POST | admin | `{contest,end_epoch}` |
| `/admin/synctreino` | POST | admin | sincroniza treino |
| `/admin/rejudge` | POST | admin | `{ids:[…]}` ou `{contest,problem}` |
| `/ops/queue` | GET | admin | tamanho da fila por contest |
| `/ops/judges` | GET | admin | status das máquinas de juiz |
| `/ops/problemtl?problem=<p>` | GET | admin | time limits do problema |
| `/ops/updateproblemset` | POST | admin | `{repo}` |

> As rotas `admin/*` e `ops/*` são consumidas também pelo **mojinho-bot** (cliente da API).

## Status do sistema (público)
| Rota | Método | Auth | I/O |
|---|---|---|---|
| `/index/status` | GET | — | health: `{queue:{total_pending,spool_queued,lists[]}, judge:{master_up,busy,machines_online,machines_total,workers_registered}, daemons:{judged,result_sink}}` (cache 20s) — base da página `/status/` |

## Criação de contest (treino)
Permissão: usuários `.admin` sempre podem; demais por **lista do admin OU threshold** de problemas resolvidos no treino (com denylist). O contest entra **no ar imediatamente**. Problemas vêm do banco público (`bank_id`), por ID (`source`+`problem_id`, p/ não-públicos) e/ou com enunciado custom — manualmente ou **sorteados por tag/dificuldade**. Usuários: **compartilhados do treino** (`users_from=treino`; login pela conta do treino, via fallback de `verify_password`) ou **próprios** (`users[]`, senhas geradas se em branco). O **admin do contest é sempre criado** (sufixo `.admin` garantido). Pode-se **criar vazio** (`allow_empty`) e configurar depois.
| Rota | Método | Auth | I/O |
|---|---|---|---|
| `/treino/contest-create/permission` | GET | Bearer | `{can_create,is_admin,reason,solved_count,threshold,in_allow,in_deny,allowed_modes,login,name}` |
| `/treino/contest-create/problems?q=&limit=` | GET | Bearer+criador | **autocomplete** dos problemas que o criador pode usar: públicos **+ os privados a que tem acesso** (dono/colaborador) `{problems:[{id,title,tags,access:mine\|shared\|public,private}],mine,shared,total}`. Privados primeiro; statement vem de `var/jsons-private/`. `/create` recusa problema privado sem acesso (`problem_denied`) |
| `/treino/contest-create/tags` | GET | Bearer+criador | tags do banco com contagem `{tags:[{tag,count}],total}` |
| `/treino/contest-create/draw?tags=&count=&match=any\|all&difficulty=any\|easy\|medium\|hard\|known&seed=` | GET | Bearer+criador | sorteia problemas por tag/dificuldade, reproduzível por seed `{problems[],candidates,drawn,seed}` |
| `/treino/contest-create/genpass?n=` | GET | Bearer+criador | N senhas legíveis (palavras-para-senha) `{passwords[]}` |
| `/treino/contest-create/create` | POST | Bearer+criador | `{id?,name,mode,start?,end,languages?,showcode?,allow_empty?, admin:{login?,password?,fullname?}, (users_from? \| users:[{login,password?,fullname?,email?}]), problems:[…], colors?:{A:"RRGGBB",…,enableSonic?}, regions?:[…], teams_meta?:[{regex,country,school?,school_full?}]}` → `{contest_id,admin_login,admin_password,users[],users_from,url,scoreboard_url}` |
| `/treino/contest-create/template` | GET | Bearer+criador | baixa template JSON do contest |
| `/treino/contest-create/import` | POST | Bearer+criador | `{tar_b64}` (.tar.gz com `contest.json` + `enunciados/`) → cria |
| `/treino/admin/contest-perms` | GET/POST | admin | lê/define `{threshold,allow[],deny[]}` |
| `/treino/admin/contests` | GET | admin | contests criados pela interface |
| `/treino/admin/contest-remove` | POST | admin | `{contest}` → move p/ lixeira (só os criados pela interface) |

> Ações auditadas (em `treino/var/admin-audit.log`): `contest-create`, `contest-perms`, `contest-remove` — além de `news-*`, `logout-*`, `lock-user`.

## Ambiente de contest (subdomínio + admin do contest)
Acessado por `<id>.moj.<base>` (subdomínio): o nginx injeta `CONTEST_HOST`; a API só serve aquele contest (`auth`/`contest`/`submit`/`submission`) e o frontend redireciona o resto para `/contest/`. Login com gate opcional por substring de User-Agent (`LOGIN_UA_SUBSTRING`, só não-privilegiados). Papéis: `.admin`/`.judge`/`.staff`/`.mon`.

| Rota | Método | Papel | I/O |
|---|---|---|---|
| `/contest/admin/sessions?contest=<c>` | GET | admin | sessões ativas + alerta de UA/IP diferentes |
| `/contest/admin/access-log?contest=<c>&day=` | GET | admin | log de acessos (epoch/login/ip/UA) + alertas |
| `/contest/admin/settings?contest=<c>` | GET/POST | admin | tempos, login on/off, abertura, freeze, locale, toggles `show_code/show_log/show_editor/allow_late/score_anon`, `login_ua_substring` |
| `/contest/admin/problems?contest=<c>` | GET/POST | admin | `{action:add\|remove\|reorder\|rename,…}` (reescreve PROBS) |
| `/contest/statistics?contest=<c>` | GET | admin/judge/mon | totais, por-problema (letra/nome resolvidos do conf), por-linguagem, veredictos, linha do tempo. **Só usuários normais** (descarta `.admin/.judge/.staff/.mon`). Cache preguiçoso em `var/statistics.cache.json` (gerado por `server/score/stats-gen.sh`), invalidado por `history`/`conf`. |
| `/contest/clarifications?contest=<c>` | GET | Bearer | role-aware (admin/judge/mon = todas; demais = próprias + públicas) |
| `/contest/clarification-ask?contest=<c>` | POST | Bearer | `{problem?,question}` |
| `/contest/clarification-answer?contest=<c>` | POST | admin/judge/mon | `{id,answer,public?}` |
| `/contest/admin/news?contest=<c>` | POST | admin/judge/mon | `{action:add\|remove,…}` notícias do contest |
| `/contest/admin/jplag-run?contest=<c>` | POST | admin | dispara o jplag (background) |
| `/contest/admin/jplag-results?contest=<c>` | GET | admin | `{status, results:[{problem,lang,pairs:[{a,b,similarity}]}]}` |
| `/contest/admin/jplag-match?contest=<c>&run=&i=` | GET | admin | HTML lado-a-lado da comparação |
| `/contest/userinfo?contest=<c>` | GET | Bearer | + `show_editor/show_log/show_code/is_mon` |
| `/contest/admin/logout-user?contest=<c>` | POST | admin | `{login}` → encerra sessões do usuário |
| `/contest/admin/user-disable?contest=<c>` | POST | admin | `{login}` → bloqueia (senha `!…`) + desloga (reabilita via user-add) |
| `/contest/admin/users-set-password?contest=<c>` | POST | admin | `{password,include_disabled?}` → senha única p/ todos os não-privilegiados (prova) |
| `/contest/admin/logout-mismatch?contest=<c>` | POST | admin | desloga sessões cujo UA ≠ `LOGIN_UA_SUBSTRING` |

> **Tela única** `/contest/admin/` (hub com sub-abas: Configurações, Problemas, Aparência, Usuários, Log & sessões); `/contest/{admin_tasks,log}/` redirecionam para ela. Placar: `score_anon` no conf → modo anônimo (agregado/quartis, sem nomes); home abre contests pelo subdomínio.
> Auditado em `contests/<c>/var/admin-audit.log`: `settings`, `problems-*`, `clarification-answer`, `news-*`, `jplag-run`, `logout-user`, `user-disable`, `users-set-password`, `logout-mismatch`.
