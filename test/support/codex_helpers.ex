defmodule Codex.TestHelpers do
  @moduledoc "Helpers for the Codex engine tests: a new game, actions that must work, zones."
  import ExUnit.Assertions

  alias Codex.Game

  @seed {1, 2, 3}

  @doc "A new game (rules mode) from a fixed seed."
  def new(seed \\ @seed), do: elem(Game.new(%{}, seed), 1)

  @doc "Free mode on."
  def free(game), do: ok!(game, {:free_mode, true})

  @doc "Do `action` for table seat 0; it must work."
  def ok!(game, action) do
    case Game.apply(game, 0, action) do
      {:ok, game} -> game
      {:error, reason} -> flunk("#{inspect(action)} refused: #{inspect(reason)}")
    end
  end

  def zone(game, seat, zone), do: game.sides[seat].zones[zone]
  def hand(game, seat), do: zone(game, seat, :hand)

  @doc "Set fields of card `id` by hand (a test set-up, not a game action)."
  def put_card(game, id, fields),
    do: %{game | cards: Map.update!(game.cards, id, &Map.merge(&1, Map.new(fields)))}

  @doc "Every card is in exactly one zone."
  def assert_conserved(game),
    do: assert(Enum.sort(Game.all_placed(game)) == Enum.sort(Map.keys(game.cards)))
end
