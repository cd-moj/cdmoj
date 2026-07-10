# server/judge-gw/ — Gateway do juiz + escalonador pull (lado servidor)

O lado servidor do julgamento. Em produção o modelo é **PULL**: o daemon
`server/daemons/judged.sh` **enfileira** cada submissão numa banda de prioridade e os
juízes (repo `judge/`, agente `moj-agent@`) **puxam** o job no heartbeat, baixam o pacote
sob demanda, calibram e reportam o veredicto/TL — tudo por HTTP, sem conexão de entrada
p/ os juízes. O protocolo completo está em **`PULL.md`**. Tudo é bash + arquivos, sem
broker/DB.

## Peças

| arquivo | papel |
|---|---|
| `sched-lib.sh` | Biblioteca do escalonador in-daemon: registro JSON por host (`run/registry/<host>.json`), fila por **bandas de prioridade** (`run/queue/`), claim atômico por `flock+mv` (`run/assigned/`), results (`run/results/`). Sourced por `handlers/judge/*` e por `judged.sh`. |
| `judge.sh` | Gateway síncrono de dev/legado. `judge_run <contest> <prob> <lang> <code_b64> <file>` → veredicto em stdout. Backends `mock`/`local` por `$JUDGE_BACKEND`. **Não é usado no modo pull** (`INTAKE_MODE=queue`): lá o daemon enfileira antes de chamar `judge_run`. |
| `PULL.md` | O protocolo pull (registro, heartbeat, claim, calibração, reporte de TL, cache por-problema). |

## Backends de `judge.sh` (só dev/legado)

- **mock** (default): `Accepted,100p` determinístico; código vazio → `Compilation Error`.
  Permite exercitar o pipeline assíncrono inteiro sem bubblewrap nem juízes.
- **local**: roda `mojtools/build-and-test.sh <lang> <src> $PROBLEMSDIR/<prob> y`
  (bubblewrap) e captura a última linha (o veredicto). Fallback com mensagem clara se
  faltar `bwrap`, o script, ou o pacote do problema.

```
JUDGE_BACKEND=mock  bash judge.sh treino p1 C "$(printf 'int main(){}'|base64 -w0)" sol.c
```

> O backend síncrono `cluster` (master `:27000` + push via `result-sink.sh`) e os helpers de
> registro por `nc` foram **removidos** — o modelo pull os substituiu (ver `PULL.md`).

## Handlers do pull (o que os juízes chamam)

Os endpoints que o agente consome vivem em `server/api/v1/handlers/judge/`:
`register`, `heartbeat`, `list`, `package`, `package-meta`, `result`, `calib-report`,
`tl-report`, `update-report` — todos autenticam com **worker-token** (`mojw_…`) e usam
`sched-lib.sh`.

## Variáveis de ambiente

| var | default | papel |
|---|---|---|
| `JUDGE_BACKEND` | `mock` | `mock`/`local` (dev/legado; `queue` no daemon = pull) |
| `PROBLEMSDIR` | `…/judge/judge/problems` | pacotes p/ o backend `local` |
| `REGISTRYDIR` | `$RUNDIR/registry` | `<host>.json` por juiz (vivo = `last_seen` recente) |
| `QUEUEDIR` | `$RUNDIR/queue` | bandas de prioridade |
| `ASSIGNEDDIR` | `$RUNDIR/assigned` | jobs reivindicados (`<host>/<ts>_<id>.json`) |
| `RESULTSDIR` | `$RUNDIR/results` | `results/<id>.json` |
| `REG_TTL` | `30` | s; heartbeat mais velho = juiz morto |
| `ASSIGN_TTL` | `120` | s; job reivindicado sem novo beat volta p/ a fila |
