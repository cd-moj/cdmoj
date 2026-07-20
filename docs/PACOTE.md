# MOJ: o pacote de problema (formato canônico)

Este documento é a **fonte única** do formato do pacote de problema do MOJ. Explica o que é um
pacote, o que faz cada arquivo dentro dele, o que são os metadados (`.moj-meta.json` e `.moj-id`),
o que são **orgs** e **coleções**, e como um problema sai de rascunho e chega ao aluno.

> Quem monta um pacote na prática (passo a passo, com os comandos) deve ler o `README.md` do
> **mojtools**, que tem o roteiro. Aqui está a **referência**: o que cada coisa é e por quê.
> As rotas da API que leem e escrevem o pacote estão em [API.md](API.md).

> **Doc atrasada = bug.** Mudou o pacote (arquivo novo, campo novo, layout, de onde vem o título)?
> Atualize **este** documento no mesmo commit. Os outros lugares (o `CLAUDE.md` do `cdmoj`, do
> `mojtools` e do `moj-cli`) apontam para cá em vez de repetir o formato.

## Sumário

1. [O que é um pacote](#1-o-que-é-um-pacote)
2. [Onde os pacotes moram](#2-onde-os-pacotes-moram)
3. [Layout canônico](#3-layout-canônico)
4. [Arquivo por arquivo](#4-arquivo-por-arquivo)
5. [`.moj-meta.json`: os metadados do problema](#5-moj-metajson-os-metadados-do-problema)
6. [`.moj-id`: o ponteiro local da CLI](#6-moj-id-o-ponteiro-local-da-cli)
7. [ORG: quem pode mexer](#7-org-quem-pode-mexer)
8. [COLEÇÃO: como os problemas são agrupados](#8-coleção-como-os-problemas-são-agrupados)
9. [ORG x COLEÇÃO](#9-org-x-coleção)
10. [Ciclo de vida de um problema](#10-ciclo-de-vida-de-um-problema)
11. [Perguntas frequentes](#11-perguntas-frequentes)

---

## 1. O que é um pacote

Um **pacote** é um diretório que descreve um problema por inteiro: o enunciado, os testes, as
soluções de referência e os limites de execução. Não existe banco de dados de problemas: o pacote
**é** o problema.

Três coisas valem saber desde já:

- **Cada pacote é um repositório git próprio**, local, dentro do servidor. Não há Gitea, nem
  serviço externo, nem chave de acesso. Quando alguém salva pelo editor web ou pelo `moj push`, o
  servidor grava os arquivos e commita ali mesmo (função `problem_commit`, em
  `server/api/v1/lib/problems.sh`, com trava por problema).
- **O identificador de um problema é `<org>#<prob>`**, por exemplo `apc#fatorial`. A parte antes do
  `#` é a **org** (seção 7), a parte depois é o nome do diretório do pacote.
- **O autor quase nunca edita o pacote na mão.** Ele usa o editor web ou a CLI (`moj`), e as duas
  falam com a mesma API. Este documento descreve o que essas ferramentas gravam, para que você
  entenda o que está acontecendo e possa conferir.

## 2. Onde os pacotes moram

```
moj-problems/<org>/<prob>/        # o pacote (raiz do repo git local daquele problema)
```

A raiz `moj-problems/` é configurável pela variável `MOJ_PROBLEMS_DIR`. No checkout de
desenvolvimento ela fica ao lado do `cdmoj/`.

Um pacote **não** contém o placar, o histórico de submissões, nem os tempos-limite calibrados. Isso
tudo vive fora dele:

| Coisa | Onde fica | Quem escreve |
|---|---|---|
| Tempos-limite calibrados | `run/tl/<id>.json` | os juízes, ao calibrar |
| Relatório de validação | `run/validation/<id>.json` | `validate-problem.sh` |
| Índice servido ao aluno | `contests/treino/var/jsons/<id>.json` | `gen-problem-json.sh` |
| Registro de orgs | `contests/treino/var/orgs.json` | a API (`lib/orgs.sh`) |
| Registro de coleções | `contests/treino/var/collections.json` | a API (`lib/problems.sh`) |

## 3. Layout canônico

Árvore de um pacote completo. A coluna da direita mostra em quantos dos 453 pacotes do acervo atual
cada item aparece, para dar noção do que é rotina e do que é exceção.

```
moj-problems/<org>/<prob>/
├── .git/                     repo git local do problema                     453  (sempre)
├── .moj-meta.json            metadados (título, público, coleções, …)       453  (sempre)
├── author                    autor(es) do problema                          453  (obrigatório)
├── tags                      assuntos, uma tag por linha                    453
├── conf                      limites e ajustes de execução                  453
├── docs/
│   ├── enunciado.md          o enunciado (também aceita .org e .tex)        453  (obrigatório)
│   ├── sample-notes.json     explicação de cada exemplo                     opcional
│   └── solucao.md            editorial, só para o autor                     opcional
├── tests/
│   ├── input/sample1         exemplo (aparece no enunciado)                 obrigatório, >= 1
│   ├── output/sample1        resposta do exemplo
│   ├── input/<nome>          teste oculto (corrige a submissão)
│   ├── output/<nome>         resposta do teste oculto
│   └── score                 grupos de pontuação (subtarefas)               254  (opcional)
├── sols/
│   ├── good/                 soluções corretas                              453  (obrigatório, >= 1)
│   ├── wrong/                soluções erradas de propósito                    18  (opcional)
│   ├── slow/                 soluções lentas de propósito                      7  (opcional)
│   ├── pass/                 soluções que devem passar raspando               3  (opcional)
│   └── upcoming/             soluções em rascunho                              1  (opcional)
└── scripts/                  correção especial                               79  (opcional)
    ├── compare.sh            comparador próprio (checker)                    18
    └── <lang>/compile.sh     compilação própria (submissão de função)       201
```

Dois arquivos aparecem no acervo mas **não** fazem parte do formato:

- `problem.yaml` e `.kattis.json` (em 395 pacotes) são metadados do formato **Kattis**, gravados
  pelo importador/exportador (`mojtools/kattis/`). O MOJ os ignora por completo.
- `.moj-id` (em 336 pacotes) é um arquivo do **cliente**, não do pacote. Ele foi parar ali por
  descuido de migrações antigas. Ver a seção 6.

## 4. Arquivo por arquivo

### `docs/enunciado.md`

O texto do problema. Aceita três formatos, procurados nesta ordem: `enunciado.md`, `enunciado.org`,
`enunciado.tex`. O `.md` é o canônico e o recomendado.

Três regras que o portão de qualidade cobra:

1. **As seções `## Entrada` e `## Saída` são obrigatórias.** Sem elas o problema não passa na
   validação. (O validador também aceita `## Input` e `## Output`, e de um a três `#`.)
2. **O título não vai no texto.** Uma primeira linha `% Título do problema` é **legado**: o
   renderizador a remove. O título verdadeiro é o campo `display_title` do `.moj-meta.json`
   (seção 5), e o renderizador injeta um `<h1>` a partir dele.
3. **Os exemplos não vão no texto.** Eles são montados a partir de `tests/input/sample*` e
   `tests/output/sample*` e injetados no fim do HTML. Se você escrever um exemplo à mão dentro do
   enunciado, ele vai aparecer duplicado. (A validação avisa, mas não bloqueia.)

Imagens devem ser embutidas em base64. O renderizador roda com `--embed-resources`, então o HTML
servido ao aluno é autocontido, sem depender de arquivo externo.

**Grafos**: um bloco de código com a classe `.graph` (fonte [graphviz DOT](https://graphviz.org/)) é
renderizado como **SVG** — a fonte DOT fica editável no enunciado, não é uma imagem colada. Ex.:
` ```{ .graph .center caption="…"} graph G { a -- b; } ``` `. Detalhes e atributos em
**`mojtools/docs/enunciado-grafos.md`**.

Quem renderiza é **um script só**: `mojtools/render-statement.sh`. O botão "Pré-visualizar" do
editor, o HTML que o aluno lê e o HTML que a validação confere são exatamente o mesmo. Não existe
segundo renderizador, e não se deve criar um.

### `docs/sample-notes.json`

Opcional. Um array JSON de textos, um por exemplo, **na ordem dos exemplos**:

```json
["No primeiro exemplo, os dois times empatam, então a saída é 0.",
 "Aqui o segundo time vence por 3 pontos."]
```

Cada nota é renderizada em markdown e aparece logo abaixo do exemplo correspondente.

### `docs/solucao.md`

Opcional. É o **editorial**: a explicação da ideia da solução, para o autor e para quem for reusar o
problema. **O aluno nunca vê este arquivo.** O `gen-problem-json.sh` o ignora de propósito. É o
lugar certo para escrever "a solução é uma DP em O(n log n)" sem medo.

Não confundir com a mecânica da correção especial, que é assunto do `scripts/` e está documentada em
`mojtools/docs/correcao-especial.md`.

### `tests/input/` e `tests/output/`

Todo arquivo em `tests/input/` precisa ter um arquivo de **mesmo nome** em `tests/output/`. Isso é
checado na validação, nos dois sentidos (input sem output e output sem input reprovam).

O nome do arquivo decide o papel do teste:

| Nome | Papel |
|---|---|
| `sample1`, `sample2`, … | **exemplo**: aparece no enunciado, e também corrige |
| qualquer outro nome | **teste oculto**: só corrige, o aluno nunca vê |

Os exemplos são todos os arquivos que começam com `sample`, ordenados por `ls -1v` (ou seja,
`sample2` vem antes de `sample10`, e não depois). É preciso ter **pelo menos um par** de teste, e na
prática pelo menos um exemplo.

O nome dos testes ocultos é livre. As convenções que aparecem no acervo são `test-001`, `test-002`
(estilo APC) e `<prob>_1_1`, `<prob>_1_2` (estilo OBI, que agrupa por subtarefa; ver `tests/score`).

### `tests/score`

Opcional. Liga a **pontuação por grupos** (subtarefas). Sem este arquivo, a nota do problema é a
porcentagem de testes que passaram.

O formato é texto puro, uma linha por grupo:

```
sample* - 0 pontos
2015f2p1_capitais_1_*, 2015f2p1_capitais_2_* - 40 pontos
2015f2p1_capitais_3_*, 2015f2p1_capitais_4_*, 2015f2p1_capitais_5_* - 60 pontos
```

Lendo a linha: um ou mais **globs** de nome de teste, depois ` - `, depois o **peso** do grupo.

Regras:

- O grupo é **tudo ou nada**: basta um teste do grupo falhar e o grupo vale 0.
- O valor total do problema é a **soma dos pesos**. Nada obriga a somar 100 (dá para passar disso).
- O separador entre globs é **vírgula e espaço** (`", "`). Isso não é estética: é o que o parser
  espera dos dois lados (API e juiz).
- Os exemplos costumam entrar com peso 0, para que apareçam no relatório sem valer nota.
- Linha começando com `#` é **comentário**. Qualquer outra linha que não seja
  `<globs> - <N> pontos` é **ignorada com aviso** no log do juiz — não vire grupo.
- O casamento teste→grupo é por **glob mesmo** (`aula_*` casa `aula_2_1`), e **todo teste
  precisa cair num grupo** (teste órfão zera a submissão; grupo de peso>0 sem teste derruba o
  veredicto). O `validate-problem.sh` confere tudo isso no upload (check `score_file_sane`).

Quem interpreta é o `mojtools/score-summary.sh`, no juiz. Editar o `tests/score` (ou um
`tests/output/*`) muda o checksum do pacote — o juiz re-baixa e recalibra sozinho.

### `sols/`

As soluções de referência, separadas por categoria. **A extensão do arquivo é o que define a
linguagem** (`sol.c` é C, `sol.cpp` é C++, `Main.java` é Java, e assim por diante).

| Diretório | O que é | Para que serve |
|---|---|---|
| `good/` | soluções **corretas** | **obrigatório, pelo menos uma.** É o que a calibração roda para descobrir o tempo-limite, e o que a validação exige que seja aceito |
| `wrong/` | soluções **erradas** de propósito | conferir que os testes pegam o erro |
| `slow/` | soluções **lentas** de propósito | conferir que o tempo-limite realmente reprova a solução ruim |
| `pass/` | soluções que devem passar **raspando** | conferir que o tempo-limite não é apertado demais |
| `upcoming/` | rascunhos | não entram na conferência |

Na prática, ponha uma `good` em cada linguagem que você quer que o aluno possa usar. O tempo-limite é
calibrado **por linguagem**, e uma linguagem sem solução `good` aceita simplesmente não ganha
tempo-limite naquele juiz (o aluno não consegue usá-la).

### `scripts/` (correção especial)

Opcional. É como o problema **customiza** a compilação, a execução ou a comparação. O
`build-and-test.sh` procura os arquivos do problema **antes** dos padrões de `mojtools/lang/<lang>/`,
então qualquer coisa que você ponha aqui vence o comportamento normal.

Os usos mais comuns:

| Arquivo | Uso | Quantos no acervo |
|---|---|---|
| `scripts/<lang>/compile.sh` | **submissão de função**: o aluno entrega só a função, e este script injeta o `main` que lê a entrada, chama a função e imprime o resultado | 201 |
| `scripts/compare.sh` | **checker**: a resposta não é única (tolerância de ponto flutuante, várias respostas válidas), então o problema traz o próprio comparador | 18 |
| `scripts/checker.cpp` | o **fonte** do checker quando ele é [testlib](https://github.com/MikeMirzayanov/testlib) (padrão Polygon/Maratona). Vem junto de um `compare.sh` de 10 linhas — o **stub** — instalado por `mojtools/testlib/install-checker.sh`. **O `testlib.h` NÃO vai no pacote** (é vendorado no mojtools) e o binário do checker **nunca** é commitado (a *bridge* do mojtools o compila no juiz, sob demanda, e cacheia FORA de `scripts/`). |
| `scripts/arbitro.{cpp,py,sh}` + `scripts/c/{prep,run}.sh` | **problema interativo** (`mojtools/interactive/install-interactive.sh`) | — |

O contrato do comparador: recebe `$1` = saída do aluno, `$2` = saída esperada, `$3` = entrada, e
responde pelo código de saída (`4` = aceito, `5` = aceito com erro de formatação, `6` = resposta
errada, qualquer outro = erro de juiz).

**Stub, não cópia.** O que roda **no host do juiz** — `scripts/compare.sh`, `scripts/<lang>/prep.sh`,
`scripts/summary.sh` — vai no pacote como um **stub** que chama o driver canônico do mojtools; só o
que **entra na jaula** (`scripts/<lang>/run.sh`, `compile.sh`) é cópia de verdade. É o que permite
consertar um bug do driver **em um lugar só**: quando cada pacote levava a sua cópia da *bridge* do
checker, um bug nela nasceu replicado em 198 pacotes (e derrubava **todos** os testes de quem o
usasse). Um problema pode, claro, trocar o stub pelo seu próprio comparador (é o caso dos 18 do
acervo, todos escritos à mão).

Todo `.sh` em `scripts/` precisa do bit de execução (`chmod +x`) — e o bit **viaja** (o `moj
push`/`clone` e o `upload` preservam). Sem ele o juiz recebe *Permission denied* ao executar o
script: `compare.sh`/`prep.sh` rodam **no host** (fora da jaula) e viram **erro de juiz (UE) em todos
os testes**; `run.sh`/`compile.sh` são montados na jaula e viram Compilation Error. O
`validate-problem.sh` reprova o pacote (`scripts_exec`) antes que isso aconteça.

**Modo dos arquivos: 644 (ou 755 com `+x`), sempre.** O servidor normaliza em toda escrita, pelos dois
caminhos (`moj push` e `moj upload`) — não é o umask do processo que decide. Isso importa porque o
`tl-checksum` inclui o **modo** de `scripts/*`: se o mesmo conteúdo entrar com modo diferente conforme
o caminho, o juiz vê "pacote mudou" e **recalibra à toa**.

**Mexer em `scripts/` obriga a recalibrar** (seção 10).

O guia completo (submissão de função, proibir funções da biblioteca, checker com testlib, problema
interativo) está em `mojtools/docs/correcao-especial.md`.

### `conf`

Os limites e ajustes de execução. **É um arquivo de shell, lido com `source`**, então nunca
interpole nele conteúdo vindo de usuário.

Um `conf` típico do acervo é curto:

```sh
TLMOD[calibrafactor]=1.35
TLMOD[java.drift]=0.02
TLMOD[spim.sum]=1
ULIMITS[-u]=10000
ALLOWPARALLELTEST=y
```

Todas as chaves que o `build-and-test.sh` entende:

| Chave | Default | O que faz | Uso hoje |
|---|---|---|---|
| `TLMOD[calibrafactor]` | `1.35` | multiplicador aplicado ao tempo da solução `good` para virar o tempo-limite. Subir dá folga ao aluno | 453 |
| `TLMOD[<lang>.drift]` | `0` | tolerância de variação de tempo naquela linguagem antes de dar TLE | 404 (`java`) |
| `TLMOD[<lang>.sum]` | `0` | soma um valor fixo (em segundos) ao tempo-limite daquela linguagem | 405 (`spim`) |
| `TLMOD[<lang>.mult]` | `1` | multiplica o tempo-limite daquela linguagem | 0 |
| `ULIMITS[-u]` | `1024` | número máximo de processos. Java e outras runtimes precisam de mais (o acervo usa `10000`) | 453 |
| `ULIMITS[-s]` | `131072` (128 MB, em KB) | tamanho da pilha. Prefira `STACKLIMITMB` | 0 |
| `ULIMITS[-f]` | `256000` | tamanho máximo de arquivo que o programa pode escrever | 0 |
| `ALLOWPARALLELTEST` | ligado | `n` força os testes a rodarem um de cada vez (necessário quando o problema é sensível a tempo) | 453 |
| `STACKLIMITMB` | 128 | pilha em MB. Vence o `ULIMITS[-s]`. A JVM espelha isso no `-Xss` | 0 |
| `MEMLIMITMB` | sem limite por RSS | limite de memória em MB, medido pelo **pico de RSS**. Ligar isso desliga o limite de memória virtual (que penalizaria injustamente JVM e Go). A JVM usa este valor no `-Xmx` | 0 |
| `COMPILEMEMLIMIT` | `2048` | memória em MB liberada para a **compilação** (o `kotlinc` passa de 600 MB) | 0 |
| `MAXPARALLELTESTS` | nº de CPUs | teto de testes em paralelo | 0 |
| `STOPWHEN_WA` | não para | `y` interrompe no primeiro Wrong Answer | 0 |
| `STOPWHEN_TLE` | não para | `y` interrompe no primeiro Time Limit Exceeded | 0 |
| `STOPWHEN_RE` | não para | `y` interrompe no primeiro Runtime Error | 0 |
| `TLERERUN` | `y` | repete o teste uma vez antes de confirmar um TLE (evita TLE por ruído da máquina) | 0 |
| `CALIBRATIONTL` | `5` | tempo-limite usado **durante** a calibração, antes de existir um TL real | 0 |

A coluna "uso hoje" conta em quantos dos 453 `conf` do acervo a chave aparece. Um zero não quer dizer
que a chave não funciona: quer dizer que o default serve para quase todo problema. Mexa só quando
tiver um motivo (um problema que exige muita memória, ou uma linguagem que precisa de folga).

`PUBLIC=no` no `conf` é **legado**. Hoje quem decide se o problema é público é o campo `public` do
`.moj-meta.json`.

### `author`

Texto livre, um autor por linha. É servido ao aluno **verbatim** (as linhas são juntadas com
`", "`). Não separe por vírgula esperando que o sistema divida: a vírgula já aparece dentro das
linhas ("Fulano, adaptado por Beltrano").

O arquivo é **obrigatório**: sem ele, a validação reprova.

### `tags`

Os assuntos do problema, uma tag por linha, começando com `#`, em minúsculas:

```
#grafos
#bfs
#matriz
```

As tags alimentam a busca do treino e o **sorteio** de problemas na criação de contest.

**Dificuldade não é uma tag e não existe no pacote.** Ela é **calculada** a partir da taxa de acerto
real dos alunos (fácil se pelo menos metade acerta, difícil se menos de 20% acerta, desconhecida se
ninguém tentou). Não adianta procurar um campo de dificuldade para preencher.

### `tl` e `tl.<host>`

**Você não escreve estes arquivos.** Eles são gerados pela calibração, no juiz. Ver a seção 10.

## 5. `.moj-meta.json`: os metadados do problema

É o metadado **canônico** do problema: o que não cabe em nenhum dos arquivos acima. Fica dentro do
pacote e é commitado junto com ele.

Quem escreve é o **servidor**, sempre (função `write_meta`, em `server/api/v1/lib/problems.sh`). Nem
o autor nem a CLI editam este arquivo à mão: eles mandam os campos pela API, e o servidor grava.

**No `moj upload` (o pacote sobe num tar), o servidor separa os campos em dois grupos:**

- **conteúdo** — `display_title` e `collections`: **vêm do `.moj-meta.json` do tar** (é o pacote que
  sabe como o problema se chama). Ausentes ⇒ o servidor **preserva** o que já tinha.
- **acesso** — `public`, `public_at` e `owner`: **nunca** vêm do tar; só as rotas próprias os mudam
  (`/problems/set-public` etc.). Se viessem, bastava baixar um problema público, adaptá-lo para uma
  prova numa org privada e dar `moj upload` — a próxima indexação publicaria a prova.

Exemplo real (`moj-problems/apc/seno/.moj-meta.json`):

```json
{
  "public": true,
  "collections": ["problemas-apc"],
  "display_title": "Seno por série de Taylor",
  "owner": "ribas.admin",
  "gitea": { "owner": "ribas.admin", "repo": "apc" },
  "languages": ["c", "cpp", "java", "py", "rs"]
}
```

Campo a campo:

| Campo | Tipo | O que é |
|---|---|---|
| `display_title` | texto | **O título do problema.** É a fonte única. Se o autor não mandar um título e o campo ainda não existir, o servidor **deriva** um (do `%` do enunciado, do `#+title:` do org, do `\section{}` do tex, ou, em último caso, do nome do diretório). Por isso o campo nunca fica vazio |
| `owner` | login | o dono do problema |
| `public` | booleano | se `true`, o problema entra no treino livre. Publicar exige que a **org** permita (seção 7) |
| `collections` | lista de textos | as coleções em que o problema está (seção 8). Pode estar em várias |
| `languages` | lista de ids | as linguagens de submissão **permitidas** neste problema. Vazio ou ausente = todas as linguagens padrão. É o que permite um problema só-PDDL, por exemplo. O servidor normaliza (minúsculas, `py2`/`py3` viram `py`, sem repetidos) |
| `public_at` | epoch | quando o problema foi publicado **pela primeira vez**. Fica lá mesmo se despublicarem depois. Alimenta a estatística de entrada de problemas públicos |
| `migrated_at` | epoch | quando o problema veio de uma migração. Só informativo |

Dois campos são **legado** e não devem ser usados em código novo:

- `gitea.{owner,repo}`: sobrou da época em que os pacotes eram espelhados num Gitea. O Gitea foi
  removido. O campo continua nos 453 metas do acervo e ainda é lido em um único lugar, como
  alternativa para descobrir o `owner` de pacotes antigos.
- `collaborators`: é lido em alguns pontos, mas **nunca é escrito**, e está vazio em todo o acervo.
  No modelo por org, colaborar em um problema é **ser membro da org** (seção 7).

Quem lê o `.moj-meta.json`: o `gen-problem-json.sh` (para montar o índice do aluno), o
`gen-problem-owners.sh` (para montar o índice de donos), e a API, ao devolver o problema ao editor e
à CLI.

## 6. `.moj-id`: o ponteiro local da CLI

Atenção, porque este é o ponto que mais confunde: **`.moj-id` não faz parte do pacote.** Repare
também que ele **não tem extensão `.json`** (não existe nenhum arquivo `.moj-id.json` no MOJ), mesmo
que o conteúdo seja JSON.

Ele é criado pelo **`moj-cli`**, na sua máquina, quando você roda `moj clone` ou `moj new`. Serve
para o clone local lembrar de qual problema ele é, e para carregar os campos editáveis do metadado de
ida e volta. O `moj push` **exclui** este arquivo do que sobe.

```json
{ "id": "apc#seno", "repo": "apc", "prob": "seno", "title": "Seno por série de Taylor",
  "format": "md", "collections": ["problemas-apc"], "public": true }
```

| Campo | O que é |
|---|---|
| `id`, `repo`, `prob` | qual problema este diretório é (`<org>#<prob>`) |
| `title` | espelho local do `display_title`. Editar aqui e dar `push` muda o título no servidor. O `push` **recusa** enviar com o título vazio |
| `format` | `md`, `org` ou `tex`, o formato do enunciado deste clone |
| `collections`, `languages`, `public` | espelhos locais dos campos do `.moj-meta.json`, com ida e volta pelo `push` |
| `scripts_rt` | marca que este clone sabe fazer ida e volta de `scripts/` e `tests/score`. Sem essa marca, o `push` não tem permissão de **apagar** esses arquivos no servidor (protege clones antigos de destruir a correção especial sem querer) |

Resumindo a diferença:

| | `.moj-meta.json` | `.moj-id` |
|---|---|---|
| Onde vive | dentro do pacote, no servidor | no clone local do autor |
| Quem escreve | o servidor | o `moj-cli` |
| Vai para o servidor? | **é** o do servidor | **não**, é excluído do envio |
| Para que serve | ser o metadado canônico | lembrar de qual problema é o diretório e levar os campos de ida e volta |

Os 336 `.moj-id` que aparecem hoje dentro de `moj-problems/` são **resíduo** de migrações antigas que
copiaram diretórios inteiros. O servidor os ignora.

## 7. ORG: quem pode mexer

Uma **org** é um grupo de acesso. Ela é a parte antes do `#` no id do problema (`apc#fatorial` está na
org `apc`), e é ela que decide **quem pode editar** o problema.

O registro fica em `contests/treino/var/orgs.json`, e o código em `server/api/v1/lib/orgs.sh`.

```json
{
  "monitores": {
    "created_by": "ribas.admin",
    "title": "monitores",
    "members": ["ribas.admin", "ryshim.admin"],
    "admins":  ["ribas.admin"],
    "public_allowed": true,
    "at": 1783051935
  },
  "ribas.admin": {
    "created_by": "ribas.admin", "title": "ribas.admin",
    "members": ["ribas.admin"], "admins": ["ribas.admin"],
    "public_allowed": false, "implicit": true, "at": 1783515797
  }
}
```

| Campo | O que é |
|---|---|
| `members` | quem **escreve** nos problemas da org. Ser membro de uma org dá acesso de edição a **todos** os problemas dela |
| `admins` | quem gere os membros e mexe na trava `public_allowed` |
| `public_allowed` | se `false` (o **default**), **nenhum** problema da org pode ficar público |
| `implicit` | marca a org pessoal de um usuário (ver abaixo) |
| `created_by`, `title`, `at` | quem criou, rótulo de exibição, quando |

As regras que valem a pena guardar:

- **Ser membro da org é a única forma de editar um problema.** Não existe atalho de administrador
  global: nem o `.admin` vê o código-fonte, as soluções ou o pacote de um problema de uma org de que
  não é membro.
- **A org nasce privada** (`public_allowed: false`). Isso é proposital: uma prova em elaboração não
  pode escapar por acidente. Enquanto a trava estiver fechada, publicar um problema da org retorna
  erro. Se um admin **rebaixar** a org depois, os problemas públicos dela são despublicados em
  cascata.
- **Todo usuário tem uma org pessoal**, com o nome do próprio login (a org **implícita**). Ela é
  criada sozinha, tem só você como membro, e **nunca** pode liberar público. É onde ficam os
  rascunhos.
- **Quem não pode ver recebe 404, não 403.** Dizer "403, existe mas você não pode ver" já vazaria a
  existência de um problema de prova. Problema privado simplesmente **não aparece** nas listagens,
  nem para o `.admin`.
- Uma org só pode ser **removida se estiver vazia**, e a org implícita nunca é removida.

Um problema pode ser **movido** de org enquanto for rascunho (`moj mv`, ou pelo editor). Isso muda o
id, então o MOJ recusa mover problema que já é público ou que já está em uso em algum contest.

Rotas: `/orgs/*` em [API.md](API.md). Pela CLI: `moj org list|create|members|public|rm` e
`moj share <org> <login>`.

## 8. COLEÇÃO: como os problemas são agrupados

Uma **coleção** é um rótulo de agrupamento, e nada mais. `problemas-apc`, `obi2016`,
`obi2016-fase2-senior` são coleções.

O registro fica em `contests/treino/var/collections.json`:

```json
{
  "problemas-apc":         { "owner": "ribas.admin", "created_by": "ribas.admin", "at": 1782519704 },
  "obi2016-fase2-senior":  { "owner": "ribas.admin", "created_by": "ribas.admin", "at": 1782927032 }
}
```

O que um problema está em quais coleções, isso mora no `.moj-meta.json` dele, no campo
`collections` (uma lista, porque **um problema pode estar em várias coleções ao mesmo tempo**, e elas
podem ser de orgs diferentes).

Pontos importantes:

- **Coleção não dá acesso a nada.** Marcar um problema numa coleção não deixa ninguém editá-lo. Quem
  decide acesso é a org, sempre.
- O nome é **texto livre**: pode ter espaço e acento (`"Maratona 2024, fase 1"` é um nome válido). Ele
  nunca vira caminho de arquivo nem id.
- O registro é **curado**: para marcar um problema numa coleção, ela precisa **já existir**. Isso
  evita o zoológico de coleções escritas com um typo cada.
- Renomear ou apagar uma coleção reetiqueta **todos** os problemas que a tinham, de uma vez.
- Só o dono da coleção (ou um `.admin`) renomeia ou apaga.

Para que servem, na prática:

1. **Navegação no treino**: o aluno filtra os problemas por coleção.
2. **Sorteio de problemas** na criação de um contest: você pede "5 problemas da coleção X, com a tag
   `grafos`, dificuldade média", e o sistema sorteia (de forma reproduzível, a partir de uma
   semente).

Rotas: `/problems/collection*` em [API.md](API.md). Pela CLI:
`moj collection ls|show|create|add|remove|rename|delete`.

## 9. ORG x COLEÇÃO

Este é o par que mais gera confusão, então vale a tabela. **Os dois são ortogonais**: um problema tem
exatamente uma org e pode ter várias coleções.

| | ORG | COLEÇÃO |
|---|---|---|
| Para que serve | **acesso** (quem edita, quem vê) | **agrupamento** (navegar, sortear) |
| Quantas por problema | exatamente **uma** | **várias**, ou nenhuma |
| Aparece no id? | sim, é o `<org>` de `<org>#<prob>` | não |
| Atravessa orgs? | não faz sentido | sim, uma coleção junta problemas de orgs diferentes |
| Tem membros? | sim (`members`, `admins`) | não |
| Controla publicação? | sim (`public_allowed`) | não |
| Onde é registrada | `contests/treino/var/orgs.json` | `contests/treino/var/collections.json` |
| Onde o problema a declara | no próprio id | no `.moj-meta.json`, campo `collections` |

Em uma frase: **a org diz quem manda no problema, a coleção diz onde ele aparece.**

## 10. Ciclo de vida de um problema

```
  rascunho  ──►  validação  ──►  calibração  ──►  público
 (org privada)   (portão)        (nos juízes)    (treino livre)
```

### Rascunho

O problema nasce na sua org (a pessoal, se você não escolher outra). Ele é privado: ninguém além dos
membros da org vê que ele existe.

### Validação (o portão de qualidade)

Roda `mojtools/validate-problem.sh`, que grava um relatório em `run/validation/<id>.json`. **Todas**
as checagens abaixo precisam passar (não existe checagem "opcional" que reprove pela metade):

| Checagem | O que exige |
|---|---|
| `has_author` | existe o arquivo `author` |
| `has_statement` | existe `docs/enunciado.{md,org,tex}` |
| `html_builds` | o pandoc consegue renderizar o enunciado |
| `secao_entrada` | o enunciado tem `## Entrada` |
| `secao_saida` | o enunciado tem `## Saída` |
| `examples_present` | existe pelo menos um par input/output |
| `tests_paired` | todo input tem seu output, e vice-versa |
| `has_good_sol` | existe pelo menos uma solução em `sols/good/` |
| `good_sol_accepts` | toda solução `good` é aceita |

Alguns avisos são **informativos** e não reprovam: LaTeX vazando na prosa do enunciado, exemplo
escrito à mão dentro do texto, e checker commitado como binário (padrão antigo, deprecado: mande o
fonte `scripts/checker.cpp` e deixe a bridge compilar).

Sobre o `good_sol_accepts`: rodar as soluções exige um sandbox de verdade. Na máquina de
desenvolvimento o `bwrap` é um no-op (`fbwrap`), então a validação **adia** essa checagem para a
calibração, que roda num juiz real. Isso não é bug.

Se a validação passa, ela **indexa** o problema (chama o `gen-problem-json.sh`), que gera o JSON que o
aluno de fato consome, com o enunciado já em HTML.

### Calibração (de onde vem o tempo-limite)

**O tempo-limite não é escrito à mão no pacote.** Ele é **medido**.

Um juiz baixa o pacote, roda cada solução de `sols/good/`, pega o pior tempo de cada linguagem,
multiplica pelo `TLMOD[calibrafactor]` (1.35 por padrão) e reporta o resultado para o servidor. O
resultado fica em `run/tl/<id>.json`, guardado **por máquina**:

```json
{ "id": "apc#ajude_simplificado", "checksum": "df7f628e84bfc6c3", "updated_at": 1783534737,
  "hosts": {
    "cpu1": { "tl": { "c": ".0335", "cpp": ".0335", "java": ".3710", "py": ".1685",
                      "default": ".0335" }, "at": 1783534737 },
    "cpu2": { "tl": { "…": "…" }, "at": 1783534733 } } }
```

O tempo-limite **servido** ao aluno é o **maior entre as máquinas**, para que a submissão não seja
reprovada por ter caído num juiz mais lento. Uma linguagem só ganha tempo-limite se alguma solução
`good` naquela linguagem foi **aceita** em algum juiz. Sem tempo-limite, a linguagem não fica
disponível.

### O checksum, e o que dispara recalibração

O campo `checksum` acima é o que amarra o TL ao pacote. Ele é calculado pelo `tl-checksum.sh` e cobre
**só o que pode mudar o tempo de execução**:

| Entra no checksum | Não entra |
|---|---|
| `conf` | `docs/enunciado.*` |
| `tests/input/*` | `tags` |
| `sols/good/*` | `author` |
| `scripts/*` (conteúdo **e** bit de execução) | `tests/output/*` |

Se o checksum do pacote deixa de bater com o guardado, o TL é considerado **velho** e some (o problema
passa a aparecer como "precisa recalibrar"). Ou seja: **corrigir um typo no enunciado não força
recalibração; trocar um teste, uma solução `good`, o `conf` ou um script força.**

### Publicação

Publicar (`moj publish`, ou o botão no editor) faz o servidor **validar e calibrar**. O problema só
entra no treino livre se os dois passarem. E, antes de tudo isso, a **org** precisa ter
`public_allowed: true` (seção 7).

## 11. Perguntas frequentes

**Onde eu ponho o título?**
No campo `display_title` do `.moj-meta.json`, e na prática você o edita pelo editor web ou pelo campo
`title` do `.moj-id` (a CLI). Nunca no texto do enunciado.

**Como eu escrevo o tempo-limite?**
Você não escreve. Ele é medido pela calibração. O que você pode ajustar é a **folga**, pelo
`TLMOD[calibrafactor]` no `conf`.

**Quero que o problema só aceite Python.**
Ponha `["py"]` no campo `languages` do `.moj-meta.json` (pelo editor ou pelo `.moj-id`).

**Meu problema tem várias respostas certas.**
Você precisa de um checker: `scripts/compare.sh`. Ver `mojtools/docs/correcao-especial.md` e o guia
de testlib em `mojtools/docs/checker-testlib.md`.

**O aluno vai entregar só uma função, não o programa inteiro.**
É a submissão de função: `scripts/<lang>/compile.sh`. Mesmo guia.

**Editei o enunciado. Preciso recalibrar?**
Não. O enunciado não entra no checksum.

**Onde fica a dificuldade do problema?**
Em lugar nenhum do pacote. Ela é calculada da taxa de acerto real dos alunos.

**Qual é a diferença entre `.moj-meta.json` e `.moj-id`?**
Ver a tabela no fim da seção 6. Em uma frase: o primeiro é o metadado do servidor, o segundo é um
bilhete que a CLI deixa no seu diretório local e que nunca sobe.

---

## Ponteiros

- **Roteiro prático** de montar um pacote, e a referência de cada comando: `mojtools/README.md`.
- **Correção especial** (checker, submissão de função, interativo): `mojtools/docs/correcao-especial.md`,
  `mojtools/docs/checker-testlib.md`, `mojtools/docs/problema-interativo.md`.
- **Rotas da API** que leem e escrevem o pacote, as orgs e as coleções: [API.md](API.md).
- **Arquitetura** geral: [OVERVIEW.md](OVERVIEW.md). **Caminho de uma submissão**: [FLOW.md](FLOW.md).
- **A CLI de autoria** (`moj`): `moj-cli/README.md`.
