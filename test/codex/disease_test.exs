defmodule Codex.DiseaseTest do
  @moduledoc "The 12 Disease codex cards (Black)."
  use ExUnit.Case, async: true

  import Codex.TestHelpers

  alias Codex.{CardRules, Stats}

  # P1 (Black) with Orpal Gloor (the Disease hero) in play, tech buildings, gold.
  defp table do
    game = black_blue() |> gold(0, 20) |> set_tech(0, [:tech_1, :tech_2, :tech_3], "Disease")
    {game, o} = place(game, 0, "orpal-gloor", :in_play)
    {game, o}
  end

  test "every Disease card runs (none is manual)" do
    for slug <- Codex.Cards.codex("Disease"), do: refute(CardRules.manual?(slug), slug)
  end

  test "Sickness: a -1/-1 rune on up to two units and/or heroes" do
    {game, _} = table()
    {game, a} = spawn(game, 1, "tax-collector", :in_play)
    {game, b} = spawn(game, 1, "scribe", :in_play)
    {game, s} = place(game, 0, "sickness", :hand)
    game = ok!(game, {:play, s, [a, b]})
    assert game.cards[a].minus == 1 and game.cards[b].minus == 1
  end

  test "Spreading Plague: destroy tech 0-II units and heroes with -1/-1 runes" do
    {game, _} = table()
    {game, a} = spawn(game, 1, "tax-collector", :in_play)
    {game, b} = spawn(game, 1, "scribe", :in_play)
    {game, c} = spawn(game, 1, "lawbringer-gryphon", :in_play)
    game = put_card(game, a, minus: 1) |> put_card(c, minus: 1)
    {game, sp} = place(game, 0, "spreading-plague", :hand)
    game = ok!(game, {:play, sp, []})
    assert a in zone(game, 1, :discard)
    assert b in zone(game, 1, :in_play) and c in zone(game, 1, :in_play)
  end

  test "Carrion Curse: the opponent discards up to two non-unit cards from hand" do
    {game, _} = table()
    {game, x} = spawn(game, 1, "boot-camp", :hand)
    {game, y} = spawn(game, 1, "jail", :hand)
    {game, u} = spawn(game, 1, "scribe", :hand)
    game = put_in(game.sides[1].zones.hand, [x, y, u])
    {game, cc} = place(game, 0, "carrion-curse", :hand)
    game = ok!(game, {:play, cc, []})
    assert hand(game, 1) == [u]
  end

  test "Death and Decay: the opponent's forces -3/-3 this turn, 3 damage to its buildings" do
    {game, o} = table()
    game = Codex.Effects.level_up(game, o, 5)
    game = game |> end_turn() |> end_turn() |> gold(0, 20)
    game = put_in(game.sides[1].tech_buildings, [:tech_1])
    {game, a} = spawn(game, 1, "tax-collector", :in_play)
    {game, b} = spawn(game, 1, "lawbringer-gryphon", :in_play)
    {game, dd} = place(game, 0, "death-and-decay", :hand)
    game = ok!(game, {:play, dd, []})
    assert a in zone(game, 1, :discard)
    assert Stats.atk(game, b) == 4
    assert game.sides[1].base_hp == 17 and game.sides[1].building_damage.tech_1 == 3
  end

  test "Crypt Crawler: sparkshot; ① → a flier loses flying this turn" do
    {game, _} = table()
    {game, c} = place(game, 0, "crypt-crawler", :in_play)
    {game, f} = spawn(game, 1, "spectral-roc", :in_play)
    game = put_card(game, f, card: "air-hammer")
    assert Stats.kw?(game, c, :sparkshot)
    game = ok!(game, {:ability, c, :ground, [f]})
    refute Stats.kw?(game, f, :flying)
    game = ok!(game, :end_turn)
    assert Stats.kw?(game, f, :flying)
  end

  test "Plague Spitter: anti-air; damage to units as -1/-1 runes" do
    {game, _} = table()
    {game, p} = place(game, 0, "plague-spitter", :in_play)
    {game, u} = spawn(game, 1, "lawbringer-gryphon", :in_play)
    assert Stats.kw?(game, p, :anti_air)
    game = ok!(game, {:attack, p, u})
    assert game.cards[u].minus == 3 and game.cards[u].damage == 0
  end

  test "Gorgon kills with deathtouch and draws when it dies" do
    {game, _} = table()
    {game, g} = place(game, 0, "gorgon", :in_play)
    {game, u} = spawn(game, 1, "justice-juggernaut", :in_play)
    game = put_card(game, u, extra: %{crumbling: true})
    n = length(hand(game, 0))
    game = ok!(game, {:attack, g, u})
    assert u in zone(game, 1, :discard) and g in zone(game, 0, :discard)
    assert length(hand(game, 0)) == n + 1
  end

  test "Cursed Ghoul: arrives: a -1/-1 rune on a unit; unstoppable by units with -1/-1 runes" do
    {game, _} = table()
    {game, p} = spawn(game, 1, "tax-collector", :patrol, :squad_leader)
    {game, g} = place(game, 0, "cursed-ghoul", :hand)
    game = ok!(game, {:play, g, [p]})
    assert game.cards[p].minus == 1
    game = game |> end_turn() |> end_turn()
    assert {:building, 1, :base} in attack_targets(game, g)
  end

  test "Cursed Crow: flying; damages a base: the defender discards at random" do
    {game, _} = table()
    {game, c} = place(game, 0, "cursed-crow", :in_play)
    n = length(hand(game, 1))
    game = ok!(game, {:attack, c, {:building, 1, :base}})
    assert length(hand(game, 1)) == n - 1 and game.sides[1].base_hp == 17
  end

  test "Abomination: all other units get -1/-1" do
    {game, _} = table()
    {game, a} = place(game, 0, "abomination", :in_play)
    {game, mine} = place(game, 0, "thieving-imp", :in_play)
    {game, theirs} = spawn(game, 1, "tax-collector", :in_play)
    assert Stats.atk(game, a) == 6 and Stats.hp(game, mine) == 1 and Stats.atk(game, theirs) == 1
  end

  test "Plague Lab: arrives: -1/-1 on the opponent's units; ②, ⤵ → more runes of a kind there" do
    {game, _} = table()
    {game, u} = spawn(game, 1, "lawbringer-gryphon", :in_play)
    {game, mine} = place(game, 0, "thieving-imp", :in_play)
    game = put_card(game, mine, plus: 1)
    {game, pl} = place(game, 0, "plague-lab", :hand)
    game = ok!(game, {:play, pl, []})
    assert game.cards[u].minus == 1
    game = game |> end_turn() |> end_turn() |> gold(0, 5)
    game = ok!(game, {:ability, pl, :plague_lab, []})
    assert game.cards[u].minus == 2 and game.cards[mine].plus == 2
    assert game.sides[0].gold == 3
  end

  test "Plague Lord: arrives or attacks: -1/-1 on each opposing force; upkeep: bases take damage per rune" do
    {game, _} = table()
    {game, u} = spawn(game, 1, "lawbringer-gryphon", :in_play)
    {game, pl} = place(game, 0, "plague-lord", :hand)
    game = ok!(game, {:play, pl, []})
    assert game.cards[u].minus == 1 and Stats.resist(game, pl) == 2
    game = game |> end_turn() |> end_turn()
    assert game.sides[1].base_hp == 19
  end
end
