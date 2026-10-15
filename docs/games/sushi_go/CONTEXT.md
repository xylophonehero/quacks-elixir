# Sushi Go! glossary

Terms used in code, tests and docs for the Sushi Go! engine. Source: `docs/games/sushi_go/rulebook.md` (§ refers to it). Proposed module prefix: `SushiGo` (`SushiGo.Game`, `SushiGo.Rules.Deck`, `SushiGo.Scoring`). Names are proposals until the engine lands.

| Term | Meaning |
|---|---|
| **card** | An atom naming the card kind. Cards of one kind are interchangeable, so no card ids. The 12 kinds: `:tempura`, `:sashimi`, `:dumpling`, `:maki1`, `:maki2`, `:maki3`, `:egg`, `:salmon`, `:squid`, `:wasabi`, `:chopsticks`, `:pudding` (§1). |
| **deck** | `game.deck`, the face-down list of undealt cards, top first. Built from `SushiGo.Rules.Deck.counts/0` (108 cards) and shuffled once at `Game.new/1` with the seed. Never reshuffled (§2). |
| **seat** | A player's place, `0..n-1`, `n` in 2..5. Every player-facing function takes the seat (`apply(game, seat, action)`, `view(game, seat)`, `legal_actions(game, seat)`). |
| **hand size** | Cards dealt per seat per round: `%{2 => 10, 3 => 9, 4 => 8, 5 => 7}` (`SushiGo.Rules.hand_size/1`, §2). Also the number of turns in a round. |
| **hand** | `game.hands[seat]`, the cards a seat holds right now. Secret: only that seat sees it. Hands rotate every turn. |
| **round** | `game.round`, 1..3. Deal, `hand size` turns, round scoring, discard (§7). |
| **turn** | `game.turn`, 1..hand size within a round. One pick per seat, then reveal, then pass. |
| **pick** | A seat's secret choice for the current turn: `game.picks[seat]`, `nil` until the seat acts. Either `{:one, i}` or `{:two, i, j}` (chopsticks). Indexes are into the seat's hand at the start of the turn. |
| **picked?** | Whether a seat has submitted its pick this turn. Public (shown as "ready"); the card itself is not. |
| **reveal** | Happens automatically inside `apply/3` when the last seat picks: every pick moves from hand to tableau at once, in seat order, log `{:reveal, %{seat => [card]}}` (§3). |
| **pass** | Right after the reveal: hand of seat `s` goes to seat `rem(s + 1, n)` ("left", ⚠️ §3). No pass after the last turn of a round. |
| **tableau** | `game.tableaux[seat]`, the revealed cards in front of a seat this round, newest first. Public. Each entry is a card atom, except a nigiri on wasabi: `{:wasabi, nigiri}`; an empty wasabi is just `:wasabi`. Cleared at round end (puddings move to `puddings`). |
| **chopsticks** | Card that lets a seat take two cards on a **later** turn (§4). Usable when the tableau holds `:chopsticks` and the hand has ≥2 cards. Using it removes one `:chopsticks` from the tableau and puts it into the hand that is passed on. One use per turn. |
| **wasabi** / **dip** | A nigiri picked while the tableau has an empty `:wasabi` must be **dipped**: that `:wasabi` entry becomes `{:wasabi, nigiri}` and scores ×3 (§5). |
| **nigiri** | `:egg` (1), `:salmon` (2), `:squid` (3). `SushiGo.Rules.nigiri_value/1`. |
| **maki icons** | Sum of icons in a tableau: `:maki1` 1, `:maki2` 2, `:maki3` 3. Majority scoring: 6 to most, 3 to second, ties split with `div/2` (§6.1). |
| **set scoring** | Tempura `div(n,2)*5`; sashimi `div(n,3)*10`; dumplings `[0,1,3,6,10,15]` capped at 5 (§6). |
| **round score** | `game.round_scores[seat]`, list of per-round points, newest first, with a breakdown in the log `{:round_score, round, seat, %{maki: _, tempura: _, sashimi: _, dumpling: _, nigiri: _}}`. |
| **puddings** | `game.puddings[seat]`, count of pudding cards kept across rounds. Public. Scored only at game end (§8). |
| **pudding score** | Game-end ±6 for most/fewest puddings, split with `div/2`, no −6 with 2 players, nothing if all equal (§8). Log `{:pudding, %{seat => points}}`. |
| **total** | Sum of round scores plus pudding score. `SushiGo.Game.total/2`. |
| **winners** | `game.winners`, list of seats with the best total; pudding count breaks ties; still tied → several winners (⚠️ §9). Set when phase becomes `:over`. |
| **phase** | `:picking` (waiting for picks) or `:over`. Round scoring and dealing happen inside `apply` and are not phases. |
| **view** | `SushiGo.Game.view(game, seat)`: what one seat may see. Own hand and own pick; every tableau, pudding count and score; other seats' hand sizes and `picked?` flags; never other hands, other picks before reveal, or the deck. |
| **house rule** | Option in `Game.new(opts)` that changes a ⚠️ ruling. Proposed: `chopsticks_wasabi: :ordered | :strict` (§5, default `:ordered`). |
