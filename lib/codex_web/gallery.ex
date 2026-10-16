defmodule CodexWeb.Gallery do
  @moduledoc """
  The gallery's Codex sandbox story (`/dev/gallery/codex/board`): the real board
  page (`CodexWeb.Board.page/1`) at a game state, with no room process.

  Each state is a real `Codex.Game` from a fixed seed, played on with
  `Codex.Game.apply/3`, so it looks the same on every run. The page's assigns come
  from `Board.init/1` and `Board.put_view/3`, as on the live page.
  """

  alias Codex.Game
  alias CodexWeb.Board

  @seed {7, 8, 9}

  @doc "The board states."
  @spec states() :: [String.t()]
  def states, do: ~w(mid-game start selected codex discard buildings log free)

  @doc "The board story. Args: `state`, `pov` (0 or 1), `reveal`."
  @spec board_story(map) :: map
  def board_story(args) do
    state = args["state"]
    {:ok, start} = Game.new(%{}, @seed)
    game = if state == "start", do: start, else: mid_game(start)
    pov = if args["pov"] == "P2", do: 1, else: 0

    socket =
      %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, flash: %{}, code: "GALRY", seats: %{}}
      }
      |> Board.init()
      |> Board.put_view(envelope(game), nil)
      |> Phoenix.Component.assign(pov: pov, reveal: args["reveal"] == true)
      |> extra(state, game)

    %{view: :codex_board, board: socket.assigns}
  end

  defp envelope(game) do
    %Table.View{
      version: 1,
      seat: 0,
      status: Game.status(game),
      actions: Game.legal_actions(game, 0),
      view: Game.view(game, 0)
    }
  end

  defp extra(socket, "selected", game) do
    [id | _] = game.sides[0].zones.in_play
    Phoenix.Component.assign(socket, selected: id)
  end

  defp extra(socket, "codex", _game), do: Phoenix.Component.assign(socket, drawer: {0, :codex})

  defp extra(socket, "discard", _game),
    do: Phoenix.Component.assign(socket, drawer: {0, :discard})

  defp extra(socket, "buildings", _game),
    do: Phoenix.Component.assign(socket, drawer: {0, :buildings})

  defp extra(socket, "log", _game), do: Phoenix.Component.assign(socket, drawer: :log)

  defp extra(socket, "free", game) do
    {:ok, game} = Game.apply(game, 0, {:free_mode, true})
    Board.put_view(socket, envelope(game), nil)
  end

  defp extra(socket, _state, _game), do: socket

  # Turn 3 of P1: heroes out with levels, units in play and on patrol, tokens,
  # gold, a tech building, cards in the discard piles and the trash.
  defp mid_game(game) do
    [p1_hero] = game.sides[0].zones.command
    [p2_hero] = game.sides[1].zones.command
    [a, b, c, d, _] = game.sides[0].zones.hand
    [e, f, g | _] = game.sides[1].zones.hand
    [x | _] = game.sides[0].zones.codex

    [
      {:free_mode, true},
      {:adjust, 0, :gold, 4},
      {:move, a, {0, :in_play}, nil},
      {:move, b, {0, :in_play}, nil},
      {:move, p1_hero, {0, :patrol}, :squad_leader},
      {:adjust_card, p1_hero, :level, 4},
      {:adjust_card, p1_hero, :damage, 1},
      {:toggle, b, :exhausted},
      {:adjust_card, b, :plus, 1},
      {:move, c, {0, :discard}, 0},
      {:move, x, {0, :discard}, 0},
      {:building, 0, :tech_1},
      :end_turn,
      {:adjust, 1, :gold, 5},
      {:move, e, {1, :patrol}, :elite},
      {:move, p2_hero, {1, :patrol}, :lookout},
      {:adjust_card, p2_hero, :level, 2},
      {:move, f, {1, :in_play}, nil},
      {:adjust_card, f, :damage, 1},
      {:move, g, :trash, nil},
      {:adjust, 0, :base_hp, -3},
      {:draw, 1, 2},
      :end_turn,
      {:move, d, {0, :workers}, nil},
      {:adjust, 0, :gold, -1},
      {:draw, 0, 2},
      {:free_mode, false}
    ]
    |> Enum.reduce(game, fn action, game ->
      {:ok, game} = Game.apply(game, 0, action)
      game
    end)
  end
end
