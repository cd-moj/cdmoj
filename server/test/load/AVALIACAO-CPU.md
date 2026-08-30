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

## Tetos por ESTÁGIO (medidos, dev, fixtures idênticas)

| estágio | teto medido | custo unitário |
|---|---|---|
| intake (submit→fila), só o daemon | 1.818/min | 33 ms |
| ingest (result→history/metrics), só o daemon | 1.500/min | 40 ms |
| **pipeline serial (intake+ingest no MESMO loop)** | **~820/min** | 73 ms/submissão |
| claim ANTIGO (1 jq/job, rescan por slot) | 1.185/min · fundo 1600: 939 | 50-63 ms/job |
| claim ANTIGO **adversarial** (prefixo de 500 presos por pool) | **30/min** | 1.956 ms/job |
| claim NOVO (lote + sidecar cmeta) | **2.603/min** · fundo 1600: 2.151 | 23-27 ms/job |
| claim NOVO adversarial (500 presos) | **1.001/min** (33×) | 59 ms/job |
| recompute em massa pós-dieta | 2.000 contas em 15,2 s | 7 ms/conta (era 44 na prova) |

## Comparação de LINGUAGENS (mesma fixture, mesmo box, mesmo trabalho)

| implementação | veredictos/min (ingest) | µs/veredicto |
|---|---|---|
| bash em produção 29/08 (pré-dieta, claim-bound) | 40-70 | — |
| bash dietado (hoje) | 1.500 isolado / ~820 no pipeline serial | 40.000 |
| **Python (ingest-drain.py, o que salvou a prova)** | **269.662** | **222** |
| piso físico de I/O (JSON + 4 file-ops, 1 thread) | 770.888 | 78 |
| compilada (Go/Rust/C) — estimativa pelo piso | ~500-770k | ~80-150 |

Leitura honesta: o Python já opera a **35% do piso físico** da arquitetura de arquivos —
acima dele a linguagem DEIXA de importar (o desenho é filesystem-bound; uma compilada
compraria ≤3× sobre o Python). A distância bash→Python (~180×) é o preço do
processo-por-operação, não do algoritmo.

## Análise de COMPLEXIDADE — onde o algoritmo segura (além do fork)

| estágio | estrutura | complexidade | quando dói |
|---|---|---|---|
| escritor ÚNICO (daemon serial) | 1 processo p/ todos os usuários | teto = 1/(t_intake+t_ingest) ≈ 820/min | **o limite ARQUITETURAL de hoje** |
| q_claim antigo | rescan da fila por job reivindicado | O(prefixo-preso)/job ⇒ O(Q²) | fila funda + pool preso — **a Maratona** (consertado: lote + cmeta ⇒ O(Q)/beat, O(1) fork/job pulado) |
| next_spool_file | glob do spool por pick | O(N)/pick ⇒ O(N²) no dreno | só >10k arquivos (glob em RAM é µs) |
| flock ÚNICO da fila | 1 lock p/ claims+enqueues+promotes | serialização global | muitos juízes batendo junto (mitigável: lock POR BANDA) |
| metrics_recompute | 1 jq sobre o history do usuário | O(\|H_u\|) por veredicto | treino (anos de history); em prova é ~50 linhas |
| recompute em massa | por conta | O(U·H̄) | deploy/edição de freeze EM prova (7 ms/conta agora) |
| build do placar | varredura completa de metrics | O(U·P) por build, coalescido 5 s | prova ≥5k contas = ~1 core contínuo só de placar (caminho: build INCREMENTAL — metrics já sabe quem mudou; a ★ global exige recomputar só o mínimo por problema) |
| resolve_submission (summary) | 3 globs `users/*` POR id | O(U·ids)/request | rota de treino com SHOWLOG visível (700k lookups/request @2.355 contas) |
| spool/fila como DIRETÓRIOS | readdir | O(N) por listagem | >50k entradas |

**A escada de folga** (pico Maratona 2026 = 120 subs/min; 2× validado ponta a ponta):

| degrau | teto estimado | folga vs 2026 | custo |
|---|---|---|---|
| hoje (dieta + claim v3) | ~820/min pipeline | **~6,8×** | FEITO (local) |
| + coproc-jq no daemon | ~1.100-1.200/min | ~10× | médio (protocolo/envelope) |
| + **SHARD do daemon por hash(login)** — os dados JÁ são por-usuário; placar/clog já são coalescidos/append-only; escritor único POR USUÁRIO preservado | K×820 (4 shards ≈ 3.300/min) | **~27×** | o próximo passo estrutural honesto em bash |
| daemon em Python (classe ingest-drain) | ≥100k/min | >800× | reescrita + operacional novo |

## A dieta aplicada (commits `dieta:`; correção provada pelos smokes)
- `metrics_recompute`: conf lido com ZERO processos + memo do deny (era ~6 execs/chamada
  idênticos p/ todo usuário do contest).
- `judged`: should_hold builtin; next_spool_file sem `basename`; setverdict 5 jq→1;
  write_result com hardlink-oufallback.
- `q_claim` v3: **claim em LOTE numa varredura + sidecar `.cmeta`** (decisão estática
  gravada na 1ª visita — 1 jq por job NA VIDA; varredura pula preso com ZERO forks) —
  adversarial 30→1.001/min, normal 1.185→2.603/min; gates provados 1:1.
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
