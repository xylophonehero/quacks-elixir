defmodule Codex.Rules do
  @moduledoc """
  The rules of Codex (1-hero mode) on a `Codex.Game`: the turn, the actions of
  the active side and the state checks. Source: `docs/research/codex.md`
  (rulebook v46, "S1", and the official rulings). A `# REVIEW:` comment marks a
  reading of an unclear rule.

  ## The turn (S1 p. 6)

  1. Ready: the active side's cards in play are readied; their arrival fatigue
     ends. (P1 has nothing to ready on its first turn.) Every squad leader's
     armor and the Towers' detection refresh.
  2. Upkeep: 1 gold per worker, at most 20 gold (S1 p. 3); then the "Upkeep:"
     abilities (`Codex.Effects.upkeep/2`).
  3. Main phase: the actions below, in any order.
  4. `:end_turn` ends the main phase: the patrol zone is locked in, the
     changes "this turn" end, the hand is discarded and the side draws that many
     cards + 2, at most 5 (S1 p. 2).
  5. Then the other side's turn starts.

  # REVIEW: patrollers stay in the patrol zone from turn to turn; the owner
  # rearranges them in its main phase (S1 p. 5 does not say that the zone
  # clears).

  ## Actions (main phase)

  - `{:hire, card_id}`: hire a worker: pay 1 gold and put a card from the hand
    face down in the workers zone. At most once per turn (S1 p. 3).
  - `{:play, card_id, targets}`: play a card from the hand: pay its cost (and
    the resist of its targets). A unit arrives in play with arrival fatigue
    (not with haste) and does its "Arrives:" ability on `targets`. A spell needs
    a hero of yours in play (an ultimate spell: one that was at max level at the
    start of the turn); it resolves on `targets`.
  - `{:patrol, card_id, slot}`: a ready unit or hero of yours goes to an empty
    patrol slot. `{:sideline, card_id}`: out of the patrol zone.
  - `{:attack, card_id, target}`: see `Codex.Combat`.
  - `:end_turn`.

  `legal/1` lists every legal action of the active side; `act/2` refuses any
  other action.
  """

  alias Codex.{CardRules, Cards, Combat, Effects, Stats, Targets, Zones}
  alias Table.Kit.Rng

  @gold_cap 20
  @hand_cap 5
  @spells ["Spell", "Minor Spell", "Ongoing Spell", "Ultimate Spell"]

  # -- legal actions -----------------------------------------------------------------------

  @doc "Every legal rules action of the active side."
  @spec legal(map) :: [term]
  def legal(%{phase: :over}), do: []

  def legal(%{phase: :main, active: s} = game) do
    hires(game, s) ++
      plays(game, s) ++
      patrols(game, s) ++
      attacks(game, s) ++ [:end_turn]
  end

  defp hires(game, s) do
    side = game.sides[s]
    if side.hired or side.gold < 1, do: [], else: for(id <- side.zones.hand, do: {:hire, id})
  end

  defp plays(game, s) do
    gold = game.sides[s].gold

    for id <- game.sides[s].zones.hand,
        targets <- play_targets(game, s, id),
        cost(game, s, id) + Targets.resist_cost(game, s, targets) <= gold,
        do: {:play, id, targets}
  end

  # The target lists a card can be played with ([] when it cannot be played).
  defp play_targets(game, s, id) do
    d = Cards.fetch!(game.cards[id].card)

    cond do
      d.type == "Unit" ->
        if tech_ok?(game, s, d), do: arrive_combos(game, s, d.slug), else: []

      d.type in @spells ->
        spell_combos(game, s, id, d)

      true ->
        []
    end
  end

  defp arrive_combos(game, s, slug) do
    case CardRules.arrive_targets(slug) do
      [] ->
        [[]]

      slots ->
        case Targets.combos(game, s, slots) do
          [] -> [[]]
          combos -> combos
        end
    end
  end

  defp spell_combos(game, s, id, d) do
    slots = CardRules.spell_targets(d.slug)

    cond do
      slots == nil -> []
      not hero_for?(game, s, d) -> []
      slots == [] -> [[]]
      true -> Targets.combos(game, s, slots, id)
    end
  end

  # A spell needs a hero of yours in play: a spec spell, the hero of that spec;
  # an ultimate spell, a hero that was at max level at the start of the turn (S1 p. 3).
  defp hero_for?(game, s, d) do
    heroes = for h <- Zones.in_play(game, s), Stats.hero?(game, h), do: h

    heroes =
      if d.spec,
        do: Enum.filter(heroes, &(Cards.fetch!(game.cards[&1].card).spec == d.spec)),
        else: heroes

    heroes =
      if d.type == "Ultimate Spell",
        do: Enum.filter(heroes, &(&1 in game.sides[s].max_at_start)),
        else: heroes

    heroes != []
  end

  # Tech 0 needs the base; tech I, II, III need that finished tech building (S1 p. 4).
  defp tech_ok?(_game, _s, %{tech: t}) when t in [nil, 0], do: true

  defp tech_ok?(game, s, %{tech: t}),
    do: String.to_existing_atom("tech_#{t}") in game.sides[s].tech_buildings

  @doc """
  The gold cost of card `id` for side `s`: Maestro makes Virtuosos cost 0;
  River Montoya at max level makes tech 0 units cost 1 less.
  """
  def cost(game, s, id) do
    d = Cards.fetch!(game.cards[id].card)
    base = d.cost || 0

    cond do
      d.subtype == "Virtuoso" and Stats.controls?(game, s, "maestro") ->
        0

      d.type == "Unit" and (d.tech || 0) == 0 and river_max?(game, s) ->
        max(base - 1, 0)

      true ->
        base
    end
  end

  defp river_max?(game, s) do
    Enum.any?(Zones.in_play(game, s), fn h ->
      c = game.cards[h]
      c.card == "river-montoya" and c.level >= Cards.max_level(c.card)
    end)
  end

  defp patrols(game, s) do
    zones = game.sides[s].zones
    empty = for slot <- Zones.patrol_slots(), zones.patrol[slot] == nil, do: slot

    moves =
      for id <- Zones.in_play(game, s),
          Stats.force?(game, id),
          not game.cards[id].exhausted,
          slot <- empty,
          do: {:patrol, id, slot}

    moves ++ for({_slot, id} <- Zones.patrollers(game, s), do: {:sideline, id})
  end

  defp attacks(game, s) do
    for a <- Combat.attackers(game, s), t <- Combat.targets(game, a), do: {:attack, a, t}
  end

  # -- doing an action ----------------------------------------------------------------------

  @doc "Do a rules action, or `{:error, reason}` when it is not legal now."
  @spec act(map, term) :: {:ok, map} | {:error, term}
  def act(game, action) do
    if action in legal(game),
      do: {:ok, do_act(game, action)},
      else: {:error, reason(game, action)}
  end

  defp do_act(game, {:hire, id}) do
    s = game.active

    game
    |> Zones.move(id, {s, :workers})
    |> Zones.update_card(id, &%{&1 | face_down: true})
    |> update_side(s, &%{&1 | gold: &1.gold - 1, hired: true})
  end

  defp do_act(game, {:play, id, targets}) do
    s = game.active
    d = Cards.fetch!(game.cards[id].card)
    pay = cost(game, s, id) + Targets.resist_cost(game, s, targets)
    game = update_side(game, s, &%{&1 | gold: &1.gold - pay})

    if d.type == "Unit" do
      game
      |> Zones.move(id, {s, :in_play})
      |> Zones.update_card(id, &%{&1 | fatigued: true})
      |> Effects.arrive(s, id, targets)
    else
      Effects.cast(game, s, id, targets)
    end
  end

  defp do_act(game, {:patrol, id, slot}), do: Zones.move(game, id, {game.active, :patrol}, slot)
  defp do_act(game, {:sideline, id}), do: Effects.sideline(game, id)
  defp do_act(game, {:attack, a, target}), do: Combat.attack(game, a, target)
  defp do_act(game, :end_turn), do: end_turn(game)

  # Why an action is refused: the first rule that it breaks.
  defp reason(%{phase: :over}, _action), do: :game_over

  defp reason(game, {:hire, id}) do
    side = game.sides[game.active]

    cond do
      side.hired -> :worker_hired
      side.gold < 1 -> :no_gold
      id not in side.zones.hand -> :not_in_hand
      true -> :illegal
    end
  end

  defp reason(game, {:play, id, _targets}) do
    side = game.sides[game.active]

    cond do
      id not in side.zones.hand ->
        :not_in_hand

      Enum.any?(
        plays(put_in(game.sides[game.active].gold, 99), game.active),
        &match?({:play, ^id, _}, &1)
      ) ->
        :no_gold

      true ->
        :illegal
    end
  end

  defp reason(game, {:attack, a, _target}) do
    if a in Combat.attackers(game, game.active), do: :illegal_target, else: :cannot_attack
  end

  defp reason(_game, _action), do: :illegal

  # -- the turn ------------------------------------------------------------------------------

  @doc "Start the turn of `seat`: ready, upkeep, then its main phase."
  @spec start_turn(map, 0 | 1) :: map
  def start_turn(game, seat) do
    game = %{game | active: seat, phase: :main}

    game
    |> update_side(seat, &%{&1 | turn: &1.turn + 1, hired: false, reshuffled: false})
    |> update_side(0, &%{&1 | tower_used: false})
    |> update_side(1, &%{&1 | tower_used: false})
    |> ready(seat)
    |> upkeep(seat)
    |> max_at_start(seat)
    |> cleanup()
  end

  defp ready(game, seat) do
    game =
      Enum.reduce(Zones.in_play(game, seat), game, fn id, game ->
        Zones.update_card(game, id, &%{&1 | exhausted: false, fatigued: false, attacked: false})
      end)

    # Squad leader armor refreshes each turn.
    Enum.reduce(Map.keys(game.cards), game, fn id, game ->
      Zones.update_card(game, id, &%{&1 | armor_used: false})
    end)
  end

  defp upkeep(game, seat) do
    workers = length(game.sides[seat].zones.workers)

    game
    |> gain_gold(seat, workers)
    |> Effects.upkeep(seat)
  end

  # The heroes at max level now may cast ultimate spells this turn.
  defp max_at_start(game, seat) do
    maxed =
      for h <- Zones.in_play(game, seat),
          Stats.hero?(game, h),
          game.cards[h].level >= Cards.max_level(game.cards[h].card),
          do: h

    update_side(game, seat, &Map.put(&1, :max_at_start, maxed))
  end

  @doc "Add gold to a side, at most 20 (S1 p. 3)."
  @spec gain_gold(map, 0 | 1, integer) :: map
  def gain_gold(game, seat, n),
    do: update_side(game, seat, &%{&1 | gold: min(&1.gold + n, @gold_cap)})

  # End of the main phase: lock in the patrol zone, end "this turn" changes,
  # discard and draw, then the other side's turn.
  defp end_turn(game) do
    s = game.active

    game =
      game
      |> lock_patrol(s)
      |> end_of_turn()
      |> deaths()

    hand = game.sides[s].zones.hand
    game = Enum.reduce(hand, game, fn id, game -> Zones.move(game, id, {s, :discard}, 0) end)

    game
    |> draw(s, min(length(hand) + 2, @hand_cap), :draw_phase)
    |> start_turn(1 - s)
  end

  # Only ready cards patrol (S1 p. 5).
  defp lock_patrol(game, s) do
    Enum.reduce(Zones.patrollers(game, s), game, fn {_slot, id}, game ->
      if game.cards[id].exhausted, do: Effects.sideline(game, id), else: game
    end)
  end

  defp end_of_turn(game) do
    Enum.reduce(Map.keys(game.cards), game, fn id, game ->
      Zones.update_card(game, id, &%{&1 | tmp_atk: 0, tmp_hp: 0, stealth: false})
    end)
  end

  @doc """
  Draw `n` cards for `seat`. When the deck is empty the discard pile is shuffled
  into a new deck. In the main phase (`:main`) that happens at most once; then
  the draws stop (S1 p. 2). `:draw_phase` and `:free` have no such limit.
  """
  @spec draw(map, 0 | 1, non_neg_integer, :main | :draw_phase | :free) :: map
  def draw(game, _seat, 0, _when), do: game

  def draw(game, seat, n, phase),
    do: Enum.reduce(1..n, game, fn _, g -> draw_one(g, seat, phase) end)

  defp draw_one(game, seat, phase) do
    side = game.sides[seat]

    case side.zones do
      %{deck: [top | rest], hand: hand} ->
        game
        |> Zones.put_zone({seat, :deck}, rest)
        |> Zones.put_zone({seat, :hand}, hand ++ [top])

      %{deck: [], discard: []} ->
        game

      %{deck: [], discard: _} when phase == :main and side.reshuffled ->
        game

      %{deck: [], discard: discard} ->
        {deck, rng} = Rng.shuffle(discard, game.rng)

        %{game | rng: rng, log: [{:reshuffle, seat} | game.log]}
        |> Zones.put_zone({seat, :discard}, [])
        |> Zones.put_zone({seat, :deck}, deck)
        |> update_side(seat, &%{&1 | reshuffled: &1.reshuffled or phase == :main})
        |> draw_one(seat, phase)
    end
  end

  # -- state checks ----------------------------------------------------------------------------

  @doc "The state checks after every action: deaths (`deaths/1`), then the win."
  @spec cleanup(map) :: map
  def cleanup(%{phase: :over} = game), do: game

  def cleanup(game) do
    game = deaths(game)

    case Enum.find([0, 1], &(game.sides[&1].base_hp <= 0)) do
      nil -> game
      loser -> %{game | phase: :over, winner: 1 - loser}
    end
  end

  @doc """
  Units and heroes with damage at least their HP (or HP 0 or less) die, one at
  a time, until none is left. Then channeling spells without their hero, and a
  Two Step that lost a partner, are sacrificed.
  """
  @spec deaths(map) :: map
  def deaths(game) do
    dead =
      Enum.find(for(s <- [0, 1], id <- Zones.in_play(game, s), do: id), fn id ->
        Stats.force?(game, id) and
          (Stats.hp(game, id) <= 0 or game.cards[id].damage >= Stats.hp(game, id))
      end)

    case dead do
      nil -> sacrifices(game)
      id -> game |> Effects.die(id) |> deaths()
    end
  end

  defp sacrifices(game) do
    gone =
      Enum.find(for(s <- [0, 1], id <- game.sides[s].zones.in_play, do: {s, id}), fn {s, id} ->
        lost?(game, s, id)
      end)

    case gone do
      nil -> game
      {_s, id} -> game |> Effects.sacrifice(id) |> deaths()
    end
  end

  # Channeling (Harmony, Two Step): sacrificed when its side has no Finesse hero in play.
  # Two Step: also when its side lost one of the partners.
  defp lost?(game, s, id) do
    case game.cards[id].card do
      slug when slug in ["harmony", "two-step"] ->
        no_hero? =
          not Enum.any?(Zones.in_play(game, s), fn h ->
            Stats.hero?(game, h) and Cards.fetch!(game.cards[h].card).spec == "Finesse"
          end)

        partners = Map.get(game.cards[id].extra, :partners, [])

        no_hero? or
          Enum.any?(partners, &(Zones.controller(game, &1) != s or not in_play?(game, &1)))

      _ ->
        false
    end
  end

  defp in_play?(game, id), do: Zones.zone_name(Zones.locate(game, id)) in [:in_play, :patrol]

  @doc "A card that leaves play: no damage, runes, exhaustion or turn state; a hero at level 1."
  @spec reset(map) :: map
  def reset(card) do
    %{
      card
      | damage: 0,
        plus: 0,
        minus: 0,
        exhausted: false,
        fatigued: false,
        attacked: false,
        armor_used: false,
        tmp_atk: 0,
        tmp_hp: 0,
        stealth: false,
        extra: %{},
        level: card.level && 1
    }
  end

  # -- stats -------------------------------------------------------------------------------------

  @doc "ATK/HP now of every unit and hero in play: `%{id => {atk, hp}}`."
  @spec all_stats(map) :: %{pos_integer => {integer, integer}}
  def all_stats(game) do
    for s <- [0, 1],
        id <- Zones.in_play(game, s),
        Stats.force?(game, id),
        into: %{},
        do: {id, {Stats.atk(game, id), Stats.hp(game, id)}}
  end

  # -- helpers ----------------------------------------------------------------------------------

  @doc false
  def update_side(game, seat, fun), do: update_in(game.sides[seat], fun)
end
