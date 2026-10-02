defmodule Quacks.Game.Potions do
  @moduledoc """
  The potions phase for one seat (rulebook §3.1, §4): drawing, placing, the flask,
  the explosion and the on-draw chip effects (red, yellow, blue).

  Plain functions called from `Quacks.Game`. They take the whole game because draws
  use the shared `rng` and every event goes to the shared log.
  """

  alias Quacks.Game
  alias Quacks.Player
  alias Quacks.Rules.PotTrack

  @explode_above 7

  @doc "What `player` may do right now in the potions phase. `[]` once done."
  @spec legal_actions(Player.t()) :: [Game.action()]
  def legal_actions(%Player{phase: :potions, bag: bag, drawn: drawn, flask: flask}) do
    List.flatten([
      if(bag == [], do: [], else: :draw),
      if(drawn == [], do: [], else: :stop),
      if(flask and match?([{{:white, _}, _} | _], drawn), do: :use_flask, else: [])
    ])
  end

  def legal_actions(%Player{phase: :yellow_choice}), do: [:return_white, :keep]

  def legal_actions(%Player{phase: :blue_choice, pending: pending}),
    do: Enum.map(Enum.sort(Enum.uniq(pending)), &{:place, &1}) ++ [:return_all]

  def legal_actions(%Player{phase: :explosion_choice}),
    do: [{:explosion_choice, :vp}, {:explosion_choice, :buy}]

  def legal_actions(%Player{phase: :done}), do: []

  @doc "Run one legal potions-phase action for `seat`. The action is already logged."
  @spec step(Game.t(), Game.seat(), Game.action()) :: Game.t()
  def step(g, seat, :draw) do
    {[chip], g} = take_random(g, seat, 1)
    resolve_draw(g, seat, chip)
  end

  # The flask takes the newest chip off the pot; the pot position falls back to the
  # chip before it (or the start space when the pot is empty).
  def step(g, seat, :use_flask) do
    %{drawn: [{chip, _index} | rest]} = p = Game.player(g, seat)

    g =
      Game.update_player(
        g,
        seat,
        &%{&1 | drawn: rest, flask: false, pot_index: last_index(rest, p)}
      )

    return_to_bag(g, seat, chip)
  end

  def step(g, seat, :stop), do: finish(g, seat)

  # Yellow (§4): the white chip directly before the yellow goes back in the bag; its
  # space stays empty, the yellow chip does not move back, the white sum reverts.
  def step(g, seat, :return_white) do
    %{drawn: [yellow, {white, _index} | rest]} = Game.player(g, seat)
    g = Game.update_player(g, seat, &%{&1 | drawn: [yellow | rest], phase: :potions})
    return_to_bag(g, seat, white)
  end

  def step(g, seat, :keep), do: Game.update_player(g, seat, &%{&1 | phase: :potions})

  # Blue (§4): one of the extra chips becomes the next chip and resolves normally.
  def step(g, seat, {:place, chip}) do
    rest = List.delete(Game.player(g, seat).pending, chip)
    g = g |> clear_offer(seat) |> return_all(seat, rest)
    resolve_draw(g, seat, chip)
  end

  def step(g, seat, :return_all) do
    pending = Game.player(g, seat).pending
    g |> clear_offer(seat) |> return_all(seat, pending)
  end

  def step(g, seat, {:explosion_choice, choice}),
    do: g |> Game.update_player(seat, &%{&1 | explosion_choice: choice}) |> finish(seat)

  defp finish(g, seat), do: Game.update_player(g, seat, &%{&1 | phase: :done, done?: true})

  defp clear_offer(g, seat),
    do: Game.update_player(g, seat, &%{&1 | pending: [], phase: :potions})

  defp return_all(g, seat, chips), do: Enum.reduce(chips, g, &return_to_bag(&2, seat, &1))

  # Place a chip as the next chip in the pot, then run its on-draw effect (§3.1).
  defp resolve_draw(g, seat, chip) do
    g = place(g, seat, chip)
    sum = Game.white_sum(g, seat)

    if sum > @explode_above do
      g
      |> Game.update_player(seat, &%{&1 | exploded?: true, phase: :explosion_choice})
      |> Game.record(seat, {:exploded, sum})
    else
      on_draw(g, seat, chip)
    end
  end

  defp on_draw(g, seat, {:yellow, _}) do
    case Game.player(g, seat).drawn do
      [_, {{:white, _}, _} | _] -> Game.update_player(g, seat, &%{&1 | phase: :yellow_choice})
      _ -> g
    end
  end

  defp on_draw(g, seat, {:blue, value}) do
    case take_random(g, seat, value) do
      {[], g} -> g
      {extra, g} -> Game.update_player(g, seat, &%{&1 | pending: extra, phase: :blue_choice})
    end
  end

  defp on_draw(g, _seat, _chip), do: g

  # Put a chip on the pot `value` (+ red bonus) spaces after the previous chip and
  # remember the space it landed on, so the page can draw it there.
  defp place(g, seat, {_, value} = chip) do
    p = Game.player(g, seat)
    index = min(p.pot_index + value + red_bonus(chip, p.drawn), PotTrack.last())

    g
    |> Game.update_player(seat, &%{&1 | drawn: [{chip, index} | &1.drawn], pot_index: index})
    |> Game.record(seat, {:drew, chip, index})
  end

  # The space of the newest chip in the pot, or the start space when the pot is empty.
  defp last_index([{_chip, index} | _], _p), do: index
  defp last_index([], p), do: Player.start_index(p)

  defp return_to_bag(g, seat, chip) do
    g
    |> Game.update_player(seat, &%{&1 | bag: [chip | &1.bag]})
    |> Game.record(seat, {:returned, chip})
  end

  # Red (§4): extra movement by the number of orange chips already in the pot.
  defp red_bonus({:red, _}, drawn) do
    case Enum.count(drawn, &match?({{:orange, _}, _}, &1)) do
      0 -> 0
      n when n <= 2 -> 1
      _ -> 2
    end
  end

  defp red_bonus(_chip, _drawn), do: 0

  # Draw up to `n` random chips from the seat's bag (fewer when the bag runs short).
  defp take_random(g, seat, n) do
    size = length(Game.player(g, seat).bag)

    Enum.reduce(1..min(n, size)//1, {[], g}, fn _, {taken, g} ->
      bag = Game.player(g, seat).bag
      {i, rng} = :rand.uniform_s(length(bag), g.rng)
      {chip, bag} = List.pop_at(bag, i - 1)
      {[chip | taken], %{Game.update_player(g, seat, &%{&1 | bag: bag}) | rng: rng}}
    end)
  end
end
