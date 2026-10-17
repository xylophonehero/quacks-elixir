defmodule Codex.Stats do
  @moduledoc """
  What a card in play is now: ATK, HP and keywords, with every bonus (research
  §5, §8, §10, §16). The controller of a card is the side whose zone holds it.

  ATK = printed (a hero: its level band) + runes + this-turn changes, plus:
  frenzy on its controller's turn; +1 in the elite slot on the other side's turn
  (S1 p. 5); Grounded Guide (your other units +1 ATK, your Virtuosos +2/+1
  instead); Two Step partners +2/+2; Star-Crossed Starlet +1 ATK per damage.
  """

  alias Codex.{CardRules, Cards, Zones}

  @doc "The controller of card `id` (nil when it is not in a side's zone)."
  def controller(game, id), do: Zones.controller(game, id)

  @doc "True for a unit or a hero."
  def force?(game, id), do: unit?(game, id) or hero?(game, id)

  @doc "True for a unit (tokens too)."
  def unit?(game, id), do: Cards.fetch!(game.cards[id].card).type == "Unit"

  @doc "True for a hero."
  def hero?(game, id), do: Cards.fetch!(game.cards[id].card).type == "Hero"

  @doc "The tech level of a unit (tokens are tech 0), nil for other cards."
  def tech(game, id) do
    d = Cards.fetch!(game.cards[id].card)
    if d.type == "Unit", do: d.tech || 0
  end

  @doc "True when the card is in its controller's patrol zone on the other side's turn."
  def patrolling?(game, id) do
    case Zones.locate(game, id) do
      {s, :patrol, _slot} -> s != game.active
      _ -> false
    end
  end

  @doc "ATK now."
  def atk(game, id) do
    c = game.cards[id]
    {atk, _hp} = printed(c)
    s = controller(game, id)

    atk + c.plus - c.minus + c.tmp_atk + frenzy(game, id, s) + elite(game, id) +
      guide(game, id, s, :atk) + partner(game, id) + starlet(c)
  end

  @doc "HP now (before damage)."
  def hp(game, id) do
    c = game.cards[id]
    {_atk, hp} = printed(c)
    s = controller(game, id)
    hp + c.plus - c.minus + c.tmp_hp + guide(game, id, s, :hp) + partner(game, id)
  end

  @doc "The printed ATK/HP of an instance (a hero: its level band)."
  def printed(c) do
    case c.level && Cards.band(c.card, c.level) do
      %{atk: a, hp: h} -> {a, h}
      _ -> {Cards.fetch!(c.card).atk || 0, Cards.fetch!(c.card).hp || 0}
    end
  end

  defp frenzy(game, id, s) do
    n = CardRules.keyword(game.cards[id].card, :frenzy) || 0
    if s == game.active, do: n, else: 0
  end

  defp elite(game, id) do
    case Zones.locate(game, id) do
      {s, :patrol, :elite} when s != game.active -> 1
      _ -> 0
    end
  end

  # Grounded Guide: your OTHER units get +1 ATK; your Virtuosos +2/+1 instead.
  defp guide(_game, _id, nil, _stat), do: 0

  defp guide(game, id, s, stat) do
    if unit?(game, id) do
      guides =
        for g <- Zones.in_play(game, s), g != id, game.cards[g].card == "grounded-guide", do: g

      virtuoso? = virtuoso?(game, id)

      case {stat, virtuoso?} do
        {:atk, true} -> 2 * length(guides)
        {:atk, false} -> length(guides)
        {:hp, true} -> length(guides)
        {:hp, false} -> 0
      end
    else
      0
    end
  end

  # Two Step: +2/+2 while its controller controls both partners.
  defp partner(game, id) do
    if Enum.any?(two_steps(game), &(id in Map.get(game.cards[&1].extra, :partners, []))),
      do: 2,
      else: 0
  end

  defp two_steps(game),
    do:
      for(s <- [0, 1], t <- game.sides[s].zones.in_play, game.cards[t].card == "two-step", do: t)

  defp starlet(%{card: "star-crossed-starlet", damage: d}), do: d
  defp starlet(_c), do: 0

  @doc ~s{The colour of a card ("Neutral", "Red", "Green", ...).}
  def color(game, id), do: Cards.fetch!(game.cards[id].card).color

  @doc "True when side `s` has Master Midori in play at her middle band or above."
  def midori_mid?(game, s) do
    Enum.any?(Zones.in_play(game, s), fn h ->
      c = game.cards[h]
      c.card == "master-midori" and c.level >= 5
    end)
  end

  @doc "True for a Virtuoso."
  def virtuoso?(game, id), do: Cards.fetch!(game.cards[id].card).subtype == "Virtuoso"

  @doc "True when `s` controls a card named `slug` in play."
  def controls?(game, s, slug),
    do: Enum.any?(Zones.in_play(game, s), &(game.cards[&1].card == slug))

  # -- keywords ------------------------------------------------------------------------------

  @doc "Haste: printed, or a Virtuoso while its controller has Nimble Fencer."
  def haste?(game, id) do
    CardRules.keyword(game.cards[id].card, :haste) == true or
      (virtuoso?(game, id) and controls?(game, controller(game, id), "nimble-fencer"))
  end

  @doc "A printed keyword (flying, anti_air, unstoppable, invisible, sparkshot, overpower, ...)."
  def kw?(game, id, key), do: CardRules.keyword(game.cards[id].card, key) not in [nil, false]

  @doc "Stealth this turn (Sneaky Pig)."
  def stealth?(game, id), do: game.cards[id].stealth

  @doc "Swift strike: the units and heroes of a side with Blademaster."
  def swift?(game, id), do: controls?(game, controller(game, id), "blademaster")

  @doc "Readiness: Troq Bashar at max level."
  def readiness?(game, id) do
    c = game.cards[id]
    c.card == "troq-bashar" and c.level >= Cards.max_level(c.card)
  end

  @doc "Resist of a card against the other side: printed, +1 in the lookout slot while patrolling."
  def resist(game, id) do
    printed = CardRules.keyword(game.cards[id].card, :resist) || 0

    lookout =
      case Zones.locate(game, id) do
        {s, :patrol, :lookout} when s != game.active -> 1
        _ -> 0
      end

    printed + lookout
  end
end
