# MOJ: Manual do Treino Livre (aluno)

> **Prefere o terminal?** A CLI `moj-comp` também funciona no treino: buscar problema, baixar
> enunciado, enviar e receber o veredicto sem sair do shell. Guia:
> [/treino/cli.html](/treino/cli.html).

Bem-vindo ao **Treino Livre** do MOJ, o juiz online. Este manual mostra, passo a passo,
como criar sua conta, entrar, achar problemas, enviar sua solução e acompanhar o
resultado. Ele foi escrito para quem está começando, então vamos com calma e sem pressa.

O Treino Livre é o espaço onde você pratica no seu ritmo: escolhe o problema, escreve o
código, envia e vê o veredicto. Sem prazo, sem placar de competição. Para competir de
verdade, veja o `MANUAL-CONTEST.md` no fim deste documento.

---

## Sumário

1. [A página inicial](#1-a-página-inicial)
2. [Criar conta pelo Telegram](#2-criar-conta-pelo-telegram)
3. [Entrar](#3-entrar)
4. [Esqueci a senha](#4-esqueci-a-senha)
5. [Achar problemas](#5-achar-problemas)
6. [Resolver um problema](#6-resolver-um-problema)
7. [Perfil](#7-perfil)
8. [Minhas estatísticas](#8-minhas-estatísticas)
9. [Página de editores](#9-página-de-editores)
10. [Para saber mais](#10-para-saber-mais)

---

## 1. A página inicial

Abra o endereço `/` do MOJ. Você **não precisa estar logado** para ver a página inicial.

No topo fica a **barra de menu** com os itens:

| Item | Para que serve |
|---|---|
| **Notícias** | Avisos e novidades da plataforma |
| **Contests** | Competições e treinos com prazo |
| **Treino Livre** | O espaço de prática livre (é o assunto deste manual) |
| **Status** | Situação dos juízes e do sistema |
| **Documentação** | Manuais e ajuda |

À **direita** da barra fica a área de login. Quando você ainda não entrou, aparecem os
campos de usuário e senha. Depois de entrar, essa área vira o seu **avatar**, que abre um
menu com atalhos.

Descendo a página, você encontra várias seções úteis:

- A **notícia em destaque** do momento.
- O **Top 10** de quem mais resolve problemas.
- Os **problemas mais resolvidos na semana**.
- Os **editores mais usados** pelos estudantes.
- O que foi **resolvido recentemente**.
- A **lista de contests**, separada em **Abertos agora**, **Por vir** e **Encerrados**,
  com uma **busca por nome**.

Para começar a praticar, clique no botão **Treino Livre**. Ele leva você para o endereço
`/treino/`.

---

## 2. Criar conta pelo Telegram

O cadastro do Treino Livre fica em `/treino/cadastro/` e é **confirmado pelo Telegram**.
Isso evita contas duplicadas. Portanto, para se cadastrar, você precisa de uma **conta no
Telegram**.

Siga os passos:

1. **Preencha o formulário:**
   - **Nome completo** (obrigatório).
   - **Login desejado** (opcional). Pode ter de 2 a 32 caracteres, usando letras,
     números e os símbolos `.`, `_` e `-`. Se você deixar em branco, o sistema usa o seu
     `@` do Telegram como login.
   - **Universidade** (opcional).
2. Clique em **Continuar no Telegram**.
3. Abra o bot **mojinho** no Telegram e toque em **Start**. A página do cadastro fica
   **esperando** e confirma sozinha assim que você fala com o bot.

Um ponto importante sobre a senha:

> A sua **senha chega só por mensagem privada no Telegram**. Ela **nunca aparece na web**.
> Guarde bem essa mensagem.

Terminado o cadastro, siga para a tela de login (próxima seção).

---

## 3. Entrar

O login fica no **topo de qualquer página do Treino**. Você verá:

- um campo de **usuário**;
- um campo de **senha**;
- o botão **Entrar**.

Preencha usuário e senha (a senha é aquela que o bot enviou pelo Telegram) e clique em
**Entrar**.

Quando você está logado, o canto direito da barra mostra o seu **avatar**. Clique nele
para abrir um menu com atalhos:

- **Minhas estatísticas**
- **Perfil**
- **Sair**
- e **mais opções**, caso a sua conta tenha permissões extras.

---

## 4. Esqueci a senha

Não existe formulário de "esqueci a senha" na web. A recuperação é feita pelo Telegram.

Se você **vinculou o Telegram** à sua conta (o que acontece no cadastro), faça assim:

1. Abra a conversa com o bot **mojinho** no Telegram.
2. Envie o comando `/trocarsenha`.
3. Você recebe uma **nova senha por mensagem privada** no próprio Telegram.

Depois, é só voltar à tela de login e entrar com a senha nova.

---

## 5. Achar problemas

A lista de problemas fica em `/treino/`. **Ver a lista e ler o enunciado não exige
login.** Já o **filtro de status** e o **envio de solução** exigem que você esteja
logado.

No alto da página há vários filtros para você achar o que quer:

- **Buscar por título:** digite parte do nome do problema.
- **Filtrar por coleção:** por exemplo, `obi2024`.
- **Filtrar por tag:** por exemplo, `grafos`.
- **Seletor Todos / Resolvidos / Tentados não resolvidos:** ajuda a ver o seu progresso.
  Este filtro **só funciona quando você está logado**.
- **Botão Mostrar/Ocultar tags:** liga e desliga a exibição das tags na tabela.
- **Navegar por coleção:** abre a relação de coleções disponíveis.

A tabela de resultados tem as colunas:

| Coluna | O que mostra |
|---|---|
| **Problema** | O título, que é o **link** para abrir o problema |
| **Coleções** | A que coleções o problema pertence |
| **Tags** | Os assuntos do problema |
| **Dificuldade** | Um indicador, com acertos e tentativas |
| **Status** | Se você resolveu, tentou ou ainda não mexeu (aparece quando logado) |

Para abrir um problema, **clique no título** dele.

---

## 6. Resolver um problema

Ao clicar no título, você chega ao endereço `/treino/problema/?id=<id>`, onde `<id>` é o
código do problema. A tela tem duas partes:

- **À esquerda:** o **enunciado** do problema.
- **À direita:** o painel **Enviar solução**.

No **topo do enunciado** você encontra:

- o(s) **autor(es)** do problema;
- as **coleções** a que ele pertence;
- as **tags** (elas começam **borradas**, com um link para **mostrar/ocultar**);
- o **tempo-limite por linguagem**;
- um **botão de estatísticas** do problema.

### Como enviar sua solução

Você precisa estar **logado** para enviar. No painel **Enviar solução**:

1. **Escolha a linguagem** no menu. Cada opção mostra o **tempo-limite** daquela
   linguagem.
2. Escreva o seu código de uma destas duas formas:
   - **Digite no editor.** O editor (chamado CodeMirror) já vem com um **modelo** da
     linguagem escolhida para você começar.
   - **Ou envie um arquivo** no campo **ou arquivo:**.
3. Clique em **Enviar solução**. Aparece a mensagem **Enviado!**.

O editor tem alguns confortos:

- **Tela cheia:** ocupa a janela toda.
- **Nova janela:** abre um modo só com o editor.
- **Recolher:** encolhe o editor quando você não precisa dele.

### Acompanhar o resultado

Logo abaixo fica o **Histórico de submissões**, com as colunas:

| Coluna | O que mostra |
|---|---|
| **Data/Hora** | Quando você enviou |
| **Ações** | Botões rápidos (veja abaixo) |
| **Linguagem** | A linguagem usada naquela submissão |
| **Status** | O veredicto do julgamento |

Os botões da coluna **Ações** são:

- **✎** (editor): recarrega aquele código no editor.
- **cód**: baixa o arquivo-fonte que você enviou.
- **log**: abre o **relatório do julgamento**.

Enquanto o resultado está **pendente**, aparece um indicador de **carregando** e a página
**atualiza sozinha** quando o veredicto sai. Você não precisa recarregar a mão.

Abaixo do veredicto, vem uma **linha de resumo**, por exemplo:

```
Passou em 3/5 testes
```

Os detalhes de cada linguagem e de como funciona a entrada e a saída dos dados ficam na página
**Ajuda** do site (`/treino/ajuda/`), que também tem o código inicial de cada linguagem. O link
"📖 Como enviar" aparece ao lado do seletor de linguagem, na hora do envio.

---

## 7. Perfil

O seu perfil fica em `/treino/perfil/`. Ele é dividido em seções, e **cada seção tem o
seu próprio botão Salvar**. Ajuste o que quiser e salve seção por seção.

| Seção | O que você ajusta |
|---|---|
| **Dados** | Nome, universidade e o **editor/IDE favorito** (ele aparece no ranking de editores) |
| **Senha** | Senha atual, nova senha e confirmação da nova |
| **Privacidade** | A opção **Perfil público**. Se você **desmarcar**, suas estatísticas ficam **só para você** |
| **Foto** | Enviar uma imagem, que é recortada para **100x100** |
| **Nome de usuário** | Trocar o seu handle |

Um cuidado com a troca de **Nome de usuário**:

> Trocar o handle **atualiza todo o seu histórico** para o nome novo. Existe um **limite
> de trocas por ano** (o padrão é **2**), e a própria tela mostra **quantas você já
> usou**.

---

## 8. Minhas estatísticas

As suas estatísticas ficam em `/treino/stat/`. É um painel completo com o seu desempenho.

Você encontra **cartões** com números como:

- total de submissões;
- problemas resolvidos;
- taxa de acerto;
- média de tentativas;
- sequência atual;
- linguagens usadas;
- e outros.

E também **gráficos**:

- evolução ao longo do tempo;
- mapa de atividade;
- distribuição de veredictos;
- desempenho por linguagem;
- força por tag.

No fim, vem o seu **histórico completo**.

Lembre-se: se o seu perfil for **privado**, essas estatísticas **só aparecem para você**.

---

## 9. Página de editores

A página `/treino/editores/` reúne a estatística dos **editores favoritos** declarados
pelos usuários: um **ranking** e a **distribuição** de quem usa o quê.

Dica: quer aparecer nesse ranking? **Declare o seu editor** na seção **Dados** do
**Perfil** (veja a seção 7).

---

## 10. Para saber mais

- Para os detalhes de **como enviar em cada linguagem** e de como funciona a **entrada e
  a saída** dos dados, veja a página **Ajuda** (`/treino/ajuda/`).
- Para **competir num contest** (com prazo e placar), veja `MANUAL-CONTEST.md`.

Bons treinos, e bom código.
