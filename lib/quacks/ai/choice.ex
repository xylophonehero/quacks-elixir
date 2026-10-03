defmodule Quacks.AI.Choice do
  @moduledoc """
  A static scorer for the choices of `choice_rule: :scored` (`docs/research/jev-plan.md`
  §4): fortune cards, chip choices (Sets 2–6), the gold witch and the essence space.
  Every option gets a value in VP from one table, and the bot takes the highest; a
  pass (`:skip`, `:chip_done`, `:witch_done`, `:return_all`) is worth 0.

  - 1 VP is 1. A chip is worth its Set 1 price times the round's `coin_weight`
    (a chip bought late is worth less). A ruby is `ruby_value`.
  - A droplet step pays one space every round still to come; a space is a coin
    and a little VP.
  - A white 1 out of the bag is worth more early than late.
  """

  alias Quacks.AI.Profile
  alias Quacks.Game
  alias Quacks.Game.Potions
  alias Quacks.Rules.Chips

  # The P13 upgrades (`Quacks.Game.Fortune`).
  @upgrade %{
    {:green, 1} => {:green, 2},
    {:green, 2} => {:green, 4},
    {:blue, 1} => {:blue, 2},
    {:blue, 2} => {:blue, 4},
    {:red, 1} => {:red, 2},
    {:red, 2} => {:red, 4},
    {:yellow, 1} => {:yellow, 2},
    {:yellow, 2} => {:yellow, 4}
  }

  # P2 trades (`Quacks.Game.Evaluation`): purple chips spent, what comes back.
  @trades %{
    1 => {[{:black, 1}], 1, 1, 0},
    2 => {[{:green, 1}, {:blue, 2}], 3, 0, 1},
    3 => {[{:yellow, 4}], 6, 1, 2}
  }

  @doc "The legal action with the highest `value/4`; the first on a tie."
  @spec pick(Game.t(), Game.seat(), Profile.t(), [Game.action()]) :: Game.action()
  def pick(game, seat, profile, legal),
    do: Enum.max_by(legal, &value(&1, game, seat, profile), fn -> hd(legal) end)

  @doc """
  The value in VP of one choice for `seat`.

      iex> game = Quacks.Game.new(seed: {1, 2, 3}, players: 2)
      iex> Quacks.AI.Choice.value({:fortune, :vp}, %{game | fortune_card: :p6}, 0, Quacks.AI.Profile.get(:balanced))
      4
  """
  @spec value(Game.action(), Game.t(), Game.seat(), Profile.t()) :: number
  def value({:fortune, choice}, game, seat, profile), do: fortune(choice, game, seat, profile)
  def value({:chip, choice}, game, seat, profile), do: chip(choice, game, seat, profile)
  def value({:witch, :gold}, _game, _seat, _profile), do: 1.0
  def value({:essence, {:space, n}}, _game, _seat, _profile), do: n
  def value(_pass, _game, _seat, _profile), do: 0

  # -- fortune cards -------------------------------------------------------------------

  defp fortune({:take, chip}, %{fortune_card: :p3} = game, _seat, profile),
    do: worth(chip, game.round, profile) - profile.ruby_value

  defp fortune({:take, chip}, game, _seat, profile), do: worth(chip, game.round, profile)
  defp fortune(:rubies, _game, _seat, profile), do: 3 * profile.ruby_value

  defp fortune(:vp, %{fortune_card: :p10} = game, seat, _profile),
    do: game |> Game.player(seat) |> Map.fetch!(:rat_stone)

  defp fortune(:vp, _game, _seat, _profile), do: 4
  defp fortune(:remove_white, game, _seat, _profile), do: white_out(game.round)
  defp fortune(:droplet, game, _seat, profile), do: 2 * droplet(game.round, profile)

  defp fortune({:rats_back, n}, game, _seat, profile),
    do: n * (profile.ruby_value - space(game.round, profile))

  defp fortune({:upgrade, chip}, game, _seat, profile),
    do:
      worth(Map.get(@upgrade, chip, chip), game.round, profile) - worth(chip, game.round, profile)

  defp fortune({:place, chip}, game, seat, profile), do: place(chip, game, seat, profile)
  defp fortune(_skip, _game, _seat, _profile), do: 0

  # B7: a coloured chip moves the pot; a white only when it cannot explode.
  defp place({:white, w}, game, seat, profile) do
    room = Potions.explode_above(game, seat) - Game.white_sum(game, seat)
    if w <= room, do: w * space(game.round, profile) - 0.5, else: -10
  end

  defp place({_colour, v}, game, _seat, profile), do: v * space(game.round, profile)

  # -- chip choices --------------------------------------------------------------------

  defp chip({:gain, c}, game, _seat, profile), do: worth(c, game.round, profile)
  defp chip({:starter, c}, game, _seat, profile), do: worth(c, game.round, profile)

  defp chip({:buy, chips}, game, _seat, profile),
    do: chips |> Enum.map(&worth(&1, game.round, profile)) |> Enum.sum()

  defp chip({:upgrade, from, to}, game, _seat, profile),
    do: worth(to, game.round, profile) - worth(from, game.round, profile)

  defp chip({:pay_ruby_move, n}, game, _seat, profile),
    do: n * (droplet(game.round, profile) - profile.ruby_value)

  defp chip({:purple_trade, tier}, game, _seat, profile) do
    {chips, vp, rubies, droplets} = @trades[tier]

    vp + rubies * profile.ruby_value + droplets * droplet(game.round, profile) +
      Enum.sum(Enum.map(chips, &worth(&1, game.round, profile))) -
      tier * worth({:purple, 1}, game.round, profile)
  end

  defp chip(:yellow_ruby, game, _seat, profile),
    do: 3 * space(game.round, profile) - profile.ruby_value

  defp chip(_other, _game, _seat, _profile), do: 0

  # -- the table -----------------------------------------------------------------------

  defp worth({:white, _}, _round, _profile), do: 0

  defp worth({_colour, value} = chip, round, profile) do
    price = if chip in Chips.shop(), do: Chips.price(chip), else: 4 * value
    price * profile.coin_weight[round]
  end

  # One space further this round: a coin and a little VP.
  defp space(round, profile), do: profile.coin_weight[round] + 0.2

  # A droplet step: one space in every round still to come (this one included).
  defp droplet(round, profile), do: (10 - round) * space(round, profile) * 0.5

  defp white_out(round), do: max(9 - round, 1) * 0.5
end
