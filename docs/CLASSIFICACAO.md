# Classificação para a próxima fase (Final Brasileira → PDA → Mundial)

O contest pode marcar times CLASSIFICADOS para a etapa seguinte — na 1ª fase da Maratona
SBC, a **Final Brasileira**. O dado mora em `contests/<c>/classification.json`
(`stages[]`, cada stage com `status: draft|published`, `teams{login→{via,sede,place,…}}` e
`next_stage` — o engate p/ PDA/Mundial). SÓ o stage **published** aparece fora do painel:
chip **↑BR** no placar ao vivo (tooltip com etapa/regra/sede), chip + página
`classificados.html` no relatório estático, e o `GET /contest/classification` público.

## O motor (`server/score/classify-br.sh <contest> <config.json> [out]`)

Preview PURO (nunca grava) sobre `var/placar-full.txt` + `regions.json`. Regras da 1ª
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
  conta p/ limite de escola.
- Vagas não usadas saem em `unused{}` p/ o comitê redistribuir (manual).

## Fluxo no painel (Prova › Classificação)

👁 Prever (mostra a relação por regra, com unused) → ✔ Aplicar rascunho (promoções
manuais `comite` são PRESERVADAS no re-apply) → 📢 Publicar. Auditado (`classify`).
A tabela oficial de vagas da 1ª fase (verificada 15/08) vem semeada como default.

Teste: `server/test/smoke-classify-br.sh` (motor + relatório + gate de rascunho).
