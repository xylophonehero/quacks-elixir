defmodule Table.Generic.GameTest do
  use ExUnit.Case, async: true

  alias Table.Generic.{Game, Spec}

  doctest Game
  doctest Spec

  defp bare(spec, players) do
    {:ok, game} = Game.new(%{spec: spec, players: players, referee: nil}, {1, 2, 3})
    game
  end

  describe "specs" do
    test "Crazy Eights: 7 cards each with 2 players, 5 with more, one card on the discard" do
      for {players, n} <- [{2, 7}, {3, 5}, {5, 5}] do
        game = bare("crazy_eights", players)

        assert for(s <- game.seats, do: length(game.zones["hand:#{s}"].items)) ==
                 List.duplicate(n, players)

        assert length(game.zones["discard"].items) == 1
        assert length(game.zones["deck"].items) == 52 - n * players - 1
        assert game.counters == %{"suit" => "", "passes" => 0}
      end
    end

    test "Go Fish: 7 cards each with 2 or 3 players, 5 with more; books per seat" do
      for {players, n} <- [{2, 7}, {3, 7}, {4, 5}, {6, 5}] do
        game = bare("go_fish", players)
        assert length(game.zones["hand:0"].items) == n
        assert game.zones["books:1"] == %Table.Kit.Zone{items: [], owner: 1, visibility: :public}
        assert game.counters["books:#{players - 1}"] == 0
        assert length(Game.all_cards(game)) == 52
      end
    end

    test "a bad spec or player count is an error" do
      assert Game.new(%{spec: "chess"}, {1, 2, 3}) == {:error, {:unknown_spec, "chess"}}
      assert Game.new(%{spec: "crazy_eights", players: 9}, {1, 2, 3}) == {:error, :bad_players}
      bad = Map.put(Spec.fixture("go_fish"), "zones", [%{"id" => "x", "visibility" => "owner"}])
      assert Game.new(%{spec: bad}, {1, 2, 3}) == {:error, :bad_zones}
    end

    test "a custom deck: ids and names" do
      spec = %{
        "name" => "fruit",
        "players" => %{"min" => 2, "max" => 2},
        "deck" => [%{"id" => "a", "name" => "Apple"}, "b", "QS"],
        "zones" => [%{"id" => "pile", "deck" => true, "layout" => "pile"}]
      }

      game = bare(spec, 2)
      assert game.zones["pile"].items == ["a", "b", "QS"]
      assert Game.view(game, 0).names == %{"a" => "Apple", "b" => "b", "QS" => "Q♠"}
    end
  end

  describe "ops" do
    test "an invalid op is an error and nothing changes, also in the middle of a list" do
      game = bare("crazy_eights", 2)
      [top | _] = game.zones["deck"].items

      bad = [
        {:move, "XX", "deck", "discard"},
        {:move, top, "deck", "deck"},
        {:move, {:top, 99}, "deck", "discard"},
        {:move, :all, "nowhere", "deck"},
        {:deal, 30, "deck", ["hand:0", "hand:1"]},
        {:flip, "deck", :owner},
        {:set, "nope", 1},
        {:add, "suit", 1},
        {:turn, 7},
        {:ask, 0, "?", []},
        {:ask, 0, "?", [{:card, "hand:1", hd(game.zones["hand:1"].items)}]},
        {:ask, 0, "?", [{:card, "deck", top}]},
        {:end, %{0 => 1}}
      ]

      for op <- bad do
        assert {:error, {1, ^op, _reason}} = Game.apply_ops(game, [{:shuffle, "deck"}, op])
      end
    end

    test "move takes from the top and puts on top, in order" do
      game = bare("crazy_eights", 2)
      [a, b | _] = game.zones["deck"].items
      [d] = game.zones["discard"].items
      {:ok, game} = Game.apply_ops(game, [{:move, {:top, 2}, "deck", "discard"}])
      assert game.zones["discard"].items == [a, b, d]
    end

    test "deal goes one card at a time; hand:* is every hand" do
      game = bare("go_fish", 3)
      [a, b, c, d, e, f | _] = game.zones["ocean"].items
      {:ok, game} = Game.apply_ops(game, [{:deal, 2, "ocean", ["books:*"]}])
      assert game.zones["books:0"].items == [d, a]
      assert game.zones["books:1"].items == [e, b]
      assert game.zones["books:2"].items == [f, c]
    end

    test "end closes the game: no more ops or actions" do
      game = bare("crazy_eights", 2)
      {:ok, game} = Game.apply_ops(game, [{:end, %{0 => 3, 1 => 0}}])
      assert Game.status(game) == {:over, %{0 => 3, 1 => 0}}
      assert Game.apply_ops(game, [{:turn, 0}]) == {:error, {0, {:turn, 0}, :game_over}}
    end

    test "JSON ops apply with the same checks" do
      game = bare("crazy_eights", 2)
      json = [%{"op" => "move", "top" => 1, "from" => "deck", "to" => "hand:0"}]
      {:ok, moved} = Game.apply_json(game, json)
      assert length(moved.zones["hand:0"].items) == 8

      assert {:error, {0, _, {:unknown_zone, "hand:9"}}} =
               Game.apply_json(game, [%{"op" => "shuffle", "zone" => "hand:9"}])
    end
  end

  describe "actions and views" do
    setup do
      {:ok, game} = Game.new(%{spec: "crazy_eights", players: 3}, {4, 5, 6})
      %{game: game}
    end

    test "only the prompt's seat can act, and only with its options", %{game: game} do
      assert {:playing, [0]} = Game.status(game)
      assert Game.legal_actions(game, 1) == []
      assert Game.apply(game, 1, {:choose, "draw"}) == {:error, :illegal_action}
      assert Game.apply(game, 0, {:choose, "fly"}) == {:error, :illegal_action}
      assert {:ok, drew} = Game.apply(game, 0, {:choose, "draw"})
      assert length(drew.zones["hand:0"].items) == 6
    end

    test "a view hides the other hands, the deck, and their cards in the log", %{game: game} do
      {:ok, game} = Game.apply(game, 0, {:choose, "draw"})
      v = Game.view(game, 1)
      assert Enum.all?(v.zones["hand:0"].items, &(&1 == :hidden))
      assert Enum.all?(v.zones["deck"].items, &(&1 == :hidden))
      assert v.zones["hand:1"].items == game.zones["hand:1"].items
      assert v.legal_actions == []
      assert Enum.all?(v.pending.options, &(is_binary(&1) or match?({:card, _, :hidden}, &1)))

      [drawn | _] = game.zones["hand:0"].items
      refute inspect(v.log) =~ ~s("#{drawn}")
      assert inspect(Game.view(game, 0).log) =~ ~s("#{drawn}")
    end

    test "a referee that leaves no prompt makes the action fail", %{game: game} do
      defmodule Quiet do
        @behaviour Table.Generic.Referee
        def decide(_view, _event), do: []
      end

      assert Game.apply(%{game | referee: Quiet}, 0, {:choose, "draw"}) == {:error, :stalled}
    end

    test "replay of the log gives the same state", %{game: game} do
      {:ok, game} = Game.apply(game, 0, {:choose, "draw"})
      assert Game.replay(game.opts, game.seed, game.log) == {:ok, game}
    end
  end
end
