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
