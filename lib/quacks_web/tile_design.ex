defmodule QuacksWeb.TileDesign do
  @moduledoc """
  The tile redesign study (gallery only, `/dev/gallery/tiles/redesign`): the facts
  that a player tile can show for one seat, in one map, so the three design options
  of `QuacksWeb.TileDesignComponents` draw the same data. Not used by the game page.
  """

  alias Quacks.{Game, Player}
  alias Quacks.Game.Potions
  alias Quacks.Rules.{Alchemists, PotTrack}
  alias QuacksWeb.TileComponents

  @typedoc "One seat's tile facts, see `facts/3`."
  @type facts :: %{atom => term}

  @doc """
  The tile facts of `seat`. `opts`: `name`, `you`, `bot`, `news` (a
  `QuacksWeb.TileReveal.news/3` map or nil).

  Keys: identity (`seat`, `name`, `initial`, `you`, `bot`, `lead` (the crown),
  `start` (the start player of this round)), `state` (`TileComponents.seat_state/2`)
  and `brewing` (the round brews), the score (`vp`), the pot (`index`, `coins`,
  `segments`: one `{chip, from, to}` per pot chip, oldest first,
  `draws`: the pot chips, newest first, `white`, `limit`, `level` safe | warn |
  danger), the pieces (`rubies`, `droplet`, `flask`, `black` with `show_black`,
  `rats` (nil when the rats rule is off), `essence` and `patient` (nil without The
  Alchemists), `pennies` (nil without The Herb Witches), `tube` (nil unless the
  reverse pot side)) and `news`.
  """
  @spec facts(Game.t(), Game.seat(), keyword) :: facts
  def facts(%Game{} = game, seat, opts) do
    p = game.players[seat]
    name = opts[:name] || "Player #{seat + 1}"
    index = Player.scoring_index(p)
    white = Game.white_sum(game, seat)
    limit = Potions.explode_above(game, seat)

    %{
      seat: seat,
      name: name,
      initial: initial(name),
      you: opts[:you] || false,
      bot: opts[:bot] || false,
      lead: seat in TileComponents.round_leaders(game),
      start: length(game.seats) > 1 and Game.start_seat(game) == seat,
      state: TileComponents.seat_state(game, seat),
      brewing: game.phase == :potions,
      exploded: p.exploded?,
      vp: p.vp,
      index: index,
      coins: PotTrack.at(index).coins,
      segments: segments(p),
      draws: Player.pot_chips(p),
      white: white,
      limit: limit,
      level: level(p, white, limit),
      rubies: p.rubies,
      droplet: p.droplet,
      flask: p.flask,
      news: opts[:news]
    }
    |> Map.merge(pieces(game, p))
  end

  # The black chips in the pot, and the pieces of the expansions and house rules
  # (nil while off).
  defp pieces(game, p) do
    %{
      black: Enum.count(Player.pot_chips(p), &match?({:black, _}, &1)),
      show_black: TileComponents.black_counts?(game),
      rats: if(game.rules.rats, do: p.rat_stone),
      essence: if(Game.expansion?(game, :alchemists), do: p.essence),
      patient: p.patient && %{id: p.patient, name: Alchemists.get(p.patient).name},
      pennies: if(game.witches, do: Enum.filter([:copper, :silver, :gold], &p.pennies[&1])),
      tube: if(game.rules.pot_side == :back, do: p.tube)
    }
  end

  # One segment per pot chip: from the space before it (the droplet for the first)
  # to its own space, oldest first.
  defp segments(%Player{drawn: drawn, droplet: droplet}) do
    {segments, _last} =
      drawn
      |> Enum.reverse()
      |> Enum.map_reduce(droplet, fn {chip, space}, from -> {{chip, from, space}, space} end)

    segments
  end

  # As the live tile (`TileComponents`): amber one point before the limit, red at it
  # or after an explosion.
  defp level(%Player{exploded?: true}, _white, _limit), do: "danger"
  defp level(_p, white, limit) when white >= limit, do: "danger"
  defp level(_p, white, limit) when white == limit - 1, do: "warn"
  defp level(_p, _white, _limit), do: "safe"

  defp initial(name),
    do: name |> String.trim() |> String.first() |> Kernel.||("?") |> String.upcase()

  @doc """
  The race's scale (option C): the furthest pot at the table plus 3 spaces, at least
  20 and at most the last space a chip can cover (52), so the leader is near the end.
  """
  @spec race_scale([facts]) :: pos_integer
  def race_scale(facts) do
    furthest = facts |> Enum.map(& &1.index) |> Enum.max(fn -> 0 end)
    furthest |> Kernel.+(3) |> max(20) |> min(PotTrack.last_chip())
  end

  @doc "Space `space` on a race of `scale` spaces as a CSS percent."
  @spec percent(integer, pos_integer) :: String.t()
  def percent(space, scale), do: "#{Float.round(min(max(space, 0), scale) * 100 / scale, 2)}%"
end
