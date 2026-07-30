# MOJ: Manual do organizador (o painel .admin do contest)

Este manual é para quem **opera** um contest: o dono da conta `.admin`. Ele explica cada aba do
painel de administração, cada opção de configuração, **como habilitar os papéis especiais**
(`.judge`, `.cjudge`, `.staff`, `.cstaff`, `.mon`), e como ligar a **correção validada por
juízes** — incluindo quantas pessoas você precisa.

> Criar o contest (wizard, problemas, contas) é o outro guia: o
> [tutorial do organizador](/treino/criar/tutorial.html). Aqui é a OPERAÇÃO, do dia da prova.

Você chega ao painel logando com a conta `.admin` do contest e clicando em **⚙ Administração**
na barra do topo.

## 1. As abas do painel

| Aba | O que faz |
|---|---|
| **📊 Situação** | O dashboard ao vivo (atualiza sozinho a cada ~12s): quem está logado, juízes de máquina online/ocupados, fila de julgamento, submissões pendentes, tarefas de impressão/balão abertas e o estado da avaliação manual. Os botões **🏆 Cerimônia de revelação** e **📦 Relatório estático** ficam aqui. |
| **✅ Pré-prova** | Checklist verde/amarelo/vermelho do que ainda bloqueia começar (problemas sem enunciado, TL não calibrado, login fechado…). Rode antes de toda prova. |
| **⚙️ Configurações** | Todas as opções do contest — a seção 2 explica uma a uma. Inclui a **⏱ Prorrogação por sede/grupo** (regras regex → novo fim; só estende, nunca encurta). |
| **📚 Problemas** | A prova em si: renomear/reordenar/remover problemas, restringir linguagens ou o pool de juízes POR problema, atualizar o enunciado a partir do banco, e **Adicionar do banco** (busca e sorteio). |
| **👥 Times** | Identidade de cada conta no placar: nome do time, país/bandeira, sede/região, universidade, brasão. Carga por CSV e "materializar matches" das regras por regex. |
| **🎨 Aparência** | Cores dos balões por problema, países/escolas por regex e filtros de região do placar. |
| **👥 Usuários & sessões** | Criar/resetar/desabilitar contas (individual e em lote), trocar a senha de todos, **sessões ativas** (alertas de multi-IP/UA, deslogar), log de acessos por dia (CSV) e download dos backups dos usuários. É AQUI que você cria as contas de papel (seção 3). |
| **🔁 Rodadas** | **Aquecimento e prova oficial no MESMO contest**: planeja cada rodada (janela + lista de problemas), mostra o checklist e promove — arquivando tudo o que aconteceu. A seção 6 explica. |
| **💻 Máquinas** | De onde cada time logou (IP e navegador) em cada rodada, com CSV: mapeia a sala no aquecimento, marca quem trocou de máquina na prova, preenche a sede dos times e arma o gate de navegador. |
| **📄 Documentos** | Gera, em PDF e HTML e nos dois idiomas, os três documentos impressos da prova: **informações do ambiente** (info sheet), **caderno da prova** (capa + enunciados) e **folha de time limits**. Baixa, publica para a sede e, se você quiser, vira notícia com o PDF anexo. A seção 5 explica. |
| **🖨️ Tarefas do staff** | Panorama e ação sobre a fila de impressão + balões, desempenho por staff e o escopo de cada staff (regex por sede/sala). |
| **⚖️ Tarefas do judge** | A fila da correção manual: quem pegou cada submissão, votos, idade; decidir/resolver na hora; e a configuração do veredicto manual (opções de rótulo + matriz de auto-veredicto). |
| **🧾 Auditoria** | Feed unificado de tudo que aconteceu (ações de admin, logins, submissões, veredictos), com filtros e download CSV. |

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

- **Linguagens** — a lista permitida no contest (cada problema pode restringir mais, na aba Problemas).
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
| **Chefe de sede** | `.cstaff` | Observar a fila do staff da sua sede (somente leitura), **🏷️ Etiquetas** de credenciais (com senha!) da sua sede, e a **🏆 revelação por sede** depois do fim. | Agir na fila de impressão; ver problemas/submeter; não herda `.staff`. |
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

## 5. Documentos da prova (aba 📄 Documentos)

A aba existe para o **`.admin` e para o juiz-chefe (`.cjudge`)**, e produz os três documentos
que a prova imprime — cada um em **PDF e HTML**, em **português e inglês**:

| Documento | O que sai | De onde vêm os dados |
|---|---|---|
| **Informações do ambiente** (*info sheet*) | Versões de compilador de cada linguagem, limite de memória, tamanho de pilha, tempo limite por teste de cada problema e a tabela de linguagens aceitas. | Texto editável (Markdown) + dados vivos: `run/registry` (o que os juízes reportam), o `conf` do contest e o TL calibrado. |
| **Caderno da prova** | Capa + um enunciado por problema, na ordem das letras. Onde o problema tem **PDF próprio** no contest, é esse PDF que entra (diagramação preservada); senão o enunciado é renderizado. | `PROBS` do contest, `enunciados/<chave>.{pdf,html}` e, se faltar, o enunciado do banco. |
| **Folha de time limits** | Tabela `letra · nome · tempo limite`, com quebra por linguagem quando o TL difere entre elas, mais a **errata** que você escrever. | O TL **calibrado e servido** aos juízes (`run/tl`). |

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

## 6. Rodadas: aquecimento e prova oficial (aba 🔁 Rodadas)

Toda maratona roda um **aquecimento** (dress rehearsal) antes da prova: dois ou três problemas
fáceis, no dia anterior ou na manhã do dia, para o time ligar a máquina, testar o login, o
editor, a impressão e o balão — e para a sua equipe de juízes e staff ensaiar. Depois disso a
prova começa **no mesmo contest**, porque é a configuração dele (contas, senhas, sedes, cores de
balão, time limits, linguagens, pool de juízes) que você quer garantir.

No MOJ isso são **rodadas**. A rodada **no ar** é a que aparece em ⚙️ Configurações e 📚
Problemas; as demais ficam planejadas até você promover.

**O roteiro**

1. **Monte o contest** normalmente, com os problemas do **aquecimento** e a janela do aquecimento.
2. Na aba 🔁 Rodadas, dê o nome certo à rodada no ar (`aquecimento`, tipo *aquecimento*) e
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

## 7. Máquinas dos times (aba 💻 Máquinas)

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
  daquele IP (o mesmo campo da aba 👥 Times) — o placar, as etiquetas e o escopo do staff passam
  a respeitá-la;
- **armar o gate de navegador**: o MOJ calcula a **substring comum** aos navegadores vistos e
  oferece usá-la como gate único. Se os navegadores forem diferentes, ele diz isso em vez de
  sugerir algo que trancaria alguém fora.

### O gate POR SEDE (o caso da maratona)

Quando cada sede roda a **sua** imagem, o UA de cada máquina carrega um pedaço do próprio login
do time: `teambrspso001` (Brasil/BR, São Paulo/SP, Sorocaba/SO) roda numa imagem cujo UA contém
`brspso`. Uma substring única não serve — então o MOJ **deriva o esperado do login**:

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
- A aba 💻 Máquinas mostra **UA esperado × UA visto** por time e conta quantos estão fora da
  imagem da sede: é assim que se conserta a sala **no aquecimento**, antes de o gate barrar
  alguém na prova.
- Quem já está logado com o navegador errado sai com **"Deslogar UA divergente"** (aba Usuários),
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

**Como configurar** (CLI hoje; a aba web é o próximo passo):

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
- **publicar o arquivo de uma rodada** (aba 🔁 Rodadas) exige os resultados liberados quando há
  coorte privada — o relatório da rodada traz o placar aberto com todos.

> ℹ️ Sobram dois canais **numéricos** que não escondem identidade mas existem: a página de status
> pública conta as submissões pendentes de **todos** os times, e a numeração de tarefas de
> impressão é única por contest (saltos indicam atividade que o time não vê).

## 9. Template de usuários (habilita todas as funções)

Cole na carga em lote da aba *Usuários & sessões* (uma linha por conta: `login nome`), ou crie
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

Depois: ligue **Veredicto manual** (e ajuste o **Nº de juízes**) nas Configurações; distribua
as senhas geradas; cada pessoa loga na MESMA tela do contest e vê os botões do seu papel.

## 10. Referências

- [Manual do juiz humano](MANUAL-JUIZ.html) — a operação da aba ⚖️ Avaliar e do juiz-chefe.
- [Manual do staff](MANUAL-STAFF.html) — impressão, balões, etiquetas, revelação por sede.
- [Manual do competidor](MANUAL-CONTEST.html) — o que o aluno vê (distribua com as senhas).
- [Tutorial do organizador](/treino/criar/tutorial.html) — criar o contest (wizard e CLI).
- [CLI do competidor](/contest/cli.html) — envio pelo terminal, com modo sem-Internet.
