<!-- i18n-source: MANUAL-TREINO.md blob:ce87837d89148ef015a8e2ff722fe27b2240fa35 -->
# MOJ: Manual del Entrenamiento libre (estudiante)

> **Nota de traducción.** Este manual es una traducción del original en portugués. Las herramientas de línea de comandos (`moj`, `moj-contest`, `moj-comp`) muestran sus mensajes en portugués, y los ejemplos de comandos son idénticos al original.

> **¿Prefieres la terminal?** La CLI `moj-comp` también funciona en el entrenamiento: buscar un problema,
> descargar el enunciado, enviar y recibir el veredicto sin salir de la shell. Guía:
> [/treino/cli.html](/treino/cli.html).

Te damos la bienvenida al **Entrenamiento libre** del MOJ, el juez en línea. Este manual muestra, paso a
paso, cómo crear tu cuenta, ingresar, encontrar problemas, enviar tu solución y seguir el
resultado. Está escrito para quien está empezando, así que vamos con calma y sin prisa.

El Entrenamiento libre es el espacio donde practicas a tu ritmo: eliges el problema, escribes el
código, lo envías y ves el veredicto. Sin plazo y sin marcador de competencia. Para competir de
verdad, consulta el `MANUAL-CONTEST.md` al final de este documento.

---

## Contenido

1. [La página de inicio](#1-la-página-de-inicio)
2. [Crear una cuenta por Telegram](#2-crear-una-cuenta-por-telegram)
3. [Ingresar](#3-ingresar)
4. [Olvidé mi contraseña](#4-olvidé-mi-contraseña)
5. [Encontrar problemas](#5-encontrar-problemas)
6. [Resolver un problema](#6-resolver-un-problema)
7. [Perfil](#7-perfil)
8. [Mis estadísticas](#8-mis-estadísticas)
9. [Página de editores](#9-página-de-editores)
10. [Para saber más](#10-para-saber-más)

---

## 1. La página de inicio

Abre la dirección `/` del MOJ. **No necesitas iniciar sesión** para ver la página de inicio.

Arriba está la **barra de menú** con estos elementos:

| Elemento | Para qué sirve |
|---|---|
| **Inicio** | Vuelve a esta página |
| **Entrenamiento libre** | El espacio de práctica libre (es el tema de este manual) |
| **Competencias** | Competencias y entrenamientos con plazo |
| **Noticias** | Avisos y novedades de la plataforma |
| **Estado** | Situación de los jueces y del sistema |
| **Docs** | Manuales y documentación |

Junto al menú está el **selector de idioma PT · EN · ES**: todo el sitio existe en los tres idiomas. A
la **derecha** está el área de inicio de sesión: antes de ingresar, los campos de usuario y contraseña;
después, tu **avatar**, que abre un menú con accesos directos (Mis estadísticas, Perfil, Salir…).

Al bajar por la página, encuentras:

- El **destacado** de arriba, con la **noticia destacada** y los botones de acceso directo
  **Entrenamiento libre →**, **Gestión de problemas →** y **📖 Ayuda**.
- La tarjeta **🗂️ Gestión de problemas** (solo aparece para quien puede crear problemas). Es para quien **crea**
  problemas (profesores, ayudantes, autores). Si solo quieres entrenar, puedes ignorarla.
- La tarjeta **🏋️ Entrenamiento libre**, con el botón **Buscar problemas →**.
- El **🏆 Top 10** de quienes más resuelven. **Haz clic en un nombre** para abrir el **perfil
  público** de esa persona (sección 8).
- Los **🔥 Más resueltos · última semana** y los **⌨ Editores · última semana**.
- Los **✅ Resueltos recientemente**, que también enlazan los perfiles de quienes resolvieron.
- La **lista de competencias**, separada en **Abiertas ahora**, **Próximas** y **Finalizadas**,
  con un **filtro por nombre**.
- Las **📰 Noticias**.

Para empezar a practicar, haz clic en **Entrenamiento libre**. Te lleva a la dirección
`/treino/` (sección 5).

---

## 2. Crear una cuenta por Telegram

El registro del Entrenamiento libre está en `/treino/cadastro/` y se **confirma por Telegram**.
Esto evita cuentas duplicadas. Por lo tanto, para registrarte necesitas una **cuenta de
Telegram**.

Sigue estos pasos:

1. **Completa el formulario:**
   - **Nombre completo** (obligatorio).
   - **Login deseado** (opcional). Puede tener de 2 a 32 caracteres, con letras,
     números y los símbolos `.`, `_` y `-`. Si lo dejas vacío, el sistema usa tu
     `@` de Telegram como usuario.
   - **Universidad** (opcional).
2. Haz clic en **Continuar en Telegram →**.
3. Abre el bot **mojinho** en Telegram y toca **Start**. La página de registro queda
   **esperando** y confirma sola en cuanto hablas con el bot.

Un punto importante sobre la contraseña:

> Tu **contraseña llega solo por mensaje privado en Telegram**. **Nunca aparece en la web**.
> Guarda bien ese mensaje.

Terminado el registro, pasa a la pantalla de inicio de sesión (siguiente sección).

> **¿Eres menor de edad (sin Telegram)?** La cuenta la crea un profesor/admin
> **responsable**, que te entrega el usuario y la contraseña. Estas cuentas tienen el perfil siempre
> privado hasta los 18 años. Detalles en [`CONTAS-GERIDAS.md`](CONTAS-GERIDAS.md).

---

## 3. Ingresar

El inicio de sesión está en la **parte superior de cualquier página del Entrenamiento libre**. Verás:

- un campo de **Usuario**;
- un campo de **Contraseña**;
- el botón **Ingresar**.

Completa usuario y contraseña (la contraseña es la que el bot te envió por Telegram) y haz clic en
**Ingresar**.

Cuando tienes la sesión iniciada, la esquina derecha de la barra muestra tu **avatar**. Haz clic en él
para abrir un menú con accesos directos:

- **Mis estadísticas**
- **Perfil**
- **Salir**
- y **más opciones**, si tu cuenta tiene permisos adicionales.

---

## 4. Olvidé mi contraseña

No existe un formulario de "olvidé mi contraseña" en la web. La recuperación se hace por Telegram.

Si **vinculaste Telegram** a tu cuenta (lo que ocurre en el registro), haz lo siguiente:

1. Abre la conversación con el bot **mojinho** en Telegram.
2. Envía el comando `/trocarsenha`.
3. Recibes una **nueva contraseña por mensaje privado** en el propio Telegram.

Después, vuelve a la pantalla de inicio de sesión e ingresa con la contraseña nueva.

Si tu cuenta **no tiene Telegram** (cuenta creada por un responsable; consulta la nota de la
sección 2), el restablecimiento de la contraseña lo hace **el responsable que creó la cuenta**.

---

## 5. Encontrar problemas

La búsqueda de problemas está en `/treino/`. **Ver la lista y leer los enunciados no requiere
iniciar sesión**. Tu **progreso personal** y el **envío de soluciones** sí lo requieren.

La página tiene **dos modos**: el **hub** (la puerta de entrada) y la **búsqueda avanzada** (la
lista completa con filtros). Cualquier búsqueda o filtro te lleva del hub a la búsqueda
avanzada automáticamente.

### El hub

- **Búsqueda central:** escribe 2 o más letras y aparecen **sugerencias agrupadas** en Colecciones,
  Etiquetas y Problemas (cada problema ya con su estado ✓/…). Usa las flechas ↑↓ y Enter, o
  haz clic. Enter sin elegir nada abre la búsqueda avanzada con el texto escrito.
- **Accesos directos:** 🎲 **problema aleatorio** (da prioridad a uno que aún no resolviste),
  🌱 **fáciles para empezar**, 🚀 **sin resolver aún** y 🔬 **búsqueda avanzada**.
- **Para ti** (aparece con la sesión iniciada): **▶ Continúa donde lo dejaste** (tu último intento
  aún sin AC) y **🎯 Sugerencia para ti** (un próximo problema).
- **📚 Colecciones destacadas:** un carrusel de tarjetas. Cada tarjeta muestra el tamaño de la colección
  y la **barra de tu progreso**; al hacer clic, la lista se filtra por esa colección. Desplázate con las
  flechas ‹ › (o con el dedo, en el celular). El enlace **todas (N) →** abre la búsqueda avanzada.
- **🔥 Más enviados esta semana:** los 10 problemas con más envíos en los últimos 7 días.

### La búsqueda avanzada

La lista completa, siempre visible, con el **riel de filtros** a la izquierda:

- **Filtrar por título:** escribe parte del nombre.
- **Mi estado** (solo con la sesión iniciada): Todos / Por resolver / ✓ Resueltos / … Intentados.
- **Dificultad:** de muy fácil a difícil, según la **tasa por usuario** de cada problema (¿quien
  lo intenta lo logra? resueltos ÷ intentados: ≥90% muy fácil, ≥70% fácil, ≥50% medio, <50%
  difícil; “nuevo” = todavía sin datos). Es la misma escala de la página de estadísticas del problema, del
  perfil y del sorteo de competencias. Cada opción muestra cuántos problemas quedan con ella.
- **Colecciones:** el árbol con **casillas de selección**. Puedes marcar **varias al mismo
  tiempo** (la lista muestra la **unión**). Marcar un **grupo** (ej.: `obi`) toma todas sus
  colecciones de una vez. El número a la derecha es **tu progreso** (ej.: `20/140`).
- **Etiquetas:** marca todas las que quieras. El problema debe tener **todas** las marcadas. Los
  conteos se **actualizan en vivo** mientras filtras.

Sobre la tabla están los **chips** de los filtros activos (la × los quita uno por uno), el conteo de
resultados y el **orden**: **Más resueltos**, **A–Z**, **Dificultad** y
**Novedades** (los publicados más recientemente primero).

| Columna | Qué muestra |
|---|---|
| **✓** | Si lo resolviste (✓) o lo intentaste (…). Aparece con la sesión iniciada |
| **Problema** | El título, que es el **enlace** para abrir el problema |
| **Colecciones** | Haz clic en una colección para **sumarla** al filtro |
| **Dificultad** | La franja según la tasa por usuario (resueltos ÷ intentados) |
| **Dirt** | Cuánto se falla antes de acertar: la parte de los envíos de quienes resolvieron que estaba equivocada. Alto = el problema castiga los errores. Verde ≤20%, amarillo ≤50%, rojo por encima. |
| **Resueltos** | Cuántos usuarios lo resolvieron / lo intentaron |

La lista viene en **páginas de 50**. Consejo: la **URL guarda tus filtros**. Copia el enlace
para compartir una búsqueda. En el celular, el riel se convierte en el botón **Filtros (n)**.

Para abrir un problema, **haz clic en su título**.

---

## 6. Resolver un problema

Al hacer clic en el título, llegas a la dirección `/treino/problema/?id=<id>`, donde `<id>` es el
código del problema. La pantalla tiene dos partes:

- **A la izquierda:** el **enunciado** del problema.
- **A la derecha:** el panel **Enviar solución**.

En la **parte superior del enunciado** encuentras:

- el(los) **autor(es)** del problema;
- las **colecciones** a las que pertenece;
- las **etiquetas** (empiezan **difuminadas**, con un enlace para **mostrar/ocultar etiquetas**);
- el **tiempo límite por lenguaje**;
- un **botón de estadísticas** del problema;
- el botón **⬇ Ejemplos**, que descarga la entrada y la salida de cada ejemplo como archivos, en un zip.

Cada bloque de ejemplo del enunciado tiene un botón **Copiar** en el título. Un clic copia el bloque
entero, con el salto de línea final.

Cuando el problema tiene el enunciado en más de un idioma, aparecen los chips **PT · EN · ES** encima
del texto. Haz clic para cambiar. El título cambia junto. El MOJ recuerda tu elección para los próximos
problemas. En la lista de problemas, el sello **EN ES** junto al título muestra qué problemas tienen
traducción.

### Cómo enviar tu solución

Necesitas **iniciar sesión** para enviar. En el panel **Enviar solución**:

1. **Elige el lenguaje** en el menú. Cada opción muestra el **tiempo límite** de ese
   lenguaje.
2. Escribe tu código de una de estas dos formas:
   - **Escríbelo en el editor.** El editor (llamado CodeMirror) ya viene con una **plantilla** del
     lenguaje elegido para que empieces.
   - **O envía un archivo** en el campo **o archivo:**.
3. Haz clic en **Enviar solución**. Aparece el mensaje **¡Enviado!**.

El editor tiene algunas comodidades:

- **Pantalla completa:** ocupa toda la ventana.
- **Nueva ventana:** abre un modo solo con el editor.
- **▾ Ocultar editor / ▸ Mostrar editor:** contrae el editor cuando no lo necesitas.

### Seguir el resultado

Justo debajo está el **Historial de envíos**, con estas columnas:

| Columna | Qué muestra |
|---|---|
| **Fecha/Hora** | Cuándo enviaste |
| **Acciones** | Botones rápidos (ver abajo) |
| **Lenguaje** | El lenguaje usado en ese envío |
| **Estado** | El veredicto de la evaluación |

Los botones de la columna **Acciones** son:

- **✎** (editor): vuelve a cargar ese código en el editor.
- **código**: descarga el archivo fuente que enviaste.
- **log**: abre el **informe de la evaluación**.

Mientras el resultado está **pendiente**, aparece un indicador de **carga** y la página se
**actualiza sola** cuando sale el veredicto. No necesitas recargarla a mano.

Debajo del veredicto viene una **línea de resumen**, por ejemplo:

```
Aprobado 3/5 pruebas
```

Los detalles de cada lenguaje y de cómo funcionan la entrada y la salida de los datos están en la página
**Ayuda** del sitio (`/treino/ajuda/`), que también tiene el código inicial de cada lenguaje. El enlace
"📖 Cómo enviar" aparece junto al selector de lenguaje, en el momento del envío.

---

## 7. Perfil

Tu perfil está en `/treino/perfil/`. Está dividido en secciones, y **cada sección tiene
su propio botón para guardar**. Ajusta lo que quieras y guarda sección por sección.

| Sección | Qué ajustas |
|---|---|
| **Datos** | Nombre, universidad y el **editor/IDE favorito** (aparece en el ranking de editores) |
| **Contraseña** | Contraseña actual, nueva contraseña y confirmación de la nueva |
| **Privacidad** | La opción **Perfil público**. Si la **desmarcas**, tus estadísticas quedan **solo para ti** |
| **Foto de perfil** | Subir una imagen, que se recorta a **100x100** |
| **Nombre de usuario** | Cambiar tu handle |

Un cuidado con el cambio de **Nombre de usuario**:

> Cambiar el handle **actualiza todo tu historial** al nombre nuevo. Existe un **límite
> de cambios por año** (el valor por defecto es **2**), y la propia pantalla muestra **cuántos ya
> usaste**.

Esa página es la **edición** del perfil. Lo que ven los demás, tu **perfil público**,
está en `/treino/stat/?user=<tu usuario>` y es el tema de la siguiente sección.

---

## 8. Mis estadísticas

Cada usuario tiene un **perfil público** en `/treino/stat/?user=<login>`. El tuyo se abre desde el
menú del avatar → **📊 Mis estadísticas**; el de los demás, haciendo clic en su nombre (en el
Top 10 de la página de inicio, por ejemplo).

De arriba abajo, el perfil muestra:

- **Encabezado:** foto (o iniciales), universidad, **miembro desde**, editor favorito
  (con su posición en el ranking de editores) y el **último envío**.
- **Tarjetas:** problemas resueltos, envíos, tasa de aceptación, **AC al primer intento**,
  intentos para resolver, **rachas** (días seguidos con envío) y el lenguaje favorito.
- **Gráficos:** evolución de los resueltos en el tiempo, mapa de actividad (26 semanas),
  **ritmo día × hora**, veredictos, desempeño por lenguaje, **dificultad de los
  resueltos**, **progreso por colección**, fortalezas por etiqueta y la lista **Abiertos**
  (problemas que intentaste y aún no resolviste: una excelente cola para volver a entrenar).
- **🏅 Logros:** medallas automáticas: Primer AC, Centurión (100 resueltos),
  rachas, Políglota, colección completa y otras. Las **bloqueadas** aparecen en gris
  con **cuánto falta** (ej.: `82/100`). El catálogo completo y las reglas están en
  [`PERFIL.md`](PERFIL.md).
- **Historial paginado** (25 por página) con **filtros** por problema, veredicto y
  lenguaje, y orden por columna. Los enlaces **código**/**log** solo aparecen para el dueño.

Recuerda: si tu perfil es **privado** (sección 7), todo esto **solo aparece para ti**,
y tu nombre también **sale de las listas públicas** de la página de inicio.

---

## 9. Página de editores

La página `/treino/editores/` reúne las estadísticas de los **editores favoritos** declarados
por los usuarios: un **ranking** y la **distribución** de quién usa qué.

Consejo: ¿quieres aparecer en ese ranking? **Declara tu editor** en la sección **Datos** del
**Perfil** (consulta la sección 7).

---

## 9½. Participación virtual: rehacer una competencia finalizada

Algunas competencias finalizadas tienen el botón **🕹️ Virtual** en la tarjeta (página de inicio y archivo de
competencias). Ese botón abre la **participación virtual**: rehaces la competencia entera, con reloj, contra el
marcador oficial. Los equipos oficiales resuelven los problemas en el mismo minuto en que los resolvieron en la competencia real.

1. **Lee las reglas y marca la casilla de aceptación.** No participes si ya viste los problemas. Haz la competencia entera.
2. Elige **Empezar ahora** o **Programar** (hasta 7 días; puedes cancelar la programación).
3. En la arena: abre un problema, elige el archivo y envíalo. El veredicto aparece en **Mis envíos**.
   El marcador muestra tu fila destacada, con la posición que ocuparías.
4. **Terminar ahora** finaliza antes de tiempo.

**Filtros del marcador.** La barra es la misma del marcador de la competencia: **Marcador** (por ejemplo, solo los equipos
oficiales, sin invitados), **Bandera**, **Universidad**, **Sede** y la búsqueda. Con un filtro activo, el
número grande es la posición en el recorte y el pequeño es la posición general. Tu fila aparece siempre.
**Mis elegidos.** Haz clic en el **📌** de una fila virtual para fijar a esa persona: aparece siempre
en el marcador, con cualquier filtro. El botón **📌 Elegidos** abre la lista: busca por nombre o usuario, marca
y desmarca, o agrega el usuario de alguien que todavía no hizo el virtual de esta competencia. La lista es de tu cuenta y
vale para todas las competencias. Ejemplo de uso: elige a tus amigos, selecciona una **Sede** y mira la
posición de cada uno entre los equipos de esa sede.

El selector **Virtuales** elige entre todos los participantes virtuales, solo los elegidos, solo tú, o ninguno. El filtro de
**Sede** no oculta a los virtuales: así comparas tu resultado con los equipos de esa sede.

**Desistir sin registrar:** el botón **Desistir** existe en los primeros **15 minutos**, o mientras
no tengas **ningún problema aceptado**. Desistir te devuelve el intento, como máximo **2 veces**. Después
de eso, el inicio es definitivo. Terminar el tiempo sin ningún aceptado cuenta como desistir.

**Después:** tu fila queda en el marcador virtual de la competencia, marcada como **virtual**. Cada cuenta hace la
participación virtual de una competencia **una vez**. Los envíos quedan en tu historial del entrenamiento.

Sin iniciar sesión, la misma página muestra el **Replay**: arrastra el control de tiempo para ver el
marcador en cualquier minuto de la competencia.

## 10. Para saber más

- Para los detalles de **cómo enviar en cada lenguaje** y de cómo funcionan la **entrada y
  la salida** de los datos, consulta la página **Ayuda** (`/treino/ajuda/`).
- Para **competir en una competencia** (con plazo y marcador), consulta `MANUAL-CONTEST.md`.

Buenos entrenamientos, y buen código.
