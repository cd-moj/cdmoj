<!-- i18n-source: PACOTE.md blob:b127fe25431890265401233fca60c7cb66b68826 -->
# MOJ: el paquete de problema (formato canónico)

> **Nota de traducción.** Este manual es una traducción del original en portugués. Las herramientas de línea de comandos (`moj`, `moj-contest`, `moj-comp`) muestran sus mensajes en portugués, y los ejemplos de comandos son idénticos al original.

Este documento es la **fuente única** del formato del paquete de problema del MOJ. Explica qué es un
paquete, qué hace cada archivo dentro de él, qué son los metadatos (`.moj-meta.json` y `.moj-id`),
qué son las **orgs** y las **colecciones**, y cómo un problema sale de borrador y llega al estudiante.

> Si vas a armar un paquete en la práctica (paso a paso, con los comandos), lee el `README.md` de
> **mojtools**, que tiene la guía. Aquí está la **referencia**: qué es cada cosa y por qué.
> Las rutas de la API que leen y escriben el paquete están en [API.md](API.md).

> ⚠ **El paquete no es fuente de lectura para las rutas de competencia ni de entrenamiento.** Quien sirve una
> competencia o el entrenamiento usa lo que ya está materializado — índice de dueños, `var/jsons{,-private}/<id>.json`,
> `run/tl/` — y nunca abre el árbol de paquetes. Quien necesita un dato que solo existe aquí dentro
> lo materializa antes. La frontera, los motivos y el inventario de lo que aún falta:
> `cdmoj/CLAUDE.md` y `bash server/test/sem-pacote.sh`.

> **Documentación atrasada = bug.** ¿Cambió el paquete (archivo nuevo, campo nuevo, estructura, de dónde viene el título)?
> Actualiza **este** documento en el mismo commit. Los otros lugares (el `CLAUDE.md` de `cdmoj`, de
> `mojtools` y de `moj-cli`) apuntan aquí en vez de repetir el formato.

## Índice

1. [Qué es un paquete](#1-qué-es-un-paquete)
2. [Dónde viven los paquetes](#2-dónde-viven-los-paquetes)
3. [Estructura canónica](#3-estructura-canónica)
4. [Archivo por archivo](#4-archivo-por-archivo)
5. [`.moj-meta.json`: los metadatos del problema](#5-moj-metajson-los-metadatos-del-problema)
6. [`.moj-id`: el puntero local de la CLI](#6-moj-id-el-puntero-local-de-la-cli)
7. [ORG: quién puede modificar](#7-org-quién-puede-modificar)
8. [COLECCIÓN: cómo se agrupan los problemas](#8-colección-cómo-se-agrupan-los-problemas)
9. [ORG x COLECCIÓN](#9-org-x-colección)
10. [Ciclo de vida de un problema](#10-ciclo-de-vida-de-un-problema)
11. [Preguntas frecuentes](#11-preguntas-frecuentes)

---

## 1. Qué es un paquete

Un **paquete** es un directorio que describe un problema por completo: el enunciado, las pruebas, las
soluciones de referencia y los límites de ejecución. No existe una base de datos de problemas: el paquete
**es** el problema.

Conviene saber tres cosas desde ya:

- **Cada paquete es un repositorio git propio**, local, dentro del servidor. No hay Gitea, ni
  servicio externo, ni clave de acceso. Cuando alguien guarda desde el editor web o con `moj push`, el
  servidor escribe los archivos y hace el commit ahí mismo (función `problem_commit`, en
  `server/api/v1/lib/problems.sh`, con bloqueo por problema).
- **El identificador de un problema es `<org>#<prob>`**, por ejemplo `apc#fatorial`. La parte antes del
  `#` es la **org** (sección 7); la parte después es el nombre del directorio del paquete.
- **El autor casi nunca edita el paquete a mano.** Usa el editor web o la CLI (`moj`), y las dos
  hablan con la misma API. Este documento describe lo que esas herramientas escriben, para que
  entiendas lo que está pasando y puedas verificarlo.

## 2. Dónde viven los paquetes

```
moj-problems/<org>/<prob>/        # el paquete (raíz del repo git local de ese problema)
```

La raíz `moj-problems/` se configura con la variable `MOJ_PROBLEMS_DIR`. En el checkout de
desarrollo queda al lado de `cdmoj/`.

Un paquete **no** contiene el marcador, el historial de envíos ni los tiempos límite calibrados. Todo
eso vive fuera de él:

| Cosa | Dónde queda | Quién lo escribe |
|---|---|---|
| Tiempos límite calibrados | `run/tl/<id>.json` | los jueces, al calibrar |
| Informe de validación | `run/validation/<id>.json` | `validate-problem.sh` |
| Índice servido al estudiante | `contests/treino/var/jsons/<id>.json` | `gen-problem-json.sh` |
| Registro de orgs | `contests/treino/var/orgs.json` | la API (`lib/orgs.sh`) |
| Registro de colecciones | `contests/treino/var/collections.json` | la API (`lib/problems.sh`) |

## 3. Estructura canónica

Árbol de un paquete completo. La columna de la derecha muestra en cuántos de los 453 paquetes del acervo actual
aparece cada elemento, para dar una idea de qué es rutina y qué es excepción.

```
moj-problems/<org>/<prob>/
├── .git/                     repo git local del problema                    453  (siempre)
├── .moj-meta.json            metadatos (título, público, colecciones, …)     453  (siempre)
├── author                    autor(es) del problema                         453  (obligatorio)
├── tags                      temas, una tag por línea                       453
├── conf                      límites y ajustes de ejecución                 453
├── docs/
│   ├── enunciado.md          el enunciado en portugués (también .org y .tex) 453  (obligatorio)
│   ├── enunciado.en.md       el enunciado en inglés (ídem enunciado.es.md)  opcional
│   ├── notes/sample1.md      explicación de cada ejemplo (markdown; 1/sample) opcional
│   ├── notes/sample1.en.md   la explicación traducida (si falta, usa la PT)   opcional
│   ├── <figura>.png          imágenes del enunciado/notas (el render las incrusta) opcional
│   ├── solucao.md            editorial, solo para el autor                  opcional
│   └── solucao.en.md         el editorial traducido (ídem solucao.es.md)    opcional
├── tests/
│   ├── input/sample1         ejemplo (aparece en el enunciado)              obligatorio, >= 1
│   ├── output/sample1        respuesta del ejemplo
│   ├── input/<nome>          prueba oculta (corrige el envío)
│   ├── output/<nome>         respuesta de la prueba oculta
│   └── score                 grupos de puntuación (subtareas)               254  (opcional)
├── sols/
│   ├── good/                 soluciones correctas                           453  (obligatorio, >= 1)
│   ├── wrong/                soluciones incorrectas a propósito               18  (opcional)
│   ├── slow/                 soluciones lentas a propósito                     7  (opcional)
│   ├── pass/                 soluciones que deben pasar por poco              3  (opcional)
│   └── upcoming/             soluciones en borrador                            1  (opcional)
└── scripts/                  corrección especial                             79  (opcional)
    ├── compare.sh            comparador propio (checker)                     18
    ├── validator.cpp         validador de ENTRADA (testlib)                  opcional
    └── <lang>/compile.sh     compilación propia (envío de función)          201
```

Dos archivos aparecen en el acervo pero **no** forman parte del formato:

- `problem.yaml` y `.kattis.json` (en 395 paquetes) son metadatos del formato **Kattis**, escritos
  por el importador/exportador (`mojtools/kattis/`). El MOJ los ignora por completo.
- `.moj-id` (en 336 paquetes) es un archivo del **cliente**, no del paquete. Terminó ahí por
  descuido de migraciones antiguas. Ver la sección 6.

## 4. Archivo por archivo

### `docs/enunciado.md`

El texto del problema. Acepta tres formatos, buscados en este orden: `enunciado.md`, `enunciado.org`,
`enunciado.tex`. El `.md` es el canónico y el recomendado.

**Cómo escribir el texto** — Markdown, fórmulas en TeX, paréntesis, casos, matrices, qué evitar y
cómo sale cada construcción en el PDF del cuadernillo, con ejemplos: **[ENUNCIADO](ENUNCIADO.md)**.

Tres reglas que exige el filtro de calidad:

1. **Las secciones `## Entrada` y `## Saída` son obligatorias.** Sin ellas el problema no pasa la
   validación. (El validador también acepta `## Input`, `## Output` y `## Salida`, y de uno a tres `#`.)
2. **El título no va en el texto.** Una primera línea `% Título do problema` es **legado**: el
   renderizador la quita. El título verdadero es el campo `display_title` del `.moj-meta.json`
   (sección 5), y el renderizador inyecta un `<h1>` a partir de él.
3. **Los ejemplos no van en el texto.** Se arman a partir de `tests/input/sample*` y
   `tests/output/sample*` y se inyectan al final del HTML. Si escribes un ejemplo a mano dentro del
   enunciado, aparecerá duplicado. (La validación avisa, pero no bloquea.) La excepción es el
   problema **sin ejemplo** (`SAMPLE=no` en el `conf`, sección 4, "Problema sin ejemplo"): en él el
   ejemplo va en el texto, en una sección `## Exemplo`, y la validación no avisa.

**Imágenes — dos formas, ambas se convierten en HTML autocontenido** (el renderizador corre con
`--embed-resources` e incrusta todo en base64):

1. **Pegar/arrastrar en el editor web**: la imagen se convierte en `data:URI` DENTRO del texto del enunciado —
   no existe un archivo aparte; viaja con el markdown por cualquier vía.
2. **Archivo en `docs/`** + `![](figura.png)` en el texto: la figura queda editable como archivo.
   Viaja en `moj push`/`clone` (campo `docs_files`, el análogo de `scripts_files`; tope de 2MB por
   imagen), en `moj upload` (tar) y aparece en la Vista previa (la vista previa recibe las imágenes del
   paquete/locales). Nombres simples (`[A-Za-z0-9._-]`, extensión png/jpg/jpeg/gif/svg/webp).

**Grafos**: un bloque de código con la clase `.graph` (fuente [graphviz DOT](https://graphviz.org/)) se
renderiza como **SVG** — la fuente DOT queda editable en el enunciado; no es una imagen pegada. Ej.:
` ```{ .graph .center caption="…"} graph G { a -- b; } ``` `. Detalles y atributos en
**`mojtools/docs/enunciado-grafos.md`**.

Quien renderiza es **un solo script**: `mojtools/render-statement.sh`. El botón "👁 Vista previa" del
editor, el HTML que lee el estudiante y el HTML que verifica la validación son exactamente el mismo. No existe
un segundo renderizador, y no se debe crear uno.

### `docs/notes/<sample>.md` — la explicación de cada ejemplo

Opcional. **Un archivo Markdown por ejemplo**, con el MISMO nombre de la prueba de ejemplo:
`docs/notes/sample1.md` explica `tests/input/sample1`, y así sucesivamente. Es markdown normal —
párrafos, listas, `código`, e **imágenes** (`![](figura.png)` con la figura en `docs/`, igual que en el
enunciado; el render la incrusta en base64). La nota aparece justo debajo del ejemplo correspondiente.

```
docs/notes/sample1.md      # "En este ejemplo tenemos:\n\n- 4 grupos...\n\n![](mesas.png)"
docs/notes/sample2.md
```

**Nunca editas JSON**: el editor web (campo "explicación" de cada ejemplo), `moj edit`
(opción `[n]ota`) y `moj push`/`clone` leen y escriben esos archivos; la serialización es de la
plataforma. La validación avisa cuando hay una nota sin ejemplo correspondiente.

**Legado**: `docs/sample-notes.json` (arreglo JSON de cadenas, por índice) todavía se LEE en paquetes
antiguos, pero **nunca más se escribe** — cualquier guardado lo convierte a `docs/notes/`.

### `docs/solucao.md`

Opcional. Es el **editorial**: la explicación de la idea de la solución, para el autor y para quien vaya a reusar el
problema. **El estudiante nunca ve este archivo.** `gen-problem-json.sh` lo ignora a propósito. Es el
lugar correcto para escribir "la solución es una DP en O(n log n)" sin miedo. El documento de editorial
de una competencia lee este archivo (o la traducción `solucao.<lang>.md`, abajo).

### Idiomas: `enunciado.<lang>.md`, `notes/<sample>.<lang>.md`, `solucao.<lang>.md`

Un problema puede tener el enunciado en más de un idioma. Las reglas son simples:

| Archivo | Qué es | Si falta |
|---|---|---|
| `docs/enunciado.md` | el enunciado en **portugués**. Es el texto principal y es obligatorio | el problema no valida |
| `docs/enunciado.<lang>.md` | la traducción. `<lang>` es `en` o `es`. Solo markdown | el problema tiene un solo idioma |
| `docs/notes/<sample>.<lang>.md` | la explicación traducida del ejemplo | el ejemplo muestra la explicación en portugués |
| `docs/solucao.<lang>.md` | el editorial traducido | el documento de editorial usa el portugués |
| `titles` en el `.moj-meta.json` | el título de cada traducción (sección 5) | el título en portugués |

⚠ Los nombres de archivo y de directorio (`enunciado`, `solucao`, `notes`) son literales y están en portugués. No los traduzcas.

Los ejemplos vienen de las pruebas y aparecen en todos los idiomas, con las etiquetas del idioma
(`Exemplos`/`Entrada`/`Saída`/`Explicação` · `Examples`/`Input`/`Output`/`Explanation` ·
`Ejemplos`/`Entrada`/`Salida`/`Explicación`). Las figuras quedan en `docs/` y sirven para todos los idiomas.

La validación trata cada traducción como al portugués: tiene que renderizar y tiene que tener las secciones de
entrada y de salida (`## Input`/`## Output`, `## Entrada`/`## Salida`). Una traducción sin la
explicación de un ejemplo genera el aviso `nota-sem-traducao(<sample>,<lang>)`. El aviso no bloquea.

El índice del entrenamiento (`var/jsons/<id>.json`) lleva `statement_langs` (la lista, portugués primero) y
`statements{<lang>:{title,html_b64}}`. El portugués sigue en `title` y `statement_html_b64`,
como siempre. La página del problema muestra un chip por idioma. En una competencia, el admin o el
juez principal elige los idiomas que ofrece el acordeón (`STATEMENT_LANGS`; ver `API.md`).

Un ejemplo de más de **256 KB** entra truncado en el HTML del enunciado (solo el comienzo, con el aviso
"Ejemplo grande"); con más de **4 MB** no va como dato (`{name, size, too_big:true}`). Un ejemplo es
para leer: una prueba grande es una prueba oculta.

El índice también lleva **`samples`**: `[{name, input, output}]`, el texto de los ejemplos. La selección es la
MISMA del HTML del enunciado (`stmt_sample_names` en `mojtools/statement-langs.sh`: los
`tests/input/sample*`, o ninguno con `SAMPLE=no`). Una prueba oculta nunca entra en ese campo. Es lo que alimenta el botón
**⬇ Ejemplos** y `moj-comp samples`/`fetch`, por la ruta `/treino/problem` y por `/contest/samples`.

En la API de autoría, las traducciones viajan en el campo `translations` de `/problems/source` y
`/problems/edit`: `{"<lang>": {title, enunciado_md, editorial_md, notes:{"<sample>": md}}}`.
Un idioma ausente del objeto queda como está. Un idioma con valor `null` se borra por completo. La CLI
(`moj clone`/`push`) y el editor web usan ese campo; tú solo editas los archivos.

No confundas esto con la mecánica de la corrección especial, que es asunto de `scripts/` y está documentada en
`mojtools/docs/correcao-especial.md`.

### `tests/input/` y `tests/output/`

Todo archivo en `tests/input/` necesita un archivo del **mismo nombre** en `tests/output/`. Esto se
verifica en la validación, en los dos sentidos (input sin output y output sin input reprueban).

El nombre del archivo decide el rol de la prueba:

| Nombre | Rol |
|---|---|
| `sample1`, `sample2`, … | **ejemplo**: aparece en el enunciado, y también corrige |
| cualquier otro nombre | **prueba oculta**: solo corrige; el estudiante nunca la ve |

Los ejemplos son todos los archivos que empiezan con `sample`, ordenados por `ls -1v` (o sea,
`sample2` viene antes de `sample10`, y no después). El prefijo `sample` es literal: no lo traduzcas. La validación exige **al menos un ejemplo**, o la
declaración de que el problema no tiene ejemplo (`SAMPLE=no`, abajo). **Una prueba oculta nunca aparece
como ejemplo**, ni siquiera cuando falta `sample*`.

#### Problema sin ejemplo: `SAMPLE=no`

En algunos problemas, la entrada y la salida de ejemplo no tienen sentido para el estudiante:

- **envío de función**: la entrada de la prueba es el formato interno del driver, que el estudiante no lee;
- **problema interactivo**: la entrada es el escenario secreto del árbitro, y la salida es solo una marca;
- **lenguaje propio** (PDDL, SAS, gramáticas): el "ejemplo" no es un par entrada/salida;
- cualquier otro caso en que el ejemplo se explique mejor en texto o figura.

En esos problemas:

1. No crees `tests/input/sample*`.
2. Pon la línea `SAMPLE=no` en el `conf`. En el editor web, es la opción **este problema no tiene
   ejemplos** de la pestaña **Límites**. En la CLI, `moj edit` → 8 (conf) → 6. `moj interactive` ya escribe la
   línea.
3. Explica el ejemplo en el texto del enunciado, en una sección `## Exemplo`: una figura, una llamada de la
   función y lo que devuelve, la transcripción de la conversación con el árbitro.

El efecto de `SAMPLE=no`:

- el enunciado no muestra el recuadro de ejemplos;
- el campo `samples` del índice queda vacío: no hay botón **⬇ Ejemplos** en el entrenamiento, ni enlace
  **Ejemplos** en la competencia (`has_samples:false` en `/contest/problems`), y `moj-comp samples` no
  descarga nada. Vale aunque existan archivos `sample*`: siguen corrigiendo, como cualquier
  prueba, pero ninguno de ellos se convierte en ejemplo;
- la línea `SAMPLE` **no** entra en el tl-checksum: marcarla o desmarcarla no pide recalibración.

Valores aceptados: `no`, `n`, `nao`, `não`, `false`, `0` (con o sin comillas). Sin la línea, el problema
tiene ejemplos (`tests/input/sample*`). Hasta 2026-09-23 existían dos legados que se eliminaron: el archivo
`samples` en la raíz del paquete (vacío = sin ejemplos) y el fallback que mostraba las dos primeras pruebas
cuando faltaba `sample*` — en un problema de función mostraba el formato interno del driver.

El nombre de las pruebas ocultas es libre. Las convenciones que aparecen en el acervo son `test-001`, `test-002`
(estilo APC) y `<prob>_1_1`, `<prob>_1_2` (estilo OBI, que agrupa por subtarea; ver `tests/score`).

### `tests/score`

Opcional. Activa la **puntuación por grupos** (subtareas). Sin este archivo, la nota del problema es el
porcentaje de pruebas que pasaron.

El formato es texto plano, una línea por grupo:

```
sample* - 0 pontos
2015f2p1_capitais_1_*, 2015f2p1_capitais_2_* - 40 pontos
2015f2p1_capitais_3_*, 2015f2p1_capitais_4_*, 2015f2p1_capitais_5_* - 60 pontos
```

Escribe la palabra `pontos` en portugués, exactamente así. Es la forma canónica del formato. El analizador solo lee el número, pero las demás herramientas y la documentación usan `pontos`.

Cómo leer la línea: uno o más **globs** de nombre de prueba, después ` - `, después el **peso** del grupo.

Reglas:

- El grupo es **todo o nada**: basta con que falle una prueba del grupo para que el grupo valga 0.
- El valor total del problema es la **suma de los pesos**. Nada obliga a sumar 100 (se puede pasar de eso).
- El separador entre globs es **coma y espacio** (`", "`). No es estética: es lo que el parser
  espera en los dos lados (API y juez).
- Los ejemplos suelen entrar con peso 0, para que aparezcan en el informe sin valer nota.
- Una línea que empieza con `#` es **comentario**. Cualquier otra línea que no sea
  `<globs> - <N> pontos` se **ignora con aviso** en el registro del juez — no se convierte en grupo.
- La correspondencia prueba→grupo es por **glob de verdad** (`aula_*` coincide con `aula_2_1`), y **toda prueba
  necesita caer en un grupo**. `validate-problem.sh` verifica todo esto en el upload (check
  `score_file_sane`): una prueba sin grupo, o un grupo de peso>0 sin ninguna prueba, es un paquete roto —
  si aun así llega al juez, el envío sale **Judge Error** con nota 0 (error del paquete, no
  del estudiante). Un grupo de **peso 0** sin prueba (ej.: `sample* - 0 pontos` en un problema `SAMPLE=no`) se
  acepta y no rompe nada.

**El veredicto es el de la peor prueba; los grupos deciden solo la nota.** Un grupo que cayó por exceder el
tiempo sale **Time Limit Exceeded** con la nota de los grupos que pasaron (y no "respuesta incorrecta"): es el
mismo veredicto que darían las pruebas sin grupos. La cadena que devuelve el juez (y que guarda el historial)
es `<veredicto canônico>,<pontos>p. Pontos | <por grupo> | [quantitativos <código>(<n>) …]`
(`<veredicto canônico>` = veredicto canónico, `<pontos>` = puntos, `<por grupo>` = puntos por grupo,
`<código>(<n>)` = código de veredicto y número de pruebas; `Pontos` y `quantitativos` son palabras literales):

```
Accepted,100p. Pontos | 30 | 70 |
Time Limit Exceeded,30p. Pontos | 30 | 0 | quantitativos TLE(2) AC(8)
Judge Error,0p. teste 'extra1' sem grupo em tests/score (erro do pacote)
```

Lo que lee el estudiante es el prefijo (el servidor lo canoniza en la lectura) y la nota es el primer `NNp` de la
cadena. Hasta el 24/09/2026 toda falla de grupo salía `Wrong,<n>p` — un TLE le llegaba al estudiante como "Wrong
Answer". El historial registrado antes de eso queda como está (`Wrong,…` y el legado `Wrong. Pontos | …`
se siguen leyendo como Wrong Answer); al volver a evaluar, aparece el veredicto real.

Quien lo interpreta es `mojtools/score-summary.sh`, en el juez. Editar `tests/score` (o un
`tests/output/*`) cambia el checksum del paquete — el juez vuelve a descargar y recalibra solo.

### `sols/`

Las soluciones de referencia, separadas por categoría. **La extensión del archivo es lo que define el
lenguaje** (`sol.c` es C, `sol.cpp` es C++, `Main.java` es Java, y así sucesivamente). C++ acepta
cuatro extensiones: `.cpp`, `.cc`, `.cxx` y `.c++`. El juez trata las cuatro como `cpp`.

| Directorio | Qué es | Qué le exige la calibración |
|---|---|---|
| `good/` | soluciones **correctas** | **obligatorio, al menos una.** Aceptada en todas las pruebas, dentro del tiempo límite **efectivo** (el que aplica el juez, con `TLOVERRIDE`). Es la que usa la calibración para medir el tiempo límite |
| `wrong/` | soluciones **incorrectas** a propósito | **reprobada**, de preferencia por respuesta incorrecta (WA): demuestra que las pruebas detectan el error |
| `slow/` | soluciones **lentas** a propósito | **TLE** en al menos 1 prueba y aceptada en las otras: demuestra que el tiempo límite reprueba la solución mala |
| `pass/` | soluciones que deben pasar **por poco** | aceptada en todas las pruebas, dentro del tiempo límite efectivo: demuestra que el límite no es demasiado ajustado |
| `upcoming/` | borradores | no se ejecuta |

La calibración verifica cada solución contra esta tabla (sección 10, "Soluciones") y el resultado aparece en el
editor, en el Panel y en `moj calib`/`moj check`.

En la práctica, pon una `good` en cada lenguaje que quieras que el estudiante pueda usar. El tiempo límite se
calibra **por lenguaje**, y un lenguaje sin solución `good` aceptada simplemente no obtiene
tiempo límite en ese juez (el estudiante no puede usarlo).

**Guardar CUALQUIER solución hace que el juez busque el paquete de nuevo** (es el `pkg_version` de la sección 10),
así que "Guardar" + "Calibrar" ejecuta el `sols/` que acabas de escribir. Solo `good/` afecta el TL.

### `scripts/` (corrección especial)

Opcional. Es como el problema **personaliza** la compilación, la ejecución o la comparación.
`build-and-test.sh` busca los archivos del problema **antes** que los predeterminados de `mojtools/lang/<lang>/`,
así que cualquier cosa que pongas aquí gana sobre el comportamiento normal.

Los usos más comunes:

| Archivo | Uso | Cuántos en el acervo |
|---|---|---|
| `scripts/<lang>/compile.sh` | **envío de función**: el estudiante entrega solo la función, y este script inyecta el `main` que lee la entrada, llama a la función e imprime el resultado. Declara el lenguaje en `FUNCTION_LANGS` en el `conf` (abajo): es lo que hace que el editor del estudiante abra vacío. El mismo archivo también sirve para un **ban** y para flags de OpenMP/MPI, que no son envío de función | 201 |
| `scripts/compare.sh` | **checker**: la respuesta no es única (tolerancia de punto flotante, varias respuestas válidas), así que el problema trae su propio comparador | 18 |
| `scripts/checker.cpp` | la **fuente** del checker cuando es [testlib](https://github.com/MikeMirzayanov/testlib) (estándar Polygon/Maratona). Viene junto con un `compare.sh` de 10 líneas — el **stub** — instalado por `mojtools/testlib/install-checker.sh`. **El `testlib.h` NO va en el paquete** (está vendorizado en mojtools) y el binario del checker **nunca** se incluye en un commit (el *bridge* de mojtools lo compila en el juez, bajo demanda, y lo guarda en caché FUERA de `scripts/`). |
| `scripts/arbitro.{cpp,py,sh}` + `scripts/c/{prep,run}.sh` | **problema interactivo** (`mojtools/interactive/install-interactive.sh`) | — |
| `scripts/validator.cpp` | **validador de ENTRADA** ([testlib](https://github.com/MikeMirzayanov/testlib) `registerValidation`, el estándar de Polygon): verifica si cada `tests/input/*` sigue el formato y los límites del enunciado. **No juzga ninguna solución.** La calibración completa lo ejecuta en el juez (dimensión **Entradas**, sección 10); en tu máquina, `moj validator`. Queda fuera del `tl_checksum` (cambiarlo no recalibra) y dentro de la versión del paquete. Guía: `mojtools/docs/validador-testlib.md` | — |

El contrato del comparador: recibe `$1` = salida del estudiante, `$2` = salida esperada, `$3` = entrada, y
responde con el código de salida (`4` = aceptado, `5` = aceptado con error de formato, `6` = respuesta
incorrecta, cualquier otro = error de juez).

**Stub, no copia.** Lo que corre **en el host del juez** — `scripts/compare.sh`, `scripts/<lang>/prep.sh`,
`scripts/summary.sh` — va en el paquete como un **stub** que llama al driver canónico de mojtools; solo
lo que **entra en la jaula** (`scripts/<lang>/run.sh`, `compile.sh`) es una copia de verdad. Es lo que permite
corregir un bug del driver **en un solo lugar**: cuando cada paquete llevaba su propia copia del *bridge* del
checker, un bug en él nació replicado en 198 paquetes (y tumbaba **todas** las pruebas de quien lo
usara). Un problema puede, claro, cambiar el stub por su propio comparador (es el caso de los 18 del
acervo, todos escritos a mano).

Todo `.sh` en `scripts/` necesita el bit de ejecución (`chmod +x`) — y el bit **viaja** (`moj
push`/`clone` y `upload` lo preservan). Sin él, el juez recibe *Permission denied* al ejecutar el
script: `compare.sh`/`prep.sh` corren **en el host** (fuera de la jaula) y se convierten en **error de juez (UE) en todas
las pruebas**; `run.sh`/`compile.sh` se montan en la jaula y se convierten en Compilation Error.
`validate-problem.sh` reprueba el paquete (`scripts_exec`) antes de que eso pase.

**Modo de los archivos: 644 (o 755 con `+x`), siempre.** El servidor lo normaliza en toda escritura, por los dos
caminos (`moj push` y `moj upload`) — no es el umask del proceso el que decide. Esto importa porque el
`tl-checksum` incluye el **modo** de `scripts/*`: si el mismo contenido entra con un modo diferente según
el camino, el juez ve "el paquete cambió" y **recalibra sin necesidad**.

**Modificar `scripts/` obliga a recalibrar** (sección 10) — excepto `scripts/validator.cpp`, que no
cambia la evaluación.

Los archivos de `scripts/` forman **4 slots independientes que se COMPONEN** — compile
(envío de función/prohibición), run (interactivo), compare (checker/tolerancia), summary (puntuación)
— así que función + checker especial es una combinación normal; solo el interactivo no se mezcla. El
`validator.cpp` no ocupa ningún slot: se compone con todos.
La guía central es `mojtools/docs/correcao-especial.md` (prohibir funciones de la biblioteca, visión general);
las guías largas: `mojtools/docs/submissao-de-funcao.md` (**envío de función** — plantillas
listas vía `moj fn` o desde el editor web, con el centinela anti-IO), `checker-testlib.md` y
`problema-interativo.md`.

### `conf`

Los límites y ajustes de ejecución. **Es un archivo de shell, leído con `source`**, así que nunca
interpoles en él contenido que venga de un usuario.

Un `conf` típico del acervo es corto:

```sh
TLMOD[calibrafactor]=1.35
TLMOD[java.drift]=0.02
TLMOD[spim.sum]=1
ULIMITS[-u]=10000
ALLOWPARALLELTEST=y
```

Todas las claves que entiende `build-and-test.sh`:

> **Tolerancia (drift) en el informe.** Una prueba aceptada con tiempo por encima del límite pasó por la tolerancia.
> El `report.html` muestra ese tiempo en **amarillo**, con cuánto se pasó del límite (`0.98s (+0.16s na tolerância)`).
> Azul es dentro del límite y el color de TLE es exceso. La tabla de pruebas del editor (test-run y
> calibración) usa el mismo amarillo.

| Clave | Default | Qué hace | Uso hoy |
|---|---|---|---|
| `TLMOD[calibrafactor]` | `1.35` | multiplicador aplicado al tiempo de la solución `good` para obtener el tiempo límite. Subirlo le da holgura al estudiante | 453 |
| `TLMOD[<lang>.drift]` | `0` | tolerancia (en segundos) por encima del tiempo límite antes de dar TLE, en ese lenguaje: la prueba solo es TLE cuando `tempo − TL > tolerância` (el tiempo menos el TL es mayor que la tolerancia) | 404 (`java`) |
| `TLMOD[default.drift]` | — | la misma tolerancia para **todo** lenguaje que no tiene la suya (`TLMOD[<lang>.drift]` gana). Vale en la evaluación y en la verificación de las soluciones de la calibración (una `good` dentro de la tolerancia no es "divergente") | 0 |
| `TLMOD[<lang>.sum]` | `0` | suma un valor fijo (en segundos) al tiempo límite de ese lenguaje | 405 (`spim`) |
| `TLMOD[<lang>.mult]` | `1` | multiplica el tiempo límite de ese lenguaje | 0 |
| `ULIMITS[-u]` | `1024` | número máximo de procesos. Java y otros runtimes necesitan más (el acervo usa `10000`) | 453 |
| `ULIMITS[-s]` | `131072` (128 MB, en KB) | tamaño de la pila. Prefiere `STACKLIMITMB` | 0 |
| `ULIMITS[-f]` | `256000` | tamaño máximo de archivo que el programa puede escribir | 0 |
| `ALLOWPARALLELTEST` | activado (ausente = `y`) | `y` = el juez **puede** ejecutar varias pruebas de este envío al mismo tiempo, cada una en sus k CPUs, cuando tiene CPU ociosa (política del admin; en una competencia queda desactivada); `n` = una prueba a la vez. **No cambia el tiempo límite**: la calibración es siempre una prueba a la vez. Ver "Problemas paralelos" abajo | 453 |
| `STACKLIMITMB` | 128 | pila en MB. Gana sobre `ULIMITS[-s]`. La JVM lo refleja en `-Xss` | 0 |
| `MEMLIMITMB` | sin límite por RSS | límite de memoria en MB, medido por el **pico de RSS**. Activarlo desactiva el límite de memoria virtual (que penalizaría injustamente a la JVM y a Go). La JVM usa este valor en `-Xmx`. La unidad es **MB**: 256 MB es `256`, no `262144`. Por encima de lo que soporta un slot de juez (hoy unos 9 GB), cada prueba ocupa más slots y el envío espera más; por encima de la memoria de cualquier juez, el problema no se puede juzgar (Judge Error) — el Panel y la pestaña Límites del editor avisan | 0 |
| `COMPILEMEMLIMIT` | `2048` | memoria en MB liberada para la **compilación** (`kotlinc` pasa de 600 MB) | 0 |
| `MAXPARALLELTESTS` | tope del juez (4) | tope de pruebas al mismo tiempo de este problema (entero ≥ 1); nunca pasa del tope del juez (`parallel_max`, default 4) ni de `nproc/k` al ejecutar a mano | 0 |
| `CPUNEEDED` | `1` | **CPUs que necesita cada prueba** (1..64; problema paralelo — OpenMP/MPI/pthreads). El juez junta k slots para cada prueba y la jaula entra con `MOJ_TEST_CPUS`/`OMP_NUM_THREADS` = k. Cambiarlo recalibra. Ver "Problemas paralelos" | 0 |
| `SAMENUMA` | `n` | con `CPUNEEDED>1`, `y` = las k CPUs de cada prueba en el mismo nodo NUMA | 0 |
| `STOPWHEN_WA` | no se detiene | `y` interrumpe en el primer Wrong Answer | 0 |
| `STOPWHEN_TLE` | no se detiene | `y` interrumpe en el primer Time Limit Exceeded | 0 |
| `STOPWHEN_RE` | no se detiene | `y` interrumpe en el primer Runtime Error | 0 |
| `TLERERUN` | `y` | repite la prueba una vez antes de confirmar un TLE (evita TLE por ruido de la máquina) | 0 |
| `CALIBRATIONTL` | `5` | tiempo límite usado **durante** la calibración, antes de que exista un TL real | 0 |
| `ALLOWTLEDURINGCALIBRATION` | desactivado | `y` acepta una solución `good` con TLE como "calibró" (el lenguaje obtiene TL aunque exceda el `CALIBRATIONTL` — casos raros de good deliberadamente en el límite) | 0 |
| `SAMPLE` | ejemplos = `tests/input/sample*` | `no` declara que el problema **no tiene ejemplos** (sección 4, "Problema sin ejemplo"): el enunciado sale sin el recuadro y no se ofrece nada para descargar. El juez no lo lee y no entra en el tl-checksum (no pide recalibración) | 0 |
| `FUNCTION_LANGS` | ninguno | los lenguajes de **envío de función** (`FUNCTION_LANGS=c,py`; ids de lenguaje de envío: `py`, no `py3`). En ellos el estudiante envía SOLO la función, y el `main` viene de `scripts/<lang>/compile.sh`. El editor del estudiante (entrenamiento y el módulo `esqueletos` de la competencia) abre **vacío** en esos lenguajes: el esqueleto de código tiene `main`, y el estudiante recibiría Compilation Error por main duplicado. **Lo declara el autor**: tener `scripts/<lang>/compile.sh` no basta, porque el mismo slot sirve para ban y OpenMP/MPI, donde el estudiante escribe el programa completo. `moj fn` y la plantilla "Envío de función" del editor web escriben la línea; en el editor, es el campo **Envío de función** de la pestaña Límites. La validación rechaza un lenguaje listado sin `scripts/<lang>/compile.sh` y avisa de un driver fuera de la lista. El json servible lo lleva como `function_langs`. El juez no lo lee y no entra en el tl-checksum (no pide recalibración) | 0 |
| `TLOVERRIDE[<lang>]` / `TLOVERRIDE[default]` | sin override | **el autor decide el TL a la fuerza** (segundos, por lenguaje + default). La calibración sigue ejecutándose (y su historial queda visible), pero el valor FINAL — en la evaluación (el juez lo aplica DESPUÉS de los `TLMOD`, así que gana sobre todo) y en TODA visualización (entrenamiento, competencia, hoja de TL de la competencia, `/problems/tl`) — es `TLOVERRIDE[lang] // TLOVERRIDE[default] // calibrado[lang]`. Solo valor numérico literal (`TLOVERRIDE[java]=2.5`); el servidor lo lee con grep, nunca ejecuta el conf. ⚠ **Usa `TLOVERRIDE[py]`, nunca `py3`/`py2`** — son claves LEGADAS: el servidor las normaliza a `py` al mostrar el valor y el juez también (desde 2026-08-24), pero antes de eso un `TLOVERRIDE[py3]` se MOSTRABA pero no se APLICABA al evaluar. La **gestión de problemas** (Panel, editor, `/problems/{get,status,calib,tl}`) también muestra el efectivo — con un sello ⚡ y el calibrado al lado; los tiempos de las tarjetas de calibración siguen siendo la MEDICIÓN, porque la calibración ignora el override a propósito. ⚠ cambiar el override cambia el tl-checksum ⇒ dispara una recalibración (inofensiva — el override gana de todos modos) | 0 |

La columna "Uso hoy" cuenta en cuántos de los 453 `conf` del acervo aparece la clave. Un cero no quiere decir
que la clave no funcione: quiere decir que el default sirve para casi todo problema. Cámbiala solo cuando
tengas un motivo (un problema que exige mucha memoria, o un lenguaje que necesita holgura).

`PUBLIC=no` en el `conf` es **legado**. Hoy lo que decide si el problema es público es el campo `public` del
`.moj-meta.json`.

#### Problemas paralelos (`CPUNEEDED`, `SAMENUMA`) y pruebas en paralelo

Dos cosas diferentes con la misma palabra:

| | Qué es | Clave |
|---|---|---|
| **prueba paralela** | UNA prueba usa **k CPUs** al mismo tiempo (el programa del estudiante es paralelo) | `CPUNEEDED=k`, `SAMENUMA=y` |
| **pruebas en paralelo** | el juez ejecuta **varias pruebas** del mismo envío al mismo tiempo, cada una en sus k CPUs | `ALLOWPARALLELTEST`, `MAXPARALLELTESTS` |

Los jueces oficiales están particionados en **slots de 1 CPU**. Un problema con `CPUNEEDED=k`:

- solo se entrega a un juez con **k slots libres** (con `SAMENUMA=y`, k slots libres **en el mismo nodo**);
  el agente los junta en un grupo, fija la prueba en él (dentro de la jaula `nproc` = k) y los separa al final;
- se **calibra con k CPUs, una prueba a la vez** — el tiempo límite solo vale con el mismo k, por eso
  cambiar `CPUNEEDED`/`SAMENUMA` recalibra (el `conf` entra en el checksum);
- entrega a la jaula `MOJ_TEST_CPUS` y `OMP_NUM_THREADS` (= k, exportados por `binfile.sh`): OpenMP se
  dimensiona solo; el `run.sh` de MPI hace `mpirun -np "$MOJ_TEST_CPUS"` — **nunca un `-np` fijo**.
  Plantillas listas: `paralelo-openmp` y `paralelo-mpi` (selector del editor);
- con hyperthreading y k ≥ 2 el grupo es de **núcleos enteros**, en la calibración y en la evaluación;
- sin un juez capaz (k mayor que cualquier juez, o que cualquier nodo con `SAMENUMA=y`) la evaluación
  espera y, pasado un tiempo, recibe **Judge Error** con el motivo — Validar avisa antes.

`ALLOWPARALLELTEST` activado (el default) solo dice que el juez **puede** ejecutar varias pruebas al mismo
tiempo cuando tiene CPU ociosa (la política global del admin decide; en una competencia queda desactivada). Cada
prueba sigue sola en sus CPUs, el tiempo se mide como siempre y un TLE visto así se rehace
en serie antes de valer; `MAXPARALLELTESTS` es el tope por problema. El informe del envío
dice lo que pasó: `Paralelismo: P teste(s) ao mesmo tempo × k CPU(s) por teste` (paralelismo: P prueba(s)
al mismo tiempo × k CPU(s) por prueba). La validación
reprueba un valor inválido en las cuatro claves. El json servible (`var/jsons/<id>.json`) lleva
`cpu_needed` y `same_numa` — es con él que el checklist previo a la competencia (`judges_cpus`) avisa
cuando ningún juez del pool tiene las CPUs, sin abrir el paquete. Guía completa:
`mojtools/docs/problema-paralelo.md`.

### `author`

Texto libre, un autor por línea. Se le sirve al estudiante **verbatim** (las líneas se unen con
`", "`). No separes con coma esperando que el sistema divida: la coma ya aparece dentro de las
líneas ("Fulano, adaptado por Mengano").

El archivo es **obligatorio**: sin él, la validación reprueba.

### `tags`

Los temas del problema, una tag por línea, empezando con `#`, en minúsculas:

```
#grafos
#bfs
#matriz
```

Las tags alimentan la búsqueda del entrenamiento y el **sorteo** de problemas al crear una competencia.

Las tags son **curaduría**, no contenido juzgable — y `moj upload` las trata así: tar **sin** el
archivo `tags` ⇒ el servidor **preserva** las que ya tiene (un directorio armado a mano rara vez trae el
archivo, y el espejado las borraba en silencio); tar **con** el archivo (aunque esté vacío) ⇒ las reemplaza.
Borrarlas todas a propósito = enviar el archivo vacío (o usar el editor web / `moj push`).

**La dificultad no es una tag y no existe en el paquete.** Se **calcula** a partir de la tasa de acierto
real de los estudiantes (fácil si al menos la mitad acierta, difícil si acierta menos del 20%, desconocida si
nadie lo intentó). No sirve de nada buscar un campo de dificultad para llenar.

### `tl` y `tl.<host>`

**Tú no escribes estos archivos.** Los genera la calibración, en el juez. Ver la sección 10.

## 5. `.moj-meta.json`: los metadatos del problema

Es el metadato **canónico** del problema: lo que no cabe en ninguno de los archivos de arriba. Queda dentro del
paquete y se incluye en el commit junto con él.

Quien lo escribe es el **servidor**, siempre (función `write_meta`, en `server/api/v1/lib/problems.sh`). Ni
el autor ni la CLI editan este archivo a mano: mandan los campos por la API, y el servidor los escribe.

**En `moj upload` (el paquete sube en un tar), el servidor separa los campos en dos grupos:**

- **contenido** — `display_title`, `collections` y `languages`: **vienen del `.moj-meta.json` del tar**
  (es el paquete el que sabe cómo se llama el problema y en qué lenguajes acepta envíos). Ausentes o
  vacíos (`[]`) ⇒ el servidor **preserva** lo que ya tenía — vaciar la whitelist de lenguajes se hace con
  `moj push`/editor, nunca por omisión en un tar.
- **acceso** — `public`, `public_at` y `owner`: **nunca** vienen del tar; solo las rutas propias los cambian
  (`/problems/set-public` etc.). Si vinieran, bastaría con descargar un problema público, adaptarlo para una
  competencia en una org privada y hacer `moj upload` — la siguiente indexación publicaría la competencia.

La CLI cierra el círculo: en el `moj upload` de un **directorio**, sintetiza un `.moj-meta.json` en el tar
a partir del `.moj-id` local (título/colecciones/languages) — un paquete de `moj clone` sube completo.
(Un tar de `moj download` ya trae el meta real del servidor.)

Ejemplo real (`moj-problems/apc/seno/.moj-meta.json`):

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

Campo por campo:

| Campo | Tipo | Qué es |
|---|---|---|
| `display_title` | texto | **El título del problema.** Es la fuente única. Si el autor no manda un título y el campo aún no existe, el servidor **deriva** uno (del `%` del enunciado, del `#+title:` del org, del `\section{}` del tex, o, en último caso, del nombre del directorio). Por eso el campo nunca queda vacío |
| `titles` | objeto `{"en": texto, "es": texto}` | el título de cada **traducción** del enunciado (sección 4, "Idiomas"). El servidor solo guarda el idioma que tiene `docs/enunciado.<lang>.md`. Un idioma sin título usa el `display_title`. En la CLI es el campo `titles` del `.moj-id` (`moj title --lang en "Hello World"`) |
| `owner` | login | el dueño del problema |
| `public` | booleano | si es `true`, el problema entra en el Entrenamiento libre. Publicar exige que la **org** lo permita (sección 7) |
| `collections` | lista de textos | las colecciones en las que está el problema (sección 8). Puede estar en varias |
| `languages` | lista de ids | los lenguajes de envío **permitidos** en este problema. Vacío o ausente = todos los lenguajes predeterminados. Es lo que permite un problema solo-PDDL, por ejemplo. El servidor normaliza (minúsculas, `py2`/`py3` se vuelven `py`, `cc`/`cxx`/`c++` se vuelven `cpp`, sin repetidos). **La API RECHAZA un envío fuera de la lista** (`400 lang_not_allowed`, en `/submit` y en el offline — no es solo el filtro del desplegable), esencial en un problema de función/prohibición: sin esto, cambiar la extensión burlaba el driver |
| `public_at` | epoch | cuándo se publicó el problema **por primera vez**. Se queda ahí aunque lo despubliquen después. Alimenta la estadística de entrada de problemas públicos |
| `migrated_at` | epoch | cuándo vino el problema de una migración. Solo informativo |

Dos campos son **legado** y no deben usarse en código nuevo:

- `gitea.{owner,repo}`: quedó de la época en que los paquetes se espejaban en un Gitea. El Gitea fue
  eliminado. El campo sigue en los 453 metas del acervo y todavía se lee en un único lugar, como
  alternativa para descubrir el `owner` de paquetes antiguos.
- `collaborators`: se lee en algunos puntos, pero **nunca se escribe**, y está vacío en todo el acervo.
  En el modelo por org, colaborar en un problema es **ser miembro de la org** (sección 7).

Quién lee el `.moj-meta.json`: `gen-problem-json.sh` (para armar el índice del estudiante),
`gen-problem-owners.sh` (para armar el índice de dueños), y la API, al devolver el problema al editor y
a la CLI.

## 6. `.moj-id`: el puntero local de la CLI

Atención, porque este es el punto que más confunde: **`.moj-id` no forma parte del paquete.** Fíjate
también en que **no tiene extensión `.json`** (no existe ningún archivo `.moj-id.json` en el MOJ), aunque
el contenido sea JSON.

Lo crea **`moj-cli`**, en tu máquina, cuando ejecutas `moj clone` o `moj new`. Sirve
para que el clon local recuerde de qué problema es, y para llevar los campos editables del metadato de
ida y vuelta. `moj push` **excluye** este archivo de lo que sube.

```json
{ "id": "apc#seno", "repo": "apc", "prob": "seno", "title": "Seno por série de Taylor",
  "format": "md", "collections": ["problemas-apc"], "public": true, "base_rev": "9f2c61d0a8b37e14" }
```

| Campo | Qué es |
|---|---|
| `id`, `repo`, `prob` | qué problema es este directorio (`<org>#<prob>`) |
| `title` | espejo local del `display_title`. Editarlo aquí y hacer `push` cambia el título en el servidor. El `push` **se niega** a enviar con el título vacío |
| `titles` | espejo local del `titles` del meta: el título de cada traducción (`{"en": "Hello World"}`). `moj title <dir> --lang en "…"` lo edita |
| `trans_rt` | `true` en un clon que **conoce** las traducciones: el `push` manda `translations` con todos los idiomas, y un idioma sin archivo local se vuelve `null` (lo borra en el servidor). Un clon antiguo no borra la traducción de nadie |
| `format` | `md`, `org` o `tex`, el formato del enunciado de este clon |
| `collections`, `languages`, `public` | espejos locales de los campos del `.moj-meta.json`, con ida y vuelta por el `push` (y el `moj upload` de un directorio lleva título/colecciones/languages en un meta **sintetizado** a partir de aquí; `public` nunca sube). `moj languages <dir>` edita la whitelist sin abrir el archivo |
| `scripts_rt` | marca que este clon sabe hacer ida y vuelta de `scripts/` y `tests/score`. Sin esta marca, el `push` no tiene permiso para **borrar** esos archivos en el servidor (protege a los clones antiguos de destruir la corrección especial sin querer) |
| `base_rev` | la revisión del servidor (`rev`) en el último `clone`, `pull` o `push` de esta carpeta. El `push` y el `upload` la mandan como `base_rev`: si el problema cambió en el servidor desde entonces (editor web, otro autor), el servidor se niega con 409 y no se escribe nada. `moj push --overwrite` envía por encima. Vacío = carpeta anterior a este bloqueo (el `push` escribe por encima, como siempre) |

Al lado del `.moj-id` la CLI escribe el **`.moj-base`**, la *línea de base* de la carpeta: una línea
`<hash>\t<caminho>` (`<caminho>` = ruta del archivo) por cada archivo del paquete (el conjunto que envía el `push`), más una línea
`<hash>\t.moj-id` con los campos de autoría del `.moj-id` (título, títulos, lenguajes, colecciones). Es lo
que usa `moj pull` para saber qué cambiaste **tú** desde el último `clone`/`pull`/`push`:

- carpeta sin cambios tuyos y servidor con versión nueva: el `pull` cambia los archivos del paquete (incluso
  borra los que desaparecieron en el servidor) y mantiene los que no son del paquete (un `gerador.py`, por ejemplo);
- carpeta con cambios tuyos: el `pull` **se niega** y lista los archivos; `moj pull --force` copia la carpeta
  entera a `<pasta>.local-AAAAMMDD-HHMMSS` (`<pasta>` = el nombre de la carpeta, `AAAAMMDD-HHMMSS` =
  fecha y hora) y luego trae la versión del servidor;
- carpeta sin `.moj-base` (clonada antes de que existiera el `pull`): el `pull` compara con el servidor; si son
  iguales, solo escribe la línea de base; si no, se niega (no hay forma de saber quién cambió) y sugiere `--force`.

El `.moj-base` tampoco sube (ni en el `push`, ni en el tar de `moj upload`).

Resumiendo la diferencia:

| | `.moj-meta.json` | `.moj-id` |
|---|---|---|
| Dónde vive | dentro del paquete, en el servidor | en el clon local del autor |
| Quién lo escribe | el servidor | `moj-cli` |
| ¿Va al servidor? | **es** el del servidor | **no**, se excluye del envío (y el `.moj-base` también) |
| Para qué sirve | ser el metadato canónico | recordar de qué problema es el directorio y llevar los campos de ida y vuelta |

Los 336 `.moj-id` que aparecen hoy dentro de `moj-problems/` son **residuos** de migraciones antiguas que
copiaron directorios enteros. El servidor los ignora.

## 7. ORG: quién puede modificar

Una **org** es un grupo de acceso. Es la parte antes del `#` en el id del problema (`apc#fatorial` está en la
org `apc`), y es ella la que decide **quién puede editar** el problema.

El registro queda en `contests/treino/var/orgs.json`, y el código en `server/api/v1/lib/orgs.sh`.

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

| Campo | Qué es |
|---|---|
| `members` | quién **escribe** en los problemas de la org. Ser miembro de una org da acceso de edición a **todos** sus problemas |
| `admins` | quién gestiona los miembros y cambia el bloqueo `public_allowed` |
| `public_allowed` | si es `false` (el **default**), **ningún** problema de la org puede ser público |
| `implicit` | marca la org personal de un usuario (ver abajo) |
| `created_by`, `title`, `at` | quién la creó, etiqueta que se muestra, cuándo |

Las reglas que vale la pena recordar:

- **Ser miembro de la org es la única forma de editar un problema.** No existe un atajo de administrador
  global: ni siquiera el `.admin` ve el código fuente, las soluciones o el paquete de un problema de una org de la que
  no es miembro.
- **La org nace privada** (`public_allowed: false`). Es intencional: una competencia en preparación no
  puede escaparse por accidente. Mientras el bloqueo esté cerrado, publicar un problema de la org devuelve
  error. Si un admin **degrada** la org después, sus problemas públicos se despublican en
  cascada.
- **Todo usuario tiene una org personal**, con el nombre de su propio login (la org **implícita**). Se
  crea sola, solo te tiene a ti como miembro, y **nunca** puede permitir problemas públicos. Es donde quedan los
  borradores.
- **Quien no puede ver recibe 404, no 403.** Decir "403, existe pero no puedes verlo" ya filtraría la
  existencia de un problema de competencia. Un problema privado simplemente **no aparece** en los listados,
  ni siquiera para el `.admin`.
- Una org solo se puede **eliminar si está vacía**, y la org implícita nunca se elimina.

Un problema se puede **mover** de org mientras sea borrador (`moj mv`, o desde el editor). Esto cambia el
id, así que el MOJ se niega a mover un problema que ya es público o que ya está en uso en alguna competencia.

Rutas: `/orgs/*` en [API.md](API.md). Por la CLI: `moj org list|create|members|public|rm` y
`moj share <org> <login>`.

## 8. COLECCIÓN: cómo se agrupan los problemas

Una **colección** es una etiqueta de agrupación, y nada más. `problemas-apc`, `obi2016`,
`obi2016-fase2-senior` son colecciones.

El registro queda en `contests/treino/var/collections.json`:

```json
{
  "problemas-apc":         { "owner": "ribas.admin", "created_by": "ribas.admin", "at": 1782519704 },
  "obi2016-fase2-senior":  { "owner": "ribas.admin", "created_by": "ribas.admin", "at": 1782927032 }
}
```

En qué colecciones está un problema es algo que vive en su `.moj-meta.json`, en el campo
`collections` (una lista, porque **un problema puede estar en varias colecciones al mismo tiempo**, y ellas
pueden ser de orgs diferentes).

Puntos importantes:

- **Una colección no da acceso a nada.** Marcar un problema en una colección no deja a nadie editarlo. Quien
  decide el acceso es la org, siempre.
- El nombre es **texto libre**: puede tener espacios y tildes (`"Maratona 2024, fase 1"` es un nombre válido). Nunca
  se convierte en ruta de archivo ni en id.
- El registro es **curado**: para marcar un problema en una colección, esta tiene que **existir ya**. Eso
  evita el zoológico de colecciones escritas cada una con un error de tipeo.
- Renombrar o borrar una colección reetiqueta **todos** los problemas que la tenían, de una vez.
- Solo el dueño de la colección (o un `.admin`) la renombra o la borra.

Para qué sirven, en la práctica:

1. **Navegación en el entrenamiento**: el estudiante filtra los problemas por colección.
2. **Sorteo de problemas** al crear una competencia: pides "5 problemas de la colección X, con la tag
   `grafos`, dificultad media", y el sistema sortea (de forma reproducible, a partir de una
   semilla).

Rutas: `/problems/collection*` en [API.md](API.md). Por la CLI:
`moj collection ls|show|create|add|remove|rename|delete`.

## 9. ORG x COLECCIÓN

Este es el par que más confusión genera, así que vale la tabla. **Los dos son ortogonales**: un problema tiene
exactamente una org y puede tener varias colecciones.

| | ORG | COLECCIÓN |
|---|---|---|
| Para qué sirve | **acceso** (quién edita, quién ve) | **agrupación** (navegar, sortear) |
| Cuántas por problema | exactamente **una** | **varias**, o ninguna |
| ¿Aparece en el id? | sí, es el `<org>` de `<org>#<prob>` | no |
| ¿Cruza orgs? | no tiene sentido | sí, una colección junta problemas de orgs diferentes |
| ¿Tiene miembros? | sí (`members`, `admins`) | no |
| ¿Controla la publicación? | sí (`public_allowed`) | no |
| Dónde se registra | `contests/treino/var/orgs.json` | `contests/treino/var/collections.json` |
| Dónde la declara el problema | en el propio id | en el `.moj-meta.json`, campo `collections` |

En una frase: **la org dice quién manda en el problema; la colección dice dónde aparece.**

## 10. Ciclo de vida de un problema

```
  borrador  ──►  paquete verificado  ──►  calibrado  ──────►  LISTO  ────►  público
 (org privada)  (botón Validar:          (en el juez:        (ningún       (Entrenamiento
                 estático)                TL, soluciones,     pendiente,    libre)
                                          entradas)           ninguna
                                                              incidencia abierta)
```

"Listo" no es un paso que alguien ejecuta: es el nombre del estado en que **todas** las dimensiones de abajo
están en verde. Publicar sigue siendo posible sin él, pero pide confirmación (subsección "Publicación").

### Borrador

El problema nace en tu org (la personal, si no eliges otra). Es privado: nadie además de los
miembros de la org ve que existe.

### Paquete verificado (el botón Validar)

Ejecuta `mojtools/validate-problem.sh`, que escribe un informe en `run/validation/<id>.json`. Es una
verificación **estática** del contenido del paquete: archivos, secciones del enunciado, ejemplos, pruebas
emparejadas. **No ejecuta ninguna solución.** Quien ejecuta las soluciones es la calibración (abajo). Por eso la
pantalla dice **"Paquete"**, y ya no "Validado": el nombre antiguo hacía que el autor creyera que las soluciones
estaban verificadas (relato de Arthur Botelho, 22/09/2026).

**Todas** las verificaciones de abajo tienen que pasar (no existe una verificación "opcional" que repruebe a medias):

| Verificación | Qué exige |
|---|---|
| `has_author` | existe el archivo `author` |
| `has_statement` | existe `docs/enunciado.{md,org,tex}` |
| `html_builds` | pandoc logra renderizar el enunciado |
| `secao_entrada` | el enunciado tiene `## Entrada` |
| `secao_saida` | el enunciado tiene `## Saída` (acepta `Output` y `Salida`) |
| `html_builds_<lang>`, `secao_entrada_<lang>`, `secao_saida_<lang>` | lo mismo, para cada traducción `docs/enunciado.<lang>.md` presente |
| `examples_present` | existe al menos un par input/output |
| `tests_paired` | todo input tiene su output, y viceversa |
| `has_good_sol` | existe al menos una solución en `sols/good/` |
| `good_sol_accepts` | toda solución `good` es aceptada |

Algunos avisos son **informativos** y no reprueban: LaTeX que se filtra en la prosa del enunciado, un ejemplo
escrito a mano dentro del texto, y un checker incluido en el commit como binario (estándar antiguo, obsoleto: manda la
fuente `scripts/checker.cpp` y deja que el bridge compile).

Sobre `good_sol_accepts`: ejecutar las soluciones exige un sandbox de verdad, y el servidor no lo tiene. La
verificación del paquete **aplaza** esa verificación para la calibración, que corre en un juez real (el informe dice
`verificado na calibração (juiz)`, o sea, verificado en la calibración en el juez). El resultado de cada solución aparece en la dimensión **Soluciones**.

Si la validación pasa, **indexa** el problema (llama a `gen-problem-json.sh`), que genera el JSON que el
estudiante de hecho consume, con el enunciado ya en HTML.

### Calibración (de dónde viene el tiempo límite)

**El tiempo límite no se escribe a mano en el paquete.** Se **mide**.

Un juez descarga el paquete, ejecuta cada solución de `sols/good/`, toma el peor tiempo de cada lenguaje,
lo multiplica por `TLMOD[calibrafactor]` (1.35 por defecto) y envía el resultado al servidor. El
resultado queda en `run/tl/<id>.json`, guardado **por máquina**:

```json
{ "id": "apc#ajude_simplificado", "checksum": "df7f628e84bfc6c3", "updated_at": 1783534737,
  "hosts": {
    "cpu1": { "tl": { "c": ".0335", "cpp": ".0335", "java": ".3710", "py": ".1685",
                      "default": ".0335" }, "at": 1783534737 },
    "cpu2": { "tl": { "…": "…" }, "at": 1783534733 } } }
```

El tiempo límite **servido** al estudiante es el **mayor entre las máquinas**, para que el envío no sea
reprobado por haber caído en un juez más lento. Un lenguaje solo obtiene tiempo límite si alguna solución
`good` en ese lenguaje fue **aceptada** en algún juez. Sin tiempo límite, el lenguaje no queda
disponible.

La calibración ejecuta **una prueba a la vez** y, en un problema paralelo, cada prueba con las **k CPUs** de
`CPUNEEDED` — exactamente la forma en que la evaluación ejecuta cada prueba (por eso el TL de k=2 no
vale para k=4 y cambiar la clave recalibra).

El "Calibrar" explícito (editor, `moj calibrate`, publicar) ejecuta **todas** las soluciones. La calibración
bajo demanda, que un juez hace solo en el 1.er envío de un paquete nuevo, ejecuta **solo las `good`** (es
rápida a propósito): después de ella, las otras categorías aparecen "sin resultado".

### Soluciones: ¿cada una hace lo que pide su categoría?

La calibración devuelve, por juez y por solución, el código de **cada prueba** (`AC`, `WA`, `TLE`, `MLE`,
`RE`, `UE`). El **servidor** lo compara con la categoría (`server/api/v1/lib/calib-expect.sh`, la fuente
única; el editor, el Panel y la CLI solo muestran el resultado) y da uno de cuatro estados:

| Estado | Cuándo |
|---|---|
| ✓ **conforme** | la solución hizo exactamente lo que pide la categoría (tabla de la sección `sols/`) |
| ≈ **conforme, otro motivo** | hizo lo que pide la categoría, pero no de la forma típica: `wrong` reprobada solo por TLE/MLE/RE (sin WA); `slow` con TLE, pero también con WA/RE en otras pruebas; `good` con TLE y `ALLOWTLEDURINGCALIBRATION=y` |
| ✗ **diverge** | no lo hizo: `good`/`pass` reprobada **o más lenta que el tiempo límite efectivo** (ej.: `TLOVERRIDE` por debajo del tiempo medido — en la evaluación recibiría TLE); `slow` sin TLE; `wrong` aceptada |
| ✗ **no se ejecutó** | CE, UE (error del corrector/juez), lenguaje no disponible en el juez, o sin veredicto: la solución no ejercitó las pruebas, así que no demuestra nada |

Dos reglas que cambiaron el 22/09/2026 (antes el juicio era solo de la pantalla y miraba la *cadena* del veredicto):

- con TLE y WA en la misma solución, la cadena decía solo "Time Limit Exceeded" y el WA desaparecía. Hoy una
  `slow` así es ≈, y una `wrong` así es ✓ (tiene WA);
- una `wrong` que **no compila** era "ok" (no fue aceptada). Hoy es ✗ **no se ejecutó**.

En un problema con puntuación (`tests/score`) la cadena trae el veredicto de la peor prueba y la nota de los grupos
(`Time Limit Exceeded,30p. Pontos | …`; hasta el 24/09/2026 era siempre `Wrong,Np`). De cualquier forma el
juicio mira las pruebas: una `slow` con TLE es ✓.

El resultado vale para la **versión** del paquete que se calibró. Guardar algo que la calibración ejercita
(`sols/`, `tests/`, `scripts/`, `conf`) marca las soluciones como **"no verificadas desde la última
edición"** hasta la próxima calibración. Guardar el enunciado no las marca.


### El checksum, y qué dispara una recalibración

Son **DOS sellos**, calculados por el mismo `tl-checksum.sh`, porque las dos preguntas son
diferentes: *"¿el tiempo límite medido todavía vale?"* y *"¿el juez todavía tiene el paquete correcto en caché?"*.

| | `tl_checksum` (estrecho) | `pkg_version` (amplio) |
|---|---|---|
| Cómo se calcula | `tl-checksum.sh <pkg>` | `tl-checksum.sh --all-sols <pkg>` |
| Cubre | `conf` (menos la línea `SAMPLE`), `tests/input/*`, `tests/output/*` (no vacíos), `tests/score`, `sols/good/*`, `scripts/*` (contenido **y** bit de ejecución) **menos `scripts/validator.cpp`** | todo lo que cubre el estrecho **+ `sols/pass`, `sols/slow`, `sols/wrong`, `sols/upcoming` + `scripts/validator.cpp`** |
| Para qué sirve | ata el **TL** al paquete: es el `checksum` de `run/tl/<id>.json`, el del índice de dueños y el que compara `/contest/problems` | es la **clave de la caché del juez** y la identidad de una calibración: `/judge/package-meta` lo devuelve como `checksum` y el agente vuelve a descargar cuando cambia |

Ninguno de los dos cubre `docs/enunciado.*`, `tags`, `author` ni el `.moj-meta.json`
(título/colecciones/tags).

> `tests/output/*` y `tests/score` entraron en el checksum el 2026-07-19: sin ellos, un archivo de respuestas o
> una puntuación corregida **nunca llegaba al juez** (la caché del problema no se invalidaba).
>
> La separación en dos sellos es del 2026-09-20 (relato de Arthur Botelho). Antes había solo el
> estrecho, y cumplía las dos funciones: cambiar una solución `pass`/`slow`/`wrong` **no cambiaba la
> clave**, así que el juez recalibraba el `sols/` de la **caché vieja** — juzgando una solución que el autor ya
> había borrado, ignorando la que acababa de escribir, y cada juez con un conjunto diferente bajo
> el mismo checksum. Ampliar el sello estrecho no sirve: también es lo que dice si el TL vale, y el
> TL desaparecería de la competencia con cada solución guardada.

Si el `tl_checksum` del paquete deja de coincidir con el guardado, el TL se considera **viejo** y desaparece (el
problema pasa a aparecer como "necesita recalibración"). O sea: **corregir un error de tipeo en el enunciado no
fuerza una recalibración; cambiar una prueba, una solución `good`, el `conf` o un script sí la fuerza.** Guardar una
solución `pass`/`slow`/`wrong` **no** invalida el TL, pero hace que el juez busque el paquete nuevo — es
exactamente lo que el "Calibrar" necesita para ejecutar lo que acabas de guardar.

### Entradas: el validador de entrada

Si el paquete tiene `scripts/validator.cpp` (sección `scripts/`), la calibración completa lo ejecuta en el juez,
antes de las soluciones, sobre cada `tests/input/*`: la testlib reprueba la entrada que se sale del formato o de los
límites, con un mensaje que dice dónde (`FAIL Integer parameter [name=N] equals to 1296, violates the
range [1, 1000]`). El resultado aparece en la tarjeta de cada juez (línea **Entradas**), en el Panel y en
`moj check`/`moj calib`. Una entrada inválida, o un validador que no se ejecutó (no compiló, pasó de 5 s en una
entrada o de 60 s en total), deja el problema como no listo. Un paquete **sin** validador no es un pendiente —
solo aparece como "sin validador de entrada". La calibración rápida del 1.er envío no ejecuta el validador.

### Listo

El problema está **listo** cuando `/problems/status` no tiene ningún **pendiente** (`pending`):

| Pendiente | Significa |
|---|---|
| `package_failed` / `package_unchecked` | la verificación del paquete reprobó / nunca se ejecutó (botón Validar) |
| `uncalibrated` / `needs_recalibration` | sin calibración / el paquete cambió desde la calibración |
| `good_no_tl:<langs>` | solución `good` sin tiempo límite en esos lenguajes (falló en todos los jueces) |
| `sols_divergent:<n>` | *n* soluciones divergentes o que no se ejecutaron |
| `sols_unchecked` | hay una solución sin resultado (calibración rápida) o el paquete cambió desde la calibración |
| `inputs_invalid:<n>` / `inputs_error` | el validador de entrada (`scripts/validator.cpp`, subsección "Entradas") reprobó *n* pruebas / no se ejecutó |
| `issues_open:<n>` | *n* incidencias abiertas (subsección "Incidencias") |

El editor muestra el sello "✓ Listo" o "N pendiente(s)" en la barra de arriba. El Panel tiene la tarjeta "listos"
y la columna Soluciones. `moj check` dice `pronto: SIM` (listo: sí) o lista los pendientes.

### Incidencias

La revisión del comité queda en **incidencias por problema**: cualquier miembro de la org abre una incidencia ("la prueba 7
está fuera del límite del enunciado", "el TL de Python está ajustado"), comenta y la cierra. Mientras haya una
incidencia abierta, el problema no está listo. Web: pestaña **🐞 Incidencias** del editor (el Panel muestra 🐞N con enlace);
CLI: `moj issues`. Las incidencias **no forman parte del paquete**: quedan en el servidor
(`contests/treino/var/problem-issues/`), así que no cambian el `rev`, no desaparecen con un `moj upload` y no van
al juez. Mover el problema de org se lleva las incidencias; borrar el problema las borra.

### Publicación

Publicar (`moj publish`, o el botón en el editor) hace que el servidor **verifique el paquete y calibre**. El
problema entra en el Entrenamiento libre cuando pasa la verificación del paquete (es ella la que genera el enunciado
servido). Y, antes de todo eso, la **org** necesita tener `public_allowed: true` (sección 7).

**Publicar un problema que aún no está listo pide confirmación** con la lista de pendientes (en el
editor, en el Panel y en `moj publish`/`moj public on`; `--yes` solo muestra la lista y sigue). Nada
**bloquea** la publicación: es decisión de quien publica.

## 11. Preguntas frecuentes

**¿Dónde pongo el título?**
En el campo `display_title` del `.moj-meta.json`, y en la práctica lo editas desde el editor web o con el campo
`title` del `.moj-id` (la CLI). Nunca en el texto del enunciado.

**¿Cómo escribo el tiempo límite?**
No lo escribes. Lo mide la calibración. Lo que puedes ajustar es la **holgura**, con
`TLMOD[calibrafactor]` en el `conf`.

**Quiero que el problema solo acepte Python.**
Pon `["py"]` en el campo `languages` del `.moj-meta.json` — desde el editor web, con
`moj languages <dir> py` + `moj push`, o editando el `.moj-id`.

**Mi problema tiene varias respuestas correctas.**
Necesitas un checker: `scripts/compare.sh`. Ver `mojtools/docs/correcao-especial.md` y la guía
de testlib en `mojtools/docs/checker-testlib.md`.

**El estudiante va a entregar solo una función, no el programa entero.**
Es el envío de función: `scripts/<lang>/compile.sh`. Misma guía.

**Edité el enunciado. ¿Necesito recalibrar?**
No. El enunciado no entra en el checksum. La traducción tampoco.

**¿Cómo traduzco un problema?**
Crea `docs/enunciado.en.md` (o `.es.md`) al lado de `docs/enunciado.md`. Traduce la explicación de
cada ejemplo en `docs/notes/<sample>.en.md` y el editorial en `docs/solucao.en.md`. Pon el título con
`moj title . --lang en "Hello World"`. En el editor web, usa los chips PT · EN · ES de la pestaña Enunciado. El
portugués sigue siendo obligatorio.

**¿Dónde está la dificultad del problema?**
En ningún lugar del paquete. Se calcula a partir de la tasa de acierto real de los estudiantes.

**Mi problema es de función (o interactivo). Mostrar la entrada no tiene sentido.**
No crees `sample*`, pon `SAMPLE=no` en el `conf` (en el editor web: pestaña Límites, "este problema no tiene
ejemplos") y explica el ejemplo en el texto del enunciado, en una sección `## Exemplo`. Ver sección 4,
"Problema sin ejemplo".

**Edité en la web. ¿Cómo lo traigo a mi carpeta?**
Ejecuta `moj pull` dentro de la carpeta del problema. Si la carpeta tiene cambios tuyos que no se enviaron, el
`pull` se niega. Envíalos antes (`moj push`) o ejecuta `moj pull --force`, que guarda tu carpeta en una copia.

**`moj push` dijo que el problema cambió en el servidor.**
Alguien guardó el problema (web u otro clon) después de tu último `clone`/`pull`/`push`. No se envió
nada. Ejecuta `moj pull --force` para traer la versión nueva y vuelve a aplicar tus cambios a partir de la
copia `.local-*`, o ejecuta `moj push --overwrite` para enviar tu versión por encima. El editor web tiene el
mismo bloqueo: avisa quién cambió y ofrece "Recargar" o "Guardar encima".

**¿Cuál es la diferencia entre `.moj-meta.json` y `.moj-id`?**
Ver la tabla al final de la sección 6. En una frase: el primero es el metadato del servidor; el segundo es una
nota que la CLI deja en tu directorio local y que nunca sube.

---

## Referencias

- **Guía práctica** para armar un paquete, y la referencia de cada comando: `mojtools/README.md`.
- **Corrección especial** (checker, envío de función, interactivo): `mojtools/docs/correcao-especial.md`,
  `mojtools/docs/checker-testlib.md`, `mojtools/docs/problema-interativo.md`.
- **Rutas de la API** que leen y escriben el paquete, las orgs y las colecciones: [API.md](API.md).
- **Arquitectura** general: [OVERVIEW.md](OVERVIEW.md). **Camino de un envío**: [FLOW.md](FLOW.md).
- **La CLI de autoría** (`moj`): `moj-cli/README.md`.
