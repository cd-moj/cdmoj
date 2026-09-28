<!-- i18n-source: MANUAL-JUIZ.md blob:17310ea67a9d6457fc517972c95e60ee3a96dfcb -->
# MOJ: Manual de los jueces (.judge y .cjudge)

> **Nota de traducción.** Este manual es una traducción del original en portugués. Las herramientas de línea de comandos (`moj`, `moj-contest`, `moj-comp`) muestran sus mensajes en portugués, y los ejemplos de comandos son idénticos al original.

Este manual es para las personas que evalúan los envíos de una competencia del MOJ desde la interfaz web. Hay dos roles, y cada uno viene del sufijo de tu usuario:

| El usuario termina en | Rol | Qué obtiene |
|---|---|---|
| `.judge` | Juez | Ve la cola de evaluación y trabaja en ella. |
| `.cjudge` | Juez principal | Hereda todo lo del juez y además obtiene un panel del juez principal. |

El juez principal **hereda** todo lo que hace el juez. Es decir, lee la Parte 1 aunque seas `.cjudge`: también vale para ti. La Parte 2 agrega los poderes extra.

## Cuándo vale este manual

Todo lo que se describe aquí solo ocurre cuando la competencia está en modo de **veredicto manual** (la organización activa la opción `MANUAL_VERDICT`). En ese modo, los envíos que marca la tabla **🔎 Qué va a revisión** quedan en una cola a la espera de que un juez los mire antes de que el resultado llegue al competidor. Lo que la tabla no marca sale automático, directo de la máquina — y el error del juez siempre va a la cola.

Sin esa opción activa, la corrección es **automática**: la máquina calcula el veredicto y lo entrega directo al competidor. En ese caso no hay cola y el juez no tiene nada que hacer. Si abres la pestaña de evaluación y está vacía o no aparece, probablemente la competencia no está en veredicto manual.

## Parte 1: `.judge` (juez)

### Pestañas que ves

Como juez, tu barra de navegación tiene estas pestañas:

| Pestaña | Para qué |
|---|---|
| **Competencia** | El enunciado de la competencia y los problemas. |
| **Marcador** | El marcador. |
| **Aclaraciones** | Preguntas y respuestas (aclaraciones). |
| **Evaluar** | Tu cola de evaluación. Aquí es donde trabajas. |
| **Todos los envíos** | El feed completo de la competencia, **anónimo**: ves la hora, el problema, el veredicto crudo, el código y el registro — pero **no** ves el usuario ni el equipo (la API tampoco los revela; quién envió es irrelevante para evaluar). |
| **Estadísticas** | Números de la competencia. |
| **Salir** | Cierra la sesión. |

Una diferencia importante respecto a un competidor: tú, como juez, también ves el **texto crudo** del veredicto que calculó la máquina. El competidor no lo ve.

### La cola de evaluación

La cola está en la pestaña **Evaluar** (URL `/contest/judge/`). Arriba de la página hay cuatro contadores que resumen el estado general:

| Contador | Significa |
|---|---|
| Sin evaluar | Envíos retenidos, todavía sin nadie trabajando en ellos. |
| En evaluación | Alguien ya los tomó y los está evaluando ahora. |
| Esperando el 2.º voto | Ya tienen un voto; falta que el segundo juez coincida. |
| En conflicto | Los dos votos no coincidieron. Solo el juez principal lo resuelve. |

Debajo de los contadores está la lista de los envíos retenidos para revisión. Para cada uno, ves:

- El **problema** al que pertenece el envío.
- El **veredicto calculado**: lo que calculó la máquina (sirve de referencia, no es la decisión final).
- El **estado** del envío en la cola.
- **Quién lo está evaluando** (si ya hay alguien).
- Los **enlaces al registro y a la fuente** (el registro de ejecución y el código enviado).
- La **acción** disponible (por ejemplo, tomarlo para evaluar).

### Flujo de evaluación, paso a paso

1. **Reservar para evaluar** (*Claim to evaluate* en una competencia en inglés)**.** Haz clic para reservar el envío. Como máximo 2 personas pueden estar en el mismo envío, y tu reserva tiene un tiempo límite de 5 minutos. Al reservarlo, la pantalla cambia a un panel estable, que no se recarga solo mientras trabajas (así no pierdes lo que estás haciendo).
2. **Analizar.** En el panel tienes todo a mano: el **veredicto calculado** (la referencia), el **registro** de ejecución, el **código** enviado y un selector de veredicto. Dos botones te ayudan: **+5 min** (pide más tiempo, si los 5 minutos no alcanzan) y **Desistir** (suelta el envío para que otra persona lo tome).
3. **Votar y liberar.** Elige el veredicto en el selector y haz clic para votar. Atención: el **voto es permanente** (no se puede deshacer) y te **libera de inmediato** para tomar la siguiente tarea.

### Dos jueces tienen que coincidir

El competidor solo recibe el veredicto de un envío cuando **N jueces votan lo mismo** — el N lo decide el admin de la competencia (Central › Reglas → "N.º de jueces que validan cada veredicto", de 1 a 5; el valor por defecto es 2). Cuando los votos coinciden, el veredicto va al competidor (la entrega la hace un único escritor, el daemon, para que no haya desorden). Con N=1, tu voto decide por sí solo.

Cuando los dos votos **no coinciden**, el envío pasa a ser un **conflicto** y queda marcado para que lo resuelva el **juez principal**. Un juez común no resuelve conflictos: su parte termina en su voto.

### Calentamiento: tu ensayo

Muchas competencias hacen un **calentamiento** antes de la competencia oficial — misma sala, mismas cuentas, misma
dirección. La cola que aparece ahí es una cola de verdad: llegan envíos, los reservas, votas, y la regla
de N jueces que coinciden vale igual. Úsalo para comprobar lo que duele descubrir después: si las
**opciones de veredicto** son las que quiere esta competencia, si el **registro** y el **código** se abren en tu
máquina, y si tú y el otro juez leen el mismo envío de la misma manera.

> **No dejes la cola del calentamiento a medias.** La promoción a la competencia oficial se **rechaza**
> mientras haya un envío sin veredicto liberado — antes de dejar que la organización cambie de ronda,
> el servidor comprueba si la ronda terminó, si hay un trabajo en curso en el juez, si hay un elemento en la
> corrección manual sin veredicto, si hay un veredicto pendiente en el historial y si el daemon está vivo.
> Una cola de calentamiento abandonada literalmente retiene el inicio de la competencia. Termina lo que reservaste.

Cuando la ronda se promueve, todo lo del calentamiento se archiva: la cola, los envíos, las aclaraciones y
el marcador. La competencia oficial empieza con el historial vacío — nada de lo que evaluaste ahí cuenta ni
se filtra a la competencia.

### Resumen de lo que puede el juez

| Puede | No puede |
|---|---|
| Ver la cola de evaluación y los contadores. | Resolver conflictos. |
| Tomar y reservar envíos (máx. 2 por envío, 5 min). | Liberar un veredicto sin los dos votos. |
| Ver la referencia, el registro y el código, y votar. | Editar la lista de veredictos o lo que va a revisión. |
| Pedir +5 min o desistir. | Ver el panel del juez principal. |
| Ver el texto crudo del veredicto. | Entrar a la administración, los equipos o los usuarios. |
| Ver el resultado del **jplag** (pares solo con el usuario; sin el nombre del equipo). | Ejecutar el jplag. |

## Parte 2: `.cjudge` (juez principal)

El juez principal hace **todo lo que hace el juez**: reserva envíos, vota, participa en la regla de los dos votos, todo igual que en la Parte 1. Además, obtiene un panel del juez principal y algunos poderes extra.

### Pestañas adicionales

Además de las pestañas del juez, el juez principal ve:

| Pestaña | Para qué |
|---|---|
| **Juez principal** | El panel del juez principal (detallado abajo). |
| **Todos los envíos** | La lista completa **con usuario y equipo** (el juez común la ve anónima), con el veredicto crudo. |

### El panel del juez principal

El panel está en `/contest/chief/` y tiene estas pestañas:

1. **📊 Situación.** Muestra tarjetas de resumen, la **cola completa** (con filtros y con los votos de los otros jueces) y una tabla **"📈 Desempeño por juez"** con: votos emitidos, tiempo medio entre reservar y votar, coincidencias y conflictos. Cada fila de la cola trae un botón **Decidir/Resolver**, que libera el veredicto **de inmediato**, sin esperar los dos votos (esa decisión queda registrada).
2. **⚖️ Conflictos.** Lista los envíos en conflicto, con los **dos votos** que no coincidieron, el registro y la fuente, y un botón para resolver cada uno.
3. **🏷️ Opciones.** Edita la lista de veredictos que los jueces eligen al votar. Cada opción tiene tres campos. El primero es el texto que ve el juez. El segundo es la clase: una de las seis clases canónicas (Accepted, Wrong Answer, Time Limit Exceeded, Memory Limit Exceeded, Runtime Error, Compilation Error). La clase define la puntuación, la penalización y el color en el marcador. El tercero es el texto que ve el equipo. Deja el tercer campo vacío para mostrar la clase. La clase Accepted no tiene texto propio.
4. **🔎 Qué revisar.** Una tabla: cada fila es un problema (letra y título), cada columna un veredicto (AC, WA, TLE, MLE, RTE, CE). **Marca lo que revisan los jueces**; lo que no esté marcado sale automático, directo de la máquina. Sin nada marcado, todo sale automático (solo el error del juez va a la cola). La fila "Todos los problemas" marca o desmarca una columna entera, y la casilla al lado de cada problema marca o desmarca la fila; **Revisar todo** y **Nada en revisión** actúan sobre toda la tabla. Un uso común: dejar CE automático (no necesita evaluación y atasca la cola al principio) y revisar TLE. Las **excepciones por lenguaje** (plegadas) valen para un lenguaje y vencen a la tabla — por ejemplo, "Python · TLE · va a revisión" con el TLE automático en la tabla. Si cambias la tabla a mitad de la competencia y hay envíos ya retenidos que ahora saldrían automáticos (sin voto y sin conflicto), la pantalla ofrece **Liberar ahora**; no los libera sola.
5. **🌐 Idiomas.** Decide los idiomas del enunciado que el acordeón ofrece al competidor. **Automático** (valor por defecto): cada problema ofrece todos los idiomas que tiene. **Solo estos idiomas**: marca la lista (portugués, inglés, español); solo PT = competencia solo en portugués. La tabla muestra, por problema, qué traducciones existen. Un idioma ofrecido sin traducción en un problema muestra el portugués en ese problema. El admin tiene el mismo panel en Competencia › Problemas.

### Alerta de conflicto

En **cualquier página de la competencia**, el juez principal recibe un **aviso rojo parpadeante (con sonido)** cada vez que surge un conflicto nuevo. Al hacer clic en el aviso vas directo a la pestaña **⚖️ Conflictos**. Así notas el conflicto aunque estés en otra pantalla.

### Otros poderes del juez principal

- Ver **Todos los envíos** con usuario y equipo (el juez común la ve anónima), con el veredicto crudo.
- Responder **aclaraciones**. Reserva la pregunta antes de responder. Ves quién preguntó: el usuario y el nombre (el juez común no lo ve). Nadie reserva una pregunta que otro juez ya reservó. Los saltos de línea en la pregunta y en la respuesta se conservan.
- Editar las **respuestas y noticias** de la competencia.

### Calentamiento: lo que solo el juez principal comprueba

El calentamiento es el único momento en que toda la mesa trabaja con envíos de verdad y sin nada en
juego. Ahí es donde compruebas lo que solo tú cambias: **cuántos jueces** exige un veredicto, qué
veredictos van a **revisión** (el resto sale solo), y si la **alarma de conflicto** de verdad
te llega. Un conflicto que nadie ve en el calentamiento es un conflicto que nadie verá en la competencia.

También es donde ves cómo se vacía la cola — porque la promoción a la competencia oficial se **rechaza**
mientras haya un elemento sin veredicto liberado, un trabajo en curso o un veredicto pendiente. La pestaña **📊
Situación** del panel es la pantalla que dice cuándo la mesa está lo bastante limpia para que la organización
cambie de ronda.

> ⚠ **En la promoción, los documentos pierden la marca de publicado.** Las plantillas y la portada se conservan
> (son configuración) y los PDF generados para el calentamiento van al archivo de la ronda — pero lo
> que estaba publicado deja de estarlo. El info sheet, el cuadernillo y la hoja de time limits tienen que
> **publicarse de nuevo** para la competencia oficial, o los equipos abren *Archivos y Recursos* y no
> encuentran nada.

### Lo que el juez principal NO es

El juez principal **no** es administrador completo. No tiene:

- la pestaña de **Administración**,
- la **configuración** de la competencia,
- la gestión de **equipos** o de **usuarios**.

Sus poderes se limitan a: evaluación, veredictos, noticias/respuestas, estadísticas y el **jplag** (ejecutarlo y ver los pares con el nombre del equipo).

### Resumen de lo que puede el juez principal

| Puede (además de todo lo que puede el juez) | No puede |
|---|---|
| Ver el panel 📊 Situación y el desempeño por juez. | Ser admin completo. |
| **Decidir/Resolver** liberando el veredicto de inmediato (queda registrado). | Abrir la pestaña de Administración. |
| Resolver **conflictos**. | |
| **Ejecutar el jplag** y ver los pares con el nombre del equipo (enlace `jplag` en la barra). | |
| Editar la lista de veredictos (🏷️ Opciones). | Cambiar la configuración de la competencia. |
| Editar **lo que va a revisión** (tabla problema x veredicto + excepciones por lenguaje). | Gestionar equipos o usuarios. |
| Ver **Todos los envíos** con usuario/equipo y veredicto crudo. | |
| Responder aclaraciones. Resérvalas antes. Ves quién preguntó (usuario y nombre). | Reservar una pregunta que otro juez ya reservó. |
| Editar respuestas y noticias. | |
| Recibir la alerta parpadeante de conflicto en cualquier página. | |

## Para saber más

- Para la visión de quien compite, consulta `MANUAL-CONTEST.md`.
- Para el personal de sala, consulta `MANUAL-STAFF.md`.

## Tutorial web con capturas de pantalla

Las pantallas de este manual, paso a paso y con imágenes (texto en PT/EN/ES; las pantallas de las capturas están en inglés), están en
`/contest/ajuda/judge.html` y `/contest/ajuda/cjudge.html` — el botón
**📖 Cómo funciona este rol** en tu pantalla los abre directamente.
