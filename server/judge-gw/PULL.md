# Controle de juízes API-first (modelo PULL)

Substitui o cluster legado (`judge/sistema_escalonador/` + `root-daemon*` +
`job-receiveitor*` com `MOJPORTS` fixo e poll-storm de `islocked`) por um modelo
**API-first, pull-based**: as máquinas se conectam à API, anunciam capacidade +
inventário e **puxam jobs no heartbeat**. O escalonador é o próprio handler de
heartbeat (sem loop, sem porta de entrada nos juízes). Ver também `README.md`
(plano incremental antigo, que mantinha o escalonador) — este doc é o destino final.

## Fluxo

```
 Juiz (agent, só curl de saída)            API (nginx+fcgiwrap, server/api/v1)
  POST /judge/register  ─────────────▶  handlers/judge/register.sh  ─▶ run/registry/<host>.json
  POST /judge/heartbeat(state,inv) ──▶  handlers/judge/heartbeat.sh = ESCALONADOR
        ◀── {assigned|null, update|null, reregister} ──  (claim atômico na fila por prioridade)
  ...julga com mojtools (NFS, tl.<host>) em background, batendo "busy"...
  POST /judge/result(verdict,tests,html_b64) ─▶ handlers/judge/result.sh ─▶ spool "result"
                                                                              │
  submit ─▶ spool ─▶ server/daemons/judged.sh (INTAKE) ─▶ enfileira na banda de prioridade
                     judged.sh (INGESTION do "result") ─▶ history/data/placar (inalterado)
                                                          + contests/<c>/results/<id>.json + report.html
```

## Componentes

| arquivo | papel |
|---|---|
| `server/judge-gw/sched-lib.sh` | Biblioteca: registro `<host>.json`, fila por bandas, `q_claim` (claim atômico por flock+mv), `q_promote_starved`, `q_reconcile` (requeue de morto), `upd_*` (atualização de repo). |
| `server/api/v1/lib/worker-auth.sh` | `require_worker`: Bearer `mojw_<token>` (compartilhado, NFS, 600). |
| `server/api/v1/handlers/judge/register.sh` | Anuncia specs (CPU/mem/**GPU**) + inventário (problemas) → `registry/<host>.json`. |
| `server/api/v1/handlers/judge/heartbeat.sh` | Pulso; se livre, reivindica 1 update OU 1 job e devolve. **É o escalonador.** |
| `server/api/v1/handlers/judge/result.sh` | Recebe o veredicto do worker → spool "result" (judged finaliza). |
| `server/api/v1/handlers/judge/update-report.sh` | Recebe o report de atualização → `registry.<host>.last_update`. |
| `server/api/v1/handlers/judge/list.sh` | (admin) Dump dos juízes: specs + inventário + `last_update`. |
| `judge/agent/moj-agent.sh` + `inventory.sh` | O agente (pull). Roda 1 por capacidade. |
| `server/etc/systemd/moj-agent@.service` | Unit do agente: `systemctl enable --now moj-agent@pos`. |

`judged.sh` ganhou: `INTAKE_MODE`/`INTAKE_QUEUE_CONTESTS` (intake p/ fila), ingestão do
comando `result` e do `synctreino`. `contest-create.sh` ganhou `CONTEST_PRIORITY`
(separado do modo). `build-and-test.sh`/`calibreitor.sh` usam `tl.<host>` (NFS).

## Prioridade (bandas)

`CONTEST_PRIORITY` (escolhido na criação) → banda: `super`(admin) > `prova` >
`lista-privada` > `rejulgar` > `lista-publica`. Job parado >5 min sobe de banda
(`q_promote_starved`). PROVA fica alta automaticamente.

## Variáveis

| var | default | papel |
|---|---|---|
| `RUNDIR` | `…/run` | estado: `registry/`, `queue/<banda>/`, `assigned/<host>/`, `results/`, `updates/` |
| `REG_TTL` | `30` | s; heartbeat mais velho = worker morto |
| `ASSIGN_TTL` | `120` | s; job reivindicado sem novo beat volta p/ fila |
| `INTAKE_MODE` | `legacy` | `queue` = intake vai p/ a fila (pull) globalmente |
| `INTAKE_QUEUE_CONTESTS` | — | `"treino c2"` = habilita o pull só nesses contests (rollout) |
| `WORKER_TOKEN_FILE` | `…/run/secrets/worker.token` (API) / `…/judge/etc/worker.token` (juiz) | token `mojw_…` |
| `MOJ_API`,`CAPABILITY`,`HEARTBEAT_SECS` | — | config do agente |

## Bootstrap do token

```bash
TOK="mojw_$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
# no host da API:
install -Dm600 <(printf '%s' "$TOK") "$RUNDIR/secrets/worker.token"
# espelhe no NFS p/ os juízes:
install -Dm600 <(printf '%s' "$TOK") /home/prof/judge/etc/worker.token
```

## Rollout (cluster vivo o tempo todo)

1. Sobe a API + `moj-judged` normalmente (já roda). Gera o token (acima).
2. Sobe `moj-agent@<cap>` em UM juiz (shadow): aparece em `GET /judge/list`.
3. Liga o pull só no treino: `INTAKE_QUEUE_CONTESTS=treino` no `moj-judged`.
   Submeta no treino → o agent puxa, julga e o resultado aparece (history+placar+`results/<id>.json`).
4. Sobe agents nos demais juízes (1 por capacidade). Acompanhe em `/judge/list` e `/index/status`.
5. Vira o default: `INTAKE_MODE=queue`.

## Aposentadoria do legado (após validar)

Pode parar/desabilitar (são arquivos de runtime no `judge/`, fora do git):
`judge/sistema_escalonador/*` (escalonador, job-receiveitor-master, lancar-master),
`judge/judge/root-daemon*.sh`, `judge/judge/job-receiveitor*.sh`, `judge/judge/lancar-*.sh`,
`moj-master.service`. **Mantém** como rede de segurança: o backend `cluster` de
`judge.sh` + `result-sink.sh` (e o registro). Rollback: `INTAKE_MODE=legacy` + parar os agents.

## O que NÃO mudou

mojtools (`build-and-test.sh`/`cage-run.sh`), `gen-report.sh`/`report.html`, o placar
(`server/score/build.sh` + formatos `history`/`data`), o intake por spool+inotify e a
auth de sessão de usuário.
