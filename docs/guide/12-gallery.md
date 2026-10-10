# 12. Gallery: stories, args, screens, scenarios

[Back to the guide](../GUIDE.md)

The gallery (`/dev/gallery`) is a viewer like Storybook. It shows one **story**
at a time in one iframe at a real viewport width. A story has **args** (typed
values with a range) that you change with the controls, and **presets** (named
sets of args). The sidebar has three kinds of groups:

- **Components**: the parts that took the most rounds to get right (results
  panel, pot board, player tiles, bottom bar, score track, chip), each in its
  edge cases.
- **Screens**: the whole game page (header, tiles, track, pot, flask, bag, bar,
  the context column on desktop) for a phase: brewing, a choice, an evaluation
  step, round scored, the shop, game over.
- **Scenarios**: one real game per rules item (a Fortune Teller card, an
  ingredient book, an Alchemists patient, a herb witch, a rule). Its steps are
  the `step` arg; each step shows as a full screen.

## Where it runs

The routes are in every build. `QuacksWeb.Plugs.Gallery` answers 404 unless the
runtime flag `:gallery` is true. Staging and prod are the same `MIX_ENV=prod`
build, so a compile-time flag cannot tell them apart.

| Where | `:gallery` | Set in |
|---|---|---|
| dev | on | `config/dev.exs` |
| test | on | `config/test.exs` |
| staging (`APP_ENV=staging`) | on | `config/runtime.exs` |
| prod (`quacks.fly.dev`) | off: `/dev/*` is 404 | `config/runtime.exs` |

The plug is also the `on_mount` of the `:gallery` live session.
`test/quacks_web/plugs/gallery_test.exs` checks both values.

Staging links: `https://quacks-staging.fly.dev/dev/gallery`, a story with args,
e.g. `https://quacks-staging.fly.dev/dev/gallery/tiles/tiles?players=8&state=shop&w=392`.

## Use it

1. Open `/dev/gallery` (dev: `http://localhost:<PORT>/dev/gallery`).
2. Click a story in the sidebar. A gear mark shows a story with args; a dot after
   a scenario is its last test result (green pass, red fail, ring: no run); "hand"
   marks a hand-written scenario.
3. The toolbar sets the width: **360, 392, 768, 1280** or **Full**. A frame wider
   than the screen is scaled down to fit. `‹` `›` and the arrow keys go to the
   previous and next story (not while a control has the focus).
4. The controls under the toolbar change the args. Presets set several args at
   once; "defaults" goes back.
5. A scenario has "Open as a live game": the real game at that step on the game
   page (`/dev/scenarios/<kind>/<id>?step=N`), with the step bar.

The URL keeps the state: `/dev/gallery/<group>/<story>?<args>&w=<width>`. Only
args that differ from the default are in it, so a link reproduces the view.
Examples:

- `/dev/gallery/results/step-die?players=8&long_names=true&vp_digits=3&w=360`
- `/dev/gallery/screens/choice?choice=mandrake&w=1280`
- `/dev/gallery/scenario-chip/blue-1?step=2&w=392`

An old variant URL that a story with args took over (for example
`/dev/gallery/bar/crow-5`) goes to the story with that variant's args
(`/dev/gallery/bar/crow?chips=5`). `/dev/scenarios` goes to the first scenario.

## The stories and their args

| Group | Story | Args |
|---|---|---|
| Results panel | Results: die / black / green / purple / scoring space | `players 2..8`, `long_names`, `exploded 0..7`, `vp_digits 1..3` |
| | Recap: the shop | `players 2..8`, `long_names` |
| | Recap: round scored | `players 2..8`, `long_names`, `vp_digits 1..3` |
| | Take a Chance | `players 2..8` |
| Pot board | Brewing: the scoring ring | `chips 0..6` |
| Player tiles | Player tiles | `players 1..8`, `state brewing\|stopped\|exploded\|shop\|done`, `long_names`, `vp_digits 1..3`, `bots` |
| Bottom bar | Crow skull | `chips 1..5` |
| Score track | Score / rat track | `players 2..8`, `spread early\|tied\|above-50\|big-gaps` |
| Screens | Brewing | `players 1..8`, `long_names` |
| | A choice | `players 1..8`, `choice crow\|mandrake\|chip_choice\|explosion`, `long_names` |
| | Evaluation step | `players 2..8`, `step die\|black\|green\|purple\|space`, `long_names`, `exploded 0..7` |
| | Round scored | `players 2..8`, `step standings\|shop`, `long_names`, `vp_digits 1..3` |
| | Shop, Game over | `players 1..8`, `long_names` |
| Scenarios | every item | `step 1..n`, `players 2..5` |

Every other component variant is a story with no args. Some args reach no such
state (a purple book step with no purple chip, a scenario whose goal no seed
reaches with that many players): the frame then says why instead of drawing.

## How it works

- `QuacksWeb.Gallery.Stories`: the catalog of groups and stories, the args
  (`args/2` parses the URL: an int is clamped, a bad value is the default;
  `query/2` gives the URL params back) and the presets. `arg_stories/1` declares
  a component's stories with args; each `claims` the old variants that only
  differ by its args.
- `QuacksWeb.Gallery.Fixtures`: the builders. Each plays a seeded `Quacks.Game`
  with `Game.apply/3` where the engine can reach the state, so the fixtures follow
  engine changes. `draw/3` rigs a draw: it puts the wanted chip where the game's
  own random number takes the next chip, then `:draw` runs. Fields set by hand
  (`put/3`) are only for states the engine does not reach easily (3-digit VP, a
  droplet at 49, a crow skull offer of 3 or 5 chips); each such place says so.
  Section 7 has the builders with args, section 8 the screens.
- `QuacksWeb.GalleryLive`: the viewer (sidebar, toolbar, controls, one iframe).
- `QuacksWeb.GalleryFrameLive` (`/dev/gallery/frame/<group>/<story>?<args>`): one
  frame. A component frame copies the wrappers its CSS needs (`.game-bar`,
  `.pot-square`, the players row grid). A screen or a scenario step is the real
  page: `QuacksWeb.GameLive.preview/3` makes the page's assigns from a game (what
  `mount/3` and `put_game/2` assign, with no `GameServer`) and
  `GameLive.render/1` draws it. Clicks do nothing.
- A scenario step: `Quacks.Scenarios.build/2` plays the scenario, the frame takes
  the game after the step's actions (`Script.game_at/2`). The moments of the
  rounds before count as seen, so this round's card or results play as on the
  page. Building is cheap (all 82 scenarios in about 0.1 s on a laptop), so there
  is no cache.

## Add a story or a variant

- A plain variant: add `{"my-id", "What it shows", fn -> ... end}` to the
  component's list in `Fixtures.catalog/0`. It shows as a story with no args.
- A story with args: add a builder `my_story(args)` in `Fixtures` section 7 and an
  `arg_story/5` in `Stories.arg_stories/1` with its args (`int/4`, `bool/1`,
  `enum/3`), presets and the old variants it `claims`.
- A screen: a builder in `Fixtures` section 8 that returns
  `%{view: :screen, game: g, preview: opts}` (opts of `GameLive.preview/3`) and a
  `screen/5` in `Stories.screens/0`.
- A new component: an entry in `catalog/0` (with the frame height in px) and a
  `frame/1` clause for its `view` in `GalleryFrameLive`.

`test/quacks_web/live/gallery_live_test.exs` renders every story with its default
args and with each preset, and every scenario step, so a broken fixture fails
`mix test`.

UI change: check it in `/dev/gallery` at 360/392/1280, and add a story, an arg or
a preset for any new state.

## Scenarios

A scenario is a real game that plays to the moment where one rules item acts. You
look at its steps in the gallery, or open it as a live game and walk the steps on
the normal game page. Each scenario also has a test.

The live game: `/dev/scenarios/card/p12`, `/dev/scenarios/chip/blue/1`,
`/dev/scenarios/patient/nervousness`, `/dev/scenarios/witch/gold/g1`,
`/dev/scenarios/rule/tube9`. Add `?step=2` to start at step 2 and `?players=4` for
4 seats. The game starts with you on seat 0 and the bots frozen. The step bar at
the top: `‹` and `Next ›` go to the previous and next step, `«` and `»` go to the
previous and next item of the same kind, the title goes to the gallery, `^` folds
the bar, and "Play on" unfreezes the bots so you can play on by hand.

A step is a point in the game's action log, not a moment of an animation. The
page shows what it shows after those actions: reveals and dialogs play as in a
real game, and you tap through them as a player does. Between steps you can also
play by hand: the game's random numbers are in the game, so your "Draw" at the
"draw" step takes the same chip as the script.

## How scenarios work

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
Each test writes its result to `tmp/scenarios/results/`; the gallery shows it as the dot.

## Snapshots

With `SCENARIO_SNAPSHOTS=1` the test writes each step's HTML to
`tmp/scenarios/snapshots/<kind>-<id>/<n>-<label>.html`. A bug report from a
scenario table carries `"scenario": {"key": "chip/blue/1", "at": 35}` in its
replay bundle, so you know which scenario and which action it came from.

## A builder reproduces a bug

1. From the report: open the scenario in the gallery (or `/dev/scenarios/<key>`) and step to the action in the
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
