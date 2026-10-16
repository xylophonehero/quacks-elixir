defmodule CodenamesDuetWeb.Gallery do
  @moduledoc """
  The gallery's Codenames Duet board story (`/dev/gallery/codenames/board`): the
  real board page (`CodenamesDuetWeb.Board.page/1`) at a game state, with no room
  process.

  Each state is a real `CodenamesDuet.Game` from a fixed seed, played on with
  actions that read the key (a green, a bystander or an assassin of the clue
  giver's side), so a state looks the same on every run. The page's assigns come
  from `Board.init/1` and `Board.put_view/3`, as on the live page.
  """

  alias CodenamesDuet.{Clue, Game, Key, Words}
  alias CodenamesDuetWeb.Board

  @doc "The board states."
  @spec states() :: [String.t()]
  def states, do: ~w(clue clue-error guessing bystander sudden-death won lost waiting watching)

  @seed {11, 22, 33}
  @clues ~w(quokka zephyr nimbus wobble jigsaw)

  @doc """
  The board story. Args: `state`, `words` (`list`: dealt from the list;
  `longest`: the 25 longest words of the list), `hide_key`, `theme`.
  """
  @spec board_story(map) :: map
  def board_story(%{"state" => state} = args) do
    timer = if state == "sudden-death", do: 2, else: 9
    {:ok, game} = Game.new(%{timer: timer}, @seed)
    game = words(game, args["words"])
    {before, now, seat} = reach(state, game)
    seat = if state == "watching", do: :spectator, else: seat

    socket =
      %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          static: true,
          key: "codenames_duet",
          code: "GALRY",
          seat: seat,
          seats: seats(state),
          env: nil,
          theme: args["theme"]
        }
      }
      |> Board.init()
      |> put(before, seat)
      |> put(now, seat)
      |> extra(state, now)
      |> Phoenix.Component.assign(hide_key: args["hide_key"] == true)

    %{view: :duet_board, board: socket.assigns}
  end

  defp words(game, "longest") do
    longest =
      Words.all()
      |> Enum.sort_by(&{-String.length(&1), &1})
      |> Enum.take(25)

    %{game | words: longest, log: [{:setup, longest, game.timer}]}
  end

  defp words(game, _list), do: game

  defp seats("waiting"),
    do: %{
      0 => %{name: "Ann", bot: false, open: false},
      1 => %{name: "Player 2", bot: false, open: true}
    }

  defp seats(_state),
    do: %{
      0 => %{name: "Ann", bot: false, open: false},
      1 => %{name: "Bob", bot: false, open: false}
    }

  defp put(socket, nil, _seat), do: socket

  defp put(socket, game, seat) do
    old = socket.assigns.env

    env = %Table.View{
      version: if(old, do: old.version + 1, else: 1),
      seat: seat,
      status: Game.status(game),
      actions: if(seat == :spectator, do: [], else: Game.legal_actions(game, seat)),
      view: Game.view(game, seat)
    }

    socket
    |> Board.put_view(env, old)
    |> Phoenix.Component.assign(env: env)
  end

  defp extra(socket, "clue-error", game) do
    word = hd(Game.visible_words(game))

    Phoenix.Component.assign(socket,
      clue_error: {:visible_word, word},
      clue_form: Phoenix.Component.to_form(%{"word" => word <> "s", "number" => "2"}, as: :clue)
    )
  end

  defp extra(socket, "guessing", game) do
    [{:guess, i} | _] = Enum.drop(Game.legal_actions(game, 1), 3)
    Phoenix.Component.assign(socket, picked: i)
  end

  defp extra(socket, _state, _game), do: socket

  # {the state before the last step (or nil), the state, the seat that looks}
  defp reach(state, game) when state in ~w(clue clue-error waiting watching), do: {nil, game, 0}

  defp reach("guessing", game) do
    before = game |> clue(0, 3)
    now = before |> guess(1, :green)
    {before, now, 1}
  end

  defp reach("bystander", game) do
    before = game |> clue(0, 2) |> guess(1, :green) |> guess(1, :green)
    {before, guess(before, 1, :neutral), 1}
  end

  defp reach("sudden-death", game) do
    before =
      game
      |> clue(0, 2)
      |> guess(1, :green)
      |> guess(1, :neutral)
      |> clue(1, 1)
      |> guess(0, :green)

    {before, guess(before, 0, :neutral), 0}
  end

  defp reach("won", game) do
    before =
      game
      |> clue(0, 9)
      |> guess_all(1)
      |> clue(1, 6)
      |> guess(0, :neutral)
      |> clue(1, 6)

    {before, guess_all(before, 0), 0}
  end

  defp reach("lost", game) do
    before = game |> clue(0, 2) |> guess(1, :green)
    {before, guess(before, 1, :assassin), 1}
  end

  defp clue(game, seat, number) do
    word = Enum.find(@clues, &(Clue.check(&1, number, Game.visible_words(game)) == :ok))
    {:ok, game} = Game.apply(game, seat, {:clue, word, number})
    game
  end

  # The guesser touches the first open word of `colour` on the clue giver's side.
  defp guess(game, seat, colour) do
    i =
      Enum.find(Key.indexes(game.key[game.giver], colour), &Game.guessable?(game, &1, game.giver))

    {:ok, game} = Game.apply(game, seat, {:guess, i})
    game
  end

  # Every green word left on the clue giver's side.
  defp guess_all(%Game{phase: :guess} = game, seat) do
    if Game.greens_left(game, game.giver) > 0,
      do: game |> guess(seat, :green) |> guess_all(seat),
      else: game
  end

  defp guess_all(game, _seat), do: game
end
