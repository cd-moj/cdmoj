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

## Números medidos (2026-07, servidor de produção: 18 núcleos, 62 GB)

### Ingestão de veredictos (o gargalo real de 1500 users)
Fixture de 1152 usuários × 13 problemas:

| | veredictos/s |
|---|---|
| **Antes (H1)** — rebuild do placar INLINE por veredicto (build.sh ~0,7s) | **1,4** |
| **Depois (H1)** — rebuild COALESCIDO (`SCORE_COALESCE_S`, 1×/janela) | **~100** |

Um contest de 1500 times gera ~1,2–2,1 veredictos/s em média e picos de 10–50/s. Antes do H1
a entrega travava em ~1,4/s (fila crescia, veredicto demorava minutos); depois folga larga.

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
