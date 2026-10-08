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
  only the host may `configure/3` the game and begin it. `create/3` opens a table
  already set up (the lobby's spell book): the host in seat 0 and bots seated, and
  when no seat is left for a human it begins at once. A table is **public** (the
  default) or private: only public games show on the lobby's Join page
  (`games/1`); a private one needs its room code (the game id). The host is the creator
  while seated; when the creator leaves a waiting game, the seated browser with the
  lowest seat is host (pages hear `{:host, id, seat}`) until the creator comes back;
  with nobody left the game idles out. After the game is over, `play_again/2` opens a
  new waiting game with the same settings and the same seated browsers.

  Presence: the server watches each page (LiveView process) that claims a seat. A
  human seat with no live page is absent; after 30 s away a spectator may take it
  back with `rejoin/4` and the seat's name (a browser that lost its cookie). Pages
  hear `{:names, id, names}` when a seat comes or goes, and `{:rejoined, id, seat}`.

  Bots: while `:waiting` the host may put a bot (`Quacks.AI`, always the `:balanced`
  profile, a name from `Quacks.AI.Names`) in a free seat (`add_bot/3`) and take it out again
  (`remove_bot/3`). A bot holds a seat like a browser does. Once the game is
  `:playing`, each bot seat that can act gets a tick (`{:bot, seat, tick}`, after
  `:bot_delay` ms, 700 by default): the bot makes one action through
  `Quacks.Session`, every page hears it, and the next tick follows.

  Lockstep: in the potions phase (rounds 1–8) a bot may `:draw` only while it has
  drawn fewer times this round than the human seat that drew most. When no human
  seat still brews, the cap is off. A capped bot gets no tick; the next human
  action schedules it again.

  Decisions revealed together: in the phases where every seat decides at the same
  time (`:fortune_choice`, `:chip_choice`, `:witch_choice`, `:shopping`), a bot
  decides at once, from the state it sees when its part of the phase starts: its
  whole part (e.g. buy, rubies, `:end_round`) is planned on a private copy of the
  game (`plan/3`). While a human seat still has something to do in that phase, the
  plan waits in `queued`; it is applied (`flush/1`) right after the last human
  action of the phase, so no bot choice shows before the humans chose, and no human
  choice changes a bot's. With no human in the phase the plan goes at once. Each
  queued action is checked again when it is applied; at the first one that is no
  longer legal (a limited supply ran out), the rest is dropped and the bot decides
  again with normal ticks. The draws of the potions phase are not queued (lockstep).

  Mandrake (yellow 1) for humans: when a human seat must answer "put the white chip
  back?" (`:yellow_choice`), the server answers `:return_white` for it at once (the
  happy path). It keeps the session from before that answer (`auto_keep`) so the
  player can take it back: `keep_white/2` answers `:keep` on that session instead
  (the same as `Session.undo/1` and then `:keep`). This works only while no other
  action happened since; the next action of any seat drops `auto_keep`, and bots
  wait while it is open. Bots answer the choice themselves.

  Debug tables (`start_from_bundle/2`): a game rebuilt from a bug report's bundle
  (`Quacks.Session.bundle/1`), at some action of its log. Its bots are frozen (no
  ticks, no plans) until `set_frozen/2`; `seek/2` rebuilds it at another action.
  The table says so in `debug`.

  Games live under `Quacks.GameSupervisor`. A game that sees no message for 2 hours
  stops. Games on disk: after each change the server writes its game file
  (`Quacks.GameStore`), at most once per 500 ms (`@write_delay`), and the app
  restores every file at boot (`start_from_bundle/2` with `restore: true`), bots and
  all. The file goes when the game idles out, or 1 hour after every human seat
  closed the final scoring. Debug tables are not stored.
  """

  use GenServer, restart: :temporary

  require Logger

  alias Quacks.{AI, Game, GameStore, Session}
  alias Quacks.AI.{Names, Profile}
  alias Quacks.Game.Essence

  @idle_timeout :timer.hours(2)
  @rejoin_after_ms :timer.seconds(30)
  @max_bots 7
  @bot_profile :balanced
  @lobby_topic "lobby"
  @write_delay 500
  @finished_ttl :timer.hours(1)

  @typedoc "A short game id, 6 lowercase letters."
  @type id :: String.t()
  @typedoc """
  What a page needs about a game. `game` is `nil` while `status` is `:waiting`.
  `players` is the number of seats in the game once `:playing`, and the maximum
  (`max_players`) while `:waiting`. `creator` is the host's seat (see the moduledoc), `nil` with nobody seated.
  `sets`, `rules` and `expansion` are the options the game starts (or started) with;
  `expansions` is every expansion on (`expansion:` and `expansions:` together).
  `patients` is The Alchemists' 3 dealt patients (from the seed; nil without the
  expansion) and `patient_picks` each human seat's pick before the game (a patient
  or `:random`; empty at a table not opened by `create/3`).
  `founder` is the seat of the browser that created the table (`nil` while it is not
  seated); only its saved settings may load into a fresh table. `absent` lists the
  human seats with no open page now; `rejoinable` those away for
  `rejoin_after_ms/0` (see `rejoin/4`). `colours` is each claimed seat's colour, `0..7` (the `--color-seat-N` palette),
  unique at the table. `bots` is the profile of each seat a bot holds. `public`:
  the game shows on the lobby's Join page. `seen` is,
  per seat, the round of the fortune card (`card`), of the round results
  (`results`) and of the final scoring (`final`) that seat closed last (`ack/4`), so a reload does not show them again.
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
          seen: %{Game.seat() => %{optional(:card | :results | :final) => 1..9}},
          creator: Game.seat() | nil,
          public: boolean,
          founder: Game.seat() | nil,
          absent: [Game.seat()],
          rejoinable: [Game.seat()],
          sets: Quacks.Rules.Chips.sets(),
          rules: map,
          witches: %{optional(atom) => atom | nil},
          patients: nil | [atom],
          patient_picks: %{optional(Game.seat()) => atom},
          expansion: nil | :herb_witches,
          expansions: MapSet.t(Game.expansion()),
          debug: nil | %{at: non_neg_integer, total: non_neg_integer, frozen: boolean}
        }

  @typedoc "A seat colour: an index into the 8-colour palette (`--color-seat-N`)."
  @type colour :: 0..7

  # -- API ---------------------------------------------------------------------------

  @doc """
  Open a game for at most 1 to 8 players; it waits for
  `begin/2`. A `nil` seed picks a random one. `sets` picks the Ingredient Set per
  colour, e.g. `%{green: 2}` (left out: Set 1). `rules` sets house rules, e.g.
  `%{explode_above: 9}` (left out: the default). `expansion: :herb_witches` turns the
  expansion on; a `MapSet` (a game's `expansions`) turns each one on. See `Quacks.Game.new/1`. `start(players)` with the defaults is enough
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
      opts: [sets: sets, rules: rules] ++ expansion_opts(expansion),
      tokens: %{},
      names: %{},
      colours: %{},
      bots: %{},
      creator: nil
    })
  end

  @doc """
  Open a table set up in the lobby's spell book. `config` holds `players` (1 to 8),
  the settings `configure/3` takes (`sets`, `rules`, `expansion`, `expansions`,
  `witches`, `public`), the `name` and `colour` (0..7) of the browser with `token`,
  which takes seat 0 and is the host, and `bots`: the seats (1 and up) that get a
  bot. With no seat left for a human the game begins at once (solo, or every other
  seat a bot). With The Alchemists, `patient` is the host's patient: one of the 3
  that `seed` deals (`Quacks.Game.Essence.dealt/1`), else (or left out) `:random`.
  `{:error, :invalid}` when the settings make no game.
  """
  @spec create(map, String.t(), {integer, integer, integer} | nil) ::
          {:ok, id} | {:error, :invalid}
  def create(config, token, seed \\ nil) do
    players = Map.get(config, :players, 2)
    opts = Keyword.new(Map.take(config, [:sets, :rules, :expansion, :expansions, :witches]))

    bots =
      config
      |> Map.get(:bots, [])
      |> Enum.filter(&(is_integer(&1) and &1 in 1..(players - 1)//1))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.take(@max_bots)

    seed = seed || random_seed()
    opts = patient_opts(opts, seed, config[:patient])

    if valid?(players, opts) do
      start_server(%{
        max_players: players,
        seed: seed,
        opts: opts,
        tokens: %{token => 0},
        names: %{0 => clean_name(config[:name], 0)},
        colours: %{0 => if(config[:colour] in 0..7, do: config[:colour], else: 0)},
        bots: %{},
        creator: token,
        public: Map.get(config, :public, true) != false,
        seat_bots: bots
      })
    else
      {:error, :invalid}
    end
  end

  # The Alchemists (round 26): the host's patient (`:random` unless a dealt one).
  # The `patients:` key also marks a spell book table, whose joiners get `:random`.
  defp patient_opts(opts, seed, pick) do
    if alchemists?(opts),
      do: Keyword.put(opts, :patients, %{0 => dealt_pick(pick, seed)}),
      else: opts
  end

  defp alchemists?(opts), do: :alchemists in List.wrap(opts[:expansions])

  # `pick` when the game with `seed` deals it, else `:random`.
  defp dealt_pick(pick, seed) do
    if is_atom(pick) and pick in Essence.dealt(seed), do: pick, else: :random
  end

  # A game's `expansions` (a MapSet) or the old single `expansion`.
  defp expansion_opts(%MapSet{} = expansions), do: [expansions: MapSet.to_list(expansions)]
  defp expansion_opts(expansion), do: [expansion: expansion]

  # Start a game process with `fields` (see `init/1`) under a new id.
  defp start_server(fields) do
    case start_server(new_id(), fields) do
      {:ok, id} -> {:ok, id}
      # Two games drew the same id; try again with a new one.
      {:error, :already_started} -> start_server(fields)
    end
  end

  defp start_server(id, fields) do
    case DynamicSupervisor.start_child(Quacks.GameSupervisor, {__MODULE__, {id, fields}}) do
      {:ok, _pid} ->
        broadcast_lobby()
        {:ok, id}

      {:error, {:already_started, _pid}} ->
        {:error, :already_started}
    end
  end

  @doc """
  A `:playing` table rebuilt from a bug report's `bundle` (see
  `Quacks.Session.bundle/1`; atom or string keys), for debugging. Options: `at:`
  replays only the first `at` actions (default: all), `token:` and `seat:` give that
  seat to the browser with `token` (the other human seats stay unclaimed). The
  bundle's `names` and `bots` (when present) name the seats and seat the bots.
  Bots start frozen (see the moduledoc), unless `frozen: false`.

  `restore: true` instead brings back a stored game from its game file (the
  bundle plus `"table"`, see `Quacks.GameStore`): the same id, seats, tokens,
  names, settings and `seen`, waiting or playing, not a debug table; its bots play
  on. `dir:` is where it keeps its file (default: `Quacks.GameStore.dir/0`).
  `{:error, :already_started}` when a game with that id runs.
  """
  @spec start_from_bundle(map, keyword) ::
          {:ok, id} | {:error, :invalid | :already_started}
  def start_from_bundle(bundle, opts \\ []) do
    bundle = bundle |> Jason.encode!() |> Jason.decode!()
    if opts[:restore], do: restore(bundle, opts), else: start_debug(bundle, opts)
  end

  defp start_debug(bundle, opts) do
    total = length(bundle["log"] || [])
    at = opts |> Keyword.get(:at, total) |> max(0) |> min(total)

    with {:ok, session} <- Session.from_bundle(bundle, at) do
      seats = 0..(session.players - 1)
      bots = Map.new(Enum.filter(bundle["bots"] || [], &(&1 in seats)), &{&1, @bot_profile})
      names = bundle["names"] || []
      token = opts[:token]

      start_server(%{
        max_players: session.players,
        seed: session.seed,
        opts: [
          sets: session.sets,
          rules: session.rules,
          expansions: Enum.to_list(session.expansions),
          witches: session.witches
        ],
        tokens: if(token && opts[:seat] in seats, do: %{token => opts[:seat]}, else: %{}),
        names: Map.new(seats, &{&1, Enum.at(names, &1) || default_name(&1)}),
        colours: Map.new(seats, &{&1, &1}),
        bots: bots,
        bot_rngs: Map.new(bots, fn {seat, _} -> {seat, AI.new_rng(session.seed, seat)} end),
        creator: token,
        public: false,
        session: session,
        store: nil,
        debug: %{bundle: bundle, at: at, total: total, frozen: Keyword.get(opts, :frozen, true)}
      })
    end
  end

  # A game file back as a running game (see `start_from_bundle/2`).
  defp restore(%{"table" => t} = bundle, opts) do
    session =
      case t["status"] do
        "playing" -> with {:ok, session} <- Session.from_bundle(bundle), do: session
        "waiting" -> nil
      end

    pairs = fn key, decode -> Map.new(t[key] || [], fn [seat, v] -> {seat, decode.(v)} end) end
    bots = pairs.("bots", &String.to_existing_atom/1)
    rngs = pairs.("bot_rngs", &restore_rng/1)
    seed = List.to_tuple(t["seed"])

    fields = %{
      max_players: t["max_players"],
      seed: seed,
      opts: Session.decode_opts(t["opts"]),
      tokens: t["tokens"],
      names: pairs.("names", & &1),
      colours: pairs.("colours", & &1),
      bots: bots,
      bot_rngs: Map.new(bots, fn {seat, _} -> {seat, rngs[seat] || AI.new_rng(seed, seat)} end),
      seen: pairs.("seen", &decode_seen/1),
      creator: t["creator"],
      public: Map.get(t, "public", true) != false,
      next_id: t["next_id"],
      session: session,
      store: Keyword.get_lazy(opts, :dir, &GameStore.dir/0)
    }

    case session do
      {:error, _} = error -> error
      _ -> start_server(t["id"], fields)
    end
  rescue
    _error in [MatchError, ArgumentError, FunctionClauseError, CaseClauseError, KeyError] ->
      {:error, :invalid}
  end

  defp restore(_bundle, _opts), do: {:error, :invalid}

  defp decode_seen(kinds) do
    for {kind, round} <- kinds, kind in ~w(card results final), into: %{} do
      {String.to_existing_atom(kind), round}
    end
  end

  # A bot's rng as `[s0, s1]`, the state `:rand.export_seed_s/1` gives.
  defp restore_rng([s0, s1]), do: :rand.seed_s({:exsss, [s0 | s1]})

  defp export_rng(rng) do
    {:exsss, [s0 | s1]} = :rand.export_seed_s(rng)
    [s0, s1]
  end

  @doc """
  Rebuild a debug table at action `at` of its bundle (clamped to the log). Bots
  keep their frozen flag; queued plans and pending ticks are dropped.
  """
  @spec seek(id, integer) :: {:ok, Game.t()} | {:error, :not_debug | :not_found}
  def seek(id, at), do: call(id, {:seek, at})

  @doc "Freeze (`true`) or unfreeze the bots of a debug table."
  @spec set_frozen(id, boolean) :: :ok | {:error, :not_debug | :not_found}
  def set_frozen(id, frozen?), do: call(id, {:set_frozen, frozen?})

  @doc """
  The game as a bug report's bundle: `Quacks.Session.bundle/1` plus the seat
  `names` (a list by seat) and the `bots` seats. `{:error, :not_started}` while
  `:waiting`.
  """
  @spec bundle(id) :: {:ok, map} | {:error, :not_started | :not_found}
  def bundle(id), do: call(id, :bundle)

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
  def apply(id, seat, action), do: call(id, {:apply, seat, action, System.monotonic_time()})

  @doc """
  Mandrake: `seat` keeps the white chip that the server put back in its bag
  (see the moduledoc). Only right after that automatic answer, before any other
  action; else `{:error, :too_late}`.
  """
  @spec keep_white(id, Game.seat()) ::
          {:ok, Game.t()} | {:error, :too_late | :not_started | :not_found}
  def keep_white(id, seat), do: call(id, {:keep_white, seat})

  @doc "Take back the last action. Solo games only."
  @spec undo(id) :: {:ok, Game.t()} | {:error, :not_solo | :not_started | :not_found}
  def undo(id), do: call(id, :undo)

  @doc """
  The seat of the browser with `token`. While `:waiting`, a new token gets the lowest
  free seat (so the creator is seat 0); when every seat is taken, or the game has
  begun, it is a spectator. The calling process is watched as the seat's page
  (see `rejoin/4`), unless `watch: false` (a LiveView's disconnected render: its
  HTTP process outlives the page).
  """
  @spec claim_seat(id, String.t(), keyword) ::
          {:ok, Game.seat()} | {:error, :full | :not_found}
  def claim_seat(id, token, opts \\ []),
    do: call(id, {:claim_seat, token, Keyword.get(opts, :watch, true)})

  @doc """
  Give the human `seat` to the browser with `token`, when no page holds that seat
  now (its browser lost the cookie, or changed browser). The old token loses the
  seat. Every `claim_seat/2` and `rejoin/4` watches the calling page (a LiveView);
  a seat is present while one of its pages lives (`absent` in the table).
  """
  @spec rejoin(id, String.t(), Game.seat(), String.t()) ::
          {:ok, Game.seat()} | {:error, :seated | :present | :name | :invalid | :not_found}
  def rejoin(id, token, seat, name), do: call(id, {:rejoin, token, seat, name})

  @doc """
  How long (ms) a seat must have had no page before `rejoin/4` may take it: a player
  who only reloads, or is online in another browser, keeps the seat. There is no
  identity check beyond the typed name (see docs/CONTEXT.md, "Rejoin").
  """
  def rejoin_after_ms, do: @rejoin_after_ms

  @doc """
  Free the seat of `token` while the game is `:waiting` (its page closed). Does
  nothing once the game has begun.
  """
  @spec leave_seat(id, String.t()) :: :ok | {:error, :not_found}
  def leave_seat(id, token), do: call(id, {:leave_seat, token})

  @doc """
  Start the game with the seats taken now. Only the host may (see the moduledoc).
  Broadcasts the new game and the renumbered names.
  """
  @spec begin(id, String.t()) ::
          {:ok, Game.t()} | {:error, :not_creator | :not_seated | :already_started | :not_found}
  def begin(id, token), do: call(id, {:begin, token})

  @doc """
  The host (creator) sets the game up while it is `:waiting`: any of `players:`
  (1..8; not fewer than the seats taken), `sets:`, `rules:`, `witches:` (the herb
  witch picks, `%{copper: :c3, silver: nil, gold: nil}`; nil: dealt),
  `expansion:` and `expansions:` (a list of `:herb_witches`, `:alchemists`; keys left
  out keep their value). Bad values are refused as
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
  The Alchemists (round 26): `seat`'s patient before the game, one of the 3 the
  table's seed deals (the table's `patients`) or `:random`, while `:waiting`. Only
  at a spell book table (`create/3`) and only for a human seat.
  """
  @spec pick_patient(id, Game.seat(), atom) ::
          :ok | {:error, :invalid | :already_started | :not_found}
  def pick_patient(id, seat, pick), do: call(id, {:pick_patient, seat, pick})

  @doc """
  The waiting panel's "Fill with bots" (host only): a bot in every free seat, and
  the game begins at once. Replies like `begin/2`.
  """
  @spec fill_bots(id, String.t()) ::
          {:ok, Game.t()} | {:error, :not_creator | :already_started | :not_found}
  def fill_bots(id, token), do: call(id, {:fill_bots, token})

  @doc """
  The host puts a bot (profile `:balanced`) in the free `seat` (nil: the lowest free
  seat), while `:waiting`. Each bot gets a name from `Quacks.AI.Names` that is not at
  the table yet (picked with the table's rng) and the next free colour. At most
  #{@max_bots} bots.
  """
  @spec add_bot(id, String.t(), Game.seat() | nil) ::
          {:ok, Game.seat()}
          | {:error, :not_creator | :already_started | :full | :too_many_bots | :not_found}
  def add_bot(id, token, seat \\ nil), do: call(id, {:add_bot, token, seat})

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

  @doc """
  `seat` closed the fortune card (`:card`), the round results (`:results`) or the
  final scoring (`:final`, round 9) of `round` (the reveal overlay). The table
  keeps it (`seen`), so a reload does not open them again.
  """
  @spec ack(id, Game.seat(), :card | :results | :final, 1..9) :: :ok | {:error, :not_found}
  def ack(id, seat, kind, round)
      when kind in [:card, :results, :final] and is_integer(round),
      do: call(id, {:ack, seat, kind, round})

  @doc "Public games on this node that are still `:waiting` with a free seat, sorted by id."
  @spec open_games() :: [table]
  def open_games do
    game_ids()
    |> Enum.flat_map(fn id ->
      case get(id) do
        {:ok, table} -> [table]
        {:error, :not_found} -> []
      end
    end)
    |> Enum.filter(&(&1.public and open?(&1)))
    |> Enum.sort_by(& &1.id)
  end

  @doc """
  The games of the lobby's Join page: every game on this node, waiting or playing,
  that is public or has a seat for `token`; not over, not a debug table. Each table
  has `mine` added: the seat of `token`, or nil. Yours come first, then by id.
  """
  @spec games(String.t() | nil) :: [map]
  def games(token) do
    game_ids()
    |> Enum.flat_map(fn id ->
      case call(id, {:listing, token}) do
        {:ok, table} -> [table]
        {:error, :not_found} -> []
      end
    end)
    |> Enum.filter(&listed?/1)
    |> Enum.sort_by(&{&1.mine == nil, &1.id})
  end

  defp listed?(%{debug: %{}}), do: false

  defp listed?(%{game: %Game{} = game} = t),
    do: (t.public or t.mine != nil) and not Game.over?(game)

  defp listed?(t), do: t.public or t.mine != nil

  defp game_ids, do: Registry.select(Quacks.GameRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])

  @doc "\"Player 1\" for seat 0: the name a seat has before anyone renames it."
  @spec default_name(Game.seat()) :: String.t()
  def default_name(seat), do: "Player #{seat + 1}"

  @doc """
  The PubSub topic of one game. Messages: `{:game, id, game}`, `{:names, id, names}`,
  `{:host, id, seat}` and `{:play_again, id, new_id}`.
  """
  @spec topic(id) :: String.t()
  def topic(id), do: "game:" <> id

  @doc "The PubSub topic the lobby listens on: `:games_changed` when seats or games change."
  @spec lobby_topic() :: String.t()
  def lobby_topic, do: @lobby_topic

  defp open?(t), do: t.status == :waiting and map_size(t.names) < t.max_players

  # A game that just stopped can still be in the Registry for a moment, or stop
  # during the call, hence the catch.
  defp call(id, msg) do
    case Registry.lookup(Quacks.GameRegistry, id) do
      [{pid, _}] -> GenServer.call(pid, msg)
      [] -> {:error, :not_found}
    end
  catch
    :exit, {reason, _} when reason in [:noproc, :normal, :shutdown, :killed] ->
      {:error, :not_found}
  end

  # -- server ------------------------------------------------------------------------

  # `fields`: `max_players`, `seed`, `opts` (the `Session.new/3` options), `tokens`
  # (a browser's player token -> its seat), `names`, `colours`, `bots` and `creator`
  # (a token). `session` is nil until begin; `next_id` is the game `play_again/2`
  # opened. `name_rng` picks bot names (`Quacks.AI.Names`). `bot_rngs` holds each
  # bot's own rng; `pages` each watched page (pid -> its token, see `watch/3`);
  # `bot_ticks` the one pending tick per
  # bot seat (seat -> tick number, see `schedule_bots/1`), `tick` the last number.
  # `queued` holds each bot's planned actions of a concurrent phase (seat -> actions,
  # see `plan/3`); `auto_keep` is `{seat, session}` right after the server answered a
  # human's Mandrake choice (the session from before it), else nil.
  # `store` is the directory of the game file (nil: not stored, see `stored/2`);
  # `write_timer` the pending debounced write, `expire_timer` the pending delete of
  # a finished game's file.
  @impl true
  def init({id, fields}) do
    # So a deploy's shutdown runs `terminate/2`, which writes a pending change.
    Process.flag(:trap_exit, true)

    state =
      Map.merge(
        %{
          id: id,
          session: nil,
          next_id: nil,
          bots: %{},
          bot_rngs: %{},
          bot_ticks: %{},
          queued: %{},
          auto_keep: nil,
          seen: %{},
          pages: %{},
          away: %{},
          tick: 0,
          debug: nil,
          public: true,
          store: GameStore.dir(),
          write_timer: nil,
          expire_timer: nil,
          name_rng: :rand.seed_s(:exsss, fields.seed)
        },
        fields
      )

    # A spell book table seats its bots now (`create/3`).
    {seat_bots, state} = Map.pop(state, :seat_bots)
    state = Enum.reduce(seat_bots || [], state, &seat_bot(&2, &1))

    # Solo has nobody to wait for (a solo play-again comes with its seat taken), nor
    # has a spell book table with every seat taken.
    full? = seat_bots != nil and map_size(state.names) == state.max_players

    state =
      if (state.max_players == 1 or full?) and state.tokens != %{} and state.session == nil,
        do: begin_game(state),
        else: state

    # A restored game's bots play on (a frozen debug table's do not).
    state = if state.session, do: schedule_bots(state), else: state
    {:ok, state |> schedule_write() |> schedule_expiry(), @idle_timeout}
  end

  # Every message goes through `stored/2`: a change to what the game file holds
  # schedules one write.
  @impl true
  def handle_call(msg, from, state), do: msg |> server_call(from, state) |> stored(state)

  @impl true
  def handle_info({:write, ref}, %{write_timer: ref} = state) when is_reference(ref),
    do: {:noreply, write_file(state), @idle_timeout}

  def handle_info({:write, _stale}, state), do: {:noreply, state, @idle_timeout}

  # A finished game everyone has seen: its file goes (the game stays until it idles).
  def handle_info(:expire, state) do
    GameStore.delete(state.store, state.id)
    {:noreply, %{state | store: nil, write_timer: nil}, @idle_timeout}
  end

  def handle_info(msg, state), do: msg |> server_info(state) |> stored(state)

  # A shutdown (a deploy) with a write pending: write it now.
  @impl true
  def terminate(_reason, %{write_timer: ref} = state) when is_reference(ref),
    do: write_file(state)

  def terminate(_reason, _state), do: :ok

  defp server_call(:get, _from, state), do: {:reply, {:ok, table(state)}, state, @idle_timeout}

  defp server_call({:listing, token}, _from, state),
    do: {:reply, {:ok, Map.put(table(state), :mine, state.tokens[token])}, state, @idle_timeout}

  defp server_call(:bundle, _from, %{session: nil} = state),
    do: {:reply, {:error, :not_started}, state, @idle_timeout}

  defp server_call(:bundle, _from, state),
    do: {:reply, {:ok, bundle_of(state)}, state, @idle_timeout}

  defp server_call({:seek, _at}, _from, %{debug: nil} = state),
    do: {:reply, {:error, :not_debug}, state, @idle_timeout}

  defp server_call({:seek, at}, _from, %{debug: debug} = state) do
    at = at |> max(0) |> min(debug.total)
    {:ok, session} = Session.from_bundle(debug.bundle, at)

    state = %{
      state
      | session: session,
        debug: %{debug | at: at},
        bot_ticks: %{},
        queued: %{},
        auto_keep: nil
    }

    reply_game(schedule_bots(state))
  end

  defp server_call({:set_frozen, _frozen?}, _from, %{debug: nil} = state),
    do: {:reply, {:error, :not_debug}, state, @idle_timeout}

  defp server_call({:set_frozen, frozen?}, _from, state) do
    state = %{state | debug: %{state.debug | frozen: frozen?}}
    state = if frozen?, do: %{state | bot_ticks: %{}, queued: %{}}, else: acted(state)
    broadcast(state, {:game, state.id, state.session.game})
    {:reply, :ok, state, @idle_timeout}
  end

  defp server_call({:apply, _, _, _}, _from, %{session: nil} = state),
    do: {:reply, {:error, :not_started}, state, @idle_timeout}

  defp server_call({:apply, seat, action, sent}, _from, state) do
    {engine_us, result} = :timer.tc(Session, :apply, [state.session, seat, action])

    reply =
      case result do
        {:ok, session} -> reply_game(acted(%{state | session: session}))
        error -> {:reply, error, state, @idle_timeout}
      end

    log_action(state.id, seat, action, elem(result, 0), engine_us, sent)
    reply
  end

  defp server_call({:keep_white, _seat}, _from, %{session: nil} = state),
    do: {:reply, {:error, :not_started}, state, @idle_timeout}

  defp server_call({:keep_white, seat}, _from, %{auto_keep: {seat, before}} = state) do
    {:ok, session} = Session.apply(before, seat, :keep)
    reply_game(acted(%{state | session: session}))
  end

  defp server_call({:keep_white, _seat}, _from, state),
    do: {:reply, {:error, :too_late}, state, @idle_timeout}

  defp server_call(:undo, _from, %{session: nil} = state),
    do: {:reply, {:error, :not_started}, state, @idle_timeout}

  # Undo after the server's Mandrake answer shows the question again.
  defp server_call(:undo, _from, %{session: %{players: 1}} = state),
    do: reply_game(%{state | session: Session.undo(state.session), auto_keep: nil})

  defp server_call(:undo, _from, state), do: {:reply, {:error, :not_solo}, state, @idle_timeout}

  defp server_call({:claim_seat, token, watch?}, {pid, _tag}, state) do
    watch = fn state -> if watch?, do: watch(state, pid, token), else: state end
    free = Enum.find(0..(state.max_players - 1), &(not Map.has_key?(state.names, &1)))

    cond do
      Map.has_key?(state.tokens, token) ->
        {:reply, {:ok, state.tokens[token]}, watch.(state), @idle_timeout}

      state.session == nil and free != nil ->
        # Watched before the seat is taken: the names broadcast below says it all.
        state = watch.(state)

        state = %{
          state
          | tokens: Map.put(state.tokens, token, free),
            names: Map.put(state.names, free, default_name(free)),
            colours: Map.put(state.colours, free, free_colour(state.colours, free)),
            creator: state.creator || token
        }

        state = put_pick(state, free, :random)

        # Solo has nobody to wait for: the game begins with its only seat.
        state = if state.max_players == 1, do: begin_game(state), else: state
        state = mark_away(state)
        broadcast_names(state)
        broadcast_lobby()
        {:reply, {:ok, free}, state, @idle_timeout}

      true ->
        {:reply, {:error, :full}, state, @idle_timeout}
    end
  end

  defp server_call({:rejoin, token, seat, name}, {pid, _tag}, state) do
    old = Enum.find_value(state.tokens, fn {t, s} -> if s == seat, do: t end)

    cond do
      Map.has_key?(state.tokens, token) ->
        {:reply, {:error, :seated}, state, @idle_timeout}

      old == nil ->
        {:reply, {:error, :invalid}, state, @idle_timeout}

      seat not in rejoinable(state) ->
        {:reply, {:error, :present}, state, @idle_timeout}

      not same_name?(name, Map.get(state.names, seat, default_name(seat))) ->
        {:reply, {:error, :name}, state, @idle_timeout}

      true ->
        state = %{
          state
          | tokens: state.tokens |> Map.delete(old) |> Map.put(token, seat),
            creator: if(state.creator == old, do: token, else: state.creator)
        }

        state = watch(state, pid, token)
        broadcast(state, {:rejoined, state.id, seat})
        {:reply, {:ok, seat}, state, @idle_timeout}
    end
  end

  defp server_call({:leave_seat, token}, _from, %{session: nil} = state) do
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

        state = drop_pick(state, seat)

        if token == host(%{state | tokens: Map.put(tokens, token, seat)}) and host(state),
          do: broadcast(state, {:host, state.id, tokens[host(state)]})

        broadcast_names(state)
        broadcast_lobby()
        {:reply, :ok, state, @idle_timeout}
    end
  end

  defp server_call({:leave_seat, _token}, _from, state), do: {:reply, :ok, state, @idle_timeout}

  defp server_call({:ack, seat, kind, round}, _from, state) do
    seen = Map.update(state.seen, seat, %{kind => round}, &Map.put(&1, kind, round))
    {:reply, :ok, %{state | seen: seen}, @idle_timeout}
  end

  defp server_call({:begin, _token}, _from, %{session: %Session{}} = state),
    do: {:reply, {:error, :already_started}, state, @idle_timeout}

  defp server_call({:begin, token}, _from, state) do
    cond do
      not Map.has_key?(state.tokens, token) ->
        {:reply, {:error, :not_seated}, state, @idle_timeout}

      token != host(state) ->
        {:reply, {:error, :not_creator}, state, @idle_timeout}

      true ->
        state = begin_game(state)
        broadcast_names(state)
        broadcast_lobby()
        reply_game(state)
    end
  end

  defp server_call({:configure, _token, _config}, _from, %{session: %Session{}} = state),
    do: {:reply, {:error, :already_started}, state, @idle_timeout}

  defp server_call({:configure, token, config}, _from, state) do
    max = Map.get(config, :players, state.max_players)

    opts =
      Keyword.merge(
        state.opts,
        Keyword.new(Map.take(config, [:sets, :rules, :expansion, :expansions, :witches]))
      )

    cond do
      token != host(state) ->
        {:reply, {:error, :not_creator}, state, @idle_timeout}

      not valid?(max, opts) or max < map_size(state.names) ->
        {:reply, {:error, :invalid}, state, @idle_timeout}

      true ->
        public = if is_boolean(config[:public]), do: config[:public], else: state.public
        state = %{state | max_players: max, opts: opts, public: public}
        broadcast_names(state)
        broadcast_lobby()
        {:reply, {:ok, table(state)}, state, @idle_timeout}
    end
  end

  defp server_call({:play_again, token}, _from, state) do
    cond do
      state.session == nil or not Game.over?(state.session.game) ->
        {:reply, {:error, :not_over}, state, @idle_timeout}

      not Map.has_key?(state.tokens, token) ->
        {:reply, {:error, :not_seated}, state, @idle_timeout}

      state.next_id ->
        {:reply, {:ok, state.next_id}, state, @idle_timeout}

      true ->
        creator = host(state) || token

        {:ok, new_id} =
          start_server(%{
            max_players: state.max_players,
            seed: random_seed(),
            opts: again_picks(state),
            tokens: state.tokens,
            names: state.names,
            colours: state.colours,
            bots: state.bots,
            creator: creator,
            public: state.public,
            store: state.store
          })

        Phoenix.PubSub.broadcast(Quacks.PubSub, topic(state.id), {:play_again, state.id, new_id})
        {:reply, {:ok, new_id}, %{state | next_id: new_id}, @idle_timeout}
    end
  end

  defp server_call({:pick_patient, _seat, _pick}, _from, %{session: %Session{}} = state),
    do: {:reply, {:error, :already_started}, state, @idle_timeout}

  defp server_call({:pick_patient, seat, pick}, _from, state) do
    cond do
      not Keyword.has_key?(state.opts, :patients) or not alchemists?(state.opts) ->
        {:reply, {:error, :invalid}, state, @idle_timeout}

      not Map.has_key?(state.names, seat) or Map.has_key?(state.bots, seat) ->
        {:reply, {:error, :invalid}, state, @idle_timeout}

      pick != :random and pick not in Essence.dealt(state.seed) ->
        {:reply, {:error, :invalid}, state, @idle_timeout}

      true ->
        state = put_pick(state, seat, pick)
        broadcast_names(state)
        {:reply, :ok, state, @idle_timeout}
    end
  end

  defp server_call({:fill_bots, token}, _from, %{session: nil} = state) do
    free = Enum.reject(0..(state.max_players - 1), &Map.has_key?(state.names, &1))

    if token == host(state) do
      state = state |> then(&Enum.reduce(free, &1, fn seat, st -> seat_bot(st, seat) end))
      state = begin_game(state)
      broadcast_names(state)
      broadcast_lobby()
      reply_game(state)
    else
      {:reply, {:error, :not_creator}, state, @idle_timeout}
    end
  end

  defp server_call({:fill_bots, _token}, _from, state),
    do: {:reply, {:error, :already_started}, state, @idle_timeout}

  defp server_call({:add_bot, token, seat}, _from, state) do
    free_seats = Enum.reject(0..(state.max_players - 1), &Map.has_key?(state.names, &1))
    free = if seat, do: Enum.find(free_seats, &(&1 == seat)), else: List.first(free_seats)

    cond do
      state.session != nil ->
        {:reply, {:error, :already_started}, state, @idle_timeout}

      token != host(state) ->
        {:reply, {:error, :not_creator}, state, @idle_timeout}

      map_size(state.bots) >= @max_bots ->
        {:reply, {:error, :too_many_bots}, state, @idle_timeout}

      free == nil ->
        {:reply, {:error, :full}, state, @idle_timeout}

      true ->
        {:reply, {:ok, free}, seat_bot(state, free), @idle_timeout}
    end
  end

  defp server_call({:remove_bot, token, seat}, _from, state) do
    cond do
      state.session != nil ->
        {:reply, {:error, :already_started}, state, @idle_timeout}

      token != host(state) ->
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

  defp server_call({:rename, seat, name}, _from, state) do
    name = clean_name(name, seat)
    state = %{state | names: Map.put(state.names, seat, name)}
    broadcast_names(state)
    {:reply, :ok, state, @idle_timeout}
  end

  defp server_call({:set_colour, seat, colour}, _from, state) do
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
  defp server_info(:timeout, state) do
    GameStore.delete(state.store, state.id)
    broadcast_lobby()
    {:stop, :normal, state}
  end

  # A bot's turn to act: one action, then the next ticks. A tick that is not the
  # seat's pending one is stale; a capped bot (a human resumed) waits; in a concurrent
  # phase where a human decides, the bot plans instead (`schedule_bots/1`).
  defp server_info({:bot, seat, tick}, %{bot_ticks: ticks} = state)
       when :erlang.map_get(seat, ticks) == tick do
    started = System.monotonic_time()
    state = %{state | bot_ticks: Map.delete(ticks, seat)}
    profile = Profile.get(state.bots[seat])

    state =
      with false <- capped?(state, state.session.game, seat),
           false <- humans_deciding?(state, state.session.game),
           nil <- state.auto_keep,
           {action, rng} <-
             AI.decide(state.session.game, seat, profile, state.bot_rngs[seat]),
           {engine_us, {:ok, session}} <-
             :timer.tc(Session, :apply, [state.session, seat, action]) do
        state = acted(%{state | session: session, bot_rngs: Map.put(state.bot_rngs, seat, rng)})
        broadcast(state, {:game, state.id, state.session.game})
        log_action(state.id, seat, {:bot, action}, :ok, engine_us, started)
        state
      else
        _none_or_error -> schedule_bots(state)
      end

    {:noreply, state, @idle_timeout}
  end

  defp server_info({:bot, _seat, _tick}, state), do: {:noreply, state, @idle_timeout}

  # A watched page closed: its seat may now be absent.
  defp server_info({:DOWN, _ref, :process, pid, _reason}, state) do
    before = absent(state)
    state = mark_away(%{state | pages: Map.delete(state.pages, pid)})
    if absent(state) != before, do: broadcast_names(state)
    {:noreply, state, @idle_timeout}
  end

  # A seat has been away long enough to be taken back: the pages offer it now.
  defp server_info(:away_tick, state) do
    broadcast_names(state)
    {:noreply, state, @idle_timeout}
  end

  # Watch the page `pid` of `token` (once per page); a seat that comes back is news.
  defp watch(%{pages: pages} = state, pid, _token) when is_map_key(pages, pid), do: state

  defp watch(state, pid, token) do
    Process.monitor(pid)
    before = absent(state)
    state = mark_away(%{state | pages: Map.put(state.pages, pid, token)})
    if absent(state) != before, do: broadcast_names(state)
    state
  end

  # When each absent seat lost its last page (`away`, monotonic ms); a seat that just
  # went away is offered for rejoin after `@rejoin_after_ms` (`:away_tick`).
  defp mark_away(state) do
    now = System.monotonic_time(:millisecond)

    away =
      Map.new(absent(state), fn seat ->
        case state.away do
          %{^seat => since} ->
            {seat, since}

          _ ->
            Process.send_after(self(), :away_tick, @rejoin_after_ms + 100)
            {seat, now}
        end
      end)

    %{state | away: away}
  end

  # The absent seats a spectator may take back (away for `@rejoin_after_ms`).
  defp rejoinable(state) do
    now = System.monotonic_time(:millisecond)
    away = Map.new(absent(state), &{&1, Map.get(state.away, &1, now)})
    for {seat, since} <- away, now - since >= @rejoin_after_ms, do: seat
  end

  defp same_name?(typed, name) when is_binary(typed),
    do: String.downcase(String.trim(typed)) == String.downcase(String.trim(name))

  defp same_name?(_typed, _name), do: false

  # The seats of browsers with no live page, in seat order. Bots have no page.
  defp absent(state) do
    present = state.pages |> Map.values() |> MapSet.new()
    for({token, seat} <- state.tokens, token not in present, do: seat) |> Enum.sort()
  end

  # After any applied action: the server's Mandrake answers, the queued bot plans,
  # then the bot ticks.
  defp acted(state), do: state |> auto_return() |> flush() |> schedule_bots()

  # Every human seat in the Mandrake choice gets `:return_white` (see the moduledoc);
  # `auto_keep` keeps the session from before it, for `keep_white/2`. Any other action
  # drops it.
  defp auto_return(state) do
    humans = state.session.game.seats -- Map.keys(state.bots)

    Enum.reduce(humans, %{state | auto_keep: nil}, fn seat, state ->
      if Game.phase(state.session.game, seat) == :yellow_choice do
        {:ok, session} = Session.apply(state.session, seat, :return_white)
        %{state | session: session, auto_keep: {seat, state.session}}
      else
        state
      end
    end)
  end

  # The phases where every seat decides at the same time; bots queue their plans.
  @concurrent [:fortune_choice, :chip_choice, :witch_choice, :shopping]

  # Some human seat still has something to do in this concurrent phase.
  defp humans_deciding?(state, %Game{phase: phase} = game) when phase in @concurrent,
    do: Enum.any?(game.seats -- Map.keys(state.bots), &(Game.legal_actions(game, &1) != []))

  defp humans_deciding?(_state, _game), do: false

  # Once no human decides any more, every queued plan is applied, seat by seat. An
  # action that is no longer legal drops the rest of that plan (the bot decides
  # again with ticks).
  defp flush(%{queued: queued} = state) when map_size(queued) == 0, do: state

  defp flush(state) do
    if humans_deciding?(state, state.session.game) do
      state
    else
      state.queued
      |> Enum.sort()
      |> Enum.reduce(%{state | queued: %{}}, &apply_plan/2)
      |> flush_again()
    end
  end

  defp apply_plan({seat, actions}, state) do
    Enum.reduce_while(actions, state, fn action, state ->
      case Session.apply(state.session, seat, action) do
        {:ok, session} -> {:cont, %{state | session: session}}
        {:error, _} -> {:halt, state}
      end
    end)
  end

  # A flushed plan can end the phase and start the next concurrent one at once.
  defp flush_again(state), do: if(state.queued == %{}, do: state, else: flush(state))

  # A bot's whole part of a concurrent phase, decided now on a private copy of the
  # game: one decision after the other while the bot still acts in the phase.
  defp plan(state, seat) do
    profile = Profile.get(state.bots[seat])
    game = state.session.game

    Enum.reduce_while(1..30, {game, [], state.bot_rngs[seat]}, fn _, {g, actions, rng} ->
      with true <- g.phase == game.phase,
           {action, rng} <- AI.decide(g, seat, profile, rng),
           {:ok, g} <- Game.apply(g, seat, action) do
        {:cont, {g, [action | actions], rng}}
      else
        _done -> {:halt, {g, actions, rng}}
      end
    end)
    |> then(fn {_g, actions, rng} ->
      %{
        state
        | queued: Map.put(state.queued, seat, Enum.reverse(actions)),
          bot_rngs: Map.put(state.bot_rngs, seat, rng)
      }
    end)
  end

  # Every bot seat that can act, is not capped and has no tick pending gets one. In
  # a concurrent phase where a human still decides, a bot plans instead (no tick).
  # While a human's Mandrake answer can be taken back, bots wait.
  defp schedule_bots(%{session: nil} = state), do: state
  defp schedule_bots(%{debug: %{frozen: true}} = state), do: state
  defp schedule_bots(%{auto_keep: {_seat, _before}} = state), do: state

  defp schedule_bots(state) do
    game = state.session.game
    delay = Application.get_env(:quacks, :bot_delay, 700)
    deciding? = humans_deciding?(state, game)

    state.bots
    |> Map.keys()
    |> Enum.reject(&(Map.has_key?(state.bot_ticks, &1) or Map.has_key?(state.queued, &1)))
    |> Enum.filter(&(Game.phase(game, &1) != :stopped and Game.legal_actions(game, &1) != []))
    |> Enum.reject(&capped?(state, game, &1))
    |> Enum.reduce(state, fn
      seat, state when deciding? ->
        plan(state, seat)

      seat, state ->
        tick = state.tick + 1
        Process.send_after(self(), {:bot, seat, tick}, delay)
        %{state | tick: tick, bot_ticks: Map.put(state.bot_ticks, seat, tick)}
    end)
  end

  # Lockstep (see the moduledoc): may the bot at `seat` not draw now? Round 9 has
  # its own lockstep (stir), so no cap there.
  defp capped?(state, %Game{phase: :potions, round: round} = game, seat) when round < 9 do
    humans = game.seats -- Map.keys(state.bots)
    draws = round_draws(game)

    :draw in Game.legal_actions(game, seat) and
      Enum.any?(humans, &brewing?(Game.player(game, &1))) and
      Map.get(draws, seat, 0) >= humans |> Enum.map(&Map.get(draws, &1, 0)) |> Enum.max()
  end

  defp capped?(_state, _game, _seat), do: false

  defp brewing?(%{phase: phase}),
    do:
      phase in [:potions, :yellow_choice, :blue_choice, :red_choice, :chip_choice, :essence_offer]

  # `:draw` actions per seat in this round's log (newest first, up to the last round end).
  defp round_draws(game) do
    game.log
    |> Enum.take_while(&(not match?({:round_end, _}, &1)))
    |> Enum.frequencies_by(fn
      {seat, :draw} -> seat
      _other -> nil
    end)
  end

  # Play again: a solo game has no waiting panel, so its patient is chosen in the
  # game; at a table every human seat starts at "Random" again (a new seed deals
  # new patients).
  defp again_picks(%{opts: opts, max_players: 1}), do: Keyword.delete(opts, :patients)

  defp again_picks(%{opts: opts} = state) do
    if Keyword.has_key?(opts, :patients) do
      humans = Map.values(state.tokens)
      Keyword.put(opts, :patients, Map.new(humans, &{&1, :random}))
    else
      opts
    end
  end

  # A bot takes `seat`, with a name nobody at the table has.
  defp seat_bot(state, seat) do
    {name, name_rng} = Names.pick(Map.values(state.names), state.name_rng)

    state = %{
      state
      | name_rng: name_rng,
        bots: Map.put(state.bots, seat, @bot_profile),
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
    opts = renumber_picks(state, renumber)

    schedule_bots(%{
      state
      | opts: opts,
        session: Session.new(state.seed, map_size(renumber), opts),
        tokens: Map.new(state.tokens, fn {token, seat} -> {token, renumber[seat]} end),
        names: names,
        colours: Map.new(state.colours, fn {seat, colour} -> {renumber[seat], colour} end),
        bots: bots,
        bot_rngs: Map.new(bots, fn {seat, _} -> {seat, AI.new_rng(state.seed, seat)} end)
    })
  end

  # The patient picks of a spell book table (round 26; no `patients:` key: none).
  defp put_pick(%{opts: opts} = state, seat, pick) do
    if Keyword.has_key?(opts, :patients),
      do: %{state | opts: Keyword.update!(opts, :patients, &Map.put(&1, seat, pick))},
      else: state
  end

  defp drop_pick(%{opts: opts} = state, seat) do
    if Keyword.has_key?(opts, :patients),
      do: %{state | opts: Keyword.update!(opts, :patients, &Map.delete(&1, seat))},
      else: state
  end

  # The picks of the seated humans, on their new seats; a patient the seed does not
  # deal becomes `:random`.
  defp renumber_picks(%{opts: opts} = state, renumber) do
    case opts[:patients] do
      picks when is_map(picks) and map_size(picks) > 0 ->
        picks =
          for {seat, pick} <- picks,
              Map.has_key?(renumber, seat) and not Map.has_key?(state.bots, seat),
              into: %{},
              do: {renumber[seat], dealt_pick(pick, state.seed)}

        if alchemists?(opts), do: Keyword.put(opts, :patients, picks), else: opts

      _none ->
        opts
    end
  end

  # A typed name: trimmed, at most 20 letters; empty is the seat's default name.
  defp clean_name(name, seat) when is_binary(name) do
    case name |> String.trim() |> String.slice(0, 20) do
      "" -> default_name(seat)
      name -> name
    end
  end

  defp clean_name(_name, seat), do: default_name(seat)

  # A new seat gets its own index as colour, or else the lowest free one.
  defp free_colour(colours, seat) do
    taken = Map.values(colours)
    if seat in taken, do: Enum.find(0..7, &(&1 not in taken)), else: seat
  end

  # The settings make a game: the player count fits and `Game.new/1` accepts them.
  # The patient picks are left out: they depend on the table's own seed.
  defp valid?(max, opts) do
    max in 1..8 and
      match?(
        %Game{},
        Game.new([seed: {1, 2, 3}, players: max] ++ Keyword.delete(opts, :patients))
      )
  rescue
    ArgumentError -> false
  end

  defp reply_game(state) do
    game = state.session.game
    Phoenix.PubSub.broadcast(Quacks.PubSub, topic(state.id), {:game, state.id, game})
    {:reply, {:ok, game}, state, @idle_timeout}
  end

  # The host's token: the creator while seated, else the seated browser with the
  # lowest seat (nil: nobody). A creator who comes back (a reload) is host again.
  defp host(%{tokens: tokens, creator: creator}) when is_map_key(tokens, creator), do: creator

  defp host(%{tokens: tokens}) do
    case Enum.min_by(tokens, fn {_token, seat} -> seat end, fn -> nil end) do
      {token, _seat} -> token
      nil -> nil
    end
  end

  defp broadcast(state, message),
    do: Phoenix.PubSub.broadcast(Quacks.PubSub, topic(state.id), message)

  defp broadcast_names(state),
    do: Phoenix.PubSub.broadcast(Quacks.PubSub, topic(state.id), {:names, state.id, state.names})

  defp broadcast_lobby, do: Phoenix.PubSub.broadcast(Quacks.PubSub, @lobby_topic, :games_changed)

  # -- timing (round 28) ---------------------------------------------------------------

  # One line per applied action: `fly logs -a quacks | grep "action "`. `engine` is
  # the time in `Session.apply/3` (the engine), `total` the time since the browser's
  # process sent the call (the wait in this mailbox, the engine, the bots' plans and
  # the broadcast). A bot's move counts from its tick. Slow ones (`@slow_ms`) log at
  # `:info`, the rest at `:debug`.
  @slow_ms 50
  defp log_action(id, seat, action, result, engine_us, started) do
    total_ms =
      System.convert_time_unit(System.monotonic_time() - started, :native, :microsecond) / 1000

    level = if total_ms >= @slow_ms, do: :info, else: :debug

    Logger.log(level, fn ->
      "action game=#{id} seat=#{seat} action=#{action_name(action)} result=#{result} " <>
        "engine_ms=#{Float.round(engine_us / 1000, 2)} total_ms=#{Float.round(total_ms, 2)}"
    end)
  end

  defp action_name({:bot, action}), do: "bot:" <> action_name(action)
  defp action_name(action) when is_atom(action), do: Atom.to_string(action)
  defp action_name(action) when is_tuple(action), do: action |> elem(0) |> action_name()
  defp action_name(_action), do: "other"

  # -- the game file ------------------------------------------------------------------

  defp stored({:reply, reply, state, timeout}, old),
    do: {:reply, reply, changed(state, old), timeout}

  defp stored({:noreply, state, timeout}, old), do: {:noreply, changed(state, old), timeout}
  defp stored(stop, _old), do: stop

  defp changed(state, old) do
    # The Join page shows each game's round.
    if stage(state) != stage(old), do: broadcast_lobby()

    if file_view(state) == file_view(old),
      do: state,
      else: state |> schedule_write() |> schedule_expiry()
  end

  defp stage(%{session: %Session{game: game}}), do: {game.round, Game.over?(game)}
  defp stage(_state), do: nil

  # What the game file holds; a change to it is worth a write.
  @file_fields [:max_players, :seed, :opts, :tokens, :names, :colours, :bots, :seen] ++
                 [:creator, :next_id, :public]
  defp file_view(state),
    do: {state.session && state.session.actions, Map.take(state, @file_fields)}

  # One pending write at a time (the debounce): changes within `@write_delay` of
  # the first one go out together.
  defp schedule_write(%{store: nil} = state), do: state
  defp schedule_write(%{debug: %{}} = state), do: state
  defp schedule_write(%{write_timer: ref} = state) when is_reference(ref), do: state

  defp schedule_write(state) do
    ref = make_ref()
    Process.send_after(self(), {:write, ref}, @write_delay)
    %{state | write_timer: ref}
  end

  defp write_file(state) do
    GameStore.write(state.store, state.id, file_body(state))
    %{state | write_timer: nil}
  end

  # A finished game whose human seats have all closed the final scoring: its file
  # goes after `@finished_ttl`. Until then a reload (or a restart) shows the podium.
  defp schedule_expiry(%{store: dir, expire_timer: nil, session: %Session{} = s} = state)
       when dir != nil do
    humans = s.game.seats -- Map.keys(state.bots)

    if Game.over?(s.game) and Enum.all?(humans, &get_in(state.seen, [&1, :final])) do
      %{state | expire_timer: Process.send_after(self(), :expire, @finished_ttl)}
    else
      state
    end
  end

  defp schedule_expiry(state), do: state

  # The bundle (absent while waiting) plus the table; `restore/2` reads it back.
  defp file_body(state) do
    base = if state.session, do: bundle_of(state), else: %{}

    Map.put(base, :table, %{
      id: state.id,
      status: if(state.session, do: "playing", else: "waiting"),
      max_players: state.max_players,
      seed: Tuple.to_list(state.seed),
      opts: Session.encode_opts(state.opts),
      tokens: state.tokens,
      names: pairs(state.names),
      colours: pairs(state.colours),
      bots: pairs(state.bots),
      bot_rngs:
        state.bot_rngs |> Map.new(fn {seat, rng} -> {seat, export_rng(rng)} end) |> pairs(),
      seen: pairs(state.seen),
      creator: state.creator,
      next_id: state.next_id,
      public: state.public
    })
  end

  # A map with integer keys as `[[key, value], ...]` (JSON keys are strings).
  defp pairs(map), do: map |> Enum.sort() |> Enum.map(fn {key, value} -> [key, value] end)

  defp bundle_of(state) do
    Map.merge(Session.bundle(state.session), %{
      names: Enum.map(0..(state.session.players - 1), &Map.get(state.names, &1)),
      bots: state.bots |> Map.keys() |> Enum.sort()
    })
  end

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
      seen: state.seen,
      creator: state.tokens[host(state)],
      founder: state.tokens[state.creator],
      public: state.public,
      absent: absent(state),
      rejoinable: rejoinable(state) |> Enum.sort(),
      sets: state.opts[:sets],
      rules: state.opts[:rules],
      witches: state.opts[:witches] || %{},
      patients: if(alchemists?(state.opts), do: Essence.dealt(state.seed)),
      patient_picks: state.opts[:patients] || %{},
      expansion: state.opts[:expansion],
      expansions:
        MapSet.new(
          List.wrap(state.opts[:expansion]) ++ Enum.to_list(state.opts[:expansions] || [])
        ),
      debug: state.debug && Map.take(state.debug, [:at, :total, :frozen])
    }
  end

  defp new_id do
    for <<byte <- :crypto.strong_rand_bytes(6)>>, into: "", do: <<?a + rem(byte, 26)>>
  end

  defp random_seed,
    do: {:rand.uniform(1_000_000), :rand.uniform(1_000_000), :rand.uniform(1_000_000)}
end
