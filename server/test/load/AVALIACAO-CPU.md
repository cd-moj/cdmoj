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
| **4× (pico 480/min) com dieta + q_claim v3** | **4.800/4.800 veredictos, wall 911 s (= o plano + 11 s, ZERO dreno residual); no platô de 480/min: in=477/486 × out=474/478, fila ≤ 90; CPU do daemon 384 s em 15 min (~42% de 1 core — a 59% do teto serial de ~820/min, coerente com o modelo); 7.123 reqs web zero erros (score avg 20 ms, summary 33 ms)** |

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
processo-por-operação, não do algoritmo. **Bench completo com awk/perl/lua/ruby/C/make na
mesma fixture: seção "awk, make e a casinha" abaixo (fontes em `linguagens/`).**

## awk, make e a casinha — o MESMO ingest em 7 linguagens (bench `linguagens/`)

Cada implementação replica o `ingest-drain.py` na MESMA fixture (2.000 results, 300
users), com o harness CONFERINDO o resultado. Duas rodadas, variação <3%:

| implementação | µs/veredicto | veredictos/min | semântica |
|---|---|---|---|
| **C** (gcc -O2, strstr) | **82** | 731.707 | = o piso físico (78 µs) — confirma: filesystem-bound |
| **Lua 5.4** (pattern) | 113 | 528.634 | atômico ✓; parse por pattern; sem listdir (find via popen) |
| **gawk** | **130** | 459.770 | **1,6× MAIS RÁPIDO que o python** — mas SEM rename (grava direto) e parse por regex |
| **ruby** (JSON em C) | 142 | 421.052 | semântica COMPLETA — parser real + rename ✓ |
| python (o drain real) | 213 | 281.690 | semântica completa (a régua) |
| busybox awk | 260 | 230.326 | idem gawk, interpretador 2× mais lento |
| perl (JSON::PP) | 302 | 198.347 | completa; perde porque JSON::PP é puro-perl (JSON::XS ≈ python, não instalado) |
| bash dietado | 40.000 | 1.500 | a esteira de hoje |

**make** (2.000 targets): 1,2 ms/target de fork por recipe (2,4 ms se a recipe tem
metachar ⇒ /bin/sh) ⇒ como "esteira" daria ~50k/min — 33× o bash, 10× pior que gawk. Mas
**115 µs/target no incremental** (nada a fazer): o superpoder do make é DECIDIR o que não
fazer (DAG+stat), não executar trabalho por item.

**A leitura honesta do quadro:**
1. **Todas as linguagens ≥130× o bash.** Acima do python a diferença é ±2-3× e o teto é o
   filesystem (o C EMPATA com o piso físico). A escolha entre elas é semântica e
   manutenção, nunca vazão — qualquer uma drena a fila da Maratona em <1 s.
2. **O que o awk não tem desqualifica o awk como ESCRITOR**: sem `rename()` (atomicidade
   do history — inegociável no escritor único), sem mkdir, sem flock, sem listdir, sem
   base64/JSON de verdade. O ingest.awk só fecha o ciclo com `find` na frente e `xargs mv`
   atrás — um awk-daemon exigiria um shim em C p/ as syscalls, que é o jqb de novo (a
   mesma conclusão: não paga). **awk no lugar certo é TRANSFORMADOR de fluxo de texto** —
   exatamente onde o MOJ já o usa (updatescore, sc_cells, stats-gen, os placares) — e lá
   ele fica.
3. **A "mais legal que python" que fecha semântica completa é ruby (142 µs)** — 1,5× o
   python, mesmo modelo. Lua é a mais rápida das leves e a melhor candidata SE um dia
   houver embutir (lua embarca em C em 200 KB) — mas parse JSON real vira dependência.
   Nada disso muda a decisão: o drain python EXISTE, está provado em prova, e a diferença
   python→X não compra nada que o gargalo real (desenho serial) não domine.

## SAT / pseudo-boolean / PDDL — onde MODELAR pagaria (e onde não)

O problema quente (o claim) formulado como otimização: matching bipartido jobs×slots com
gates booleanos — variáveis x(j,h), at-most-s por juiz, at-most-1 por job, objetivo
lexicográfico banda ≻ FIFO ≻ cache-hit. Instância da Maratona: Q=2.000 × H=24 slots =
48k vars, ~100k cláusulas PB — **qualquer solver moderno resolve em <1 s**. E mesmo assim
NÃO compensa, por três razões que não são de desempenho:

1. **O guloso já realiza o ótimo do objetivo real.** Banda ≻ FIFO é exatamente a varredura
   ordenada; o único termo "otimizável" é o cache-hit, e o valor total dele é minúsculo:
   miss = 1 download de pacote, no MÁXIMO P×H ≈ 13×4 = 52 misses NA PROVA INTEIRA
   (minutos agregados). O COLD_GRACE já captura quase tudo com uma espera limitada.
2. **O problema é ONLINE** (heartbeats a cada ~2 s, chegadas contínuas): a solução ótima
   de um instante está obsoleta no seguinte; garantias offline não transferem, e guloso
   com prioridades é o que a teoria de matching online recomenda para chegadas
   adversariais.
3. **Explicabilidade operacional**: às 14h da prova, "por que o job X não saiu?" precisa
   de resposta em 10 s — posição na fila + 4 gates. Um certificado de otimalidade de
   solver não é resposta.

**Onde modelagem PAGARIA no MOJ** (ranqueado com honestidade):
- **Recalibração em massa** (P||Cmax, juízes heterogêneos, tempos conhecidos das
  calibrações passadas): NP-difícil de verdade, CP-SAT/PB acharia o ótimo p/ 1.400
  problemas × 4 juízes em segundos; LPT guloso já dá 4/3-aprox em 10 linhas de awk.
  Ganho: ~20-30% do makespan de uma noite de recalibração geral — que roda ~2× por ano.
- **Montagem de prova** (seleção ~13 de ~1.400 cobrindo tópicos×dificuldade×autoria):
  set-cover pequeno, PB acha o ótimo E enumera alternativas — ferramenta de AUTORIA
  divertida (casa com eda2-provas/aed1-provas), não infra.
- **Coerência de TL entre linguagens**: conjunto mínimo de TLOVERRIDEs t.q. nenhuma
  solução do autor vira TLE = hitting set minúsculo; hoje heurística + auditoria dão conta.
- **PDDL**: planejamento pede ações com precondições/efeitos e ESCOLHA de ordem; o
  pipeline do MOJ é uma linha reta, e o único fluxo com pré-condições encadeadas (promoção
  de rodada) tem UM plano válido, já codificado. Não há busca a fazer.

**E o shard não tem problema de otimização nenhum**: os dados são independentes por
usuário; qualquer partição balanceada serve e hash uniforme é ótimo em expectativa — não
há o que modelar, é só particionar. Conclusão de professor p/ professor: o gargalo do MOJ
é vazão de I/O serial, não combinatória — as decisões combinatórias ou são rasas (matching
com preferências fracas) ou são raras e offline (recalibração, montagem de prova), e é
NESSAS que SAT/PB entram bem, como ferramenta, quando a vontade bater.

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

**A escada de folga** (pico Maratona 2026 = 120 subs/min; **4× validado ponta a ponta** —
480/min de pico com fila ≤ 90 e daemon a 42% de 1 core):

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
