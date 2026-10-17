defmodule Codex.Table do
  @moduledoc """
  The Codex sandbox in a `Table.Server` room: the adapter from the server's
  callbacks to `Codex.Game`.

  Hot-seat (the default): one browser plays both sides, so the room has one
  seat and no bots; a second browser watches. Against the bot (`opts.bot`):
  two seats, P2 is the bot, one action per tick. Bot levels: `:search` (the
  default, `Codex.Bot.Search`, at most #{400} ms of search per turn), `:plan`
  (the stage-1 bot, `Codex.Bot.Plan`) and `:basic` (the first bot,
  `Codex.Bot`).
  """
  @behaviour Table.Server

  alias Codex.Bot.{Plan, Search}
  alias Codex.Game

  @impl true
  def new(opts, seed), do: Game.new(opts, seed)

  @impl true
  def seats(%Game{} = game), do: Game.table_seats(game)

  @impl true
  def legal_actions(game, seat), do: Game.legal_actions(game, seat)

  @impl true
  def apply(game, seat, action), do: Game.apply(game, seat, action)

  @impl true
  def winners(%Game{winner: nil}), do: []
  def winners(%Game{winner: winner}), do: [winner]

  @impl true
  def status(game), do: Game.status(game)

  @impl true
  def view(game, seat), do: Game.view(game, seat)

  @impl true
  def bot_levels, do: [:search, :plan, :basic]

  @impl true
  def bot_new(:search, seed), do: Search.new(seed: :erlang.phash2(seed), budget_ms: 400)
  def bot_new(:plan, _seed), do: Plan.new()
  def bot_new(_level, _seed), do: nil

  @impl true
  def bot_choose(:search, view, bot), do: Search.choose(view, bot)
  def bot_choose(:plan, view, bot), do: Plan.choose(view, bot)
  def bot_choose(:basic, view, bot), do: Codex.Bot.choose(view, bot)

  # A short pause per bot action, so the page shows each one.
  @impl true
  def bot_delay(_game), do: 650
end
