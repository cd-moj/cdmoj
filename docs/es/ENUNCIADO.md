<!-- i18n-source: ENUNCIADO.md blob:f5fe9f2a5b40ad163417a47e89df1ace605fd0cb -->
# Escribir el enunciado: Markdown y fórmulas

> **Nota de traducción.** Este manual es una traducción del original en portugués. Las herramientas de línea de comandos (`moj`, `moj-contest`, `moj-comp`) muestran sus mensajes en portugués, y los ejemplos de comandos son idénticos al original.

Esta es la guía de **cómo escribir** el `docs/enunciado.md`, con ejemplos para copiar. El formato del
paquete (dónde va cada archivo, título, ejemplos, idiomas) está en [PACOTE](PACOTE.md); aquí el
tema es el **texto**: el formato y, sobre todo, las fórmulas.

El enunciado es **Markdown** (el de pandoc) con fórmulas en **TeX** entre `$`. El mismo texto se
convierte en dos cosas:

- el **HTML** que el estudiante lee en el sitio: la fórmula va en MathML y la dibuja el navegador. Es
  lo que muestran la "👁 Vista previa" del editor y `moj preview`;
- el **PDF del cuadernillo** de la competencia (Evento › Documentos): la fórmula la dibuja
  LibreOffice, que tiene sus propios límites. La columna **PDF** de las tablas de abajo dice cómo sale
  allí cada construcción: ✓ sale bien; ⚠ sale distinto (y la nota dice cómo).

> También se aceptan `enunciado.org` y `enunciado.tex`, pero el `.md` es el formato canónico y el
> único que se acepta en las traducciones. Esta página usa Markdown.

## 1. El esqueleto

```markdown
Juana tiene una secuencia de $N$ enteros y quiere saber cuántos pares de posiciones $(i, j)$, con
$i < j$, tienen suma par.

## Entrada

La primera línea contiene un entero $N$ ($1 \le N \le 2 \cdot 10^5$). La segunda línea contiene
$N$ enteros $a_1, a_2, \ldots, a_N$ ($|a_i| \le 10^9$).

## Salida

Imprime un único entero: la cantidad de pares.
```

Tres reglas que la validación exige o sobre las que advierte:

1. **`## Entrada` y `## Salida` son obligatorias.** También valen `## Input`/`## Output` y el título
   portugués `## Saída`. Las demás secciones son libres: `## Notas`, `## Observaciones`, `## Subtareas`…
2. **El título no va en el texto.** Es un campo del problema; un `% Título` en la primera línea es
   un formato heredado y el sistema lo elimina.
3. **Los ejemplos no van en el texto.** Vienen de `tests/input/sample*` y aparecen solos al final.
   La explicación de cada uno va en `docs/notes/sample1.md` (ver [PACOTE](PACOTE.md)).

## 2. Texto

| Escribes | Resultado | PDF |
|---|---|---|
| `*cursiva*` o `_cursiva_` | *cursiva* | ✓ |
| `**negrita**` | **negrita** | ✓ |
| `` `abacaba` `` (código, cadenas, nombres de archivo) | `abacaba` | ✓ |
| `[texto](https://exemplo.org)` | [texto](https://exemplo.org) | ✓ (el texto) |
| `## Sección` / `### Subsección` | título de sección | ✓ |
| `R\$ 10,00` | R\$ 10,00 | ✓ |
| `\*` `\_` `\#` (el carácter, sin formato) | \* \_ \# | ✓ |

Los **párrafos** se separan con una **línea en blanco**. Cortar la línea en medio de un párrafo no
cambia nada (el texto sigue en el mismo párrafo): escribe con libertad, una oración por línea.

**Listas**: con `-` o con números, y una línea en blanco antes:

```markdown
Las operaciones son:

- `ADD x`: inserta $x$ en el conjunto;
- `DEL x`: elimina $x$;
- `QRY`: imprime el menor elemento.

1. primer paso;
2. segundo paso.
```

**Tabla** (la línea de `---` es obligatoria; `:---:` centra):

```markdown
| Subtarea  | Puntos | Restricciones     |
|:---------:|:------:|-------------------|
| 1         | 20     | $N \le 100$       |
| 2         | 80     | sin restricciones |
```

**Bloque de código** (entrada ilustrativa, un fragmento de programa): tres comillas invertidas antes y
después:

````markdown
```
3
1 2 3
```
````

**Cita**: empieza la línea con `> `.

**Texto centrado**: el bloque `::: center` (sección 3, "Centrar") también sirve para texto.

**Imágenes**: sección 3.

### Tipografía

| Escribes | Resultado | PDF |
|---|---|---|
| `1--10` (guion medio, para intervalos) | 1–10 | ✓ |
| `pausa --- así` (raya) | pausa — así | ✓ |
| `"comillas"` y `'simples'` (se vuelven curvas solas) | “comillas” y ‘simples’ | ✓ |
| `...` | … | ✓ |
| `10\ km` (espacio que no corta la línea) | 10 km | ✓ |
| `~~tachado~~` | ~~tachado~~ | ✓ |
| `[subrayado]{.underline}` | <u>subrayado</u> | ✓ |
| `H~2~O`, `2^10^` (subíndice y exponente en el **texto**; en una fórmula usa `$…$`) | H<sub>2</sub>O, 2<sup>10</sup> | ✓ |
| `<!-- anotación del autor -->` | (no aparece) | ✓ |
| `---` en una línea propia, con una línea en blanco antes | línea horizontal | ✓ |
| línea terminada en `\` (salto de línea forzado) | corta la línea | ⚠ la línea antes del salto sale estirada (el PDF está justificado); prefiere párrafos separados o una lista |
| nota al pie: `texto[^1]` y, después, `[^1]: la nota` | nota al final | ⚠ **el texto de la nota desaparece en el PDF**; escribe la observación en el propio texto o en una sección `## Notas` |

## 3. Imágenes

### Agregar

Pon el archivo en `docs/`, junto al `enunciado.md`, y cítalo por el nombre:

```markdown
![Mapa de las ciudades](mapa.png)
```

(o pega/arrastra la imagen en el editor web: queda incrustada en el texto). Nombres simples (letras,
dígitos, `.`, `_`, `-`), formatos png, jpg, jpeg, gif, svg o webp, hasta 2 MB. Detalles en
[PACOTE](PACOTE.md).

Lo que pones entre los corchetes decide lo que sale:

| Escribes | Resultado |
|---|---|
| `![Mapa de las ciudades](mapa.png)` sola en el párrafo | **figura**: la imagen y, debajo, la leyenda "Mapa de las ciudades" (en cursiva en el PDF) |
| `![](mapa.png)` sola en el párrafo | la imagen, sin leyenda |
| `… el símbolo ![](seta.png) indica …` en medio de la oración | la imagen dentro de la línea; solo para íconos pequeños |

### Tamaño

Si no indicas nada, la imagen sale en su tamaño natural, sin pasar del ancho del texto (en el sitio) ni
de la página (en el PDF). Para elegirlo, da el ancho **en %** del ancho del texto:

```markdown
![Mapa de las ciudades](mapa.png){width=50%}
```

Vale en el sitio y en el PDF, y la altura acompaña (se mantiene la proporción).

### Centrar

Por defecto, la imagen (y la figura) queda a la **izquierda**. Para centrarla, ponla dentro de un
bloque `::: center`, con una línea en blanco antes:

```markdown
La red queda así:

::: center
![Mapa de las ciudades](mapa.png){width=60%}
:::
```

Vale en el sitio (la página del problema, la competencia, la pestaña HTML y la 👁 Vista previa del editor)
y en el PDF, con la leyenda centrada junto a la imagen. Dentro del bloque puede ir más de una imagen, y
también texto. (El `moj preview` de la línea de comandos todavía muestra el bloque a la izquierda.)

| No funciona | Por qué |
|---|---|
| `![Mapa](mapa.png){.center}` | una clase en la **imagen** no la centra (el `.center` es para el bloque) |
| `<center>…</center>` o `<div style="text-align:center">…</div>` | HTML crudo: centra en el sitio, pero **no en el PDF** |

### Grafo

Para un grafo dibujado a partir de DOT, en lugar de una imagen pegada: `mojtools/docs/enunciado-grafos.md`.

## 4. Fórmulas: las reglas

- **En línea**: `$...$`. **Destacada** (centrada, en su propio párrafo): `$$...$$`.
- **No pongas espacios pegados al `$`**: `$ x $` **no** es una fórmula (sale el texto `$ x $`). Escribe `$x$`.
- **Toda** variable, número de restricción y expresión va en una fórmula: `$N$`, `$10^5$`,
  `$1 \le N \le 10^5$`; no `N`, `10^5` ni `1 ≤ N ≤ 10⁵` escritos como texto.
  En el sitio se ve igual, pero en el **PDF** el `≤` y el `⁵` escritos en el texto salen en otra fuente
  (la del cuerpo no tiene esos caracteres).
- **Signo de dólar de verdad** en el texto: `R\$`.
- Las **macros** funcionan: `\newcommand{\abs}[1]{\left|#1\right|}` en un párrafo propio, y después
  `$\abs{x}$`.

## 5. Fórmulas: la guía rápida

Cada fila: lo que escribes, cómo sale en el sitio y cómo sale en el PDF del cuadernillo.

### Subíndices, potencias y restricciones

| Escribes | Resultado | PDF |
|---|---|---|
| `$a_i$`, `$a_{i,j}$`, `$x_i^2$` | $a_i$, $a_{i,j}$, $x_i^2$ | ✓ |
| `$x^2$`, `$2^{n+1}$`, `$10^{18}$` | $x^2$, $2^{n+1}$, $10^{18}$ | ✓ |
| `$1 \le N \le 2 \cdot 10^5$` | $1 \le N \le 2 \cdot 10^5$ | ✓ |
| `$0 \le a_i < 2^{63}$` | $0 \le a_i < 2^{63}$ | ✓ |
| `$a \ne b$`, `$a \ge b$`, `$a \approx b$` | $a \ne b$, $a \ge b$, $a \approx b$ | ✓ |
| `$10^9 + 7$` | $10^9 + 7$ | ✓ |
| valores `$\le 10^9$` (relación sin el lado izquierdo) | valores $\le 10^9$ | ✓ |

### Fracciones, raíces, sumatorias

| Escribes | Resultado | PDF |
|---|---|---|
| `$\frac{a}{b}$` | $\frac{a}{b}$ | ✓ |
| `$\dfrac{a}{b}$` (más grande, en la línea) | $\dfrac{a}{b}$ | ✓ |
| `$\sqrt{x}$`, `$\sqrt[3]{x}$` | $\sqrt{x}$, $\sqrt[3]{x}$ | ✓ |
| `$\sum_{i=1}^{n} a_i$`, `$\prod_{i=1}^{n} a_i$` | $\sum_{i=1}^{n} a_i$, $\prod_{i=1}^{n} a_i$ | ✓ |
| `$\max_{1 \le i \le n} a_i$`, `$\min(a, b)$` | $\max_{1 \le i \le n} a_i$, $\min(a, b)$ | ✓ |
| `$\binom{n}{k}$` | $\binom{n}{k}$ | ✓ |

### Funciones, complejidad, aritmética

| Escribes | Resultado | PDF |
|---|---|---|
| `$\log n$`, `$\log_2 n$`, `$\ln x$` | $\log n$, $\log_2 n$, $\ln x$ | ✓ |
| `$\gcd(a, b)$`, `$\operatorname{lcm}(a, b)$` | $\gcd(a, b)$, $\operatorname{lcm}(a, b)$ | ✓ |
| `$O(n \log n)$`, `$O(n^2)$`, `$\mathcal{O}(1)$` | $O(n \log n)$, $O(n^2)$, $\mathcal{O}(1)$ | ✓ |
| `$a \bmod m$`, `$a \equiv b \pmod{m}$` | $a \bmod m$, $a \equiv b \pmod{m}$ | ✓ |
| `$\lfloor n / 2 \rfloor$`, `$\lceil n / k \rceil$` | $\lfloor n / 2 \rfloor$, $\lceil n / k \rceil$ | ✓ |
| `$a \times b$`, `$a \cdot b$`, `$a \pm b$` | $a \times b$, $a \cdot b$, $a \pm b$ | ✓ |
| `$n!$`, `$-x$` | $n!$, $-x$ | ✓ |
| `$\infty$` | $\infty$ | ✓ |

### Conjuntos, lógica, flechas, griego

| Escribes | Resultado | PDF |
|---|---|---|
| `$\{1, 2, \ldots, n\}$` | $\{1, 2, \ldots, n\}$ | ✓ |
| `$a_1, \dots, a_n$`, `$a_1 + \cdots + a_n$` | $a_1, \dots, a_n$, $a_1 + \cdots + a_n$ | ✓ |
| `$x \in S$`, `$x \notin S$`, `$A \subseteq B$` | $x \in S$, $x \notin S$, $A \subseteq B$ | ✓ |
| `$A \cup B$`, `$A \cap B$`, `$\emptyset$` | $A \cup B$, $A \cap B$, $\emptyset$ | ✓ |
| `$\mathbb{Z}$`, `$\mathbb{N}$`, `$\mathbb{R}$` | $\mathbb{Z}$, $\mathbb{N}$, $\mathbb{R}$ | ✓ |
| `$\{x \in S \mid x > 0\}$` (usa `\mid`, no `\|`) | $\{x \in S \mid x > 0\}$ | ✓ |
| `$a \land b$`, `$a \lor b$`, `$\neg a$`, `$a \oplus b$` | $a \land b$, $a \lor b$, $\neg a$, $a \oplus b$ | ✓ |
| `$\forall x$`, `$\exists y$` | $\forall x$, $\exists y$ | ✓ |
| `$a \to b$`, `$a \Rightarrow b$`, `$a \iff b$` | $a \to b$, $a \Rightarrow b$, $a \iff b$ | ✓ |
| `$\alpha$`, `$\beta$`, `$\pi$`, `$\varepsilon$`, `$\Delta$`, `$\Sigma$` | $\alpha$, $\beta$, $\pi$, $\varepsilon$, $\Delta$, $\Sigma$ | ✓ |

### Texto y espacio dentro de la fórmula

| Escribes | Resultado | PDF |
|---|---|---|
| `$\text{si } x > 0$` (texto normal dentro de la fórmula) | $\text{si } x > 0$ | ✓ |
| `$a\,b$` (espacio fino), `$a \quad b$` (espacio ancho) | $a\,b$, $a \quad b$ | ✓ |
| `$\mathbf{v}$`, `$\mathrm{d}x$` | $\mathbf{v}$, $\mathrm{d}x$ | ✓ |
| `$\texttt{abc}$` | $\texttt{abc}$ | ⚠ otra fuente monoespaciada; para cadenas, prefiere `` `abc` `` fuera de la fórmula |
| `$50\%$`, `$a \# b$`, `$a \& b$` | $50\%$, $a \# b$, $a \& b$ | ✓ |

### Dónde difiere el PDF

| Escribes | Resultado | PDF |
|---|---|---|
| `$\bar{x}$`, `$\hat{x}$`, `$\vec{v}$`, `$\tilde{x}$`, `$\dot{x}$` | $\bar{x}$, $\hat{x}$, $\vec{v}$, $\tilde{x}$, $\dot{x}$ | ⚠ el acento sale suelto, alto y pequeño |
| `$\overline{AB}$`, `$\underline{x}$` | $\overline{AB}$, $\underline{x}$ | ⚠ ídem |
| `$f'(x)$`, `$f''(x)$` | $f'(x)$, $f''(x)$ | ⚠ la prima (′) sale pequeña y separada de la letra |

Con acento, si el PDF importa, prefiere otro nombre (`$m$` para la media en lugar de `$\bar{x}$`,
`$g$` en lugar de `$f'$`). En el sitio todo sale bien.

## 6. Paréntesis, corchetes y barras

Escribe como en TeX; el tamaño se resuelve solo:

- Los **paréntesis y corchetes comunes** quedan del tamaño del texto: `$(x_1, y_1)$` → $(x_1, y_1)$,
  `$[l, r]$` → $[l, r]$.
- **Crecen con el contenido**: `\left( … \right)` alrededor de una fracción, una sumatoria, una matriz:
  `$\left( \frac{a}{b} \right)^2$` → $\left( \frac{a}{b} \right)^2$.
- El **intervalo semiabierto** funciona: `$[l, r)$` → $[l, r)$, `$(a, b]$` → $(a, b]$.
- Las **llaves** necesitan barra: `$\{1, 2\}$` → $\{1, 2\}$ (sin la barra, `{` solo agrupa).
- **Valor absoluto**: `$|x|$` → $|x|$ (o `$\lvert x \rvert$`). **Norma**: `$\|v\|$` → $\|v\|$.
- **Divide / "tal que" / probabilidad condicional**: `$a \mid b$` → $a \mid b$,
  `$a \nmid b$` → $a \nmid b$, `$P(A \mid B)$` → $P(A \mid B)$.
- **Ángulo**: `$\langle a, b \rangle$` → $\langle a, b \rangle$.

## 7. Estructuras: casos, matrices, alineación

Definición por casos:

```markdown
$$f(n) = \begin{cases} 1 & \text{si } n = 0 \\ 2 f(n-1) & \text{si } n > 0 \end{cases}$$
```

$$f(n) = \begin{cases} 1 & \text{si } n = 0 \\ 2 f(n-1) & \text{si } n > 0 \end{cases}$$

Matriz (`pmatrix` entre paréntesis, `bmatrix` entre corchetes, `vmatrix` entre barras):

```markdown
$$A = \begin{pmatrix} a & b \\ c & d \end{pmatrix}, \qquad \det A = \begin{vmatrix} a & b \\ c & d \end{vmatrix}$$
```

$$A = \begin{pmatrix} a & b \\ c & d \end{pmatrix}, \qquad \det A = \begin{vmatrix} a & b \\ c & d \end{vmatrix}$$

Cuentas alineadas en el `=` (`&` marca el punto de alineación, `\\` corta la línea):

```markdown
$$\begin{aligned} S &= a_1 + a_2 + \cdots + a_n \\ &= \frac{n(n+1)}{2} \end{aligned}$$
```

$$\begin{aligned} S &= a_1 + a_2 + \cdots + a_n \\ &= \frac{n(n+1)}{2} \end{aligned}$$

Todas salen bien en el PDF (✓).

## 8. Qué evitar

| Evita | Por qué | Escribe |
|---|---|---|
| `1 ≤ N ≤ 10⁵` escrito como texto | en el PDF sale en otra fuente | `$1 \le N \le 10^5$` |
| `\textbf{…}`, `\emph{…}`, `\section{…}`, `\begin{itemize}` | es LaTeX de texto, no Markdown: el texto **desaparece**, sin aviso, en el sitio y en el PDF | `**…**`, `*…*`, `## …`, `- item` |
| `$ x $` | con espacio pegado al `$` no es una fórmula | `$x$` |
| un ejemplo copiado en el texto | aparece duplicado (los ejemplos vienen de `tests/`) | `tests/input/sample1` + `docs/notes/sample1.md` |
| `$\bar{x}$`, `$f'$` cuando el PDF importa | ver la tabla "Dónde difiere el PDF" | otro nombre |
| `{…}` para mostrar llaves | `{` solo agrupa en TeX | `\{…\}` |
| `<center>`, `<div style=…>` para centrar | en el PDF no centra | `::: center` (sección 3) |
| nota al pie (`[^1]`) | en el PDF el texto de la nota desaparece | la observación en el texto o en `## Notas` |

## 9. Un enunciado completo

```markdown
Una tienda registra el precio $p_i$ de cada uno de los $N$ días de una temporada. Para un intervalo de
días $[l, r)$ —del día $l$ al día $r - 1$—, la *ganancia* es
$$L(l, r) = \max_{l \le i < r} p_i - \min_{l \le i < r} p_i.$$

Dadas $Q$ consultas, responde la ganancia de cada intervalo. Si $r - l < 2$, la ganancia es $0$.

## Entrada

La primera línea contiene dos enteros $N$ y $Q$ ($1 \le N, Q \le 2 \cdot 10^5$). La segunda línea
contiene $N$ enteros $p_1, p_2, \ldots, p_N$ ($1 \le p_i \le 10^9$). Cada una de las $Q$ líneas
siguientes contiene dos enteros $l$ y $r$ ($1 \le l < r \le N + 1$).

## Salida

Para cada consulta, imprime una línea con $L(l, r)$.

## Subtareas

| Subtarea | Puntos | Restricciones                 |
|:--------:|:------:|-------------------------------|
| 1        | 30     | $N, Q \le 1000$               |
| 2        | 70     | sin restricciones adicionales |
```

## 10. Cómo verificar

- **Sitio**: el botón **👁 Vista previa** del editor, o `moj preview` en la CLI (el mismo renderizador
  del HTML que lee el estudiante).
- **PDF**: el cuadernillo lo genera el administrador o el juez principal de la competencia en
  **Evento › Documentos**. Pide la generación y revisa las fórmulas antes de publicar.

---

*Para quien mantiene el MOJ*: el PDF del cuadernillo sale por `pandoc -f html -t odt` → `soffice`.
LibreOffice no dibuja el MathML: lo traduce a StarMath y lee ese texto. El
`server/api/v1/lib/odt-math-bars.py` corrige el MathML a mitad de camino (tamaño y fuente de la
fórmula, delimitadores, caracteres de sintaxis, relación sin operando; y el tamaño de las imágenes); el
`server/api/v1/lib/odt-center.lua` centra el bloque `::: center` (estilo `Center` del
`server/etc/caderno-reference.odt`). La columna **PDF** de esta página
se midió con pandoc 3.1.11 y LibreOffice 25.2 (las versiones de la imagen); las pruebas que la
respaldan son `server/test/smoke-odt-math-bars.sh` y `server/test/render-docs.sh`.
