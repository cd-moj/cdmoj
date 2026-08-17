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
4. A rota `GET /api/v1/contest/score?contest=<c>` serve esse TXT cru — com **cache preguiçoso**:
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
- O cabeçalho pode começar com colunas-marcador `desc`/`asc` (campos de ordenação já aplicados):
  **o renderizador deve descartar TODAS as colunas iniciais cujo valor seja `desc` ou `asc`.**
- Colunas: `flag` (ISO), `username`, `univ short`, `team name`, `univ full` (as de univ são opcionais),
  uma coluna por problema (na ordem dos short names), `Total`; no modo `icpc` também
  **`Penalty`** (soma das penalidades, coluna VISÍVEL) e **`LastAC`** (minuto de prova do
  último problema resolvido — coluna de SISTEMA: a UI usa p/ detectar empate exato, não exibe).

### Células por modo
| Modo | Célula de problema | Ordenação | Cor |
|---|---|---|---|
| `icpc` | vazio=não tentou · `tentativas/minuto`=resolveu · `tentativas/minuto*`=**first to solve** (★ + contorno; menor `first_ac_epoch` do problema entre os times do placar, na mesma visão frozen/full) · `tentativas/-`=tentou | **1º** acertos↓ · **2º** penalidade↑ (penalidade=(tent−1)·`PENALTY_MINUTES`+minuto; default 20) · **3º** minuto do ÚLTIMO problema resolvido↑ (`LastAC`) | pinta com a cor do balão |

**Penalidade configurável (modo `icpc`)** — duas vars de conf, editáveis pelo
`/contest/admin/settings` (mudar em prova recomputa o placar no próximo GET):
- `PENALTY_MINUTES` (default 20): minutos somados por tentativa que conta antes do AC.
- `PENALTY_VERDICTS` (códigos `wa tle mle rte ce`; default `wa tle mle rte`): quais verdicts
  entram no `counted` do metrics. **Judge Error/No_Servers e provisórios nunca contam**;
  strings legadas fora do vocabulário canônico continuam contando (comportamento histórico).
  Lista vazia (`PENALTY_VERDICTS=''`) = nenhum verdict penaliza (só o minuto do AC).
| `obi` | pontos (0–100) | Total↓ | — |
| `treino` | resolvidos / tentativas | resolvidos↓ | — |
| `heuristic` | melhor Score | Score↓ (Score Ajustado como desempate) | — |
| `outro` | colunas 100% personalizadas (cabeçalho traz os nomes reais) | já ordenado | se houver coluna `flag`, mostra bandeira |

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

**A coluna `guest`** (só existe quando a visão tem coorte `unranked`) é a última do TXT, com `1`
para convidado. Os renderizadores acham coluna por NOME no cabeçalho, então quem não a conhece
simplesmente a ignora; o front usa para pular a numeração e marcar a linha.

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
- **Celular (≤640px)**: o número sai de cena e a célula vira **marca** (`✓` resolvido, `✗`
  tentou; o fundo do balão continua sendo a informação principal). Tentativas e minuto ficam no
  `title` (`A: 1 tentativa, 28 min`, via `cellTitle`).
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
  logo por regra) e o link 📷 da **foto** (`/contest/team-photo`, abre em nova aba).
- **`teams-meta`** (`contests/<id>/teams-meta.json`, lido por `GET /contest/teams-meta`):
  regras **regex no login → {country, school, school_full, logo?}**. **Fallback**: o placar
  preenche bandeira/universidade/logo só no que o por-usuário e a coluna não trouxeram, e
  habilita **filtro por país/escola**. O logo é um data-URL embutido (offline). Editável na
  criação e no admin do contest.
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
