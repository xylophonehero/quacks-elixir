defmodule Codex.BloodTest do
  @moduledoc "The 12 Blood codex cards (Red)."
  use ExUnit.Case, async: true

  import Codex.TestHelpers

  alias Codex.{CardRules, Stats}

  # P1 (Red) with Drakk Ramhorn (the Blood hero) in play, tech buildings, gold.
  defp table do
    game =
      red_green()
      |> gold(0, 20)
      |> put_in([Access.key(:sides), 0, :tech_buildings], [:tech_1, :tech_2, :tech_3])
      |> put_in([Access.key(:sides), 0, :tech_spec], "Blood")

    {game, drakk} = place(game, 0, "drakk-ramhorn", :in_play)
    {game, drakk}
  end

  test "every Blood card runs (none is manual)" do
    for slug <- Codex.Cards.codex("Blood"), do: refute(CardRules.manual?(slug), slug)
  end

  test "Desperation: only with no other card in hand; trash it, draw 3; discard the hand at the end of the main phase" do
    {game, _} = table()
    {game, d} = place(game, 0, "desperation", :hand)
    refute Enum.any?(legal(game), &match?({:play, ^d, _}, &1))
    others = hand(game, 0) -- [d]

    game =
      game
      |> put_in([Access.key(:sides), 0, :zones, :hand], [d])
      |> put_in([Access.key(:sides), 0, :zones, :discard], others ++ zone(game, 0, :discard))

    game = ok!(game, {:play, d, []})
    assert d in game.trash
    assert length(hand(game, 0)) == 3
    game = ok!(game, :end_turn)
    # The hand was discarded at the end of the main phase: 0 discarded → 2 drawn.
    assert length(hand(game, 0)) == 2
  end

  test "Kidnapping: control an opposing tech 0-II unit until the end of the turn, ready, with haste" do
    {game, _} = table()
    {game, u} = place(game, 1, "tiger-cub", :in_play)
    game = put_card(game, u, exhausted: true)
    {game, k} = place(game, 0, "kidnapping", :hand)
    game = ok!(game, {:play, k, [u]})
    assert u in zone(game, 0, :in_play)
    assert {:building, 1, :base} in attack_targets(game, u)
    game = ok!(game, :end_turn)
    assert u in zone(game, 1, :in_play)
  end

  test "Bloodlust: up to two forces +1 ATK and haste this turn, then 1 damage each" do
    {game, _} = table()
    {game, u} = place(game, 0, "nautical-dog", :hand)
    game = ok!(game, {:play, u, []})
    {game, bl} = place(game, 0, "bloodlust", :hand)
    game = ok!(game, {:play, bl, [u, nil]})
    assert Stats.atk(game, u) == 3
    assert {:building, 1, :base} in attack_targets(game, u)
    game = end_turn(game)
    # 1 damage killed the 1/1 dog.
    refute u in zone(game, 0, :in_play)
  end

  test "War Drums: an ultimate ongoing spell, channeling; your units get +X ATK (X = your units)" do
    {game, drakk} = table()
    game = put_card(game, drakk, level: 6)
    {game, a} = place(game, 0, "nautical-dog", :in_play)
    {game, _b} = place(game, 0, "mad-man", :in_play)
    game = game |> end_turn() |> end_turn() |> gold(0, 20)
    {game, wd} = place(game, 0, "war-drums", :hand)
    game = ok!(game, {:play, wd, []})
    # Dog 1 + frenzy 1 + Drakk frenzy 1 + 2 units.
    assert Stats.atk(game, a) == 5
    game = game |> free() |> ok!({:adjust_card, drakk, :damage, 9}) |> ok!({:free_mode, false})
    assert wd in zone(game, 0, :discard)
  end

  test "Crash Bomber dies on your turn: 1 damage to a patroller or building; on the other turn: to that player's base" do
    {game, _} = table()
    {game, cb} = place(game, 0, "crash-bomber", :in_play)
    {game, p} = place(game, 1, "tiger-cub", :patrol, :squad_leader)
    game = put_card(game, p, damage: 1)
    game = ok!(game, {:attack, cb, p})
    # The bomber died on its turn: 1 damage finished the cub (2 HP, 1 armor).
    assert p in zone(game, 1, :discard)
  end

  test "Rickety Mine: ⤵ gain 3 gold, flip a coin" do
    {game, _} = table()
    {game, m} = place(game, 0, "rickety-mine", :in_play)
    game = gold(game, 0, 0)
    game = ok!(game, {:ability, m, :mine, []})
    assert game.sides[0].gold == 3
    assert Enum.any?(game.log, &match?({:coin, _}, &1))
  end

  test "Shoddy Glider and Crashbarrow: haste and ephemeral" do
    {game, _} = table()
    {game, g} = place(game, 0, "shoddy-glider", :hand)
    game = ok!(game, {:play, g, []})
    assert {:building, 1, :base} in attack_targets(game, g)
    game = end_turn(game)
    refute g in zone(game, 0, :in_play)
  end

  test "Captured Bugblatter: whenever a unit dies, the opposing base takes 1" do
    {game, _} = table()
    {game, _bug} = place(game, 0, "captured-bugblatter", :in_play)
    {game, u} = place(game, 1, "tiger-cub", :in_play)
    game = game |> free() |> ok!({:adjust_card, u, :damage, 2}) |> ok!({:free_mode, false})
    assert game.sides[1].base_hp == 19
  end

  test "Land Octopus: upkeep, sacrifice two workers or the Octopus; can't patrol" do
    {game, _} = table()
    {game, o} = place(game, 0, "land-octopus", :in_play)
    refute Enum.any?(legal(game), &match?({:patrol, ^o, _}, &1))
    game = game |> end_turn() |> end_turn()
    # 4 workers: the Octopus goes.
    assert o in zone(game, 0, :discard)
  end

  test "Ogre Recruiter: attacks; if it survives, take control of a tech 0 or I unit" do
    {game, _} = table()
    {game, o} = place(game, 0, "ogre-recruiter", :in_play)
    {game, u} = place(game, 1, "tiger-cub", :in_play)
    game = ok!(game, {:attack, o, {:building, 1, :base}})
    assert u in zone(game, 0, :in_play)
  end

  test "Pirate-Gang Commander: arrives with three Pirates; your units deal 1 to each opposing base when they die; free Blood units" do
    {game, _} = table()
    game = put_in(game.sides[0].tech_buildings, [])
    {game, pgc} = place(game, 0, "pirate-gang-commander", :in_play)
    {game, glider} = place(game, 0, "shoddy-glider", :hand)
    assert Codex.Rules.cost(game, 0, glider) == 0
    assert [[]] == plays(game, glider)
    game = game |> put_in([Access.key(:sides), 0, :tech_buildings], [:tech_1, :tech_2, :tech_3])
    {game, pgc2} = spawn(game, 0, "pirate-gang-commander", :hand)
    game = ok!(game, {:play, pgc2, []})
    pirates = for id <- zone(game, 0, :in_play), game.cards[id].card == "pirate", do: id
    assert length(pirates) == 3

    game =
      game |> free() |> ok!({:adjust_card, hd(pirates), :damage, 2}) |> ok!({:free_mode, false})

    # Two Commanders: 2 damage.
    assert game.sides[1].base_hp == 18
    assert pgc
  end
end
