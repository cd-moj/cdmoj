<!-- i18n-source: MANUAL-CONTEST.md blob:2f6045baa00570d0ac79353f486f9ec1c061b516 -->
# MOJ: Manual del competidor (competencia)

> **Nota de traducción.** Este manual es una traducción del original en portugués. Las herramientas de línea de comandos (`moj`, `moj-contest`, `moj-comp`) muestran sus mensajes en portugués, y los ejemplos de comandos son idénticos al original.

> **¿Tú ORGANIZAS la competencia?** La guía del organizador (crear y gestionar competencias, web y
> CLI) es otra: [/treino/criar/tutorial.html](/treino/criar/tutorial.html). Este manual es el que
> entregas a los competidores.

Este manual es para ti, que vas a participar en una maratón o competencia en el MOJ (el juez en línea). Aquí aprendes a entrar a la competencia, enviar tus soluciones, leer el marcador, hacer preguntas (aclaraciones), pedir impresiones y usar el respaldo.

> **¿Prefieres ver las pantallas?** El **tutorial web con capturas de pantalla** (PT/EN/ES) es
> [/contest/ajuda/competidor.html](/contest/ajuda/competidor.html): la versión corta e ilustrada
> de este manual. Muestra el acordeón del problema, el envío, el color cuando aciertas, la
> notificación de aclaración y cómo se lee el marcador. Se abre con el botón **📖 Cómo funciona la
> competencia**, en tu tarjeta, en la parte superior de la página de la competencia. Los otros roles
> (personal de sala, pantalla, juez) tienen el suyo en [/contest/ajuda/](/contest/ajuda/).

> **¿Prefieres la terminal?** (En una competencia con gate de navegador por sede, la CLI solo entra
> **en la máquina de la competencia**: lee el User-Agent de la imagen en `/etc/moj/user-agent` y lo
> envía junto con el suyo. Web y CLI en la misma máquina son la misma sesión-máquina.) Existe la CLI
> del competidor, **`moj-comp`**. Envía soluciones, sigue veredictos y marcador, y tiene el modo de
> emergencia para **caída de Internet** (el envío queda guardado cifrado con la hora y cuenta
> correctamente cuando la red vuelve). Guía completa: [/contest/cli.html](/contest/cli.html).
> **No siempre está habilitada**: si vale o no en esa competencia lo decide la organización del
> evento, y esa información viene de ella. No supongas que está activada.

Si solo quieres saber cómo enviar en cada lenguaje y cómo funcionan la entrada y la salida de los programas, consulta la página **Ayuda** (`/treino/ajuda/`). Se abre **desde dentro de la competencia**, con el enlace **"📖 Cómo enviar"** que está junto al selector de lenguaje, al momento de enviar.

## 1. Antes que nada: la inscripción

Buena parte de las competencias del MOJ usa las **cuentas del Entrenamiento libre**: compites con el
mismo usuario y la misma contraseña que usas para entrenar. En esas competencias, **entrar exige
inscripción previa**. Si intentas iniciar sesión sin estar inscrito, recibes un aviso. Cuando todavía es posible inscribirse, el aviso trae el enlace a la página de inscripción.
El servidor muestra uno de estos avisos, en portugués:
`Você não está inscrito neste contest…` (no estás inscrito en esta competencia),
`As inscrições deste contest ainda não abriram` (las inscripciones de esta competencia todavía no
abrieron) o `As inscrições deste contest estão encerradas` (las inscripciones de esta competencia
están cerradas).

La inscripción está en el **sitio principal**, no en la dirección de la competencia:
`/contests/inscricao/?c=<id>` (el subdominio de la competencia no ve tu sesión del entrenamiento;
por eso son direcciones diferentes).

**Individual o en equipo.** Eliges el modo en la inscripción, y esa elección es **definitiva** para
ti: para cambiarla después, habla con la organización. En equipo:

- alguien **crea** el equipo e invita a los demás por su usuario del entrenamiento (cada invitado
  recibe un aviso del bot en Telegram, si lo tiene vinculado);
- el equipo tiene un límite de integrantes (normalmente 3);
- **cada persona entra con su propia contraseña del entrenamiento**: la competencia es del equipo,
  pero el MOJ registra quién estaba en el teclado en cada envío.

**Lo que el equipo (o tú, si compites solo) declara**: la universidad (la sigla que aparece en el
marcador), la bandera, si va a usar **IA** durante la competencia (se convierte en el 🤖 en el
marcador) y, en el caso de equipo, la **foto** que aparece en la pantalla cuando resuelven un problema.

> **El calentamiento también exige inscripción.** Por defecto, la inscripción vale para *todas* las
> rondas de la competencia, incluido el calentamiento. La ventana de inscripción está anclada a la
> **competencia oficial**, así que puede cerrar antes de que termine el calentamiento. No lo dejes
> para el último día.

## 2. Entrar a la competencia

Accedes a la competencia por un enlace con el formato `/contest/?c=<id>` (o por un subdominio que informe la organización). Cambia `<id>` por el identificador de tu competencia.

Antes de iniciar sesión, ya ves:

- El nombre de la competencia.
- Los horarios de **Inicio** y **Fin**.

Lo que aparece después depende del momento:

| Situación | Lo que ves |
|---|---|
| El inicio de sesión todavía no abrió | Una **cuenta regresiva** con "Abre en HH:MM:SS". La página se actualiza sola: si la organización pospone o adelanta la apertura, el cambio aparece en el momento. |
| El inicio de sesión abrió | Una tarjeta de inicio de sesión con los campos **Usuario** y **Contraseña** y el botón **Iniciar sesión**. |

El idioma de la pantalla lo define la competencia y puede estar en portugués, inglés o español.

Cuando la organización abre el inicio de sesión **antes** del inicio de la competencia, entras y ves
la pantalla "La competencia todavía no empezó", con una cuenta regresiva. No hace falta recargar la
página: los problemas aparecen solos cuando empieza la competencia.

> **En una competencia con el formato de la Maratona SBC / ICPC, no entras antes del inicio.** La
> apertura del inicio de sesión está programada para el minuto del comienzo. Hasta entonces, la
> pantalla tiene cuenta regresiva y **ningún formulario**, y eso no es un defecto. Tampoco sirve
> intentar desde tu computadora portátil: la competencia corre en la máquina que preparó la
> organización, y la verificación de navegador rechaza las otras. El lugar para probar todo es el
> **calentamiento** (sección 3).

## 3. Página principal (después de iniciar sesión)

En la parte superior hay una barra con:

- El nombre de la competencia.
- Una cuenta regresiva: "Termina en: HH:MM:SS" y, cuando el tiempo se acaba, "Competencia terminada".
  El **horario de fin viene del servidor**, pero quien hace la cuenta es el reloj de tu máquina:
  en una computadora con la hora equivocada, la cuenta también sale equivocada. Quien decide es el
  servidor: un envío que llega después del fin no cuenta, diga lo que diga tu pantalla.
- El botón **Salir**.

Justo debajo hay un menú de navegación con **Competencia**, **Marcador**, **Aclaraciones** y, a veces, **Respaldo** e **Impresión**.

Un **aviso** en la parte superior indica cuando hay "noticias nuevas" y "aclaraciones respondidas". Parpadea cuando una pregunta tuya fue respondida y todavía no la leíste.

Si la competencia tiene un **calentamiento** (ronda de ensayo antes de la competencia oficial), una
franja fija avisa en la parte superior: *"🔁 CALENTAMIENTO — esta ronda sirve para probar el entorno
y tu cuenta: su marcador NO es el de la competencia"*. Como **no entras antes de que empiece la
competencia**, el calentamiento es tu única oportunidad de ver estas pantallas con calma. Vale la
pena usarlo completo:

1. **entra** con la credencial que recibiste (una etiqueta que no inicia sesión es un problema para
   resolver ahí, no en el minuto 3 de la competencia);
2. **abre un problema** y mira qué pantalla tienes: enunciado + editor, solo el enunciado, o solo
   el límite de tiempo (competencia que distribuye solo el cuadernillo en PDF);
3. **envía una solución a propósito** (incluso una equivocada) y sigue el veredicto hasta el final;
4. **envía una aclaración**, **pide una impresión** y **guarda un archivo en el respaldo**;
5. **mira el marcador** y encuentra tu fila.

Si algo te parece extraño, avisa al personal ahí mismo.

Cuando el calentamiento termina, la organización pone la competencia
oficial en línea **en la misma dirección, con el mismo usuario**: el marcador vuelve a cero y los
problemas cambian. El marcador y tus envíos del calentamiento siguen disponibles (enlace **Rondas
terminadas** en *Archivos y Recursos*), cuando la organización los publica.

Cuando existen, también aparecen las secciones **Información y noticias** y **Archivos y Recursos**.
En **Archivos y Recursos**, la organización publica los documentos de la competencia cuando quiere
que los tengas a mano. Son hasta cuatro: el **Entorno de evaluación** (sistema, versiones de
compilador, límites, líneas de compilación y ejecución, veredictos y penalización), el **Cuadernillo
de problemas**, la hoja de **Límites de tiempo** y el
**Editorial** (las soluciones; este solo aparece después de que la competencia termina para *todas* las sedes).

Cada documento es una fila con el nombre a la izquierda y los **idiomas como botones**: `PT`, `EN`, `ES`.
El nombre no es clicable: haz clic en el idioma que quieres. El cuadernillo y la hoja de límites de
tiempo solo se abren **a partir del inicio de la competencia**, aunque ya aparezcan en la lista. Si la
organización no publicó nada, la sección ni siquiera aparece.

### La lista de problemas

La lista de problemas es un acordeón. Cada fila tiene:

- Un **triángulo** para abrir y cerrar el problema.
- Un **globo** que se colorea cuando resuelves ese problema.
- El nombre corto y el nombre completo del problema.
- A la derecha, los enlaces del enunciado (**Enunciado**, **HTML**, **PDF**), el enlace **Ejemplos**
  (descarga la entrada y la salida de cada ejemplo como archivos, en un zip) y un **envío rápido** por archivo.

Cada bloque de ejemplo del enunciado tiene un botón **Copiar** en el título. Un clic copia el bloque
completo, con el salto de línea final. En la CLI, `moj-comp fetch` guarda los ejemplos de todos los
problemas en la carpeta `samples/` del kit.

Al abrir un problema, la primera línea es el **límite de tiempo**, un chip por lenguaje (los más
lentos reciben más tiempo, medido en la máquina del juez). Después viene el enunciado y, si la
organización habilitó el editor, el editor al lado, con las opciones **Lado a lado**, **Solo enunciado** y **Solo editor**.

> **Enunciado en más de un idioma.** Cuando la organización ofrece el enunciado en otros
> idiomas, aparecen los chips **PT · EN · ES** encima del enunciado. Haz clic para cambiar. El cambio
> vale para todos los problemas de la competencia, y el MOJ recuerda tu elección. Los enlaces **HTML** y
> **PDF** se abren en el idioma elegido. Un problema sin traducción muestra el texto en portugués.
El MOJ recuerda tu elección en el próximo problema que abras. Abrir un problema no cierra los
otros: puedes dejar dos abiertos al mismo tiempo.

> **Competencia solo con PDF.** Muchas competencias entregan solo el cuadernillo en PDF, sin versión
> HTML. Ahí la fila tiene solo el enlace **PDF** y el acordeón se abre con el **límite de tiempo** (y
> el editor, si lo hay) y nada más. No es una pantalla rota: el enunciado está en el PDF.

> **El editor del navegador no siempre existe.** Es una comodidad, no una regla, y la organización
> puede desactivarlo. **En la Maratona SBC está desactivado.** En ese caso escribes en un editor de
> la propia máquina, compilas en la terminal y envías el archivo con el selector de la fila del
> problema. La imagen de la competencia viene preparada: en **Maratona Linux** hay Vim, Emacs,
> VS Code, CLion y PyCharm, con compiladores y depurador listos. Descubre cuál de las dos pantallas
> tienes **en el calentamiento**.

Para enviar una solución:

1. Elige el **lenguaje**.
2. Escribe el código en el editor o envía un **archivo**.
3. Haz clic en **Enviar solución**.

> **Lo que el MOJ acepta.** La extensión del archivo tiene que ser de un lenguaje que la plataforma
> ejecuta y, si el problema restringe los lenguajes, de uno de los permitidos ahí. Si envías un
> binario compilado (`.exe`), un PDF o un `.zip`, se rechaza **en el momento**, con la lista de lo
> que acepta ese problema: ningún juez del mundo ejecuta un `.exe`, y antes ese envío entraba en la
> cola y quedaba pendiente para siempre. El tamaño del código está limitado a **1 MB**.
>
> Si la respuesta es un error en lugar de "✓ ¡Enviado!", **lee el mensaje**: dice exactamente qué
> pasó. Un envío solo se acepta cuando el servidor lo confirma; no existe "se perdió en el camino".

## 4. Mis envíos

La tabla está al final de la página de la competencia y también tiene una **página propia**: el botón
**Mis envíos** de la barra abre `/contest/submissions/`, solo con la tabla, el filtro por
problema y el orden por columna. La lista se actualiza sola mientras hay un veredicto pendiente.

Justo debajo de la lista de problemas hay un filtro por problema y una tabla con tus envíos. Las columnas son:

| Columna | Lo que muestra |
|---|---|
| Tiempo | Minutos desde el inicio de la competencia. |
| Problema | Qué problema enviaste. |
| Archivo | El nombre del archivo; el enlace **cód** descarga tu código fuente. |
| Resultado | El veredicto de la evaluación. |
| Fecha | Cuándo se hizo el envío. |
| Log | Aparece cuando ver el registro está habilitado; abre el informe de la evaluación. |

Ves **siempre el veredicto canónico** (sin la puntuación incluida), con una línea de resumen según el modo de la competencia. Mientras haya algún envío pendiente, la lista se actualiza sola.

La columna (o enlace) **Log** abre el informe de la evaluación. En competencias en modo **ICPC**, el registro suele estar oculto por defecto, para evitar que se filtren los casos de prueba, y la organización puede activar o desactivar esa opción.

## 5. Marcador (`/contest/score/?c=<id>`)

> **Antes de que empiece la competencia**, el marcador es una **vitrina**: muestra los equipos
> inscritos y nada más, sin ninguna columna de problema. Es a propósito: cuántos problemas tiene la
> competencia también es una sorpresa.

El marcador se actualiza solo y anima a quien sube y a quien baja. Tiene:

- Una barra de **filtros**: qué marcador (cuando la competencia tiene cohortes: *oficial* × *invitados*,
  o *equipos* × *individual*), bandera, universidad, sede y una **búsqueda** por equipo, universidad
  o usuario. Filtrar **no renumera** a nadie: las posiciones siguen siendo las del marcador completo, y
  un contador muestra cuántas filas quedaron.
- Casillas para **desactivar la animación** y para el modo **Anónimo** (la competencia puede dejarlo
  activado a la fuerza; en ese caso no puedes desmarcarlo).

En el modo **ICPC**, las columnas son: posición, bandera, equipo, una columna por problema, **Total** y **Pen.** (la suma de las penalizaciones, que es el primer criterio de desempate). En la celda del equipo puede aparecer 🤖 (el equipo declaró uso de IA en la inscripción). En cada celda de problema:

| Celda | Significado |
|---|---|
| En blanco | No intentaste ese problema. |
| `1/12` en el **color del globo** del problema | Resuelto en el 1.er intento, en el minuto 12 de la competencia. |
| `2/45` en el color del globo | Resuelto en el 2.º intento, en el minuto 45: el primero estaba equivocado. |
| Con **★** y un anillo alrededor | Fuiste el primero en resolver ese problema (el menor minuto entre los equipos de ese marcador). |
| `2/-` en celda naranja | Lo intentaste y todavía no lo resolviste. Un intento nunca recibe el color del globo. |

El color de cada columna es el del globo de ese problema, y la mayoría de las competencias usa la
**paleta oficial del ICPC** en el orden de las letras: A blanco, B negro, C rojo, D bordó, E amarillo,
F verde, G azul, H azul marino. Una mirada a tu fila ya dice qué globos tienes.
Algunas competencias prefieren mostrar la celda en un verde neutro con un puntito de color en lugar
de pintarla: es la misma información, por elección de la organización. En los dos estilos, la A blanca
y la B negra reciben un contorno fino; sin él, una celda blanca en una tabla blanca no se vería. En
el celular, la celda se convierte en ✓/✗ con los números en el `title`, por la misma razón.

En el modo **OBI**, cada problema muestra los **puntos** obtenidos.

Durante el **congelamiento (freeze)**, ves el marcador congelado, igual que todos, y una franja en la
parte superior dice **desde cuándo**. Todos ven la clasificación como estaba en ese minuto, y nadie
sabe el orden real hasta la ceremonia. Tus envíos se siguen evaluando con normalidad: lo que se
congela es la **visualización**, no la competencia. El AC que obtengas después del freeze está en tu
lista de envíos y no está en la columna del marcador. Sigue resolviendo.

En el modo **anónimo**, el marcador se convierte en una vista agregada, sin nombres.

Algunas competencias tienen **equipos invitados** (extraoficiales). Si eres uno de ellos, una franja
avisa en la parte superior del marcador: apareces en él, pero fuera de la clasificación oficial. Tu fila
viene marcada como **invitado** y sin número de posición. El marcador que ves incluye a los equipos
oficiales; el marcador de los equipos oficiales no incluye a los invitados hasta que la organización libera los resultados.

Si la competencia es secreta y no iniciaste sesión, tienes que entrar para poder ver el marcador.

## 6. Aclaraciones (`/contest/clarification/?c=<id>`)

> **Solo durante la competencia.** Antes del inicio y después del fin, el MOJ no acepta preguntas de
> equipos. La API responde en portugués: `A competição ainda não começou` (la competencia todavía no
> empezó) o `A competição já terminou` (la competencia ya terminó). Una sede con tiempo prorrogado
> puede seguir enviando preguntas hasta su propio fin.

Una aclaración es una pregunta a los jueces sobre un problema. Necesitas haber iniciado sesión.

Para hacer una pregunta:

1. Elige el **problema**. Para una duda general, elige **General**.
2. Escribe la pregunta. Sé específico. *"En el B, ¿el laberinto puede tener más de una salida?"* tiene
   respuesta. *"No entendí el B"* no la tiene.
3. Haz clic en **Enviar pregunta**.

Los saltos de línea de la pregunta y de la respuesta se conservan.

Los jueces no ven quién preguntó. El juez principal y el administrador ven tu usuario y tu nombre.
El informe público de la competencia no muestra quién preguntó.

La página tiene dos secciones:

- **Tus preguntas**. Cada pregunta muestra **P:** (pregunta) y **R:** (respuesta). Una pregunta
  sin respuesta queda arriba.
- **Respuestas públicas y avisos**. Aquí están los **avisos oficiales** de la organización y las
  respuestas públicas a preguntas de otros equipos. Cuando una duda le sirve a toda la sala, el juez
  publica la respuesta para todos. Por eso la lista tiene respuestas que no pediste.

La página se actualiza sola cada 30 segundos. Puedes filtrar por problema.

El aviso en la parte superior de la página principal indica cuando una pregunta tuya fue respondida.

## 7. Impresión (`/contest/print/?c=<id>`)

La impresión solo aparece cuando existe personal de impresión y la organización habilitó el recurso.

Para pedir una impresión:

1. Elige un **archivo** (PDF, imagen, texto o código, hasta 10 MB).
2. Haz clic en **Solicitar impresión**.

Sale una portada con el nombre de tu equipo y un número de referencia. El personal de tu sede imprime y **te la entrega en mano**.

El código fuente sale en **fuente monoespaciada, con tu indentación y las líneas numeradas**, y **cada
página repite el usuario de tu equipo** y el nombre del archivo: una hoja que se separa del montón
todavía encuentra el camino de vuelta a tu mesa.

En **Mis solicitudes** sigues el estado de cada solicitud: pendiente, procesada o entregada.

## 8. Respaldo (`/contest/backup/?c=<id>`)

> **Guardar solo durante la competencia.** Antes del inicio y después del fin, el MOJ no guarda archivos
> nuevos. Sigues viendo, descargando y borrando los archivos que ya guardaste.

El respaldo es un espacio privado para que guardes versiones de tus soluciones.

- **No cuenta como envío** y solo tú ves lo que está ahí.
- Subes un archivo (hasta 10 MB) y puedes descargarlo o borrarlo cuando quieras.
- **No es automático**: lo que no subas no está guardado. Es el cajón para la versión que
  funcionaba antes de que reescribieras todo, y para la máquina que decide morir en el
  minuto 150. Para descargar de nuevo la solución **enviada**, usa el enlace `cód` de la lista de
  envíos: son cosas diferentes.

El respaldo aparece a menos que la organización lo desactive.

## Para saber más

Cómo enviar en cada lenguaje y cómo funcionan la entrada y la salida de los programas está en la página **Ayuda** (`/treino/ajuda/`), que se abre desde dentro de la competencia con el enlace "📖 Cómo enviar", junto al selector de lenguaje.
