defmodule Table.Server do
  @moduledoc """
  One room of a table game (Hearts first): the game state, the seats, the bots
  and the push of one view per seat. A process per room, found by `{key, code}`
  in `Table.Registry` and started under `Table.RoomSupervisor`.

  This is the smallest room that works, not yet the `Table.Server` of the RFC
  (`docs/design/table-game.md` §6, §10 step 11): no persistence (a room dies with
  the node or after 30 minutes without a page), no `Table.Session` (no replay or
  undo), and the game comes through a small adapter (the callbacks below), not
  through the `Table.Game` behaviour.

  ## Seats

  Seat 0 is the creator's. The last `bots` seats are bots; the other seats are
  free until a browser takes one (`join/4`: by its player token, the lowest free
  seat). The same token gets the same seat again on reload. A browser without a
  seat watches (`:spectator`). A seat stays with its token: there are no
  accounts, as in Quacks.

  ## Pushes

  Every change adds 1 to `version` and broadcasts on `Quacks.PubSub`:

  - `seat_topic(key, code, seat)`: `{:table_view, %Table.View{seat: seat}}`
  - `watch_topic(key, code)`: `{:table_view, %Table.View{seat: :spectator}}`
  - `topic(key, code)`: `{:table_seats, seats}` when a seat is taken

  A page renders only the envelope of its seat, so no page holds hidden cards.

  ## Bots

  When a bot seat can act, a tick comes after the adapter's `bot_delay/1` (ms,
  times the `:table_bot_speed` config: 0 in tests). On a tick every bot seat
  that can act does one action: in a phase where all seats act at once (the
  Hearts pass) all bots act together.
  """
  use GenServer

  require Logger

  alias Table.View

  @type key :: String.t()
  @type code :: String.t()
  @type seat :: non_neg_integer

  # -- the adapter ------------------------------------------------------------------

  @doc "A new game from the room's `opts`."
  @callback new(opts :: map, seed :: {integer, integer, integer}) :: {:ok, term} | {:error, term}
  @callback seats(state :: term) :: [seat]
  @callback legal_actions(state :: term, seat) :: [term]
  @callback apply(state :: term, seat, action :: term) :: {:ok, term} | {:error, term}
  @callback status(state :: term) :: {:playing, [seat]} | {:over, map}
  @callback view(state :: term, seat | :spectator) :: term
  @doc "The bot levels; the first is the default."
  @callback bot_levels() :: [atom]
  @callback bot_new(level :: atom, seed :: {integer, integer, integer}) :: term
  @callback bot_choose(level :: atom, view :: term, bot :: term) :: {term, term}
  @doc "How long the next bot waits (ms) after this state: lets the motion play."
  @callback bot_delay(state :: term) :: non_neg_integer

  @idle_ms :timer.minutes(30)
  @alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  @bot_names ~w(Ada Basil Clove Dill Fennel Juniper Mace Saffron)

  # -- the API ----------------------------------------------------------------------

  @doc """
  A new room of game `key`. `config`: `opts` (the game's options, given to
  `new/2`), `bots` (how many seats are bots), `level` (the bots' level), `name`
  (the creator's name). The creator (`token`) gets seat 0.
  """
  @spec create(key, map, String.t()) :: {:ok, code} | {:error, term}
  def create(key, config, token) do
    with %{game: adapter} <- Table.game(key) || {:error, :unknown_game},
         seed = random_seed(),
         {:ok, game} <- adapter.new(config.opts, seed),
         {:ok, seats} <- seats(adapter, game, config, token) do
      code = new_code(key)

      fields = %{
        key: key,
        code: code,
        adapter: adapter,
        opts: config.opts,
        game: game,
        seats: seats,
        bots: new_bots(adapter, seats, seed)
      }

      case DynamicSupervisor.start_child(Table.RoomSupervisor, {__MODULE__, fields}) do
        {:ok, _pid} -> {:ok, code}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp seats(adapter, game, config, token) do
    all = adapter.seats(game)
    bots = Map.get(config, :bots, 0)
    level = Map.get(config, :level) || hd(adapter.bot_levels())

    cond do
      bots not in 0..(length(all) - 1)//1 ->
        {:error, :invalid_bots}

      level not in adapter.bot_levels() ->
        {:error, :invalid_level}

      true ->
        first_bot = length(all) - bots
        name = config |> Map.get(:name, "") |> to_string() |> String.trim()

        {:ok,
         Map.new(all, fn
           0 -> {0, %{bot: nil, token: token, name: if(name == "", do: "Player 1", else: name)}}
           s when s >= first_bot -> {s, %{bot: level, token: nil, name: bot_name(s, first_bot)}}
           s -> {s, %{bot: nil, token: nil, name: "Player #{s + 1}"}}
         end)}
    end
  end

  defp bot_name(seat, first_bot), do: Enum.at(@bot_names, seat - first_bot)

  defp new_bots(adapter, seats, {a, b, c}) do
    for {seat, %{bot: level}} <- seats,
        level,
        into: %{},
        do: {seat, adapter.bot_new(level, {a + seat + 1, b, c})}
  end

  @doc """
  Take a seat in room `code` for the browser with `token` (its old seat, else the
  lowest free seat, else `:spectator`). The calling process is the page: the room
  watches it. Returns the seat, its `Table.View` and the public seats.
  """
  @spec join(key, code, String.t()) ::
          {:ok, %{seat: seat | :spectator, view: View.t(), seats: map}} | {:error, :not_found}
  def join(key, code, token), do: call(key, code, {:join, token})

  @doc "The key of the game that has a room with `code`, or nil."
  @spec find(code) :: key | nil
  def find(code) do
    code = String.upcase(code)
    Enum.find(Map.keys(Table.games()), &(Registry.lookup(Table.Registry, {&1, code}) != []))
  end

  @doc "Do `action` for the seat of `token`."
  @spec act(key, code, String.t(), term) :: {:ok, View.t()} | {:error, term}
  def act(key, code, token, action), do: call(key, code, {:act, token, action})

  @doc "After the game is over: a new game at the same seats (any seated human)."
  @spec play_again(key, code, String.t()) :: :ok | {:error, term}
  def play_again(key, code, token), do: call(key, code, {:play_again, token})

  @doc "The whole room state, with the full game. Tests and debug only."
  @spec state(key, code) :: map | {:error, :not_found}
  def state(key, code), do: call(key, code, :state)

  @doc "The room's topic: `{:table_seats, seats}`."
  @spec topic(key, code) :: String.t()
  def topic(key, code), do: "table:#{key}:#{code}"

  @doc "The topic of one seat: `{:table_view, %Table.View{}}`."
  @spec seat_topic(key, code, seat | :spectator) :: String.t()
  def seat_topic(key, code, :spectator), do: topic(key, code) <> ":watch"
  def seat_topic(key, code, seat), do: topic(key, code) <> ":seat:#{seat}"

  defp call(key, code, msg) do
    case Registry.lookup(Table.Registry, {key, code}) do
      [{pid, _}] -> GenServer.call(pid, msg)
      [] -> {:error, :not_found}
    end
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc false
  def start_link(%{key: key, code: code} = fields),
    do:
      GenServer.start_link(__MODULE__, fields,
        name: {:via, Registry, {Table.Registry, {key, code}}}
      )

  @doc false
  def child_spec(fields),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [fields]}, restart: :temporary}

  # -- the process --------------------------------------------------------------------

  @impl true
  def init(fields) do
    state = Map.merge(fields, %{version: 1, timer: nil, pages: %{}, idle: nil})
    {:ok, state |> idle() |> schedule()}
  end

  @impl true
  def handle_call({:join, token}, {pid, _}, state) do
    {seat, state} = take_seat(state, token)

    state =
      if Map.has_key?(state.pages, pid),
        do: state,
        else: %{state | pages: Map.put(state.pages, pid, Process.monitor(pid)), idle: nil}

    {:reply, {:ok, %{seat: seat, view: envelope(state, seat), seats: public(state)}}, state}
  end

  def handle_call({:act, token, action}, _from, state) do
    with {:ok, seat} <- seat_of(state, token),
         {:ok, game} <- state.adapter.apply(state.game, seat, action) do
      state = state |> changed(game) |> schedule()
      {:reply, {:ok, envelope(state, seat)}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:play_again, token}, _from, state) do
    with {:ok, _seat} <- seat_of(state, token),
         {:over, _} <- state.adapter.status(state.game),
         seed = random_seed(),
         {:ok, game} <- state.adapter.new(state.opts, seed) do
      state = %{state | bots: new_bots(state.adapter, state.seats, seed)}
      {:reply, :ok, state |> changed(game) |> schedule()}
    else
      {:playing, _} -> {:reply, {:error, :not_over}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:state, _from, state), do: {:reply, state, state}

  @impl true
  def handle_info(:tick, state) do
    state = %{state | timer: nil}
    {:playing, active} = state.adapter.status(state.game)

    {game, bots} =
      active
      |> Enum.filter(&state.seats[&1].bot)
      |> Enum.reduce({state.game, state.bots}, &bot_act(state, &1, &2))

    state = if game == state.game, do: state, else: changed(%{state | bots: bots}, game)
    {:noreply, schedule(state)}
  end

  def handle_info({:DOWN, _ref, :process, pid, _}, state) do
    {:noreply, idle(%{state | pages: Map.delete(state.pages, pid)})}
  end

  def handle_info({:idle, ref}, %{idle: ref} = state), do: {:stop, :normal, state}
  def handle_info({:idle, _ref}, state), do: {:noreply, state}

  defp bot_act(state, seat, {game, bots}) do
    level = state.seats[seat].bot
    {action, bot} = state.adapter.bot_choose(level, state.adapter.view(game, seat), bots[seat])

    case state.adapter.apply(game, seat, action) do
      {:ok, game} ->
        {game, Map.put(bots, seat, bot)}

      {:error, reason} ->
        Logger.warning(
          "table bot #{seat} in #{state.code}: #{inspect(action)} #{inspect(reason)}"
        )

        {game, bots}
    end
  end

  defp take_seat(state, token) do
    case Enum.find(state.seats, fn {_, s} -> s.token == token end) do
      {seat, _} ->
        {seat, state}

      nil ->
        case state.seats |> Enum.sort() |> Enum.find(fn {_, s} -> !s.bot and !s.token end) do
          {seat, _} ->
            state = put_in(state.seats[seat].token, token)
            broadcast(state, topic(state.key, state.code), {:table_seats, public(state)})
            {seat, state}

          nil ->
            {:spectator, state}
        end
    end
  end

  defp seat_of(state, token) do
    case Enum.find(state.seats, fn {_, s} -> s.token == token end) do
      {seat, _} -> {:ok, seat}
      nil -> {:error, :no_seat}
    end
  end

  defp public(state) do
    Map.new(state.seats, fn {seat, s} ->
      {seat, %{name: s.name, bot: s.bot != nil, open: s.bot == nil and s.token == nil}}
    end)
  end

  # A new game state: count up, push every seat's view.
  defp changed(state, game) do
    state = %{state | game: game, version: state.version + 1}

    for seat <- state.adapter.seats(game),
        do:
          broadcast(
            state,
            seat_topic(state.key, state.code, seat),
            {:table_view, envelope(state, seat)}
          )

    broadcast(
      state,
      seat_topic(state.key, state.code, :spectator),
      {:table_view, envelope(state, :spectator)}
    )

    state
  end

  defp envelope(state, seat) do
    %View{
      version: state.version,
      seat: seat,
      status: state.adapter.status(state.game),
      actions:
        if(seat == :spectator, do: [], else: state.adapter.legal_actions(state.game, seat)),
      view: state.adapter.view(state.game, seat)
    }
  end

  defp broadcast(_state, topic, msg), do: Phoenix.PubSub.broadcast(Quacks.PubSub, topic, msg)

  defp schedule(%{timer: nil} = state) do
    with {:playing, active} <- state.adapter.status(state.game),
         true <- Enum.any?(active, &state.seats[&1].bot) do
      speed = Application.get_env(:quacks, :table_bot_speed, 1)
      delay = round(state.adapter.bot_delay(state.game) * speed)
      %{state | timer: Process.send_after(self(), :tick, delay)}
    else
      _ -> state
    end
  end

  defp schedule(state), do: state

  defp idle(%{pages: pages} = state) when map_size(pages) == 0 do
    ref = make_ref()
    Process.send_after(self(), {:idle, ref}, @idle_ms)
    %{state | idle: ref}
  end

  defp idle(state), do: state

  defp new_code(key) do
    code = for _ <- 1..5, into: "", do: <<Enum.random(@alphabet)>>
    if Registry.lookup(Table.Registry, {key, code}) == [], do: code, else: new_code(key)
  end

  defp random_seed,
    do: {:rand.uniform(1_000_000), :rand.uniform(1_000_000), :rand.uniform(1_000_000)}
end
