defmodule Codex.SetupTest do
  @moduledoc "Set-up presets, a custom set-up, and the 3-hero mode rules (research §2)."
  use ExUnit.Case, async: true

  import Codex.TestHelpers

  alias Codex.{Cards, Game}

  defp slugs(game, seat, zone), do: Enum.map(zone(game, seat, zone), &game.cards[&1].card)

  test "Red vs Green: colour starting decks, 3 heroes, 72 codex cards each" do
    game = red_green()

    assert Enum.sort(slugs(game, 0, :hand) ++ slugs(game, 0, :deck)) ==
             Enum.sort(Cards.starter("Red"))

    assert Enum.sort(slugs(game, 1, :hand) ++ slugs(game, 1, :deck)) ==
             Enum.sort(Cards.starter("Green"))

    assert Enum.sort(slugs(game, 0, :command)) == ~w(captain-zane drakk-ramhorn jaina-stormborne)
    assert Enum.sort(slugs(game, 1, :command)) == ~w(argagarg-garg calamandra-moss master-midori)
    assert length(zone(game, 0, :codex)) == 72
    assert game.sides[1].specs == ["Balance", "Feral", "Growth"]
    assert game.sides[0].tech_spec == nil
    assert_conserved(game)
  end

  test "the first game stays the default" do
    game = new()
    assert game.sides[0].specs == ["Bashing"]
    assert game.sides[0].tech_spec == "Bashing"
  end

  test "custom: a starting deck and one spec per side" do
    {:ok, game} =
      Game.new(
        %{
          "preset" => "custom",
          "p1_starter" => "Green",
          "p1_spec" => "Fire",
          "p2_starter" => "Neutral",
          "p2_spec" => "Feral"
        },
        {1, 1, 1}
      )

    assert Enum.sort(slugs(game, 0, :hand) ++ slugs(game, 0, :deck)) ==
             Enum.sort(Cards.starter("Green"))

    assert slugs(game, 0, :command) == ["jaina-stormborne"]
    assert slugs(game, 1, :command) == ["calamandra-moss"]

    assert Game.new(%{"preset" => "custom", "p1_starter" => "Pink"}, {1, 1, 1}) ==
             {:error, :invalid_setup}

    assert Game.new(%{preset: "nope"}, {1, 1, 1}) == {:error, :invalid_setup}
  end

  describe "3-hero mode" do
    test "hero limit: 1, +1 with tech II, +1 with tech III" do
      game = red_green() |> gold(0, 20)
      [a, b, c] = zone(game, 0, :command)
      game = ok!(game, {:summon, a})
      refute {:summon, b} in legal(game)
      game = put_in(game.sides[0].tech_buildings, [:tech_1, :tech_2])
      game = ok!(game, {:summon, b})
      refute {:summon, c} in legal(game)
      game = put_in(game.sides[0].tech_buildings, [:tech_1, :tech_2, :tech_3])
      assert {:summon, c} in legal(game)
    end

    test "tech II: declare a spec; tech II units of the other specs cannot be played" do
      game = red_green() |> gold(0, 20)
      {extra, _} = Game.add_cards(game, 0, List.duplicate("worker", 4))
      ids = Map.keys(extra.cards) -- Map.keys(game.cards)
      game = put_in(extra.sides[0].zones.workers, extra.sides[0].zones.workers ++ ids)
      game = put_in(game.sides[0].tech_buildings, [:tech_1])
      assert {:build, :tech_2, "Fire"} in legal(game)
      refute {:build, :tech_2} in legal(game)
      game = ok!(game, {:build, :tech_2, "Fire"}) |> end_turn() |> end_turn() |> gold(0, 20)
      assert game.sides[0].tech_spec == "Fire"
      {game, archer} = place(game, 0, "doubleshot-archer", :hand)
      {game, tank} = place(game, 0, "steam-tank", :hand)
      assert Enum.any?(legal(game), &match?({:play, ^archer, _}, &1))
      refute Enum.any?(legal(game), &match?({:play, ^tank, _}, &1))
    end

    test "Heroes' Hall: an add-on in 3-hero mode only" do
      assert {:build, :heroes_hall} in legal(red_green() |> gold(0, 5))
      refute {:build, :heroes_hall} in legal(new() |> gold(0, 5))
    end

    test "a coloured minor spell costs 1 more without a hero of its colour" do
      {:ok, game} =
        Game.new(
          %{
            preset: "custom",
            p1_starter: "Red",
            p1_spec: "Bashing",
            p2_starter: "Neutral",
            p2_spec: "Finesse"
          },
          {1, 1, 1}
        )

      game = gold(game, 0, 20)
      {game, _} = place(game, 0, "troq-bashar", :in_play)
      {game, scorch} = place(game, 0, "scorch", :hand)
      assert Codex.Rules.cost(game, 0, scorch) == 4
    end
  end
end
