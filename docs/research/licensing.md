# Licensing: what Quacks must comply with before going public

Research date: 2026-10-15. Issue #76. Related: #71 (embed in WebinarGeek).
**This is research, not legal advice.** It is what a developer can find in public sources in one evening. Before a public launch, and always before any commercial use, ask a lawyer (Dutch or German IP law) or the publisher.
Tags: **[R]** = read in this repo. **[S]** = from a source (numbered list in §10). **[E]** = an estimate or an inference. ⚠️ = could not be verified.

Note on the sources: web pages could not be opened from this session (the proxy refused boardgamearena.com, BGG, Wikipedia, the Sirlin forum, schmidtspiele.de and others). Every [S] claim comes from search-result text with its URL. Each claim that carries legal weight should be checked on its page before anyone relies on it.

## 0. Short answer

- **The mechanics are free. The rest is not.** No one can own a game's rules as a system: the US Copyright Office says so outright [S1], and German courts say the same about a "Spielidee" [S3, S4]. The **wording** of the rules and cards, the **art**, and the **names** (trademarks) are protected. A Quacks clone is legal only if it copies the system and nothing else.
- **Today this repo copies more than the system.** It contains a full scan of the printed player board (`docs/assets/player-board-reference.jpg`), a crop of the rulebook, two BGG photos, and the verbatim English text of the 20 Alchemists fortune cards. It uses the game's names everywhere: "Quacks of Quedlinburg", "The Herb Witches", "The Alchemists", "Fortune Teller", the ingredient and patient names. **The GitHub repo is public** and has **no LICENSE file** [R].
- **The highest risk is not the game. It is the public repo.** A rights holder can get the scans removed with a single DMCA notice to GitHub, and the files stay in the git history after a delete. Fix: make the repo private now, or remove the scans and rewrite the history.
- **Friends-only (the current use) is low risk** if the site is hard to find: room codes, `noindex`, no "Quacks of Quedlinburg" in titles or meta, no links from public places. It is still not *legal* in the strict sense, because copyright needs no commercial use. But a publisher has no reason to act against an unlisted site for friends [E].
- **A real public version needs one of two things:** (a) a **licence** from Schmidt Spiele (the rights holder; Wolfgang Warsch as the author), or (b) a **rename and retheme**: a new name, new card and patient wording, no "Quedlinburg", no "Quacks", no expansion names. Schmidt itself uses "Quacks" as a sub-brand ("Quacks & Co.", "Quacks: The Duel") [S10, S11], so the short name "Quacks" is not safe either.
- **WebinarGeek (#71) changes the picture: from "fan project" to "use in the course of trade".** Trademark law then applies fully, any tolerance a publisher shows to fans no longer covers it, and the claim for damages grows. **Do not embed the Quacks theme in a WebinarGeek product without a licence.** A rethemed game with original text and art is fine.
- **An official digital Quacks exists, which raises the risk.** Tabletopia lists the base game and both expansions [S12, S13, S14]. Outline Development announced a licensed app for 20 January 2022 [S15, S16]; whether it shipped is ⚠️ unclear. Quacks is not on Board Game Arena (no BGA page was found) ⚠️. A publisher with a digital licensee has a reason to protect it.
- **Next games:** Hearts and other traditional card games are **green** (public domain; use public-domain or own card art). No Thanks! and Sushi Go! are **amber**: both are licensed on BGA [S20, S21], so their publishers license digital versions, but a fan copy needs a licence or a retheme. Codex is **red**: Sirlin reportedly had Codex pulled from Tabletopia and asked for a TTS module to be removed [S24]. Mage Wars is **amber-red**: an active publisher with its own licensed digital Academy [S26].

## 1. What is protected in a board game

| Element | Protected? | By what | Notes |
|---|---|---|---|
| Mechanics, rules as a system (bag-building, push your luck, the pot track numbers) | **No** | – | US: "Copyright does not protect the idea for a game, its name or title, or the method or methods for playing it" [S1, S2]. Germany: LG Mannheim 7 O 240/07: the idea of a dice game is not protected [S3]. The Spiele-Autoren-Zunft has asked for rules to be protected by law, which shows that they are not today [S5]. Numbers (prices, track values) are facts or parts of the system [E]. |
| Rule text, card text, the Almanac | **Yes**, as a literary work, if the wording is original enough | Copyright | US: the rules text can be registered (Form TX) [S1]. Germany: a rulebook can be a "Sprachwerk" when it goes beyond plain instructions [S3, S4]. **Rewrite every text in our own words**, with no copy-paste. Short rule lines have thin protection (merger doctrine [S6]), but flavour text and card titles that copy the original as a set are a risk [E]. |
| Art (board, chips, cards, box, icons on the board) | **Yes** | Copyright | Board art by Dennis Lohausen [S9]. Never use scans, crops or traces. |
| The whole "look and feel" | **Partly** | Copyright and trade dress (US), unfair competition (EU) | *Tetris v. Xio* (D.N.J. 2012): one copied element can be fine, but copying the whole visual expression is infringement, and the look was protected as trade dress too [S7]. A chip shown as a coloured disc with a number is a function [E]. A layout that copies the printed pot spiral one to one is the risky part [E]. |
| Names: "Die Quacksalber von Quedlinburg", "The Quacks of Quedlinburg", "Quacks", "Herb Witches"/"Kräuterhexen", "Alchemists"/"Alchemisten" | **Yes** if registered or used as marks; also passing off / unfair competition | Trademark | No register entry was found in search results; the DPMA, EUIPO and USPTO registers could not be read ⚠️ [S8]. Assume the names are marks: Schmidt sells a product line under them [S10, S11]. "Quedlinburg" is a town, but the full title is clearly the brand. A trademark claim needs use "in the course of trade" (EU) [E]; a commercial embed is that. |
| Ingredient and patient names (cherry bomb, crow skull, toadstool, hawkmoth; Nervousness, Ear worm...) | Weak one by one (short names are not copyrightable [S1]) | Together they are part of the expression of the game [E] | Rename them in a public version. |
| Designer's name, publisher's name | Not protected as text | – | Crediting them is fine and good practice, but a credit must not suggest an endorsement [E]. |

Jurisdiction: Nick lives in the Netherlands and the Fly app runs in `ams` [R: `fly.toml`]. EU and Dutch law have **no general fair use**. The exceptions (quotation, parody, pastiche) are narrow and do not cover a playable copy of a game [E]. The publisher is German (Schmidt, Berlin [S17]), so German law would apply too.

## 2. Audit: what this repo uses

### 2.1 Third-party art from the game: **remove**

| File | What it is | Risk |
|---|---|---|
| `docs/assets/player-board-reference.jpg` | A full scan of the printed player board (cauldron, pot track, the starting-bag book, bag, bowls), 2053×1864, 1.4 MB [R] | **High.** Pure copy of the publisher's art, in a public repo. Used only as a reference for the pot track (`docs/research/ingredient-sets-and-customisation.md:247`). |
| `docs/assets/scoring-track-rulebook-p3.jpg` | A crop of page 3 of the 2024 Schmidt English rulebook [R: `docs/research/rat-tails.md:81`] | **High.** |
| `docs/assets/scoring-track-bgg4953930.jpg`, `docs/assets/scoring-track-bgg8807552-compare.jpg` | Photos from BGG users of the scoring track [R: `rat-tails.md:80-82`] | **High.** Two rights holders: the photographer and the publisher. |

All four came in on 2026-10-03 and are in the **git history** [R]. A delete in a new commit leaves them on GitHub. Options: make the repo private, or delete them and rewrite the history (`git filter-repo`), then force-push. The scans are not needed now: the numbers are already in `lib/quacks/rules/pot_track.ex` and `scoring_track.ex`.

Not in the repo but on Nick's machine: the TTS card-sheet crops (`scratchpad/alchemists-cards/...`, `docs/research/alchemists-fortune-cards.md` §1) [R]. Keep them out.

### 2.2 Rule and card text

| Where | What | Risk |
|---|---|---|
| `lib/quacks/rules/fortune.ex` (base 24) | Titles and texts "from a fan transcription of the North Star English edition"; the texts are short and partly rephrased [R] | **Medium.** The titles ("Take a Chance", "Flea Market", ...) are the original English titles. |
| `lib/quacks/rules/fortune.ex` (`:ap1`…`:ab10`) | The 20 Alchemists cards, **verbatim Schmidt English text** with the original titles ("Spoiled for choice", "Ruby fever", "A rat to cherish", "The white blessing"...) [R, `alchemists-fortune-cards.md` §1: "Same words as F1, so F1 is the official English print"] | **High** for a public version. Copied word for word, and shown in the UI. |
| `lib/quacks/rules/alchemists.ex` | The 8 patient names in English and German (`"Nervousness", "Schreckhaftigkeit"`...) with texts in our own short words [R] | **Medium.** The German names are the original's. |
| `lib/quacks/rules/witches.ex` | The 12 herb witch cards; texts are ours, and the moduledoc says only the silver titles are printed in the rulebook [R] | **Low–medium.** |
| `lib/quacks/rules/books.ex` | Ingredient-book texts, one line each, our own words; names "Cherry bomb", "Pumpkin", "Garden spider", "Crow skull"... [R] | **Low** for the text, **medium** for the set of names. |
| `docs/research/rulebook.md`, `herb-witches.md`, `alchemists*.md`, `rat-tails.md` | Research notes: rule summaries, card lists, links to the official PDFs [R] | **Medium** in a public repo: long transcriptions of card texts. Fine in a private repo. |

### 2.3 Names and branding in the UI

| Where | What | Risk |
|---|---|---|
| `lib/quacks_web/components/layouts/root.html.heex:18` | `<.live_title default="Quacks">` [R] | **Medium.** "Quacks" is Schmidt's short brand (§1). |
| `lib/quacks_web/controllers/pwa_controller.ex:8` | PWA name "Quacks" / "Quacks Staging" / "Quacks Dev"; description "Brew, push your luck, don't explode." [R] | **Medium.** The name is installed on phones. |
| `lib/quacks_web/live/lobby_live.ex:119,540`; `game_live.ex:157` | Page titles "Quacks", "Quacks <id>", the lobby header "Quacks" [R] | Medium. |
| `lib/quacks_web/components/final_components.ex:221` | Share text "Quacks of Quedlinburg: 1. Ann 54 VP, ..." [R] | **Medium–high.** The only place with the full title, and it is the text that leaves the site. |
| `lib/quacks_web/components/setup_components.ex:37,515,523`; `panel_components.ex:526,630` | "The Alchemists", "The Alchemists' box cards", "Fortune Teller cards", "needs The Alchemists" [R] | Medium. Expansion names. |
| `fly.toml:9` | Host `quacks.fly.dev` [R] | Medium for a public launch. |
| `priv/static/robots.txt` | Allows all crawlers [R] | Turn it into `Disallow: /` plus `<meta name="robots" content="noindex">` while friends-only. |

### 2.4 Our own and third-party assets: **fine, two follow-ups**

- **Icons:** 27 icons from game-icons.net, CC BY 3.0, credited in `docs/CREDITS.md` and in the lobby footer `#credits` (`lobby_live.ex:693`) [R]. This meets CC BY (author, licence link, a note of the changes). 5 icons are our own drawings [R]. The **PWA icons** (`priv/static/images/pwa/*.png`, a cream cauldron) are not listed in `CREDITS.md`. If they come from `cauldron-2.svg` (DarkZaitzev, CC BY), the credit should name them too [R/E].
- **Logo:** `priv/static/images/logo.svg` is the Phoenix bird from the generator (MIT) [R].
- **Sounds:** `priv/static/sounds/LICENSES.md`: all CC0 (Kenney, OpenGameArt, freesound) or our own synthesis [R]. Open item from that file: replace the lossy freesound previews with the originals before a release (quality, not licence).
- **Font:** Kalam, Indian Type Foundry, SIL OFL 1.1 [S18]: free to use, even commercially. **But it is loaded from `fonts.googleapis.com`** (`root.html.heex:19-23`) [R]. LG München I (3 O 17493/20, 20 January 2022) held that this sends the visitor's IP to Google without a legal basis under the GDPR and awarded damages; a wave of warning letters followed in Germany [S19]. **Self-host the font** before going public (the OFL allows it). This is a privacy rule, not a game licence, but it is the easiest real claim against an EU site [E].
- **Vendored JS:** `assets/vendor/heroicons.js`, `topbar.js` (MIT) [R/E].
- **Hex deps** (`mix.exs`): phoenix, phoenix_html, phoenix_live_view, phoenix_live_dashboard, bandit, heroicons, tailwind, esbuild, usage_rules, credo (MIT); jason, req, telemetry_*, dns_cluster, tidewave, dialyxir, stream_data, lazy_html (Apache-2.0) ⚠️ from memory: `deps/` is not fetched here, so check with `mix hex.licenses` or each `hex_metadata.config`. Both licences allow commercial use. Apache-2.0 asks to keep the NOTICE files when redistributing; a hosted web app does not redistribute [E].

### 2.5 The code licence of this repo

- **There is no `LICENSE` file**, and `mix.exs` has no `licenses` [R]. The GitHub API reports the repo as **public** with `license: null` [R]. Without a licence, all rights are reserved: others may read the code but not reuse it [E]. That is fine for a private project.
- `docs/CREDITS.md` says our own icons have "the same licence as the project". That points to nothing today. Pick one: add a `LICENSE` (MIT for the code, and say that game names and rules belong to their owners), or change the line to "all rights reserved".
- An open-source licence on the code **does not** cover the game names, card text or art. A README note should say so.

## 3. Precedents: how other sites do it

| Who | Model | What it shows |
|---|---|---|
| **Board Game Arena** | Every commercial game needs a licence from the publisher first; development may start only after a licence agreement is received; public-domain games need admin approval [S22]. All rights in the idea and graphics stay with the licensor [S22]. | The norm for a public site. BGA removed Dominion when Rio Grande launched its own app [S23]: an official app ends other licences. |
| **Yucata.de** | Free, non-commercial hobby site; volunteers implement games **with publisher permission**. Some publishers refuse free licences (Queen Games, Cwali; Knizia games are excluded) [S25]. | Even a free site asks first. Some publishers say no. |
| **Tabletopia** | Licensed catalogue, pays royalties. Hosts Quacks + Herb Witches + Alchemists [S12, S13, S14]. Sirlin pulled Codex when royalties were not paid ⚠️ [S24]. | Quacks has a digital licensee. |
| **Tabletop Simulator workshop** | User mods; several Quacks mods exist, one with all expansions [S12]. Some workshop items show "removed ... violates Steam Community & Content Guidelines" ⚠️ [S12]. Games Workshop had 40K mods removed in June 2026 [S27]. | Publishers do send takedowns for unlicensed digital copies, mainly when a mod competes with an official product. |
| **Scrabulous (2008)** | Facebook Scrabble clone. Hasbro sued, Mattel complained, Facebook removed it [S28]. Relaunched as **Wordscraper/Lexulous** with round tiles and a new name; Hasbro then dropped the suit [S28]. | The classic case for "rename and retheme". The mechanics stayed; the name and look changed, and that was enough. |
| **NetrunnerDB (2014)**, **Games Workshop fan sites (2009)** | C&D letters to fan sites over card images and text [S29]. | Card text and images draw the letters. |
| **Hans im Glück vs "Meeple Inc" (2024)** | C&D against a crowdfunded game; it was renamed [S30]. | German publishers do enforce, even on words close to their brand. |

**Schmidt Spiele / North Star Games / CMYK fan policy:** no published fan-content or digital policy was found for any of them ⚠️ [S31]. Without a policy, the default applies: you need permission. North Star Games published the first English edition (2018) [S9]; CMYK publishes the newer US/English editions ⚠️ (role and date not confirmed) [S9, S32]. Schmidt is the original publisher and the one to ask for a digital licence [E].

## 4. Options for Quacks

### 4.1 Private / friends-only (today's use)
- Make the GitHub repo **private** (or remove the scans and rewrite the history; §2.1).
- `robots.txt`: `Disallow: /`; add `<meta name="robots" content="noindex, nofollow">` in `root.html.heex`.
- Remove the full title from the share text (`final_components.ex:221`), and keep the full title out of page titles and the PWA manifest.
- No public links (Reddit, BGG, a portfolio).
- Rooms by code only (already the model: `/g/:id`) [R]. Optionally add a shared password on the lobby.
- **Residual risk:** low [E]. Copyright still applies, but the publisher would have to find the site, and the worst likely outcome is a request to take it down.

### 4.2 Rename and retheme (public, free)
Keep the engine (the system is free). Change everything that is expression:
- **Name:** not "Quacks", not "Quedlinburg", not "Quacksalber". Check the name in DPMA, EUIPO and USPTO. Keep it clear of "Quacks" in sound and meaning: no "Quack", "Quackery" or "Quacksalber" variants [E].
- **Theme:** the potion-brewing theme itself is free (it is an idea), but a new setting lowers the "look and feel" risk. Different ingredient names, no "cherry bomb", no "Fortune Teller", no patients, no herb witches.
- **Text:** rewrite all card texts and titles from scratch. The 20 verbatim Alchemists cards must go first.
- **Expansions:** do not offer "Herb Witches" or "Alchemists" by name; the rules can become our own "modules" with new names. Large parts of Alchemists are distinctive (essence, patients): rethink them, don't just rename them [E].
- **Layout:** our pot is our own SVG [R: `CREDITS.md`], which is good. Do not copy the printed pot spiral, the colours of the board or its icons one to one.
- **Credit line:** "Inspired by bag-building games" is safe. Avoid "A version of The Quacks of Quedlinburg", because it uses the mark to attract players [E].

### 4.3 Ask for a licence
- **Who:** Schmidt Spiele GmbH, Lahnstraße 21, 12055 Berlin [S17], via the contact form on schmidtspiele.de, asking for the licensing department ("Lizenzen") ⚠️ (no direct address found). Copy Wolfgang Warsch (designer); a designer's support helps [E]. For the US English edition, also CMYK ⚠️.
- **What to say:** non-commercial, free, no ads, friends' groups; offer to credit them and link to the shop; ask for a written, revocable licence for the name and the card texts. Mention that a licensed app and Tabletopia exist and that this is not a competitor.
- **Expect:** a no, or no answer, is likely. A publisher with a digital licensee (Outline Development, Tabletopia) may be bound by exclusivity [E]. BGA itself rarely asks one publisher for more than one game at a time [S22].
- **For a commercial use (WebinarGeek):** this is the only clean path with the Quacks theme, and it would be a paid licence.

## 5. Embedding in WebinarGeek (#71): commercial use

- **Copyright:** the same rules, but every argument for tolerance is gone. A company makes it available to its customers as part of a product. Damages are measured by a "reasonable licence fee", which is now a real number [E].
- **Trademark:** EU trademark infringement needs use "in the course of trade". A friends' site is arguably not; a feature in a SaaS product is [E]. "Quacks" in a WebinarGeek UI is a clear risk.
- **Who is liable:** WebinarGeek as the operator, not only Nick [E]. A company has a known address, so it receives the letter, and it has money.
- **Licences of our own assets:** CC BY 3.0, CC0, OFL and MIT/Apache all allow commercial use [S18, R]. Keep the credits visible inside the embed too (CC BY needs a credit "reasonable to the medium") [E].
- **Privacy:** an embed for business customers will need a DPA review anyway; self-host the font (§2.4).
- **Verdict:** **red with the Quacks theme; green with a rethemed game** that has its own name, text and art.

## 6. Next games

| Game | Rights | Digital today | Notes |
|---|---|---|---|
| **No Thanks!** (Thorsten Gimmler; Amigo, "Geschenkt!"; Z-Man in English) [S20] | Mechanics free; the name is a mark of Amigo ⚠️; cards are just numbers 3–35 and chips | On BGA, with thanks to Amigo and Gimmler [S20] | The game *is* almost only mechanics: numbered cards and tokens. A retheme is easy (new name, own card art) [E]. Amigo licenses digital, so asking is realistic. |
| **Sushi Go!** (Phil Walker-Harding; Gamewright) [S21] | Mechanics free; name, the sushi art and card set names are protected | On BGA ("thanks to Gamewright") [S21]; official app by Lummox Labs (2016) [S21] | The theme and the art are the selling point. A retheme (not sushi, own art, own names) works; "Sushi Go" in the name does not. |
| **Hearts** and other traditional card games | Public domain | Everywhere | Only the card art matters. Draw our own faces or use a set with a clear licence. Byron Knoll's vector cards are labelled CC0 on OpenGameArt, but the ace of spades artist is unclear ⚠️ [S33]. Our own simple faces are the safest. |
| **Codex** (David Sirlin; Sirlin Games) | Mechanics free; card text, hero names, art and "Codex" protected | No licensed digital version. Tabletopia's version removed (royalties not paid), TTS module reportedly asked to be removed ⚠️ [S24]. A fan asking for web permission got no answer [S24]. | Sirlin cares about digital rights and has acted. A fan version with the original cards would draw a request. |
| **Mage Wars** (Arcane Wonders) | Mechanics free; a large card pool with art and text | Mage Wars Academy on Tabletopia (licensed) [S26]; a fan OCTGN module existed ⚠️ [S26] | Card-heavy: a copy *is* the card text. Only a licence makes sense. |

## 7. Checklist before going public (ordered by risk)

1. **Make the GitHub repo private now**, or delete `docs/assets/player-board-reference.jpg`, `scoring-track-rulebook-p3.jpg`, `scoring-track-bgg4953930.jpg`, `scoring-track-bgg8807552-compare.jpg` **and rewrite the history** (§2.1). These are verbatim copies of the publisher's art and of other users' photos.
2. **Do not ship the Quacks theme in WebinarGeek** (#71) without a written licence (§5).
3. **Replace the 20 verbatim Alchemists fortune cards** (`lib/quacks/rules/fortune.ex` `:ap1`–`:ab10`) with our own titles and wording, and rewrite the 24 base cards' titles too (§2.2).
4. **Remove the full title "Quacks of Quedlinburg"** from the share text (`final_components.ex:221`), and keep it out of all titles, meta and manifest text.
5. **Friends-only hardening:** `robots.txt` `Disallow: /`, a `noindex` meta tag, no public links; an optional lobby password (§4.1).
6. **Self-host the Kalam font** (OFL allows it) instead of loading from Google Fonts (GDPR, §2.4).
7. **Decide the code licence:** add `LICENSE` (e.g. MIT for the code only, with a note that game names and rules belong to their owners), and fix the "same licence as the project" line in `docs/CREDITS.md` (§2.5).
8. **Credits:** add the PWA icons' source to `docs/CREDITS.md` if they derive from a CC BY icon; keep the footer credit in every embed.
9. **Research docs:** in a public repo, shorten the long verbatim card and rulebook transcriptions in `docs/research/*.md` to summaries and links.
10. **For a public launch: pick one path.** (a) Rename and retheme: new name (not "Quacks"; check DPMA/EUIPO/USPTO), new ingredient, patient and witch names, our own expansion names, new domain instead of `quacks.fly.dev`. Or (b) write to Schmidt Spiele (licensing) and Wolfgang Warsch for a licence (§4.3).
11. **Before any money is involved:** ask a lawyer.

## 8. Verdicts per game

| Game | Friends-only | Public, free | Commercial (WebinarGeek) | Reasoning |
|---|---|---|---|---|
| **Quacks (as it is)** | 🟡 amber | 🔴 red | 🔴 red | Original names, verbatim card text and scans in a public repo. An official app and Tabletopia exist, so the publisher has a reason to act. |
| **Quacks after checklist items 1–6** | 🟢 green | 🟡 amber | 🔴 red | The art is gone and the text is ours, but the name and theme are still the brand. |
| **Rethemed bag-builder** (new name, text, art) | 🟢 | 🟢 | 🟢 / 🟡 | Mechanics are free [S1, S3]. Amber only if the look stays too close (*Tetris v. Xio* [S7]). |
| **No Thanks!** | 🟢 | 🟡 | 🟡 | Almost pure mechanics; retheme is trivial; Amigo licenses BGA. |
| **Sushi Go!** | 🟢 | 🟡 | 🟡 / 🔴 | Theme and art are the brand; a retheme is needed; licensed on BGA and as an app. |
| **Hearts / traditional** | 🟢 | 🟢 | 🟢 | Public domain; use our own card art. |
| **Codex** | 🟡 | 🔴 | 🔴 | Sirlin has had digital versions removed ⚠️; the game is its card text. |
| **Mage Wars** | 🟡 | 🔴 | 🔴 | A card game: the copy is the cards; an active publisher with licensed digital products. |

## 9. Open items (⚠️)

1. Trademark registrations for "Quacksalber von Quedlinburg", "The Quacks of Quedlinburg", "Quacks", "Kräuterhexen", "Alchemisten": search DPMA, EUIPO and USPTO by hand.
2. Is the Outline Development app live, and is the licence exclusive?
3. Is Quacks really absent from BGA? (boardgamearena.com was not reachable.)
4. The Schmidt licensing contact address.
5. CMYK's exact role and date as the North American publisher.
6. Hex dependency licences: confirm with `deps/*/hex_metadata.config` once deps are fetched.
7. Sirlin's stance comes from forum posts, not from Sirlin.

## 10. Sources

- S1 US Copyright Office, "Games" (registration guidance): https://www.copyright.gov/register/tx-games.html
- S2 US Copyright Office FL-108 (archived): https://webharvest.gov/peth04/20041015023438/http://www.copyright.gov/fls/fl108.html
- S3 Ferner Alsdorf, Schutzfähigkeit von Spielidee oder Spielanleitung (LG Mannheim 7 O 240/07): https://www.ferner-alsdorf.de/schutzfaehigkeit-von-spielidee-oder-schriftlich-niedergelegter-spielanleitung/
- S4 Spiele-Autoren-Zunft, SAZ-Zeichen Nr. 5, Spiele und Urheberrechtsschutz: https://www.spieleautorenzunft.de/files/public/SAZ-Zeichen-DE/SAZ-Zeichen%20Nr%205%20-%20Spiele%20und%20Urheberrechtsschutz.pdf
- S5 SAZ position paper (urheberrecht.org): https://www.urheberrecht.org/topic/Diskussion/SAZ.pdf
- S6 "Copyright and game rules" (merger doctrine): https://godsmonsters.com/Features/copyright-game-rules
- S7 *Tetris Holding v. Xio Interactive* (D.N.J. 2012), Loeb & Loeb summary: https://www.loeb.com/en/insights/publications/2012/06/tetris-holding-llc-v-xio-interactive-inc
- S8 DPMA register (not searched): https://www.dpma.de/recherche/dpmaregister/index.html
- S9 Wikipedia, The Quacks of Quedlinburg: https://en.wikipedia.org/wiki/The_Quacks_of_Quedlinburg ; ICv2 on the North Star edition: https://icv2.com/print/article/41085
- S10 Wikipedia, Quacks & Co.: Quedlinburg Dash: https://en.wikipedia.org/wiki/Quacks_%26_Co.:_Quedlinburg_Dash
- S11 Meeple's Herald, Quacks: The Duel (2024): https://meeplesherald.com/news/the-quacks-of-quedlinburg-get-a-duel-version-in-2024/
- S12 Steam Workshop Quacks mods: https://steamcommunity.com/sharedfiles/filedetails/?id=2804616513 , https://steamcommunity.com/sharedfiles/filedetails/?id=1864138254
- S13 Tabletopia, Quacks: https://tabletopia.com/games/the-quacks-of-quedlinburg ; Herb Witches: https://tabletopia.com/games/the-quacks-of-quedlinburg-the-herb-witches ; Alchemists: https://tabletopia.com/games/die-quacksalber-von-quedlinburg-die-alchemisten
- S14 Tabletopia news on Steam: https://store.steampowered.com/news/app/402560/view/2892958487018857770
- S15 Outline Development on X (release date 20 Jan 2022): https://x.com/outlinedev/status/1474411198301020160 ; "coming soon": https://twitter.com/outlinedev/status/1394194956382785539
- S16 spielen.de forum, "Wird es das Spiel auch als App geben?": https://www.spielen.de/forum/viewtopic.php?t=393379
- S17 Schmidt Spiele (company, Berlin): https://en.wikipedia.org/wiki/Schmidt_Spiele
- S18 Kalam, SIL OFL 1.1: https://fontsource.org/fonts/kalam/about , https://www.fontsquirrel.com/fonts/kalam
- S19 LG München I, 3 O 17493/20 (Google Fonts), IHK summary: https://www.ihk.de/bergische/recht-und-steuern/wettbewerbsrecht/google-fonts-5646176 ; https://www.dr-datenschutz.de/schadensersatz-urteil-google-fonts-und-die-dsgvo/
- S20 BGA news, No Thanks!: https://en.boardgamearena.com/news?id=503 ; Wikipedia: https://en.wikipedia.org/wiki/No_Thanks!_(game)
- S21 BGA Sushi Go!: https://en.boardgamearena.com/gamepanel?game=sushigo ; Sushi Go Party!: https://en.boardgamearena.com/gamepanel?game=sushigoparty ; TouchArcade, digital Sushi Go! (2016): https://toucharcade.com/2016/09/09/the-digital-version-of-sushi-go-is-out-now/
- S22 BGA Game licences: https://en.doc.boardgamearena.com/BGA_Game_licences ; BGA developer terms: https://tr.doc.boardgamearena.com/images/0/02/BGA_TC_Dev_en.pdf
- S23 BGA news, end of Dominion on BGA: https://en.boardgamearena.com/news?id=77
- S24 Sirlin Games forum: https://forums.sirlingames.com/t/digital-version-of-codex/301?page=5 , https://forums.sirlingames.com/t/tabletop-simulator/3029?page=2
- S25 Yucata FAQ: https://www.yucata.de/en/FAQ ; BGG geeklist "Proposed yucata.de games": https://boardgamegeek.com/geeklist/22833/proposed-yucatade-games?page=18
- S26 Tabletopia, Mage Wars Academy: https://tabletopia.com/games/mage-wars-academy ; BGG Mage Wars Arena files: https://boardgamegeek.com/files/thing/101721/page/1
- S27 Games Workshop TTS takedowns (2026): https://finalboss.io/gw-nuked-the-core-40k-tts-mods-right
- S28 Scrabulous: https://www.theregister.co.uk/2008/12/16/hasbro_drops_scrabulous_creators_lawsuit/ , https://www.informationweek.com/it-leadership/facebook-blocks-scrabulous-worldwide , https://www.cbsnews.com/news/new-scrabble-version-on-facebook
- S29 NetrunnerDB C&D: https://boardgamegeek.com/thread/1234809/netrunnerdb-cease-and-desist/page/10 ; GW C&D letters: https://boardgamegeek.com/thread/468517/gw-cease-and-desist-letters
- S30 Board Game Wire, Hans im Glück / "meeple" (2024): https://boardgamewire.com/index.php/2024/06/14/the-word-meeple-is-being-trademarked-in-the-us-in-reaction-to-cease-and-desist-activity-from-carcassonne-publisher-hans-im-glueck/
- S31 Searches for a Schmidt / North Star fan-content policy returned none (2026-10-15).
- S32 Board Game Wire, CMYK tag: https://boardgamewire.com/index.php/tag/cmyk/
- S33 OpenGameArt, Byron Knoll playing cards: https://opengameart.org/content/playing-cards-vector-png
