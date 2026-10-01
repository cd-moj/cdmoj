# Classificação para a próxima fase (Final Brasileira → PDA → Mundial)

O contest pode marcar times CLASSIFICADOS para a etapa seguinte — na 1ª fase da Maratona
SBC, a **Final Brasileira**. O dado mora em `contests/<c>/classification.json`
(`stages[]`, cada stage com `status: draft|published`, `teams{login→{via,sede,place,…}}` e
`next_stage` — o engate p/ PDA/Mundial). SÓ o stage **published** aparece fora do painel:
chip **↑BR** no placar ao vivo (tooltip com etapa/regra/sede), chip + página
`classificados.html` no relatório estático, e o `GET /contest/classification` público.

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
- **regra 3** (~4): manual — botão "Promover time (comitê)" (`via:"comite"` + nota).
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

## Algoritmos (o motor é escolhido por CATÁLOGO)

`config.algorithm` diz qual motor roda; o handler (`admin/classify.sh`) despacha por
**allowlist** `CL_ENGINES` (`id → score/classify-<x>.sh`) e o `GET` devolve `algorithms[]`
(`{id,name,desc}`) — é o `select` "Algoritmo" do painel. Hoje só `sbc-fase1` (as regras
acima). **Como entra a regra da PDA** (Final Brasileira → Programadores da América):
`score/classify-pda.sh <contest> <config.json> [out]` com o MESMO contrato de saída
(`{classified:[{login,via,sede,place,total,detail}], unused{}, region}`), uma linha em
`CL_ENGINES`, uma entrada em `cl_catalog` e o smoke (`smoke-classify-br.sh` é o molde). Nada
mais muda: o painel, o placar (chip ↑BR) e o relatório leem o stage, não o motor. Id fora da
lista = 422 `algorithm_invalid`. A classificação é o módulo `classificacao` do contest
(Central › Módulos); o spec de criação leva `modules.classificacao{algorithm,config}`.

## Fluxo no painel (Evento › Classificação — módulo `classificacao`)

👁 Prever (mostra a relação por regra, com unused) → ✔ Aplicar rascunho (promoções
manuais `comite` são PRESERVADAS no re-apply) → 📢 Publicar. Auditado (`classify`).
A tabela oficial de vagas da 1ª fase (verificada 15/08) vem semeada como default.

Teste: `server/test/smoke-classify-br.sh` (motor + relatório + gate de rascunho).
