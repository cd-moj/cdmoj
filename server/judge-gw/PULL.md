# Controle de juízes API-first (modelo PULL)

Modelo **API-first, pull-based**: as máquinas se conectam à API, anunciam capacidade +
inventário e **puxam jobs no heartbeat**. O escalonador é o próprio handler de heartbeat
(sem loop, sem porta de entrada nos juízes) — substituiu o modelo síncrono antigo.

## Fluxo

```
 Juiz (agent, só curl de saída)            API (nginx+fcgiwrap, server/api/v1)
  POST /judge/register  ─────────────▶  handlers/judge/register.sh  ─▶ run/registry/<host>.json
  GET  /judge/package-meta?id ───────▶  handlers/judge/package-meta.sh ─▶ {checksum} (afeta-TL)
  GET  /judge/package?id ────────────▶  handlers/judge/package.sh   ─▶ .tar.gz + X-Moj-Checksum
  ...cacheia em ~/.cache/moj/problems/<id>, CALIBRA na 1ª vez (calibreitor → tl.<host>)...
  POST /judge/tl-report(id,checksum,tl)▶ handlers/judge/tl-report.sh ─▶ run/tl/<id>.json (por host)
  POST /judge/heartbeat(state,inv,free_slots,total_slots,cfg_hash) ─▶ heartbeat.sh = ESCALONADOR
        ◀── {assigned:[…]|null, update|null, command|null, reregister, config?} ──
        (claim atômico; LOTE de até free_slots jobs; config por juiz quando o cfg_hash difere)
  ...julga com mojtools no CACHE local (tl.<host>): N SLOTS em paralelo, cada job PINADO
     no cpuset do slot (partition off|numa|cpus:X + reserve — ver judges-config)...
  POST /judge/result(verdict,verdict_canon,score*,groups?,tests,html_b64) ─▶ handlers/judge/result.sh ─▶ spool "result"
                                                                              │
  submit ─▶ spool ─▶ server/daemons/judged.sh (INTAKE) ─▶ enfileira na banda de prioridade
                     judged.sh (INGESTION do "result") ─▶ history/data/placar (inalterado)
                                                          + contests/<c>/results/<id>.json + report.html
```

## Componentes

| arquivo | papel |
|---|---|
| `server/judge-gw/sched-lib.sh` | Biblioteca: registro `<host>.json`, fila por bandas, `q_claim` (claim atômico + **preferência quente/`COLD_GRACE`**), `q_promote_starved`, `q_reconcile`, `upd_*`/`cal_request` (pedidos de calibração). |
| `server/api/v1/lib/tl-store.sh` | Store dos TLs reportados pelos juízes (`run/tl/<id>.json`, por host, por checksum); TL servível = **máx entre hosts**; `pkg_tl_checksum`, `index_problem_bg` (índice no servidor). |
| `server/api/v1/lib/worker-auth.sh` | `require_worker`: Bearer `mojw_<token>` (compartilhado, 600). |
| `server/api/v1/handlers/judge/register.sh` | Anuncia specs (CPU/mem/**GPU**) + inventário (problemas **em cache**) → `registry/<host>.json`. GPU só entra com **compute comprovado** (vendor nvidia/amd, do `nvidia-smi`/`rocm-smi`; lspci/erro de driver são descartados) e `capability=gpu` sem GPU real rebaixa p/ `pos`. |
| `server/api/v1/handlers/judge/package{,-meta}.sh` | Serve o pacote do problema (.tar.gz) + checksum p/ o juiz cachear. |
| `server/api/v1/handlers/judge/tl-report.sh` | Recebe o TL calibrado pelo juiz → `run/tl/<id>.json`; re-indexa o `var/jsons`. |
| `server/api/v1/handlers/judge/heartbeat.sh` | Pulso; reivindica 1 command OU 1 update OU um LOTE de até `free_slots` jobs (multi-slot) e devolve; entrega a CONFIG por juiz quando muda (`cfg_hash`). **É o escalonador.** |
| `server/api/v1/handlers/judge/result.sh` | Recebe o veredicto do worker → spool "result" (judged finaliza). |
| `server/api/v1/handlers/judge/update-report.sh` | Recebe o report de calibração (ok/log) → `registry.<host>.last_update`. |
| `server/api/v1/handlers/ops/problemtl.sh` | (admin) TL de um problema, do store (máx entre hosts) + por host. |
| `server/api/v1/handlers/judge/list.sh` | (admin) Dump dos juízes: specs + inventário + `last_update`. |
| `mojtools/tl-checksum.sh` | Checksum (16 hex) dos arquivos que afetam o TL/compilação (conf+tests/input+sols/good+scripts/*, este último com o bit +x). |
| `judge/agent/moj-agent.sh` + `inventory.sh` | O agente (pull + **cache**). Roda 1 por capacidade. |
| `server/etc/systemd/moj-agent@.service` | Unit do agente: `systemctl enable --now moj-agent@pos`. |

`judged.sh` ganhou: `INTAKE_MODE`/`INTAKE_QUEUE_CONTESTS` (intake p/ fila), ingestão do
comando `result` e do `synctreino`. `contest-create.sh` ganhou `CONTEST_PRIORITY`
(separado do modo). `build-and-test.sh`/`calibreitor.sh` rodam no **cache local** do juiz
(`tl.<host>`), sem depender de NFS.

## Modelo cache (pacotes por problema + TL reportado)

O juiz **não clona repositório**. Ele baixa o **pacote de cada problema** (sob demanda,
no 1º job ou num pedido de calibração) p/ um **cache local** (`~/.cache/moj/problems/<id>`)
e guarda, junto, o **checksum** dos arquivos que afetam o TL/compilação (`conf`+`tests/input`+
`sols/good`+`scripts/*` da correção especial, este com o bit +x; via `mojtools/tl-checksum.sh`).
Na 1ª vez (ou quando o checksum muda) ele **calibra**
(`calibreitor.sh` → `tl.<host>`) e **reporta** o TL ao MOJ (`POST /judge/tl-report`). O MOJ
guarda o TL **por host, por checksum** (`run/tl/<id>.json`) e serve o **máximo entre os hosts**
no `var/jsons` (conservador). Ao **relançar**, o agente re-reporta os TLs do cache (sem
recalibrar). Se o problema muda, o checksum novo **descarta** o TL antigo (todos recalibram).

- **GC do cache no juiz** (lado agente): pacote sem uso há `AGENT_CACHE_MAX_DAYS` (14) vira
  **stub** — o `pkg/` pesado sai, `tl.<host>`+meta ficam (o registro segue anunciando o
  problema e o boot re-reporta o TL); no próximo uso com o MESMO checksum o agente re-baixa e
  **restaura o TL sem recalibrar**. Teto opcional `AGENT_CACHE_MAX_MB` (LRU). O custo escondido
  de um stub p/ o escalonador é só 1 re-download.
- **NFS** vira opcional: só serve p/ "aproveitar o cache" — levantar um juiz é só conectar.
- **Escalonamento**: `q_claim` prefere juízes **quentes** (já têm o problema em cache); quem
  não tem só pega o job após `COLD_GRACE` (8 s) — aí baixa+calibra sob demanda. Qualquer juiz
  capaz julga qualquer problema; nada de "validar inventário".
- **Pool de juízes** (consistência de hardware): o contest pode fixar as máquinas que corrigem
  (`CONTEST_JUDGES` no conf; override por problema em `problem-judges.json`). O daemon resolve o
  pool EFETIVO no enqueue e grava **`allowed_hosts`** no job; `q_claim` só entrega a host listado.
  **ESTRITO por default** (`POOL_GRACE=0`): pool offline = job espera na fila (o preflight e o
  dashboard do contest avisam); `POOL_GRACE>0` libera p/ qualquer juiz após esse tempo. Com pool,
  o TL servido em `/contest/problems` = máx **só entre os hosts do pool efetivo**.
- **"update problems"** (`/ops/updateproblemset`) não clona: enfileira **calibração** dos
  problemas novos/alterados (checksum ≠ o do TL guardado). `{all:true}` recalibra tudo.
- **Calibração é IDEMPOTENTE** (lição do incidente 2026-07-15, quando 4 pedidos duplicados
  entupiram os 6 slots do juiz): `cal_request` é o choke-point único — se já existe calibração
  **pendente ou em execução** p/ o mesmo problema (`upd_find_calibrate`, sob o lock do
  `upd_claim`), devolve o `reqid` existente e NÃO cria outro job. Re-disparar `moj calibrate`,
  re-validar ou publicar em massa nunca multiplica jobs. O caminho direcionado
  (`request-calibration` com `hosts`) dedupa os comandos ainda não entregues por host
  (`cmd_find_calibrate`). E o **publish** (`/problems/set-public`) só enfileira calibração se o
  `tl-checksum` atual difere do checksum calibrado servido (`run/tl/<id>.json`) — publicar sem
  mudança de pacote responde `calibration:"up_to_date"` e não toca a fila.
- **Indexar** (`var/jsons`, HTML do enunciado) roda **no servidor** (`index_problem_bg`, via o
  Makefile do repo no store) — o `publish` chama isso + pede calibração. Só o
  enunciado HTML precisa do repo; calibrar/julgar usam só o pacote no cache + o `mojtools`.

## Multi-slot (particionamento) + config por juiz

O agente pode PARTICIONAR a máquina em **slots de cpus disjuntas** e corrigir **N problemas ao
mesmo tempo**, cada job (e cada calibração) pinado no cpuset do seu slot (`taskset` no subshell;
herda p/ bwrap/compilador/solução; o `nproc` da fatia limita o paralelismo interno de testes).
Modos: `off` (1 slot, máquina toda — default), `numa` (1 slot por NUMA node), `cpus:<X>` (fatias
de X cpus); `reserve` tira as N primeiras cpus dos slots (SO/agente); `disabled` drena e para.

- **Config por juiz** = `contests/treino/var/judges-config.json` (estado DESEJADO do admin;
  NUNCA no registry — o register o sobrescreve). Editada por `POST /ops/judge-config`
  (`moj judges config <host> …` na CLI, ou a aba 🖥️ Máquinas). O heartbeat compara o
  `cfg_hash` do agente com o vigente e entrega `config` quando difere; o agente **drena**
  (espera os jobs em andamento) e aplica.
- **Heartbeat multi-slot**: agente manda `free_slots`/`total_slots`; o handler entrega um
  **lote `assigned:[…]`** de até `free_slots` jobs (agente ANTIGO sem `free_slots` recebe o
  escalar de sempre). O registro guarda `free_slots`/`total_slots` p/ os painéis
  (`/index/status` `judge.busy` = Σ slots ocupados, `judge.slots` = Σ slots).
- **Relatório por juiz**: `GET /ops/judge-results?host=&limit=` — últimas correções (de
  `run/results/`, que carrega o `.host`) + agregado por host. CLI: `moj judges results`.

## Prioridade (bandas)

`CONTEST_PRIORITY` (escolhido na criação) → banda: `super`(admin) > `prova` >
`lista-privada` > `rejulgar` > `lista-publica`. Job parado >5 min sobe de banda
(`q_promote_starved`). PROVA fica alta automaticamente.

## Variáveis

| var | default | papel |
|---|---|---|
| `RUNDIR` | `…/run` | estado: `registry/`, `queue/<banda>/`, `assigned/<host>/`, `results/`, `updates/`, **`tl/`** |
| `REG_TTL` | `30` | s; heartbeat mais velho = worker morto |
| `ASSIGN_TTL` | `120` | s; job reivindicado sem novo beat volta p/ fila |
| `COLD_GRACE` | `8` | s; juiz que NÃO tem o problema em cache só reivindica após isso |
| `POOL_GRACE` | `0` | s; job com `allowed_hosts` (pool): `0` = ESTRITO (só o pool julga; offline = fila espera), `>0` = qualquer juiz após esse tempo |
| `JUDGE_CACHE` | `~/.cache/moj/problems` | (juiz) cache local de pacotes por problema |
| `MOJ_PROBLEMS_DIR` | `…/moj-problems` | (servidor) store dos pacotes servidos aos juízes |
| `INTAKE_MODE` | `legacy` | `queue` = intake vai p/ a fila (pull) globalmente |
| `INTAKE_QUEUE_CONTESTS` | — | `"treino c2"` = habilita o pull só nesses contests (rollout) |
| `WORKER_TOKEN_FILE` | `…/run/secrets/worker.token` (API) / `…/judge/etc/worker.token` (juiz) | token `mojw_…` |
| `MOJ_API`,`CAPABILITY`,`HEARTBEAT_SECS` | — | config do agente |

## Bootstrap do token

```bash
TOK="mojw_$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
# no host da API:
install -Dm600 <(printf '%s' "$TOK") "$RUNDIR/secrets/worker.token"
# distribua p/ cada juiz (NFS ou cópia — o juiz só precisa do token + mojtools + cache):
install -Dm600 <(printf '%s' "$TOK") /home/prof/judge/etc/worker.token
```

## Rollout do pull (zero-downtime)

1. Sobe a API + `moj-judged` normalmente (já roda). Gera o token (acima).
2. Sobe `moj-agent@<cap>` em UM juiz (shadow): aparece em `GET /judge/list`.
3. Liga o pull só no treino: `INTAKE_QUEUE_CONTESTS=treino` no `moj-judged`.
   Submeta no treino → o agent puxa, julga e o resultado aparece (history+placar+`results/<id>.json`).
4. Sobe agents nos demais juízes (1 por capacidade). Acompanhe em `/judge/list` e `/index/status`.
5. Vira o default: `INTAKE_MODE=queue`.

## Legado (aposentado)

O modelo síncrono antigo foi **removido** — hoje o julgamento é 100% pull. Fallback de
emergência sem juízes: `INTAKE_MODE=legacy` + `JUDGE_BACKEND=mock|local`.

## O que NÃO mudou

mojtools (`build-and-test.sh`/`cage-run.sh`), `gen-report.sh`/`report.html`, o placar
(`server/score/build.sh` + formatos `history`/`data`), o intake por spool+inotify e a
auth de sessão de usuário.
