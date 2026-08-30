# BANCADA — replay local da carga da Maratona (custo/vazão sem tocar produção)

A bancada mede **quantos veredictos/min o MOJ sustenta e a que custo** (CPU, forks),
localmente, com o fluxo REAL: submit → spool → judged (fila) → `q_claim` via
`/judge/heartbeat` → `/judge/result` → ingest → metrics → placar — e, no rig `prova`,
com o tier web junto e **pollers retroalimentados** (time com pendência pola
history+summary a 5-10 s: a espiral do dia 29/08).

## Rigs

```
bash server/test/load/bancada.sh backlog --backlog 2000        # dreno puro × profundidade
bash server/test/load/bancada.sh esteira                       # fluxo pull completo (fixture mktemp)
bash server/test/load/bancada.sh prova --teams 300             # + tier web (nginx 8080 de dev)
   opções comuns: --scenario nome --scale N --seed N --teams N
                  --plateaus "40,60,80,100,120" --plateau-dur 180 --keep
```

- **backlog**: forja N *results* no spool + pendências no history e roda `judged --drain`.
  Responde "o custo por veredicto depende da profundidade?" (S2: NÃO — é plano).
- **esteira**: replay do plano no relógio via `router.sh` direto + juiz mock em PULL
  (exercita `q_claim` e `/judge/result` reais). Fixture inteira em mktemp.
- **prova**: tudo por HTTP na pilha de dev (`start-fcgiwrap.sh` + nginx do
  `~/nginx-proxy`, porta 8080), contest DEMO **zz-bancada** no CONTESTSDIR real, com
  **guarda de escritor único** (recusa se já houver judged no spool real). Rotas
  `/judge/*` vão no host PRINCIPAL (o vhost de contest as isola).

## O plano (bancada-plan.awk)

Determinístico por seed: **escadaria** de platôs (subs/min × duração). Não se comprime
taxa — trunca-se duração: cada platô mede TAXA e inclinação de backlog em regime; o p50
de 68 min da prova real é integral de backlog e não se reproduz em 15 min — se PREVÊ
(inclinação > 0 no platô de 120/min). Mesmo seed ⇒ `plan.tsv` byte-idêntico (o sha sai
no `env.txt`; runs só comparam com sha igual). Mix de veredictos ≈ o da prova.

## Métricas

- latência de veredicto: epoch do submit × mtime do result em `submissions-done`;
- CPU por componente: `utime+stime+cutime+cstime` do judged (que ESPERA os filhos — eles
  contam) e a SOMA do pool prefork do fcgiwrap;
- forks do box: delta de `processes` em `/proc/stat` (verificação global);
- execs: `strace -f -c -e trace=execve` em janela (quando disponível).

## O que a compressão NÃO cobre

Leak/drift de 5 h (fica p/ um soak do cenário vencedor), e o grau de CONTENÇÃO de
produção (o box de dev tem 32 cores ociosos; comparações são RELATIVAS entre cenários no
mesmo box — números absolutos não transferem).

## Números de referência (spike de 30/08, dev 5950X 32T)

| medição | resultado |
|---|---|
| dreno (backlog) 50/500/2000 | 60/48/50 ms/veredicto — **PLANO na profundidade** (o O(N²) do glob não domina) |
| baseline frio | ~48 ms/veredicto ≈ **1.250/min** (a barra é 150/min) |
| dieta (conf 0-fork no metrics, sem basename, setverdict 1 jq, hardlink) | **40 ms** frio / 66 ms sob tempestade (−16%) |
| jq forkado × coproc-jq persistente | 2.537 µs × **34 µs** (75×; semântica idêntica, zero ABI) |
| tempestade de forks (32×/bin/true) | +60% no ms/veredicto — contenção conta, mas NÃO explica o 20× da prova sozinha |

Conclusão do spike: **builtin compilado (jqb) descartado com números** — o coproc-jq
captura ≥98% do ganho sem C/ABI/binário duplo; o gargalo real da prova é o ACOPLAMENTO
(tier web forkando + esteira serial no mesmo box), que o rig `prova` reproduz.
Avaliação completa: `AVALIACAO-CPU.md`.

## linguagens/ — o mesmo ingest em awk/perl/lua/ruby/C

`linguagens/teto-lang.sh <label> <cmd>` monta a fixture dos tetos (2.000 results, 300
users) e mede qualquer drain que respeite RUNDIR/CONTESTSDIR, CONFERINDO o resultado.
Implementações em `linguagens/ingest.{awk,pl,lua,rb,c}` (+ `drain-awk.sh` que embrulha o
awk com find/xargs). Números e leitura: seção "awk, make e a casinha" do AVALIACAO-CPU.md.
