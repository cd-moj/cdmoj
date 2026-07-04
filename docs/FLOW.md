# MOJ — Fluxo de comunicação (API, daemons e cluster de juiz)

Como uma submissão viaja do browser até virar veredicto no placar, e como as
peças conversam entre si. Tudo é **bash + arquivos** (sem DB, sem broker); a
comunicação assíncrona usa **spool de arquivos + `inotifywait`** e, no caminho do
juiz distribuído, **resultado por push** (em vez do polling duplo do sistema antigo).

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

O resultado do juiz carrega, além do `verdict` de display (com o score embutido, ex.
`Accepted,100p`), os campos **estruturados** `verdict_canon` (canônico **sem** score),
`score/score_max/score_kind`, `correct/total_tests` — persistidos em `results/<id>.json` e
servidos pelo `/submission/summary` (linha "resumo" do treino). No **modo veredicto manual**, o
casamento da matriz de auto-veredicto usa o **`verdict_canon`** (não a string com score), e os
**erros de juiz** (`Judge Error`/`No_Servers`) também são **segurados** p/ revisão — o competidor
vê só `Not Answered Yet` até um veredicto sair.

## 3. Gateway de juiz — `server/judge-gw/judge.sh`

Expõe `judge_run <contest> <problemid> <lang> <code_b64> <filename>` → ecoa o veredicto.
Três backends, escolhidos por `$JUDGE_BACKEND`:

- **`mock`** (default em dev) — heurística local, sem juiz; bom para testar a malha.
- **`local`** — compila/roda na própria máquina via `mojtools` (bubblewrap sandbox).
- **`cluster`** — manda o job ao **escalonador** (master) e recebe o veredicto.

### Backend cluster (o caminho de produção)

```
judge.sh (cluster)                    master :27000 (judge/sistema_escalonador)
──────────────────                    ─────────────────────────────────────────
  printf '{"cmd":"run",…}\n' | nc host 27000   ─────▶  enfileira por prioridade
       ◀── {"jobid":"…"}                                 (diretórios 000-super … 080-…)
                                                          despacha p/ um worker livre
  espera o RESULTADO POR PUSH:                            (match por capacidade)
    run/results/<jobid>  aparece  ◀───────────────  worker termina → PUSH do veredicto
       (inotifywait; sem polling)                         p/ o result-sink (:28000)
  fallback: se não houver push em alguns s,
    poll limitado de {"cmd":"getresult",…}
```

Variáveis: `JUDGE_MASTER` (default `localhost:27000`), `JUDGE_PUSH_WAIT` (24h),
`JUDGE_POLL_MAX` (limite do fallback de poll).

## 4. Resultado por push — `server/judge-gw/result-sink.sh`

Serviço systemd **`moj-result-sink`** (porta `RESULT_SINK_PORT`, default **28000**).
Inverte o **double-poll** do sistema antigo (web→master→worker em loop de 0.5s por até
24h): quando o worker termina, ele (ou o master) faz **um** POST do veredicto:

```
{"cmd":"result","jobid":"<id>","verdict":"Accepted,100p"}   →  grava run/results/<jobid>
```

O backend cluster do `judge.sh` está esperando esse arquivo via `inotifywait` e acorda
na hora — **zero polling no caminho feliz**. Transporte: `socat` (primário) / `ncat -k`
/ `nc -l` (fallbacks). Sem broker, sem DB.

## 5. Registro + heartbeat de worker — `server/judge-gw/register.sh`

Substitui a lista `MOJPORTS` hardcoded e o **poll-storm de `islocked`**. Cada worker se
anuncia ao subir e manda heartbeat de estado num registro em arquivo:

```
run/registry/workers   (uma linha por worker, atômico via flock)
  host:port:capability:state:epoch       ex.: pos1:41050:pos:free:1718800000
  state ∈ {free,busy};  linhas com epoch < agora-REG_TTL (30s) = mortas
```

```
worker:        register.sh up   pos1 41050 pos
               register.sh beat pos1 41050 pos free|busy   # heartbeat
               register.sh down pos1 41050
escalonador:   mapfile -t LIVRES < <(register.sh list free)        # free-set vivo
               mapfile -t GPUS   < <(register.sh list free gpu)    # por capacidade
```

A afinidade `contest_servers` vira **match por capacidade** (pos/gpu/cm/hu). É aditivo:
os scripts vivos passam a *chamar* o `register.sh`, sem reescrita.

## 6. Cluster de juiz — `judge/` (máquinas separadas)

- **master / escalonador** (`judge/sistema_escalonador`, porta `:27000` via `tcpserver`):
  fila por **diretórios de prioridade** (`000-super` → `080-lista-publica` + `intermed`),
  atribuição gulosa a workers livres por capacidade. Comandos: `run`, `getresult`,
  `islocked`, `reportmachine`, **`listmachines`** (agrega specs/estado de todos os workers,
  usado pela página de status e pelo painel admin).
- **workers** (`pos`/`gpu`/`cm`/`hu`, portas `:41000-44000`): rodam `mojtools/build-and-test.sh`
  sob `flock`, no sandbox **bubblewrap** (`mojtools/cage-run.sh` + `lang/<lang>/{compile,run}.sh`).

A API fala com o master pelo gateway `handlers/ops/*` e `handlers/treino/admin/judges.sh`
(`listmachines`/`reportmachine`/`islocked` via `nc`), e a página pública `/status/`
(`handlers/index/status.sh`) agrega fila + máquinas + liveness dos daemons.

## 7. Placar — `server/score/build.sh`

Chamado pelo `judged.sh` após cada veredicto. Lê `contests/<c>/conf` (`CONTEST_TYPE`),
gera o placar a partir de `users/*/metrics.json` (uma passada; ver `SCOREBOARD.md`) e grava
`contests/<c>/var/placar.txt` — **1ª linha = modo**
(`icpc`/`obi`/`treino`/`heuristic`/`outro`), as demais já ordenadas.
O front (`web/contest/score/`) busca `GET /contest/score`, despacha pelo modo e renderiza
(com bandeiras locais de `/shared/flags/`, regras `teams-meta`, modo anônimo, etc.).

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
| `moj-judged.service` | daemon que consome o spool e julga |
| `moj-result-sink.service` | recebe o resultado por push do cluster |
| `moj-master.service` | escalonador `:27000` (no host do master) |
| `moj-worker@.service` | worker parametrizado (`@pos1` etc., no host do worker) |
| `moj-bot.service` | mojinho-bot (cliente da API) |

## Resumo do "porquê"

- **Não bloquear a CGI**: submit enfileira e retorna; o front faz polling de HTTP.
- **Push > poll**: o veredicto volta por um POST único ao `result-sink`, eliminando o
  loop de 0.5s/24h do sistema antigo.
- **Registry > MOJPORTS fixo**: workers se anunciam com capacidade e heartbeat.
- **Arquivos > broker**: spool + `inotifywait` + `flock`, fiel ao bash-nativo do MOJ.
