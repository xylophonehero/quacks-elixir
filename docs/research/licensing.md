# Licensing: what Quacks must obey before it goes public (#76)

Research note, 2026-10-16. Research only: no app code is changed. ⚠️ = not verified
on a primary source, or the sources do not agree.

**This is not legal advice.** It is a summary of public sources, written by an agent.
Before a public launch or a commercial use (the WebinarGeek embed, #71), ask a lawyer
who knows German and Dutch IP law.

## TL;DR

- **Mechanics are free; expression is not.** Copyright does not protect a game's
  idea, rules or method of play (US: Copyright Office FL-108, 17 U.S.C. §102(b); EU:
  CJEU *SAS Institute* C-406/10 for functionality). It **does** protect the rule
  text, the card text, the art and the board graphics. The game name can be a
  **trademark**.
- **The publisher has said "no" to a digital Quacks before.** A Board Game Arena
  (BGA) adaptation stopped in 2021 because "the publisher has denied them the
  license" (§3.1). Thus a licence request is not likely to succeed, and an unlicensed
  public "Quacks of Quedlinburg" has a real takedown risk.
- **The repo is PUBLIC on GitHub now.** It contains verbatim fortune-card text, a
  photo of the player board, two BoardGameGeek photos and a crop of the Schmidt
  rulebook (§2). These are the largest risk today, larger than the app.
- **The app itself is mostly clean.** Own chip art or CC BY icons with credit, CC0
  sounds, own synthesis, an OFL font, MIT/Apache dependencies. The risks in the app
  are the **names** ("Quacks", "Quedlinburg", "Herb Witches", "Alchemists", card
  titles) and the **fortune-card text**.
- **Best route:** option 2, a **renamed and re-themed** public version (own name, own
  card text, own art), with the same mechanics. Until then, keep it at option 1
  (friends only, no indexing). The WebinarGeek embed is commercial use: do it only
  with the renamed version (or with a licence).
- **Verdicts:** Quacks **amber** (red if public as is), No Thanks! **amber**, Sushi
  Go! **amber**, Hearts family **green**, Codex **red**, Mage Wars **red** (§6).

---

## 1. The law in short

### 1.1 Copyright: idea versus expression

| What | Protected? | Source |
|---|---|---|
| The idea of the game, the rules as a system, the method of play, the scoring | No | US Copyright Office FL-108: "Copyright does not protect the idea for a game, its name or title, or the method or methods for playing it" (archived 2004 copy: https://webharvest.gov/peth04/20041015011900/http://copyright.gov/fls/fl108.pdf). 17 U.S.C. §102(b). *DaVinci Editrice v. Ziko Games* (S.D. Tex. 2016), summary: https://www.americanbar.org/groups/intellectual_property_law/resources/landslide/archive/why-videogame-rules-are-not-expression-protected-copyright-law/ |
| The functionality of software | No (EU) | CJEU C-406/10 *SAS Institute v World Programming*, 2 May 2012, summary: https://www.fieldfisher.com/en/insights/sas-institute-inc-v-world-programming-limited |
| The rule text (the words), card text, almanac text | Yes, if original | FL-108: "the text matter describing the rules of the game … may be registrable". *SAS*: manuals are protected "to the extent that they are … the expression of the intellectual creation of the author". |
| Art, board graphics, chip faces, box art, photos of components | Yes | FL-108: "pictorial matter appearing on the gameboard or container". |
| Short names and titles | Usually no copyright, but see trademark | FL-108 (names and titles). |

⚠️ FL-108 is now only on archive copies (the copyright.gov URL gives 404). The
principle is the same in the current Compendium; this note did not check the
Compendium text. ⚠️ German law (UrhG) is the most relevant for Schmidt. This note
did not find a German board-game case; the EU rule (*SAS*, Software and InfoSoc
Directives) is the nearest source.

### 1.2 Trademark

- A game name used as a brand can be a registered trademark. Schmidt's site notice
  says brands on its site are protected and "naming a brand does not mean it is
  unprotected" (https://www.schmidtspiele.de/site-notice.html).
- ⚠️ This note did **not** find the register entries for "Die Quacksalber von
  Quedlinburg" or "The Quacks of Quedlinburg" (DPMA, EUIPO, USPTO). The registers
  were not reachable from search. **Assume they are registered.** Nick: check
  https://register.dpma.de, https://euipo.europa.eu/eSearch and
  https://tmsearch.uspto.gov before a decision.
- EU trademark law applies to use "in the course of trade", that is "a commercial
  activity intended to obtain an economic advantage" (CJEU *Audi* referral summary:
  https://ipkitten.blogspot.com/2024/02/four-rings-on-car-grille-infringe-audis.html).
  A free hobby site is a weak case for the owner; a **WebinarGeek** embed is in the
  course of trade. Art. 14(1)(c) EUTMR allows **referential** use ("a fan game
  inspired by …") when it agrees with "honest practices" (Springer commentary:
  https://link.springer.com/article/10.1007/s40319-022-01182-x). ⚠️ Not tested for
  game titles.
- Precedent: *Scrabulous* (2008). Hasbro sued; Facebook blocked the app in the US
  and Canada. The makers changed the name and the look (Wordscraper, Lexulous), and
  Hasbro dropped the suit in December 2008. The same rules engine continued under a
  new name (https://www.nbcnews.com/news/amp/wbna28241658,
  https://www.chiefmarketer.com/hasbro-drops-suit-against-scrabulous-makers). This
  is the model for option 2.

---

## 2. Audit of this repo (branch `staging`, 2026-10-16)

The repo `xylophonehero/quacks-elixir` is **PUBLIC** (`gh repo view`). Anything in
git history is public, also after a delete, until the history is rewritten. GitHub:
forks and local copies "will still exist" after you make a repo private
(https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository).

### 2.1 In the app (what a player sees)

| Item | Where | Status | Risk |
|---|---|---|---|
| Name "Quacks" (title, PWA name) | `root.html.heex` `live_title`, `QuacksWeb.PwaController` (`Quacks`, `Quacks Staging`) | Short form of the trademark | **Amber**: the name says "this is that game". |
| "Quacks of Quedlinburg" | `final_components.ex:226` (share text) | Full title | **Red** for a public or commercial version. |
| Expansion names "The Herb Witches", "The Alchemists" | configure screen, `CONTEXT.md` | Product names of Schmidt | **Amber**. |
| Fortune-card **titles and text**, base game (24) and Alchemists (20) | `lib/quacks/rules/fortune.ex` | Verbatim: "North Star English edition" (fan transcription) and "Schmidt English card text" (the moduledoc says so) | **Red**: copied expression. Rewrite in own words. |
| Herb witch cards | `lib/quacks/rules/witches.ex` | Own short text (for example "Draw 6 chips from your bag…") | Green-amber: own words. The titles are short and descriptive. |
| Patient names (Nervousness, Ear worm, Carrot nose, …) | `lib/quacks/rules/alchemists.ex` | Names from the Alchemists box | **Amber**: a set of 8 invented names is maybe original expression ⚠️. Rename. |
| Ingredient names (cherry bomb, pumpkin, garden spider, toadstool, crow skull, mandrake, ghost's breath, hawkmoth, locoweed) | `lib/quacks/rules/books.ex`, `chips.ex` | Names from the game | Amber: single words, weak copyright, but they make the theme. Rename in option 2. |
| Ingredient-book effects | `books.ex` | Mechanics, own words ⚠️ (not compared with the almanac line by line) | Green (mechanics). |
| Chip icons | `priv/static/images/icons/` | game-icons.net CC BY 3.0 with credit in `#credits` and `docs/CREDITS.md`; own `crow-skull`, `mandrake`, `hawkmoth`, `coin`, `boom` | Green. CC BY 3.0 allows commercial use with credit (https://creativecommons.org/licenses/by/3.0/). |
| Board, pot, flask, die, test tubes | inline SVG in templates | Own drawing (CREDITS) | Green. ⚠️ The score track and pot layout copy the **numbers** of the board (mechanics), not its art. Keep the look own. |
| PWA icons (cauldron) | `priv/static/images/pwa/` | ⚠️ origin not written down; probably the CC BY `cauldron` icon | Add a row to `CREDITS.md`. |
| `logo.svg` | `priv/static/images/` | Phoenix scaffold logo, not used | Delete. |
| Sounds | `priv/static/sounds/`, `LICENSES.md` | CC0 (Kenney, OpenGameArt, freesound) and own synthesis | Green (Kenney: "public domain licensed (CC0)", commercial use allowed, https://kenney.nl/support). ⚠️ freesound parts are from the lossy previews; `LICENSES.md` already says so. |
| Font Kalam | Google Fonts CDN (`root.html.heex`) | SIL OFL (https://github.com/google/fonts/tree/main/ofl/kalam) | Licence green. **GDPR amber**: loading from Google sends the visitor's IP to Google without consent. LG München I, 3 O 17493/20, 20 Jan 2022: €100 damages (https://www.gesetze-bayern.de/Content/Document/Y-300-Z-GRURRS-B-2022-N-612). Self-host the font. |
| Heroicons | dep | MIT | Green. |

### 2.2 In the repo only (docs, not served)

| Item | Status | Risk |
|---|---|---|
| `docs/assets/player-board-reference.jpg` | Photo or scan of the real player board (2053×1864, Photoshop CS6 EXIF 2021) | **Red**: publisher art, public. |
| `docs/assets/scoring-track-bgg4953930.jpg`, `scoring-track-bgg8807552-compare.jpg` | BoardGameGeek user photos (`rat-tails.md` §sources) | **Red**: third-party copyright (uploader and publisher art). |
| `docs/assets/scoring-track-rulebook-p3.jpg` | Crop of the Schmidt rulebook PDF | **Red**: Schmidt copyright. |
| `docs/research/rulebook.md`, `herb-witches.md`, `alchemists*.md`, `alchemists-fortune-cards.md`, `ingredient-sets-and-customisation.md`, `books-audit.md` | Rules notes with quotes, full fortune-card text and almanac text from the rulebooks | **Amber**: rules summaries are fine; long verbatim quotes and the full card lists are copied expression. |
| `docs/assets/*.png` screenshots | Own app screenshots | Green (they show the "Quacks" name). |
| `docs/assets/candidates/*.svg` | Icon candidates from game-icons and others (`art-assets.md`) | Green-amber: check each one has its licence in `art-assets.md`. |

### 2.3 Code licence and dependencies

- **No `LICENSE` file.** Then "the default copyright laws apply … no one may
  reproduce, distribute, or create derivative works" (GitHub docs above). Others can
  only view and fork on GitHub. That is a valid choice. If Nick wants others to
  re-use the engine, add MIT or Apache-2.0, but the licence then covers only **our**
  code, not the Quacks text or names.
- **Dependencies** (from `deps/*/hex_metadata.config`): all MIT or Apache-2.0
  (Phoenix, LiveView, Bandit, Req, Jason, Plug, Telemetry, …). Both allow commercial
  use; Apache-2.0 needs the licence and NOTICE kept in a redistribution (a Fly
  release image is a redistribution only if we give it to others ⚠️). `daisyui` is
  still in `deps/` but not in `mix.exs` (removed; run `mix deps.clean daisyui
  --unlock` sometime).

---

## 3. Precedents

### 3.1 Quacks itself

- **BGA: licence refused.** The repo `TacoV/TheQuacksOfQuedlinburg`, "Code for the
  Board Game Arena adaptation of The Quacks Of Quedlinburg", says: "the publisher has
  denied them the license, therefore, this project will be discontinued." Last push
  2021-05-14, archived 2023-06-15 (https://github.com/TacoV/TheQuacksOfQuedlinburg,
  `gh api`). ⚠️ It does not say which publisher (Schmidt or the English licensee).
- **Not on BGA.** A fan request on the BGA forum (22 Mar 2021) got no official answer
  (https://forum.boardgamearena.com/viewtopic.php?t=20262). ⚠️ The BGA game page
  gave HTTP 500 when this note was written; no listing was found.
- **Tabletopia has it**, with "Schmidt Spiele" in the credits and a link to the
  Schmidt shop, also The Herb Witches (https://tabletopia.com/games/the-quacks-of-quedlinburg,
  https://tabletopia.com/games/the-quacks-of-quedlinburg-the-herb-witches). The page
  does not say "licensed" ⚠️, but the publisher link suggests a deal. Thus Schmidt
  **has** an online partner, and wants to control online versions.
- **No official app found** (App Store, Steam, Wikipedia lists none:
  https://en.wikipedia.org/wiki/The_Quacks_of_Quedlinburg). ⚠️ Absence is not proof.
- **Rights holders:** Schmidt Spiele (Berlin, original 2018, art Dennis Lohausen).
  English: North Star Games first, now **CMYK** (Wikipedia; Amazon "CMYK The Quacks
  of Quedlinburg"). Other licensees: 999 Games, Devir, and others (Wikipedia).
- **No fan or digital policy** found for Schmidt, North Star or CMYK. Schmidt's site
  notice forbids copying of its graphics, audio and text "without written permission"
  (https://www.schmidtspiele.de/site-notice.html).

### 3.2 Platforms

- **Board Game Arena** gets a licence for every commercial game: "the copyright
  owners must first grant a license/authorisation", and without the publisher "your
  game will remain private indefinitely". Public-domain games need no licence
  (https://en.doc.boardgamearena.com/BGA_Game_licences). The BGA licence template is
  "free of charge" and the licensor can end it "forthwith"
  (https://en.doc.boardgamearena.com/images/e/e0/BGA_TC_Pub_en.pdf).
- **Licensed is not permanent.** BGA removed *Dominion* when Rio Grande and Donald X.
  Vaccarino released their own app (https://en.boardgamearena.com/news?id=77, ⚠️ year
  2012 not on the page).
- **Yucata** says it is non-commercial and funded by donations, and lists the
  publisher of each game (https://www.yucata.de/). ⚠️ No public statement of its
  licence terms found.
- **Fan takedowns:** *Scrabulous* (§1.2). FFG sent NetrunnerDB a cease-and-desist
  (BGG thread, https://boardgamegeek.com/thread/1234809/netrunnerdb-cease-and-desist/page/10,
  ⚠️ forum source). Sirlin asked for the removal of a public Codex Tabletop Simulator
  module (⚠️ forum memory, §6).

---

## 4. Options

| Option | What | Risk | Cost |
|---|---|---|---|
| 1. Private / friends only | Room codes only, `robots.txt` `Disallow: /`, `noindex`, no public link, no "Quedlinburg" in the title, no listing on BGG or socials | Low. Not "safe" in law (copying is copying), but no economic damage and hard to find. | Very small (§5 items 1–3). |
| 2. Renamed, re-themed public version | Own name (not "Quacks"), own ingredient, card and patient names, own card text, own art (most is own already), a "inspired by" credit with no logo | Low-medium. Mechanics are free (§1.1); Scrabulous shows the path. ⚠️ A very close copy of the "feel" can still give a claim under unfair competition (German UWG §4 Nr. 3, imitation) — not researched. | Medium: a rename pass on text and names. |
| 3. Licence | Write to Schmidt Spiele GmbH, Lahnstraße 21, 12055 Berlin, info@schmidtspiele.de, +49 30 68 39 02 0 (site notice); for English, CMYK. Ask for a non-commercial web licence. | Low if granted. | Likely **no** (§3.1, Tabletopia already, BGA refused). Asking also tells them we exist. |

**WebinarGeek embed (#71)** is commercial: a company shows the game to its webinar
audience to make its product better. Then (1) trademark use is "in the course of
trade" (§1.2); (2) a free-hobby argument stops; (3) the damage claim gets larger
(lost licence fee); (4) WebinarGeek (not only Nick) becomes a party; (5) GDPR becomes
WebinarGeek's problem too (Google Fonts, §2.1). Do #71 **only** with option 2 or 3,
and ask WebinarGeek's legal contact first. ⚠️ The CC BY icons and CC0 sounds are
fine for commercial use; Kalam (OFL) is fine.

---

## 5. Checklist for Quacks before it goes public

Order = most risk first.

1. **Remove publisher and third-party images from the public repo and its history**:
   `docs/assets/player-board-reference.jpg`, `scoring-track-bgg4953930.jpg`,
   `scoring-track-bgg8807552-compare.jpg`, `scoring-track-rulebook-p3.jpg`. Keep them
   local or in a private repo. Rewrite history (`git filter-repo`) **or** make the
   repo private (forks stay, §2). Nick decides.
2. **Rewrite the fortune cards in own words** (`lib/quacks/rules/fortune.ex`, 44
   cards): new titles, new text, same effect. Then remove the full verbatim card
   lists from `docs/research/` (or move them to a private place) and keep only own
   summaries and links to the official PDFs.
3. **Choose a new name** and use it in `live_title`, `PwaController`, the manifest,
   `final_components.ex` share text, the Fly app hostnames that show to players, and
   the README. No "Quacks", "Quacksalber" or "Quedlinburg". ⚠️ Check the new name in
   DPMA/EUIPO/USPTO first.
4. **Rename the theme words**: expansions ("The Herb Witches", "The Alchemists"),
   the 8 patients, the ingredient names, "fortune teller", "rat tails" if Nick wants a
   clean theme. Mechanics (bag, pot, explosion threshold, droplet, rubies) stay.
5. **Self-host the Kalam font** (OFL allows it) and remove the Google Fonts links
   (GDPR, §2.1).
6. Until 1–4 are done: `robots.txt` → `User-agent: *` / `Disallow: /`, add
   `<meta name="robots" content="noindex">`, share only by link.
7. Add a short **disclaimer** in the footer: "A fan project. Not made or endorsed by
   any publisher. Inspired by a bag-building game by Wolfgang Warsch." ⚠️ A
   disclaimer does not fix copying; it helps against confusion.
8. **Credits**: add the PWA icon source to `docs/CREDITS.md`; delete the unused
   `priv/static/images/logo.svg`.
9. **Sounds**: build the freesound parts again from the original files before a
   public launch (already in `LICENSES.md`).
10. **Code licence**: decide (none = all rights reserved, or MIT). Write in the README
    that the licence covers our code only.
11. **#71**: only after 1–5, and after WebinarGeek legal says yes.

---

## 6. Per-game verdicts

| Game | Verdict | Why | Sources |
|---|---|---|---|
| **The Quacks of Quedlinburg** | **Amber** (as is and public: **red**) | Mechanics free; names, card text and board photos are not. Publisher refused BGA; Tabletopia partner exists. Green-ish after the §5 checklist (renamed). | §3.1 |
| **No Thanks!** (Thorsten Gimmler / Amigo) | **Amber** | Licensed on BGA ("No Thanks! is now in beta", Amigo approved, 2021: https://forum.boardgamearena.com/viewtopic.php?p=80365, https://en.boardgamearena.com/news?id=503). Rules are tiny and fully mechanical; the components are numbered cards 3–35 and chips, no art needed. A re-named version with own art is low risk. Amigo licensed BGA, so a licence request is possible. ⚠️ Name is likely a trademark. | BGA |
| **Sushi Go!** (Phil Walker-Harding / Gamewright) | **Amber** | Mechanics free (draft and set scoring), but the whole appeal is the art and the dish names. BGA has a rules page (https://be.doc.boardgamearena.com/Gamehelpsushigo) ⚠️ licence not stated; an official iOS app existed (Lummox Labs, 2016, https://www.pocketgamer.com/sushi-go/). An official digital version makes enforcement more likely. Do only re-themed (own food or theme, own art, own name). | as cited |
| **Hearts and traditional card games** | **Green** | Public-domain games need no licence (BGA rule above). Use own card faces or a checked public-domain set. ⚠️ Byron Knoll's "CC0" deck has disputed provenance (https://opengameart.org/content/playing-cards-vector-png); simple own faces (number + suit pips) are the safest. Avoid "Bicycle" and other brand backs. | as cited |
| **Codex** (Sirlin Games) | **Red** | Hundreds of unique cards: text and art are the game. Sirlin wants control of digital versions (official Tabletopia: https://forums.sirlingames.com/t/digital-version-of-codex/301; a TTS module was asked to be removed, ⚠️ forum memory: https://forums.sirlingames.com/t/tabletop-simulator/3029?page=2; a fan app waits for an answer: https://forums.sirlingames.com/t/codex-on-ios/2701 ⚠️). Sirlin is reworking Codex on Patreon in 2024–2025 with an official Screentop version (https://forums.sirlingames.com/t/big-codex-news-new-stuff-coming-on-patreon/9060). Only with written permission; Sirlin is a small, reachable publisher. | as cited |
| **Mage Wars** (Arcane Wonders) | **Red** | Card-driven; spell text and art are the game. A Vassal module exists (https://vassalengine.org/wiki/Module:Mage_Wars) ⚠️ its permission status is unknown. No policy found. Only with a licence. | as cited |

---

## 7. Open questions for Nick

- Private repo or history rewrite (§5 item 1)?
- A new name: ask the agents for 10 candidates and a trademark check?
- Ask Schmidt anyway (one polite e-mail), or not at all?
- #71: who at WebinarGeek decides on legal risk?
