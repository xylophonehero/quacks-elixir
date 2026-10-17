# Codex: Card-Time Strategy (Sirlin Games, Deluxe Set): rules and card data

Scope: the rules and card data that a builder needs to make a pure Elixir engine for Codex
(1-hero mode first, then 3-hero mode). Compiled 2026-10-16.
Text marked ⚠️ is not stated in a primary source. Do a check before you use it.

Sources:
- **S1** Official rulebook v46 (2016-03-19, "Codex core set rulebook", covers Core and Deluxe Set), 22 pages.
  From the official Dropbox folder "Official Rulebooks (searchable PDFs)":
  https://www.dropbox.com/sh/oqxpfz2bpkln4hq/AACbSiB6hRBCz-8HKdGFkNJIa?dl=0
  (`?dl=1` gives a zip with `codex_rulebook_46.pdf` and `codex_starter_rulebook_32.pdf`).
  The folder link is in the forum thread S5. Text below is from S1 unless marked.
- **S2** Official starter-set rulebook v32 (same zip). Same rules as S1 for the 1-hero game.
- **S3** Codex Card Database raw data, repo `rgdelato/codex-cards-gatsby` (MIT, 2023-04):
  https://github.com/rgdelato/codex-cards-gatsby/tree/master/raw_data (site: https://codexcarddb.com).
- **S4** Official rulings (Sirlin), in S3 `raw_data/rulings.json` (572 rulings, with date and author).
  The original list: http://www.sirlin.net/rules (S1 p. 18 points there).
- **S5** Forum "Collected Codex Resources": https://forums.sirlingames.com/t/collected-codex-resources/860
  It also links the Official Rulings Spreadsheet (errata):
  https://docs.google.com/spreadsheets/d/1WyO1v5RCqBQwKYi4tfKOqOjRfTn2h9PDzvUMgSF4S2Y/
- **S6** Older card data, repo `sharpobject/codex_rules` (no licence, 2016-07):
  https://github.com/sharpobject/codex_rules
- **S7** Local TTS mod "Codex Deluxe Set" (2017-07-25):
  `~/Library/Tabletop Simulator/Mods/Workshop/1081687194.json`, sheet images in
  `~/Library/Tabletop Simulator/Mods/Images/`.
- **S8** Secondary summary, RulesPal: https://rulespal.com/codex-card-time-strategy/rulebook
  (agrees with S1 on every point that I checked).

No Codex rulebook PDF is in `~/Library/Tabletop Simulator/Mods/PDF/`. The S7 mod has no `CustomPDF` object.

Copies for the builder (scratchpad, not in the repo):
`/private/tmp/claude-501/-Users-nick-dev-quacks-elixir/74229621-ca3c-42ed-af4c-1507dfc6c251/scratchpad/codex/research/`
(`rulebook/rb46.txt`, `codexcarddb/*.json`, `sharpobject/*.json`, `tts_decks.txt`, `thumbs/`).

---

## 1. Glossary (engine terms)

| Term | Meaning (S1) |
|---|---|
| Base | Your main building. 20 HP. It is a tech building that lets you play tech 0 cards. |
| Worker | 1 gold per worker in each upkeep. A worker is a face-down card. |
| Codex | Your private pool of extra cards. 1-hero mode: 24 cards (2 copies of 12). 3-hero mode: 72 cards. |
| Starting deck | 10 tech-0 cards with a coloured dot. One deck for each colour, two neutral decks in Deluxe. |
| Command zone | Heroes wait here. Not part of the deck. |
| Spec | Specialisation. 3 per colour, 2 for neutral. Each spec = 1 hero + 12 codex cards x2. |
| Forces | Units and heroes. |
| Patrol zone | 5 slots: squad leader, elite, scavenger, technician, lookout. |
| Exhaust / ready | Turn sideways / turn straight. |
| Arrival fatigue | A card that was not under your control at the start of your turn cannot attack or pay an exhaust cost. |
| Trash | Remove from the game. Not the discard pile. |
| Sideline | Move out of the patrol zone. |
| Rune | Marker on a card: +1/+1, -1/-1, time, and named runes ("blood", "sword", ...). |
| Token | Unit card with no standard back. Counts as tech 0. If it leaves play, it is destroyed. |

Symbols in card text (S3): `①②④` = gold amounts, `⤵` = exhaust this (cost), `◎` = target icon, `→` = cost/effect separator.

---

## 2. Setup (1-hero mode)

1. Each player picks 1 hero. First game: one player Bashing (Troq Bashar), the other Finesse (River Montoya). Both neutral. (S1 p. 7)
2. Put the hero in the command zone. (S1 p. 7)
3. Worker card in the worker area. **Player 1 starts with 4 workers, player 2 with 5.** (S1 p. 3, p. 21) The 5th worker is the only second-player bonus.
4. **Starting gold: 0.** ⚠️ S1 does not say "0" in words. But S1 p. 9 says player 1 gets 4 gold in the first upkeep and must save 1 for a worker. No other gold is given. So start with 0.
5. Take the 10-card starting deck of the hero's colour. Shuffle. Draw 5. (S1 p. 7)
6. Take the 24 codex cards of the hero's spec (2 copies of 12). (S1 p. 7)
7. Base: 20 HP (S1 p. 1). Optional: one random map card (Deluxe only, S1 p. 7).
8. Pick player 1 at random (S1 p. 9).

3-hero mode differences (S1 pp. 10-12):
- Pick 3 different heroes. Name one the "main". Use the starting deck of the main hero's colour.
- Codex = 24 cards of each of the 3 specs (72 cards).
- Hero limit: 1 with base only, 2 while you have a finished tech II, 3 while you have a tech III. Check only when you summon. Heroes' Hall gives +1.
- Multicolour heroes: the first tech building or add-on that you build costs 1 extra gold. Neutral heroes have no colour.
- Minor spells (starting-deck spells) are tied to a colour. A hero of another colour can cast them for +1 gold. Neutral minor spells have no extra cost.
- Spec spells need that spec's hero in play. No exception.
- Tech II: declare one spec when you start to build it. Locked for the game. Tech II and III then make only that spec's cards. Tech I makes cards of all specs.

---

## 3. Turn order (S1 p. 6, p. 21)

1. **Ready**: ready all your exhausted cards. (Player 1 skips it on turn 1. S1 p. 9.)
2. **Upkeep**: get 1 gold for each worker. Then do all "Upkeep:" effects (healing, fading, forecast, Surplus draw, ...).
   Gold cap: 20. Gold above 20 is lost. Gold stays between turns. (S1 p. 3)
3. **Main phase**, any order, any count unless stated:
   - Hire a worker (max 1 per turn): pay 1 gold, put a card from hand face down under the worker card.
   - Build a tech building and/or an add-on.
   - Summon a hero from the command zone (pay its cost; all 20 heroes cost 2, S3).
   - Level up heroes (1 gold per level, many times per turn).
   - Play cards from hand. Use abilities.
   - Attack, one combat at a time.
   - Lock in the patrol zone. This ends the main phase.
4. **Discard/draw**: discard all of your hand face down. Draw (discarded count + 2), max hand 5.
   0→2, 1→3, 2→4, 3+→5. (S1 p. 2)
5. **Tech**: choose 2 cards from your codex. They go face down into your discard pile **just before your next turn starts**.
   2 copies of one card or 1 each of two cards. Mandatory 2 until you have 10 workers; then 0, 1 or 2. (S1 p. 6)

Draw rule: if the draw pile is empty, shuffle the discard pile into a new draw pile. Only once per main phase. If it is empty a second time in that main phase, you draw nothing more in that main phase. (S1 p. 2)

Discard piles are face down. Owner may look at their own pile. (S1 p. 2)

---

## 4. Workers and gold (S1 p. 3)

- 1 gold per worker per upkeep.
- Hire: 1 gold + 1 card from hand, max once per turn.
- Destroyed or sacrificed workers are trashed (not discarded).
- Gold cap 20.

---

## 5. Heroes (S1 p. 3, p. 11, p. 21)

- Heroes are **not units**. "Destroy a unit" does not hit a hero.
- Summon cost: printed (2 for every hero, S3). Arrive at level 1. Arrival fatigue applies.
- Level up: 1 gold per level, as many as you want in your main phase. Max level = no more levels.
- Level bands: a hero card has 3 bands. S3 fields: `ATK_1/HP_1` + `base_text_*` (level 1), `mid_level` + `ATK_2/HP_2` + `mid_text_*`, `max_level` + `ATK_3/HP_3` + `max_text_*`.
  Band pairs in S3: (mid 3, max 5) ×7, (4, 6) ×4, (5, 8) ×4, (4, 7) ×3, (3, 7) ×1, (5, 7) ×1.
- A hero keeps the abilities of lower bands.
- When a hero reaches its mid band or its max level, heal all its damage.
- "Max level: do X" triggers once when it reaches max level.
- Ultimate spell: the hero must be under your control **and** max level at the start of your turn.
- You must have a hero in play to cast any spell. Spec spells need the hero of that spec.
- Hero death: goes to the command zone, loses levels, runes, damage and all modifiers. **Cannot be summoned again until after your next turn** (cooldown = skip your next turn).
- When a hero dies, **one** opposing hero in play gets 2 free levels. Active player picks which, only from heroes that can level up.
- Sacrificed hero goes to the command zone (S1 p. 20).

---

## 6. Card types (S1 pp. 3-4)

- **Unit**: attacks and patrols. Tech 0/I/II/III. Dies → owner's discard pile (face down).
- **Hero**: see §5.
- **Spell**: one-shot, then discard. Needs a hero in play.
  - **Minor spell**: starting-deck spell, colour-tied (+1 gold off-colour, neutral free).
  - **Ongoing spell**: stays in play. "Channeling" = sacrifice it when the casting hero leaves play. "Attach" = discard it when the host leaves. Ongoing spells cannot be attacked.
  - **Ultimate spell**: see §5.
- **Upgrade**: bonus card. Cannot be attacked, cannot attack or patrol.
- **Building** (from cards): cannot attack or patrol, **can** be attacked.
- **Legendary**: max 1 copy with that name under your control. A second copy goes to the discard pile.
- **Token**: tech 0 unit. Destroyed when it leaves play. Never in hand or deck.

S3 type counts (all colours, without heroes): Unit 197, Spell 51, Building 21, Minor Spell 20, Ultimate Spell 17,
Worker 14, Legendary Unit 11, Ongoing Spell 9, Upgrade 9, Legendary Building 3, other ultimate/ongoing mixes 3, Legendary Upgrade 1.

---

## 7. Tech buildings and add-ons

Requirements and time (S1 p. 4, p. 21). Gold cost and HP from S3 card records.

| Building | Needs | Gold (S3) | HP (S3) | Lets you play |
|---|---|---|---|---|
| Base | - | - | 20 | tech 0 |
| Tech I | 6 workers | 1 | 5 | tech I, all specs |
| Tech II | 8 workers + tech I | 4 | 5 | tech II, one declared spec (3-hero) |
| Tech III | 10 workers + tech II | 5 | 5 | tech III, same spec as tech II |
| Add-on: Tech Lab | - | 1 | 4 | unlock 1 more spec (3-hero) |
| Add-on: Heroes' Hall | - | 2 | 4 | +1 hero limit (3-hero) |
| Add-on: Tower | - | 3 | 4 | see below |
| Add-on: Surplus | - | 5 | 4 | Upkeep: draw a card |

The gold values match the TTS add-on cards (S7 sheet 18: Tower 3, Surplus 5, Tech Lab 1, Heroes' Hall 2; all 4 HP).

Rules (S1 p. 4, p. 12, p. 21):
- All tech buildings and add-ons **finish at the end of your turn**. You cannot use them in the turn you start them.
- Tech building destroyed → your base takes 2 damage. Rebuild costs 0 gold, still takes until end of turn.
- Max 1 add-on at a time. Add-on destroyed → base takes 2 damage. You may sacrifice your own add-on (base takes 2 damage) to build another one.
- 1-hero mode uses only Surplus and Tower. 3-hero mode adds Tech Lab and Heroes' Hall.
- Tech Lab destroyed → lose its spec until rebuilt; you may pick a new spec on rebuild. Tech II destroyed → no tech II cards even with a Tech Lab. Tech II spec never changes.
- Tech Lab built before tech II: pick its spec when you build tech II (S4).
- Heroes' Hall lost → heroes stay in play (S1 p. 12, S4).
- **Tower** (S1 p. 4, S4):
  - Detects 1 stealth or invisible thing per turn, until end of turn. On an opponent's turn it detects the **first** stealth/invisible attacker automatically. That attacker cannot ignore your patrollers.
  - On your turn, you may reveal 1 invisible thing; you can then attack and target it.
  - Deals 1 combat damage to **each** enemy attacker that it can see, at the same time as that attacker's combat damage. Applies to attacks on anything you control, not only on the Tower.
  - Has anti-air (hits fliers). Hits long-range attackers. Damage is simultaneous with swift strike.
  - If its detection is used up, it does not hit later stealth/invisible attackers that turn.

---

## 8. Patrol zone (S1 p. 5, p. 21)

- 5 slots, 1 ready unit or hero each. Exhausted forces cannot patrol.
- During your main phase you move forces in and out freely. They count as patrollers only after you lock in (end of main phase), until your next turn. Patrollers protect you only on opponents' turns.
- Slot bonuses (on opponents' turns):

| Slot | Bonus |
|---|---|
| Squad leader | 1 armor while patrolling (refreshes each turn). Must be attacked first. |
| Elite | +1 ATK |
| Scavenger | You get 1 gold if it dies while patrolling. |
| Technician | You draw 1 card if it dies while patrolling. |
| Lookout | Resist 1 |

- Slot order matters for **sparkshot** (adjacent slots) and some card effects (shove, pull). Empty slots break adjacency.

---

## 9. Attacking and combat (S1 p. 5, p. 17, p. 21)

Attack legality:
1. Attacker = unit or hero under your control since the start of your turn (or haste), and ready.
2. Exhaust it (not with readiness) and declare one target. Any number of attacks per turn, one at a time.
3. Target rule: if it **can** attack the opposing squad leader, it must. Else, if it can attack any other patroller, it must attack a patroller (your choice). Else, any opposing unit, hero or building.
   A patroller that the attacker **cannot** attack (for example a flier vs a ground attacker) is ignored for this rule.
4. "Attacks:" triggers resolve after exhaust and target, before damage.

Damage:
- Attacker deals ATK to the defender; defender deals ATK to the attacker; at the same time.
- Swift strike first (see §10). Tower damage and sparkshot are simultaneous with normal combat damage.
- Armor absorbs damage before HP, then is gone (squad leader armor refreshes each turn).
- Dies at damage ≥ HP, or at HP ≤ 0 from runes/debuffs. Damage stays across turns.
- Dead units → owner's discard pile face down. Heroes → command zone. Workers → trash. Tokens → destroyed.
- Buildings have no ATK; they do not hit back (the Tower add-on is the exception).

Other combat rules:
- The defender makes no choices. **Active player decides** every choice. If a card asks an opponent to choose on your turn, nothing happens. (S1 p. 18)
- No instants. Finish each action or combat before the next one. Triggers may happen inside an action; activated abilities cannot. (S1 pp. 17-18)
- "Do as much as you can": if part of an effect is impossible, do the rest. (S1 p. 17)
- "You" = controller unless "owner" is written. Return-to-hand goes to the owner. (S1 p. 18)

---

## 10. Keywords (S1 pp. 19-20, rulings S4)

| Keyword | Rule |
|---|---|
| Anti-air | Can attack fliers, but may ignore patrolling fliers. Deals combat damage to fliers that it fights or that fly over it while it patrols. |
| Armor | Absorbs damage before HP, then destroyed. |
| Armor piercing | Ignores armor. |
| Arrives: X | Do X when it comes into play. |
| Attacks: X | After target and exhaust, before damage. |
| Boost X | May pay X more when you play it for the boost effect. |
| Channeling | Ongoing spell; sacrifice when the casting hero leaves play. |
| Deathtouch | Its combat damage (even to armor) kills units/heroes. |
| Detector | Opposing stealth and invisible forces are visible to you. |
| Dies: X | When put into your discard pile from play, do X. |
| Disable | Exhaust it; it does not ready in its next ready step; sideline it if patrolling. |
| Ephemeral | Dies at end of turn (each player's turn, S4). |
| Fading X | Arrives with X time runes; remove one each of your upkeeps; sacrifice at the last one. |
| Flying | May ignore non-flying patrollers. Ground forces without anti-air cannot attack it and deal it no combat damage. Fliers cannot ignore flying patrollers (S4). |
| Forecast X | Starts in the future with X time runes; remove one each upkeep; arrives at the last. |
| Frenzy X | +X ATK on your turn. Stacks (S4). |
| Haste | Can attack and pay exhaust costs the turn it arrives. |
| Healing X | Your upkeep: heal X damage from all friendly units and heroes. Only removes damage, not -1/-1 runes (S4). |
| Illusion | Dies when targeted by a spell or ability. |
| Indestructible | Instead of dying: exhaust, remove all damage and attachments. Cannot be sacrificed. Can be trashed. |
| Invisible | To opponents without a detector: untargetable, unattackable, sneaks past patrollers. Attackable while patrolling. |
| Leaves: X | When it goes from in play to not in play. |
| Legendary | Max 1 with that name under your control. |
| Long-range | Defenders without long-range deal it no damage when it attacks. Does not stop anti-air fly-over damage or Tower. |
| Max level: X | Trigger when the hero reaches max level. |
| Obliterate X | When it attacks, destroy the defender's X lowest-tech units first (no target; skips indestructible). If the target is gone, pick a new target. |
| Overpower | Excess combat damage to a patroller hits one other thing this could attack (patrollers first if possible). No cascade. Does nothing on defence or vs non-patrollers. Excess = damage above remaining HP (S4). |
| Readiness | Does not exhaust to attack, but only 1 attack per turn. |
| Resist X | Opponents pay X gold each time they target it with a spell or ability. Stacks. Not for attacks (S4). |
| Sacrifice | Destroy a thing you control, no target. |
| Sideline | Move out of the patrol zone. |
| Sparkshot | When attacking a patroller, deal 1 damage to an adjacent patroller. Combat damage, no target, hits fliers, stacks (S4). |
| Stealth | Sneaks past patrollers if that opponent has no detector. The defender still hits back (S4). |
| Swift strike | Deals combat damage before forces without swift strike. If it kills them, they deal none. Both with it → simultaneous (S4). |
| Trash | Remove from game. |
| Unattackable | Cannot be attacked; may be ignored while patrolling. |
| Unstoppable | Can ignore patrollers when attacking. Detectors do not stop it (S4). |
| Untargetable | Cannot be the target of spells or abilities. |
| Upkeep: X | Do X in your upkeep. |
| Flagbearer (subtype) | Opponent spells/abilities that can target a flagbearer must target one at least once (card text). |
| Limit: X | Cap on runes/tokens from that card (card text, e.g. Harmony "limit: 3"). |

---

## 11. Runes and tokens (S1 p. 8, p. 17)

- +1/+1 and -1/-1 runes change ATK/HP. A +1/+1 and a -1/-1 on the same object destroy each other.
- HP ≤ 0 → dies at once.
- Time runes: fading and forecast. Other named runes: card-specific (blood rune, sword rune, ...).
- Tokens: tech 0 units; destroyed when they leave play.

---

## 12. Win condition (S1 p. 1, p. 9)

- Destroy the opponent's base (20 HP). The game ends at once.
- 2v2 "Two-Headed Dragon": shared 30-HP base per team; P1 team 4 workers each, P2 team 5 each. (S1 p. 13)
- Free-for-all 3-5 players: ends when any base is destroyed; highest base HP wins. (S1 p. 14)

---

## 13. Map cards (Deluxe, optional, S1 p. 7)

12 maps. Text from S3 `maps.json` and S7 sheet 33: Big Game Hunters (+2 gold each upkeep), Hard Times Mill (workers cost +1),
Daggerfall Prison Camp (hiring costs no card), Flagstone Mines (hire any number per turn), Bloodbowl (all units +1 ATK and haste),
Mystical Forest, Burial Grounds (a dead hero is gone for the game), Pinnacle, Vortoss Ruins, No Rush 15 Minutes, Fury Road (1 patroller max), Lost Temple.
Not needed for the first slice.

---

## 14. Card data (machine-readable)

### 14.1 Recommended source: codexcarddb raw data (S3)

- Repo: https://github.com/rgdelato/codex-cards-gatsby (branch `master`). Licence file: MIT ("Copyright (c) 2015 gatsbyjs";
  it covers the site code). ⚠️ The card texts and art are © Sirlin Games. No licence for them is stated.
- Site: https://www.codexcarddb.com/ (Nick's chosen source). Raw URL pattern:
  `https://raw.githubusercontent.com/rgdelato/codex-cards-gatsby/HEAD/raw_data/<color>.json`.
  Local copies: scratchpad `codex/carddb/` (colour + heroes files) and `codex/research/codexcarddb/` (also maps, rulings).
- Raw downloads:
  - https://raw.githubusercontent.com/rgdelato/codex-cards-gatsby/master/raw_data/neutral.json
  - https://raw.githubusercontent.com/rgdelato/codex-cards-gatsby/master/raw_data/red.json
  - https://raw.githubusercontent.com/rgdelato/codex-cards-gatsby/master/raw_data/green.json
  - https://raw.githubusercontent.com/rgdelato/codex-cards-gatsby/master/raw_data/blue.json
  - https://raw.githubusercontent.com/rgdelato/codex-cards-gatsby/master/raw_data/black.json
  - https://raw.githubusercontent.com/rgdelato/codex-cards-gatsby/master/raw_data/white.json
  - https://raw.githubusercontent.com/rgdelato/codex-cards-gatsby/master/raw_data/purple.json
  - https://raw.githubusercontent.com/rgdelato/codex-cards-gatsby/master/raw_data/heroes.json
  - https://raw.githubusercontent.com/rgdelato/codex-cards-gatsby/master/raw_data/maps.json
  - https://raw.githubusercontent.com/rgdelato/codex-cards-gatsby/master/raw_data/rulings.json
- Size: 362 records (342 cards + 20 heroes), each file 23-29 KB; rulings.json 156 KB.
- Each colour file: 36 codex cards (3 specs × 12; neutral 2 × 12 = 24), 10 starting-deck cards, 2 worker records,
  plus tokens and (neutral only) Base, Tech I-III, the 4 add-ons and Mercenary.
- Fields (one record per distinct card; 2 copies each in the codex):
  `name, color, spec, type, subtype, cost, tech_level, ATK, HP, rules_text_1..4, target_icon, starting_zone, flavor_text, filename, sirlins_filename, sha1`.
  Heroes: `ATK_1, HP_1, base_text_1..2, mid_level, ATK_2, HP_2, mid_text_1..2, max_level, ATK_3, HP_3, max_text_1..2`.
- `starting_zone`: `deck` (starting deck), `codex`, `command` (hero), `worker`, `trash` (tokens, buildings, add-ons; i.e. "not in a deck").
- Quirks:
  - Spells have no `tech_level`. Units in the codex: tech 1 ×36, tech 2 ×82, tech 3 ×15.
  - On Tech II/III building records, `tech_level` is the **prerequisite** building level (1 and 2).
  - Tower text ends with "Anti-air (?)". S1 confirms anti-air.
  - ⚠️ **Master Midori** mid band in S3 is "Your units with no abilities get +1/+1." S6 has the later patch text
    "Your units with no abilities cost ① less to play and get +2/+2.", and the S4 rulings speak of +2/+2 and the cost
    reduction. Use the S6 text for Midori.
  - Other patched values are present in S3 and S6 (Giant Panda 2/4 for 3, R&D "Draw five cards" for 2,
    Patriot Gryphon 8, Spectral Roc 4, Skeletal Lord "Exhaust five").
- Rulings file: keys `General, Neutral, Red, Green, Blue, Black, White, Purple, Heroes`; records `{card, ruling, date, author, abilityText?}`.

### 14.2 Other sources found

- S6 `sharpobject/codex_rules`: the same JSON shape (S3 descends from it), plus a `pedantry` field. No licence. Last push 2016-07.
  Same 362 names as S3; the only difference is Master Midori (above).
  Raw: `https://raw.githubusercontent.com/sharpobject/codex_rules/master/<colour>.json`.
- `adambiltcliffe/codex` (ISC, 2022): a JS rules engine with per-spec card code in `src/cardinfo/*.js` and tests per keyword
  (`src/cardinfo/abilities/*.test.js`). Not a data file, but a good reference for edge cases.
- `rgraciano/codex` (MIT, 2022): TypeScript engine, one class per card (`src/cards/<colour>/<spec>/*.ts`).
- Official "Codex Cards Spreadsheet" (Google Sheets, linked in S5):
  https://docs.google.com/spreadsheets/d/1IB2D82Fsd8cZ3gGDRAB3Dkd0eUSMURYJKpRq9Ho81q0/ (not checked).
- No JSON on BGG or the Sirlin forums.

---

## 15. TTS mod "Codex Deluxe Set" (S7)

Every `CustomDeck` sheet is a **10 × 7 grid** (NumWidth 10, NumHeight 7), 4096 × 4096 px, so one cell is 409.6 × 585 px.
CardID = deckId × 100 + index; index is row-major from top left (0..69). Card nicknames are empty on most cards;
I mapped the sheets by looking at the cached images.

| Deck id | Face URL | Content |
|---|---|---|
| 1 | `theshobo.com/codex/deck.png` | Neutral: Bashing + Finesse codex, both heroes, neutral starter (44 cards). Still online (22 MB). Not in local cache. |
| 2 | `theshobo.com/codex/deck.png?v=1` | Same image (only Brick Thief uses it). |
| 5 | `http://cloud-3.steamusercontent.com/ugc/835832657114541905/79F13E7977C1B706EEA2A31304B99AD2F64CA23C/` | White worker x4 (index 0). Back `.../835832657114542239/ED51B6FF2549214DF3AF7D6C429D0BE0AE28B4E7/` = x5 side. |
| 8 | `.../ugc/835832657115148478/CD4D6B6412B1E32B3BD9EAB438B7F71E80F44069/` | Red worker x4 (back = x5). |
| 10 | `.../ugc/835832813003748318/061851BC68F9A1C7FA1E24CA760EF33D52AAC333/` | Green worker x4. |
| 12 | `.../ugc/835832813003859137/53C3F13DC378D2EFC9A9A75333499D3DF3171553/` | Blue worker x4. |
| 14 | `.../ugc/835832813004064880/0E675A5DAD39FA832B8580AD15C36363D066857F/` | Purple worker x4. |
| 16 | `.../ugc/835832813004167726/83F351635E5AE4DA6FE4FBE8756C5B49F7E3B577/` | Black worker x4. |
| 17, 32 | `.../ugc/835832813004343624/163DF7ECD4375FAFD4D6412F1DADE5B71B6C6366/` | 20 spec mini-cards (index 0-19: Bashing, Finesse, Anarchy, Blood, Fire, Balance, Feral, Growth, Law, Peace, Truth, Demonology, Disease, Necromancy, Discipline, Ninjutsu, Strength, Past, Present, Future). |
| 18 | `.../ugc/835832813004392397/1B48A292B49FAFE11630BDCA58BEBDE2257FBFBD/` | Add-ons (0 Tower, 1 Surplus, 2 Tech Lab, 3 Heroes' Hall), tokens (4-24: Pirate, Shark, Elemental, Wisp, Frog, Beast, Squirrel, Hunter, Soldier, Mirror Illusion, Skeleton, Zombie, Horror, Warlock, Bird, Ninja, Ghost, Mech, Stinger, Mercenary, Dancer), 25 neutral worker x4. |
| 20 | `.../ugc/835832813003999964/9569287EF1675BB987A7520ED223F7134C5818E3/` | Purple: 0-2 heroes, 3-12 starter, 13-48 codex. |
| 21 | `.../ugc/835832657115101722/A46870CB2B331265ABD80799E2D08E1DE6BDBA65/` | Red: same layout. |
| 22 | `.../ugc/835832813003826804/9CA9E96F2BD8F2847536697F95CFEA4365A16116/` | Blue: same layout. |
| 29 | `.../ugc/835832657116480813/F3853E3A4CBEBFB448859849D52C9656F3D04A60/` | Green: same layout. |
| 31 | `.../ugc/835832813004129641/0BAB8B262622F251EBF7205E30890A85845805D1/` | Black: same layout. |
| 25 | `.../ugc/835832657114498910/1D4AD277A02A35738FE80E7FEE0B9A9FA1111BFD/` | White heroes (0-2) + white starter (3-12). |
| 30 | `.../ugc/835832657114648386/6389D5922A973BF20CB320EA391E6FC2AA584256/` | White codex (36 cards). |
| 33 | `.../ugc/835833377774704178/D98BCFF77833E96BD8439A9589A202A2DC8C55DB/` | 12 map cards (0-11). |

`...` = `http://cloud-3.steamusercontent.com`. Card back for most sheets: `theshobo.com/codex/card_back.png`.
Board: `Custom_Board` image `http://cloud-3.steamusercontent.com/ugc/835833377773148914/A0DA933AB8C8D61952FB915F1B494FE...` (truncated in my dump; see the JSON).

⚠️ The `cloud-3.steamusercontent.com` URLs now return **403**, and the `steamusercontent-a.akamaihd.net` form returns 404.
The images exist only in the local cache: `~/Library/Tabletop Simulator/Mods/Images/httpssteamusercontentaakamaihdnetugc<id><hash>.png`
(all 16 Steam sheets are there). Downscaled copies: scratchpad `codex/research/thumbs/d<deckId>.png`.

Neutral sheet (deck 1) index map from S7 nicknames:
0 Wrecking Ball, 2 Grounded Guide, 3 The Boot, 4 Nimble Fencer, 5 Maestro, 6 Intimidate, 10 Harmony, 11 Appel Stomp,
12 Leaping Lizard, 13 Discord, 15 Blademaster, 16 Two Step, 17 Eggship, 18 Fruit Ninja, 19 Backstabber, 23 River Montoya,
25 Troq Bashar, 26 Timely Messenger, 28 Star-Crossed Starlet, 29 Iron Man, 30 Helpful Turtle, 31 Spark, 32 Older Brother,
33 Granfalloon Flagbearer, 34 Bloom, 35 Wither, 36 Hired Stomper, 37 Cloud Sprite, 38 Tenderfoot, 2:27 Brick Thief.
Unnamed: 1, 39-43 = the 6 remaining Bashing cards (Final Smash, Revolver Ocelot, Regular-sized Rhinoceros, Sneaky Pig,
Harvest Reaper, Trojan Duck); order not known. Indexes 7-9, 14, 20-22, 24, 27 are not used by objects in the save.

---

## 16. First playable slice (recommendation)

**Use the official first-game set-up: Neutral starter deck for both players, Bashing hero vs Finesse hero, 1-hero mode, no maps** (S1 p. 7).
Reasons:
- It is the set-up that Sirlin tells new players to use. The Deluxe box has 2 neutral starter decks for this.
- Neutral minor spells have no colour tax. No multicolour tax. No tech II spec choice (only 1 spec each).
- 1 spec each = 12 codex cards. 10 + 12 + 12 + 1 + 1 = 36 distinct cards in total.
- Mechanics needed: haste, healing, resist, frenzy, flagbearer, sparkshot, stealth, invisible, flying, anti-air, overpower,
  obliterate, readiness, swift strike, +1/+1 and -1/-1 runes, channeling, tokens (Dancer/Angry Dancer), sideline, control change (Final Smash).

Build order inside the slice:
1. Economy and turn loop: workers, gold cap, hire, draw/discard, reshuffle once, tech 2 cards, buildings finish at end of turn.
2. Tech-0 units, patrol zone, attack legality, simultaneous damage, armor, base damage, win.
3. Heroes: summon, levels, band heals, death + cooldown + 2 free levels for the killer side.
4. Spells and keywords on the cards below.
5. Tech I-III, Tower, Surplus.
6. Hard cards last: Final Smash (control change), Harmony/Dancers (flip), Two Step (pairs), Appel Stomp (top of deck), Maestro (granted ability), Trojan Duck (obliterate).

A good second slice: **Red (Anarchy/Blood/Fire) vs Green (Balance/Feral/Growth)**, the Core Set pairing (S1 p. 7, p. 10).

### 16.1 Neutral starting deck (10 cards, all tech 0) (S3)

| Card | Type | Cost | ATK/HP | Text |
|---|---|---|---|---|
| Timely Messenger | Unit — Mercenary | 1 | 1/1 | Haste. |
| Tenderfoot | Unit — Virtuoso | 1 | 1/2 | — |
| Older Brother | Unit — Drunkard | 2 | 2/2 | — |
| Brick Thief | Unit — Mercenary | 2 | 2/1 | Arrives or attacks: Deal 1 damage to a building and repair 1 damage from another building. Resist 1. |
| Helpful Turtle | Unit — Cute Animal | 2 | 1/2 | Healing 1. |
| Granfalloon Flagbearer | Unit — Flagbearer | 3 | 2/2 | Whenever an opponent plays a spell or ability that can ◎ a flagbearer, it must ◎ a flagbearer at least once. |
| Fruit Ninja | Unit — Ninja | 3 | 2/2 | Frenzy 1. |
| Spark | Minor Spell — Burn ◎ | 1 | — | Deal 1 damage to a patroller. |
| Bloom | Minor Spell — Buff ◎ | 2 | — | Put a +1/+1 rune on a friendly unit or hero that doesn't have a +1/+1 rune. |
| Wither | Minor Spell — Debuff ◎ | 2 | — | Put a -1/-1 rune on a unit or hero. |

Neutral tokens (S3): Dancer 0/1 "When you 'stop the music,' flip this." ↔ Angry Dancer 2/1 Unstoppable. Mercenary 1/1 (free-for-all only).

### 16.2 Bashing (hero + 12 codex cards, 2 copies each) (S3)

Hero **Troq Bashar** (Renegade Beast), cost 2.
- Lv 1-4: 2/3, no text.
- Lv 5-7: 3/4, "Attacks: Deal 1 damage to that opponent's base. ◎" (S4: the base of the player who controls the attacked thing.)
- Lv 8 (max): 4/5, "Readiness."

| Card | Type | Tech | Cost | ATK/HP | Text |
|---|---|---|---|---|---|
| Wrecking Ball | Spell ◎ | - | 0 | — | Deal 2 damage to a building. |
| The Boot | Spell — Debuff ◎ | - | 3 | — | Destroy a tech 0 or tech I unit. (Heroes aren't units.) |
| Intimidate | Spell — Debuff ◎ | - | 1 | — | Give a unit or hero -4 ATK this turn. |
| Final Smash | Ultimate Spell — Debuff ◎ | - | 6 | — | Destroy a tech 0 unit, return a tech I unit to its owner's hand, and gain control of a tech II unit. |
| Iron Man | Unit — Mercenary | I | 3 | 3/4 | — |
| Revolver Ocelot | Unit — Leopard | I | 2 | 3/3 | Sparkshot. |
| Hired Stomper | Unit — Lizardman ◎ | II | 4 | 4/3 | Arrives: Deal 3 damage to a unit. |
| Regular-sized Rhinoceros | Unit — Rhino | II | 4 | 5/6 | — |
| Sneaky Pig | Unit — Pig | II | 3 | 3/3 | Haste. Arrives: Gets stealth this turn. |
| Eggship | Unit — Contraption | II | 4 | 4/3 | Flying. |
| Harvest Reaper | Unit — Contraption | II | 5 | 6/5 | Overpower. |
| Trojan Duck | Unit — Contraption ◎ | III | 7 | 8/9 | Obliterate 2. Arrives or attacks: Deal 4 damage to a building. |

Final Smash rulings (S4): do as much as you can; parts are mandatory even on your own units; pick each target as that part resolves.

### 16.3 Finesse (hero + 12 codex cards, 2 copies each) (S3)

Hero **River Montoya** (Dancing Fencer), cost 2.
- Lv 1-2: 2/3, no text.
- Lv 3-4: 2/4, "⤵ → Sideline a tech 0 or tech I patroller. ◎"
- Lv 5 (max): 3/4, "Your tech 0 units cost ① less to play." (min cost 0, S4)

| Card | Type | Tech | Cost | ATK/HP | Text |
|---|---|---|---|---|---|
| Harmony | Ongoing Spell — Buff | - | 2 | — | Channeling. Whenever you play a spell, summon a 0/1 neutral Dancer token (limit: 3). Sacrifice Harmony → "Stop the music." (Your Dancers flip over.) |
| Discord | Spell — Debuff | - | 2 | — | Give all of an opponent's tech 0 and I units -2/-1 until end of turn. |
| Two Step | Ongoing Spell — Buff ◎ | - | 2 | — | Channeling. Two of your units become dance partners if they aren't partnered already. While you control both, they each get +2/+2. If you lose one, sacrifice Two Step. |
| Appel Stomp | Ultimate Spell — Debuff ◎ | - | 1 | — | Sideline a patroller, draw a card, then you may put Appel Stomp on top of your draw pile. |
| Nimble Fencer | Unit — Virtuoso | I | 2 | 2/3 | Your Virtuosos have haste. |
| Star-Crossed Starlet | Unit — Virtuoso | I | 2 | 3/2 | Upkeep: This takes 1 damage. This gets +1 ATK for each damage on her. |
| Grounded Guide | Unit — Thespian | II | 5 | 4/4 | Your other units get +1 ATK. Your Virtuosos get +2/+1 instead. |
| Maestro | Unit — Thespian | II | 3 | 3/5 | Your Virtuosos cost ⓪ to play and gain "⤵ → Deal 2 damage to a building. ◎" |
| Backstabber | Unit — Rogue | II | 3 | 3/3 | Invisible. |
| Cloud Sprite | Unit — Fairy | II | 2 | 3/2 | Flying. |
| Leaping Lizard | Unit — Lizardman | II | 1 | 3/5 | Anti-air. |
| Blademaster | Unit — Virtuoso | III | 6 | 7/5 | Your units and heroes have swift strike. |

Finesse rulings (S4):
- Harmony does not trigger on itself. The Dancer arrives after the triggering spell resolves fully.
  Losing the Finesse hero sacrifices Harmony but does **not** "stop the music".
- Two Step: a partnered unit is not a legal target for a second Two Step. "Lose one" = leaves play or leaves your control.
- Appel Stomp: if not put on top of the draw pile, it goes to the discard pile.
- Maestro: the granted ⤵ ability still needs the Virtuoso under your control since start of turn (or haste).
- Tenderfoot (starter) is a Virtuoso, so Nimble Fencer, Maestro and Grounded Guide affect it.

### 16.4 Second slice reference: Red and Green starting decks (S3)

Red (workers "Scallywag"): Nautical Dog 1 1/1 Frenzy 1; Mad Man 1 1/1 Haste; Bombaster 2 2/2 "①, Sacrifice Bombaster → Deal 2 damage to a patrolling unit."; Careless Musketeer 2 2/1 "⤵ → Deal 1 damage to a unit or building and 1 damage to your base."; Bloodrage Ogre 2 3/2 "End of turn: Return to owner's hand if he didn't arrive or attack this turn."; Makeshift Rambaster 2 1/2 Haste, +2 ATK when attacking buildings, can't patrol; Bloodburn (Upgrade) 3 "Whenever a unit dies, put a blood rune on this (limit: 4). ⤵, remove two blood runes → Deal 1 damage to a unit or building."; Scorch (minor) 3 "Deal 2 damage to a patroller or building."; Charge (minor) 2 "Give one of your units haste and +1 ATK this turn."; Pillage (minor) 1 "Deal 1 damage to a base. Steal ① from that player. If you have a Pirate, instead deal 2 damage and steal ②."

Green: Merfolk Prospector 1 1/1 "⤵ → Gain ①."; Tiger Cub 2 2/2; Young Treant 2 0/2 "Arrives: Draw a card. Can't attack."; Playful Panda 2 2/2 "Arrives: Exhausted. Summon a 0/1 green Wisp token." ⚠️ (S3 text; check the card image); Ironbark Treant 3 3/2 "-2 ATK / +2 armor while patrolling."; Spore Shambler 3 0/1 "Arrives: Put two +1/+1 runes on this. ① or ⤵, then remove a +1/+1 rune → Put a +1/+1 rune on another unit."; Verdant Tree (Building) 2 HP 3 "Healing 1. ⤵ → Your tech buildings build instantly this turn."; Rich Earth (Upgrade) 3 "You may hire workers for free."; Rampant Growth (minor) 2 "+2 ATK / +2 armor this turn."; Forest's Favor (minor) 2 "+1/+1 rune on a friendly unit or hero without one."

Red heroes (S3): Captain Zane (Anarchy, bands 1-3/4-5/6), Drakk Ramhorn (Blood, 1-3/4-5/6), Jaina Stormborne (Fire, 1-3/4-6/7).
Green heroes (S3): Master Midori (Balance, 1-4/5-7/8; see Midori quirk §14.1), Calamandra Moss (Feral, 1-2/3-4/5), Argagarg Garg (Growth, 1-2/3-4/5).

### 16.5 Blue and Black in the engine (built 2026-10-17)

Preset `blue_black`: P1 Blue (Law, Peace, Truth; Blue starting deck), P2 Black
(Demonology, Disease, Necromancy; Black starting deck), 3 heroes each, 72 codex
cards each. Preset `black_blue` swaps the seats (for the bot bench).

All 20 starting-deck cards, the 6 heroes and the 72 codex cards run. No card is
"manual". Tests: one file per spec (`test/codex/law_test.exs` ...) and
`test/codex/blue_black_starters_test.exs`.

New shared mechanics (`Codex.Effects`, `Codex.Stats`, `Codex.Rules`, `Codex.Combat`):

- Disable: exhaust, sideline, no ready in the next ready step.
- Illusion: dies when a spell or ability with ◎ targets it, before the effect
  (rulings: Insurance Agent). Only ◎ targets count: a card without the ◎ icon,
  and the choice slots (sacrifice, hand, codex), do not kill it. Arrest and
  Zarramonde have a ◎ that the data file misses.
- Copies (Manufactured Truth, Sirus Quince): the printed card, no modifiers.
- Damage as -1/-1 runes; "dies from combat damage"; "would die" replacements
  (indestructible, Soul Stone, Two Lives, Brave Knight).
- Stash, silence (Free Speech), detector, unattackable, "unstoppable when
  attacking a building or a hero", "unstoppable by" some units, a flying base,
  the Blackhand Dozer base floor, Injunction (a building not operational).

Decisions where the card lets a player choose, or where the rules are not
clear (each has a `# REVIEW:` in the code):

| Card | Engine reading |
|---|---|
| Jail, Graveyard | No new zone: jailed or buried units wait in the trash, marked. A released or exhumed unit arrives with no "Arrives:" targets. |
| Stash | The hand ends at the size it would have had without the stash (rulings example). |
| Reputable Newsman | The choice is cost 0 to 8; the printed cost counts. |
| Community Service | The engine takes the costliest tech I/II unit (hand first on a tie). |
| Carrion Curse | The engine discards the two costliest non-unit cards. |
| Lawful Search | The look at a hand or a discard pile has no effect (hot seat shows both hands). |
| Sirus Quince, max level | The first plain Mirror always copies ("you may"). |
| Vandy Anadrose, max level | Opposing unit: most ATK + HP; friendly unit: least. |
| Orpal Gloor, max level | The two friendly units with the least HP left. |
| Plague Lab | -1/-1 on each opposing card with one, +1/+1 on each own card with one. |
| Voidblocker | The attacker's ready force with the least ATK is exhausted. |
| Blackhand Dozer, dies | Active player: its own weakest, or the opponent's strongest of the lowest tech. All damage to a base counts as dealt by the other side for the floor. |
| Banefire Golem | Sacrifices the weakest other unit, else itself. |
| Death Rites | Destroys the strongest of the opponent's lowest tech units. |
| Sacrifice the Weak, Hooded Executioner | A tie goes to the lowest id. |
| Blackhand Resurrector | The hero limit still applies. |

---

## 17. Engine notes for the builder

- Hidden information: hand, draw pile order, discard pile (face down), codex choices, tech picks, worker cards. The engine state holds them; the view must hide them.
- The tech pick for player A is due only "just before A's next turn starts". The opponent may play meanwhile. A simple engine can force the pick at end of turn.
- Shuffles: use the `:rand` `_s` API on state in the game struct (project rule). Shuffle points: setup, and the once-per-main-phase reshuffle.
- Choices inside effects (targets, Final Smash parts, overpower spill, sparkshot side, free-level hero) are all by the active player. Model them as pending-decision states.
- Damage is a counter on each card, not a reduced HP value. Healing removes counters only. Runes change base stats.
- Tower and sparkshot damage are part of the same simultaneous combat-damage step. Swift strike makes two steps.
- Arrival fatigue needs "under control since start of turn" per card (tracks control changes too).
- Patrol-lock happens at end of main phase; "patroller" status is only valid on the opponent's turn.

### Uncertain points

- ⚠️ Starting gold 0: inferred from S1 p. 9, not stated as a number.
- ⚠️ Tech II gold 4 and Tech III gold 5: from S3 card records only. S1 gives the worker needs but no gold cost for tech II/III.
- ⚠️ Rulebook v46 is from March 2016. Later errata live in the Official Rulings Spreadsheet (S5), which I did not read.
- ⚠️ Master Midori text differs between S3 and S6 (§14.1).
- ⚠️ Six neutral-sheet indexes (1, 39-43) are not mapped to names (§15).

---

## Sources (useful links from "Collected Codex Resources")

Thread: https://forums.sirlingames.com/t/collected-codex-resources/860

- Official rulebooks, searchable PDFs (rulebook v46 + starter v32; main source for §2-§12): https://www.dropbox.com/sh/oqxpfz2bpkln4hq/AACbSiB6hRBCz-8HKdGFkNJIa?dl=0
- Official Rulings Spreadsheet (errata, clarifications): https://docs.google.com/spreadsheets/d/1WyO1v5RCqBQwKYi4tfKOqOjRfTn2h9PDzvUMgSF4S2Y/
- Rules Questions Thread: http://forums.sirlingames.com/t/rules-questions-thread/146/2
- Codex Card Database (card images, ruling summaries): http://codexcarddb.com/ (data: https://github.com/rgdelato/codex-cards-gatsby)
- Codex Cards Spreadsheet (official card list): https://docs.google.com/spreadsheets/d/1IB2D82Fsd8cZ3gGDRAB3Dkd0eUSMURYJKpRq9Ho81q0/
- Unofficial Rulebook Rewrite (dreamshade; secondary): http://forums.sirlingames.com/t/codex-unofficial-manual-rewrite/4003
- Towards a Comprehensive Rulebook (Persephone; secondary): http://forums.sirlingames.com/t/towards-a-comprehensive-rulebook-proposed-errata-rules-changes-partial-draft-request-for-feedback/6208/1
- Map Card List: http://forums.sirlingames.com/t/map-card-list/639/2
- Deck Reference Website (Offkilter): https://forums.sirlingames.com/t/i-made-a-thing-deck-reference-website/8718
- Codex Forum Game Template (tracking sheet; a model of full game state): http://forums.sirlingames.com/t/codex-tracking-spreadsheet/383
- Card ratings, starter decks: http://forums.sirlingames.com/t/card-ratings-the-starter-decks/171
- Card ratings, heroes: http://forums.sirlingames.com/t/card-ratings-the-heroes/172
- Beginner's Guide to Workers: http://forums.sirlingames.com/t/guide-beginners-guide-to-workers/1003
- Beginner's Guide to Teching: http://forums.sirlingames.com/t/guide-beginners-guide-to-teching/1421
- New Player Reference Sheets: http://forums.sirlingames.com/t/new-player-reference-sheets/1077
- Sirlin rulings list (named in rulebook p. 18): http://www.sirlin.net/rules
