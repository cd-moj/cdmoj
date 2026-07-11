// shared/languages.js — linguagens aceitas pelo MOJ (espelha mojtools/lang/*).
// id == extensão enviada (FILETYPE = id em maiúsculas, casa com o dir do juiz).
// cm = modo do CodeMirror (null = sem realce, mas funciona como template).
// optIn: true = linguagem EXÓTICA/custom (PDDL, grepe do curso de compiladores, …). NÃO aparece
// no dropdown de submissão por padrão — SÓ quando o problema a declara no seu campo `languages`.
// As normais (sem optIn) formam DEFAULT_SUBMIT_LANGUAGES, oferecidas p/ todo problema irrestrito.
export const LANGUAGES = [
  { id: 'c',     label: 'C',            cm: 'cpp',        template: '#include <stdio.h>\n\nint main(void) {\n    \n    return 0;\n}\n' },
  { id: 'cpp',   label: 'C++',          cm: 'cpp',        template: '#include <bits/stdc++.h>\nusing namespace std;\n\nint main() {\n    \n    return 0;\n}\n' },
  { id: 'py',    label: 'Python',       cm: 'python',     template: 'import sys\ninput = sys.stdin.readline\n\ndef main():\n    pass\n\nif __name__ == "__main__":\n    main()\n' },
  { id: 'java',  label: 'Java',         cm: 'java',       template: 'import java.util.*;\nimport java.io.*;\n\nclass Main {\n    public static void main(String[] args) {\n        \n    }\n}\n' },
  { id: 'kt',    label: 'Kotlin',       cm: 'kotlin',     template: 'import java.io.BufferedReader\nimport java.io.InputStreamReader\n\nfun main() {\n    val br = BufferedReader(InputStreamReader(System.`in`))\n    \n}\n' },
  { id: 'rs',    label: 'Rust',         cm: 'rust',       template: 'use std::io::*;\n\nfn main() {\n    \n}\n' },
  { id: 'go',    label: 'Go',           cm: 'go',         template: 'package main\n\nimport (\n    "bufio"\n    "fmt"\n    "os"\n)\n\nfunc main() {\n    r := bufio.NewReader(os.Stdin)\n    _ = r; _ = fmt.Sprint\n}\n' },
  { id: 'js',    label: 'JavaScript',   cm: 'javascript', template: 'const data = require("fs").readFileSync(0, "utf8");\nconst lines = data.split("\\n");\n\n' },
  { id: 'hs',    label: 'Haskell',      cm: null,         template: 'main :: IO ()\nmain = do\n    return ()\n' },
  { id: 'ml',    label: 'OCaml',        cm: null,         template: 'let () =\n  ()\n' },
  { id: 'pas',   label: 'Pascal',       cm: null,         template: 'program Main;\nbegin\nend.\n' },
  { id: 'pl',    label: 'Prolog',       cm: null,         template: 'main :-\n    read_line_to_string(user_input, Linha),\n    % resolva aqui e escreva o resultado com writeln/1\n    writeln(Linha).\n' },
  { id: 'cs',    label: 'C#',           cm: null,         template: 'using System;\n\nclass Main {\n    static void Main() {\n        \n    }\n}\n' },
  { id: 'sh',    label: 'Shell (bash)', cm: null,         template: '#!/bin/bash\n\n' },
  { id: 'apl',   label: 'APL',          cm: null,         template: '' },
  { id: 'spim',  label: 'MIPS (spim)',  cm: null,         template: '.data\n\n.text\n.globl main\nmain:\n    \n' },
  { id: 'riscv', label: 'RISC-V',       cm: null,         template: '.text\n.globl main\nmain:\n    \n' },
  // ---- exóticas / custom (opt-in: só no dropdown quando o problema declara) ----
  { id: 'pddl',     label: 'PDDL',                    cm: null, template: '', optIn: true },
  { id: 'grepe',    label: 'grepe (regex)',           cm: null, template: '', optIn: true },
  { id: 'sas',      label: 'SAS',                     cm: null, template: '', optIn: true },
  { id: 'l',        label: 'Lex (.l)',                cm: null, template: '', optIn: true },
  { id: 'lpp',      label: 'LPP (.lpp)',              cm: null, template: '', optIn: true },
  { id: 'downward', label: 'Fast Downward (.downward)', cm: null, template: '', optIn: true },
];
// linguagens mostradas por PADRÃO (problema sem restrição). Exclui as exóticas opt-in.
export const DEFAULT_SUBMIT_LANGUAGES = LANGUAGES.filter((l) => !l.optIn);
// langById: entrada da linguagem por id. Fallback GENÉRICO p/ id exótico não-registrado
// (linguagem custom futura declarada no `languages` de um problema): aparece com o próprio id
// como label, sem realce/template — sem precisar de código novo. Só cai no LANGUAGES[0] p/ id vazio.
export const langById = (id) =>
  LANGUAGES.find((l) => l.id === id) || (id ? { id, label: id, cm: null, template: '' } : LANGUAGES[0]);
// extensão de arquivo -> id de linguagem do MOJ
export function langByExt(ext) {
  const e = (ext || '').toLowerCase();
  const direct = LANGUAGES.find((l) => l.id === e);
  if (direct) return direct;
  const alias = { cc: 'cpp', cxx: 'cpp', 'c++': 'cpp', hpp: 'cpp', h: 'c',
                  py3: 'py', py2: 'py', python: 'py', rb: 'py', kts: 'kt', rs: 'rs', bash: 'sh', s: 'spim' };
  return langById(alias[e] || 'c');
}
