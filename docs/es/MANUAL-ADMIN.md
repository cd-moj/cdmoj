<!-- i18n-source: MANUAL-ADMIN.md blob:8672804f448e9d790bec4e4ce45319c584530e16 -->
# MOJ: Manual del organizador (el panel .admin de la competencia)

> **Nota de traducción.** Este manual es una traducción del original en portugués. Las herramientas de línea de comandos (`moj`, `moj-contest`, `moj-comp`) muestran sus mensajes en portugués, y los ejemplos de comandos son idénticos al original.

Este manual es para quien **opera** una competencia: el dueño de la cuenta `.admin`. Explica cada pestaña
del panel de administración, cada opción de configuración, **cómo habilitar los roles especiales**
(`.judge`, `.cjudge`, `.staff`, `.cstaff`, `.mon`) y cómo activar la **corrección validada por
jueces**, incluida la cantidad de personas que necesitas.

> Crear la competencia (asistente, problemas, cuentas) es la otra guía: el
> [tutorial del organizador](/treino/criar/tutorial.html). Aquí se trata la OPERACIÓN, la del día de la competencia.

Llegas al panel al iniciar sesión con la cuenta `.admin` de la competencia y hacer clic en **Administración**
en la barra superior.

## 1. El panel: la Central, los grupos y los MÓDULOS

El panel abre en **🏁 Central**. La barra superior tiene los **cuatro grupos comunes**, que toda competencia
tiene, y, después de un separador, los **grupos de evento**, que solo aparecen cuando la competencia activa el
**módulo** correspondiente (sección 1½). Cada grupo tiene sus paneles en la segunda línea. La dirección
guarda el panel (`#grupo/painel`), así que puedes guardar el enlace. Los enlaces antiguos (`#settings`,
`#users`, `#machines`, `#prova/rodadas`…) siguen funcionando: se redirigen. Un enlace a un
panel de un módulo **desactivado** lleva a **Central › Módulos**, con un aviso que dice qué módulo activar.

```
[🏁 Central] [🧩 Competencia] [👥 Personas] [🎛️ Operación] │ [🏟️ Evento] [🖥️ Máquinas]        📖 Manual
                                                            └── solo con módulo activado ──┘
```

| Grupo | Paneles | Aparece |
|---|---|---|
| **🏁 Central** | Central · **Módulos** · Reglas | siempre |
| **🧩 Competencia** | Problemas · Esqueletos (`esqueletos`) · **Informe** | siempre (Esqueletos solo con el módulo) |
| **👥 Personas** | Cuentas · Inscripciones (`inscricoes`) · Sesiones | siempre (Inscripciones solo con el módulo) |
| **🎛️ Operación** | Situación · Staff · Jueces · Auditoría | siempre |
| **🏟️ Evento** | Rondas (`rodadas`) · Documentos (`documentos`) · Globos (`baloes`) · Clasificación (`classificacao`) · Equipos (`sedes` o `telao`) · Cohortes (`coortes`) · Sedes y escuelas (`sedes`) | con el módulo entre paréntesis |
| **🖥️ Máquinas** | Gate y bloqueo · Anomalías · mlinux | con el módulo `maquinas` |

### 🏁 Central: lo que falta y lo que hay que generar

| Bloque | Qué hace |
|---|---|
| **🚦 Antes de empezar** | El checklist previo a la competencia (verde/amarillo/rojo), con un **botón que abre el panel exacto** de cada pendiente. El rojo es **crítico**: revísalo antes de empezar. El checklist es un aviso: el MOJ no impide el inicio de sesión ni los envíos por su causa; los ítems ya revisados quedan plegados. Revisa la ventana, el registro de evaluación, el congelamiento, los jueces, los lenguajes, el TL calibrado, el pool, las cuentas, el staff y el daemon, y si **cada juez ya calibró cada problema** (*Jueces calentados*): el tiempo límite se mide por máquina, y el juez que todavía no calibró un problema lo hace en el 1.er envío de ese problema, que espera minutos. Cuando hay un juez frío, el ítem trae el botón **🔥 Calentar jueces**, que manda calibrar solo a los jueces fríos. Hazlo **antes del inicio** (cada calibración ocupa un lugar del juez por algunos minutos) y vuelve a ejecutar el checklist (↻) para ver cómo "calentando" pasa a "calentados". Además, **solo con el módulo activado**: cohortes, gate de navegador, bloqueo de sede, ronda siguiente, documentos, globos y prórroga. La revisión **módulos** avisa cuando un módulo está desactivado pero tiene datos en la competencia. |
| **🧰 Generar** | Una tarjeta por artefacto, con el estado actual: etiquetas de credenciales, informe de la competencia y jplag siempre (el jplag también abre para el juez principal, que puede ejecutarlo, y para el juez, que solo lo ve); documentos (`documentos`), promover ronda (`rodadas`), ceremonia de revelación y pantalla (`telao`) con el módulo. |
| **📡 En vivo** | Resumen corto (pendientes, envíos, jueces en línea, respuesta p95, corrección manual). Se actualiza solo; el panel completo es **Operación › Situación**. |
| **⏱️ Reglas de la competencia** | Inicio, fin y congelamiento, editables ahí mismo; el modo y los lenguajes, en solo lectura; y los **módulos activados** (con un atajo para activarlos/desactivarlos). El resto está en **Central › Reglas**. |

| Panel | Qué hace |
|---|---|
| **Central › Módulos** | Activa y desactiva los módulos de la competencia (sección 1½): una tarjeta por módulo, con lo que abre y si ya hay datos suyos en la competencia; ajustes predefinidos (examen de curso · examen de curso con Maratona Linux · selectiva · Maratona). |
| **Central › Reglas** | **Todas** las opciones de la competencia, en cinco secciones plegables (identidad y ventana · lo que el equipo ve · evaluación · marcador/congelamiento/penalización · acceso). La sección 2 explica opción por opción. La ⏱ prórroga por sede está en **Evento › Sedes y escuelas**. |

### 🧩 Competencia: el contenido

| Panel | Qué hace |
|---|---|
| **Problemas** | La competencia en sí: renombrar/reordenar/quitar, **editar el identificador** (la "letra": puede ser `W1`, `Q`…; reordenar conserva el identificador personalizado y el color del globo se mueve con él), restringir lenguajes o el pool de jueces POR problema, actualizar el enunciado desde el banco (o enviar HTML/PDF, **por idioma**), el panel **🌐 Idiomas del enunciado** (abajo) y **🏦 Agregar del banco** (búsqueda y sorteo). |
| **Informe** | El informe estático de la competencia en un solo lugar: descargar el `tar.gz` navegable, **publicar como histórico** en `/relatorio/<contest>/` (republicar, despublicar) y publicar el informe de cada ronda archivada. La sección 6½ lo explica. |

**🌐 Idiomas del enunciado.** Un problema del banco puede tener el enunciado en portugués, inglés y
español (el autor escribe `docs/enunciado.en.md` y `docs/enunciado.es.md` en el paquete). El panel
**🌐 Idiomas del enunciado** (Competencia › Problemas; el juez principal tiene el mismo en la pestaña **🌐 Idiomas** de
su panel) tiene dos modos:

- **Automático** (el predeterminado, sin configurar nada): cada problema ofrece en el acordeón todos los idiomas
  que tiene. Un problema solo en portugués no muestra chips.
- **Solo estos idiomas**: marca la lista. Solo PT marcado = competencia solo en portugués, aunque el problema
  tenga traducción.
- El acordeón abre en el idioma de la competencia (`LOCALE`) si se ofrece; si no, en el primero. El
  competidor cambia con los chips **PT · EN · ES** y el MOJ recuerda su elección.
- Un idioma ofrecido sin traducción en un problema muestra el portugués en ese problema. La tabla del
  panel muestra, por letra, lo que existe.
- Para enviar un HTML o PDF propio para un idioma, elige el idioma en el selector al lado de los botones
  **Enviar HTML** / **Enviar PDF**. El archivo vale solo para ese idioma.
- El cuadernillo y el editorial en EN/ES usan la traducción de cada problema. Un problema sin traducción sale
  en portugués en el cuadernillo. El título del problema también sale traducido.

### 👥 Personas: quién entra, quién es quién

| Panel | Qué hace |
|---|---|
| **Cuentas** | Crear/restablecer/deshabilitar/quitar cuentas (individualmente y en lote por .txt/.csv), cambiar la contraseña de todos y el atajo a las **Etiquetas de credenciales**. AQUÍ creas las cuentas de rol (sección 3). En una competencia con usuarios **compartidos con Entrenamiento libre**, la tarjeta **🔗 Cuentas compartidas** convierte todo en cuentas propias (sección 8¾). |
| **Inscripciones** (módulo `inscricoes`) | El **roster** de la competencia (solo entra quien está inscrito) y la **ventana**: cuándo abre, cuándo cierra (predeterminado: el inicio de la competencia) y cuántos minutos de entrada tardía. Lista equipos e individuales, disuelve equipos, inscribe a mano, **recuerda por DM las invitaciones pendientes** (🔔) y exporta CSV. La sección 8½ lo explica. |
| **Sesiones** | Quién tiene la sesión iniciada ahora, con la opción de cerrarla; **🚪 salir en masa y bloqueo de login** (cerrar el login, desconectar a todos, reabrir: es el final de una competencia en sala y el cambio de ronda); y el registro de accesos por día. Vale para cualquier competencia. |

### 🎛️ Operación: el día de la competencia

| Panel | Qué hace |
|---|---|
| **Situación** | El tablero en vivo (se actualiza en su lugar cada ~12 s): sesiones iniciadas, jueces en línea/ocupados, cola, pendientes, latencia, línea de tiempo, evaluación manual y las **acciones sugeridas** cuando algo no está bien. Globos pendientes/retenidos solo con el módulo `baloes`. |
| **Staff** | Panorama y acciones sobre la cola de impresión (+ globos con el módulo), desempeño por miembro del staff y el **alcance** de cada staff/jefe de sede (regex o `region:<sede>`). `region:<nombre>` cubre todo lo que está **en ese nodo** de Evento › Sedes y escuelas: la sede y, si es un nodo padre, todas las sedes debajo de él (`region:Nordeste` ve las sedes del Nordeste), y también un recorte (`view`) por su nombre. Vale la sede grabada en el equipo o, sin ella, la regex. Una regex en el alcance se prueba en el usuario. |
| **Jueces** | La cola de la corrección manual: quién reservó cada envío, votos, antigüedad; decidir/resolver en el momento; y la configuración del veredicto manual (opciones de etiqueta + **🔎 Qué va a revisión**: una tabla problema × veredicto; lo marcado va a los jueces y el resto sale automático; sin nada marcado, todo sale automático; con excepciones por lenguaje y el botón para liberar los retenidos que la tabla nueva deja salir). |
| **Auditoría** | Feed unificado de todo lo que pasó (acciones de admin, inicios de sesión, envíos, veredictos) con filtros y CSV, más los **respaldos** que subieron los usuarios (por usuario, con ZIP). |

### 🏟️ Evento: lo que una competencia de varias sedes tiene de más

| Panel (módulo) | Qué hace |
|---|---|
| **Rondas** (`rodadas`) | **Calentamiento y competencia oficial en la MISMA competencia**: planifica cada ronda (ventana + problemas), muestra el checklist y promueve, archivando todo lo que pasó. La sección 6 lo explica. |
| **Documentos** (`documentos`) | Genera, en PDF y HTML en los tres idiomas (pt/en/es), los documentos de la competencia: **Entorno de evaluación** (info sheet), **Cuadernillo de la competencia** (portada + enunciados), **Hoja de límites de tiempo** y el **editorial** (solo se publica después del FIN de la competencia). La sección 5 lo explica. |
| **Globos** (`baloes`) | El color de cada letra: es lo que sale dibujado en la hoja del globo. El predeterminado cubre A–O; con más de 15 problemas, define los demás (si no, salen grises). Son los colores de la ronda en vivo. Para dar colores propios a otra ronda, usa Evento › Rondas. |
| **Clasificación** (`classificacao`) | Quién se clasifica para las próximas etapas. Cada **etapa** (Final Brasileña, PDA, Mundial) tiene su motor, elegido en el panel: vista previa, borrador, publicación (un chip 🎓 por etapa en el marcador) y el **override manual** — excluir del cálculo, retirar sin recalcular, promover a mano, siempre con motivo. `docs/CLASSIFICACAO.md` lo explica. |
| **Equipos** (`sedes` o `telao`) | Identidad de cada cuenta en el marcador: nombre del equipo, país/bandera, sede, universidad, escudo y foto. Carga por CSV y "materializar coincidencias". |
| **Cohortes** (`coortes`) | Equipos **invitados** (extraoficiales, "CCL") separados de los oficiales: quién aparece en el marcador público, quién ve a quién, y el **🔓 Liberar resultados** de después de la ceremonia. La sección 8 lo explica. |
| **Sedes y escuelas** (`sedes`) | Las sedes (nombre + regex sobre el login), que alimentan el filtro del marcador, el alcance del staff, las etiquetas, **las fotos/músicas que cada jefe de sede gestiona en la pantalla** y el gate por sede; las reglas de país/escuela por regex; y la **⏱ prórroga por sede/grupo** (regex → nuevo fin; solo extiende, nunca acorta). En **tres modos** (Simple, Intermedio, Avanzado) con vista previa — sección 7¼. |

### 🖥️ Máquinas: cuando la competencia corre en Maratona Linux (módulo `maquinas`)

| Panel | Qué hace |
|---|---|
| **Gate y bloqueo** | Desde dónde inició sesión cada equipo (IP y navegador) en cada ronda, con CSV; la configuración del **gate de navegador por sede** (esperado × visto por equipo) y el **bloqueo de sede por IP** (IP fijados, bloqueos, fijar/soltar). La sección 7 lo explica. |
| **Anomalías** | Lo que no está bien en el uso de las máquinas **durante la competencia** (solo con el gate de UA activado): equipo con 2 sesiones activas, máquina compartida por 2 equipos, envío desde otra máquina, UA fuera de la sede, sede con menos máquinas que equipos, cambios de máquina, el rastro de la **sesión única** y los bloqueos del bloqueo de sede. Línea de tiempo, tabla por equipo, CSV, cerrar sesión, **desconectar UA divergente**. La sección 7½ lo explica. |
| **mlinux** | El panorama de las máquinas por sede que recoge el nutellaboot (hardware y modelo del equipo, RAM, editores, presión de memoria con PSI, salud en la competencia: reinicios, procesos terminados por falta de memoria, reloj desfasado, inactividad), con la recolección y los comandos remotos. Los datos de salud y PSI solo aparecen para las máquinas con el agente nuevo del mlinux; la pantalla dice cuántas son. La tarjeta **Vínculo máquina-equipo** muestra cuántas máquinas el MOJ ya vinculó a un equipo en el nutellaboot (ocurre solo, en el inicio de sesión del equipo, con el agente nuevo del mlinux), y tiene los botones **enviar roster** y **republicar vínculos**: usa los dos, en este orden, cuando la tarjeta diga "equipo fuera del roster de la imagen". La tarjeta **Alertas de máquinas en tiempo real** instala el aviso del nutellaboot: cuando una máquina levanta una alerta (pendrive, celular, red por USB, identidad repetida), aparece en Máquinas › Anomalías y, durante la competencia, el dueño de la competencia la recibe en Telegram. Para instalarlo o quitarlo, la clave guardada tiene que ser la de administración del nutellaboot. `docs/NUTELLABOOT.md` lo explica. |

> **Globo y congelamiento.** Por defecto, un acierto logrado con el marcador **congelado no genera tarea de
> globo**, y esos globos **no se entregan después**: la tarea no existe. Es la regla de
> competencia (el globo que cruza la sala revela lo que el congelamiento esconde), y vale solo para el globo:
> **la solicitud de impresión sigue libre**. Si quieres el clásico del ICPC (globos circulando
> durante el congelamiento, el público adivinando), marca **Entregar globos durante el congelamiento** en
> **Central › Reglas**; marcarlo también **libera los que ya quedaron retenidos**. El checklist previo a la competencia
> muestra qué política está vigente, y **Operación › Situación** muestra cuántos globos están
> retenidos.

> **Cómo marca el marcador a quien resolvió.** Por defecto la celda de quien resolvió **siempre se ve igual**
> (verde) y el color del globo va en un **puntito** al lado. Es a propósito: la paleta ICPC le da al
> problema A el color **blanco**, y el blanco sobre el fondo blanco del marcador es el mismo píxel: quien resolvía
> el A parecía no haberlo resuelto (la queja que originó el cambio vino de un estudiante). Si
> prefieres el clásico (la celda entera pintada con el color del globo), márcalo en **Central ›
> Reglas › Celda de "resuelto" en el marcador**; los colores claros reciben un contorno para no desaparecer. Vale
> para el marcador, la ceremonia de revelación y el informe.

Fuera del panel, pero enlazadas desde la Central: **etiquetas de credenciales**, **ceremonia de revelación**,
**jplag**, **cola del staff** y **marcador**.

## 1½. Módulos de la competencia: activa solo lo que tu competencia usa

Un **módulo** es un grupo de recursos que la competencia usa. Un examen de curso no activa ninguno:
el panel muestra solo lo común (problemas, cuentas, sesiones, marcador, staff, jueces). Un examen
de curso en laboratorio con **Maratona Linux** activa `maquinas` (gate de máquina, sesión única,
anomalías). La Maratona activa todos. Activar muestra los paneles, las revisiones de la Central y las tarjetas
correspondientes; **desactivar oculta, sin borrar nada**: reactivar restaura todo.

| Módulo | Qué activa | Detectado por |
|---|---|---|
| `sedes` | Evento › Sedes y escuelas, Evento › Equipos (identidad), prórroga por sede, alcance del staff por sede | `regions.json`, `teams-meta.json`, prórrogas |
| `maquinas` | Máquinas › Gate y bloqueo, Anomalías, mlinux; revisiones de gate/bloqueo/sesión única | gate de UA activado, `SITE_LOCK=1`, clave del nutellaboot |
| `rodadas` | Evento › Rondas; tarjeta Promover; informes de ronda | `rounds.json` |
| `documentos` | Evento › Documentos; tarjeta Documentos; pestaña del juez principal | `docs/config.json` |
| `baloes` | Evento › Globos; globos en la cola del staff y en Situación; globos durante el congelamiento | `balloons.json` |
| `coortes` | Evento › Cohortes | `cohorts.json` |
| `inscricoes` | Personas › Inscripciones | `registrations.json` |
| `telao` | tarjetas Revelación y Pantalla; Evento › Equipos (fotos) | `animeitor.json`, `webcast.json`, fotos de equipo |
| `classificacao` | Evento › Clasificación (selector de etapa y de motor) | `classification.json` |
| `virtual` | Evento › Virtual; botón **Virtual** en la tarjeta de la competencia terminada; enlace en el marcador (ver §6¾) | `virtual/runs/` |
| `esqueletos` | Competencia › Esqueletos: el editor de código del equipo abre con el esqueleto del lenguaje (abajo) | `esqueletos.json` |

Dónde se activa: **Central › Módulos** (ajustes predefinidos que solo marcan de antemano), el paso **7 · Módulos** de
[crear competencia](/treino/criar/), `moj-contest -c <cid> modules on|off` o la sección `modules{}` del
spec de creación. **Y solo, al usar el recurso**: crear una ronda, una cohorte, activar el gate,
generar un documento, activar la inscripción, definir un color de globo, una sede o una clave de webcast
(por la web o por la CLI) activa el módulo correspondiente en el momento (la auditoría registra `modules-auto`).
Solo desactivar es manual. También vale para el spec de creación: un solo JSON levanta la competencia entera, con los datos de cada módulo (sedes,
colores, cohortes, gate, rondas, documentos, ventana de inscripción, pantalla, clasificación); el `export`
devuelve la misma sección, sin secretos. Las competencias creadas antes de los módulos se detectan una vez
por los archivos que ya tienen (`server/bin/contest-modules-detect.sh`).

### Esqueletos de código (módulo `esqueletos`)

En la competencia, el editor de código del equipo abre **vacío**: el equipo escribe su código completo.
Con el módulo `esqueletos`, el editor abre con el **esqueleto** del lenguaje (el `main` y las lecturas
habituales). Úsalo en una lista o un examen de curso, cuando el esqueleto ayuda al estudiante.

- **Necesita el editor de código en el navegador activado** (Central › Reglas). Activar el módulo con
  el editor desactivado se rechaza. Desactivar el editor con el módulo activado también se rechaza:
  desactiva el módulo antes.
- En **Competencia › Esqueletos**, cada lenguaje tiene tres opciones:
  - **predeterminado del MOJ**: el mismo esqueleto del entrenamiento;
  - **personalizado**: el esqueleto que escribas para esta competencia;
  - **sin esqueleto**: ese lenguaje abre vacío.
- Al cambiar de lenguaje, el texto solo cambia mientras todavía es el esqueleto intacto. El código que
  el equipo escribió se queda.
- Enviar el esqueleto sin cambios se rechaza en pantalla ("Todavía no cambiaste el esqueleto"). La
  verificación de editor vacío sigue valiendo.
- Un problema de **envío de función** (el paquete declara `FUNCTION_LANGS`) abre vacío en los
  lenguajes del driver: el `main` del esqueleto daría Compilation Error.
- Atención: el editor envía el archivo como `solution.<extensión>`. En Java, no declares la clase como
  `public` (`javac` exige que una clase pública tenga el nombre del archivo). La Central avisa.
- El módulo queda fuera del preset "Maratona / ICPC": en la maratón el equipo espera el editor vacío.
  En una competencia ICPC la Central avisa.
- El esqueleto personalizado va junto en el export, la plantilla y el duplicado. Por la CLI:
  `moj-contest -c <cid> esqueletos ls|show|set|off|reset`.

## 2. Reglas (Central › Reglas): opción por opción

**Identidad y ventana**

- **Nombre**: el título que se muestra; el *id* (que se convierte en el subdominio) no cambia.
- **Inicio / Fin**: la ventana de la competencia. Antes del inicio: cuenta regresiva; después del fin: nadie más envía (excepto los roles de juez). La prórroga fina está en la sección ⏱ (por regex de login; ej.: solo una sala que se quedó sin luz).
- **Apertura del login (pantalla de espera)**: desde cuándo el alumno puede INICIAR SESIÓN (antes de eso, cuenta regresiva en la pantalla de inicio de sesión). Sirve para liberar el inicio de sesión minutos antes del inicio.
- **Congelamiento del marcador**: congela el marcador público a partir de esta hora (estilo ICPC). Los jueces y el admin siguen viendo todo; la revelación ocurre en la ceremonia.
- **Idioma**: portugués, inglés o español. Fija el idioma de las pantallas de todos en la competencia (sin selector) y también el del **papel impreso** (portada de la impresión y hoja del globo), del **informe** final y de los mensajes de invitación en Telegram (en inglés o español, el mensaje lleva también el portugués). Los enunciados y los documentos tienen su propio idioma (🌐 Idiomas del enunciado, Evento › Documentos).

**👁 Lo que el equipo ve durante la competencia**

- **Inicio de sesión habilitado**: desactívalo para cerrar la puerta (quien ya está adentro sigue).
- **El usuario puede ver el registro de evaluación**: el informe prueba por prueba. ⚠ En una competencia que vale nota, dejar el registro visible puede **filtrar las pruebas** (el alumno ve la entrada/salida): es el clásico "SHOWLOG". Desactívalo.
- **Editor de código en el navegador disponible**: el editor lado a lado con el enunciado.
- **Mostrar el tiempo límite de los problemas a los usuarios**: muestra los TL por lenguaje en el enunciado.
- **Permitir el backup de archivos por los usuarios** / **Permitir solicitudes de impresión por los usuarios (.staff)**: habilitan la subida de respaldos por el alumno y las solicitudes de impresión (que van a la cola del staff).
- **Marcador anónimo**: oculta el desempeño individual (solo la posición del propio alumno).
- **Filtro de inicio de sesión por substring de UA**: solo los navegadores cuya identificación contiene la substring pueden iniciar sesión (máquina de competencia bloqueada). Los roles privilegiados están exentos.
- **🕵️ SUPER SECRETO**: la competencia desaparece de la página de inicio/archivo/estado e incluso el marcador exige iniciar sesión. Para competencias de las que ni siquiera puede constar que existen.

**⚖️ Evaluación (lenguajes, pool, veredicto manual)**

- **💻 Lenguajes permitidos en la competencia**: la lista permitida en la competencia (cada problema puede restringir más, en Competencia › Problemas).
- **🖥️ Máquinas de juez (pool)**: qué MÁQUINAS de evaluación atienden esta competencia (vacío = cualquier juez en línea). No confundir con los jueces HUMANOS (sección 4).
- **Veredicto manual**: activa la **corrección validada por jueces humanos** (sección 4).
- **N.º de jueces que validan cada veredicto**: el quórum de la corrección manual: **de 1 a 5, predeterminado 2**. Con 1, un único voto decide (revisión simple); con N≥2, el veredicto solo sale con N votos **unánimes**: cualquier divergencia se convierte en conflicto para el juez principal.
- **⏱ Penalización (marcador ICPC)**: minutos sumados por cada intento no aceptado antes del Accepted (predeterminado 20) y QUÉ veredictos penalizan (predeterminado wa/tle/mle/rte: **Compilation Error queda FUERA** por defecto; vacío = nada penaliza).
- **👁️ Marcador completo (sin congelamiento)**: lista de usuarios permitidos que ven el marcador sin congelamiento (además de admin/jueces).

Por la CLI, todo esto es `moj contest -c <cid> settings set chave=valor` (ej.:
`settings set manual_verdict=true review_judges=3`).

## 3. Roles especiales: qué son y cómo habilitarlos

**Habilitar un rol es solo crear la cuenta con el sufijo correcto en el login**, en el panel
*Personas › Cuentas* (o `moj contest -c <cid> users add fulano.judge`). No hay casilla de permiso: el
sufijo ES el rol. El autorregistro público nunca crea cuentas con esos sufijos (reservados), y las
operaciones en masa (restablecer contraseña, deshabilitar) **se saltan** las cuentas privilegiadas a propósito.

| Rol | Sufijo | Puede | No puede |
|---|---|---|---|
| **Administrador** | `.admin` | Todo: panel ⚙, enviar a cualquier hora, ver los problemas antes del inicio, marcador sin congelamiento, votar como juez, resolver conflictos, responder aclaraciones. | Aparecer en el marcador (ningún rol aparece). |
| **Juez (humano)** | `.judge` | Pestaña **Evaluar** (corrección manual), enviar/ver problemas a cualquier hora (¡probar la competencia!), marcador sin congelamiento, responder aclaraciones, Estadísticas. | Resolver conflictos; panel de admin. |
| **Juez principal** | `.cjudge` | Todo lo del `.judge` **+** panel **Juez principal**: resolver conflictos de votos, editar respuestas de aclaraciones ya dadas, ver el login y el nombre de quien preguntó, liberar la reserva de otro juez (botón propio, con confirmación), opciones y qué va a revisión. | Panel de admin (Central › Reglas, etc.). Reservar una aclaración que otro juez ya reservó. |
| **Staff (personal de sala)** | `.staff` | Cola de **🖨️ impresión y globos** (reservar/imprimir/entregar, modo automático de quiosco). | Ver problemas o enviar (nunca); etiquetas; marcador sin congelamiento. |
| **Jefe de sede** | `.cstaff` | Observar la cola del staff de su sede (solo lectura), **Etiquetas** de credenciales de los competidores y del **`.staff`** de su sede (con contraseña, excepto en una competencia que usa cuentas del entrenamiento, donde la contraseña es personal y no sale en la etiqueta; la credencial del propio jefe tampoco sale en etiqueta), la **🎥 pantalla** de la sede y la **🏆 revelación por sede** después del fin. | Actuar en la cola de impresión; ver problemas/enviar; no hereda `.staff`. |
| **Monitor** | `.mon` | Enviar DURANTE la competencia (sin aparecer en el marcador), **responder aclaraciones**, Todos los envíos y Estadísticas. | Ver problemas antes del inicio; corrección manual. |

Regla de oro: **ninguna cuenta con sufijo de rol entra en el marcador ni en las estadísticas**:
crea todas las que necesites sin miedo de ensuciar el resultado.

> Competencia con usuarios **compartidos con Entrenamiento libre**: una cuenta de rol del
> entrenamiento **no** entra con el rol aquí. Solo entran el `.admin` de quien creó la competencia y
> los superadmins del entrenamiento. Juez, staff y co-organizador = una cuenta creada **en esta**
> competencia (sección 8¾).

## 4. Corrección validada por jueces (veredicto manual)

Con **Veredicto manual** activado, la evaluación automática sigue funcionando, pero el veredicto
queda **retenido**: el alumno ve el envío pendiente hasta que los jueces humanos lo validen.

El flujo, en la pestaña **Evaluar** (página del `.judge`):

1. El juez **reserva** un envío de la cola (reserva con plazo; máx. N jueces en el mismo).
2. Ve el veredicto calculado, el registro y el código, y **vota** (confirmar o cambiar la etiqueta).
3. Cuando se acumulan **N votos unánimes** (N = *N.º de jueces que validan*, predeterminado 2), el
   veredicto se libera: entra en el historial del alumno y en el marcador en el momento.
4. Los votos **divergentes** se convierten en **conflicto**: el **juez principal** (`.cjudge`) decide en su panel
   (una alerta global avisa).

**Opciones de veredicto.** El juez principal o el admin edita la lista en **🏷️ Opciones** (panel del
juez principal u Operación › Jueces). Cada opción tiene tres campos:

1. El texto que el **juez** ve y elige. Ejemplo: `5 - NO - Wrong answer`.
2. La **clase**: una de las seis clases canónicas. La clase define la puntuación, la penalización y el
   color en el marcador. Ejemplo: `Wrong Answer`.
3. El texto que ve el **equipo**. Ejemplo: `Formato de saída errado`. Déjalo vacío para mostrar la
   clase. La clase `Accepted` no tiene texto propio.

Así cada competencia personaliza lo que lee el equipo sin cambiar cómo puntúa el marcador.

**¿Cuántas personas necesitas?** Como mínimo **N cuentas `.judge`** (el quórum) **+ 1 `.cjudge`**
para los conflictos, y recomiendo **N+1 jueces** para que la cola no se trabe cuando alguien hace una pausa.
El `.admin` también vota (cuenta como juez), pero en una competencia grande deja al admin libre para operar.
Con **N=1** un único juez revisa todo (bueno para una competencia pequeña); N=2 es el predeterminado equilibrado;
N≥3 es para finales donde el veredicto necesita un tribunal.

## 5. Documentos de la competencia (Evento › Documentos, módulo `documentos`)

La pestaña existe para el **`.admin` y para el juez principal (`.cjudge`)**, y produce los documentos de la
competencia, cada uno en **PDF y HTML**, en **portugués, inglés y español**:

| Documento | Qué sale | De dónde vienen los datos |
|---|---|---|
| **Entorno de evaluación** (*info sheet*; antes "Información del ambiente") | En el formato de la hoja de la Maratona SBC: sistema operativo y versiones de los compiladores, lenguajes aceptados con sus extensiones, límites de memoria, tiempo, tamaño del código fuente, salida y compilación, las **líneas de compilación y ejecución** de cada lenguaje (las mismas del juez), los veredictos, las notas de evaluación, la penalización y los tiempos de respuesta. | Texto editable (Markdown) + datos en vivo: `run/registry` (lo que reportan los jueces), el `conf` de la competencia y el TL calibrado. |
| **Cuadernillo de la competencia** | Portada + un enunciado por problema, en el orden de las letras. Donde el problema tiene un **PDF propio** en la competencia, entra ese PDF (con la diagramación preservada); si no, el enunciado se renderiza con el molde de los cuadernillos de la Maratona SBC: Computer Modern con el interlineado y la separación silábica de LaTeX, título del problema centrado, ejemplos en cajas apiladas (como en el sitio) o, si marcas **"ejemplos del cuadernillo en tabla (entrada \| salida)"** en el panel Documentos, en una tabla "Ejemplo de entrada · Ejemplo de salida" como la de la SBC (un ejemplo con líneas largas queda mejor apilado), y pie de página "evento – Problema X – título" con el número de página. | `PROBS` de la competencia, `enunciados/<chave>.{pdf,html}` y, si falta, el enunciado del banco. |
| **Hoja de límites de tiempo** | Tabla `letra · nome · tempo limite por teste`. Si el límite es el mismo en todos los lenguajes, sale una columna y la nota "no depende del lenguaje". Si difiere, sale una columna por lenguaje. Más la **fe de erratas** que escribas. | El TL **calibrado y servido** a los jueces (`run/tl`). |
| **Editorial** | Una portada (título, fecha, nota introductoria e índice de los problemas) y la **solución** de cada problema, en el orden de las letras, cada problema en una página nueva. Genera y revisa cuando quieras; el servidor **solo deja PUBLICAR después del fin de la competencia** (contando las prórrogas por sede), y el equipo solo lo descarga con la competencia terminada. | El `docs/solucao.md` del **paquete** de cada problema (el texto que escribió el autor y que nunca llega al alumno). |

**Flujo, de principio a fin**

1. **Completa los datos** (⚙️ *Datos de los documentos*): versión del cuadernillo (`v1.0`), nota de la portada
   y fe de erratas. Guarda.
2. **Ajusta la portada**, si quieres (🎨 *Portada del cuadernillo*). Hay dos modos, en este orden de
   precedencia: **PDF subido** › **texto**. El texto ya abre con la **portada predeterminada del MOJ** (es
   ella, escrita en Markdown), así que editas solo lo que quieras cambiar. Los marcadores se
   sustituyen al generar: `{{CONTEST_NAME}}`, `{{DATE}}`, `{{N_PROBLEMS}}`, `{{N_PAGES}}`,
   `{{SITES}}`, `{{VERSION}}` y `{{NOTE}}` (la nota de la portada). `{{N_PAGES}}`, `{{SITES}}` y
   `{{NOTE}}` son opcionales: el bloque en el que uno de ellos queda vacío desaparece. Sube un PDF cuando la portada
   sea un arte listo del evento: entra tal como está y el resto del cuadernillo se anexa después de ella.

   **Logo** (🏷️ *Logo del encabezado*, opcional): una franja con los logos del evento (PNG, JPEG,
   WebP o SVG, hasta 5 MB) que sale en la parte superior de cada página del cuadernillo y del editorial y en la portada
   generada, como en los cuadernillos de la Maratona SBC. Vale para los tres idiomas; *eliminar* la quita.
3. **Ajusta el texto del info sheet**, si quieres (📝): también es Markdown, con los marcadores
   `{{TOOLCHAIN}}`, `{{TL_TABLE}}`, `{{LANGS_TABLE}}`, `{{MEMLIMIT}}`, `{{STACK}}`,
   `{{CONTEST_NAME}}` y `{{DATE}}`.

   Los dos textos usan el **editor del MOJ** (colores del Markdown y números de línea) con **una pestaña
   por idioma** (PT · EN · ES), como en la gestión de problemas. *Guardar* graba todos los idiomas
   modificados; *restaurar predeterminado* devuelve el idioma de la pestaña al texto del MOJ.
4. **Genera** (botón de cada fila, o *⚙️ Generar todo (pt+en+es)*), **o sube un PDF listo**
   (botón *subir PDF* de la fila). El PDF subido es un documento completo: gana al generado en
   todo lo que el MOJ sirve y se puede publicar sin generar. *volver al generado* borra solo el subido.
   Convertir los PDF lleva algunos segundos; el cuadernillo es el que más tarda, porque junta un PDF
   por problema.
5. **Revisa**: cada fila tiene **PDF**, **HTML** y **abrir**. Revísalo antes de publicar.
   ¿**Algo torcido en el PDF generado** (demasiado espacio o muy poco entre los elementos, una imagen
   grande) que causó el Markdown del enunciado? Cada documento generado tiene también el **✎ .odt**,
   el archivo editable que dio origen al PDF. Descárgalo, ajústalo en LibreOffice (o Word), expórtalo a
   PDF y súbelo con *subir PDF*: el archivo subido gana al generado y es el que todos descargan. El `.odt`
   del cuadernillo trae la portada como página editable seguida de los enunciados; si la portada es un PDF
   subido, o un problema tiene el enunciado en un PDF propio, el `.odt` marca el lugar y tú unes el
   PDF al exportar. Solo el admin y el juez principal descargan el `.odt`.
6. **Publica**. Publicar hace dos cosas: el documento pasa a aparecer en la sección **Competencia** de la
   página de la competencia y en **Documentos**. Quién ve qué:
   - **Entorno de evaluación**: publicado = visible para todos los roles (es logística).
   - **Cuadernillo y hoja de límites de tiempo**: antes del INICIO de la competencia solo los descargan `.admin`, `.cjudge` y
     `.judge`. **La sede (`.staff`, `.cstaff`), el `.mon` y los equipos, solo a partir del inicio**:
     el cuadernillo en manos de alguien antes de la competencia es la competencia filtrada, sin importar el rol. La sede
     imprime a partir del inicio (el `+ noticia` de estos dos se rechaza antes del inicio, porque la
     noticia adjunta el PDF).
   - **Editorial**: solo se publica después del fin, y solo los jueces lo descargan antes de que la competencia termine
     para TODAS las sedes.
   Si marcas **+ noticia**, el MOJ además crea una noticia con el PDF adjunto.
   **Despublicar** lo deshace (el enlace desaparece; la noticia, si se creó, sigue; bórrala en la pestaña de
   noticias si corresponde).

**¿Lo regeneraste? No hace falta publicar de nuevo**: el enlace publicado apunta al documento actual,
así que generar de nuevo ya entrega la versión nueva a quien lo descargue. Pero **avisa a la sede**: quien ya
imprimió se quedó con la versión vieja (para eso sirve el campo *versión del cuadernillo* en la portada).

> 🌐 **El cuadernillo y el editorial salen en el idioma del documento.** El cuadernillo en inglés usa el
> `enunciado.en.md` de cada problema (o el HTML/PDF en inglés que enviaste en el panel de
> Problemas), y el editorial en inglés usa el `solucao.en.md`. Un problema sin traducción sale en
> portugués en medio del cuadernillo: el documento nunca queda solo con la portada traducida. El título del
> problema sale traducido cuando el paquete tiene el título en ese idioma. Una competencia bilingüe con el
> enunciado listo por fuera sigue entrando por el **PDF subido**.

> ∑ **Las fórmulas salen en el PDF como en el enunciado de la página**, incluida la barra vertical (`|x|`,
> `a | b`): el autor no necesita escapar nada. Si algún símbolo de una fórmula sale con un `¿`
> rojo en el PDF, es un defecto del generador, no del enunciado: repórtalo (con el problema) y, mientras
> tanto, sube el PDF listo de ese cuadernillo. Un cuadernillo generado antes de una corrección no se rehace
> solo: genéralo de nuevo.
>
> 🖼 **Las imágenes del enunciado caben en la página.** En el PDF, cada imagen sale como máximo del tamaño que tiene
> en la página web y nunca más grande que el área útil (una imagen grande se reduce, manteniendo la proporción). El
> ancho que pidió el autor en el enunciado (`![](figura.png){width=50%}`) también vale en el PDF.

> 🔒 **El cuadernillo es contenido de la competencia.** Antes de publicarlo, solo `.admin` y `.cjudge` lo descargan.
> Publicado, antes del inicio solo se suman a ellos los jueces (`.judge`). Para la sede y los equipos la
> API responde **404** hasta el inicio: no es un bloqueo de interfaz.

## 6. Rondas: calentamiento y competencia oficial (Evento › Rondas, módulo `rodadas`)

Toda maratón tiene un **calentamiento** (ensayo general) antes de la competencia: dos o tres problemas
fáciles, el día anterior o en la mañana del mismo día, para que el equipo encienda la máquina y pruebe el login, el
editor, la impresión y el globo, y para que tus jueces y tu personal de sala ensayen. Después de eso la
competencia oficial empieza **en la misma competencia del MOJ**, porque lo que quieres garantizar es su configuración (cuentas, contraseñas, sedes, colores de
globo, límites de tiempo, lenguajes, pool de jueces).

En el MOJ esto son **rondas**. La ronda **en vivo** es la que aparece en Central › Reglas y en Competencia ›
Problemas; las demás quedan planificadas hasta que las promuevas.

**El guion** (fíjate en el orden: el calentamiento va PRIMERO)

1. **Arma la competencia** normalmente, con los problemas del **calentamiento** y la ventana del calentamiento.
2. En Evento › Rondas, dale el nombre correcto a la ronda en vivo (`aquecimento`, tipo *calentamiento*) y
   **crea la siguiente** (`oficial`): ventana, congelamiento y la lista de problemas de la competencia de verdad.
   La lista queda guardada y solo queda en vivo al promover: nadie ve los problemas de la competencia antes.
   Puedes usar cualquier problema que el dueño de la competencia pueda ver: público, suyo, de un
   colaborador o de su org. La regla es la misma de Competencia › Problemas, en la ronda en vivo y en la
   planificada.
   Cada ronda puede tener **sus propios colores de globo**. Abre la ronda, ve a "🎈 Colores de los globos
   de esta ronda" y guarda. Los colores quedan en vivo cuando la ronda se promueve. Una ronda sin
   colores propios hereda los colores vigentes. En la ronda en vivo, esta sección y Evento › Globos editan
   lo mismo.
3. **Ejecuta el calentamiento.** El equipo ve una franja fija que dice que es un calentamiento y que ese marcador
   no es el de la competencia. Trátalo como **ensayo general de toda la operación**: si el login abre en el minuto
   del inicio (modelo ICPC), ese es el único momento en que cada rol usa las pantallas de verdad sin
   nada en juego. Entrega antes a cada persona el tutorial de su rol
   ([/contest/ajuda/](/contest/ajuda/)) y pídele que recorra su propia lista: el equipo (entrar, abrir
   un problema, enviar a propósito, aclaración, impresión, respaldo, marcador), el **personal de sala**
   (impresora, el **pop-up** permitido, quiosco, el recorrido), el **jefe de sede** (todo equipo de la sede
   entró al menos una vez), los **jueces** (opciones de veredicto, registro/código, la pareja leyendo
   igual), el **juez principal** (n.º de jueces, qué va a revisión, alarma de conflicto) y la **pantalla** (proyector,
   conexión con el Animeitor: publicar los marcadores y encender el alimentador; fotos y músicas).
4. Cuando termine, haz clic en **🚀 Promover ahora**. El MOJ revisa el checklist y, si todo está listo:
   - **archiva** la ronda: envíos (con código fuente), veredictos, registro del juez, marcador,
     estadísticas, aclaraciones, noticias, tareas del staff y los registros de acceso quedan guardados
     en `rounds/<rodada>/`, más un **informe navegable** de la ronda;
   - **reinicia** el marcador y el historial de los equipos, reinicia la numeración de la impresión y limpia las
     prórrogas por sede;
   - **aplica** la ventana y los problemas de la competencia oficial, y sus colores de globo, si los tiene.
   Atención: con el marcador congelado, la promoción solo se acepta a partir del fin de la competencia para todas
   las sedes + 1 minuto. El checklist muestra `freeze_locked` con la hora. La opción "ignorar los
   bloqueadores" no pasa por encima de esta regla.
   Escribes el id de la competencia para confirmar. Todo queda auditado.

**Registré la COMPETENCIA primero, ¿y ahora?** ¿Armaste la competencia ya con los problemas oficiales y solo
después creaste la ronda de calentamiento? **No promuevas**: promover archiva la ronda en vivo (tu
competencia, vacía), y el archivo es inmutable. Lo correcto es **invertir editando las dos rondas** ahí mismo
(el panel avisa cuando detecta una planificada que empieza antes de la que está en vivo):

1. Edita la ronda **planificada**: renómbrala a `prova`, tipo *competencia oficial*, y dale la
   ventana + congelamiento de la competencia; en **Problemas de la ronda**, pon la lista de la competencia (queda
   guardada, nadie la ve).
2. Edita la ronda **en vivo**: renómbrala a `aquecimento`, tipo *calentamiento*, ventana del
   calentamiento (sin congelamiento) y cambia los problemas por los del calentamiento; en la ronda en vivo,
   guardar **aplica en el momento**.
3. Revisa en Central › Reglas que la ventana vigente sea la del calentamiento, y sigue el guion
   normal a partir del paso 3.
5. **Después**: el marcador y los envíos del calentamiento siguen legibles en Rondas (y puedes
   **publicar** la ronda para que la vean los equipos). El **archivo bruto** en `.tar.gz`, con
   código fuente, sale con un clic, para la auditoría posterior.

**El checklist es serio.** La promoción se RECHAZA mientras haya:

| Bloqueador | Por qué |
|---|---|
| `round_running` | la ronda en vivo no terminó (contando la prórroga por sede) |
| `jobs_in_flight` | hay un envío en el spool/cola del juez. Si se evaluara después del cambio, el tiempo se calcularía contra el inicio de la competencia y el envío del calentamiento reaparecería en el historial de la competencia |
| `pending_verdicts` | todavía hay envíos sin veredicto en el historial |
| `review_pending` | hay envíos en la corrección manual sin veredicto liberado: el voto del juez caería en el marcador de la competencia |
| `judged_down` | el daemon de evaluación no está vivo, así que la cola no se vacía |
| `no_next_round` | no hay ronda planificada |

Hay un `--force` (casilla "ignorar los bloqueadores"), para emergencias: **no** elimina el
riesgo, solo asume que sabes lo que estás haciendo. El único que el `--force` **no** ignora es
`no_next_round` (sin ronda planificada no hay adónde promover).

> Una competencia que usa las cuentas de otra (`USERS_FROM`) **promueve normalmente**: el archivado solo
> toca el `users/` local. Antes era un bloqueador; dejó de serlo porque es justamente el caso de uso
> real (calentamiento + competencia con las cuentas del entrenamiento).

**Lo que NO cambia en la promoción:** cuentas y contraseñas, equipos/sedes/banderas, alcance del staff, colores de
globo, regiones, límites de tiempo calibrados, lenguajes, pool de jueces, la tabla de qué va a revisión y los
textos/portada de los documentos. **Lo que se reinicia:** marcador, historial y envíos de los equipos (archivados,
no perdidos), globos, numeración de impresión, prórrogas y la lista de documentos publicados.

> ⚠️ **Los colores de globo son por LETRA.** Si el problema A del calentamiento y el A de la competencia son
> diferentes, el color del globo A es el mismo en las dos rondas. Revísalo en Evento › Globos antes de la competencia.

**En la CLI:** `moj contest -c <cid> rounds ls | add | set | problems | promote | publish | archive`.

## 6½. Después de la competencia: terminar el evento

Cuando la competencia termina, el marcador sigue **congelado** y los documentos siguen **sin
publicar** hasta que alguien mande liberarlos: nada de esto ocurre automáticamente con el reloj. La Central
pasa a mostrar el bloque **"🏁 Después de la competencia"** con el checklist de lo que sigue cerrado y el
botón **🏁 Terminar evento**, que hace de una vez las dos cosas que todos olvidan:

1. **abre el marcador**: quita el congelamiento (`FREEZE_TIME=0`), así el resultado final queda
   público (es el mismo efecto del botón "🔓 Descongelar todo (público)" de la ceremonia de revelación).
   El MOJ solo acepta descongelar a partir del **fin de la competencia para todas las sedes + 1 minuto**. La
   prórroga de una sede cuenta. La regla vale para todos los caminos: este botón, la ceremonia,
   el campo de congelamiento en la Central y la promoción de ronda. La pantalla muestra la hora a partir de la cual el
   botón queda disponible;
2. **publica los documentos ya generados** que todavía no estaban publicados: el cuadernillo, la hoja de
   límites de tiempo, el info sheet y el editorial pasan a aparecer en "Archivos y Recursos" para
   los equipos. (El editorial solo se puede publicar después del fin; por eso entra aquí).

El botón **no** toca el resto: liberar el **registro de evaluación** para los equipos (`SHOWLOG`),
mostrar los **límites de tiempo** y
**liberar las cohortes** (invitados) siguen siendo decisión tuya: cada uno aparece en el
checklist con el atajo "resolver →" a la pantalla correcta. Solo funciona después de que la competencia terminó
**para todas las sedes** (la prórroga por sede cuenta) y puede repetirse sin problema: la
segunda vez no hace nada.

El ciclo se cierra con el **informe final** (Competencia › Informe): el `tar.gz` navegable lleva el
marcador abierto, los envíos, las estadísticas completas, los enunciados **y** los documentos
publicados: es el paquete que se envía a los participantes y al archivo del evento.
Al lado de la descarga está **📢 Publicar como histórico**: el mismo sitio pasa a existir en
`https://moj…/relatorio/<contest>/` y la tarjeta de la competencia en la página de inicio y en `/contests/`
recibe el botón **📑 Informe**: es el **histórico** del evento. La generación corre en segundo plano
(~1–2 min en una competencia grande; el panel muestra "publicando…" y cambia solo cuando termina).
Es público: el informe no incluye código fuente, registro del juez ni contraseñas, y las aclaraciones
salen anónimas, pero muestra nombres de equipos, runs y estadísticas: publícalo cuando todo ya se haya
divulgado. **🔄 Republicar** lo genera de nuevo y reemplaza el sitio entero de una vez (quien lo esté leyendo
no ve un estado a medias); **Despublicar** borra la dirección y el botón de las tarjetas. Las **rondas
archivadas** (el calentamiento, por ejemplo) tienen su propio botón en Competencia › Informe: **🌐 publicar**
pone el informe generado en la promoción en
`/relatorio/<contest>/rodada/<slug>/`, y la página de inicio del informe principal, al ser
(re)publicada, pasa a enlazar las rondas públicas en "Rondas anteriores de este evento".

## 6¾. Participación virtual (Evento › Virtual, módulo `virtual`)

Con la competencia terminada, cualquier cuenta del Entrenamiento libre puede **rehacer la competencia una vez**, en su propio
tiempo, contra el marcador oficial. El marcador oficial **no cambia**. Referencia completa: `docs/VIRTUAL.md`.

**Para activarla:** Central › Módulos › **Participación virtual**. El módulo solo se activa cuando:

1. la competencia **no es secreta**;
2. el modo es **ICPC**;
3. **todos los problemas ya son públicos en el entrenamiento**. Si alguno no lo es, la respuesta es un error que dice
   cuántos faltan. Publica los problemas primero (gestión de problemas) y actívalo de nuevo.

Puedes activar el módulo antes del fin de la competencia. Queda **inactivo** y se abre solo cuando la competencia
termina para todas las sedes **y** el marcador se descongela (botón **Terminar evento**).

**Atención:** activar este módulo hace que el marcador final y la lista de problemas sean visibles para las cuentas del
entrenamiento. Una competencia que no puede verse desde fuera no debe activar el módulo.

**El panel Evento › Virtual muestra:**

- las **condiciones**, una por línea, con ✅ o ⛔: el público solo ve "no disponible"; tú ves lo que falta;
- el **enlace** de la página (`/treino/virtual/?c=<contest>`);
- las **participaciones registradas**, con resueltos y penalización. El botón **quitar del marcador** quita una
  fila del marcador virtual (el registro queda guardado; **restaurar** lo deshace). La acción queda auditada.
  El botón **devolver intento** borra la fila y deja que esa cuenta vuelva a empezar en esta competencia. Úsalo
  para un probador, o para quien tuvo un problema durante la competencia. La acción también queda auditada.

**Regla del participante** (la lee antes de empezar): una participación por cuenta; puede desistir sin
registrar en los primeros 15 minutos o mientras no tenga ningún aceptado, como máximo 2 veces; el 3.er inicio
es definitivo.

## 7. Máquinas de los equipos (Máquinas › Gate y bloqueo, módulo `maquinas`)

Es en el calentamiento cuando los equipos encienden de verdad las computadoras, y de ahí el MOJ saca el mapa
**equipo × IP × navegador** de la sala (del registro de accesos de la competencia, recortado por la ventana de la ronda:
no se captura nada nuevo). La pestaña muestra, por ronda:

- **por equipo**: nombre, sede, IP y navegadores usados, primer inicio de sesión y una alerta cuando el equipo
  usó **más de un IP**;
- **por IP**: qué equipos vinieron de cada máquina; marca **IP compartido** (dos equipos en la
  misma máquina es señal de mesa cambiada o cuenta prestada);
- **quién cambió de máquina**: en la competencia oficial, el equipo que inicia sesión desde un IP/navegador distinto del que
  usó en el calentamiento aparece marcado en rojo;
- **⇣ CSV** de todo, para comparar con la lista de la sede.

De aquí salen dos acciones, que escriben en el lugar de siempre:

- **aplicar sede**: en la vista por IP, escribir el nombre de la sede y hacer clic graba la **sede** de los equipos
  de ese IP (el mismo campo de Evento › Equipos); el marcador, las etiquetas y el alcance del staff pasan
  a respetarla;
- **configurar el gate de navegador**: la sección 🔒 en la parte superior de la pestaña (justo abajo); los navegadores
  realmente vistos en la ronda quedan listados ahí, y cada uno puede convertirse en el *fallback* con un clic.

### El gate POR SEDE (el caso de la maratón)

Cuando cada sede corre **su propia** imagen, el UA de cada máquina lleva un pedazo del propio login
del equipo: `teambrspso001` (Brasil/BR, `São Paulo`/SP, Sorocaba/SO) corre en una imagen cuyo UA contiene
`brspso`. Una substring única no sirve, así que el MOJ **deriva lo esperado del login**.

**En la web** (sección 🔒 de Máquinas › Gate y bloqueo): el interruptor **"Bloquear a quien no venga de la imagen de la
sede"** lo activa/desactiva; debajo van la **regex del login (con captura)** y el **UA esperado** (`\1`),
con un **probador en vivo** ("probar con el login" → *UA debe contener `brspso` · sede Sorocaba*),
y tres listas plegables: **overrides por sede**, **reglas regex de login** y **exentos**.
Guardar ya vale para el próximo inicio de sesión.

**En la CLI**, lo mismo:

```
moj contest -c <cid> ua-gate set --from-login '^team([a-z]{6})[0-9]{3}$' --expect '\1'
moj contest -c <cid> ua-gate set --region 'Sorocaba=brspso-v2'     # sede fuera del patrón
moj contest -c <cid> ua-gate set --exempt '^ccl' --exempt time-reserva-07
moj contest -c <cid> ua-gate check teambrspso001                   # lo que se espera de él
moj contest -c <cid> ua-gate show
```

Una regla cubre **todas las sedes de una vez**. El orden de resolución es: **exentos** › cuenta de
rol (siempre entra) › regla por regex › **override de la sede** › captura en el login › substring
única (el `login_ua_substring` de siempre, que sigue valiendo como último recurso).

- Quien no coincide queda **bloqueado en el inicio de sesión** (403): la decisión fue bloquear, con la lista de **exentos**
  como margen. `--mode off` desactiva el gate sin borrar la configuración.
- El panel Máquinas › Gate y bloqueo muestra **UA esperado × UA visto** por equipo y cuenta cuántos están fuera de la
  imagen de la sede: así se arregla la sala **en el calentamiento**, antes de que el gate bloquee
  a alguien en la competencia.
- Quien ya tiene la sesión iniciada con el navegador equivocado sale con **"Desconectar UA divergente"** (Máquinas ›
  Anomalías), que compara cada sesión con lo esperado para **ese** equipo.
- **Bloqueo de sede por IP** (interruptor en la misma sección 🔒, DESACTIVADO por defecto; actívalo en la competencia): el gate
  y el aislamiento por subdominio no frenan `curl --resolve moj…:443:<IP>` desde la máquina de competencia al
  sitio base (entrenamiento, respaldos que el alumno subió antes, otra competencia). Con el bloqueo, cada inicio de sesión de un
  competidor **fija el IP de origen** (la salida de la sede) a esta competencia hasta el fin + margen; desde ese IP
  cualquier otro destino responde **403 `site_locked`**, incluida una sesión del entrenamiento abierta antes. Las cuentas
  de rol están exentas. **Toda reivindicación y todo bloqueo van a la auditoría** (`site-lock-claim`,
  `site-lock-block`) y aparecen en Máquinas › Gate y bloqueo (bloqueo de sede), con "soltar" por IP y "🔒 Fijar IPs
  ya vistos" (útil en la mañana de la competencia). Efecto secundario aceptado: durante la ventana, todos los que estén detrás
  de ese IP público pierden el entrenamiento.
- **Sesión única por equipo** (interruptor en la misma sección 🔒, activado por defecto): con el gate vigente, un
  nuevo inicio de sesión en **otra máquina cierra la sesión anterior** del equipo. Cambiar de máquina por una falla
  sigue funcionando (el equipo inicia sesión en la nueva y la vieja pierde la sesión); recargar la página en la misma
  máquina no cierra nada. Cada cierre se convierte en un evento en Máquinas › Anomalías.

## 7¼. Sedes (Evento › Sedes y escuelas — módulo `sedes`)

La sede de cada equipo alimenta el filtro del marcador, el alcance del staff (`region:<nombre>`), las
etiquetas, el gate de navegador por sede, las estadísticas, la clasificación y la pantalla. Todos usan la
**misma regla**:

1. gana la sede **grabada** en el equipo (el nombre, sin distinguir mayúsculas);
2. si no, la **regex más profunda** que coincide con el usuario (sin distinguir mayúsculas);
3. un grupo/país **suma** las sedes debajo de él; un nodo con el mismo nombre de la sede también la cuenta;
4. una sede grabada que no existe en el árbol aparece como "fuera del árbol" y cuenta en el nodo que daría
   la regex;
5. un **recorte** (`view`: supersede, equipos femeninos) agrupa equipos que ya están en las sedes y nunca es
   la sede de nadie.

El panel tiene **tres modos**. Elige el que sirva para tu competencia; se puede subir de modo en cualquier
momento. Un modo que no cabe en el árbol actual queda deshabilitado y dice por qué.

- **Simple** — una lista de sedes. Cada sede tiene "usuarios que empiezan con" (separados por coma). Para
  asignar equipos, pega la lista de usuarios y elige la sede, o elige la sede de cada equipo sin sede.
  Renombrar una sede se lleva los equipos grabados con el nombre viejo (la vista previa muestra cuántos antes
  de guardar). Por la IP de la máquina de la competencia: Máquinas › Gate.
- **Intermedio** — grupos (país, región) › sedes. Cada sede tiene reglas: empieza con, contiene, termina
  con, o es uno de (lista).
- **Avanzado** — el árbol completo: subregiones, recortes `view` y regex libre.

La **vista previa** de abajo muestra lo que verán el marcador, las etiquetas y el alcance del staff: cuántos
equipos tiene cada sede, quién quedó sin sede, quién se quedó en un grupo/país (la regex coincidió con el
grupo y con ninguna de sus sedes), quién coincide con dos sedes y las sedes grabadas fuera del árbol. "Por
guardar" resume el cambio. Si otra pestaña o la CLI cambió las sedes después de que abriste la pantalla, el
guardado se rechaza: recarga y rehazlo.

Un equipo **inscrito** guarda la sede en la inscripción: no desaparece cuando el equipo cambia. La Central
muestra el ítem **Sedes** cuando hay algo por revisar.

La regex sigue un subconjunto que coincide igual en el navegador y en el servidor: `\d \w \s` y `(?:`
sirven; `\b`, `(?=`, `[[:clase:]]`, cuantificadores perezosos, un guion ambiguo dentro de `[ ]` y las letras
con acento no (el usuario no lleva acentos). El guardado dice qué sede y por qué.

En la CLI: `moj-contest -c <id> regions show|who|assign|set|map`.

## 7½. Anomalías de máquina (Máquinas › Anomalías) y Sesiones (Personas › Sesiones)

En la Maratona 2026 solo se pudo responder "¿algún equipo usó dos máquinas?" después de la competencia, cruzando
registros a mano. El panel **Máquinas › Anomalías** responde **durante** la competencia (las sesiones activas, la salida en masa y el registro de accesos, que valen para CUALQUIER competencia, están en **Personas › Sesiones**). Solo vale con el **gate de UA activado**: es el
navegador de la imagen del mlinux el que identifica la máquina (`machine_id/boot_id`). El inicio de sesión desde un navegador
común solo tiene el IP, y detrás de un NAT el IP es la sede entera: esos inicios de sesión quedan fuera de las anomalías de
máquina (solo aparecen en "UA fuera de la sede" y en la lista de sesiones). Con el gate desactivado el panel
avisa y muestra solo las sesiones y el registro de accesos.

- **Tarjetas** (clic = filtro): sesiones activas, 👥 **2 sesiones activas** (el mismo equipo en dos
  máquinas; con la sesión única activada esto solo ocurre por un token copiado), 🖥 **máquina
  compartida** (2+ equipos iniciaron sesión en la misma máquina durante la competencia; grave si los dos siguen activos en ella),
  📤 **envío desde otra máquina** (el envío vino de una máquina distinta de la que inició la sesión;
  la misma máquina reiniciada aparece como *info*), 🧭 **UA fuera de la sede**, 🏫 **sede con pocas
  máquinas** (de la última recolección del nutellaboot), 🔁 **cambió de máquina** (info: normal cuando la máquina
  falla) y las **revocaciones** de la sesión única.
- **Línea de tiempo**: cada evento con hora, tipo, equipo, máquina y detalle; filtros por tipo y texto;
  CSV; botón para **cerrar sesión** del equipo.
- **Equipos**: solo los que tienen alguna anomalía (o todos los que tienen sesión): sesiones activas y en cuántas máquinas,
  las máquinas usadas en la competencia en orden, el último envío (✓ vino de la máquina de la sesión; ✗ no) y las
  anomalías como etiquetas.
- **🚪 Salir en masa y bloqueo de login**: el cambio de ronda en tres clics: **cerrar el login**
  (el competidor recibe 403 `login_disabled`; la organización entra), **desconectar a los competidores**, al **staff y
  jefes de sede** o a los dos (nunca al admin, los jueces, el juez principal, el monitor ni la pantalla), promover la ronda en
  Evento › Rondas, y **reabrir el login** cuando los equipos puedan entrar. Cada sesión cerrada se convierte en
  un evento en la línea de tiempo; la acción va a la auditoría (`logout-all`).
- **🔒 Bloqueo de sede**: los IP fijados a esta competencia (inicios de sesión, bloqueos, hasta cuándo), los bloqueos
  registrados (cuándo, IP, destino, ruta, sesión) y los botones **soltar** y **🔒 Fijar IPs ya vistos**.
  La tarjeta "bloqueos del bloqueo de sede" y los eventos 🔒 de la línea de tiempo vienen de la auditoría. La sección 7 lo explica.
- **Canal de los pedidos en la competencia**: cuántos inicios de sesión y envíos de la competencia vinieron de la **web**, de la **CLI** (`moj-comp`) y de
  **paquetes offline**. Vale incluso sin gate. La CLI se identifica en el User-Agent (`moj-comp/<build>`) y,
  en la máquina de competencia, antepone el **mismo User-Agent del navegador de la imagen** (leído de
  `/etc/moj/user-agent`, grabado por la imagen): así pasa el gate por sede y se queda con la
  misma clave de máquina que el navegador; usar los dos en la misma máquina no cierra la sesión. Fuera de la
  máquina de competencia, el gate bloquea la CLI (403), a propósito.
- Se actualiza solo cada 30 s. El envío graba el origen (IP, navegador y la sesión usada) en
  `var/submit-origin.log`; los inicios de sesión, en `var/access.log`; los cierres de sesión, en
  `var/session-events.log`. Los tres atraviesan las rondas y entran en el archivo.

## 8. Equipos invitados (cohortes de marcador: Evento › Cohortes, módulo `coortes`)

La Maratona invita equipos que **compiten sin entrar en la disputa oficial**: la gente los llama
invitados, extraoficiales, "CCL". El MOJ trata esto como una **cohorte**: un grupo de equipos con una política
de visibilidad propia.

**Lo que garantiza una cohorte privada**

- sus equipos **no aparecen en el marcador público**;
- los equipos regulares **no saben que existe**: ni en el marcador, ni en el directorio de equipos
  (`/contest/teams`, que es público y listaba todos los logins);
- los **propios invitados ven a todos** (su marcador trae oficiales + invitados);
- cuando **liberas los resultados**, todos pasan a ver a todos, y el invitado aparece
  **intercalado según su desempeño, pero sin ocupar una posición oficial**: el podio combinado sigue
  coincidiendo con el oficial.

**Cómo configurarlo (Evento › Cohortes)**

Una fila por cohorte, con lo que decide el comportamiento: **id**, **nombre**, **regex de login**,
**pública** (aparece en el marcador público), **extraoficial** (entra sin ocupar posición), **predeterminado**
(quien no coincide con nada cae en ella) y **ve**: las casillas que dicen qué cohortes ve esa vista
(la cohorte siempre se ve a sí misma). La columna **equipos** cuenta cuántos hay en cada una.

- **+ crear cohorte**: nace privada y extraoficial, viendo a todas: es el caso del CCL.
- **Numerar los equipos invitados en su propia secuencia**: por defecto el invitado muestra `–` en lugar
  de la posición. Con la opción activada, muestra la posición entre los invitados, en cursiva, en el
  marcador, en la revelación y en el informe. La numeración oficial no cambia.
- **asignar**: elige un equipo y su cohorte (el campo gana a la regex); "— por regla (regex) —" devuelve el
  equipo a la regex.
- **📌 Materializar (N)**: fija la cohorte de quien hoy solo coincide por regex; después de eso, cambiar la
  regex no reasigna a nadie. El contador dice cuántos equipos están en esa situación.
- **🔓 Liberar resultados**: pide que escribas el **id de la competencia** para confirmar (en la práctica es irreversible:
  el marcador público pasa a mostrar a todos).
- **Marcadores generados**: las vistas que mantiene el `build.sh` (una por cada cohorte que ve un conjunto
  diferente, más la pública).

Para cambiar la cohorte **predeterminada**, marca el botón de radio de la otra fila y guarda **esa** fila. Quitar
una cohorte exige que esté **vacía** (y la predeterminada nunca se puede quitar).

**Lo mismo en la CLI:**

```
moj contest -c <cid> cohorts ls
moj contest -c <cid> cohorts add ccl --name "Café com Leite" --regex ccl --private --unranked
moj contest -c <cid> cohorts assign timeconvidado07 ccl     # invitado sin 'ccl' en el login
moj contest -c <cid> cohorts materialize                    # fija la regla en un campo por equipo
moj contest -c <cid> cohorts release                        # el "liberamos todo" (pide el id)
```

La cohorte coincide por **regex sobre el login** y/o por el campo `.team.cohort` de cada equipo (el campo gana).
`materialize` convierte la regla en dato: después de eso, cambiar la regex no reasigna a nadie.
Quien no coincide con nada cae en la cohorte **default** (la de los oficiales).

**Lo que sigue completo, a propósito** (son roles privilegiados, y los necesitas):
**Todos los envíos**, **Estadísticas** (incluido quién resolvió primero), la **cola del
staff** (el globo del invitado tiene que entregarse) y el **informe final**. Dos consecuencias
prácticas:

- el **código de un envío** solo lo ven el equipo que lo envió y los jueces/admin. La opción antigua
  "mostrar el código de los envíos a todos" (`SHOWCODE`) se **eliminó** el 2026-09-18;
- **publicar el archivo de una ronda** (Evento › Rondas) exige los resultados liberados cuando hay una
  cohorte privada: el informe de la ronda trae el marcador abierto con todos.

> ℹ️ Quedan dos canales **numéricos** que no revelan identidades, pero existen: la página de estado
> pública cuenta los envíos pendientes de **todos** los equipos, y la numeración de tareas de
> impresión es única por competencia (los saltos indican actividad que el equipo no ve).

## 8½. Inscripción previa y equipos de 3 cuentas del entrenamiento

Vale para las competencias creadas con **"Compartir usuarios de Entrenamiento libre"**. Al activar la inscripción
(Personas › Inscripciones → **Activar**), la competencia pasa a tener una **puerta**: quien no
se inscribió **no entra** (la API rechaza el inicio de sesión; no es solo la pantalla).

**Cómo se inscribe la persona:** en el sitio principal, con la sesión del entrenamiento iniciada, en
`/contests/inscricao/?c=<id>` (la tarjeta de la competencia en la página de inicio recibe el botón **📝 Inscríbete**).
Elige **individual** o **crear un equipo**: le da un nombre e invita hasta 2 usuarios del entrenamiento;
cada invitado tiene que **aceptar**. Mientras la ventana esté abierta se puede salir, renombrar y
deshacer. La participación es exclusiva: aceptar una invitación deshace la inscripción individual.

**La invitación avisa sola.** En el instante en que el capitán invita, **el mojinho manda un DM** al
invitado con el enlace para aceptar/rechazar; y en la **víspera del cierre** (24 h antes) manda **un
único** último aviso a quien todavía no respondió (el mensaje sale en portugués; si la competencia
tiene `LOCALE=en`, va en inglés **y** en portugués en el mismo texto; el DM no tiene selector de
idioma). Solo llega a quien tiene **Telegram vinculado**
(perfil del entrenamiento → 📨 Telegram); por eso la lista de invitaciones muestra `📨` (alcanzable) o `⚠️`
(sin canal), y el resumen cuenta cuántos quedaron sin él. En la tabla de equipos, cada invitación pendiente tiene
el botón **🔔** para recordarla en el momento, y el encabezado tiene **🔔 Recordar a todos**; recordarlas a mano **no**
cancela el aviso automático de la víspera. Para desactivar el automático en esta competencia, desmarca
*recordatorio automático* en la caja de la ventana (graba `REG_REMIND=n`). Esto importa porque **quien no
acepta la invitación no entra en el equipo**, y a veces ni siquiera está inscrito.

**En la competencia, cada miembro entra con SU PROPIO usuario y contraseña del entrenamiento** y la sesión pasa a ser la del equipo:
el marcador, los globos y la impresión ven **una sola fila**. Quién estaba en el teclado queda registrado
(`var/actor-log` y la 5.ª columna del `var/access.log`): útil para revisarlo después.

**La ventana** (Personas › Inscripciones → *Ventana de inscripción*): **abre** (vacío = ya abierta), **cierra**
(vacío = el inicio de la competencia) y **retraso (min)**: minutos después del inicio en los que todavía se puede
entrar, pero en la cohorte `…-atrasado`, que aparece en el marcador **sin ocupar posición** (es la *extra
registration* de Codeforces). Pasado ese tiempo, la puerta se cierra.

**En qué reloj están estos campos:** en el de **tu navegador**; la caja muestra cuál es, justo
debajo. En cambio, las horas que el **MOJ escribe para las personas** (el DM del mojinho, el checklist
previo a la competencia, la fecha del cuadernillo, el informe final) salen en la **zona horaria de la competencia**, que defines en
*Central › Reglas → 🕒 Identidad y ventana → 🌎 Zona horaria de la competencia* (vacío = `America/Sao_Paulo`). Cuando los dos relojes
difieren, la caja de la ventana muestra también la hora en la zona horaria de la competencia, para que no haya dudas.

**Marcador:** la inscripción siembra las cohortes `individual` y `times`, cada una con **su propio marcador**:
el selector "Marcador: General | Equipos | Individual" aparece solo en la página del marcador. Si la
competencia ya tenía cohortes configuradas, el checklist previo a la competencia avisa que faltan esas dos.

**Con CALENTAMIENTO (el que queda varios días en vivo):** planifica las dos rondas en *Evento › Rondas*
(el calentamiento ahora, la competencia oficial en la fecha real). Por defecto **el calentamiento también exige
inscripción**: es en él donde el competidor resuelve el inicio de sesión, el envío y el marcador; dejar entrar sin
inscripción solo empuja el problema al día de la competencia. La inscripción se cierra sola **al inicio de la
competencia oficial** (es esa fecha la que hereda "cierra", no la del calentamiento). Si prefieres el
calentamiento de puerta abierta (cualquier cuenta de la fuente entra sin inscripción), activa
`REG_WARMUP_OPEN=y` en el conf; en ese caso la **promoción** cierra la sesión de quien no se
inscribió y el marcador de la competencia nace solo con los inscritos; el panel muestra el sello
*🔥 calentamiento: puerta abierta* mientras esto esté vigente.

**El modo de participación es definitivo:** después de inscribirse (individualmente o en equipo), el competidor
no cancela ni cambia de modo por su cuenta: la página de inscripción lo deja claro antes de elegir, y
cualquier cambio pasa por ti (Personas › Inscripciones: quitar, disolver, inscribir a mano).

**El equipo también declara en la inscripción:** la **universidad** (se convierte en el prefijo `[SIGLA] Nome do Time`
en el marcador y en la columna/filtro de escuela), el **uso de IA** (aparece como 🤖 al lado del nombre: es
transparencia, no un juicio), la **bandera** (país o estado de Brasil: la banderita del
marcador) y una **foto del equipo** (la que va a la pantalla; se reprocesa en el servidor, sin metadatos). El capitán puede editar todo mientras la ventana esté abierta, y es visible en tu
panel y en el CSV. **El inscrito INDIVIDUAL declara lo mismo** (menos la foto):
universidad, IA y bandera, en la inscripción o después, en la misma página. La organización ajusta
cualquiera de ellos con las acciones `team-meta`/`individual-meta` del panel, sin una regla regex en el
`teams-meta.json` (el mecanismo heredado sigue valiendo solo como superposición visual).

> Consejo para el día de la competencia: el checklist de la Central muestra cuántos se inscribieron y **cuántas invitaciones
> quedaron pendientes**: una invitación no aceptada significa gente que cree que está en el equipo y que, a la
> hora de la verdad, no entra.

## 8¾. Cuentas compartidas con Entrenamiento libre: elegir y deshacer

Al crear la competencia (paso 3 del asistente) eliges entre **cuentas propias** de la competencia y
**usuarios compartidos con Entrenamiento libre**. En el modo compartido, cada persona entra con la
cuenta y la contraseña del entrenamiento. Es práctico para una lista de ejercicios. En un examen,
ten en cuenta lo que implica:

1. El usuario y la contraseña son los de Entrenamiento libre. No los ves ni los restableces, y las
   etiquetas salen sin contraseña.
2. Cualquier cuenta de Entrenamiento libre entra. Para limitarlo, activa el módulo **Inscripciones**
   (sección 8½).
3. Solo **tu** `.admin` (el de quien creó la competencia) y los superadmins del entrenamiento entran
   con rol. Juez, staff y co-organizador necesitan una cuenta **propia** de la competencia
   (Personas › Cuentas, sección 3).
4. No existe cambio masivo de contraseña del examen: quien conoce la contraseña del entrenamiento de
   alguien entra como esa persona aquí también.
5. Se puede deshacer convirtiendo en cuentas propias (abajo). La conversión no tiene vuelta atrás.

El asistente solo crea la competencia compartida después de **☐ Entendido**. La Central muestra el
ítem **Cuentas compartidas** mientras la competencia siga así.

**Actuar sobre un participante compartido.** En Personas › Cuentas, quien entra con la cuenta del
entrenamiento aparece con **🔗 entrenamiento**. **Deshabilitar** bloquea a la persona en esta
competencia (la cuenta del entrenamiento sigue valiendo allá) y **reactivar** lo deshace.
**Descalificar** la saca del marcador. **Quitar** la bloquea para siempre: no vuelve con la cuenta
del entrenamiento. Una cuenta que creaste o restableciste aquí vale con la contraseña **de aquí**: la
del entrenamiento ya no abre esa cuenta en esta competencia.

**Convertir en cuentas propias** (Personas › Cuentas › tarjeta **🔗 Cuentas compartidas**):

1. **Ver vista previa de la conversión.** No se graba nada. La vista previa cuenta quién recibe
   cuenta (quien tiene carpeta en la competencia, sesión abierta, registro en el log de accesos o
   inscripción), los equipos, los miembros de equipo que pierden el login y los avisos.
2. Confirma. Antes de la competencia, marca **☐ Entendido**. Con la competencia ya empezada, escribe
   el **id de la competencia**. Si la lista cambió entre la vista previa y la confirmación (alguien
   entró), la pantalla muestra la vista previa nueva y pide confirmar de nuevo.
3. **Descarga el CSV** de las credenciales en el momento. Las contraseñas nuevas solo aparecen ahí y
   en las **Etiquetas**.

Lo que hace la conversión:

- cada participante recibe una cuenta propia con contraseña **nueva** (del entrenamiento solo viene
  el nombre);
- cada **equipo** pasa a ser **una** cuenta (usuario `time-…`) con contraseña única, y los miembros
  dejan de entrar con sus propias cuentas; el miembro que ya envió pasa a ser una cuenta
  deshabilitada, y su fila en el marcador se mantiene;
- tu `.admin` del entrenamiento pasa a ser un `.admin` propio de la competencia con contraseña nueva
  (la pantalla la muestra);
- la inscripción se cierra y el roster queda archivado;
- el historial y el marcador se mantienen. Quien entró sin enviar pasa a aparecer en cero;
- quien nunca entró en la competencia no recibe cuenta (agrégalo en ➕ Agregar);
- los superadmins del entrenamiento dejan de entrar en esta competencia;
- las sesiones abiertas siguen. La opción **cerrar las sesiones** hace que todos vuelvan a entrar con
  la contraseña nueva.

En la CLI: `moj-contest -c <id> users convert` (vista previa) y `users convert --apply --csv creds.csv`.

## 9. Plantilla de usuarios (habilita todas las funciones)

Pégala en la carga en lote de *Personas › Cuentas* (una línea por cuenta: `login nome`), o crea
uno por uno con `moj contest -c <cid> users add <login> --name "<nome>"`:

```
juiz1.judge      Juez Uno
juiz2.judge      Juez Dos
juiz3.judge      Juez Tres (reserva del quórum de 2)
chefe.cjudge     Juez Principal
apoio1.staff     Staff de impresión y globos
sede1.cstaff     Jefe de la Sede 1 (etiquetas + revelación)
monitor1.mon     Monitor (responde aclaraciones)
```

Después: activa **Veredicto manual** (y ajusta el **N.º de jueces**) en Central › Reglas; distribuye
las contraseñas generadas; cada persona inicia sesión en la MISMA pantalla de la competencia y ve los botones de su rol.

## 9½. Panel del entrenamiento › Contests y quién puede crear

El panel administrativo del Entrenamiento libre (`/treino/admin/`, cuenta `.admin`) tiene la pestaña **🏆 Contests**.
Lista las competencias creadas por la interfaz y controla quién puede crear competencias y problemas.

**Quién ve qué.** La regla vale en la API, no solo en la pantalla.

- El **super-admin** ve y opera las competencias de todos. Un super-admin es una cuenta `.admin` listada en
  `SUPERADMINS` en el archivo `contests/treino/conf` (usuarios separados por espacios). Solo quien tiene acceso
  al servidor edita esa lista. No hay pantalla para eso.
- El **admin común** ve sus propias competencias y las competencias de creadores sin rol de admin (alumnos y
  monitores habilitados). No ve la competencia de otro administrador. Quitar, duplicar y exportar siguen
  la misma regla: una competencia fuera de tu alcance responde "no encontrado".

**Filtros de la lista.** Busca por nombre, id o propietario. Filtra por propietario, modo y situación (próxima, en
curso, terminada). Ordena por fecha de creación, inicio, nombre o propietario. Marca **solo las mías** para
ver solo lo que creaste. El propietario aparece con foto, nombre y enlace a su perfil.

**Id reservado.** Un id que empieza por `icpc` es de la organización de la Maratona. Solo un super-admin crea
una competencia con ese id. El asistente avisa antes y la API la rechaza.

**Quién puede crear competencias y problemas.** El mismo permiso vale para crear competencias y para crear
problemas y colecciones en la Gestión de Problemas. Las cuentas `.admin` siempre pueden. Para las demás:

- **✅ Permitidos**: escribe el usuario y una nota opcional y haz clic en **✅ Permitir**. La cuenta tiene que existir
  en el entrenamiento. Cada fila muestra a la persona, quién la habilitó y cuándo.
- **⛔ Bloqueados**: lo mismo, con **⛔ Bloquear**. Un bloqueo gana al umbral automático.
- **Umbral automático** (*Permitir automáticamente a quien resolvió ≥*): quien resolvió al menos N
  problemas puede crear. Cero lo desactiva.

## 10. Referencias

- [Manual del juez humano](MANUAL-JUIZ.md): la operación de la pestaña Evaluar y del juez principal.
- [Manual del personal de sala](MANUAL-STAFF.md): impresión, globos, etiquetas, revelación por sede.
- [Manual del competidor](MANUAL-CONTEST.md): lo que ve el alumno (distribúyelo con las contraseñas).
- [Tutorial del organizador](/treino/criar/tutorial.html): crear la competencia (asistente y CLI).
- [CLI del competidor](/contest/cli.html): envío por la terminal, con modo sin Internet.
