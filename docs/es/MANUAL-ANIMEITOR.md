<!-- i18n-source: MANUAL-ANIMEITOR.md blob:cc164fe430e20209a05f71d7e2a12ed0dc81e3a0 -->
# MOJ: Manual de la pantalla (`.animeitor`)

> **Nota de traducción.** Este manual es una traducción del original en portugués. Las herramientas de línea de comandos (`moj`, `moj-contest`, `moj-comp`) muestran sus mensajes en portugués, y los ejemplos de comandos son idénticos al original.

Este es el manual de quien **opera la pantalla** de una competencia en el MOJ: el marcador en el
proyector, las fotos y la música que animan la remontada, y la ceremonia de revelación.

> **Tutorial web con capturas de pantalla** (PT/EN/ES): `/contest/ajuda/animeitor.html` — se abre con el botón
> **📖 Cómo funciona este rol** en la propia página de la pantalla.
> **Documento técnico**: la integración por la API del Animeitor en [ANIMEITOR.md](ANIMEITOR.md); el paquete
> legado (formato BOCA) en [WEBCAST.md](WEBCAST.md).

## Cómo funciona el rol

El rol viene del **sufijo del usuario**: una cuenta terminada en `.animeitor` es la mesa de la pantalla. La
crea el administrador (panel **Personas › Cuentas**); nadie se vuelve `.animeitor` por
autorregistro.

La cuenta existe para alimentar la pantalla con tres cosas: el **marcador** (el MOJ lo envía al Animeitor por la
API — sección 📡 más abajo), las **fotos** de los equipos y la **música** de los equipos. Queda **fuera** del marcador, de la lista de equipos,
de las estadísticas, de los globos y de las etiquetas — no es un competidor.

El **administrador entra en la misma página con los mismos poderes**, por la tarjeta *🎥 Pantalla (Animeitor)* de la Central
del panel o por el enlace en *Evento › Equipos*. En una competencia con usuarios compartidos (`USERS_FROM`),
esa es la **única** puerta para subir foto/música.

## Pestañas que ves

| Pestaña | Para qué sirve |
|---|---|
| **Marcador** | El marcador, **siempre descongelado** — incluso antes de que empiece la competencia. Es la razón de ser del rol: quien anima la remontada necesita ver la clasificación real. |
| **Animeitor** | Tu mesa: 📡 el envío al Animeitor (marcadores, sedes, alimentador, verificación, reveleitor), fotos y música de los equipos y, plegadas, las claves de streaming legadas. |
| **Estadísticas** | Números de la competencia (envíos por problema, lenguajes, línea de tiempo) — buen material para los intervalos. |
| **Revelación** | La ceremonia **experimental del MOJ** (ver el aviso abajo). Disponible en **cualquier** momento para ti, para ensayar antes de que llegue el público. |
| **Salir** | Cierra la sesión. |

## ⚠ La ceremonia oficial es el Animeitor, no la página del MOJ

La página `/contest/score/reveal.html` (botón **Revelación**) es **EXPERIMENTAL**: sirve para
ensayos, para una sede pequeña, o como plan B si no es posible montar el Animeitor. La ceremonia
oficial de un evento la conduce el **Animeitor, de Emílio Wuerges** — el sistema que este rol
entero existe para alimentar.

El flujo oficial es la sección **📡 Animeitor (pantalla)** de tu mesa: el MOJ **empuja** el evento, los marcadores, los
envíos y el reloj al servidor del Animeitor, y la revelación de cada sede sale de allá. El Animeitor anima la
remontada y mantiene el congelamiento hasta la hora de la revelación.

## 📡 Animeitor por la API (la forma actual)

1. **Conexión.** El MOJ ya tiene una **clave propia en el Animeitor** (la *clave del MOJ*): la página dice "Clave del MOJ —
   no hay nada que configurar". La clave nunca aparece en la página. Si tu evento usa otro servidor del Animeitor, o si
   recibiste una clave tuya, abre "usar una clave propia" y guarda el usuario y el token — la tuya tiene prioridad sobre la del MOJ, y
   "eliminarla y usar la clave del MOJ" deshace el cambio. La clave del MOJ solo vale en el servidor predeterminado.
2. **URL pública del MOJ.** Es de donde la pantalla obtiene la foto y la música de cada equipo; revísala.
3. **Marcadores y sedes.** El MOJ propone el general, uno por cohorte y uno por país, con las sedes; ajusta nombres y
   medallas y guarda. Una competencia de una sola sede recibe la sede `Geral` (sin sede no hay enlace de revelación).
4. **📡 publicar en la pantalla** e **▶ iniciar el alimentador** (reloj cada segundo y envíos cada 2 s). El nombre
   del evento es el id de la competencia; un nombre que ya pertenece a otra competencia del MOJ se rechaza.
5. **Verificación.** El MOJ le pregunta al Animeitor, sede por sede, si tiene **todos** los envíos, con la respuesta
   correcta — automáticamente, cada 5 minutos durante la competencia y, después del final, hasta la **verificación final**. Lo que falte
   o no coincida se reenvía automáticamente. La línea "Verificación" del estado muestra el último resultado; **🔎 verificar ahora**
   verifica en el momento. "✓ VALIDADO" = la competencia terminó para todas las sedes, nada está en evaluación y el Animeitor
   lo tiene todo. Los envíos de equipos fuera de cualquier sede no entran en la verificación (la página dice cuántos).
6. **🎬 liberar los enlaces de revelación a las sedes.** Antes de liberar, la mesa verifica y muestra el resultado en la
   pregunta de confirmación. Cada jefe de sede (y cada miembro del staff) pasa a ver el enlace de su sede, **con el sello de la verificación**
   ("✓ Validado", "Verificado" o "⚠"). El enlace muestra las respuestas después del congelamiento: trátalo como una contraseña.

## 🎥 Claves de streaming (legado)

El paquete en el formato del BOCA, que el Animeitor antiguo consultaba por clave, sigue en la mesa, plegado.

Cada clave se convierte en una **URL** que el sistema Animeitor (u otro visualizador compatible) consulta en bucle y
de la que recibe el paquete del marcador. Cada clave declara **cuál** marcador sirve: el general, o el de una cohorte
específica cuando la competencia tiene equipos invitados.

1. Elige el marcador, dale una etiqueta a la clave (`telão principal`, `transmissão YouTube`) y créala.
2. **copiar** pone la URL en el portapapeles; **probar** la abre para comprobar que el paquete llega.
3. La tabla muestra **cuántas consultas** recibió la clave y el **último acceso con IP** — así
   sabes que el proyector realmente está conectado.

> ⚠ **La clave abre el marcador DESCONGELADO, sin inicio de sesión.** Quien tiene la URL ve la clasificación real
> durante la competencia. Trátala como una contraseña: una clave por pantalla y **revócalas todas después del evento**.
> Revocar es inmediato (la clave pasa a responder 404, y el intento queda registrado).

## 📷 Fotos y ♪ música de los equipos

Cada equipo puede tener una **foto** (aparece cuando resuelve) y un **mp3** (suena en ese momento). La
galería se abre en el filtro **⚠ Pendientes** — exactamente los equipos que todavía no tienen foto o música.

- **⬆ Subir en lote** es el camino rápido: arrastra decenas de archivos; el **nombre del archivo es el
  usuario** del equipo (`time-alfa.jpg`, `time-alfa.mp3`). Las fotos y la música pueden ir juntas.
- La **foto** la convierte y la redimensiona el servidor (webp + miniatura). La **música** va tal como
  llegó y tiene que ser un **mp3 de verdad** (hasta 15 MB) — el servidor revisa el archivo, no la extensión.
- **⬇ Descargar paquete (.zip)**: todo en un archivo (fotos, música y un CSV de los equipos) — es lo que se le entrega
  a quien opera el visualizador.
- Los **jefes de sede** (`.cstaff`) suben las fotos **de su sede**. En una competencia con varias sedes,
  deja que ellos las recojan localmente y tú solo revisas la lista de pendientes.

### La foto/música PREDETERMINADA

Un equipo sin foto no arruina el espectáculo: el MOJ responde con la **predeterminada de la competencia** (y lo mismo para la
música). La tarjeta en la parte superior de la galería cambia esa predeterminada — una imagen con la identidad del evento, un
jingle — o vuelve a la predeterminada de fábrica del MOJ. **Solo tú y el administrador** cambian la predeterminada.

En el paquete `.zip`, la foto predeterminada se copia por equipo (es pequeña) y la música predeterminada va **una vez** en la
raíz (megabytes × mil equipos, no).

### En una competencia 🕵️ SÚPER SECRETA

La galería funciona igual: las fotos y la música siguen visibles para quien inició sesión en la competencia
(pantalla, sede, administrador) — el MOJ las obtiene con **tu sesión**, y quien no inició sesión no ve
ni oye nada, que es el objetivo del modo secreto. La única diferencia que se nota está en el ♪: la pista se
descarga completa antes de sonar (el botón muestra **⏳**), así que una canción grande tarda algunos
segundos en empezar. Si operas la pantalla en ese modo, presiona ♪ una vez en cada pista antes de la
competencia — la segunda vez suena de inmediato.

> Si las fotos aparecen en blanco en una competencia secreta, el servidor está actualizado pero el
> navegador tiene la versión antigua de la página en caché: recarga con Ctrl+Shift+R.

## Ensayo general: la víspera y el calentamiento

Muchas competencias tienen un **calentamiento** antes de la competencia oficial — misma sala, mismas cuentas, misma
dirección. Es el ensayo general de la sala y, por lo tanto, de la pantalla: el marcador se llena de envíos
reales, así que es el momento de apuntar el proyector, activar la clave de webcast en el Animeitor **de
verdad** y ver las fotos y la música aparecer en la pared. Una pantalla probada solo con el marcador vacío es una pantalla
no probada.

> Nada de lo que montes se pierde en la promoción a la competencia oficial: **claves, fotos, música y
> las predeterminadas** son configuración de la competencia, no datos de la ronda. Lo que se archiva es la ronda — el
> marcador y sus envíos, que siguen accesibles como ronda cerrada.

La lista de la víspera, en orden:

1. Revisa la **conexión** (clave del MOJ o la tuya), **publica** e inicia el **alimentador**; abre el enlace público de
   cada marcador en la máquina que va a proyectar.
2. Abre la galería en **⚠ Pendientes** y persigue las fotos que faltan (pídeselas a los jefes de sede).
3. Define la **foto y la música predeterminadas** con la identidad del evento.
4. Descarga el **.zip** y guárdalo en la máquina del espectáculo como plan B.
5. **Ensaya** la página de revelación y prueba el sonido en el audio de la sala.
6. Durante el **calentamiento**: pon la pantalla real en la pared y mírala llenarse — fotos, música, marcador y la línea
   **Verificación** coincidiendo.
7. A la hora de la ceremonia: espera el **✓ VALIDADO** y **libera los enlaces de revelación** a las sedes.
8. Si usaste claves de streaming legadas: **revócalas todas** después del evento.

## Lo que el `.animeitor` NO hace

| Intento | Respuesta |
|---|---|
| Enviar solución / ver enunciado | Rechazado (la cuenta no compite) |
| Cola de impresión, globos, archivo del competidor | Rechazado (es de la `.staff`) |
| Etiquetas de credenciales (contraseñas) | Rechazado (es de la `.cstaff`) |
| Responder aclaraciones / publicar noticia | Rechazado |
| Foto o música de una cuenta de ROL (staff, juez…) | Rechazado — los roles no son equipos |
| Cualquier página de administración | Rechazado |

> ⚠ **Dos asimetrías que sorprenden**: a diferencia del personal de sala, el `.animeitor` **no** ve
> documentos de la competencia antes del inicio y **no** ve rondas archivadas que no fueron publicadas. Si
> necesitas el cuadernillo para preparar la pantalla, pídele al administrador que lo publique.

## Tabla resumen: pantalla × sede

| Acción | `.animeitor` | `.cstaff` (sede) | `.staff` (sala) |
|---|:---:|:---:|:---:|
| Ver la galería de fotos/música | Todos los equipos | Solo la sede | Solo la sede |
| Subir/cambiar/quitar foto y música | Sí | Sí (solo la sede) | **No** |
| Descargar el paquete `.zip` | Completo | Recortado a la sede | **No** |
| Cambiar la foto/música **predeterminada** de la competencia | **Sí** | No | No |
| Publicar en el Animeitor, alimentador, **verificación** | **Sí** | No | No |
| Liberar los enlaces de revelación | **Sí** | Recibe el de la sede, con el sello de la verificación | Ídem |
| Ver/crear/revocar **claves de webcast** (legado) | **Sí** | No | No |
| Marcador | Siempre descongelado | Congelado | Congelado |
| Estadísticas | Sí | No | No |

## Referencias

- **[ANIMEITOR.md](ANIMEITOR.md)**: la integración por la API (clave del MOJ, marcadores/sedes, alimentador,
  verificación, reveleitor) y las decisiones técnicas.
- **[WEBCAST.md](WEBCAST.md)**: el protocolo del paquete legado (formato del BOCA).
- **[MANUAL-STAFF.md](MANUAL-STAFF.md)**: el personal de sala y el jefe de sede — quienes comparten la página
  de la pantalla contigo.
- **[MANUAL-ADMIN.md](MANUAL-ADMIN.md)**: el organizador — quien crea tu cuenta y publica los
  documentos.
