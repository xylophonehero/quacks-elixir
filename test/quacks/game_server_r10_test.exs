defmodule Quacks.GameServerR10Test do
  @moduledoc """
  Round 10 (handoff quacks-r10-engine): bot decisions in the concurrent phases are
  revealed together with the humans' (item 4), and the server answers a human's
  Mandrake choice with `:return_white`, which the player may take back (item 5).

  The checks read only what a page sees: the game's log and the broadcasts
  (architecture review G6), not the server's state, so they hold through #81.
  """
  use ExUnit.Case, async: true

  import Quacks.GameHelpers,
    only: [assert_game_update: 1, await_game: 2, refute_game_update: 0, replace_game: 2, put: 3]

  alias Quacks.{Game, GameServer, Session}

  # 1 human (seat 0) and 1 bot (seat 1), begun.
  defp human_and_bot(seed, rules \\ %{fortune: false}) do
    {:ok, id} = GameServer.start(2, seed)
    {:ok, 0} = GameServer.claim_seat(id, "human-#{inspect(seed)}")
    {:ok, 1} = GameServer.add_bot(id, "human-#{inspect(seed)}")
    {:ok, _table} = GameServer.configure(id, "human-#{inspect(seed)}", %{rules: rules})
    {:ok, _game} = GameServer.begin(id, "human-#{inspect(seed)}")
    id
  end

  defp subscribe(id), do: :ok = Phoenix.PubSub.subscribe(Quacks.PubSub, GameServer.topic(id))

  defp bot_entries(game, pred),
    do: Enum.filter(game.log, &(match?({1, _}, &1) and pred.(&1)))

  defp bot_buys(game), do: for({1, {:buy, chips}} <- game.log, do: chips)

  # The human draws one chip and stops; the bot brews to its end: the shop opens.
  defp to_shop(id) do
    {:ok, _} = GameServer.apply(id, 0, :draw)
    {:ok, _} = GameServer.apply(id, 0, :stop)
    await_game(id, &(&1.phase == :shopping))
  end

  describe "bot decisions revealed together" do
    test "in the shop the bot's plan waits for the human, then shows at once" do
      id = human_and_bot({4, 5, 6})
      game = to_shop(id)
      subscribe(id)

      # the bot does nothing the pages can see while the human shops
      assert bot_entries(game, &match?({1, {:buy, _}}, &1)) == []
      refute_game_update()

      {:ok, game} = GameServer.apply(id, 0, {:buy, []})
      assert bot_entries(game, &match?({1, {:buy, _}}, &1)) == []
      assert Game.phase(game, 1) == :shop

      # the human's last shop action reveals the bot's whole plan: the round ends
      {:ok, game} = GameServer.apply(id, 0, :end_round)
      assert game.round == 2
      round1 = Enum.drop_while(game.log, &(&1 != {:round_end, 1}))
      [bot_buy] = for {1, {:buy, _} = buy} <- round1, do: buy
      # it came after the human's choices
      assert Enum.find_index(round1, &(&1 == {1, bot_buy})) <
               Enum.find_index(round1, &(&1 == {0, :end_round}))
    end

    test "a bot's fortune choice is not in the log until the human chose" do
      seed = Enum.find(1..500, fn i -> fortune_choice_for_both?({i, i, i}) end)
      id = human_and_bot({seed, seed, seed}, %{})
      subscribe(id)
      {:ok, %{game: game}} = GameServer.get(id)
      assert game.phase == :fortune_choice
      assert bot_entries(game, &match?({1, {:fortune, _}}, &1)) == []
      # the bot has decided, but no page sees it yet
      refute_game_update()

      [choice | _] = Game.legal_actions(game, 0)
      {:ok, game} = GameServer.apply(id, 0, choice)
      assert [_] = bot_entries(game, &match?({1, {:fortune, _}}, &1))
      assert game.phase == :potions
    end

    test "with no human in the phase the bot acts at once" do
      # A debug table in the shop: the human is done (`:ready`), the bot (frozen)
      # has not shopped yet.
      session = shop_session({4, 5, 6})
      assert Game.phase(session.game, 0) == :ready and Game.phase(session.game, 1) == :shop

      bundle = session |> Session.bundle() |> Map.put(:bots, [1])
      {:ok, id} = GameServer.start_from_bundle(bundle, token: "human", seat: 0)
      assert {:ok, %{game: %Game{round: 1}}} = GameServer.get(id)

      # unfrozen, the bot shops by itself and the round ends
      :ok = GameServer.set_frozen(id, false)
      game = await_game(id, &(&1.round == 2))
      assert [_] = bot_entries(game, &match?({1, :end_round}, &1))
    end

    test "a queued plan that a limited supply makes illegal is dropped; the bot decides again" do
      # The shop has one orange chip left. Without the human's buy the bot buys it.
      control = limited_orange_game({4, 5, 6})
      {:ok, _} = GameServer.apply(control, 0, {:buy, []})
      {:ok, game} = GameServer.apply(control, 0, :end_round)
      assert game.round == 2
      assert [{:orange, 1}] in bot_buys(game)

      # The human buys the last orange chip first: the bot's plan is no longer legal
      # when the human's last shop action applies it; the round waits for the bot.
      id = limited_orange_game({4, 5, 6})
      {:ok, _} = GameServer.apply(id, 0, {:buy, [{:orange, 1}]})
      {:ok, game} = GameServer.apply(id, 0, :end_round)
      refute [{:orange, 1}] in bot_buys(game)
      assert game.round == 1 and Game.phase(game, 1) == :shop

      # the bot decides again (ticks) and the round ends
      game = await_game(id, &(&1.round == 2))
      refute [{:orange, 1}] in bot_buys(game)
      assert [_] = bot_entries(game, &match?({1, :end_round}, &1))
    end
  end

  # A human and a bot in the shop of round 1 with a limited supply of one orange
  # chip (nothing else) and coins for the human.
  defp limited_orange_game(seed) do
    id = human_and_bot(seed, %{fortune: false, supply: :limited})

    replace_game(id, fn g ->
      %{
        g
        | supply: g.supply |> Map.new(fn {chip, _} -> {chip, 0} end) |> Map.put({:orange, 1}, 1)
      }
    end)

    to_shop(id)
    replace_game(id, &put(&1, 0, coins: 10))
    id
  end

  # Both seats play the first legal action (stop when they can) until the shop of
  # round 1; then seat 0 ends its shop.
  defp shop_session(seed) do
    session =
      Stream.iterate(Session.new(seed, 2, rules: %{fortune: false}), fn s ->
        {seat, actions} = Enum.find_value(s.game.seats, &acting(s.game, &1))
        action = if :stop in actions, do: :stop, else: hd(actions)
        {:ok, s} = Session.apply(s, seat, action)
        s
      end)
      |> Enum.find(&(&1.game.phase == :shopping))

    {:ok, session} = Session.apply(session, 0, {:buy, []})
    {:ok, session} = Session.apply(session, 0, :end_round)
    session
  end

  defp acting(game, seat) do
    case Game.legal_actions(game, seat) -- [:resume] do
      [] -> nil
      actions -> {seat, actions}
    end
  end

  # Round 1's card asks both seats a choice.
  defp fortune_choice_for_both?(seed) do
    game = Game.new(seed: seed, players: 2)
    game.phase == :fortune_choice and Enum.all?([0, 1], &(Game.legal_actions(game, &1) != []))
  end

  describe "Mandrake for humans" do
    # The human's next draw is a yellow 1 right after a white 1.
    defp mandrake(id) do
      replace_game(id, &put(&1, 0, drawn: [{{:white, 1}, 1}], pot_index: 1, bag: [{:yellow, 1}]))
      subscribe(id)
      GameServer.apply(id, 0, :draw)
    end

    test "the server puts the white chip back; keep_white takes that back once" do
      id = human_and_bot({4, 5, 6})
      {:ok, game} = mandrake(id)

      assert Game.phase(game, 0) == :potions
      assert [{0, {:returned, {:white, 1}}}, {0, :return_white} | _] = game.log
      assert {:white, 1} in game.players[0].bag
      # bots wait while the answer can be taken back
      assert assert_game_update(id) == game
      refute_game_update()

      {:ok, game} = GameServer.keep_white(id, 0)
      assert [{0, :keep} | _] = game.log
      assert Game.pot_chips(game, 0) == [{:yellow, 1}, {:white, 1}]
      refute {:white, 1} in game.players[0].bag
      assert GameServer.keep_white(id, 0) == {:error, :too_late}
    end

    test "after the next action it is too late" do
      id = human_and_bot({4, 5, 6})
      {:ok, _game} = mandrake(id)
      {:ok, _game} = GameServer.apply(id, 0, :stop)
      assert GameServer.keep_white(id, 0) == {:error, :too_late}
    end
  end
end
