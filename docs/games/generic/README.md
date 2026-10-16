# Generic card games: ops on zones

`Table.Generic.Game` (`lib/table/generic/`) is a pure engine that knows only zones,
counters and one prompt. The rules come from a **referee**. The referee never
writes the state: it returns **ops**, and the engine checks and applies them, all
or none. Step A (this) has a hand-written referee. Step B adds an LLM referee with
the same callback.

| File | What |
|---|---|
| `*.json` | Game specs: deck, zones, counters, players, set-up ops (`Table.Generic.Spec`, read at compile time) |
| `crazy_eights.md`, `go_fish.md` | Short rule notes |

## The parts

- `Table.Generic.Ops`: the closed set of ops, the JSON schema (`schema/0`) and the
  JSON codec (`decode/1`, `encode/1`).
- `Table.Generic.Game`: `new/2`, `legal_actions/2`, `apply/3`, `status/1`,
  `view/2`, `apply_ops/2`, `apply_json/2`, `replay/3`, `referee_view/1`.
- `Table.Generic.Referee`: the behaviour, `decide(view, event) :: [op]`;
  events `:start`, `{seat, action}`, `:continue`.
- `Table.Generic.Referee.Scripted`: Crazy Eights by hand.
- `Table.Generic.Oracle`: Hearts (`Hearts.Game`) written as ops on a mirror
  table: the true ops for each step, for step B to compare with.
- `Table.Generic.Table`: the `Table.Server` adapter (`/games/generic/<code>`),
  with a random bot. `TableWeb.GenericBoard` draws any zones view.

## Rules of the engine

- A player can only answer the prompt (`pending`): a choice
  (`{:choose, label}`) or a card (`{:play, zone, card}`).
- After an action the referee answers. When its ops leave no prompt and the game
  is not over, the engine asks again with `:continue`, so the referee can see a
  shuffle or a draw before it asks. No prompt after that: the action fails.
- Every op goes into the log with who saw its cards. `view/2` hides the cards of
  `:owner` and `:hidden` zones, and the log entries that the viewer did not see.
- `replay/3` applies the log again with no referee and gives the same state.
