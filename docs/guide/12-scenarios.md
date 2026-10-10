# 12. Scenarios

[Back to the guide](../GUIDE.md)

A scenario is a real game that plays to the moment where one rules item acts: a
Fortune Teller card, an ingredient book, an Alchemists patient, a herb witch or a
rule such as the round-9 test tube. You open it in the browser and walk its steps
on the normal game page. Each scenario also has a test.

Scenarios are dev and test only. The routes are behind the `gallery_routes` flag,
as the component gallery is (on in `config/dev.exs` and `config/test.exs`).

## Use it

1. Start the server (`mix phx.server`) and open `http://localhost:<PORT>/dev/scenarios`.
2. The index lists every item, grouped by kind. A gold "hand-written" tag marks a
   scenario with its own choices and checks. The last column is the last test
   result ("pass", "fail" with the step in the tooltip, or "no run").
3. Click an item. The game starts at step 1 on the game page, with you on seat 0
   and the bots frozen.
4. The step bar at the top: `‹` and `Next ›` go to the previous and next step,
   `«` and `»` go to the previous and next item of the same kind (walk all cards in
   a row), the title goes back to the index, `^` folds the bar, and "Play on"
   unfreezes the bots so you can play on by hand.

The URL of one item: `/dev/scenarios/card/p12`, `/dev/scenarios/chip/blue/1`,
`/dev/scenarios/patient/nervousness`, `/dev/scenarios/witch/gold/g1`,
`/dev/scenarios/rule/tube9`. Add `?step=2` to start at step 2.

A step is a point in the game's action log, not a moment of an animation. The
page shows what it shows after those actions: reveals and dialogs play as in a
real game, and you tap through them as a player does. Between steps you can also
play by hand: the game's random numbers are in the game, so your "Draw" at the
"draw" step takes the same chip as the script.

## How it works

- `Quacks.Scenarios` (`lib/quacks/scenarios.ex`): the catalog. `all/0` makes one
  entry per item from the rules data (`Quacks.Rules.Fortune.all/0`,
  `Quacks.Rules.Books.keys/0`, `Quacks.Rules.Alchemists.patients/0`,
  `Quacks.Rules.Witches.ids/1`), so a new card or book gets a scenario at once.
  `hand/0` holds the hand-written scenarios.
- `Quacks.Scenarios.Builders`: one generic builder per kind. For example, a card
  is round 2's card for 3 players; a book's chip is bought in every shop until it
  is drawn, and you stop right after it.
- `Quacks.Scenarios.Script`: the driver. It plays a `Quacks.Session` with
  `Quacks.Game.apply/3` (the bots play with `Quacks.AI`) and marks the steps.
  **Nothing is set by hand.** `Script.search/2` tries seeds until the script
  reaches its goal and every step's check passes. So the deck order or the draw
  comes from the seed, and the log is a normal replay bundle.
- `QuacksWeb.ScenarioController` builds the scenario and starts it with
  `GameServer.start_from_bundle/2` (the `/debug/replay` path). The bundle carries
  the steps under `"scenario"`; the table shows them in `debug.scenario`.
- `QuacksWeb.ScenarioComponents.step_bar/1` is the bar. Its step buttons send
  the scrubber's `seek` event (`GameServer.seek/2`).

## Add or tighten a scenario

Every item already has a generic scenario. Make one hand-written when the generic
one does not reach the moment, or when you want to check the outcome. Add an entry
to `Quacks.Scenarios.hand/0`, with the key `kind/id`:

```elixir
"card/p6" => [
  # Your choice and a bot's choice (nil leaves it to the bot).
  me: fn _g, legal -> if {:fortune, :remove_white} in legal, do: {:fortune, :remove_white} end,
  others: fn _g, seat, legal -> if seat == 1 and {:fortune, :vp} in legal, do: {:fortune, :vp} end,
  # Engine checks per step label: true, or a message.
  checks: %{"resolve" => fn g -> {0, {:fortune, :p6, :remove_white}} in Quacks.Scenarios.this_round(g) end},
  # Elements the page shows at a step.
  sees: %{"reveal" => ["[data-role=choice-grid]"]},
  # A tap at a step, and what the page shows after it.
  taps: %{"reveal" => [{"#card-tap", ["#card-stage-2-row-0"]}]}
]
```

Other options: `ready:` (a book: a condition on the game when the chip lands,
else the script plays on to the next round). A step that `checks:` names must
exist, else the seed does not count. If no seed in 60 (cards: 400) reaches the
goal, the build fails with the last reason.

A new kind of item: add a builder to `Quacks.Scenarios.Builders` and its entries
to `Quacks.Scenarios.all/0`.

## The test

`test/quacks_web/live/scenarios_test.exs` has one test per scenario. It builds the
scenario, opens its URL, walks the steps with `#scenario-next` and checks, per step,
the step bar and the step's `sees:` (and its `taps:`). A failure names the item and
the step:

```
card/p12, reveal: step 1 (reveal): the page has no #card-stage-2-row-1 [data-role=reveal-die]
```

One scenario: `mix test test/quacks_web/live/scenarios_test.exs --only scenario:card/p12`.
Each test writes its result to `tmp/scenarios/results/` for the index.

## Snapshots

With `SCENARIO_SNAPSHOTS=1` the test writes each step's HTML to
`tmp/scenarios/snapshots/<kind>-<id>/<n>-<label>.html`. A bug report from a
scenario table carries `"scenario": {"key": "chip/blue/1", "at": 35}` in its
replay bundle, so you know which scenario and which action it came from.

## A builder reproduces a bug

1. From the report: open `/dev/scenarios/<key>` and step to the action in the
   bundle's `"scenario"` (or use `/debug/replay?issue=N` for a report from a
   normal game, and find the scenario of the item).
2. Get the wrong snapshot:
   `SCENARIO_SNAPSHOTS=1 mix test test/quacks_web/live/scenarios_test.exs --only scenario:<key>`,
   then read `tmp/scenarios/snapshots/<kind>-<id>/`.
3. Write the test first: add the element that should show (or the engine fact)
   to the scenario's `sees:` or `checks:` in `hand/0`. Run the test: it fails at
   that step.
4. Fix the UI or the engine. Run the test again, then look at the step in the
   browser at 392 px.
5. Run `mix precommit`.
