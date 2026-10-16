defmodule HeartsWeb.Gallery do
  @moduledoc """
  The gallery's Hearts board story (`/dev/gallery/hearts/board`): the real
  board page (`HeartsWeb.Board.page/1`) at a game state, with no room process.

  Each state is a real `Hearts.Game` from a fixed seed, played on by the
  heuristic bot in every seat until the state comes. The page's assigns come
  from `HeartsWeb.Board.init/1` and `put_view/3`, as on the live page, so the
  collect, the hand scores and the game over show as they do after a push.
  """

  alias Hearts.AI.Heuristic
  alias Hearts.Game
  alias HeartsWeb.Board

  @doc "The board states."
  @spec states() :: [String.t()]
  def states, do: ~w(pass waiting play collect scores over)

  @names ~w(Ada Basil Clove Dill)

  @doc "The board story: `state` and `players` (3..5)."
  @spec board_story(map) :: map
  def board_story(%{"state" => state, "players" => players}) do
    {:ok, game} = Game.new(%{players: players, target: target(state)}, {7, 8, 9})
    {before, now, selected} = reach(state, game)
    seats = seats(players)

    socket =
      %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          static: true,
          key: "hearts",
          code: "GALRY",
          seat: 0,
          seats: seats,
          env: nil
        }
      }
      |> Board.init()
      |> put(before, nil)
      |> put(now, before)
      |> sweep(state)

    %{view: :hearts_board, board: Map.put(socket.assigns, :selected, selected)}
  end

  defp target("over"), do: 30
  defp target(_state), do: 100

  defp seats(players) do
    Map.new(0..(players - 1), fn
      0 -> {0, %{name: "You", bot: false, open: false}}
      s -> {s, %{name: Enum.at(@names, s - 1), bot: true, open: false}}
    end)
  end

  defp put(socket, nil, _old), do: socket

  defp put(socket, game, old) do
    env = env(game, socket.assigns.env)
    old_env = if old, do: socket.assigns.env

    socket
    |> Board.put_view(env, old_env)
    |> Phoenix.Component.assign(env: env)
  end

  defp env(game, old) do
    %Table.View{
      version: if(old, do: old.version + 1, else: 1),
      seat: 0,
      status: Game.status(game),
      actions: Game.legal_actions(game, 0),
      view: Game.view(game, 0)
    }
  end

  # The scores and the game over open after the last trick flies.
  defp sweep(socket, state) when state in ~w(scores over) do
    {:noreply, socket} = Board.handle_info({:hearts_sweep, socket.assigns.env.version}, socket)
    socket
  end

  defp sweep(socket, _state), do: socket

  # {state before the last step (or nil), the state, the cards picked for the pass}
  defp reach("pass", game), do: {nil, game, Enum.take(game.hands[0], 2)}

  defp reach("waiting", game) do
    {:pass, cards} = bot(game, 0)
    {:ok, now} = Game.apply(game, 0, {:pass, cards})
    {nil, now, []}
  end

  defp reach("play", game),
    do: until(game, &(&1.phase == :playing and &1.turn == 0 and length(&1.trick) >= 2))

  defp reach("collect", game), do: until(game, &match?([{:trick_won, _, _, _} | _], &1.log))

  defp reach(state, game) when state in ~w(scores over),
    do: until(game, &Enum.any?(&1.log, fn e -> match?({:hand_scored, _}, e) end), state)

  defp until(game, done?, state \\ nil) do
    game
    |> Stream.iterate(&step/1)
    |> Stream.chunk_every(2, 1)
    |> Enum.find(fn [_prev, now] -> stop?(now, done?, state) end)
    |> then(fn [prev, now] -> {prev, now, []} end)
  end

  defp stop?(game, _done?, "over"), do: Game.over?(game)
  defp stop?(game, done?, _state), do: done?.(game)

  # One step: the first seat that can act does the heuristic bot's action.
  defp step(game) do
    {:playing, [seat | _]} = Game.status(game)
    {:ok, game} = Game.apply(game, seat, bot(game, seat))
    game
  end

  defp bot(game, seat) do
    {action, nil} = Heuristic.choose(Game.view(game, seat), nil)
    action
  end
end
