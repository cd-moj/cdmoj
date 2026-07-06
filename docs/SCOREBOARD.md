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

## Formato do TXT

```
icpc                                                  ← linha 1: o modo (bare)
desc:asc:flag:username:univ short:team name:univ full:A:B:C:D:Total   ← cabeçalho
1:1:BR:br-df-alfa:UNB:ALFA:Universidade de Brasília:1/30:2/40:1/55::3/68::15
```

- Campos separados por `:`. **O placar já vem ordenado** — o front só renderiza na ordem.
- O cabeçalho pode começar com colunas-marcador `desc`/`asc` (campos de ordenação já aplicados):
  **o renderizador deve descartar TODAS as colunas iniciais cujo valor seja `desc` ou `asc`.**
- Colunas: `flag` (ISO), `username`, `univ short`, `team name`, `univ full` (as de univ são opcionais),
  uma coluna por problema (na ordem dos short names), `Total`.

### Células por modo
| Modo | Célula de problema | Ordenação | Cor |
|---|---|---|---|
| `icpc` | vazio=não tentou · `tentativas/minuto`=resolveu · `tentativas/minuto*`=**first to solve** (★ + contorno; menor `first_ac_epoch` do problema entre os times do placar, na mesma visão frozen/full) · `tentativas/-`=tentou | acertos↓, depois penalidade↑ (penalidade=(tent−1)·`PENALTY_MINUTES`+minuto; default 20) | pinta com a cor do balão |

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

## Como adicionar um modo novo (ex.: `xyz`)

1. `server/score/updatescore-xyz.sh <contest>` — emite o TXT (1ª linha `xyz` + cabeçalho + linhas
   ordenadas). Reaproveite `server/score/score-common.sh`.
2. Registre no dispatcher `server/score/build.sh` (case `xyz) updatescore-xyz.sh ;;`).
3. `web/contest/score/score-xyz.js` — recebe o TXT já parseado e renderiza.
4. Registre no dispatcher do front `web/contest/score/score.js`.

Geradores existentes (testados contra dados reais, batem com os placares legados):
`updatescore-icpc.sh`, `updatescore-obi.sh`, `updatescore-treino.sh`, `updatescore-heuristic.sh`,
`updatescore-outro.sh`.

## Recursos do placar (web/contest/score/)

- **Bandeiras locais (offline):** a coluna `flag` (código de país ISO-2 ou estado `BR-SP`)
  vira um SVG servido pelo próprio MOJ em `/shared/flags/` (271 países + 27 estados) — nada de
  CDN externo. Ver `web/shared/flags.js`.
- **`teams-meta`** (`contests/<id>/teams-meta.json`, lido por `GET /contest/teams-meta`):
  regras **regex no login → {country, school, school_full, logo?}**. O placar preenche
  bandeira/universidade quando faltam na coluna e habilita **filtro por país/escola**. O logo
  é um data-URL embutido (offline). Editável na criação e no admin do contest.
- **Filtro por região** (`regions.json`, `GET /contest/regions`): árvore de regex hierárquica
  testada contra o login.
- **Modo anônimo** (`SCORE_ANON=1` no conf, ou toggle local): esconde o desempenho individual e
  mostra agregado — participantes, **quartis** por nº de problemas resolvidos, distribuição e
  resolvedores por problema. Forçado para não-admins quando `SCORE_ANON=1`.
- **Cores dos balões** (`balloons.json`, `GET /contest/balloons`): mapa letra→cor (default ICPC
  A–O). Campo `enableSonic` ativa o **modo secreto do Sonic** (GIFs locais em `/shared/assets/sonic/`).
- **Estatísticas** ricas em `/contest/statistics/` (admin/judge/mon) e similaridade em
  `/contest/jplag/`.
