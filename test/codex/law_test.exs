defmodule Codex.LawTest do
  @moduledoc "The 12 Law codex cards (Blue)."
  use ExUnit.Case, async: true

  import Codex.TestHelpers

  alias Codex.{CardRules, Stats}

  # P1 (Blue) with Bigby Hayes (the Law hero) in play, tech buildings, gold.
  defp table do
    game = blue_black() |> gold(0, 20) |> set_tech(0, [:tech_1, :tech_2, :tech_3], "Law")
    {game, bigby} = place(game, 0, "bigby-hayes", :in_play)
    {game, bigby}
  end

  test "every Law card runs (none is manual)" do
    for slug <- Codex.Cards.codex("Law"), do: refute(CardRules.manual?(slug), slug)
  end

  test "Injunction: disable a tech building and that player's units of its tech level" do
    {game, _} = table()
    game = set_tech(game, 1, [:tech_1, :tech_2], "Necromancy")
    {game, t1} = spawn(game, 1, "bone-collector", :in_play)
    {game, t2} = spawn(game, 1, "wight", :in_play)
    {game, inj} = place(game, 0, "injunction", :hand)
    game = ok!(game, {:play, inj, [{:building, 1, :tech_2}]})
    assert game.cards[t2].exhausted and game.cards[t2].extra.disabled
    refute game.cards[t1].exhausted
    # Not operational on P2's next turn: no tech II units, no tech III.
    game = game |> end_turn() |> gold(1, 20) |> add_workers(1, 10)
    {game, w} = place(game, 1, "necromancer", :hand)
    assert plays(game, w) == []
    refute {:build, :tech_3} in legal(game)
    # After that turn it works again.
    game = game |> end_turn() |> end_turn() |> gold(1, 20)
    {game, w} = place(game, 1, "necromancer", :hand)
    assert plays(game, w) == [[]]
  end

  test "Community Service: a tech I/II unit from an opponent's discard pile or hand into play for you" do
    {game, _} = table()
    {game, u} = place(game, 1, "wight", :discard)
    {game, cs} = place(game, 0, "community-service", :hand)
    game = ok!(game, {:play, cs, []})
    assert u in zone(game, 0, :in_play)
    assert game.cards[u].seat == 1
    assert game.sides[0].gold == 15
  end

  test "Jurisdiction: play a non-ultimate spell from your codex, paying its cost" do
    {game, _} = table()
    {game, j} = place(game, 0, "jurisdiction", :hand)
    {game, u} = spawn(game, 1, "bone-collector", :in_play)
    inj = Enum.find(zone(game, 0, :codex), &(game.cards[&1].card == "community-service"))
    targets = plays(game, j)
    assert [inj] in targets
    refute Enum.any?(targets, fn [c | _] -> game.cards[c].card == "judgment-day" end)
    [cid] = Enum.find(targets, fn [c | _] -> game.cards[c].card == "community-service" end)
    game = put_in(game.sides[1].zones.discard, [u | game.sides[1].zones.discard])
    game = put_in(game.sides[1].zones.in_play, game.sides[1].zones.in_play -- [u])
    game = ok!(game, {:play, j, [cid]})
    assert game.sides[0].gold == 13
    assert cid in zone(game, 0, :discard) and j in zone(game, 0, :discard)
    assert u in zone(game, 0, :in_play)
  end

  test "Judgment Day: a max-level Law hero casts it at once; destroy all tech 0-II units" do
    {game, bigby} = table()
    game = Codex.Effects.level_up(game, bigby, 4)
    {game, a} = place(game, 0, "scribe", :in_play)
    {game, b} = spawn(game, 1, "wight", :in_play)
    {game, c} = spawn(game, 1, "lord-of-shadows", :in_play)
    {game, jd} = place(game, 0, "judgment-day", :hand)
    game = ok!(game, {:play, jd, []})
    assert a in zone(game, 0, :discard) and b in zone(game, 1, :discard)
    assert c in zone(game, 1, :in_play) and bigby in zone(game, 0, :in_play)
  end

  test "Tax Collector steals 1 gold; Scribe draws a card" do
    {game, _} = table()
    game = put_in(game.sides[1].gold, 2)
    {game, t} = place(game, 0, "tax-collector", :hand)
    game = ok!(game, {:play, t, []})
    assert game.sides[1].gold == 1 and game.sides[0].gold == 19
    {game, s} = place(game, 0, "scribe", :hand)
    n = length(hand(game, 0))
    game = ok!(game, {:play, s, []})
    assert length(hand(game, 0)) == n
  end

  test "Guardian of the Gates: can't attack; disables a unit it deals combat damage to" do
    {game, _} = table()
    {game, g} = place(game, 0, "guardian-of-the-gates", :patrol, :squad_leader)
    assert attack_targets(game, g) == []
    game = end_turn(game)
    {game, a} = spawn(game, 1, "bone-collector", :in_play)
    game = ok!(game, {:attack, a, g})
    assert game.cards[a].extra.disabled
  end

  test "Insurance Agent: when the insured unit dies, gain its cost in gold and draw" do
    {game, _} = table()
    {game, u} = place(game, 0, "justice-juggernaut", :in_play)
    game = put_card(game, u, extra: %{crumbling: true})
    {game, ia} = place(game, 0, "insurance-agent", :hand)
    game = ok!(game, {:play, ia, [u]}) |> gold(0, 5)
    gold = game.sides[0].gold
    n = length(hand(game, 0))
    game = Codex.Effects.destroy(game, u)
    assert game.sides[0].gold == gold + 6
    assert length(hand(game, 0)) == n + 1
  end

  test "Insurance Agent on an Illusion: it dies at once, no insurance" do
    {game, _} = table()
    {game, aven} = place(game, 0, "spectral-aven", :in_play)
    {game, ia} = place(game, 0, "insurance-agent", :hand)
    gold = game.sides[0].gold
    game = ok!(game, {:play, ia, [aven]})
    assert aven in zone(game, 0, :discard)
    assert game.sides[0].gold == gold - 1
  end

  test "Justice Juggernaut: unstoppable, can't patrol, two lives" do
    {game, _} = table()
    {game, j} = place(game, 0, "justice-juggernaut", :in_play)
    {game, _} = spawn(game, 1, "wight", :patrol, :squad_leader)
    assert {:building, 1, :base} in attack_targets(game, j)
    refute Enum.any?(legal(game), &match?({:patrol, ^j, _}, &1))
    game = Codex.Effects.destroy(game, j)
    assert j in zone(game, 0, :in_play) and game.cards[j].extra.crumbling
    game = Codex.Effects.destroy(game, j)
    assert j in zone(game, 0, :discard)
  end

  test "Arresting Constable: ⤵ → disable a tech 0-II unit" do
    {game, _} = table()
    {game, c} = place(game, 0, "arresting-constable", :in_play)
    {game, u} = spawn(game, 1, "wight", :patrol, :elite)
    {game, l} = spawn(game, 1, "lord-of-shadows", :in_play)
    targets = for {:arrest, [t]} <- abilities(game, c), do: t
    assert u in targets and l not in targets
    game = ok!(game, {:ability, c, :arrest, [u]})
    assert game.cards[u].extra.disabled and u in zone(game, 1, :in_play)
  end

  test "Censorship Council: opponents play at most one card from hand each turn" do
    {game, _} = table()
    {game, _} = place(game, 0, "censorship-council", :in_play)
    game = game |> end_turn() |> gold(1, 20)
    {game, a} = place(game, 1, "pestering-haunt", :hand)
    {game, b} = place(game, 1, "thieving-imp", :hand)
    game = ok!(game, {:play, a, []})
    assert plays(game, b) == []
    assert Enum.any?(legal(game), &match?({:hire, _}, &1))
  end

  test "Lawbringer Gryphon: flying, resist 2, obliterate 4; your base gains flying" do
    {game, _} = table()
    {game, g} = place(game, 0, "lawbringer-gryphon", :in_play)
    assert Stats.kw?(game, g, :flying) and Stats.resist(game, g) == 2
    game = end_turn(game)
    {game, a} = spawn(game, 1, "bone-collector", :in_play)
    game = put_card(game, a, fatigued: false)
    refute {:building, 0, :base} in attack_targets(game, a)
    {game, f} = spawn(game, 1, "spectral-aven", :in_play)
    game = put_card(game, f, fatigued: false)
    assert {:building, 0, :base} in attack_targets(game, f)
  end
end
