defmodule QuacksWeb.AlchemistsComponents do
  @moduledoc """
  The Alchemists on the page (`docs/research/alchemists-essences.md` §5.8): the flask
  strip with the patient badge, the patient card and its 10 glass slots, the patient
  choice and the essence choice. Rendering only; `QuacksWeb.GameLive` passes the
  encoded actions in.
  """
  use Phoenix.Component

  import QuacksWeb.Icons, only: [patient_icon: 1, piece_icon: 1]
  import QuacksWeb.GameComponents, only: [chip: 1, chip_name: 1, seat_colour: 1]

  alias Quacks.Game
  alias Quacks.Rules.Alchemists

  # Patients whose essence pays for actions in the next preparation phase.
  @spenders [:carrot_nose, :wing_ears, :witch_hump, :forgetfulness]

  @doc """
  The alchemist's flask of `seat`: a rack of 11 glass vials (spaces 0–10) on a
  wooden shelf, filled in the seat colour up to the essence marker, a big filled
  vial with its number. `:lg` (above your pot) starts with the
  patient badge, a button for `#sheet-patient`; `:sm` (a player card) names the
  patient above the beads. While the essence pays for actions this round, the
  marker wears a gold ring.
  """
  attr :game, Game, required: true
  attr :seat, :integer, required: true
  attr :size, :atom, default: :lg, values: [:lg, :sm]
  attr :beat, :integer, default: nil, doc: "the replay beat the marker lights up on"

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
          "inline-flex h-10 max-w-[8.5rem] shrink-0 items-center gap-1.5 rounded-full pr-3 pl-1",
          "bg-iron-dark text-xs font-semibold text-parchment ring-1 ring-iron touch-manipulation",
          "transition-transform duration-150 ease-out active:scale-[0.96]"
        ]}
      >
        <span class="grid size-8 shrink-0 place-items-center rounded-full bg-(--bead) text-ink ring-1 ring-black/25">
          <.patient_icon id={@p.patient} class="size-6" />
        </span>
        <span class="truncate">{@patient.name}</span>
      </button>
      <div class="min-w-0 flex-1">
        <p :if={@size == :sm} class="text-xs font-semibold text-ink-soft">
          {@patient.name} · essence {@p.essence}
        </p>
        <%!-- A rack of 11 vials on a wooden shelf, like the test tubes. --%>
        <div class="relative pb-1.5" data-role="essence-rack">
          <ol
            class={["grid grid-cols-11 items-end", @size == :lg && "h-8"]}
            aria-label={"Essence #{@p.essence} of 10"}
          >
            <li
              :for={space <- 0..10}
              class="flex justify-center"
              aria-current={space == @p.essence && "step"}
            >
              <span class={[
                vial_class(space, @p.essence, @size, @spendable),
                space == @p.essence && "invisible"
              ]}>
                {if space == @p.essence, do: space}
              </span>
            </li>
          </ol>
          <span
            class="absolute inset-x-0 bottom-0 h-1.5 rounded-sm bg-wood shadow-[inset_0_2px_0_rgb(0_0_0/0.3)]"
            aria-hidden="true"
          />
          <%!-- The visible marker: one node with a fixed id, one column wide, moved by
               `translate` in whole columns, so a new essence slides it (app.css). --%>
          <span
            id={"essence-marker-#{@seat}-#{@size}"}
            class="essence-marker pointer-events-none absolute top-0 bottom-1.5 left-0 flex w-[calc(100%/11)] items-end justify-center"
            style={"translate: #{@p.essence * 100}% 0"}
            aria-hidden="true"
            data-role="essence-marker"
          >
            <span class={vial_class(@p.essence, @p.essence, @size, @spendable)}>
              {@p.essence}
            </span>
            <span
              :if={@beat}
              class="absolute inset-0 m-auto size-8 rounded-full ring-4 ring-gold"
              data-role="beat-ring"
              data-beat={@beat}
              style={"--beat: #{@beat}"}
            />
          </span>
        </div>
      </div>
    </div>
    """
  end

  # Each space is a small glass vial standing on the rack: a passed one holds the
  # seat colour, faded; the marker is a big vial filled with the seat colour and its
  # number; the vials ahead are empty glass.
  defp vial_class(space, marker, size, spendable) do
    [
      "grid shrink-0 place-items-center rounded-t-[3px] rounded-b-full font-bold tabular-nums",
      "transition-[background-color,scale] duration-200 ease-out",
      vial_fill(compare(space, marker), size),
      (space == marker and spendable) && "ring-2 ring-gold ring-offset-1 ring-offset-iron-dark"
    ]
  end

  defp compare(space, marker) when space < marker, do: :passed
  defp compare(space, marker) when space == marker, do: :marker
  defp compare(_space, _marker), do: :ahead

  defp vial_fill(:marker, :lg),
    do: "h-8 w-6 bg-(--bead) pb-1 text-sm text-ink shadow ring-1 ring-black/30"

  defp vial_fill(:marker, _sm),
    do: "h-5 w-4 bg-(--bead) text-[10px] text-ink ring-1 ring-black/25"

  defp vial_fill(:passed, :lg), do: "h-5 w-2.5 bg-(--bead)/70 ring-1 ring-black/25"
  defp vial_fill(:passed, _sm), do: "h-3 w-1.5 bg-(--bead)/70"
  defp vial_fill(:ahead, :lg), do: "h-5 w-2.5 bg-parchment/12 ring-1 ring-parchment/35"
  defp vial_fill(:ahead, _sm), do: "h-3 w-1.5 bg-ink/12 ring-1 ring-ink/20"

  # The essence pays for actions now: a spending patient, essence left, brewing.
  defp spendable?(%{phase: :potions}, %{patient: patient, essence: essence}),
    do: patient in @spenders and essence > 0

  defp spendable?(_game, _p), do: false

  @doc """
  A patient card: the patient's picture, name, German name, text, and the 10 glass
  slots in a 5×2 grid. `reached` rings that slot (the essence marker's space).
  """
  attr :id, :atom, required: true, doc: "a `Quacks.Rules.Alchemists` patient id"
  attr :reached, :integer, default: nil

  def patient_card(assigns) do
    assigns = assign(assigns, patient: Alchemists.get(assigns.id))

    ~H"""
    <div class="space-y-2.5" data-role="patient-card" data-patient={@id}>
      <div class="flex items-center gap-3">
        <div
          class="grid size-16 shrink-0 place-items-center rounded-full bg-ink/8 ring-2 ring-ink/15"
          aria-hidden="true"
        >
          <.patient_icon id={@id} class="size-12 text-ink" />
        </div>
        <div class="min-w-0">
          <h3 class="font-hand text-2xl leading-tight font-bold">{@patient.name}</h3>
          <span class="text-xs text-ink-soft italic">{@patient.de}</span>
        </div>
      </div>
      <p class="text-sm leading-snug text-pretty">{@patient.text}</p>
      <.slot_grid id={@id} reached={@reached} />
    </div>
    """
  end

  @doc """
  The 10 glass slots of patient `id`, 5 per row, each drawn as a small glass with
  its bonus as glyphs (VP seal, ruby, rat, chip, ...; words where no glyph fits).
  `reached` has a gold ring.
  """
  attr :id, :atom, required: true
  attr :reached, :integer, default: nil

  def slot_grid(assigns) do
    assigns = assign(assigns, slots: Alchemists.get(assigns.id).slots)

    ~H"""
    <ol class="grid grid-cols-5 gap-x-1.5 gap-y-2" aria-label="Essence glasses" data-role="slot-grid">
      <li
        :for={space <- 1..10}
        class="flex flex-col items-center"
        data-space={space}
        data-reached={space == @reached && "true"}
      >
        <span class="text-[10px] leading-none font-bold text-ink-soft tabular-nums">{space}</span>
        <span class={[
          "mt-0.5 h-1 w-[78%] rounded-full",
          if(space == @reached, do: "bg-gold", else: "bg-ink/25")
        ]} />
        <span
          class={[
            "flex min-h-12 w-[74%] flex-wrap content-center items-center justify-center gap-0.5 text-center",
            "rounded-t-sm rounded-b-[999px] px-0.5 pt-0.5 pb-2 text-[10px] leading-tight font-semibold",
            if(space == @reached,
              do: "bg-gold/35 ring-2 ring-gold ring-offset-1 ring-offset-parchment",
              else: "bg-white/45 ring-1 ring-ink/25 ring-inset"
            )
          ]}
          title={slot_text(@slots[space])}
        >
          <.slot_term :for={term <- @slots[space]} term={term} />
          <span class="sr-only">{slot_text(@slots[space])}</span>
        </span>
      </li>
    </ol>
    """
  end

  # One glass term as a glyph (with its number) or, without a glyph, short words.
  attr :term, :any, required: true

  defp slot_term(%{term: {:chip, chip}} = assigns) do
    assigns = assign(assigns, chip: chip)

    ~H"""
    <span aria-hidden="true" data-glyph="chip"><.chip chip={@chip} size={:xs} /></span>
    """
  end

  defp slot_term(%{term: term} = assigns) do
    assigns = assign(assigns, glyph: glyph(term))

    ~H"""
    <span
      :if={@glyph}
      class="inline-flex items-center text-[10px] font-bold"
      aria-hidden="true"
      data-glyph={elem(@glyph, 0)}
    >
      <.piece_icon name={elem(@glyph, 0)} class={["size-5", elem(@glyph, 2)]} />{elem(@glyph, 1)}
    </span>
    <span :if={!@glyph} class="text-balance" aria-hidden="true">{term_text(@term)}</span>
    """
  end

  # term => {icon, the count beside it ("" for one), icon colour}; nil: words.
  # VP: the laurel seal of the score track, not a coin disc.
  defp glyph({:vp, n}), do: {:vp, "#{n}", "text-gold drop-shadow-[0_0_0.5px_#7a5a10]"}
  defp glyph(:rat), do: {:rat, "", "text-ink"}
  defp glyph({:rubies, n}), do: {:ruby, count(n), "text-ruby"}
  defp glyph(:flask), do: {:flask, "", "text-ink"}
  defp glyph({:dice, n}), do: {:die, count(n), "text-ink"}
  defp glyph({:droplet, n}), do: {:droplet, "+#{n}", "text-droplet"}
  defp glyph(_term), do: nil

  defp count(1), do: ""
  defp count(n), do: "×#{n}"

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
        Each round you collect essence. Your marker moves along the patient's card, and you get the bonus under the marker. Tap a patient to take it.
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
      <h2 class="text-xl font-bold">Essence: you reach space {@reach}</h2>
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
        autofocus
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
