<!-- i18n-source: ENUNCIADO.md blob:f5fe9f2a5b40ad163417a47e89df1ace605fd0cb -->
# Writing the statement: Markdown and formulas

> **Translation note.** This manual is a translation of the Portuguese original. The command-line tools (`moj`, `moj-contest`, `moj-comp`) print their messages in Portuguese, and the command examples below are identical to the original.

This guide tells you **how to write** the `docs/enunciado.md` file. It has examples that you can copy. The
[PACOTE](PACOTE.md) document gives the package format (the location of each file, the title, the samples,
the languages). This page is about the **text**: the formatting and, most importantly, the formulas.

The statement is **Markdown** (the pandoc dialect) with formulas in **TeX** between `$` signs. The same
text becomes two things:

- the **HTML** that the student reads on the site. The formulas are in MathML, and the browser draws them.
  The editor's "👁 Preview" and `moj preview` show this HTML;
- the **PDF of the problem set** of the contest (Event › Documents). LibreOffice draws the formulas, and it
  has its own limits. The **PDF** column of the tables below tells you how each construct comes out there:
  ✓ it comes out correctly; ⚠ it comes out differently (the note tells you how).

> `enunciado.org` and `enunciado.tex` are also valid. But `.md` is the canonical format, and it is the only
> format that translations accept. This page uses Markdown.

## 1. The skeleton

```markdown
Joana has a sequence of $N$ integers. She wants to know how many pairs of positions $(i, j)$, with
$i < j$, have an even sum.

## Input

The first line contains an integer $N$ ($1 \le N \le 2 \cdot 10^5$). The second line contains
$N$ integers $a_1, a_2, \ldots, a_N$ ($|a_i| \le 10^9$).

## Output

Print a single integer: the number of pairs.
```

The validation enforces or warns about three rules:

1. **`## Input` and `## Output` are required.** The Portuguese headings `## Entrada`/`## Saída` are also
   valid (and so are the Spanish `## Entrada`/`## Salida`). You can add other sections freely:
   `## Notes`, `## Remarks`, `## Subtasks`…
2. **Do not put the title in the text.** The title is a field of the problem. A `% Title` on the first
   line is legacy, and the system removes it.
3. **Do not put the samples in the text.** They come from `tests/input/sample*`, and they appear
   automatically at the end. Put the explanation of each sample in `docs/notes/sample1.md` (see
   [PACOTE](PACOTE.md)).

## 2. Text

| You write | Result | PDF |
|---|---|---|
| `*italic*` or `_italic_` | *italic* | ✓ |
| `**bold**` | **bold** | ✓ |
| `` `abacaba` `` (code, strings, file names) | `abacaba` | ✓ |
| `[text](https://exemplo.org)` | [text](https://exemplo.org) | ✓ (the text) |
| `## Section` / `### Subsection` | section heading | ✓ |
| `R\$ 10,00` | R\$ 10,00 | ✓ |
| `\*` `\_` `\#` (the character, without formatting) | \* \_ \# | ✓ |

A **blank line** separates **paragraphs**. A line break inside a paragraph changes nothing (the text
stays in the same paragraph). You can write as you like, for example one sentence per line.

**Lists**: use `-` or numbers, and put a blank line before the list:

```markdown
The operations are:

- `ADD x`: inserts $x$ into the set;
- `DEL x`: removes $x$;
- `QRY`: prints the smallest element.

1. first step;
2. second step.
```

**Table** (the `---` line is required; `:---:` centers the column):

```markdown
| Subtask   | Points | Constraints       |
|:---------:|:------:|-------------------|
| 1         | 20     | $N \le 100$       |
| 2         | 80     | no constraints    |
```

**Code block** (an illustrative input, a piece of a program): put three backticks before and after it:

````markdown
```
3
1 2 3
```
````

**Quotation**: start the line with `> `.

**Centered text**: the `::: center` block (section 3, "Center") also applies to text.

**Images**: see section 3.

### Typography

| You write | Result | PDF |
|---|---|---|
| `1--10` (en dash, for ranges) | 1–10 | ✓ |
| `pause --- like this` (em dash) | pause — like this | ✓ |
| `"quotes"` and `'single'` (they become curly automatically) | “quotes” and ‘single’ | ✓ |
| `...` | … | ✓ |
| `10\ km` (a space that does not break the line) | 10 km | ✓ |
| `~~strikethrough~~` | ~~strikethrough~~ | ✓ |
| `[underlined]{.underline}` | <u>underlined</u> | ✓ |
| `H~2~O`, `2^10^` (subscript and superscript in the **text**; in a formula, use `$…$`) | H<sub>2</sub>O, 2<sup>10</sup> | ✓ |
| `<!-- author's note -->` | (does not appear) | ✓ |
| `---` on its own line, with a blank line before it | horizontal rule | ✓ |
| line that ends with `\` (forced line break) | breaks the line | ⚠ the line before the break comes out stretched (the PDF is justified); use separate paragraphs or a list |
| footnote: `text[^1]` and, later, `[^1]: the note` | note at the end | ⚠ **the text of the note disappears in the PDF**; write the remark in the text itself or in a `## Notes` section |

## 3. Images

### Add

Put the file in `docs/`, next to `enunciado.md`, and refer to it by its name:

```markdown
![Map of the cities](mapa.png)
```

(You can also paste or drag the image into the web editor. The editor then embeds it in the text.) Use
simple names (letters, digits, `.`, `_`, `-`). The formats are png, jpg, jpeg, gif, svg or webp, up to
2 MB. The [PACOTE](PACOTE.md) document gives the details.

The text between the brackets decides the result:

| You write | Result |
|---|---|
| `![Map of the cities](mapa.png)` alone in the paragraph | **figure**: the image and, below it, the caption "Map of the cities" (in italics in the PDF) |
| `![](mapa.png)` alone in the paragraph | the image, without a caption |
| `… the symbol ![](seta.png) indicates …` in the middle of a sentence | the image inside the line — only for small icons |

### Size

If you specify nothing, the image comes out at its natural size. It does not go past the width of the text
(on the site) or of the page (in the PDF). To set the size, give the width **in %** of the text width:

```markdown
![Map of the cities](mapa.png){width=50%}
```

This applies on the site and in the PDF. The height follows (the aspect ratio stays the same).

### Center

By default, the image (and the figure) is on the **left**. To center it, put it inside a `::: center`
block, with a blank line before the block:

```markdown
The network looks like this:

::: center
![Map of the cities](mapa.png){width=60%}
:::
```

This applies on the site (the problem page, the contest, the HTML tab and the editor's 👁 Preview) and in the
PDF. The caption is centered too. The block can contain more than one image, and also text. (The
command-line `moj preview` still shows the block on the left.)

| Does not work | Why |
|---|---|
| `![Map](mapa.png){.center}` | a class on the **image** does not center it (`.center` is for the block) |
| `<center>…</center>` or `<div style="text-align:center">…</div>` | raw HTML: it centers on the site, but **not in the PDF** |

### Graph

To draw a graph from DOT instead of a pasted image, see `mojtools/docs/enunciado-grafos.md`.

## 4. Formulas: the rules

- **Inline**: `$...$`. **Display** (centered, in its own paragraph): `$$...$$`.
- **Do not put a space next to the `$`**: `$ x $` is **not** a formula (the output is the text `$ x $`).
  Write `$x$`.
- Put **every** variable, constraint number and expression in a formula: `$N$`, `$10^5$`,
  `$1 \le N \le 10^5$`. Do not type `N`, `10^5` or `1 ≤ N ≤ 10⁵` as text.
  On the site they look the same. But in the **PDF**, the `≤` and the `⁵` typed in the text come out in a
  different font (the body font does not have these characters).
- **A real dollar sign** in the text: `R\$`.
- **Macros** work: put `\newcommand{\abs}[1]{\left|#1\right|}` in its own paragraph, and then use
  `$\abs{x}$`.

## 5. Formulas: the cheat sheet

Each row gives what you write, how it comes out on the site, and how it comes out in the PDF of the problem
set.

### Subscripts, powers and constraints

| You write | Result | PDF |
|---|---|---|
| `$a_i$`, `$a_{i,j}$`, `$x_i^2$` | $a_i$, $a_{i,j}$, $x_i^2$ | ✓ |
| `$x^2$`, `$2^{n+1}$`, `$10^{18}$` | $x^2$, $2^{n+1}$, $10^{18}$ | ✓ |
| `$1 \le N \le 2 \cdot 10^5$` | $1 \le N \le 2 \cdot 10^5$ | ✓ |
| `$0 \le a_i < 2^{63}$` | $0 \le a_i < 2^{63}$ | ✓ |
| `$a \ne b$`, `$a \ge b$`, `$a \approx b$` | $a \ne b$, $a \ge b$, $a \approx b$ | ✓ |
| `$10^9 + 7$` | $10^9 + 7$ | ✓ |
| values `$\le 10^9$` (relation without the left side) | values $\le 10^9$ | ✓ |

### Fractions, roots, sums

| You write | Result | PDF |
|---|---|---|
| `$\frac{a}{b}$` | $\frac{a}{b}$ | ✓ |
| `$\dfrac{a}{b}$` (larger, inline) | $\dfrac{a}{b}$ | ✓ |
| `$\sqrt{x}$`, `$\sqrt[3]{x}$` | $\sqrt{x}$, $\sqrt[3]{x}$ | ✓ |
| `$\sum_{i=1}^{n} a_i$`, `$\prod_{i=1}^{n} a_i$` | $\sum_{i=1}^{n} a_i$, $\prod_{i=1}^{n} a_i$ | ✓ |
| `$\max_{1 \le i \le n} a_i$`, `$\min(a, b)$` | $\max_{1 \le i \le n} a_i$, $\min(a, b)$ | ✓ |
| `$\binom{n}{k}$` | $\binom{n}{k}$ | ✓ |

### Functions, complexity, arithmetic

| You write | Result | PDF |
|---|---|---|
| `$\log n$`, `$\log_2 n$`, `$\ln x$` | $\log n$, $\log_2 n$, $\ln x$ | ✓ |
| `$\gcd(a, b)$`, `$\operatorname{lcm}(a, b)$` | $\gcd(a, b)$, $\operatorname{lcm}(a, b)$ | ✓ |
| `$O(n \log n)$`, `$O(n^2)$`, `$\mathcal{O}(1)$` | $O(n \log n)$, $O(n^2)$, $\mathcal{O}(1)$ | ✓ |
| `$a \bmod m$`, `$a \equiv b \pmod{m}$` | $a \bmod m$, $a \equiv b \pmod{m}$ | ✓ |
| `$\lfloor n / 2 \rfloor$`, `$\lceil n / k \rceil$` | $\lfloor n / 2 \rfloor$, $\lceil n / k \rceil$ | ✓ |
| `$a \times b$`, `$a \cdot b$`, `$a \pm b$` | $a \times b$, $a \cdot b$, $a \pm b$ | ✓ |
| `$n!$`, `$-x$` | $n!$, $-x$ | ✓ |
| `$\infty$` | $\infty$ | ✓ |

### Sets, logic, arrows, Greek

| You write | Result | PDF |
|---|---|---|
| `$\{1, 2, \ldots, n\}$` | $\{1, 2, \ldots, n\}$ | ✓ |
| `$a_1, \dots, a_n$`, `$a_1 + \cdots + a_n$` | $a_1, \dots, a_n$, $a_1 + \cdots + a_n$ | ✓ |
| `$x \in S$`, `$x \notin S$`, `$A \subseteq B$` | $x \in S$, $x \notin S$, $A \subseteq B$ | ✓ |
| `$A \cup B$`, `$A \cap B$`, `$\emptyset$` | $A \cup B$, $A \cap B$, $\emptyset$ | ✓ |
| `$\mathbb{Z}$`, `$\mathbb{N}$`, `$\mathbb{R}$` | $\mathbb{Z}$, $\mathbb{N}$, $\mathbb{R}$ | ✓ |
| `$\{x \in S \mid x > 0\}$` (use `\mid`, not `\|`) | $\{x \in S \mid x > 0\}$ | ✓ |
| `$a \land b$`, `$a \lor b$`, `$\neg a$`, `$a \oplus b$` | $a \land b$, $a \lor b$, $\neg a$, $a \oplus b$ | ✓ |
| `$\forall x$`, `$\exists y$` | $\forall x$, $\exists y$ | ✓ |
| `$a \to b$`, `$a \Rightarrow b$`, `$a \iff b$` | $a \to b$, $a \Rightarrow b$, $a \iff b$ | ✓ |
| `$\alpha$`, `$\beta$`, `$\pi$`, `$\varepsilon$`, `$\Delta$`, `$\Sigma$` | $\alpha$, $\beta$, $\pi$, $\varepsilon$, $\Delta$, $\Sigma$ | ✓ |

### Text and space inside the formula

| You write | Result | PDF |
|---|---|---|
| `$\text{if } x > 0$` (normal text inside the formula) | $\text{if } x > 0$ | ✓ |
| `$a\,b$` (thin space), `$a \quad b$` (wide space) | $a\,b$, $a \quad b$ | ✓ |
| `$\mathbf{v}$`, `$\mathrm{d}x$` | $\mathbf{v}$, $\mathrm{d}x$ | ✓ |
| `$\texttt{abc}$` | $\texttt{abc}$ | ⚠ a different monospaced font; for strings, use `` `abc` `` outside the formula |
| `$50\%$`, `$a \# b$`, `$a \& b$` | $50\%$, $a \# b$, $a \& b$ | ✓ |

### Where the PDF is different

| You write | Result | PDF |
|---|---|---|
| `$\bar{x}$`, `$\hat{x}$`, `$\vec{v}$`, `$\tilde{x}$`, `$\dot{x}$` | $\bar{x}$, $\hat{x}$, $\vec{v}$, $\tilde{x}$, $\dot{x}$ | ⚠ the accent comes out detached, high and small |
| `$\overline{AB}$`, `$\underline{x}$` | $\overline{AB}$, $\underline{x}$ | ⚠ the same |
| `$f'(x)$`, `$f''(x)$` | $f'(x)$, $f''(x)$ | ⚠ the prime (′) comes out small and far from the letter |

If the PDF is important, do not use a name with an accent. Use a different name (`$m$` for the mean
instead of `$\bar{x}$`, `$g$` instead of `$f'$`). On the site, everything comes out correctly.

## 6. Parentheses, brackets and bars

Write them as in TeX. The size is set automatically:

- **Normal parentheses and brackets** have the size of the text: `$(x_1, y_1)$` → $(x_1, y_1)$,
  `$[l, r]$` → $[l, r]$.
- **They grow with the content**: use `\left( … \right)` around a fraction, a sum or a matrix:
  `$\left( \frac{a}{b} \right)^2$` → $\left( \frac{a}{b} \right)^2$.
- **Half-open intervals** work: `$[l, r)$` → $[l, r)$, `$(a, b]$` → $(a, b]$.
- **Braces** need a backslash: `$\{1, 2\}$` → $\{1, 2\}$ (without the backslash, `{` only groups).
- **Absolute value**: `$|x|$` → $|x|$ (or `$\lvert x \rvert$`). **Norm**: `$\|v\|$` → $\|v\|$.
- **Divides / "such that" / conditional probability**: `$a \mid b$` → $a \mid b$,
  `$a \nmid b$` → $a \nmid b$, `$P(A \mid B)$` → $P(A \mid B)$.
- **Angle brackets**: `$\langle a, b \rangle$` → $\langle a, b \rangle$.

## 7. Structures: cases, matrices, alignment

Definition by cases:

```markdown
$$f(n) = \begin{cases} 1 & \text{if } n = 0 \\ 2 f(n-1) & \text{if } n > 0 \end{cases}$$
```

$$f(n) = \begin{cases} 1 & \text{if } n = 0 \\ 2 f(n-1) & \text{if } n > 0 \end{cases}$$

Matrix (`pmatrix` between parentheses, `bmatrix` between brackets, `vmatrix` between bars):

```markdown
$$A = \begin{pmatrix} a & b \\ c & d \end{pmatrix}, \qquad \det A = \begin{vmatrix} a & b \\ c & d \end{vmatrix}$$
```

$$A = \begin{pmatrix} a & b \\ c & d \end{pmatrix}, \qquad \det A = \begin{vmatrix} a & b \\ c & d \end{vmatrix}$$

Calculations aligned on the `=` (`&` marks the alignment point, `\\` breaks the line):

```markdown
$$\begin{aligned} S &= a_1 + a_2 + \cdots + a_n \\ &= \frac{n(n+1)}{2} \end{aligned}$$
```

$$\begin{aligned} S &= a_1 + a_2 + \cdots + a_n \\ &= \frac{n(n+1)}{2} \end{aligned}$$

All of them come out correctly in the PDF (✓).

## 8. What to avoid

| Avoid | Why | Write |
|---|---|---|
| `1 ≤ N ≤ 10⁵` typed as text | in the PDF it comes out in a different font | `$1 \le N \le 10^5$` |
| `\textbf{…}`, `\emph{…}`, `\section{…}`, `\begin{itemize}` | this is LaTeX for text, not Markdown: the text **disappears**, without a warning, on the site and in the PDF | `**…**`, `*…*`, `## …`, `- item` |
| `$ x $` | with a space next to the `$`, it is not a formula | `$x$` |
| a sample copied into the text | it appears twice (the samples come from `tests/`) | `tests/input/sample1` + `docs/notes/sample1.md` |
| `$\bar{x}$`, `$f'$` when the PDF is important | see the table "Where the PDF is different" | a different name |
| `{…}` to show braces | in TeX, `{` only groups | `\{…\}` |
| `<center>`, `<div style=…>` to center | it does not center in the PDF | `::: center` (section 3) |
| footnote (`[^1]`) | in the PDF, the text of the note disappears | the remark in the text or in `## Notes` |

## 9. A complete statement

```markdown
A store records the price $p_i$ of each of the $N$ days of a season. For an interval of
days $[l, r)$ — from day $l$ to day $r - 1$ —, the *profit* is
$$L(l, r) = \max_{l \le i < r} p_i - \min_{l \le i < r} p_i.$$

Given $Q$ queries, answer the profit of each interval. If $r - l < 2$, the profit is $0$.

## Input

The first line contains two integers $N$ and $Q$ ($1 \le N, Q \le 2 \cdot 10^5$). The second line
contains $N$ integers $p_1, p_2, \ldots, p_N$ ($1 \le p_i \le 10^9$). Each of the next $Q$ lines
contains two integers $l$ and $r$ ($1 \le l < r \le N + 1$).

## Output

For each query, print a line with $L(l, r)$.

## Subtasks

| Subtask   | Points | Constraints               |
|:---------:|:------:|---------------------------|
| 1         | 30     | $N, Q \le 1000$           |
| 2         | 70     | no additional constraints |
```

## 10. How to check

- **Site**: use the **👁 Preview** button of the editor, or `moj preview` in the CLI (the same renderer
  as the HTML that the student reads).
- **PDF**: the admin or the chief judge of the contest generates the problem set in
  **Event › Documents**. Ask for the generation. Check the formulas before you publish.

---

*For the MOJ maintainers*: the PDF of the problem set comes from `pandoc -f html -t odt` → `soffice`.
LibreOffice does not draw the MathML. It translates the MathML to StarMath and reads that text.
`server/api/v1/lib/odt-math-bars.py` fixes the MathML between the two steps (the size and font of the
formula, the delimiters, the syntax characters, a relation without an operand, and also the size of the
images). `server/api/v1/lib/odt-center.lua` centers the `::: center` block (the `Center` style of
`server/etc/caderno-reference.odt`). The **PDF** column of this page
was measured with pandoc 3.1.11 and LibreOffice 25.2 (the versions in the image). The tests that support it
are `server/test/smoke-odt-math-bars.sh` and `server/test/render-docs.sh`.
