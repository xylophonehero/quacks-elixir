defmodule Codex.Stats do
  @moduledoc """
  What a card in play is now: its kind, ATK, HP, armor and keywords, with every
  bonus (research §5, §8, §10, §16). The controller of a card is the side whose
  zone holds it.

  ATK = printed (a hero: its level band; a feather rune: 3/1; Chaos Mirror: a
  swapped printed ATK) + runes + this-turn changes, plus: frenzy on its
  controller's turn; +1 in the elite slot on the other side's turn (S1 p. 5);
  the static bonuses of other cards (Grounded Guide, Two Step, War Drums, Master
  Midori, Spirit of the Panda, Final Showdown, Might of Leaf and Claw, Stampede,
  Ironbark Treant on patrol, Star-Crossed Starlet).

  Keywords (`kw?/3`) are printed (`Codex.CardRules`) or given by other cards
  (Nimble Fencer, Blademaster, Drakk Ramhorn, Calamandra Moss, Behind the Ferns,
  Moss Ancient, Ferocity, feather runes, Wandering Mimic, ...).
  """

  alias Codex.{CardRules, Cards, Zones}

  @mimic_keys [:flying, :overpower, :haste, :sparkshot, :untargetable, :stealth]

  # -- kinds -------------------------------------------------------------------------------

  @doc "The controller of card `id` (nil when it is not in a side's zone)."
  def controller(game, id), do: Zones.controller(game, id)

  defp def_of(game, id), do: Cards.fetch!(game.cards[id].card)

  @doc "True for a unit or a hero."
  def force?(game, id), do: unit?(game, id) or hero?(game, id)

  @doc "True for a unit (legendary units and tokens too)."
  def unit?(game, id), do: def_of(game, id).type in ["Unit", "Legendary Unit"]

  @doc "True for a hero."
  def hero?(game, id), do: def_of(game, id).type == "Hero"

  @doc "True for a building card in play (Sanatorium, Firehouse, Verdant Tree, ...)."
  def building_card?(game, id), do: def_of(game, id).type in ["Building", "Legendary Building"]

  @doc "True for an upgrade card."
  def upgrade?(game, id), do: String.contains?(def_of(game, id).type, "Upgrade")

  @doc "True for an ongoing spell."
  def ongoing?(game, id), do: String.contains?(def_of(game, id).type, "Ongoing")

  @doc "True for a token (never in a deck: it is destroyed when it leaves play)."
  def token?(game, id), do: def_of(game, id).zone == "trash" and unit?(game, id)

  @doc "The tech level of a unit (tokens are tech 0), nil for other cards."
  def tech(game, id), do: if(unit?(game, id), do: def_of(game, id).tech || 0)

  @doc ~s{The colour of a card ("Neutral", "Red", "Green", ...).}
  def color(game, id), do: def_of(game, id).color

  @doc "The spec of a card (nil for starting-deck cards and tokens)."
  def spec(game, id), do: def_of(game, id).spec

  @doc ~s{True when the card's subtype has the word `word` ("Demon", "Skeleton", ...).}
  def subtype?(game, id, word),
    do: word in String.split(def_of(game, id).subtype || "", ~r/[\s—-]+/, trim: true)

  @doc """
  True for an Illusion now: a unit with the Illusion subtype, a copy that is
  still an Illusion (Sirus Quince), a unit made an Illusion this turn
  (Hallucination), or a tech 0-II unit while a Dreamscape is in play.
  """
  def illusion?(game, id) do
    c = game.cards[id]

    unit?(game, id) and
      (subtype?(game, id, "Illusion") or Map.get(c.extra, :illusion) == true or
         Map.get(c.this_turn, :illusion) == true or
         (tech(game, id) in [0, 1, 2] and
            Enum.any?([0, 1], &controls?(game, &1, "dreamscape"))))
  end

  @doc "True when card `id` can be sacrificed (not indestructible, not \"can't be sacrificed\")."
  def sacrificable?(game, id),
    do: not kw?(game, id, :cant_sacrifice) and not kw?(game, id, :indestructible)

  @doc "True when side `s` has a detector (Eyes of the Chancellor): it sees stealth and invisible."
  def detector?(_game, nil), do: false
  def detector?(game, s), do: Enum.any?(Zones.in_play(game, s), &kw?(game, &1, :detector))

  @doc "True for a Virtuoso."
  def virtuoso?(game, id), do: def_of(game, id).subtype == "Virtuoso"

  @doc "True for a unit with no rules text (tokens like Pirate, Frog; Tiger Cub, ...)."
  def vanilla?(game, id), do: unit?(game, id) and def_of(game, id).text == []

  @doc "True when `s` controls a card named `slug` in play."
  def controls?(_game, nil, _slug), do: false

  def controls?(game, s, slug),
    do: Enum.any?(Zones.in_play(game, s), &(game.cards[&1].card == slug))

  defp count_in_play(game, s, slug),
    do: Enum.count(Zones.in_play(game, s), &(game.cards[&1].card == slug))

  @doc "True when the card is in its controller's patrol zone on the other side's turn."
  def patrolling?(game, id) do
    case Zones.locate(game, id) do
      {s, :patrol, _slot} -> s != game.active
      _ -> false
    end
  end

  defp patrol_slot(game, id) do
    case Zones.locate(game, id) do
      {s, :patrol, slot} when s != game.active -> slot
      _ -> nil
    end
  end

  @doc "True when side `s` has Master Midori in play at her middle band or above."
  def midori_mid?(game, s) do
    Enum.any?(Zones.in_play(game, s), fn h ->
      c = game.cards[h]
      c.card == "master-midori" and c.level >= 5
    end)
  end

  @doc "True when side `s` has a hero of `spec` in play."
  def spec_hero?(game, s, spec),
    do: Enum.any?(Zones.in_play(game, s), &(hero?(game, &1) and spec(game, &1) == spec))

  @doc "A side effect flag (`side.effects`)."
  def side_effect(game, s, key), do: Map.get(game.sides[s].effects, key)

  # -- ATK and HP ------------------------------------------------------------------------------

  @doc "ATK now."
  def atk(game, id) do
    c = game.cards[id]
    {atk, _hp} = base(game, c)
    atk = Map.get(c.this_turn, :printed_atk, atk)
    s = controller(game, id)

    atk =
      atk + c.plus - c.minus + c.tmp_atk + frenzy(game, id, s) + elite(game, id) +
        static(game, id, s, :atk) + starlet(c) + ironbark(game, id)

    # Pestering Haunt: "Can't have more than 1 ATK."
    case CardRules.keyword(c.card, :max_atk) do
      nil -> atk
      max -> min(atk, max)
    end
  end

  @doc "HP now (before damage)."
  def hp(game, id) do
    c = game.cards[id]

    case base(game, c) do
      {_atk, hp} when is_integer(hp) ->
        s = controller(game, id)
        hp + c.plus - c.minus + c.tmp_hp + static(game, id, s, :hp)
    end
  end

  @doc "The printed ATK/HP of an instance (a hero: its level band)."
  def printed(c) do
    if c.level, do: band(c), else: {Cards.fetch!(c.card).atk || 0, Cards.fetch!(c.card).hp || 0}
  end

  # A feather rune makes a unit 3/1 while a Fairie Dragon is in play (rulings).
  defp base(game, c), do: if(feather?(game, c), do: {3, 1}, else: printed(c))

  defp feather?(game, c) do
    Map.get(c.extra, :feather) == true and
      Enum.any?([0, 1], &controls?(game, &1, "fairie-dragon"))
  end

  defp band(c) do
    case Cards.band(c.card, c.level) do
      %{atk: a, hp: h} -> {a, h}
      _ -> {0, 0}
    end
  end

  defp frenzy(game, id, s) do
    c = game.cards[id]

    n =
      (CardRules.keyword(c.card, :frenzy, hero_level(game, id)) || 0) + drakk_frenzy(game, id, s)

    if s == game.active, do: n, else: 0
  end

  # Drakk Ramhorn, middle band: your units get frenzy 1.
  defp drakk_frenzy(game, id, s) do
    drakk? =
      Enum.any?(Zones.in_play(game, s), fn h ->
        game.cards[h].card == "drakk-ramhorn" and game.cards[h].level >= 4
      end)

    if drakk? and unit?(game, id), do: 1, else: 0
  end

  defp elite(game, id), do: if(patrol_slot(game, id) == :elite, do: 1, else: 0)

  # Ironbark Treant: -2 ATK / +2 armor while patrolling.
  defp ironbark(game, id) do
    if game.cards[id].card == "ironbark-treant" and patrolling?(game, id), do: -2, else: 0
  end

  defp starlet(%{card: "star-crossed-starlet", damage: d}), do: d
  defp starlet(_c), do: 0

  # The bonuses that other cards give, `{atk, hp}` summed, picked by `stat`.
  defp static(_game, _id, nil, _stat), do: 0

  defp static(game, id, s, stat) do
    bonuses = [
      guide(game, id, s),
      partner(game, id),
      war_drums(game, id, s),
      midori(game, id, s),
      attached(game, id),
      leaf_and_claw(game, id, s),
      stampede(game, id, s),
      marked(game, id),
      trained(game, id),
      whisper(game, id, s)
    ]

    Enum.sum(for {a, h} <- bonuses, do: if(stat == :atk, do: a, else: h))
  end

  # Grounded Guide: your OTHER units get +1 ATK; your Virtuosos +2/+1 instead.
  defp guide(game, id, s) do
    if unit?(game, id) do
      n =
        Enum.count(
          Zones.in_play(game, s),
          &(&1 != id and game.cards[&1].card == "grounded-guide")
        )

      if virtuoso?(game, id), do: {2 * n, n}, else: {n, 0}
    else
      {0, 0}
    end
  end

  # Two Step: +2/+2 while its controller controls both partners.
  defp partner(game, id) do
    two_steps =
      for s <- [0, 1], t <- game.sides[s].zones.in_play, game.cards[t].card == "two-step", do: t

    if Enum.any?(two_steps, &(id in Map.get(game.cards[&1].extra, :partners, []))),
      do: {2, 2},
      else: {0, 0}
  end

  # War Drums: your units get +X ATK, X the number of units you have.
  defp war_drums(game, id, s) do
    drums = count_in_play(game, s, "war-drums")

    if drums > 0 and unit?(game, id) do
      units = Enum.count(Zones.in_play(game, s), &unit?(game, &1))
      {drums * units, 0}
    else
      {0, 0}
    end
  end

  # REVIEW: Master Midori's middle band uses the later patch text (research §14.1):
  # your units with no abilities get +2/+2 (and cost 1 less, `Codex.Rules.cost/3`).
  defp midori(game, id, s),
    do: if(vanilla?(game, id) and midori_mid?(game, s), do: {2, 2}, else: {0, 0})

  # Spirit of the Panda (+2/+2) and Final Showdown (+3/+3) on the card they attach to.
  defp attached(game, id) do
    Enum.reduce(attachments(game, id), {0, 0}, fn a, {x, y} ->
      case game.cards[a].card do
        "spirit-of-the-panda" -> {x + 2, y + 2}
        "final-showdown" -> {x + 3, y + 3}
        _ -> {x, y}
      end
    end)
  end

  @doc "The ongoing spells attached to card `id`."
  def attachments(game, id) do
    for s <- [0, 1],
        a <- game.sides[s].zones.in_play,
        Map.get(game.cards[a].extra, :attached) == id,
        do: a
  end

  # Might of Leaf and Claw: with 5+ growth runes, your units and heroes get +5/+5.
  defp leaf_and_claw(game, id, s) do
    strong =
      Enum.count(Zones.in_play(game, s), fn m ->
        game.cards[m].card == "might-of-leaf-and-claw" and
          Map.get(game.cards[m].extra, :growth, 0) >= 5
      end)

    if strong > 0 and force?(game, id), do: {5 * strong, 5 * strong}, else: {0, 0}
  end

  # Macciatus, The Whisperer: your Illusion units get +1/+1.
  defp whisper(game, id, s) do
    if controls?(game, s, "macciatus-the-whisperer") and illusion?(game, id),
      do: {1, 1},
      else: {0, 0}
  end

  # Elite Training (+1 ATK each) and The Art of War (+2 ATK), until the caster's next upkeep.
  defp trained(game, id) do
    c = game.cards[id]
    {Map.get(c.extra, :elite, 0) + if(Map.has_key?(c.extra, :art_of_war), do: 2, else: 0), 0}
  end

  # Vandy Anadrose's max level: +2/+2 until her side's next upkeep.
  defp marked(game, id),
    do: if(Map.has_key?(game.cards[id].extra, :vandy), do: {2, 2}, else: {0, 0})

  # Stampede: your units get +3 ATK / +3 armor this turn.
  defp stampede(game, id, s) do
    if side_effect(game, s, :stampede) && unit?(game, id), do: {3, 0}, else: {0, 0}
  end

  # -- armor -------------------------------------------------------------------------------------

  @doc """
  The armor card `id` has left this turn: the squad leader's 1 and Ironbark
  Treant's 2 while patrolling, this turn's armor (Rampant Growth, Dinosize,
  Argagarg Garg), Stampede's 3; minus what it absorbed this turn.
  """
  def armor(game, id) do
    c = game.cards[id]
    s = controller(game, id)
    slot = patrol_slot(game, id)

    total =
      if(slot == :squad_leader, do: 1, else: 0) +
        if(c.card == "ironbark-treant" and slot != nil, do: 2, else: 0) +
        c.tmp_armor + if(side_effect(game, s, :stampede) && unit?(game, id), do: 3, else: 0) +
        Map.get(c.extra, :elite, 0) + if(Map.has_key?(c.extra, :art_of_war), do: 2, else: 0)

    max(total - c.armor_dmg, 0)
  end

  # -- keywords ------------------------------------------------------------------------------

  @doc "A keyword now: printed or given by another card."
  def kw?(game, id, key) do
    c = game.cards[id]

    cond do
      Map.get(c.extra, :polymorph) -> false
      silenced?(game, id) -> false
      printed_kw?(game, id, key) -> true
      Map.get(c.this_turn, key) == true -> true
      Map.get(c.extra, key) == true -> true
      granted?(game, id, key) -> true
      key in @mimic_keys and c.card == "wandering-mimic" -> mimic?(game, id, key)
      true -> false
    end
  end

  defp printed_kw?(game, id, key) do
    c = game.cards[id]
    level = hero_level(game, id)

    kws =
      CardRules.keywords(c.card) ++
        if(level, do: CardRules.hero_keywords(c.card, level), else: [])

    Keyword.get(kws, key) not in [nil, false]
  end

  # The level of a hero whose abilities count (nil for other cards and for a
  # silenced hero: Free Speech).
  defp hero_level(game, id) do
    if silenced?(game, id), do: nil, else: game.cards[id].level
  end

  @doc """
  True for a hero whose side is silenced (Free Speech): it can't cast spells
  and has no abilities until after that side's next turn.
  """
  def silenced?(game, id) do
    game.cards[id].level != nil and
      case controller(game, id) do
        nil -> false
        s -> side_effect(game, s, :silenced) != nil
      end
  end

  defp mimic?(game, id, key) do
    Enum.any?(for(s <- [0, 1], o <- Zones.in_play(game, s), do: o), fn o ->
      o != id and game.cards[o].card != "wandering-mimic" and force?(game, o) and
        (printed_kw?(game, o, key) or granted?(game, o, key))
    end)
  end

  # Keywords that other cards give.
  defp granted?(game, id, :haste) do
    s = controller(game, id)

    (virtuoso?(game, id) and controls?(game, s, "nimble-fencer")) or
      (game.cards[id].card == "squirrel" and controls?(game, s, "moss-ancient"))
  end

  defp granted?(game, id, :flying) do
    c = game.cards[id]

    (c.card == "master-midori" and c.level >= 8 and controller(game, id) == game.active) or
      feather?(game, c)
  end

  defp granted?(game, id, :stealth) do
    s = controller(game, id)
    c = game.cards[id]

    c.stealth or
      (unit?(game, id) and controls?(game, s, "behind-the-ferns") and atk(game, id) <= 3)
  end

  defp granted?(game, id, :invisible) do
    s = controller(game, id)
    c = game.cards[id]

    case c.card do
      _ when is_map_key(c.extra, :eyes) ->
        true

      "stalking-tiger" ->
        Enum.any?(Zones.in_play(game, s), &(hero?(game, &1) and spec(game, &1) == "Feral"))

      "squirrel" ->
        controls?(game, s, "moss-ancient")

      _ ->
        false
    end
  end

  defp granted?(game, id, :swift) do
    s = controller(game, id)

    controls?(game, s, "blademaster") or
      (unit?(game, id) and side_effect(game, s, :ferocity) != nil) or
      Map.has_key?(game.cards[id].extra, :art_of_war)
  end

  defp granted?(game, id, :armor_piercing),
    do: unit?(game, id) and side_effect(game, controller(game, id), :ferocity) != nil

  defp granted?(game, id, :readiness),
    do: Enum.any?(attachments(game, id), &(game.cards[&1].card == "final-showdown"))

  defp granted?(game, id, :overpower) do
    c = game.cards[id]
    c.plus > 0 and force?(game, id) and controls?(game, controller(game, id), "blooming-elm")
  end

  defp granted?(game, id, :long_range) do
    c = game.cards[id]

    # Bluecoat Musketeer: "While this has exactly 1 ATK, it has long-range."
    (c.card == "bluecoat-musketeer" and atk(game, id) == 1) or skeletal_archery?(game, id)
  end

  defp granted?(game, id, :anti_air),
    do: skeletal_archery?(game, id) or Map.get(game.cards[id].extra, :elite, 0) > 0

  defp granted?(game, id, :sparkshot), do: Map.get(game.cards[id].extra, :elite, 0) > 0

  defp granted?(game, id, :unstoppable),
    do: Map.has_key?(game.cards[id].extra, :art_of_war) or liberty?(game, id)

  defp granted?(game, id, key) when key in [:unattackable, :untargetable], do: liberty?(game, id)

  defp granted?(_game, _id, _key), do: false

  # Liberty Gryphon: unstoppable, unattackable and untargetable while its side
  # controls an Illusion with another name.
  defp liberty?(game, id) do
    c = game.cards[id]
    s = controller(game, id)

    c.card == "liberty-gryphon" and s != nil and
      Enum.any?(Zones.in_play(game, s), fn o ->
        game.cards[o].card != "liberty-gryphon" and illusion?(game, o)
      end)
  end

  # Skeletal Archery: "Your Skeletons have long-range and anti-air."
  defp skeletal_archery?(game, id) do
    subtype?(game, id, "Skeleton") and controls?(game, controller(game, id), "skeletal-archery")
  end

  @doc "Haste (S1 p. 17)."
  def haste?(game, id), do: kw?(game, id, :haste)

  @doc "Stealth (printed, this turn, or given)."
  def stealth?(game, id), do: kw?(game, id, :stealth)

  @doc "Swift strike."
  def swift?(game, id), do: kw?(game, id, :swift)

  @doc "Readiness."
  def readiness?(game, id), do: kw?(game, id, :readiness)

  @doc """
  Resist of a card against the other side: printed (and a hero's), +1 in the
  lookout slot while patrolling, +1 for units with Calamandra Moss's middle
  band, +1 with Final Showdown attached.
  """
  def resist(game, id) do
    c = game.cards[id]
    s = controller(game, id)
    printed = CardRules.keyword(c.card, :resist, hero_level(game, id)) || 0
    lookout = if patrol_slot(game, id) == :lookout, do: 1, else: 0

    calamandra =
      if unit?(game, id) and
           Enum.any?(
             Zones.in_play(game, s),
             &(game.cards[&1].card == "calamandra-moss" and game.cards[&1].level >= 3)
           ),
         do: 1,
         else: 0

    showdown = Enum.count(attachments(game, id), &(game.cards[&1].card == "final-showdown"))
    printed + lookout + calamandra + showdown
  end
end
