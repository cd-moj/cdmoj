# ENSAIO DE ESCRITA — o caminho das submissões a 2× o pico esperado, em produção

Preparado em 15/10/2026 para a Maratona de 8/11 (~800 times, 20 sedes com um `.staff` cada). O teste de carga de
27/08 (`TESTE-CARGA.md`) provou só a **leitura**; a crise da prova de 29/08 foi na **escrita** (a esteira do judged
represou 35 min antes de alguém ver). Este ensaio passa submissões **de verdade** por todo o caminho:

```
POST /submit → spool (shard do login) → judged ×2 → fila (banda) → JUÍZES REAIS (/judge/heartbeat)
  → /judge/result → history/metrics → placar e balões → o time vê o veredicto no /contest/history
```

## O desenho (e por que não um juiz simulado)

- **Juízes reais.** O escalonador não tem "juiz dedicado": job sem pool vai a qualquer juiz, e linguagem/cache frio só
  ATRASAM (depois de uma carência o juiz pega como plano B). Um juiz simulado em produção acabaria julgando — com
  veredicto falso — submissões reais de alunos. Com os juízes reais o ensaio também mede o que importa no dia.
- **Problema trivial:** `ribas.admin#teste-juiz` (A+B, 4 testes de milissegundos; soluções em C/C++/Python/Java). Um
  WA custa os mesmos 4 testes. ~55% AC, ~35% WA (soma + 1), ~10% CE (sintaxe quebrada).
- **Banda mais baixa:** o contest nasce `lista-publica` — a última das bandas do escalonador (`super › prova ›
  lista-privada › rejulgar › lista-publica`). Nada sintético passa na frente de prova; na mesma banda, ordem de chegada
  com listas e treino.
- **Contest `DEMO=1` + `SECRET=1`, dono `ribas.admin`** (o problema é privado dele), criado pelo endpoint oficial.
  800 times `eNNtMMM` em 20 sedes (regions.json por regex do login) + `eNN.staff` com escopo `region:Sede NN`.
  Palco VAZIO: as escritas são o teste.
- **Balões:** com o módulo `baloes`, o 1º AC de cada time vira uma TAREFA na fila do staff (o reconcile roda quando a
  fila é carregada — escrita leve, e realista). O **PDF** da folha só nasce no print (`print-pdf`), que o ensaio NÃO
  faz: a renderização das folhas no dia (0,46 s/folha desde 03/10) fica fora desta medida.
- **Cliente com o ritmo da tela:** `/contest/updates` a cada 30 s, `/contest/score` a cada 45 s em metade dos times,
  `/contest/history` a cada 5 s enquanto há envio pendente, `/contest/staff/queue` a cada 15 s por sede.

Diferenças do dia real (não mudam a vazão do escritor; diga no relatório): 1 problema em vez de 12 (placar O(U·P)
menor — a leitura de 12 problemas já foi provada em 27/08) e banda `lista-publica` (teto de 3 pendentes por time;
a prova real é `prova`, sem teto e com deprio depois de 5).

## O plano (escadaria)

`30:5,60:5,90:5,125:10,180:5,250:3` (subs/min : minutos) ≈ **3.800 envios em 33 min** + o dreno — a janela
precisa de **~50 min** de ponta a ponta (fixture, plano, dreno, limpeza). O platô de
**125/min** é a régua (2× o pico esperado de ~62/min p/ 800 times, tirado de 29/08: 1.550 times, pico 120/min);
180 e 250 mostram a folga. Critério da bancada: no platô, **backlog (spool + fila) com inclinação ≈ 0** ⇒ o servidor
acompanha; inclinação > 0 sustentada ⇒ aquela taxa passa da capacidade.

## Salvaguardas antes de começar

1. **Janela combinada com o Ribas.** Nunca entre 01:30 e 02:30 BRT (o disco da VM trava ~05:00 UTC e falsearia a
   medida). Rodar o scan de contests no ar (nenhuma prova curta no ar nem começando em 2 h).
2. Os juízes reais vão ficar ocupados por minutos nos platôs altos: um aluno que enviar nesse momento espera alguns
   segundos a mais. É o único efeito em usuário real.
3. Abortar a qualquer momento: `pkill -f ensaio-injetor.py` (no dev) e a limpeza com `--purge` (abaixo).

## Passo a passo

Variáveis: `C=zz-ensaio-800`, servidor `root@moj.mdp.naquadah.com.br`, container `systemd-moj-api` (podman do usuário
`moj`: `sudo -u moj XDG_RUNTIME_DIR=/run/user/$(id -u moj) podman …`). Os scripts entram no servidor **pelo git** (são
do repositório) e vão ao container por `podman cp` — nunca `bash -s < script` (ver a armadilha no topo do
`ensaio-limpeza.sh`).

```bash
# 0. servidor: código em dia (git pull) e os scripts p/ dentro do container; diretório dos tokens FECHADO
#    (são credenciais vivas de ~820 contas sintéticas num contest secreto)
mkdir -p /root/ensaio && chmod 700 /root/ensaio
cd /home/moj/moj/cdmoj && sudo -u moj git pull --ff-only
for f in ensaio-fixture.sh ensaio-limpeza.sh; do podman cp server/test/load/$f systemd-moj-api:/tmp/; done

# 0½. FUMAÇA (antes da janela, ~2 min): os ramos que o ensaio a seco NÃO cobre — problema PRIVADO (o criador tem de
#     ser o dono), a sessão temporária do ribas.admin, banda lista-publica e um envio REAL indo a um juiz e voltando AC
podman exec systemd-moj-api bash /tmp/ensaio-fixture.sh zz-ensaio-fumaca 3 1
#   (no dev) injetor com --plan "6:1" --drain 120 contra https://zz-ensaio-fumaca.moj.naquadah.com.br → 6 envios, todos
#   com veredicto; depois: podman exec systemd-moj-api bash /tmp/ensaio-limpeza.sh zz-ensaio-fumaca

# 1. palco (~1 min p/ 800 times): contest + times + staff + sessões; tokens em /tmp do container
podman exec systemd-moj-api bash /tmp/ensaio-fixture.sh zz-ensaio-800 800 20
# o podman do usuário moj NÃO escreve no /root/ensaio (700 do root): copiar via temporário do moj e mover como root
for t in times staff; do f=$(sudo -u moj mktemp /tmp/ensaio-tok.XXXXXX)
  podman cp systemd-moj-api:/tmp/ensaio-tokens-$t.txt "$f" && mv "$f" /root/ensaio/ensaio-tokens-$t.txt; done
chown root:root /root/ensaio/*; chmod 600 /root/ensaio/*
# ESPERE ~2 min: a criação do contest dispara trabalho de fundo (na fumaça de 15/10: ~40 s com a API em ~170% de um
# núcleo). Só comece o plano com a linha de base da sonda de volta a ~15–20% (API) e 0% (judged).
# (no dev) scp root@…:/root/ensaio/ensaio-tokens-*.txt <scratchpad>/ensaio/   — credenciais SÓ das contas sintéticas

# 2. sonda no host (root), 10 s, até 70 min
nohup bash /home/moj/moj/cdmoj/server/test/load/ensaio-sonda.sh /root/ensaio/sonda.tsv 10 4200 zz-ensaio-800 >/dev/null 2>&1 &

# 3. injetor (no dev; ~40 req/s de poll + os envios do plano)
python3 server/test/load/ensaio-injetor.py --base https://zz-ensaio-800.moj.naquadah.com.br --contest zz-ensaio-800 \
  --times ensaio-tokens-times.txt --staff ensaio-tokens-staff.txt --sols <dir com sol.{c,cpp,py,java}> \
  --out run1/ --plan "30:5,60:5,90:5,125:10,180:5,250:3" --drain 900

# 4. relatório: trazer a sonda e juntar
scp root@…:/root/ensaio/sonda.tsv run1/ && python3 server/test/load/ensaio-relatorio.py run1/

# 5. limpeza (servidor): para se ainda houver job do ensaio em voo; --purge só em ensaio abortado
pkill -f ensaio-sonda.sh; podman exec systemd-moj-api bash /tmp/ensaio-limpeza.sh zz-ensaio-800
rm -rf /root/ensaio; podman exec systemd-moj-api rm -f /tmp/ensaio-*   # e os tokens no dev
```

As soluções de referência saem do pacote: `moj-problems/ribas.admin/teste-juiz/sols/good/sol.{c,cpp,java,py}`.

## Ensaio a seco (local)

Antes do ensaio real, o mesmo encadeamento roda todo local (fixture em mktemp, ponte HTTP→router, judged ×2, o juiz
simulado da bancada — aqui seguro: não há job real p/ roubar —, sonda, injetor comprimido com `--minute 6`). Prova os
scripts; os números não valem (outra máquina, sem inotify). Em 15/10/2026: 249/249 veredictos, 0 erro.

## Fumaça em produção (15/10/2026, 18:44 BRT)

`zz-ensaio-fumaca 3 1` + 6 envios: os ramos de produção passaram (problema privado com o dono `ribas.admin`, sessão
temporária apagada, banda `lista-publica`, sedes/balões); **6/6 veredictos dos juízes reais** (5 AC, 1 WA, como pedido),
envio→veredicto p50 5,6 s (com o poll de 5 s), 0 5xx; a sonda coletou (cgroups, nginx incremental, balões); a limpeza
deixou zero sessão/job. Linha de base parada: API 15–18% de um núcleo, judged 0%.

## Resultado do ensaio de 800 times (15/10/2026, 18:54–19:30 BRT)

3.800 envios em 33 min: **3.800 aceitos, 3.800 veredictos, 0 erro, 0 5xx**. Os 81 slots dos juízes estavam
disponíveis e o servidor tinha `JUDGED_SHARDS=2`.

| platô (subs/min) | veredictos/min | envio→veredicto p95* | backlog máx | judged % | API % | load máx |
|---|---|---|---|---|---|---|
| 30 | 29 | 10,5 s | 2 | 15 | 59 | 0,83 |
| 60 | 59 | 10,4 s | 5 | 26 | 74 | 0,91 |
| 90 | 89 | 10,5 s | 9 | 36 | 103 | 1,56 |
| **125** (2× o pico) | **124** | **10,5 s** | 12 | **49** | 131 | 2,41 |
| 180 | 178 | 15,4 s | 25 | 64 | 180 | 2,45 |
| 250 | 238 | 20,5 s | 50 (+1,1/min) | 86 | 270 | 2,16 |

\* O tempo foi visto pelo cliente, que consulta a cada 5 s. O veredicto real sai de 0 a 5 s antes. As colunas
da sonda já estão corrigidas para a diferença de relógio (o dev estava 24 s à frente do servidor; o
`ensaio-relatorio.py` a mede pelo `epoch` de cada envio).

- **O escritor sobra.** O judged chegou a no máximo 132% de um núcleo (soma dos 2 shards), mesmo a 250/min.
  Não é preciso aumentar `JUDGED_SHARDS` para 800 times.
- **Os juízes são o primeiro recurso a apertar.** Até 180/min o backlog fica estável. A 250/min os slots livres
  caíram a 12, a vazão parou em 238/min e o backlog cresce (+1,1/min). Na virada do degrau, 12 envios esperaram
  ~45 s. Esta medida usa o problema trivial: com os problemas reais (mais testes, TL maior), cada envio ocupa o
  slot por mais tempo. A folga dos juízes no dia sai da calibração da prova, não deste número.
- **Achado — o 1º build do placar estaciona o pool.** No segundo zero, ~120 `/contest/score` pediram um placar
  que ainda não existia. O `regen_locked` só espera (`flock -w 20`) quando o cache é inexistente. O build a frio
  (recompute dos metrics de 820 contas + placar) levou ~11 s. Enquanto isso, os workers do fcgiwrap ficaram
  presos no lock, e **todas** as rotas bash esperaram junto: submit 4,3 s, history 4,9 s e staff/queue 4,2 s
  (log do nginx: `urt` do fcgiwrap = `rt`). Isso não ocorre quando o placar já existe antes do início. A
  promoção de rodada o monta (`rd_promote`), e o placar aberto por um admin ou juiz também. Contest novo, sem
  rodada e que ninguém da organização abriu passa por isso no início da prova.
- **staff/queue cresce com as tarefas de balão.** O p95 subiu de ~0,5 s (14 tarefas) para ~1,5 s (746 tarefas,
  API a 266%). Com veredicto a todo segundo, o reconcile está sempre devido, e o porteiro declina p/ o bash.
  Com 12 problemas, o dia terá alguns milhares de tarefas.
- **2 TLE espúrios em Java (2 de 354 envios Java), os dois no host `judge` e no platô de 180/min.** O TL de Java
  deste problema trivial é 0,1955 s, que é quase só a partida da JVM. Com o host cheio, cada teste levou de 0,17 a
  0,21 s, e o `TLERERUN` repetiu e confirmou. Num problema com TL de segundos, ~50 ms a mais não mudam nada. Num
  problema cujo TL de Java fique perto da partida da JVM (abaixo de ~0,5 s), o mesmo pode acontecer no dia.

**Consertos (15/10/2026, mesma noite):** o placar a frio passou a recalcular as métricas num jq só (821 contas:
6,5 s → 0,24 s), e só quando freeze ou penalidade mudam. O placar completo é montado antes da largada
(`score_build_bg`). A fila do staff relê só as tarefas que mudaram (porteiro: 4.470 tarefas, 72 → 11 ms). E o
reconcile de balão saiu da consulta e roda em lote (60 balões novos: 2,65 s → 0,43 s). Detalhes no `CLAUDE.md` do
cdmoj (store por-usuário, PORTEIRO, Balão, Placar pré-início).

**2º ensaio, depois do deploy dos consertos (15–16/10/2026, 23:41–00:15 BRT, mesmo plano):** 3.800/3.800, 0 erro, 0 5xx.

| | 1º ensaio | 2º ensaio |
|---|---|---|
| arranque: placar / submit / history (máx) | 11,6 s / 4,3 s / 4,9 s | 0,61 s / 0,21 s / 0,03 s |
| placar p95 / máx (toda a carga) | 148 ms / 11,7 s | 152 ms / 1,0 s |
| fila do staff p95 / máx | 758 ms / 4,2 s | 197 ms / 0,55 s |
| envio→veredicto p50 / p95 (geral) | 10,4 s / 15,5 s | 5,4 s / 10,4 s |
| 250/min: veredictos/min, backlog máx | 238, 50 | 249, 15 |
| CPU máx: judged / API | 132% / 348% | 103% / 242% |

O placar completo já existia quando o injetor começou. O 2º ensaio foi à meia-noite, com menos tráfego real do que
o 1º (19h): parte do ganho no envio→veredicto pode vir disso. De novo houve TLE em Java (2 envios AC e 2 WA): o TL
de Java do problema trivial é ~a partida da JVM.

Limites desta medida: 1 problema, banda `lista-publica` e PDF de balão não impresso. Todo o tráfego veio de
um IP só (o dev).

## O que ler no relatório

- **por platô:** envios aceitos/min ≈ a taxa pedida (senão o limite foi o cliente — veja "sem time livre"),
  veredictos/min ≈ envios/min, **inclinação do backlog ≈ 0**, p95 de envio→veredicto estável entre platôs;
- **rotas:** nenhum 5xx; bytes coerentes (200 com 0 byte é falso-verde);
- **servidor:** CPU do judged (% de UM núcleo, os 2 shards somados) e da API, load, judged sem parar (`alive` < 30 s).
