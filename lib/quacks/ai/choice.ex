defmodule Quacks.AI.Choice do
  @moduledoc """
  A static scorer for the choices of `choice_rule: :scored` (`docs/research/jev-plan.md`
  §4): fortune cards, chip choices (Sets 2–6), the gold witch, the copper witch C1's
  upgrade and the essence space.
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

  # The P13 upgrades (`Quacks.Game.Fortune`), also the copper witch C1's.
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

  @penny_order %{silver: 0, copper: 0.1, gold: 0.2}

  # One bonus-die roll: about 1 VP (1 VP, 2 VP, a ruby, a droplet step, an orange 1).
  @roll 1.2

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

  # Round 45: C1 upgrades pot chips; her penny is 2 VP at the end (a visit is free).
  def value({:witch, from, {:upgrade, chips}}, game, _seat, profile) do
    gain =
      Enum.sum(
        Enum.map(
          chips,
          &(worth(@upgrade[&1], game.round, profile) - worth(&1, game.round, profile))
        )
      )

    if from == :visit, do: gain, else: gain - 2
  end

  # AB8: the visiting witch costs no penny.
  def value({:witch, :visit}, _game, _seat, _profile), do: 2.0
  def value({:essence, {:space, n}}, _game, _seat, _profile), do: n
  def value(_pass, _game, _seat, _profile), do: 0

  # -- fortune cards -------------------------------------------------------------------

  defp fortune({:take, chip}, %{fortune_card: :p3} = game, _seat, profile),
    do: worth(chip, game.round, profile) - profile.ruby_value

  defp fortune({:take, chip}, %{fortune_card: :ab1} = game, seat, profile) do
    {:swap, old} = Enum.find_value(game.log, &ab1_swap(&1, seat))
    worth(chip, game.round, profile) - worth(old, game.round, profile)
  end

  # The Alchemists box: AP3 costs rubies, AP9 rat tails, AP10 droplet spaces.
  defp fortune({:take, {_, v} = chip}, %{fortune_card: :ap3} = game, _seat, profile),
    do: worth(chip, game.round, profile) - v * profile.ruby_value

  defp fortune({:take, {_, v} = chip}, %{fortune_card: :ap9} = game, _seat, profile),
    do: worth(chip, game.round, profile) - 2 * v * space(game.round, profile)

  defp fortune({:take, {_, v} = chip}, %{fortune_card: :ap10} = game, _seat, profile),
    do: worth(chip, game.round, profile) - div(v, 2) * droplet(game.round, profile)

  defp fortune({:take, chip}, game, _seat, profile), do: worth(chip, game.round, profile)
  defp fortune(:rubies, %{fortune_card: :ap3}, _seat, profile), do: 2 * profile.ruby_value
  defp fortune(:rubies, _game, _seat, profile), do: 3 * profile.ruby_value

  defp fortune(:bundle, game, _seat, profile),
    do: profile.ruby_value + @roll + 3 * space(game.round, profile)

  defp fortune(:rats, game, _seat, profile), do: 8 * space(game.round, profile)
  defp fortune(:rolls, _game, _seat, _profile), do: 4 * @roll

  defp fortune({:cherish, k}, game, _seat, profile),
    do: k * (3 * space(game.round, profile) - profile.ruby_value)

  # AP7: a penny is 2 VP at the end and one witch call; the chip comes next. Spend
  # the silver penny first.
  defp fortune({:penny, colour}, game, _seat, profile),
    do: worth({:green, 4}, game.round, profile) - 3 - Map.fetch!(@penny_order, colour)

  # AP8: the left neighbour gets the smaller gift (a white 1 out, not a free chip).
  defp fortune({:gift, :white}, _game, _seat, _profile), do: 0
  defp fortune({:gift, :chip}, _game, _seat, _profile), do: -1

  # AB1: a 2-chip swaps up to a 4-chip; a 4-chip only to another colour.
  defp fortune({:swap, {_, 2}}, _game, _seat, _profile), do: 1
  defp fortune({:swap, {_, _}}, _game, _seat, _profile), do: -1

  defp fortune(:droplet, %{fortune_card: :ap4} = game, _seat, profile),
    do: 3 * droplet(game.round, profile)

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

  defp ab1_swap({seat, {:fortune, :ab1, {:swap, _} = swap}}, seat), do: swap
  defp ab1_swap(_entry, _seat), do: nil

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
