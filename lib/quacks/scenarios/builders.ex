defmodule Quacks.Scenarios.Builders do
  @moduledoc """
  The scenario scripts of `Quacks.Scenarios`: one generic builder per kind (a
  Fortune Teller card, an ingredient book, an Alchemists patient, a herb witch) and
  the round-9 test tube. A hand-written scenario is a generic builder with options:
  its own choices (`me:`, `others:`), a stricter goal (`ready:`), extra checks
  per step (`checks:`, a map of step label to a function of the game), extra
  elements per step (`sees:`, label to selectors) and taps (`taps:`, label to
  `[{selector, selectors_after}]`).

  Every builder returns `{:ok, Quacks.Scenarios.Script.t()} | {:error, reason}`.
  """

  alias Quacks.Game
  alias Quacks.Rules.{Books, Chips, Fortune}
  alias Quacks.Rules.Witches, as: WitchCards
  alias Quacks.Scenarios.Script

  # The seat's own choice phases (a dialog or an offer on the page).
  @choices [
    :yellow_choice,
    :blue_choice,
    :red_choice,
    :chip_choice,
    :witch_choice,
    :fortune_choice,
    :essence_offer,
    :essence_bonus,
    :essence_choice,
    :ear_worm,
    :droplet_choice
  ]
  # The evaluation is over (or a choice of it is open) when the game is in one of these.
  @after_brew [:chip_choice, :witch_choice, :shopping, :over]

  # -- Fortune Teller cards --------------------------------------------------------

  @doc """
  The card `id` is round 2's card (a seed whose deck has it second), 3 players.
  Steps: reveal (round 2 starts: the card and what it did for everyone), resolve
  (only for a card with a choice: every seat answered), brew (your first draw of
  round 2, the card in the corner) and results (round 2's evaluation).
  """
  @spec card(Fortune.id(), keyword) :: {:ok, Script.t()} | {:error, term}
  def card(id, opts \\ []) do
    name = Fortune.card(id).name

    search(
      opts,
      fn seed ->
        s = Script.new(seed, Keyword.get(opts, :players, 3))
        if hd(Script.game(s).fortune_deck) != id, do: throw({:miss, :deck})
        s = Script.play(s, &(&1.round == 2))
        g = Script.game(s)

        s =
          mark(s, "reveal", opts,
            note: "Round 2 turns up #{name}.",
            check: fn g -> g.round == 2 and g.fortune_card == id end,
            sees: ["#pot-card-2", "[data-role=fortune-tile]"]
          )

        s =
          if g.phase == :fortune_choice do
            ready!(opts, :resolve, g)

            s
            |> Script.play(&(&1.phase != :fortune_choice), play_opts(opts))
            |> mark("resolve", opts,
              note: "Every seat answered the card.",
              check: fn g -> g.phase != :fortune_choice end
            )
          else
            s
          end

        s =
          s
          |> Script.play(&(&1.round > 2 or Game.player(&1, 0).drawn != []), play_opts(opts))
          |> mark("brew", opts,
            note: "Your first draw of round 2.",
            check: fn g -> g.round == 2 end,
            sees: ["#corner-card"]
          )

        results(s, 2, opts)
      end,
      400
    )
  end

  # -- ingredient books --------------------------------------------------------------

  @doc """
  Book `{colour, set}`: 2 players, no cards. You buy its chip (`target/1`) in every
  shop until you draw it; you stop right after it (so a green chip is your last
  chip). Steps: draw (the next draw takes the chip), placed, chosen (only when the
  chip asks you something), book choice (only for an evaluation choice) and results.
  `ready:` (a function of the game) must hold when the chip lands, else the script
  plays on to the next round.
  """
  @spec chip({Chips.colour(), 1..6}, keyword) :: {:ok, Script.t()} | {:error, term}
  def chip({colour, set} = book, opts \\ []) do
    target = target(book)
    ready = Keyword.get(opts, :ready, fn _g -> true end)
    name = Books.get(book).name

    game_opts =
      [sets: if(colour == :white, do: %{}, else: %{colour => set}), rules: %{fortune: false}] ++
        if(book == {:locoweed, 3}, do: [expansions: [:alchemists]], else: [])

    search(opts, fn seed ->
      s = Script.new(seed, Keyword.get(opts, :players, 2), game_opts)
      me = chip_me(target, opts[:me])
      s = Script.play(s, fn g -> target in Game.pot_chips(g, 0) and ready.(g) end, me: me)
      g = Script.game(s)
      round = g.round
      placed = Script.at(s)

      s =
        s
        |> mark("draw", opts,
          at: placed - 1,
          note: "Your next draw takes the #{name} (#{chip_name(target)}).",
          check: fn g -> g.round == round end
        )
        |> mark("placed", opts,
          note: "The #{name} is in your pot.",
          check: fn g -> target in Game.pot_chips(g, 0) end,
          sees: ["[id^=pot-0-]"]
        )

      s = choice_steps(s, opts, me, "chosen")
      results(s, round, Keyword.put(opts, :me, me))
    end)
  end

  @doc "The chip a book scenario draws: the cheapest chip of its colour that the book puts in play."
  @spec target({Chips.colour(), 1..6}) :: Chips.chip()
  def target({:orange, 2}), do: {:orange, 6}
  def target({colour, _set}), do: {colour, 1}

  # You: buy the target in every shop; draw while the whites stay safe (at most 4);
  # stop once the target is in the pot. Other moments: the bot.
  defp chip_me(target, custom) do
    fn g, legal -> own(custom, g, legal) || chip_move(Game.phase(g, 0), g, legal, target) end
  end

  defp own(nil, _g, _legal), do: nil
  defp own(custom, g, legal), do: custom.(g, legal)

  defp chip_move(:shop, _g, legal, target),
    do: if({:buy, [target]} in legal, do: {:buy, [target]})

  defp chip_move(:potions, g, legal, target) do
    cond do
      target in Game.pot_chips(g, 0) -> if :stop in legal, do: :stop
      :draw in legal and Game.white_sum(g, 0) <= 4 -> :draw
      :stop in legal -> :stop
      true -> nil
    end
  end

  defp chip_move(_phase, _g, _legal, _target), do: nil

  # -- The Alchemists' patients ----------------------------------------------------------

  @doc """
  Patient `id` (The Alchemists): 2 players, no cards, a seed that deals it. Steps:
  pick (you pick it), essence (round 1's essence phase), round 2 (the next potions
  phase, where the patient acts) and results.
  """
  @spec patient(atom, keyword) :: {:ok, Script.t()} | {:error, term}
  def patient(id, opts \\ []) do
    search(opts, fn seed ->
      s =
        Script.new(seed, Keyword.get(opts, :players, 2),
          expansions: [:alchemists],
          rules: %{fortune: false}
        )

      if id not in Script.game(s).patients, do: throw({:miss, :not_dealt})

      s
      |> mark("pick", opts,
        note: "Pick the patient.",
        check: fn g -> g.phase == :patient_choice end,
        sees: ["dialog#decision-patient_choice [data-role=patient-choice]"]
      )
      |> Script.act(0, {:patient, id})
      |> Script.play(&(&1.phase != :patient_choice))
      |> Script.play(&(&1.phase == :essence))
      |> mark("essence", opts,
        note: "Round 1's essence phase.",
        check: fn g -> g.phase == :essence and Game.player(g, 0).patient == id end
      )
      |> Script.play(&(&1.round == 2))
      |> mark("round 2", opts,
        note: "Round 2: the patient acts while you brew.",
        check: fn g -> g.round == 2 end
      )
      |> results(2, opts)
    end)
  end

  # -- herb witches --------------------------------------------------------------------

  @doc """
  Herb witch `id` (The Herb Witches): 2 players, no cards, the witch dealt. You call
  it as soon as you may (S1 and S4 need an explosion: you draw on). Steps: call
  (just before), called, chosen (when it asks you something) and results.
  """
  @spec witch(WitchCards.id(), keyword) :: {:ok, Script.t()} | {:error, term}
  def witch(id, opts \\ []) do
    %{colour: colour, title: title} = WitchCards.card(id)

    search(opts, fn seed ->
      s =
        Script.new(seed, Keyword.get(opts, :players, 2),
          expansions: [:herb_witches],
          witches: %{colour => id},
          rules: %{fortune: false}
        )

      me = witch_me(id, colour, opts[:me])
      s = Script.play(s, &called?(&1, id), me: me)
      round = Script.game(s).round
      called = Script.at(s)

      s =
        s
        |> mark("call", opts,
          at: called - 1,
          note: "Call the #{colour} witch: #{title}.",
          check: fn g -> not called?(g, id) end,
          sees: ["#witches-column"]
        )
        |> mark("called", opts,
          note: "The witch acts: see its result.",
          check: &called?(&1, id)
        )

      s = choice_steps(s, opts, me, "chosen")

      if Script.game_at(s, called - 1).phase == :shopping,
        do: results_after_shop(s, round, opts),
        else: results(s, round, Keyword.put(opts, :me, me))
    end)
  end

  defp witch_me(id, colour, custom) do
    fn g, legal -> own(custom, g, legal) || witch_move(g, legal, id, colour) end
  end

  defp witch_move(g, legal, id, colour) do
    call =
      Enum.find(legal, &(&1 == {:witch, colour})) ||
        Enum.find(legal, &match?({:witch, ^colour, _}, &1))

    cond do
      call && not called?(g, id) -> call
      # S1 and S4 need an explosion: draw on.
      id in [:s1, :s4] and Game.phase(g, 0) == :potions and :draw in legal -> :draw
      true -> nil
    end
  end

  defp called?(g, id), do: Enum.any?(g.log, &match?({0, {:witch, ^id, _}}, &1))

  # -- other rules -------------------------------------------------------------------------

  @doc """
  The reverse pot side in round 9: you keep your rubies until round 9's shop, then
  move the test-tube droplet with 2 of them. 2 players. Steps: shop (round 9's
  shop), tube (the glass paid its bonus) and final (the game is over).
  """
  @spec tube9(keyword) :: {:ok, Script.t()} | {:error, term}
  def tube9(opts \\ []) do
    keep = fn g, legal ->
      if g.round < 9 and Game.phase(g, 0) == :shop and :end_round in legal and
           Game.player(g, 0).bought?,
         do: :end_round
    end

    search(opts, fn seed ->
      s =
        Script.new(seed, Keyword.get(opts, :players, 2),
          rules: %{pot_side: :back, fortune: false}
        )

      s =
        Script.play(
          s,
          &(&1.round == 9 and &1.phase == :shopping and
              {:rubies, :tube} in Game.legal_actions(&1, 0)),
          me: keep
        )

      tube = Game.player(Script.game(s), 0).tube

      s
      |> mark("shop", opts,
        note: "Round 9's shop: 2 rubies move the test-tube droplet.",
        check: fn g -> {:rubies, :tube} in Game.legal_actions(g, 0) end,
        sees: ["#bar-rubies"]
      )
      |> Script.act(0, {:rubies, :tube})
      |> mark("tube", opts,
        note: "The droplet moves 1 glass and pays its bonus.",
        check: fn g ->
          Game.player(g, 0).tube == tube + 1 and
            match?({0, {:tube, _, _}}, Enum.find(g.log, &match?({0, {:tube, _, _}}, &1)))
        end
      )
      |> Script.play(&Game.over?/1)
      |> mark("final", opts, note: "The game is over.", check: &Game.over?/1)
    end)
  end

  # -- shared steps ---------------------------------------------------------------------

  # When you are in a choice phase now: play until you leave it and mark `label`.
  defp choice_steps(s, opts, me, label) do
    phase = Game.phase(Script.game(s), 0)

    if phase in @choices do
      s
      |> Script.play(&(Game.phase(&1, 0) != phase), me: me, others: opts[:others])
      |> mark(label, opts,
        note: "You answered.",
        check: fn g -> Game.phase(g, 0) != phase end
      )
    else
      s
    end
  end

  # Play on to the end of round `round`'s brewing; mark an evaluation choice (when you
  # have one) and the results (the shop, or the end of the game).
  defp results(s, round, opts) do
    s = Script.play(s, &(&1.round > round or &1.phase in @after_brew), play_opts(opts))
    g = Script.game(s)

    s =
      if g.round == round and g.phase in [:chip_choice, :witch_choice] and
           Game.legal_actions(g, 0) != [] do
        phase = g.phase

        s
        |> mark("book choice", opts,
          note: "The evaluation asks you to choose.",
          check: fn g -> g.phase == phase end
        )
        |> Script.play(&(&1.round > round or &1.phase in [:shopping, :over]), play_opts(opts))
      else
        s
      end

    # A gold witch acts in the evaluation's last choice: its step shows the results.
    if Script.at(s) == List.last(s.steps).at,
      do: s,
      else:
        mark(s, "results", opts,
          note: "Round #{round}'s results.",
          check: fn g -> g.phase in [:shopping, :over] or g.round > round end,
          sees: ["#reveal-results-#{round}"]
        )
  end

  # A call in the shop (copper witches, G4): the results are the next round's start.
  defp results_after_shop(s, round, opts) do
    s
    |> Script.play(&(&1.round > round or Game.over?(&1)), play_opts(opts))
    |> mark("results", opts,
      note: "The shop is over.",
      check: fn g -> g.round > round or Game.over?(g) end
    )
  end

  # `Script.search/2`, and every step that `checks:` names must be there (a hand-written
  # scenario that misses its step tries the next seed).
  defp search(opts, script, tries \\ 60) do
    Script.search(
      fn seed ->
        s = script.(seed)
        labels = Enum.map(s.steps, & &1.label)
        missing = Map.keys(opts[:checks] || %{}) -- labels
        if missing != [], do: throw({:miss, {:no_step, missing}})
        s
      end,
      tries
    )
  end

  defp play_opts(opts), do: Keyword.take(opts, [:me, :others])

  # A step with the scenario's extra check for `label` (`checks:`) added to its own.
  defp mark(s, label, opts, step) do
    check = step[:check] || fn _g -> true end
    extra = get_in(opts, [:checks, label])

    both = fn g -> both(check.(g), extra, g) end

    sees = Keyword.get(step, :sees, []) ++ (get_in(opts, [:sees, label]) || [])
    taps = get_in(opts, [:taps, label]) || []

    Script.mark(
      s,
      label,
      step |> Keyword.put(:check, both) |> Keyword.merge(sees: sees, taps: taps)
    )
  end

  defp both(true, nil, _g), do: true
  defp both(true, extra, g), do: extra.(g)
  defp both(failed, _extra, _g), do: failed

  # A hand-written scenario's `ready:` for a step that only happens once: no retry.
  defp ready!(opts, key, g) do
    case opts[:ready] do
      %{^key => ready} -> if not ready.(g), do: throw({:miss, {:not_ready, key}})
      _other -> :ok
    end
  end

  defp chip_name({colour, value}), do: "#{colour} #{value}"
end
