<!-- i18n-source: MANUAL-CONTEST.md blob:de0793bac66ec94955168314c4648b09dfb944f6 -->
# MOJ: Contestant manual (contest)

> **Translation note.** This manual is a translation of the Portuguese original. The command-line tools (`moj`, `moj-contest`, `moj-comp`) print their messages in Portuguese, and the command examples below are identical to the original.

> **Do you ORGANIZE the contest?** The organizer guide (create and manage contests, web and CLI) is
> a different document: [/treino/criar/tutorial.html](/treino/criar/tutorial.html). Give this manual
> to the contestants.

This manual is for you if you take part in a programming contest or an exam on MOJ (the online judge). It tells you how to enter the contest, submit your solutions, read the scoreboard, ask questions (clarifications), request printing and use the backup.

> **Do you prefer to see the screens?** The **web tutorial with screenshots** (PT/EN/ES) is
> [/contest/ajuda/competidor.html](/contest/ajuda/competidor.html). It is the short, illustrated
> version of this manual. It shows the problem accordion, the submission, the color when you solve
> a problem, the clarification notice and how to read the scoreboard. To open it, click the
> **📖 How the contest works** button on your card at the top of the contest page. The other roles
> (room staff, big screen, judge) have their own tutorials at [/contest/ajuda/](/contest/ajuda/).

> **Do you prefer the terminal?** There is a contestant CLI, **`moj-comp`**. It submits solutions and
> shows verdicts and the scoreboard. It also has an emergency mode for an **Internet outage**: the
> submission is stored encrypted with its time, and it counts correctly when the network comes back.
> Full guide: [/contest/cli.html](/contest/cli.html).
> In a contest with a browser gate per site, the CLI works only **on the contest machine**. It reads
> the User-Agent of the image from `/etc/moj/user-agent` and sends it together with its own. The web
> and the CLI on the same machine are the same machine session.
> **The CLI is not always allowed.** The event organizers decide if you can use it in that contest,
> and they give you this information. Do not assume that it is enabled.

If you only want to know how to submit in each language and how program input and output work, see the **Help** page (`/treino/ajuda/`). You can open it **from inside the contest**: use the **"📖 How to submit"** link next to the language selector when you submit.

## 1. First: registration

Many MOJ contests use the **Free Training accounts**. You compete with the same login and the same
password that you use to practice. In these contests, **you must register before you can enter**.
If you try to log in without registration, you get a message. If registration is still possible, the message has a link to the registration page.
The server shows one of these messages, in Portuguese:
`Você não está inscrito neste contest…` (you are not registered in this contest),
`As inscrições deste contest ainda não abriram` (registration for this contest has not opened yet) or
`As inscrições deste contest estão encerradas` (registration for this contest is closed).

The registration page is on the **main site**, not at the contest address:
`/contests/inscricao/?c=<id>`. The contest subdomain cannot see your training session. This is why
the two addresses are different.

**Individual or team.** You select the mode when you register. This choice is **final** for you.
To change it later, contact the organizers. In team mode:

- one person **creates** the team and invites the others by their training login (each invitee
  gets a notice from the Telegram bot, if the invitee has a linked Telegram account);
- the team has a member limit (usually 3);
- **each person logs in with his or her own training password**. The contest belongs to the team,
  but MOJ records who was at the keyboard for each submission.

**What the team (or you, alone) declares**: the university (the acronym that shows on the
scoreboard), the flag, and if you will use **AI** during the contest (this shows as 🤖 on the
scoreboard). A team also declares a **photo**. The photo shows on the big screen when you solve a
problem.

> **The warm-up also requires registration.** By default, the registration is valid for *all* the
> rounds of the contest, and this includes the warm-up. The registration window is anchored to the
> **official contest**, so it can close before the warm-up ends. Do not wait until the last day.

## 2. Enter the contest

You open the contest with a link in the format `/contest/?c=<id>` (or with a subdomain that the organizers give you). Replace `<id>` with the identifier of your contest.

Before you log in, you already see:

- The contest name.
- The **Start** and **End** times.

What you see next depends on the time:

| Situation | What you see |
|---|---|
| Login is not open yet | A **countdown** with "Opens in HH:MM:SS" (from 24 h up, with the days: "2d 07:04:14"). The page updates automatically. If the organizers move the opening later or earlier, you see the change immediately. |
| Login is open | A login card with the **Username** and **Password** fields and the **Log in** button. |

The contest sets the screen language. It can be Portuguese, English or Spanish.

If the organizers open the login **before** the contest starts, you log in and see the screen "The
contest has not started yet", with a countdown. You do not need to reload the page. The problems
show automatically when the contest starts.

> **In a contest in the format of the Maratona SBC / ICPC, you cannot enter before the start.** The
> login opens at the minute the contest starts. Until then, the screen shows a countdown and **no
> form**. This is not a defect. Do not try from your laptop. The contest runs on the
> machine that the organizers prepared, and the browser check refuses other machines. Use the
> **warm-up** to try everything (section 3).

## 3. Main page (after login)

At the top there is a bar with:

- The contest name.
- A countdown: "Ends in: HH:MM:SS". When the time ends, it shows "Contest ended". In a contest longer than 24 h, it shows the days: "Ends in: 60d 07:04:14".
  The **end time comes from the server**, but the clock of your machine does the countdown.
  If the computer has the wrong time, the countdown is also wrong. The server decides:
  a submission that arrives after the end does not count, even if your screen shows time left.
- The **Logout** button.

Below it there is a navigation menu with **Contest**, **Score** (the scoreboard), **Clarification** and, sometimes, **Backup** and **Printing**.

A **notice** at the top shows when there are "new posts" and "answered clarifications". It blinks when one of your questions has an answer that you did not read yet.

If the contest has a **warm-up** (a practice round before the official contest), a fixed banner at
the top tells you: *"🔁 WARM-UP — This round is for testing the environment and your account: its
scoreboard is NOT the contest one."* **You cannot enter before the contest starts**, so the warm-up
is your only chance to see these screens calmly. Use all of it:

1. **log in** with the credential that you received (if the login on your label does not work,
   get it fixed there, not at minute 3 of the contest);
2. **open a problem** and see which screen you have: statement + editor, statement only, or only
   the time limit (a contest that gives only the problem set as a PDF);
3. **submit a solution on purpose** — including a wrong one — and follow the verdict until the end;
4. **ask for a clarification**, **request printing** and **store a file in the backup**;
5. **look at the scoreboard** and find your row.

If something looks wrong, tell the staff there.

When the warm-up ends, the organizers put the official contest
online **at the same address, with the same login**. The scoreboard goes back to zero and the
problems change. The scoreboard and your submissions from the warm-up stay available (link
**Finished rounds** in *Files & Resources*), if the organizers publish them.

When they exist, the sections **Info & News** and **Files & Resources** also show.
The organizers publish the contest documents in **Files & Resources** when they want you to have
them. There are up to four: the **Judging environment** (system, compiler versions, limits,
compile and run command lines, verdicts and penalty), the **Problem set**, the **Time limits**
sheet and the
**Editorial** (the solutions — it shows only after the contest ends for *all* the sites).

Each document is a row with the name on the left and the **languages as buttons**: `PT`, `EN`, `ES`.
The name is not a link. Click the language that you want. The problem set and the time limits
sheet open only **from the contest start**, even if they already show in the list. If the
organizers did not publish anything, the section does not show.

### The problem list

The problem list is an accordion. Each row has:

- A **triangle** to open and close the problem.
- A **balloon** that gets a color when you solve that problem.
- The short name and the full name of the problem.
- On the right, the statement links (**Statement**, **HTML**, **PDF**), the **Samples** link (it
  downloads the input and the output of each sample as files, in a zip) and a **quick submit** by file.

Each sample block in the statement has a **Copy** button in its title. One click copies the full
block, with the final line break. In the CLI, `moj-comp fetch` writes the samples of all the
problems into the `samples/` folder of the kit.

When you open a problem, the first line is the **time limit**: one chip per language (slower
languages get more time, measured on the judge machine). Then comes the statement. If the
organizers enabled the editor, the editor is next to it, with the options **Side by side**,
**Statement only** and **Editor only**.

> **Statement in more than one language.** If the organizers give the statement in other
> languages, the chips **PT · EN · ES** show above the statement. Click one to change the language.
> The change applies to all the problems of the contest, and MOJ remembers your choice. The
> **HTML** and **PDF** links open in the language that you selected. A problem without a translation
> shows the Portuguese text.
MOJ keeps your choice for the next problem that you open. When you open a problem, the others stay
open: you can keep two problems open at the same time.

> **Contest with PDF only.** Many contests give only the problem set as a PDF, without an HTML
> version. In that case, the row has only the **PDF** link, and the accordion shows only the **time
> limit** (and the editor, if there is one). The screen is not broken: the statement is in the PDF.

> **The browser editor is not always available.** It is a convenience, not a rule, and the
> organizers can disable it. **In the Maratona SBC it is disabled.** In that case, write your code
> in an editor on the machine, compile it in the terminal and submit the file with the file selector
> on the problem row. The contest image is ready for this: **Maratona Linux** has Vim, Emacs,
> VS Code, CLion and PyCharm, with compilers and a debugger. Find out **during the warm-up** which of
> the two screens you have.

To submit a solution:

1. Select the **language**.
2. Type the code in the editor or send a **file**.
3. Click **Submit solution**.

> **What MOJ accepts.** The file extension must belong to a language that the platform runs. If the
> problem limits the languages, it must be one of the languages allowed there. MOJ refuses a
> compiled binary (`.exe`), a PDF or a `.zip` **immediately**, and shows the list of what that
> problem accepts. No judge can run an `.exe`. Before this check, such a submission went into the
> queue and stayed pending forever. The maximum source code size is **1 MB**.
>
> If you get an error instead of "✓ Sent!", **read the message**: it tells you exactly what
> happened. A submission is accepted only when the server confirms it. A submission cannot be
> "lost on the way".

## 4. My submissions

The table is at the end of the contest page. It also has its **own page**: the
**My submissions** button in the bar opens `/contest/submissions/`. That page has only the table,
the filter by problem and the sort by column. The list updates automatically while a verdict is pending.

Below the problem list there is a filter by problem and a table with your submissions. The columns are:

| Column | What it shows |
|---|---|
| Time | Minutes since the contest start. |
| Problem | The problem that you submitted. |
| File | The file name. The **src** link downloads your source code. |
| Result | The judging verdict. |
| Date | When you made the submission. |
| Log | Shows when viewing the log is allowed. It opens the judging report. |

You **always see the canonical verdict** (without the embedded score), with a summary line that depends on the contest mode. While a submission is pending, the list updates automatically.

The **Log** column (or link) opens the judging report. In contests in **ICPC** mode, the log is usually hidden by default, to prevent test data leaks. The organizers can enable or disable this option.

## 5. Scoreboard (`/contest/score/?c=<id>`)

> **Before the contest starts**, the scoreboard is a **showcase**: it shows the registered teams and
> nothing more. It has no problem columns. This is on purpose: the number of problems in the contest
> is also a surprise.

The scoreboard updates automatically and animates the teams that go up and down. It has:

- A **filter** bar: which scoreboard (when the contest has cohorts — *official* × *guests*,
  or *teams* × *individual*), flag, university, site and a **search** by team, university
  or login. Filtering **does not renumber** anyone: the places stay the places of the full
  scoreboard, and a counter shows how many rows are left.
- Checkboxes to **disable the animation** and for **Anonymous** mode (the contest can force this
  mode on — then you cannot clear the checkbox).

In **ICPC** mode, the columns are: place, flag, team, one column per problem, **Total** and **Pen.** (the sum of the penalties, which is the first tie-break). The team cell can show 🤖 (the team declared AI use when it registered). In each problem cell:

| Cell | Meaning |
|---|---|
| Empty | You did not try that problem. |
| `1/12` in the **balloon color** of the problem | Solved on the 1st try, at minute 12 of the contest. |
| `2/45` in the balloon color | Solved on the 2nd try, at minute 45 — the first try was wrong. |
| With **★** and a ring around it | You were the first to solve that problem (the lowest minute among the teams of that scoreboard). |
| `2/-` in an orange cell | You tried and did not solve it yet. A try never gets the balloon color. |

The color of each column is the balloon color of that problem. Most contests use the **official
ICPC palette** in letter order: A white, B black, C red, D dark red, E yellow, F green, G blue,
H navy blue. A quick look at your row tells you which balloons you have.
Some contests show the cell in a neutral green with a small colored dot instead of a colored
cell. It is the same information, and the organizers select the style. In both styles, the white A
and the black B get a thin outline. Without it, a white cell in a white table would not show. On a
mobile phone the cell shows ✓/✗, with the numbers in the `title`, for the same reason.

In **OBI** mode, each problem shows the **points** that you got.

During the **freeze**, you see the frozen scoreboard, the same as everyone else. A banner at the
top tells you **since when**. Everyone sees the standings as they were at that minute, and nobody
knows the real order until the ceremony. Your submissions continue to be judged
normally: the freeze stops the **display**, not the contest. An AC that you get after the freeze
is in your submission list, but it is not in the scoreboard column. Continue to solve problems.

In **anonymous** mode, the scoreboard shows an aggregated view, without names.

Some contests have **guest teams** (unofficial teams). If you are a guest team, a banner at the top
of the scoreboard tells you. You show on the scoreboard, but outside the official ranking: your row
has the **guest** mark and no place number. The scoreboard that you see includes the official
teams. The scoreboard of the official teams does not include the guest teams until the organizers
release the results.

If the contest is secret and you are not logged in, you must log in to see the scoreboard.

## 6. Clarifications (`/contest/clarification/?c=<id>`)

> **Only during the contest.** Before the start and after the end, MOJ does not accept questions
> from teams. The API answers in Portuguese: `A competição ainda não começou` (the contest has not
> started yet) or `A competição já terminou` (the contest has already ended).
> A site with extended time can continue to ask questions until its own end.

A clarification is a question to the judges about a problem. You must be logged in.

To ask a question:

1. Select the **Problem**. For a general question, select **General**.
2. Write the question. Be specific. *"In B, can the maze have more than one exit?"* has an
   answer. *"I did not understand B"* has no answer.
3. Click **Submit question**.

Line breaks in the question and in the answer are kept.

The judges do not see who asked. The chief judge and the administrator see your login and your name.
The public report of the contest does not show who asked.

The page has two sections:

- **Your questions**. Each question shows **Q:** (question) and **A:** (answer). A question
  without an answer stays at the top.
- **Public answers and notices**. This section has the **official notices** from the organizers
  and the public answers to questions from other teams. When a question is useful to the whole
  room, the judge publishes the answer for everyone. This is why the list has answers that you did
  not ask for.

The page updates automatically every 30 seconds. You can filter by problem.

The notice at the top of the main page tells you when one of your questions has an answer.

## 7. Printing (`/contest/print/?c=<id>`)

Printing shows only when there is printing staff and the organizers enabled the feature.

To request printing:

1. Select a **file** (PDF, image, text or source code, up to 10 MB).
2. Click **Request printing**.

The print has a cover sheet with your team name and a reference number. The staff at your site prints it and **hands it to you**.

Source code prints in a **monospaced font, with your indentation and numbered lines**. **Each
page repeats the login of your team** and the file name. If a sheet gets separated from the pile,
the staff can still find your desk.

In **My requests** you can see the status of each request: pending, processed or delivered.

## 8. Backup (`/contest/backup/?c=<id>`)

> **Store files only during the contest.** Before the start and after the end, MOJ does not store
> new files. You can still see, download and delete the files that you already stored.

The backup is a private area where you store versions of your solutions.

- It **does not count as a submission**, and only you can see its contents.
- You upload a file (up to 10 MB) and you can download or delete it at any time.
- **It is not automatic**: if you do not upload a file, it is not stored. Use it to keep the
  version that worked before you rewrote everything, and for the case where your machine stops
  working at minute 150. To download a **submitted** solution, use the `src` link in the
  submission list. These are two different things.

The backup is available unless the organizers disable it.

## More information

For how to submit in each language and how program input and output work, see the **Help** page (`/treino/ajuda/`). You can open it from inside the contest with the "📖 How to submit" link, next to the language selector.
