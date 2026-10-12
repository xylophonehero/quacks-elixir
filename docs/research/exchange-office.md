# Wolfgang's Exchange Office (Wolfgangs Wechselstube)

Research and design for the promo mini-expansion. Compiled 2026-10-11. Status: research only.
Build it after the UI component refactor. Read with `pot-reverse-and-faq.md` §1 (the
**droplet choice**, which this expansion uses again) and `rulebook.md` §3, §7.

Text marked ⚠️ is not confirmed by an official source.

## 0. Summary

- A shared test-tube stand ("Reagenzglasständer") in the middle of the table. Each player puts
  a second droplet on it. Two sides: **brown** (end-game VP from all your chips) and **green**
  (buy VP with coins during the game).
- Each time you can move your droplet, you choose: the pot droplet or the stand droplet. This is
  the same choice as the reverse pot side. The engine already has it (`Game.move_droplet/3`,
  `:droplet_choice`, `{:droplet, :pot | :tube}`).
- Official: you can play it **only with the front side of the pot** ("nur mit der
  Kesselvorderseite"). So it never combines with `pot_side: :back`. The engine can use the same
  `Player.tube` field (0..12) for the stand droplet.
- Size: engine about 1 builder round (M); UI about 1 builder round (M). See §8.

## 1. Sources

- **S1 Official German rules sheet** (Schmidt Spiele, from the Deutscher Spielepreis 2018 Goodie
  Box; the same sheet is in the Big Box, file name `49390_Quacksalber_BigBox_Anleitung_Wolfgangs_Wechselstube.pdf`).
  Photo on BGG, image 4494454, linked by German Wikipedia as "Offizielle Spielregeln … Volltext":
  https://boardgamegeek.com/image/4494454/quacks-quedlinburg-wolfgangs-exchange-office
  (full-size file: https://cf.geekdo-images.com/Zngg3yI2KUhbu6lOCD1GQg__original/img/9O6N8T0iAngkO0xB5594LooTMbI=/0x0/filters:format(jpeg)/pic4494454.jpg ,
  found with `https://api.geekdo.com/api/images/4494454`). The photo also shows the brown side
  of the stand. The PDF itself was not found on schmidtspiele.de (404 on the guessed paths).
- **S2 English text** in Nick's Tabletop Simulator mod (`1864138254`, object "Wolfgang's Exchange
  Office", a `Custom_Model` with no description). The rules PDF from the TTS cache, copied to the
  scratchpad as `tts/exchange.pdf`. Its text is the same as the BGG expansion description
  (BGG 264019, mirrored on https://jogonamesa.pt/X/ficha.cgi?bgg_id=264019). It is a fan
  translation of S1, with small additions ("bag **and cauldron**").
- **S3 Stand image** from the TTS cache (`tts/exchange.jpg`). I read it myself (§2.4).
- **S4 Roger BellWest rules summary** v0.002, 2024-05-15 (covers all expansions and the
  Exchange Office): http://tekeli.li/rogers-rules/quacks_rules.pdf . It puts the VP purchase in
  the buy step and says "divide … and round down".
- **S5 German Wikipedia**, section "Wolfgangs Wechselstube":
  https://de.wikipedia.org/wiki/Die_Quacksalber_von_Quedlinburg (Goodie Box at Spiel 2018 in
  Essen; Big Box contents).
- **S6 boardbattle.de** review: https://www.boardbattle.de/brettspiele/quacksalber-von-quedlinburg/ .
  It says the brown side scores "am Ende jeder Runde" (at the end of each round) from "Chips, die
  sich noch im Beutel befinden". This **disagrees** with S1 ("Bei Spielende"). We ignore S6 on
  this point.
- BGG forum threads: none found. The BGG XML API and pages return 401/403 to our fetcher. ⚠️ We
  found no official FAQ or designer answer for the open questions in §3.

Other names: German "Wolfgangs Wechselstube"; English "Wolfgang's Exchange Office". Release:
Deutscher Spielepreis 2018 Goodie Box (Internationale Spieltage, Essen, October 2018), with
promos for Azul, Rajas of the Ganges, Altiplano and Black Stories. Later in the German "Big Box"
(base game + Die Kräuterhexen + Wechselstube).

## 2. The rules

### 2.1 Official text (S1, German, transcribed from the photo)

> **Wolfgangs Wechselstube**
> *Diese Variante ist nur mit der Kesselvorderseite zusammen spielbar.*
>
> **Spielvorbereitung**
> Legt den Reagenzglasständer (bestehend aus 2 Teilen) in der Tischmitte aus. Legt auf das
> Reagenzglas ganz links je einen Tropfen pro Spielerfarbe.
>
> **Spielablauf**
> Immer wenn ihr im Verlaufe des Spiels einen Tropfen vorwärtsbewegen könnt (durch eine
> Wahrsagekarte, durch Chip-Aktionen oder durch das Bezahlen von 2 Rubinen), könnt ihr euch
> entscheiden, welchen eurer beiden Tropfen ihr vorwärts bewegen wollt: Den Tropfen im Kessel oder
> den auf den Reagenzgläsern in der Tischmitte. Entscheidet ihr euch für den Tropfen auf den
> Reagenzgläsern, so wird dieser 1 Glas weiter nach rechts bewegt. Ihr könnt dadurch leichter an
> Siegpunkte kommen. Je nachdem mit welcher Seite des Reagenzglasständers ihr spielt habt ihr
> folgende Verbesserungen:
>
> [brown icon: chips : 1]
> Bei Spielende leeren alle Spieler ihre Beutel und zählen alle Zahlen auf ihren Chips (inkl.
> weiße Chips) zusammen. Den Gesamtwert müssen sie durch den Zahlenwert teilen, den sie mit ihrem
> Tropfen erreicht haben. Sollte der Tropfen z.B. noch auf dem Startfeld stehen, wird der
> Gesamtwert durch 15 geteilt.
>
> [green icon: ? : 1]
> Die Spieler können sich bereits **im Spielverlauf** neben Zutaten auch Siegpunkte kaufen. Der
> Kaufpreis für **Siegpunkte** wird durch die Position des Tropfens festgelegt. Zu Spielbeginn,
> wenn der Tropfen noch nicht vorwärts gezogen wurde, kostet ein Siegpunkt 12 Geld. Sollte ein
> Spieler seinen Tropfen bis zum letzten Reagenzglas vorangetrieben haben, kostet ihn ein
> Siegpunkt 2 Geld. Ein Spieler kann in einer Runde beliebig viele Siegpunkte (sofern er genug
> Geld hat) kaufen.

### 2.2 English text (S2, the fan translation; typos as in the source)

> This mini-expansion can only be played when you use the front sides of the cauldrons, as it
> uses the extra droplet from each player.
>
> Setup: Choose whether to use the brown side or green side of the test tube stand. Assemble the
> test tube stand (consisting of 2 parts) and place it in the middle of the table with the chosen
> side facing up. Place an unused droplet of each player's color on the leftmost test tube (on nr.
> 15 for the brown side, on nr. 12 for the green side). The track is shared by all players.
>
> Gameplay: Whenever you get the opportunity to move your droplet forward in the course of the
> game (either with a fortune telling card, a chip-action or by paying 2 rubies), you may either
> move your droplet in your cauldron as normal or you may move your droplet on the test tube stand
> in the middle of the table. If you decide for the drop on the test tubes, you move the drop one
> glass forward to the right. […]
>
> Brown side: At the end of the game, all players empty their bags and add up the values of all
> of their chips in their bag and cauldron (white chips included). Each player divides their total
> value by the value of the test tube their droplet is at on the test tube stand, and this number
> is added as VP to their final score. For example, if the chips in your bag and cauldron add up to
> 60, you would gain 4 VP if your droplet is at "15" (60 divided by 15), but if you managed to get
> your droplet all the way to "2" you would gain 30 VP (60 divided by 2)! Note that the track is
> only used in the end game scoring, there are no benefits just by moving your drop during each
> turn.
>
> Green side: Players can buy ingredients as well as victory points during the course of the
> game. The purchase price for each victory point is determined by the position of the drop. At
> the start of the game, when the drop has not been moved forward yet, one victory point costs 12
> money. if a player has moved their drop to the last test tube, one victory point costs only 2
> money. A player may buy any number of victory points during a round, if they have enough money
> to afford it. Not that you get the chance to buy victory points during every turn of the game,
> but they are very expensive during the first rounds.

### 2.3 Rules, item by item

- **Front pot side only (S1, S2).** The second droplet of each colour goes on the stand. The
  reverse pot side (test tubes on the pot) also needs that droplet, so the two never combine.
- **Setup.** Choose one side (brown or green). One stand in the middle of the table, shared. Each
  player puts a droplet on the leftmost tube (brown 15, green 12).
- **The stand is shared, the droplets are not.** Each player has an own droplet and an own
  position. The stand is one board for the table only. Several droplets can be on the same tube
  (S1 says nothing to stop it, like the scoring track). No interaction between players.
- **Moving.** Every time a player can move a droplet ("Wahrsagekarte, Chip-Aktionen, 2 Rubine"),
  that player chooses: the pot droplet (as usual) or the stand droplet (1 tube to the right).
  This is the same choice as the reverse pot side (`pot-reverse-and-faq.md` §1.3).
- **Brown side, end of game only.** No effect during the game. At the game end each player adds
  the values of **all** their chips, white chips included, and divides the total by the number
  under their stand droplet. The result is VP. S2 says "bag and cauldron"; S1 says "empty your
  bags", which means the same chips at the game end.
- **Green side, during the game.** In the buy phase ("neben Zutaten", next to ingredients), a
  player can buy VP with coins ("Geld"). The price per VP is the number under the stand droplet:
  12 at the start, 2 on the last tube. Any number of VP per round, while the coins last.
- **Coins.** Leftover coins are lost at the end of a round (rulebook). So on the green side, coins
  that the chips do not use can become VP at once.

### 2.4 The stand (S3, read from the image; S1 photo agrees for the brown side)

13 tubes. The droplet starts on tube 0 (leftmost). Index = number of moves made.

| Tube | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Green: coins per 1 VP | 12 | 10 | 9 | 8 | 7 | 6 | 5 | 5 | 4 | 4 | 3 | 3 | 2 |
| Brown: divisor | 15 | 13 | 11 | 9 | 7 | 6 | 5 | 5 | 4 | 4 | 3 | 3 | 2 |

Signs at the left end of each row: green side "green blob with ? : [1]" (? coins buy 1 VP);
brown side "grey pile of chips : [1]" (chip value per 1 VP).

The track has 13 positions, 0..12, the same as the reverse-side test tubes
(`Quacks.Rules.TestTubes.last/0` = 12). 12 moves reach the end.

Notes:
- Green tubes 0..6 (12 → 5) need 6 moves before a VP costs less than the rulebook's end rate of
  5 coins. Green is a slow, long-term investment.
- Brown: ⚠️ an end bag is worth about 60 to 110 (estimate, not measured; check with
  `mix quacks.sim`). At 15: 4 to 7 VP; at 7: 8 to 15 VP;
  at 4: 15 to 27 VP; at 2: 30 to 55 VP. Brown is strong. Each pot droplet move that you give up
  costs about 1 coin per later round.

## 3. Open rules questions and our proposed reading

| # | Question | Sources | Our reading |
|---|---|---|---|
| Q1 | Shared stand or one per player? | S1, S2: one stand, in the middle, "shared by all players". | One shared board, one droplet per player, each with an own position. Engine: per-player value. UI: one rack with all droplets. |
| Q2 | Can several droplets be on one tube? | Not stated. | Yes. No blocking, no bonus for being first. |
| Q3 | When can you buy VP on the green side? | S1 "neben Zutaten" (with the ingredients); S4 lists it in the buy-chips step. | In the shop step (`:shopping`, player phase `:shop`), before "Done". Not in the chip-actions step (e.g. purple Set 5's step-B purchase buys chips only ⚠️). |
| Q4 | Is the VP purchase part of the "max 2 chips of different colours" limit? | S1: "beliebig viele Siegpunkte". | No. VP are separate. Any number of VP, plus the normal chip buy. |
| Q5 | Order of the VP purchase and the ruby spends in the shop. A ruby stand move (phase F) lowers the price; must the VP purchase come first (phase E)? | Not stated. The engine already lets rubies come in the buy step (round 35). | ⚠️ Any order before "Done". A ruby stand move then makes this round's VP cheaper. Simple and the same as the engine's shop today. Strict alternative: VP only before the first ruby spend. **Ask Nick.** |
| Q6 | Black book II: buying a black chip moves your droplet. Does that move lower the price in the same shop? | Not stated. | Yes, if you choose the stand. The move happens at the buy; later VP purchases use the new price. |
| Q7 | Exploded player who took the VP instead of the buy. | Rulebook: they skip the buy. | No VP purchase either (it is a buy with coins). Same gate as `may_buy?/2` (copper witch C4 coins: can buy). |
| Q8 | Round 9 on the green side. The rulebook has no buy in round 9; coins become VP at 5 : 1. | S1: VP "im Spielverlauf" and "in einer Runde beliebig viele". Nothing about round 9. | ⚠️ In round 9 the coins convert at the **better** rate: `min(5, price)`. Automatic at "Done", so the player cannot lose. (Alternative: offer the green purchase in round 9's shop as a separate action, then 5 : 1 for the rest.) Same result, fewer clicks. **Ask Nick.** |
| Q9 | Stand moves in round 9. The engine removes `{:rubies, :droplet}` in round 9 (a pot droplet is worth nothing then). | S1: any droplet move can go to the stand. | Keep the choice in round 9. A stand move is worth a lot in round 9 (brown: a smaller divisor; green: a cheaper round-9 conversion). Offer `{:rubies, :tube}` in round 9's shop (as the reverse side does since round 37). Die, chip and card moves in round 9 also ask the choice. |
| Q10 | Brown: which chips count? | S1: empty the bag, all numbers on all chips, white included. S2: bag and cauldron. | All chips the player owns at the end: bag, pot (`drawn`), overflow bowl, red Set 2 chips beside the pot (`aside`), Nervousness `display`, `pending`. ⚠️ The extra places are our reading. Chips that left the game (given away by black book II, returned to the supply) do not count. |
| Q11 | Brown: rounding. | S2 example 60 / 15 = 4 is exact. S4: "round down". | Round down (`div/2`). ⚠️ |
| Q12 | Brown: when is the score added? | S1: "Bei Spielende". S6 says each round; S6 disagrees with S1, we ignore it. | Once, after round 9 (after every seat's "Done" and final conversion). Before the final ranking. Tie-break stays as now. |
| Q13 | End of the stand (tube 12). | Not stated. | Same as the reverse side: on tube 12 the stand droplet cannot move; all later moves go to the pot droplet with no choice. |
| Q14 | A move of 2 (purple S2 tier 3, P11). | Not stated. | Same as the reverse side: 2 single moves, each with its own choice. |
| Q15 | Herb Witches: gold witch G4 ("1 ruby to move a droplet"). | G4 says "move a droplet forward". | Applies to the stand move too (`ruby_price`). Unused witch pennies stay 2 VP each. Witch coins/chips: brown counts the chips the player has at the end. |
| Q16 | The Alchemists: a patient reward `{:droplet, n}`. | Not stated. | Goes through `move_droplet/3`, so it asks the choice. The flask track and essence: no interaction. |
| Q17 | VP purchases and the rat stones / black standings. | Not stated. | Bought VP are normal VP. They count for the next round's rats and for `black_rule: :standings`. |
| Q18 | Fortune cards that act on the droplet (B1, P2, P11, …). | S1 names "Wahrsagekarte". | All go through `move_droplet/3`, so all ask the choice. No card change. |
| Q19 | Purple Set 5 in round 9 ("purchase VP as normal (5 : 1)"). | Herb Witches almanac. | ⚠️ Keep 5 : 1 for that sum. The green price is for coins in the shop. **Low priority; ask Nick only if a builder needs it.** |

## 4. Engine proposal

### 4.1 Rule flag

- New house rule `exchange: :off | :brown | :green` in `Game.@rule_values` and `@rules`
  (default `:off`). It is an official mini-expansion, but the side is a table choice, like
  `pot_side`, so a rule is the simplest fit. (Alternative: an entry in `expansions` plus a side
  rule. More code, no gain.)
- `Game.rules/1` (the validation behind `new/1`) must also reject the pair `pot_side: :back`
  with `exchange != :off` (`ArgumentError`, as for other bad rules). Today the validation checks
  each key alone; add one cross-check.
- `Session` encodes rules with `encode_map/1`, so the new atom values round-trip. Add a test.
- `mix quacks.sim --rules exchange:brown` works when the atoms exist.

### 4.2 Rules data

New module `Quacks.Rules.ExchangeOffice` (plain data, as `TestTubes`):

```elixir
@green {12, 10, 9, 8, 7, 6, 5, 5, 4, 4, 3, 3, 2}
@brown {15, 13, 11, 9, 7, 6, 5, 5, 4, 4, 3, 3, 2}
def last, do: 12
def price(tube), do: elem(@green, tube)      # coins per 1 VP
def divisor(tube), do: elem(@brown, tube)    # brown end-game divisor
def value(:green | :brown, tube)
```

### 4.3 State

- Use the existing `Player.tube` (0..12) for the stand droplet. Both tracks have 13 positions and
  never play together. Update the `Player` moduledoc: "`tube`: the second droplet: the test-tube
  glass (`pot_side: :back`) or the Exchange Office tube (`exchange: :brown | :green`)".
- Use the existing `Player.droplet_moves` for waiting moves. No new fields.

### 4.4 Actions and the droplet choice

One helper decides if a seat has a second droplet that can move:

```elixir
defp second_droplet?(g, p),
  do: (g.rules.pot_side == :back or g.rules.exchange != :off) and p.tube < 12
```

- `move_droplet/3`: use `second_droplet?/2` instead of the `pot_side == :back` test. Moves then
  wait in `droplet_moves`, and `phase/2` gives `:droplet_choice` as today.
- `{:droplet, :pot}`: no change.
- `{:droplet, :tube}`: today `tube/2` moves 1 glass and pays the glass bonus. Branch on the rule:
  - reverse side: as now (`{:tube, glass, bonus}` in the log);
  - exchange: move 1 tube, no bonus, log `{:stand, tube}` (tube = new position 1..12).
- `droplet_moved/2` (rest to the pot on the last tube): no change.
- Shop `{:rubies, :tube}`: legal when `second_droplet?/2`. In round 9 legal too (Q9), as on the
  reverse side. `ruby_actions/2` already does this for `tube?/2`; widen `tube?/2` to
  `second_droplet?/2`.
- New action (green only): **`{:buy_vp, n}`**: pay `n * price` coins, gain `n` VP. Legal in
  `:shopping`, player phase `:shop`, rounds 1..8, when `may_buy?`-style gate holds (not the
  `bought?` part: it stays legal after the chip buy, Q5) and `n` in `1..div(coins, price)`.
  `legal_actions/2` lists every `n` (at most `div(coins, 2)`, so about 20 entries; fine). Log
  `{:vp_bought, n, price}`. One action for many VP keeps the UI to one click.
- Round 9, green: `final_conversion/2` converts coins at `rate = min(5, price)` (Q8). Log keeps
  `{:final_conversion, coins, coins_vp, rubies, rubies_vp}`; add the rate as a 6th element only if
  the UI needs it (it can recompute it from the log's `{:stand, _}` events or `Player.tube`).

### 4.5 Scoring (brown)

- In `end_round/1` for round 9, before `{:round_end, 9}`: for each seat compute
  `total = sum of chip values over bag ++ Player.pot_chips(p) ++ bowl ++ aside ++ display ++ pending`
  (chip value = the second element of `{colour, value}`), `divisor = ExchangeOffice.divisor(p.tube)`,
  `vp = div(total, divisor)`. Add `vp`, log `{seat, {:exchange_score, total, divisor, vp}}`.
- Put it in one function `exchange_score/1` that does nothing unless `exchange: :brown`.
- `Game.score/1` then includes it. `Reveal.final_rows/1` reads it from the log as one more part.

### 4.6 Bots (`Quacks.AI`)

Today `choose(:droplet_choice, …)` always takes the tube while it can (good for the reverse side,
where every glass pays). For the Exchange Office the bot must compare.

- **Value of a pot move** (exists): `AI.Choice.droplet(round, profile)` ≈ one space per later round.
- **Value of a stand move, brown:** `est_total * (1/d(t) - 1/d(t+1))`, where `est_total` = the
  value of the chips the bot owns now plus about 8 per round left (a typical buy). Example: total
  80, 15 → 13: 0.8 VP; 7 → 6: 1.9 VP; 3 → 2: 13 VP. So a bot moves the stand early, and the value
  grows with each step. In round 9 the pot move is worth 0, so always the stand.
- **Value of a stand move, green:** `spare * rounds_left * (1/p(t+1) - 1/p(t))`, where `spare` is
  the expected coins per round that the chips do not use (profile value, e.g. 4) plus the round-9
  coins. Early this is small (12 → 10: 0.07 VP per spare coin per round), so green bots move the
  pot droplet first and the stand later. ⚠️ Tune with `mix quacks.sim`.
- **Shop, green:** after the chip buy, if `coins >= price`, take `{:buy_vp, div(coins, price)}`
  (leftover coins are lost anyway). Before the chip buy, prefer VP over chips when
  `price <= 5` and round ≥ 7 (a chip bought late gives little). One rule in `AI.Shop.pick/4`.
- **Shop rubies:** in `AI.Shop.rubies/3` a `:droplet` plan entry tries `{:rubies, :tube}` first
  only when the stand value above is higher than the pot value. In round 9: `{:rubies, :tube}`
  when the stand move gains more than 1 VP (brown: `div(total, d(t+1)) - div(total, d(t))`;
  green: the extra VP the coins convert to), else `{:rubies, :vp}`.
- Put the two value functions in `AI.Choice` (one table of VP values, as its moduledoc says), and
  use them from `AI.choose(:droplet_choice, …)` and `AI.Shop`.

## 5. UI proposal (in areas; the components are being refactored)

- **Lobby / setup.** Replace the single "Pot: reverse side" checkbox with one option group
  "Second droplet": *None* / *Test tubes (reverse pot side)* / *Exchange Office: brown* /
  *Exchange Office: green*. One control makes the invalid pair impossible. Each choice has a
  one-line hint (brown: "End: your chips ÷ the tube"; green: "Buy VP with coins; the tube sets
  the price"). The game page's "House rules" list names it ("Exchange Office (green)").
- **Pot side rack (pot column).** Where the reverse side shows its test-tube rack, show the
  stand: 13 tubes with their numbers (green coin price or brown divisor) and the side's sign at
  the left. Unlike the test tubes, the stand is **shared**: show every seat's droplet as a small
  disc in the seat colour, own droplet larger with a ring; discs on the same tube stack. On a
  phone: a compact strip (numbers + discs); a tap opens a small sheet with the rule text. The
  droplet hop animation of the test-tube rack can be used again.
- **Player tile.** One small stand item: green "1 VP = 7 coins" (current price), brown "÷ 9".
- **Bottom context bar, droplet choice.** Same bar choice as the reverse side, with labels for
  the side: "Pot droplet +1" and "Exchange: VP 12 → 10 coins" (green) or "Exchange: ÷15 → ÷13"
  (brown). The info row names the source of the move (as today). Brown info row adds a forecast:
  "Your chips: 74 → now 4 VP, after the move 5 VP".
- **Shop (green).** A "Buy VP" item next to the chips: price per VP, a − / + stepper up to
  `div(coins, price)`, and the coins left. It stays after the chip buy. In the rubies step (bar),
  when the seat has `coins >= price`, add "Buy N VP (P coins each)" next to the ruby uses, and a
  soft warning on "Done": "You lose X coins" when X ≥ price. Round 9: the info row says
  "Coins convert at P : 1 (Exchange Office)" when P < 5.
- **Recap / results stage.** The Shop step lists "Bought N VP". Replay gains: `{:vp_bought, n, _}`
  is `+n VP`; `{:stand, _}` has no gain (a droplet push, shown like the other droplet pushes).
- **Final scoring panel (score chart).** One more part per row, brown only: a chips icon,
  "74 ÷ 6 = 12 VP", counted up like the coins and rubies parts. Green adds nothing here (the VP
  were bought during the game); the round-9 coins part shows the rate when it is not 5.
- **Rules / help sheet.** One short entry for each side, from §2.3.

## 6. Test plan

### 6.1 Engine tests (`test/quacks/exchange_office_test.exs`)

1. Data: `ExchangeOffice.price/1` and `divisor/1` return the §2.4 rows; `last/0` is 12.
2. `Game.new(rules: %{exchange: :green, pot_side: :back})` raises `ArgumentError`; each side alone
   is valid; the default is `:off`.
3. With `exchange: :brown`, a die droplet face (or a black chip) puts the seat in
   `:droplet_choice`; legal actions are `{:droplet, :pot}` and `{:droplet, :tube}`.
4. `{:droplet, :tube}` moves `tube` +1, gives no bonus (VP, rubies, bag unchanged) and logs
   `{seat, {:stand, 1}}`.
5. On tube 12, a move goes to the pot droplet at once (no choice).
6. A move of 2 (P11) asks 2 choices.
7. Shop: `{:rubies, :tube}` is legal with the exchange on, in rounds 1..8 and in round 9.
8. Green: `{:buy_vp, n}` is legal only in `:shop` with `n * price <= coins`; it adds `n` VP and
   takes the coins; it is legal before and after `{:buy, chips}`; never on `:brown` or `:off`;
   not for an exploded seat that took the VP.
9. Green: the price follows the tube (move the stand, the price drops in the same shop).
10. Green, round 9: coins convert at `min(5, price)` at "Done" (tube 8, price 4: 13 coins → 3 VP).
11. Brown: at game end the VP = `div(total, divisor)`; the total counts white chips, pot chips,
    bowl chips and `aside` chips; logged `{:exchange_score, total, divisor, vp}`; with the droplet
    on tube 0 the divisor is 15.
12. Session: a game with `exchange: :green` encodes, decodes and replays to the same state.
13. Bots: full games (`mix quacks.sim`-style, several seeds, 1, 2 and 4 players) with each side
    finish without a stall; a green bot with spare coins buys VP.
14. The "never rests without a legal action" property test runs with each side.

### 6.2 Gallery story

- One component story for the stand rack, with args: side (`:green | :brown`), seats (1..5),
  each seat's tube (0..12), own seat. Shows the shared stack of discs and the phone strip.
- Variants: shop with the "Buy VP" item (coins 13, price 4); final score chart with a brown part.

### 6.3 Scenarios (`Quacks.Scenarios`, group "Other rules")

- `rule/exchange-green`: 2 players, `exchange: :green`, fortune off. Steps: *choice* (a droplet
  move asks pot or stand), *stand* (the stand droplet moved, the price dropped), *shop* (buy VP
  with leftover coins), *final*. Builder like `Builders.tube9/1`.
- `rule/exchange-brown`: 2 players, `exchange: :brown`. Steps: *choice*, *round 9 stand move*
  (rubies move the stand in round 9), *final* (the score chart shows "total ÷ divisor").
- Both run in `test/quacks_web/live/scenarios_test.exs` (it runs every entry).

### 6.4 LiveView test

- `test/quacks_web/live/exchange_office_live_test.exs`: the lobby option group; the stand rack
  renders with all seats' droplets; the droplet choice buttons have the side's labels; the green
  "Buy VP" control sends `{:buy_vp, n}`; the final board shows the brown part. Use element IDs
  (e.g. `#exchange-stand`, `#buy-vp`, `#final-exchange-<seat>`).

## 7. Build plan (for a later builder, after the component refactor)

1. **Data.** Add `Quacks.Rules.ExchangeOffice` (§4.2) with doctests. Test 6.1.1.
2. **Rule flag.** Add `exchange` to `@rule_values` / `@rules`, the cross-check against
   `pot_side: :back`, and docs in `Game` and `Player` moduledocs. Tests 6.1.2, 6.1.12.
3. **Droplet choice.** Add `second_droplet?/2`; use it in `move_droplet/3`, `tube?/2` and the
   round-9 `ruby_actions/2`; branch `tube/2` for the exchange (`{:stand, n}`, no bonus). Tests
   6.1.3 to 6.1.7. Run the existing test-tube tests (`test_tubes_test.exs`,
   `pot_reverse_live_test.exs`, `droplets_last_test.exs`): they must stay green.
4. **Green purchase.** `{:buy_vp, n}` in the action type, `phase_actions(:shopping)`, `step/3`
   and the log type; round-9 rate in `final_conversion/2`. Tests 6.1.8 to 6.1.10.
5. **Brown score.** `exchange_score/1` in `end_round/1` for round 9. Test 6.1.11.
6. **Bots.** Value functions in `AI.Choice`; use them in `AI.choose(:droplet_choice, …)` and
   `AI.Shop`. Tests 6.1.13, 6.1.14. Run `mix quacks.sim` for each side and note the average
   stand VP in this doc.
7. **CONTEXT.md.** Add the glossary entries **exchange office**, **stand**, **VP purchase**;
   update **droplet choice**, **house rules**, **shopping**, **rubies step**.
8. **UI.** Lobby option group; stand rack; tile item; bar labels and brown forecast; shop "Buy
   VP" and the rubies-step entry with the "coins lost" hint; recap gains; score chart part;
   labels in the action/log label table. LiveView test 6.4.
9. **Gallery and scenarios.** Story 6.2, scenarios 6.3.
10. `mix precommit`; staging; a Taskwarrior task for Nick to play one game on each side.

## 8. Size estimate

| Part | Size | Notes |
|---|---|---|
| Data + rule flag + cross-check | S | ~60 lines + tests |
| Droplet choice for the stand | S | The mechanism exists; ~40 lines changed |
| Green purchase + round-9 rate | S–M | New action in the shop; ~80 lines |
| Brown end score | S | ~30 lines |
| Bots | M | Two value functions, tuning with the sim |
| Engine tests | M | ~250 lines |
| UI (lobby, rack, bar, shop, recap, score chart) | M | Depends on the refactored components; the shared rack is the only new visual |
| Gallery story + 2 scenarios | S–M | Copy `tube9` |
| **Total** | **M (about 2 builder rounds: engine + bots, then UI)** | |

## 9. Questions for Nick

1. **Q5:** On the green side, may a ruby stand move in the shop lower the price for VP bought in
   the same shop (any order), or must the VP purchase come before the rubies?
2. **Q8:** Green, round 9: convert coins at the better rate `min(5, price)` automatically (our
   proposal), or show a separate "Buy VP" step?
3. **Q9:** Allow stand moves (rubies, die, chips) in round 9? We say yes; it matters most on the
   brown side.
4. **Q10:** Brown: count chips beside the pot, in the overflow bowl and in the Nervousness
   display? We say yes ("all your chips").
5. Lobby: one "Second droplet" option group (none / test tubes / brown / green) instead of the
   current checkbox. OK?
