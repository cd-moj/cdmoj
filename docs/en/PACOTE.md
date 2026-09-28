<!-- i18n-source: PACOTE.md blob:d6a1a7e40e4c7a6b1e6867a955a38e42677af7a7 -->
# MOJ: the problem package (canonical format)

> **Translation note.** This manual is a translation of the Portuguese original. The command-line tools (`moj`, `moj-contest`, `moj-comp`) print their messages in Portuguese, and the command examples below are identical to the original.

This document is the **single source** for the format of the MOJ problem package. It explains what a
package is and what each file in it does. It explains the metadata (`.moj-meta.json` and `.moj-id`),
what **orgs** and **collections** are, and how a problem goes from draft to the student.

> If you build a package in practice (step by step, with the commands), read the `README.md` of
> **mojtools**. It has the walkthrough. This document is the **reference**: what each item is and why.
> The API routes that read and write the package are in [API.md](API.md).

> ⚠ **The package is not a read source for contest routes or training routes.** A route that serves a
> contest or the training uses data that is already materialized: the owners index,
> `var/jsons{,-private}/<id>.json`, `run/tl/`. It never opens the package tree. If you need data that
> exists only in the package, materialize it first. The boundary, the reasons and the inventory of
> what is still open: `cdmoj/CLAUDE.md` and `bash server/test/sem-pacote.sh`.

> **An outdated doc is a bug.** Did you change the package (new file, new field, layout, the source of
> the title)? Update **this** document in the same commit. The other places (the `CLAUDE.md` of
> `cdmoj`, of `mojtools` and of `moj-cli`) point here. They do not repeat the format.

## Contents

1. [What a package is](#1-what-a-package-is)
2. [Where packages live](#2-where-packages-live)
3. [Canonical layout](#3-canonical-layout)
4. [File by file](#4-file-by-file)
5. [`.moj-meta.json`: the problem metadata](#5-moj-metajson-the-problem-metadata)
6. [`.moj-id`: the local CLI pointer](#6-moj-id-the-local-cli-pointer)
7. [ORG: who can make changes](#7-org-who-can-make-changes)
8. [COLLECTION: how problems are grouped](#8-collection-how-problems-are-grouped)
9. [ORG x COLLECTION](#9-org-x-collection)
10. [Life cycle of a problem](#10-life-cycle-of-a-problem)
11. [Frequently asked questions](#11-frequently-asked-questions)

---

## 1. What a package is

A **package** is a directory that describes a complete problem: the statement, the tests, the
reference solutions and the execution limits. There is no problem database: the package **is** the
problem.

Know these three things from the start:

- **Each package is its own git repository**, local, on the server. There is no Gitea, no external
  service and no access key. When a person saves from the web editor or with `moj push`, the server
  writes the files and commits them in that repository (function `problem_commit`, in
  `server/api/v1/lib/problems.sh`, with a lock per problem).
- **The identifier of a problem is `<org>#<prob>`**, for example `apc#fatorial`. The part before the
  `#` is the **org** (section 7). The part after it is the name of the package directory.
- **The author almost never edits the package by hand.** The author uses the web editor or the CLI
  (`moj`). Both talk to the same API. This document describes what these tools write, so that you
  understand what happens and can check it.

## 2. Where packages live

```
moj-problems/<org>/<prob>/        # the package (root of the local git repo of that problem)
```

The variable `MOJ_PROBLEMS_DIR` sets the root `moj-problems/`. In the development checkout it is next
to `cdmoj/`.

A package does **not** contain the scoreboard, the submission history or the calibrated time limits.
All of these live outside it:

| Item | Where it is | Who writes it |
|---|---|---|
| Calibrated time limits | `run/tl/<id>.json` | the judges, when they calibrate |
| Validation report | `run/validation/<id>.json` | `validate-problem.sh` |
| Index served to the student | `contests/treino/var/jsons/<id>.json` | `gen-problem-json.sh` |
| Org registry | `contests/treino/var/orgs.json` | the API (`lib/orgs.sh`) |
| Collection registry | `contests/treino/var/collections.json` | the API (`lib/problems.sh`) |

## 3. Canonical layout

This is the tree of a complete package. The right column shows in how many of the 453 packages of the
current archive each item appears. It shows what is routine and what is an exception.

```
moj-problems/<org>/<prob>/
├── .git/                     local git repo of the problem                  453  (always)
├── .moj-meta.json            metadata (title, public, collections, …)       453  (always)
├── author                    author(s) of the problem                       453  (mandatory)
├── tags                      topics, one tag per line                       453
├── conf                      execution limits and settings                  453
├── docs/
│   ├── enunciado.md          the statement in Portuguese (also .org, .tex)  453  (mandatory)
│   ├── enunciado.en.md       the statement in English (same: enunciado.es.md) optional
│   ├── notes/sample1.md      explanation of each sample (markdown; 1/sample) optional
│   ├── notes/sample1.en.md   the translated explanation (falls back to PT)  optional
│   ├── <figura>.png          images of the statement/notes (render embeds)  optional
│   ├── solucao.md            editorial, only for the author                 optional
│   └── solucao.en.md         the translated editorial (same: solucao.es.md) optional
├── tests/
│   ├── input/sample1         sample (shown in the statement)                mandatory, >= 1
│   ├── output/sample1        answer of the sample
│   ├── input/<nome>          hidden test (grades the submission)
│   ├── output/<nome>         answer of the hidden test
│   └── score                 scoring groups (subtasks)                      254  (optional)
├── sols/
│   ├── good/                 correct solutions                              453  (mandatory, >= 1)
│   ├── wrong/                intentionally wrong solutions                    18  (optional)
│   ├── slow/                 intentionally slow solutions                      7  (optional)
│   ├── pass/                 solutions that must pass by a small margin       3  (optional)
│   └── upcoming/             draft solutions                                   1  (optional)
└── scripts/                  special judging                                 79  (optional)
    ├── compare.sh            custom comparator (checker)                     18
    ├── validator.cpp         INPUT validator (testlib)                       optional
    └── <lang>/compile.sh     custom compilation (function submission)       201
```

Two files appear in the archive but are **not** part of the format:

- `problem.yaml` and `.kattis.json` (in 395 packages) are metadata of the **Kattis** format. The
  importer/exporter (`mojtools/kattis/`) writes them. MOJ ignores them completely.
- `.moj-id` (in 336 packages) is a **client** file, not a package file. Old migrations put it there by
  mistake. See section 6.

## 4. File by file

### `docs/enunciado.md`

The text of the problem. It accepts three formats. MOJ looks for them in this order: `enunciado.md`,
`enunciado.org`, `enunciado.tex`. The `.md` is the canonical and recommended format.

**How to write the text** — Markdown, TeX formulas, parentheses, cases, matrices, what to avoid and how
each construct looks in the PDF of the problem set, with examples: **[ENUNCIADO](ENUNCIADO.md)**.

The quality gate enforces three rules:

1. **The sections `## Entrada` and `## Saída` are mandatory.** Without them the problem fails
   validation. (The validator also accepts `## Input`, `## Output` and `## Salida`, with one to three `#`.)
2. **The title does not go in the text.** A first line `% Título do problema` is **legacy**: the
   renderer removes it. The real title is the field `display_title` of `.moj-meta.json` (section 5).
   The renderer injects an `<h1>` from it.
3. **The samples do not go in the text.** MOJ builds them from `tests/input/sample*` and
   `tests/output/sample*` and injects them at the end of the HTML. If you write a sample by hand in
   the statement, it appears twice. (Validation warns, but does not block.) The exception is the
   problem **without samples** (`SAMPLE=no` in `conf`, section 4, "Problem without samples"). In that
   problem the example goes in the text, in a section `## Exemplo`, and validation does not warn.

**Images — two methods, both become self-contained HTML** (the renderer runs with
`--embed-resources` and embeds everything in base64):

1. **Paste or drag into the web editor**: the image becomes a `data:URI` INSIDE the statement text.
   There is no separate file. It travels with the markdown by any path.
2. **File in `docs/`** + `![](figura.png)` in the text: you can edit the figure as a file. It travels
   with `moj push`/`clone` (field `docs_files`, the equivalent of `scripts_files`; limit 2MB per
   image) and with `moj upload` (tar). It appears in the Preview (the preview receives the images of the
   package or the local images). Use simple names (`[A-Za-z0-9._-]`, extension png/jpg/jpeg/gif/svg/webp).

**Graphs**: a code block with the class `.graph` ([graphviz DOT](https://graphviz.org/) source) is
rendered as **SVG**. The DOT source stays editable in the statement. It is not a pasted image. Example:
` ```{ .graph .center caption="…"} graph G { a -- b; } ``` `. Details and attributes are in
**`mojtools/docs/enunciado-grafos.md`**.

**One script** does the rendering: `mojtools/render-statement.sh`. The "👁 Preview" button of the editor,
the HTML that the student reads and the HTML that validation checks are exactly the same. There is no
second renderer. Do not create one.

### `docs/notes/<sample>.md` — the explanation of each sample

Optional. **One Markdown file per sample**, with the SAME name as the sample test:
`docs/notes/sample1.md` explains `tests/input/sample1`, and so on. It is normal markdown: paragraphs,
lists, `code`, and **images** (`![](figura.png)` with the figure in `docs/`, the same as in the
statement; the render embeds it in base64). The note appears directly below the related sample.

```
docs/notes/sample1.md      # "In this example we have:\n\n- 4 groups...\n\n![](mesas.png)"
docs/notes/sample2.md
```

You **never edit JSON**. The web editor ("explanation" field of each sample), `moj edit` (option
`[n]ota`) and `moj push`/`clone` read and write these files. Serialization is the job of the platform.
Validation warns when a note has no related sample.

**Legacy**: MOJ still READS `docs/sample-notes.json` (JSON array of strings, by index) in old
packages, but it **never writes it again**. Each save converts it to `docs/notes/`.

### `docs/solucao.md`

Optional. It is the **editorial**: the explanation of the idea of the solution, for the author and for
people who reuse the problem. **The student never sees this file.** `gen-problem-json.sh` ignores it on
purpose. It is the correct place to write "the solution is a DP in O(n log n)" safely. The editorial
document of a contest reads this file (or the translation `solucao.<lang>.md`, below).

### Languages: `enunciado.<lang>.md`, `notes/<sample>.<lang>.md`, `solucao.<lang>.md`

A problem can have the statement in more than one language. The rules are simple:

| File | What it is | If it is missing |
|---|---|---|
| `docs/enunciado.md` | the statement in **Portuguese**. It is the main text and it is mandatory | the problem does not validate |
| `docs/enunciado.<lang>.md` | the translation. `<lang>` is `en` or `es`. Markdown only | the problem has only one language |
| `docs/notes/<sample>.<lang>.md` | the translated explanation of the sample | the sample shows the explanation in Portuguese |
| `docs/solucao.<lang>.md` | the translated editorial | the editorial document uses Portuguese |
| `titles` in `.moj-meta.json` | the title of each translation (section 5) | the title in Portuguese |

⚠ The file and directory names (`enunciado`, `solucao`, `notes`) are literal and in Portuguese. Do not translate them.

The samples come from the tests and appear in all languages, with the labels of the language
(Exemplos/Entrada/Saída/Explicação · Examples/Input/Output/Explanation ·
Ejemplos/Entrada/Salida/Explicación). The figures stay in `docs/` and serve all languages.

Validation treats each translation the same as the Portuguese text: it must render and it must have
the input and output sections (`## Input`/`## Output`, `## Entrada`/`## Salida`). A translation without
the explanation of a sample gives the warning `nota-sem-traducao(<sample>,<lang>)`. The warning does
not block.

The training index (`var/jsons/<id>.json`) has `statement_langs` (the list, Portuguese first) and
`statements{<lang>:{title,html_b64}}`. The Portuguese text stays in `title` and `statement_html_b64`,
as always. The problem page shows one chip per language. In a contest, the admin or the chief judge
selects the languages that the accordion offers (`STATEMENT_LANGS`; see `API.md`).

A sample larger than **256 KB** is truncated in the statement HTML (only the start, with the warning
"Large sample"). A sample larger than **4 MB** is not sent as data (`{name, size, too_big:true}`). A
sample is for reading: a large test is a hidden test.

The index also has **`samples`**: `[{name, input, output}]`, the text of the samples. The selection is
the SAME as in the statement HTML (`stmt_sample_names` in `mojtools/statement-langs.sh`: the
`tests/input/sample*`, or none with `SAMPLE=no`). A hidden test never goes into this field. This field
feeds the **⬇ Samples** button and `moj-comp samples`/`fetch`, through the routes `/treino/problem`
and `/contest/samples`.

In the authoring API, the translations travel in the field `translations` of `/problems/source` and
`/problems/edit`: `{"<lang>": {title, enunciado_md, editorial_md, notes:{"<sample>": md}}}`.
A language that is not in the object stays as it is. A language with the value `null` is deleted
completely. The CLI (`moj clone`/`push`) and the web editor use this field. You only edit the files.

Do not confuse this with the mechanics of special judging. That is the subject of `scripts/`, and it is
documented in `mojtools/docs/correcao-especial.md`.

### `tests/input/` and `tests/output/`

Each file in `tests/input/` must have a file with the **same name** in `tests/output/`. Validation
checks this in both directions (an input without output and an output without input both fail).

The file name sets the role of the test:

| Name | Role |
|---|---|
| `sample1`, `sample2`, … | **sample**: appears in the statement, and also grades |
| any other name | **hidden test**: only grades, the student never sees it |

The samples are all the files whose names start with `sample`, sorted by `ls -1v` (so `sample2` comes
before `sample10`, not after it). The prefix `sample` is literal. Do not translate it. Validation requires **at least one sample**, or the declaration that
the problem has no samples (`SAMPLE=no`, below). **A hidden test never appears as a sample**, not
even when `sample*` is missing.

#### Problem without samples: `SAMPLE=no`

In some problems, sample input and output have no meaning for the student:

- **function submission**: the test input is the internal format of the driver, which the student
  does not read;
- **interactive problem**: the input is the secret scenario of the referee, and the output is a
  marker;
- **custom language** (PDDL, SAS, grammars): the "sample" is not an input/output pair;
- any other case where text or a figure explains the example better.

In these problems:

1. Do not create `tests/input/sample*`.
2. Put the line `SAMPLE=no` in `conf`. In the web editor, it is the option **this problem has no
   samples** of the **Limits** tab. In the CLI, `moj edit` → 8 (conf) → 6. `moj interactive` already
   writes the line.
3. Explain the example in the statement text, in a section `## Exemplo`: a figure, a call of the
   function and what it returns, the transcript of the conversation with the referee.

The effect of `SAMPLE=no`:

- the statement does not show the samples box;
- the field `samples` of the index is empty: there is no **⬇ Samples** button in the training, no
  **Samples** link in the contest (`has_samples:false` in `/contest/problems`), and `moj-comp samples`
  downloads nothing. This applies also if `sample*` files exist: they continue to grade, like any
  test, but none of them becomes a sample;
- the line `SAMPLE` is **not** part of the tl-checksum: if you set or clear it, no recalibration is
  necessary.

Accepted values: `no`, `n`, `nao`, `não`, `false`, `0` (with or without quotes). Without the line, the
problem has samples (`tests/input/sample*`). Until 2026-09-23 there were two legacy mechanisms, now
removed: the file `samples` in the package root (empty = no samples), and the fallback that showed
the first two tests when `sample*` was missing. In a function problem, that fallback showed the
internal format of the driver.

The names of hidden tests are free. The conventions in the archive are `test-001`, `test-002` (APC
style) and `<prob>_1_1`, `<prob>_1_2` (OBI style, which groups by subtask; see `tests/score`).

### `tests/score`

Optional. It turns on **scoring by groups** (subtasks). Without this file, the score of the problem is
the percentage of tests that passed.

The format is plain text, one line per group:

```
sample* - 0 pontos
2015f2p1_capitais_1_*, 2015f2p1_capitais_2_* - 40 pontos
2015f2p1_capitais_3_*, 2015f2p1_capitais_4_*, 2015f2p1_capitais_5_* - 60 pontos
```

Write the word `pontos` in Portuguese, exactly as shown. It is the canonical form of the format. The parser reads only the number, but other tools and the documentation use `pontos`.

How to read a line: one or more **globs** of test names, then ` - `, then the **weight** of the group.

Rules:

- A group is **all or nothing**: if one test of the group fails, the group is worth 0.
- The total value of the problem is the **sum of the weights**. The sum does not have to be 100 (it
  can be more).
- The separator between globs is **comma and space** (`", "`). This is not style: it is what the
  parser expects on both sides (API and judge).
- Samples usually have weight 0, so that they appear in the report and give no score.
- A line that starts with `#` is a **comment**. Any other line that is not
  `<globs> - <N> pontos` is **ignored with a warning** in the judge log. It does not become a group.
- Tests match groups by **real glob** (`aula_*` matches `aula_2_1`), and **each test must fall into a
  group**. `validate-problem.sh` checks all of this at upload (check `score_file_sane`). A test
  without a group, or a group with weight>0 and no test, is a broken package. If it gets to the judge
  anyway, the submission gets **Judge Error** with score 0 (an error of the package, not of the
  student). A group with **weight 0** and no test (e.g., `sample* - 0 pontos` in a `SAMPLE=no`
  problem) is accepted and breaks nothing.

**The verdict is the verdict of the worst test; the groups set only the score.** A group that failed
because of a time-out gets **Time Limit Exceeded** with the score of the groups that passed (not "wrong
answer"). It is the same verdict that the tests give without groups. The string that the judge returns
(and that the history keeps) is
`<veredicto canônico>,<pontos>p. Pontos | <por grupo> | [quantitativos <código>(<n>) …]`
(`<veredicto canônico>` = canonical verdict, `<pontos>` = points, `<por grupo>` = points per group,
`<código>(<n>)` = verdict code and number of tests; `Pontos` and `quantitativos` are literal words):

```
Accepted,100p. Pontos | 30 | 70 |
Time Limit Exceeded,30p. Pontos | 30 | 0 | quantitativos TLE(2) AC(8)
Judge Error,0p. teste 'extra1' sem grupo em tests/score (erro do pacote)
```

The student reads the prefix (the server makes it canonical when it reads it), and the score is the
first `NNp` of the string. Until 2026-09-24 each group failure gave `Wrong,<n>p`, so a TLE got to the
student as "Wrong Answer". The history recorded before that date stays as it is (`Wrong,…` and the
legacy `Wrong. Pontos | …` are still read as Wrong Answer). A rejudge gives the real verdict.

`mojtools/score-summary.sh`, on the judge, interprets the file. If you edit `tests/score` (or a
`tests/output/*`), the checksum of the package changes. The judge downloads it again and recalibrates
automatically.

### `sols/`

The reference solutions, separated by category. **The file extension sets the language** (`sol.c` is
C, `sol.cpp` is C++, `Main.java` is Java, and so on). C++ accepts four extensions: `.cpp`, `.cc`,
`.cxx` and `.c++`. The judge treats all four as `cpp`.

| Directory | What it is | What calibration requires from it |
|---|---|---|
| `good/` | **correct** solutions | **mandatory, at least one.** Accepted in all tests, within the **effective** time limit (the one the judge enforces, with `TLOVERRIDE`). Calibration uses it to measure the time limit |
| `wrong/` | intentionally **wrong** solutions | **rejected**, preferably by wrong answer (WA): it proves that the tests catch the error |
| `slow/` | intentionally **slow** solutions | **TLE** in at least 1 test and accepted in the others: it proves that the time limit rejects the bad solution |
| `pass/` | solutions that must pass **by a small margin** | accepted in all tests, within the effective time limit: it proves that the limit is not too tight |
| `upcoming/` | drafts | does not run |

Calibration checks each solution against this table (section 10, "Solutions"). The result appears in
the editor, in the Dashboard and in `moj calib`/`moj check`.

In practice, put one `good` solution in each language that you want the student to use. The time
limit is calibrated **per language**. A language without an accepted `good` solution gets no time
limit on that judge (the student cannot use it).

**If you save ANY solution, the judge fetches the package again** (it is the `pkg_version` of section
10). Thus "Save" + "Calibrate" runs the `sols/` that you just wrote. Only `good/` changes the TL.

### `scripts/` (special judging)

Optional. With it the problem **customizes** compilation, execution or comparison.
`build-and-test.sh` looks for the files of the problem **before** the defaults of
`mojtools/lang/<lang>/`. Thus anything that you put here overrides the normal behavior.

The most common uses:

| File | Use | How many in the archive |
|---|---|---|
| `scripts/<lang>/compile.sh` | **function submission**: the student submits only the function, and this script injects the `main` that reads the input, calls the function and prints the result | 201 |
| `scripts/compare.sh` | **checker**: the answer is not unique (floating-point tolerance, many valid answers), so the problem has its own comparator | 18 |
| `scripts/checker.cpp` | the **source** of the checker when it is [testlib](https://github.com/MikeMirzayanov/testlib) (Polygon/Maratona standard). It comes with a 10-line `compare.sh` — the **stub** — that `mojtools/testlib/install-checker.sh` installs. **`testlib.h` does NOT go in the package** (it is vendored in mojtools), and the checker binary is **never** committed (the mojtools *bridge* compiles it on the judge, on demand, and caches it OUTSIDE `scripts/`). |
| `scripts/arbitro.{cpp,py,sh}` + `scripts/c/{prep,run}.sh` | **interactive problem** (`mojtools/interactive/install-interactive.sh`) | — |
| `scripts/validator.cpp` | **INPUT validator** ([testlib](https://github.com/MikeMirzayanov/testlib) `registerValidation`, the Polygon standard): checks that each `tests/input/*` follows the format and the limits of the statement. **It does not judge any solution.** Full calibration runs it on the judge (dimension **Inputs**, section 10). On your machine, use `moj validator`. It is outside the `tl_checksum` (a change to it does not recalibrate) and inside the package version. Guide: `mojtools/docs/validador-testlib.md` | — |

The contract of the comparator: it receives `$1` = output of the student, `$2` = expected output,
`$3` = input. It answers with the exit code (`4` = accepted, `5` = accepted with presentation error,
`6` = wrong answer, any other = judge error).

**Stub, not copy.** What runs **on the judge host** — `scripts/compare.sh`, `scripts/<lang>/prep.sh`,
`scripts/summary.sh` — goes in the package as a **stub** that calls the canonical driver of mojtools.
Only what **goes into the cage** (`scripts/<lang>/run.sh`, `compile.sh`) is a real copy. This lets us
fix a bug of the driver **in one place only**. When each package had its own copy of the checker
*bridge*, one bug in it was replicated in 198 packages (and it failed **all** tests of the problems
that used it). A problem can, of course, replace the stub with its own comparator (the 18 in the
archive do this, all written by hand).

Each `.sh` in `scripts/` needs the execute bit (`chmod +x`), and the bit **travels** (`moj
push`/`clone` and `upload` keep it). Without it, the judge gets *Permission denied* when it runs the
script. `compare.sh`/`prep.sh` run **on the host** (outside the cage) and become a **judge error (UE) in
all tests**. `run.sh`/`compile.sh` are mounted in the cage and become Compilation Error.
`validate-problem.sh` rejects the package (`scripts_exec`) before this happens.

**File mode: 644 (or 755 with `+x`), always.** The server normalizes the mode on each write, through
both paths (`moj push` and `moj upload`). The umask of the process does not decide it. This is
important because `tl-checksum` includes the **mode** of `scripts/*`. If the same content comes in with
a different mode on each path, the judge sees "package changed" and **recalibrates for no reason**.

**A change to `scripts/` makes a recalibration necessary** (section 10). The exception is
`scripts/validator.cpp`, which does not change the judging.

The files of `scripts/` form **4 independent slots that COMBINE** — compile (function
submission/ban), run (interactive), compare (checker/tolerance), summary (scoring). Thus function +
special checker is a normal combination. Only the interactive slot does not mix. The
`validator.cpp` takes no slot: it combines with all of them.
The hub guide is `mojtools/docs/correcao-especial.md` (forbid library functions, overview).
The long guides: `mojtools/docs/submissao-de-funcao.md` (**function submission** — ready templates
with `moj fn` or in the web editor, with the anti-IO sentinel), `checker-testlib.md` and
`problema-interativo.md`.

### `conf`

The execution limits and settings. **It is a shell file, read with `source`.** Thus never
interpolate content that comes from a user into it.

A typical `conf` of the archive is short:

```sh
TLMOD[calibrafactor]=1.35
TLMOD[java.drift]=0.02
TLMOD[spim.sum]=1
ULIMITS[-u]=10000
ALLOWPARALLELTEST=y
```

All the keys that `build-and-test.sh` understands:

> **Tolerance (drift) in the report.** An accepted test with a time above the limit passed through the
> tolerance. `report.html` shows this time in **yellow**, with the amount over the limit
> (`0.98s (+0.16s na tolerância)`). Blue is within the limit, and the TLE color is over the limit. The
> test table of the editor (test-run and calibration) uses the same yellow.

| Key | Default | What it does | Use today |
|---|---|---|---|
| `TLMOD[calibrafactor]` | `1.35` | multiplier applied to the time of the `good` solution to get the time limit. A higher value gives the student more margin | 453 |
| `TLMOD[<lang>.drift]` | `0` | tolerance (in seconds) above the time limit before TLE, in that language: the test is TLE only when `tempo − TL > tolerância` (time minus TL is greater than the tolerance) | 404 (`java`) |
| `TLMOD[default.drift]` | — | the same tolerance for **each** language that does not have its own (`TLMOD[<lang>.drift]` wins). It applies in judging and in the calibration check of the solutions (a `good` within the tolerance is not "diverging") | 0 |
| `TLMOD[<lang>.sum]` | `0` | adds a fixed value (in seconds) to the time limit of that language | 405 (`spim`) |
| `TLMOD[<lang>.mult]` | `1` | multiplies the time limit of that language | 0 |
| `ULIMITS[-u]` | `1024` | maximum number of processes. Java and other runtimes need more (the archive uses `10000`) | 453 |
| `ULIMITS[-s]` | `131072` (128 MB, in KB) | stack size. Prefer `STACKLIMITMB` | 0 |
| `ULIMITS[-f]` | `256000` | maximum size of a file that the program can write | 0 |
| `ALLOWPARALLELTEST` | on (absent = `y`) | `y` = the judge **can** run many tests of this submission at the same time, each on its k CPUs, when it has idle CPU (admin policy; off during a contest); `n` = one test at a time. **It does not change the time limit**: calibration always runs one test at a time. See "Parallel problems" below | 453 |
| `STACKLIMITMB` | 128 | stack in MB. It wins over `ULIMITS[-s]`. The JVM mirrors it in `-Xss` | 0 |
| `MEMLIMITMB` | no RSS limit | memory limit in MB, measured by the **peak RSS**. If you set it, the virtual memory limit is turned off (that limit is unfair to JVM and Go). The JVM uses this value in `-Xmx` | 0 |
| `COMPILEMEMLIMIT` | `2048` | memory in MB available for **compilation** (`kotlinc` uses more than 600 MB) | 0 |
| `MAXPARALLELTESTS` | judge ceiling (4) | ceiling of simultaneous tests for this problem (integer ≥ 1); it is never more than the judge ceiling (`parallel_max`, default 4) or `nproc/k` in a manual run | 0 |
| `CPUNEEDED` | `1` | **CPUs that each test needs** (1..64; parallel problem — OpenMP/MPI/pthreads). The judge joins k slots for each test, and the cage gets `MOJ_TEST_CPUS`/`OMP_NUM_THREADS` = k. A change recalibrates. See "Parallel problems" | 0 |
| `SAMENUMA` | `n` | with `CPUNEEDED>1`, `y` = the k CPUs of each test are on the same NUMA node | 0 |
| `STOPWHEN_WA` | does not stop | `y` stops at the first Wrong Answer | 0 |
| `STOPWHEN_TLE` | does not stop | `y` stops at the first Time Limit Exceeded | 0 |
| `STOPWHEN_RE` | does not stop | `y` stops at the first Runtime Error | 0 |
| `TLERERUN` | `y` | runs the test one more time before it confirms a TLE (prevents TLE from machine noise) | 0 |
| `CALIBRATIONTL` | `5` | time limit used **during** calibration, before a real TL exists | 0 |
| `ALLOWTLEDURINGCALIBRATION` | off | `y` accepts a `good` solution with TLE as "calibrated" (the language gets a TL even when it goes over `CALIBRATIONTL` — rare cases of a `good` solution that is deliberately at the limit) | 0 |
| `SAMPLE` | samples = `tests/input/sample*` | `no` declares that the problem **has no samples** (section 4, "Problem without samples"): the statement has no box and nothing is offered for download. The judge does not read it, and it is not part of the tl-checksum (no recalibration) | 0 |
| `TLOVERRIDE[<lang>]` / `TLOVERRIDE[default]` | no override | **the author forces the TL** (seconds, per language + default). Calibration continues to run (and its history stays visible), but the FINAL value — in judging (the judge applies it AFTER the `TLMOD`, so it wins over everything) and in EACH display (training, contest, TL sheet of the contest, `/problems/tl`) — is `TLOVERRIDE[lang] // TLOVERRIDE[default] // calibrado[lang]`. Only a literal numeric value (`TLOVERRIDE[java]=2.5`); the server reads it with grep and never runs the conf. ⚠ **Use `TLOVERRIDE[py]`, never `py3`/`py2`.** These are LEGACY keys: the server normalizes them to `py` for display, and the judge does too (since 2026-08-24). Before that date, a `TLOVERRIDE[py3]` was DISPLAYED but not USED IN JUDGING. **Problem management** (Dashboard, editor, `/problems/{get,status,calib,tl}`) also shows the effective value — with a ⚡ badge and the calibrated value next to it. The times on the calibration cards continue to be the MEASUREMENT, because calibration ignores the override on purpose. ⚠ A change to the override changes the tl-checksum ⇒ it starts a recalibration (harmless — the override wins anyway) | 0 |

The column "Use today" counts in how many of the 453 `conf` files of the archive the key appears. A zero
does not mean that the key does not work. It means that the default is correct for almost all
problems. Change a key only when you have a reason (a problem that needs much memory, or a language
that needs more margin).

`PUBLIC=no` in `conf` is **legacy**. Today the field `public` of `.moj-meta.json` decides if the
problem is public.

#### Parallel problems (`CPUNEEDED`, `SAMENUMA`) and tests in parallel

Two different things use the same word:

| | What it is | Key |
|---|---|---|
| **parallel test** | ONE test uses **k CPUs** at the same time (the program of the student is parallel) | `CPUNEEDED=k`, `SAMENUMA=y` |
| **tests in parallel** | the judge runs **many tests** of the same submission at the same time, each on its k CPUs | `ALLOWPARALLELTEST`, `MAXPARALLELTESTS` |

The official judges are partitioned into **slots of 1 CPU**. A problem with `CPUNEEDED=k`:

- goes only to a judge with **k free slots** (with `SAMENUMA=y`, k free slots **on the same node**);
  the agent joins them into a group, pins the test to it (inside the cage `nproc` = k) and separates
  them at the end;
- is **calibrated with k CPUs, one test at a time**. The time limit is valid only with the same k.
  Thus a change to `CPUNEEDED`/`SAMENUMA` recalibrates (the `conf` is part of the checksum);
- gives the cage `MOJ_TEST_CPUS` and `OMP_NUM_THREADS` (= k, exported by `binfile.sh`). OpenMP sizes
  itself. The MPI `run.sh` does `mpirun -np "$MOJ_TEST_CPUS"` — **never a fixed `-np`**. Ready
  templates: `paralelo-openmp` and `paralelo-mpi` (selector of the editor);
- with hyperthreading and k ≥ 2, the group is made of **full cores**, in calibration and in judging;
- with no capable judge (k larger than any judge, or than any node with `SAMENUMA=y`), the judging
  waits. After some time, it gets **Judge Error** with the reason. "Validate" warns before this.

`ALLOWPARALLELTEST` on (the default) only says that the judge **can** run many tests at the same time
when it has idle CPU (the global admin policy decides; it is off during a contest). Each test stays
alone on its CPUs, and the time is measured as always. A TLE seen in this mode is run again serially
before it counts. `MAXPARALLELTESTS` is the ceiling per problem. The submission report says what
happened: `Paralelismo: P teste(s) ao mesmo tempo × k CPU(s) por teste` (parallelism: P test(s) at
the same time × k CPU(s) per test). Validation rejects an invalid
value in the four keys. The servable json (`var/jsons/<id>.json`) has `cpu_needed` and `same_numa`.
The pre-contest checklist of the contest (`judges_cpus`) uses it to warn when no judge of the pool has
the CPUs, without opening the package. Full guide: `mojtools/docs/problema-paralelo.md`.

### `author`

Free text, one author per line. It is served to the student **verbatim** (the lines are joined with
`", "`). Do not separate names with commas and expect the system to split them: commas already appear
inside lines ("Fulano, adaptado por Beltrano").

The file is **mandatory**: without it, validation fails.

### `tags`

The topics of the problem, one tag per line, starting with `#`, in lowercase:

```
#grafos
#bfs
#matriz
```

The tags feed the training search and the **random selection** of problems when you create a contest.

Tags are **curation**, not judged content, and `moj upload` treats them that way. A tar **without** the
`tags` file ⇒ the server **keeps** the tags that it has (a directory built by hand seldom has the file,
and the mirroring deleted the tags silently). A tar **with** the file (even an empty one) ⇒ it replaces
them. To delete all tags on purpose, send an empty file (or use the web editor / `moj push`).

**Difficulty is not a tag and does not exist in the package.** MOJ **calculates** it from the real
success rate of the students (easy if at least half solve it, hard if less than 20% solve it, unknown
if nobody tried). Do not look for a difficulty field to fill in.

### `tl` and `tl.<host>`

**You do not write these files.** Calibration makes them, on the judge. See section 10.

## 5. `.moj-meta.json`: the problem metadata

It is the **canonical** metadata of the problem: what does not fit in any of the files above. It is
inside the package and is committed with it.

The **server** always writes it (function `write_meta`, in `server/api/v1/lib/problems.sh`). The author
and the CLI do not edit this file by hand. They send the fields through the API, and the server writes
them.

**In `moj upload` (the package goes up as a tar), the server separates the fields into two groups:**

- **content** — `display_title`, `collections` and `languages`: they **come from the `.moj-meta.json`
  of the tar** (the package knows the name of the problem and the languages that it accepts for
  submission). If they are absent or empty (`[]`) ⇒ the server **keeps** the values that it had. To
  clear the language whitelist, use `moj push` or the editor, never an omission in a tar.
- **access** — `public`, `public_at` and `owner`: they **never** come from the tar. Only their own
  routes change them (`/problems/set-public` etc.). If they came from the tar, a person could download
  a public problem, adapt it for a contest in a private org and run `moj upload`. The next indexing
  would publish the contest problem.

The CLI closes the loop. In `moj upload` of a **directory**, it synthesizes a `.moj-meta.json` in the
tar from the local `.moj-id` (title/collections/languages). Thus a package from `moj clone` goes up
complete. (A tar from `moj download` already has the real meta of the server.)

Real example (`moj-problems/apc/seno/.moj-meta.json`):

```json
{
  "public": true,
  "collections": ["problemas-apc"],
  "display_title": "Seno por série de Taylor",
  "owner": "ribas.admin",
  "gitea": { "owner": "ribas.admin", "repo": "apc" },
  "languages": ["c", "cpp", "java", "py", "rs"]
}
```

Field by field:

| Field | Type | What it is |
|---|---|---|
| `display_title` | text | **The title of the problem.** It is the single source. If the author does not send a title and the field does not exist yet, the server **derives** one (from the `%` of the statement, from the `#+title:` of the org file, from the `\section{}` of the tex file, or, as a last option, from the directory name). Thus the field is never empty |
| `titles` | object `{"en": text, "es": text}` | the title of each **translation** of the statement (section 4, "Languages"). The server keeps only a language that has `docs/enunciado.<lang>.md`. A language without a title uses `display_title`. In the CLI it is the field `titles` of `.moj-id` (`moj title --lang en "Hello World"`) |
| `owner` | login | the owner of the problem |
| `public` | boolean | if `true`, the problem goes into the Free Training. To publish, the **org** must allow it (section 7) |
| `collections` | list of texts | the collections that contain the problem (section 8). It can be in many |
| `languages` | list of ids | the submission languages **allowed** in this problem. Empty or absent = all the default languages. This makes possible, for example, a PDDL-only problem. The server normalizes the list (lowercase, `py2`/`py3` become `py`, `cc`/`cxx`/`c++` become `cpp`, no duplicates). **The API REJECTS a submission that is not in the list** (`400 lang_not_allowed`, in `/submit` and in offline submission — it is not only the filter of the dropdown). This is essential in a function/ban problem: without it, a change of the extension got past the driver |
| `public_at` | epoch | when the problem was published **for the first time**. It stays there also if the problem is unpublished later. It feeds the statistics of new public problems |
| `migrated_at` | epoch | when the problem came from a migration. Information only |

Two fields are **legacy**. Do not use them in new code:

- `gitea.{owner,repo}`: it remains from the time when the packages were mirrored in a Gitea. The Gitea
  was removed. The field is still in the 453 metas of the archive, and one place still reads it, as an
  alternative to find the `owner` of old packages.
- `collaborators`: some points read it, but it is **never written**, and it is empty in the full
  archive. In the org model, to collaborate on a problem is to **be a member of the org** (section 7).

Who reads `.moj-meta.json`: `gen-problem-json.sh` (to build the student index),
`gen-problem-owners.sh` (to build the owners index), and the API, when it returns the problem to the
editor and to the CLI.

## 6. `.moj-id`: the local CLI pointer

Pay attention, because this point causes the most confusion: **`.moj-id` is not part of the
package.** Note also that it **has no `.json` extension** (there is no file `.moj-id.json` in MOJ),
although its content is JSON.

**`moj-cli`** creates it, on your machine, when you run `moj clone` or `moj new`. It lets the local
clone remember which problem it is, and it carries the editable metadata fields in both directions.
`moj push` **excludes** this file from the upload.

```json
{ "id": "apc#seno", "repo": "apc", "prob": "seno", "title": "Seno por série de Taylor",
  "format": "md", "collections": ["problemas-apc"], "public": true, "base_rev": "9f2c61d0a8b37e14" }
```

| Field | What it is |
|---|---|
| `id`, `repo`, `prob` | which problem this directory is (`<org>#<prob>`) |
| `title` | local mirror of `display_title`. If you edit it here and run `push`, the title changes on the server. `push` **refuses** to send an empty title |
| `titles` | local mirror of `titles` of the meta: the title of each translation (`{"en": "Hello World"}`). `moj title <dir> --lang en "…"` edits it |
| `trans_rt` | `true` in a clone that **knows** the translations: `push` sends `translations` with all languages, and a language without a local file becomes `null` (deleted on the server). An old clone does not delete the translation of other people |
| `format` | `md`, `org` or `tex`, the statement format of this clone |
| `collections`, `languages`, `public` | local mirrors of the fields of `.moj-meta.json`, in both directions with `push` (and `moj upload` of a directory sends title/collections/languages in a meta **synthesized** from here; `public` never goes up). `moj languages <dir>` edits the whitelist without opening the file |
| `scripts_rt` | marks that this clone can send `scripts/` and `tests/score` in both directions. Without this mark, `push` has no permission to **delete** these files on the server (this prevents old clones from destroying the special judging by accident) |
| `base_rev` | the server revision (`rev`) at the last `clone`, `pull` or `push` of this folder. `push` and `upload` send it as `base_rev`. If the problem changed on the server since then (web editor, another author), the server refuses with 409 and writes nothing. `moj push --overwrite` sends over it. Empty = a folder from before this lock (`push` writes over it, as always) |

Next to `.moj-id`, the CLI writes **`.moj-base`**, the *baseline* of the folder: one line
`<hash>\t<caminho>` (`<caminho>` = file path) for each file of the package (the set that `push` sends), plus one line
`<hash>\t.moj-id` with the authoring fields of `.moj-id` (title, titles, languages, collections).
`moj pull` uses it to know what **you** changed since the last `clone`/`pull`/`push`:

- folder without changes from you, and a new version on the server: `pull` replaces the package files
  (it also deletes the files that are gone from the server) and keeps the files that are not part of
  the package (a `gerador.py`, for example);
- folder with changes from you: `pull` **refuses** and lists the files. `moj pull --force` copies the
  full folder to `<pasta>.local-AAAAMMDD-HHMMSS` (`<pasta>` = the folder name, `AAAAMMDD-HHMMSS` =
  date and time) and then gets the server version;
- folder without `.moj-base` (cloned before `pull` existed): `pull` compares with the server. If they
  are equal, it only writes the baseline. If not, it refuses (it cannot know who made the change) and
  suggests `--force`.

`.moj-base` also does not go up (not in `push`, and not in the tar of `moj upload`).

The difference, in summary:

| | `.moj-meta.json` | `.moj-id` |
|---|---|---|
| Where it lives | inside the package, on the server | in the local clone of the author |
| Who writes it | the server | `moj-cli` |
| Does it go to the server? | it **is** the server's | **no**, it is excluded from the upload (and `.moj-base` also) |
| What it is for | to be the canonical metadata | to remember which problem the directory is and to carry the fields in both directions |

The 336 `.moj-id` files that appear today inside `moj-problems/` are **residue** of old migrations
that copied full directories. The server ignores them.

## 7. ORG: who can make changes

An **org** is an access group. It is the part before the `#` in the problem id (`apc#fatorial` is in
the org `apc`), and it decides **who can edit** the problem.

The registry is in `contests/treino/var/orgs.json`, and the code is in `server/api/v1/lib/orgs.sh`.

```json
{
  "monitores": {
    "created_by": "ribas.admin",
    "title": "monitores",
    "members": ["ribas.admin", "ryshim.admin"],
    "admins":  ["ribas.admin"],
    "public_allowed": true,
    "at": 1783051935
  },
  "ribas.admin": {
    "created_by": "ribas.admin", "title": "ribas.admin",
    "members": ["ribas.admin"], "admins": ["ribas.admin"],
    "public_allowed": false, "implicit": true, "at": 1783515797
  }
}
```

| Field | What it is |
|---|---|
| `members` | who **writes** to the problems of the org. A member of an org has edit access to **all** of its problems |
| `admins` | who manages the members and changes the lock `public_allowed` |
| `public_allowed` | if `false` (the **default**), **no** problem of the org can be public |
| `implicit` | marks the personal org of a user (see below) |
| `created_by`, `title`, `at` | who created it, display label, when |

The rules to remember:

- **To be a member of the org is the only way to edit a problem.** There is no shortcut for a global
  administrator. Not even `.admin` sees the source code, the solutions or the package of a problem of
  an org of which it is not a member.
- **An org starts private** (`public_allowed: false`). This is intentional: a contest in preparation
  must not leak by accident. While the lock is closed, an attempt to publish a problem of the org
  returns an error. If an admin **downgrades** the org later, its public problems are unpublished in
  cascade.
- **Each user has a personal org**, with the name of the user's login (the **implicit** org). MOJ
  creates it automatically. It has only you as a member, and it can **never** allow public problems.
  It is the place for drafts.
- **A person who cannot see gets 404, not 403.** A "403, it exists but you cannot see it" already leaks
  the existence of a contest problem. A private problem simply **does not appear** in the lists, not
  even for `.admin`.
- You can **remove** an org only **if it is empty**. The implicit org is never removed.

You can **move** a problem to another org while it is a draft (`moj mv`, or in the editor). This
changes the id. Thus MOJ refuses to move a problem that is already public or already in use in a
contest.

Routes: `/orgs/*` in [API.md](API.md). With the CLI: `moj org list|create|members|public|rm` and
`moj share <org> <login>`.

## 8. COLLECTION: how problems are grouped

A **collection** is a grouping label, and nothing more. `problemas-apc`, `obi2016`,
`obi2016-fase2-senior` are collections.

The registry is in `contests/treino/var/collections.json`:

```json
{
  "problemas-apc":         { "owner": "ribas.admin", "created_by": "ribas.admin", "at": 1782519704 },
  "obi2016-fase2-senior":  { "owner": "ribas.admin", "created_by": "ribas.admin", "at": 1782927032 }
}
```

The collections that contain a problem are recorded in its `.moj-meta.json`, in the field
`collections` (a list, because **a problem can be in many collections at the same time**, and they can
be from different orgs).

Important points:

- **A collection gives no access.** If you mark a problem in a collection, nobody gets permission to
  edit it. The org always decides access.
- The name is **free text**: it can have spaces and accents (`"Maratona 2024, fase 1"` is a valid
  name). It never becomes a file path or an id.
- The registry is **curated**: to mark a problem in a collection, the collection must **already
  exist**. This prevents a zoo of collections, each with a different typo.
- If you rename or delete a collection, **all** the problems that had it are relabeled at once.
- Only the owner of the collection (or a `.admin`) can rename or delete it.

What they are for, in practice:

1. **Navigation in the training**: the student filters the problems by collection.
2. **Random selection of problems** when you create a contest: you ask for "5 problems of collection X,
   with the tag `grafos`, medium difficulty", and the system selects them (in a reproducible way, from
   a seed).

Routes: `/problems/collection*` in [API.md](API.md). With the CLI:
`moj collection ls|show|create|add|remove|rename|delete`.

## 9. ORG x COLLECTION

This pair causes the most confusion, so here is a table. **The two are orthogonal**: a problem has
exactly one org and can have many collections.

| | ORG | COLLECTION |
|---|---|---|
| What it is for | **access** (who edits, who sees) | **grouping** (browse, random selection) |
| How many per problem | exactly **one** | **many**, or none |
| Is it in the id? | yes, it is the `<org>` of `<org>#<prob>` | no |
| Does it cross orgs? | not applicable | yes, a collection joins problems from different orgs |
| Does it have members? | yes (`members`, `admins`) | no |
| Does it control publication? | yes (`public_allowed`) | no |
| Where it is registered | `contests/treino/var/orgs.json` | `contests/treino/var/collections.json` |
| Where the problem declares it | in the id itself | in `.moj-meta.json`, field `collections` |

In one sentence: **the org says who controls the problem, the collection says where it appears.**

## 10. Life cycle of a problem

```
   draft     ──►  package checked  ──►  calibrated  ──►   READY    ──►   public
 (private org)   (Validate button:     (on the judge:   (no pending    (Free Training)
                  static)               TL, solutions,   item, no
                                        inputs)          open issue)
```

"Ready" is not a step that a person does. It is the name of the state in which **all** the dimensions
below are green. You can still publish without it, but MOJ asks for confirmation (subsection
"Publication").

### Draft

The problem starts in your org (the personal org, if you do not select another one). It is private:
nobody except the members of the org sees that it exists.

### Package checked (the Validate button)

It runs `mojtools/validate-problem.sh`, which writes a report in `run/validation/<id>.json`. It is a
**static** check of the package content: files, statement sections, samples, paired tests. **It runs
no solution.** Calibration runs the solutions (below). This is why the screen says **"Package"**, and
no longer "Validated". The old name made authors think that the solutions were checked (report from
Arthur Botelho, 2026-09-22).

**All** the checks below must pass (there is no "optional" check that fails halfway):

| Check | What it requires |
|---|---|
| `has_author` | the file `author` exists |
| `has_statement` | `docs/enunciado.{md,org,tex}` exists |
| `html_builds` | pandoc can render the statement |
| `secao_entrada` | the statement has `## Entrada` |
| `secao_saida` | the statement has `## Saída` (accepts `Output` and `Salida`) |
| `html_builds_<lang>`, `secao_entrada_<lang>`, `secao_saida_<lang>` | the same, for each translation `docs/enunciado.<lang>.md` that exists |
| `examples_present` | at least one input/output pair exists |
| `tests_paired` | each input has its output, and the reverse |
| `has_good_sol` | at least one solution exists in `sols/good/` |
| `good_sol_accepts` | each `good` solution is accepted |

Some warnings are **for information** and do not fail: LaTeX leaking into the prose of the statement,
a sample written by hand in the text, and a checker committed as a binary (old pattern, deprecated:
send the source `scripts/checker.cpp` and let the bridge compile it).

About `good_sol_accepts`: to run the solutions, a real sandbox is necessary, and the server does not
have one. The package check **defers** this check to calibration, which runs on a real judge (the
report says `verificado na calibração (juiz)`, that is, checked at calibration on the judge). The result of each solution appears in the dimension
**Solutions**.

If validation passes, it **indexes** the problem (it calls `gen-problem-json.sh`). This makes the JSON
that the student actually uses, with the statement already in HTML.

### Calibration (where the time limit comes from)

**You do not write the time limit by hand in the package.** It is **measured**.

A judge downloads the package, runs each solution of `sols/good/`, takes the worst time of each
language, multiplies it by `TLMOD[calibrafactor]` (1.35 by default) and reports the result to the
server. The result goes into `run/tl/<id>.json`, stored **per machine**:

```json
{ "id": "apc#ajude_simplificado", "checksum": "df7f628e84bfc6c3", "updated_at": 1783534737,
  "hosts": {
    "cpu1": { "tl": { "c": ".0335", "cpp": ".0335", "java": ".3710", "py": ".1685",
                      "default": ".0335" }, "at": 1783534737 },
    "cpu2": { "tl": { "…": "…" }, "at": 1783534733 } } }
```

The time limit **served** to the student is the **largest value across the machines**, so that a
submission is not rejected because it went to a slower judge. A language gets a time limit only if a
`good` solution in that language was **accepted** on a judge. Without a time limit, the language is not
available.

Calibration runs **one test at a time**. In a parallel problem, each test runs with the **k CPUs** of
`CPUNEEDED` — exactly the way in which judging runs each test (this is why the TL for k=2 is not valid
for k=4, and a change to the key recalibrates).

The explicit "Calibrate" (editor, `moj calibrate`, publish) runs **all** the solutions. The on-demand
calibration, which a judge does automatically at the first submission of a new package, runs **only the
`good` solutions** (it is fast on purpose). After it, the other categories show "without result".

### Solutions: does each one do what its category requires?

Calibration returns, per judge and per solution, the code of **each test** (`AC`, `WA`, `TLE`, `MLE`,
`RE`, `UE`). The **server** compares it with the category (`server/api/v1/lib/calib-expect.sh`, the
single source; the editor, the Dashboard and the CLI only show the result) and gives one of four
states:

| State | When |
|---|---|
| ✓ **as expected** | the solution did exactly what its category requires (table of the `sols/` section) |
| ≈ **as expected, other reason** | it did what its category requires, but not in the typical way: `wrong` rejected only by TLE/MLE/RE (no WA); `slow` with TLE, but also with WA/RE in other tests; `good` with TLE and `ALLOWTLEDURINGCALIBRATION=y` |
| ✗ **diverges** | it did not: `good`/`pass` rejected **or slower than the effective time limit** (e.g., `TLOVERRIDE` below the measured time — in judging it would get TLE); `slow` without TLE; `wrong` accepted |
| ✗ **did not run** | CE, UE (error of the grader/judge), language not available on the judge, or no verdict: the solution did not exercise the tests, so it proves nothing |

Two rules changed on 2026-09-22 (before that date, only the screen made the decision, and it looked at
the verdict *string*):

- with TLE and WA in the same solution, the string said only "Time Limit Exceeded" and the WA was
  lost. Today such a `slow` is ≈, and such a `wrong` is ✓ (it has WA);
- a `wrong` that **does not compile** was "ok" (it was not accepted). Today it is ✗ **did not run**.

In a scored problem (`tests/score`) the string has the verdict of the worst test and the score of the
groups (`Time Limit Exceeded,30p. Pontos | …`; until 2026-09-24 it was always `Wrong,Np`). In both
cases the decision looks at the tests: a `slow` with TLE is ✓.

The result is valid for the **version** of the package that was calibrated. If you save something that
calibration exercises (`sols/`, `tests/`, `scripts/`, `conf`), the solutions are marked **"not checked
since the last edit"** until the next calibration. A save of the statement does not mark them.


### The checksum, and what starts a recalibration

There are **TWO stamps**, calculated by the same `tl-checksum.sh`, because the two questions are
different: *"is the measured time limit still valid?"* and *"does the judge still have the correct
package in cache?"*.

| | `tl_checksum` (narrow) | `pkg_version` (wide) |
|---|---|---|
| How it is calculated | `tl-checksum.sh <pkg>` | `tl-checksum.sh --all-sols <pkg>` |
| Covers | `conf` (except the line `SAMPLE`), `tests/input/*`, `tests/output/*` (not empty), `tests/score`, `sols/good/*`, `scripts/*` (content **and** execute bit) **except `scripts/validator.cpp`** | all that the narrow stamp covers **+ `sols/pass`, `sols/slow`, `sols/wrong`, `sols/upcoming` + `scripts/validator.cpp`** |
| What it is for | it ties the **TL** to the package: it is the `checksum` of `run/tl/<id>.json`, the one of the owners index and the one that `/contest/problems` compares | it is the **key of the judge cache** and the identity of a calibration: `/judge/package-meta` returns it as `checksum`, and the agent downloads again when it changes |

Neither of the two covers `docs/enunciado.*`, `tags`, `author` or `.moj-meta.json`
(title/collections/tags).

> `tests/output/*` and `tests/score` became part of the checksum on 2026-07-19. Without them, a
> corrected answer key or score **never got to the judge** (the problem cache did not become invalid).
>
> The split into two stamps is from 2026-09-20 (report from Arthur Botelho). Before that date there was
> only the narrow stamp, and it did both jobs. A change to a `pass`/`slow`/`wrong` solution **did not
> change the key**. Thus the judge recalibrated the `sols/` of the **old cache**: it judged a solution
> that the author had already deleted, it ignored the one that the author had just written, and each
> judge had a different set under the same checksum. Widening the narrow stamp does not work: it also
> says if the TL is valid, and the TL would disappear from the contest at each saved solution.

If the `tl_checksum` of the package no longer matches the stored one, the TL is considered **old** and
disappears (the problem then shows "needs recalibration"). Thus: **a typo fix in the statement does not
force a recalibration; a change to a test, a `good` solution, the `conf` or a script forces one.** A
save of a `pass`/`slow`/`wrong` solution does **not** make the TL invalid, but it makes the judge fetch
the new package. This is exactly what "Calibrate" needs to run what you just saved.

### Inputs: the input validator

If the package has `scripts/validator.cpp` (section `scripts/`), full calibration runs it on the judge,
before the solutions, on each `tests/input/*`. The testlib rejects an input that does not follow the
format or the limits, with a message that says where (`FAIL Integer parameter [name=N] equals to 1296, violates the
range [1, 1000]`). The result appears on the card of each judge (line **Inputs**), in the Dashboard and
in `moj check`/`moj calib`. An invalid input, or a validator that did not run (did not compile, took
more than 5 s on one input or more than 60 s in total), makes the problem not ready. A package
**without** a validator is not a pending item — it only shows "no input validator". The fast
calibration of the first submission does not run the validator.

### Ready

The problem is **ready** when `/problems/status` has no **pending item** (`pending`):

| Pending item | Meaning |
|---|---|
| `package_failed` / `package_unchecked` | the package check failed / never ran (Validate button) |
| `uncalibrated` / `needs_recalibration` | no calibration / the package changed since the calibration |
| `good_no_tl:<langs>` | `good` solution without a time limit in these languages (it failed on all judges) |
| `sols_divergent:<n>` | *n* solutions that diverge or did not run |
| `sols_unchecked` | a solution has no result (fast calibration), or the package changed since the calibration |
| `inputs_invalid:<n>` / `inputs_error` | the input validator (`scripts/validator.cpp`, subsection "Inputs") rejected *n* tests / did not run |
| `issues_open:<n>` | *n* open issues (subsection "Issues") |

The editor shows the badge "✓ Ready" or "N pending" in the top bar. The Dashboard has the card "ready"
and the column Solutions. `moj check` says `pronto: SIM` (ready: yes) or lists the pending items.

### Issues

The review by the problem-setting team uses **issues per problem**. Any member of the org opens an
issue ("test 7 is outside the limit of the statement", "the Python TL is tight"), comments and closes
it. While an issue is open, the problem is not ready. Web: tab **🐞 Issues** of the editor (the
Dashboard shows 🐞N with a link). CLI: `moj issues`. The issues **are not part of the package**: they
stay on the server (`contests/treino/var/problem-issues/`). Thus they do not change the `rev`, they are
not lost in a `moj upload`, and they do not go to the judge. If you move the problem to another org,
the issues go with it. If you delete the problem, its issues are deleted.

### Publication

When you publish (`moj publish`, or the button in the editor), the server **checks the package and
calibrates**. The problem goes into the Free Training when the package check passes (the check makes
the served statement). And, before all this, the **org** must have `public_allowed: true` (section 7).

**If you publish a problem that is not ready yet, MOJ asks for confirmation** with the list of pending
items (in the editor, in the Dashboard and in `moj publish`/`moj public on`; `--yes` only shows the list
and continues). Nothing **blocks** the publication: the person who publishes decides.

## 11. Frequently asked questions

**Where do I put the title?**
In the field `display_title` of `.moj-meta.json`. In practice you edit it in the web editor or in the
field `title` of `.moj-id` (the CLI). Never in the statement text.

**How do I write the time limit?**
You do not write it. Calibration measures it. You can adjust the **margin**, with
`TLMOD[calibrafactor]` in `conf`.

**I want the problem to accept only Python.**
Put `["py"]` in the field `languages` of `.moj-meta.json` — in the web editor, with
`moj languages <dir> py` + `moj push`, or by editing `.moj-id`.

**My problem has many correct answers.**
You need a checker: `scripts/compare.sh`. See `mojtools/docs/correcao-especial.md` and the testlib
guide in `mojtools/docs/checker-testlib.md`.

**The student submits only a function, not the full program.**
It is a function submission: `scripts/<lang>/compile.sh`. Same guide.

**I edited the statement. Do I need to recalibrate?**
No. The statement is not part of the checksum. A translation is not part of it either.

**How do I translate a problem?**
Create `docs/enunciado.en.md` (or `.es.md`) next to `docs/enunciado.md`. Translate the explanation of
each sample in `docs/notes/<sample>.en.md` and the editorial in `docs/solucao.en.md`. Set the title
with `moj title . --lang en "Hello World"`. In the web editor, use the PT · EN · ES chips of the
Statement tab. The Portuguese text is still mandatory.

**Where is the difficulty of the problem?**
Nowhere in the package. MOJ calculates it from the real success rate of the students.

**My problem is a function problem (or interactive). To show the input has no meaning.**
Do not create `sample*`, put `SAMPLE=no` in `conf` (in the web editor: the **Limits** tab, option "this
problem has no samples") and explain the example in the statement text, in a section `## Exemplo`. See section 4,
"Problem without samples".

**I edited on the web. How do I get the changes into my folder?**
Run `moj pull` in the problem folder. If the folder has changes of yours that you did not send, `pull`
refuses. Send them first (`moj push`), or run `moj pull --force`, which keeps your folder in a copy.

**`moj push` said that the problem changed on the server.**
A person saved the problem (web or another clone) after your last `clone`/`pull`/`push`. Nothing was
sent. Run `moj pull --force` to get the new version and apply your changes again from the copy
`.local-*`. Or run `moj push --overwrite` to send your version over it. The web editor has the same
lock: it tells you who made the change and offers "Reload" or "Save over it".

**What is the difference between `.moj-meta.json` and `.moj-id`?**
See the table at the end of section 6. In one sentence: the first is the server metadata. The second is
a note that the CLI puts in your local directory, and it never goes up.

---

## Pointers

- **Practical walkthrough** to build a package, and the reference of each command: `mojtools/README.md`.
- **Special judging** (checker, function submission, interactive): `mojtools/docs/correcao-especial.md`,
  `mojtools/docs/checker-testlib.md`, `mojtools/docs/problema-interativo.md`.
- **API routes** that read and write the package, the orgs and the collections: [API.md](API.md).
- General **architecture**: [OVERVIEW.md](OVERVIEW.md). **Path of a submission**: [FLOW.md](FLOW.md).
- **The authoring CLI** (`moj`): `moj-cli/README.md`.
