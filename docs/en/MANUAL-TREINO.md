<!-- i18n-source: MANUAL-TREINO.md blob:ce87837d89148ef015a8e2ff722fe27b2240fa35 -->
# MOJ: Free Training Manual (student)

> **Translation note.** This manual is a translation of the Portuguese original. The command-line tools (`moj`, `moj-contest`, `moj-comp`) print their messages in Portuguese, and the command examples below are identical to the original.

> **Prefer the terminal?** The `moj-comp` CLI also works in the training. You can search for a
> problem, download the statement, submit, and get the verdict without leaving the shell. Guide:
> [/treino/cli.html](/treino/cli.html).

Welcome to the MOJ **Free Training**. MOJ is an online judge. This manual shows, step by step,
how to create your account, log in, find problems, submit your solution, and follow the
result. It is for beginners, so it goes slowly and one step at a time.

Free Training is the place where you practice at your own pace. You choose the problem, write the
code, submit it, and see the verdict. There is no deadline and no contest scoreboard. To compete
for real, see `MANUAL-CONTEST.md` at the end of this document.

---

## Contents

1. [The home page](#1-the-home-page)
2. [Create an account through Telegram](#2-create-an-account-through-telegram)
3. [Log in](#3-log-in)
4. [Forgot your password](#4-forgot-your-password)
5. [Find problems](#5-find-problems)
6. [Solve a problem](#6-solve-a-problem)
7. [Profile](#7-profile)
8. [My statistics](#8-my-statistics)
9. [Editors page](#9-editors-page)
10. [More information](#10-more-information)

---

## 1. The home page

Open the MOJ address `/`. You **do not need to log in** to see the home page.

At the top is the **menu bar**, with these items:

| Item | What it is for |
|---|---|
| **Home** | Goes back to this page |
| **Free Training** | The free practice area (the subject of this manual) |
| **Contests** | Contests and trainings with a deadline |
| **News** | Announcements and news about the platform |
| **Status** | Status of the judges and of the system |
| **Docs** | Manuals and documentation |

Next to the menu is the **language selector PT · EN · ES**. The full site is available in the three
languages. On the **right** is the login area. Before you log in, it shows the user and password
fields. After you log in, it shows your **avatar**. The avatar opens a menu with shortcuts (My
statistics, Profile, Log out…).

Lower on the page, you find:

- The **highlight** at the top, with the **featured news item** and the shortcut buttons
  **Free Training →**, **Problem Management →** and **📖 Help**.
- The **🗂️ Problem Management** card (it shows only for users who can create problems). It is for
  users who **create** problems (teachers, teaching assistants, authors). If you only want to
  train, you can ignore it.
- The **🏋️ Free Training** card, with the **Search problems →** button.
- The **🏆 Top 10** of the users who solve the most. **Click a name** to open the **public
  profile** of that person (section 8).
- The **🔥 Most solved · last week** and the **⌨ Editors · last week**.
- The **✅ Recently solved** list. It also links to the profiles of the users who solved.
- The **list of contests**, split into **Open now**, **Upcoming** and **Ended**, with a
  **filter by name**.
- The **📰 News**.

To start to practice, click **Free Training**. It takes you to the address `/treino/`
(section 5).

---

## 2. Create an account through Telegram

The Free Training sign-up is at `/treino/cadastro/`, and **Telegram confirms it**. This prevents
duplicate accounts. Thus, to sign up, you need a **Telegram account**.

Do these steps:

1. **Fill in the form:**
   - **Full name** (required).
   - **Desired login** (optional). It can have 2 to 32 characters: letters, numbers, and the
     symbols `.`, `_` and `-`. If you leave it empty, the system uses your Telegram `@` as the
     login.
   - **University** (optional).
2. Click **Continue on Telegram →**.
3. Open the **mojinho** bot on Telegram and tap **Start**. The sign-up page **waits** and confirms
   automatically when you talk to the bot.

An important point about the password:

> Your **password comes only in a private message on Telegram**. It **never shows on the web**.
> Keep this message in a safe place.

When the sign-up is complete, go to the login screen (next section).

> **Under 18 (no Telegram)?** A **responsible** teacher/admin creates the account and gives you
> the login and the password. These accounts always have a private profile until the age of 18.
> Details are in [`CONTAS-GERIDAS.md`](CONTAS-GERIDAS.md).

---

## 3. Log in

The login is at the **top of every Free Training page**. You see:

- a **User** field;
- a **Password** field;
- the **Log in** button.

Type the user and the password (the password is the one that the bot sent on Telegram). Then
click **Log in**.

When you are logged in, the right corner of the bar shows your **avatar**. Click it to open a
menu with shortcuts:

- **My statistics**
- **Profile**
- **Log out**
- and **more options**, if your account has extra permissions.

---

## 4. Forgot your password

There is no "forgot password" form on the web. You recover the password through Telegram.

If you **linked Telegram** to your account (this occurs at sign-up), do these steps:

1. Open the chat with the **mojinho** bot on Telegram.
2. Send the command `/trocarsenha`.
3. You get a **new password in a private message** on Telegram.

Then go back to the login screen and log in with the new password.

If your account **has no Telegram** (an account that a responsible person created; see the note in
section 2), the **responsible person who created the account** resets the password.

---

## 5. Find problems

The problem search is at `/treino/`. **You do not need to log in to see the list and read the
statements.** You must log in to see your **personal progress** and to **submit a solution**.

The page has **two modes**: the **hub** (the entry page) and the **advanced search** (the full
list with filters). Any search or filter takes you from the hub to the advanced search
automatically.

### The hub

- **Central search:** type 2 or more letters. **Grouped suggestions** show in Collections,
  Tags and Problems (each problem shows its status ✓/…). Use the arrow keys ↑↓ and Enter, or
  click. If you press Enter without a selection, the advanced search opens with the typed text.
- **Shortcuts:** 🎲 **random problem** (it prefers a problem that you did not solve yet),
  🌱 **easy starters**, 🚀 **not solved yet** and 🔬 **advanced search**.
- **For you** (shows when you are logged in): **▶ Pick up where you left off** (your last attempt
  that has no AC yet) and **🎯 Suggested for you** (a next problem).
- **📚 Featured collections:** a carousel of cards. Each card shows the size of the collection
  and the **bar of your progress**. Click a card to filter the list by that collection. Scroll
  with the arrows ‹ › (or with your finger, on a phone). The link **all (N) →** opens the
  advanced search.
- **🔥 Most submitted this week:** the 10 problems with the most submissions in the last 7 days.

### The advanced search

The full list is always visible, with the **filter rail** on the left:

- **Filter by title:** type part of the name.
- **My status** (only when logged in): All / To solve / ✓ Solved / … Attempted.
- **Difficulty:** from very easy to hard. It uses the **per-user rate** of each problem (do the
  users who try succeed? solved ÷ attempted). The ranges are: ≥90% very easy, ≥70% easy, ≥50%
  medium, <50% hard. "new" means no data yet. This is the same scale as the problem statistics
  page, the profile, and the contest problem draw. Each option shows how many problems remain
  with it.
- **Collections:** the tree with **checkboxes**. You can select **several at the same time** (the
  list shows the **union**). Select a **group** (for example, `obi`) to get all its collections at
  once. The number on the right is **your progress** (for example, `20/140`).
- **Tags:** select as many as you want. The problem must have **all** the selected tags. The
  counts **update live** as you filter.

Above the table are the **chips** of the active filters (the × removes them one at a time), the
result count, and the **sort order**: **Most solved**, **A–Z**, **Difficulty** and
**Newest** (the most recently published first).

| Column | What it shows |
|---|---|
| **✓** | If you solved (✓) or attempted (…). It shows when you are logged in |
| **Problem** | The title. It is the **link** that opens the problem |
| **Collections** | Click a collection to **add it** to the filter |
| **Difficulty** | The range from the per-user rate (solved ÷ attempted) |
| **Dirt** | How much users fail before they succeed: the part of the submissions of the solvers that was wrong. High = the problem punishes errors. Green ≤20%, yellow ≤50%, red above. |
| **Solved** | How many users solved / attempted |

The list comes in **pages of 50**. Tip: the **URL keeps your filters**. Copy the link to share a
search. On a phone, the rail becomes the **Filters (n)** button.

To open a problem, **click its title**.

---

## 6. Solve a problem

When you click the title, you go to the address `/treino/problema/?id=<id>`. `<id>` is the code
of the problem. The screen has two parts:

- **On the left:** the problem **statement**.
- **On the right:** the **Submit solution** panel.

At the **top of the statement** you find:

- the **author(s)** of the problem;
- the **collections** that the problem is in;
- the **tags** (they start **blurred**, with a **show/hide tags** link);
- the **time limit per language**;
- a **statistics button** for the problem;
- the **⬇ Samples** button. It downloads the input and the output of each sample as files, in a
  zip.

Each sample block in the statement has a **Copy** button in its title. One click copies the full
block, with the final line break.

When the problem has the statement in more than one language, the chips **PT · EN · ES** show
above the text. Click a chip to change the language. The title changes too. MOJ remembers your
selection for the next problems. In the problem list, the **EN ES** badge next to the title shows
which problems have a translation.

### How to submit your solution

You must be **logged in** to submit. In the **Submit solution** panel:

1. **Select the language** in the menu. Each option shows the **time limit** of that
   language.
2. Write your code in one of these two ways:
   - **Type it in the editor.** The editor (its name is CodeMirror) comes with a **template** of
     the selected language to help you start.
   - **Or upload a file** in the **or file:** field.
3. Click **Submit solution**. The message **Submitted!** shows.

The editor has some conveniences:

- **Full screen:** the editor fills the full window.
- **New window:** opens a mode with only the editor.
- **▾ Hide editor / ▸ Show editor:** makes the editor small when you do not need it.

### Follow the result

Below is the **Submission history**, with these columns:

| Column | What it shows |
|---|---|
| **Date/Time** | When you submitted |
| **Actions** | Quick buttons (see below) |
| **Language** | The language of that submission |
| **Status** | The verdict of the judgment |

The buttons in the **Actions** column are:

- **✎** (editor): loads that code into the editor again.
- **code**: downloads the source file that you submitted.
- **log**: opens the **judgment report**.

While the result is **pending**, a **loading** indicator shows, and the page **updates
automatically** when the verdict is ready. You do not need to reload the page manually.

Below the verdict is a **summary line**, for example:

```
Passed 3/5 tests
```

The details of each language and of how data input and output work are on the site's **Help**
page (`/treino/ajuda/`). This page also has the starter code for each language. The link
"📖 How to submit" shows next to the language selector when you submit.

---

## 7. Profile

Your profile is at `/treino/perfil/`. It has sections, and **each section has its own save
button**. Change what you want and save one section at a time.

| Section | What you change |
|---|---|
| **Details** | Name, university and the **favorite editor/IDE** (it shows in the editor ranking) |
| **Password** | Current password, new password and confirmation of the new password |
| **Privacy** | The **Public profile** option. If you **clear** it, your statistics are **only for you** |
| **Profile photo** | Upload an image. The image is cropped to **100x100** |
| **Username** | Change your handle |

⚠ Be careful when you change the **Username**:

> A change of handle **updates all your history** to the new name. There is a **limit of changes
> per year** (the default is **2**). The screen shows **how many you already used**.

This page is where you **edit** the profile. What other users see, your **public profile**, is at
`/treino/stat/?user=<your login>`. The next section is about it.

---

## 8. My statistics

Each user has a **public profile** at `/treino/stat/?user=<login>`. To open yours, use the avatar
menu → **📊 My statistics**. To open the profile of another user, click the name (for example, in
the Top 10 on the home page).

From top to bottom, the profile shows:

- **Header:** photo (or initials), university, **member since**, favorite editor (with its
  position in the editor ranking) and the **last submission**.
- **Cards:** problems solved, submissions, acceptance rate, **AC on first try**, attempts to
  solve, **streaks** (consecutive days with a submission) and the favorite language.
- **Charts:** solved problems over time, activity map (26 weeks), **rhythm day × hour**,
  verdicts, performance per language, **difficulty of solved**, **progress by collection**,
  strengths by tag, and the **Open** list (problems that you attempted and did not solve yet —
  a very good queue to return to training).
- **🏅 Achievements:** automatic medals — First AC, Centurion (100 solved), streaks, Polyglot,
  collection complete, and others. The **locked** medals show in gray, with **how much is
  missing** (for example, `82/100`). The full catalog and the rules are in
  [`PERFIL.md`](PERFIL.md).
- **Paginated history** (25 per page), with **filters** by problem, verdict and language, and
  sort by column. The **code**/**log** links show only for the owner.

Remember: if your profile is **private** (section 7), all of this **shows only for you**. Your
name is also **removed from the public lists** on the home page.

---

## 9. Editors page

The page `/treino/editores/` collects the statistics of the **favorite editors** that users
declare: a **ranking** and the **distribution** of who uses what.

Tip: do you want to show in this ranking? **Declare your editor** in the **Details** section of
the **Profile** (see section 7).

---

## 9½. Virtual participation: do an ended contest again

Some ended contests have the **🕹️ Virtual** button on their card (home page and contests
archive). It opens the **virtual participation**. You do the full contest again, with a clock,
against the official scoreboard. The official teams solve the problems at the same minute as in
the real contest.

1. **Read the rules and accept them.** Do not participate if you already saw the problems. Do
   the full contest.
2. Select **Start now** or **Schedule** (up to 7 days ahead; you can cancel the schedule).
3. In the arena: open a problem, select the file, and submit. The verdict shows in
   **My submissions**. The scoreboard highlights your row, with the position that you would
   have.
4. **Finish now** ends before the time is over.

**Scoreboard filters.** The bar is the same as on the contest scoreboard: **Board** (for example,
only the official teams, without guests), **Flag**, **University**, **Site** and the search. When
a filter is active, the large number is the position in the filtered subset. The small number is
the overall position. Your row always shows.
**My picks.** Click the **📌** on a virtual row to pin that person. That person then always shows
on the scoreboard, with any filter. The **📌 Picks** button opens the list. In the list, you can
search by name or login, select and clear entries, or add the login of a user who did not do the
virtual participation of this contest yet. The list belongs to your account and applies to all
contests. Example: pick your friends, select a **Site**, and see the position of each friend
among the teams of that site.

The **Virtuals** selector selects one of these: all the virtual participants, only the picks,
only you, or none. The **Site** filter does not hide the virtual participants. Thus you can
compare your result with the teams of that site.

**Give up without a record:** the **Give up** button is available in the first **15 minutes**,
or while you have **no accepted problem**. When you give up, you get the attempt back, **2 times**
at most. After that, the start is final. If the time ends with no accepted problem, it counts as
giving up.

**After:** your row stays on the virtual scoreboard of the contest, marked as **virtual**. Each
account does the virtual participation of a contest **one time**. The submissions stay in your
training history.

When you are not logged in, the same page shows the **Replay**. Drag the time control to see the
scoreboard at any minute of the contest.

## 10. More information

- For the details of **how to submit in each language** and of how data **input and output**
  work, see the **Help** page (`/treino/ajuda/`).
- To **compete in a contest** (with a deadline and a scoreboard), see `MANUAL-CONTEST.md`.

Good training, and good code.
