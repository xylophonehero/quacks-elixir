defmodule Table.View do
  @moduledoc """
  What a page gets from `Table.Server`: one seat's view of the game, with a
  version number (RFC `docs/design/table-game.md` §3).

  - `version`: the room's counter, +1 on every change. A page drops an envelope
    that is not newer than the one it has.
  - `seat`: the seat, or `:spectator`.
  - `status`: the adapter's `status/1`.
  - `actions`: the legal actions of `seat` (`[]` for `:spectator`).
  - `view`: the adapter's `view(state, seat)`. It holds no hidden information.
  """

  @enforce_keys [:version, :seat, :status, :actions, :view]
  defstruct [:version, :seat, :status, :actions, :view]

  @type t :: %__MODULE__{
          version: non_neg_integer,
          seat: non_neg_integer | :spectator,
          status: {:playing, [non_neg_integer]} | {:over, map},
          actions: [term],
          view: term
        }
end
