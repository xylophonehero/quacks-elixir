defmodule Quacks.Game.Round do
  @moduledoc false
  # The engine's round steps that the submodules call: the start of a round (the
  # card, then the rats), the rats, and the shop. Internal, like `Quacks.Game.State`
  # (issue #79).

  alias Quacks.Game.{Essence, Fortune, State, Witches}
  alias Quacks.Rules.ScoringTrack

  # Rulebook §3 steps 1–2: the Fortune Teller card, then the rats. A purple card's
  # VP (its choices included) count for the rats, so `Fortune.resolve/1` places them
  # once the card is through (`rats/1`); only the cards about the rats (Infestation,
  # Good Start) find them placed first (round 28). Nervousness lays out its chips.
  def start_round(g) do
    g
    |> Fortune.draw()
    |> Fortune.resolve()
    |> Essence.display()
  end

  # The round's rats; The Alchemists: a rat-tail glass adds to them.
  def rats(g), do: g |> place_rats() |> Essence.rats()

  # Rulebook §3 step 2 (round 2+, 2+ players): everyone behind the leader counts the
  # rat tails up to the leader and starts that many spaces past their droplet.
  defp place_rats(%{seats: [_]} = g), do: g
  defp place_rats(%{rules: %{rats: false}} = g), do: g

  defp place_rats(g) do
    leader = g.players |> Map.values() |> Enum.map(& &1.vp) |> Enum.max()

    Enum.reduce(g.seats, g, fn seat, g ->
      case ScoringTrack.rat_tails(State.player(g, seat).vp, leader) do
        0 ->
          g

        tails ->
          g
          |> State.update_player(seat, &%{&1 | rat_stone: tails, pot_index: &1.droplet + tails})
          |> State.record(seat, {:rats, tails})
      end
    end)
  end

  # Open the shop for every seat at once, in one step (`:shop`): buy once, spend
  # rubies, end. ponytail: round 9 has no buy; chips bought now are useless (§7).
  # Coins stay on the player and convert to VP at the seat's `:end_round`.
  # Round 45: a seat the copper witch C1 can help starts in `:upgrade`.
  def to_shop(g) do
    Enum.reduce(g.seats, %{g | phase: :shopping}, fn seat, g ->
      g
      |> State.update_player(seat, &%{&1 | phase: :shop})
      |> Witches.open_upgrade(seat)
    end)
  end
end
