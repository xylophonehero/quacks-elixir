defmodule Codex.TruthTest do
  @moduledoc "The 12 Truth codex cards (Blue)."
  use ExUnit.Case, async: true

  import Codex.TestHelpers

  alias Codex.{CardRules, Stats}

  # P1 (Blue) with Sirus Quince (the Truth hero) in play, tech buildings, gold.
  defp table do
    game = blue_black() |> gold(0, 20) |> set_tech(0, [:tech_1, :tech_2, :tech_3], "Truth")
    {game, q} = place(game, 0, "sirus-quince", :in_play)
    {game, q}
  end

  test "every Truth card runs (none is manual)" do
    for slug <- Codex.Cards.codex("Truth"), do: refute(CardRules.manual?(slug), slug)
  end

  test "Free Speech: the opponent's heroes can't cast spells and lose abilities until after its next turn" do
    {game, _} = table()
    {game, v} = place(game, 1, "vandy-anadrose", :in_play)
    {game, fs} = place(game, 0, "free-speech", :hand)
    game = ok!(game, {:play, fs, []})
    refute Stats.kw?(game, v, :sparkshot)
    game = game |> end_turn() |> gold(1, 10)
    {game, d} = place(game, 1, "deteriorate", :hand)
    assert plays(game, d) == []
    game = end_turn(game)
    assert Stats.kw?(game, v, :sparkshot)
  end

  test "Hallucination: up to two tech 0-II units are Illusions this turn" do
    {game, _} = table()
    {game, u} = spawn(game, 1, "wight", :in_play)
    {game, h} = place(game, 0, "hallucination", :hand)
    game = ok!(game, {:play, h, [u, nil]})
    assert u in zone(game, 1, :in_play) and Stats.illusion?(game, u)
    game = ok!(game, :end_turn)
    refute Stats.illusion?(game, u)
  end

  test "Hallucination then a targeted spell kills the unit" do
    {game, _} = table()
    {game, u} = spawn(game, 1, "wight", :patrol, :squad_leader)
    {game, h} = place(game, 0, "hallucination", :hand)
    game = ok!(game, {:play, h, [u, nil]})
    {game, a} = place(game, 0, "arrest", :hand)
    game = ok!(game, {:play, a, [u]})
    assert u in zone(game, 1, :discard)
  end

  test "Dreamscape: channeling; all tech 0-II units are Illusions" do
    {game, q} = table()
    {game, u} = spawn(game, 1, "wight", :in_play)
    {game, l} = spawn(game, 1, "lord-of-shadows", :in_play)
    {game, d} = place(game, 0, "dreamscape", :hand)
    game = ok!(game, {:play, d, []})
    assert Stats.illusion?(game, u) and not Stats.illusion?(game, l)
    game = ok!(game, {:free_mode, true}) |> ok!({:move, q, {0, :command}, nil})
    assert d in zone(game, 0, :discard)
  end

  test "Mind Control: an ultimate; attach to a tech 0-II unit, you control it" do
    {game, q} = table()
    game = Codex.Effects.level_up(game, q, 4)
    game = game |> end_turn() |> end_turn() |> gold(0, 20)
    {game, u} = spawn(game, 1, "wight", :in_play)
    {game, mc} = place(game, 0, "mind-control", :hand)
    game = ok!(game, {:play, mc, [u]})
    assert u in zone(game, 0, :in_play) and mc in zone(game, 0, :in_play)
    # Mind Control destroyed: the unit goes back.
    game = Codex.Effects.destroy(game, mc)
    game = Codex.Rules.cleanup(game)
    assert u in zone(game, 1, :in_play)
  end

  test "Spectral Flagbearer, Hound, Tiger, Roc: Illusions; the Flagbearer must be targeted" do
    {game, _} = table()
    {game, f} = place(game, 0, "spectral-flagbearer", :in_play)
    {game, r} = place(game, 0, "spectral-roc", :in_play)
    {game, t} = place(game, 0, "spectral-tiger", :in_play)
    assert Stats.kw?(game, r, :flying) and Stats.illusion?(game, t)
    game = game |> end_turn() |> gold(1, 10)
    {game, _} = place(game, 1, "vandy-anadrose", :in_play)
    {game, d} = place(game, 1, "deteriorate", :hand)
    assert plays(game, d) == [[f]]
  end

  test "Macciatus: your Illusions get +1/+1 and do not die when targeted" do
    {game, _} = table()
    {game, _m} = place(game, 0, "macciatus-the-whisperer", :in_play)
    {game, h} = place(game, 0, "spectral-hound", :in_play)
    assert Stats.atk(game, h) == 4
    game = game |> end_turn() |> gold(1, 10)
    {game, _} = place(game, 1, "vandy-anadrose", :in_play)
    {game, d} = place(game, 1, "deteriorate", :hand)
    game = ok!(game, {:play, d, [h]})
    assert h in zone(game, 0, :in_play)
  end

  test "Reteller of Truths: the first two of your non-token Illusions to die each turn return to hand" do
    {game, _} = table()
    {game, r} = place(game, 0, "reteller-of-truths", :in_play)
    {game, h} = place(game, 0, "spectral-hound", :in_play)
    {game, t} = place(game, 0, "spectral-tiger", :in_play)
    game = Codex.Effects.destroy(game, h)
    game = Codex.Effects.destroy(game, r)
    game = Codex.Effects.destroy(game, t)
    assert h in hand(game, 0) and r in hand(game, 0)
    assert t in zone(game, 0, :discard)
  end

  test "Eyes of the Chancellor: detector, haste; ⤵ make a friendly unit invisible" do
    {game, _} = table()
    {game, e} = place(game, 0, "eyes-of-the-chancellor", :hand)
    game = ok!(game, {:play, e, []})
    {game, u} = place(game, 0, "spectral-hound", :in_play)
    game = ok!(game, {:ability, e, :eyes, [u]})
    assert Stats.kw?(game, u, :invisible)
    game = game |> end_turn()
    assert Stats.kw?(game, u, :invisible)
    game = end_turn(game)
    refute Stats.kw?(game, u, :invisible)
    # The detector: an opposing invisible unit can be targeted.
    {game, spy} = spawn(game, 1, "flagstone-spy", :in_play)
    assert Codex.Targets.targetable?(game, 0, spy)
  end

  test "Liberty Gryphon: unstoppable, unattackable, untargetable with another Illusion" do
    {game, _} = table()
    {game, g} = place(game, 0, "liberty-gryphon", :in_play)
    assert Stats.kw?(game, g, :haste) and Stats.kw?(game, g, :flying)
    refute Stats.kw?(game, g, :untargetable)
    {game, _} = place(game, 0, "spectral-hound", :in_play)
    assert Stats.kw?(game, g, :untargetable) and Stats.kw?(game, g, :unattackable)
    assert Stats.kw?(game, g, :unstoppable)
  end
end
