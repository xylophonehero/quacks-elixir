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

  A game has two statuses. `:waiting` (the pre-game lobby): there is no `Quacks.Game`
  yet, browsers take seats (`claim_seat/2`) and leave them (`leave_seat/2`), up to the
  configured number of players. `begin/2` starts the game with the seats taken
  (renumbered `0..n-1` in seat order) and makes it `:playing`; from then on no new
  seats are given out. The creator is the first browser to take a seat; only the
  creator may begin, unless the creator left, then any seated browser may.

  Games live under `Quacks.GameSupervisor` and are not persisted: a game that sees no
  message for 2 hours stops, and a node restart forgets every game.
  """

  use GenServer, restart: :temporary

  alias Quacks.{Game, Session}

  @idle_timeout :timer.hours(2)
  @lobby_topic "lobby"

  @typedoc "A short game id, 6 lowercase letters."
  @type id :: String.t()
  @typedoc """
  What a page needs about a game. `game` is `nil` while `status` is `:waiting`.
  `players` is the number of seats in the game once `:playing`, and the maximum
  (`max_players`) while `:waiting`. `creator` is the creator's seat, `nil` once they left.
  """
  @type table :: %{
          id: id,
          status: :waiting | :playing,
          game: Game.t() | nil,
          seed: {integer, integer, integer},
          players: 1..5,
          max_players: 1..5,
          names: %{Game.seat() => String.t()},
          creator: Game.seat() | nil
        }

  # -- API ---------------------------------------------------------------------------

  @doc """
  Open a game for at most 1 to 4 players (5 with The Herb Witches); it waits for
  `begin/2`. A `nil` seed picks a random one. `sets` picks the Ingredient Set per
  colour, e.g. `%{green: 2}` (left out: Set 1). `rules` sets house rules, e.g.
  `%{explode_above: 9}` (left out: the default). `expansion: :herb_witches` turns the
  expansion on. See `Quacks.Game.new/1`.
  """
  @spec start(
          1..5,
          {integer, integer, integer} | nil,
          Quacks.Rules.Chips.sets(),
          map,
          Quacks.Rules.Chips.expansion()
        ) :: {:ok, id}
  def start(players, seed \\ nil, sets \\ %{}, rules \\ %{}, expansion \\ nil)
      when players in 1..4 or (players == 5 and expansion == :herb_witches) do
    id = new_id()
    seed = seed || random_seed()
    arg = {id, players, seed, sets, rules, expansion}

    case DynamicSupervisor.start_child(Quacks.GameSupervisor, {__MODULE__, arg}) do
      {:ok, _pid} ->
        broadcast_lobby()
        {:ok, id}

      # Two games drew the same id; try again with a new one.
      {:error, {:already_started, _pid}} ->
        start(players, seed, sets, rules, expansion)
    end
  end

  @doc false
  def start_link({id, _players, _seed, _sets, _rules, _expansion} = arg),
    do: GenServer.start_link(__MODULE__, arg, name: {:via, Registry, {Quacks.GameRegistry, id}})

  @doc """
  The game and its table. `names` holds the claimed seats only; a seat that is not in
  it has nobody yet.
  """
  @spec get(id) :: {:ok, table} | {:error, :not_found}
  def get(id), do: call(id, :get)

  @doc "Apply `action` for `seat`. Returns the new game, or the engine's error."
  @spec apply(id, Game.seat(), Game.action()) ::
          {:ok, Game.t()} | {:error, :not_started | :not_found | term}
  def apply(id, seat, action), do: call(id, {:apply, seat, action})

  @doc "Take back the last action. Solo games only."
  @spec undo(id) :: {:ok, Game.t()} | {:error, :not_solo | :not_started | :not_found}
  def undo(id), do: call(id, :undo)

  @doc """
  The seat of the browser with `token`. While `:waiting`, a new token gets the lowest
  free seat (so the creator is seat 0); when every seat is taken, or the game has
  begun, it is a spectator.
  """
  @spec claim_seat(id, String.t()) :: {:ok, Game.seat()} | {:error, :full | :not_found}
  def claim_seat(id, token), do: call(id, {:claim_seat, token})

  @doc """
  Free the seat of `token` while the game is `:waiting` (its page closed). Does
  nothing once the game has begun.
  """
  @spec leave_seat(id, String.t()) :: :ok | {:error, :not_found}
  def leave_seat(id, token), do: call(id, {:leave_seat, token})

  @doc """
  Start the game with the seats taken now. Only the creator may, or any seated
  browser once the creator left. Broadcasts the new game and the renumbered names.
  """
  @spec begin(id, String.t()) ::
          {:ok, Game.t()} | {:error, :not_creator | :not_seated | :already_started | :not_found}
  def begin(id, token), do: call(id, {:begin, token})

  @doc "Set the nickname of `seat`. A blank name goes back to \"Seat N\"."
  @spec rename(id, Game.seat(), String.t()) :: :ok | {:error, :not_found}
  def rename(id, seat, name), do: call(id, {:rename, seat, name})

  @doc "Games on this node that are still `:waiting` with a free seat, sorted by id."
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

  defp open?(t), do: t.status == :waiting and map_size(t.names) < t.max_players

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
  def init({id, players, seed, sets, rules, expansion}) do
    # `tokens` maps a browser's player token to its seat; `session` is nil until begin.
    state = %{
      id: id,
      max_players: players,
      seed: seed,
      opts: [sets: sets, rules: rules, expansion: expansion],
      session: nil,
      tokens: %{},
      names: %{},
      creator: nil
    }

    {:ok, state, @idle_timeout}
  end

  @impl true
  def handle_call(:get, _from, state), do: {:reply, {:ok, table(state)}, state, @idle_timeout}

  def handle_call({:apply, _, _}, _from, %{session: nil} = state),
    do: {:reply, {:error, :not_started}, state, @idle_timeout}

  def handle_call({:apply, seat, action}, _from, state) do
    case Session.apply(state.session, seat, action) do
      {:ok, session} -> reply_game(%{state | session: session})
      error -> {:reply, error, state, @idle_timeout}
    end
  end

  def handle_call(:undo, _from, %{session: nil} = state),
    do: {:reply, {:error, :not_started}, state, @idle_timeout}

  def handle_call(:undo, _from, %{session: %{players: 1}} = state),
    do: reply_game(%{state | session: Session.undo(state.session)})

  def handle_call(:undo, _from, state), do: {:reply, {:error, :not_solo}, state, @idle_timeout}

  def handle_call({:claim_seat, token}, _from, state) do
    free = Enum.find(0..(state.max_players - 1), &(not Map.has_key?(state.names, &1)))

    cond do
      Map.has_key?(state.tokens, token) ->
        {:reply, {:ok, state.tokens[token]}, state, @idle_timeout}

      state.session == nil and free != nil ->
        state = %{
          state
          | tokens: Map.put(state.tokens, token, free),
            names: Map.put(state.names, free, default_name(free)),
            creator: state.creator || token
        }

        # Solo has nobody to wait for: the game begins with its only seat.
        state = if state.max_players == 1, do: begin_game(state), else: state
        broadcast_names(state)
        broadcast_lobby()
        {:reply, {:ok, free}, state, @idle_timeout}

      true ->
        {:reply, {:error, :full}, state, @idle_timeout}
    end
  end

  def handle_call({:leave_seat, token}, _from, %{session: nil} = state) do
    case Map.pop(state.tokens, token) do
      {nil, _} ->
        {:reply, :ok, state, @idle_timeout}

      {seat, tokens} ->
        state = %{state | tokens: tokens, names: Map.delete(state.names, seat)}
        broadcast_names(state)
        broadcast_lobby()
        {:reply, :ok, state, @idle_timeout}
    end
  end

  def handle_call({:leave_seat, _token}, _from, state), do: {:reply, :ok, state, @idle_timeout}

  def handle_call({:begin, _token}, _from, %{session: %Session{}} = state),
    do: {:reply, {:error, :already_started}, state, @idle_timeout}

  def handle_call({:begin, token}, _from, state) do
    cond do
      not Map.has_key?(state.tokens, token) ->
        {:reply, {:error, :not_seated}, state, @idle_timeout}

      token != state.creator and Map.has_key?(state.tokens, state.creator) ->
        {:reply, {:error, :not_creator}, state, @idle_timeout}

      true ->
        state = begin_game(state)
        broadcast_names(state)
        broadcast_lobby()
        reply_game(state)
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

  # The seats taken become seats 0..n-1, in seat order. An untouched default name
  # follows the new seat number.
  defp begin_game(state) do
    renumber =
      state.names |> Map.keys() |> Enum.sort() |> Enum.with_index() |> Map.new()

    names =
      Map.new(state.names, fn {old, name} ->
        new = renumber[old]
        {new, if(name == default_name(old), do: default_name(new), else: name)}
      end)

    %{
      state
      | session: Session.new(state.seed, map_size(renumber), state.opts),
        tokens: Map.new(state.tokens, fn {token, seat} -> {token, renumber[seat]} end),
        names: names
    }
  end

  defp reply_game(state) do
    game = state.session.game
    Phoenix.PubSub.broadcast(Quacks.PubSub, topic(state.id), {:game, state.id, game})
    {:reply, {:ok, game}, state, @idle_timeout}
  end

  defp broadcast_names(state),
    do: Phoenix.PubSub.broadcast(Quacks.PubSub, topic(state.id), {:names, state.id, state.names})

  defp broadcast_lobby, do: Phoenix.PubSub.broadcast(Quacks.PubSub, @lobby_topic, :games_changed)

  defp table(%{session: session} = state) do
    %{
      id: state.id,
      status: if(session, do: :playing, else: :waiting),
      game: session && session.game,
      seed: state.seed,
      players: if(session, do: session.players, else: state.max_players),
      max_players: state.max_players,
      names: state.names,
      creator: state.tokens[state.creator]
    }
  end

  defp new_id do
    for <<byte <- :crypto.strong_rand_bytes(6)>>, into: "", do: <<?a + rem(byte, 26)>>
  end

  defp random_seed,
    do: {:rand.uniform(1_000_000), :rand.uniform(1_000_000), :rand.uniform(1_000_000)}
end
