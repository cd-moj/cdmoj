# Avaliação: menos CPU no MOJ — bash × builtins compilados × Python (30/08/2026)

A pergunta do Ribas depois da Maratona: *compensa manter bash? dá p/ cortar os forks com
builtins compilados (`enable -f`)? os workers Python salvaram — dá p/ replicar o efeito
em bash?* Respondida com a BANCADA local (ver `BANCADA.md`) — **nada foi a produção**.

## O veredicto, em uma tela

1. **A esteira bash NUNCA foi o gargalo em isolamento**: com a dieta, drena a
   **1.500 veredictos/min** (40 ms/veredicto) — 10× a barra (150/min = pico da prova
   +25%). O modelo "30 execs × 1,7 ms" prevê ~1.100/min e a medição CONFIRMA: em
   isolamento a conta fecha.
2. **O termo dominante que faltava era o `q_claim`**: 2-6 jq POR JOB examinado, varrendo
   a fila INTEIRA dentro do flock global, POR HEARTBEAT. A bancada acoplada o reproduziu
   ao vivo: com o q_claim antigo, a escadaria inteira (min 1-14) saiu com **out≈0** e os
   1.166 veredictos drenaram em RAJADA nos 3 min finais (~390/min de capacidade de
   ingest, presa atrás do claim); com o q_claim de **1 jq/job**, o fluxo acompanha a
   entrada desde o 1º platô. Na Maratona (fila de 2.000, N juízes batendo por segundo,
   exec a dezenas de ms sob carga) esse é o mecanismo que fecha a conta dos 40-70/min.
3. **Builtin compilado (jqb): DESCARTADO com números.** O coproc-jq (jq REAL persistente,
   1 linha por chamada) faz o round-trip em **34 µs** contra 2.537 µs do fork — 75×, com
   semântica idêntica por construção, zero ABI, zero binário duplo. O builtin só
   compraria os últimos ~24 µs ao preço de C + headers do bash por distro + risco de
   SIGSEGV no processo persistente. Se um dia o perfil mostrar o coproc como gargalo
   (não mostra), o desenho está em B2 do plano.
4. **Python continua tendo lugar — como está**: porteiro p/ leitura quente (0 forks) e
   os drains como **break-glass** (2.033 veredictos/46 s provados na prova). Promovê-los
   a caminho primário não se justifica com a esteira bash dietada 10× acima da barra —
   o custo real deles é operacional (parar o daemon = janela de handoff).
5. **Bash fica.** Com três disciplinas já demonstradas no repo: (a) UMA extração/uma
   varredura por operação (nunca N comandos por item), (b) leitura de conf/estado por
   builtin (zero processo), (c) processos persistentes (molde/daemon) em vez de
   exec-por-request. O que resta de jq nos caminhos quentes é candidato a coproc-jq —
   apenas SE a matriz 2× mostrar necessidade.

## Números (dev 5950X 32T/125G; comparações RELATIVAS, mesmo box, seed 42; runs em ~/.cache/moj-bancada/)

### Esteira (rig backlog/esteira)
| cenário | ms/veredicto | veredictos/min | obs |
|---|---|---|---|
| baseline, dreno frio (50/500/2000 de fila) | 60/48/50 | ~1.250 | custo PLANO na profundidade — o O(N²) do glob não domina |
| baseline sob tempestade de forks (32 cores) | 78 | 769 | contenção custa +60% — mas não explica o 20× da prova |
| **dieta** frio | **40** | **1.500** | conf 0-fork no metrics (~30k dos ~35k processos do recompute em massa), sem basename, setverdict 1 jq, hardlink |
| dieta sob tempestade | 66 | 909 | |
| escadaria completa 40→120/min (feed+pull mock) | p50 10 s ESTÁVEL | 1.200/1.200 | CPU do daemon: 93 s em 15 min (~10% de 1 core) |

### Acoplado (rig prova: web dev + pollers retroalimentados + juiz pull)
| run | resultado |
|---|---|
| 1× com q_claim ANTIGO | 1.200/1.200 mas **out≈0 min 1-14**; rajada de ~390/min no dreno final — o colapso de claim reproduzido |
| 1×: tier web | 7.969 reqs, **zero erros**, p.ex. score avg 50 ms, updates 13 ms, summary 31 ms |
| **2× (pico 240/min) com dieta completa** | **2.400/2.400 veredictos, wall = a duração exata da escadaria (ZERO dreno residual); saldo in−out ≈ 0 em TODOS os platôs (ex.: min12 in=237 out=233), fila ≤ 31; CPU do daemon 190 s em 15 min (~21% de 1 core); 7.162 reqs web zero erros (score avg 16 ms)** |

### Spike (decisor do builtin)
| medição | resultado |
|---|---|
| S1 censo do caminho quente | <10 filtros distintos; flags -j/-e/-c/-cn/-R -s/--arg/--argjson — subset viável, mas… |
| S4 coproc-jq round-trip | **34 µs** vs 2.537 µs fork (75×) ⇒ o builtin não paga o próprio custo |

## A dieta aplicada (commits `dieta:`; correção provada pelos smokes)
- `metrics_recompute`: conf lido com ZERO processos + memo do deny (era ~6 execs/chamada
  idênticos p/ todo usuário do contest).
- `judged`: should_hold builtin; next_spool_file sem `basename`; setverdict 5 jq→1;
  write_result com hardlink-oufallback.
- `q_claim`: **1 jq por job** (4 decisões numa extração; GRACEs no bash; semântica 1:1
  provada por teste unitário de cada gate).
- `/judge/result`: read_body_file + 1 extração (eram 5 parses do corpo com o report
  inteiro EM VARIÁVEL); `/judge/heartbeat` 8 jq→1.
- `updates`/`clarifications`: um `cat` com todos os arquivos + `jq -s` (era 2 forks POR
  clarification na rota mais polada do dia).
- `params.sh`: decode com `printf -v` (eram 2 forks POR PARÂMETRO em toda requisição).

## O que NÃO foi feito (backlog ranqueado, com os locais no inventário da sessão)
- `reconcile_stale_pending` fora do funil serial (1 awk global) — Tier 0 restante.
- `review/list`/`conflicts` 1 jq p/ o diretório; `summary` sem 3 globs×id;
  `/contest/history` no porteiro; `auth/status` 8 subshells→1.
- Tier 2 frios (contest-docs, users-bulk, updatescore-heuristic O(users×prob),
  stats-gen first_solver, problem-stats por solver…).
- coproc-jq no molde/daemon — SÓ se a matriz mostrar necessidade.
- py-drains: unit/quadlet + smoke + doc (break-glass de 1ª classe).
- Teste-como-inventário da classe (`fork-per-item.sh`, molde do sem-pacote.sh).

## Deploy
**Nada deste trabalho foi a produção.** A ordem sugerida quando o Ribas aprovar:
dieta (baixo risco, smokes verdes) → observar uma carga real → decidir coproc-jq
com o perfil de produção em mãos.
