defmodule Quacks.GameServerTest do
  use ExUnit.Case, async: true

  alias Quacks.{AI, Game, GameServer}

  # A process that subscribes to the game and forwards everything to the test.
  defp listener(id) do
    test = self()

    pid =
      spawn_link(fn ->
        Phoenix.PubSub.subscribe(Quacks.PubSub, GameServer.topic(id))
        send(test, {:subscribed, self()})
        forward(test)
      end)

    assert_receive {:subscribed, ^pid}
    pid
  end

  defp forward(test) do
    receive do
      msg -> send(test, {:forwarded, self(), msg}) && forward(test)
    end
  end

  # Open a game for `players`, seat `tokens` and begin it with the first one.
  defp begun(players, tokens, seed \\ {1, 2, 3}) do
    {:ok, id} = GameServer.start(players, seed)
    for token <- tokens, do: {:ok, _} = GameServer.claim_seat(id, token)
    if players > 1, do: {:ok, _game} = GameServer.begin(id, hd(tokens))
    id
  end

  test "start gives a 6-letter id and a waiting table without a game" do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    assert id =~ ~r/^[a-z]{6}$/
    {:ok, table} = GameServer.get(id)
    assert {table.status, table.game, table.players, table.max_players} == {:waiting, nil, 2, 2}
    assert table.seed == {1, 2, 3}
    assert table.names == %{} and table.creator == nil
    assert GameServer.apply(id, 0, :draw) == {:error, :not_started}
    assert GameServer.undo(id) == {:error, :not_started}
  end

  test "begin with fewer players than the maximum; then no new seats" do
    {:ok, id} = GameServer.start(4, {1, 2, 3})
    {:ok, 0} = GameServer.claim_seat(id, "a")
    {:ok, 1} = GameServer.claim_seat(id, "b")
    {:ok, %{creator: 0}} = GameServer.get(id)

    assert {:ok, game} = GameServer.begin(id, "a")
    assert game == Game.new(seed: {1, 2, 3}, players: 2)
    {:ok, table} = GameServer.get(id)
    assert {table.status, table.players, table.max_players} == {:playing, 2, 4}
    assert GameServer.claim_seat(id, "c") == {:error, :full}
    assert GameServer.claim_seat(id, "b") == {:ok, 1}
    assert GameServer.begin(id, "a") == {:error, :already_started}
    assert {:ok, _} = GameServer.apply(id, 1, :draw)
  end

  test "only the creator may begin, unless the creator left" do
    {:ok, id} = GameServer.start(3)
    {:ok, 0} = GameServer.claim_seat(id, "a")
    {:ok, 1} = GameServer.claim_seat(id, "b")
    assert GameServer.begin(id, "b") == {:error, :not_creator}
    assert GameServer.begin(id, "nobody") == {:error, :not_seated}

    :ok = GameServer.leave_seat(id, "a")
    assert {:ok, %{creator: nil}} = GameServer.get(id)
    assert {:ok, game} = GameServer.begin(id, "b")
    assert game.seats == [0]
  end

  test "leave_seat frees a seat while waiting; begin renumbers the seats" do
    {:ok, id} = GameServer.start(3)
    one = listener(id)
    {:ok, 0} = GameServer.claim_seat(id, "a")
    {:ok, 1} = GameServer.claim_seat(id, "b")
    {:ok, 2} = GameServer.claim_seat(id, "c")
    :ok = GameServer.rename(id, 2, "Cleo")

    :ok = GameServer.leave_seat(id, "b")
    assert_receive {:forwarded, ^one, {:names, ^id, %{0 => "Player 1", 2 => "Cleo"}}}
    assert [_] = Enum.filter(GameServer.open_games(), &(&1.id == id))

    # the free seat goes to the next browser
    {:ok, 1} = GameServer.claim_seat(id, "d")
    :ok = GameServer.leave_seat(id, "d")

    {:ok, game} = GameServer.begin(id, "a")
    assert game.seats == [0, 1]
    assert GameServer.claim_seat(id, "c") == {:ok, 1}
    assert {:ok, %{names: %{0 => "Player 1", 1 => "Cleo"}}} = GameServer.get(id)
    assert_receive {:forwarded, ^one, {:game, ^id, ^game}}

    # once playing, leaving changes nothing
    :ok = GameServer.leave_seat(id, "c")
    assert GameServer.claim_seat(id, "c") == {:ok, 1}
  end

  test "an unknown id is :not_found" do
    assert GameServer.get("nosuch") == {:error, :not_found}
    assert GameServer.apply("nosuch", 0, :draw) == {:error, :not_found}
  end

  test "seats fill in join order; a known token keeps its seat; then the game is full" do
    {:ok, id} = GameServer.start(2)
    assert GameServer.claim_seat(id, "a") == {:ok, 0}
    assert GameServer.claim_seat(id, "b") == {:ok, 1}
    assert GameServer.claim_seat(id, "a") == {:ok, 0}
    assert GameServer.claim_seat(id, "c") == {:error, :full}
    assert {:ok, %{names: %{0 => "Player 1", 1 => "Player 2"}}} = GameServer.get(id)
  end

  test "apply broadcasts the new game to every subscriber" do
    id = begun(2, ["a", "b"])
    one = listener(id)
    two = listener(id)

    assert {:ok, game} = GameServer.apply(id, 1, :draw)
    assert length(game.players[1].drawn) == 1
    assert_receive {:forwarded, ^one, {:game, ^id, ^game}}
    assert_receive {:forwarded, ^two, {:game, ^id, ^game}}

    assert {:error, {:illegal_action, :end_round, :potions}} =
             GameServer.apply(id, 0, :end_round)

    refute_receive {:forwarded, _, {:game, _, _}}
  end

  test "claiming a seat and renaming broadcast the names" do
    {:ok, id} = GameServer.start(2)
    one = listener(id)
    {:ok, 0} = GameServer.claim_seat(id, "a")
    assert_receive {:forwarded, ^one, {:names, ^id, %{0 => "Player 1"}}}

    :ok = GameServer.rename(id, 0, "  Nick  ")
    assert_receive {:forwarded, ^one, {:names, ^id, %{0 => "Nick"}}}

    :ok = GameServer.rename(id, 0, "   ")
    assert_receive {:forwarded, ^one, {:names, ^id, %{0 => "Player 1"}}}
  end

  test "undo works in solo only" do
    solo = begun(1, ["a"])
    {:ok, _} = GameServer.apply(solo, 0, :draw)
    assert {:ok, game} = GameServer.undo(solo)
    assert game == Game.new(seed: {1, 2, 3}, players: 1)

    duo = begun(2, ["a", "b"])
    {:ok, _} = GameServer.apply(duo, 0, :draw)
    assert GameServer.undo(duo) == {:error, :not_solo}
  end

  test "open games are the waiting ones with a free seat" do
    {:ok, open} = GameServer.start(2)
    {:ok, full} = GameServer.start(1)
    {:ok, 0} = GameServer.claim_seat(full, "a")
    playing = begun(2, ["a"])

    ids = Enum.map(GameServer.open_games(), & &1.id)
    assert open in ids
    refute full in ids
    refute playing in ids
  end

  # A plain table: draw while the white sum is 4 or less, then stop; buy nothing; in
  # round 9 trade rubies for VP; skip every other choice.
  defp pick(actions, white) do
    cond do
      :draw in actions and white <= 4 -> :draw
      :stop in actions -> :stop
      {:rubies, :vp} in actions -> {:rubies, :vp}
      :end_round in actions -> :end_round
      :chip_done in actions -> :chip_done
      :witch_done in actions -> :witch_done
      true -> hd(actions)
    end
  end

  # Play the game through `GameServer` and `legal_actions` until it is over: the
  # lowest seat with something to do acts (never `:resume`). Returns the last game and
  # every player phase seen in round 9.
  defp play_to_end(id, seen \\ MapSet.new()) do
    {:ok, %{game: g}} = GameServer.get(id)

    if Game.over?(g) do
      {g, seen}
    else
      seen = if g.round == 9, do: round9_checks(g, seen), else: seen

      {seat, actions} =
        g.seats
        |> Enum.map(&{&1, Game.legal_actions(g, &1) -- [:resume]})
        |> Enum.find(fn {_seat, actions} -> actions != [] end)

      {:ok, _} = GameServer.apply(id, seat, pick(actions, Game.white_sum(g, seat)))
      play_to_end(id, seen)
    end
  end

  # Round 9: nobody buys or resumes; a seat that picked for the stir waits.
  defp round9_checks(g, seen) do
    for seat <- g.seats do
      actions = Game.legal_actions(g, seat)
      refute Enum.any?(actions, &match?({:buy, _}, &1))
      refute :resume in actions
      if Game.phase(g, seat) == :waiting_stir, do: assert(actions == [])
    end

    Enum.reduce(g.seats, seen, &MapSet.put(&2, Game.phase(g, &1)))
  end

  test "round 9 end to end for 2 players: stir, no shop, conversion, game over" do
    id = begun(2, ["a", "b"])
    {game, seen} = play_to_end(id)

    assert :waiting_stir in seen and :shop in seen
    assert hd(game.log) == {:round_end, 9}
    assert Enum.count(game.log, &match?({0, {:final_conversion, _, _, _, _}}, &1)) == 1
    assert Enum.count(game.log, &match?({1, {:final_conversion, _, _, _, _}}, &1)) == 1
    assert GameServer.apply(id, 0, :draw) |> elem(0) == :error
  end

  test "the host configures a waiting game; bad settings are refused" do
    {:ok, id} = GameServer.start(2)
    one = listener(id)
    {:ok, 0} = GameServer.claim_seat(id, "a")
    {:ok, 1} = GameServer.claim_seat(id, "b")
    assert GameServer.configure(id, "b", %{players: 3}) == {:error, :not_creator}

    assert {:ok, table} =
             GameServer.configure(id, "a", %{
               players: 3,
               sets: %{black: 5},
               rules: %{overflow: false}
             })

    assert {table.max_players, table.sets, table.rules} == {3, %{black: 5}, %{overflow: false}}
    assert_receive {:forwarded, ^one, {:names, ^id, %{1 => "Player 2"}}}

    # fewer seats than taken, more than 8, a set that does not exist
    assert GameServer.configure(id, "a", %{players: 1}) == {:error, :invalid}
    assert GameServer.configure(id, "a", %{players: 9}) == {:error, :invalid}
    assert GameServer.configure(id, "a", %{sets: %{blue: 9}}) == {:error, :invalid}

    assert {:ok, %{max_players: 5, expansion: :herb_witches}} =
             GameServer.configure(id, "a", %{players: 5, expansion: :herb_witches})

    {:ok, game} = GameServer.begin(id, "a")
    assert {game.sets.black, game.rules.overflow, game.expansion} == {5, false, :herb_witches}
    assert GameServer.configure(id, "a", %{players: 2}) == {:error, :already_started}
  end

  test "play again: a new waiting game with the same settings, seats and names" do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{black: 5}, %{overflow: false})
    {:ok, 0} = GameServer.claim_seat(id, "a")
    {:ok, 1} = GameServer.claim_seat(id, "b")
    :ok = GameServer.rename(id, 1, "Bea")
    {:ok, _} = GameServer.begin(id, "a")
    assert GameServer.play_again(id, "a") == {:error, :not_over}

    play_to_end(id)
    one = listener(id)
    assert GameServer.play_again(id, "zed") == {:error, :not_seated}
    {:ok, new_id} = GameServer.play_again(id, "b")
    assert new_id != id
    assert_receive {:forwarded, ^one, {:play_again, ^id, ^new_id}}
    # asking again gives the same game
    assert GameServer.play_again(id, "a") == {:ok, new_id}

    {:ok, table} = GameServer.get(new_id)
    assert {table.status, table.max_players, table.creator} == {:waiting, 2, 0}

    assert {table.sets, table.rules, table.names} ==
             {%{black: 5}, %{overflow: false}, %{0 => "Player 1", 1 => "Bea"}}

    assert GameServer.claim_seat(new_id, "b") == {:ok, 1}
    assert {:ok, %Game{round: 1}} = GameServer.begin(new_id, "a")
  end

  test "play again solo begins at once" do
    id = begun(1, ["a"])
    play_to_end(id)
    {:ok, new_id} = GameServer.play_again(id, "a")
    assert {:ok, %{status: :playing, game: %Game{round: 1}}} = GameServer.get(new_id)
  end

  test "an idle game stops on the timeout" do
    {:ok, id} = GameServer.start(1)
    [{pid, _}] = Registry.lookup(Quacks.GameRegistry, id)
    ref = Process.monitor(pid)
    send(pid, :timeout)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert GameServer.get(id) == {:error, :not_found}
  end

  describe "bots" do
    test "the host adds and removes bots while waiting" do
      {:ok, id} = GameServer.start(4, {1, 2, 3})
      {:ok, 0} = GameServer.claim_seat(id, "a")

      assert GameServer.add_bot(id, "a") == {:ok, 1}
      assert GameServer.add_bot(id, "a") == {:ok, 2}
      {:ok, table} = GameServer.get(id)
      assert table.bots == %{1 => :balanced, 2 => :balanced}
      assert {table.names[1], table.names[2]} == {"Steady Sam", "Steady Sam 2"}
      assert table.colours == %{0 => 0, 1 => 1, 2 => 2}

      assert GameServer.remove_bot(id, "a", 1) == :ok
      assert GameServer.remove_bot(id, "a", 0) == {:error, :not_a_bot}
      {:ok, table} = GameServer.get(id)
      assert table.bots == %{2 => :balanced}
      refute Map.has_key?(table.names, 1)

      # names stay unique: the free "Steady Sam" comes first again
      assert GameServer.add_bot(id, "a") == {:ok, 1}
      {:ok, table} = GameServer.get(id)
      assert table.names[1] == "Steady Sam"
      :ok = GameServer.remove_bot(id, "a", 1)

      # a browser takes the lowest free seat, around the bot
      assert GameServer.claim_seat(id, "b") == {:ok, 1}
      assert GameServer.add_bot(id, "a", 1) == {:error, :full}
      assert GameServer.add_bot(id, "a", 3) == {:ok, 3}
      assert GameServer.add_bot(id, "a") == {:error, :full}
      assert GameServer.configure(id, "a", %{players: 3}) == {:error, :invalid}
    end

    test "only the host, only while waiting, at most 7 bots" do
      {:ok, id} = GameServer.start(8, {1, 2, 3})
      {:ok, 0} = GameServer.claim_seat(id, "a")
      {:ok, 1} = GameServer.claim_seat(id, "b")

      assert GameServer.add_bot(id, "b") == {:error, :not_creator}
      {:ok, 2} = GameServer.add_bot(id, "a")
      assert GameServer.remove_bot(id, "b", 2) == {:error, :not_creator}

      :ok = GameServer.leave_seat(id, "b")

      for seat <- [1, 3, 4, 5, 6, 7],
          do: assert(GameServer.add_bot(id, "a") == {:ok, seat})

      # the host leaves: a free seat, but 7 bots is the limit
      :ok = GameServer.leave_seat(id, "a")
      assert GameServer.add_bot(id, "a") == {:error, :too_many_bots}

      {:ok, 0} = GameServer.claim_seat(id, "a")
      {:ok, _game} = GameServer.begin(id, "a")
      assert GameServer.add_bot(id, "a") == {:error, :already_started}
      assert GameServer.remove_bot(id, "a", 1) == {:error, :already_started}
    end

    test "bots follow the renumbered seats and survive play again" do
      {:ok, id} = GameServer.start(4, {1, 2, 3})
      {:ok, 0} = GameServer.claim_seat(id, "a")
      {:ok, 1} = GameServer.add_bot(id, "a")
      {:ok, 2} = GameServer.add_bot(id, "a")
      :ok = GameServer.remove_bot(id, "a", 1)
      {:ok, %Game{seats: [0, 1]}} = GameServer.begin(id, "a")

      {:ok, table} = GameServer.get(id)
      assert {table.bots, table.names[1]} == {%{1 => :balanced}, "Steady Sam 2"}

      play_with_bots(id, 0)
      {:ok, new_id} = GameServer.play_again(id, "a")
      {:ok, table} = GameServer.get(new_id)

      assert {table.status, table.bots, table.names[1]} ==
               {:waiting, %{1 => :balanced}, "Steady Sam 2"}
    end

    test "1 human and 1 bot play to the end, the human stopping each round" do
      {:ok, id} = GameServer.start(2, {4, 5, 6})
      {:ok, 0} = GameServer.claim_seat(id, "a")
      {:ok, 1} = GameServer.add_bot(id, "a")
      {:ok, _game} = GameServer.begin(id, "a")

      game = play_with_bots(id, 0)
      assert Game.over?(game)
      assert game.players[1].vp > game.players[0].vp
      # the bot drew chips: its moves are in the log
      assert Enum.any?(game.log, &match?({1, :draw}, &1))
    end

    test "lockstep: a bot draws no more often than the human, then finishes" do
      {:ok, id} = GameServer.start(2, {4, 5, 6})
      {:ok, 0} = GameServer.claim_seat(id, "a")
      {:ok, 1} = GameServer.add_bot(id, "a")
      {:ok, _table} = GameServer.configure(id, "a", %{rules: %{fortune: false}})
      {:ok, _game} = GameServer.begin(id, "a")
      [{pid, _}] = Registry.lookup(Quacks.GameRegistry, id)

      # the human has not drawn: the bot waits, with no tick
      game = run_ticks(pid)
      assert bot_draws(game) == 0

      {:ok, _} = GameServer.apply(id, 0, :draw)
      game = run_ticks(pid)
      assert bot_draws(game) == 1
      assert game.phase == :potions

      {:ok, _} = GameServer.apply(id, 0, :draw)
      assert bot_draws(run_ticks(pid)) <= 2

      # the human stops: the cap is off and the bot finishes its potion
      {:ok, _} = GameServer.apply(id, 0, :stop)
      game = run_ticks(pid)
      assert game.phase != :potions or game.round > 1
    end

    test "a stale tick does nothing" do
      {:ok, id} = GameServer.start(2, {1, 2, 3})
      {:ok, 0} = GameServer.claim_seat(id, "a")
      {:ok, 1} = GameServer.add_bot(id, "a")
      {:ok, _game} = GameServer.begin(id, "a")
      [{pid, _}] = Registry.lookup(Quacks.GameRegistry, id)
      # forget the pending tick: every tick in the mailbox is stale now
      state = :sys.replace_state(pid, &%{&1 | bot_ticks: %{}})
      send(pid, {:bot, 1, state.tick})
      send(pid, {:bot, 1, state.tick + 100})
      game = state.session.game
      assert {:ok, %{game: ^game}} = GameServer.get(id)
    end
  end

  # Drive a game with bots to the end: the human at `human` stops at once and
  # otherwise plays like a cautious bot; bot ticks are sent by hand, in order.
  defp play_with_bots(id, human, steps \\ 5000) do
    [{pid, _}] = Registry.lookup(Quacks.GameRegistry, id)
    profile = AI.Profile.get(:cautious)

    Enum.reduce_while(1..steps, AI.new_rng({0, 0, 0}, human), fn _, rng ->
      state = :sys.get_state(pid)
      game = state.session.game
      legal = Game.legal_actions(game, human)

      cond do
        Game.over?(game) ->
          {:halt, game}

        :stop in legal ->
          {:ok, _} = GameServer.apply(id, human, :stop)
          {:cont, rng}

        legal != [] and Game.phase(game, human) != :stopped ->
          {action, rng} = AI.decide(game, human, profile, rng)
          {:ok, _} = GameServer.apply(id, human, action)
          {:cont, rng}

        state.bot_ticks != %{} ->
          send_ticks(pid, state.bot_ticks)
          {:cont, rng}

        true ->
          flunk("nobody can act in round #{game.round}")
      end
    end)
  end

  # Send the pending bot ticks until there are none; then the game.
  defp run_ticks(pid, n \\ 200) do
    state = :sys.get_state(pid)

    if state.bot_ticks == %{} or n == 0 do
      state.session.game
    else
      send_ticks(pid, state.bot_ticks)
      run_ticks(pid, n - 1)
    end
  end

  defp bot_draws(game), do: Enum.count(game.log, &(&1 == {1, :draw}))

  defp send_ticks(pid, ticks),
    do: Enum.each(ticks, fn {seat, tick} -> send(pid, {:bot, seat, tick}) end)
end
