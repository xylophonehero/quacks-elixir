defmodule Codex.Bot do
  @moduledoc """
  The first Codex bot (bot level `:basic`; the default is `Codex.Bot.Plan`). It picks one action per call from the legal actions in its
  view (`Codex.Game.view/2` gives the bot's seat a `legal` list), so it never
  breaks a rule. Its plan for a main phase, in this order:

  1. Hire a worker (the least useful hand card) while it has fewer than 10.
  2. Summon its hero.
  3. Spells that kill something (Spark, Wither on a 1-HP force, ...).
  4. Good attacks: kill without dying, a fair trade, or hit the base when
     nothing blocks.
  5. Play its best unit or another useful card.
  6. Level up its hero with the gold that is left.
  7. Put ready units and heroes into empty patrol slots (squad leader: the
     most HP; then elite, lookout, technician, scavenger).
  8. End the turn. In the tech step, pick codex cards (units first).

  It uses no hidden information beyond what its view holds.
  """

  alias Codex.Cards

  @slot_order [:squad_leader, :elite, :lookout, :technician, :scavenger]

  @doc "The bot's next action for `view`, and its (unused) state."
  @spec choose(map, term) :: {term, term}
  def choose(view, state), do: {pick(view), state}

  defp pick(%{legal: []}), do: :end_turn

  defp pick(%{legal: legal} = v) do
    tech = for {:tech, _} = a <- legal, do: a

    if tech != [] do
      best_tech(v, tech)
    else
      main(v, legal)
    end
  end

  defp main(v, legal) do
    find(legal, &hire(v, &1)) ||
      find(legal, &match?({:summon, _}, &1)) ||
      best(legal, &kill_spell(v, &1)) ||
      best(legal, &attack(v, &1)) ||
      best(legal, &play(v, &1)) ||
      best(legal, &ability(v, &1)) ||
      find(legal, &match?({:level_up, _}, &1)) ||
      patrol(v, legal) ||
      :end_turn
  end

  defp find(legal, fun), do: Enum.find(legal, fun)

  # The legal action with the best positive score.
  defp best(legal, score) do
    scored = for a <- legal, s = score.(a), is_number(s), s > 0, do: {s, a}

    case Enum.max_by(scored, &elem(&1, 0), fn -> nil end) do
      {_s, a} -> a
      nil -> nil
    end
  end

  # -- hire -------------------------------------------------------------------------------------

  defp hire(v, {:hire, id}) do
    side = v.sides[v.active]
    hand = side.zones.hand

    length(side.zones.workers) < 10 and
      id == Enum.min_by(hand, &card_value(v, &1))
  end

  defp hire(_v, _action), do: false

  # -- spells and plays -------------------------------------------------------------------------

  # Spells and "Arrives:" that kill a target with at most this much HP left.
  @kills %{"spark" => 1, "wither" => 1, "the-boot" => 99, "hired-stomper" => 3}

  defp kill_spell(v, {:play, id, [t]}) when is_integer(t) do
    limit = Map.get(@kills, v.cards[id].card)
    if limit && enemy?(v, t) && hp_left(v, t) <= limit, do: 10 + card_value(v, t)
  end

  defp kill_spell(_v, _action), do: nil

  defp play(v, {:play, id, targets}) do
    d = Cards.fetch!(v.cards[id].card)

    cond do
      d.type in ["Unit", "Legendary Unit"] -> unit_score(v, d, targets)
      d.type in ["Building", "Upgrade"] -> 2
      true -> spell_score(v, d.slug, targets)
    end
  end

  defp play(_v, _action), do: nil

  # Cards whose targets should be your own (buffs, repairs, sacrifices).
  @friendly ~w(bloom forest-s-favor charge rampant-growth dinosize spirit-of-the-panda
               bloodlust final-showdown two-step circle-of-life artisan-mantis fairie-dragon)

  # Cards the bot does not play (they hurt its side or need a careful moment).
  @never ~w(maximum-anarchy desperation)

  defp spell_score(_v, slug, _targets) when slug in @never, do: nil
  defp spell_score(_v, slug, _targets) when slug in ["spark", "the-boot"], do: nil

  defp spell_score(v, slug, targets) when slug in @friendly,
    do: if(own_targets?(v, targets), do: 3)

  defp spell_score(_v, _slug, [:boost]), do: 4
  defp spell_score(_v, _slug, [atom]) when is_atom(atom) and atom != nil, do: 3
  defp spell_score(_v, _slug, []), do: 2
  defp spell_score(v, _slug, targets), do: if(enemy_targets?(v, targets), do: 3)

  # A unit: its stats; its "Arrives:" targets must be on the right side; boost when it can.
  defp unit_score(v, d, targets) do
    base = (d.atk || 0) + (d.hp || 0) + 1
    if targets == [], do: base, else: arrive_score(v, d, targets, base)
  end

  defp arrive_score(v, d, targets, base) do
    cond do
      :boost in targets -> base + 3
      :plain in targets -> base
      d.slug in @friendly -> if(own_targets?(v, targets), do: base + 2)
      enemy_targets?(v, targets) -> base + 2
      true -> nil
    end
  end

  defp enemy_targets?(v, targets) do
    real = Enum.reject(targets, &is_nil/1)

    real != [] and
      Enum.all?(
        real,
        &(enemy?(v, &1) or enemy_building?(v, &1) or match?({:worker, s} when s != v.active, &1))
      )
  end

  defp own_targets?(v, targets) do
    real = Enum.reject(targets, &is_nil/1)

    real != [] and
      Enum.all?(real, &(mine?(v, &1) or match?({:building, s, _} when s == v.active, &1)))
  end

  # -- abilities --------------------------------------------------------------------------------

  # Gold and damage to the opponent.
  defp ability(_v, {:ability, _id, name, []}) when name in [:prospect, :mine], do: 2

  defp ability(v, {:ability, _id, name, targets})
       when name in [:lob, :firebat, :firehouse, :jaina_1, :jaina_3, :wreck, :burn, :shoot],
       do: if(enemy_targets?(v, targets), do: 2)

  defp ability(_v, _action), do: nil

  # -- attacks ----------------------------------------------------------------------------------

  defp attack(v, {:attack, a, {:building, _s, :base}}), do: atk(v, a) + 1
  defp attack(v, {:attack, a, {:building, _s, _b}}), do: atk(v, a) + 0.5

  defp attack(v, {:attack, a, t}) do
    my_atk = atk(v, a)
    armor = if armored?(v, t), do: 1, else: 0
    back = atk(v, t)
    kill? = my_atk >= hp_left(v, t) + armor
    die? = back >= hp_left(v, a)

    cond do
      kill? and not die? -> 10 + card_value(v, t)
      kill? and die? -> card_value(v, t) - card_value(v, a) + 1
      not die? -> 0.5
      true -> -10
    end
  end

  defp attack(_v, _action), do: nil

  # -- patrol -----------------------------------------------------------------------------------

  defp patrol(v, legal) do
    moves =
      for {:patrol, id, slot} <- legal, id in v.sides[v.active].zones.in_play, do: {id, slot}

    Enum.find_value(@slot_order, &patrol_slot(v, moves, &1))
  end

  # The squad leader: the most HP left; the other slots: the most ATK.
  defp patrol_slot(v, moves, slot) do
    case for({id, ^slot} <- moves, do: id) do
      [] -> nil
      ids when slot == :squad_leader -> {:patrol, Enum.max_by(ids, &hp_left(v, &1)), slot}
      ids -> {:patrol, Enum.max_by(ids, &atk(v, &1)), slot}
    end
  end

  # -- tech -------------------------------------------------------------------------------------

  # Pick the codex cards with the best value (units of the lowest tech first).
  defp best_tech(v, tech) do
    Enum.max_by(tech, fn {:tech, ids} -> Enum.sum(Enum.map(ids, &tech_value(v, &1))) end)
  end

  defp tech_value(v, id) do
    d = Cards.fetch!(v.cards[id].card)

    case d.type do
      "Unit" -> unit_tech_value(d, v.sides[v.active].tech_buildings)
      "Ultimate Spell" -> 1
      _ -> 6
    end
  end

  defp unit_tech_value(d, built) do
    stats = (d.atk || 0) + (d.hp || 0)

    case d.tech || 0 do
      t when t <= 1 -> 10 + stats
      2 -> if(:tech_2 in built, do: 12, else: 4) + (d.atk || 0)
      _ -> 2
    end
  end

  # -- the view ---------------------------------------------------------------------------------

  defp atk(v, id), do: v.stats |> Map.get(id, {0, 0}) |> elem(0)
  defp hp_left(v, id), do: elem(Map.get(v.stats, id, {0, 0}), 1) - v.cards[id].damage

  defp armored?(v, id) do
    opp = 1 - v.active
    v.sides[opp].zones.patrol.squad_leader == id and v.cards[id].armor_dmg == 0
  end

  defp controller(v, id) do
    Enum.find([0, 1], fn s ->
      z = v.sides[s].zones
      id in z.in_play or id in Map.values(z.patrol)
    end)
  end

  defp enemy?(v, id) when is_integer(id), do: controller(v, id) == 1 - v.active
  defp enemy?(_v, _t), do: false
  defp mine?(v, id) when is_integer(id), do: controller(v, id) == v.active
  defp mine?(_v, _t), do: false

  defp enemy_building?(v, {:building, s, _b}), do: s == 1 - v.active
  defp enemy_building?(_v, _t), do: false

  # How much a card is worth: its cost, or its stats for a token.
  defp card_value(v, id) do
    d = Cards.fetch!(v.cards[id].card)

    case d do
      %{type: "Hero"} -> 6 + (v.cards[id].level || 1)
      %{cost: c} when is_integer(c) and c > 0 -> c
      _ -> (d.atk || 0) + (d.hp || 0)
    end
  end
end
