defmodule Table.Generic.Referee do
  @moduledoc """
  A referee runs the rules of a `Table.Generic.Game`. It never writes the state:
  it gets the full table (`Table.Generic.Game.referee_view/1`) and an event,
  and answers with ops (`Table.Generic.Ops`). The engine checks and applies them.

  The events:

  - `:start`: the spec's setup ops are done. Set the turn and the phase.
  - `{seat, action}`: a seat answered the prompt (`{:choose, label}` or
    `{:play, zone, card}`); the prompt is already closed.
  - `:continue`: the last ops left no prompt and the game is not over. The
    referee sees their result now (a shuffle, a draw) and goes on, usually with
    an `{:ask, ...}`.

  `Table.Generic.Referee.Scripted` is the hand-written referee of Crazy Eights.
  An LLM referee (step B) implements the same callback.
  """

  alias Table.Generic.Ops

  @callback decide(view :: map, event :: :start | :continue | {non_neg_integer, term}) ::
              [Ops.t()] | {:ok, [Ops.t()]} | {:error, term}

  @referees %{"crazy_eights" => Table.Generic.Referee.Scripted}

  @doc "The referee module of a spec's `referee` key, or nil. Never makes an atom."
  @spec for(String.t() | nil) :: module | nil
  def for(key) when is_binary(key), do: Map.get(@referees, key)
  def for(_key), do: nil
end
