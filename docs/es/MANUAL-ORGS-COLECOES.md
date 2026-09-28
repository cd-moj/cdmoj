<!-- i18n-source: MANUAL-ORGS-COLECOES.md blob:9aac199c01a6f43778c4f0e5f7bc9771264c685b -->
# Gestión de orgs y colecciones (manual del gestor de problemas)

> **Nota de traducción.** Este manual es una traducción del original en portugués. Las herramientas de línea de comandos (`moj`, `moj-contest`, `moj-comp`) muestran sus mensajes en portugués, y los ejemplos de comandos son idénticos al original.

Este manual es para quien **crea y organiza problemas** en el MOJ: profesores, ayudantes y
organizadores. Explica los dos ejes de organización (**org** y **colección**), qué hace cada uno
y **cómo operar cada cosa en las DOS interfaces**: la web (Gestión de Problemas) y la CLI
`moj`. Los dos clientes hablan con la misma API, así que cualquier operación se puede hacer desde
cualquiera de los dos. Usa el que te resulte más cómodo.

> El **formato** de los metadatos (lo que queda en el `.moj-meta.json`, cómo se arma el id) se describe,
> con detalle canónico, en [PACOTE.md](PACOTE.md) (secciones 7–9). Aquí el foco es el **uso**.

## Los dos ejes, en 30 segundos

| | **ORG** | **COLECCIÓN** |
|---|---|---|
| Para qué sirve | **Acceso**: quién puede ver/editar el problema | **Agrupación**: etiqueta para navegar/organizar |
| Cuántas por problema | **Exactamente 1** (es el prefijo del id `org#prob`) | **Varias** (m:n): el problema puede estar en todas las que quieras |
| ¿Da acceso? | **Sí**: un miembro de la org edita los problemas de la org | **No**: es solo una etiqueta; no permite que nadie edite |
| ¿Cambia el id? | Sí: el problema es `<org>#<prob>` | No |
| Ejemplo | `apc`, `obi-problems`, `mdp-2026-1` | `problemas-apc`, `Prova EDA1 2026/1`, `dificil` |

Regla de oro: **la org decide QUIÉN modifica; la colección decide CÓMO lo encuentras.** Son
ortogonales: dos problemas de orgs diferentes pueden estar en la misma colección, y una org puede
tener problemas repartidos en varias colecciones.

Todo usuario nace con una **org implícita con su propio usuario** (ej.: `ana.silva`),
siempre privada. Ahí quedan tus borradores si no creas otra org.

---

## Parte 1 — ORGs

### Crear una org

Una org suele representar una **asignatura, grupo o competencia** (ej.: una por semestre de
una materia, una para cada olimpiada). El nombre va **en minúsculas y sin espacios**: es el **prefijo del id** `<org>#<prob>` (`^[a-z0-9][a-z0-9._-]{1,63}$`; lo que se convierte en subdominio es el id de la *competencia*, no la org). Crear una org exige el **mismo permiso** que crear un problema o una competencia.

| Web (Gestión de Problemas) | CLI |
|---|---|
| En el **editor de un problema nuevo**, en la parte superior de la pestaña *Enunciado*, haz clic en **“+ nueva org”**. O ve a la pestaña **Orgs** y créala desde ahí. | `moj mkdir <org>`  · o `moj org create <org> [--public] [--members a,b] [--admins c]` |

Quien crea la org pasa automáticamente a ser **miembro y admin** de ella. Un problema **solo se puede guardar
dentro de una org**. Por eso el editor pide crear la primera antes de permitir guardar.

### Miembros y admins

- **Miembro** de la org: **edita todos los problemas de la org**, incluso los privados (es el modelo de
  autoría compartida: los coautores de una asignatura son miembros de la misma org).
- **Admin** de la org: además de editar, **gestiona miembros/admins** y el **permiso de público** (abajo).

| Web | CLI |
|---|---|
| Pestaña **Orgs** → elige la org → gestiona miembros/admins: **haz clic en la estrella** del chip del miembro (⭐ admin ↔ ☆ miembro) para **promover/degradar**; ✕ lo quita de la org. Quien creó la org es siempre admin (no se puede degradar). En el editor de un problema también está el recuadro **Miembros de la org** (agrega un coautor a la org de ese problema). | `moj share <org> <login>` (agrega un miembro) · `moj org members <org> --add a,b --remove c --admins-add d --admins-remove e` |

> El acceso a un problema **privado** lo decide **solo la org**: ni siquiera un `.admin` global del MOJ ve el
> contenido/paquete de un problema privado de una org de la que no es miembro. Las competencias en elaboración
> no se filtran, por construcción.

### Quién PUEDE ser miembro (validado desde 2026-08-20)

Al agregar a alguien a una org, ya no se acepta cualquier texto. Cada usuario que **entra** (como miembro
o admin, por la web, por `moj share` o por `moj org members --add`) se verifica en el momento:

| Situación | Respuesta |
|---|---|
| Formato inválido (`Inv@lido`) | **422** `login_invalid` |
| No existe la cuenta en el entrenamiento | **404**: `Não existe conta no treino: 'fulano'` ("No existe una cuenta en el entrenamiento: 'fulano'") |
| Existe, pero **no puede crear problemas** | **403**: `'fulano' não pode criar problemas (motivo) — membro de org edita o acervo dela` ("'fulano' no puede crear problemas (motivo): un miembro de una org edita el acervo de la org") |

El criterio de "puede crear problemas" es el **mismo** que para crear un problema o una competencia. Una cuenta
`.admin` siempre puede. Para las demás cuentas, deciden la lista de autorizados y la de bloqueados del panel del
entrenamiento. Si el usuario no está en ninguna de las dos, vale el umbral de problemas resueltos. Si tu ayudante
fue rechazado, la solución es autorizarlo en el **🛡 Panel de administración** del entrenamiento, sección
**Quién puede crear competencias y problemas**. No intentes rodearlo por otra pantalla.

El rechazo es **atómico**: si envías cinco usuarios y uno es inválido, **ninguno** entra (en el caso del
`create`, la org ni siquiera se crea). **Quitar** no valida nada: siempre puedes quitar
las entradas inválidas que quedaron de antes.

### Permiso de público (`public_allowed`): la protección antifiltración

Toda org nace **privada**: sus problemas **no se pueden publicar** en el Entrenamiento libre. Esto es
intencional: es la protección contra filtrar una competencia en elaboración. Para que los problemas de una org
puedan ser públicos, un **admin de la org** tiene que **permitir problemas públicos en la org** (activar `public_allowed`).

| Web | CLI |
|---|---|
| Pestaña **Orgs** → la org → columna **Bloqueo**: haz clic en el estado para alternar entre **permite público** (`public_allowed` activado) y **privada 🔒** (`public_allowed` desactivado). | `moj org public <org> on`  /  `moj org public <org> off` |

> ⚠️ **Desactivar el permiso de público DESPUBLICA en cascada** todos los problemas públicos de esa org (vuelven
> a privados en el acto). Actívalo con calma; desactívalo con más calma todavía.

La **org implícita** (`<tuusuario>`) es **siempre privada** y no puede permitir problemas públicos: es tu
borrador personal. Para publicar, mueve el problema a una org que permita problemas públicos.

### Eliminar una org

Solo se puede eliminar una org **vacía** (sin ningún problema). La org implícita nunca se elimina.

| Web | CLI |
|---|---|
| Pestaña **Orgs** → **eliminar org** (solo se habilita si está vacía). | `moj org rm <org>` |

### Mover un borrador a otra org

Como la org es el prefijo del id, mover un problema **cambia el id** (`orgA#p` → `orgB#p`). Solo vale para un
problema **no público** (409 `is_public`; un problema privado que ya se usó en una competencia sí se mueve). Necesitas ser miembro de las
**dos** orgs.

| Web | CLI |
|---|---|
| En la lista de problemas, el botón **“Mover”** (aparece solo en tus borradores). | `moj mv <id> <org-destino>` |

---

## Parte 2 — COLECCIONES

Una colección es una **etiqueta libre** para agrupar problemas. Puede tener **espacios y tildes** (ej.:
`Prova EDA1 2026/1`, `Geometria`, `iniciantes`). Un problema puede estar en **varias**. Sirve
para: la navegación en el Entrenamiento libre, los filtros de la búsqueda y el **sorteo** de problemas al crear una
competencia. **Una colección no da acceso a nada**: es pura organización.

El registro de colecciones es **curado**: para marcar un problema en una colección, esta tiene que **existir**
(primero creas la colección). Cada colección tiene un **dueño** (quien la creó).

**Un problema sin colección marcada queda en la colección de la org**: la que tiene el mismo nombre de la org (`grub`
para la org `grub`), creada junto con ella. Vale en todas partes: en la Gestión, en el Entrenamiento libre y en el
sorteo al crear una competencia. Para sacar un problema de la colección de la org, marca otra colección.

### Crear una colección

| Web | CLI |
|---|---|
| Pestaña **Colecciones** de la Gestión de Problemas → campo *nueva colección* → **“+ Colección”**. (También puedes crearla desde el panel de colecciones dentro del editor.) | `moj collection create "<nome livre>"` |

### Marcar / desmarcar un problema en una colección

| Web | CLI |
|---|---|
| En el **editor** del problema, panel de colecciones: marca/desmarca las etiquetas y haz clic en **Guardar**. | `moj collection add <id> "<nome>"`  ·  `moj collection remove <id> "<nome>"` |

### Navegar y listar

| Web | CLI |
|---|---|
| Pestaña **Colecciones** (filtro **“solo mías”**; haz clic en el nombre para ver los problemas). En el **Entrenamiento libre**, el explorador agrupa las colecciones por prefijo y filtra por texto. | `moj collection ls`  ·  `moj collection show "<nome>"` |

### Renombrar / eliminar una colección

Solo el **dueño** de la colección (o un `.admin`) la renombra/elimina. La operación vuelve a etiquetar los N problemas
en **segundo plano** (el servidor hace el trabajo pesado sin bloquearse); la CLI **sigue el proceso hasta el final**
y muestra el progreso.

| Web | CLI |
|---|---|
| Pestaña **Colecciones** → renombrar/eliminar (dueño/admin); un **banner de progreso** ("⏳ re-tag en curso: N/M") aparece en la misma pestaña hasta que el job termina. | `moj collection rename "<nome>" "<novo>"`  ·  `moj collection delete "<nome>"`  ·  `moj collection status` (sigue los jobs) |

> Renombrar/eliminar no afecta el **acceso** de nadie (la colección es solo una etiqueta): solo cambia/quita la
> etiqueta en los problemas.

---

## Permisos y trampas (el resumen que evita dolores de cabeza)

- **Un miembro de la org ve y edita todo lo de la org**, incluso los problemas privados. Coautoría = miembro.
- **Lo privado no se filtra**, ni siquiera a un `.admin` global; el acceso lo decide la membresía de la org.
- **La colección no propaga acceso**: poner el problema de otra persona en tu colección **no** te
  da permiso para editarlo. Para editarlo, necesitas ser miembro de su org.
- **Lo público exige una org que lo permita**: publicar un problema solo funciona si la org tiene
  `public_allowed` activado; si no, el botón/la publicación lo rechaza.
- **Desactivar el permiso de público de la org despublica en cascada**: cuidado al cambiar ese permiso.
- **Renombrar/eliminar una colección es asíncrono**: responde en el acto y vuelve a etiquetar en segundo plano;
  en la web, la pestaña Colecciones muestra un banner de progreso; en la CLI, `moj collection status`.
- **Mover un problema cambia el id**: los enlaces/referencias antiguos al id viejo dejan de resolverse.

## Recetas rápidas

**Armar una asignatura desde cero (privada):**
1. `moj mkdir eda1-2026` (o “+ nueva org” en el editor): nace privada.
2. Crea los problemas dentro de ella (quedan privados, buenos para una competencia).
3. `moj collection create "Prova 1 EDA1 2026/1"` y marca en ella los problemas de la competencia, para
   organizarlos/sortearlos.

**Abrir problemas al Entrenamiento libre:**
1. Un admin de la org permite problemas públicos: `moj org public eda1-2026 on` (o la pestaña Orgs en la web).
2. Publica cada problema: `moj publish eda1-2026#<prob>` (o la opción **volver público** en el editor, pestaña **Publicación**):
   el servidor valida + calibra y el problema aparece en el Entrenamiento libre.

**Compartir la autoría con un colega:**
- `moj share eda1-2026 colega.login` (o el recuadro **Miembros de la org** en el editor): el colega pasa a editar todos
  los problemas de la org.

## Ver también

- **[PACOTE.md](PACOTE.md)**: el formato canónico (lo que queda en el `.moj-meta.json`, el id, las
  secciones 7 (ORG), 8 (COLECCIÓN) y 9 (ORG × COLECCIÓN)).
- **Tutoriales paso a paso**: [Crear problemas en la CLI](/problemas/tutorial.html) y
  [Crear y gestionar una competencia](/treino/criar/tutorial.html).
- **[API.md](API.md)**: las rutas `/orgs/*` y `/problems/collection*` para quien automatiza.
