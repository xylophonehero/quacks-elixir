defmodule Table.ServerTest do
  @moduledoc "A `Table.Server` room of Hearts: seats, bots, the pushes per seat."
  use ExUnit.Case, async: true

  alias Table.{Server, View}

  defp create(config) do
    config = Map.merge(%{opts: %{players: 4}, bots: 3, name: "Nick"}, config)
    {:ok, code} = Server.create("hearts", config, "host-#{System.unique_integer()}")
    code
  end

  test "a bad set-up is refused" do
    assert {:error, :invalid_bots} = Server.create("hearts", %{opts: %{players: 4}, bots: 4}, "t")

    assert {:error, {:invalid_option, :players, 6}} =
             Server.create("hearts", %{opts: %{players: 6}}, "t")

    assert {:error, :unknown_game} = Server.create("chess", %{opts: %{}}, "t")
  end

  test "join: the creator's seat, a free seat, then a watcher; seats are public without tokens" do
    host = "host-#{System.unique_integer()}"
    {:ok, code} = Server.create("hearts", %{opts: %{players: 4}, bots: 2}, host)

    assert {:ok, %{seat: 0, view: %View{seat: 0}, seats: seats}} =
             Server.join("hearts", code, host)

    assert %{1 => %{open: true}, 2 => %{bot: true}} = seats
    refute inspect(seats) =~ host

    Phoenix.PubSub.subscribe(Quacks.PubSub, Server.topic("hearts", code))
    assert {:ok, %{seat: 1}} = Server.join("hearts", code, "friend")
    assert_receive {:table_seats, %{1 => %{open: false}}}
    assert {:ok, %{seat: :spectator, view: %View{actions: []}}} = Server.join("hearts", code, "x")
    assert Server.find(String.downcase(code)) == "hearts"
  end

  test "bots pass together; each seat gets its own view with a new version" do
    code = create(%{})
    Phoenix.PubSub.subscribe(Quacks.PubSub, Server.seat_topic("hearts", code, 0))
    Phoenix.PubSub.subscribe(Quacks.PubSub, Server.seat_topic("hearts", code, 2))

    # The bots' tick (0 ms in tests): one change with all 3 passes.
    assert_receive {:table_view, %View{seat: 0, version: 2, view: v}}
    assert v.passed == [1, 2, 3]
    assert_receive {:table_view, %View{seat: 2, version: 2, view: v2}}
    assert v2.hand != v.hand

    host = Server.state("hearts", code).seats[0].token
    hand = Server.state("hearts", code).game.hands[0]
    assert {:error, :invalid_pass} = Server.act("hearts", code, host, {:pass, Enum.take(hand, 2)})

    assert {:ok, %View{version: 3}} =
             Server.act("hearts", code, host, {:pass, Enum.take(hand, 3)})

    assert {:error, :no_seat} = Server.act("hearts", code, "nobody", {:pass, []})
  end
end
