# MOJ: Manual dos juízes (.judge e .cjudge)

Este manual é para as pessoas que julgam as submissões de um contest do MOJ pela interface web. Há dois papéis, e cada um vem do sufixo do seu login:

| Login termina em | Papel | O que ganha |
|---|---|---|
| `.judge` | Juiz | Vê e trabalha a fila de avaliação. |
| `.cjudge` | Juiz-chefe | Herda tudo do juiz e ainda ganha um painel de chefia. |

O juiz-chefe **herda** tudo o que o juiz faz. Ou seja, leia a Parte 1 mesmo se você for `.cjudge`: ela vale para você também. A Parte 2 acrescenta os poderes extras.

## Quando este manual vale

Tudo aqui só acontece quando a prova está em modo de **veredicto manual** (a organização liga a opção `MANUAL_VERDICT`). Nesse modo, as submissões param numa fila esperando o olho de um juiz antes de o resultado chegar ao competidor.

Sem essa opção ligada, a correção é **automática**: a máquina calcula o veredicto e entrega direto ao competidor. Nesse caso não há fila e não há nada para o juiz fazer. Se você abrir a aba de avaliação e ela estiver vazia ou ausente, provavelmente a prova não está em veredicto manual.

## Parte 1: `.judge` (juiz)

### Abas que você vê

Como juiz, sua barra de navegação tem estas abas:

| Aba | Para quê |
|---|---|
| **Contest** | O enunciado da prova e os problemas. |
| **Score** | O placar. |
| **Clarification** | Perguntas e respostas (esclarecimentos). |
| **⚖️ Avaliar** | A sua fila de avaliação. É aqui que você trabalha. |
| **Estatísticas** | Números da prova. |
| **Sair** | Encerra a sessão. |

Uma diferença importante em relação a um competidor: você, juiz, também enxerga o **texto cru** do veredicto que a máquina calculou. O competidor não vê isso.

### A fila de avaliação

A fila fica na aba **⚖️ Avaliar** (URL `/contest/judge/`). No topo da página há quatro contadores que resumem o estado geral:

| Contador | Significa |
|---|---|
| Não avaliadas | Submissões seguradas, ainda sem ninguém trabalhando nelas. |
| Sendo avaliadas | Alguém já pegou e está julgando agora. |
| Aguardando 2º voto | Já tem um voto, falta o segundo juiz concordar. |
| Em conflito | Os dois votos divergiram. Só o juiz-chefe resolve. |

Abaixo dos contadores vem a lista das submissões seguradas para revisão. Para cada uma, você vê:

- **Problema** a que a submissão pertence.
- **Veredicto de referência**: o que a máquina calculou (serve de referência, não é decisão final).
- **Status** da submissão na fila.
- **Quem está avaliando** (se já houver alguém).
- **Links de log e de fonte** (o log de execução e o código enviado).
- A **ação** disponível (por exemplo, pegar para avaliar).

### Fluxo de avaliação, passo a passo

1. **Pegar p/ avaliar.** Clique para reservar a submissão. No máximo 2 pessoas podem estar na mesma submissão, e sua reserva tem um tempo limite de 5 minutos. Ao pegar, a tela troca para um painel estável, que não recarrega sozinho enquanto você trabalha (assim você não perde o que está fazendo).
2. **Analisar.** No painel você tem tudo à mão: o **veredicto de referência**, o **log** de execução, o **código** enviado e um seletor de veredicto. Dois botões ajudam: **+5 min** (pede mais tempo, caso os 5 minutos não bastem) e **Desistir** (larga a submissão para outra pessoa pegar).
3. **Votar e liberar.** Escolha o veredicto no seletor e clique para votar. Atenção: o **voto é permanente** (não dá para desfazer) e ele **libera você na hora** para pegar a próxima tarefa.

### Dois juízes têm de concordar

Uma submissão só tem seu veredicto entregue ao competidor quando **dois juízes votam a mesma coisa**. Quando os dois votos batem, o veredicto vai para o competidor (a entrega é feita por um único escritor, o daemon, para não haver bagunça).

Quando os dois votos **divergem**, a submissão vira um **conflito** e fica marcada para o **juiz-chefe** resolver. Um juiz comum não resolve conflito: sua parte termina no seu voto.

### Resumo do que o juiz pode

| Pode | Não pode |
|---|---|
| Ver a fila de avaliação e os contadores. | Resolver conflitos. |
| Pegar e reservar submissões (máx. 2 por submissão, 5 min). | Liberar um veredicto sem os dois votos. |
| Ver referência, log, código e votar. | Editar a lista de veredictos ou o auto-veredicto. |
| Pedir +5 min ou desistir. | Ver o painel de chefia. |
| Ver o texto cru do veredicto. | Acessar administração, jplag, times, usuários. |

## Parte 2: `.cjudge` (juiz-chefe)

O juiz-chefe faz **tudo o que o juiz faz**: pega submissões, vota, participa da regra dos dois votos, tudo igual à Parte 1. Além disso, ganha um painel de chefia e alguns poderes extras.

### Abas a mais

Além das abas do juiz, o juiz-chefe vê:

| Aba | Para quê |
|---|---|
| **👑 Juiz-chefe** | O painel de chefia (detalhado abaixo). |
| **Todas as Submissões** | A lista completa de submissões, com o veredicto cru. |

### O painel do chefe

O painel fica em `/contest/chief/` e tem 4 abas:

1. **📊 Situação.** Mostra cartões de resumo, a **fila completa** (com filtros e mostrando os votos dos outros juízes) e uma tabela **"Desempenho por juiz"** com: votos dados, tempo médio entre pegar e votar, concordâncias e conflitos. Cada linha da fila traz um botão **Decidir/Resolver**, que libera o veredicto **na hora**, sem esperar os dois votos (essa decisão fica registrada).
2. **⚖️ Conflitos.** Lista as submissões em conflito, mostrando os **dois votos** que divergiram, o log e a fonte, com um botão para resolver cada uma.
3. **🏷️ Opções.** Edita a **lista de veredictos** que os juízes podem escolher ao votar.
4. **⚙️ Auto-veredicto.** Edita a **matriz** (problema x linguagem x veredicto) que decide quais veredictos calculados pela máquina **pulam** a revisão manual e vão direto ao competidor.

### Alerta de conflito

Em **qualquer página do contest**, o juiz-chefe recebe um **aviso vermelho piscando (com som)** toda vez que surge um novo conflito. Clicar no aviso leva direto à aba **⚖️ Conflitos**. Assim você percebe o conflito mesmo que esteja em outra tela.

### Outros poderes do chefe

- Ver **Todas as Submissões**, com o veredicto cru.
- Responder **clarifications** (esclarecimentos). Você precisa **reservar** a pergunta antes de responder. O autor da pergunta é **anônimo** para você.
- Editar **respostas e notícias** da prova.

### O que o juiz-chefe NÃO é

O juiz-chefe **não** é administrador pleno. Ele não tem:

- a aba de **Administração**,
- **jplag** (comparação de plágio),
- **configurações** do contest,
- gestão de **times** ou de **usuários**.

Os poderes dele se limitam a: julgamento, veredictos, notícias/respostas e estatística.

### Resumo do que o juiz-chefe pode

| Pode (além de tudo o que o juiz pode) | Não pode |
|---|---|
| Ver o painel 📊 Situação e o desempenho por juiz. | Ser admin pleno. |
| **Decidir/Resolver** liberando veredicto na hora (registrado). | Abrir a aba de Administração. |
| Resolver **conflitos**. | Usar jplag. |
| Editar a lista de veredictos (🏷️ Opções). | Mudar configurações do contest. |
| Editar o **auto-veredicto** (matriz problema x linguagem x veredicto). | Gerenciar times ou usuários. |
| Ver **Todas as Submissões** com veredicto cru. | |
| Responder clarifications (reservando antes; autor anônimo). | |
| Editar respostas e notícias. | |
| Receber o alerta piscante de conflito em qualquer página. | |

## Para saber mais

- Para a visão de quem compete, veja `MANUAL-CONTEST.md`.
- Para a equipe de sala, veja `MANUAL-STAFF.md`.
