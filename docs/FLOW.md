# MOJ — Fluxo de comunicação (API, daemons e juízes pull)

Como uma submissão viaja do browser até virar veredicto no placar, e como as
peças conversam entre si. Tudo é **bash + arquivos** (sem DB, sem broker); a
comunicação assíncrona usa **spool de arquivos + `inotifywait`** e, no julgamento,
o modelo **pull** (os juízes puxam o job no heartbeat — sem master, sem push de entrada).

## Visão geral

```
  Browser (web/)                      API (server/api/v1, via nginx+fcgiwrap)
  ──────────────                      ─────────────────────────────────────
   POST /api/v1/submit  ───────────▶  handlers/submit.sh
                                        1. valida + gera id (md5)
                                        2. escreve JSON no SPOOL  ───────────┐
                                        3. grava linha provisória            │
                                           "Not Answered Yet" no history     │
                                        4. responde {submission_id,queued}    │
   (front faz polling de /contest/history até sair de "Not Answered Yet")     │
                                                                              ▼
                                                       run/spool/submissions/<arquivo>
                                                                              │ inotifywait (push)
                                                                              ▼
  server/daemons/judged.sh  (consumidor do spool, systemd: moj-judged)
    para cada arquivo novo:
      1. lê o JSON {contest,login,problem_id,code_b64,lang,...}
      2. verdict = judge_run(...)   ──────────────▶  server/judge-gw/judge.sh
      3. troca a linha "Not Answered Yet :<id>" pelo veredicto real (mv atômico)
      4. recomputa users/<login>/metrics.json (fonte do placar)
      5. arquiva o fonte em users/<login>/submissions/<id>.<ext>
      6. roda server/score/build.sh <c>  ──▶  reescreve var/placar.txt
      7. move o arquivo de spool p/ run/spool/submissions-done/
                                                              │
   Placar:  GET /api/v1/contest/score  ◀── lê var/placar.txt (1ª linha = modo)
```

O ponto-chave: **a CGI nunca bloqueia**. `submit.sh` enfileira e retorna na hora; o
`judged.sh` é o único que fala com o juiz. O front descobre o veredicto por polling
do `history` (HTTP), não segurando a conexão.

## 1. API → spool (enfileiramento)

`handlers/submit.sh` (e `handlers/contest/rejudge.sh`, `set-verdict.sh`) escrevem um
arquivo no **spool** `run/spool/submissions/`. O **nome** carrega o roteamento e o
**conteúdo** é o JSON com os dados:

```
nome:   <contest>:<epoch>:<id>:<login>:<comando>:<arg>[:<FILETYPE>]
comando ∈ { submit, rejulgar, setverdict, synctreino, newcontest, … }

submit:     <c>:<ts>:<id>:<login>:submit:<problemid>:<LANG>
rejulgar:   <c>:<ts>:<id>:<login>:rejulgar:<subid>
setverdict: <c>:<ts>:<id>:<login>:setverdict:<problemid>
```

Conteúdo (submit): `{contest,login,problem_id,filename,code_b64,lang,time,id}`.
A escrita é **atômica** (`.in.<id>` → `mv`), então o daemon só vê o arquivo pronto.

Logo após enfileirar, `submit.sh` anexa ao `contests/<c>/users/<login>/history` uma linha
provisória terminada em `:<id>` com veredicto `Not Answered Yet` (e recomputa o
`metrics.json` do usuário, p/ o PENDING aparecer no placar) — é o que o front
mostra como "julgando" enquanto faz polling.

**Formato do history por-usuário (6 campos, login implícito no diretório):**
`tempo:problemid:lang:verdict:epoch:subid`. Os leitores agregados usam
`emit_user_history`/`emit_history_stream` (lib/users.sh), que reinjetam o login e
entregam o formato global de 7 campos `tempo:login:problemid:lang:verdict:epoch:subid`.

## 2. Daemon de julgamento — `server/daemons/judged.sh`

Serviço systemd **`moj-judged`**. Observa o spool com `inotifywait -m -e create -e moved_to`
(fallback: poll de 1s). Para cada arquivo: lê o JSON, chama `judge_run`, e aplica o
veredicto reescrevendo **só a linha com sufixo `:<id>`** no `history` do usuário (casamento
seguro, reescrita atômica via `mv`), recomputa `users/<login>/metrics.json`, arquiva o fonte
decodificado, e dispara `server/score/build.sh <contest>` para recalcular o placar. Por fim
move o arquivo para `run/spool/submissions-done/`.

No modo **fila/pull** (`INTAKE_MODE=queue`, ver `server/judge-gw/PULL.md`), em vez de julgar
na hora o daemon **enfileira** um job JSON `{id,contest,problem_id,login,lang,filename,
code_b64,priority,enqueued_at,allowed_hosts?}` na banda do `CONTEST_PRIORITY`; um juiz o
reivindica no heartbeat. `allowed_hosts` é o **pool de juízes** efetivo (override do problema
em `problem-judges.json` → `CONTEST_JUDGES` do conf; ausente = qualquer juiz) — o claim é
**estrito**: com o pool offline o job espera na fila (preflight/dashboard avisam).

O resultado do juiz carrega, além do `verdict` de display (com o score embutido, ex.
`Accepted,100p`), os campos **estruturados** `verdict_canon` (canônico **sem** score),
`score/score_max/score_kind`, `correct/total_tests` e **`groups`** (subtarefas
`[{earned,max},…]`, quando o problema pontua por grupos) — persistidos em `results/<id>.json`
e servidos pelo `/submission/summary`. **Ao competidor o veredicto servido é SEMPRE o
canônico** (todos os modos; `lib/verdict.sh` canoniza os endpoints de history na leitura — o
history em disco não muda) e o summary é **redigido por modo**: treino/lista = tudo;
obi/heurístico/outro = score/grupos/heur; icpc/ausente = só o canônico. No **modo veredicto manual**, o
casamento da matriz de auto-veredicto usa o **`verdict_canon`** (não a string com score), e os
**erros de juiz** (`Judge Error`/`No_Servers`) também são **segurados** p/ revisão — o competidor
vê só `Not Answered Yet` até um veredicto sair.

## 3. Gateway de juiz — `server/judge-gw/judge.sh` (dev/legado)

Expõe `judge_run <contest> <problemid> <lang> <code_b64> <filename>` → ecoa o veredicto.
**Não é usado no modo pull de produção** (lá o daemon enfileira antes de chamar `judge_run`
— ver §2 e `PULL.md`). Fica p/ dev e p/ o intake legado (`INTAKE_MODE=legacy`), com dois
backends por `$JUDGE_BACKEND`:

- **`mock`** (default em dev) — heurística local, sem juiz; bom para testar a malha assíncrona.
- **`local`** — compila/roda na própria máquina via `mojtools` (bubblewrap sandbox).

## 4. Julgamento pull — os juízes puxam o job

Em produção (`INTAKE_MODE=queue JUDGE_BACKEND=queue`) o julgamento é **pull**, e o lado
servidor é a biblioteca `server/judge-gw/sched-lib.sh` + os handlers `handlers/judge/*`. Não
há master, worker nem porta de entrada p/ os juízes:

```
daemon enfileira ─▶ run/queue/<banda>/<id>.json        (bandas 000-super … 080-…)
juiz (repo judge/, agente moj-agent@)
   POST /judge/heartbeat  ─▶ reivindica um job (claim atômico flock+mv → run/assigned/<host>/)
   GET  /judge/package     ─▶ baixa o pacote sob demanda p/ o cache local (calibra na 1ª vez)
   ...julga (mojtools/build-and-test.sh, sandbox bwrap)...
   POST /judge/result      ─▶ sched-lib grava run/results/<id>.json (o daemon consome via consumer)
   POST /judge/tl-report   ─▶ reporta o TL calibrado (run/tl/<id>.json)
```

`allowed_hosts` (pool de juízes do problema/contest) é respeitado no claim: com o pool
offline o job **espera na fila** (o preflight/dashboard avisam). Protocolo completo em
`server/judge-gw/PULL.md`.

## 5. Registro + heartbeat — `sched-lib.sh` + `handlers/judge/*`

Cada juiz se registra (`POST /judge/register`) e manda heartbeat (`POST /judge/heartbeat`),
gravando um registro JSON por host:

```
run/registry/<host>.json     (cpu, langs, slots, last_seen; vivo = last_seen recente)
  last_seen < agora-REG_TTL (30s) = juiz morto (sai do free-set)
```

O escalonador in-daemon (`sched-lib.sh`) casa job×juiz por **capacidade** e por
`allowed_hosts`, com claim atômico (`flock`+`mv` p/ `run/assigned/`); job reivindicado sem
novo beat em `ASSIGN_TTL` (120s) volta p/ a fila.

## 6. Juízes — `judge/` (máquinas separadas, modelo pull)

Uma máquina de juiz clona só `judge/` + `mojtools/` (não o `cdmoj`) e sobe o agente
`moj-agent@<cap>` (`pos`/`gpu`/`cm`/`hu`). O agente: registra a capacidade, puxa job no
heartbeat, baixa o pacote sob demanda p/ um **cache local**, calibra na 1ª vez e **reporta o
TL**, e roda a solução em sandbox **bubblewrap** (`mojtools/cage-run.sh` +
`lang/<lang>/{compile,run}.sh`, tipicamente sobre um rootfs `moj-sysroot`). Ver `judge/README.md`.

A API expõe o estado dos juízes por `handlers/treino/admin/judges.sh` (painel admin, `model:"pull"`)
e a página pública `/status/` (`handlers/index/status.sh`) agrega fila + juízes + liveness do daemon.

## 7. Placar — `server/score/build.sh`

Chamado pelo `judged.sh` após cada veredicto. Lê `contests/<c>/conf` (`CONTEST_TYPE`),
gera o placar a partir de `users/*/metrics.json` (uma passada; ver `SCOREBOARD.md`) e grava
`contests/<c>/var/placar.txt` — **1ª linha = modo**
(`icpc`/`obi`/`treino`/`heuristic`/`outro`), as demais já ordenadas.
O front (`web/contest/score/`) busca `GET /contest/score`, despacha pelo modo e renderiza
(com bandeiras locais de `/shared/flags/`, regras `teams-meta`, modo anônimo, etc.).

## 7½. Submissão OFFLINE de contest (moj-comp, rota emergencial)

Caiu a Internet na sala? A CLI do competidor (`moj-comp`) empacota a submissão **cifrada com a
hora UTC corrente** e reenvia quando a rede volta — e ela **conta no horário do carimbo**
(penalidade justa). O tempo é cercado por dois lados:

- **Piso**: o pacote embute o último **beacon** (carimbo `{c,l,t,n}` assinado RSA-PSS com a
  chave do contest, renovado a cada comando com rede — `GET /contest/beacon`). O pacote
  provadamente nasceu **depois** de `beacon.t`.
- **Teto**: a chegada. O servidor exige `beacon.t ≤ claimed ≤ now+30s`, claimed dentro da
  janela DO aluno (extend por sede conta) e monotonicidade entre pacotes aceitos.

O pacote é híbrido RSA-OAEP(+sha do conteúdo no envelope — integridade)/AES-256-CBC; a
privada vive em `contests/<c>/secrets/` e nunca sai. A CLI mede o desvio do relógio local
contra `server_utc` a cada contato (funciona sem root) e carimba com a hora corrigida.
Pacote aceito entra no MESMO spool da seção 1 com `time=claimed` + `offline:true`; o
organizador enxerga tudo em `var/offline-log` e no audit (`offline-submit`, com os gaps
beacon→claimed→chegada). Lib: `server/api/v1/lib/contest-offline.sh`; rotas em API.md.

## 8. Outros caminhos pelo mesmo spool

O mesmo mecanismo (API → spool → daemon) serve comandos administrativos vindos da web
**e do mojinho-bot** (cliente da API): `synctreino`, `newcontest`, `adduser`, `passwd`,
`alteravigenciacontest`, `rejulgar`. O `jplag` roda à parte: `handlers/contest/admin/jplag-run.sh`
dispara `server/score/jplag-run.sh` em background, que junta as soluções aceitas, roda o jar
e grava os pares de similaridade em `contests/<c>/jplag/`.

## Serviços systemd (`server/etc/systemd/`)

| Unit | Papel |
|---|---|
| `moj-fcgiwrap.socket`/`.service` | socket + fcgiwrap que roda o `router.sh` (a API) |
| `moj-judged.service` | daemon que consome o spool e enfileira p/ o pull |
| `moj-agent@.service` | agente do juiz (repo `judge/`, nas máquinas de julgamento; `@pos`/`@gpu`/…) |
| `moj-bot.service` | mojinho-bot (cliente da API) |
| `moj-contest-backup@.service`/`.timer` | snapshot rotacionado do contest `%i` a cada 5 min durante a prova (`server/bin/contest-backup.sh`: tar de `contests/<c>/` + spool pendente; ligar o timer no dia) |

## Resumo do "porquê"

- **Não bloquear a CGI**: submit enfileira e retorna; o front faz polling de HTTP.
- **Julgamento pull**: o juiz puxa o job no heartbeat e reporta por HTTP; sem porta de entrada
  p/ os juízes (o servidor nunca conecta no juiz).
- **Registry vivo**: cada juiz se anuncia com capacidade + heartbeat (`run/registry/<host>.json`).
- **Arquivos > broker**: spool + `inotifywait` + `flock`, fiel ao bash-nativo do MOJ.
