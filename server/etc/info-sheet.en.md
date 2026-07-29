# Testing environment and submission system

This document describes the environment in which submissions for **{{CONTEST_NAME}}** are
compiled and executed. Edit this text in the **📄 Documents** tab of the contest panel — the
marked blocks are filled in automatically by the system.

## 1. Execution environment

Submissions run inside a sandbox (bubblewrap) on GNU/Linux, with the following compilers and
interpreters, as reported by the judging machines:

{{TOOLCHAIN}}

## 2. Memory limits

All submissions, in every language, are limited to **{{MEMLIMIT}}** of memory and a maximum
stack size of **{{STACK}}**.

> The memory limit includes the memory used by the execution environment. For Java, Kotlin and
> Python, keep in mind that the runtime itself takes several megabytes. For C and C++ the
> standard library footprint is small, but not zero.

## 3. Time limits

Before the contest the judges solve every problem, and each problem's time limit is calibrated
from the running time of those solutions, **per language**. The current table is:

{{TL_TABLE}}

## 4. Accepted languages

{{LANGS_TABLE}}

## 5. Input and output

1. Input must be read from **standard input**.
2. Output must be written to **standard output**.
3. The input consists of a single test case, with no extra data.
4. When a line contains several values, they are separated by single spaces.

## 6. Recommendations

- In C++, `cin`/`cout` are synchronized with `stdio` by default and can be slow on large
  inputs; use `std::ios::sync_with_stdio(false)` (and then avoid mixing with `scanf`/`printf`).
- In Java and Kotlin, prefer buffered I/O (`BufferedReader`, `PrintWriter`) over `Scanner`.
- Your program must exit with status zero.
