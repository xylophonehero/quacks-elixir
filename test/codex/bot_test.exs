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
          view = game |> Game.view(seat) |> Map.put(:legal, Rules.legal(game))
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
end
