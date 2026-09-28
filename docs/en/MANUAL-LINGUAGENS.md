<!-- i18n-source: MANUAL-LINGUAGENS.md blob:fb85a1e361ea3519d8d95018d1df012362e0889e -->
# MOJ: Submitting solutions (languages and input/output)

> **Translation note.** This manual is a translation of the Portuguese original. The command-line tools (`moj`, `moj-contest`, `moj-comp`) print their messages in Portuguese, and the command examples below are identical to the original.

This manual is now a **page of MOJ itself**:

> ### 📖 [`/treino/ajuda/`](/treino/ajuda/)
> On the site: use the **"📖 How to submit"** link, next to the language
> selector, when you submit the solution. **It also works inside a contest**: it is the only page outside
> `/contest/` that `contest-guard` lets you open on the contest subdomain (there it uses the contest
> top bar and follows the contest LOCALE). The reason is that the competitor needs it on the isolated LAN.

The page teaches the same content that this file taught. The content now lives there:

1. **Input and output**: the program reads from stdin, writes to stdout and never opens a file.
2. **The extension is the language**: in the editor, the menu decides (the code becomes `solution.<ext>`).
   With a file, the file extension decides and MOJ ignores the menu. C++ accepts `.cpp`, `.cc`, `.cxx` and
   `.c++`. MOJ records the canonical language (`cpp`) and keeps the name of your file.
3. **Language table**, with the `id` (which is the extension) and the note for each language.
4. **Code template for each language**: the skeleton that the editor gives you and a complete solution,
   with a copy button.
5. **Warnings**: the `public` class in Java, `.pl` that is Prolog and not Perl, Python that is pypy3, and the
   128 MB stack.
6. **What MOJ refuses on receipt**: an extension that the platform does not run (`.exe`, `.pdf`, `.zip`…) comes back
   with **400 `lang_not_allowed`** and the list of what that problem accepts. An empty language list
   means **the platform languages** (`PLATFORM_LANGS`, the mirror of `mojtools/lang/`), never
   "any extension". A source file larger than **1 MB** comes back with **413 `source_too_large`**. These two
   checks came from the incident of 2026-08-19. In that incident, a compiled binary entered the queue and stayed
   pending forever.

## Why it became a page and not a `.md` file

- **The language table is generated** from the real list that the site uses to build the submission menu
  (`web/shared/languages.js`). A new language shows in the help automatically, thus the page **does not
  get old**. A table written by hand here would get old at the first change.
- The code skeleton on the page is the **same** field that the editor inserts. The student reads exactly what
  shows on the screen.
- The page is **trilingual (pt/en/es)**, like every MOJ screen. We run contests with competitors from other countries.
  A manual only in Portuguese would leave these people without instructions.
- The student **does not read the repository**. The student reads the site. When MOJ served this as a `.md` file in `/docs/`,
  the browser downloaded a text file.

The content is `web/treino/ajuda/` (the page) and `web/treino/ajuda/exemplos.js` (the complete solutions).
To add a language to the table, change `web/shared/languages.js`. To add an example
solution, **run the code first** and then add it to `exemplos.js`.

## Where to go now

- How to use the **training** day to day: [MANUAL-TREINO.md](MANUAL-TREINO.md).
- How to submit during a **contest**: [MANUAL-CONTEST.md](MANUAL-CONTEST.md).
- How the judge implements the languages (the `lang/<lang>/` contract): `mojtools/README.md`.
