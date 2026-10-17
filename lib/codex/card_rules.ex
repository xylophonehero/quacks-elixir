defmodule Codex.CardRules do
  @moduledoc """
  The rules data of the cards (research §10, §16): keywords and what each card's
  text targets. Plain data; the logic is in `Codex.Stats`, `Codex.Effects` and
  `Codex.Combat`.

  ## Keywords

  `keywords/1`: the printed keywords of a card (haste, flying, frenzy 1, ...).
  Keywords that other cards give (Nimble Fencer, Blademaster) are in
  `Codex.Stats`.

  ## Targets

  `targets/1`: the target slots of a spell or an "Arrives:" ability, a list of
  target kinds. A kind names the things a slot can take:

  - `:patroller`: an opposing patroller.
  - `:force`: a unit or hero in play (either side).
  - `:my_force_no_plus`: your unit or hero with no +1/+1 rune.
  - `:unit`: a unit in play (either side).
  - `:unit_t01`: a tech 0 or tech I unit. `:unit_t0`, `:unit_t1`, `:unit_t2`:
    a unit of that tech level (Final Smash; each may be skipped).
  - `:my_unit_unpartnered`: your unit with no dance partner (Two Step takes two).
  - `:building`: any building (a base, a tech building, an add-on).
  - `:opp_patroller_t01`: an opposing tech 0 or tech I patroller (River Montoya).
  """

  @keywords %{
    "timely-messenger" => [haste: true],
    "brick-thief" => [resist: 1],
    "helpful-turtle" => [healing: 1],
    "fruit-ninja" => [frenzy: 1],
    "granfalloon-flagbearer" => [flagbearer: true],
    "angry-dancer" => [unstoppable: true],
    "sneaky-pig" => [haste: true],
    "eggship" => [flying: true],
    "cloud-sprite" => [flying: true],
    "leaping-lizard" => [anti_air: true],
    "revolver-ocelot" => [sparkshot: true],
    "harvest-reaper" => [overpower: true],
    "trojan-duck" => [obliterate: 2],
    "backstabber" => [invisible: true]
  }

  # Spells: the target slots. A slot kind in a tuple `{:optional, kind}` may be
  # skipped (nil).
  @spell_targets %{
    "spark" => [:patroller],
    "bloom" => [:my_force_no_plus],
    "wither" => [:force],
    "wrecking-ball" => [:building],
    "the-boot" => [:unit_t01],
    "intimidate" => [:force],
    "final-smash" => [{:optional, :unit_t0}, {:optional, :unit_t1}, {:optional, :unit_t2}],
    "harmony" => [],
    "discord" => [],
    "two-step" => [:my_unit_unpartnered, :my_unit_unpartnered],
    "appel-stomp" => [:patroller]
  }

  # "Arrives:" abilities with a target. The slot may be empty only when there is
  # no legal target ("do as much as you can", S1 p. 17).
  @arrive_targets %{
    "hired-stomper" => [:unit],
    "brick-thief" => [:building],
    "trojan-duck" => [:building]
  }

  @doc "The printed keywords of a card (a keyword list)."
  @spec keywords(String.t()) :: keyword
  def keywords(slug), do: Map.get(@keywords, slug, [])

  @doc "The value of keyword `key` of a card, or nil."
  @spec keyword(String.t(), atom) :: term
  def keyword(slug, key), do: Keyword.get(keywords(slug), key)

  @doc "The target slots of a spell (`[]`: no target), or nil for a card that is not a spell here."
  @spec spell_targets(String.t()) :: [term] | nil
  def spell_targets(slug), do: Map.get(@spell_targets, slug)

  @doc "The target slots of a unit's \"Arrives:\" ability (`[]`: none)."
  @spec arrive_targets(String.t()) :: [term]
  def arrive_targets(slug), do: Map.get(@arrive_targets, slug, [])

  @doc "The slugs whose text the engine runs (the rest are played as \"manual\")."
  @spec implemented() :: [String.t()]
  def implemented,
    do: Map.keys(@spell_targets) ++ Map.keys(@keywords) ++ Map.keys(@arrive_targets)

  @doc "A token: a unit that is never in a deck (Dancer, Angry Dancer, Mercenary)."
  @spec token?(String.t()) :: boolean
  def token?(slug), do: slug in ~w(dancer angry-dancer mercenary)
end
