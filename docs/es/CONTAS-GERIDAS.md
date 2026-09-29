<!-- i18n-source: CONTAS-GERIDAS.md blob:1fc6fa8f7dc76d01cd3e8e82743b9fd4e4ad0a6b -->
# Cuentas gestionadas (menores de edad, sin Telegram)

> **Nota de traducción.** Este manual es una traducción del original en portugués. Las herramientas de línea de comandos (`moj`, `moj-contest`, `moj-comp`) muestran sus mensajes en portugués, y los ejemplos de comandos son idénticos al original.

El registro normal del Entrenamiento libre se confirma por **Telegram**. Eso excluye a quien no
puede tener una cuenta en la aplicación de mensajería, típicamente los **menores de edad**. La
**cuenta gestionada** es la solución: la crea un `.admin` **responsable**, no tiene ningún vínculo
con Telegram y tiene bloqueos de privacidad que **se levantan automáticamente a los 18 años**.

## El modelo en 30 segundos

| | Cuenta normal | Cuenta GESTIONADA (menor) |
|---|---|---|
| Se crea | registro web + Telegram | pestaña **🧒 Cuentas gestionadas** de `/treino/admin/` |
| Contraseña | por DM del bot | **generada y mostrada UNA vez** al admin |
| Olvidé la contraseña | `/trocarsenha` en el bot | **solo el admin** (🔑 en la pestaña) |
| Perfil público | opcional (público por defecto) | **siempre privado** (el servidor se niega a hacerlo público) |
| Telegram | opcional | **bloqueado** |
| A los 18 | — | los bloqueos **se levantan solos**: puede vincular Telegram y abrir el perfil |

La marca queda en el `account.json` del usuario:

```json
"managed": { "by": "prof.admin", "note": "turma A, Escola X",
             "birthdate": "2011-03-14", "expires_at": null, "created_at": 1785000000 }
```

La condición de **menor** se calcula a partir de la fecha de nacimiento en cada acceso. Nada se
"cambia" a los 18: las restricciones simplemente dejan de aplicarse. La marca `managed` se mantiene
(historial/listado, con la etiqueta `18+`), y el perfil sigue privado hasta que el propio usuario
lo abra.

## Lo que el menor puede y no puede hacer

- **Puede**: todo lo del entrenamiento: resolver, enviar, ver su propio perfil/estadísticas,
  editar nombre/universidad/editor/foto y cambiar su propia contraseña (si conoce la actual).
- **No puede (hasta los 18)**:
  - **hacer público el perfil**: `profile_is_public` lo corta en el servidor. La cuenta no
    aparece en el "Top 10" ni en "Resueltos recientemente" de la página de inicio. Para los demás,
    el perfil se ve con el candado 🔒 (la misma regla del perfil privado común);
  - **vincular Telegram**: `POST /treino/telegram/link-start` responde 403
    `managed_minor`.
- **Vencimiento (opcional)**: si `expires_at` ya venció, el inicio de sesión responde 403
  `account_expired`. El mensaje está en portugués: `Conta expirada — fale com o responsável que a criou`
  (cuenta vencida: habla con el responsable que la creó). Para renovar, edita o borra la fecha en
  la pestaña.

## Operación (pestaña 🧒 Cuentas gestionadas de `/treino/admin/`)

- **➕ Nueva cuenta**: nombre completo + **fecha de nacimiento** (obligatorios), usuario opcional
  (vacío = se genera a partir del nombre, `nome.sobrenome`, sin duplicados), nota libre y
  vencimiento opcional.
- **📥 Crear en lote**: una línea por cuenta con el formato `Nome Completo;AAAA-MM-DD`, con
  nota y vencimiento comunes. La pantalla muestra este modelo en el idioma de la interfaz
  (`Nombre Completo;AAAA-MM-DD`). Es ideal para un grupo de clase.
- **Credenciales**: la respuesta muestra el **usuario + la contraseña de cada cuenta creada, UNA
  sola vez**, con "📋 Copiar todo". La contraseña **no se puede recuperar después**: anótala o
  imprímela en ese momento (el entrenamiento no tiene pantalla de etiquetas: `/contest/badges`
  rechaza `contest=treino` a propósito, para no volcar toda la base en texto plano).
- **Por cuenta**: 🔑 nueva contraseña (se muestra una vez; cierra las sesiones) · ✎ editar
  nota/nacimiento/vencimiento · ⏻ deshabilitar (contraseña centinela + cierra las sesiones) /
  ▶ habilitar (nueva contraseña) · ✕ quitar (se archiva en `.removed-users/`, los envíos se
  conservan).
- **Filtros**: por texto y **"solo las mías"** (cuentas de las que yo soy el responsable).
- **Auditoría**: `managed-create/reset/update/remove` entran en el registro de auditoría con el
  admin que hizo la acción (pestaña 📜 Actividad).

## Por la API (mismo efecto; Bearer de `.admin`)

| Ruta | Uso |
|---|---|
| `GET  /treino/admin/managed-users` | lista `{login,fullname,by,note,birthdate,minor,expires_at,disabled}` |
| `POST /treino/admin/managed-create` | `{users:[{fullname,birthdate,login?,note?,expires_at?}]}` (1..500) → `{created:[{login,password,…}], skipped}` |
| `POST /treino/admin/managed-reset` | `{login}` → nueva contraseña (una vez) |
| `POST /treino/admin/managed-update` | `{login, note?, birthdate?, expires_at?\|null, disabled?}` |
| `POST /treino/admin/managed-remove` | `{login}` |

## Privacidad y datos (nota sobre la LGPD)

- El único dato extra que se guarda es la **fecha de nacimiento**, necesaria para el
  desbloqueo automático a los 18, más la nota libre del responsable (evita datos sensibles en
  la nota; todos los admins la ven).
- El perfil del menor es **invisible al público por diseño** (control en el servidor, no en la
  interfaz): estadísticas, foto e historial solo para el propio usuario y para los admins.
- La contraseña **no queda almacenada en texto plano en ningún lugar nuevo** además del
  `account.json` (modelo estándar de la plataforma) y solo viaja en la respuesta de
  creación/restablecimiento.

## Para quien mantiene el código

- Helpers: `managed_json` / `is_managed_minor` en `server/api/v1/lib/profile.sh`.
  `is_managed_minor` es el gate que usan `profile_is_public`, el POST de `/treino/profile`
  y el `link-start`. Fecha ilegible = se trata como menor (fail-safe).
- La interfaz del perfil (`web/treino/perfil/perfil.js`) oculta el vínculo con Telegram y bloquea
  la casilla de privacidad cuando `GET /treino/profile` devuelve `managed.minor:true`.
- Protección colateral: `POST /contest/admin/users-set-password` **rechaza `contest=treino`**
  (un POST restablecería todas las cuentas de la plataforma).

## Ver también

- [`MANUAL-TREINO.md`](MANUAL-TREINO.md): el manual del estudiante (registro normal, inicio de sesión).
- [`PERFIL.md`](PERFIL.md): el perfil público y los logros.
- [`API.md`](API.md): contratos completos de las rutas.
