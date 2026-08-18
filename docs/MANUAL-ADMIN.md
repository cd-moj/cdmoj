# MOJ: Manual do organizador (o painel .admin do contest)

Este manual é para quem **opera** um contest: o dono da conta `.admin`. Ele explica cada aba do
painel de administração, cada opção de configuração, **como habilitar os papéis especiais**
(`.judge`, `.cjudge`, `.staff`, `.cstaff`, `.mon`), e como ligar a **correção validada por
juízes** — incluindo quantas pessoas você precisa.

> Criar o contest (wizard, problemas, contas) é o outro guia: o
> [tutorial do organizador](/treino/criar/tutorial.html). Aqui é a OPERAÇÃO, do dia da prova.

Você chega ao painel logando com a conta `.admin` do contest e clicando em **⚙ Administração**
na barra do topo.

## 1. O painel: a Central e os 4 grupos

O painel abre na **🏁 Central** e tem quatro grupos na barra de cima; cada grupo tem seus painéis
na segunda linha. O endereço guarda o painel (`#grupo/painel`), então dá para salvar o link — e os
links antigos (`#settings`, `#users`, `#machines`…) continuam funcionando, redirecionados.

```
[🏁 Central] [🧩 Prova] [👥 Pessoas] [🎛️ Operação]                        📖 Manual
```

### 🏁 Central — o que falta e o que gerar

| Bloco | O que faz |
|---|---|
| **Falta para começar** | O checklist pré-prova (verde/amarelo/vermelho) com **botão que abre o painel exato** de cada pendência. Vermelho BLOQUEIA a prova; os itens já conferidos ficam recolhidos. Confere janela, log de julgamento, freeze, juízes, linguagens, TL calibrado, pool, contas, staff, **coortes**, **gate de navegador**, **rodada seguinte**, **documentos**, **balões**, prorrogação e o daemon. |
| **Gerar** | Um cartão por artefato, com o estado atual: documentos da prova, etiquetas de credenciais, promover rodada (com os bloqueadores), relatório final, cerimônia de revelação e jplag. |
| **Ao vivo** | Resumo curto (pendentes, submissões, juízes online, resposta p95, correção manual). Atualiza sozinho; o painel completo é **Operação › Situação**. |
| **Regras da prova** | Início, fim e freeze editáveis ali mesmo, mais o modo e as linguagens em leitura. O resto está em **Central › Regras**. |

| Painel | O que faz |
|---|---|
| **Central › Regras** | **Todas** as opções do contest, em cinco seções dobráveis (identidade e janela · o que o time vê · julgamento · placar/freeze/penalidade · acesso) + a **⏱ Prorrogação por sede/grupo** (regex → novo fim; só estende, nunca encurta). A seção 2 explica opção por opção. |

### 🧩 Prova — o conteúdo

| Painel | O que faz |
|---|---|
| **Problemas** | A prova em si: renomear/reordenar/remover, **editar o identificador** (a "letra" — pode ser `W1`, `Q`…; reordenar preserva identificador customizado e a cor do balão migra junto), restringir linguagens ou o pool de juízes POR problema, atualizar o enunciado a partir do banco (ou enviar HTML/PDF), e **Adicionar do banco** (busca e sorteio). |
| **Rodadas** | **Aquecimento e prova oficial no MESMO contest**: planeja cada rodada (janela + problemas), mostra o checklist e promove — arquivando tudo o que aconteceu. A seção 6 explica. |
| **Documentos** | Gera, em PDF e HTML nos dois idiomas, os documentos da prova: **informações do ambiente** (info sheet), **caderno da prova** (capa + enunciados), **folha de time limits** e o **editorial** (solução de cada problema — só publica depois do FIM da prova). Baixa, publica para a sede e, se você quiser, vira notícia com o PDF anexo. Times só veem caderno/times publicados a partir do INÍCIO (a sede vê antes, para imprimir). A seção 5 explica. |
| **Balões** | A cor de cada letra — é o que sai desenhado na folha do balão. O default cobre A–O; com mais de 15 problemas, defina as demais (senão saem cinza). |

### 👥 Pessoas — quem entra, quem é quem

| Painel | O que faz |
|---|---|
| **Contas** | Criar/resetar/desabilitar/remover contas (individual e em lote por .txt/.csv), trocar a senha de todos e o atalho das **🏷️ Etiquetas de credenciais**. É AQUI que você cria as contas de papel (seção 3). |
| **Times** | Identidade de cada conta no placar: nome do time, país/bandeira, sede, universidade, brasão e foto. Carga por CSV e "materializar matches". |
| **Inscrições** | O **roster** do contest (só inscrito entra) e a **janela**: quando abre, quando fecha (default: o início da prova) e quantos minutos de entrada atrasada. Lista times e individuais, dissolve time, inscreve à mão, **cutuca convite pendente por DM** (🔔) e exporta CSV. A seção 8½ explica. |
| **Coortes** | Times **convidados** (extra-oficiais, "CCL") separados dos oficiais: quem aparece no placar público, quem vê quem, e o **🔓 Liberar resultados** do pós-cerimônia. A seção 8 explica. |
| **Sedes & escolas** | As sedes (nome + regex no login) — que alimentam o filtro do placar, o escopo do staff, as etiquetas, **as fotos/músicas que cada chefe de sede gere no telão** e o gate por sede — e as regras de país/escola por regex. |
| **Máquinas & gate** | De onde cada time logou (IP e navegador) em cada rodada, com CSV, **e a configuração do gate de navegador por sede** (esperado × visto por time). A seção 7 explica. |
| **Sessões** | Sessões ativas com alerta de multi-IP/UA, deslogar, **deslogar UA divergente** e o log de acessos por dia (CSV). |

### 🎛️ Operação — o dia da prova

| Painel | O que faz |
|---|---|
| **Situação** | O dashboard ao vivo (atualiza a cada ~12s): logados, juízes online/ocupados, fila, pendentes, latência, timeline, avaliação manual, e as **ações sugeridas** quando algo está fora do lugar. Os botões **🏆 Cerimônia de revelação** e **📦 Relatório estático** ficam aqui. |
| **Staff** | Panorama e ação sobre a fila de impressão + balões, desempenho por staff e o **escopo** de cada staff/chefe de sede (regex ou `region:<sede>`). |
| **Juízes** | A fila da correção manual: quem pegou cada submissão, votos, idade; decidir/resolver na hora; e a configuração do veredicto manual (opções de rótulo + matriz de auto-veredicto). |
| **Auditoria** | Feed unificado de tudo que aconteceu (ações de admin, logins, submissões, veredictos) com filtros e CSV, mais os **backups** que os usuários subiram (por usuário, com ZIP). |

Fora do painel, mas linkadas da Central: **etiquetas de credenciais**, **cerimônia de revelação**,
**jplag**, **fila do staff** e **placar**.

## 2. Configurações — opção por opção

**Identidade e janela**

- **Nome** — o título exibido; o *id* (que vira o subdomínio) não muda.
- **Início / Fim** — a janela da prova. Antes do início: contagem regressiva; depois do fim: ninguém mais submete (exceto papéis de juiz). Prorrogação fina é na seção ⏱ (por regex de login — ex.: só uma sala que ficou sem luz).
- **Abertura do login** — a partir de quando o aluno consegue LOGAR (antes disso, contagem regressiva na tela de login). Útil p/ liberar o login minutos antes da largada.
- **Freeze** — congela o placar público a partir deste horário (estilo ICPC). Juízes e admin seguem vendo tudo; a revelação acontece na cerimônia.
- **Idioma** — o idioma default das telas do competidor.

**O que o aluno vê/pode**

- **Login habilitado** — desliga p/ trancar a porta (quem já está dentro continua).
- **Ver código das submissões** — o aluno rever o próprio código enviado.
- **Ver log de execução** — o relatório teste-a-teste. ⚠ Em prova valendo nota, deixar o log visível pode **vazar os testes** (o aluno vê entrada/saída) — o clássico "SHOWLOG" — desligue.
- **Editor no browser** — o editor lado a lado com o enunciado.
- **Mostrar time-limit** — exibe os TLs por linguagem no enunciado.
- **Aceitar atrasados** — permite login de conta criada depois da largada.
- **Backup** / **Impressão** — habilitam o upload de backup pelo aluno e os pedidos de impressão (que caem na fila do staff).
- **Placar anônimo** — esconde o desempenho individual (só a posição do próprio aluno).
- **Gate de login por UA** — só navegadores cuja identificação contém a substring conseguem logar (máquina de prova travada). Papéis privilegiados são isentos.
- **🕵️ SUPER SECRETO** — o contest some da home/arquivo/status e até o placar exige login. Para provas que não podem nem constar que existem.

**Julgamento**

- **Linguagens** — a lista permitida no contest (cada problema pode restringir mais, em Prova › Problemas).
- **Pool de juízes (máquinas)** — quais MÁQUINAS de julgamento atendem este contest (vazio = qualquer juiz online). Não confundir com juízes HUMANOS (seção 4).
- **Veredicto manual** — liga a **correção validada por juízes humanos** (seção 4).
- **Nº de juízes que validam cada veredicto** — o quórum da correção manual: **1 a 5, padrão 2**. Com 1, um único voto decide (revisão simples); com N≥2, o veredicto só sai com N votos **unânimes** — qualquer divergência vira conflito p/ o juiz-chefe.
- **Penalidade (ICPC)** — minutos somados por tentativa não aceita antes do Accepted (padrão 20) e QUAIS veredictos penalizam (padrão wa/tle/mle/rte/ce; vazio = nada penaliza).
- **Placar completo p/ logins** — allowlist de logins que veem o placar sem freeze (além de admin/juízes).

Pela CLI, tudo isso é `moj contest -c <cid> settings set chave=valor` (ex.:
`settings set manual_verdict=true review_judges=3`).

## 3. Papéis especiais — o que são e como habilitar

**Habilitar um papel é só criar a conta com o sufixo certo no login** — na aba *Usuários &
sessões* (ou `moj contest -c <cid> users add fulano.judge`). Não há caixinha de permissão: o
sufixo É o papel. O auto-cadastro público nunca cria conta com esses sufixos (reservados), e
operações em massa (reset de senha, desabilitar) **pulam** contas privilegiadas de propósito.

| Papel | Sufixo | Pode | Não pode |
|---|---|---|---|
| **Administrador** | `.admin` | Tudo: painel ⚙, submeter a qualquer hora, ver problemas antes da largada, placar sem freeze, votar como juiz, resolver conflitos, responder clarifications. | Aparecer no placar (nenhum papel aparece). |
| **Juiz (humano)** | `.judge` | Aba **⚖️ Avaliar** (correção manual), submeter/ver problemas a qualquer hora (testar a prova!), placar sem freeze, responder clarifications, Estatísticas. | Resolver conflitos; painel admin. |
| **Juiz-chefe** | `.cjudge` | Tudo do `.judge` **+** painel **👑 Juiz-chefe**: resolver conflitos de votos, editar respostas de clarification já dadas, opções e auto-veredicto. | Painel admin (Configurações etc.). |
| **Staff** | `.staff` | Fila de **🖨️ impressão e balões** (pegar/imprimir/entregar, modo automático de quiosque). | Ver problemas ou submeter (nunca); etiquetas; placar sem freeze. |
| **Chefe de sede** | `.cstaff` | Observar a fila do staff da sua sede (somente leitura), **🏷️ Etiquetas** de credenciais dos competidores e do **`.staff`** da sua sede (com senha — exceto em contest que usa contas do treino, onde a senha é pessoal e não sai na etiqueta; a credencial do próprio chefe também não sai em etiqueta), o **🎥 telão** da sede e a **🏆 revelação por sede** depois do fim. | Agir na fila de impressão; ver problemas/submeter; não herda `.staff`. |
| **Monitor** | `.mon` | Submeter DURANTE a prova (sem aparecer no placar), **responder clarifications**, Todas as Submissões e Estatísticas. | Ver problemas antes da largada; correção manual. |

Regra de ouro: **nenhuma conta com sufixo de papel entra no placar ou nas estatísticas** —
crie quantas precisar sem medo de sujar o resultado.

## 4. Correção validada por juízes (veredicto manual)

Com **Veredicto manual** ligado, o julgamento automático continua rodando, mas o veredicto
fica **retido**: o aluno vê a submissão pendente até juízes humanos validarem.

O fluxo, na aba **⚖️ Avaliar** (página do `.judge`):

1. O juiz **pega** uma submissão da fila (reserva com prazo; máx. N juízes na mesma).
2. Vê o veredicto computado, o log e o código, e **vota** (confirmar ou trocar o rótulo).
3. Quando **N votos unânimes** se acumulam (N = *Nº de juízes que validam*, padrão 2), o
   veredicto é liberado: entra no histórico do aluno e no placar na hora.
4. Votos **divergentes** viram **conflito**: o **juiz-chefe** (`.cjudge`) decide no painel dele
   (um alerta global avisa).

**Quantas pessoas você precisa?** No mínimo **N contas `.judge`** (o quórum) **+ 1 `.cjudge`**
para conflitos — e recomendo **N+1 juízes** para a fila não travar quando alguém pausa.
O `.admin` também vota (conta como juiz), mas em prova grande deixe o admin livre p/ operar.
Com **N=1** um único juiz revisa tudo (bom p/ prova pequena); N=2 é o padrão equilibrado;
N≥3 é para finais onde o veredicto precisa de banca.

## 5. Documentos da prova (Prova › Documentos)

A aba existe para o **`.admin` e para o juiz-chefe (`.cjudge`)**, e produz os documentos da
prova — cada um em **PDF e HTML**, em **português e inglês**:

| Documento | O que sai | De onde vêm os dados |
|---|---|---|
| **Informações do ambiente** (*info sheet*) | Versões de compilador de cada linguagem, limite de memória, tamanho de pilha, tempo limite por teste de cada problema e a tabela de linguagens aceitas. | Texto editável (Markdown) + dados vivos: `run/registry` (o que os juízes reportam), o `conf` do contest e o TL calibrado. |
| **Caderno da prova** | Capa + um enunciado por problema, na ordem das letras. Onde o problema tem **PDF próprio** no contest, é esse PDF que entra (diagramação preservada); senão o enunciado é renderizado. | `PROBS` do contest, `enunciados/<chave>.{pdf,html}` e, se faltar, o enunciado do banco. |
| **Folha de time limits** | Tabela `letra · nome · tempo limite`, com quebra por linguagem quando o TL difere entre elas, mais a **errata** que você escrever. | O TL **calibrado e servido** aos juízes (`run/tl`). |
| **Editorial** | A **solução** de cada problema, na ordem das letras, com uma nota introdutória opcional. Gere e revise quando quiser; o servidor **só deixa PUBLICAR depois do fim da prova** (contando prorrogações por sede) — e o time só o baixa com a prova encerrada. | O `docs/solucao.md` do **pacote** de cada problema (o texto que o autor escreveu e que nunca vai ao aluno). |

**Fluxo, do começo ao fim**

1. **Preencha os dados** (⚙️ *Dados dos documentos*): versão do caderno (`v1.0`), nota da capa
   e errata. Salve.
2. **Ajuste a capa**, se quiser (🎨 *Capa do caderno*). São três modos, nesta ordem de
   precedência: **PDF enviado** › **texto editado** › **capa padrão**. O texto editado é
   Markdown e aceita marcadores substituídos na geração: `{{CONTEST_NAME}}`, `{{DATE}}`,
   `{{N_PROBLEMS}}`, `{{N_PAGES}}`, `{{SITES}}`, `{{VERSION}}`. Envie um PDF quando a capa for
   arte pronta do evento — ela entra como está e o resto do caderno é anexado depois dela.
3. **Ajuste o texto do info sheet**, se quiser (📝): também Markdown, com os marcadores
   `{{TOOLCHAIN}}`, `{{TL_TABLE}}`, `{{LANGS_TABLE}}`, `{{MEMLIMIT}}`, `{{STACK}}`,
   `{{CONTEST_NAME}}` e `{{DATE}}`. Apagar o texto volta ao padrão embarcado.
4. **Gere** (botão de cada linha, ou *Gerar todos (pt+en)*). Converter os PDFs leva alguns
   segundos — o caderno é o mais demorado, porque junta um PDF por problema.
5. **Confira**: cada linha tem **PDF**, **HTML** e **abrir**. Reveja antes de publicar.
6. **Publique** o que a sede pode ver. Publicar faz duas coisas: o documento passa a aparecer na
   seção **Prova** da página do contest e o `.cstaff` consegue baixá-lo em **📄 Documentos**.
   **Times NÃO veem caderno/time limits publicados antes do INÍCIO da prova** — publicar cedo
   serve para a sede imprimir, sem vazar nada (o `+ notícia` desses dois é recusado antes do
   início, porque a notícia anexa o PDF). O **editorial** só publica depois do fim.
   Marcando **+ notícia**, o MOJ ainda cria uma notícia com o PDF anexado.
   **Despublicar** desfaz (o link some; a notícia, se criada, continua — apague-a na aba de
   notícias se for o caso).

**Regenerou? Publique de novo não é preciso** — o link publicado aponta para o documento atual,
então gerar de novo já entrega a versão nova a quem baixar. Mas **avise a sede**: quem já
imprimiu ficou com a versão velha (é para isso que serve o campo *versão do caderno* na capa).

> ⚠️ **Enunciado não é traduzido.** PT/EN vale para a capa, os títulos, as tabelas e o info
> sheet. O corpo do enunciado sai no idioma em que foi escrito — o MOJ guarda um enunciado por
> problema, não dois. Prova bilíngue continua exigindo dois problemas (ou um enunciado que já
> traga as duas versões).

> 🔒 **Antes de publicar, o caderno é conteúdo de prova**: só `.admin` e `.cjudge` conseguem
> baixá-lo. Para todo o resto (inclusive `.cstaff` e times) a API responde **404** — não é uma
> trava de interface.

## 6. Rodadas: aquecimento e prova oficial (Prova › Rodadas)

Toda maratona roda um **aquecimento** (dress rehearsal) antes da prova: dois ou três problemas
fáceis, no dia anterior ou na manhã do dia, para o time ligar a máquina, testar o login, o
editor, a impressão e o balão — e para a sua equipe de juízes e staff ensaiar. Depois disso a
prova começa **no mesmo contest**, porque é a configuração dele (contas, senhas, sedes, cores de
balão, time limits, linguagens, pool de juízes) que você quer garantir.

No MOJ isso são **rodadas**. A rodada **no ar** é a que aparece em Central › Regras e em Prova ›
Problemas; as demais ficam planejadas até você promover.

**O roteiro** (repare na ordem: o aquecimento vem PRIMEIRO)

1. **Monte o contest** normalmente, com os problemas do **aquecimento** e a janela do aquecimento.
2. Em Prova › Rodadas, dê o nome certo à rodada no ar (`aquecimento`, tipo *aquecimento*) e
   **crie a próxima** (`oficial`): janela, freeze e a lista de problemas da prova de verdade.
   A lista fica guardada e só entra no ar na promoção — ninguém vê os problemas da prova antes.
3. **Rode o aquecimento.** O time vê uma faixa fixa dizendo que é aquecimento e que aquele placar
   não é o da prova.
4. Quando terminar, clique **🚀 Promover**. O MOJ confere o checklist e, se estiver tudo pronto:
   - **arquiva** a rodada — submissões (com código-fonte), veredictos, log do juiz, placar,
     estatísticas, clarifications, notícias, tarefas do staff e os logs de acesso ficam guardados
     em `rounds/<rodada>/`, mais um **relatório navegável** da rodada;
   - **zera** o placar e o histórico dos times, reinicia a numeração da impressão e limpa as
     prorrogações por sede;
   - **aplica** a janela e os problemas da prova oficial.
   Você digita o id do contest para confirmar. Tudo é auditado.

**Registrei a PROVA primeiro — e agora?** Aconteceu de montar o contest já com a prova e só
depois criar a rodada de aquecimento? **Não promova** — promover arquiva a rodada no ar (a sua
prova, vazia), e arquivo é imutável. O certo é **inverter editando as duas rodadas** ali mesmo
(o painel avisa quando detecta uma planejada começando antes da que está no ar):

1. Edite a rodada **planejada**: renomeie para `prova`, tipo *prova oficial*, e dê a ela a
   janela + freeze da prova; em **Problemas da rodada**, coloque a lista da prova (fica
   guardada, ninguém vê).
2. Edite a rodada **no ar**: renomeie para `aquecimento`, tipo *aquecimento*, janela do
   aquecimento (sem freeze) e troque os problemas pelos do aquecimento — na rodada no ar,
   salvar **aplica na hora**.
3. Confira em Central › Regras que a janela vigente é a do aquecimento — e siga o roteiro
   normal a partir do passo 3.
5. **Depois**: o placar e as submissões do aquecimento continuam legíveis em 🔁 Rodadas (e você
   pode **publicar** a rodada para os times verem). O **arquivo bruto** em `.tar.gz` — com
   código-fonte — sai por um clique, para a auditoria posterior.

**O checklist é sério.** A promoção RECUSA enquanto houver:

| Bloqueador | Por quê |
|---|---|
| `round_running` | a rodada no ar não terminou (contando prorrogação por sede) |
| `jobs_in_flight` | tem submissão no spool/fila do juiz. Se ela fosse julgada depois da troca, o tempo seria calculado contra o início da prova e a submissão do aquecimento reapareceria no histórico da prova |
| `pending_verdicts` | ainda há submissão sem veredicto no histórico |
| `review_pending` | tem submissão na correção manual sem veredicto liberado — o voto do juiz cairia no placar da prova |
| `judged_down` | o daemon de julgamento não está vivo, então a fila não drena |
| `no_next_round` | não há rodada planejada |
| `shared_users` | o contest usa as contas de outro (`USERS_FROM`) — arquivar aqui mexeria no store alheio |

Há um `--force` (checkbox "ignorar os bloqueadores"), para emergência: ele **não** desfaz o
risco, só assume que você sabe o que está fazendo. Os dois últimos bloqueadores nunca são
ignorados.

**O que NÃO muda na promoção:** contas e senhas, times/sedes/bandeiras, escopo do staff, cores de
balão, regiões, time limits calibrados, linguagens, pool de juízes, matriz de auto-veredicto e os
textos/capa dos documentos. **O que zera:** placar, histórico e submissões dos times (arquivados,
não perdidos), balões, numeração de impressão, prorrogações, e a lista de documentos publicados.

> ⚠️ **Cores de balão são por LETRA.** Se o problema A do aquecimento e o A da prova são
> diferentes, a cor do balão A é a mesma nas duas rodadas. Confira em 🎨 Aparência antes da prova.

**Na CLI:** `moj contest -c <cid> rounds ls | add | set | problems | promote | publish | archive`.

## 6½. Depois da prova: encerrar o evento

Quando a prova acaba, o placar continua **congelado** e os documentos seguem **não
publicados** até alguém mandar liberar — nada disso vira automático com o relógio. A Central
passa a mostrar o bloco **"Depois da prova"** com o checklist do que ainda está fechado e o
botão **🏁 Encerrar evento**, que faz de uma vez as duas coisas que todo mundo esquece:

1. **abre o placar** — tira o congelamento (`FREEZE_TIME=0`), então o resultado final fica
   público (é o mesmo efeito do botão "🔓 Descongelar tudo" da cerimônia de revelação);
2. **publica os documentos já gerados** que ainda não estavam publicados — caderno, folha de
   limites de tempo, info sheet e editorial passam a aparecer em "Arquivos & Recursos" para
   os times. (O editorial só pode ser publicado depois do fim; por isso ele entra aqui.)

O botão **não** mexe no resto: liberar o **relatório de correção** para os times (`SHOWLOG`),
abrir o **código das outras equipes** (`SHOWCODE`), mostrar os **limites de tempo** e
**liberar as coortes** (convidados) continuam sendo escolha sua — cada um aparece no
checklist com o atalho "resolver →" para a tela certa. Só roda depois que a prova terminou
**para todas as sedes** (prorrogação por sede conta) e pode ser repetido à vontade: na
segunda vez ele não faz nada.

Fecha o ciclo com o **relatório final** (Operação › Situação): o `tar.gz` navegável leva o
placar aberto, as submissões, as estatísticas completas, os enunciados **e** os documentos
publicados — é o pacote que se manda para os participantes e para o arquivo do evento.

## 7. Máquinas dos times (Pessoas › Máquinas & gate)

É no aquecimento que os times ligam de fato os computadores — e é dali que o MOJ tira o mapa
**time × IP × navegador** da sala (do log de acessos do contest, recortado pela janela da rodada:
nada novo é capturado). A aba mostra, por rodada:

- **por time**: nome, sede, IPs e navegadores usados, primeiro login e um alerta quando o time
  usou **mais de um IP**;
- **por IP**: quais times vieram de cada máquina — e marca **IP compartilhado** (dois times na
  mesma máquina é sinal de mesa trocada ou conta emprestada);
- **quem trocou de máquina**: na prova oficial, o time que loga de IP/navegador diferente do que
  usou no aquecimento aparece marcado em vermelho;
- **⇣ CSV** de tudo, para conferir com a planilha da sede.

Duas ações saem daqui e escrevem no lugar de sempre:

- **aplicar sede**: na visão por IP, digitar o nome da sede e clicar grava a **sede** dos times
  daquele IP (o mesmo campo de Pessoas › Times) — o placar, as etiquetas e o escopo do staff passam
  a respeitá-la;
- **configurar o gate de navegador**: a seção 🔒 no topo da aba (logo abaixo) — os navegadores
  realmente vistos na rodada ficam listados lá, e cada um pode virar o *fallback* com um clique.

### O gate POR SEDE (o caso da maratona)

Quando cada sede roda a **sua** imagem, o UA de cada máquina carrega um pedaço do próprio login
do time: `teambrspso001` (Brasil/BR, São Paulo/SP, Sorocaba/SO) roda numa imagem cujo UA contém
`brspso`. Uma substring única não serve — então o MOJ **deriva o esperado do login**.

**Na web** (seção 🔒 no topo de Pessoas › Máquinas & gate): a chave **"Barrar quem não vem da imagem da
sede"** liga/desliga; abaixo dela vão a **regex do login com captura** e o **UA esperado** (`\1`),
com um **testador ao vivo** ("testar com o login" → *UA precisa conter `brspso` · sede Sorocaba*),
e três listas dobráveis — **overrides por sede**, **regras por regex de login** e **isentos**.
Salvar já vale para o próximo login.

**Na CLI**, o mesmo:

```
moj contest -c <cid> ua-gate set --from-login '^team([a-z]{6})[0-9]{3}$' --expect '\1'
moj contest -c <cid> ua-gate set --region 'Sorocaba=brspso-v2'     # sede fora do padrão
moj contest -c <cid> ua-gate set --exempt '^ccl' --exempt time-reserva-07
moj contest -c <cid> ua-gate check teambrspso001                   # o que se espera dele
moj contest -c <cid> ua-gate show
```

Uma regra cobre **todas as sedes de uma vez**. A ordem de resolução é: **isentos** › conta de
papel (sempre entra) › regra por regex › **override da sede** › captura no login › substring
única (o `login_ua_substring` de sempre, que continua valendo como último recurso).

- Quem não casa é **barrado no login** (403) — a decisão foi barrar, com a lista de **isentos**
  como margem. `--mode off` desliga o gate sem apagar a configuração.
- O painel Máquinas & gate mostra **UA esperado × UA visto** por time e conta quantos estão fora da
  imagem da sede: é assim que se conserta a sala **no aquecimento**, antes de o gate barrar
  alguém na prova.
- Quem já está logado com o navegador errado sai com **"Deslogar UA divergente"** (Pessoas › Sessões),
  que agora compara cada sessão com o esperado **daquele** time.

## 8. Times convidados (coortes de placar)

Maratona convida times que **competem sem entrar na disputa oficial** — o pessoal chama de
convidado, extra-oficial, "CCL". O MOJ trata isso como **coorte**: um grupo de times com política
de visibilidade própria.

**O que uma coorte privada garante**

- os times dela **não aparecem no placar público**;
- os times regulares **não sabem que ela existe** — nem no placar, nem no diretório de times
  (`/contest/teams`, que é público e listava todo login);
- os **próprios convidados veem todos** (o placar deles traz oficiais + convidados);
- quando você **libera os resultados**, todo mundo passa a ver todos, e o convidado aparece
  **intercalado pelo desempenho mas sem consumir posição oficial** — o pódio combinado continua
  batendo com o oficial.

**Como configurar (Pessoas › Coortes)**

Uma linha por coorte, com o que decide o comportamento: **id**, **nome**, **regex do login**,
**pública** (aparece no placar público), **extra-oficial** (entra sem consumir posição), **padrão**
(quem não casa nada cai nela) e **vê** — as caixas que dizem quais coortes aquela visão enxerga
(a coorte sempre vê a si mesma). A coluna **times** conta quantos estão em cada uma.

- **+ criar coorte**: nasce privada e extra-oficial vendo todas — que é o caso do CCL.
- **atribuir**: escolhe um time e a coorte dele (o campo vence a regex); "— pela regra —" solta o
  time de volta para o regex.
- **📌 Materializar (N)**: carimba a coorte de quem hoje só casa por regex — depois disso, mudar o
  regex não remaneja ninguém. O contador diz quantos times estão nessa situação.
- **🔓 Liberar resultados**: pede o **id do contest** digitado para confirmar (é irreversível na
  prática — o placar público passa a mostrar todos).
- **Placares gerados**: as visões que o `build.sh` mantém (uma por coorte que vê um conjunto
  diferente, mais a pública).

Para mudar a coorte **padrão**, marque o rádio da outra linha e salve **aquela** linha. Remover
uma coorte exige que ela esteja **vazia** (e a padrão nunca é removível).

**A mesma coisa na CLI:**

```
moj contest -c <cid> cohorts ls
moj contest -c <cid> cohorts add ccl --name "Café com Leite" --regex ccl --private --unranked
moj contest -c <cid> cohorts assign timeconvidado07 ccl     # convidado sem 'ccl' no login
moj contest -c <cid> cohorts materialize                    # carimba a regra em campo por time
moj contest -c <cid> cohorts release                        # o "liberamos tudo" (pede o id)
```

A coorte casa por **regex no login** e/ou pelo campo `.team.cohort` de cada time (o campo vence).
`materialize` transforma a regra em dado: depois disso, mudar o regex não remaneja ninguém.
Quem não casa nada cai na coorte **default** (a dos oficiais).

**O que continua completo, de propósito** — são papéis privilegiados, e você precisa deles:
**⚖️ Todas as Submissões**, **📊 Estatísticas** (inclusive quem resolveu primeiro), a **fila do
staff** (o balão do convidado tem de ser entregue) e o **relatório final**. Duas consequências
práticas:

- **não** ligue "ver código das submissões" (`SHOWCODE`) numa prova com convidados: ela abre o
  fonte de qualquer submissão para qualquer login;
- **publicar o arquivo de uma rodada** (Prova › Rodadas) exige os resultados liberados quando há
  coorte privada — o relatório da rodada traz o placar aberto com todos.

> ℹ️ Sobram dois canais **numéricos** que não escondem identidade mas existem: a página de status
> pública conta as submissões pendentes de **todos** os times, e a numeração de tarefas de
> impressão é única por contest (saltos indicam atividade que o time não vê).

## 8½. Inscrição prévia e times de 3 contas do treino

Vale para contest criado com **"usuários compartilhados do Treino Livre"**. Ligando a inscrição
(Pessoas › Inscrições → **Ligar inscrição**), o contest passa a ter uma **porta**: quem não se
inscreveu **não entra** (a API recusa o login, não é só a tela).

**Como a pessoa se inscreve:** no site principal, logada no treino, em
`/contests/inscricao/?c=<id>` (o cartão do contest na home ganha o botão **📝 Inscreva-se**).
Ela escolhe **individual** ou **criar um time**: dá um nome e convida até 2 logins do treino;
cada convidado precisa **aceitar**. Enquanto a janela estiver aberta dá para sair, renomear e
desfazer. Participação é exclusiva — aceitar convite desfaz a inscrição individual.

**O convite avisa sozinho.** No instante em que o capitão convida, o **mojinho manda uma DM** ao
convidado com o link de aceitar/recusar; e na **véspera do fechamento** (24 h antes) manda **um
único** último aviso para quem ainda não respondeu (a mensagem sai em português; se o contest
estiver com `LOCALE=en`, vai em inglês **e** português no mesmo texto — DM não tem seletor de
idioma). Só alcança quem tem **Telegram vinculado**
(perfil do treino → 📨 Telegram) — por isso a lista de convites mostra `📨` (alcançável) ou `⚠️`
(sem canal), e o resumo conta quantos ficaram sem. Na tabela de times, cada convite pendente tem
o botão **🔔** para cutucar na hora, e o cabeçalho tem **🔔 Lembrar todos**; cutucar à mão **não**
cancela o aviso automático da véspera. Para desligar o automático neste contest, desmarque
*lembrete automático* na caixa da janela (grava `REG_REMIND=n`). Isso importa porque **quem não
aceita o convite não entra no time** — e às vezes nem está inscrito.

**Na prova, cada membro entra com o PRÓPRIO login e senha do treino** e a sessão vira a do time:
o placar, os balões e a impressão veem **uma linha só**. Quem estava no teclado fica registrado
(`var/actor-log` e a 5ª coluna do `var/access.log`) — útil para conferir depois.

**A janela** (Pessoas › Inscrições → *Janela de inscrição*): `abre` (vazio = já aberta), `fecha`
(vazio = o início da prova) e **`atraso (min)`** — minutos após o início em que ainda dá para
entrar, mas na coorte `…-atrasado`, que aparece no placar **sem ocupar posição** (é a *extra
registration* do Codeforces). Passou disso, a porta fecha.

**Em que relógio estão esses campos:** no do **seu navegador** — a caixa mostra qual é, logo
abaixo. Já as horas que o **MOJ escreve para as pessoas** (a DM do mojinho, o checklist
pré-prova, a data do caderno, o relatório final) saem no **fuso da prova**, que você define em
*Configurações → 🌎 Fuso horário da prova* (vazio = `America/Sao_Paulo`). Quando os dois relógios
diferem, a caixa da janela mostra também o horário no fuso da prova, para não haver dúvida.

**Placar:** a inscrição semeia as coortes `individual` e `times`, cada uma com **placar próprio**
— o seletor "Placar: Geral | Times | Individual" aparece sozinho na página do placar. Se o
contest já tinha coortes configuradas, o checklist pré-prova avisa que faltam essas duas.

**Com AQUECIMENTO (o esquenta que fica dias no ar):** planeje as duas rodadas em *Prova → Rodadas*
(aquecimento agora, prova oficial na data real). Por padrão **o aquecimento também exige
inscrição** — é nele que o competidor resolve login, submissão e placar; deixar entrar sem
inscrição só empurra o problema para o dia da prova. A inscrição fecha sozinha **no início da
prova oficial** (é essa data que o "fecha" herda, não a do aquecimento). Se você preferir o
aquecimento de porta aberta (qualquer conta da fonte entra sem inscrição), ligue
`REG_WARMUP_OPEN=y` no conf — nesse caso a **promoção** derruba a sessão de quem não se
inscreveu e o placar da prova nasce só com os inscritos; o painel mostra o selo
*🔥 aquecimento: entrada livre* enquanto isso vale.

**O modo de participação é definitivo:** depois de inscrito (individual ou em time), o competidor
não cancela nem troca de modo sozinho — a página de inscrição deixa isso claro antes da escolha, e
qualquer mudança passa por você (Pessoas › Inscrições: remover, dissolver, inscrever à mão).

**O time também declara na inscrição:** a **universidade** (vira o prefixo `[SIGLA] Nome do Time`
no placar e a coluna/filtro de escola), o **uso de IA** (aparece como 🤖 ao lado do nome — é
transparência, não julgamento), a **bandeira** (país ou estado do Brasil — a bandeirinha do
placar) e uma **foto do time** (o 📷 do placar; reprocessada no servidor, sem metadados). Tudo editável pelo capitão enquanto a janela estiver aberta, e visível no seu
painel e no CSV. **O inscrito INDIVIDUAL declara as mesmas coisas** (menos a foto):
universidade, IA e bandeira, na inscrição ou depois, pela mesma página. A organização ajusta
qualquer um pelas ações `team-meta`/`individual-meta` do painel — sem regra regex no
`teams-meta.json` (o mecanismo legado continua valendo só como sobreposição visual).

> Dica de dia de prova: o checklist da Central mostra quantos se inscreveram e **quantos convites
> ficaram pendentes** — convite não aceito significa gente achando que está no time e que, na
> hora, não entra.

## 9. Template de usuários (habilita todas as funções)

Cole na carga em lote de *Pessoas › Contas* (uma linha por conta: `login nome`), ou crie
um a um com `moj contest -c <cid> users add <login> --name "<nome>"`:

```
juiz1.judge      Juiz Um
juiz2.judge      Juiz Dois
juiz3.judge      Juiz Três (reserva do quórum de 2)
chefe.cjudge     Juiz Chefe
apoio1.staff     Staff de impressão e balões
sede1.cstaff     Chefe da Sede 1 (etiquetas + revelação)
monitor1.mon     Monitor (responde clarifications)
```

Depois: ligue **Veredicto manual** (e ajuste o **Nº de juízes**) em Central › Regras; distribua
as senhas geradas; cada pessoa loga na MESMA tela do contest e vê os botões do seu papel.

## 10. Referências

- [Manual do juiz humano](MANUAL-JUIZ.md) — a operação da aba ⚖️ Avaliar e do juiz-chefe.
- [Manual do staff](MANUAL-STAFF.md) — impressão, balões, etiquetas, revelação por sede.
- [Manual do competidor](MANUAL-CONTEST.md) — o que o aluno vê (distribua com as senhas).
- [Tutorial do organizador](/treino/criar/tutorial.html) — criar o contest (wizard e CLI).
- [CLI do competidor](/contest/cli.html) — envio pelo terminal, com modo sem-Internet.
