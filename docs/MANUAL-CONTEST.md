# MOJ: Manual do competidor (contest)

Este manual é para você que vai participar de uma maratona ou prova no MOJ (o juiz online). Aqui você aprende a entrar no contest, enviar suas soluções, ler o placar, tirar dúvidas (clarifications), pedir impressão e usar o backup.

Se você só quer saber como enviar em cada linguagem e como funciona a entrada e a saída dos programas, veja o `MANUAL-LINGUAGENS.md`.

## 1. Entrar no contest

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

## 2. Página principal (depois de logar)

No topo há uma barra com:

- O nome do contest.
- Uma contagem regressiva: "Termina em: HH:MM:SS" e, quando o tempo acaba, "Competição encerrada".
- O botão **Sair**.

Logo abaixo há um menu de navegação com **Contest**, **Score** (placar), **Clarification** e, às vezes, **Backup** e **Impressão**.

Um **aviso** no topo mostra quando há "novas notícias" e "clarifications respondidas". Ele pisca quando existe uma dúvida sua que foi respondida e você ainda não leu.

Quando existirem, aparecem também as seções **Informações & Notícias** e **Arquivos & Recursos**.

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

## 3. Minhas submissões

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

## 4. Placar (`/contest/score/?c=<id>`)

O placar se atualiza sozinho e anima quem sobe e quem desce. Ele tem:

- Uma **busca** por time, universidade ou login.
- Uma opção para **desligar a animação**.
- Às vezes um botão **Anônimo** e filtros por região, país ou escola.

No modo **ICPC**, as colunas são: posição, bandeira, equipe, uma coluna por problema e **Total**. Em cada célula de problema:

| Célula | Significado |
|---|---|
| Em branco | Você não tentou aquele problema. |
| Tentativas e minutos em célula colorida | Problema resolvido. |
| Com **★** e contorno | Você foi o primeiro a resolver aquele problema. |
| Tentativas e "-" em célula amarela | Você tentou e ainda não resolveu. |

No modo **OBI**, cada problema mostra os **pontos** obtidos.

Durante o **congelamento (freeze)**, você vê o placar congelado, igual a todo mundo. O que mudar depois do congelamento aparece como pendente.

No modo **anônimo**, o placar vira uma visão agregada, sem nomes.

Se o contest for secreto e você não estiver logado, é preciso entrar para conseguir ver o placar.

## 5. Clarifications (`/contest/clarification/?c=<id>`)

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

## 6. Impressão (`/contest/print/?c=<id>`)

A impressão aparece só quando existe equipe de impressão e a organização habilitou o recurso.

Para pedir uma impressão:

1. Escolha um **arquivo** (PDF, imagem, texto ou código, até 10 MB).
2. Clique em **Pedir impressão**.

Sai uma folha de rosto com o nome do seu time e um número de conferência. A equipe da sua sede imprime e **entrega em mãos**.

Em **Meus pedidos** você acompanha o status de cada pedido: pendente, processada ou entregue.

## 7. Backup (`/contest/backup/?c=<id>`)

O backup é um espaço privado para você guardar versões das suas soluções.

- **Não conta como submissão** e só você vê o que está lá.
- Você envia um arquivo (até 10 MB) e pode baixar ou apagar quando quiser.

O backup aparece a menos que a organização o desligue.

## Para saber mais

Como enviar em cada linguagem e como funciona a entrada e a saída dos programas estão no `MANUAL-LINGUAGENS.md`.
