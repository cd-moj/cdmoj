<!-- i18n-source: MANUAL-STAFF.md blob:925b645d2465c91a33dbe510315a130be7abb5e0 -->
# MOJ: Manual del personal de sala (.staff y .cstaff)

> **Nota de traducción.** Este manual es una traducción del original en portugués. Las herramientas de línea de comandos (`moj`, `moj-contest`, `moj-comp`) muestran sus mensajes en portugués, y los ejemplos de comandos son idénticos al original.

Este manual es para ti, que formas parte del personal de sala de una competencia en el MOJ (el juez en línea). Cubre dos roles: **.staff** (personal de sala) y **.cstaff** (jefe de sede). El foco es la interfaz web.

Si quieres la visión de quien compite, consulta el `MANUAL-CONTEST.md`.

## Cómo funciona el rol

En el MOJ tu rol viene del **sufijo del usuario**:

- Una cuenta que termina en `.staff` es personal de sala.
- Una cuenta que termina en `.cstaff` es jefe de sede.

Entras a la competencia como cualquier persona (usuario y contraseña) y el sistema ya muestra las pantallas de tu rol. No necesitas hacer nada especial: basta con usar las credenciales que te entregó la organización.

Hay una diferencia importante entre los dos roles: el `.staff` **ejecuta** las tareas de la cola (reserva, imprime, entrega), mientras que el `.cstaff` **sigue** la cola en modo de solo lectura y tiene acceso a las etiquetas con contraseña. La idea central del `.cstaff` es: **ve, pero no ejecuta las acciones de la cola.**

---

## Parte 1: `.staff` (personal de sala)

Eres la persona que se queda en la sala a cargo de las impresiones y de los globos. No eres competidor: no envías código y no ves las aclaraciones.

### Pestañas que ves

| Pestaña | Para qué sirve |
|---|---|
| **Marcador** | El marcador (la versión congelada, como un usuario común). |
| **Cola de impresión** | La cola de impresión y de globos de tu sede. Es tu pantalla principal. |
| **Animeitor** | La mesa de la pantalla en modo de **solo lectura**: las fotos y la música de los equipos de tu sede. Miras y escuchas; no envías, no cambias y no descargas el paquete. |
| **Documentos** | Los documentos que publicó la organización (info sheet, cuadernillo de la competencia, hoja de límites de tiempo) para que los descargues e imprimas. |
| **Rondas** | El marcador y los envíos de las rondas terminadas (el calentamiento, por ejemplo). |
| **Salir** | Cierra tu sesión. |

### La cola de impresión (`/contest/staff/`)

> **Entra desde la máquina que tiene la impresora de la sala instalada y funcionando.** Quien imprime es tu
> máquina, desde tu navegador — el servidor solo arma el PDF. En una competencia en la que los equipos usan una
> imagen cerrada, esa imagen es la máquina de los equipos: la tuya es un escritorio común (Windows, macOS o
> cualquier Linux), con la impresora configurada. El `.cstaff`, que solo sigue la cola, entra desde cualquier
> máquina.

La pantalla de impresión es una tabla con **dos cosas en la misma cola**:

1. **Solicitudes de impresión** de los equipos: un archivo enviado por el equipo, ya armado con una portada.
2. **Globos**: tareas **automáticas**, creadas en el primer Accepted de cada par (equipo, problema). El globo muestra el **color** de ese problema, para que lleves el globo correcto a la mesa del equipo.

> **Durante el congelamiento del marcador (freeze) no entra ningún globo nuevo — y esto no es un defecto.** Un globo
> que cruza la sala le cuenta al público exactamente lo que el freeze existe para esconder: quién acaba de
> resolver. Por eso, un acierto hecho con el marcador congelado **no se convierte en tarea** y **no se entrega después**;
> la tarea simplemente no existe. Si la organización prefiere lo clásico (globos circulando durante el
> freeze), el `.admin` lo activa en **Central › Reglas** — y entonces aparecen normalmente. La página de
> **Impresión** avisa la hora del congelamiento en una franja 🧊 (antes y durante), para que nadie piense que la cola se trabó.
>
> **Las solicitudes de impresión no cambian**: el equipo sigue imprimiendo en cualquier momento, con freeze o sin él.

Solo ves la cola de **tu sede**. Las solicitudes y los globos de otras sedes no aparecen para ti.

### Cómo manejar una tarea

Cada botón es una etapa del proceso. El flujo normal es: **Reservar**, después **🖨️ Imprimir** (o
**Abrir PDF**) y, por último, **✅ Entregado**. El idioma de la pantalla es el de la competencia.
En una competencia en portugués, estos botones aparecen como *Pegar*, *🖨️ Imprimir*, *Abrir PDF* y *✅ Entregue*.
En una competencia en inglés, aparecen como *Claim*, *🖨️ Print*, *Open PDF* y *✅ Delivered* — es lo que
ves en las pantallas del [tutorial ilustrado](/contest/ajuda/staff.html).

| Botón | Qué hace |
|---|---|
| **Reservar** | Reserva la tarea para ti. Si otra persona ya la reservó, aparece un aviso. |
| **🖨️ Imprimir** | Abre el PDF combinado, llama a la impresión y marca la tarea como procesada. |
| **Abrir PDF** | Solo abre el PDF, sin imprimir. |
| **✅ Entregado** | Marca que entregaste el material en mano al equipo. |

#### Qué sale de la impresora

Primero la **portada** (equipo, universidad, usuario, número de la tarea, número de páginas y una
línea para firmar), después el documento. El código fuente sale en **fuente monoespaciada, con la
indentación original y las líneas numeradas** — se puede señalar con el dedo y decir "línea 42".

**Cada página de código se identifica sola**, arriba y abajo: arriba, la fecha y el nombre del
archivo; en el pie, el **usuario del equipo**, el archivo y el número de la tarea. En una mesa con treinta
impresiones apiladas, una hoja que se suelta de la portada sigue diciendo de quién es.

#### Modo automático

Hay una **casilla de verificación** de modo automático, y tu elección queda guardada. Con el modo automático activado y la pestaña abierta, cada nueva tarea se **reserva, imprime y marca** sola, sin que hagas clic.

Para que la ventana de impresión del navegador no aparezca en cada tarea, ejecuta el navegador en **modo quiosco**. En Chrome/Chromium, usa la opción `--kiosk-printing`.

### Calentamiento: tu ensayo (y la competencia puede tener dos rondas)

Muchas competencias hacen un **calentamiento** antes de la competencia oficial — la misma sala, las mismas cuentas, la misma
dirección. Para ti no es una simulación: las solicitudes y las tareas de globo que aparecen en la cola
son reales, y es la única oportunidad de descubrir si el mostrador funciona antes de que eso cueste caro.

Cuatro pruebas, en este orden:

1. **La impresora** — papel, tóner y la cola del sistema operativo. Imprime una tarea de principio a
   fin, y compara el color del globo en el papel con el globo que tienes en la mano.
2. **La ventana emergente** — el **🖨️ Imprimir** abre otra pestaña; si el navegador la bloquea, la tarea **no** se
   marca como impresa. Permite las ventanas emergentes de este sitio en el calentamiento, no en el minuto 3 de la competencia.
3. **El modo automático**, si lo vas a usar — con el navegador en modo quiosco (`--kiosk-printing`),
   para que nada se detenga en un diálogo de impresión.
4. **El trayecto** — lleva un papel hasta una mesa y un globo hasta un equipo. Quien descubre el número de la
   sala durante la competencia ya va con retraso.

Cuando la organización promueve la competencia oficial:

- la **numeración de las solicitudes vuelve a 1** y los **globos del calentamiento no cuentan** (la cola empieza
  limpia) — si anotaste números, se refieren al calentamiento. Si todavía hay papel del calentamiento en el
  mostrador, entrégalo **antes** de la promoción;
- tu **alcance de sede se mantiene** (es configuración, no un dato de la ronda): lo que viste en el
  calentamiento es lo que verás en la competencia;
- lo que pasó en el calentamiento se sigue pudiendo consultar en la pestaña **Rondas**.

### Lo que el `.staff` NO hace

- No envía soluciones.
- No ve las aclaraciones.
- No ve el marcador completo (ve el marcador congelado, como un usuario común).
- No ve las contraseñas ni las etiquetas de credenciales: la pantalla de etiquetas responde **acceso denegado** al `.staff`.

---

## Parte 2: `.cstaff` (jefe de sede)

Supervisas una sede. Sigues la cola de tu sede, imprimes las etiquetas con las credenciales (incluida la contraseña) y, al final, conduces la revelación del marcador de tu sede. La idea central: **ve, pero no ejecuta las acciones de la cola.**

### Pestañas que ves

| Pestaña | Para qué sirve |
|---|---|
| **Marcador** | El marcador (la versión congelada, como un usuario común). |
| **Cola de impresión** | La cola de tu sede, en modo de **solo lectura**. |
| **Etiquetas** | Las hojas de credenciales de tu sede, con contraseña. |
| **Animeitor** | La mesa de la pantalla recortada a tu sede: aquí **escribes** (envías/cambias/quitas la foto y la música de tus equipos, y descargas el paquete .zip de la sede). No cambias el predeterminado de la competencia ni ves las claves de webcast. |
| **Documentos** | Los documentos publicados de la competencia, para descargarlos e imprimirlos en la sede. |
| **Rondas** | El marcador y los envíos de las rondas ya terminadas. |
| **Salir** | Cierra tu sesión. |
| **Revelación** | La ceremonia de revelación de tu sede. Solo aparece **después de que la competencia termina para todas las sedes** y, cuando el evento usa la pantalla del Animeitor, **después de que el operador de la pantalla libera la revelación**. |

### Impresión, solo lectura (`/contest/staff/`)

Es la misma pantalla del `.staff`, pero **sin los botones de acción**: la columna de acciones queda vacía y la barra indica "solo lectura". Sigues la cola de tu sede, pero quien reserva, imprime y entrega es el `.staff`.

### Etiquetas (`/contest/badges/`), con contraseña

Aquí está lo que el `.staff` no tiene: las hojas de credenciales listas para imprimir (modelo Pimaco A4), con **nombre, usuario, contraseña, sede e institución** de cada cuenta.

- Ves solo **tu sede**: sus equipos y, de las cuentas de rol, solo las **`.staff`**. Tu propia credencial (de jefe) **no** sale en etiqueta, porque es la que abre esta pantalla.
- Sirve para imprimir las etiquetas de las mesas y las credenciales de los equipos de tu sede.
- Las opciones de administración (elegir el archivo de otra sede, incluir cuentas deshabilitadas) **no aparecen** para ti.
- **Una competencia que usa las cuentas de Entrenamiento libre no tiene contraseña en la etiqueta**: la credencial es personal
  de cada participante (la misma que usa en el entrenamiento), así que la etiqueta sale con "usa tu contraseña de
  `treino`" en su lugar. La lista trae **solo a quienes están inscritos** en esa competencia.
- **Una cuenta deshabilitada** sale con "cuenta deshabilitada" en lugar de la contraseña — deshabilitar cambia la contraseña
  por una aleatoria, así que no existe una credencial para imprimir (el admin la vuelve a habilitar con un reset).
- Todo acceso a esta pantalla queda registrado.

### Documentos de la competencia (`/contest/docs/`)

Aquí están los documentos que la organización **publicó**, listos para que los descargues e imprimas en la sede:

| Documento | Qué es |
|---|---|
| **Entorno de evaluación** | El *info sheet*: sistema y versiones de compilador, lenguajes aceptados, límites, líneas de compilación y ejecución, veredictos y penalización. Suele fijarse en la sala o entregarse con el cuadernillo. |
| **Cuadernillo de la competencia** | Portada + todos los enunciados. Es lo que va impreso en la mesa de cada equipo. |
| **Hoja de límites de tiempo** | La tabla `letra · nome · tempo limite` (con fe de erratas, si la hay). |

Cada uno sale en **PDF** (para imprimir) y **HTML**, en **portugués, inglés y español** — elige la línea del idioma que usa tu sede. El botón **abrir** muestra el archivo al instante, para revisarlo antes de mandarlo a la impresora.

- Solo ves lo que ya fue **publicado**. Antes de eso, el cuadernillo es contenido de la competencia y ni siquiera aparece — tampoco para ti.
- Si la lista está vacía, la organización todavía no publicó nada: vuelve más cerca de la competencia.
- **Revisa la versión de la portada** antes de imprimir en cantidad: si la organización corrige un enunciado, vuelve a generar el cuadernillo y sube la versión. Imprimir la víspera puede significar reimprimir.

### Marcador congelado

Tu marcador es el **congelado**, como el de un usuario común. Un administrador puede liberar la vista completa para una cuenta específica (la lista `SCORE_FULL_USERS`), pero eso es una excepción controlada por el admin.

### Revelación por sede (`/contest/score/reveal.html`)

Conduces la ceremonia de revelación de tu sede, al estilo ICPC (de abajo hacia arriba).

1. La pantalla filtra los equipos que puedes ver (tu sede).
2. Solo se desbloquea **después de que la competencia termina para todas las sedes** (el horario base más las prórrogas).
   Cuando el evento usa la **pantalla del Animeitor**, también espera que el operador de la pantalla **libere la
   revelación** (el mismo botón que libera el **Reveleitor**). Antes de eso, la pantalla dice que la revelación todavía no fue liberada.
3. Revelas posición por posición, del último al primero.
4. Toda celda con un intento después del congelamiento aparece con **?** (acierto o error), hasta que la revelas.
   Después de revelada, el error queda en **rojo** y el acierto toma el color del globo.

Descongelar todo y publicar el marcador global son acciones del **administrador**, no tuyas (lo hace con el botón **🏁 Terminar evento**, en la Central del panel — ver `MANUAL-ADMIN.md` §6½).

### Reveleitor de la pantalla (Animeitor)

Cuando la ceremonia es en la **pantalla del Animeitor**, la revelación de tu sede es un **enlace** que libera el operador de la
pantalla. Después de que lo libera, aparece el botón **Reveleitor** en tu barra, con la tarjeta **🎬 Reveleitor de tu
sede** (abrir / copiar). La tarjeta trae el **sello de la verificación** — el MOJ le pregunta al Animeitor si tiene todos los
envíos de tu sede:

- **✓ Validado**: la competencia terminó para todas las sedes, nada está en evaluación y el Animeitor tiene todo. Puedes empezar.
- **✓ Verificado**: coincidió en la última verificación; la validación final llega cuando la competencia termine para todas las sedes.
- **⚠**: faltaba algo en la última verificación. El MOJ ya lo reenvió; espera el "Validado" o habla con el operador.

El enlace muestra las respuestas posteriores al congelamiento: ábrelo solo en la computadora de la pantalla de la sede y no lo compartas. Una cuenta sin
sede definida no recibe enlace.

### Calentamiento: el ensayo de la sede

El calentamiento es cuando las credenciales que entregaste pasan por la única prueba que vale. Lo que
quieres saber al salir del calentamiento es una sola cosa: **cada equipo de tu sede entró al menos
una vez**. Una etiqueta que no inicia sesión es un problema que hay que resolver antes de que empiece el reloj — y quien
tiene la contraseña eres tú.

También es el momento del resto de la lista: comprobar que la cola muestra tus equipos y solo ellos, ver al
personal de sala de tu sede ensayando con una cola real, y recoger las **fotos** que faltan
mientras nadie está bajo presión.

> Dos cosas **no** se pierden en la promoción a la competencia oficial: tu **alcance de sede** (es
> configuración) y las **fotos y la música** que recogiste (son de la cuenta del equipo, no de la
> ronda). Lo que se archiva es la ronda: marcador, envíos, cola de impresión, aclaraciones.

### Lo que el `.cstaff` NO hace

- No envía soluciones.
- No ejecuta las acciones de impresión: reservar, imprimir y entregar dan **acceso denegado**.
- No ve las etiquetas de otras sedes.
- No descongela ni publica el marcador global.

---

## Tabla resumen: lo que cada rol puede y no puede hacer

| Acción | `.staff` | `.cstaff` |
|---|:---:|:---:|
| Ver el marcador congelado (Marcador) | Sí | Sí |
| Ver la cola de impresión de tu sede | Sí | Sí (solo lectura) |
| Reservar, imprimir y entregar tareas de la cola | Sí | No (acceso denegado) |
| Usar el modo automático de impresión | Sí | No |
| Ver las etiquetas con contraseña (Etiquetas) | No (acceso denegado) | Sí (solo tu sede) |
| Descargar los documentos publicados (Documentos) | Sí | Sí |
| Generar/publicar documentos | No (es del admin/juez principal) | No (es del admin/juez principal) |
| Conducir la revelación de tu sede (🏆) | No | Sí (después de que terminen todas las sedes y, con la pantalla del Animeitor, después de la liberación) |
| Ver la mesa de la pantalla (Animeitor) de tu sede | Sí (solo mirar/escuchar) | Sí |
| Enviar/cambiar la foto y la música de los equipos de la sede | No (acceso denegado) | Sí (solo tu sede) |
| Descargar el paquete .zip de la pantalla | No | Sí (recortado a la sede) |
| Cambiar la foto/música PREDETERMINADA de la competencia | No | No (es del `.animeitor`/admin) |
| Ver o crear claves de webcast | No | No (es del `.animeitor`/admin) |
| Enviar soluciones (competir) | No | No |
| Ver las aclaraciones | No | No |
| Ver el marcador completo | No | No (salvo liberación del admin) |
| Ver las etiquetas de otras sedes | No | No |
| Descongelar todo / publicar el marcador global | No | No (es del admin) |

---

## Referencias

- **Tutorial web de tu rol** (con capturas de las pantallas, PT/EN/ES): `/contest/ajuda/staff.html`
  y `/contest/ajuda/cstaff.html` — se abre con el botón **📖 Cómo funciona este rol** en tu pantalla.
- **[MANUAL-ANIMEITOR.md](MANUAL-ANIMEITOR.md)**: quien opera la pantalla (el dueño de la foto/música predeterminada
  y de las claves de webcast que ustedes NO tienen).

- Para la visión de quien compite (inicio de sesión, envío de soluciones, marcador, aclaraciones, impresión y backup), consulta el `MANUAL-CONTEST.md`.
