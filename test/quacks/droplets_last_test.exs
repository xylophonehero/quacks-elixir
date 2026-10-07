defmodule Quacks.DropletsLastTest do
  @moduledoc """
  Round 18: on the reverse pot side, droplet moves won in the evaluation wait while
  the evaluation asks its choices (`:chip_choice`, `:witch_choice`); the seat answers
  those first, the evaluation ends and is logged, and the droplet choice comes in
  the shop.
  """
  use ExUnit.Case, async: true

  import Quacks.GameHelpers

  alias Quacks.Game
  alias Quacks.Rules.PotTrack

  @seed {1, 2, 3}

  defp new(rules),
    do: Game.new(seed: @seed, fortune: false, sets: %{green: 2}, rules: rules)

  # An exploded seat that chose to buy (no bonus die), with a green 2 on its last
  # chip (G2: a choice); then one droplet move won in step A or B waits.
  defp evaluate(g) do
    g
    |> put(phase: :explosion_choice, exploded?: true, drawn: [{{:green, 2}, 10}], pot_index: 10)
    |> apply!({:explosion_choice, :buy})
    |> put(droplet_moves: 1)
  end

  test "the chip choice comes first; the droplet waits for the shop" do
    g = evaluate(new(%{supply: :limited, pot_side: :back}))

    assert g.phase == :chip_choice
    assert Game.phase(g, 0) == :chip_choice
    assert {:droplet, :tube} not in Game.legal_actions(g, 0)
    assert {:error, {:illegal_action, _, :chip_choice}} = Game.apply(g, 0, {:droplet, :tube})

    g = apply!(g, :chip_done)

    # the evaluation is over: steps C/D paid the coins before the droplet
    assert g.phase == :shopping
    assert me(g).coins == PotTrack.at(11).coins
    assert Game.phase(g, 0) == :droplet_choice
    assert Game.legal_actions(g, 0) == [{:droplet, :pot}, {:droplet, :tube}]

    g = apply!(g, {:droplet, :tube})
    assert me(g).tube == 1 and me(g).droplet_moves == 0
    assert Game.phase(g, 0) == :shop
  end

  test "outside the evaluation's choices a waiting move still comes first" do
    g = new(%{pot_side: :back}) |> put(droplet_moves: 1)
    assert Game.phase(g, 0) == :droplet_choice
    assert Game.legal_actions(g, 0) == [{:droplet, :pot}, {:droplet, :tube}]
  end
end
