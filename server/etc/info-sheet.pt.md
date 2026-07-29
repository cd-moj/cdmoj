# Ambiente de julgamento e sistema de submissão

Este documento descreve o ambiente em que as submissões de **{{CONTEST_NAME}}** serão
compiladas e executadas. Edite este texto na aba **📄 Documentos** do painel do contest — os
blocos marcados são preenchidos automaticamente pelo sistema.

## 1. Ambiente de execução

As submissões rodam em sandbox (bubblewrap) sobre GNU/Linux, com os seguintes compiladores e
interpretadores, conforme reportado pelas máquinas de julgamento:

{{TOOLCHAIN}}

## 2. Limites de memória

Todas as submissões, em todas as linguagens, têm o limite total de **{{MEMLIMIT}}** de memória
e pilha (*stack*) máxima de **{{STACK}}**.

> O limite de memória inclui a memória usada pelo ambiente de execução. Em Java, Kotlin e
> Python, considere que o *runtime* consome vários megabytes. Em C e C++ o consumo da
> biblioteca padrão é pequeno, mas ainda assim existe.

## 3. Limites de tempo

Antes da prova, os juízes resolvem todos os problemas e o tempo limite de cada um é calibrado
a partir do tempo de execução dessas soluções, **por linguagem**. A tabela vigente é:

{{TL_TABLE}}

## 4. Linguagens aceitas

{{LANGS_TABLE}}

## 5. Entrada e saída

1. A entrada deve ser lida da **entrada padrão**.
2. A saída deve ser escrita na **saída padrão**.
3. A entrada contém um único caso de teste e não há dados extras.
4. Quando uma linha contém vários valores, eles são separados por um único espaço.

## 6. Recomendações

- Em C++, `cin`/`cout` são sincronizados com o `stdio` por padrão e podem ser lentos em
  entradas grandes; use `std::ios::sync_with_stdio(false)` (e então evite misturar com
  `scanf`/`printf`).
- Em Java e Kotlin, prefira E/S com *buffer* (`BufferedReader`, `PrintWriter`) a `Scanner`.
- Seu programa deve terminar com código de saída zero.
