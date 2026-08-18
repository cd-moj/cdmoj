# MOJ: Manual da equipe de sala (.staff e .cstaff)

Este manual é para você que faz parte da equipe de sala de um contest no MOJ (o juiz online). Ele cobre dois papéis: **.staff** (equipe de sala) e **.cstaff** (chefe de staff de uma sede). O foco é a interface web.

Se você quer a visão de quem compete, veja o `MANUAL-CONTEST.md`.

## Como o papel funciona

No MOJ o seu papel vem do **sufixo do login**:

- Uma conta que termina em `.staff` é equipe de sala.
- Uma conta que termina em `.cstaff` é chefe de staff de uma sede.

Você entra no contest como qualquer pessoa (usuário e senha) e o sistema já mostra as telas do seu papel. Você não precisa fazer nada de especial: basta usar as credenciais que a organização te entregou.

Uma diferença importante entre os dois papéis: a `.staff` **executa** as tarefas da fila (pega, imprime, entrega), enquanto a `.cstaff` **acompanha** a fila em modo somente leitura e tem acesso às etiquetas com senha. A ideia central da `.cstaff` é: **vê, mas não executa as ações da fila.**

---

## Parte 1: `.staff` (equipe de sala)

Você é a pessoa que fica na sala cuidando das impressões e dos balões. Você não é competidor: não envia código e não vê clarifications.

### Abas que você vê

| Aba | Para que serve |
|---|---|
| **Score** | O placar (a versão congelada, como um usuário comum). |
| **🖨️ Impressão** | A fila de impressão e balões da sua sede. É a sua tela principal. |
| **📄 Documentos** | Os documentos que a organização publicou (info sheet, caderno da prova, folha de time limits) para você baixar e imprimir. |
| **🔁 Rodadas** | O placar e as submissões das rodadas encerradas (o aquecimento, por exemplo). |
| **Sair** | Encerra a sua sessão. |

### A fila de impressão (`/contest/staff/`)

A tela de impressão é uma tabela com **duas coisas na mesma fila**:

1. **Pedidos de impressão** dos times: um arquivo enviado pelo time, já montado com uma folha de rosto.
2. **Balões**: tarefas **automáticas**, criadas no primeiro Accepted de cada dupla (time, problema). O balão mostra a **cor** daquele problema, para você levar o balão certo até a mesa do time.

Você só vê a fila da **sua sede**. Pedidos e balões de outras sedes não aparecem para você.

### Como tratar uma tarefa

Cada botão é uma etapa do processo. O fluxo normal é: **Pegar**, depois **🖨️ Imprimir** (ou **Abrir PDF**), e por fim **✅ Entregue**.

| Botão | O que faz |
|---|---|
| **Pegar** | Reserva a tarefa para você. Se outra pessoa já pegou, aparece um aviso. |
| **🖨️ Imprimir** | Abre o PDF combinado, chama a impressão e marca a tarefa como processada. |
| **Abrir PDF** | Só abre o PDF, sem imprimir. |
| **✅ Entregue** | Marca que você entregou o material em mãos ao time. |

#### Modo automático

Há uma **caixa de seleção** de modo automático, e a sua escolha fica guardada. Com o modo automático ligado e a aba aberta, cada nova tarefa é **pega, impressa e marcada** sozinha, sem você clicar.

Para que a janela de impressão do navegador não apareça a cada tarefa, rode o navegador em **modo quiosque**. No Chrome/Chromium, use a opção `--kiosk-printing`.

### Aquecimento: a prova pode ter duas rodadas

Muita prova roda um **aquecimento** antes da prova oficial — mesma sala, mesmas contas, mesmo
endereço. Para você isso significa três coisas:

- o aquecimento é o ensaio da **sua** operação também: pegue os pedidos, imprima, entregue balão,
  confira a impressora e a cor dos balões;
- quando a organização promove a prova oficial, a **numeração dos pedidos volta a 1** e os
  **balões do aquecimento não contam** (a fila começa limpa) — se você anotou números, eles se
  referem ao aquecimento;
- o que aconteceu no aquecimento continua consultável na aba **🔁 Rodadas**.

### O que a `.staff` NÃO faz

- Não envia solução.
- Não vê clarifications.
- Não vê o placar completo (vê o placar congelado, como um usuário comum).
- Não vê as senhas nem as etiquetas de credenciais: a tela de etiquetas responde **acesso negado** para `.staff`.

---

## Parte 2: `.cstaff` (chefe de staff de uma sede)

Você supervisiona uma sede. Você acompanha a fila da sua sede, imprime as etiquetas com as credenciais (incluindo senha) e, no fim, conduz a revelação do placar da sua sede. A ideia central: **vê, mas não executa as ações da fila.**

### Abas que você vê

| Aba | Para que serve |
|---|---|
| **Score** | O placar (a versão congelada, como um usuário comum). |
| **🖨️ Impressão** | A fila da sua sede, em modo **somente leitura**. |
| **🏷️ Etiquetas** | As folhas de credenciais da sua sede, com senha. |
| **📄 Documentos** | Os documentos publicados da prova, para baixar e imprimir na sede. |
| **🔁 Rodadas** | O placar e as submissões das rodadas já encerradas. |
| **Sair** | Encerra a sua sessão. |
| **🏆 Revelação** | A cerimônia de revelação da sua sede. Só aparece **depois que a prova encerra para todas as sedes**. |

### 🖨️ Impressão, somente leitura (`/contest/staff/`)

É a mesma tela da `.staff`, mas **sem os botões de ação**: a coluna de ações fica vazia e a barra indica "somente leitura". Você acompanha a fila da sua sede, mas quem pega, imprime e entrega é a `.staff`.

### 🏷️ Etiquetas (`/contest/badges/`), com senha

Aqui está o que a `.staff` não tem: as folhas de credenciais prontas para imprimir (modelo Pimaco A4), com **nome, login, senha, sede e instituição** de cada conta.

- Você vê só a **sua sede** — e só as contas **`.staff`** dela: a sua própria credencial (de chefe) **não** sai em etiqueta, porque é ela que abre esta tela.
- Serve para imprimir as etiquetas das mesas e as credenciais dos times da sua sede.
- As opções de administração (escolher o arquivo de outra sede, incluir contas desabilitadas) **não aparecem** para você.
- **Contest que usa as contas do Treino Livre não tem senha na etiqueta**: a credencial é pessoal
  de cada participante (a mesma que ele usa no treino), então a etiqueta sai com "use sua senha do
  treino" no lugar. A lista traz **só quem está inscrito** naquele contest.
- **Conta desabilitada** sai com "conta desabilitada" em vez de senha — desabilitar troca a senha
  por uma aleatória, então não existe credencial para imprimir (o admin reabilita com um reset).
- Todo acesso a esta tela é registrado.

### 📄 Documentos da prova (`/contest/docs/`)

Aqui ficam os documentos que a organização **publicou**, prontos para você baixar e imprimir na sede:

| Documento | O que é |
|---|---|
| **Informações do ambiente** | O *info sheet*: versões de compilador, limite de memória e de pilha, linguagens aceitas e o tempo limite de cada problema. Costuma ser afixado na sala ou entregue com o caderno. |
| **Caderno da prova** | Capa + todos os enunciados. É o que vai impresso na mesa de cada time. |
| **Folha de time limits** | A tabela `letra · nome · tempo limite` (com errata, se houver). |

Cada um sai em **PDF** (para imprimir) e **HTML**, em **português e em inglês** — escolha a linha do idioma que a sua sede usa. O botão **abrir** mostra o arquivo na hora, para conferir antes de mandar para a impressora.

- Você só vê o que já foi **publicado**. Antes disso, o caderno é conteúdo de prova e nem aparece — inclusive para você.
- Se a lista estiver vazia, a organização ainda não publicou nada: volte mais perto da prova.
- **Confira a versão da capa** antes de imprimir em quantidade: se a organização corrigir um enunciado, ela regera o caderno e sobe a versão. Imprimir na véspera pode significar reimprimir.

### Score congelado

O seu placar é o **congelado**, como um usuário comum. Um administrador pode liberar a visão completa para uma conta específica (a lista `SCORE_FULL_USERS`), mas isso é uma exceção controlada pelo admin.

### 🏆 Revelação por sede (`/contest/score/reveal.html`)

Você conduz a cerimônia de revelação da sua sede, no estilo ICPC (de baixo para cima).

1. A tela filtra para os times que você enxerga (a sua sede).
2. Ela só destrava **depois que a prova encerra para todas as sedes** (o horário base mais as prorrogações).
3. Você revela posição por posição, do último para o primeiro.

Descongelar tudo e publicar o placar global são ações do **administrador**, não suas (ele faz isso pelo botão **🏁 Encerrar evento**, na Central do painel — ver `MANUAL-ADMIN.md` §6½).

### O que a `.cstaff` NÃO faz

- Não envia solução.
- Não executa as ações de impressão: pegar, imprimir e entregar dão **acesso negado**.
- Não vê etiquetas de outras sedes.
- Não descongela nem publica o placar global.

---

## Tabela-resumo: o que cada papel pode e não pode

| Ação | `.staff` | `.cstaff` |
|---|:---:|:---:|
| Ver o placar congelado (Score) | Sim | Sim |
| Ver a fila de impressão da sua sede | Sim | Sim (somente leitura) |
| Pegar, imprimir e entregar tarefas da fila | Sim | Não (acesso negado) |
| Usar o modo automático de impressão | Sim | Não |
| Ver etiquetas com senha (🏷️ Etiquetas) | Não (acesso negado) | Sim (só a sua sede) |
| Baixar os documentos publicados (📄 Documentos) | Sim | Sim |
| Gerar/publicar documentos | Não (é do admin/juiz-chefe) | Não (é do admin/juiz-chefe) |
| Conduzir a revelação da sua sede (🏆) | Não | Sim (após encerrar todas as sedes) |
| Enviar solução (competir) | Não | Não |
| Ver clarifications | Não | Não |
| Ver o placar completo | Não | Não (salvo liberação do admin) |
| Ver etiquetas de outras sedes | Não | Não |
| Descongelar tudo / publicar placar global | Não | Não (é do admin) |

---

## Ponteiros

- Para a visão de quem compete (login, envio de soluções, placar, clarifications, impressão e backup), veja o `MANUAL-CONTEST.md`.
