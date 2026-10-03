defmodule Quacks.AI.Shop do
  @moduledoc """
  The bot in its shop step (`docs/research/ai-opponents.md` §3.3): buy the best
  scored `{:buy, chips}`, then spend rubies by the profile's `ruby_plan`, then
  `:end_round`. Round 9: `{:rubies, :vp}` while it can.
  """

  alias Quacks.AI.Profile
  alias Quacks.{Game, Player}

  @two_chip_bonus 0.5
  @penalty 2.0

  @doc "The next shop action for `seat` out of `legal`."
  @spec pick(Game.t(), Game.seat(), Profile.t(), [Game.action()]) :: Game.action()
  def pick(%{round: 9}, _seat, _profile, legal),
    do: if({:rubies, :vp} in legal, do: {:rubies, :vp}, else: :end_round)

  def pick(game, seat, profile, legal) do
    case for {:buy, chips} <- legal, do: chips do
      [] -> rubies(game, profile, legal) || :end_round
      buys -> {:buy, best_buy(buys, game.round, owned(game, seat), profile)}
    end
  end

  @doc "The buy with the highest `score/4`; `[]` only when no chip scores above 0."
  @spec best_buy([[Quacks.Rules.Chips.chip()]], 1..9, [Quacks.Rules.Chips.chip()], Profile.t()) ::
          [Quacks.Rules.Chips.chip()]
  def best_buy(buys, round, owned, profile) do
    best = Enum.max_by(buys, &score(&1, round, owned, profile))
    if score(best, round, owned, profile) > 0, do: best, else: []
  end

  @doc """
  How much the bot likes buying `chips` in `round` when it owns `owned`: per chip its
  colour weight times its value weight (4-chips gain a little each round), a bonus
  for two chips, a penalty for black over `black_max`, purple before `purple_from`
  or in round 8, and yellow 1 from round 7.
  """
  @spec score([Quacks.Rules.Chips.chip()], 1..9, [Quacks.Rules.Chips.chip()], Profile.t()) ::
          float
  def score([], _round, _owned, _profile), do: 0.0

  def score(chips, round, owned, profile) do
    blacks = Enum.count(owned, &match?({:black, _}, &1))
    bonus = if length(chips) == 2, do: @two_chip_bonus, else: 0.0

    chips
    |> Enum.map(&(chip_value(&1, round, profile) - penalty(&1, round, blacks, profile)))
    |> Enum.sum()
    |> Kernel.+(bonus)
  end

  defp chip_value({colour, value}, round, profile) do
    weight = Map.get(profile.colour_weight, colour, 0.8)
    base = Map.get(profile.value_weight, value, value * 0.6)
    weight * (base + 0.05 * round * (value - 1))
  end

  defp penalty({:black, _}, _round, blacks, %{black_max: max}) when blacks >= max, do: @penalty
  defp penalty({:purple, _}, round, _b, %{purple_from: from}) when round < from, do: @penalty
  defp penalty({:purple, _}, 8, _blacks, _profile), do: @penalty
  defp penalty({:yellow, 1}, round, _blacks, _profile) when round >= 7, do: 0.5
  defp penalty(_chip, _round, _blacks, _profile), do: 0.0

  # The first ruby buy of the plan that is legal; droplets only up to `droplet_until`.
  defp rubies(game, profile, legal) do
    Enum.find_value(profile.ruby_plan, fn
      :droplet when game.round > profile.droplet_until -> nil
      what -> if {:rubies, what} in legal, do: {:rubies, what}
    end)
  end

  defp owned(game, seat) do
    p = Game.player(game, seat)
    p.bag ++ Player.pot_chips(p) ++ p.bowl
  end
end
