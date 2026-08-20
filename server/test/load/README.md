# Suíte de carga do MOJ + nota de dimensionamento

Ferramentas p/ medir a capacidade do MOJ sob a carga de um contest grande (ex.: 1500 usuários
× 5h). Antes desta suíte não havia NENHUM dado empírico de dimensionamento no repositório.

## Os dois gargalos e as duas ferramentas

O custo de um contest tem dois eixos independentes:

1. **Vazão de ingestão de veredictos** (o daemon `server/daemons/judged.sh`, serial) —
   `daemon-ingest-bench.sh`.
2. **Vazão do web tier** (nginx → fcgiwrap → handlers bash) sob o polling dos competidores —
   `web-poll-bench.sh`.

### `daemon-ingest-bench.sh <contest-fonte> [M] [modo] [janela]`
Mede quantos veredictos/s o daemon ingere. Rode DENTRO do container da API
(`CONTESTSDIR=/data/contests`, `SERVER_DIR=/opt/moj/cdmoj/server`). Usa uma cópia scratch —
não toca o contest fonte.

```
# dentro do container systemd-moj-api:
/tmp/bench.sh rto_treino12 40 inline      # comportamento PRÉ-H1 (rebuild inline por veredicto)
/tmp/bench.sh rto_treino12 40 coalesced 5 # PÓS-H1 (rebuild coalescido)
```

### `web-poll-bench.sh <base-url> <contest> [clients] [dur_s] [host]`
Simula `clients` competidores virtuais polando o mix público do contest (score+basic) o mais
rápido possível por `dur_s` segundos; reporta throughput e p50/p95/p99. Rode DO HOST do nginx.
Para incluir `/contest/updates` (auth), exporte `MOJ_BENCH_TOKEN`.

```
bash web-poll-bench.sh https://127.0.0.1 rto_treino12 150 8 moj.naquadah.com.br
```

## Números medidos (2026-07, servidor de produção: 62 GB)

> ⚠ Esta seção dizia **18 núcleos**; a máquina de produção tem **32** (Xeon E5-2690 v4,
> conferido em 2026-08-20). Ou a nota nasceu de outra máquina, ou o servidor cresceu depois —
> os números de julho ficam como estão, mas **não os normalize por núcleo** sem remedir.

### Ingestão de veredictos (o gargalo real de 1500 users)
Fixture de 1152 usuários × 13 problemas:

| | veredictos/s |
|---|---|
| **Antes (H1)** — rebuild do placar INLINE por veredicto (build.sh ~0,7s) | **1,4** |
| **Depois (H1)** — rebuild COALESCIDO (`SCORE_COALESCE_S`, 1×/janela) | **~100** |

Um contest de 1500 times gera ~1,2–2,1 veredictos/s em média e picos de 10–50/s. Antes do H1
a entrega travava em ~1,4/s (fila crescia, veredicto demorava minutos); depois folga larga.

## Números medidos (2026-08-20, alvo 2000 times — fixture de 2000 × 12 problemas, 31k submissões)

Levantamento para a prova de 2000+ times. A **demanda** saiu do esquenta de 15/08 (90 times ativos,
`moj.access.log` + `history`/`results`); a **capacidade** foi medida no dia, contra fixture criada e
removida. Relatório completo com a interpolação: veja o artifact de capacidade de 2026-08-20.

| Subsistema | Medida | Leitura |
|---|---|---|
| Web (nginx→fcgiwrap→bash) | **~460 req/s** (461/451/470 com 50/150/300 clientes, 0 erros) | não é o gargalo: 2000 times pedem ~64 req/s de média, ~229 no pico |
| Ingestão de veredicto | **92/s** | folga larga (a prova pede ~1,7/s) |
| Rebuild do placar | **2,85 s** quente · **44,6 s** frio | frio dispara quando o `conf` muda ⇒ **não editar config durante a prova** |
| Placar servido | **168 KB** cru · **11 KB** em gzip (14×) | ⚠ `gzip_types` está COMENTADO no nginx: `text/plain` e JSON saem crus (60 Mbit/s sustentados) |
| `pr_reconcile_balloons` | **427 s** frio · **27 s** por recarga | ⚠ roda SÍNCRONO no `staff/queue`, a tela pola a cada 5–8 s e o `fastcgi_read_timeout` é 300 s |
| Frota de juízes | 12 slots (2 × 6) | a 1ª hora de 2000 times pede **~20** — ver a conta em s-juiz no relatório |

**Perfil temporal do esquenta** (é o que dimensiona o juiz): 591 · 333 · 208 · 148 · 108 submissões
por hora — **43% na 1ª hora**. Dimensionar pela média das 5h subestima o pico em 2,2×.

**Por submissão** (esquenta): mediana 5 s, p90 10 s, p99 21 s, total **7.559 s-juiz** em 1.388
submissões. Cada juiz de 6 slots entrega 21.600 s-juiz/hora ≈ 3.970 submissões/hora.

### ⚠ Use as FASES REAIS, não o esquenta, para dimensionar o juiz

O esquenta teve **15,4 submissões por time**; as duas primeiras fases do ICPC Brasil tiveram
**8,0** (2024: 12.751 subs / 1.462 times · 2025: 10.784 / 1.480 — `Runs.html` do BOCA, descontadas
as de juiz). Dimensionar pelo aquecimento **dobra** a necessidade de frota. O perfil também difere:
o esquenta só tem pico inicial; a fase real é **em U** (2024: 29·19·15·15·22% · 2025: 26·16·15·17·26%)
e o pico absoluto é o **último minuto** (117 e 138 submissões — a corrida do fim).

A 2000 times isso dá 16.000 submissões, e o que decide é o custo de julgar uma:

| s/submissão | hora de pico pede | cabe em 12 slots? | uso médio |
|---|---|---|---|
| 5,5 s | 7,0 slots | sim, folgado | 40% |
| 8 s | 10,3 slots | apertado | 59% |
| 10 s | 12,9 slots | **não** | 74% |
| 15 s | 19,3 slots | **não** | 111% |

**Meça o `duration_s` das soluções oficiais do problem set antes do evento** — é o único parâmetro
que muda a conclusão.

### ⚠ O teto de "460 req/s" era do GERADOR, não da API (corrigido 2026-08-20)

O `web-poll-bench.sh` sobe um `curl` **por requisição**. Num servidor cujo gargalo é criar
processo, isso mede o gerador. Com `stress.sh` (curl `-Z`, processo único) a MESMA API entrega:

| | req/s | erros |
|---|---|---|
| estático (nginx puro) | **7.934** | 0 |
| API trivial | **2.370** | 0 até conc=512 |
| `/contest/history` | 1.361 | 0 |
| `/contest/problems` (cache + gzip pronto) | 1.130 | 0 |
| `/contest/basic` | 950 | 0 |
| `/contest/updates` | 932 | 0 |
| `/contest/score` (144 KB, 2000 times) | 758 | 0 |
| **mistura real de contest** | **~875** | **0 até conc=2048** |

**Estampida** (2000 times × basic+problems+history no mesmo instante = 6.000 requisições):
escoa em **5,5 s**, zero erro, pior requisição individual **0,31 s**.

### ⚠ O limite REAL é de CONEXÕES SIMULTÂNEAS, e só aparece medindo DE FORA (2026-08-20)

Carga gerada de 5 máquinas externas (chococino, cm2/cm3/cm4, hu1) contra a produção, com RTT de
~30 ms — que é o que faz várias requisições ficarem de fato simultâneas no servidor (do localhost
elas terminam rápido demais para se acumular):

| conexões simultâneas (total) | resultado |
|---|---|
| até **480** | **limpo** — ~950 req/s, zero erro |
| 640 | 26% de **502** |
| 1.000 | 58% de 502 |
| 2.000 | 82% de 502 |

O erro é `connect() to unix:…fcgiwrap.sock failed (11: Resource temporarily unavailable)`: a fila
de accept do socket do fcgiwrap enche. **Não é o nginx** (32 workers × 768 conexões = 24k) nem CPU.

O que foi testado e **NÃO** resolve:
- **mais workers de fcgiwrap** (`FCGI_WORKERS=96`): melhora à margem (estampida de 5,8 s p/ 5,3 s,
  pior requisição de 1,03 s p/ 0,61 s) mas o joelho continua no mesmo lugar — o limite é o backlog
  do socket, não o número de filhos. Não vale mudar o padrão;
- **pool persistente do nginx p/ o upstream** (`upstream ... keepalive 64` + `fastcgi_keep_conn on`):
  **PIORA MUITO** — o fcgiwrap 1.1.0 não lida bem com conexão FastCGI reaproveitada; a estampida
  passou de 5 s p/ 190 s com quase tudo falhando. Testado e revertido; não repita.

**O que foi feito** (tudo medido depois):

1. **Backlog do socket de 512 p/ 10.000.** O fcgiwrap abre com 512 fixo (medido: a 545ª conexão
   pendente dá EAGAIN) e não tem opção. O `deploy/moj-entrypoint` passou a criar o socket com o
   backlog desejado e entregá-lo no **fd 0** (convenção do FastCGI). Backlog efetivo medido depois:
   **4.129**. A 2000 conexões simultâneas os erros caíram de 82% para 18%.
   ⚠ **O `listen()` é clampado por `net.core.somaxconn`** (no syscall genérico — vale p/ socket
   unix também), que é **por namespace de rede** e estava em 4096: pedir mais dava 4096 **em
   silêncio**. Por isso o par: `FCGI_BACKLOG` no entrypoint **e** `Sysctl=net.core.somaxconn` no
   `deploy/quadlet/moj-api.container` — os dois números andam juntos, e o entrypoint avisa no log
   quando o pedido é maior que o teto. Medido na imagem de produção: somaxconn 4096 ⇒ **4.097**
   conexões enfileiradas antes do EAGAIN; somaxconn 10000 ⇒ **10.001**. Hoje os dois estão em
   **10.000**, p/ rajada de F5 muito intensa.
2. **Cliente espalha a largada** (até 1,2 s sorteado) e **retenta com espera crescente**
   (`web/contest/contest.js`, `loadContestBody`). Antes, um 502 ali deixava a página parada num
   aviso de erro até o time recarregar à mão.
3. **Cache do LOTE DE BOOT INTEIRO.** Cada rota que toda página de contest pede virou resposta
   cacheada (`resp_cache_fresh`/`resp_cache_store`), com **variante por dimensão de segurança** —
   ver a receita no `cdmoj/CLAUDE.md`. Processos por requisição com o cache quente, medidos com
   `strace -c -e trace=execve` contra o fixture de 2000 times:

   | rota | antes | depois |
   |---|---:|---:|
   | `/contest/problems` (12 problemas) | 89 | **2** |
   | `/contest/rounds` | 20 | **2** |
   | `/contest/navbuttons` | 9 | **2** |
   | `/contest/basic` (contest **com** coortes) | 28 | **3** |
   | `/contest/basic` (sem coortes) | 4 | **2** |
   | `/contest/balloons` | 7 | **1** |

   Os dois maiores ganhos não vieram do cache em si: o `/contest/basic` custava 28 processos
   porque `ch_enabled`/`ch_of`/`ch_view_for_login` se chamam em cascata (hoje `ch_ctx` responde os
   três num jq só), e o `/contest/balloons` chegou a 1 processo ao trocar o teto de idade por ter
   o próprio handler como entrada, e ao substituir o `grep | cut` do `contest_is_secret` — que
   roda em TODA rota pública de contest — por leitura em bash puro (`conf_value`).

### O F5 na contagem regressiva (o comportamento real do aluno)

Um F5 custa **6 chamadas de API** (o navegador serve os estáticos do cache). Medido:

| | F5/s | 2000 times podem apertar F5 a cada |
|---|---|---|
| antes | 107 | 18,8 s |
| depois do cache de rounds | 149 | 13,4 s |
| **depois do cache do lote inteiro** | **175** | **11,4 s** |

Medido em 20/08/2026 contra fixture de 2000 times × 12 problemas **com coortes ligadas** (a
configuração da prova de verdade), enunciados de ~130 KB cada, cliente mandando `Accept-Encoding:
gzip` como o navegador faz. Rota a rota, 30.000 requisições a 100 conexões:

| rota | antes | depois |
|---|---:|---:|
| `/contest/balloons` | 1040 | **1657** req/s |
| `/contest/navbuttons` | 865 | **1223** |
| `/contest/rounds` | 991 | **1055** |
| `/contest/updates` | — | 904 |
| `/contest/basic` | 788 | **840** |
| `/contest/userinfo` (sem cache: é por usuário) | 547 | 527 |

⚠ **O gzip é o que salva o `/contest/problems`**: 1.587.225 bytes crus contra **42.211** com
`Accept-Encoding: gzip` — 38× menos. É o corpo pré-comprimido gravado junto do cache; sem ele o
nginx recomprimiria 1,5 MB por time. Sem gzip o F5 completo cai de 1053 p/ 847 req/s.

Use `stress.sh` para número de capacidade. O `web-poll-bench.sh` continua útil como carga de
"cliente burro", mas o número dele é piso, não teto.

### O nginx do HOST era o teto — e foi corrigido (medido 20/08/2026, de 5 máquinas externas)

Com o backlog em 10.000, a rajada que antes dava 502 passou limpa e o joelho mudou de lugar: o
erro virou **500**, e o `error.log` dizia `768 worker_connections are not enough while connecting
to upstream`. Era o default do Debian — com um agravante: cada requisição proxiada gasta **dois**
descritores (cliente + upstream) e o worker do nginx subia com `LimitNOFILESoft=1024`, ou seja
~512 requisições simultâneas por worker, antes mesmo de encostar nas 768.

Correção aplicada em `/etc/nginx/nginx.conf` (o `conf.d` **não serve**: `worker_connections` mora
no bloco `events`, que é fora do `http`), + `nginx -t && systemctl reload nginx` (gracioso):

```nginx
worker_rlimit_nofile 65535;   # topo do arquivo: cada requisição proxiada gasta 2 fds
events { worker_connections 8192; }
```

Lote de boot completo (6 chamadas por F5), de `cm1..cm4` + `hu1` pela internet, antes × depois:

| conexões simultâneas | requisições | antes | depois |
|---:|---:|---|---|
| 2.000 | 12.000 | 0 erro | **0 erro** |
| 5.000 | 30.000 | 14% de **500** | **0 erro** |
| 10.000 | 30.000 | 17% de **500** | **0 erro** |
| 20.000 | 40.000 | — | **0 erro** |

Vazão agregada estável em ~1.030 req/s em todos — igual à medida no loopback (1.054), então a
rede não é o limite; o que o ajuste comprou foi **não perder requisição na rajada**. Um F5
coletivo de 2000 times chega a ~12.000 simultâneas (o navegador abre 6 em paralelo por site), e
20.000 passam sem um erro. Máquina no fim: load 24, **1 GB de 62 em uso**.

### O que sobrou de mais caro: o `/contest/score`

Com o lote de boot resolvido, a rota mais lenta do caminho quente é o placar — e ela é **29% da
mistura real**. Medido no mesmo fixture de 2000 times:

| | req/s | p50 | pior |
|---|---:|---:|---:|
| 1ª chamada (reconstrói de 2001 `metrics.json`) | — | — | 92,9 s |
| regime permanente, conc=100 | **259** | 0,381 s | 0,525 s |
| regime permanente, conc=300 | 260 | 1,139 s | 1,473 s |
| mistura real completa, conc=100 | **525** | 0,170 s | 1,200 s |

⚠ **O rebuild frio é o número que assusta e o que engana**: os 92,9 s de pior caso são a primeira
chamada depois de tocar o `.score-dirty` com 2001 usuários — o `SCORE_SERVE_FLOOR_S` serve cache
depois disso. Aquecer o placar **antes** de abrir a prova é item de véspera; medir sem aquecer dá
119 req/s e um p99 de 10 s que não representa nada.

Na rede o placar são **174.810 bytes** crus e **15.692** com gzip. A 259 req/s, 2000 times podem
recarregar o placar a cada ~8 s — o poll padrão é mais lento que isso, mas é a folga menor que
sobrou. É o próximo alvo se precisar de mais.

### Hipótese testada e DESCARTADA: os buffers do FastCGI

O `error.log` mostrava `an upstream response is buffered to a temporary file` e o repo não define
`fastcgi_buffers` (default 32 KB), enquanto o `/contest/problems` cru tem 1,5 MB — parecia disco
por requisição. **Não é**: com `Accept-Encoding: gzip` (o que o navegador manda) o corpo tem 42 KB,
a rota faz **1.096 req/s** e o contador de `buffered to a temporary file` fica em **zero**. Os
avisos vinham das medições SEM gzip. Não mexa nos buffers sem antes contar os avisos.

### Onde está o custo por requisição (medido 2026-08-20, 30 conexões, gerador antigo)

| Camada | req/s |
|---|---|
| arquivo estático (só nginx) | **1.654** |
| API trivial (+ fcgiwrap + bash) | **692** |
| rota real (+ conf + jq) | **420** |

O nginx **não** é o gargalo. Sob carga sustentada: `us=43% sy=55% id=3%` com 39–56 processos
prontos para 32 núcleos — **CPU saturada e mais da metade em tempo de KERNEL** (fork/exec). Duas
consequências: **subir os workers de 32 p/ 64 não cria vazão** (só troca de contexto), e o caminho
para ganhar throughput é **menos processos por requisição**, não mais workers.

### Web tier (nginx→fcgiwrap→bash)
`/contest/score` (placar de 1152 users, 41 KB), 200 requests concorrentes:

| | throughput | p50 | p99 |
|---|---|---|---|
| **Antes (H3)** — fcgiwrap `-c 8` | 267 req/s | 347 ms | 539 ms |
| **Depois (H3)** — 32 workers (2×núcleos) | 385 req/s | 211 ms | 257 ms |

Saturação do mix de polling (score+basic), 32 workers: **~430 req/s** (além disso a
concorrência só aumenta a latência, não o throughput). Um contest de **1500 clientes** oferece
**~100–130 req/s** (o competidor ocioso quase não pola — `/contest/history` só repolla
enquanto há submissão pendente) ⇒ ~30% de utilização, **~3,3× de folga**, p99 ~127 ms.

### Outros ganhos
- **H2** — piso de staleness no `/contest/score`: 16 requests concorrentes logo após um
  veredicto iam de **~0,74 s cada** (pileup de rebuild no `flock`) p/ **~33 ms** (serve cache).
- **H4** — `/submission/summary`: lote de 60 ids de **192 ms** (1 jq por id) p/ **8 ms**
  (1 jq sobre N arquivos).

## Veredicto
Com H1–H4 o servidor **aguenta 1500 usuários × 5h** com folga: a ingestão de veredictos deixou
de ser o teto (~1,4→~100/s) e o web tier roda a ~30% sob o polling real. A frota de juízes
(PULL) escala à parte (mais máquinas/slots). Regenere estes números após mudanças no
`build.sh`, no daemon ou no fcgiwrap.
