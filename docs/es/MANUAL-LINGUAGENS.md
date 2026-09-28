<!-- i18n-source: MANUAL-LINGUAGENS.md blob:fb85a1e361ea3519d8d95018d1df012362e0889e -->
# MOJ: Enviar soluciones (lenguajes y entrada/salida)

> **Nota de traducción.** Este manual es una traducción del original en portugués. Las herramientas de línea de comandos (`moj`, `moj-contest`, `moj-comp`) muestran sus mensajes en portugués, y los ejemplos de comandos son idénticos al original.

Este manual se convirtió en una **página del propio MOJ**:

> ### 📖 [`/treino/ajuda/`](/treino/ajuda/)
> En el sitio: por el enlace **"📖 Cómo enviar"**, junto al selector de
> lenguaje, en el momento de enviar la solución. **También vale dentro de una competencia**: es la única página fuera
> de `/contest/` que el `contest-guard` deja abrir en el subdominio de la competencia (allí toma la barra superior de la
> competencia y obedece su LOCALE), porque el competidor la necesita en la LAN aislada.

La página enseña lo mismo que enseñaba este archivo, y es donde el contenido pasa a vivir:

1. **Entrada y salida**: el programa lee de stdin, escribe en stdout y nunca abre archivos.
2. **La extensión es el lenguaje**: desde el editor, el menú decide (el código se convierte en `solution.<ext>`); si
   envías un archivo, la extensión del archivo decide y el menú se ignora. C++ acepta `.cpp`, `.cc`, `.cxx` y
   `.c++`. El MOJ guarda el lenguaje canónico (`cpp`) y mantiene el nombre de tu archivo.
3. **Tabla de lenguajes**, con el `id` (que es la extensión) y la observación de cada uno.
4. **Plantilla de código de cada lenguaje**: el esqueleto que entrega el editor y una solución completa,
   con botón para copiar.
5. **Avisos**: la clase `public` de Java, `.pl` que es Prolog y no Perl, Python que es pypy3, y la pila
   de 128 MB.
6. **Lo que se rechaza al recibir el envío**: una extensión que la plataforma no ejecuta (`.exe`, `.pdf`, `.zip`…) vuelve
   con **400 `lang_not_allowed`** y la lista de lo que ese problema acepta. Una lista de lenguajes
   vacía significa **los de la plataforma** (`PLATFORM_LANGS`, el espejo de `mojtools/lang/`), nunca
   "cualquier extensión". Un código fuente de más de **1 MB** vuelve con **413 `source_too_large`**. Estos dos
   controles nacieron del incidente del 2026-08-19, en el que un binario compilado entró en la cola y quedó
   pendiente para siempre.

## Por qué se convirtió en página, y no en un `.md`

- **La tabla de lenguajes se genera** a partir de la lista real que el sitio usa para armar el menú de envío
  (`web/shared/languages.js`). Un lenguaje nuevo aparece en la ayuda solo, así que la página **no
  envejece**. Una tabla escrita a mano aquí envejecería con el primer cambio.
- El esqueleto de código que se muestra es el **mismo** campo que inserta el editor: el estudiante lee exactamente lo que
  va a ver en pantalla.
- La página es **trilingüe (pt/en/es)**, como toda pantalla del MOJ. Organizamos competencias con competidores de otros países, y
  un manual solo en portugués dejaría a esas personas sin instrucciones.
- El estudiante **no lee el repositorio**. Lee el sitio. Servir esto como `.md` en `/docs/` hacía que el navegador
  descargara un archivo de texto.

El contenido es `web/treino/ajuda/` (la página) y `web/treino/ajuda/exemplos.js` (las soluciones completas).
Para agregar un lenguaje a la tabla, modifica `web/shared/languages.js`. Para agregar una
solución de ejemplo, **ejecuta el código antes** y agrégala en `exemplos.js`.

## A dónde ir ahora

- Cómo usar el **entrenamiento** en el día a día: [MANUAL-TREINO.md](MANUAL-TREINO.md).
- Cómo enviar durante una **competencia**: [MANUAL-CONTEST.md](MANUAL-CONTEST.md).
- Cómo se implementan los lenguajes en el juez (el contrato de `lang/<lang>/`): `mojtools/README.md`.
