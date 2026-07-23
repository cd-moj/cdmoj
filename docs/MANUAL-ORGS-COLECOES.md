# Gestão de orgs e coleções (manual do gestor de problemas)

Este manual é para quem **cria e organiza problemas** no MOJ — professores, monitores,
organizadores. Explica os dois eixos de organização (**org** e **coleção**), o que cada um
faz, e **como operar cada coisa nas DUAS interfaces**: a web (Gestão de Problemas) e a CLI
`moj`. Os dois clientes falam com a mesma API, então qualquer operação pode ser feita de
qualquer lado — use o que for mais confortável.

> O **formato** dos metadados (o que fica no `.moj-meta.json`, como o id é montado) é descrito,
> em detalhe canônico, no [PACOTE.md](PACOTE.html) (seções 7–9). Aqui o foco é o **uso**.

## Os dois eixos, em 30 segundos

| | **ORG** | **COLEÇÃO** |
|---|---|---|
| Para que serve | **Acesso**: quem pode ver/editar o problema | **Agrupamento**: rótulo para navegar/organizar |
| Quantas por problema | **Exatamente 1** (é o prefixo do id `org#prob`) | **Várias** (m:n) — o problema pode estar em quantas quiser |
| Dá acesso? | **Sim** — membro da org edita os problemas dela | **Não** — é só um rótulo; não deixa ninguém editar |
| Muda o id? | Sim: o problema é `<org>#<prob>` | Não |
| Exemplo | `apc`, `obi-problems`, `mdp-2026-1` | `problemas-apc`, `Prova EDA1 2026/1`, `dificil` |

Regra de ouro: **a org decide QUEM mexe; a coleção decide COMO você encontra.** Elas são
ortogonais — dois problemas de orgs diferentes podem estar na mesma coleção, e uma org pode
ter problemas espalhados por várias coleções.

Todo usuário já nasce com uma **org implícita com o seu próprio login** (ex.: `ana.silva`),
sempre privada — é onde seus rascunhos ficam se você não criar outra org.

---

## Parte 1 — ORGs

### Criar uma org

Uma org costuma representar uma **disciplina, turma ou competição** (ex.: uma por semestre de
uma matéria, uma para cada olimpíada). O nome é **minúsculo, sem espaços** (vira subdomínio/id).

| Web (Gestão de Problemas) | CLI |
|---|---|
| No **editor de um problema novo**, no topo da aba *Enunciado*, clique **“+ nova org”**. Ou vá à aba **Orgs** e crie por lá. | `moj mkdir <org>`  · ou `moj org create <org> [--public] [--members a,b] [--admins c]` |

Quem cria a org vira automaticamente **membro e admin** dela. Um problema **só pode ser salvo
dentro de uma org** — por isso o editor pede para criar a primeira antes de deixar salvar.

### Membros e admins

- **Membro** da org: **edita todos os problemas da org**, inclusive os privados (é o modelo de
  autoria compartilhada — coautores de uma disciplina são membros da mesma org).
- **Admin** da org: além de editar, **gere membros/admins** e a **trava de público** (abaixo).

| Web | CLI |
|---|---|
| Aba **Orgs** → escolha a org → gerencie membros/admins. No editor de um problema há também o **share** (adiciona coautor à org daquele problema). | `moj share <org> <login>` (adiciona membro) · `moj org members <org> --add a,b --remove c --admins-add d --admins-remove e` |

> Acesso a problema **privado** é decidido **só pela org** — nem um `.admin` global do MOJ vê o
> conteúdo/pacote de um problema privado de uma org da qual não é membro. Provas em elaboração
> não vazam, por construção.

### Trava de público (`public_allowed`) — o anti-vazamento

Toda org nasce **privada**: seus problemas **não podem ser publicados** no Treino Livre. Isso é
proposital — é a proteção contra vazar uma prova em elaboração. Para que os problemas de uma org
possam ficar públicos, um **admin da org** precisa **liberar o público da org**.

| Web | CLI |
|---|---|
| Aba **Orgs** → a org → ligar/desligar a trava de público. | `moj org public <org> on`  /  `moj org public <org> off` |

> ⚠️ **Desligar a trava DESPUBLICA em cascata** todos os problemas públicos daquela org (eles
> voltam a privado na hora). Ligue com calma; desligue com mais calma ainda.

A **org implícita** (`<seulogin>`) é **sempre privada** e não aceita liberar público — ela é seu
rascunho pessoal. Para publicar, mova o problema para uma org com público liberado.

### Apagar uma org

Só é possível apagar uma org **vazia** (sem nenhum problema). A org implícita nunca é removida.

| Web | CLI |
|---|---|
| Aba **Orgs** → remover (só habilita se estiver vazia). | `moj org rm <org>` |

### Mover um rascunho para outra org

Como a org é o prefixo do id, mover um problema **muda o id** (`orgA#p` → `orgB#p`). Só vale para
**rascunho** (problema **não** público e **não** em uso em contest); você precisa ser membro das
**duas** orgs.

| Web | CLI |
|---|---|
| Na lista de problemas, o botão **“Mover”** (aparece só nos seus rascunhos). | `moj mv <id> <org-destino>` |

---

## Parte 2 — COLEÇÕES

Coleção é um **rótulo livre** para agrupar problemas — pode ter **espaços e acentos** (ex.:
`Prova EDA1 2026/1`, `Geometria`, `iniciantes`). Um problema pode estar em **várias**. Serve
para: navegação no Treino Livre, filtros da busca, e o **sorteio** de problemas na criação de
contest. **Coleção não dá acesso a nada** — é puramente organização.

O registro de coleções é **curado**: para marcar um problema numa coleção, ela precisa **existir**
(você cria a coleção primeiro). Cada coleção tem um **dono** (quem a criou).

### Criar uma coleção

| Web | CLI |
|---|---|
| Aba **Coleções** da Gestão de Problemas → campo *nova coleção* → **“+ Coleção”**. (Também dá para criar do painel de coleções dentro do editor.) | `moj collection create "<nome livre>"` |

### Marcar / desmarcar um problema numa coleção

| Web | CLI |
|---|---|
| No **editor** do problema, painel de coleções: marque/desmarque os rótulos e **Salve**. | `moj collection add <id> "<nome>"`  ·  `moj collection remove <id> "<nome>"` |

### Navegar e listar

| Web | CLI |
|---|---|
| Aba **Coleções** (filtro **“só minhas”**, clique no nome para ver os problemas). No **Treino Livre**, o explorador agrupa as coleções por prefixo e filtra por texto. | `moj collection ls`  ·  `moj collection show "<nome>"` |

### Renomear / apagar uma coleção

Só o **dono** da coleção (ou um `.admin`) renomeia/apaga. A operação re-etiqueta os N problemas
em **segundo plano** (o servidor faz o trabalho pesado sem travar); a CLI **acompanha até o fim**
mostrando o progresso.

| Web | CLI |
|---|---|
| Aba **Coleções** → renomear/excluir (dono/admin). | `moj collection rename "<nome>" "<novo>"`  ·  `moj collection delete "<nome>"`  ·  `moj collection status` (acompanha os jobs) |

> Renomear/apagar não afeta o **acesso** de ninguém (coleção é só rótulo) — só troca/remove a
> etiqueta nos problemas.

---

## Permissões e armadilhas (o resumo que evita dor de cabeça)

- **Membro da org vê e edita tudo da org**, inclusive problemas privados. Coautoria = membro.
- **Privado não vaza** — nem para `.admin` global; o acesso é decidido pela membership da org.
- **Coleção não propaga acesso** — colocar o problema de outra pessoa na sua coleção **não** te
  dá permissão de editá-lo. Para editar, você precisa ser membro da org dele.
- **Público exige org liberada** — publicar um problema só funciona se a org tiver o
  `public_allowed` ligado; senão o botão/publish recusa.
- **Desligar o público da org despublica em cascata** — cuidado ao mexer nessa trava.
- **Rename/delete de coleção é assíncrono** — responde na hora e re-etiqueta em segundo plano;
  na CLI, `moj collection status` mostra o andamento.
- **Mover problema muda o id** — links/refs antigos ao id velho deixam de resolver.

## Receitas rápidas

**Montar uma disciplina do zero (privada):**
1. `moj mkdir eda1-2026` (ou “+ nova org” no editor) — nasce privada.
2. Crie os problemas dentro dela (ficam privados, bons para prova).
3. `moj collection create "Prova 1 EDA1 2026/1"` e marque os problemas da prova nela, para
   organizar/sortear.

**Abrir problemas ao Treino Livre:**
1. Um admin da org liga o público: `moj org public eda1-2026 on` (ou aba Orgs na web).
2. Publique cada problema: `moj publish eda1-2026#<prob>` (ou o botão **Publicar** no editor) —
   o servidor valida + calibra e ele aparece no Treino Livre.

**Compartilhar a autoria com um colega:**
- `moj share eda1-2026 colega.login` (ou o **share** no editor) — o colega passa a editar todos
  os problemas da org.

## Ver também

- **[PACOTE.md](PACOTE.html)** — o formato canônico (o que fica no `.moj-meta.json`, o id, as
  seções 7 (ORG), 8 (COLEÇÃO) e 9 (ORG × COLEÇÃO)).
- **Tutoriais passo a passo**: [Criar problemas na CLI](/problemas/tutorial.html) e
  [Criar e gerir um contest](/treino/criar/tutorial.html).
- **[API.md](API.html)** — as rotas `/orgs/*` e `/problems/collection*` para quem automatiza.
