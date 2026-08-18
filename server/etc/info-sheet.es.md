# Entorno de juzgamiento y sistema de envíos

Este documento describe el entorno en el que los envíos de **{{CONTEST_NAME}}** serán
compilados y ejecutados. Edite este texto en la pestaña **📄 Documentos** del panel de la
competencia — los bloques marcados los completa el sistema automáticamente.

## 1. Entorno de ejecución

Los envíos se ejecutan en un *sandbox* (bubblewrap) sobre GNU/Linux, con los siguientes
compiladores e intérpretes, según lo reportado por las máquinas de juzgamiento:

{{TOOLCHAIN}}

## 2. Límites de memoria

Todos los envíos, en todos los lenguajes, tienen un límite total de **{{MEMLIMIT}}** de memoria
y una pila (*stack*) máxima de **{{STACK}}**.

> El límite de memoria incluye la memoria que usa el entorno de ejecución. En Java, Kotlin y
> Python, tenga en cuenta que el *runtime* consume varios megabytes. En C y C++ el consumo de
> la biblioteca estándar es pequeño, pero también existe.

## 3. Límites de tiempo

Antes de la competencia, los jueces resuelven todos los problemas y el límite de tiempo de cada
uno se calibra a partir del tiempo de ejecución de esas soluciones, **por lenguaje**. La tabla
vigente es:

{{TL_TABLE}}

## 4. Lenguajes aceptados

{{LANGS_TABLE}}

## 5. Entrada y salida

1. La entrada debe leerse de la **entrada estándar**.
2. La salida debe escribirse en la **salida estándar**.
3. La entrada contiene un único caso de prueba y no hay datos adicionales.
4. Cuando una línea contiene varios valores, estos se separan por un solo espacio.

## 6. Recomendaciones

- En C++, `cin`/`cout` están sincronizados con `stdio` por omisión y pueden ser lentos con
  entradas grandes; use `std::ios::sync_with_stdio(false)` (y entonces evite mezclarlos con
  `scanf`/`printf`).
- En Java y Kotlin, prefiera E/S con *buffer* (`BufferedReader`, `PrintWriter`) a `Scanner`.
- Su programa debe terminar con código de salida cero.
