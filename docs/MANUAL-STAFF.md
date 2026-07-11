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
| **Sair** | Encerra a sua sessão. |
| **🏆 Revelação** | A cerimônia de revelação da sua sede. Só aparece **depois que a prova encerra para todas as sedes**. |

### 🖨️ Impressão, somente leitura (`/contest/staff/`)

É a mesma tela da `.staff`, mas **sem os botões de ação**: a coluna de ações fica vazia e a barra indica "somente leitura". Você acompanha a fila da sua sede, mas quem pega, imprime e entrega é a `.staff`.

### 🏷️ Etiquetas (`/contest/badges/`), com senha

Aqui está o que a `.staff` não tem: as folhas de credenciais prontas para imprimir (modelo Pimaco A4), com **nome, login, senha, sede e instituição** de cada conta.

- Você vê só a **sua sede**: a sua conta e as contas `.staff` e `.cstaff` do mesmo escopo.
- Serve para imprimir as etiquetas das mesas e as credenciais dos times da sua sede.
- As opções de administração (escolher o arquivo de outra sede, incluir contas desabilitadas) **não aparecem** para você.
- Todo acesso a esta tela é registrado.

### Score congelado

O seu placar é o **congelado**, como um usuário comum. Um administrador pode liberar a visão completa para uma conta específica (a lista `SCORE_FULL_USERS`), mas isso é uma exceção controlada pelo admin.

### 🏆 Revelação por sede (`/contest/score/reveal.html`)

Você conduz a cerimônia de revelação da sua sede, no estilo ICPC (de baixo para cima).

1. A tela filtra para os times que você enxerga (a sua sede).
2. Ela só destrava **depois que a prova encerra para todas as sedes** (o horário base mais as prorrogações).
3. Você revela posição por posição, do último para o primeiro.

Descongelar tudo e publicar o placar global são ações do **administrador**, não suas.

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
| Conduzir a revelação da sua sede (🏆) | Não | Sim (após encerrar todas as sedes) |
| Enviar solução (competir) | Não | Não |
| Ver clarifications | Não | Não |
| Ver o placar completo | Não | Não (salvo liberação do admin) |
| Ver etiquetas de outras sedes | Não | Não |
| Descongelar tudo / publicar placar global | Não | Não (é do admin) |

---

## Ponteiros

- Para a visão de quem compete (login, envio de soluções, placar, clarifications, impressão e backup), veja o `MANUAL-CONTEST.md`.
