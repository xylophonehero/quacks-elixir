defmodule Quacks.GameTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Quacks.{Game, Session}
  alias Quacks.Rules.PotTrack

  doctest Game

  @seed {1, 2, 3}

  defp new, do: Game.new(seed: @seed)

  defp apply!(game, action) do
    {:ok, game} = Game.apply(game, action)
    game
  end

  defp run(game, actions), do: Enum.reduce(actions, game, &apply!(&2, &1))

  # Draw exactly these chips, in order, by replacing the bag before each draw.
  defp force_draws(game, chips), do: Enum.reduce(chips, game, &apply!(%{&2 | bag: [&1]}, :draw))

  defp inventory(g) do
    chips = Enum.frequencies(g.bag ++ g.drawn ++ g.pending)
    Map.merge(g.supply, chips, fn _chip, a, b -> a + b end)
  end

  defp rolled?(game), do: Enum.any?(game.log, &match?({:bonus_die, _}, &1))

  defp play(game, policy) do
    if Game.over?(game), do: game, else: play(apply!(game, policy.(game)), policy)
  end

  # Deterministic policy: draw while the white sum is 4 or less, keep the VP when
  # exploded, buy the last listed option, spend rubies on the droplet when possible.
  defp cautious(%{phase: :potions} = g) do
    if Game.white_sum(g) <= 4 or g.drawn == [], do: :draw, else: :stop
  end

  defp cautious(%{phase: :buy_chips} = g), do: g |> Game.legal_actions() |> List.last()
  defp cautious(g), do: g |> Game.legal_actions() |> hd()

  test "a fixed seed draws the same chips every time" do
    a = run(new(), [:draw, :draw, :draw])
    b = run(new(), [:draw, :draw, :draw])
    assert a.drawn == b.drawn
    assert length(a.drawn) == 3 and length(a.bag) == 6
    assert a.rng != new().rng
  end

  test "explodes at white sum 8, not at 7" do
    safe = force_draws(new(), [{:white, 3}, {:white, 2}, {:white, 2}])
    assert safe.phase == :potions
    refute safe.exploded?

    boom = force_draws(new(), [{:white, 3}, {:white, 2}, {:white, 3}])
    assert boom.phase == :explosion_choice
    assert boom.exploded?
    assert length(boom.drawn) == 3
    assert Game.legal_actions(boom) == [{:explosion_choice, :vp}, {:explosion_choice, :buy}]
    assert {:error, {:illegal_action, :draw, :explosion_choice}} = Game.apply(boom, :draw)
  end

  test "coloured chips do not count toward the explosion" do
    g = force_draws(new(), [{:white, 3}, {:white, 2}, {:white, 2}, {:green, 4}, {:blue, 4}])
    assert g.phase == :potions
    assert g.pot_index == 15
  end

  test "use_flask returns the last white chip, once per round" do
    g = force_draws(new(), [{:white, 2}, {:white, 1}])
    assert :use_flask in Game.legal_actions(g)

    g = apply!(g, :use_flask)
    assert g.drawn == [{:white, 2}]
    assert g.bag == [{:white, 1}]
    assert g.pot_index == 2
    refute g.flask
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
    g = %{new() | droplet: 50, pot_index: 50} |> force_draws([{:white, 3}, {:white, 3}])
    assert g.pot_index == 53
    assert Game.scoring_index(g) == 53
  end

  test "stopping rolls the die and pays the scoring space" do
    # pot_index 4 -> scoring space 5: 5 coins, 0 VP, ruby
    g = new() |> force_draws([{:white, 3}, {:orange, 1}]) |> apply!(:stop)
    assert rolled?(g)
    assert g.phase == :buy_chips
    assert g.coins == 5
    assert g.rubies >= 2
  end

  test "an exploded player takes rubies and chooses VP or buying, never the die" do
    # pot_index 8 -> scoring space 9: 9 coins, 1 VP, ruby
    boom = force_draws(new(), [{:white, 3}, {:white, 3}, {:white, 2}])

    vp = apply!(boom, {:explosion_choice, :vp})
    assert {vp.vp, vp.rubies, vp.coins, vp.phase} == {1, 2, 0, :spend_rubies}
    refute rolled?(vp)

    buy = apply!(boom, {:explosion_choice, :buy})
    assert {buy.vp, buy.rubies, buy.coins, buy.phase} == {0, 2, 9, :buy_chips}
    refute rolled?(buy)
  end

  test "buying 0, 1 or 2 chips of different colours within the coins" do
    g = %{new() | phase: :buy_chips, coins: 8}
    actions = Game.legal_actions(g)
    assert {:buy, []} in actions
    assert {:buy, [{:green, 2}]} in actions
    assert {:buy, [{:green, 1}, {:orange, 1}]} in actions
    refute {:buy, [{:purple, 1}]} in actions
    refute Enum.any?(actions, &match?({:buy, [{c, _}, {c, _}]}, &1))

    g = apply!(g, {:buy, [{:orange, 1}, {:green, 1}]})
    assert g.coins == 1
    assert g.phase == :spend_rubies
    assert Enum.count(g.bag, &(&1 == {:green, 1})) == 2
    assert {:error, _} = Game.apply(g, {:buy, []})
  end

  test "spending rubies, then ending the round" do
    g = %{new() | phase: :spend_rubies, rubies: 4, flask: false, drawn: [{:white, 1}], round: 5}
    assert Game.legal_actions(g) == [{:rubies, :droplet}, {:rubies, :flask}, :end_round]

    g = g |> apply!({:rubies, :droplet}) |> apply!({:rubies, :flask})
    assert {g.droplet, g.flask, g.rubies} == {1, true, 0}
    assert Game.legal_actions(g) == [:end_round]

    g = apply!(g, {:rubies, :skip})
    assert {g.round, g.phase, g.drawn, g.pot_index} == {6, :potions, [], 1}
    assert length(g.bag) == 9 + 1 + 1
    assert hd(g.log) == :end_round
  end

  test "round 9 converts coins 5->1 VP and rubies 2->1 VP, then the game is over" do
    g = %{new() | round: 9, phase: :spend_rubies, coins: 12, rubies: 5, vp: 10}
    g = apply!(g, :end_round)
    assert Game.over?(g)
    assert Game.score(g) == 10 + 2 + 2
    assert Game.legal_actions(g) == []
    assert {:error, _} = Game.apply(g, :draw)
  end

  test "round 9 skips the shop" do
    g = %{new() | round: 9} |> force_draws([{:white, 3}, {:orange, 1}]) |> apply!(:stop)
    assert g.phase == :spend_rubies
    assert g.coins == 5
  end

  test "a scripted game lasts 9 rounds and ends with a known score" do
    g = play(new(), &cautious/1)
    assert Game.over?(g)
    assert g.round == 9
    assert Game.score(g) == 31
  end

  test "Session replays to the same game and undoes the last action" do
    {:ok, s} = Session.apply(Session.new(@seed), :draw)
    {:ok, s} = Session.apply(s, :draw)
    assert {:error, _} = Session.apply(s, :end_round)
    assert s.game == Session.replay(@seed, s.actions)
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
    assert Session.replay(@seed, session.actions) == direct
  end

  property "random legal play keeps the invariants and never stalls" do
    check all(
            seed <- tuple({positive_integer(), positive_integer(), positive_integer()}),
            picks <- list_of(non_negative_integer(), min_length: 20, max_length: 200)
          ) do
      Enum.reduce_while(picks, Game.new(seed: seed), fn pick, g ->
        if Game.over?(g) do
          assert Game.legal_actions(g) == []
          {:halt, g}
        else
          actions = Game.legal_actions(g)
          assert actions != []
          next = apply!(g, Enum.at(actions, rem(pick, length(actions))))
          # chips are conserved: supply + bag + pot + blue offer per kind is constant
          assert inventory(next) == inventory(g)
          assert next.droplet >= g.droplet
          assert next.pot_index <= 53 and next.round in 1..9
          {:cont, next}
        end
      end)
    end
  end
end
