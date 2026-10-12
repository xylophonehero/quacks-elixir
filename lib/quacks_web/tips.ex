defmodule QuacksWeb.Tips do
  @moduledoc """
  Round 38: the first-time hints (tour design T2). The first time a moment comes
  (the first fortune card, the first brew, the first choice, ...), the game page
  shows one small parchment card in the bottom context area, and a gold ring
  pulses on the area the card talks about (app.css `[data-tip]`).

  `pick/2` is the whole rule: "moment + seen keys -> hint or nil". The page
  (`QuacksWeb.GameLive`) names the moment from its assigns (`moment` below) and
  keeps the seen keys of this browser (`localStorage["quacks:tips"]`, sent with
  the `RevealSettings` push). The first brew has a chain of 3 hints (`brew`,
  `bag`, `players`).

  A moment is a map with `:phase` and, for `:brew`, the seat's white total
  (`:white`), its rat tails (`:rats`) and the chips it drew (`:drawn`):

    * `:card` - a new fortune card waits over the pot
    * `:brew` - this seat can draw
    * `:choice` - a choice waits in the bar
    * `:scoring` - the first step of the round's results plays on the tiles
      (`:auto` true in Auto mode: no Next then)
    * `:scored` - the "Round scored" step plays (with the score track)
    * `:shop` - the shop's buy step
    * `:none` - nothing to say now
  """

  @typedoc "One hint: its key (also its seen key), head, text and main button."
  @type tip :: %{
          key: String.t(),
          label: String.t(),
          text: String.t(),
          button: String.t(),
          place: :bar | :pot
        }

  @type moment :: %{required(:phase) => atom(), optional(atom()) => term()}

  @tips %{
    "card" => %{
      label: "First fortune card",
      text:
        "A new fortune card every round. It changes the rules for this round only. " <>
          "Tap the card in the corner to read it again.",
      button: "Got it",
      place: :bar
    },
    "brew" => %{
      label: "First brew · 1 of 3",
      text:
        "Tap Draw to add a chip to your pot. Tap Stop to keep what you have. " <>
          "More than 7 white and your pot explodes.",
      button: "Next tip",
      place: :bar
    },
    "bag" => %{
      label: "First brew · 2 of 3",
      text: "Your bag. Tap the magnifier to see the chips that are still in it.",
      button: "Next tip",
      place: :bar
    },
    "players" => %{
      label: "First brew · 3 of 3",
      text:
        "These are the players. Each tile shows their score and how their brew is going. " <>
          "Tap a tile for more.",
      button: "Got it",
      place: :bar
    },
    "risk" => %{
      label: "White 3 or more",
      text:
        "The % is the chance that your next chip explodes the pot. " <>
          "If your last chip is white, the flask can put it back.",
      button: "Got it",
      place: :bar
    },
    "choice" => %{
      label: "First choice",
      text: "Choices show here, above your buttons. Pick one, then the game goes on.",
      button: "Got it",
      place: :bar
    },
    "scoring" => %{
      label: "First scoring",
      text: "The round is scored one step at a time. Tap Next to go on, or Skip to see the end.",
      button: "Got it",
      place: :pot
    },
    "scored" => %{
      label: "First round scored",
      text: "Points move you along the track at the top. The most points after 9 rounds wins.",
      button: "Got it",
      place: :pot
    },
    "shop" => %{
      label: "First shop",
      text: "Spend the coins from this round on new chips. Coins you do not spend are lost.",
      button: "Got it",
      place: :bar
    },
    "rats" => %{
      label: "First rat tails",
      text:
        "You are behind on points, so the rat gives you a head start. " <>
          "Your first chip goes after it.",
      button: "Got it",
      place: :bar
    }
  }

  @doc "Every hint key, e.g. to keep only known keys from the browser."
  @spec keys() :: [String.t()]
  def keys, do: Map.keys(@tips)

  @doc "The hint for `key`."
  @spec tip(String.t()) :: tip()
  def tip(key), do: Map.put(Map.fetch!(@tips, key), :key, key)

  @doc """
  The hint for `moment`, or nil: the first of the moment's hints whose key is not
  in `seen`. Pure: the same moment and seen keys give the same hint.
  """
  @spec pick(moment(), Enumerable.t()) :: tip() | nil
  def pick(moment, seen) do
    moment
    |> candidates()
    |> Enum.find(&(&1 not in seen))
    |> then(&(&1 && moment |> tip_for(&1)))
  end

  # In Auto mode the results have no Next: they go on by themselves.
  defp tip_for(%{phase: :scoring, auto: true}, "scoring" = key),
    do: %{
      tip(key)
      | text:
          "The round is scored one step at a time. It goes on by itself; tap Skip to see the end."
    }

  defp tip_for(_moment, key), do: tip(key)

  # The hints of a moment, first to last. The brew: the rat tails before the
  # first chip, then the first-brew chain, then the risk once white reaches 3.
  defp candidates(%{phase: :brew} = moment) do
    rats? = Map.get(moment, :rats, 0) > 0 and Map.get(moment, :drawn, 0) == 0
    rats = if rats?, do: ["rats"], else: []
    risk = if Map.get(moment, :white, 0) >= 3, do: ["risk"], else: []
    rats ++ ["brew", "bag", "players"] ++ risk
  end

  defp candidates(%{phase: phase})
       when phase in [:card, :choice, :scoring, :scored, :shop],
       do: [Atom.to_string(phase)]

  defp candidates(_moment), do: []

  @doc """
  The browser's stored state (`{"v":1,"seen":[...],"off":false}`) as
  `%{seen: MapSet, off: boolean}`; unknown keys and a wrong version are dropped.
  """
  @spec from_browser(term()) :: %{seen: MapSet.t(), off: boolean()}
  def from_browser(%{"v" => 1} = stored) do
    seen = Map.get(stored, "seen", [])
    seen = if is_list(seen), do: Enum.filter(seen, &(&1 in keys())), else: []
    %{seen: MapSet.new(seen), off: Map.get(stored, "off") == true}
  end

  def from_browser(_stored), do: %{seen: MapSet.new(), off: false}

  @doc "The state to store in the browser (`localStorage[\"quacks:tips\"]`)."
  @spec to_browser(%{seen: MapSet.t(), off: boolean()}) :: map()
  def to_browser(%{seen: seen, off: off}), do: %{v: 1, seen: Enum.sort(seen), off: off}
end
