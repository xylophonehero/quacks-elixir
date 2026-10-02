defmodule Quacks.GameTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Quacks.GameHelpers

  alias Quacks.{Game, Session}
  alias Quacks.Rules.{PotTrack, ScoringTrack}

  doctest Game
  doctest ScoringTrack

  @seed {1, 2, 3}

  defp new, do: Game.new(seed: @seed)
  defp new(players), do: Game.new(seed: @seed, players: players)

  defp rolled?(game, seat \\ 0), do: Enum.any?(game.log, &match?({^seat, {:bonus_die, _}}, &1))

  defp play(game, policy) do
    if Game.over?(game), do: game, else: play(apply!(game, policy.(game)), policy)
  end

  # Deterministic policy: draw while the white sum is 4 or less, keep the VP when
  # exploded, buy the last listed option, spend rubies on the droplet when possible.
  defp cautious(g) do
    case Game.phase(g, 0) do
      :potions -> if Game.white_sum(g) <= 4 or me(g).drawn == [], do: :draw, else: :stop
      :buy_chips -> g |> Game.legal_actions() |> List.last()
      _ -> g |> Game.legal_actions() |> hd()
    end
  end

  test "a fixed seed draws the same chips every time" do
    a = run(new(), [:draw, :draw, :draw])
    b = run(new(), [:draw, :draw, :draw])
    assert me(a).drawn == me(b).drawn
    assert length(me(a).drawn) == 3 and length(me(a).bag) == 6
    assert a.rng != new().rng
  end

  test "explodes at white sum 8, not at 7" do
    safe = force_draws(new(), [{:white, 3}, {:white, 2}, {:white, 2}])
    assert Game.phase(safe, 0) == :potions
    refute me(safe).exploded?

    boom = force_draws(new(), [{:white, 3}, {:white, 2}, {:white, 3}])
    assert Game.phase(boom, 0) == :explosion_choice
    assert me(boom).exploded?
    assert length(me(boom).drawn) == 3
    assert Game.legal_actions(boom) == [{:explosion_choice, :vp}, {:explosion_choice, :buy}]
    assert {:error, {:illegal_action, :draw, :explosion_choice}} = Game.apply(boom, :draw)
  end

  test "coloured chips do not count toward the explosion" do
    g = force_draws(new(), [{:white, 3}, {:white, 2}, {:white, 2}, {:green, 4}, {:blue, 4}])
    assert Game.phase(g, 0) == :potions
    assert me(g).pot_index == 15
  end

  test "use_flask returns the last white chip, once per round" do
    g = force_draws(new(), [{:white, 2}, {:white, 1}])
    assert :use_flask in Game.legal_actions(g)

    g = apply!(g, :use_flask)
    assert me(g).drawn == [{{:white, 2}, 2}]
    assert me(g).bag == [{:white, 1}]
    assert me(g).pot_index == 2
    refute me(g).flask
    refute :use_flask in Game.legal_actions(g)
    assert {:error, _} = Game.apply(g, :use_flask)
  end

  test "use_flask is not offered after a coloured chip" do
    g = force_draws(new(), [{:white, 2}, {:orange, 1}])
    assert Game.legal_actions(g) == [:stop]
  end

  test "pot track payout, including the spoon clamp" do
    assert PotTrack.at(0) == %{coins: 0, vp: 0, ruby?: false}
    assert PotTrack.at(5) == %{coins: 5, vp: 0, ruby?: true}
    assert PotTrack.at(36) == %{coins: 25, vp: 9, ruby?: true}
    assert PotTrack.at(53) == %{coins: 35, vp: 15, ruby?: false}
    assert PotTrack.at(99) == PotTrack.at(53)
  end

  test "chips past the spoon land on the spoon" do
    g = new() |> put(droplet: 50, pot_index: 50) |> force_draws([{:white, 3}, {:white, 3}])
    assert me(g).pot_index == 53
    assert Game.scoring_index(g) == 53
  end

  test "stopping rolls the die and pays the scoring space" do
    # pot_index 4 -> scoring space 5: 5 coins, 0 VP, ruby
    g = new() |> force_draws([{:white, 3}, {:orange, 1}]) |> apply!(:stop)
    assert rolled?(g)
    assert g.phase == :buy_chips
    assert me(g).coins == 5
    assert me(g).rubies >= 2
  end

  test "an exploded player takes rubies and chooses VP or buying, never the die" do
    # pot_index 8 -> scoring space 9: 9 coins, 1 VP, ruby
    boom = force_draws(new(), [{:white, 3}, {:white, 3}, {:white, 2}])

    vp = apply!(boom, {:explosion_choice, :vp})
    assert {me(vp).vp, me(vp).rubies, me(vp).coins, vp.phase} == {1, 2, 0, :spend_rubies}
    refute rolled?(vp)

    buy = apply!(boom, {:explosion_choice, :buy})
    assert {me(buy).vp, me(buy).rubies, me(buy).coins, buy.phase} == {0, 2, 9, :buy_chips}
    refute rolled?(buy)
  end

  test "buying 0, 1 or 2 chips of different colours within the coins" do
    g = put(new(), phase: :buy_chips, coins: 8)
    actions = Game.legal_actions(g)
    assert {:buy, []} in actions
    assert {:buy, [{:green, 2}]} in actions
    assert {:buy, [{:green, 1}, {:orange, 1}]} in actions
    refute {:buy, [{:purple, 1}]} in actions
    refute Enum.any?(actions, &match?({:buy, [{c, _}, {c, _}]}, &1))

    g = apply!(g, {:buy, [{:orange, 1}, {:green, 1}]})
    assert me(g).coins == 1
    assert g.phase == :spend_rubies
    assert Enum.count(me(g).bag, &(&1 == {:green, 1})) == 2
    assert {:error, _} = Game.apply(g, {:buy, []})
  end

  test "spending rubies, then ending the round" do
    g =
      put(new(),
        phase: :spend_rubies,
        rubies: 4,
        flask: false,
        drawn: [{{:white, 1}, 1}],
        round: 5
      )

    assert Game.legal_actions(g) == [{:rubies, :droplet}, {:rubies, :flask}, :end_round]

    g = g |> apply!({:rubies, :droplet}) |> apply!({:rubies, :flask})
    assert {me(g).droplet, me(g).flask, me(g).rubies} == {1, true, 0}
    assert Game.legal_actions(g) == [:end_round]

    g = apply!(g, {:rubies, :skip})
    assert {g.round, g.phase, me(g).drawn, me(g).pot_index} == {6, :potions, [], 1}
    assert length(me(g).bag) == 9 + 1 + 1
    assert Enum.take(g.log, 2) == [{:round_end, 5}, {0, :end_round}]
  end

  test "round 9 converts coins 5->1 VP and rubies 2->1 VP, then the game is over" do
    g = put(new(), round: 9, phase: :spend_rubies, coins: 12, rubies: 5, vp: 10)
    g = apply!(g, :end_round)
    assert Game.over?(g)
    assert Game.score(g) == %{0 => 10 + 2 + 2}
    assert Game.legal_actions(g) == []
    assert {:error, _} = Game.apply(g, :draw)
  end

  test "round 9 skips the shop" do
    g = new() |> put(round: 9) |> force_draws([{:white, 3}, {:orange, 1}]) |> apply!(:stop)
    assert g.phase == :spend_rubies
    assert me(g).coins == 5
  end

  test "a scripted game lasts 9 rounds and ends with a known score" do
    g = play(new(), &cautious/1)
    assert Game.over?(g)
    assert g.round == 9
    assert Game.score(g) == %{0 => 31}
  end

  test "the log narrates each action: draws, returns, explosions, buys, rubies" do
    g = force_draws(new(), [{:white, 3}, {:white, 2}])
    assert Enum.take(g.log, 2) == [{0, {:drew, {:white, 2}, 5}}, {0, :draw}]

    flask = apply!(g, :use_flask)
    assert Enum.take(flask.log, 2) == [{0, {:returned, {:white, 2}}}, {0, :use_flask}]

    boom = force_draws(g, [{:white, 3}])
    assert hd(boom.log) == {0, {:exploded, 8}}

    shop =
      new() |> put(phase: :buy_chips, coins: 8) |> apply!({:buy, [{:orange, 1}, {:green, 1}]})

    assert hd(shop.log) == {0, {:bought, [{:green, 1}, {:orange, 1}]}}
    assert hd(apply!(put(new(), phase: :buy_chips), {:buy, []}).log) == {0, {:buy, []}}

    rubies = apply!(put(new(), phase: :spend_rubies, rubies: 2), {:rubies, :droplet})
    assert hd(rubies.log) == {0, {:rubies_spent, :droplet}}
  end

  # Scoring events (step C–E and the round end). Chip-action events live in
  # Quacks.ChipEffectsTest.
  test "the log records a ruby taken from the scoring space" do
    # pot_index 4 -> scoring space 5: 5 coins, 0 VP, ruby
    g =
      put(new(),
        phase: :explosion_choice,
        exploded?: true,
        pot_index: 4,
        drawn: [{{:white, 3}, 4}]
      )

    g = apply!(g, {:explosion_choice, :buy})
    assert {0, {:pot_ruby, 5}} in g.log
    refute Enum.any?(g.log, &match?({_, {:pot_vp, _, _}}, &1))
  end

  test "the log records VP taken from the scoring space, not when buying after an explosion" do
    # pot_index 8 -> scoring space 9: 9 coins, 1 VP, ruby
    boom =
      put(new(),
        phase: :explosion_choice,
        exploded?: true,
        pot_index: 8,
        drawn: [{{:white, 3}, 8}]
      )

    assert {0, {:pot_vp, 1, 9}} in apply!(boom, {:explosion_choice, :vp}).log

    refute Enum.any?(
             apply!(boom, {:explosion_choice, :buy}).log,
             &match?({_, {:pot_vp, _, _}}, &1)
           )
  end

  test "the log ends every round with {:round_end, round}" do
    g = apply!(put(new(), phase: :spend_rubies, round: 3), :end_round)
    assert hd(g.log) == {:round_end, 3}
  end

  test "the log records the final conversion in round 9, then the round end" do
    g = put(new(), round: 9, phase: :spend_rubies, coins: 12, rubies: 5)
    g = apply!(g, :end_round)

    assert Enum.take(g.log, 3) == [
             {:round_end, 9},
             {0, {:final_conversion, 2, 2}},
             {0, :end_round}
           ]
  end

  test "Session replays to the same game and undoes the last action" do
    {:ok, s} = Session.apply(Session.new(@seed), :draw)
    {:ok, s} = Session.apply(s, :draw)
    assert {:error, _} = Session.apply(s, :end_round)
    assert s.actions == [{0, :draw}, {0, :draw}]
    assert s.game == Session.replay(@seed, 1, s.actions)
    assert Session.undo(s).game == apply!(new(), :draw)
    assert Session.undo(Session.new(@seed)) == Session.new(@seed)
  end

  test "a whole game played through Session equals the game played directly" do
    direct = play(new(), &cautious/1)

    session =
      Enum.reduce_while(Stream.cycle([nil]), Session.new(@seed), fn _, s ->
        if Game.over?(s.game) do
          {:halt, s}
        else
          {:ok, s} = Session.apply(s, cautious(s.game))
          {:cont, s}
        end
      end)

    assert session.game == direct
    assert Session.replay(@seed, 1, session.actions) == direct
  end

  describe "two or more players" do
    test "new/1 seats 1..4 players, each with a starting bag from the shared supply" do
      g = new(3)
      assert g.seats == [0, 1, 2]
      assert Enum.all?(g.players, fn {_seat, p} -> length(p.bag) == 9 end)
      assert g.supply[{:white, 1}] == 20 - 3 * 4
      assert_raise ArgumentError, fn -> Game.new(seed: @seed, players: 5) end
    end

    test "players draw and stop in any order; the evaluation runs once the last is done" do
      g = new(2)
      assert Game.legal_actions(g, 0) == [:draw] and Game.legal_actions(g, 1) == [:draw]

      # seat 0: white 3, white 2 -> index 5, scoring space 6 (6 coins, 1 VP)
      # seat 1: white 1 -> index 1, scoring space 2 (2 coins)
      g =
        g
        |> force_draws(1, [{:white, 1}])
        |> force_draws(0, [{:white, 3}])
        |> force_draws(0, [{:white, 2}])

      g = apply!(g, 0, :stop)
      assert Game.legal_actions(g, 0) == [] and Game.phase(g, 0) == :done
      assert g.phase == :potions and Game.legal_actions(g, 1) == [:stop, :use_flask]
      refute rolled?(g, 0)
      assert {:error, {:illegal_action, :draw, :done}} = Game.apply(g, 0, :draw)

      g = apply!(g, 1, :stop)
      assert g.phase == :buy_chips and g.turn == 0
      assert me(g, 0).coins == 6 and me(g, 1).coins == 2
      assert {0, {:pot_vp, 1, 6}} in g.log
      assert rolled?(g, 0) and not rolled?(g, 1)
      assert Enum.count(g.log, &match?({_, {:bonus_die, _}}, &1)) == 1
    end

    test "the bonus die goes to the higher scoring space; a tie means both roll" do
      stop_both = fn g -> g |> apply!(0, :stop) |> apply!(1, :stop) end

      g =
        new(2)
        |> put(0, drawn: [{{:orange, 1}, 5}], pot_index: 5)
        |> put(1, drawn: [{{:orange, 1}, 3}], pot_index: 3)

      g = stop_both.(g)
      assert rolled?(g, 0) and not rolled?(g, 1)

      tie =
        new(2)
        |> put(0, drawn: [{{:orange, 1}, 5}], pot_index: 5)
        |> put(1, drawn: [{{:orange, 1}, 5}], pot_index: 5)

      tie = stop_both.(tie)
      assert rolled?(tie, 0) and rolled?(tie, 1)

      # an exploded player never rolls, even on the higher space
      boom =
        new(2)
        |> put(0,
          phase: :explosion_choice,
          exploded?: true,
          drawn: [{{:white, 3}, 9}],
          pot_index: 9
        )

      boom = boom |> put(1, drawn: [{{:orange, 1}, 1}], pot_index: 1)
      boom = boom |> apply!(0, {:explosion_choice, :buy}) |> apply!(1, :stop)
      refute rolled?(boom, 0)
      assert rolled?(boom, 1)
    end

    test "rats: tails strictly between the markers; the first chip counts from the rat stone" do
      assert ScoringTrack.rat_tails(3, 12) == 4
      assert ScoringTrack.rat_tails(12, 12) == 0
      assert ScoringTrack.rat_tails(12, 3) == 0
      assert ScoringTrack.rat_tails(0, 1) == 0
      assert ScoringTrack.rat_tails(0, 2) == 1
      assert ScoringTrack.rat_tails(0, 50) == 2 + 22

      g = new(2) |> put(0, vp: 12) |> put(1, vp: 3, droplet: 2) |> put(phase: :spend_rubies)
      g = g |> apply!(0, :end_round) |> apply!(1, :end_round)
      assert g.round == 2
      assert {me(g, 0).rat_stone, me(g, 0).pot_index} == {0, 0}
      assert {me(g, 1).rat_stone, me(g, 1).pot_index} == {4, 6}
      assert {1, {:rats, 4}} in g.log
      refute Enum.any?(g.log, &match?({0, {:rats, _}}, &1))

      g = force_draws(g, 1, [{:white, 1}])
      assert hd(me(g, 1).drawn) == {{:white, 1}, 7}
      # the flask falls back to the rat stone, not the droplet
      assert me(apply!(g, 1, :use_flask), 1).pot_index == 6

      # a tie for the lead gives nobody rats; the stone is gone at the next round end
      level = new(2) |> put(0, vp: 5) |> put(1, vp: 5) |> put(phase: :spend_rubies)
      level = level |> apply!(0, :end_round) |> apply!(1, :end_round)
      assert me(level, 0).rat_stone == 0 and me(level, 1).rat_stone == 0

      # round 2: seat 1 is the start seat, so seat 0 ends the round
      caught_up = g |> put(0, vp: 3) |> put(1, phase: :spend_rubies)
      caught_up = caught_up |> apply!(1, :end_round) |> apply!(0, :end_round)
      assert {me(caught_up, 1).rat_stone, me(caught_up, 1).pot_index} == {0, 2}
    end

    test "the shop and the rubies phase go round the table from the start seat" do
      g =
        new(2)
        |> put(0, drawn: [{{:orange, 1}, 1}], pot_index: 1)
        |> put(1, drawn: [{{:orange, 1}, 1}], pot_index: 1)

      g = g |> apply!(0, :stop) |> apply!(1, :stop)
      assert {g.phase, g.turn} == {:buy_chips, 0}
      assert Game.legal_actions(g, 1) == []
      assert {:error, {:illegal_action, {:buy, []}, :buy_chips}} = Game.apply(g, 1, {:buy, []})

      g = apply!(g, 0, {:buy, []})
      assert {g.phase, g.turn} == {:buy_chips, 1}
      g = apply!(g, 1, {:buy, []})
      assert {g.phase, g.turn} == {:spend_rubies, 0}
      assert Game.legal_actions(g, 1) == []

      g = apply!(g, 0, :end_round)
      assert {g.phase, g.turn} == {:spend_rubies, 1}
      g = apply!(g, 1, :end_round)
      assert {g.round, g.phase, g.turn} == {2, :potions, nil}
      assert hd(g.log) == {:round_end, 1}

      # round 2 starts with seat 1
      g =
        g
        |> put(0, drawn: [{{:orange, 1}, 1}], pot_index: 1)
        |> put(1, drawn: [{{:orange, 1}, 1}], pot_index: 1)

      g = g |> apply!(0, :stop) |> apply!(1, :stop)
      assert {g.phase, g.turn} == {:buy_chips, 1}
      assert Game.start_seat(g) == 1
    end

    test "an exploded player who took the VP skips the shop" do
      g =
        new(2)
        |> put(0,
          phase: :explosion_choice,
          exploded?: true,
          drawn: [{{:white, 3}, 9}],
          pot_index: 9
        )

      g = g |> put(1, drawn: [{{:orange, 1}, 4}], pot_index: 4)
      g = g |> apply!(0, {:explosion_choice, :vp}) |> apply!(1, :stop)
      assert {g.phase, g.turn} == {:buy_chips, 1}
      assert Game.legal_actions(g, 0) == []
      assert me(g, 0).coins == 0

      # both took the VP: straight to the rubies phase, start seat first
      both = new(2)

      both =
        put(both, 0,
          phase: :explosion_choice,
          exploded?: true,
          drawn: [{{:white, 3}, 9}],
          pot_index: 9
        )

      both =
        put(both, 1,
          phase: :explosion_choice,
          exploded?: true,
          drawn: [{{:white, 3}, 9}],
          pot_index: 9
        )

      both = both |> apply!(0, {:explosion_choice, :vp}) |> apply!(1, {:explosion_choice, :vp})
      assert {both.phase, both.turn} == {:spend_rubies, 0}
    end

    test "round 6 gives every player a white chip; round 9 converts for everyone" do
      g =
        new(2)
        |> put(round: 5, phase: :spend_rubies)
        |> apply!(0, :end_round)
        |> apply!(1, :end_round)

      assert Enum.count(me(g, 0).bag, &(&1 == {:white, 1})) == 5
      assert Enum.count(me(g, 1).bag, &(&1 == {:white, 1})) == 5
      assert g.supply[{:white, 1}] == 20 - 8 - 2

      last =
        new(2)
        |> put(round: 9, phase: :spend_rubies)
        |> put(0, coins: 10, vp: 3)
        |> put(1, rubies: 4, vp: 7)

      last = last |> apply!(0, :end_round) |> apply!(1, :end_round)
      assert Game.over?(last)
      assert Game.score(last) == %{0 => 5, 1 => 9}

      assert Enum.take(last.log, 3) == [
               {:round_end, 9},
               {1, {:final_conversion, 0, 2}},
               {0, {:final_conversion, 2, 0}}
             ]
    end

    test "Session records the seat with each action and replays a 2-player game" do
      {:ok, s} = Session.apply(Session.new(@seed, 2), 1, :draw)
      {:ok, s} = Session.apply(s, 0, :draw)
      assert s.actions == [{0, :draw}, {1, :draw}]
      assert s.game == Session.replay(@seed, 2, s.actions)
      assert Session.undo(s).game == apply!(new(2), 1, :draw)
    end
  end

  property "random legal play by random seats keeps the invariants and never stalls" do
    check all(
            seed <- tuple({positive_integer(), positive_integer(), positive_integer()}),
            players <- integer(1..4),
            picks <- list_of(non_negative_integer(), min_length: 20, max_length: 200)
          ) do
      Enum.reduce_while(picks, Game.new(seed: seed, players: players), fn pick, g ->
        active = Enum.filter(g.seats, &(Game.legal_actions(g, &1) != []))

        if Game.over?(g) do
          assert active == []
          {:halt, g}
        else
          # exactly the expected seats may act: everyone not done, or the turn seat
          assert active != []

          if g.phase == :potions,
            do: assert(active == Enum.reject(g.seats, &me(g, &1).done?)),
            else: assert(active == [g.turn])

          seat = Enum.at(active, rem(pick, length(active)))
          actions = Game.legal_actions(g, seat)
          next = apply!(g, seat, Enum.at(actions, rem(div(pick, 7), length(actions))))
          # chips are conserved: supply + bags + pots + blue offers per kind is constant
          assert inventory(next) == inventory(g)
          assert Enum.all?(g.seats, &(me(next, &1).droplet >= me(g, &1).droplet))
          assert Enum.all?(g.seats, &(me(next, &1).pot_index <= 53)) and next.round in 1..9
          {:cont, next}
        end
      end)
    end
  end
end
