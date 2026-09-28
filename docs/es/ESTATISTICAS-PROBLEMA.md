<!-- i18n-source: ESTATISTICAS-PROBLEMA.md blob:cf1f671fce64d14299108da488a974cbb9164f18 -->
# Estadísticas del problema: cómo se calcula cada métrica

> **Nota de traducción.** Este manual es una traducción del original en portugués. Las herramientas de línea de comandos (`moj`, `moj-contest`, `moj-comp`) muestran sus mensajes en portugués, y los ejemplos de comandos son idénticos al original.

Este documento explica, sección por sección, cómo la página **Estadísticas del problema** del
Entrenamiento libre (`/treino/problema/stats/?id=<problema>`) calcula lo que muestra, incluidas
las decisiones estadísticas y las limitaciones honestas de cada número. La fuente de verdad es el
endpoint `GET /treino/problem-stats` (contrato completo en [API.md](API.md)); esta página
describe la **semántica**.

## De dónde vienen los datos

Cada cuenta del entrenamiento guarda su propio historial de envíos (1 línea por envío:
problema, **lenguaje**, **veredicto** y **hora** en epoch). La estadística de un problema es la
agregación de todas las líneas de todos los usuarios para ese problema, **solo del Entrenamiento
libre**: los envíos hechos en competencias de grupos de clase no entran.

- **Solo los problemas públicos** tienen estadística (un problema privado responde 404: una
  competencia en preparación no se filtra ni siquiera por su existencia).
- El resultado queda en una **caché por evento**: se regenera cuando hay un envío nuevo
  (cualquier juzgamiento toca una marca global), con un mínimo de 2 minutos entre
  regeneraciones durante las ráfagas. Sin envíos nuevos, el número no cambia, así que la caché
  vale indefinidamente.
- Los **veredictos** se agrupan en las familias canónicas: `Accepted`, `Wrong Answer`,
  `Time Limit Exceeded`, `Runtime Error`, `Compilation Error` y `Outro` (lo que no coincide
  con ningún prefijo conocido). "Aceptado" = veredicto que empieza con `Accepted`
  (incluye `Accepted,100p`, etc.).
- Los **lenguajes** se normalizan antes de cualquier conteo: minúsculas; las variantes de
  C++ (`CC`/`CXX`/`C++`/`HPP`) pasan a `cpp`, `H` pasa a `c`, y los heredados `PY3`/`PY2` pasan a
  `py`. Por eso un envío `.py3` y uno `.py` cuentan en el mismo lenguaje.

## Resumen

| Métrica | Cálculo |
|---|---|
| **envíos** | total de líneas del historial del problema |
| **intentaron** | usuarios **distintos** con ≥1 envío |
| **resolvieron** | usuarios distintos con ≥1 envío aceptado |
| **lo resuelven (por usuario)** | resolvieron ÷ intentaron: la **tasa por usuario** |
| **tasa por envío** | envíos aceptados ÷ envíos totales. Mide cuánto se falla al intentar; **no define la dificultad** |
| **envíos / usuario** | envíos ÷ intentaron |
| **dificultad** | etiqueta según la **tasa por usuario**: ≥90% muy fácil · ≥70% fácil · ≥50% medio · <50% difícil · sin usuarios que lo intentaran = nuevo |
| **dirt** | (envíos de quienes resolvieron hasta el 1.er AC − ACs) ÷ (esos envíos). Es la métrica del *resolver* de ICPC, la misma de las estadísticas de la competencia. Alto = el problema castiga los errores. |

La dificultad tiene **una sola fuente** en el sistema (`lib/difficulty.sh` en el servidor,
`shared/difficulty.js` en la web). La búsqueda, la sugerencia, el perfil, el sorteo de la
competencia y esta página leen la misma clave. Antes, esta página etiquetaba según la tasa por
envío, y el mismo problema salía "fácil" en la búsqueda y "difícil" aquí (issue #30). La tasa por
envío sigue en la página como número, con el nombre correcto.

## Percentil de dificultad frente al acervo

La tarjeta "**X% del acervo es más fácil que este**" compara la **tasa de éxito por usuario**
(resolvieron ÷ intentaron) de este problema con la de todos los problemas públicos del
entrenamiento (la misma base de la lista de problemas).

- **Elegibilidad**: solo entran en la escala los problemas con **≥5 usuarios que lo
  intentaron**; el percentil solo se muestra si la cohorte elegible tiene **≥10** problemas.
- **Ranking con suavizado de Laplace**: la posición no usa la tasa cruda, sino
  `(resolveram + 1) ÷ (tentaram + 2)`, es decir, (resolvieron + 1) ÷ (intentaron + 2). El
  motivo es empírico: una fracción grande del acervo tiene 100% de éxito en cohortes diminutas
  (5–10 usuarios que lo intentaron). Empatadas en la cima, aplastaban el extremo fácil. Sin el
  suavizado, hasta un "hola mundo" con 33/34 salía "más difícil que el 45% del acervo", porque
  8/8 contaba como más fácil que 33/34. Con el suavizado, 8/8 pasa a 0,90 y queda **por debajo**
  de 33/34 = 0,944, como dicta la intuición. Los empates restantes usan *midrank* (la mitad
  cuenta arriba, la mitad abajo).
- El **tooltip** de la tarjeta muestra la tasa **cruda** del problema y el tamaño de la cohorte.
  La suavizada es solo una escala interna de ordenación.

## Datos

- **primer/último envío**: la hora menor/mayor del historial del problema.
- **primero en resolver**: el usuario cuyo primer envío aceptado tiene la hora menor.
  **Privacidad**: el nombre/usuario solo aparece si el perfil de la cuenta es público; si no, la
  tarjeta muestra solo la fecha.
- **día pico**: el día (huso horario de Brasilia) con más envíos.
- **mediana de intentos hasta la aceptación**: ver "Cómo lo resuelven" más abajo.
- **tiempo mediano hasta resolver**: ídem.

## Línea de tiempo

- **Envíos por mes**: histograma de todos los envíos desde el primero, en meses del
  calendario (huso horario de Brasilia).
- **Resolutores acumulados**: para cada usuario que resolvió, se toma la hora de su **primera
  aceptación**; la curva es el conteo acumulado de esas horas (cuándo el problema "se hizo
  popular").
- **Tasa de aceptación acumulada (%)**: suma corriente de aceptados ÷ suma corriente de
  envíos, mes a mes (la tasa "histórica hasta aquí"). Muestra si el problema se volvió más
  fácil de acertar con el tiempo, p. ej., después de aclarar el enunciado.

## Calendario de actividad

- Todos los días/horas usan el huso horario **America/Sao_Paulo** (el historial guarda UTC; la
  conversión se hace en la agregación).
- **Mapa de calor anual** (estilo GitHub): envíos por día. El selector alterna entre años. La
  pestaña "**Σ todos**" suma todos los años **por día del año** y lo proyecta en un año bisiesto
  (para que aparezca el 29/02). Es la vista de **estacionalidad**: los períodos intensos del
  calendario escolar saltan a la vista.
- **Hora del día × día de la semana** (punchcard): envíos por celda (dom–sáb × 0–23 h),
  todos los años sumados.

## Cómo lo resuelven

- **Veredictos**: gráfico de dona con las familias canónicas (conteo por envío).
- **Resolutores distintos por lenguaje**: usuarios distintos con un envío aceptado en ese
  lenguaje (quien resolvió en C y después en Python cuenta en los dos). Las extensiones no
  reconocidas se juntan en "Otros (ext. no reconocidas)".
- **Tasa de aceptación por lenguaje**: aceptados ÷ envíos de ese lenguaje; solo aparecen los
  lenguajes con **≥3 envíos** (menos que eso es ruido).
- **Envíos hasta la primera aceptación**: para cada usuario que resolvió, cuántos envíos hizo
  hasta el primero aceptado (inclusive); distribución en rangos `1 · 2 · 3 · 4–5 ·
  6–10 · >10` y mediana en la tarjeta de Datos. Quien nunca resolvió no entra (es el
  `tentaram − resolveram`, es decir, intentaron − resolvieron).
- **Tiempo entre el primer intento y la aceptación**: por resolutor, el intervalo entre su primer
  envío y su primera aceptación, en rangos `<1h · 1h–1d · 1d–1sem · >1sem`
  (mediana en Datos). Mide la persistencia: un problema puede ser "difícil de acertar a la
  primera" pero rápido de dominar, o lo contrario.
- **Editores de quienes resolvieron**: el editor **declarado en el perfil** de los resolutores
  (quien no lo declara no cuenta; es un autorretrato, no telemetría).

## Tiempo de ejecución (envíos aceptados)

- El "tiempo" de un envío aceptado es el de su **caso de prueba más lento**: la misma definición
  de Kattis (es el número que realmente se compara con el límite de tiempo).
- Viene del registro estructurado que el juez graba por envío (tiempos por caso de prueba,
  medidos en la máquina de juzgamiento). **Cobertura**: solo los envíos juzgados en la
  plataforma actual. Los envíos migrados del MOJ antiguo no tienen medición, así que la
  distribución empieza pequeña y **crece sola** con cada juzgamiento nuevo. La página dice
  cuántos envíos cubre.
- **Distribución**: histograma con rangos "redondos" (paso 1/2/5×10ᵏ, ~10 rangos).
- **Más rápida por lenguaje**: el mínimo por lenguaje (barra corta = más rápida).
- Cuidado al comparar lenguajes: los tiempos vienen de envíos diferentes, de máquinas de
  juez posiblemente diferentes, y el TL del MOJ es **por lenguaje** (calibrado con las
  soluciones del autor, o fijado por él con `TLOVERRIDE` en el conf del paquete, que tiene
  prioridad sobre el calibrado). La comparación aquí es ilustrativa, no un benchmark controlado.

---

Contrato del endpoint (campos y formatos): [API.md](API.md), ruta `/treino/problem-stats`.
La presentación de los veredictos sigue la política central de la plataforma (fuente única
`lib/verdict.sh`: los veredictos nunca se traducen).
