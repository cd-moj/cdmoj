<!-- i18n-source: MANUAL-ORGS-COLECOES.md blob:9aac199c01a6f43778c4f0e5f7bc9771264c685b -->
# Managing orgs and collections (manual for problem managers)

> **Translation note.** This manual is a translation of the Portuguese original. The command-line tools (`moj`, `moj-contest`, `moj-comp`) print their messages in Portuguese, and the command examples below are identical to the original.

This manual is for people who **create and organize problems** on MOJ: professors, teaching
assistants and organizers. It explains the two axes of organization (**org** and **collection**)
and what each one does. It also shows **how to operate each item in BOTH interfaces**: the web
(Problem Management) and the `moj` CLI. The two clients use the same API. Thus you can do any
operation from either side. Use the one that is more comfortable for you.

> The **format** of the metadata (what goes in `.moj-meta.json`, how the id is built) has its
> canonical, detailed description in [PACOTE.md](PACOTE.md) (sections 7–9). This manual is about **use**.

## The two axes, in 30 seconds

| | **ORG** | **COLLECTION** |
|---|---|---|
| Purpose | **Access**: who can see/edit the problem | **Grouping**: a label to browse/organize |
| How many per problem | **Exactly 1** (it is the prefix of the id `org#prob`) | **Many** (m:n): a problem can be in as many as you want |
| Does it give access? | **Yes**: an org member edits the problems of the org | **No**: it is only a label; it does not let anyone edit |
| Does it change the id? | Yes: the problem is `<org>#<prob>` | No |
| Example | `apc`, `obi-problems`, `mdp-2026-1` | `problemas-apc`, `Prova EDA1 2026/1`, `dificil` |

Golden rule: **the org decides WHO can change a problem; the collection decides HOW you find it.**
The two axes are orthogonal. Two problems from different orgs can be in the same collection. One
org can have problems in many collections.

Each user starts with an **implicit org that has the user's own login** (for example, `ana.silva`).
This org is always private. Your drafts stay there if you do not create another org.

---

## Part 1 — ORGs

### Create an org

An org usually represents a **course, class or competition** (for example, one for each semester of a course, or one for each olympiad). The name is **lowercase, with no spaces**, because it is the **prefix of the id** `<org>#<prob>` (`^[a-z0-9][a-z0-9._-]{1,63}$`). The *contest* id becomes a subdomain, not the org. To create an org, you need the **same permission** that you need to create a problem or a contest.

| Web (Problem Management) | CLI |
|---|---|
| In the **editor of a new problem**, at the top of the *Statement* tab, click **“+ new org”**. Or go to the **Orgs** tab and create it there. | `moj mkdir <org>`  · or `moj org create <org> [--public] [--members a,b] [--admins c]` |

The person who creates the org automatically becomes a **member and admin** of it. You **can save
a problem only inside an org**. For this reason, the editor asks you to create your first org
before it lets you save.

### Members and admins

- An org **member** **edits all the problems of the org**, including the private ones. This is the
  shared authorship model: the co-authors of a course are members of the same org.
- An org **admin** can also edit. In addition, an admin **manages members/admins** and the
  **public permission** (see below).

| Web | CLI |
|---|---|
| **Orgs** tab → select the org → manage members/admins. **Click the star** on the member chip (⭐ admin ↔ ☆ member) to **promote/demote**. ✕ removes the person from the org. The creator of the org is always an admin (you cannot demote the creator). The problem editor also has the **Org members** box (it adds a co-author to the org of that problem). | `moj share <org> <login>` (adds a member) · `moj org members <org> --add a,b --remove c --admins-add d --admins-remove e` |

> **Only the org** decides access to a **private** problem. Even a global MOJ `.admin` cannot see
> the content/package of a private problem of an org if the `.admin` is not a member. Thus,
> contests in preparation do not leak, by design.

### Who CAN become a member (validated since 2026-08-20)

MOJ no longer accepts just any text when you add a person to an org. MOJ checks each login that **enters** the org immediately.
This applies to members and admins, from the web, from `moj share` or from `moj org members --add`:

| Situation | Response |
|---|---|
| Invalid format (`Inv@lido`) | **422** `login_invalid` |
| No account in the training | **404** — *"Não existe conta no treino: 'fulano'"* (no account in the training: 'fulano') |
| The account exists, but it **cannot create problems** | **403** — *"'fulano' não pode criar problemas (motivo) — membro de org edita o acervo dela"* ('fulano' cannot create problems (reason) — an org member edits the org's problems) |

The criterion for "can create problems" is the **same** as for creating a problem or a contest. A
`.admin` account can always create. For other accounts, the list of authorized logins and the list
of blocked logins in the training admin panel decide. If the login is in neither list, the threshold
of solved problems applies. If MOJ refused your teaching assistant, the fix is to authorize the
assistant in the **🛡 Admin panel** of the training, section **Who can create contests and problems**.
Do not try to go around it through another screen.

The refusal is **atomic**. If you send five logins and one is invalid, **none** of them enters. With
`create`, the org is not even created. **Removal** does not validate anything: you can always
remove old invalid entries.

### Public permission (`public_allowed`): the anti-leak protection

Each org starts **private**: you **cannot publish** its problems in the Free Training. This is on
purpose. It is the protection against a leak of a contest in preparation. To let the problems of
an org become public, an **org admin** must **allow public problems in the org** (turn `public_allowed` on).

| Web | CLI |
|---|---|
| **Orgs** tab → the org → **Lock** column: click the status to switch between **allows public** (`public_allowed` on) and **private 🔒** (`public_allowed` off). | `moj org public <org> on`  /  `moj org public <org> off` |

> ⚠️ **Turning the public permission OFF UNPUBLISHES, in cascade,** all the public problems of that
> org. They become private immediately. Turn it on with care. Turn it off with even more care.

The **implicit org** (`<yourlogin>`) is **always private**. You cannot allow public problems in it: it
is your personal draft space. To publish, move the problem to an org that allows public problems.

### Delete an org

You can delete only an **empty** org (an org with no problems). MOJ never removes the implicit org.

| Web | CLI |
|---|---|
| **Orgs** tab → **delete org** (the button is active only if the org is empty). | `moj org rm <org>` |

### Move a draft to another org

The org is the prefix of the id. Thus, when you move a problem, **the id changes** (`orgA#p` →
`orgB#p`). This applies only to a problem that is **not public** (409 `is_public`). You can still
move a private problem that a contest already uses. You must be a member of **both** orgs.

| Web | CLI |
|---|---|
| In the problem list, the **“Move”** button (it shows only on your drafts). | `moj mv <id> <org-destino>` |

---

## Part 2 — COLLECTIONS

A collection is a **free label** that groups problems. It can have **spaces and accents** (for
example, `Prova EDA1 2026/1`, `Geometria`, `iniciantes`). A problem can be in **many** collections.
Collections are for: browsing in the Free Training, search filters, and the **random draw** of
problems when you create a contest. **A collection gives no access to anything.** It is only for
organization.

The collection registry is **curated**. To tag a problem with a collection, the collection must
**exist** (create the collection first). Each collection has an **owner** (the person who created it).

**A problem with no collection tagged stays in the org collection.** This is the collection with
the same name as the org (`grub` for the org `grub`), created together with the org. This applies
everywhere: in Problem Management, in the Free Training and in the random draw when you create a
contest. To take a problem out of the org collection, tag another collection.

### Create a collection

| Web | CLI |
|---|---|
| **Collections** tab of Problem Management → *new collection* field → **“+ Collection”**. (You can also create one from the collections panel inside the editor.) | `moj collection create "<nome livre>"` |

### Tag / untag a problem with a collection

| Web | CLI |
|---|---|
| In the problem **editor**, collections panel: select/clear the labels and click **Save**. | `moj collection add <id> "<nome>"`  ·  `moj collection remove <id> "<nome>"` |

### Browse and list

| Web | CLI |
|---|---|
| **Collections** tab (filter **“mine only”**; click the name to see the problems). In the **Free Training**, the explorer groups the collections by prefix and filters by text. | `moj collection ls`  ·  `moj collection show "<nome>"` |

### Rename / delete a collection

Only the collection **owner** (or a `.admin`) can rename or delete it. The operation re-tags the N
problems in the **background** (the server does the heavy work without blocking). The CLI
**follows the job until the end** and shows the progress.

| Web | CLI |
|---|---|
| **Collections** tab → rename/delete (owner/admin). A **progress banner** ("⏳ re-tag in progress: N/M") shows in the tab until the job ends. | `moj collection rename "<nome>" "<novo>"`  ·  `moj collection delete "<nome>"`  ·  `moj collection status` (follows the jobs) |

> Rename/delete does not change the **access** of any person (a collection is only a label). It
> only changes/removes the label on the problems.

---

## Permissions and pitfalls (the summary that prevents problems)

- **An org member sees and edits everything in the org**, including private problems. Co-author = member.
- **Private problems do not leak**, not even to a global `.admin`. The org membership decides access.
- **A collection does not give access.** If you put another person's problem in your collection,
  this does **not** give you permission to edit it. To edit it, you must be a member of its org.
- **Public status requires an org that allows it.** You can publish a problem only if the org has
  `public_allowed` on. Otherwise, the button/publish refuses.
- **Turning off the org public permission unpublishes in cascade.** Be careful with this setting.
- **Collection rename/delete is asynchronous.** It responds immediately and re-tags in the
  background. On the web, the Collections tab shows a progress banner. On the CLI, use `moj collection status`.
- **Moving a problem changes the id.** Old links/references to the old id stop working.

## Quick recipes

**Set up a course from zero (private):**
1. `moj mkdir eda1-2026` (or “+ new org” in the editor). The org starts private.
2. Create the problems inside it (they stay private, which is good for a contest).
3. `moj collection create "Prova 1 EDA1 2026/1"` and tag the contest problems with it, to
   organize/draw them.

**Open problems to the Free Training:**
1. An org admin allows public problems: `moj org public eda1-2026 on` (or the Orgs tab on the web).
2. Publish each problem: `moj publish eda1-2026#<prob>` (or the **make public** option in the editor, **Publishing** tab).
   The server validates + calibrates, and the problem shows in the Free Training.

**Share authorship with a colleague:**
- `moj share eda1-2026 colega.login` (or the **Org members** box in the editor). The colleague can
  then edit all the problems of the org.

## See also

- **[PACOTE.md](PACOTE.md)**: the canonical format (what goes in `.moj-meta.json`, the id, and
  sections 7 (ORG), 8 (COLLECTION) and 9 (ORG × COLLECTION)).
- **Step-by-step tutorials**: [Create problems with the CLI](/problemas/tutorial.html) and
  [Create and manage a contest](/treino/criar/tutorial.html).
- **[API.md](API.md)**: the `/orgs/*` and `/problems/collection*` routes, for people who automate.
