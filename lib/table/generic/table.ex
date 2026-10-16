defmodule Table.Generic.Table do
  @moduledoc """
  A generic card game in a `Table.Server` room: the adapter from the server's
  callbacks to `Table.Generic.Game`. The room's `opts` are `%{spec: name,
  players: n}`; the spec's referee runs the rules (`Table.Generic.Referee.for/1`).

  The bot (`:random`) plays a random card when it can play one, else a random
  choice. It has its own rng.
  """
  @behaviour Table.Server

  alias Table.Generic.Game
  alias Table.Kit.Rng

  @impl true
  def new(opts, seed), do: Game.new(Map.take(opts, [:spec, :players]), seed)

  @impl true
  def seats(%Game{seats: seats}), do: seats

  @impl true
  def legal_actions(game, seat), do: Game.legal_actions(game, seat)

  @impl true
  def apply(game, seat, action), do: Game.apply(game, seat, action)

  @impl true
  def status(game), do: Game.status(game)

  @impl true
  def view(game, seat), do: Game.view(game, seat)

  @impl true
  def bot_levels, do: [:random]

  @impl true
  def bot_new(:random, seed), do: Rng.seed(seed)

  @impl true
  def bot_choose(:random, %{legal_actions: [_ | _] = actions}, rng) do
    plays = for {:play, _, _} = a <- actions, do: a
    Rng.pick(if(plays == [], do: actions, else: plays), rng)
  end

  @impl true
  def bot_delay(_game), do: 900
end
