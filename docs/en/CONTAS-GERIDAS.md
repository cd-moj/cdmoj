<!-- i18n-source: CONTAS-GERIDAS.md blob:1fc6fa8f7dc76d01cd3e8e82743b9fd4e4ad0a6b -->
# Managed accounts (minors, without Telegram)

> **Translation note.** This manual is a translation of the Portuguese original. The command-line tools (`moj`, `moj-contest`, `moj-comp`) print their messages in Portuguese, and the command examples below are identical to the original.

A normal Free Training sign-up is confirmed through **Telegram**. This excludes people who
cannot have an account on the messenger, typically **minors**. The **managed account** solves
this. A **responsible** `.admin` creates it. It has no link to Telegram. It has privacy locks
that **are removed automatically at age 18**.

## The model in 30 seconds

| | Normal account | MANAGED account (minor) |
|---|---|---|
| Created via | web sign-up + Telegram | the **🧒 Managed accounts** tab of `/treino/admin/` |
| Password | by bot DM | **generated and shown ONCE** to the admin |
| Forgot the password | `/trocarsenha` in the bot | **only the admin** (🔑 in the tab) |
| Public profile | optional (default public) | **always private** (the server refuses to make it public) |
| Telegram | optional | **blocked** |
| At 18 | — | the locks **are removed automatically**: the user can link Telegram and open the profile |

The mark is in the user's `account.json`:

```json
"managed": { "by": "prof.admin", "note": "turma A, Escola X",
             "birthdate": "2011-03-14", "expires_at": null, "created_at": 1785000000 }
```

The system calculates **minor** from the birthdate on each access. Nothing is "switched" at 18;
the gates simply stop applying. The `managed` mark stays (for history and listing, with the
`18+` badge). The profile stays private until the user opens it.

## What the minor can and cannot do

- **Can**: everything in the training. Solve, submit, see their own profile and statistics,
  edit name/university/editor/photo, and change their own password (if they know the current one).
- **Cannot (until 18)**:
  - **make the profile public**. `profile_is_public` blocks this on the server. The account
    does not appear in the home page "Top 10" or in "Recently solved". Other users see the
    profile as the 🔒 lock (the same rule as a common private profile);
  - **link Telegram**. `POST /treino/telegram/link-start` returns 403
    `managed_minor`.
- **Expiration (optional)**: when `expires_at` is in the past, login returns 403
  `account_expired`. The message is in Portuguese: `Conta expirada — fale com o responsável que a criou`
  (account expired — talk to the person responsible who created it). To renew, edit or clear the date in the tab.

## Operation (🧒 Managed accounts tab of `/treino/admin/`)

- **➕ New account**: full name + **birthdate** (required), optional login
  (empty = generated from the name, `nome.sobrenome`, with dedup), free-text note, and optional expiration.
- **📥 Batch create**: one line per account in the format `Nome Completo;AAAA-MM-DD`, with
  a common note and expiration. The screen shows this model in the interface language
  (`Full Name;YYYY-MM-DD`). This is ideal for a class.
- **Credentials**: the response shows the **login + password of each created account, ONE
  time only**, with "📋 Copy all". You **cannot recover the password later**. Write it down or print it immediately. (The training has no label screen: `/contest/badges` refuses `contest=treino` on purpose, so that it does not dump the whole user base in clear text.)
- **Per account**: 🔑 new password (shown once; ends the sessions) · ✎ edit
  note/birthdate/expiration · ⏻ disable (sentinel password + ends the sessions) /
  ▶ enable (new password) · ✕ remove (archives in `.removed-users/`; submissions
  are kept).
- **Filters**: by text and **"only mine"** (accounts for which I am the person responsible).
- **Audit**: `managed-create/reset/update/remove` go to the audit log with the admin
  who did the action (📜 Activity tab).

## Through the API (same effect; `.admin` Bearer)

| Route | Use |
|---|---|
| `GET  /treino/admin/managed-users` | lists `{login,fullname,by,note,birthdate,minor,expires_at,disabled}` |
| `POST /treino/admin/managed-create` | `{users:[{fullname,birthdate,login?,note?,expires_at?}]}` (1..500) → `{created:[{login,password,…}], skipped}` |
| `POST /treino/admin/managed-reset` | `{login}` → new password (once) |
| `POST /treino/admin/managed-update` | `{login, note?, birthdate?, expires_at?\|null, disabled?}` |
| `POST /treino/admin/managed-remove` | `{login}` |

## Privacy and data (LGPD note)

- The only extra data stored is the **birthdate**. It is necessary for the automatic
  unlock at 18. The free-text note of the person responsible is also stored. Do not put
  sensitive data in the note. All admins can see it.
- The minor's profile is **invisible to the public by design** (a gate on the server, not in the
  UI). Statistics, photo, and history are visible only to the user and to admins.
- The password **is not stored in clear text in any new place** other than `account.json`
  (the standard model of the platform). It travels only in the create/reset response.

## For code maintainers

- Helpers: `managed_json` / `is_managed_minor` in `server/api/v1/lib/profile.sh`.
  `is_managed_minor` is the gate that `profile_is_public`, the POST of
  `/treino/profile`, and `link-start` use. An unreadable date is treated as a minor (fail-safe).
- The profile UI (`web/treino/perfil/perfil.js`) hides the Telegram link and locks the
  privacy checkbox when `GET /treino/profile` returns `managed.minor:true`.
- Collateral guard: `POST /contest/admin/users-set-password` **refuses `contest=treino`**
  (one POST would reset all the accounts of the platform).

## See also

- [`MANUAL-TREINO.md`](MANUAL-TREINO.md) — the student manual (normal sign-up, login).
- [`PERFIL.md`](PERFIL.md) — the public profile and the achievements.
- [`API.md`](API.md) — full contracts of the routes.
