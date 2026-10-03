defmodule QuacksWeb.AlchemistsComponents do
  @moduledoc """
  The Alchemists on the page (`docs/research/alchemists-essences.md` §5.8): the flask
  strip with the patient badge, the patient card and its 10 glass slots, the patient
  choice and the essence choice. Rendering only; `QuacksWeb.GameLive` passes the
  encoded actions in.
  """
  use Phoenix.Component

  import QuacksWeb.CoreComponents, only: [icon: 1]
  import QuacksWeb.GameComponents, only: [chip_name: 1, seat_colour: 1]

  alias Quacks.Game
  alias Quacks.Rules.Alchemists

  # Patients whose essence pays for actions in the next preparation phase.
  @spenders [:carrot_nose, :wing_ears, :witch_hump, :forgetfulness]

  @doc """
  The alchemist's flask of `seat`: 11 beads (spaces 0–10) in the seat colour, the
  essence marker a big bead with its number. `:lg` (above your pot) starts with the
  patient badge, a button for `#sheet-patient`; `:sm` (a player card) names the
  patient above the beads. While the essence pays for actions this round, the
  marker wears a gold ring.
  """
  attr :game, Game, required: true
  attr :seat, :integer, required: true
  attr :size, :atom, default: :lg, values: [:lg, :sm]

  def flask_strip(assigns) do
    p = assigns.game.players[assigns.seat]

    assigns =
      assign(assigns,
        p: p,
        patient: Alchemists.get(p.patient),
        spendable: spendable?(assigns.game, p)
      )

    ~H"""
    <div
      class={["flex min-w-0 items-center gap-2", @size == :lg && "h-10"]}
      style={"--bead: #{seat_colour(@seat)}"}
      data-role="flask-strip"
      data-essence={@p.essence}
      data-spendable={@spendable && "true"}
    >
      <button
        :if={@size == :lg}
        type="button"
        popovertarget="sheet-patient"
        aria-label={"Patient: #{@patient.name}"}
        data-role="patient-badge"
        class={[
          "inline-flex h-9 max-w-[8.5rem] shrink-0 items-center gap-1.5 rounded-full pr-3 pl-1",
          "bg-iron-dark text-xs font-semibold text-parchment ring-1 ring-iron touch-manipulation",
          "transition-transform duration-150 ease-out active:scale-[0.96]"
        ]}
      >
        <span class="grid size-7 shrink-0 place-items-center rounded-full bg-(--bead) text-ink">
          <.icon name="hero-beaker" class="size-4" />
        </span>
        <span class="truncate">{@patient.name}</span>
      </button>
      <div class="min-w-0 flex-1">
        <p :if={@size == :sm} class="text-xs font-semibold text-ink-soft">
          {@patient.name} · essence {@p.essence}
        </p>
        <ol
          class="grid grid-cols-11 items-center"
          aria-label={"Essence #{@p.essence} of 10"}
        >
          <li
            :for={space <- 0..10}
            class="flex justify-center"
            aria-current={space == @p.essence && "step"}
          >
            <span class={bead_class(space, @p.essence, @size, @spendable)}>
              {if space == @p.essence, do: space}
            </span>
          </li>
        </ol>
      </div>
    </div>
    """
  end

  # A passed bead is the seat colour, faded; the marker is solid with its number;
  # the beads ahead are empty glass.
  defp bead_class(space, marker, size, spendable) do
    [
      "grid shrink-0 place-items-center rounded-full font-bold tabular-nums",
      "transition-[background-color,scale] duration-200 ease-out",
      cond do
        space == marker and size == :lg -> "size-7 bg-(--bead) text-sm text-ink shadow"
        space == marker -> "size-5 bg-(--bead) text-[10px] text-ink"
        space < marker -> "size-2.5 bg-(--bead) opacity-60"
        size == :lg -> "size-2.5 bg-parchment/15 ring-1 ring-parchment/25"
        true -> "size-2 bg-ink/15"
      end,
      (space == marker and spendable) && "ring-2 ring-gold ring-offset-1 ring-offset-iron-dark"
    ]
  end

  # The essence pays for actions now: a spending patient, essence left, brewing.
  defp spendable?(%{phase: :potions}, %{patient: patient, essence: essence}),
    do: patient in @spenders and essence > 0

  defp spendable?(_game, _p), do: false

  @doc """
  A patient card: name, German name, text, and the 10 glass slots in a 5×2 grid.
  `reached` rings that slot (the essence marker's space).
  """
  attr :id, :atom, required: true, doc: "a `Quacks.Rules.Alchemists` patient id"
  attr :reached, :integer, default: nil

  def patient_card(assigns) do
    assigns = assign(assigns, patient: Alchemists.get(assigns.id))

    ~H"""
    <div class="space-y-2" data-role="patient-card" data-patient={@id}>
      <div class="flex items-baseline gap-2">
        <h3 class="font-hand text-xl font-bold">{@patient.name}</h3>
        <span class="text-xs text-ink-soft italic">{@patient.de}</span>
      </div>
      <p class="text-sm leading-snug text-pretty">{@patient.text}</p>
      <.slot_grid id={@id} reached={@reached} />
    </div>
    """
  end

  @doc "The 10 glass slots of patient `id`, 5 per row; `reached` has a ring."
  attr :id, :atom, required: true
  attr :reached, :integer, default: nil

  def slot_grid(assigns) do
    assigns = assign(assigns, slots: Alchemists.get(assigns.id).slots)

    ~H"""
    <ol class="grid grid-cols-5 gap-1" aria-label="Essence glasses" data-role="slot-grid">
      <li
        :for={space <- 1..10}
        class={[
          "flex min-h-11 flex-col rounded-md px-1 py-0.5 text-[11px] leading-tight",
          if(space == @reached,
            do: "bg-gold/30 ring-2 ring-ink",
            else: "bg-ink/8 ring-1 ring-ink/10 ring-inset"
          )
        ]}
        data-space={space}
        data-reached={space == @reached && "true"}
      >
        <span class="font-bold tabular-nums text-ink-soft">{space}</span>
        <span class="font-semibold">{slot_text(@slots[space])}</span>
      </li>
    </ol>
    """
  end

  @doc """
  The patient choice (game phase `:patient_choice`): the 3 dealt patients as cards;
  a tap sends that patient's encoded action. `picks` is `[{id, encoded}]`.
  """
  attr :picks, :list, required: true

  def patient_picks(assigns) do
    ~H"""
    <section class="space-y-3" data-role="patient-choice">
      <h2 class="text-xl font-bold">Choose your patient</h2>
      <p class="text-sm text-ink-soft">
        Your essence each round pays the glass under the marker. Tap a patient to take it.
      </p>
      <ul class="grid gap-2.5">
        <li :for={{id, encoded} <- @picks}>
          <button
            type="button"
            phx-click="action"
            phx-value-action={encoded}
            data-role="patient-pick"
            data-patient={id}
            class={[
              "w-full cursor-pointer rounded-[14px] bg-parchment-light p-3 text-left text-ink",
              "shadow-sm ring-1 ring-ink/20 touch-manipulation",
              "transition-[scale,box-shadow] duration-150 ease-out hover:ring-2 hover:ring-ink/50",
              "active:scale-[0.98] focus-visible:outline-3 focus-visible:outline-droplet"
            ]}
          >
            <.patient_card id={id} />
          </button>
        </li>
      </ul>
    </section>
    """
  end

  @doc """
  The essence choice (player phase `:essence_choice`): the reached space and how it
  was counted, the slot of the picked space, a stepper down to space 0 and "Take".
  `parts` is the `{:essence, reach, parts}` log entry's map (nil when not found).
  """
  attr :patient, :atom, required: true
  attr :reach, :integer, required: true
  attr :pick, :integer, required: true
  attr :parts, :map, default: nil
  attr :take, :string, required: true, doc: "the encoded `{:essence, {:space, pick}}`"

  def essence_choice(assigns) do
    assigns = assign(assigns, glass: Alchemists.slot(assigns.patient, assigns.pick))

    ~H"""
    <section class="space-y-3" data-role="essence-choice">
      <h2 class="text-xl font-bold">Essence: space {@reach}</h2>
      <ul :if={@parts} class="flex flex-wrap gap-1.5 text-xs" data-role="essence-parts">
        <li :for={part <- parts_text(@parts)} class="rounded-full bg-ink/10 px-2 py-0.5 font-semibold">
          {part}
        </li>
      </ul>
      <p class="text-sm text-ink-soft">
        You may take a lower space when its glass suits you better.
      </p>
      <div class="flex items-center gap-3" data-role="essence-stepper">
        <button
          type="button"
          phx-click="essence_pick"
          phx-value-space={@pick - 1}
          disabled={@pick <= 0}
          aria-label="Lower space"
          class="grid size-11 cursor-pointer place-items-center rounded-full bg-ink/10 text-xl font-bold transition-transform duration-100 ease-out active:scale-90 disabled:cursor-not-allowed disabled:opacity-35"
        >
          −
        </button>
        <div class="min-w-0 flex-1 text-center">
          <p class="text-2xl font-bold tabular-nums" data-role="essence-pick">Space {@pick}</p>
          <p class="text-sm font-semibold">{glass_text(@glass)}</p>
        </div>
        <button
          type="button"
          phx-click="essence_pick"
          phx-value-space={@pick + 1}
          disabled={@pick >= @reach}
          aria-label="Higher space"
          class="grid size-11 cursor-pointer place-items-center rounded-full bg-ink/10 text-xl font-bold transition-transform duration-100 ease-out active:scale-90 disabled:cursor-not-allowed disabled:opacity-35"
        >
          +
        </button>
      </div>
      <.slot_grid id={@patient} reached={@pick} />
      <button
        type="button"
        phx-click="action"
        phx-value-action={@take}
        data-role="essence-take"
        class="min-h-12 w-full cursor-pointer rounded-lg bg-gold font-semibold text-ink shadow transition-transform duration-100 ease-out active:scale-[0.98]"
      >
        Take space {@pick}
      </button>
    </section>
    """
  end

  @doc ~s{How the essence was counted, e.g. `["3 colours", "+1 white 7"]`.}
  @spec parts_text(map) :: [String.t()]
  def parts_text(parts) do
    [
      "#{parts.colours} #{if parts.colours == 1, do: "colour", else: "colours"}",
      parts.locoweed > 0 && "+#{parts.locoweed} locoweed",
      parts.white7 > 0 && "+1 white 7",
      parts.neighbours > 0 &&
        "+#{parts.neighbours} #{if parts.neighbours == 1, do: "neighbour", else: "neighbours"} exploded"
    ]
    |> Enum.filter(& &1)
  end

  @doc ~s[A glass's bonus in words, "No bonus" for an empty glass.]
  @spec glass_text([Alchemists.term_()]) :: String.t()
  def glass_text([]), do: "No bonus"
  def glass_text(slot), do: slot_text(slot)

  @doc ~s[A glass slot in short words, e.g. "draw 2 + rat"; "—" when empty.]
  @spec slot_text([Alchemists.term_()]) :: String.t()
  def slot_text([]), do: "—"
  def slot_text(slot), do: Enum.map_join(slot, " + ", &term_text/1)

  @doc "One glass term in short words."
  @spec term_text(Alchemists.term_()) :: String.t()
  def term_text({:vp, n}), do: "#{n} VP"
  def term_text(:rat), do: "rat"
  def term_text({:draw, n}), do: "lay out #{n}"
  def term_text({:ear_worm, n}), do: "draw #{n}"
  def term_text({:buy, coins}), do: "buy ≤#{coins}"
  def term_text({:rubies, 1}), do: "1 ruby"
  def term_text({:rubies, n}), do: "#{n} rubies"
  def term_text({:chip, chip}), do: chip_name(chip)
  def term_text({:swap, 1, to}), do: "swap 1→#{to}"
  def term_text(:flask), do: "fill flask"
  def term_text({:dice, 1}), do: "bonus die"
  def term_text({:dice, n}), do: "die ×#{n}"
  def term_text({:droplet, n}), do: "droplet +#{n}"
  def term_text(other), do: inspect(other)
end
