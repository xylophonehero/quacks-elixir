defmodule Quacks.Game.Potions do
  @moduledoc """
  The potions phase for one seat (rulebook §3.1, §4): drawing, placing, the flask,
  the explosion and the on-draw chip effects (red, yellow, blue).

  Chip effects dispatch on `{colour, set}`, the colour's Ingredient Set in
  `game.sets`: `bonus/3` for extra movement, `on_draw/4` for the rest. Round
  modifiers (Y2, Y3, R4, B2) live on `Quacks.Player.mods`.

  Red Set 2 (R2): a drawn red chip goes beside the pot (`Quacks.Player.aside`). When
  the player stops or settles an explosion, they decide each chip there in the
  player phase `:red_choice`: place it after the last chip, keep it for a later round,
  or return it to the bag. Only then is the player done.

  Plain functions called from `Quacks.Game`. They take the whole game because draws
  use the shared `rng` and every event goes to the shared log.
  """

  alias Quacks.Game
  alias Quacks.Game.Fortune
  alias Quacks.Player
  alias Quacks.Rules.PotTrack

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

  def legal_actions(%Player{phase: :red_choice, pending: pending}) do
    for chip <- Enum.sort(Enum.uniq(pending)),
        how <- [:place, :keep, :return],
        do: {:red, {how, chip}}
  end

  # :fortune_choice (B7) actions come from `Quacks.Game.Fortune`.
  def legal_actions(%Player{phase: phase}) when phase in [:done, :fortune_choice], do: []

  @doc "Run one legal potions-phase action for `seat`. The action is already logged."
  @spec step(Game.t(), Game.seat(), Game.action()) :: Game.t()
  def step(g, seat, :draw) do
    {[chip], g} = take_random(g, seat, 1)
    resolve_draw(g, seat, chip)
  end

  # The flask takes the newest chip off the pot; the pot position falls back to the
  # chip before it (or the start space when the pot is empty).
  def step(g, seat, :use_flask),
    do: g |> Game.update_player(seat, &%{&1 | flask: false}) |> take_back(seat)

  # A card may open a choice on stop (B7); otherwise the player is done.
  def step(g, seat, :stop) do
    g = Fortune.on_stop(g, seat)
    if Game.player(g, seat).phase == :fortune_choice, do: g, else: finish(g, seat)
  end

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

  # R2: one chip from beside the pot. A placed red moves only its own value.
  def step(g, seat, {:red, {how, chip}}) do
    g = Game.update_player(g, seat, &%{&1 | pending: List.delete(&1.pending, chip)})

    g =
      case how do
        :place -> put_on_pot(g, seat, chip, Game.player(g, seat).pot_index + elem(chip, 1))
        :keep -> Game.update_player(g, seat, &%{&1 | aside: [chip | &1.aside]})
        :return -> return_to_bag(g, seat, chip)
      end

    if Game.player(g, seat).pending == [], do: done(g, seat), else: g
  end

  @doc false
  # The player stopped or settled an explosion. R2 chips beside the pot come first.
  def finish(g, seat) do
    case Game.player(g, seat).aside do
      [] -> done(g, seat)
      aside -> Game.update_player(g, seat, &%{&1 | aside: [], pending: aside, phase: :red_choice})
    end
  end

  defp done(g, seat), do: Game.update_player(g, seat, &%{&1 | phase: :done, done?: true})

  @doc false
  # The newest chip leaves the pot for the bag (flask, B10).
  def take_back(g, seat) do
    %{drawn: [{chip, _index} | rest]} = p = Game.player(g, seat)

    g
    |> Game.update_player(seat, &%{&1 | drawn: rest, pot_index: last_index(rest, p)})
    |> return_to_bag(seat, chip)
  end

  @doc false
  # B7: the chip is placed without its on-draw effect; then the player is done.
  def place_last(g, seat, chip) do
    g = place(g, seat, chip)
    if exploded?(g, seat), do: explode(g, seat), else: finish(g, seat)
  end

  defp clear_offer(g, seat),
    do: Game.update_player(g, seat, &%{&1 | pending: [], phase: :potions})

  defp return_all(g, seat, chips), do: Enum.reduce(chips, g, &return_to_bag(&2, seat, &1))

  # R2: a drawn red chip is not placed; it goes beside the pot.
  defp resolve_draw(%{sets: %{red: 2}} = g, seat, {:red, _} = chip) do
    g
    |> Game.update_player(seat, &%{&1 | aside: [chip | &1.aside]})
    |> Game.effect(seat, {:red, 2}, {:aside, chip})
  end

  # Place a chip as the next chip in the pot, then run its on-draw effect (§3.1).
  # B2: a chip drawn inside the crow skull's window cannot explode the pot for real.
  defp resolve_draw(g, seat, chip) do
    protected? = Game.player(g, seat).mods.protect > 0
    g = g |> update_mods(seat, &%{&1 | protect: max(&1.protect - 1, 0)}) |> place(seat, chip)

    cond do
      not exploded?(g, seat) -> on_draw(g, seat, chip)
      protected? -> protected_explosion(g, seat)
      true -> explode(g, seat)
    end
  end

  @doc "The highest white sum `seat` may have: 7, or more with B5 or the Y3 mandrake."
  @spec explode_above(Game.t(), Game.seat()) :: 7..9
  def explode_above(g, seat),
    do: max(Game.player(g, seat).mods.explode_above, Fortune.explode_above(g))

  defp exploded?(g, seat), do: Game.white_sum(g, seat) > explode_above(g, seat)

  defp explode(g, seat) do
    g
    |> Game.update_player(seat, &%{&1 | exploded?: true, phase: :explosion_choice})
    |> Game.record(seat, {:exploded, Game.white_sum(g, seat)})
  end

  # B2: VP and coins (`explosion_choice` stays nil), still no bonus die.
  defp protected_explosion(g, seat) do
    g
    |> Game.update_player(seat, &%{&1 | exploded?: true})
    |> Game.record(seat, {:exploded, Game.white_sum(g, seat)})
    |> Game.effect(seat, {:blue, 2}, :protected_explosion)
    |> finish(seat)
  end

  defp on_draw(g, seat, {colour, _} = chip), do: on_draw(g, seat, chip, {colour, set(g, colour)})

  defp on_draw(g, seat, {:yellow, _}, {:yellow, 1}) do
    case Game.player(g, seat).drawn do
      [_, {{:white, _}, _} | _] -> Game.update_player(g, seat, &%{&1 | phase: :yellow_choice})
      _ -> g
    end
  end

  defp on_draw(g, seat, {:blue, value}, {:blue, 1}) do
    case take_random(g, seat, value) do
      {[], g} -> g
      {extra, g} -> Game.update_player(g, seat, &%{&1 | pending: extra, phase: :blue_choice})
    end
  end

  # Windows do not add up: the larger of what is left and the new chip's value.
  defp on_draw(g, seat, {:blue, value}, {:blue, 2} = book) do
    window = max(Game.player(g, seat).mods.protect, value)

    g
    |> update_mods(seat, &%{&1 | protect: window})
    |> Game.effect(seat, book, {:protect, window})
  end

  defp on_draw(g, seat, _chip, {:blue, 3} = book) do
    if on_ruby?(g, seat),
      do:
        g
        |> Game.update_player(seat, &%{&1 | rubies: &1.rubies + 1})
        |> Game.effect(seat, book, :ruby),
      else: g
  end

  defp on_draw(g, seat, {:blue, value}, {:blue, 4} = book) do
    if on_ruby?(g, seat),
      do:
        g
        |> Game.update_player(seat, &%{&1 | vp: &1.vp + value})
        |> Game.effect(seat, book, {:vp, value}),
      else: g
  end

  defp on_draw(g, seat, _chip, {:red, 4}), do: update_mods(g, seat, &%{&1 | white1_plus1: true})

  defp on_draw(g, seat, _chip, {:yellow, 2}),
    do: update_mods(g, seat, &%{&1 | next_chip_x2: true})

  defp on_draw(g, seat, _chip, {:yellow, 3} = book) do
    case count(Game.player(g, seat).drawn, :yellow) do
      1 ->
        g |> update_mods(seat, &%{&1 | explode_above: 8}) |> Game.effect(seat, book, {:limit, 8})

      3 ->
        g |> update_mods(seat, &%{&1 | explode_above: 9}) |> Game.effect(seat, book, {:limit, 9})

      _ ->
        g
    end
  end

  defp on_draw(g, _seat, _chip, _book), do: g

  # Put a chip on the pot `value` (+ bonus) spaces after the previous chip and
  # remember the space it landed on, so the page can draw it there. Y2 doubles the
  # whole move of the next chip, once.
  defp place(g, seat, {colour, value} = chip) do
    p = Game.player(g, seat)
    {bonus, effects} = bonus(chip, {colour, set(g, colour)}, p)
    move = value + bonus + Fortune.extra_move(g, chip)

    {move, effects} =
      if p.mods.next_chip_x2,
        do: {2 * move, effects ++ [{{:yellow, 2}, {:doubled, 2 * move}}]},
        else: {move, effects}

    g =
      g
      |> update_mods(seat, &%{&1 | next_chip_x2: false})
      |> put_on_pot(seat, chip, p.pot_index + move)

    Enum.reduce(effects, g, fn {book, detail}, g -> Game.effect(g, seat, book, detail) end)
  end

  # The chip lands on `index` (clamped to the last space) and becomes the newest chip.
  defp put_on_pot(g, seat, chip, index) do
    index = min(index, PotTrack.last())

    g
    |> Game.update_player(seat, &%{&1 | drawn: [{chip, index} | &1.drawn], pot_index: index})
    |> Game.record(seat, {:drew, chip, index})
  end

  # Extra movement and the effects to log. Red 1 (§4): by the oranges in the pot.
  defp bonus(_chip, {:red, 1}, p) do
    case count(p.drawn, :orange) do
      0 -> {0, []}
      n when n <= 2 -> {1, []}
      _ -> {2, []}
    end
  end

  defp bonus(_chip, {:red, 3} = book, %{drawn: [{{:white, w}, _} | _]}),
    do: {w, [{book, {:extra, w}}]}

  defp bonus(_chip, {:yellow, 4} = book, p) do
    case count(p.drawn, :yellow) + 1 do
      n when n <= 3 -> {n, [{book, {:extra, n}}]}
      _ -> {0, []}
    end
  end

  defp bonus({:white, 1}, _book, %{mods: %{white1_plus1: true}}),
    do: {1, [{{:red, 4}, :white_plus1}]}

  defp bonus(_chip, _book, _p), do: {0, []}

  defp set(g, colour), do: Map.get(g.sets, colour, 1)
  defp count(drawn, colour), do: Enum.count(drawn, &match?({{^colour, _}, _}, &1))
  defp on_ruby?(g, seat), do: PotTrack.at(Game.player(g, seat).pot_index).ruby?

  defp update_mods(g, seat, fun), do: Game.update_player(g, seat, &%{&1 | mods: fun.(&1.mods)})

  # The space of the newest chip in the pot, or the start space when the pot is empty.
  defp last_index([{_chip, index} | _], _p), do: index
  defp last_index([], p), do: Player.start_index(p)

  defp return_to_bag(g, seat, chip) do
    g
    |> Game.update_player(seat, &%{&1 | bag: [chip | &1.bag]})
    |> Game.record(seat, {:returned, chip})
  end

  @doc false
  # Draw up to `n` random chips from the seat's bag (fewer when the bag runs short).
  def take_random(g, seat, n) do
    size = length(Game.player(g, seat).bag)

    Enum.reduce(1..min(n, size)//1, {[], g}, fn _, {taken, g} ->
      bag = Game.player(g, seat).bag
      {i, rng} = :rand.uniform_s(length(bag), g.rng)
      {chip, bag} = List.pop_at(bag, i - 1)
      {[chip | taken], %{Game.update_player(g, seat, &%{&1 | bag: bag}) | rng: rng}}
    end)
  end
end
