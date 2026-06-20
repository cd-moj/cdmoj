# server/judge-gw/ — Gateway do juiz + comunicação por PUSH

Gateway entre o backend web (daemon `server/daemons/judged.sh`) e o **cluster de
juiz distribuído** (`judge/`). É **aditivo**: nada aqui reescreve os scripts vivos
do cluster em lugar — eles passam a *chamar* estas peças. Tudo é bash + arquivos,
sem broker/DB, mantendo o escalonador-por-prioridade e o sandbox `mojtools`.

## Peças

| arquivo | papel |
|---|---|
| `judge.sh` | Biblioteca. `judge_run <contest> <prob> <lang> <code_b64> <file>` → veredicto em stdout. Backends `mock`/`local`/`cluster` por `$JUDGE_BACKEND`. |
| `result-sink.sh` | Listener TCP que recebe o veredicto **por push** do worker/master e grava `$RUNDIR/results/<jobid>` (e `<corr>`). Substitui o **double-poll** de retorno. |
| `register.sh` | Registro + heartbeat de worker (capacidade + free/busy) num arquivo `$RUNDIR/registry/workers`. Substitui o `MOJPORTS` fixo e o poll-storm de `islocked`. |

## Os três backends de `judge.sh`

- **mock** (default): `Accepted,100p` determinístico; código vazio → `Compilation
  Error`. Permite testar o pipeline assíncrono inteiro sem bubblewrap nem cluster.
- **local**: roda `mojtools/build-and-test.sh <lang> <src> $PROBLEMSDIR/<prob> y`
  (bubblewrap) e captura a última linha (o veredicto). Faz fallback com mensagem
  clara se faltar `bwrap`, o script, ou o pacote do problema.
- **cluster**: monta `{"cmd":"run",...}` (mesmos campos de
  `old/.../enviar-newcdmoj.sh`), envia por `nc` ao escalonador (`$JUDGE_MASTER`,
  default `localhost:27000`), pega o `jobid` e **espera o push** (arquivo em
  `$RUNDIR/results/`). Se o push não vier (sink fora do ar), cai para um **poll
  limitado** de `getresult` — a rede de segurança do mecanismo antigo.

```
JUDGE_BACKEND=mock    bash judge.sh treino p1 C "$(printf 'int main(){}'|base64 -w0)" sol.c
JUDGE_BACKEND=cluster JUDGE_MASTER=localhost:27000 RESULT_SINK=mojweb:28000 bash judge.sh ...
```

## Como o PUSH substitui o double-poll

**Antes** (3 camadas, todas polling sobre `nc`, retorno em loop de 0.5s por até 24h):

```
corrige.sh ──getresult(loop)──> master:27000 ──getresult(loop)──> worker:4x000
   (enviar-newcdmoj.sh::pega-resultado-newcdmoj  +  master::cmd-getresultindirect)
```

**Depois** (event-driven; o retorno não faz polling nenhum no caminho feliz):

```
judged.sh ─run─> master:27000 ─dispatch─> worker            (só o dispatch é req/resp)
                                              │  ...julga (mojtools)...
worker  ──push {"cmd":"result",jobid,verdict}──> result-sink:28000
                                              └─> grava $RUNDIR/results/<jobid>
judge.sh (backend cluster) acorda na hora lendo esse arquivo (inotify/curto sleep)
```

Ganho: elimina as duas malhas de polling de 0.5s/24h. O **único** req/resp que
sobra é o `run` (dispatch) — naturalmente síncrono e curto.

---

## Migração incremental do cluster vivo (checklist)

Fazer **um passo de cada vez**, validando entre eles. Os números de linha são do
estado atual dos arquivos (podem variar levemente).

### Passo 1 — PUSH do worker (maior ganho, menor risco)

Worker grava o status localmente hoje em `root-daemon*.sh`. Logo após escrever o
veredicto final, **adicionar** um push ao sink do master (não remova nada ainda).

- **`judge/judge/root-daemon.sh`** (e `-cm/-gpu/-hu`), logo após
  `echo "${RESP[1]}" > $LOGDIR/$ID/status` (linha ~49):
  ```bash
  # PUSH do veredicto p/ o master (aditivo; fallback continua sendo getresult)
  VERDICT="${RESP[1]}"
  CORR="$(jq -r '.corr // empty'        < "$JSON")"
  SINK="$(jq -r '.result_sink // empty' < "$JSON")"   # ex.: mojweb:28000
  if [[ -n "$SINK" ]]; then
    printf '{"cmd":"result","jobid":"%s","corr":"%s","verdict":"%s"}\n' \
      "$ID" "$CORR" "$VERDICT" \
      | timeout 10 nc "${SINK%:*}" "${SINK##*:}" >/dev/null 2>&1 || true
  fi
  ```
  > Onde `corr`/`result_sink` vêm no job.json porque `judge.sh` já os coloca no
  > `run`. **`job-receiveitor*.sh::queuejob`** já persiste o JSON inteiro em
  > `job.json`, então `corr`/`result_sink` chegam ao worker sem mudança extra.

- Subir o sink no host web: `bash server/judge-gw/result-sink.sh` (porta 28000).
- A partir daqui, `judge.sh` backend cluster recebe o veredicto por arquivo e o
  poll vira só fallback. **Pode-se manter os dois em paralelo** durante a transição.

### Passo 2 — master encaminha o push (quando worker e web não se enxergam)

Se o worker não alcança o host web diretamente, o **master** reencaminha. Em
`judge/sistema_escalonador/job-receiveitor-master.sh`, adicionar um comando:

```bash
# registrar a função no COMMANDFUNCTIONS (linha ~204) e implementar:
function cmd-result() {
  local JOBID=$(jq -r '.jobid // empty'   <<< "$JSON")
  local CORR=$( jq -r '.corr  // empty'   <<< "$JSON")
  local VERD=$( jq -r '.verdict // empty' <<< "$JSON")
  local SINK="${MOJ_WEB_SINK:-localhost:28000}"
  printf '{"cmd":"result","jobid":"%s","corr":"%s","verdict":"%s"}\n' \
    "$JOBID" "$CORR" "$VERD" | nc "${SINK%:*}" "${SINK##*:}" >/dev/null 2>&1
  echo '{"ok":true}'
}
```
e o worker passa a empurrar para o **master** (`SINK=master:27000`) em vez do web.

### Passo 3 — registro + heartbeat (aposenta o `MOJPORTS` fixo)

- **`judge/judge/lancar-juizes.sh`**: ao subir cada worker, anunciar a capacidade
  e iniciar um heartbeat. Para o grupo `pos` (`relacao[pos1]=41050` etc.):
  ```bash
  ssh "$MACHINE" "bash ~/server/judge-gw/register.sh up $MACHINE ${relacao[$MACHINE]} pos"
  ssh "$MACHINE" "tmux new-window -n hb -d \
    'while sleep 5; do S=free; flock -n /dev/shm/free-machine true || S=busy; \
       bash ~/server/judge-gw/register.sh beat $MACHINE ${relacao[$MACHINE]} pos \$S; done'"
  ```
  (capability = `pos`/`gpu`/`cm`/`hu` conforme o grupo). O `free/busy` reaproveita
  o mesmo `flock` de `/dev/shm/free-machine` que `cmd-islocked` já usa.

- **`judge/sistema_escalonador/escalonador.sh`**: trocar o array fixo e o
  `get_free_machine` (poll-storm) por leitura do registro.
  - Remover/neutralizar o array literal `MOJPORTS+=(...)` (linhas ~25–35).
  - `get_free_machine()` (linha ~161) vira:
    ```bash
    function get_free_machine() {
      mapfile -t LISTADELIVRES < <(bash ~/server/judge-gw/register.sh list free)
    }
    ```
  - A afinidade por máquina (`contest_servers`/`index_of_server`) passa a ser
    **match por capacidade**: filtre `register.sh list free <cap>` em vez de casar
    nome de host. Isso elimina o algoritmo guloso de 2 passos (`run`/`run2`).
  - Opcional: chamar `register.sh gc` de tempos em tempos no loop principal.

### Passo 4 — higiene (jobid de correlação + arquivamento)

- **jobid de correlação único ponta-a-ponta**: `judge.sh` já gera `corr` e o
  propaga no `run`; faça `corr` ser o id logado em master e worker (em vez de
  trocar o id a cada etapa) para `trace` ponta-a-ponta.
- **rotacionar `master/enviado/`** (cresce sem limite; `find … *<jobid>*` é O(n)):
  mover jobs concluídos (com `resultado_final_ts`) para `master/enviado-YYYYMM/`
  num `gc` periódico.

### O que **NÃO** muda

Permanecem: o **escalonador por diretórios de prioridade** (`000-super` →
`080-lista-publica` + `intermed`), o `check_starvation`, o sandbox
`mojtools/{build-and-test.sh,cage-run.sh}` e o spool de jobs em arquivos. O
dispatch `run` continua req/resp por `nc`/`tcpserver`. Cross-host pode ganhar
multiplexação SSH (`ControlMaster`); web↔master, unix socket — ambos opcionais.

## Variáveis de ambiente

| var | default | papel |
|---|---|---|
| `JUDGE_BACKEND` | `mock` | `mock`/`local`/`cluster` |
| `JUDGE_MASTER` | `localhost:27000` | host:port do escalonador |
| `PROBLEMSDIR` | `…/judge/judge/problems` | pacotes p/ backend `local` |
| `RESULT_SINK` | (vazio) | host:port do sink anunciado ao master no `run` |
| `RESULT_SINK_PORT` | `28000` | porta de escuta do `result-sink.sh` |
| `RESULTSDIR` | `$RUNDIR/results` | onde o sink grava e o gateway espera |
| `REGISTRYDIR` | `$RUNDIR/registry` | arquivo de registro de workers |
| `REG_TTL` | `30` | s; heartbeat mais velho = worker morto |
