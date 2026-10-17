defmodule Codex.Bot.Plan do
  @moduledoc """
  The stage-1 Codex bot (`docs/research/codex-bot.md` §4.1). It picks one
  action per call from the `legal` list of its fair view
  (`Codex.Game.bot_view/2`), so it never breaks a rule and never sees hidden
  cards.

  Its main phase, in this order:

  1. Hire a worker while it has fewer than 10 (`TechPlan.worker_order/0`).
  2. Build tech I, tech II and tech III as soon as they are legal.
  3. Summon its hero.
  4. Play Harmony (it makes a Dancer for each later spell).
  5. Play the units and spells that make the board better: a one-action
     look-ahead. It does the action on a copy of the public state
     (`Codex.Rules.act_legal/2`) and scores the result with `eval/2`.
  6. Attacks and exhaust abilities (Maestro's wreck) that make the board
     better by more than the cost of an exhausted force (it cannot patrol).
  7. Level the hero up with the gold that is left.
  8. Fill the empty patrol slots: the squad leader has the most HP, the other
     slots the most ATK.

  In the tech step it follows `Codex.Bot.TechPlan.plan/1`, and at 10 workers it
  techs only the cards of the plan that are left. It builds a Tower add-on at
  8 workers.

  `new/1` turns rules on or off (`rules/0`), so `mix codex.bench` can measure
  each rule alone. The bot keeps no state between calls and uses no
  randomness: the same view gives the same action.
  """

  alias Codex.Bot.TechPlan
  alias Codex.{Cards, Rules, Stats, Zones}
  alias Table.Kit.Rng

  # Each rule kept here won games in `mix codex.bench`, or is a choice for
  # later tuning (off). The numbers: `docs/research/codex-bot.md`, "Stage 1 results".
  @rules %{
    # The worker order of `TechPlan.worker_order/0`; off: the cheapest card.
    hire_order: true,
    # Build tech I, II, III when legal.
    build: true,
    # Tech by `TechPlan`; off: the first bot's tech choice.
    tech_plan: true,
    # At 10 workers, tech only the cards of the plan that are left.
    tech_zero: true,
    # Build a Tower add-on at 8 workers (it hits each attacker for 1).
    tower: true,
    # Build a Surplus add-on at 10 workers (when there is no Tower).
    surplus: false,
    # Base HP counts 1.5 (not 1) in `eval/2`.
    aggro: true,
    # Level the hero to its next band before the attacks.
    band_first: false,
    # Use an enabler (River's sideline, Intimidate, Discord, Appel Stomp, "stop
    # the music") when the best attack after it is better.
    enablers: false,
    # Put the weakest forces in the scavenger and technician slots.
    patrol_smart: false
  }

  # The score lost when a force exhausts (it cannot patrol on the opponent's turn).
  @exhaust_cost 0.5
  # The worth of 1 gold in `eval/2` (gold carries over to the next turn).
  @gold_value 0.3

  @slot_order [:squad_leader, :elite, :lookout, :technician, :scavenger]
  @enabler_spells ~w(intimidate discord appel-stomp)

  @doc "The rules and their default values (true = on)."
  @spec rules() :: map
  def rules, do: @rules

  @doc "A bot state: the default rules with `changes` (`[{rule, boolean}]`)."
  @spec new([{atom, boolean}]) :: map
  def new(changes \\ []) do
    for {rule, _} <- changes, not Map.has_key?(@rules, rule) do
      raise ArgumentError, "unknown rule #{inspect(rule)}"
    end

    %{rules: Map.merge(@rules, Map.new(changes))}
  end

  @doc "The bot's next action for `view`, and its state (unchanged)."
  @spec choose(map, map | nil) :: {term, map}
  def choose(view, nil), do: choose(view, new())
  def choose(view, state), do: {pick(view, state.rules), state}

  defp pick(%{legal: []}, _r), do: :end_turn

  defp pick(%{phase: :tech} = v, r) do
    if r.tech_plan, do: tech(v, r), else: elem(Codex.Bot.choose(v, nil), 0)
  end

  defp pick(v, r) do
    ctx = %{v: v, g: game_of(v), legal: v.legal, me: v.active, r: r}

    Enum.find_value(
      [
        &hire/1,
        &build/1,
        &summon/1,
        &harmony/1,
        &plays/1,
        &band/1,
        &fight/1,
        &level/1,
        &patrol/1
      ],
      :end_turn,
      & &1.(ctx)
    )
  end

  # -- hire -------------------------------------------------------------------------------------

  defp hire(%{v: v, me: me, legal: legal, r: r}) do
    hand = for {:hire, id} <- legal, do: id

    if hand != [] and length(v.sides[me].zones.workers) < 10 do
      {:hire, Enum.min_by(hand, &keep(v, &1, r))}
    end
  end

  # How much the bot wants to keep a hand card (the lowest becomes a worker).
  defp keep(v, id, %{hire_order: true}) do
    slug = v.cards[id].card

    case Enum.find_index(TechPlan.worker_order(), &(&1 == slug)) do
      nil -> 20 + (Cards.fetch!(slug).cost || 0)
      i -> i
    end
  end

  defp keep(v, id, _r), do: Cards.fetch!(v.cards[id].card).cost || 0

  # -- build ------------------------------------------------------------------------------------

  defp build(%{legal: legal, r: %{build: true}} = ctx) do
    Enum.find(legal, &match?({:build, b} when b in [:tech_1, :tech_2, :tech_3], &1)) ||
      Enum.find(legal, &match?({:build, :tech_2, _}, &1)) ||
      add_on(ctx)
  end

  defp build(_ctx), do: nil

  defp add_on(%{v: v, me: me, legal: legal, r: r}) do
    side = v.sides[me]
    done? = :tech_3 in (side.tech_buildings ++ side.pending)

    workers = length(side.zones.workers)

    cond do
      r.tower and {:build, :tower} in legal and workers >= 8 ->
        {:build, :tower}

      r.surplus and done? and {:build, :surplus} in legal ->
        {:build, :surplus}

      true ->
        nil
    end
  end

  defp summon(%{legal: legal}), do: Enum.find(legal, &match?({:summon, _}, &1))

  # Harmony makes a Dancer for each later spell: play it early.
  defp harmony(%{v: v, legal: legal}) do
    Enum.find(legal, fn
      {:play, id, []} -> v.cards[id].card == "harmony"
      _ -> false
    end)
  end

  # -- plays: units and spells with a lasting effect ---------------------------------------------

  defp plays(%{v: v, g: g, me: me, legal: legal, r: r}) do
    now = eval(g, me, r)

    candidates =
      for {:play, id, _} = a <- legal,
          slug = v.cards[id].card,
          slug not in @enabler_spells,
          slug != "harmony",
          do: a

    best_positive(candidates, fn a -> delta(g, a, me, now, r) end)
  end

  # -- hero levels ------------------------------------------------------------------------------

  # Level up to the next band now when the gold for all the levels is there.
  defp band(%{v: v, g: g, me: me, legal: legal, r: %{band_first: true}}) do
    Enum.find_value(legal, fn
      {:level_up, id} = a ->
        level = g.cards[id].level
        next = next_band(g.cards[id].card, level)
        if next && next - level <= v.sides[me].gold, do: a

      _ ->
        nil
    end)
  end

  defp band(_ctx), do: nil

  defp next_band(slug, level) do
    case for(%{level: l} <- Cards.fetch!(slug).bands || [], l > level, do: l) do
      [] -> nil
      ls -> Enum.min(ls)
    end
  end

  defp level(%{legal: legal}), do: Enum.find(legal, &match?({:level_up, _}, &1))

  # -- attacks, exhaust abilities and enablers ---------------------------------------------------

  defp fight(%{g: g, me: me, legal: legal, r: r} = ctx) do
    now = eval(g, me, r)
    {best, score} = best_exhaust(g, legal, me, now, r)

    enabler =
      if r.enablers do
        ctx
        |> enablers()
        |> Enum.map(fn e -> {e, enabler_score(g, e, me, now, r)} end)
        |> Enum.max_by(&elem(&1, 1), fn -> {nil, 0} end)
      else
        {nil, 0}
      end

    case enabler do
      {e, s} when e != nil and s > max(score, 0) + 0.5 -> e
      _ -> if score > 0, do: best
    end
  end

  # The best attack or exhaust ability, and its score (`{nil, 0}` when none).
  defp best_exhaust(g, legal, me, now, r) do
    legal
    |> Enum.filter(&exhaust_action?/1)
    |> Enum.map(fn a -> {a, delta(g, a, me, now, r) - @exhaust_cost} end)
    |> Enum.max_by(&elem(&1, 1), fn -> {nil, 0} end)
  end

  defp exhaust_action?({:attack, _, _}), do: true
  defp exhaust_action?({:ability, _, :wreck, _}), do: true
  defp exhaust_action?(_), do: false

  defp enablers(%{v: v, g: g, me: me, legal: legal}) do
    Enum.filter(legal, fn
      {:ability, _, :sideline, _} -> true
      {:ability, h, :stop_music, []} -> music?(g, me, h)
      {:play, id, _} -> v.cards[id].card in @enabler_spells
      _ -> false
    end)
  end

  # Stop the music when 2 or more Dancers can attack, and Harmony has made all
  # 3 or the Angry Dancers would take the base to 0.
  defp music?(g, me, harmony) do
    ready =
      Enum.count(Zones.in_play(g, me), fn id ->
        c = g.cards[id]
        c.card == "dancer" and not c.exhausted and not c.fatigued
      end)

    ready >= 2 and
      (Map.get(g.cards[harmony].extra, :dancers, 0) >= 3 or
         g.sides[1 - me].base_hp <= 2 * ready)
  end

  # The enabler, then the best attack after it: the gain over the state now.
  defp enabler_score(g, e, me, now, r) do
    case sim(g, e) do
      nil ->
        -1000

      g1 ->
        then = eval(g1, me, r)
        {_a, s} = best_exhaust(g1, Rules.legal(g1), me, then, r)
        # River's sideline exhausts her: she cannot patrol.
        cost = if match?({:ability, _, :sideline, _}, e), do: 2, else: 0
        then - now + max(s, 0) - cost
    end
  end

  # -- patrol -----------------------------------------------------------------------------------

  defp patrol(%{g: g, me: me, legal: legal, r: r}) do
    free = g.sides[me].zones.in_play

    moves = for {:patrol, id, slot} <- legal, id in free, do: {id, slot}
    Enum.find_value(@slot_order, &patrol_slot(g, me, moves, &1, r))
  end

  defp patrol_slot(g, me, moves, slot, r) do
    case for({id, ^slot} <- moves, do: id) do
      [] -> nil
      ids -> {:patrol, patroller(g, me, ids, slot, r), slot}
    end
  end

  defp patroller(g, _me, ids, :squad_leader, _r), do: Enum.max_by(ids, &hp_left(g, &1))

  defp patroller(g, _me, ids, slot, %{patrol_smart: true})
       when slot in [:technician, :scavenger],
       do: Enum.min_by(ids, &(hp_left(g, &1) + atk(g, &1)))

  defp patroller(g, _me, ids, _slot, _r), do: Enum.max_by(ids, &atk(g, &1))

  # -- tech -------------------------------------------------------------------------------------

  defp tech(v, r) do
    side = v.sides[v.active]
    slug = &v.cards[&1].card
    left = side.zones.codex |> Enum.map(slug) |> Enum.frequencies()
    queue = queue(TechPlan.plan(side.spec), left)
    must? = length(side.zones.workers) < 10

    want =
      cond do
        must? ->
          fill = Enum.filter(TechPlan.fillers(side.spec), &(Map.get(left, &1, 0) > 0))
          Enum.take(queue ++ fill, 2)

        r.tech_zero ->
          Enum.take(queue, 2)

        true ->
          :basic
      end

    find_tech(v, want, slug) || elem(Codex.Bot.choose(v, nil), 0)
  end

  defp find_tech(_v, :basic, _slug), do: nil

  defp find_tech(%{legal: legal}, want, slug) do
    sorted = Enum.sort(want)

    Enum.find(legal, fn {:tech, ids} -> Enum.sort(Enum.map(ids, slug)) == sorted end) ||
      Enum.find(legal, fn {:tech, ids} -> Enum.map(ids, slug) == Enum.take(want, 1) end)
  end

  # The cards of `plan` that are not teched yet, in order (2 copies of each card).
  defp queue(plan, left) do
    taken = Map.new(Map.keys(left) ++ plan, &{&1, 2 - Map.get(left, &1, 0)})

    {queue, _} =
      Enum.reduce(plan, {[], taken}, fn s, {q, t} ->
        if t[s] > 0, do: {q, Map.update!(t, s, &(&1 - 1))}, else: {[s | q], t}
      end)

    Enum.reverse(queue)
  end

  # -- look-ahead -------------------------------------------------------------------------------

  defp best_positive(candidates, score) do
    scored = for a <- candidates, s = score.(a), s > 0, do: {s, a}

    case Enum.max_by(scored, &elem(&1, 0), fn -> nil end) do
      {_s, a} -> a
      nil -> nil
    end
  end

  defp delta(g, action, me, now, r) do
    case sim(g, action) do
      nil -> -1000
      g1 -> eval(g1, me, r) - now
    end
  end

  @doc false
  # Do `action` on a copy of the public state; nil when it fails.
  def sim(g, action), do: g |> Rules.act_legal(action) |> Rules.cleanup()

  @doc """
  A score of a game state for side `me`: its board minus the other side's.
  Per side: base HP (more per HP when it is low), each unit and hero (ATK + HP
  left, a hero also its level), tech buildings, gold. Changes "this turn" do
  not count (they end with the turn); a win is +1000.
  """
  @spec eval(map, 0 | 1, map) :: float
  def eval(g, me, rules \\ @rules)
  def eval(%{phase: :over, winner: w}, me, _r), do: if(w == me, do: 1000.0, else: -1000.0)

  def eval(g, me, r) do
    g = lasting(g)
    side(g, me, r) - side(g, 1 - me, r)
  end

  defp side(g, s, r) do
    sd = g.sides[s]
    hp = sd.base_hp * if(r.aggro, do: 1.5, else: 1)
    forces = for id <- Zones.in_play(g, s), Stats.force?(g, id), do: force_value(g, id)

    buildings =
      for b <- sd.tech_buildings ++ sd.pending,
          do: if(b in [:tech_1, :tech_2, :tech_3], do: 4, else: 2)

    damage = sd.building_damage |> Map.values() |> Enum.sum()
    ongoing = Enum.count(sd.zones.in_play, &(g.cards[&1].card in ["two-step", "harmony"]))

    hp + 0.5 * max(10 - sd.base_hp, 0) + Enum.sum(forces) + Enum.sum(buildings) -
      0.5 * damage + @gold_value * sd.gold + ongoing
  end

  defp force_value(g, id) do
    c = g.cards[id]
    base = max(Stats.atk(g, id), 0) + max(Stats.hp(g, id) - c.damage, 0)
    kws = Enum.count([:flying, :unstoppable, :swift], &Stats.kw?(g, id, &1))
    hero = if c.level, do: 2 + c.level, else: 0
    base + kws + hero
  end

  # The state with the changes "this turn" gone.
  defp lasting(g) do
    cards =
      Map.new(g.cards, fn {id, c} -> {id, %{c | tmp_atk: 0, tmp_hp: 0, tmp_armor: 0}} end)

    %{g | cards: cards}
  end

  # -- the public state as a game ----------------------------------------------------------------

  @doc false
  # A `%Codex.Game{}` from the fair view: hidden zones (counts) are empty lists.
  def game_of(v) do
    sides =
      Map.new(v.sides, fn {s, side} ->
        zones = Map.new(side.zones, fn {k, z} -> {k, if(is_integer(z), do: [], else: z)} end)
        {s, %{side | zones: zones}}
      end)

    %Codex.Game{
      seed: {1, 2, 3},
      rng: Rng.seed({1, 2, 3}),
      active: v.active,
      phase: v.phase,
      bot: v.bot,
      cards: Map.new(v.cards, fn {id, c} -> {id, Map.delete(c, :now)} end),
      sides: sides,
      trash: v.trash
    }
  end

  defp atk(g, id), do: Stats.atk(g, id)
  defp hp_left(g, id), do: Stats.hp(g, id) - g.cards[id].damage
end
