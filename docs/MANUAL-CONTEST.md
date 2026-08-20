# MOJ: Manual do competidor (contest)

> **Você ORGANIZA a prova?** O guia do organizador (criar e gerenciar contests, web e CLI) é
> outro: [/treino/criar/tutorial.html](/treino/criar/tutorial.html). Este manual aqui é o que
> você distribui aos competidores.

Este manual é para você que vai participar de uma maratona ou prova no MOJ (o juiz online). Aqui você aprende a entrar no contest, enviar suas soluções, ler o placar, tirar dúvidas (clarifications), pedir impressão e usar o backup.

> **Prefere o terminal?** Existe a CLI do competidor, **`moj-comp`** — envia soluções, acompanha
> veredictos e placar, e tem o modo emergencial de **queda de Internet** (a submissão fica
> guardada cifrada com o horário e conta certo quando a rede volta). Guia completo:
> [/contest/cli.html](/contest/cli.html).

Se você só quer saber como enviar em cada linguagem e como funciona a entrada e a saída dos programas, veja a página **Ajuda** (`/treino/ajuda/`). Ela abre **de dentro da prova**, pelo link **"📖 Como enviar"** que fica ao lado do seletor de linguagem, na hora do envio.

## 1. Antes de tudo: a inscrição

Boa parte das competições do MOJ usa as **contas do Treino Livre** — você compete com o mesmo
login e a mesma senha que usa para treinar. Nesses contests, **entrar exige inscrição prévia**:
tentar logar sem estar inscrito devolve um recado (*você não está inscrito*, *as inscrições ainda
não abriram* ou *já fecharam*) com o link da página certa.

A inscrição fica no **site principal**, não no endereço da prova: `/contests/inscricao/?c=<id>`
(o subdomínio do contest não enxerga a sua sessão do treino — é por isso que são endereços
diferentes).

**Individual ou em time.** Você escolhe o modo na inscrição, e essa escolha é **definitiva** para
você: trocar depois é com a organização. Em time:

- alguém **cria** o time e convida os outros pelo login do treino (cada convidado recebe um aviso
  do bot no Telegram, se tiver vinculado);
- o time tem um limite de integrantes (normalmente 3);
- **cada pessoa entra com a própria senha do treino** — a prova é do time, mas o MOJ registra quem
  estava no teclado em cada submissão.

**O que o time (ou você, sozinho) declara**: a universidade (a sigla que aparece no placar), a
bandeira, se vai usar **IA** durante a prova (vira o 🤖 no placar) e, no caso de time, a **foto**
que aparece no telão quando vocês resolvem um problema.

> **Aquecimento também exige inscrição.** Por padrão a inscrição vale para *todas* as rodadas do
> contest, o aquecimento incluso — a janela de inscrição é ancorada na **prova oficial**, então
> ela pode fechar antes de o aquecimento acabar. Não deixe para o último dia.

## 2. Entrar no contest

Você acessa o contest por um link no formato `/contest/?c=<id>` (ou por um subdomínio que a organização informar). Troque `<id>` pelo identificador do seu contest.

Antes de fazer login, você já vê:

- O nome do contest.
- Os horários de **Início** e **Término**.

O que aparece depois disso depende do momento:

| Situação | O que você vê |
|---|---|
| O login ainda não abriu | Uma **contagem regressiva** com "Abertura em HH:MM:SS". A página se atualiza sozinha, então, se a organização adiar ou adiantar a abertura, a mudança aparece na hora. |
| O login abriu | Um cartão de login com os campos **Usuário** e **Senha** e o botão **Entrar**. |

O idioma da tela é definido pelo contest e pode estar em inglês.

Se você fizer login **antes de a prova começar**, verá a tela "A competição ainda não começou", com uma contagem regressiva. Não é preciso ficar recarregando: os problemas aparecem sozinhos quando a prova começar.

## 3. Página principal (depois de logar)

No topo há uma barra com:

- O nome do contest.
- Uma contagem regressiva: "Termina em: HH:MM:SS" e, quando o tempo acaba, "Competição encerrada".
- O botão **Sair**.

Logo abaixo há um menu de navegação com **Contest**, **Score** (placar), **Clarification** e, às vezes, **Backup** e **Impressão**.

Um **aviso** no topo mostra quando há "novas notícias" e "clarifications respondidas". Ele pisca quando existe uma dúvida sua que foi respondida e você ainda não leu.

Se a prova tiver um **aquecimento** (rodada de ensaio antes da prova oficial), uma faixa fixa
avisa no topo: *"🔁 AQUECIMENTO — esta rodada serve para testar o ambiente e a sua conta: o placar
dela NÃO é o da prova"*. É a hora de conferir login, editor, envio, impressão e balão — e de
avisar o staff se algo estiver errado. Quando o aquecimento acaba, a organização coloca a prova
oficial no ar **no mesmo endereço, com o mesmo login**: o placar volta a zero e os problemas
mudam. O placar e as suas submissões do aquecimento continuam disponíveis (link **Rodadas
encerradas** em *Arquivos & Recursos*), quando a organização os publica.

Quando existirem, aparecem também as seções **Informações & Notícias** e **Arquivos & Recursos**.
Em **Arquivos & Recursos** é onde a organização publica os documentos da prova quando quer que
você os tenha em mãos. São até quatro: as **informações do ambiente** (versões de compilador,
limites de memória e de tempo), o **caderno da prova**, a **folha de time limits** e o
**editorial** (as soluções — esse só aparece depois que a prova acaba para *todas* as sedes).

Cada documento é uma linha com o nome à esquerda e os **idiomas como botões**: `PT`, `EN`, `ES`.
O nome não é clicável — clique no idioma que você quer. Caderno e folha de time limits só abrem
**a partir do início da prova**, mesmo que já apareçam na lista; se a organização não publicou
nada, a seção nem aparece.

### A lista de problemas

A lista de problemas é um acordeão. Cada linha tem:

- Um **triângulo** para abrir e fechar o problema.
- Um **balão** que fica colorido quando você resolve aquele problema.
- O nome curto e o nome completo do problema.
- À direita, os links do enunciado (**Enunciado**, **HTML**, **PDF**) e um **envio rápido** por arquivo.

Ao abrir um problema, você vê os tempos-limite. Se a organização habilitou o editor, aparece um editor lado a lado com o enunciado, com as opções **Lado a lado**, **Só enunciado** e **Só editor**.

Para enviar uma solução:

1. Escolha a **linguagem**.
2. Digite o código no editor ou envie um **arquivo**.
3. Clique em **Enviar solução**.

> **O que o MOJ aceita.** A extensão do arquivo tem de ser de uma linguagem que a plataforma
> roda — e, se o problema restringe as linguagens, de uma das permitidas ali. Mandar um binário
> compilado (`.exe`), um PDF ou um `.zip` é recusado **na hora**, com a lista do que aquele
> problema aceita: nenhum juiz do mundo roda um `.exe`, e antes essa submissão entrava na fila e
> ficava pendente para sempre. O tamanho do código é limitado a **1 MB**.
>
> Se a resposta for um erro em vez de "enviada", **leia a mensagem**: ela diz exatamente o que
> houve. Uma submissão só é aceita quando o servidor confirma — não existe "sumiu no caminho".

## 4. Minhas submissões

Logo abaixo da lista de problemas há um filtro por problema e uma tabela com as suas submissões. As colunas são:

| Coluna | O que mostra |
|---|---|
| Tempo | Minutos desde o início do contest. |
| Problema | Qual problema você enviou. |
| Arquivo | O nome do arquivo; o link **cód** baixa o seu fonte. |
| Resultado | O veredicto do julgamento. |
| Data | Quando a submissão foi feita. |
| Log | Aparece quando ver o log está liberado; abre o relatório do julgamento. |

Você vê **sempre o veredicto canônico** (sem o placar embutido), com uma linha de resumo conforme o modo do contest. Enquanto houver alguma submissão pendente, a lista se atualiza sozinha.

A coluna (ou link) **Log** abre o relatório do julgamento. Em provas no modo **ICPC** o log costuma vir oculto por padrão, para evitar vazamento dos testes, e a organização pode ligar ou desligar essa opção.

## 5. Placar (`/contest/score/?c=<id>`)

> **Antes de a prova começar** o placar é uma **vitrine**: mostra os times inscritos e mais nada —
> sem nenhuma coluna de problema. É de propósito: quantos problemas a prova tem também é surpresa.

O placar se atualiza sozinho e anima quem sobe e quem desce. Ele tem:

- Uma barra de **filtros**: qual placar (quando a prova tem coortes — *oficial* × *convidados*,
  ou *times* × *individual*), bandeira, universidade, sede e uma **busca** por time, universidade
  ou login. Filtrar **não renumera** ninguém: as posições continuam as do placar inteiro, e um
  contador mostra quantas linhas sobraram.
- Caixas para **desligar a animação** e para o modo **Anônimo** (a prova pode deixá-lo ligado à
  força — aí você não desmarca).

No modo **ICPC**, as colunas são: posição, bandeira, equipe, uma coluna por problema, **Total** e **Penal.** (a soma das penalidades, que é o primeiro desempate). Na célula da equipe podem aparecer 📷 (o time mandou foto para o telão) e 🤖 (o time declarou uso de IA na inscrição). Em cada célula de problema:

| Célula | Significado |
|---|---|
| Em branco | Você não tentou aquele problema. |
| Tentativas e minutos em célula colorida | Problema resolvido. |
| Com **★** e contorno | Você foi o primeiro a resolver aquele problema. |
| Tentativas e "-" em célula amarela | Você tentou e ainda não resolveu. |

No modo **OBI**, cada problema mostra os **pontos** obtidos.

Durante o **congelamento (freeze)**, você vê o placar congelado, igual a todo mundo. O que mudar depois do congelamento aparece como pendente.

No modo **anônimo**, o placar vira uma visão agregada, sem nomes.

Algumas provas têm **times convidados** (extra-oficiais). Se você for um deles, uma faixa avisa no
topo do placar: você aparece nele, mas fora da classificação oficial — a sua linha vem marcada
**convidado** e sem número de posição. O placar que você vê inclui os times oficiais; o placar
deles não inclui os convidados até a organização liberar os resultados.

Se o contest for secreto e você não estiver logado, é preciso entrar para conseguir ver o placar.

## 6. Clarifications (`/contest/clarification/?c=<id>`)

Para usar as clarifications você precisa estar logado.

Para fazer uma pergunta:

1. Escolha o **problema** (ou selecione **Geral**).
2. Escreva a sua pergunta.
3. Clique em **Enviar**.

A sua identidade fica **anônima para os juízes**.

Na lista você vê:

- As suas perguntas, marcadas com **P:** (pergunta) e **R:** (resposta).
- Os **avisos oficiais**, que são comunicados públicos da organização.

O aviso no topo da página principal sinaliza quando uma dúvida sua foi respondida.

## 7. Impressão (`/contest/print/?c=<id>`)

A impressão aparece só quando existe equipe de impressão e a organização habilitou o recurso.

Para pedir uma impressão:

1. Escolha um **arquivo** (PDF, imagem, texto ou código, até 10 MB).
2. Clique em **Pedir impressão**.

Sai uma folha de rosto com o nome do seu time e um número de conferência. A equipe da sua sede imprime e **entrega em mãos**.

Em **Meus pedidos** você acompanha o status de cada pedido: pendente, processada ou entregue.

## 8. Backup (`/contest/backup/?c=<id>`)

O backup é um espaço privado para você guardar versões das suas soluções.

- **Não conta como submissão** e só você vê o que está lá.
- Você envia um arquivo (até 10 MB) e pode baixar ou apagar quando quiser.

O backup aparece a menos que a organização o desligue.

## Para saber mais

Como enviar em cada linguagem e como funciona a entrada e a saída dos programas estão na página **Ajuda** (`/treino/ajuda/`), que abre de dentro da prova pelo link "📖 Como enviar", ao lado do seletor de linguagem.
