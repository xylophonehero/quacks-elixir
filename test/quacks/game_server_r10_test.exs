defmodule Quacks.GameServerR10Test do
  @moduledoc """
  Round 10 (handoff quacks-r10-engine): bot decisions in the concurrent phases are
  revealed together with the humans' (item 4), and the server answers a human's
  Mandrake choice with `:return_white`, which the player may take back (item 5).
  """
  use ExUnit.Case, async: true

  alias Quacks.{Game, GameServer}

  # 1 human (seat 0) and 1 bot (seat 1), begun.
  defp human_and_bot(seed, rules \\ %{fortune: false}) do
    {:ok, id} = GameServer.start(2, seed)
    {:ok, 0} = GameServer.claim_seat(id, "human-#{inspect(seed)}")
    {:ok, 1} = GameServer.add_bot(id, "human-#{inspect(seed)}")
    {:ok, _table} = GameServer.configure(id, "human-#{inspect(seed)}", %{rules: rules})
    {:ok, _game} = GameServer.begin(id, "human-#{inspect(seed)}")
    [{pid, _}] = Registry.lookup(Quacks.GameRegistry, id)
    {id, pid}
  end

  defp run_ticks(pid, n \\ 300) do
    state = :sys.get_state(pid)

    if state.bot_ticks == %{} or n == 0 do
      state.session.game
    else
      Enum.each(state.bot_ticks, fn {seat, tick} -> send(pid, {:bot, seat, tick}) end)
      run_ticks(pid, n - 1)
    end
  end

  defp bot_entries(game, pred),
    do: Enum.filter(game.log, &(match?({1, _}, &1) and pred.(&1)))

  # The human draws one chip and stops; the bot brews to its end: the shop opens.
  defp to_shop(id, pid) do
    {:ok, _} = GameServer.apply(id, 0, :draw)
    {:ok, _} = GameServer.apply(id, 0, :stop)
    game = run_ticks(pid)
    assert game.phase == :shopping
    game
  end

  describe "bot decisions revealed together" do
    test "in the shop the bot's plan waits for the human, then shows at once" do
      {id, pid} = human_and_bot({4, 5, 6})
      game = to_shop(id, pid)

      state = :sys.get_state(pid)
      assert [_ | _] = state.queued[1]
      assert state.bot_ticks == %{}
      assert bot_entries(game, &match?({1, {:buy, _}}, &1)) == []

      {:ok, _} = GameServer.apply(id, 0, {:buy, []})
      assert bot_entries(run_ticks(pid), &match?({1, {:buy, _}}, &1)) == []

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
      {id, pid} = human_and_bot({seed, seed, seed}, %{})
      game = run_ticks(pid)
      assert game.phase == :fortune_choice
      assert bot_entries(game, &match?({1, {:fortune, _}}, &1)) == []
      assert [_] = :sys.get_state(pid).queued[1]

      [choice | _] = Game.legal_actions(game, 0)
      {:ok, game} = GameServer.apply(id, 0, choice)
      assert [_] = bot_entries(game, &match?({1, {:fortune, _}}, &1))
      assert game.phase == :potions
    end

    test "with no human in the phase the bot acts at once" do
      {id, pid} = human_and_bot({4, 5, 6})
      to_shop(id, pid)

      # the human is done shopping; the bot has no plan and a tick
      :sys.replace_state(pid, fn st ->
        st = put_in(st.session.game.players[0].phase, :ready)
        %{st | queued: %{}, bot_ticks: %{1 => 999}}
      end)

      send(pid, {:bot, 1, 999})
      game = :sys.get_state(pid).session.game
      assert [_] = bot_entries(game, &match?({1, {:buy, _}}, &1))
    end

    test "a queued action that is no longer legal is dropped; the bot decides again" do
      {id, pid} = human_and_bot({4, 5, 6})
      to_shop(id, pid)
      :sys.replace_state(pid, &%{&1 | queued: %{1 => [{:buy, [{:green, 99}]}, :end_round]}})

      {:ok, game} = GameServer.apply(id, 0, {:buy, []})
      {:ok, game} = if game.round == 1, do: GameServer.apply(id, 0, :end_round), else: {:ok, game}
      assert game.round == 1 and Game.phase(game, 1) == :shop
      refute {1, {:buy, [{:green, 99}]}} in game.log

      assert run_ticks(pid).round == 2
    end
  end

  # Round 1's card asks both seats a choice.
  defp fortune_choice_for_both?(seed) do
    game = Game.new(seed: seed, players: 2)
    game.phase == :fortune_choice and Enum.all?([0, 1], &(Game.legal_actions(game, &1) != []))
  end

  describe "Mandrake for humans" do
    # The human's next draw is a yellow 1 right after a white 1.
    defp mandrake(id, pid) do
      :sys.replace_state(pid, fn st ->
        update_in(
          st.session.game.players[0],
          &%{&1 | drawn: [{{:white, 1}, 1}], pot_index: 1, bag: [{:yellow, 1}]}
        )
      end)

      GameServer.apply(id, 0, :draw)
    end

    test "the server puts the white chip back; keep_white takes that back once" do
      {id, pid} = human_and_bot({4, 5, 6})
      {:ok, game} = mandrake(id, pid)

      assert Game.phase(game, 0) == :potions
      assert [{0, {:returned, {:white, 1}}}, {0, :return_white} | _] = game.log
      assert {:white, 1} in game.players[0].bag
      # bots wait while the answer can be taken back
      assert :sys.get_state(pid).bot_ticks == %{}

      {:ok, game} = GameServer.keep_white(id, 0)
      assert [{0, :keep} | _] = game.log
      assert Game.pot_chips(game, 0) == [{:yellow, 1}, {:white, 1}]
      refute {:white, 1} in game.players[0].bag
      assert GameServer.keep_white(id, 0) == {:error, :too_late}
    end

    test "after the next action it is too late" do
      {id, pid} = human_and_bot({4, 5, 6})
      {:ok, _game} = mandrake(id, pid)
      {:ok, _game} = GameServer.apply(id, 0, :stop)
      assert GameServer.keep_white(id, 0) == {:error, :too_late}
    end
  end
end
