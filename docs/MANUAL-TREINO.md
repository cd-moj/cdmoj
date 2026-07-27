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
| **Início** | Volta para esta página |
| **Treino Livre** | O espaço de prática livre (é o assunto deste manual) |
| **Contests** | Competições e treinos com prazo |
| **Notícias** | Avisos e novidades da plataforma |
| **Status** | Situação dos juízes e do sistema |
| **Docs** | Manuais e documentação |

Ao lado do menu há o **seletor de idioma PT/EN** — o site inteiro é bilíngue. À
**direita** fica a área de login: antes de entrar, os campos de usuário e senha; depois,
o seu **avatar**, que abre um menu com atalhos (Minhas estatísticas, Perfil, Sair…).

Descendo a página, você encontra:

- O **destaque** do topo, com a **notícia em evidência** e os botões-atalho
  **Treino Livre →**, **Gestão de Problemas →** e **📖 Ajuda**.
- O card **🗂️ Gestão de Problemas** — para quem **cria** problemas (professores,
  monitores, autores). Se você só quer treinar, pode ignorar.
- O card **🏋️ Treino Livre**, com o botão **Buscar problemas →**.
- O **🏆 Top 10** de quem mais resolve — **clique num nome** para abrir o **perfil
  público** daquela pessoa (seção 8).
- Os **🔥 mais resolvidos na semana passada** e os **⌨ editores da semana**.
- O **✅ resolvido recentemente** — que também linka os perfis de quem resolveu.
- A **lista de contests**, separada em **Abertos agora**, **Por vir** e **Encerrados**,
  com um **filtro por nome**.
- As **📰 notícias**.

Para começar a praticar, clique em **Treino Livre**. Ele leva você para o endereço
`/treino/` (seção 5).

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

> **Menor de idade (sem Telegram)?** A conta é criada por um professor/admin
> **responsável**, que entrega o login e a senha. Essas contas têm o perfil sempre
> privado até os 18 anos — detalhes em [`CONTAS-GERIDAS.md`](CONTAS-GERIDAS.md).

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

Se a sua conta **não tem Telegram** (conta criada por um responsável — ver a nota da
seção 2), o reset de senha é feito **pelo responsável que criou a conta**.

---

## 5. Achar problemas

A busca de problemas fica em `/treino/`. **Ver a lista e ler os enunciados não exige
login** — o seu **progresso pessoal** e o **envio de solução**, sim.

A página tem **dois modos**: o **hub** (a porta de entrada) e a **busca avançada** (a
lista completa com filtros). Qualquer busca ou filtro leva você do hub para a busca
avançada automaticamente.

### O hub

- **Busca central:** digite 2+ letras e aparecem **sugestões agrupadas** em Coleções,
  Tags e Problemas (cada problema já com o seu status ✓/…). Use as setas ↑↓ e Enter, ou
  clique. Enter sem escolher abre a busca avançada com o texto digitado.
- **Atalhos:** 🎲 **problema aleatório** (prioriza um que você ainda não resolveu),
  🌱 **fáceis para começar**, 🚀 **ainda não resolvidos** e 🔬 **busca avançada**.
- **Para você** (aparece logado): **Continue de onde parou** (sua última tentativa ainda
  sem AC) e uma **Sugestão** de próximo problema.
- **Coleções em destaque:** um carrossel de cards — cada card mostra o tamanho da coleção
  e a **barra do seu progresso**; clicar filtra a lista por aquela coleção. Role com as
  setas ‹ › (ou o dedo, no celular). O link **todas (N) →** abre a busca avançada.
- **Mais enviados na semana:** os 10 problemas com mais envios nos últimos 7 dias.

### A busca avançada

A lista completa, sempre visível, com o **trilho de filtros** à esquerda:

- **Filtrar por título:** digite parte do nome.
- **Meu status** (só logado): Todos / A resolver / ✓ Resolvidos / … Tentados.
- **Dificuldade:** muito fácil → difícil, **derivada da taxa de acerto** de cada problema
  (“novo” = ainda sem dados). Cada opção mostra quantos problemas restam com ela.
- **Coleções:** a árvore com **caixas de seleção** — dá para marcar **várias ao mesmo
  tempo** (a lista mostra a **união**). Marcar um **grupo** (ex.: `obi`) pega todas as
  coleções dele de uma vez. O número à direita é o **seu progresso** (ex.: `20/140`).
- **Tags:** marque quantas quiser — o problema precisa ter **todas** as marcadas. As
  contagens se **atualizam ao vivo** conforme você filtra.

Sobre a tabela ficam os **chips** dos filtros ativos (o × remove um a um), a contagem de
resultados e a **ordenação**: **Mais resolvidos**, **A–Z**, **Dificuldade** e
**Novidades** (mais recém-publicados primeiro).

| Coluna | O que mostra |
|---|---|
| **✓** | Se você resolveu (✓) ou tentou (…) — aparece quando logado |
| **Problema** | O título, que é o **link** para abrir o problema |
| **Coleções** | Clique numa coleção para **somá-la** ao filtro |
| **Dificuldade** | A faixa derivada da taxa de acerto |
| **Resolvidos** | Quantos usuários resolveram / tentaram |

A lista vem em **páginas de 50**. Dica: a **URL guarda os seus filtros** — copie o link
para compartilhar uma busca. No celular, o trilho vira o botão **Filtros (n)**.

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

Essa página é a **edição** do perfil. O que os outros veem — o seu **perfil público** —
fica em `/treino/stat/?user=<seu login>` e é o assunto da próxima seção.

---

## 8. Minhas estatísticas

Cada usuário tem um **perfil público** em `/treino/stat/?user=<login>`. O seu abre pelo
menu do avatar → **📊 Minhas estatísticas**; o dos outros, clicando no nome deles (no
Top 10 da home, por exemplo).

De cima para baixo, o perfil mostra:

- **Cabeçalho:** foto (ou iniciais), universidade, **membro desde**, editor favorito
  (com a posição dele no ranking de editores) e o **último envio**.
- **Cartões:** problemas resolvidos, submissões, taxa de acerto, **AC na 1ª tentativa**,
  tentativas até resolver, **streaks** (dias seguidos com envio) e a linguagem preferida.
- **Gráficos:** evolução dos resolvidos no tempo, mapa de atividade (26 semanas),
  **ritmo dia × hora**, veredictos, desempenho por linguagem, **dificuldade dos
  resolvidos**, **progresso por coleção**, forças por tag e a lista **Em aberto**
  (problemas que você tentou e ainda não resolveu — uma ótima fila de volta ao treino).
- **🏅 Conquistas:** medalhas automáticas — Primeiro AC, Centurião (100 resolvidos),
  streaks, Poliglota, coleção completa e outras. As **travadas** aparecem acinzentadas
  com o **quanto falta** (ex.: `82/100`). O catálogo completo e as regras estão em
  [`PERFIL.md`](PERFIL.md).
- **Histórico paginado** (25 por página) com **filtros** por problema, veredicto e
  linguagem, e ordenação por coluna. Os links de **cód**/**log** só aparecem para o dono.

Lembre-se: se o seu perfil for **privado** (seção 7), tudo isso **só aparece para você**
— e o seu nome também **sai das listas públicas** da página inicial.

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
