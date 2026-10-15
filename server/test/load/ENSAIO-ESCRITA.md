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

## O que ler no relatório

- **por platô:** envios aceitos/min ≈ a taxa pedida (senão o limite foi o cliente — veja "sem time livre"),
  veredictos/min ≈ envios/min, **inclinação do backlog ≈ 0**, p95 de envio→veredicto estável entre platôs;
- **rotas:** nenhum 5xx; bytes coerentes (200 com 0 byte é falso-verde);
- **servidor:** CPU do judged (% de UM núcleo, os 2 shards somados) e da API, load, judged sem parar (`alive` < 30 s).
