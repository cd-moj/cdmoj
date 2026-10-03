<!-- i18n-source: MANUAL-JUIZ.md blob:b8d6e4b9f0f66d79dfe606653a03c20461fdb725 -->
# MOJ: Manual for judges (.judge and .cjudge)

> **Translation note.** This manual is a translation of the Portuguese original. The command-line tools (`moj`, `moj-contest`, `moj-comp`) print their messages in Portuguese, and the command examples below are identical to the original.

This manual is for the persons who judge the submissions of an MOJ contest in the web interface. There are two roles. The suffix of your login gives your role:

| Login ends in | Role | What you get |
|---|---|---|
| `.judge` | Judge | You see and work on the evaluation queue. |
| `.cjudge` | Chief judge | You get all that a judge gets, plus a chief judge panel. |

The chief judge **inherits** all that the judge does. Thus, read Part 1 even if you are `.cjudge`: it applies to you too. Part 2 adds the extra powers.

## When this manual applies

All of this occurs only when the contest is in **manual verdict** mode (the organization turns on the `MANUAL_VERDICT` option). In this mode, the submissions that the **🔎 What goes to review** table marks stop in a queue. They wait for a judge to examine them before the result goes to the competitor. The submissions that the table does not mark go out automatically, directly from the machine. A judge error always goes to the queue.

If this option is off, judging is **automatic**: the machine calculates the verdict and sends it directly to the competitor. In this case, there is no queue and the judge has nothing to do. If you open the evaluation tab and it is empty or not there, the contest is probably not in manual verdict mode.

## Part 1: `.judge` (judge)

### Tabs that you see

As a judge, your navigation bar has these tabs:

| Tab | Purpose |
|---|---|
| **Contest** | The contest statement and the problems. |
| **Score** | The scoreboard. |
| **Clarification** | Questions and answers (clarifications). |
| **Judge** | Your evaluation queue. You do your work here. |
| **All Submissions** | The full feed of the contest, **anonymous**: you see the time, problem, raw verdict, code and log. You do **not** see the user or the team (the API does not show them either; the identity of the submitter is not relevant to the evaluation). |
| **Statistics** | The numbers of the contest. |
| **Logout** | Ends the session. |

An important difference from a competitor: you, the judge, also see the **raw text** of the verdict that the machine calculated. The competitor does not see it.

### The evaluation queue

The queue is in the **Judge** tab (URL `/contest/judge/`). At the top of the page, four counters give a summary of the general status:

| Counter | Meaning |
|---|---|
| Not evaluated | Held submissions. Nobody works on them yet. |
| Being evaluated | A person took the submission and judges it now. |
| Awaiting 2nd vote | The submission has one vote. The second judge must agree. |
| In conflict | The two votes are different. Only the chief judge can resolve it. |

Below the counters, you see the list of the submissions that are held for review. For each one, you see:

- The **Problem** of the submission.
- The **Computed verdict**: the verdict that the machine calculated (it is a reference, not the final decision).
- The **Status** of the submission in the queue.
- **Who evaluates it** (if a person has it).
- **Log and source links** (the execution log and the submitted code).
- The available **Action** (for example, claim it for evaluation).

### Evaluation flow, step by step

1. **Claim to evaluate.** Click to reserve the submission. A maximum of 2 persons can work on the same submission. Your reservation has a time limit of 5 minutes. When you claim it, the screen changes to a stable panel. This panel does not reload automatically while you work (thus you do not lose your work).
2. **Analyze.** The panel gives you all the data: the **computed verdict** (the reference), the execution **log**, the submitted **code** and a verdict selector. Two buttons help you: **+5 min** (asks for more time, if 5 minutes are not sufficient) and **Give up** (releases the submission, so that another person can claim it).
3. **Vote and release.** Select the verdict in the selector. Click **✓ Vote and release**. ⚠ The **vote is permanent** (you cannot undo it). The vote **releases you immediately**, so that you can claim the next task.

### Two judges must agree

The competitor gets the verdict of a submission only when **N judges vote the same verdict**. The contest admin sets N (Home › Rules → "Judges required to validate each verdict", from 1 to 5; the default is 2). When the votes agree, the verdict goes to the competitor. (A single writer, the daemon, sends it. This prevents conflicting updates.) With N=1, your vote alone decides.

When the two votes are **different**, the submission becomes a **conflict**. The system marks it for the **chief judge** to resolve. A regular judge does not resolve conflicts: your part ends with your vote.

### Warm-up: your rehearsal

Many contests have a **warm-up** before the official contest: the same room, the same accounts, the same
address. The queue in the warm-up is a real queue: submissions come in, you claim them, you vote, and
the rule of N judges in agreement applies the same way. Use it to examine the items that are difficult to
find later. Make sure that the **verdict options** are the ones that this contest wants. Make sure that
the **log** and the **code** open on your computer. Make sure that you and the other judge read the same
submission in the same way.

> **Do not leave the warm-up queue unfinished.** The system **refuses** the promotion to the official
> contest while a submission has no released verdict. Before the organization can change the round, the
> server checks that: the round ended, no job is in progress on the judge, all items in manual review
> have a verdict, no verdict is pending in the history, and the daemon is alive.
> An abandoned warm-up queue blocks the start of the contest. Finish the items that you claimed.

When the organization promotes the round, the system archives all of the warm-up: queue, submissions,
clarifications and scoreboard. The official contest starts with an empty history. Nothing that you judged
in the warm-up counts in the contest, and nothing leaks into it.

### Alert on any page (bar at the top and sound)

You do not have to stay on the correct tab to know that there is work to do. On **any page of the contest**, a bar at the top of the screen tells you, with a sound:

- **💬 unanswered clarification**: a question that nobody reserved (or with an expired reservation). Click it to go to the **Clarification** tab.
- **⚖ verdict awaiting your vote**: a submission in review that you can still vote on. Click it to go to the **Judge** tab.

The number of pending items also shows in the **title of the browser tab**, for example "(2) …". The sound plays when a new item arrives and plays again every 2 minutes while items are pending.

- **Enable the sound.** The browser plays sound only after you click on the page. If the bar shows **🔇 enable sound**, click it (or click anywhere on the page).
- **Mute** with the **🔊 sound on** button on the bar. This applies to this contest, in this browser.
- **Outside the browser:** the **🔔 notify outside the browser** button asks for the system permission. With it, a new item shows as a notification of the computer, also when the browser is minimized.

When you have many tabs of the contest open, only one tab asks the server and tells the others. More open tabs do not put more load on the contest.

### Summary of the judge permissions

| Can | Cannot |
|---|---|
| See the evaluation queue and the counters. | Resolve conflicts. |
| Claim and reserve submissions (max. 2 per submission, 5 min). | Release a verdict without the two votes. |
| See the reference, log and code, and vote. | Edit the verdict list or what goes to review. |
| Ask for +5 min or give up. | See the chief judge panel. |
| See the raw text of the verdict. | Open administration, teams, users. |
| See the **jplag** result (pairs with the login only; no team name). | Run jplag. |
| Get the unanswered clarifications and the pending votes on the alert bar, with sound, on any page. | |

## Part 2: `.cjudge` (chief judge)

The chief judge does **all that the judge does**: claims submissions, votes, takes part in the two-vote rule, all the same as in Part 1. In addition, the chief judge gets a chief judge panel and some extra powers.

### Additional tabs

In addition to the judge tabs, the chief judge sees:

| Tab | Purpose |
|---|---|
| **Chief judge** | The chief judge panel (details below). |
| **All Submissions** | The full list **with user and team** (the regular judge sees it anonymous), with the raw verdict. |

### The chief judge panel

The panel is at `/contest/chief/`. It has these tabs:

1. **📊 Status.** Shows summary cards, the **full queue** (with filters and with the votes of the other judges) and a **"📈 Performance by judge"** table. The table shows: votes, average time from claim to vote, agreements and conflicts. Each row of the queue has a **Decide/Resolve** button. This button releases the verdict **immediately**, without the two votes (the system records this decision).
2. **⚖️ Conflicts.** Lists the submissions in conflict. It shows the **two votes** that are different, the log and the source. Each submission has a button to resolve it.
3. **🏷️ Options.** Edits the list of verdicts that the judges select when they vote. Each option has three fields. The first field is the text that the judge sees. The second field is the class: one of the six canonical classes (Accepted, Wrong Answer, Time Limit Exceeded, Memory Limit Exceeded, Runtime Error, Compilation Error). The class sets the score, the penalty and the color on the scoreboard. The third field is the text that the team sees. Leave the third field empty to show the class. The Accepted class has no text of its own.
4. **🔎 What to review.** A table: each row is a problem (letter and title), each column is a verdict (AC, WA, TLE, MLE, RTE, CE). **Mark the items that the judges review**. The items that are not marked go out automatically, directly from the machine. If nothing is marked, all goes out automatically (only a judge error goes to the queue). The "All problems" row marks or clears a full column. The box near each problem marks or clears the row. **Review everything** and **Nothing in review** change the full table. A common configuration: leave CE automatic (it does not need judgment and it fills the queue at the start) and review TLE. The **Per-language exceptions** (collapsed) apply to one language and override the table. For example, "Python · TLE · goes to review" when TLE is automatic in the table. If you change the table during the contest, some held submissions can now be automatic (without votes and without conflict). In this case, the screen shows **Release now**. It does not release them automatically.
5. **🌐 Languages.** Sets the statement languages that the accordion shows to the competitor. **Automatic** (default): each problem shows all the languages that it has. **Only these languages**: mark the list (Portuguese, English, Spanish). PT only = a contest only in Portuguese. The table shows, for each problem, which translations exist. If a problem has no translation in a language that the contest shows, that problem shows the Portuguese text. The admin has the same panel in Contest › Problems.

### Conflict alert

The alert bar from Part 1 also tells the chief judge about each new **conflict**: a **red ⚠** item, with a different alarm sound. Click the item to go directly to the **⚖️ Conflicts** tab. Thus, you see the conflict even when you are on a different screen.

### Other chief powers

- See **All Submissions** with user and team (the regular judge sees it anonymous), with the raw verdict.
- Answer **clarifications**. Reserve the question before you answer it. You see who asked: the login and the name (the regular judge does not see them). Nobody can reserve a question that another judge reserved. Line breaks in the question and in the answer stay as they are.
- Edit the **answers and news** of the contest.

### Warm-up: what only the chief checks

The warm-up is the only time when all the judging team works with real submissions and nothing is at
stake. Use it to check the items that only you can change: **how many judges** a verdict needs, which
verdicts go to **review** (the others go out automatically), and whether the **conflict alarm** really
gets to you. If nobody sees a conflict in the warm-up, nobody will see it in the contest.

The warm-up is also where you see the queue become empty. The system **refuses** the promotion to the
official contest while an item has no released verdict, a job is in progress or a verdict is pending. The
**📊 Status** tab of the panel is the screen that shows when the judging team is clean enough for
the organization to change the round.

> ⚠ **At promotion, the documents lose their published mark.** The templates and the cover stay
> (they are configuration). The PDFs that the system generated for the warm-up go to the round archive.
> But the documents that were published are not published anymore. The info sheet, the problem set and
> the time limits sheet must be **published again** for the official contest. If not, the teams
> open *Files & Resources* and find nothing.

### What the chief judge is NOT

The chief judge is **not** a full administrator. The chief judge does not have:

- the **Administration** tab,
- contest **settings**,
- management of **teams** or **users**.

The chief judge powers are limited to: judging, verdicts, news/answers, statistics and **jplag** (run it and see the pairs with the team name).

### Summary of the chief judge permissions

| Can (in addition to all that the judge can) | Cannot |
|---|---|
| See the 📊 Status panel and the performance by judge. | Be a full admin. |
| **Decide/Resolve** to release a verdict immediately (recorded). | Open the Administration tab. |
| Resolve **conflicts**. | |
| **Run jplag** and see the pairs with the team name (`jplag` link in the bar). | |
| Edit the verdict list (🏷️ Options). | Change the contest settings. |
| Edit **what goes to review** (problem x verdict table + per-language exceptions). | Manage teams or users. |
| See **All Submissions** with user/team and the raw verdict. | |
| Answer clarifications. Reserve first. You see who asked (login and name). | Reserve a question that another judge reserved. |
| Edit answers and news. | |
| Get the **conflicts** on the alert bar too, on any page. | |

## More information

- For the view of the competitor, see `MANUAL-CONTEST.md`.
- For the room staff, see `MANUAL-STAFF.md`.

## Web tutorial with screenshots

The screens of this manual, step by step and with images (text in PT/EN/ES; the screens in the images are in English), are at
`/contest/ajuda/judge.html` and `/contest/ajuda/cjudge.html`. The
**📖 How this role works** button on your screen opens them directly.
