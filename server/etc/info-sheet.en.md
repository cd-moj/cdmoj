# Judging environment and submission system

This document describes the environment that compiles and runs the submissions of
**{{CONTEST_NAME}}**. You can edit this text in the **📄 Documents** tab of the contest panel.
The system fills the marked blocks.

## 1. Judging environment

### 1.1 Environment

The judging system runs on **{{OS}}**. The judging machines report these compilers and
interpreters:

{{TOOLCHAIN}}

### 1.2 Accepted languages

The judge accepts these languages and file extensions:

{{LANGS_TABLE}}

The extension of the file that you submit identifies the language. Submit your source code with
the correct extension. The judge rejects a file with an extension that is not in the table. To
rename a file does not change the language: the server checks the language again when the
submission arrives.

### 1.3 Memory limits

Every submission, in every language, has a total memory limit of **{{MEMLIMIT}}** and a
maximum stack size of **{{STACK}}**. The judge measures the peak resident memory of the
submission (the memory that the program touches), not the address space that it reserves.

Note: the memory limit includes the memory of the runtime. In Java, Kotlin and Python the
runtime uses several megabytes. In C and C++ the C runtime is small, but it is not zero.

### 1.4 Time limits

Before the contest, the judges solve every problem. The time limit of each problem comes from
the running time of those solutions. The current table is:

{{TL_TABLE}}

The time limit of each problem is also available in the MOJ interface.

### 1.5 Other limits

- Source file size: {{SOURCE_MAX}}.
- Program output size, including the standard error output: {{OUTPUT_MAX}}.
- Compilation time: {{COMPILE_TL}} seconds.

### 1.6 Compilation and execution

Compile and run your solutions with the commands in the sections below. These commands do not
apply the memory and time limits of the judge, but they match the environment of the judge.

{{#LANG c cpp}}
#### C and C++

- The judge runs the executable file that the compiler produces.
- Your program must exit with status zero: end `main` with `return 0`, or call `exit(0)`.
- For problems with large inputs, `cin` and `cout` can be slow. By default they use a buffer
  synchronized with the `stdio` library. To use `cin` and `cout`, call
  `std::ios::sync_with_stdio(false);` at the start of `main`. In this case, do not mix `scanf`
  and `printf` in the same program.
- Compile C solutions with:

      gcc -lm -O2 -static {submitted_file} -o main

- Compile C++ solutions with:

      g++ -lm -O2 -static -std=gnu++20 -pipe {submitted_file} -o main

- Run C and C++ solutions with:

      ./main
{{/LANG}}
{{#LANG java}}
#### Java

- The judge runs the compiled class that contains `main`.
- Do not declare a `package` in your program. A program with a package does not run in MOJ.
- The name of the file must match the public class. If your file is `Klass.java`, the public
  class with `main` must be `Klass`. Otherwise you can get a Compilation Error.
- For problems with large inputs, `Scanner` can be slow. Use buffered I/O, for example
  `BufferedReader` and `PrintWriter`.
- Compile Java solutions with:

      javac {submitted_file}

- Run Java solutions with:

      java -Xms10m -Xmx{{MEMLIMIT_MB}}m -Xss{{STACK_KB}}k {class_name}

- The judge sets the heap and stack sizes above from the memory limits of section 1.3.
{{/LANG}}
{{#LANG kt}}
#### Kotlin

- The judge runs the compiled program.
- Do not declare a `package` in your program. A program with a package does not run in MOJ.
- There is no rule for the file name. The entry point is the top-level `fun main()` of the
  file that you submit.
- Compile Kotlin solutions with:

      kotlinc {submitted_file} -include-runtime -d prog.jar

- Run Kotlin solutions with:

      java -Xms10m -Xmx{{MEMLIMIT_MB}}m -Xss{{STACK_KB}}k -jar prog.jar

- The judge sets the heap and stack sizes above from the memory limits of section 1.3.
{{/LANG}}
{{#LANG py}}
#### Python

- The judge runs the file that you submit with the **PyPy3** interpreter, not with CPython.
  PyPy3 is usually faster, but some behaviors are different.
- The judge checks the syntax of the file when you submit it. A file with a syntax error gets
  a Compilation Error.
- Check the syntax of Python solutions with:

      pypy3 -m py_compile {submitted_file}

- Run Python solutions with:

      pypy3 {submitted_file}
{{/LANG}}

For other accepted languages, the judge compiles and runs the file with the standard tools of
the language, with the same limits.

## 2. How to use the MOJ system

### 2.1 Verdicts

You can receive these verdicts:

{{VERDICTS}}

In a contest the verdict is all that you receive: no failed test case, no diff and no partial
score. The test data is contest material.

If you think that a verdict is wrong, use the **Clarification** tab. Identify the submission by
problem and time.

### 2.2 Judging notes

- The judge can run your program on several input files. If your program has more than one
  error, for example Time Limit Exceeded and Wrong Answer, you can receive any of them.
- If the compilation takes too long, or if the compiled program is too large, you receive a
  Compilation Error.
- There is no Presentation Error and no Format Error. If the problem asks for the word
  `impossible` and you write it with a typo, the verdict is Wrong Answer.
- Follow the output format of the sample output. Extra whitespace within reason is accepted:
  a space at the end of a line, a space between tokens, or a blank line at the end. Thousands of
  blank spaces are not accepted.
- For problems with floating-point output, the judge accepts any answer inside the tolerance
  of the statement. The tolerance is absolute or relative, as the statement says. Your answer
  does not need to match the digits of the sample.
- When the statement says that several outputs are acceptable, the judge checks the format and
  the constraints. The judge does not compare your output with the sample output.
- If your program writes too much output, the verdict is Runtime Error. The standard error
  output counts. Remove debug messages before you submit.

### 2.3 Penalties

Each submission that receives a verdict other than Accepted, before the first Accepted verdict
of the same problem, adds a penalty of **{{PENALTY}} minutes** to the total time of the team.
There is no penalty for problems that the team does not solve.

Verdicts without penalty: **{{PENALTY_EXCEPTIONS}}**.

### 2.4 Response times

The time to get a verdict depends on the problem, on the verdict and on the moment of the
contest. The judge runs submissions in parallel, so you can receive verdicts out of order. Some
submissions need a manual check by the judges. In that case, a delay of some minutes is normal.

### 2.5 Input and output

1. Read the input from the **standard input**.
2. Write the output to the **standard output**.
3. The input has one test case and no extra data.
4. When a line has several values, one space separates them.

For more questions about the judging system, read the competitor documentation in the web
interface.
