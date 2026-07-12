// treino/ajuda/exemplos.js — solução COMPLETA do problema condutor da página de ajuda,
// em cada linguagem: lê N, lê M, imprime 2*M - N (entrada "13\n16" => saída "19").
//
// Todos os exemplos abaixo foram COMPILADOS E EXECUTADOS antes de entrar aqui (c/cpp/py/java/
// rs/go/js/ml/cs/sh no host; hs/pas/pl no juiz do C3SL, no rootfs real). O `apl` vem do antigo
// docs/MANUAL-LINGUAGENS.md, onde já estava publicado como solução aceita.
//
// Linguagem SEM exemplo aqui (kt, spim, riscv) não é bug: a página cai no esqueleto que o editor
// já oferece (o campo `template` de shared/languages.js) + a dica de leitura de HOW_TO_READ.
// Só acrescente uma entrada nova DEPOIS de rodar o código de verdade.
export const EXEMPLOS = {
  c: `#include <stdio.h>

int main(void) {
    int n, m;
    scanf("%d %d", &n, &m);
    printf("%d\\n", m + m - n);
    return 0;
}
`,
  cpp: `#include <bits/stdc++.h>
using namespace std;

int main() {
    int n, m;
    cin >> n >> m;
    cout << m + m - n << "\\n";
    return 0;
}
`,
  py: `import sys

n, m = map(int, sys.stdin.read().split())
print(m + m - n)
`,
  // classe SEM 'public': funciona tanto no editor (vira solution.java) quanto por upload.
  java: `import java.util.*;

class Main {
    public static void main(String[] args) {
        Scanner sc = new Scanner(System.in);
        int n = sc.nextInt();
        int m = sc.nextInt();
        System.out.println(m + m - n);
    }
}
`,
  rs: `use std::io::*;

fn main() {
    let mut s = String::new();
    stdin().read_to_string(&mut s).unwrap();
    let v: Vec<i64> = s.split_whitespace().map(|x| x.parse().unwrap()).collect();
    println!("{}", v[1] + v[1] - v[0]);
}
`,
  go: `package main

import "fmt"

func main() {
    var n, m int
    fmt.Scan(&n, &m)
    fmt.Println(m + m - n)
}
`,
  js: `const data = require("fs").readFileSync(0, "utf8");
const [n, m] = data.split(/\\s+/).filter(Boolean).map(Number);
console.log(m + m - n);
`,
  hs: `main :: IO ()
main = do
    n <- readLn :: IO Int
    m <- readLn :: IO Int
    print (m + m - n)
`,
  ml: `let () =
  let n = read_int () in
  let m = read_int () in
  print_int (m + m - n);
  print_newline ()
`,
  pas: `program Main;
var
  n, m: integer;
begin
  readln(n);
  readln(m);
  writeln(m + m - n);
end.
`,
  pl: `main :-
    read_line_to_string(user_input, A),
    read_line_to_string(user_input, B),
    number_string(N, A),
    number_string(M, B),
    Ans is 2 * M - N,
    writeln(Ans).
`,
  cs: `using System;

class Program {
    static void Main() {
        int n = int.Parse(Console.ReadLine());
        int m = int.Parse(Console.ReadLine());
        Console.WriteLine(m + m - n);
    }
}
`,
  sh: `#!/bin/bash
read -r n
read -r m
echo $(( m + m - n ))
`,
  apl: `a←⍎⍞
b←⍎⍞
⎕←a-⍨2×b
`,
};
