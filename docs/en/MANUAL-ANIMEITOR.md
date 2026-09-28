<!-- i18n-source: MANUAL-ANIMEITOR.md blob:cc164fe430e20209a05f71d7e2a12ed0dc81e3a0 -->
# MOJ: Big-screen manual (`.animeitor`)

> **Translation note.** This manual is a translation of the Portuguese original. The command-line tools (`moj`, `moj-contest`, `moj-comp`) print their messages in Portuguese, and the command examples below are identical to the original.

This manual is for the person who **operates the big screen** of a contest on MOJ: the scoreboard on
the projector, the photos and music that animate the comeback, and the reveal ceremony.

> **Web tutorial with screenshots** (PT/EN/ES): `/contest/ajuda/animeitor.html`. To open it, click
> **📖 How this role works** on the big-screen page.
> **Technical document**: the integration through the Animeitor API is in [ANIMEITOR.md](ANIMEITOR.md). The
> legacy package (BOCA format) is in [WEBCAST.md](WEBCAST.md).

## How the role works

The role comes from the **login suffix**: an account that ends in `.animeitor` is the big-screen desk.
The administrator creates it (panel **People › Accounts**). Nobody becomes `.animeitor` through
self-registration.

The account feeds the big screen with three things: the **scoreboard** (MOJ sends it to the Animeitor
through the API — see the 📡 section below), the team **photos** and the team **music**. The account is
**not** in the scoreboard, the team list, the statistics, the balloons or the badges. It is not a
competitor.

The **administrator opens the same page with the same powers**, from the *🎥 Big screen (Animeitor)*
card on the **Home** panel, or from the link in *Event › Teams*. In a contest with shared users
(`USERS_FROM`), this is the **only** way to upload a photo or music.

## Tabs that you see

| Tab | What it is for |
|---|---|
| **Score** | The scoreboard, **always unfrozen** — also before the contest starts. This is the purpose of the role: the person who animates the comeback must see the real standings. |
| **Animeitor** | Your desk: 📡 the push to the Animeitor (scoreboards, sites, feeder, check, reveleitor), the team photos and music and, collapsed, the legacy streaming keys. |
| **Statistics** | Contest numbers (submissions per problem, languages, timeline) — good material for the breaks. |
| **Reveal** | The **experimental MOJ** ceremony (see the warning below). It is available to you at **any** time, so you can rehearse before the audience arrives. |
| **Logout** | Ends the session. |

## ⚠ The official ceremony is the Animeitor, not the MOJ page

The page `/contest/score/reveal.html` (button **Reveal**) is **EXPERIMENTAL**. Use it for a
rehearsal, for a small site, or as plan B if you cannot set up the Animeitor. The official
ceremony of an event runs on the **Animeitor, by Emílio Wuerges** — the system that this whole role
exists to feed.

The official flow is the **📡 Animeitor (big screen)** section of your desk. MOJ **pushes** the event,
the scoreboards, the submissions and the clock to the Animeitor server, and the reveal of each site
comes from there. The Animeitor animates the comeback and keeps the freeze until the reveal time.

## 📡 Animeitor through the API (the current way)

1. **Connection.** MOJ already has **its own key on the Animeitor** (the *MOJ key*). The page shows
   "MOJ key — … there is nothing to configure". The key never appears on the page. If your event uses a
   different Animeitor server, or if you received a key of your own, open "use your own key" and save
   the user and the token. Your key has priority over the MOJ key. To go back, click "delete it and use
   the MOJ key". The MOJ key works only on the default server.
2. **MOJ public URL.** The big screen fetches the photo and the music of each team from this address.
   Check it.
3. **Scoreboards and sites.** MOJ proposes the overall scoreboard, one per cohort and one per country,
   with the sites. Adjust the names and the medals, then save. A single-site contest gets the site
   `Geral` (without a site, there is no reveal link).
4. Click **📡 publish to the big screen** and **▶ start the feeder** (the clock every second and the
   submissions every 2 s). The event name is the contest id. MOJ refuses a name that already belongs to
   another MOJ contest.
5. **Check.** MOJ asks the Animeitor, site by site, if it has **all** the submissions, with the correct
   answer. MOJ does this automatically every 5 minutes during the contest and, after the end, until the
   **final check**. MOJ automatically resends anything that is missing or different. The "Check" line of
   the status shows the last result. **🔎 check now** runs the check immediately. "✓ VALIDATED" means
   that the contest is over for all sites, nothing is being judged, and the Animeitor has everything.
   Runs of teams that are outside every site are not part of the check (the page shows how many).
6. **🎬 release the reveal links to the sites.** Before the release, the desk runs the check and shows
   the result in the confirmation question. Then each site chief (and each staff member) sees the link
   of their own site, **with the check seal** ("✓ Validated", "Checked" or "⚠"). The link shows the
   answers after the freeze. ⚠ Treat it as a password.

## 🎥 Streaming keys (legacy)

The package in the BOCA format, which the old Animeitor fetched by key, is still on the desk, collapsed.

Each key becomes a **URL**. The Animeitor system (or another compatible display) fetches it in a loop
and receives the scoreboard package. Each key declares **which** scoreboard it serves: the overall one,
or the one of a specific cohort when the contest has guest teams.

1. Select the scoreboard, give the key a label (`telão principal`, `transmissão YouTube`) and create it.
2. **copy** puts the URL on the clipboard. **test** opens it, so you can make sure that the package comes.
3. The table shows **how many fetches** the key received and the **last access with IP**. This is how
   you know that the projector is really connected.

> ⚠ **The key opens the UNFROZEN scoreboard, without login.** A person with the URL sees the real
> standings during the contest. Treat it as a password: use one key per screen and **revoke all keys
> after the event**. Revocation is immediate (the key starts to answer 404, and MOJ records the attempt).

## 📷 Team photos and ♪ music

Each team can have a **photo** (it appears when the team solves a problem) and an **mp3** (it plays at
that moment). The gallery opens on the **⚠ To do** filter — exactly the teams that still have no photo
or no music.

- **⬆ Bulk upload** is the fast way: drag dozens of files. The **file name is the team
  login** (`time-alfa.jpg`, `time-alfa.mp3`). You can send photos and music together.
- The server converts and resizes the **photo** (webp + thumbnail). The **music** stays as it
  was sent and must be a **real mp3** (up to 15 MB). The server checks the file, not the extension.
- **⬇ Download package (.zip)**: everything in one file (photos, music and a CSV of the teams). Give
  this file to the person who operates the display.
- The **site chiefs** (`.cstaff`) upload the photos **of their own site**. In a contest with many sites,
  let them collect the photos locally. Then you only check the to-do list.

### The DEFAULT photo and music

A team without a photo does not break the show: MOJ answers with the **contest default** (and the same
for the music). The card at the top of the gallery changes this default — for example, an image with
the event identity, or a jingle — or goes back to the MOJ factory default. **Only you and the
administrator** can change the default.

In the `.zip` package, MOJ copies the default photo for each team (it is small). The default music goes
**once**, at the root (megabytes × a thousand teams is too much).

### In a 🕵️ SUPER SECRET contest

The gallery works the same way. Photos and music stay visible to the people who are logged in to the
contest (big screen, site, administrator) — MOJ fetches them with **your session**. A person who is not
logged in does not see or hear anything, which is the purpose of the secret mode. The only difference
that you notice is on ♪: the browser downloads the whole track before it plays (the button shows
**⏳**), so a large music file takes some seconds to start. If you operate the big screen in this mode,
press ♪ once on each track before the contest. The second time, it plays immediately.

> If the photos show as blank in a secret contest, the server is up to date but the browser has the old
> version of the page in its cache. Reload with Ctrl+Shift+R.

## Dress rehearsal: the day before and the warm-up

Many contests run a **warm-up** before the official contest — same room, same accounts, same address.
It is the dress rehearsal of the room and, thus, of the big screen. The scoreboard fills with real
submissions, so this is the time to aim the projector, run the webcast key on the Animeitor **for
real**, and see the photos and the music come up on the wall. A big screen that you tested only with an
empty scoreboard is a big screen that you did not test.

> Nothing that you set up is lost when the warm-up is promoted to the official contest: **keys, photos,
> music and the defaults** are contest configuration, not round data. What MOJ archives is the round —
> its scoreboard and its submissions, which stay available as a closed round.

The checklist for the day before, in order:

1. Check the **connection** (the MOJ key or your own), **publish**, and start the **feeder**. Open the
   public link of each scoreboard on the computer that will project.
2. Open the gallery on **⚠ To do** and chase the missing photos (ask the site chiefs).
3. Set the **default photo and music** with the event identity.
4. Download the **.zip** and keep it on the show computer as plan B.
5. **Rehearse** the reveal page and test the sound on the room audio.
6. During the **warm-up**: put the real screen on the wall and watch it fill — photos, music,
   scoreboard and the **Check** line in agreement.
7. At the ceremony time: wait for **✓ VALIDATED**, then **release the reveal links** to the sites.
8. If you used legacy streaming keys: **revoke all of them** after the event.

## What `.animeitor` does NOT do

| Attempt | Answer |
|---|---|
| Submit a solution / see a statement | Refused (the account does not compete) |
| Print queue, balloons, competitor file | Refused (these belong to `.staff`) |
| Credential badges (passwords) | Refused (these belong to `.cstaff`) |
| Answer a clarification / publish news | Refused |
| Photo or music of a ROLE account (staff, judge…) | Refused — roles are not teams |
| Any administration page | Refused |

> ⚠ **Two differences that surprise people**: unlike the room staff, `.animeitor` does **not** see
> contest documents before the start, and does **not** see an archived round that is not published. If
> you need the problem set to prepare the screen, ask the administrator to publish it.

## Summary table: big screen × site

| Action | `.animeitor` | `.cstaff` (site) | `.staff` (room) |
|---|:---:|:---:|:---:|
| See the photo/music gallery | All teams | Only the site | Only the site |
| Upload/replace/remove a photo and music | Yes | Yes (only the site) | **No** |
| Download the `.zip` package | Complete | Limited to the site | **No** |
| Change the contest **default** photo/music | **Yes** | No | No |
| Publish to the Animeitor, feeder, **check** | **Yes** | No | No |
| Release the reveal links | **Yes** | Receives the link of the site, with the check seal | Same |
| See/create/revoke **webcast keys** (legacy) | **Yes** | No | No |
| Scoreboard | Always unfrozen | Frozen | Frozen |
| Statistics | Yes | No | No |

## Pointers

- **[ANIMEITOR.md](ANIMEITOR.md)**: the integration through the API (MOJ key, scoreboards/sites, feeder,
  check, reveleitor) and the technical decisions.
- **[WEBCAST.md](WEBCAST.md)**: the protocol of the legacy package (BOCA format).
- **[MANUAL-STAFF.md](MANUAL-STAFF.md)**: the room staff and the site chief — the people who share the
  big-screen page with you.
- **[MANUAL-ADMIN.md](MANUAL-ADMIN.md)**: the organizer — the person who creates your account and
  publishes the documents.
