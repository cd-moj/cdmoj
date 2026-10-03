<!-- i18n-source: MANUAL-STAFF.md blob:462066f6d4fb062a338f0d30ce083a54f9c6d4d3 -->
# MOJ: Room staff manual (.staff and .cstaff)

> **Translation note.** This manual is a translation of the Portuguese original. The command-line tools (`moj`, `moj-contest`, `moj-comp`) print their messages in Portuguese, and the command examples below are identical to the original.

This manual is for you if you are part of the room staff of a contest on MOJ (the online judge). It covers two roles: **.staff** (room staff) and **.cstaff** (site chief). The focus is the web interface.

For the competitor view, see `MANUAL-CONTEST.md`.

## How the role works

On MOJ, your role comes from the **login suffix**:

- An account that ends in `.staff` is room staff.
- An account that ends in `.cstaff` is the site chief of one site.

You log in to the contest like any other person (user and password). The system then shows the screens of your role. You do not have to do anything special: use the credentials that the organization gave you.

There is one important difference between the two roles. The `.staff` **does** the queue tasks (claims, prints, delivers). The `.cstaff` **follows** the queue in read-only mode and has access to the labels with passwords. The main idea of the `.cstaff` is: **it sees, but it does not do the queue actions.**

---

## Part 1: `.staff` (room staff)

You are the person in the room who takes care of the printouts and the balloons. You are not a competitor: you do not submit code and you do not see clarifications.

### Tabs that you see

| Tab | What it is for |
|---|---|
| **Score** | The scoreboard (the frozen version, as a regular user sees it). |
| **Print queue** | The print and balloon queue of your site. This is your main screen. |
| **Animeitor** | The big-screen desk in **read-only** mode: the photos and songs of the teams of your site. You look and listen. You do not upload, replace or download the package. |
| **Documents** | The documents that the organization published (info sheet, problem set, time limits sheet). You download and print them. |
| **Rounds** | The scoreboard and the submissions of the finished rounds (for example, the warm-up). |
| **Logout** | Ends your session. |

### The print queue (`/contest/staff/`)

> **Log in from the computer that has the room printer installed and working.** Your computer
> prints, through your browser. The server only builds the PDF. In a contest where the teams use a
> locked image, that image is on the team computers. Your computer is a regular desktop (Windows,
> macOS or any Linux) with the printer configured. The `.cstaff` only follows the queue, so it can
> log in from any computer.

The print screen is a table with **two kinds of items in the same queue**:

1. **Print requests** from the teams: a file that the team sent, with a cover sheet already added.
2. **Balloons**: **automatic** tasks. The system creates one at the first Accepted of each pair (team, problem). The balloon shows the **color** of that problem, so that you take the correct balloon to the team's desk.

> **During the scoreboard freeze, no new balloon enters the queue. This is not a defect.** A balloon
> that crosses the room tells the audience exactly what the freeze hides: who solved a problem just now.
> So a correct answer during the freeze **does not become a task** and **is not delivered later**.
> The task does not exist. If the organization prefers the classic mode (balloons during the
> freeze), the `.admin` turns it on in **Home › Rules**. Then the balloons show as usual.
>
> **Print requests do not change**: the team can print at any time, with or without the freeze.

You see only the queue of **your site**. Requests and balloons of other sites do not show for you.

### How to handle a task

Each button is one step of the process. The usual flow is: **Claim**, then **🖨️ Print** (or
**Open PDF**), and last **✅ Delivered**. The screen language is the contest language.
In a contest in Portuguese, these buttons show as *Pegar*, *🖨️ Imprimir*, *Abrir PDF* and *✅ Entregue*.
In a contest in Spanish, they show as *Reservar*, *🖨️ Imprimir*, *Abrir PDF* and *✅ Entregado*.
The screens in the [illustrated tutorial](/contest/ajuda/staff.html) show the English buttons.

| Button | What it does |
|---|---|
| **Claim** | Reserves the task for you. If another person claimed it first, a warning shows. |
| **🖨️ Print** | Opens the combined PDF, starts the printing and marks the task as processed. |
| **Open PDF** | Only opens the PDF. It does not print. |
| **✅ Delivered** | Marks that you gave the material to the team in person. |

#### What comes out of the printer

First the **cover sheet** (team, university, login, task number, number of pages and a
line for a signature), then the document. Source code comes out in a **monospaced font, with the
original indentation and numbered lines**. So you can point to a line and say "line 42".

**Each page of code identifies itself**, at the top and at the bottom. At the top: the date and the
file name. In the footer: the **team login**, the file and the task number. On a desk with thirty
printouts in a stack, a sheet that comes loose from its cover still tells whose it is.

#### Automatic mode

There is a **checkbox** for automatic mode, and the system keeps your choice. When automatic mode is on and the tab is open, the system **claims, prints and marks** each new task. You do not click.

To stop the browser print window from opening for each task, run the browser in **kiosk mode**. In Chrome/Chromium, use the option `--kiosk-printing`.

### Warm-up: your rehearsal (and the contest can have two rounds)

Many contests run a **warm-up** before the official contest: the same room, the same accounts, the
same address. For you it is not a simulation. The requests and the balloon tasks in the queue
are real. It is the only chance to find out if the desk works before a failure costs a lot.

Do four tests, in this order:

1. **The printer**: paper, toner and the operating system queue. Print one task from start
   to end. Compare the balloon color on the paper with the balloon in your hand.
2. **The pop-up**: **🖨️ Print** opens another tab. If the browser blocks it, the system does
   **not** mark the task as printed. Allow pop-ups for this site during the warm-up, not at minute 3 of the contest.
3. **Automatic mode**, if you will use it: run the browser in kiosk mode (`--kiosk-printing`),
   so that no print dialog stops the work.
4. **The route**: take one paper to a desk and one balloon to a team. If you find the room
   number during the contest, you are already late.

When the organization promotes the official contest:

- the **request numbers start again at 1** and the **warm-up balloons do not count** (the queue starts
  empty). If you wrote down numbers, they refer to the warm-up. If warm-up papers are still at the
  desk, deliver them **before** the promotion;
- your **site scope stays** (it is configuration, not round data). What you saw in the
  warm-up is what you will see in the contest;
- the **Rounds** tab still shows what happened in the warm-up.

### What the `.staff` does NOT do

- It does not submit solutions.
- It does not see clarifications.
- It does not see the full scoreboard (it sees the frozen scoreboard, as a regular user).
- It does not see the passwords or the credential labels: the labels screen answers **access denied** to `.staff`.

---

## Part 2: `.cstaff` (site chief)

You supervise one site. You follow the queue of your site, you print the labels with the credentials (password included) and, at the end, you run the scoreboard reveal of your site. The main idea: **you see, but you do not do the queue actions.**

### Tabs that you see

| Tab | What it is for |
|---|---|
| **Score** | The scoreboard (the frozen version, as a regular user sees it). |
| **Print queue** | The queue of your site, in **read-only** mode. |
| **Badges** | The credential sheets of your site, with passwords. |
| **Animeitor** | The big-screen desk, cut to your site. Here you **write**: you upload, replace and remove the photo and the song of your teams, and you download the .zip package of the site. You cannot change the contest default and you cannot see webcast keys. |
| **Documents** | The published contest documents, to download and print at the site. |
| **Rounds** | The scoreboard and the submissions of the finished rounds. |
| **Logout** | Ends your session. |
| **Reveal** | The reveal ceremony of your site. It shows only **after the contest ends for all sites** and, when the event uses the Animeitor big screen, **after the big-screen operator releases the reveal**. |

### Print queue, read-only (`/contest/staff/`)

It is the same screen as for the `.staff`, but **without the action buttons**. The actions column is empty and the bar shows "read-only". You follow the queue of your site, but the `.staff` claims, prints and delivers.

### Badges (`/contest/badges/`), with passwords

This is what the `.staff` does not have: the credential sheets, ready to print (Pimaco A4 template), with the **name, login, password, site and institution** of each account.

- You see only **your site**: its teams and, of the role accounts, only the **`.staff`** accounts. Your own credential (the chief credential) does **not** go on a label, because it is the credential that opens this screen.
- Use it to print the desk labels and the team credentials of your site.
- The administration options (choose the file of another site, include disabled accounts) **do not show** for you.
- **A contest that uses the Free Training accounts has no password on the label.** The credential
  belongs to each participant (the same one they use in training). So the label shows "use your `treino`
  password" in its place. The list shows **only the people who registered** for that contest.
- A **disabled account** shows "account disabled" in place of the password. Disabling an account replaces the password
  with a random one, so there is no credential to print (the admin enables the account again with a reset).
- The system records each access to this screen.

### Contest documents (`/contest/docs/`)

Here you find the documents that the organization **published**, ready for you to download and print at the site:

| Document | What it is |
|---|---|
| **Judging environment** | The *info sheet*: system and compiler versions, accepted languages, limits, compile and run command lines, verdicts and penalty. Usually you put it on the room wall or give it with the problem set. |
| **Problem set** | Cover + all the statements. This is the printout for the desk of each team. |
| **Time limits sheet** | The table `letra · nome · tempo limite` (with errata, if there is one). |

Each one comes as **PDF** (to print) and **HTML**, in **Portuguese, English and Spanish**. Choose the line for the language of your site. The **open** button shows the file immediately, so that you can check it before you send it to the printer.

- You see only what the organization already **published**. Before that, the problem set is contest content and does not show. This is also true for you.
- If the list is empty, the organization did not publish anything yet. Come back closer to the contest.
- **Check the version on the cover** before you print many copies. If the organization corrects a statement, it generates the problem set again with a new version. If you print one day before the contest, it is possible that you must print again.

### Frozen score

Your scoreboard is the **frozen** one, as for a regular user. An administrator can give the full view to a specific account (the list `SCORE_FULL_USERS`). But this is an exception that the admin controls.

### Reveal by site (`/contest/score/reveal.html`)

You run the reveal ceremony of your site, in ICPC style (from the bottom to the top).

1. The screen filters to the teams that you can see (your site).
2. It unlocks only **after the contest ends for all sites** (the base time plus the extensions). When the
   event uses the **Animeitor big screen**, it also waits for the big-screen operator to **release the reveal**
   (the same button that releases the **Reveleitor**). Before that, the screen tells you that the reveal is not released yet.
3. You reveal position by position, from the last to the first.
4. Each cell with an attempt after the freeze shows **?** (accepted or not), until you reveal it. After the
   reveal, a wrong answer is **red** and an accepted answer gets the balloon color.

To unfreeze everything and publish the global scoreboard are **administrator** actions, not yours. The administrator uses the **🏁 Finish event** button, in the panel's Home (see `MANUAL-ADMIN.md` §6½).

### Big-screen Reveleitor (Animeitor)

When the ceremony is on the **Animeitor big screen**, the reveal of your site is a **link** that the big-screen operator
releases. After the release, the **Reveleitor** button shows in your bar, with the card **🎬 Reveal for your
site** (open / copy). The card shows the **check badge**: MOJ asks the Animeitor if it has all the
submissions of your site:

- **✓ Validated**: the contest ended for all sites, nothing is in judging and the Animeitor has everything. You can start.
- **✓ Checked**: the last check matched. The final validation comes when the contest ends for all sites.
- **⚠**: something was missing at the last check. MOJ already sent it again. Wait for "Validated" or speak to the operator.

The link shows the answers after the freeze. Open it only on the big-screen computer of the site. Do not give it to other people.
An account with no site set does not get a link.

### Warm-up: the site rehearsal

In the warm-up, the credentials that you gave out go through the only test that counts. At the end of
the warm-up, you want to know one thing: **each team of your site logged in at least
one time**. A label that does not log in is a problem to solve before the clock starts. You
have the password.

It is also the time for the rest of the list: make sure that the queue shows your teams and only your teams, watch the
room staff of your site rehearse with a real queue, and collect the missing **photos**
while nobody is under pressure.

> Two things are **not** lost at the promotion to the official contest: your **site scope** (it is
> configuration) and the **photos and songs** that you collected (they belong to the team account, not to the
> round). The system archives the round: scoreboard, submissions, print queue, clarifications.

### What the `.cstaff` does NOT do

- It does not submit solutions.
- It does not do the print actions: claim, print and deliver give **access denied**.
- It does not see the labels of other sites.
- It does not unfreeze or publish the global scoreboard.

---

## Summary table: what each role can and cannot do

| Action | `.staff` | `.cstaff` |
|---|:---:|:---:|
| See the frozen scoreboard (Score) | Yes | Yes |
| See the print queue of your site | Yes | Yes (read-only) |
| Claim, print and deliver queue tasks | Yes | No (access denied) |
| Use the automatic print mode | Yes | No |
| See labels with passwords (Badges) | No (access denied) | Yes (only your site) |
| Download the published documents (Documents) | Yes | Yes |
| Generate/publish documents | No (admin/chief judge only) | No (admin/chief judge only) |
| Run the reveal of your site (🏆) | No | Yes (after the contest ends for all sites and, with the Animeitor big screen, after the release) |
| See the big-screen desk (Animeitor) of your site | Yes (look/listen only) | Yes |
| Upload/replace the photo and song of the site teams | No (access denied) | Yes (only your site) |
| Download the big-screen .zip package | No | Yes (cut to the site) |
| Change the DEFAULT photo/song of the contest | No | No (`.animeitor`/admin only) |
| See or create webcast keys | No | No (`.animeitor`/admin only) |
| Submit solutions (compete) | No | No |
| See clarifications | No | No |
| See the full scoreboard | No | No (unless the admin allows it) |
| See the labels of other sites | No | No |
| Unfreeze everything / publish the global scoreboard | No | No (admin only) |

---

## Pointers

- **Web tutorial for your role** (with screenshots of the screens, PT/EN/ES): `/contest/ajuda/staff.html`
  and `/contest/ajuda/cstaff.html`. Open it with the **📖 How this role works** button on your screen.
- **[MANUAL-ANIMEITOR.md](MANUAL-ANIMEITOR.md)**: for the big-screen operator (the owner of the default photo/song
  and of the webcast keys that you do NOT have).

- For the competitor view (login, solution submission, scoreboard, clarifications, printing and backup), see `MANUAL-CONTEST.md`.
