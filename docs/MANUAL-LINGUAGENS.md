# MOJ: Enviar soluções (linguagens e entrada/saída)

Este manual explica como enviar suas soluções no MOJ e, principalmente, como
funciona a entrada e a saída (IO) dos problemas. Se você já programa em maratona,
vai reconhecer o modelo. Se está começando, leia com calma a primeira seção: ela
vale para todas as linguagens.

## 1. Entrada e saída (o mais importante)

No MOJ, todo problema lê da **entrada padrão** (stdin) e escreve na **saída
padrão** (stdout), igual a maratona de programação. Seu programa **não abre
arquivos**: ele lê do teclado (stdin), calcula e imprime na tela (stdout). Quando
você roda o programa na sua máquina, é como se você digitasse a entrada e visse a
saída aparecer.

Os exemplos que aparecem no enunciado (os "sample") são exatamente pares de
**entrada** e **saída**. O juiz alimenta a sua solução com uma entrada e compara,
linha a linha, o que você imprimiu com a saída esperada.

Vamos usar um problema simples como fio condutor deste manual:

> Leia `N` na primeira linha e `M` na segunda linha. Imprima `2*M - N`.

Para esse problema, um exemplo de entrada e saída fica assim:

**Entrada**

```
13
16
```

**Saída**

```
19
```

Ou seja: `N = 13`, `M = 16`, e a resposta é `2*16 - 13 = 19`. Todas as soluções de
exemplo deste manual resolvem exatamente esse problema. Repare que cada uma só faz
três coisas: lê do stdin, calcula, imprime no stdout.

## 2. Como você escolhe a linguagem

Há duas formas de enviar uma solução, e elas decidem a linguagem de jeitos
diferentes:

1. **Digitar no editor.** Você escreve o código na tela e escolhe a linguagem no
   menu suspenso. Ao enviar, o seu código vira um arquivo chamado
   `solution.<extensão>`, e **o menu decide** qual linguagem será usada.
2. **Enviar um arquivo.** Você anexa um arquivo pronto (por exemplo `sol.cpp`).
   Nesse caso, **a extensão do próprio arquivo decide** a linguagem, e o menu é
   ignorado.

Em resumo: a **extensão** é o `id` da linguagem. Se o arquivo termina em `.cpp`, o
juiz usa C++; se termina em `.py`, usa Python; e assim por diante.

## 3. Tabela de linguagens

A linguagem padrão é **C**. A coluna `id` é a extensão que vale no envio.

| id | Linguagem | Observação |
|---|---|---|
| `c` | C | gcc, `-O2 -static`. É a linguagem padrão. |
| `cpp` | C++ | g++ `-O2 -static`, padrão **gnu++20**. `#include <bits/stdc++.h>` funciona. |
| `py` | Python | Roda em **pypy3** (não é o CPython). Erro de sintaxe vira Compilation Error. |
| `java` | Java | Veja o aviso na seção 4. |
| `kt` | Kotlin | `fun main()`. Sem trava de nome de arquivo. |
| `rs` | Rust | Compilador rustc. |
| `go` | Go | Compilado com **gccgo**. Precisa de `package main` e `func main()`. |
| `js` | JavaScript | Executado com node. |
| `hs` | Haskell | Compilador GHC. |
| `ml` | OCaml | Compilador ocaml. |
| `pas` | Pascal | Free Pascal (fpc). |
| `pl` | Prolog | SWI-Prolog. Defina um predicado `main`. Veja o aviso na seção 4. |
| `cs` | C# | Mono. Sem trava de nome de arquivo. |
| `sh` | Shell | bash. |
| `apl` | APL | Dyalog. |
| `spim` | MIPS | Assembly MIPS no simulador spim. |
| `riscv` | RISC-V | Assembly RISC-V no simulador rars. |

Além dessas, existem linguagens **exóticas** que só aparecem quando o problema
específico pede (por exemplo `pddl`, `grepe`, `sas`, `l`, `lpp`, `downward`). Elas
não fazem parte do dia a dia: você só as encontra em disciplinas ou problemas que
as exigem.

**Regra geral de limites:** todas as linguagens rodam com **pilha (stack) de
128 MB**. Na JVM (Java, Kotlin), o limite de memória do problema é aplicado como
`-Xmx`.

## 4. Avisos importantes

### 4.1. Java: nome do arquivo e classe `public`

Quando você digita Java **no editor**, o envio vira `solution.java`, e o juiz
compila o arquivo com esse nome. Em Java, uma classe `public` **precisa** ter o
mesmo nome do arquivo. Por isso o modelo padrão do editor já vem com a classe
**sem `public`** (`class Main { ... }`): assim ele funciona direto, tanto no
editor quanto por upload.

Fique atento só se você mesmo escrever uma classe `public`:

- **No editor:** uma `public class Main` daria Compilation Error, porque o arquivo
  é `solution.java`, e não `Main.java`. Deixe a classe **sem `public`**
  (`class Main { ... }`), ou renomeie para `public class solution`.
- **Enviando por arquivo:** nomeie o arquivo igual à classe pública. Por exemplo,
  `Main.java` com `public class Main` (é o exemplo real da seção 5).

> Kotlin (`kt`), C# (`cs`), Go (`go`) e Rust (`rs`) **não** têm essa trava de nome
> de arquivo. Só o Java exige o casamento entre o nome do arquivo e o nome da
> classe pública.

### 4.2. `.pl` é Prolog

> **Atenção:** a extensão `.pl` também é usada por Perl, mas no MOJ a linguagem
> `.pl` é **Prolog**: o juiz executa **SWI-Prolog** (`prolog -g main`). Defina um
> predicado `main` (veja o exemplo em Prolog na seção 5). Um código escrito em Perl
> e enviado como `.pl` **não** será executado como Perl.

## 5. Exemplos por linguagem

Todos os exemplos abaixo resolvem o mesmo problema: lê `N`, lê `M`, imprime
`2*M - N`. Eles são soluções reais aceitas no juiz.

### C (`c`)

```c
#include <stdio.h>
int main(void){int n,m;if(scanf("%d %d",&n,&m)!=2)return 0;printf("%d\n",m+m-n);return 0;}
```

### C++ (`cpp`)

```cpp
// OBI2020
// fase 1 - irmãos

#include <cstdio>
using namespace std;

int n, m;

int main () {
  
  scanf("%d%d", &n, &m);
  printf("%d\n", m + m - n);
}
```

### Java (`java`)

Este é o exemplo enviado **por arquivo**: o arquivo se chama `Main.java` e a classe
é `public class Main` (os nomes casam). Se fosse digitar no editor, você usaria
`class Main` sem `public` (veja a seção 4.1).

```java
import java.io.*;
public class Main{public static void main(String[] a) throws IOException{
StreamTokenizer st=new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
st.nextToken();int n=(int)st.nval;st.nextToken();int m=(int)st.nval;System.out.println(m+m-n);}}
```

### Python (`py`)

Roda em pypy3. Dá para ler de dois jeitos.

Estilo 1, lendo tudo de uma vez com `sys.stdin`:

```python
import sys
n,m=map(int,sys.stdin.read().split());print(m+m-n)
```

Estilo 2, lendo linha a linha com `input()`:

```python
#!/usr/bin/env python

menor = int(input())
meio = int(input())

print(meio + meio - menor)

```

### Rust (`rs`)

```rust
use std::io::*;
fn main(){let mut s=String::new();stdin().read_to_string(&mut s).unwrap();let v:Vec<i64>=s.split_whitespace().map(|x|x.parse().unwrap()).collect();println!("{}",v[1]+v[1]-v[0]);}
```

### Haskell (`hs`)

```haskell
main = do
    a <- readLn :: IO Int
    b <- readLn :: IO Int
    print $ 2*b - a
```

### Prolog (`pl`)

Lembre do aviso da seção 4.2: `.pl` é Prolog, e você precisa de um predicado
`main`.

```prolog
main :-
    read_string(user_input, "\n", "\n", _, A),
    number_string(X, A),
    read_string(user_input, "\n", "\n", _, B),
    number_string(Y, B),
    Ans is 2*Y - X,
    writeln(Ans).
```

### Bash (`sh`)

```bash
#!/bin/bash
read -r n; read -r m
echo $(( m+m-n ))
```

### APL (`apl`)

```apl
a←⍎⍞
b←⍎⍞
⎕←a-⍨2×b

```

## 6. Linguagens sem exemplo aqui

Para Go, Kotlin, C#, JavaScript, OCaml e Pascal, não há um exemplo pronto neste
manual, mas você não precisa começar do zero: ao escolher a linguagem no menu do
editor, o **modelo que aparece** já traz o esqueleto certo de leitura do stdin. É
só preencher a lógica. Como cada linguagem lê a entrada, em uma frase:

| Linguagem | Como ler do stdin |
|---|---|
| Go (`go`) | Use `bufio.NewReader(os.Stdin)` (ou `fmt.Scan`) dentro de `func main()`. |
| Kotlin (`kt`) | Use `readLine()` a cada linha, dentro de `fun main()`. |
| C# (`cs`) | Use `Console.ReadLine()`. |
| JavaScript (`js`) | Leia tudo de uma vez com `require('fs').readFileSync(0,'utf8')`. |
| OCaml (`ml`) | Use `read_int ()` ou `read_line ()`. |
| Pascal (`pas`) | Use `readln(n)` e `writeln(...)`. |

## 7. Para onde ir agora

- Como enviar no **dia a dia** (treino): veja `MANUAL-TREINO.md`.
- Como enviar durante uma **prova** (contest): veja `MANUAL-CONTEST.md`.
