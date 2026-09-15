# Entorno de evaluación y sistema de envío

Este documento describe el entorno que compila y ejecuta los envíos de **{{CONTEST_NAME}}**.
Puede editar este texto en la pestaña **📄 Documentos** del panel del contest. El sistema
completa los bloques marcados.

## 1. Entorno de evaluación

### 1.1 Entorno

El sistema de evaluación funciona en **{{OS}}**. Las máquinas de evaluación reportan estos
compiladores e intérpretes:

{{TOOLCHAIN}}

### 1.2 Lenguajes aceptados

El juez acepta estos lenguajes y extensiones de archivo:

{{LANGS_TABLE}}

La extensión del archivo que usted envía identifica el lenguaje. Envíe el código fuente con la
extensión correcta. El juez rechaza un archivo con una extensión que no está en la tabla.
Renombrar un archivo no cambia el lenguaje: el servidor verifica el lenguaje otra vez cuando el
envío llega.

### 1.3 Límites de memoria

Todo envío, en todo lenguaje, tiene un límite total de memoria de **{{MEMLIMIT}}** y un tamaño
máximo de pila (*stack*) de **{{STACK}}**. El juez mide el pico de memoria residente del envío
(la memoria que el programa toca), y no el espacio de direcciones que reserva.

Nota: el límite de memoria incluye la memoria del *runtime*. En Java, Kotlin y Python el
*runtime* usa varios megabytes. En C y C++ el *runtime* es pequeño, pero no es cero.

### 1.4 Límites de tiempo

Antes de la competencia, los jueces resuelven todos los problemas. El límite de tiempo de cada
problema viene del tiempo de ejecución de esas soluciones. La tabla vigente es:

{{TL_TABLE}}

El límite de tiempo de cada problema también está disponible en la interfaz del MOJ.

### 1.5 Otros límites

- Tamaño del archivo fuente: {{SOURCE_MAX}}.
- Tamaño de la salida del programa, incluida la salida de error estándar: {{OUTPUT_MAX}}.
- Tiempo de compilación: {{COMPILE_TL}} segundos.

### 1.6 Compilación y ejecución

Compile y ejecute sus soluciones con los comandos de las secciones siguientes. Estos comandos
no aplican los límites de memoria y de tiempo del juez, pero reproducen el entorno del juez.

{{#LANG c cpp}}
#### C y C++

- El juez ejecuta el archivo ejecutable que produce el compilador.
- Su programa debe terminar con código de salida cero: termine `main` con `return 0`, o llame a
  `exit(0)`.
- En problemas con entradas grandes, `cin` y `cout` pueden ser lentos. Por defecto usan un
  *buffer* sincronizado con la biblioteca `stdio`. Para usar `cin` y `cout`, llame a
  `std::ios::sync_with_stdio(false);` al inicio de `main`. En ese caso, no mezcle `scanf` y
  `printf` en el mismo programa.
- Compile soluciones en C con:

      gcc -lm -O2 -static {archivo_enviado} -o main

- Compile soluciones en C++ con:

      g++ -lm -O2 -static -std=gnu++20 -pipe {archivo_enviado} -o main

- Ejecute soluciones en C y C++ con:

      ./main
{{/LANG}}
{{#LANG java}}
#### Java

- El juez ejecuta la clase compilada que contiene `main`.
- No declare `package` en su programa. Un programa con *package* no funciona en el MOJ.
- El nombre del archivo debe ser igual al de la clase pública. Si su archivo es `Klass.java`,
  la clase pública con `main` debe ser `Klass`. En otro caso puede recibir Compilation Error.
- En problemas con entradas grandes, `Scanner` puede ser lento. Use E/S con *buffer*, por
  ejemplo `BufferedReader` y `PrintWriter`.
- Compile soluciones en Java con:

      javac {archivo_enviado}

- Ejecute soluciones en Java con:

      java -Xms10m -Xmx{{MEMLIMIT_MB}}m -Xss{{STACK_KB}}k {nombre_de_la_clase}

- El juez define los tamaños de *heap* y de pila anteriores a partir de los límites de memoria
  de la sección 1.3.
{{/LANG}}
{{#LANG kt}}
#### Kotlin

- El juez ejecuta el programa compilado.
- No declare `package` en su programa. Un programa con *package* no funciona en el MOJ.
- No hay regla para el nombre del archivo. El punto de entrada es la `fun main()` de nivel
  superior del archivo que usted envía.
- Compile soluciones en Kotlin con:

      kotlinc {archivo_enviado} -include-runtime -d prog.jar

- Ejecute soluciones en Kotlin con:

      java -Xms10m -Xmx{{MEMLIMIT_MB}}m -Xss{{STACK_KB}}k -jar prog.jar

- El juez define los tamaños de *heap* y de pila anteriores a partir de los límites de memoria
  de la sección 1.3.
{{/LANG}}
{{#LANG py}}
#### Python

- El juez ejecuta el archivo que usted envía con el intérprete **PyPy3**, y no con CPython.
  PyPy3 suele ser más rápido, pero algunos comportamientos son diferentes.
- El juez verifica la sintaxis del archivo cuando usted lo envía. Un archivo con error de
  sintaxis recibe Compilation Error.
- Verifique la sintaxis de soluciones en Python con:

      pypy3 -m py_compile {archivo_enviado}

- Ejecute soluciones en Python con:

      pypy3 {archivo_enviado}
{{/LANG}}

Para los otros lenguajes aceptados, el juez compila y ejecuta el archivo con las herramientas
estándar del lenguaje, con los mismos límites.

## 2. Cómo usar el sistema MOJ

### 2.1 Veredictos

Usted puede recibir estos veredictos:

{{VERDICTS}}

En una competencia el veredicto es todo lo que usted recibe: ningún caso de prueba fallido,
ningún *diff* y ninguna puntuación parcial. Los datos de prueba son material de la competencia.

Si usted cree que un veredicto es incorrecto, use la pestaña **Clarification**. Identifique el
envío por el problema y por la hora.

### 2.2 Notas de evaluación

- El juez puede ejecutar su programa con varios archivos de entrada. Si su programa tiene más
  de un error, por ejemplo Time Limit Exceeded y Wrong Answer, usted puede recibir cualquiera de
  ellos.
- Si la compilación tarda demasiado, o si el programa compilado es demasiado grande, usted
  recibe Compilation Error.
- No existe Presentation Error ni Format Error. Si el problema pide la palabra `impossible` y
  usted la escribe con un error, el veredicto es Wrong Answer.
- Siga el formato de la salida de ejemplo. Se aceptan espacios en blanco extra dentro de lo
  razonable: un espacio al final de una línea, un espacio entre valores, o una línea en blanco
  al final. Miles de espacios en blanco no se aceptan.
- En problemas con salida de punto flotante, el juez acepta cualquier respuesta dentro de la
  tolerancia del enunciado. La tolerancia es absoluta o relativa, según el enunciado. Su
  respuesta no necesita tener los mismos dígitos del ejemplo.
- Cuando el enunciado dice que varias salidas son aceptables, el juez verifica el formato y las
  restricciones. El juez no compara su salida con la salida de ejemplo.
- Si su programa escribe demasiada salida, el veredicto es Runtime Error. La salida de error
  estándar cuenta. Quite los mensajes de depuración antes de enviar.

### 2.3 Penalizaciones

Cada envío que recibe un veredicto distinto de Accepted, antes del primer Accepted del mismo
problema, suma una penalización de **{{PENALTY}} minutos** al tiempo total del equipo. No hay
penalización por problemas que el equipo no resuelve.

Veredictos sin penalización: **{{PENALTY_EXCEPTIONS}}**.

### 2.4 Tiempos de respuesta

El tiempo hasta el veredicto depende del problema, del veredicto y del momento de la
competencia. El juez ejecuta los envíos en paralelo, así que usted puede recibir los veredictos
fuera de orden. Algunos envíos necesitan una verificación manual de los jueces. En ese caso, una
demora de algunos minutos es normal.

### 2.5 Entrada y salida

1. Lea la entrada de la **entrada estándar**.
2. Escriba la salida en la **salida estándar**.
3. La entrada tiene un caso de prueba y no tiene datos extra.
4. Cuando una línea tiene varios valores, un espacio separa los valores.

Para más dudas sobre el sistema de evaluación, lea la documentación del competidor en la
interfaz web.
