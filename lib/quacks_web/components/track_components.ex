defmodule QuacksWeb.TrackComponents do
  @moduledoc """
  The score and rat track (rat_track/1): each seat's VP on the scoring track and
  its rat tails, with the labels placed so they do not overlap.
  """
  use Phoenix.Component

  alias Quacks.{Game, Player}
  alias Quacks.Rules.ScoringTrack

  import QuacksWeb.ChipComponents
  import QuacksWeb.Icons

  # Round 41: the labels' room on the narrowest track (a 360 px phone: 328 px
  # between the insets, less a margin), a 13 px digit and the space between labels.
  @track_px 320

  @digit_px 8

  @label_gap_px 3

  # A label's centre and half width in px on the narrowest track.
  defp label_box(x, shift, vp),
    do: {x * @track_px + shift * 7, length(Integer.digits(vp)) * @digit_px / 2}

  defp clear?({c, half}, {c2, half2}), do: abs(c - c2) >= half + half2 + @label_gap_px

  # From the leader's side: each label above the line when it does not touch the
  # label before it above, else below; when both touch, the side with more room.
  defp place_vp_labels(labels) do
    labels
    |> Enum.map_reduce({nil, nil}, fn l, {above, below} ->
      box = label_box(l.x, l.shift, l.vp)

      below? =
        cond do
          above == nil or clear?(box, above) -> false
          below == nil or clear?(box, below) -> true
          true -> gap(box, below) > gap(box, above)
        end

      l = Map.put(l, :below, below?)
      {l, if(below?, do: {above, box}, else: {box, below})}
    end)
    |> elem(0)
  end

  defp gap({c, half}, {c2, half2}), do: abs(c - c2) - half - half2

  # Round 35: a rat keeps its VP only in a small gap (1 or 2 rats) between two
  # neighbouring seats. Round 41: and only when it does not repeat a seat's VP and
  # its number does not touch a VP below the line or the rat VP before it.
  defp label_rats(rats, dots, vp_labels) do
    seat_vps = MapSet.new(dots, & &1.vp)
    below = for l <- vp_labels, l.below, do: label_box(l.x, l.shift, l.vp)

    big_gaps =
      dots
      |> Enum.map(& &1.step)
      |> Enum.uniq()
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.filter(fn [a, b] -> b - a >= 3 end)

    rats
    |> Enum.map_reduce(nil, fn rat, last ->
      box = label_box(rat.x, 0, rat.vp)

      show? =
        not Enum.any?(big_gaps, fn [a, b] -> a <= rat.j and rat.j < b end) and
          rat.vp not in seat_vps and
          Enum.all?(below, &clear?(box, &1)) and
          (last == nil or clear?(box, last))

      {Map.put(rat, :show_vp, show?), if(show?, do: box, else: last)}
    end)
    |> elem(0)
  end

  @doc """
  The pot spaces of a player's rat pebbles: the spaces after the droplet, at most
  `rat_stone` of them, and never past `mods.rat_end` (the stone's space). Before the first draw
  the start follows the droplet (`Game.move_droplet/3`); after it the rats stay put,
  so a droplet move takes the first rat's space and that rat goes (round 35).
  """
  @spec rat_spaces(Player.t()) :: [non_neg_integer]
  def rat_spaces(%Player{rat_stone: 0}), do: []

  def rat_spaces(%Player{droplet: droplet, rat_stone: n, mods: mods, drawn: drawn}) do
    rat_end = mods[:rat_end]

    last = if drawn == [] or is_nil(rat_end), do: droplet + n, else: min(droplet + n, rat_end)
    Enum.to_list((droplet + 1)..last//1)
  end

  @doc """
  The rat track (round 16; equal steps since round 22): a slim strip between the
  name cards and the pot. Not to scale: one step per rat tail
  (`ScoringTrack.tails_between/2`, on every lap) between the last player and the leader, the leader on
  the left. Every seat's dot sits in the step of its rats
  (`ScoringTrack.rat_tails/2`: the leader's step has none, each tail to the right
  adds one); seats in one step stack. Under each rat tail its VP. Since round 28
  every seat's VP sits by its dot (`track-vp`, the leader's `leader-vp`): one
  number for seats in a step with the same VP, above the line or, when it would
  touch the number before it, below. Since round 35 a rat shows its VP only in a
  gap of 1 or 2 rats between neighbouring seats; since round 41 only when it is
  not a seat's VP and touches no other number. A fixed height; nothing to tap.
  """
  attr :game, :map, required: true
  attr :seat, :any, default: nil, doc: "this browser's seat, nil for a spectator"
  attr :names, :map, required: true
  attr :class, :any, default: nil

  attr :vps, :any,
    default: nil,
    doc: "`%{seat => vp}` in place of the seats' VP (the evaluation on the tiles)"

  def rat_track(assigns) do
    game = assigns.game
    vps = for s <- game.seats, do: {s, (assigns.vps || %{})[s] || Game.player(game, s).vp}
    {low, leader} = vps |> Enum.map(&elem(&1, 1)) |> Enum.min_max()

    # The tails from the leader's side: a seat behind tail `t` (VP <= t) gets its rat.
    tails = low |> ScoringTrack.tails_between(leader) |> Enum.reverse()
    steps = length(tails) + 1

    dots =
      vps
      |> Enum.map(fn {s, vp} -> {s, vp, ScoringTrack.rat_tails(vp, leader)} end)
      |> Enum.sort_by(fn {s, vp, step} -> {step, -vp, s} end)
      |> Enum.chunk_by(&elem(&1, 2))
      |> Enum.flat_map(fn same ->
        for {{s, vp, step}, i} <- Enum.with_index(same),
            do: %{
              seat: s,
              vp: vp,
              step: step,
              bg: seat_bg(s),
              x: (step + 0.5) / steps,
              shift: i - (length(same) - 1) / 2
            }
      end)

    rats = for {t, j} <- Enum.with_index(tails), do: %{vp: t, x: (j + 1) / steps, j: j}

    # Round 28: every seat's VP by its dot. Seats in one step with the same VP share
    # one number. A number goes above the line, or below it when it would touch the
    # number before it above (round 41: also across neighbouring steps).
    vp_labels =
      dots
      |> Enum.chunk_by(& &1.step)
      |> Enum.flat_map(fn same ->
        same
        |> Enum.chunk_by(& &1.vp)
        |> Enum.map(fn group ->
          %{
            vp: hd(group).vp,
            x: hd(group).x,
            shift: Enum.sum(Enum.map(group, & &1.shift)) / length(group),
            leader: hd(group).vp == leader,
            seats: Enum.map(group, & &1.seat)
          }
        end)
      end)
      |> place_vp_labels()

    rats = label_rats(rats, dots, vp_labels)

    label =
      Enum.map_join(vps, "; ", fn {s, vp} ->
        n = ScoringTrack.rat_tails(vp, leader)

        "#{Map.get(assigns.names, s, "Player #{s + 1}")} #{vp} VP, #{n} #{if n == 1, do: "rat", else: "rats"}"
      end)

    assigns =
      assign(assigns,
        dots: dots,
        rats: rats,
        vp_labels: vp_labels,
        steps: steps,
        leader: leader,
        label: label
      )

    ~H"""
    <div
      id="rat-track"
      class={["relative h-8 select-none", @class]}
      role="img"
      aria-label={"Rat track, leader first: " <> @label}
      data-role="rat-track"
      data-steps={@steps}
    >
      <span
        class="absolute top-3.5 h-px rounded-full bg-parchment/35"
        style={"left: #{pos(0.5 / @steps)}; right: #{pos(0.5 / @steps)}"}
      />
      <span
        :for={rat <- @rats}
        class="absolute top-3.5 flex -translate-x-1/2 -translate-y-1/2 flex-col items-center text-parchment-dim"
        style={"left: #{pos(rat.x)}"}
        data-role="track-rat"
        data-vp={rat.vp}
      >
        <.piece_icon name={:rat} class="size-3" />
        <span
          :if={rat.show_vp}
          class="absolute top-full text-tag leading-none font-semibold tabular-nums"
        >
          {rat.vp}
        </span>
      </span>
      <span
        :for={dot <- @dots}
        class="absolute top-3.5 -translate-x-1/2 -translate-y-1/2 transition-[left] duration-500 ease-out motion-reduce:transition-none"
        style={"left: calc(#{pos(dot.x)} + #{dot.shift * 7}px)"}
        title={"#{Map.get(@names, dot.seat, "Player #{dot.seat + 1}")}: #{dot.vp} VP"}
        data-role="track-dot"
        data-seat={dot.seat}
        data-vp={dot.vp}
        data-step={dot.step}
      >
        <span class={[
          "block rounded-full",
          dot.bg,
          if(dot.seat == @seat,
            do: "size-3 ring-2 ring-parchment/80",
            else: "size-2.5 ring-1 ring-black/40"
          )
        ]} />
      </span>
      <span
        :for={l <- @vp_labels}
        class={[
          "absolute top-3.5 -translate-x-1/2 text-tag leading-none font-bold tabular-nums transition-[left] duration-500 ease-out motion-reduce:transition-none",
          if(l.below, do: "translate-y-[0.4rem]", else: "-translate-y-[calc(100%+0.4rem)]"),
          if(l.leader, do: "text-parchment-light", else: "text-parchment")
        ]}
        style={"left: calc(#{pos(l.x)} + #{Float.round(l.shift * 7.0, 2)}px)"}
        aria-hidden="true"
        data-role={if l.leader, do: "leader-vp", else: "track-vp"}
        data-vp={l.vp}
        data-seats={Enum.join(l.seats, " ")}
        data-below={l.below && "true"}
      >
        {l.vp}
      </span>
    </div>
    """
  end

  # A position on the track, 0..1, as a CSS length inside an 0.5rem inset.
  defp pos(x), do: "calc(0.5rem + (100% - 1rem) * #{Float.round(x * 1.0, 4)})"
end
