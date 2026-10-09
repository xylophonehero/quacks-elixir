defmodule Quacks.DropletsLastTest do
  @moduledoc """
  Round 18: on the reverse pot side, droplet moves won in the evaluation wait while
  the gold witches ask (`:witch_choice`); the droplet choice comes in the shop.
  Round 35: in the chip actions' choices (`:chip_choice`) the droplet move comes
  first (the die and black before green and purple).
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

  # Round 35 (item 7): rulebook §3.2 B resolves black before green and purple, and
  # the die (step A) comes before them all: a free droplet move won there comes
  # before the chip choices. The scoring space does not move with it.
  test "the droplet move comes first, then the chip choice; the space pays the same" do
    g = evaluate(new(%{supply: :limited, pot_side: :back}))

    assert g.phase == :chip_choice
    assert Game.phase(g, 0) == :droplet_choice
    assert Game.legal_actions(g, 0) == [{:droplet, :pot}, {:droplet, :tube}]
    assert {:error, {:illegal_action, _, _}} = Game.apply(g, 0, :chip_done)

    g = apply!(g, {:droplet, :tube})
    assert me(g).tube == 1 and me(g).droplet_moves == 0
    assert g.phase == :chip_choice and Game.phase(g, 0) == :chip_choice

    g = apply!(g, :chip_done)
    assert g.phase == :shopping
    assert me(g).coins == PotTrack.at(11).coins
    assert Game.phase(g, 0) == :shop
  end

  test "the gold witches' choice still holds a droplet move until the shop" do
    g = new(%{pot_side: :back}) |> put(droplet_moves: 1) |> Map.put(:phase, :witch_choice)
    refute {:droplet, :tube} in Game.legal_actions(g, 0)
  end

  test "outside the evaluation's choices a waiting move still comes first" do
    g = new(%{pot_side: :back}) |> put(droplet_moves: 1)
    assert Game.phase(g, 0) == :droplet_choice
    assert Game.legal_actions(g, 0) == [{:droplet, :pot}, {:droplet, :tube}]
  end
end
