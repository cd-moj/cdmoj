# Classificação para as próximas fases (Final Brasileira → PDA → Mundial)

O contest pode marcar times CLASSIFICADOS para as etapas seguintes. O dado mora em
`contests/<c>/classification.json`, com `stages[]`: um **estágio** por etapa — `final-br` e `pda` no contest da 1ª
fase/regional, `mundial` no do Campeonato. Cada estágio tem o seu motor, `status: draft|published` e `teams{login→{via,
sede,place,…}}`. SÓ o estágio **published** aparece fora do painel:
- um chip **🎓 <chip do estágio>** por estágio no placar ao vivo (o time na Final BR e na PDA mostra os dois; tooltip com
  etapa · via · sede);
- os mesmos chips no relatório estático, mais a página `classificados.html` (uma seção por estágio);
- o `GET /contest/classification` público.

## O motor (`server/score/classify-br.sh <contest> <config.json> [out]`)

Preview PURO (nunca grava) sobre `var/placar-full.txt` + `regions.json`.

O placar é lido pelo CABEÇALHO, com o parser único `sc_board_rows` (`score/score-common.sh`), pelo comum aos motores
(`score/classify-common.sh`). Até 30/09/2026 o motor contava as colunas a partir do FIM, com `$NF` = guest. A coluna
`guest` só existe com coorte unranked: sem ela, o motor lia o total de uma célula de problema e tomava por convidado
quem tinha LastAC=1. Num contest sem coorte, a Final saía VAZIA. Em 2026 escapou porque havia a coorte CCL. A
regressão está no `smoke-classify-br.sh`, e o motor novo deu os mesmos 61 automáticos publicados na LATAM 2026.

Quem disputa = quem ESTÁ no
nó da região (`config.region`, padrão "Brasil") e a sede de cada time = a sede pela regra única de sedes
(`lib/regions.sh`: a gravada vence, senão a regex mais funda; quem "parou no pai" fica sem sede). Até
28/09/2026 eram a regex do nó da região e a 1ª folha pela regex, ignorando a sede gravada. Regras da 1ª
fase, aplicadas EM ORDEM (config define vagas; tudo editável no painel):

- **regra 0** (elegibilidade): Total ≥ 3; o CAMPEÃO da sede (1º dela no ranking) é
  elegível com Total ≥ 2. Filtra todas as regras automáticas (a 4 inclusive).
- **regra 1** (`r1`, 15): melhores do ranking da região; máx. **2 por escola** (univ short).
- **regra 2** (`sedes{}` + `supersedes{}`, Σ≈40): por sede normal, os melhores N da sede;
  por supersede, os melhores K entre as sedes membras com **≤1 por sede membra** (a
  membresia vem das `subregions` do nó no regions.json — só nós COM vaga no config
  contam como pai). Nos dois casos: ≤1 por escola nesta regra, e escola que classificou
  pela regra 1 não entra.
- **regra 3** (~4): manual — override `add` ("➕ Promover à mão", via `manual` + motivo).
- **regra 4** (`r4{f3,f2,f1}`, 3+2+1): pelas listas de login de
  `/Times femininos/{3,2,1 competidoras}` do regions.json; não repete classificado e NÃO
  conta p/ limite de escola. A faixa de cada time é a PERTENÇA aos recortes (lib/regions.sh), pela função
  `cl_female`, e vale a maior faixa. Até 30/09/2026 a faixa saía dos tokens `team…` das regexes, e login de
  outro formato sumia.
  - Avisos na saída (`warnings[]`): `female_prefix_match` (a regex casa o login, mas ele não é token literal
    dela: `^(teamsp03)` casa `teamsp030`), `female_multi_bucket` e `female_node_missing`.
  - Antes de trocar de árvore, rode o `server/bin/regions-audit.sh <c>`: a seção FEMININAS compara as faixas,
    corte antigo × novo.
- Vagas não usadas saem em `unused{}` p/ o comitê redistribuir (manual).
- Overrides: `exclude[]` tira o login da região antes do ranking (ele nem conta como campeão da sede);
  `preassigned[]` pula o time em todas as regras e sai em `pre[]` com os dados do placar.

## Motores e catálogo

`config.algorithm` diz qual motor roda. O handler (`admin/classify.sh`) só executa um script da **allowlist**
`CL_ENGINES` (`lib/classify.sh`). O **catálogo** `server/score/classify-catalog.json` descreve cada motor: estágio padrão,
próximo estágio, formulário do painel (`form`), padrões (nome, local, quando, chip), vias e semente. Ele também traz os
rótulos pt/en/es de toda via. O `smoke-contest-modules.sh` confere que catálogo e allowlist têm os mesmos ids. Hoje:
`sbc-fase1` (as regras acima, estágio `final-br`, chip "Final BR").

**Motor novo** = `score/classify-<x>.sh` + uma linha em `CL_ENGINES` + uma entrada no catálogo + smoke. O placar, o
relatório e a rota pública leem o ESTÁGIO, nunca o motor. Id fora da lista = 422 `algorithm_invalid`.

Contrato de um motor (`score/classify-common.sh` tem o comum: placar pelo cabeçalho, femininas, avisos):
- `classify-<x>.sh <contest> <config.json> [out]` → `{classified:[{login,via,place,total,detail,…}], pre:[…],
  warnings:[{code,data}], …}`. Pode trazer `via_order` e `labels` próprios (os blocos da PDA).
- `classify-<x>.sh --check <config.json>` → só valida a config. A criação de contest usa isso.
- rc: 0 ok · 1 uso/IO · 2 config inválida (stderr `{errors:[…]}`) · 3 RECUSA de dado (stderr diz qual time/código). O
  handler responde 422 `config_invalid` (com `errors`), `engine_refused` ou `engine_failed`.
- Config que o handler acrescenta: `exclude[]` (overrides exclude) e `preassigned[]` (overrides add). Ver abaixo.

## Override manual (salvaguarda contra erro de execução e caso de borda)

Vale para TODO estágio. O cálculo do motor e as decisões manuais ficam SEPARADOS: o estágio guarda `config`, `result`
(a saída PURA do motor) e `overrides[]`. O `teams` é a COMPOSIÇÃO: motor − retirados + manuais. A regra da composição
é ÚNICA, o `CL_JQ` em `lib/classify.sh`, usada pelo GET, pela prévia, pelo apply e pelos overrides. Cada override é
`{id, op, login|ext, reason, by, at}`, com motivo OBRIGATÓRIO. O motivo é interno: só o painel o mostra.

| Ação | Efeito | Quando usar |
|---|---|---|
| `exclude {login}` | O time sai do CÁLCULO (`exclude[]` do motor) e o motor roda de novo: o próximo pela regra herda a vaga. | Time inelegível, dado errado (escola ou região trocada). |
| `withdraw {login\|ext}` | O time sai da lista SEM recalcular: a vaga fica vaga (o comitê ou a lista de espera a preenche). | Time que desistiu depois da classificação. |
| `add {login \| ext+team, via}` | O time entra à mão, com a via `manual`, `lista` ou `reserva`. Para o motor ele já está promovido (`preassigned[]`): o recálculo não lhe dá outra vaga. Time de fora do placar entra como `ext:<id>`. | Decisão do comitê (a regra 3 da SBC), caso de borda. |
| `override_undo {id}` | Desfaz o override e volta ao cálculo. | Engano. |

- Um override por time: o segundo dá 409 `override_exists` (desfaça o primeiro).
- Os overrides SOBREVIVEM a um novo "Aplicar": o apply sempre roda motor + overrides, nessa ordem.
- `withdraw` e o undo dele não rodam o motor (compõem sobre o `result` guardado).
- No motor BR, o `preassigned` pula o time em todas as regras e não conta no limite de escola de nenhuma.
- Tudo vai ao audit (`classify-override`), e a trava `var/.classify.lock` serializa as escritas.
- Estágio no formato antigo (antes dos overrides, 30/09/2026) tem os promovidos à mão como times `via:"comite"`; a leitura os converte em
  override `add`, com a nota como motivo.
- A lista que avança para a PRÓXIMA etapa é a do estágio com os overrides.
- O chip, o `classificados.html` e o `/contest/classification` mostram o time manual com a via "Promoção manual
  (comitê)". O time `ext:` só aparece no `classificados.html`.

## Fluxo no painel (Evento › Classificação — módulo `classificacao`)

- **Etapa:** o seletor lista os estágios do contest. "＋ nova etapa…" propõe o 1º motor cujo estágio padrão ainda não
  existe (id do catálogo); com todos existindo, o id fica em branco. Digitar o id de um estágio que já existe abre
  esse estágio (e um estágio ainda sem motor leva o motor escolhido). O motor se escolhe na caixa de config.
- **Config:** o motor `sbc-fase1` usa o formulário de sempre (vagas por regra, sedes, supersedes), semeado com a
  tabela oficial. Os outros motores usam um editor JSON semeado com a regra oficial do motor (`seed` do catálogo). O
  servidor valida.
- 👁 **Prever** mostra os avisos do motor primeiro, depois a relação por via, já com os overrides do estágio.
- ✔ **Aplicar** grava o estágio. Num estágio já PUBLICADO, aplicar muda o placar na hora, e o painel avisa. Estágio de
  outro motor pede confirmação (409 `stage_algorithm_mismatch` → `force`).
- 📢 **Publicar** exige o id do contest digitado. 🗑 apaga só rascunho.
- Na relação, cada linha do motor tem ✂ (retirar sem recalcular) e ⊘ (excluir e recalcular). Linha manual ou retirada
  tem ↩ (desfazer). "➕ Promover à mão" leva login ou time de fora do placar, via e motivo. A lista "🛠 Overrides
  manuais" mostra todos, com quem e quando.

A criação de contest leva `modules.classificacao{algorithm, config}` (um estágio, o padrão do motor) ou
`{stages:[{id?, algorithm, config, name?, venue?, when?, chip?}]}`. O motor é conferido na allowlist e a config pelo
`--check` do motor. O export devolve `stages[]` quando há mais de um estágio. Resultado e overrides não entram: são
dados da prova.

Testes: `server/test/smoke-classify-br.sh` (motor, relatório com dois estágios, gate de rascunho, handler e overrides),
`smoke-score-classified.gjs.sh` (chips do placar), `smoke-classify-tab.gjs.sh` (o painel: grupos, ações no estágio
certo, nova etapa, editor JSON), `smoke-contest-modules.sh` (catálogo × allowlist, spec com
`stages[]`).
