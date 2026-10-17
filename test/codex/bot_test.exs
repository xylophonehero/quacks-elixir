defmodule Codex.BotTest do
  @moduledoc "The Codex bot: legal actions only, whole games, and a room against it."
  use ExUnit.Case, async: true

  import Codex.TestHelpers, only: [assert_conserved: 1]

  alias Codex.{Bot, Game, Rules}

  defp bot_game(seed), do: elem(Game.new(%{bot: true}, seed), 1)

  # Both sides played by the bot, to the end (or `max` actions).
  defp play_out(game, max) do
    Enum.reduce_while(1..max, game, fn _, game ->
      case Game.status(game) do
        {:over, _} ->
          {:halt, game}

        {:playing, [seat]} ->
          view = Game.bot_view(game, seat)
          {action, _} = Bot.choose(view, nil)
          assert {:ok, game} = Game.apply(game, seat, action), "#{inspect(action)} was refused"
          {:cont, game}
      end
    end)
  end

  test "bot against bot: every action is legal, every card stays in one zone, games end" do
    games = for seed <- 1..8, do: play_out(bot_game({seed, 2, 3}), 3000)
    Enum.each(games, &assert_conserved/1)
    over = Enum.count(games, &(Game.status(&1) |> elem(0) == :over))
    assert over >= 6, "only #{over} of 8 games ended"
  end

  test "bot against bot, Red vs Green: legal actions, card conservation, all 10 games end" do
    games =
      for seed <- 1..10 do
        {:ok, game} = Game.new(%{bot: true, preset: "red_green"}, {seed, 2, 3})
        play_out(game, 4000)
      end

    Enum.each(games, &assert_conserved/1)
    assert Enum.all?(games, &(Game.status(&1) |> elem(0) == :over))
  end

  test "against the bot: two seats, each acts only on its own turn" do
    game = bot_game({1, 2, 3})
    assert Game.table_seats(game) == [0, 1]
    assert Game.status(game) == {:playing, [0]}
    assert Game.legal_actions(game, 1) == []
    assert Game.apply(game, 1, :end_turn) == {:error, :not_your_seat}
    {:ok, game} = Game.apply(game, 0, :end_turn)
    # P1's tech step, then the bot's turn.
    assert game.phase == :tech

    {:ok, game} =
      Game.apply(game, 0, Enum.find(Game.legal_actions(game, 0), &match?({:tech, _}, &1)))

    assert Game.status(game) == {:playing, [1]}
    assert Game.legal_actions(game, 0) == []
    assert Game.view(game, 1).legal == Rules.legal(game)
    # The bot has no free mode and no undo.
    assert Game.apply(game, 1, {:free_mode, true}) == {:error, :not_your_seat}
  end

  test "a room against the bot: the bot plays its turn and gives the turn back" do
    token = "bot-#{System.unique_integer()}"
    {:ok, code} = Table.Server.create("codex", %{opts: %{bot: true}, bots: 1, name: "Ann"}, token)
    [{pid, _}] = Registry.lookup(Table.Registry, {"codex", code})
    {:ok, env} = Table.Server.act("codex", code, token, :end_turn)
    tech = Enum.find(env.actions, &match?({:tech, _}, &1))
    {:ok, _} = Table.Server.act("codex", code, token, tech)

    game =
      Enum.reduce_while(1..500, nil, fn _, _ ->
        game = :sys.get_state(pid).game
        if game.active == 0, do: {:halt, game}, else: {:cont, game}
      end)

    assert game.active == 0
    assert game.sides[1].turn == 1
    assert Enum.any?(game.log, &match?({:action, 1, _}, &1))
  end

  describe "the fair view of a bot (Game.bot_view/2)" do
    # A bot game a few turns in: both sides have cards in hand, discard and workers.
    defp mid_game do
      Enum.reduce(1..55, bot_game({4, 5, 6}), fn _, game ->
        seat = game.active
        {action, _} = Bot.choose(Game.bot_view(game, seat), nil)
        {:ok, game} = Game.apply(game, seat, action)
        game
      end)
    end

    test "the other side's hand, discard pile, codex and workers are counts; decks too" do
      game = mid_game()
      view = Game.bot_view(game, 1)
      opp = game.sides[0].zones

      for zone <- [:hand, :discard, :codex, :workers] do
        assert view.sides[0].zones[zone] == length(opp[zone])
        for id <- opp[zone], do: refute(Map.has_key?(view.cards, id))
      end

      assert view.sides[1].zones.deck == length(game.sides[1].zones.deck)
      for id <- game.sides[1].zones.deck, do: refute(Map.has_key?(view.cards, id))
      # Its own hand, discard pile and codex stay.
      assert view.sides[1].zones.hand == game.sides[1].zones.hand
      assert view.sides[1].zones.codex == game.sides[1].zones.codex
      assert view.log == []
    end

    test "legal actions only on its own turn; view/2 gives the bot seat the fair view" do
      game = bot_game({1, 2, 3})
      assert Game.bot_view(game, 0).legal == Rules.legal(game)
      assert Game.bot_view(game, 1).legal == []
      assert Game.view(game, 1) == Game.bot_view(game, 1)
    end

    test "the person's view in a bot game and the hot-seat view still show both hands" do
      game = mid_game()
      view = Game.view(game, 0)
      assert view.sides[1].zones.hand == game.sides[1].zones.hand
      for id <- game.sides[1].zones.hand, do: assert(Map.has_key?(view.cards, id))
      hot = Game.view(%{game | bot: nil}, 0)
      assert hot.sides[1].zones.hand == game.sides[1].zones.hand
    end

    test "the bot's choice does not change when the hidden cards change" do
      game = mid_game()
      seat = game.active
      opp = 1 - seat
      zones = game.sides[opp].zones
      # Swap the other side's hand with the top of its deck (same counts).
      n = min(length(zones.hand), length(zones.deck))
      {top, rest} = Enum.split(zones.deck, n)
      {hand_out, hand_keep} = Enum.split(zones.hand, n)
      zones = %{zones | hand: top ++ hand_keep, deck: hand_out ++ rest}
      other = put_in(game.sides[opp].zones, zones)
      assert n > 0
      assert Game.bot_view(game, seat) == Game.bot_view(other, seat)

      assert Bot.choose(Game.bot_view(game, seat), nil) ==
               Bot.choose(Game.bot_view(other, seat), nil)
    end
  end
end
