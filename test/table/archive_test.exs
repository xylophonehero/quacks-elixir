defmodule Table.ArchiveTest do
  @moduledoc """
  The archive of finished `Table.Server` games (`Table.Archive`): for each game a
  whole game played by its bots, written as an archive body, through JSON and
  back, replays through its engine to the same final game and status. And a
  Hearts room writes its file at game over.
  """
  # Not async: the games directory is app config, read when a room starts.
  use ExUnit.Case, async: false

  alias Quacks.GameStore
  alias Table.{Archive, Server}

  doctest Archive

  # key => {opts, bot level, seed}
  @games %{
    "hearts" => {%{players: 4, target: 40}, :heuristic, {11, 12, 13}},
    "codenames_duet" => {%{}, :vectors, {21, 22, 23}},
    "codex" => {%{bot: true}, :basic, {31, 32, 33}},
    "generic" => {%{spec: "crazy_eights", players: 3}, :random, {41, 42, 43}}
  }

  # Bots play every seat to the end; the room as `Table.Server` keeps it.
  defp play(key) do
    {opts, level, seed} = @games[key]
    adapter = Table.game(key).game
    {:ok, game} = adapter.new(opts, seed)
    seats = adapter.seats(game)
    bots = Map.new(seats, fn s -> {s, adapter.bot_new(level, put_elem(seed, 0, s + 1))} end)

    {game, log} =
      Enum.reduce_while(1..20_000, {game, bots, []}, fn _, {game, bots, log} ->
        case adapter.status(game) do
          {:over, _} ->
            {:halt, {game, log}}

          {:playing, active} ->
            {:cont,
             Enum.reduce(active, {game, bots, log}, fn seat, {g, b, l} ->
               {action, bot} = adapter.bot_choose(level, bot_view(key, adapter, g, seat), b[seat])
               {:ok, g} = adapter.apply(g, seat, action)
               {g, Map.put(b, seat, bot), [{seat, action} | l]}
             end)}
        end
      end)

    room = %{
      key: key,
      code: "ABCDE",
      adapter: adapter,
      opts: opts,
      seed: seed,
      log: log,
      game: game,
      seats: Map.new(seats, &{&1, %{name: "P#{&1}", bot: if(&1 > 0, do: level), token: nil}})
    }

    {room, adapter.status(game)}
  end

  # Codex: the human seat's page view has another shape; its bot view fits the bot.
  defp bot_view("codex", _adapter, game, seat), do: Codex.Game.bot_view(game, seat)
  defp bot_view(_key, adapter, game, seat), do: adapter.view(game, seat)

  for key <- ["hearts", "codenames_duet", "codex", "generic"] do
    test "#{key}: the archived game replays to the same final game and status" do
      {room, {:over, _} = status} = play(unquote(key))

      body = room |> Archive.body(status) |> Jason.encode!() |> Jason.decode!()
      assert %{"format" => 1, "game" => unquote(key), "id" => "ABCDE"} = body
      assert length(body["log"]) == length(room.log) and room.log != []
      assert [%{"seat" => 0, "human" => true, "bot" => nil} | bots] = body["seats"]
      assert Enum.all?(bots, &(&1["human"] == false and is_binary(&1["bot"])))
      assert is_list(body["winners"])

      assert {:ok, replayed} = Archive.replay(body)
      assert replayed == room.game
      assert Archive.decode(body["status"]) == status
      assert body["status"] == status |> Archive.encode() |> Jason.encode!() |> Jason.decode!()
    end
  end

  test "a broken log does not replay" do
    {room, status} = play("generic")
    body = room |> Archive.body(status) |> Jason.encode!() |> Jason.decode!()
    [[seat, _] | rest] = body["log"]
    assert {:error, _} = Archive.replay(%{body | "log" => [[seat, ["no_such_atom_xyz"]] | rest]})
    assert {:error, :unknown_game} = Archive.replay(%{body | "game" => "chess"})
  end

  test "a Hearts room writes its archive file when the game is over" do
    dir = Quacks.GameHelpers.games_dir()
    token = "arc-#{System.unique_integer([:positive])}"

    {:ok, code} =
      Server.create(
        "hearts",
        %{opts: %{players: 4, target: 30}, bots: 3, level: :heuristic, name: "Nick"},
        token
      )

    file = Path.join(GameStore.finished_dir(dir, "hearts"), code <> ".json")
    {:ok, _} = Server.join("hearts", code, token)

    Enum.reduce_while(1..5_000, nil, fn _, _ ->
      %{game: game} = Server.state("hearts", code)
      Server.ready("hearts", code, token)

      case {Hearts.Table.status(game), Hearts.Table.legal_actions(game, 0)} do
        {{:over, _}, _} -> {:halt, :over}
        {_, [action | _]} -> {:cont, Server.act("hearts", code, token, action)}
        {_, []} -> {:cont, :sys.get_state(pid(code))}
      end
    end)

    body = file |> File.read!() |> Jason.decode!()
    assert %{"game" => "hearts", "id" => ^code, "winners" => [_ | _]} = body
    assert [%{"name" => "Nick", "human" => true} | _] = body["seats"]
    assert {:ok, replayed} = Archive.replay(body)
    assert replayed == Server.state("hearts", code).game
  end

  defp pid(code), do: GenServer.whereis({:via, Registry, {Table.Registry, {"hearts", code}}})
end
