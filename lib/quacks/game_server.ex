defmodule Quacks.GameServer do
  @moduledoc """
  One process per game. It holds the `Quacks.Session` and the table: which browser
  (player token) sits in which seat, and the seat nicknames.

  Why a process per game? A LiveView process lives as long as one browser tab. When
  two or more browsers play the same game, the game must live somewhere they can all
  reach, and every change must reach every tab. A GenServer gives us exactly that:
  it serialises the moves (two clicks at the same moment are applied one after the
  other, never on top of each other), it is found by its short game id through
  `Quacks.GameRegistry`, and after every change it broadcasts on `Quacks.PubSub`
  (topic `"game:" <> id`), so each LiveView re-renders. The rules stay in the pure
  `Quacks.Game`; this module only stores, serialises and announces.

  Games live under `Quacks.GameSupervisor` and are not persisted: a game that sees no
  message for 2 hours stops, and a node restart forgets every game.
  """

  use GenServer, restart: :temporary

  alias Quacks.{Game, Session}

  @idle_timeout :timer.hours(2)
  @lobby_topic "lobby"

  @typedoc "A short game id, 6 lowercase letters."
  @type id :: String.t()
  @typedoc "What a page needs about a game besides the game itself."
  @type table :: %{
          id: id,
          game: Game.t(),
          seed: {integer, integer, integer},
          players: 1..4,
          names: %{Game.seat() => String.t()}
        }

  # -- API ---------------------------------------------------------------------------

  @doc "Start a game for 1 to 4 players. A `nil` seed picks a random one."
  @spec start(1..4, {integer, integer, integer} | nil) :: {:ok, id}
  def start(players, seed \\ nil) when players in 1..4 do
    id = new_id()
    seed = seed || random_seed()

    case DynamicSupervisor.start_child(Quacks.GameSupervisor, {__MODULE__, {id, players, seed}}) do
      {:ok, _pid} ->
        broadcast_lobby()
        {:ok, id}

      # Two games drew the same id; try again with a new one.
      {:error, {:already_started, _pid}} ->
        start(players, seed)
    end
  end

  @doc false
  def start_link({id, _players, _seed} = arg),
    do: GenServer.start_link(__MODULE__, arg, name: {:via, Registry, {Quacks.GameRegistry, id}})

  @doc """
  The game and its table. `names` holds the claimed seats only; a seat that is not in
  it has nobody yet.
  """
  @spec get(id) :: {:ok, table} | {:error, :not_found}
  def get(id), do: call(id, :get)

  @doc "Apply `action` for `seat`. Returns the new game, or the engine's error."
  @spec apply(id, Game.seat(), Game.action()) :: {:ok, Game.t()} | {:error, term}
  def apply(id, seat, action), do: call(id, {:apply, seat, action})

  @doc "Take back the last action. Solo games only."
  @spec undo(id) :: {:ok, Game.t()} | {:error, :not_solo | :not_found}
  def undo(id), do: call(id, :undo)

  @doc """
  The seat of the browser with `token`. A new token gets the next free seat (join
  order, so the creator is seat 0); when every seat is taken it is a spectator.
  """
  @spec claim_seat(id, String.t()) :: {:ok, Game.seat()} | {:error, :full | :not_found}
  def claim_seat(id, token), do: call(id, {:claim_seat, token})

  @doc "Set the nickname of `seat`. A blank name goes back to \"Seat N\"."
  @spec rename(id, Game.seat(), String.t()) :: :ok | {:error, :not_found}
  def rename(id, seat, name), do: call(id, {:rename, seat, name})

  @doc "Games on this node that still have a free seat and are not over, sorted by id."
  @spec open_games() :: [table]
  def open_games do
    Quacks.GameRegistry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.flat_map(fn id ->
      case get(id) do
        {:ok, table} -> [table]
        {:error, :not_found} -> []
      end
    end)
    |> Enum.filter(&open?/1)
    |> Enum.sort_by(& &1.id)
  end

  @doc "\"Seat 1\" for seat 0: the name a seat has before anyone renames it."
  @spec default_name(Game.seat()) :: String.t()
  def default_name(seat), do: "Seat #{seat + 1}"

  @doc "The PubSub topic of one game. Messages: `{:game, id, game}`, `{:names, id, names}`."
  @spec topic(id) :: String.t()
  def topic(id), do: "game:" <> id

  @doc "The PubSub topic the lobby listens on: `:games_changed` when seats or games change."
  @spec lobby_topic() :: String.t()
  def lobby_topic, do: @lobby_topic

  defp open?(t), do: map_size(t.names) < t.players and not Game.over?(t.game)

  # A game that just stopped can still be in the Registry for a moment, hence the catch.
  defp call(id, msg) do
    case Registry.lookup(Quacks.GameRegistry, id) do
      [{pid, _}] -> GenServer.call(pid, msg)
      [] -> {:error, :not_found}
    end
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  # -- server ------------------------------------------------------------------------

  @impl true
  def init({id, players, seed}) do
    # `tokens` maps a browser's player token to its seat.
    state = %{id: id, session: Session.new(seed, players), tokens: %{}, names: %{}}
    {:ok, state, @idle_timeout}
  end

  @impl true
  def handle_call(:get, _from, state), do: {:reply, {:ok, table(state)}, state, @idle_timeout}

  def handle_call({:apply, seat, action}, _from, state) do
    case Session.apply(state.session, seat, action) do
      {:ok, session} -> reply_game(%{state | session: session})
      error -> {:reply, error, state, @idle_timeout}
    end
  end

  def handle_call(:undo, _from, %{session: %{players: 1}} = state),
    do: reply_game(%{state | session: Session.undo(state.session)})

  def handle_call(:undo, _from, state), do: {:reply, {:error, :not_solo}, state, @idle_timeout}

  def handle_call({:claim_seat, token}, _from, state) do
    seated = map_size(state.tokens)

    cond do
      Map.has_key?(state.tokens, token) ->
        {:reply, {:ok, state.tokens[token]}, state, @idle_timeout}

      seated < state.session.players ->
        state = %{
          state
          | tokens: Map.put(state.tokens, token, seated),
            names: Map.put(state.names, seated, default_name(seated))
        }

        broadcast_names(state)
        broadcast_lobby()
        {:reply, {:ok, seated}, state, @idle_timeout}

      true ->
        {:reply, {:error, :full}, state, @idle_timeout}
    end
  end

  def handle_call({:rename, seat, name}, _from, state) do
    name = name |> String.trim() |> String.slice(0, 20)
    name = if name == "", do: default_name(seat), else: name
    state = %{state | names: Map.put(state.names, seat, name)}
    broadcast_names(state)
    {:reply, :ok, state, @idle_timeout}
  end

  # No message for @idle_timeout: nobody plays this game any more.
  @impl true
  def handle_info(:timeout, state) do
    broadcast_lobby()
    {:stop, :normal, state}
  end

  defp reply_game(state) do
    game = state.session.game
    Phoenix.PubSub.broadcast(Quacks.PubSub, topic(state.id), {:game, state.id, game})
    {:reply, {:ok, game}, state, @idle_timeout}
  end

  defp broadcast_names(state),
    do: Phoenix.PubSub.broadcast(Quacks.PubSub, topic(state.id), {:names, state.id, state.names})

  defp broadcast_lobby, do: Phoenix.PubSub.broadcast(Quacks.PubSub, @lobby_topic, :games_changed)

  defp table(state) do
    %{
      id: state.id,
      game: state.session.game,
      seed: state.session.seed,
      players: state.session.players,
      names: state.names
    }
  end

  defp new_id do
    for <<byte <- :crypto.strong_rand_bytes(6)>>, into: "", do: <<?a + rem(byte, 26)>>
  end

  defp random_seed,
    do: {:rand.uniform(1_000_000), :rand.uniform(1_000_000), :rand.uniform(1_000_000)}
end
