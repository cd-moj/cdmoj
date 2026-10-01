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

## Motor `latam-pda` (regional LATAM → Campeonato Latino-Americano, a "PDA")

`server/score/classify-pda.sh`, estágio `pda`, chip "PDA". A regra é o PDF "2026-2027 ICPC Latin America – Promotion
Rules". A config oficial está em `server/score/classify-seeds/latam-pda-2027.json`, a semente do editor JSON do painel.

**Dados** (todos pelo `classify-common.sh`):
- Participante = todo time no placar (sem convidados e sem desclassificados), menos o `exclude[]`.
- Região e país saem do LOGIN, pelas duas capturas de `login_regex` (padrão `^team([a-z]{2})([a-z]{2})`: `teamsoar01` =
  região `so`, país `ar`). Códigos de região: `br` Brasil, `mx` México, `cb` Caribe, `ca` América Central, `no`
  América do Sul Norte, `so` América do Sul Sul (`regions[]`; a ordem é a das tabelas).
- Login fora do padrão, ou com região fora da tabela: o motor RECUSA (rc 3) e lista os logins. Ele nunca adivinha.
  Para seguir, exclua o login (override `exclude`) ou corrija a regra. O código de PAÍS não é validado.
- Escola = `"<país>:<sigla>"`, com a sigla (`univ_short`, senão `univ_full`) em minúsculas e sem espaço, ponto,
  vírgula, hífen, sublinhado e aspas. `school_alias` junta chaves numa só (os campi de uma instituição). Avisos:
  `school_missing` (time sem escola vira a própria escola) e `school_key_collision` (a mesma chave com nomes completos
  diferentes).
- Feminina = a faixa dos recortes "Times femininos" (`female_node`). Só mulheres = a faixa 3; "≥2 competidoras" =
  faixa 3 ou 2; "≥1" = qualquer faixa.

**Regra geral:** a escola ainda não tem time promovido. O 2º time de uma escola só entra no passo 1 (até
`max_per_school`, padrão 2). Os blocos sem a regra geral só exigem que o time não esteja promovido.

**Passos padrão, nesta ordem** (cada um vê os promovidos dos anteriores):
1. **P1 desempenho:** N/2 vagas aos melhores, com até `max_per_school` por escola.
2. **P2 países:** o teto é calculado UMA vez, antes do passo: `min(N/4, X) − 1`, com X = países participantes ainda sem
   time (`countries.cap: "min_minus_1"`, decisão do Ribas; a variante `"min_of_x_minus_1"` = `min(N/4, X − 1)`). Vaga a
   vaga, o melhor time de país sem time, com ≥ `countries.min_solved` (1) resolvido. País só com times de 0 resolvidos
   sai em `countries.zero_solved`. Vaga que sobra fica para o P4.
3. **P3 instituição-sede:** se nenhuma escola de `host_schools` tem time, 1 vaga ao melhor time de QUALQUER escola sem
   time (decisão do Ribas: a condição é sobre as escolas-sede, a vaga não). Sem `host_schools`, o passo é pulado com
   aviso.
4. **P4 representação geográfica:** o algoritmo do PDF, em INTEIROS (o PDF divide duas vezes; em ponto flutuante,
   9 × 21 / 27 dá 6,999… e o trunc dá 6 em vez de 7):
   - `restantes = N − vagas dos passos 1 a 3`; `q_R = escolas_R × restantes`;
   - `vagas_R = q_R div escolas_LATAM`; `fração_R = fractions_prev_R + (q_R mod escolas_LATAM) / escolas_LATAM`;
   - enquanto o total < N: a região com a MAIOR fração ganha 1 vaga e zera a fração. Empate (eps 1e-9) = TODAS as
     empatadas levam; pode passar de N (`geo.overflow` + aviso `geo_tie_overflow`);
   - `fractions_out` = as frações > 0, para a config do ano seguinte (o painel tem o botão de copiar);
   - a vaga da região vai ao melhor time da região de escola sem time. Região sem time elegível: a vaga fica sem uso,
     com o aviso `geo_unfilled` (`geo.on_unfilled: "none"`).
5. **Femininas padrão** (`female[]`, sem a regra geral): a melhor só-mulheres do país-sede (`host_country`), depois a
   melhor só-mulheres da LATAM.

**Blocos da edição 2027** (`edition_blocks[]`, na ordem; cada um com `label` pt/en/es):

| Tipo | O que faz |
|---|---|
| `fixed` | Times de fora do placar (os pendentes de 2026), chave `ext:<id>`, sem posição. Por padrão não contam como time da escola/país/região (`counts_for_school: false`). |
| `female` | `scope`: `host_school` (a instituição-sede), `host_country`, `latam` ou `per_region` (`slots` POR região); `min_women` 3/2/1. Sem a regra geral. |
| `country_participation` | Cotas `quotas` (5, 4, 3, 2, 1) aos países com mais times no CICLO, desempate por instituições: a tabela do RCD em `cycle_teams`/`cycle_institutions`. Vazia, a prévia usa as contagens DESTE contest e avisa (`cycle_table_empty`). Empate nas duas = `cycle_tie`. As vagas vão aos melhores times de instituições ainda sem time (1 por instituição). |
| `host_school` | Vagas extras da instituição-sede; `general_rule: false` na semente (decisão do Ribas). |
| `reserve` | Só reportada (`reserve.slots`). O comitê usa as vagas com "➕ Promover à mão" via `reserva`; passar do número = 409 `reserve_full`. |

Mínimo de resolvidos: só onde o PDF diz (`countries.min_solved: 1`). Os outros blocos aceitam `min_solved`, padrão 0.

**Lista de espera** (`waitlist`): faixas em ordem (`tiers`, cada uma com `schools` e/ou `countries`): na semente,
instituições de Monterrey, de Nuevo León e o resto do México. Cada time cai na 1ª faixa que casa; dentro dela, pela
posição. Com `general_rule: true`, a escola não pode ter time promovido nem um time antes na lista. A ação
`promote_next` do handler recalcula a lista contra o estágio ATUAL (`--waitlist`: os times compostos contam como
promovidos, os retirados ficam de fora) e promove o 1º, como override `add` via `lista`.

**O RCD preenche antes da rodada real** (a semente os deixa vazios e o motor avisa onde faz diferença):
`host_schools` (e o `school_alias` se os campi do ITESM são uma escola só), a tabela do ciclo, as escolas das faixas
da lista de espera e as `fractions_prev` que sobraram do ano anterior.

**Saída:** além de `classified[]` (na ordem de promoção, `seq`), `pre[]` e `warnings[]`: `blocks[]` (vagas e
usadas), `unused{}`, `countries`, `host`, `geo` (por região: escolas, q, inteiras, frações, extra, vagas,
preenchidas), `fractions_out`, `country_participation`, `reserve`, `waitlist[]`, `labels` e `via_order`.

Os logins da LATAM 2026 (`teambrspso…`) não seguem o padrão `team<RR><PP>`; o motor foi validado pelo
`server/test/smoke-classify-pda.sh` (N=12, cada caso conferido à mão).

## Motor `latam-mundial` (Campeonato Latino-Americano → Mundial)

`server/score/classify-mundial.sh`, estágio `mundial`, chip "Mundial". Roda no contest do CAMPEONATO. A semente é
`server/score/classify-seeds/latam-mundial-2027.json`; o RCD informa `N_WF` (as vagas da LATAM no Mundial). Sem ele, o
motor avisa (`n_wf_missing`) e não classifica ninguém.

1. **Campeão de cada região** (`wf-region`): o melhor time da região com ≥ `min_solved` (1) resolvido.
2. **Geral** (`wf-overall`): as `N_WF − campeões` vagas restantes aos melhores do placar. A vaga de região sem time
   elegível vai ao geral (`region_slot_unfilled: "overall"`, decisão do Ribas; `"none"` a deixa sem uso), com o aviso
   `wf_region_unfilled`.

Só UM time por instituição (`max_per_school: 1`) vai ao Mundial, nos dois passos. Região, país e escola saem como no
`latam-pda` (login + `school_alias`), com a mesma recusa.

**Prêmios** (`awards`, INFORMATIVOS: não mudam a classificação): o campeão LATAM (1º lugar), as medalhas pela posição
(`awards: {gold:4, silver:4, bronze:4}` = ouro 1–4, prata 5–8, bronze 9–12) e o campeão de cada região com o título
dela (`regions[].title`, pt/en/es). Empate divide a posição; se ele atravessa a faixa, a medalha vai a mais times e o
motor avisa (`award_tie`). O painel mostra os prêmios em "📊 Detalhes do cálculo".

## Motores e catálogo

`config.algorithm` diz qual motor roda. O handler (`admin/classify.sh`) só executa um script da **allowlist**
`CL_ENGINES` (`lib/classify.sh`). O **catálogo** `server/score/classify-catalog.json` descreve cada motor: estágio padrão,
próximo estágio, formulário do painel (`form`), padrões (nome, local, quando, chip), vias e semente. Ele também traz os
rótulos pt/en/es de toda via. O `smoke-contest-modules.sh` confere que catálogo e allowlist têm os mesmos ids. Hoje:
`sbc-fase1` (estágio `final-br`, chip "Final BR"), `latam-pda` (estágio `pda`, chip "PDA") e `latam-mundial` (estágio
`mundial`, chip "Mundial").

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
| `promote_next {reason}` | O 1º da lista de espera (recalculada agora) entra como `add` via `lista`. Só motor com lista de espera; lista vazia = 409 `waitlist_empty`. | Vaga aberta por desistência. |

- Um override por time: o segundo dá 409 `override_exists` (desfaça o primeiro).
- Os overrides SOBREVIVEM a um novo "Aplicar": o apply sempre roda motor + overrides, nessa ordem.
- `withdraw` e o undo dele não rodam o motor (compõem sobre o `result` guardado).
- No motor BR, o `preassigned` pula o time em todas as regras e não conta no limite de escola de nenhuma.
- No motor `latam-pda`, o promovido à mão conta como promovido para a regra geral (a escola, o país e a região dele
  já têm time), mas NÃO ocupa uma das N vagas padrão: o P4 completa N com as vagas dos passos 1 a 3. É uma
  interpretação (o PDF não fala de promoção manual): o `add` é a vaga extra do comitê; erro do cálculo se corrige
  com `exclude`, que recalcula.
- O `promote_next` roda o motor com os MESMOS overrides (`exclude` incluído): um login excluído por override nem
  trava a lista (recusa) nem aparece nela.
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
`smoke-classify-pda.sh` (o motor da PDA passo a passo, `--check`, `--geo`, lista de espera, `promote_next`, reserva,
trava com 8 escritas em paralelo), `smoke-classify-mundial.sh` (campeões, 1 por instituição, região sem time → geral,
medalhas com empate),
`smoke-score-classified.gjs.sh` (chips do placar), `smoke-classify-tab.gjs.sh` (o painel: grupos, ações no estágio
certo, nova etapa, editor JSON), `smoke-contest-modules.sh` (catálogo × allowlist, spec com
`stages[]`).
