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

  @doc "The id of the first card `slug` owned by `seat` that is not in play."
  def find(game, seat, slug) do
    Enum.find(Enum.sort(Map.keys(game.cards)), fn id ->
      c = game.cards[id]

      c.card == slug and c.seat == seat and
        Codex.Zones.zone_name(Codex.Zones.locate(game, id)) not in [:in_play, :patrol]
    end) || flunk("no free #{slug} of P#{seat + 1}")
  end

  @doc """
  Put card `slug` of `seat` into `zone` of `seat` with a free-mode move (a test
  set-up). Returns `{game, id}`. Free mode stays as it was.
  """
  def place(game, seat, slug, zone, at \\ nil) do
    id = find(game, seat, slug)
    was = game.free
    game = game |> ok!({:free_mode, true}) |> ok!({:move, id, {seat, zone}, at})
    game = if was, do: game, else: ok!(game, {:free_mode, false})
    {game, id}
  end

  @doc "Set a side's gold by hand."
  def gold(game, seat, n), do: put_in(game.sides[seat].gold, n)

  @doc "The legal actions of the game (rules)."
  def legal(game), do: Game.legal_actions(game, 0)

  @doc "The legal attack targets of `a`."
  def attack_targets(game, a), do: for({:attack, ^a, t} <- legal(game), do: t)

  @doc "End the turn; in the tech step, pick the first legal codex cards. The next side's turn."
  def end_turn(game) do
    game = ok!(game, :end_turn)

    case game.phase do
      :tech -> ok!(game, game |> legal() |> Enum.find(&match?({:tech, _}, &1)))
      _ -> game
    end
  end

  @doc """
  A new copy of card `slug` for `seat`, put into `zone` (a test set-up for cards
  that side does not own, or a second copy). Returns `{game, id}`.
  """
  def spawn(game, seat, slug, zone, at \\ nil) do
    {game, [id]} = Game.add_cards(game, seat, [slug])
    {Codex.Zones.insert(game, id, {seat, zone}, at), id}
  end

  @doc "A Red (P1) vs Green (P2) game."
  def red_green(seed \\ {1, 2, 3}), do: elem(Game.new(%{preset: "red_green"}, seed), 1)

  @doc "Every Codex rules action of a card: `{:ability, id, name, targets}`."
  def abilities(game, id), do: for({:ability, ^id, name, t} <- legal(game), do: {name, t})

  @doc "The target lists card `id` can be played with."
  def plays(game, id), do: for({:play, ^id, t} <- legal(game), do: t)
end
