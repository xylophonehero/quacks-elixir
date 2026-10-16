defmodule Table.Generic.RefereeTest do
  @moduledoc "The scripted Crazy Eights referee: whole games and single rules."
  use ExUnit.Case, async: true

  alias Table.Generic.{Game, Spec}
  alias Table.Generic.Referee.Scripted
  alias Table.Kit.Rng

  # Random legal play (a card when it can) to the end.
  defp play(game, rng, steps \\ 0) do
    case Game.status(game) do
      {:over, _} ->
        {game, steps}

      {:playing, [seat]} ->
        actions = Game.legal_actions(game, seat)
        plays = for {:play, _, _} = a <- actions, do: a
        {action, rng} = Rng.pick(if(plays == [], do: actions, else: plays), rng)
        {:ok, game} = Game.apply(game, seat, action)
        assert Enum.sort(Game.all_cards(game)) == Enum.sort(game.spec.cards)
        play(game, rng, steps + 1)
    end
  end

  test "random games with 2 to 5 players end, and replay gives the same state" do
    for players <- 2..5, s <- 1..10 do
      {:ok, game} = Game.new(%{spec: "crazy_eights", players: players}, {s, players, 7})
      {game, _steps} = play(game, Rng.seed({s, 1, 1}))
      assert {:over, scores} = Game.status(game)
      assert Enum.count(scores, fn {_, v} -> v > 0 end) <= 1
      assert Game.replay(game.opts, game.seed, game.log) == {:ok, game}
    end
  end

  # A game set by hand: the deck, the hands and the discard.
  defp table(hands, discard, deck, suit) do
    {:ok, game} = Game.new(%{spec: "crazy_eights", players: length(hands)}, {1, 2, 3})
    zones = Map.new(game.zones, fn {id, z} -> {id, %{z | items: []}} end)

    zones = %{
      zones
      | "discard" => %{zones["discard"] | items: discard},
        "deck" => %{zones["deck"] | items: deck}
    }

    zones =
      hands
      |> Enum.with_index()
      |> Enum.reduce(zones, fn {h, s}, zs -> put_in(zs["hand:#{s}"].items, h) end)

    %{
      game
      | zones: zones,
        counters: %{game.counters | "suit" => suit},
        turn: 0,
        phase: "play",
        pending: nil
    }
  end

  defp ask(game) do
    [ask] = Scripted.decide(Game.referee_view(game), :continue)
    {:ok, game} = Game.apply_ops(game, [ask])
    game
  end

  test "the prompt: cards of the suit or the rank, any 8, and draw" do
    game = table([~w(3H 9C 8S KD), ~w(2C)], ~w(9H), ~w(4S), "hearts") |> ask()

    assert Enum.sort(Game.legal_actions(game, 0)) ==
             Enum.sort([
               {:play, "hand:0", "3H"},
               {:play, "hand:0", "9C"},
               {:play, "hand:0", "8S"},
               {:choose, "draw"}
             ])
  end

  test "an 8 asks for a suit; the suit then holds for the next seat" do
    game = table([~w(8S KD), ~w(2C 5D)], ~w(9H), ~w(4S), "hearts") |> ask()
    {:ok, game} = Game.apply(game, 0, {:play, "hand:0", "8S"})
    assert game.phase == "choose_suit"
    assert {:choose, "diamonds"} in Game.legal_actions(game, 0)
    {:ok, game} = Game.apply(game, 0, {:choose, "diamonds"})
    assert game.counters["suit"] == "diamonds"
    assert Game.legal_actions(game, 1) == [{:play, "hand:1", "5D"}, {:choose, "draw"}]
  end

  test "draw from an empty deck turns the discard under its top card into the deck" do
    game = table([~w(2C), ~w(3C)], ~w(9H 7S 6D), [], "hearts") |> ask()
    {:ok, game} = Game.apply(game, 0, {:choose, "draw"})
    assert game.zones["discard"].items == ["9H"]
    assert length(game.zones["hand:0"].items) == 2
    assert length(game.zones["deck"].items) == 1
  end

  test "the last card wins: the others' cards score for the winner" do
    game = table([~w(5H), ~w(8C KD 2S)], ~w(9H), ~w(4S), "hearts") |> ask()
    {:ok, game} = Game.apply(game, 0, {:play, "hand:0", "5H"})
    assert Game.status(game) == {:over, %{0 => 50 + 10 + 2, 1 => 0}}
  end

  test "blocked: nobody can play or draw, the lowest hand wins" do
    game = table([~w(2C), ~w(KD)], ~w(9H), [], "hearts") |> ask()
    assert Game.legal_actions(game, 0) == [{:choose, "pass"}]
    {:ok, game} = Game.apply(game, 0, {:choose, "pass"})
    {:ok, game} = Game.apply(game, 1, {:choose, "pass"})
    assert Game.status(game) == {:over, %{0 => 10, 1 => 0}}
  end

  test "an 8 as the starter goes back into the deck" do
    {:ok, game} = Game.new(%{spec: "crazy_eights", players: 2, referee: nil}, {1, 2, 3})
    [top | _] = game.zones["discard"].items
    eight = Enum.find(game.zones["deck"].items, &match?({8, _}, Spec.standard(&1)))
    {:ok, game} = Game.apply_ops(game, [{:move, eight, "deck", "discard"}])
    game = %{game | referee: Scripted}
    ops = Scripted.decide(Game.referee_view(game), :continue)
    assert [{:move, ^eight, "discard", "deck"}, {:shuffle, "deck"} | _] = ops
    assert top != eight
  end
end
