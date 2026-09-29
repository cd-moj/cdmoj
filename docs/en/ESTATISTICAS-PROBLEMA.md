<!-- i18n-source: ESTATISTICAS-PROBLEMA.md blob:cf1f671fce64d14299108da488a974cbb9164f18 -->
# Problem statistics: how each metric is computed

> **Translation note.** This manual is a translation of the Portuguese original. The command-line tools (`moj`, `moj-contest`, `moj-comp`) print their messages in Portuguese, and the command examples below are identical to the original.

This document explains, section by section, how the **Problem statistics** page of
Free Training (`/treino/problema/stats/?id=<problema>`) calculates what it shows. It includes the
statistical decisions and the honest limitations of each number. The source of truth is the
endpoint `GET /treino/problem-stats` (full contract in [API.md](API.md)). This page
describes the **semantics**.

## Where the data comes from

Each training account keeps its own submission history (1 line per submission:
problem, **language**, **verdict**, and **time** in epoch). The statistics of a problem
are the aggregation of all the lines of all the users for that problem. They come **only from Free
Training**: submissions made in class contests are not included.

- **Only public problems** have statistics. A private problem returns 404: a contest in
  preparation does not leak, not even by its existence.
- The result is in a **per-event cache**. The system regenerates it when there is a new
  submission (each judgment touches a global marker). During a burst of submissions, it regenerates
  the cache at most once every 2 minutes. Without a new submission, the number does not change.
  So the cache is valid indefinitely.
- **Verdicts** are grouped into the canonical families: `Accepted`, `Wrong Answer`,
  `Time Limit Exceeded`, `Runtime Error`, `Compilation Error`, and `Outro` (other: anything that
  matches no known prefix). "Accepted" = a verdict that starts with `Accepted`
  (this includes `Accepted,100p` etc.).
- **Languages** are canonicalized before any count: lowercase, the C++ variants
  (`CC`/`CXX`/`C++`/`HPP`) become `cpp`, `H` becomes `c`, and the legacy `PY3`/`PY2` become
  `py`. So a `.py3` submission and a `.py` submission count in the same language.

## Summary

| Metric | Calculation |
|---|---|
| **submissions** | total number of history lines of the problem |
| **attempted** | **distinct** users with ≥1 submission |
| **solved** | distinct users with ≥1 accepted submission |
| **solve it (per user)** | solved ÷ attempted — the **per-user rate** |
| **per-submission rate** | accepted submissions ÷ total submissions — measures how much people fail while trying; **it does not define the difficulty** |
| **subs / user** | submissions ÷ attempted |
| **difficulty** | label from the **per-user rate**: ≥90% very easy · ≥70% easy · ≥50% medium · <50% hard · no users who attempted = new |
| **dirt** | (submissions of the solvers up to the 1st AC − ACs) ÷ (those submissions). It is the ICPC *resolver* metric, the same one as in the contest statistics. High = the problem punishes mistakes. |

The difficulty has **a single source** in the system (`lib/difficulty.sh` on the server,
`shared/difficulty.js` on the web). The search, the suggestion, the profile, the contest draw, and this
page read the same key. Before, this page labeled by the per-submission rate. As a result, the same
problem showed "easy" in the search and "hard" here (issue #30). The per-submission rate stays on the
page as a number, with the correct name.

## Difficulty percentile against the archive

The "**X% of the archive is easier than this**" card compares the **per-user success rate**
(solved ÷ attempted) of this problem with the rate of all the public training problems
(the same base as the problem list).

- **Eligibility**: only problems with **≥5 users who attempted** enter the scale. The percentile
  shows only if the eligible cohort has **≥10** problems.
- **Ranking with Laplace smoothing**: the position does not use the raw rate. It uses
  `(resolveram + 1) ÷ (tentaram + 2)`, that is, (solved + 1) ÷ (attempted + 2). The reason is empirical: a large fraction of the archive
  has 100% success in very small cohorts (5–10 users who attempted). Tied at the top, these problems
  crushed the easy end. Without the smoothing, even a "hello world" with 33/34 showed "harder
  than 45% of the archive", because 8/8 counted as easier than 33/34. With the
  smoothing, 8/8 becomes 0.90 and goes **below** 33/34 = 0.944, as intuition says.
  The remaining ties use *midrank* (half counts above, half below).
- The card **tooltip** shows the **raw** rate of the problem and the size of the cohort. The
  smoothed rate is only an internal scale for ordering.

## Facts

- **first/last submission** — the earliest/latest time in the history of the problem.
- **first to solve** — the user whose first accepted submission has the earliest time.
  **Privacy**: the name/login shows only if the account profile is public. If not, the card
  shows only the date.
- **peak day** — the day (Brasília time zone) with the most submissions.
- **median tries until accept** — see "How they solve" below.
- **median time to solve** — same.

## Timeline

- **Submissions per month** — histogram of all the submissions since the first one, in calendar
  months (Brasília time zone).
- **Cumulative solvers** — for each user who solved, the system takes the time of their
  **first accept**. The curve is the cumulative count of these times (when the problem
  "became popular").
- **Cumulative acceptance rate (%)** — running sum of accepted ÷ running sum of
  submissions, month by month (the "historical up to here" rate). It shows if the problem became
  easier to get right over time, e.g. after a statement was clarified.

## Activity calendar

- All days/hours use the **America/Sao_Paulo** time zone. The history stores UTC; the
  conversion happens in the aggregation.
- **Annual heatmap** (GitHub style): submissions per day. The selector switches between years. The
  "**Σ all**" tab sums all the years **by day of the year** and projects them onto a leap year (so that
  29 February shows). This is the **seasonality** view: the busy periods of the school calendar
  stand out.
- **Hour of day × weekday** (punchcard): submissions per cell (Sun–Sat × 0–23h),
  all years summed.

## How they solve

- **Verdicts** — donut chart with the canonical families (count per submission).
- **Distinct solvers by language** — distinct users with an accept in that
  language (a user who solved in C and later in Python counts in both). Unrecognized
  extensions are merged into "Others (unrecognized ext.)".
- **Acceptance rate by language** — accepted ÷ submissions of that language. Only
  languages with **≥3 submissions** show (fewer than that is noise).
- **Submissions until first accept** — for each user who solved, how many submissions they
  made up to (and including) the first accepted one. Distribution in the buckets `1 · 2 · 3 · 4–5 ·
  6–10 · >10`, and the median in the Facts card. Users who never solved are not included (they are
  `tentaram − resolveram`, that is, attempted − solved).
- **Time from first try to accept** — per solver, the interval between their
  first submission and their first accept, in the buckets `<1h · 1h–1d · 1d–1sem · >1sem`
  (median in Facts). It measures persistence: a problem can be "hard to get right on the
  first try" but fast to master, or the opposite.
- **Editors of those who solved** — the editor **declared in the profile** of the solvers
  (users who do not declare one do not count; it is a self-portrait, not telemetry).

## Running time (accepted submissions)

- The "time" of an accepted submission is the time of its **slowest test**. This is the same
  definition as Kattis (it is the number that the time limit actually checks).
- It comes from the structured record that the judge writes for each submission (times per test,
  measured on the judging machine). **Coverage**: only submissions judged on the current platform.
  Submissions migrated from the old MOJ have no measurement. So the distribution starts small
  and **grows by itself** with each new judgment. The page shows how many submissions it covers.
- **Distribution** — histogram with "round" buckets (step 1/2/5×10ᵏ, ~10 buckets).
- **Fastest by language** — the minimum per language (short bar = faster).
- ⚠ Be careful when you compare languages. The times come from different submissions, from
  possibly different judge machines. The MOJ time limit is **per language** (calibrated with the
  author's solutions, or set by the author with `TLOVERRIDE` in the package conf, which overrides the
  calibrated value). The comparison here is illustrative, not a controlled benchmark.

---

Endpoint contract (fields and formats): [API.md](API.md), route `/treino/problem-stats`.
The display of verdicts follows the central policy of the platform (single source
`lib/verdict.sh` — verdicts are never translated).
