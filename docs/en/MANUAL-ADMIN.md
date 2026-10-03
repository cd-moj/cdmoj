<!-- i18n-source: MANUAL-ADMIN.md blob:045c0b4774bef400ce0448953dae02c270721ec0 -->
# MOJ: Organizer manual (the contest .admin panel)

> **Translation note.** This manual is a translation of the Portuguese original. The command-line tools (`moj`, `moj-contest`, `moj-comp`) print their messages in Portuguese, and the command examples below are identical to the original.

This manual is for the person who **operates** a contest: the owner of the `.admin` account. It
explains each tab of the administration panel and each configuration option. It also explains
**how to enable the special roles** (`.judge`, `.cjudge`, `.staff`, `.cstaff`, `.mon`) and how to
turn on **judge-validated grading**, including how many persons you need.

> Creating the contest (wizard, problems, accounts) is in the other guide: the
> [organizer tutorial](/treino/criar/tutorial.html). This manual is about OPERATION, on the contest day.

To get to the panel, log in with the `.admin` account of the contest. Then click
**Administration** in the top bar.

## 1. The panel: Home, the groups and the MODULES

The panel opens on **🏁 Home**. The top bar has the **four common groups**, which every contest
has. After a separator, it has the **event groups**. An event group appears only when the contest
turns on the related **module** (section 1½). Each group shows its panels on the second line. The
address keeps the panel (`#group/panel`), so you can save the link. The old links (`#settings`,
`#users`, `#machines`, `#prova/rodadas`…) continue to work: they are redirected. A link to a panel
of a module that is **off** goes to **Home › Modules**, with a notice that tells which module to
turn on.

```
[🏁 Home] [🧩 Contest] [👥 People] [🎛️ Operations] │ [🏟️ Event] [🖥️ Machines]        📖 Manual
                                                   └── only with the module on ──┘
```

| Group | Panels | Appears |
|---|---|---|
| **🏁 Home** | Home · **Modules** · Rules | always |
| **🧩 Contest** | Problems · Skeletons (`esqueletos`) · **Report** | always (Skeletons only with the module) |
| **👥 People** | Accounts · Registrations (`inscricoes`) · Sessions | always (Registrations only with the module) |
| **🎛️ Operations** | Status · Staff · Judges · Audit | always |
| **🏟️ Event** | Rounds (`rodadas`) · Documents (`documentos`) · Balloons (`baloes`) · Qualification (`classificacao`) · Teams (`sedes` or `telao`) · Cohorts (`coortes`) · Sites & schools (`sedes`) | with the module in parentheses |
| **🖥️ Machines** | Gate & lock · Anomalies · mlinux | with the `maquinas` module |

### 🏁 Home: what is missing and what to generate

| Block | What it does |
|---|---|
| **🚦 Before you start** | The pre-contest checklist (green/yellow/red), with a **button that opens the exact panel** of each open item. Red is **critical**: check it before the start. The checklist is only a warning. MOJ does not block login or submissions because of it. The items that are already correct stay collapsed. It checks the window, the judging log, the freeze, the judges, the languages, the calibrated TL, the pool, the accounts, the staff and the daemon. It also checks if **each judge has already calibrated each problem** (*Judges warmed up*). The time limit is measured per machine. A judge that did not calibrate a problem yet does it on the 1st submission of that problem, and that submission waits for minutes. When a judge is cold, the item shows the **🔥 Warm up judges** button, which tells only the cold judges to calibrate. Do this **before the start** (each calibration uses one slot of the judge for some minutes). Then run the checklist again (↻) to see "warming up" change to "warmed up". **Only with the module on**, it also checks cohorts, browser gate, site lock, next round, documents, balloons and extensions. The **modules** check warns when a module is off but the contest has data for it. |
| **🧰 Generate** | One card per artifact, with the current state. Always: credential badges, contest report and jplag (jplag also opens for the chief judge, who can run it, and for the judge, who can only see it). With the module: documents (`documentos`), promote round (`rodadas`), reveal ceremony and big screen (`telao`). |
| **📡 Live** | A short summary (pending, submissions, online judges, p95 response, manual review). It refreshes automatically. The full panel is **Operations › Status**. |
| **⏱️ Contest rules** | Start, end and freeze, which you can edit there. The mode and the languages, read-only. The **modules that are on** (with a shortcut to turn them on/off). All other options are in **Home › Rules**. |

| Panel | What it does |
|---|---|
| **Home › Modules** | Turns the contest modules on and off (section 1½). One card per module shows what it opens and if the contest already has data for it. Presets: course exam · course exam with Maratona Linux · selection contest · Maratona. |
| **Home › Rules** | **All** the contest options, in five collapsible sections (identity and window · what the team sees · judging · scoreboard/freeze/penalty · access). Section 2 explains each option. The ⏱ extension by site is in **Event › Sites & schools**. |

### 🧩 Contest: the content

| Panel | What it does |
|---|---|
| **Problems** | The contest itself: rename/reorder/remove problems. **Edit the identifier** (the "letter": it can be `W1`, `Q`…; reordering keeps a custom identifier, and the balloon color moves with it). Restrict the languages or the judge pool PER problem. Update the statement from the bank (or send HTML/PDF, **per language**). The **🌐 Statement languages** panel (below) and **🏦 Add from bank** (search and random draw). |
| **Report** | The static contest report in one place: download the browsable `tar.gz`, **publish it as history** at `/relatorio/<contest>/` (republish, unpublish) and publish the report of each archived round. Section 6½ explains it. |

**🌐 Statement languages.** A problem from the bank can have its statement in Portuguese, English
and Spanish (the author writes `docs/enunciado.en.md` and `docs/enunciado.es.md` in the package).
The **🌐 Statement languages** panel (Contest › Problems; the chief judge has the same panel in
the **🌐 Languages** tab of the chief judge panel) has two modes:

- **Automatic** (the default, with no configuration): each problem offers in the accordion all
  the languages that it has. A problem only in Portuguese shows no chips.
- **Only these languages**: select the list. Only PT selected = contest only in Portuguese, even
  if a problem has a translation.
- The accordion opens in the contest language (`LOCALE`) if the contest offers it. If not, it opens
  in the first language. The competitor changes the language with the **PT · EN · ES** chips, and
  MOJ remembers the choice.
- If the contest offers a language and a problem has no translation for it, that problem shows the
  Portuguese text. The table of the panel shows, per letter, what exists.
- To send your own HTML or PDF for a language, select the language in the selector next to the
  **Send HTML** / **Send PDF** buttons. The file applies only to that language.
- The problem set and the editorial in EN/ES use the translation of each problem. A problem
  without a translation is in Portuguese in the problem set. The problem title is also translated.

### 👥 People: who gets in, who is who

| Panel | What it does |
|---|---|
| **Accounts** | Create/reset/disable/remove accounts (one by one, or in bulk from a .txt/.csv file). Change the password of all accounts. The shortcut to the **Credential badges**. You create the role accounts HERE (section 3). In a contest with users **shared with Free Training**, the **🔗 Shared accounts** card converts all of them into own accounts (section 8¾). |
| **Registrations** (module `inscricoes`) | The contest **roster** (only registered persons get in) and the **window**: when it opens, when it closes (default: the contest start) and how many minutes of late entry. It lists teams and individuals. It can dissolve a team, register a person manually, **nudge a pending invitation by DM** (🔔) and export CSV. Section 8½ explains it. |
| **Sessions** | Who is logged in now, with logout. **🚪 Mass logout and login lock**: close the login, log everybody out, reopen. This is the end of a room exam and the round change. It also has the access log per day. It applies to any contest. |

### 🎛️ Operations: the contest day

| Panel | What it does |
|---|---|
| **Status** | The live dashboard (it refreshes in place every ~12 s): logged-in users, online/busy judges, queue, pending, latency, timeline, manual evaluation, and the **suggested actions** when something is wrong. Pending/held balloons only with the `baloes` module. |
| **Staff** | Overview of the print queue, and actions on it (+ balloons with the module). Performance per staff member, and the **scope** of each staff member / site chief (regex or `region:<site>`). `region:<name>` covers everything that is **in that node** of Event › Sites & schools: the site and, if it is a parent node, all the sites below it (`region:Nordeste` sees the sites of Nordeste), and also a cut (`view`) by its name. The site stored on the team applies or, without it, the regex. A regex in the scope is tested on the login. |
| **Judges** | The manual review queue: who claimed each submission, votes, age. Decide/resolve immediately. It also has the manual verdict configuration: the label options and **🔎 What goes to review**. This is a problem × verdict table: a checked cell goes to the judges, and the rest goes out automatically. With no cell checked, everything goes out automatically. The table has exceptions per language, and a button to release the held submissions that the new table no longer holds. |
| **Audit** | A unified feed of all events (admin actions, logins, submissions, verdicts) with filters and CSV. It also has the **backups** that the users uploaded (per user, with ZIP). |

### 🏟️ Event: what a multi-site contest has in addition

| Panel (module) | What it does |
|---|---|
| **Rounds** (`rodadas`) | **Warm-up and official contest in the SAME contest**: plans each round (window + problems), shows the checklist and promotes. The promotion archives all that happened. Section 6 explains it. |
| **Documents** (`documentos`) | Generates the contest documents, in PDF and HTML, in the three languages (pt/en/es): **Judging environment** (info sheet), **problem set** (cover + statements), **time limits sheet** and the **editorial** (it is published only after the END of the contest). Section 5 explains it. |
| **Balloons** (`baloes`) | The color of each letter. This is the color on the balloon sheet. The default covers A–O. With more than 15 problems, set the other colors (if not, they are gray). These are the colors of the live round. To give its own colors to another round, use Event › Rounds. |
| **Qualification** (`classificacao`) | Who qualifies for the next stages. Each **stage** (Brazilian Final, PDA, World Finals) has its own engine, which you select in the panel: preview, draft, publication (one 🎓 chip per stage on the scoreboard) and the **manual override** — exclude from the computation, withdraw without recomputing, promote by hand, always with a reason. For smaller contests (a selection contest), the **Manual** engine: you set how many teams advance and what the next stage is, and you click on the scoreboard to promote teams (reason optional). `docs/CLASSIFICACAO.md` explains it. |
| **Teams** (`sedes` or `telao`) | The identity of each account on the scoreboard: team name, country/flag, site, university, crest and photo. Load from CSV and "materialize matches". |
| **Cohorts** (`coortes`) | **Guest** teams (unofficial, "CCL") separated from the official teams: who appears on the public scoreboard, who sees whom, and the **🔓 Release results** of the post-ceremony. Section 8 explains it. |
| **Sites & schools** (`sedes`) | The sites (name + regex on the login). The sites feed the scoreboard filter, the staff scope, the badges, **the photos/music that each site chief manages on the big screen** and the gate by site. It also has the country/school rules by regex and the **⏱ extension by site/group** (regex → new end; it only extends, it never shortens). In **three modes** (Simple, Intermediate, Advanced) with a preview — section 7¼. |

### 🖥️ Machines: when the contest runs on Maratona Linux (module `maquinas`)

| Panel | What it does |
|---|---|
| **Gate & lock** | Where each team logged in from (IP and browser) in each round, with CSV. The configuration of the **browser gate by site** (expected × seen per team) and the **per-site IP lock** (pinned IPs, blocks, pin/release). Section 7 explains it. |
| **Anomalies** | What is wrong in the use of the machines **during the contest** (only with the UA gate on): a team with 2 live sessions, a machine shared by 2 teams, a submission from another machine, a UA outside the site, a site with fewer machines than teams, machine changes, the **single session** trail and the lock blocks. Timeline, table per team, CSV, logout, **log out mismatched UA**. Section 7½ explains it. |
| **mlinux** | The overview of the machines per site that nutellaboot collects: hardware and equipment model, RAM, editors, memory pressure with PSI, health during the contest (restarts, processes killed for lack of memory, wrong clock, idle time). It also has the collection and the remote commands. The health and PSI data appear only for machines with the new mlinux agent; the screen tells how many there are. The **Machine-team link** card shows how many machines MOJ has already linked to a team in nutellaboot. This occurs automatically when the team logs in, with the new mlinux agent. The card has the **send roster** and **republish links** buttons. Use the two, in this order, when the card says "team not in the image roster". The **Real-time machine alerts** card installs the nutellaboot notification. When a machine raises an alert (USB drive, mobile phone, network over USB, repeated identity), the alert appears in Machines › Anomalies. During the contest, the contest owner also gets it on Telegram. To install or remove it, the saved key must be the nutellaboot administration key. `docs/NUTELLABOOT.md` explains it. |

> **Balloons and the freeze.** By default, an accepted submission made while the scoreboard is
> **frozen does not create a balloon task**. These balloons are **not delivered later**: the task
> does not exist. This is the competition rule (a balloon that moves through the room shows what
> the freeze hides). It applies only to balloons: **print requests continue to work**. If you want
> the classic ICPC behavior (balloons in the room during the freeze, and the audience guesses),
> check **Deliver balloons during the freeze** in **Home › Rules**. This also **releases the
> balloons that were already held**. The pre-contest checklist shows which policy applies, and
> **Operations › Status** shows how many balloons are held.

> **How the scoreboard marks who solved a problem.** By default, the cell of a team that solved a
> problem is **always the same** (green), and the balloon color is in a **dot** next to it. This is
> intentional. The ICPC palette gives problem A the color **white**, and white on the white
> background of the scoreboard is the same pixel. A team that solved A looked like it did not
> solve it (the complaint that caused the change came from a student). If you prefer the classic
> style (the full cell painted with the balloon color), set it in **Home › Rules › "Solved" cell
> on the scoreboard**. Light colors get an outline so that they stay visible. This applies to the
> scoreboard, the reveal ceremony and the report.

Outside the panel, but linked from Home: **credential badges**, **reveal ceremony**, **jplag**,
**staff queue** and **scoreboard**.

## 1½. Contest modules: turn on only what your contest uses

A **module** is a group of features that the contest uses. A course exam turns on no module: the
panel shows only the common part (problems, accounts, sessions, scoreboard, staff, judges). A
course exam in a lab with **Maratona Linux** turns on `maquinas` (machine gate, single session,
anomalies). The Maratona turns on all of them. When you turn on a module, MOJ shows the related
panels, Home checks and cards. **When you turn it off, MOJ hides them and deletes nothing.** When
you turn it on again, all comes back.

| Module | What it turns on | Detected by |
|---|---|---|
| `sedes` | Event › Sites & schools, Event › Teams (identity), extension by site, staff scope by site | `regions.json`, `teams-meta.json`, extensions |
| `maquinas` | Machines › Gate & lock, Anomalies, mlinux; gate/lock/single-session checks | UA gate on, `SITE_LOCK=1`, nutellaboot key |
| `rodadas` | Event › Rounds; Promote card; round reports | `rounds.json` |
| `documentos` | Event › Documents; Documents card; chief judge tab | `docs/config.json` |
| `baloes` | Event › Balloons; balloons in the staff queue and in Status; balloons in the freeze | `balloons.json` |
| `coortes` | Event › Cohorts | `cohorts.json` |
| `inscricoes` | People › Registrations | `registrations.json` |
| `telao` | Reveal and Big screen cards; Event › Teams (photos) | `animeitor.json`, `webcast.json`, team photos |
| `classificacao` | Event › Qualification (stage and engine selector) | `classification.json` |
| `virtual` | Event › Virtual; **Virtual** button on the card of the ended contest; link on the scoreboard (see §6¾) | `virtual/runs/` |
| `esqueletos` | Contest › Skeletons: the team code editor opens with the language skeleton (below) | `esqueletos.json` |

Where to turn a module on: **Home › Modules** (the presets only preselect), step **7 · Modules** of
[create contest](/treino/criar/), `moj-contest -c <cid> modules on|off` or the `modules{}` section
of the creation spec. **It also turns on automatically when you use the feature.** Create a round
or a cohort, turn on the gate, generate a document, turn on registration, set a balloon color, a
site or a webcast key, on the web or in the CLI: the related module turns on immediately (the
audit records `modules-auto`). Only turning off is manual. This also applies to the creation spec:
one JSON creates the full contest, with the data of each module (sites, colors, cohorts, gate,
rounds, documents, registration window, big screen, qualification). The `export` gives back the
same section, without secrets. For contests created before the modules, MOJ detects the modules
one time from the files that they already have (`server/bin/contest-modules-detect.sh`).

### Code skeletons (module `esqueletos`)

In a contest, the team code editor opens **empty**: the team writes its full code. With the module
`esqueletos`, the editor opens with the language **skeleton** (the `main` and the usual reads). Use it
in a course list or a course exam, when the skeleton helps the student.

- **It needs the in-browser code editor on** (Home › Rules). MOJ refuses to turn the module on with
  the editor off. MOJ also refuses to turn the editor off while the module is on: turn the module off
  first.
- In **Contest › Skeletons**, each language has three choices:
  - **MOJ default**: the same skeleton as in training;
  - **custom**: the skeleton that you write for this contest;
  - **no skeleton**: that language opens empty.
- When the team changes the language, the text changes only while it is still the untouched
  skeleton. The code that the team typed stays.
- The screen refuses to submit the skeleton without changes ("You have not changed the skeleton
  yet"). The empty-editor check still applies.
- A **function-submission** problem (the package declares `FUNCTION_LANGS`) opens empty in the driver
  languages: the `main` of the skeleton would give a Compilation Error.
- Warning: the editor sends the file as `solution.<extension>`. In Java, do not declare the class as
  `public` (`javac` requires a public class to have the file name). The Home page warns.
- The module is not in the "Maratona / ICPC" preset: in a programming marathon the team expects an
  empty editor. In an ICPC contest the Home page warns.
- The custom skeleton goes with the export, the template and the duplicate. From the CLI:
  `moj-contest -c <cid> esqueletos ls|show|set|off|reset`.

## 2. Rules (Home › Rules): option by option

**Identity and window**

- **Name**: the displayed title. The *id* (which becomes the subdomain) does not change.
- **Start / End**: the contest window. Before the start: a countdown. After the end: nobody can submit (except judge roles). For a fine-grained extension, use the ⏱ section (by login regex, for example only one room that lost power).
- **Login opening (waiting screen)**: the time from which the student can LOG IN (before it, the login screen shows a countdown). Use it to open the login some minutes before the start. The API also blocks teams before this time (the organization can always log in). **Changing the round does not change this field**: with a warm-up and an official contest, set the opening before the start of the warm-up. The **🏁 Central** warns when the opening is after the start (warning) or after the end (critical) of the round on the air. Clearing the field does not remove the opening: select another time.
- **Scoreboard freeze**: freezes the public scoreboard from this time (ICPC style). Judges and the admin continue to see all. The reveal occurs in the ceremony.
- **Language**: Portuguese, English or Spanish. It sets the screen language of all persons in the contest (with no selector). It also sets the language of the **printed paper** (print cover sheet and balloon sheet), of the final **report** and of the invitation messages on Telegram (in English or Spanish, the message also includes the Portuguese text). The statements and documents have their own language (🌐 Statement languages, Event › Documents).

**👁 What the team sees during the contest**

- **Login enabled**: turn it off to lock the door (the persons that are already in stay in).
- **User can see the judging log**: the test-by-test report. ⚠ In a graded contest, a visible log can **leak the tests** (the student sees the input/output). This is the classic "SHOWLOG". Turn it off.
- **In-browser code editor available**: the editor side by side with the statement.
- **Show problems' time limit to users**: shows the TLs per language in the statement.
- **Allow file backup by users** / **Allow print requests by users (.staff)**: enable the backup upload by the student and the print requests (which go to the staff queue).
- **Anonymous scoreboard**: hides the individual performance (the student sees only his or her own position).
- **Login gate by UA substring**: only browsers whose identification contains the substring can log in (locked contest machine). Privileged roles are exempt.
- **🕵️ SUPER SECRET**: the contest disappears from home/archive/status, and even the scoreboard requires login. For contests that must not even be known to exist.

**⚖️ Judging (languages, pool, manual verdict)**

- **💻 Languages allowed in the contest**: the list of allowed languages in the contest (each problem can restrict it more, in Contest › Problems).
- **🖥️ Judge machines (pool)**: which judging MACHINES serve this contest (empty = any online judge). Do not confuse them with HUMAN judges (section 4).
- **Judging priority and submissions in the queue**: decides the contest's turn in the judging queue and the submission rule. You select it at creation and you can change it here at any time, at the end of the **⚖️ Judging** section. With **Public list** (the default) or **Private list**, each team has at most **3 submissions waiting for a verdict**: the 4th one is refused until a result comes out. This protects the judge from accounts that resubmit without a stop. With **Contest**, the contest is judged before the lists and there is no limit: from the **6th submission waiting for a verdict**, the next submissions of that team go further back in the queue (as if they arrived 2 minutes later). Nothing is refused. A submission held for manual verdict does not count. The change applies to the next submissions. Only the **training super-admin** gives or removes **Super** (it jumps the whole queue), in Training panel › Contests: Super does not show here, and a contest on Super has a locked field. Every priority change goes to the contest **Audit** log and to the training trail, with who changed it, from which to which, and through which screen. The **🏁 Central** shows the rule in effect (item "Submissions in the queue") and warns when an ICPC contest has no selected priority. The MOJ operator changes the limit of 3 in the conf: `SUBMIT_MAX_INFLIGHT=<n>` (`0` turns it off).
- **Manual verdict**: turns on **grading validated by human judges** (section 4).
- **Judges required to validate each verdict**: the quorum of the manual review: **1 to 5, default 2**. With 1, one vote decides (single review). With N≥2, the verdict goes out only with N **unanimous** votes. Any disagreement becomes a conflict for the chief judge.
- **⏱ Penalty (ICPC scoreboard)**: the minutes added per non-accepted attempt before the Accepted (default 20), and WHICH verdicts count as penalty (default wa/tle/mle/rte: **Compilation Error is OUT** by default; empty = nothing counts).
- **👁️ Full scoreboard (no freeze)**: an allowlist of logins that see the scoreboard without the freeze (in addition to admin/judges).

In the CLI, all of this is `moj contest -c <cid> settings set chave=valor` (for example:
`settings set manual_verdict=true review_judges=3`).

## 3. Special roles: what they are and how to enable them

**To enable a role, create the account with the correct suffix in the login**, in the
**People › Accounts** panel (or `moj contest -c <cid> users add fulano.judge`). There is no
permission checkbox: the suffix IS the role. The public self-registration never creates accounts
with these suffixes (they are reserved). Bulk operations (password reset, disable) **skip**
privileged accounts on purpose.

| Role | Suffix | Can | Cannot |
|---|---|---|---|
| **Administrator** | `.admin` | All: ⚙ panel, submit at any time, see the problems before the start, scoreboard without freeze, vote as a judge, resolve conflicts, answer clarifications. | Appear on the scoreboard (no role appears). |
| **Judge (human)** | `.judge` | **Judge** tab (manual review), submit/see the problems at any time (test the contest!), scoreboard without freeze, answer clarifications, Statistics. | Resolve conflicts; admin panel. |
| **Chief judge** | `.cjudge` | All that `.judge` can **+** the **Chief judge** panel: resolve vote conflicts, edit clarification answers already given, see the login and the name of who asked, release the reservation of another judge (own button, with confirmation), options and what goes to review. | Admin panel (Home › Rules, etc.). Reserve a clarification that another judge has already reserved. |
| **Staff (room staff)** | `.staff` | The **🖨️ print and balloons** queue (claim/print/deliver, automatic kiosk mode). | See problems or submit (never); badges; scoreboard without freeze. |
| **Site chief** | `.cstaff` | Follow the staff queue of the site (read-only). **Badges** with the credentials of the competitors and of the **`.staff`** of the site (with password, except in a contest that uses the training accounts: there the password is personal and does not go on the badge; the credential of the site chief also never goes on a badge). The **🎥 big screen** of the site and the **🏆 reveal by site** after the end. | Act on the print queue; see problems/submit; does not inherit `.staff`. |
| **Monitor** | `.mon` | Submit DURING the contest (without appearing on the scoreboard), **answer clarifications**, All Submissions and Statistics. | See the problems before the start; manual review. |

Golden rule: **no account with a role suffix goes to the scoreboard or to the statistics**. Create
as many as you need: they do not change the result.

**Alert for the organization on any page.** Admin, chief judge, judge and `.mon` get, on any page of the
contest, a bar at the top with a sound: **💬 unanswered clarification** (all these roles), **⚖ verdict
awaiting your vote** (admin, chief and judge, when manual verdict is on) and **⚠ conflict** (admin and
chief). The count also shows in the title of the tab. The sound plays again every 2 minutes while items are
pending. The bar has the buttons to enable or mute the sound and to ask for the system notification. The
scoreboard reveal, the Animeitor big screen and the editor window do not show the bar. More information in
`MANUAL-JUIZ.md`.

> Contest with users **shared with Free Training**: a role account of the training site does **not**
> get in with its role here. Only the `.admin` of the person who created the contest and the
> training superadmins get in. A judge, a staff member or a co-organizer = an account that you
> create **in this** contest (section 8¾).

## 4. Grading validated by judges (manual verdict)

With **Manual verdict** on, the automatic judging continues to run, but the verdict is **held**:
the student sees the submission as pending until human judges validate it.

The flow, in the **Judge** tab (the `.judge` page):

1. The judge **claims** a submission from the queue (a reservation with a deadline; max. N judges
   on the same submission).
2. The judge sees the computed verdict, the log and the code, and **votes** (confirm, or change
   the label).
3. When **N unanimous votes** accumulate (N = *Judges required to validate each verdict*, default
   2), the verdict is released. It goes to the history of the student and to the scoreboard
   immediately.
4. **Different** votes become a **conflict**: the **chief judge** (`.cjudge`) decides in the chief
   judge panel (a global alert gives a warning).

**Verdict options.** The chief judge or the admin edits the list in **🏷️ Options** (chief judge
panel or Operations › Judges). Each option has three fields:

1. The text that the **judge** sees and selects. Example: `5 - NO - Wrong answer`.
2. The **class**: one of the six canonical classes. The class sets the score, the penalty and the
   color on the scoreboard. Example: `Wrong Answer`.
3. The text that the **team** sees. Example: `Formato de saída errado`. Leave it empty to show the
   class. The `Accepted` class has no text of its own.

Thus each contest customizes what the team reads, without a change to how the scoreboard counts
points.

**How many persons do you need?** At least **N `.judge` accounts** (the quorum) **+ 1 `.cjudge`**
for conflicts. I recommend **N+1 judges**, so that the queue does not stop when a person takes a
break. The `.admin` also votes (it counts as a judge), but in a large contest keep the admin free
to operate. With **N=1**, one judge reviews everything (good for a small contest). N=2 is the
balanced default. N≥3 is for finals where the verdict needs a panel.

## 5. Contest documents (Event › Documents — module `documentos`)

The tab exists for the **`.admin` and for the chief judge (`.cjudge`)**. It produces the contest
documents, each in **PDF and HTML**, in **Portuguese, English and Spanish**:

| Document | What it contains | Where the data comes from |
|---|---|---|
| **Judging environment** (*info sheet*; formerly "Environment information") | In the format of the Maratona SBC sheet: operating system and compiler versions, accepted languages with their extensions, limits of memory, time, source size, output and compilation, the **compile and run lines** of each language (the same as the judge), the verdicts, the judging notes, the penalty and the response times. | Editable text (Markdown) + live data: `run/registry` (what the judges report), the contest `conf` and the calibrated TL. |
| **Problem set** | Cover + one statement per problem, in letter order. If the problem has its **own PDF** in the contest, that PDF goes in (the layout stays the same). If not, MOJ renders the statement in the format of the Maratona SBC problem sets: Computer Modern with LaTeX line spacing and hyphenation, centered problem title, samples in stacked boxes (as on the site). Or, if you check **"problem set samples as a table (input \| output)"** in the Documents panel, the samples go in an "Input sample · Output sample" table, as in the SBC (a sample with long lines is better stacked). The footer is "event – Problem X – title", with the page number. | `PROBS` of the contest, `enunciados/<chave>.{pdf,html}` and, if missing, the statement from the bank. |
| **Time limits sheet** | Table `letter · name · time limit per test`. If the limit is the same in all languages, there is one column and the note "does not depend on the language". If it is different, there is one column per language. Plus the **errata** that you write. | The TL **calibrated and served** to the judges (`run/tl`). |
| **Editorial** | A cover (title, date, introduction note and index of the problems) and the **solution** of each problem, in letter order, each problem on a new page. Generate and review it when you want. The server **lets you PUBLISH it only after the end of the contest** (extensions by site included), and the team can download it only after the contest ends. | The `docs/solucao.md` of the **package** of each problem (the text that the author wrote and that never goes to the student). |

**Flow, from start to end**

1. **Fill in the data** (⚙️ *Document data*): problem set version (`v1.0`), cover note and
   errata. Save.
2. **Adjust the cover**, if you want (🎨 *Problem set cover*). There are two modes, in this order
   of precedence: **uploaded PDF** › **text**. The text opens with the **MOJ default cover**: it is
   that cover, written in Markdown, so you edit only what you want to change. The markers are
   replaced when MOJ generates the document: `{{CONTEST_NAME}}`, `{{DATE}}`, `{{N_PROBLEMS}}`,
   `{{N_PAGES}}`, `{{SITES}}`, `{{VERSION}}` and `{{NOTE}}` (the cover note). `{{N_PAGES}}`,
   `{{SITES}}` and `{{NOTE}}` are optional: when one of them is empty, its block disappears. Upload
   a PDF when the cover is finished artwork of the event. It goes in as it is, and the rest of the
   problem set is attached after it.

   **Logo** (🏷️ *Header logo*, optional): a strip with the event logos (PNG, JPEG, WebP or SVG, up
   to 5 MB). It goes at the top of each page of the problem set and of the editorial, and on the
   generated cover, as in the Maratona SBC problem sets. It applies to the three languages;
   *remove* takes it out.
3. **Adjust the info sheet text**, if you want (📝). It is also Markdown, with the markers
   `{{TOOLCHAIN}}`, `{{TL_TABLE}}`, `{{LANGS_TABLE}}`, `{{MEMLIMIT}}`, `{{STACK}}`,
   `{{CONTEST_NAME}}` and `{{DATE}}`.

   The two texts use the **MOJ editor** (Markdown colors and line numbers), with **one tab per
   language** (PT · EN · ES), as in problem management. *Save* saves all the changed languages.
   *restore default* gives the language of the tab back the MOJ text.
4. **Generate** (the button of each line, or *⚙️ Generate all (pt+en+es)*), **or upload a finished
   PDF** (the *upload PDF* button of the line). The uploaded PDF is a complete document. It
   overrides the generated one in all that MOJ serves, and you can publish it without generating.
   *back to generated* deletes only the uploaded file. The conversion to PDF takes some seconds.
   The problem set takes the longest, because it joins one PDF per problem.
5. **Check**: each line has **PDF**, **HTML** and **open**. Review before you publish.
   **Something wrong in the generated PDF**, such as too much or too little space between the
   elements, or a large image, caused by the Markdown of the statement? Each generated document
   also has the **✎ .odt**, the editable file that the PDF came from. Download it, adjust it in
   LibreOffice (or Word), export it to PDF and upload it with *upload PDF*. The uploaded file
   overrides the generated one, and it is the file that all persons download. The `.odt` of the
   problem set has the cover as an editable page, followed by the statements. If the cover is an
   uploaded PDF, or a problem has its own PDF statement, the `.odt` marks the place, and you join
   the PDF when you export. Only the admin and the chief judge can download the `.odt`.
6. **Publish**. Publishing does two things: the document appears in the **Contest** section of
   the contest page and in **Documents**. Who sees what:
   - **Judging environment**: published = visible to all roles (it is logistics).
   - **Problem set and time limits sheet**: before the START of the contest, only `.admin`,
     `.cjudge` and `.judge` can download them. **The site (`.staff`, `.cstaff`), the `.mon` and
     the teams only from the start.** A problem set in the hands of any person before the contest
     is a leaked contest, for any role. The site prints from the start (the `+ news` of these two
     documents is refused before the start, because the news item attaches the PDF).
   - **Editorial**: it is published only after the end, and only the judges can download it
     before the contest ends for ALL sites.
   If you check **+ news**, MOJ also creates a news item with the PDF attached.
   **Unpublish** undoes this (the link disappears; the news item, if MOJ created one, stays:
   delete it in the news tab if necessary).

**Did you generate again? You do not need to publish again.** The published link points to the
current document, so a new generation delivers the new version to the next person who downloads
it. But **tell the site**: the persons who already printed it have the old version (this is why
the cover has the *problem set version* field).

> 🌐 **The problem set and the editorial are in the language of the document.** The English problem
> set uses the `enunciado.en.md` of each problem (or the English HTML/PDF that you sent in the
> Problems panel), and the English editorial uses the `solucao.en.md`. A problem without a
> translation is in Portuguese in the middle of the problem set: the document never has only the
> cover translated. The problem title is translated when the package has the title in that
> language. A bilingual contest with statements prepared outside MOJ continues to use the
> **uploaded PDF**.

> ∑ **The formulas in the PDF look as in the statement on the page**, including the vertical bar
> (`|x|`, `a | b`). The author does not need to escape anything. If a formula symbol shows as a
> red `¿` in the PDF, this is a defect of the generator, not of the statement. Report it (with the
> problem) and, in the meantime, upload the finished PDF of that problem set. A problem set
> generated before a fix does not update itself: generate it again.
>
> 🖼 **Statement images fit on the page.** In the PDF, each image is at most the size that it has on
> the web page, and never larger than the usable area (a large image is reduced, with the same
> proportions). The width that the author set in the statement (`![](figura.png){width=50%}`) also
> applies in the PDF.

> 🔒 **The problem set is contest content.** Before it is published, only `.admin` and `.cjudge`
> can download it. After it is published, before the start only the judges (`.judge`) are added to
> them. For the site and the teams, the API responds **404** until the start: this is not an
> interface lock.

## 6. Rounds: warm-up and official contest (Event › Rounds — module `rodadas`)

Every programming marathon has a **warm-up** (dress rehearsal) before the contest: two or three
easy problems, on the day before or on the morning of the contest. The team uses it to turn on
the machine and to test the login, the editor, the printing and the balloon. Your team of judges
and staff also rehearses. After that, the contest starts **in the same contest**, because you want
to be sure of its configuration (accounts, passwords, sites, balloon colors, time limits,
languages, judge pool).

In MOJ, these are **rounds**. The **live** round is the one that appears in Home › Rules and in
Contest › Problems. The other rounds stay planned until you promote them.

**The procedure** (note the order: the warm-up comes FIRST)

1. **Set up the contest** as usual, with the **warm-up** problems and the warm-up window.
2. In Event › Rounds, give the correct name to the live round (`aquecimento`, type *warm-up*) and
   **create the next round** (`oficial`): window, freeze and the list of problems of the real
   contest. MOJ keeps the list and puts it live only at the promotion: nobody sees the contest
   problems before.
   You can use any problem that the contest owner can see: public, his or her own, of a
   collaborator or of his or her org. The rule is the same as in Contest › Problems, for the live
   round and for the planned round.
   Each round can have **its own balloon colors**. Open the round, go to "🎈 Balloon colours for
   this round" and save. The colors go live when the round is promoted. A round without its own
   colors inherits the current colors. For the live round, this section and Event › Balloons edit
   the same data.
3. **Run the warm-up.** The team sees a fixed banner that tells that this is a warm-up and that
   this scoreboard is not the contest scoreboard. Use it as a **full rehearsal of the whole
   operation**. If the login opens at the minute of the start (ICPC model), this is the only
   moment when each role uses the real screens with nothing at stake. Before it, give each person
   the tutorial of his or her role ([/contest/ajuda/](/contest/ajuda/)), and ask each person to do
   his or her own list: the team (log in, open a problem, submit on purpose, clarification,
   printing, backup, scoreboard), the **room staff** (printer, the **pop-up** allowed, kiosk, the
   route), the **site chief** (every team of the site logged in at least one time), the
   **judges** (verdict options, log/code, the pair reads the same), the **chief judge** (number of
   judges, what goes to review, conflict alarm) and the **big screen** (projector, connection to
   the Animeitor — publish the scoreboards and turn on the feeder —, photos and music).
4. When it ends, click **🚀 Promote now**. MOJ checks the checklist and, if all is ready:
   - it **archives** the round: submissions (with source code), verdicts, judge log, scoreboard,
     statistics, clarifications, news, staff tasks and the access logs are kept in
     `rounds/<rodada>/`, plus a **browsable report** of the round;
   - it **resets** the scoreboard and the history of the teams, restarts the print numbering and
     clears the extensions by site;
   - it **applies** the window and the problems of the official contest, and its balloon colors, if
     it has them.
   Caution: with the scoreboard frozen, MOJ accepts the promotion only from the end of the contest
   for all sites + 1 minute. The checklist shows `freeze_locked` with the time. The "ignore
   blockers" option does not override this rule.
   You type the contest id to confirm. MOJ audits all of it.

**I registered the CONTEST first. What now?** Did you set up the contest with the official
contest first, and create the warm-up round only after? **Do not promote.** Promotion archives
the live round (your contest, empty), and an archive cannot change. The correct procedure is to
**swap them by editing the two rounds** in the same panel (the panel warns you when it finds a
planned round that starts before the live round):

1. Edit the **planned** round: rename it to `prova`, type *official contest*, and give it the
   window + freeze of the contest. In **Round problems**, put the list of the contest problems
   (MOJ keeps it, and nobody sees it).
2. Edit the **live** round: rename it to `aquecimento`, type *warm-up*, warm-up window (no
   freeze), and replace the problems with the warm-up problems. For the live round, saving
   **applies immediately**.
3. In Home › Rules, make sure that the current window is the warm-up window. Then follow the
   normal procedure from step 3.
5. **After**: the scoreboard and the submissions of the warm-up stay readable in Rounds (and you can
   **publish** the round so that the teams see it). The **raw archive** in `.tar.gz`, with source
   code, is one click away, for a later audit.

**The checklist is serious.** The promotion REFUSES while there is:

| Blocker | Why |
|---|---|
| `round_running` | the live round did not end (extensions by site included) |
| `jobs_in_flight` | there is a submission in the spool/judge queue. If it were judged after the change, its time would be calculated against the contest start, and the warm-up submission would appear again in the contest history |
| `pending_verdicts` | there is still a submission without a verdict in the history |
| `review_pending` | there is a submission in the manual review without a released verdict: the judge vote would go to the contest scoreboard |
| `judged_down` | the judging daemon is not alive, so the queue does not drain |
| `no_next_round` | there is no planned round |
| `official_over` | the live round is the **official contest** and it has ended: promoting archives its result and the visible scoreboard goes back to zero. To **show the result**, do not promote: turn the secret off in Rules and publish the report |

There is a `--force` (the "ignore blockers" checkbox) for emergencies. It does **not** remove the
risk: it only assumes that you know what you do. The only blocker that `--force` does **not**
ignore is `no_next_round` (without a planned round, there is no round to promote to).

**Did you promote by mistake? Undo it.** In Event › Rounds, the card **↩ Undo the last promotion**
(or `moj-contest rounds undo`) brings the archived round back live with everything it had —
submissions, verdicts, clarifications, prints, scoreboard — and the round that went live goes back
to planned. It works only while the round that went live has had **no activity** (no submission,
clarification, print or notice); if not, the card tells what happened in it. You type the contest
id to confirm, and it goes to the audit. This was the case at TCP 2026: after the contest, the
organizer created an extra round and promoted it, and the scoreboard went back to zero.

> A contest that uses the accounts of another contest (`USERS_FROM`) **promotes normally**: the
> archive changes only the local `users/`. This was a blocker before. It is not a blocker now,
> because this is the real use case (warm-up + contest with the training accounts).

**What does NOT change at the promotion:** accounts and passwords, teams/sites/flags, staff
scope, balloon colors, regions, calibrated time limits, languages, judge pool, the table of what
goes to review and the texts/cover of the documents. **What is reset:** the scoreboard, the
history and the submissions of the teams (archived, not lost), balloons, print numbering,
extensions, and the list of published documents.

> ⚠️ **Balloon colors are per LETTER.** If problem A of the warm-up and problem A of the contest are
> different, the color of balloon A is the same in the two rounds. Check it in Event › Balloons
> before the contest.

**In the CLI:** `moj contest -c <cid> rounds ls | add | set | problems | promote | publish | archive`.

## 6½. After the contest: finish the event

When the contest ends, the scoreboard stays **frozen** and the documents stay **not published**
until a person releases them. None of this occurs automatically with the clock. Home then shows
the **"🏁 After the contest"** block, with the checklist of what is still closed, and the
**🏁 Finish event** button. This button does at one time the two things that everybody forgets:

1. **it opens the scoreboard**: it removes the freeze (`FREEZE_TIME=0`), so the final result
   becomes public (this has the same effect as the "🔓 Unfreeze all (public)" button of the reveal
   ceremony). MOJ accepts the unfreeze only from the **end of the contest for all sites + 1
   minute**. The extension of a site counts. The rule applies to all paths: this button, the
   ceremony, the freeze field in Home and the round promotion. The screen shows the time from
   which the button is available;
2. **it publishes the documents already generated** that are not published yet: problem set, time
   limits sheet, info sheet and editorial appear in "Files & Resources" for the teams. (The
   editorial can be published only after the end; this is why it is included here.)

The button does **not** change the rest. Release of the **judging report** to the teams
(`SHOWLOG`), display of the **time limits** and **release of the cohorts** (guest teams) stay
your decision. Each one appears in the checklist with a "fix →" shortcut to the correct screen.
The button runs only after the contest ended **for all sites** (extension by site counts), and you
can use it again as many times as you want: the second time, it does nothing.

The **final report** closes the cycle (Contest › Report). The browsable `tar.gz` contains the open
scoreboard, the submissions, the full statistics, the statements **and** the published documents.
This is the package that you send to the participants and to the event archive. Next to the
download there is **📢 Publish as history**. The same site then exists at
`https://moj…/relatorio/<contest>/`, and the contest card on the home page and on `/contests/`
gets the **📑 Report** button. It is the **history** of the event. The generation runs in the
background (~1–2 min for a large contest; the panel shows "publishing…" and changes automatically
when it ends). It is public. The report does not contain source code, judge log or passwords, and
the clarifications are anonymous. But it shows team names, runs and statistics: publish it when
all has been announced. **🔄 Republish** generates it again and replaces the full site at one time
(a reader does not see a half-done site). **Unpublish** deletes the address and the button of the
cards. The **archived rounds** (warm-up, for example) have their own button in Contest › Report:
**🌐 publish** puts the report that the promotion generated at
`/relatorio/<contest>/rodada/<slug>/`. When the main report is (re)published, its home page links
the public rounds in "Earlier rounds of this event".

## 6¾. Virtual participation (Event › Virtual — module `virtual`)

After the contest ends, any Free Training account can **do the contest again one time**, in its
own time, against the official scoreboard. The official scoreboard **does not change**. Full
reference: `docs/VIRTUAL.md`.

**To turn it on:** Home › Modules › **Virtual participation**. The module turns on only when:

1. the contest **is not secret**;
2. the mode is **ICPC**;
3. **all the problems are already public in the training**. If one is not, the response is an
   error that tells how many are missing. Publish the problems first (problem management) and turn
   the module on again.

You can turn on the module before the end of the contest. It stays **inactive** and opens
automatically when the contest ends for all sites **and** the scoreboard is unfrozen (the
**Finish event** button).

**Caution:** this module makes the final scoreboard and the problem list visible to training
accounts. A contest that must not be seen from outside must not turn on this module.

**The Event › Virtual panel shows:**

- the **conditions**, one per line, with ✅ or ⛔. The public sees only "unavailable"; you see what
  is missing;
- the **link** to the page (`/treino/virtual/?c=<contest>`);
- the **recorded participations**, with solved problems and penalty. The **remove from board**
  button removes a row from the virtual scoreboard (the record stays; **restore** undoes it). The
  action is audited.
  The **give attempt back** button deletes the row and lets that account start again in this
  contest. Use it for a tester, or for a person who had a problem during the contest. This action
  is also audited.

**Participant rule** (the participant reads it before the start): one participation per account.
The participant can give up without a record in the first 15 minutes, or while he or she has no
accepted submission, at most 2 times. The 3rd start is final.

## 7. Team machines (Machines › Gate & lock — module `maquinas`)

The warm-up is when the teams really turn on the computers. From it, MOJ gets the room map
**team × IP × browser** (from the contest access log, cut to the round window: MOJ captures
nothing new). The tab shows, per round:

- **per team**: name, site, IPs and browsers used, first login, and an alert when the team used
  **more than one IP**;
- **per IP**: which teams came from each machine. It marks a **shared IP** (two teams on the same
  machine is a sign of a swapped desk or a borrowed account);
- **who changed machines**: in the official contest, a team that logs in from an IP/browser
  different from the one it used in the warm-up is marked in red;
- **⇣ CSV** of all of it, to compare with the spreadsheet of the site.

Two actions start here, and they write to the usual place:

- **set site**: in the per-IP view, type the site name and click. This saves the **site** of the
  teams of that IP (the same field as in Event › Teams). The scoreboard, the badges and the staff
  scope then use it;
- **configure the browser gate**: the 🔒 section at the top of the tab (just below). The browsers
  actually seen in the round are listed there, and you can make each one the *fallback* with one
  click.

### The gate BY SITE (the programming marathon case)

When each site runs **its own** image, the UA of each machine contains a part of the team login:
`teambrspso001` (Brazil/BR, `São Paulo`/SP, Sorocaba/SO) runs on an image whose UA contains
`brspso`. One substring is not sufficient, so MOJ **derives the expected value from the login**.

**On the web** (🔒 section of Machines › Gate & lock): the **"Block anyone not coming from the site
image"** switch turns it on/off. Below it are the **login regex (with capture)** and the **expected
UA** (`\1`), with a **live tester** ("test with login" → *UA must contain `brspso` · site
Sorocaba*), and three collapsible lists: **per-site overrides**, **login regex rules** and
**exempt**. When you save, it applies from the next login.

**In the CLI**, the same:

```
moj contest -c <cid> ua-gate set --from-login '^team([a-z]{6})[0-9]{3}$' --expect '\1'
moj contest -c <cid> ua-gate set --region 'Sorocaba=brspso-v2'     # site outside the pattern
moj contest -c <cid> ua-gate set --exempt '^ccl' --exempt time-reserva-07
moj contest -c <cid> ua-gate check teambrspso001                   # what MOJ expects from it
moj contest -c <cid> ua-gate show
```

One rule covers **all sites at one time**. The resolution order is: **exempt** › role account
(always gets in) › regex rule › **site override** › capture in the login › single substring (the
usual `login_ua_substring`, which continues to apply as the last option).

- A login that does not match is **blocked at login** (403). The decision was to block, with the
  **exempt** list as the margin. `--mode off` turns off the gate without deleting the
  configuration.
- The Machines › Gate & lock panel shows the **expected UA × seen UA** per team, and counts how
  many are outside the site image. This is how you fix the room **in the warm-up**, before the
  gate blocks a team in the contest.
- To log out a team that is already logged in with the wrong browser, use **"Log out mismatched
  UA"** (Machines › Anomalies). It compares each session with the expected value of **that** team.
- **Per-site IP lock** (switch in the same 🔒 section, OFF by default; turn it on for the contest):
  the gate and the subdomain isolation do not stop `curl --resolve moj…:443:<IP>` from the contest
  machine to the base site (training, backups that the student uploaded before, another contest).
  With the lock, each competitor login **pins the source IP** (the exit of the site) to this
  contest until the end + a margin. From that IP, any other target responds **403 `site_locked`**,
  also a training session opened before. Role accounts are exempt. **Every claim and every block
  goes to the audit** (`site-lock-claim`, `site-lock-block`). They appear in Machines › Gate &
  lock (site lock), with "release" per IP and "🔒 Pin IPs already seen" (useful on the morning of
  the contest). An accepted side effect: during the window, all persons behind that public IP
  lose access to the training.
- **Single session per team** (switch in the same 🔒 section, on by default): with the gate in
  effect, a new login on **another machine ends the previous session** of the team. A change of
  machine because of a defect continues to work (the team logs in on the new machine, and the old
  one loses the session). A page reload on the same machine ends nothing. Each ended session
  becomes an event in Machines › Anomalies.

## 7¼. Sites (Event › Sites & schools — module `sedes`)

The site of each team feeds the scoreboard filter, the staff scope (`region:<name>`), the badges, the
per-site browser gate, the statistics, the classification and the big screen. All of them use the **same
rule**:

1. the site **stored** on the team wins (the name, not case-sensitive);
2. otherwise, the **deepest regex** that matches the login (not case-sensitive);
3. a group/country **adds up** the sites below it; a node with the same name as the site also counts it;
4. a stored site that does not exist in the tree shows as "outside the tree" and counts in the node that the
   regex gives;
5. a **cut** (`view`: super-site, women teams) groups teams that are already in the sites, and it is never
   the site of a team.

The panel has **three modes**. Choose the mode that is sufficient for your contest; you can go up a mode at
any time. A mode that does not fit the current tree is disabled and tells you why.

- **Simple** — a list of sites. Each site has "logins that start with" (comma-separated). To assign teams,
  paste the list of logins and choose the site, or choose the site of each team without a site. When you
  rename a site, the teams stored with the old name move with it (the preview shows how many before you
  save). By the IP of the contest machine: Machines › Gate.
- **Intermediate** — groups (country, region) › sites. Each site has rules: starts with, contains, ends with,
  or is one of (list).
- **Advanced** — the whole tree: sub-regions, `view` cuts and free regex.

The **preview** below shows what the scoreboard, the badges and the staff scope will see: how many teams each
site has, who has no site, who stopped at a group/country (the regex matched the group and none of its
sites), who matches two sites, and the stored sites that are outside the tree. "To save" summarizes the
change. If another tab or the CLI changed the sites after you opened the screen, the save refuses: reload
and do it again.

A **registered** team keeps its site in the registration: the site does not disappear when the team
changes. The Home shows the item **Sites** when there is something to check.

The regex follows a subset that matches the same in the browser and on the server: `\d \w \s` and `(?:`
are accepted; `\b`, `(?=`, `[[:class:]]`, lazy quantifiers, an ambiguous hyphen inside `[ ]` and accented
letters are not (logins have no accents). The save tells you which site and why.

In the CLI: `moj-contest -c <id> regions show|who|assign|set|map`.

## 7½. Machine anomalies (Machines › Anomalies) and Sessions (People › Sessions)

In the Maratona 2026, the question "did a team use two machines?" had an answer only after the
contest, with a manual cross-check of logs. The **Machines › Anomalies** panel answers it
**during** the contest (the active sessions, the mass logout and the access log, which apply to
ANY contest, are in **People › Sessions**). It applies only with the **UA gate on**: the browser of
the mlinux image identifies the machine (`machine_id/boot_id`). A login from a common browser has
only the IP, and behind NAT the IP is the full site. These logins stay out of the machine
anomalies (they appear only in "UA off-site" and in the session list). With the gate off, the
panel shows a warning and shows only the sessions and the access log.

- **Cards** (click = filter): active sessions, 👥 **2 live sessions** (the same team on two
  machines; with single session on, this occurs only with a copied token), 🖥 **shared machine**
  (2+ teams logged in on the same machine in the contest; serious if the two sessions are live on
  it), 📤 **submission from another machine** (the submission came from a machine different from
  the one that made the login; the same machine after a restart appears as *info*), 🧭 **UA
  off-site**, 🏫 **site short of machines** (from the last nutellaboot collection), 🔁 **switched
  machine** (info: normal when a machine fails) and the **revocations** of the single session.
- **Timeline**: each event with time, type, team, machine and detail; filters by type and text;
  CSV; a **log out** button for the team.
- **Teams**: only the teams with an anomaly (or all with a session): live sessions and on how many
  machines, the machines used in the contest in order, the last submission (✓ came from the
  machine of the session; ✗ did not) and the anomalies as tags.
- **🚪 Mass logout and login lock**: the round change in three clicks. **Close login** (a
  competitor gets 403 `login_disabled`; the organization gets in). **Log out competitors**, **staff
  and site chiefs** or both (never admin, judges, chief judge, monitor or big screen). Promote the
  round in Event › Rounds. Then **reopen login** when the teams can get in. Each ended session
  becomes an event in the timeline; the action goes to the audit (`logout-all`).
- **🔒 Site lock**: the IPs pinned to this contest (logins, blocks, until when), the recorded
  blocks (when, IP, target, route, session) and the **release** and **🔒 Pin IPs already seen**
  buttons. The "lock blocks" card and the 🔒 events of the timeline come from the audit. Section 7
  explains it.
- **Request channel in the contest**: how many contest logins and submissions came from the **web**, from the **CLI**
  (`moj-comp`) and from **offline packages**. This applies also without a gate. The CLI identifies
  itself in the User-Agent (`moj-comp/<build>`). On the contest machine, it sends first the **same
  User-Agent as the browser of the image** (read from `/etc/moj/user-agent`, which the image
  writes). This is how it passes the gate by site and gets the same machine key as the browser:
  if you use the two on the same machine, the session does not end. Outside the contest machine,
  the gate blocks the CLI (403), on purpose.
- It refreshes automatically every 30 s. The submission records its origin (IP, browser and the
  session used) in `var/submit-origin.log`; the logins go to `var/access.log`; the ended sessions
  go to `var/session-events.log`. The three logs continue across the rounds and go into the
  archive.

## 8. Guest teams (scoreboard cohorts — Event › Cohorts, module `coortes`)

A programming marathon invites teams that **compete without being in the official competition**:
people call them guest, unofficial, "CCL". MOJ handles them as a **cohort**: a group of teams with
its own visibility policy.

**What a private cohort guarantees**

- its teams **do not appear on the public scoreboard**;
- the regular teams **do not know that it exists**: not on the scoreboard, and not in the team
  directory (`/contest/teams`, which is public and listed every login);
- the **guest teams themselves see all teams** (their scoreboard shows official + guest teams);
- when you **release the results**, everybody sees all teams, and a guest team appears
  **placed by its performance but without taking an official position**: the combined podium
  continues to agree with the official one.

**How to configure it (Event › Cohorts)**

One row per cohort, with the fields that set the behavior: **id**, **name**, **login regex**,
**public** (appears on the public scoreboard), **unranked** (included without taking a position),
**default** (a team that matches nothing goes to it) and **sees**: the checkboxes that tell which
cohorts that view sees (a cohort always sees itself). The **teams** column counts how many teams
are in each cohort.

- **+ create cohort**: it starts private and unranked, and it sees all. This is the CCL case.
- **Number guest teams in their own sequence**: by default, a guest team shows `–` in place of
  the position. With this option on, it shows its position among the guest teams, in italics, on
  the scoreboard, in the reveal and in the report. The official numbering does not change.
- **assign**: select a team and its cohort (the field overrides the regex). "— by rule (regex) —"
  sends the team back to the regex.
- **📌 Materialize (N)**: records the cohort of each team that now matches only by regex. After
  this, a change to the regex moves nobody. The counter tells how many teams are in this
  situation.
- **🔓 Release results**: asks you to type the **contest id** to confirm (in practice it cannot be
  undone: the public scoreboard then shows all teams).
- **Generated scoreboards**: the views that `build.sh` maintains (one per cohort that sees a
  different set, plus the public one).

To change the **default** cohort, select the radio button of the other row and save **that** row.
To remove a cohort, it must be **empty** (and you can never remove the default cohort).

**The same in the CLI:**

```
moj contest -c <cid> cohorts ls
moj contest -c <cid> cohorts add ccl --name "Café com Leite" --regex ccl --private --unranked
moj contest -c <cid> cohorts assign timeconvidado07 ccl     # guest team without 'ccl' in the login
moj contest -c <cid> cohorts materialize                    # records the rule as a field per team
moj contest -c <cid> cohorts release                        # the "release everything" (asks for the id)
```

The cohort matches by **regex on the login** and/or by the `.team.cohort` field of each team (the
field overrides). `materialize` changes the rule into data: after it, a change to the regex moves
nobody. A team that matches nothing goes to the **default** cohort (the one of the official
teams).

**What stays complete, on purpose**: these are privileged roles, and you need them: **All
Submissions**, **Statistics** (including who solved first), the **staff queue** (the balloon of a
guest team must be delivered) and the **final report**. Two practical results:

- the **code of a submission** is visible only to the team that sent it and to judge/admin. The
  old option "show the code of submissions to everybody" (`SHOWCODE`) was **removed** on
  2026-09-18;
- to **publish the archive of a round** (Event › Rounds), the results must be released when there
  is a private cohort: the round report has the open scoreboard with all teams.

> ℹ️ Two **numeric** channels remain. They do not hide identity, but they exist: the public status
> page counts the pending submissions of **all** teams, and the print task numbering is unique per
> contest (gaps show activity that the team does not see).

## 8½. Pre-registration and teams of 3 training accounts

This applies to a contest created with **"Share Free Training users"**. When you turn on
registration (People › Registrations → **Turn on**), the contest gets a **door**: a person who did
not register **does not get in** (the API refuses the login; it is not only the screen).

**How a person registers:** on the main site, logged in to the training, at
`/contests/inscricao/?c=<id>` (the contest card on the home page gets the **📝 Register** button).
The person selects **individual** or **create a team**: gives a name and invites up to 2 training
logins. Each invited person must **accept**. While the window is open, it is possible to leave,
rename and undo. Participation is exclusive: to accept an invitation cancels the individual
registration.

**The invitation sends notifications automatically.** At the moment when the captain invites, the
**mojinho sends a DM** to the invited person, with the accept/decline link. On the **day before
the close** (24 h before), it sends **one** last notification to the persons who did not answer
yet (the message is in Portuguese; if the contest has `LOCALE=en`, it is in English **and**
Portuguese in the same text: a DM has no language selector). It reaches only persons with a
**linked Telegram** account (training profile → 📨 Telegram). This is why the invitation list
shows `📨` (reachable) or `⚠️` (no channel), and the summary counts how many have no channel. In
the team table, each pending invitation has the **🔔** button to nudge the person immediately, and
the header has **🔔 Remind all**. A manual nudge does **not** cancel the automatic notification of
the day before. To turn off the automatic notification for this contest, clear *automatic
reminder* in the window box (this saves `REG_REMIND=n`). This is important because **a person who
does not accept the invitation is not in the team**, and sometimes is not even registered.

**In the contest, each member logs in with his or her OWN training login and password**, and the
session becomes the team session: the scoreboard, the balloons and the printing see **one row
only**. MOJ records who was at the keyboard (`var/actor-log` and the 5th column of
`var/access.log`), which is useful for a later check.

**The window** (People › Registrations → *Registration window*): **opens** (empty = already open),
**closes** (empty = the contest start) and **late (min)**: the minutes after the start during which
a person can still get in, but in the `…-atrasado` cohort. This cohort appears on the scoreboard
**without taking a position** (it is the *extra registration* of Codeforces). After that, the door
closes.

**Which clock these fields use:** the clock of **your browser**. The box shows which one, just
below. But the times that **MOJ writes for people** (the mojinho DM, the pre-contest checklist,
the date of the problem set, the final report) use the **contest timezone**. You set it in
*Home › Rules → 🕒 Identity and window → 🌎 Contest timezone* (empty = `America/Sao_Paulo`). When
the two clocks are different, the window box also shows the time in the contest timezone, so
there is no doubt. Type the name of any timezone (`America/Santiago`, `America/Mexico_City`…). The list
suggests all of them, starting with your browser's. Use your own city's timezone, not another one that has the
same time today: daylight saving time changes on different dates in each country, and the texts would be 1 h
off after the change. You can also select the timezone in the creation wizard, and it goes with the contest
when you export, duplicate or save a template. From the CLI: `moj-contest -c <cid> settings set tz=America/Santiago`.

**Scoreboard:** registration creates the `individual` and `times` cohorts, each with **its own
scoreboard**. The "Board: Overall | Times | Individual" selector appears automatically on the
scoreboard page. If the contest already had cohorts, the pre-contest checklist warns that these
two are missing.

**With a WARM-UP (a warm-up that stays live for days):** plan the two rounds in *Event › Rounds*
(warm-up now, official contest on the real date). By default, **the warm-up also requires
registration**. It is in the warm-up that the competitor solves login, submission and scoreboard
problems. To let persons in without registration only moves the problem to the contest day.
Registration closes automatically **at the start of the official contest** (this is the date
that "closes" inherits, not the warm-up date). If you prefer a warm-up with an open door (any
account of the source gets in without registration), set `REG_WARMUP_OPEN=y` in the conf. In this
case, the **promotion** ends the session of each person who did not register, and the contest
scoreboard starts with only the registered persons. While this applies, the panel shows the
*🔥 warm-up: open door* badge.

**The participation mode is final:** after registration (individual or in a team), the
competitor cannot cancel or change the mode alone. The registration page makes this clear before
the choice, and any change goes through you (People › Registrations: remove, dissolve, register
manually).

**The team also declares at registration:** the **university** (it becomes the prefix
`[SIGLA] Nome do Time` on the scoreboard, and the school column/filter), the **use of AI** (it
appears as 🤖 next to the name: it is transparency, not judgment), the **flag** (country or
Brazilian state: the small flag on the scoreboard) and a **team photo** (the one that goes to the
big screen; the server processes it again, without metadata). The captain can edit all of this
while the window is open, and it is visible in your panel and in the CSV. **The INDIVIDUAL
registrant declares the same data** (except the photo): university, AI and flag, at registration
or later, on the same page. The organization adjusts any of them with the `team-meta`/
`individual-meta` actions of the panel, without a regex rule in `teams-meta.json` (the legacy
mechanism continues to apply only as a visual overlay).

> Contest-day tip: the Home checklist shows how many persons registered and **how many invitations
> are pending**. A pending invitation means a person who thinks that he or she is in the team and
> who, at the time of the contest, cannot get in.

## 8¾. Accounts shared with Free Training: choose and undo

When you create the contest (step 3 of the wizard), you choose between **own accounts** of the
contest and **users shared with Free Training**. With shared users, each person logs in with the
account and the password of the training site. This is practical for an exercise list. For an
exam, know the consequences:

1. The login and the password are the Free Training ones. You cannot see or reset them, and the
   badges show no password.
2. Any Free Training account gets in. To limit this, turn on the **Registrations** module
   (section 8½).
3. Only **your** `.admin` (the one of the person who created the contest) and the training
   superadmins get in with a role. A judge, a staff member and a co-organizer need an **own**
   account of the contest (People › Accounts, section 3).
4. There is no exam-wide password change. A person who knows the training password of another
   person also gets in as that person here.
5. You can undo this: convert to own accounts (below). You cannot undo the conversion.

The wizard creates a shared contest only after you tick **☐ I understand**. While the contest stays
shared, the Home shows the item **Shared accounts**.

**Act on a shared participant.** In People › Accounts, a person who logs in with the training
account shows **🔗 training**. **Disable** blocks the person in this contest (the training account
continues to work on the training site). **Re-enable** undoes this. **Disqualify** removes the
person from the scoreboard. **Remove** blocks the person permanently: the person cannot come back
with the training account. When you create or reset an account here, the password **of this
contest** applies: the training password does not open that account in this contest any more.

**Convert to own accounts** (People › Accounts › the **🔗 Shared accounts** card):

1. **Preview the conversion.** Nothing is written. The preview counts who gets an account (the
   persons with a folder in the contest, an open session, a line in the access log or a
   registration), the teams, the team members who lose their login, and the warnings.
2. Confirm. Before the contest, tick **☐ I understand**. After the start, type the **contest id**.
   If the list changes between the preview and the confirmation (a person logged in), the screen
   shows the new preview and asks you to confirm again.
3. **Download the CSV** with the credentials immediately. The new passwords show only there and on
   the **Badges**.

What the conversion does:

- Each participant gets an own account with a **new** password. Only the name comes from the
  training site.
- Each **team** becomes **one** account (login `time-…`) with one password. The members cannot log
  in with their own accounts any more. A member who submitted becomes a disabled account, and the
  scoreboard row of that member stays.
- Your training `.admin` becomes an own `.admin` of the contest with a new password (the screen
  shows it).
- The registration closes and the roster goes to the archive.
- The history and the scoreboard stay. A person who logged in and did not submit now shows with
  zero on the scoreboard.
- A person who never entered the contest gets no account (add that person in ➕ Add).
- The training superadmins cannot get in to this contest any more.
- The open sessions continue. The option **log out the sessions** makes all participants log in
  again with the new password.

In the CLI: `moj-contest -c <id> users convert` (preview) and `users convert --apply --csv creds.csv`.

## 9. User template (enables all functions)

Paste it in the bulk load of *People › Accounts* (one line per account: `login nome`), or create
the accounts one by one with `moj contest -c <cid> users add <login> --name "<nome>"`:

```
juiz1.judge      Judge One
juiz2.judge      Judge Two
juiz3.judge      Judge Three (spare for the quorum of 2)
chefe.cjudge     Chief Judge
apoio1.staff     Print and balloons staff
sede1.cstaff     Site 1 chief (badges + reveal)
monitor1.mon     Monitor (answers clarifications)
```

Then: turn on **Manual verdict** (and adjust the **number of judges**) in Home › Rules. Give out
the generated passwords. Each person logs in on the SAME contest screen and sees the buttons of his
or her role.

## 9½. Training panel › Contests and who can create them

The administration panel of the Free Training (`/treino/admin/`, `.admin` account) has the
**🏆 Contests** tab. It lists the contests created with the interface, and it controls who can
create contests and problems.

**Who sees what.** The rule applies in the API, not only on the screen.

- A **super-admin** sees and operates the contests of all persons. A super-admin is a `.admin`
  account listed in `SUPERADMINS` in the `contests/treino/conf` file (logins separated by
  spaces). Only persons with access to the server edit this list. There is no screen for it.
- A **regular admin** sees his or her own contests and the contests of creators without an admin
  role (students and allowed monitors). A regular admin does not see the contest of another
  administrator. Remove, duplicate and export follow the same rule: a contest outside your scope
  responds "not found".

**List filters.** Search by name, id or owner. Filter by owner, mode and state (upcoming, in
progress, ended). Sort by creation date, start, name or owner. Check **only mine** to see only
what you created. The owner appears with photo, name and a link to the profile.

**Reserved id.** An id that starts with `icpc` belongs to the Maratona organization. Only a
super-admin can create a contest with this id. The wizard warns before, and the API refuses.

**Priority (Priority column).** The super-admin changes the priority of any contest directly in the table,
including **Super**, which jumps the whole queue. This is the only place to give or remove Super. The
wizard offers Super only to the super-admin, and a copy (**duplicate**) of a Super contest made by another
account starts as **Contest**. The other administrators only see the column: the admin of each contest
changes the other priorities in Central › Rules. Every change goes to the contest Audit log and to the
training trail (📜 Activity feed, action `contest-priority`). From the CLI: `moj contest priority <cid> <priority>`.

**Who can create contests and problems.** The same permission applies to creating contests and to
creating problems and collections in Problem Management. `.admin` accounts can always create
them. For the other accounts:

- **✅ Allowed**: type the login and an optional note, and click **✅ Allow**. The account must
  exist in the training. Each row shows the person, who allowed it and when.
- **⛔ Blocked**: the same, with **⛔ Block**. A block overrides the automatic threshold.
- **Automatic threshold** (*Auto-allow whoever solved ≥*): a person who solved at least N problems
  can create. Zero turns it off.

## 10. References

- [Judge manual](MANUAL-JUIZ.md): the operation of the Judge tab and of the chief judge.
- [Room staff manual](MANUAL-STAFF.md): printing, balloons, badges, reveal by site.
- [Competitor manual](MANUAL-CONTEST.md): what the student sees (give it out with the passwords).
- [Organizer tutorial](/treino/criar/tutorial.html): create the contest (wizard and CLI).
- [Competitor CLI](/contest/cli.html): submission from the terminal, with an offline mode.
