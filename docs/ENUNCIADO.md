# Escrevendo o enunciado: Markdown e fórmulas

Este é o guia de **como escrever** o `docs/enunciado.md`, com exemplos para copiar. O formato do
pacote (onde fica cada arquivo, título, exemplos, idiomas) está no [PACOTE](PACOTE.md); aqui o
assunto é o **texto**: a formatação e, principalmente, as fórmulas.

O enunciado é **Markdown** (o do pandoc) com fórmulas em **TeX** entre `$`. O mesmo texto vira duas
coisas:

- o **HTML** que o aluno lê no site: fórmula em MathML, desenhada pelo navegador. É o que o
  "Pré-visualizar" do editor e o `moj preview` mostram;
- o **PDF do caderno** da prova (Evento › Documentos): fórmula desenhada pelo LibreOffice, que
  tem limites próprios. A coluna **PDF** das tabelas abaixo diz como cada construção sai lá:
  ✓ sai certo; ⚠ sai diferente (e a nota diz como).

> Também valem `enunciado.org` e `enunciado.tex`, mas o `.md` é o formato canônico e o único
> aceito nas traduções. Esta página usa Markdown.

## 1. O esqueleto

```markdown
Joana tem uma sequência de $N$ inteiros e quer saber quantos pares de posições $(i, j)$, com
$i < j$, têm soma par.

## Entrada

A primeira linha contém um inteiro $N$ ($1 \le N \le 2 \cdot 10^5$). A segunda linha contém
$N$ inteiros $a_1, a_2, \ldots, a_N$ ($|a_i| \le 10^9$).

## Saída

Imprima um único inteiro: a quantidade de pares.
```

Três regras que a validação cobra ou avisa:

1. **`## Entrada` e `## Saída` são obrigatórias** (valem também `## Input`/`## Output`). Outras
   seções são livres: `## Notas`, `## Observação`, `## Subtarefas`…
2. **O título não vai no texto.** Ele é um campo do problema; um `% Título` na primeira linha é
   legado e é removido.
3. **Os exemplos não vão no texto.** Eles vêm de `tests/input/sample*` e aparecem sozinhos no fim.
   A explicação de cada um vai em `docs/notes/sample1.md` (ver [PACOTE](PACOTE.md)).

## 2. Texto

| Você escreve | Sai | PDF |
|---|---|---|
| `*itálico*` ou `_itálico_` | *itálico* | ✓ |
| `**negrito**` | **negrito** | ✓ |
| `` `abacaba` `` (código, cadeias, nomes de arquivo) | `abacaba` | ✓ |
| `[texto](https://exemplo.org)` | [texto](https://exemplo.org) | ✓ (o texto) |
| `## Seção` / `### Subseção` | título de seção | ✓ |
| `R\$ 10,00` | R\$ 10,00 | ✓ |
| `\*` `\_` `\#` (o caractere, sem formatar) | \* \_ \# | ✓ |

**Parágrafo** é separado por uma **linha em branco**. Quebrar a linha no meio de um parágrafo não
muda nada (o texto continua no mesmo parágrafo) — escreva à vontade, uma frase por linha.

**Listas** — com `-` ou números, e uma linha em branco antes:

```markdown
As operações são:

- `ADD x`: insere $x$ no conjunto;
- `DEL x`: remove $x$;
- `QRY`: imprime o menor elemento.

1. primeiro passo;
2. segundo passo.
```

**Tabela** (a linha de `---` é obrigatória; `:---:` centraliza):

```markdown
| Subtarefa | Pontos | Restrições        |
|:---------:|:------:|-------------------|
| 1         | 20     | $N \le 100$       |
| 2         | 80     | sem restrições    |
```

**Bloco de código** (entrada ilustrativa, um trecho de programa) — três crases antes e depois:

````markdown
```
3
1 2 3
```
````

**Citação**: comece a linha com `> `.

**Texto centralizado**: o bloco `::: center` (seção 3, "Centralizar") vale para texto também.

**Imagens**: seção 3.

### Tipografia

| Você escreve | Sai | PDF |
|---|---|---|
| `1--10` (meia-risca, para intervalos) | 1–10 | ✓ |
| `pausa --- assim` (travessão) | pausa — assim | ✓ |
| `"aspas"` e `'simples'` (viram curvas sozinhas) | “aspas” e ‘simples’ | ✓ |
| `...` | … | ✓ |
| `10\ km` (espaço que não quebra a linha) | 10 km | ✓ |
| `~~tachado~~` | ~~tachado~~ | ✓ |
| `[sublinhado]{.underline}` | <u>sublinhado</u> | ✓ |
| `H~2~O`, `2^10^` (índice e expoente no **texto**; em fórmula use `$…$`) | H<sub>2</sub>O, 2<sup>10</sup> | ✓ |
| `<!-- anotação do autor -->` | (não aparece) | ✓ |
| `---` numa linha própria, com linha em branco antes | linha horizontal | ✓ |
| linha terminada em `\` (quebra de linha forçada) | quebra a linha | ⚠ a linha antes da quebra sai esticada (o PDF é justificado); prefira parágrafos separados ou uma lista |
| nota de rodapé: `texto[^1]` e, depois, `[^1]: a nota` | nota no fim | ⚠ **o texto da nota some no PDF**; escreva a observação no próprio texto ou numa seção `## Notas` |

## 3. Imagens

### Adicionar

Ponha o arquivo em `docs/`, ao lado do `enunciado.md`, e cite pelo nome:

```markdown
![Mapa das cidades](mapa.png)
```

(ou cole/arraste a imagem no editor web: ela vai embutida no texto). Nomes simples (letras, dígitos,
`.`, `_`, `-`), formatos png, jpg, jpeg, gif, svg ou webp, até 2 MB — detalhes no [PACOTE](PACOTE.md).

O que você põe entre os colchetes decide o que sai:

| Você escreve | Sai |
|---|---|
| `![Mapa das cidades](mapa.png)` sozinha no parágrafo | **figura**: a imagem e, embaixo, a legenda "Mapa das cidades" (em itálico no PDF) |
| `![](mapa.png)` sozinha no parágrafo | a imagem, sem legenda |
| `… o símbolo ![](seta.png) indica …` no meio da frase | a imagem dentro da linha — só para ícones pequenos |

### Tamanho

Sem nada, a imagem sai no tamanho natural, sem passar da largura do texto (no site) nem da página
(no PDF). Para escolher, dê a largura **em %** da largura do texto:

```markdown
![Mapa das cidades](mapa.png){width=50%}
```

Vale no site e no PDF, e a altura acompanha (a proporção é mantida).

### Centralizar

Por padrão a imagem (e a figura) fica à **esquerda**. Para centralizar, ponha dentro de um bloco
`::: center`, com uma linha em branco antes:

```markdown
A rede fica assim:

::: center
![Mapa das cidades](mapa.png){width=60%}
:::
```

Vale no site (a página do problema, a prova, a aba HTML e o Pré-visualizar do editor) e no PDF, com a
legenda centralizada junto. Dentro do bloco pode ir mais de uma imagem, e texto também. (O
`moj preview` da linha de comando ainda mostra o bloco à esquerda.)

| Não funciona | Por quê |
|---|---|
| `![Mapa](mapa.png){.center}` | classe na **imagem** não centraliza (o `.center` é para o bloco) |
| `<center>…</center>` ou `<div style="text-align:center">…</div>` | HTML cru: centraliza no site, mas **não no PDF** |

### Grafo

Um grafo desenhado a partir de DOT, em vez de imagem colada: `mojtools/docs/enunciado-grafos.md`.

## 4. Fórmulas: as regras

- **Na linha**: `$...$`. **Em destaque** (centralizada, no próprio parágrafo): `$$...$$`.
- **Nada de espaço colado no `$`**: `$ x $` **não** é fórmula (sai o texto `$ x $`). Escreva `$x$`.
- **Toda** variável, número de restrição e expressão vai em fórmula: `$N$`, `$10^5$`,
  `$1 \le N \le 10^5$` — não `N`, `10^5` ou `1 ≤ N ≤ 10⁵` digitados como texto.
  No site parece igual, mas no **PDF** o `≤` e o `⁵` digitados no texto saem em outra fonte
  (a do corpo não tem esses caracteres).
- **Cifrão de verdade** no texto: `R\$`.
- **Macros** funcionam: `\newcommand{\abs}[1]{\left|#1\right|}` num parágrafo próprio, e depois
  `$\abs{x}$`.

## 5. Fórmulas: a cola

Cada linha: o que você escreve, como sai no site, e como sai no PDF do caderno.

### Índices, potências e restrições

| Você escreve | Sai | PDF |
|---|---|---|
| `$a_i$`, `$a_{i,j}$`, `$x_i^2$` | $a_i$, $a_{i,j}$, $x_i^2$ | ✓ |
| `$x^2$`, `$2^{n+1}$`, `$10^{18}$` | $x^2$, $2^{n+1}$, $10^{18}$ | ✓ |
| `$1 \le N \le 2 \cdot 10^5$` | $1 \le N \le 2 \cdot 10^5$ | ✓ |
| `$0 \le a_i < 2^{63}$` | $0 \le a_i < 2^{63}$ | ✓ |
| `$a \ne b$`, `$a \ge b$`, `$a \approx b$` | $a \ne b$, $a \ge b$, $a \approx b$ | ✓ |
| `$10^9 + 7$` | $10^9 + 7$ | ✓ |
| valores `$\le 10^9$` (relação sem o lado esquerdo) | valores $\le 10^9$ | ✓ |

### Frações, raízes, somatórios

| Você escreve | Sai | PDF |
|---|---|---|
| `$\frac{a}{b}$` | $\frac{a}{b}$ | ✓ |
| `$\dfrac{a}{b}$` (maior, na linha) | $\dfrac{a}{b}$ | ✓ |
| `$\sqrt{x}$`, `$\sqrt[3]{x}$` | $\sqrt{x}$, $\sqrt[3]{x}$ | ✓ |
| `$\sum_{i=1}^{n} a_i$`, `$\prod_{i=1}^{n} a_i$` | $\sum_{i=1}^{n} a_i$, $\prod_{i=1}^{n} a_i$ | ✓ |
| `$\max_{1 \le i \le n} a_i$`, `$\min(a, b)$` | $\max_{1 \le i \le n} a_i$, $\min(a, b)$ | ✓ |
| `$\binom{n}{k}$` | $\binom{n}{k}$ | ✓ |

### Funções, complexidade, aritmética

| Você escreve | Sai | PDF |
|---|---|---|
| `$\log n$`, `$\log_2 n$`, `$\ln x$` | $\log n$, $\log_2 n$, $\ln x$ | ✓ |
| `$\gcd(a, b)$`, `$\operatorname{lcm}(a, b)$` | $\gcd(a, b)$, $\operatorname{lcm}(a, b)$ | ✓ |
| `$O(n \log n)$`, `$O(n^2)$`, `$\mathcal{O}(1)$` | $O(n \log n)$, $O(n^2)$, $\mathcal{O}(1)$ | ✓ |
| `$a \bmod m$`, `$a \equiv b \pmod{m}$` | $a \bmod m$, $a \equiv b \pmod{m}$ | ✓ |
| `$\lfloor n / 2 \rfloor$`, `$\lceil n / k \rceil$` | $\lfloor n / 2 \rfloor$, $\lceil n / k \rceil$ | ✓ |
| `$a \times b$`, `$a \cdot b$`, `$a \pm b$` | $a \times b$, $a \cdot b$, $a \pm b$ | ✓ |
| `$n!$`, `$-x$` | $n!$, $-x$ | ✓ |
| `$\infty$` | $\infty$ | ✓ |

### Conjuntos, lógica, setas, grego

| Você escreve | Sai | PDF |
|---|---|---|
| `$\{1, 2, \ldots, n\}$` | $\{1, 2, \ldots, n\}$ | ✓ |
| `$a_1, \dots, a_n$`, `$a_1 + \cdots + a_n$` | $a_1, \dots, a_n$, $a_1 + \cdots + a_n$ | ✓ |
| `$x \in S$`, `$x \notin S$`, `$A \subseteq B$` | $x \in S$, $x \notin S$, $A \subseteq B$ | ✓ |
| `$A \cup B$`, `$A \cap B$`, `$\emptyset$` | $A \cup B$, $A \cap B$, $\emptyset$ | ✓ |
| `$\mathbb{Z}$`, `$\mathbb{N}$`, `$\mathbb{R}$` | $\mathbb{Z}$, $\mathbb{N}$, $\mathbb{R}$ | ✓ |
| `$\{x \in S \mid x > 0\}$` (use `\mid`, não `\|`) | $\{x \in S \mid x > 0\}$ | ✓ |
| `$a \land b$`, `$a \lor b$`, `$\neg a$`, `$a \oplus b$` | $a \land b$, $a \lor b$, $\neg a$, $a \oplus b$ | ✓ |
| `$\forall x$`, `$\exists y$` | $\forall x$, $\exists y$ | ✓ |
| `$a \to b$`, `$a \Rightarrow b$`, `$a \iff b$` | $a \to b$, $a \Rightarrow b$, $a \iff b$ | ✓ |
| `$\alpha$`, `$\beta$`, `$\pi$`, `$\varepsilon$`, `$\Delta$`, `$\Sigma$` | $\alpha$, $\beta$, $\pi$, $\varepsilon$, $\Delta$, $\Sigma$ | ✓ |

### Texto e espaço dentro da fórmula

| Você escreve | Sai | PDF |
|---|---|---|
| `$\text{se } x > 0$` (texto normal dentro da fórmula) | $\text{se } x > 0$ | ✓ |
| `$a\,b$` (espaço fino), `$a \quad b$` (espaço largo) | $a\,b$, $a \quad b$ | ✓ |
| `$\mathbf{v}$`, `$\mathrm{d}x$` | $\mathbf{v}$, $\mathrm{d}x$ | ✓ |
| `$\texttt{abc}$` | $\texttt{abc}$ | ⚠ outra fonte monoespaçada; para cadeias prefira `` `abc` `` fora da fórmula |
| `$50\%$`, `$a \# b$`, `$a \& b$` | $50\%$, $a \# b$, $a \& b$ | ✓ |

### Onde o PDF difere

| Você escreve | Sai | PDF |
|---|---|---|
| `$\bar{x}$`, `$\hat{x}$`, `$\vec{v}$`, `$\tilde{x}$`, `$\dot{x}$` | $\bar{x}$, $\hat{x}$, $\vec{v}$, $\tilde{x}$, $\dot{x}$ | ⚠ o acento sai solto, alto e pequeno |
| `$\overline{AB}$`, `$\underline{x}$` | $\overline{AB}$, $\underline{x}$ | ⚠ idem |
| `$f'(x)$`, `$f''(x)$` | $f'(x)$, $f''(x)$ | ⚠ a linha (′) sai pequena, afastada da letra |

Com acento, se o PDF importa, prefira outro nome (`$m$` para a média em vez de `$\bar{x}$`,
`$g$` em vez de `$f'$`). No site, tudo sai certo.

## 6. Parênteses, colchetes e barras

Escreva como no TeX; o tamanho se resolve sozinho:

- **Parênteses e colchetes comuns** ficam do tamanho do texto: `$(x_1, y_1)$` → $(x_1, y_1)$,
  `$[l, r]$` → $[l, r]$.
- **Crescem com o conteúdo**: `\left( … \right)` em volta de fração, somatório, matriz —
  `$\left( \frac{a}{b} \right)^2$` → $\left( \frac{a}{b} \right)^2$.
- **Intervalo semiaberto** funciona: `$[l, r)$` → $[l, r)$, `$(a, b]$` → $(a, b]$.
- **Chaves** precisam de barra: `$\{1, 2\}$` → $\{1, 2\}$ (sem a barra, `{` só agrupa).
- **Valor absoluto**: `$|x|$` → $|x|$ (ou `$\lvert x \rvert$`). **Norma**: `$\|v\|$` → $\|v\|$.
- **Divide / "tal que" / probabilidade condicional**: `$a \mid b$` → $a \mid b$,
  `$a \nmid b$` → $a \nmid b$, `$P(A \mid B)$` → $P(A \mid B)$.
- **Ângulo**: `$\langle a, b \rangle$` → $\langle a, b \rangle$.

## 7. Estruturas: casos, matrizes, alinhamento

Definição por casos:

```markdown
$$f(n) = \begin{cases} 1 & \text{se } n = 0 \\ 2 f(n-1) & \text{se } n > 0 \end{cases}$$
```

$$f(n) = \begin{cases} 1 & \text{se } n = 0 \\ 2 f(n-1) & \text{se } n > 0 \end{cases}$$

Matriz (`pmatrix` entre parênteses, `bmatrix` entre colchetes, `vmatrix` entre barras):

```markdown
$$A = \begin{pmatrix} a & b \\ c & d \end{pmatrix}, \qquad \det A = \begin{vmatrix} a & b \\ c & d \end{vmatrix}$$
```

$$A = \begin{pmatrix} a & b \\ c & d \end{pmatrix}, \qquad \det A = \begin{vmatrix} a & b \\ c & d \end{vmatrix}$$

Contas alinhadas no `=` (`&` marca o ponto de alinhamento, `\\` quebra a linha):

```markdown
$$\begin{aligned} S &= a_1 + a_2 + \cdots + a_n \\ &= \frac{n(n+1)}{2} \end{aligned}$$
```

$$\begin{aligned} S &= a_1 + a_2 + \cdots + a_n \\ &= \frac{n(n+1)}{2} \end{aligned}$$

Todas saem certas no PDF (✓).

## 8. O que evitar

| Evite | Por quê | Escreva |
|---|---|---|
| `1 ≤ N ≤ 10⁵` digitado como texto | no PDF sai em outra fonte | `$1 \le N \le 10^5$` |
| `\textbf{…}`, `\emph{…}`, `\section{…}`, `\begin{itemize}` | é LaTeX de texto, não Markdown: o texto **some**, sem aviso, no site e no PDF | `**…**`, `*…*`, `## …`, `- item` |
| `$ x $` | com espaço colado no `$` não é fórmula | `$x$` |
| exemplo copiado no texto | aparece duplicado (os exemplos vêm de `tests/`) | `tests/input/sample1` + `docs/notes/sample1.md` |
| `$\bar{x}$`, `$f'$` quando o PDF importa | ver a tabela "Onde o PDF difere" | outro nome |
| `{…}` para mostrar chaves | `{` só agrupa em TeX | `\{…\}` |
| `<center>`, `<div style=…>` para centralizar | no PDF não centraliza | `::: center` (seção 3) |
| nota de rodapé (`[^1]`) | no PDF o texto da nota some | a observação no texto ou em `## Notas` |

## 9. Um enunciado completo

```markdown
Uma loja registra o preço $p_i$ de cada um dos $N$ dias de uma temporada. Para um intervalo de
dias $[l, r)$ — do dia $l$ até o dia $r - 1$ —, o *lucro* é
$$L(l, r) = \max_{l \le i < r} p_i - \min_{l \le i < r} p_i.$$

Dadas $Q$ consultas, responda o lucro de cada intervalo. Se $r - l < 2$, o lucro é $0$.

## Entrada

A primeira linha contém dois inteiros $N$ e $Q$ ($1 \le N, Q \le 2 \cdot 10^5$). A segunda linha
contém $N$ inteiros $p_1, p_2, \ldots, p_N$ ($1 \le p_i \le 10^9$). Cada uma das $Q$ linhas
seguintes contém dois inteiros $l$ e $r$ ($1 \le l < r \le N + 1$).

## Saída

Para cada consulta, imprima uma linha com $L(l, r)$.

## Subtarefas

| Subtarefa | Pontos | Restrições                |
|:---------:|:------:|---------------------------|
| 1         | 30     | $N, Q \le 1000$           |
| 2         | 70     | sem restrições adicionais |
```

## 10. Como conferir

- **Site**: o botão **Pré-visualizar** do editor, ou `moj preview` na CLI (o mesmo renderizador
  do HTML que o aluno lê).
- **PDF**: o caderno é gerado pelo admin ou juiz-chefe da prova em **Evento › Documentos** —
  peça a geração e confira as fórmulas antes de publicar.

---

*Para quem mantém o MOJ*: o PDF do caderno sai por `pandoc -f html -t odt` → `soffice`. O
LibreOffice não desenha o MathML — traduz para StarMath e lê esse texto — e o
`server/api/v1/lib/odt-math-bars.py` conserta o MathML no meio do caminho (tamanho e fonte da
fórmula, delimitadores, caracteres de sintaxe, relação sem operando; e o tamanho das imagens); o
`server/api/v1/lib/odt-center.lua` centraliza o bloco `::: center` (estilo `Center` do
`server/etc/caderno-reference.odt`). A coluna **PDF** desta página
foi medida com pandoc 3.1.11 e LibreOffice 25.2 (as versões da imagem); os testes que a sustentam
são `server/test/smoke-odt-math-bars.sh` e `server/test/render-docs.sh`.
