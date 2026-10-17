defmodule TableWeb.Gallery.Generic do
  @moduledoc """
  The gallery's generic table story (`/dev/gallery/generic/board`): the real
  board page (`TableWeb.GenericBoard.page/1`) for a Crazy Eights game
  (`Table.Generic.Game` with the scripted referee), with no room process.

  Each state comes from a fixed seed: every seat plays a random legal action
  (a card when it can) with a fixed rng until the state comes. The page's
  assigns come from `GenericBoard.init/1` and `put_view/3`, as on the live page.
  """

  alias Table.Generic.Game
  alias Table.Kit.Rng
  alias TableWeb.GenericBoard

  @names ~w(Ada Basil Clove Dill)

  @doc "The board states."
  @spec states() :: [String.t()]
  def states, do: ~w(start play suit waiting spectator over)

  @doc "The board story: `state` and `players` (2..5)."
  @spec board_story(map) :: map
  def board_story(%{"state" => state, "players" => players}) do
    {:ok, game} = Game.new(%{spec: "crazy_eights", players: players}, {7, 8, 9})

    case reach(state, game, Rng.seed({1, 2, 3}), nil, 0) do
      nil ->
        %{view: :error, message: "no #{state} state within 3000 steps"}

      {before, now} ->
        seat = if state == "spectator", do: :spectator, else: 0

        socket =
          %Phoenix.LiveView.Socket{
            assigns: %{
              __changed__: %{},
              flash: %{},
              static: true,
              key: "generic",
              code: "GALRY",
              seat: seat,
              seats: seats(players),
              env: nil
            }
          }
          |> GenericBoard.init()
          |> put(before, seat)
          |> put(now, seat)

        %{view: :generic_board, board: socket.assigns}
    end
  end

  defp seats(players) do
    Map.new(0..(players - 1), fn
      0 -> {0, %{name: "Nick", bot: false, open: false}}
      s -> {s, %{name: Enum.at(@names, s - 1), bot: true, open: false}}
    end)
  end

  defp put(socket, nil, _seat), do: socket

  defp put(socket, game, seat) do
    old = socket.assigns.env

    env = %Table.View{
      version: if(old, do: old.version + 1, else: 1),
      seat: seat,
      status: Game.status(game),
      actions: Game.legal_actions(game, seat),
      view: Game.view(game, seat)
    }

    socket |> GenericBoard.put_view(env, old) |> Phoenix.Component.assign(env: env)
  end

  defp reach(_state, _game, _rng, _prev, steps) when steps > 3000, do: nil

  defp reach(state, game, rng, prev, steps) do
    if done?(state, game, steps) do
      {prev, game}
    else
      case Game.status(game) do
        {:over, _} ->
          nil

        {:playing, [seat]} ->
          {action, rng} = pick(Game.legal_actions(game, seat), rng)
          {:ok, next} = Game.apply(game, seat, action)
          reach(state, next, rng, game, steps + 1)
      end
    end
  end

  defp pick(actions, rng) do
    plays = for {:play, _, _} = a <- actions, do: a
    Rng.pick(if(plays == [], do: actions, else: plays), rng)
  end

  defp done?("start", _game, _steps), do: true
  defp done?("over", game, _steps), do: game.result != nil
  defp done?("suit", game, _steps), do: game.phase == "choose_suit" and mine?(game)

  defp done?("play", game, steps),
    do: steps >= 6 and mine?(game) and Enum.any?(game.pending.options, &is_tuple/1)

  defp done?(state, game, steps) when state in ~w(waiting spectator),
    do: steps >= 6 and game.pending != nil and game.pending.seat != 0

  defp mine?(game), do: game.pending != nil and game.pending.seat == 0
end
