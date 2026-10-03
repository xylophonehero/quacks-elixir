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
  configured number of players (1 to 8). `begin/2` starts the game with the seats taken
  (renumbered `0..n-1` in seat order) and makes it `:playing`; from then on no new
  seats are given out. The creator (the host) is the first browser to take a seat;
  only the creator may `configure/3` the game and begin it, unless the creator left,
  then any seated browser may begin. After the game is over, `play_again/2` opens a
  new waiting game with the same settings and the same seated browsers.

  Bots: while `:waiting` the host may put a bot (`Quacks.AI`) in a free seat
  (`add_bot/3`) and take it out again (`remove_bot/3`). A bot holds a seat like a
  browser does. Once the game is `:playing`, each bot seat that can act gets a tick
  (`{:bot, seat, tick}`, after `:bot_delay` ms, 700 by default): the bot makes one
  action through `Quacks.Session`, every page hears it, and the next tick follows.

  Games live under `Quacks.GameSupervisor` and are not persisted: a game that sees no
  message for 2 hours stops, and a node restart forgets every game.
  """

  use GenServer, restart: :temporary

  alias Quacks.{AI, Game, Session}
  alias Quacks.AI.Profile

  @idle_timeout :timer.hours(2)
  @max_bots 7
  @lobby_topic "lobby"

  @typedoc "A short game id, 6 lowercase letters."
  @type id :: String.t()
  @typedoc """
  What a page needs about a game. `game` is `nil` while `status` is `:waiting`.
  `players` is the number of seats in the game once `:playing`, and the maximum
  (`max_players`) while `:waiting`. `creator` is the creator's seat, `nil` once they left.
  `sets`, `rules` and `expansion` are the options the game starts (or started) with.
  `colours` is each claimed seat's colour, `0..7` (the `--color-seat-N` palette),
  unique at the table. `bots` is the profile of each seat a bot holds.
  """
  @type table :: %{
          id: id,
          status: :waiting | :playing,
          game: Game.t() | nil,
          seed: {integer, integer, integer},
          players: 1..8,
          max_players: 1..8,
          names: %{Game.seat() => String.t()},
          colours: %{Game.seat() => colour},
          bots: %{Game.seat() => Profile.name()},
          creator: Game.seat() | nil,
          sets: Quacks.Rules.Chips.sets(),
          rules: map,
          expansion: Quacks.Rules.Chips.expansion()
        }

  @typedoc "A seat colour: an index into the 8-colour palette (`--color-seat-N`)."
  @type colour :: 0..7

  # -- API ---------------------------------------------------------------------------

  @doc """
  Open a game for at most 1 to 8 players; it waits for
  `begin/2`. A `nil` seed picks a random one. `sets` picks the Ingredient Set per
  colour, e.g. `%{green: 2}` (left out: Set 1). `rules` sets house rules, e.g.
  `%{explode_above: 9}` (left out: the default). `expansion: :herb_witches` turns the
  expansion on. See `Quacks.Game.new/1`. `start(players)` with the defaults is enough
  when the host sets the game up afterwards (`configure/3`).
  """
  @spec start(
          1..8,
          {integer, integer, integer} | nil,
          Quacks.Rules.Chips.sets(),
          map,
          Quacks.Rules.Chips.expansion()
        ) :: {:ok, id}
  def start(players, seed \\ nil, sets \\ %{}, rules \\ %{}, expansion \\ nil)
      when players in 1..8 do
    start_server(%{
      max_players: players,
      seed: seed || random_seed(),
      opts: [sets: sets, rules: rules, expansion: expansion],
      tokens: %{},
      names: %{},
      colours: %{},
      bots: %{},
      creator: nil
    })
  end

  # Start a game process with `fields` (see `init/1`) under a new id.
  defp start_server(fields) do
    id = new_id()

    case DynamicSupervisor.start_child(Quacks.GameSupervisor, {__MODULE__, {id, fields}}) do
      {:ok, _pid} ->
        broadcast_lobby()
        {:ok, id}

      # Two games drew the same id; try again with a new one.
      {:error, {:already_started, _pid}} ->
        start_server(fields)
    end
  end

  @doc false
  def start_link({id, _fields} = arg),
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

  @doc """
  The host (creator) sets the game up while it is `:waiting`: any of `players:`
  (1..8; not fewer than the seats taken), `sets:`, `rules:`
  and `expansion:` (keys left out keep their value). Bad values are refused as
  `Quacks.Game.new/1` would refuse them. Waiting pages hear `{:names, id, names}` and
  re-read the table.
  """
  @spec configure(id, String.t(), map) ::
          {:ok, table}
          | {:error, :not_creator | :already_started | :invalid | :not_found}
  def configure(id, token, config), do: call(id, {:configure, token, config})

  @doc """
  After the game is over, a seated browser opens the next game: a new `:waiting` game
  with the same settings, seats, names and host (a new seed). Every page hears
  `{:play_again, id, new_id}` and moves there. Asking again gives the same `new_id`.
  """
  @spec play_again(id, String.t()) ::
          {:ok, id} | {:error, :not_over | :not_seated | :not_found}
  def play_again(id, token), do: call(id, {:play_again, token})

  @doc """
  The host puts a bot with `profile` (see `Profile.all/0`) in the free
  `seat` (nil: the lowest free seat), while `:waiting`. It gets the profile's name and the next free colour.
  At most #{@max_bots} bots.
  """
  @spec add_bot(id, String.t(), Profile.name(), Game.seat() | nil) ::
          {:ok, Game.seat()}
          | {:error,
             :not_creator | :already_started | :full | :too_many_bots | :invalid | :not_found}
  def add_bot(id, token, profile, seat \\ nil), do: call(id, {:add_bot, token, profile, seat})

  @doc "The host takes the bot out of `seat`, while `:waiting`."
  @spec remove_bot(id, String.t(), Game.seat()) ::
          :ok | {:error, :not_creator | :already_started | :not_a_bot | :not_found}
  def remove_bot(id, token, seat), do: call(id, {:remove_bot, token, seat})

  @doc "Set the nickname of `seat`. A blank name goes back to \"Player N\"."
  @spec rename(id, Game.seat(), String.t()) :: :ok | {:error, :not_found}
  def rename(id, seat, name), do: call(id, {:rename, seat, name})

  @doc """
  Give `seat` the palette colour `colour` (0..7). A colour another seat has is
  refused. Pages hear `{:names, id, names}` and re-read the table.
  """
  @spec set_colour(id, Game.seat(), colour) ::
          :ok | {:error, :taken | :invalid | :not_found}
  def set_colour(id, seat, colour), do: call(id, {:set_colour, seat, colour})

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

  @doc "\"Player 1\" for seat 0: the name a seat has before anyone renames it."
  @spec default_name(Game.seat()) :: String.t()
  def default_name(seat), do: "Player #{seat + 1}"

  @doc """
  The PubSub topic of one game. Messages: `{:game, id, game}`, `{:names, id, names}`
  and `{:play_again, id, new_id}`.
  """
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

  # `fields`: `max_players`, `seed`, `opts` (the `Session.new/3` options), `tokens`
  # (a browser's player token -> its seat), `names`, `colours`, `bots` and `creator`
  # (a token). `session` is nil until begin; `next_id` is the game `play_again/2`
  # opened. `bot_rngs` holds each bot's own rng; `bot_ticks` the one pending tick per
  # bot seat (seat -> tick number, see `schedule_bots/1`), `tick` the last number.
  @impl true
  def init({id, fields}) do
    state =
      Map.merge(
        %{id: id, session: nil, next_id: nil, bots: %{}, bot_rngs: %{}, bot_ticks: %{}, tick: 0},
        fields
      )

    # Solo has nobody to wait for (a solo play-again comes with its seat taken).
    state = if state.max_players == 1 and state.tokens != %{}, do: begin_game(state), else: state
    {:ok, state, @idle_timeout}
  end

  @impl true
  def handle_call(:get, _from, state), do: {:reply, {:ok, table(state)}, state, @idle_timeout}

  def handle_call({:apply, _, _}, _from, %{session: nil} = state),
    do: {:reply, {:error, :not_started}, state, @idle_timeout}

  def handle_call({:apply, seat, action}, _from, state) do
    case Session.apply(state.session, seat, action) do
      {:ok, session} -> reply_game(schedule_bots(%{state | session: session}))
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
            colours: Map.put(state.colours, free, free_colour(state.colours, free)),
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
        state = %{
          state
          | tokens: tokens,
            names: Map.delete(state.names, seat),
            colours: Map.delete(state.colours, seat)
        }

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

  def handle_call({:configure, _token, _config}, _from, %{session: %Session{}} = state),
    do: {:reply, {:error, :already_started}, state, @idle_timeout}

  def handle_call({:configure, token, config}, _from, state) do
    max = Map.get(config, :players, state.max_players)
    opts = Keyword.merge(state.opts, Keyword.new(Map.take(config, [:sets, :rules, :expansion])))

    cond do
      token != state.creator ->
        {:reply, {:error, :not_creator}, state, @idle_timeout}

      not valid?(max, opts) or max < map_size(state.names) ->
        {:reply, {:error, :invalid}, state, @idle_timeout}

      true ->
        state = %{state | max_players: max, opts: opts}
        broadcast_names(state)
        broadcast_lobby()
        {:reply, {:ok, table(state)}, state, @idle_timeout}
    end
  end

  def handle_call({:play_again, token}, _from, state) do
    cond do
      state.session == nil or not Game.over?(state.session.game) ->
        {:reply, {:error, :not_over}, state, @idle_timeout}

      not Map.has_key?(state.tokens, token) ->
        {:reply, {:error, :not_seated}, state, @idle_timeout}

      state.next_id ->
        {:reply, {:ok, state.next_id}, state, @idle_timeout}

      true ->
        creator = if Map.has_key?(state.tokens, state.creator), do: state.creator, else: token

        {:ok, new_id} =
          start_server(%{
            max_players: state.max_players,
            seed: random_seed(),
            opts: state.opts,
            tokens: state.tokens,
            names: state.names,
            colours: state.colours,
            bots: state.bots,
            creator: creator
          })

        Phoenix.PubSub.broadcast(Quacks.PubSub, topic(state.id), {:play_again, state.id, new_id})
        {:reply, {:ok, new_id}, %{state | next_id: new_id}, @idle_timeout}
    end
  end

  def handle_call({:add_bot, token, profile, seat}, _from, state) do
    free_seats = Enum.reject(0..(state.max_players - 1), &Map.has_key?(state.names, &1))
    free = if seat, do: Enum.find(free_seats, &(&1 == seat)), else: List.first(free_seats)

    cond do
      state.session != nil ->
        {:reply, {:error, :already_started}, state, @idle_timeout}

      token != state.creator ->
        {:reply, {:error, :not_creator}, state, @idle_timeout}

      profile not in Profile.all() ->
        {:reply, {:error, :invalid}, state, @idle_timeout}

      map_size(state.bots) >= @max_bots ->
        {:reply, {:error, :too_many_bots}, state, @idle_timeout}

      free == nil ->
        {:reply, {:error, :full}, state, @idle_timeout}

      true ->
        {:reply, {:ok, free}, seat_bot(state, free, profile), @idle_timeout}
    end
  end

  def handle_call({:remove_bot, token, seat}, _from, state) do
    cond do
      state.session != nil ->
        {:reply, {:error, :already_started}, state, @idle_timeout}

      token != state.creator ->
        {:reply, {:error, :not_creator}, state, @idle_timeout}

      not Map.has_key?(state.bots, seat) ->
        {:reply, {:error, :not_a_bot}, state, @idle_timeout}

      true ->
        state = %{
          state
          | bots: Map.delete(state.bots, seat),
            names: Map.delete(state.names, seat),
            colours: Map.delete(state.colours, seat)
        }

        broadcast_names(state)
        broadcast_lobby()
        {:reply, :ok, state, @idle_timeout}
    end
  end

  def handle_call({:rename, seat, name}, _from, state) do
    name = name |> String.trim() |> String.slice(0, 20)
    name = if name == "", do: default_name(seat), else: name
    state = %{state | names: Map.put(state.names, seat, name)}
    broadcast_names(state)
    {:reply, :ok, state, @idle_timeout}
  end

  def handle_call({:set_colour, seat, colour}, _from, state) do
    cond do
      colour not in 0..7 or not Map.has_key?(state.colours, seat) ->
        {:reply, {:error, :invalid}, state, @idle_timeout}

      Enum.any?(state.colours, fn {other, c} -> c == colour and other != seat end) ->
        {:reply, {:error, :taken}, state, @idle_timeout}

      true ->
        state = %{state | colours: Map.put(state.colours, seat, colour)}
        broadcast_names(state)
        {:reply, :ok, state, @idle_timeout}
    end
  end

  # No message for @idle_timeout: nobody plays this game any more.
  @impl true
  def handle_info(:timeout, state) do
    broadcast_lobby()
    {:stop, :normal, state}
  end

  # A bot's turn to act: one action, then the next ticks. A tick that is not the
  # seat's pending one is stale.
  def handle_info({:bot, seat, tick}, %{bot_ticks: ticks} = state)
      when :erlang.map_get(seat, ticks) == tick do
    state = %{state | bot_ticks: Map.delete(ticks, seat)}
    profile = Profile.get(state.bots[seat])

    state =
      with {action, rng} <-
             AI.decide(state.session.game, seat, profile, state.bot_rngs[seat]),
           {:ok, session} <- Session.apply(state.session, seat, action) do
        game = session.game
        Phoenix.PubSub.broadcast(Quacks.PubSub, topic(state.id), {:game, state.id, game})
        %{state | session: session, bot_rngs: Map.put(state.bot_rngs, seat, rng)}
      else
        _none_or_error -> state
      end

    {:noreply, schedule_bots(state), @idle_timeout}
  end

  def handle_info({:bot, _seat, _tick}, state), do: {:noreply, state, @idle_timeout}

  # Every bot seat that can act and has no tick pending gets one.
  defp schedule_bots(%{session: nil} = state), do: state

  defp schedule_bots(state) do
    game = state.session.game
    delay = Application.get_env(:quacks, :bot_delay, 700)

    state.bots
    |> Map.keys()
    |> Enum.reject(&Map.has_key?(state.bot_ticks, &1))
    |> Enum.filter(&(Game.phase(game, &1) != :stopped and Game.legal_actions(game, &1) != []))
    |> Enum.reduce(state, fn seat, state ->
      tick = state.tick + 1
      Process.send_after(self(), {:bot, seat, tick}, delay)
      %{state | tick: tick, bot_ticks: Map.put(state.bot_ticks, seat, tick)}
    end)
  end

  # The bot with `profile` takes `seat`; a second bot of the same profile gets a number.
  defp seat_bot(state, seat, profile) do
    base = Profile.names()[profile]
    same = Enum.count(state.bots, fn {_seat, other} -> other == profile end)
    name = if same == 0, do: base, else: "#{base} #{same + 1}"

    state = %{
      state
      | bots: Map.put(state.bots, seat, profile),
        names: Map.put(state.names, seat, name),
        colours: Map.put(state.colours, seat, free_colour(state.colours, seat))
    }

    broadcast_names(state)
    broadcast_lobby()
    state
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

    bots = Map.new(state.bots, fn {seat, profile} -> {renumber[seat], profile} end)

    schedule_bots(%{
      state
      | session: Session.new(state.seed, map_size(renumber), state.opts),
        tokens: Map.new(state.tokens, fn {token, seat} -> {token, renumber[seat]} end),
        names: names,
        colours: Map.new(state.colours, fn {seat, colour} -> {renumber[seat], colour} end),
        bots: bots,
        bot_rngs: Map.new(bots, fn {seat, _} -> {seat, AI.new_rng(state.seed, seat)} end)
    })
  end

  # A new seat gets its own index as colour, or else the lowest free one.
  defp free_colour(colours, seat) do
    taken = Map.values(colours)
    if seat in taken, do: Enum.find(0..7, &(&1 not in taken)), else: seat
  end

  # The settings make a game: the player count fits and `Game.new/1` accepts them.
  defp valid?(max, opts) do
    max in 1..8 and
      match?(%Game{}, Game.new([seed: {1, 2, 3}, players: max] ++ opts))
  rescue
    ArgumentError -> false
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
      colours: state.colours,
      bots: state.bots,
      creator: state.tokens[state.creator],
      sets: state.opts[:sets],
      rules: state.opts[:rules],
      expansion: state.opts[:expansion]
    }
  end

  defp new_id do
    for <<byte <- :crypto.strong_rand_bytes(6)>>, into: "", do: <<?a + rem(byte, 26)>>
  end

  defp random_seed,
    do: {:rand.uniform(1_000_000), :rand.uniform(1_000_000), :rand.uniform(1_000_000)}
end
