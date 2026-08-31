# MOJ — Placares multi-modo

Princípio: **adicionar um modo = 1 gerador (`server/score/updatescore-<modo>.sh`) + 1 renderizador
(`web/contest/score/score-<modo>.js`)**, ligados pela mesma string de modo.

## Fluxo

1. O `conf` do contest define `CONTEST_TYPE` (`icpc` | `obi` | `treino` | `heuristic` | `outro`;
   `lista-publica`/`lista-privada` → `treino`; ausente → `icpc`).
2. **A fonte de dados dos geradores é `users/<login>/metrics.json`** (mantido incremental
   pelo daemon a cada veredicto via `metrics_recompute`): cada metrics carrega, por problema,
   `counted` (tentativas até o 1º AC — quais verdicts contam obedece o `PENALTY_VERDICTS`
   do conf; ver modo `icpc` abaixo), `first_ac_epoch`, `pending`, `best_score` (NNp),
   `heur` (Score/Score Ajustado) e a visão **`frozen`** (pré-`FREEZE_TIME`). Os geradores
   leem tudo numa passada só (`sc_cells` em `score-common.sh`: `find users -name
   metrics.json | xargs jq`) — rebuild O(usuários), sem varrer history.
3. `server/score/build.sh <contest>` recomputa os metrics em massa se o `conf` mudou desde
   o último build (`var/.metrics-stamp` — cobre edição de `FREEZE_TIME` e o 1º build de um
   contest importado), despacha para `updatescore-<modo>.sh` e grava
   `contests/<contest>/var/placar.txt` (atômico; `var/placar-full.txt` = sem freeze, p/
   privilegiados). É chamado pelo daemon após cada veredicto.
   Grava também um **`.gz` ao lado de cada placar**: 175 KB por requisição no corpo mais servido
   do dia, e sem isso o nginx recomprime o MESMO conteúdo a cada uma (7% da vazão da rota). O
   `.gz` é escrito DEPOIS do `.txt`; a rota só o usa quando ele **não é mais velho** que o `.txt`
   (build que falhou no meio não pode servir placar de outro instante) e nunca no recorte por
   sede, que filtra linhas.
4. A rota `GET /api/v1/contest/score?contest=<c>` serve esse TXT cru e diz, no cabeçalho
   **`X-MOJ-Frozen: 0|1`**, se o placar entregue está congelado. Quem decide é o SERVIDOR: só ele
   sabe qual dos dois arquivos escolheu para ESTE login — juiz, `.animeitor` e `SCORE_FULL_USERS`
   recebem 0. A página do placar liga o aviso `#freezeNotice` por esse cabeçalho; sem ele o
   competidor lê um placar parado nos últimos 60 minutos achando que é o placar de verdade.
   Cache preguiçoso:
   se o `placar.txt` está velho (`var/.score-dirty` — tocado a cada escrita de history — ou
   `conf` mais novos) ou nunca foi gerado, a rota chama `build.sh` na hora (sob `flock`, sem
   estampida) e então serve. Assim contests importados deixam de ficar com placar vazio.
5. O front (`web/contest/score/`) lê a **1ª linha = modo** e despacha para o renderizador.

### Pré-início: a VITRINE (`var/placar-prestart.txt`)

**REGRA: o placar nunca revela a quantidade de problemas antes de a competição começar.**
Antes do `CONTEST_START`, quem não é `is_judge` (`.admin`/`.judge`/`.cjudge`) recebe a
**vitrine**: o mesmo TXT, mas com **zero colunas de problema** — só os times (bandeira, sigla,
nome, totais 0), na visão **pública** das coortes (convidado oculto continua oculto). Gerada
por `build.sh <c> --prestart` (`MOJ_PRESTART=1` zera as tuplas de problema no `sc_load`, então
vale p/ todos os modos), servida pelo mesmo cache preguiçoso do handler. O front mostra o aviso
"ainda não começou" + contagem regressiva e, no start, busca o placar de verdade. O corte é da
**API** (o cabeçalho com os short names nunca sai do servidor antes da hora); pela mesma regra,
`/index/contests` emite `problems_count:0` p/ contest `upcoming`.

## Formato do TXT

```
icpc                                                  ← linha 1: o modo (bare)
desc:asc:flag:username:univ short:team name:univ full:A:B:C:D:Total:Penalty:LastAC   ← cabeçalho
BR:br-df-alfa:UNB:ALFA:Universidade de Brasília:1/30:2/40:1/55::3/68::4:213:68
```

- Campos separados por `:`. **O placar já vem ordenado** — o front só renderiza na ordem.
- **A linha 1 (modo) pode trazer FLAGS** depois do nome do modo. Hoje só existe a **`s`** do
  ICPC (`icpc s`, 2026-08-30): a célula resolvida carrega o tempo em **SEGUNDOS** desde o
  início, e o cliente **exibe** `floor(seg/60)` — o placar renderizado é o mesmo de sempre; o
  segundo exato serve p/ recalcular a estrela de first-to-solve DENTRO de um recorte de filtro
  sem empate artificial de minuto. TXT **sem** a flag (placares arquivados de rodadas antigas)
  continua sendo lido como minutos — todo parser trata os dois.
- O cabeçalho pode começar com colunas-marcador `desc`/`asc` (campos de ordenação já aplicados):
  **o renderizador deve descartar TODAS as colunas iniciais cujo valor seja `desc` ou `asc`.**
- Colunas: `flag` (ISO), `username`, `univ short`, `team name`, `univ full` (as de univ são opcionais),
  uma coluna por problema (na ordem dos short names), `Total`; no modo `icpc` também
  **`Penalty`** (soma das penalidades, coluna VISÍVEL) e **`LastAC`** (minuto de prova do
  último problema resolvido — coluna de SISTEMA: a UI usa p/ detectar empate exato, não exibe).

### Células por modo
| Modo | Célula de problema | Ordenação | Cor |
|---|---|---|---|
| `icpc` | vazio=não tentou · `tentativas/tempo`=resolveu (tempo em SEGUNDOS com a flag `s` na linha 1, exibido em minutos; em minutos no legado) · `tentativas/tempo*`=**first to solve** (★ + contorno; menor `first_ac_epoch` do problema entre os times do placar, na mesma visão frozen/full) · `tentativas/-`=tentou | **1º** acertos↓ · **2º** penalidade↑ (penalidade=(tent−1)·`PENALTY_MINUTES`+minuto; default 20 — SEMPRE em minutos ICPC, mesmo com célula em segundos) · **3º** minuto do ÚLTIMO problema resolvido↑ (`LastAC`) | ver **Balão × visibilidade** abaixo |
| `obi` | pontos (0–100) | Total↓ | — |
| `treino` | resolvidos / tentativas | resolvidos↓ | — |
| `heuristic` | melhor Score | Score↓ (Score Ajustado como desempate) | — |
| `outro` | colunas 100% personalizadas (cabeçalho traz os nomes reais) | já ordenado | se houver coluna `flag`, mostra bandeira |

**Penalidade configurável (modo `icpc`)** — duas vars de conf, editáveis pelo
`/contest/admin/settings` (mudar em prova recomputa o placar no próximo GET):
- `PENALTY_MINUTES` (default 20): minutos somados por tentativa que conta antes do AC.
- `PENALTY_VERDICTS` (códigos `wa tle mle rte ce`; default `wa tle mle rte`): quais verdicts
  entram no `counted` do metrics. **Judge Error/No_Servers e provisórios nunca contam**;
  strings legadas fora do vocabulário canônico continuam contando (comportamento histórico).
  Lista vazia (`PENALTY_VERDICTS=''`) = nenhum verdict penaliza (só o minuto do AC).

## Coortes: times oficiais × CONVIDADOS (extra-oficiais / "CCL")

Maratona convida times que competem na mesma prova sem entrar na disputa oficial. Eles **não
podem aparecer no placar público** e os times regulares não podem nem saber que existem; os
próprios convidados **veem todos**. Depois que a organização **libera os resultados**, todos
aparecem juntos. Isso é uma **coorte com política**, não um caso especial no código.

`contests/<c>/cohorts.json` (ausente = comportamento clássico, custo zero):

```json
{ "version": 1, "results_released": false,
  "cohorts": [
    {"id":"oficial","name":"Oficiais","default":true,"public":true},
    {"id":"ccl","name":"Café com Leite","regex":"ccl","public":false,
     "unranked":true,"sees":["oficial","ccl"]} ] }
```

| campo | efeito |
|---|---|
| `regex` | casa o **login** (case-insensitive). `.team.cohort` no `account.json` **vence** o regex; sem os dois, o time cai na coorte `default` |
| `public` | `false` = não entra no placar que todo mundo vê |
| `unranked` | aparece **intercalado** pelo desempenho mas **não consome posição oficial** (convenção ICPC para time extra-oficial) |
| `sees` | as coortes que um membro desta enxerga (default: as públicas + ela mesma) |
| `ranking` | `true` numa coorte **pública** dá a ela um **placar PRÓPRIO** (`var/placar-view-<id>.txt`), que vira uma opção do seletor — é assim que *times* × *individual* da inscrição aparecem separados. `?view=<id>` dessa coorte é aceito de qualquer um (`ch_is_ranking_view`) e mostra **só ela** |
| `results_released` | o "liberamos tudo": todos passam a ver todos e o placar público vira o combinado |

**VISÕES são derivadas, não configuradas**: a pública (as `public:true`), uma por coorte privada
(o `sees` dela) e a completa (`all`, para privilegiado e pós-liberação). `build.sh` gera **um par
de placares por visão** — `var/placar[-full].txt` continua sendo a pública e cada visão extra vira
`var/placar-view-<id>[-full].txt`. `/contest/score` escolhe pelo login (`?view=oficial` força a
pública; `?view=geral` só vale para quem já pode ver tudo).

**Por que o corte sobe até `sc_users` e não fica no TXT pronto:** no TXT a **posição é a ordem das
linhas**, então filtrar linhas daria posição correta de graça — mas a **estrela de first-to-solve**
é um mínimo global sobre a saída de `sc_users`. Cortando só no TXT, o placar público exibiria a
estrela de um problema que, para ele, ninguém resolveu primeiro. `MOJ_COHORTS="<id> …"` é o
filtro (vazio = todas) e `MOJ_UNRANKED="<id> …"` liga a coluna `guest`.

## A estrela de first-to-solve só pinta com CERTEZA

O `*` da célula (ICPC) marca quem resolveu o problema primeiro. Até 25/08/2026 ele era o **mínimo
puro** dos `first_ac_epoch` conhecidos, e não olhava run pendente — então **nascia errado e
migrava**: o time A submete no minuto 10 e a run fica na fila; o B submete no 12, é julgado antes,
e a estrela aparecia nele; quando o AC do A chegava, ela pulava para o A. O placar se autocorrige
(é repintado a cada build), mas para quem está olhando é confusão pura.

Hoje `updatescore-icpc.sh` calcula, no MESMO laço, `PENDMIN[prob]` = a run **não julgada** mais
antiga do problema entre os times da visão, e **retira a estrela do problema inteiro** enquanto
`PENDMIN <= FTSMIN`. Ela passa a aparecer **uma vez, no time certo**. O dado vem do
`pending_min_epoch` do `metrics.json` (10ª coluna do `sc_cells`), que tem TRÊS estados: `N>0`
epoch real · `0` campo presente e nulo (na visão **congelada** isso é comum e legítimo: pendente
pós-freeze não pode roubar estrela pré-freeze) · `-1` campo ausente (metrics anterior ao campo)
⇒ desconhecido, e aí o placar é conservador. Para não haver janela sem estrela depois de um
deploy, o `build.sh` recomputa o metrics em massa quando a `lib/users.sh` é mais nova que o
`var/.metrics-stamp` — a mesma receita do cache de impressão, que usa o `${BASH_SOURCE[0]}`.

O **balão** faz a mesma pergunta, mas por SEDE e com uma diferença que manda no desenho: ele é
FÍSICO. Ver `first_site` em `docs/API.md` (`/contest/staff/queue`). Teste: `smoke-score-fts.sh`.

**A coluna `guest`** (só existe quando a visão tem coorte `unranked`) é a última do TXT, com `1`
para convidado. Os renderizadores acham coluna por NOME no cabeçalho, então quem não a conhece
simplesmente a ignora; o front usa para pular a numeração e marcar a linha.

**A BARRA DE FILTROS é a mesma no placar ao vivo e no relatório** (coorte · bandeira ·
universidade · sede · busca · contador · limpar): mesmos rótulos, mesmos `id`
(`fView`/`fFlag`/`fUniv`/`fRegion`/`fQ`/`fCount`) e o mesmo CSS (`.fbar` em `web/shared/ui.css`,
que o relatório inlina). Ao vivo ela é montada por `renderFilters()` (`web/contest/score/score.js`)
com as opções dos times PRESENTES no placar exibido; a sede vem da árvore do `regions.json` mais
as sedes que aparecem no placar. Trocar de coorte é o único controle que fala com o servidor
(`?view=`); os outros recortam linhas no cliente e **RENUMERAM o recorte** (R1, 2026-08-30 —
revoga o "nunca renumera" que valeu até a Maratona): com QUALQUER filtro ativo
(bandeira/universidade/sede/busca) o número grande da coluna `#` vira a **posição no recorte**
e o `.plg` mostra a posição no placar completo; a dupla coorte×geral (`genPlace`) só aparece
SEM filtro — nunca três números. No ICPC a **★ vira a do recorte** (menor tempo de AC entre os
times visíveis, em SEGUNDOS pela flag `s` — exata; no TXT legado a precisão é o minuto e um
empate pode dar mais de uma ★, deliberado) e o contador avisa ("· ★ = 1º do recorte"). Quem diz
que há filtro ativo é o contador ("Mostrando N de M times").
`/contest/score/?c=<c>&view=<coorte>` abre direto num placar paralelo (link compartilhável). ⚠ O casamento é **estrito**: quem não tem o dado não
casa — o `t._country !== undefined` de antes fazia time sem bandeira aparecer em QUALQUER filtro
de bandeira. **A bandeira é HIERÁRQUICA** (2026-08-30): o seletor lista o PAÍS e, indentados, os
estados usados; selecionar o país casa por prefixo (`br` pega `br` E `br-*` — na Maratona 2026 só
14 de 1500+ times tinham `br` cru, o resto declarou estado) e o estado segue exato. Mesma regra
no relatório (`data-country`/`data-cname` na `<tr>`) e no `by_country` das estatísticas (prefixo).

**No relatório offline as visões viram um seletor**: `report-gen.sh` publica **um placar por
visão** (`rep_score_boards`, uma `<section class="board-view" data-view="…">` por TXT, a primeira
visível) e o `<select>` só troca qual aparece — pelo mesmo motivo do parágrafo acima, o script
NÃO filtra linhas do placar geral para fabricar um placar de coorte. Decisão do produto: entram
**todas** as visões (inclusive `all` e coorte privada, sem esperar `results_released`), porque o
relatório é privilegiado e só o admin o baixa; placares de conteúdo idêntico são deduplicados
(quando toda coorte é pública, `public` == `all`) e a ordem do seletor é pública › placares
paralelos › todos › visão de coorte privada. Em placar de coorte a coluna `#` leva **duas**
posições — a da coorte (grande) e a do **placar geral** (menor, cinza, `.plg`) —, e ela só
aparece quando informa algo (na visão cuja classificação é a do geral, não). **O placar ao vivo faz
o mesmo**: ao entrar num placar paralelo ele busca TAMBÉM o placar geral (`fetchGenPlace`, um GET
a mais só nesse caso) e mostra as duas posições; se as classificações coincidem, o segundo número
não aparece.

**No relatório o filtro renumera como ao vivo** (R1/R6, 2026-08-30): cada `<tr>` leva
`data-place` (posição original; vazio = convidado) e `data-tie` (chave de empate), cada célula
resolvida leva `data-sec` (segundos exatos, da flag `s` do TXT) — o script inline renumera os
visíveis, esconde a ★ global (classe `gfts`, via `flt` na section) e pinta a ★ do recorte
(`rfts`), tudo restaurado ao limpar. **Fotos**: miniaturas em `fotos/<login>.webp` (arquivos
relativos — nunca data:URI por linha, incidente dos 21MB) e o 📷 só no placar ABERTO
(`score-frozen.html` sai sem). **Estatísticas** ganham selects Sede×País sobre os recortes
`by_region`/`by_country` que o `stats-gen.sh` já embute no cache — o de Sede com a MESMA
árvore do placar (`regions.json`, ordem e indentação; nós de cima agregados por regex no
gerador), no relatório via `RTREE` embutido.
**A barra do placar ao vivo não é reconstruída à toa** (2026-08-30): o poll de 30-60s
remontava a barra a cada ciclo e fechava o dropdown aberto — hoje a barra nova é montada
num contêiner avulso e comparada (innerHTML) com a da tela; igual ⇒ só re-sincroniza os
values, mudou com o usuário interagindo ⇒ adia p/ o próximo ciclo (`renderFilters`,
`filtersSig` em `score.js`).

### Balão × visibilidade (a célula "resolveu")

**Regra: a cor do balão é adorno; "resolvido" nunca pode depender dela.** A paleta ICPC dá
`A = FFFFFF` e a API a devolve **sempre** (o `balloons.json` só sobrepõe chaves) — branco sobre o
fundo branco do placar é **o mesmo pixel** (1,00:1), então quem resolvia o A parecia não ter
resolvido. Não era exceção: **5 das 15 cores padrão** ficam abaixo de 3:1 (branco 1,00 · amarelo
1,07 · azul-claro 1,25 · limão 1,37 · prata 1,82), e o amarelo dá **1,05 contra a célula de erro** —
quem RESOLVIA parecia ter feito menos que quem ERROU.

O admin escolhe como a célula se pinta (`SCORE_BALLOON_STYLE` no conf; `balloon_style` no
settings e no `/contest/basic`), e vale para o **placar ao vivo, a cerimônia e o relatório**:

| Modo | Célula resolvida |
|---|---|
| **`icon`** (padrão) | fundo neutro igual p/ todos + **ponto da cor** (`.bdot`) ao lado do número. "Resolvido" deixa de depender de enxergar cor |
| `fill` | o clássico: fundo com a cor do balão + **contorno** derivado (`balloonEdge`) — cor clara deixa de sumir |

O **contorno** é a própria cor escurecida até cruzar **3:1** contra o branco (WCAG 1.4.11) —
`FFFFFF→8A8A8A`; cor já escura não muda (`000000→000000`). Fator fixo não serve: o limão parava
em 2,29:1. Fonte única em `web/contest/score/score-colors.js` (`balloonEdge`/`balloonTint`/
`paintSolvedCell`/`balloonDot`); o gêmeo inevitável é o awk de `score/report-gen.sh` (`bl_edge`).
O anel do **first-to-solve** vence nos dois modos. No **celular** (≤640px) o ponto e o contorno
somem: ali quem diz "resolvido" é o **✓** — um símbolo, o canal que não depende de cor — e a cor
segue no balão do cabeçalho. Esse ✓ é **só do ICPC** (`table.score.m-icpc`): no OBI a célula é a
NOTA. Na **página do contest** a linha resolvida usa tom claro da cor + barra lateral com a cor
real (contornada) + selo "✔ resolvido" — pintá-la com a cor crua deixava o título ilegível nas
5 cores escuras.

**O balão obedece ao freeze** (desde 2026-08-20): acerto com `sub_epoch >= FREEZE_TIME` **não vira
tarefa de entrega** e não é entregue depois — um balão atravessando a sala conta à plateia
exatamente o que o placar congelado esconde. A supressão é permanente (lápide em
`print-requests/.balloon-frozen`), sobrevive ao "Encerrar evento" e só o admin a desfaz, ligando
`balloons_during_freeze` (o clássico do ICPC), o que também **libera os retidos**. Pedido de
impressão não é afetado. Ver `OVERVIEW.md` (§ Balões) e `MANUAL-STAFF.md`.

**A conta `.animeitor`** (mesa do telão) recebe o placar **sempre descongelado** e é dela que sai
o **webcast**: um pacote por VISÃO, no formato do BOCA, que o sistema Animeitor busca em loop —
inclusive com os runs pós-freeze, porque quem anima a virada é ele. Ver `docs/WEBCAST.md`.

**O que NÃO é recortado** (e está assim de propósito, porque é papel privilegiado):
`/contest/statistics` (admin/juiz/monitor — inclusive `first_solver` nominal),
`/contest/allsubmissions`, a fila do staff (o balão do convidado precisa ser entregue) e o
relatório final do admin. E há canais laterais **numéricos** que continuam existindo:
`/index/status` conta as submissões pendentes de todos os times do contest, e o contador de
tarefas de impressão é único. São contagens, não identidade — mas saiba que existem.
`updatescore-outro.sh` (placar custom) não participa de coortes.

## Como adicionar um modo novo (ex.: `xyz`)

1. `server/score/updatescore-xyz.sh <contest>` — emite o TXT (1ª linha `xyz` + cabeçalho + linhas
   ordenadas). Reaproveite `server/score/score-common.sh`.
2. Registre no dispatcher `server/score/build.sh` (case `xyz) updatescore-xyz.sh ;;`).
3. `web/contest/score/score-xyz.js` — recebe o TXT já parseado e renderiza.
4. Registre no dispatcher do front `web/contest/score/score.js`.

Geradores existentes (testados contra dados reais, batem com os placares legados):
`updatescore-icpc.sh`, `updatescore-obi.sh`, `updatescore-treino.sh`, `updatescore-heuristic.sh`,
`updatescore-outro.sh`.

## Layout: o placar NUNCA rola para o lado

Regra de produto: todas as colunas têm de ser visíveis em qualquer tela — pode quebrar linha,
não pode rolar. Como isso é garantido (vale para o placar do contest, a **cerimônia de
revelação** e o placar do **relatório offline**, que inlina o mesmo CSS):

> ⚠ A página de revelação (`/contest/score/reveal.html`) é **EXPERIMENTAL** — serve para
> ensaio, sede pequena ou plano B. A cerimônia **oficial** de um evento é conduzida pelo
> **Animeitor, de Emílio Wuerges**, alimentado pelo pacote de webcast (ver `WEBCAST.md` e
> `MANUAL-ANIMEITOR.md`).


- `table.score { table-layout:fixed }` + **`<colgroup>`**: a coluna vale o que o `<col>` diz e
  o conteúdo quebra dentro dela. Antes era layout automático + `white-space:nowrap`: o nome
  comprido do time esticava a tabela e, com 14 problemas, em 1024px só três apareciam.
- As larguras são **fração**, não pixel: o renderizador só carimba o cenário
  (`--nprob`, e zera `--w-flag`/`--w-pen` quando a coluna não existe) e o `ui.css` divide —
  colunas fixas (`#`, bandeira, Total, Penal.), os problemas ficam com `--w-prob-share` do que
  sobra e o time com o resto. Helper: `web/contest/score/score-cols.js` (`scoreCols`).
  ⚠ **Não use `min()`/`max()` na largura de `<col>`**: o Firefox ignora função de comparação
  ali e a tabela cai para colunas uniformes (testado). Só `calc()` com `+ - * /`.
- O número da célula vive em **`<span class="pv">`** e tem fonte menor que o cabeçalho — a
  referência da coluna (letra + balão) é o que precisa ser legível. Cada faixa de tela
  (`≤1100`, `≤820`, `≤640`) só ajusta constantes.
- **Celular (≤640px)**: na célula de **problema** o número sai de cena e vira **marca** (`✓`
  resolvido, `✗` tentou; o fundo do balão continua sendo a informação principal). Tentativas e
  minuto ficam no `title` (`A: 1 tentativa, 28 min`, via `cellTitle`). **Total e penalidade
  continuam com o número** — os dois também são `td.cell` (`.tot`/`.pen`), então a regra que
  esconde o `.pv` os EXCLUI explicitamente; sem isso a coluna "Penal." aparecia com cabeçalho e
  células vazias, gastando largura sem informar a 1ª desempatadora.
- O embrulho do placar é **`.board-wrap`** (sem `overflow-x`), nunca `.chart-wrap`/`.tblwrap` —
  esses rolam e são para as outras tabelas.

## Recursos do placar (web/contest/score/)

- **Bandeiras locais (offline):** a coluna `flag` (código de país ISO-2 ou estado `BR-SP`)
  vira um SVG servido pelo próprio MOJ em `/shared/flags/` (271 países + 27 estados) — nada de
  CDN externo. Ver `web/shared/flags.js`.
- **`/contest/teams` (por-usuário, PRECEDE o teams-meta)**: diretório dos times a partir do
  `.team{univ_short,univ_full,flag,region}` do account.json (aba 👥 Times do admin) +
  `has_logo`/`has_photo`. O **nome do time é o `fullname`** (campo único; a coluna `team name`
  do TXT sai de `.team.name // .fullname` — `.team.name` é só legado da migração). O placar mescla **explícito primeiro**: bandeira/univ que faltarem no
  TXT, a **sede** (`t._region`, filtro por nome), o **brasão** (`/contest/team-logo`, vence o
  logo por regra) e o **📷** (R4, 2026-08-30 — revoga o "não mostra quem tem foto" de
  2026-08-24): `has_photo` vira `t.photoUrl` (`/contest/team-photo`, rota pública) e o link só
  RENDERIZA com o placar **aberto** (`opts.showPhotos = !frozenView`, decidido pelo cabeçalho
  `X-MOJ-Frozen` do servidor) — durante o freeze a foto denunciaria presença/atividade. A
  galeria do telão e o painel Pessoas › Times continuam usando `has_photo` como antes.
- **`teams-meta`** (`contests/<id>/teams-meta.json`, lido por `GET /contest/teams-meta`):
  regras **regex no login → {country, school, school_full, logo?}**. **Fallback**: o placar
  preenche bandeira/universidade/logo só no que o por-usuário e a coluna não trouxeram, e
  habilita **filtro por país/escola**. O logo é um data-URL embutido (offline). Editável na
  criação e no admin do contest.
- **Chip ↑BR (classificação p/ a próxima fase)**: time em stage **published** do
  `classification.json` ganha o chip ao lado do nome (tooltip: etapa · regra · sede) no
  placar ao vivo E no relatório (que também gera `classificados.html` com a relação por
  regra). Rascunho não aparece em lugar nenhum. Ver `docs/CLASSIFICACAO.md`.
- **Empate compartilha a posição e CONSOME (ranking de competição, 2026-08-31)**: N times
  empatados (icpc: total+penalty+lastac; obi: mesmo total; cerimônia: solved+penalty)
  mostram a MESMA posição e o próximo classificado vem N abaixo (1-2-2-4, nunca 1-2-2-3 —
  era a numeração DENSA que o Carlos flagrou na LATAM: grupo em 1106 e o seguinte em 1107).
  Vale na numeração geral, no `.plg`, no recorte renumerado (slicePlaces + o JS inline do
  relatório) e no `data-place` do relatório offline; convidado segue SEM consumir posição.
  Modo genérico (colunas livres, sem tupla de desempate estruturada) fica sequencial.
  Teste: `smoke-score-ties.sh`.
- **Desclassificação (`.disqualified=true` no account.json, via `/contest/admin/user-disqualify`)**:
  o time some do placar (`sc_users` não o emite — fora do rank, da ★ de first-to-solve e das
  coortes por construção) E da estatística (o stats-gen pula o login por inteiro) — as duas
  telas sempre contam a MESMA população. Desabilitar (`user-disable`) só bloqueia o login e
  NÃO tira do placar.
- **Nó de RECORTE no `regions.json`** (`"view": true`): supersedes e recortes transversais
  (ex.: times femininos) repetem times que já estão nas sedes — a flag marca a fatia na
  estatística (`by_region[...].view:true`) e a UI avisa que somar recortes com sedes conta
  em dobro. Sem a flag o nó se comporta como sempre (a LATAM 2026 tinha 307 times em ≥2
  fatias e a soma "sede a sede" dava 1.272 onde havia 965).
- **Filtro por região** (`regions.json`, `GET /contest/regions`): árvore hierárquica; cada
  entrada casa por **nome** (igualdade com a sede `.team.region` do time) **ou** pelo `regex`
  no login (clássico).
- **Modo anônimo** (`SCORE_ANON=1` no conf, ou toggle local): esconde o desempenho individual e
  mostra agregado — participantes, **quartis** por nº de problemas resolvidos, distribuição e
  resolvedores por problema. Forçado para não-admins quando `SCORE_ANON=1`.
- **Cores dos balões** (`balloons.json`, `GET /contest/balloons`): mapa letra→cor (default ICPC
  A–O). Campo `enableSonic` ativa o **modo secreto do Sonic** (GIFs locais em `/shared/assets/sonic/`).
- **Estatísticas** ricas em `/contest/statistics/` (admin/judge/mon) e similaridade em
  `/contest/jplag/`.
