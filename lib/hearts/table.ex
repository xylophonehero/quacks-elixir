defmodule Hearts.Table do
  @moduledoc """
  Hearts in a `Table.Server` room: the adapter from the server's callbacks to
  `Hearts.Game` and the bots (`Hearts.AI.Heuristic`, `Hearts.AI.Random`).

  The bot delays (`bot_delay/1`) follow the last log event, so the page can
  play its motion first: a card about 750 ms, a full trick a longer look, a pass
  and a new deal longer again.
  """
  @behaviour Table.Server

  alias Hearts.AI.{Heuristic, Random}
  alias Hearts.Game

  @impl true
  def new(opts, seed), do: Game.new(opts, seed)

  @impl true
  def seats(%Game{seats: seats}), do: seats

  @impl true
  def legal_actions(game, seat), do: Game.legal_actions(game, seat)

  @impl true
  def apply(game, seat, action), do: Game.apply(game, seat, action)

  @impl true
  def status(game), do: Game.status(game)

  @impl true
  def view(game, seat), do: Game.view(game, seat)

  @impl true
  def bot_levels, do: [:heuristic, :random]

  @impl true
  def bot_new(:heuristic, _seed), do: nil
  def bot_new(:random, seed), do: Random.new(seed)

  @impl true
  def bot_choose(:heuristic, view, bot), do: Heuristic.choose(view, bot)
  def bot_choose(:random, view, bot), do: Random.choose(view, bot)

  @impl true
  def bot_delay(%Game{log: [event | _]}), do: delay(event)
  def bot_delay(%Game{}), do: 750

  defp delay({:trick_won, _, _, _}), do: 1600
  defp delay({:deal, _, _, _}), do: 2600
  defp delay({:pass, _, _}), do: 1800
  defp delay({:pass_chosen, _}), do: 500
  defp delay(_event), do: 750
end
