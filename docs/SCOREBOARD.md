# MOJ — Placares multi-modo

Princípio: **adicionar um modo = 1 gerador (`server/score/updatescore-<modo>.sh`) + 1 renderizador
(`web/contest/score/score-<modo>.js`)**, ligados pela mesma string de modo.

## Fluxo

1. O `conf` do contest define `CONTEST_TYPE` (`icpc` | `obi` | `treino` | `heuristic` | `outro`;
   `lista-publica`/`lista-privada` → `treino`; ausente → `icpc`).
2. `server/score/build.sh <contest>` despacha para `updatescore-<modo>.sh` e grava
   `contests/<contest>/controle/placar.txt` (atômico). É chamado pelo daemon após cada veredicto.
3. A rota `GET /api/v1/contest/score?contest=<c>` serve esse TXT cru.
4. O front (`web/contest/score/`) lê a **1ª linha = modo** e despacha para o renderizador.

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
| `icpc` | vazio=não tentou · `tentativas/minuto`=resolveu · `tentativas/-`=tentou | acertos↓, depois penalidade↑ (penalidade=(tent−1)·20+minuto) | pinta com a cor do balão |
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
