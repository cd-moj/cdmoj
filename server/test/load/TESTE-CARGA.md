# TESTE-CARGA — simulação realista de prova grande contra a produção

Runbook completo para repetir o teste de carga de 27/08/2026 (véspera da Maratona): **milhares
de clientes autenticados reais**, com o ritmo real dos clientes web, PDFs de balão renderizando,
pedidos de impressão nascendo e veredictos fluindo — contra a produção **viva**, sem derrubar os
usuários reais. Os quatro scripts `carga-*.sh` desta pasta são os provados naquele teste.

**A régua validada**: 12.000 clientes (10k times + 2k staff) = pico de 428 req/s, zero 5xx,
usuários reais a p95 70 ms. Essa é a barra de comparação de qualquer rodada futura.

---

## O modelo mental (leia antes de rodar)

O teste tem **palco** e **ação**, e confundir os dois foi o erro da primeira tentativa:

- **Palco** (`carga-fixture.sh`): o estado que já existiria no meio da prova — contas, histories,
  metrics, placar, staff com escopo. Pré-fabricado porque construí-lo "ao natural" exigiria
  julgamento real nos juízes de produção.
- **Ação**: os clientes polando (`carga-gerador.sh`) **e o mundo mudando** (`carga-injetor.sh`,
  ~3 veredictos/s = o gesto do judged.sh sem juiz). **Sem o injetor o teste MENTE**: placar nunca
  rebuilda, balões não nascem, caches nunca invalidam — foi o falso-verde da 1ª rodada (a fila
  respondia 51 bytes de lista vazia e parecia rápida).
- **Verificação de conteúdo**: o gerador loga `%{size_download}` — confira os BYTES por rota no
  final (score ≈ 100 KB gzip, PDF ≈ 300 KB, fila ≈ 1,4 KB). Código 200 sozinho não prova nada.

## Pré-requisitos

- ssh sem senha: `moj@moj.naquadah.com.br` (+ `root@` p/ o nginx) e `chococino.naquadah.com.br`.
- **Frota geradora** (LAN atrás da chococino, usuário ribas): cm1-4 = `10.63.1.81-84` (12c),
  gpu2 = `.92` (16c), hu1 = `.85` (48c). ⚠ amd1 (`.87`) falhou 100% em 27/08 — evitar ou
  re-testar antes. A máquina dev (32c) também gera (~1.700 clientes por máquina é tranquilo).
- Um contest **`DEMO=1` + `SECRET=1`** (a trava dos scripts; SECRET p/ ficar fora da home).
  O `zz-carga-2026` (12.001 contas, 12 problemas) provavelmente ainda existe — REUSE: a fixture
  é idempotente. Criar do zero:

```bash
T=$(cat ~/.config/moj/token-treino)   # admin do treino
curl -s -H "Authorization: Bearer $T" -H 'Content-Type: application/json' -X POST \
  https://moj.naquadah.com.br/api/v1/treino/contest-create/create -d '{
  "id":"zz-carga-2026","name":"Carga (teste)","mode":"icpc","secret":true,"demo":true,
  "start":'$(($(date +%s)-7200))',"end":'$(($(date +%s)+14400))',
  "problems":[{"bank_id":"apc#ajude_simplificado","name":"A"}, …12 do banco…]}'
```

## Passo a passo

### 1 · Palco (no servidor, DENTRO do container — ~3 min p/ 2k, ~8 min p/ 10k)

```bash
# os scripts vão por podman cp porque o /tmp do container MORRE a cada make deploy
for f in carga-fixture.sh carga-sessoes.sh carga-injetor.sh; do
  scp server/test/load/$f moj@moj.naquadah.com.br:/tmp/
  ssh moj@moj.naquadah.com.br "podman cp /tmp/$f systemd-moj-api:/tmp/"
done
ssh moj@moj.naquadah.com.br 'podman exec systemd-moj-api bash /tmp/carga-fixture.sh zz-carga-2026 10000 2000'
ssh moj@moj.naquadah.com.br 'podman exec systemd-moj-api bash /tmp/carga-sessoes.sh zz-carga-2026'
```

### 2 · Tokens fatiados para as N máquinas geradoras

```bash
ssh moj@moj.naquadah.com.br 'podman exec systemd-moj-api cat /tmp/carga-tokens-teams.txt' > tk-teams.txt
ssh moj@moj.naquadah.com.br 'podman exec systemd-moj-api cat /tmp/carga-tokens-staff.txt' > tk-staff.txt
split -n l/7 -d tk-teams.txt t7-; split -n l/7 -d tk-staff.txt s7-
scp t7-0* s7-0* server/test/load/carga-gerador.sh chococino.naquadah.com.br:/tmp/
```

### 3 · Disparo (injetor primeiro, depois os geradores)

```bash
# injetor no servidor (dur = janela + folga)
ssh -f moj@moj.naquadah.com.br \
  'podman exec -d systemd-moj-api bash -c "nohup bash /tmp/carga-injetor.sh zz-carga-2026 1100 > /tmp/injetor.out 2>&1 &"'

# frota (⚠ ssh -f, e SEMPRE conferir com pgrep depois — o disparo "travado" costuma ter funcionado)
ssh chococino.naquadah.com.br 'i=0; for ip in 10.63.1.81 10.63.1.82 10.63.1.83 10.63.1.84 10.63.1.92 10.63.1.85; do
  scp -q /tmp/carga-gerador.sh /tmp/t7-0$i /tmp/s7-0$i $ip:/tmp/
  timeout 8 ssh -f -o BatchMode=yes $ip "cd /tmp && rm -f carga.log && setsid nohup bash carga-gerador.sh t7-0$i s7-0$i 900 carga.log > gerador.out 2>&1 < /dev/null"
  i=$((i+1)); done'
# dev local: mesma linha com t7-06/s7-06
```

### 4 · Monitorar (OBRIGATÓRIO — é produção viva)

A cada ~2 min, do access log do nginx (formato tem `rt=` no fim): req/min, códigos ≥400, e —
**o gatilho de aborto** — o p95 dos usuários REAIS (rotas de contests que não são o de carga).
**Se os reais passarem de ~0,5 s: ABORTE** (`pkill -9 -f "carga-gerado[r]"` em cada geradora +
`podman exec systemd-moj-api pkill -f carga-injetor`). Em 27/08 o aborto levou ~2 min e o
servidor voltou ao normal em segundos.

### 5 · Colheita

- **Cliente** (a verdade sobre o que o usuário viu): junte os `carga.log` das máquinas; cada
  linha é `epoch rota código tempo bytes`. p50/p95 por rota + **bytes médios** (a prova de
  conteúdo). Código `000` = a requisição NEM SAIU da máquina geradora (NAT/burst local) — se o
  nginx não a viu, não é problema do servidor.
- **Servidor**: janela no `moj.access.log` (⚠ rotaciona à MEIA-NOITE UTC — dia anterior no `.1`)
  → soma de rt por rota, p95s, códigos; loadavg/vmstat do coletor se estiver rodando
  (`/root/moj-load-collect.sh`).

### 6 · LIMPEZA (não pule)

```bash
ssh moj@moj.naquadah.com.br 'podman exec systemd-moj-api bash -c "rm -f /data/run/sessions/zc*"'
# frota: rm /tmp/{t7,s7}-* carga.log; o contest DEMO pode ficar p/ a próxima rodada
```

## Critérios de aceite (os números de 27/08 como barra)

| métrica | barra |
|---|---|
| usuários reais durante o teste | p95 ≤ 0,1 s (idêntico ao repouso) |
| 5xx / 429 do servidor | **zero** |
| `updates` / `basic` / `problems` | p95 ≤ 50 ms |
| `score` (placar grande, gzip) | p95 ≤ 0,5 s |
| `staff/queue` | p95 ≤ 0,5 s |
| `print-pdf` (magick real) | p50 ~4-5 s, sem arrastar as outras rotas |
| bytes | score ~100 KB · pdf ~300 KB · fila ≥1 KB (lista CHEIA) |

## As armadilhas que já morderam (cada uma custou tempo real)

1. **`noglob` do `common.sh`**: sourceou lib da API? `set +o noglob; shopt -s nullglob` ANTES de
   qualquer glob — senão laços `users/eq-*/` rodam uma vez, em cima da string literal.
2. **`pkill -f <nome>` de dentro de um ssh MATA O PRÓPRIO SSH** (o padrão casa a cmdline
   remota). Sempre `pkill -f "carga-gerado[r]"` (o colchete quebra o auto-casamento).
3. **ssh aninhado com `&` trava** mesmo com nohup/setsid/redirects — use `ssh -f` e confira
   com `pgrep` depois; o disparo que "travou" geralmente funcionou.
4. **Frota em BRT, servidor em UTC** — confira `date -u` antes de concluir que algo travou.
5. **`/tmp` do container morre no `make deploy`** — reenviar scripts e RECRIAR sessões após
   qualquer deploy no meio do preparo.
6. **curl sem `--compressed` não é um navegador**: sem ele o score de 10k linhas sai cru
   (600 KB × N/s satura o LINK, não o servidor) e o teste mede a coisa errada.
7. **rt de ESTÁTICO no nginx = download do cliente**, não CPU — os PNGs do tutorial sempre
   aparecem no topo da soma de rt; ignorar.
8. **Máquina geradora 100% falha** (amd1 em 27/08): sempre conferir falhas POR MÁQUINA antes de
   somar — e uma geradora saturada pode nem responder `pkill` (último recurso: `kill -9 -1`).
9. **O placar de coorte depende de `MOJ_COHORTS` dentro do `sc_users`** — qualquer cache/memo
   novo nessa área precisa da coorte na CHAVE (memo único = times de uma coorte no placar da
   outra).
10. **Saturar o pool ATRASA O JULGAMENTO em ~15 min, mesmo com as rotas de juiz isentas do
    nginx** (visto em 27/08, no teste de 1.000 req/s): a isenção de `limit_conn` não protege do
    POOL fcgiwrap, que é um só — beat com resposta perdida (502) deixa o job órfão em
    `assigned/` até o TTL de 15 min re-enfileirar. Submissão real que cair na janela saturada
    resolve sozinha (reconcile + TTL), mas conte com o atraso — e confira `run/assigned/` e
    `Not Answered` nos histories na colheita, não só o access log.
11. **O teto do servidor é ~350-430 req/s com CPU pela METADE** (64 workers; o custo por
    requisição infla ~3× sob contenção) e **acima do teto não há degradação graciosa**: fila
    mais funda que capacidade×timeout ⇒ goodput vai a ~2-6 resp/s (todo request que um worker
    pega já foi abandonado pelo cliente), backlog do socket transborda em 502. Ofereça no
    máximo o teto; para "testar 1.000 req/s" precisaria de pool maior ou quebra-circuito.

## Histórico que dá contexto

- 27/08/2026: rodada 1 (estática, falso-verde) → rodada 2 com injetor achou o colapso do
  rebuild inline (score p95 12,6 s, pool estacionado) → 4 consertos (`flock -n`+servir velho,
  `sc_users` memo por visão, build do daemon destacado, piso no reconcile de balões) → rodada 3
  na mesma régua: 428 req/s, zero erros. Detalhes: memória do agente
  (`teste-carga-10k-gargalo-placar`) e commits `score: o rebuild sob veredicto…` no cdmoj.
