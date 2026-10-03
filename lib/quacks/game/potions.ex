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

  The Herb Witches: Sets 5–6 and the locoweed books dispatch the same way. A locoweed
  chip with Set 6 acts as the last coloured chip in the pot (its value, bonus and
  on-draw action). With the house rule `overflow` (default on, every game), a chip
  drawn after a chip sits on the last space goes in the overflow bowl
  (`Quacks.Player.bowl`): no action, but a white one still counts toward the
  explosion.

  Choice books on draw: red Set 6 sets one more chip aside (`aside`), which the
  player places with `{:red, {:place, chip}}` at any time and must place this round;
  yellow Set 6 offers `{:chip, :yellow_ruby}` (1 ruby: the yellow moves 3 more) in
  the player phase `:chip_choice`; locoweed 5 there offers `{:chip, {:return, chip}}`
  (a coloured pot chip back to the bag). Green Set 5 starter chips (`Quacks.Player.starters`)
  are the first chips `:draw` takes.

  Plain functions called from `Quacks.Game`. They take the whole game because draws
  use the shared `rng` and every event goes to the shared log.
  """

  alias Quacks.Game
  alias Quacks.Game.Fortune
  alias Quacks.Player
  alias Quacks.Rules.PotTrack

  @doc """
  What `seat` may do right now in the potions phase. `[]` once done. Red Set 6: a
  chip set aside may be placed at any time, and after stopping it must be placed.
  """
  @spec legal_actions(Game.t(), Game.seat()) :: [Game.action()]
  def legal_actions(%{sets: %{red: 6}} = g, seat) do
    p = Game.player(g, seat)
    places = for chip <- Enum.sort(Enum.uniq(p.aside)), do: {:red, {:place, chip}}

    case p.phase do
      :potions -> legal_actions(p) ++ places
      :red_choice -> Enum.filter(legal_actions(p), &match?({:red, {:place, _}}, &1))
      _ -> legal_actions(p)
    end
  end

  def legal_actions(g, seat), do: legal_actions(Game.player(g, seat))

  @doc "What `player` may do right now in the potions phase, from its own state."
  @spec legal_actions(Player.t()) :: [Game.action()]
  def legal_actions(%Player{phase: :potions, bag: bag, drawn: drawn, flask: flask} = p) do
    List.flatten([
      if(bag == [], do: [], else: :draw),
      if(drawn == [], do: [], else: :stop),
      if(flask and last_white?(p), do: :use_flask, else: [])
    ])
  end

  def legal_actions(%Player{phase: :yellow_choice}), do: [:return_white, :keep]

  def legal_actions(%Player{phase: :chip_choice, chip_choices: choices}),
    do: Enum.map(choices, &{:chip, &1}) ++ [:chip_done]

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
  # :stopped (`:resume`) comes from `Quacks.Game`: it depends on the other seats.
  def legal_actions(%Player{phase: phase})
      when phase in [:done, :fortune_choice, :stopped, :waiting_stir],
      do: []

  @doc "Run one legal potions-phase action for `seat`. The action is already logged."
  @spec step(Game.t(), Game.seat(), Game.action()) :: Game.t()
  # Green Set 5: the chosen starter chips come out of the bag first, in order. A
  # starter no longer in the bag (traded away since) is skipped.
  def step(g, seat, :draw) do
    case Game.player(g, seat) do
      %{starters: [chip | rest], bag: bag} ->
        g = Game.update_player(g, seat, &%{&1 | starters: rest})

        if chip in bag do
          g
          |> Game.update_player(seat, &%{&1 | bag: List.delete(&1.bag, chip)})
          |> resolve_draw(seat, chip)
          |> Game.effect(seat, {:green, 5}, {:first, chip})
        else
          step(g, seat, :draw)
        end

      _ ->
        {[chip], g} = take_random(g, seat, 1)
        resolve_draw(g, seat, chip)
    end
  end

  # The flask takes the newest chip off the pot; the pot position falls back to the
  # chip before it (or the start space when the pot is empty).
  def step(g, seat, :use_flask),
    do: g |> Game.update_player(seat, &%{&1 | flask: false}) |> take_back(seat)

  # Soft stop: the player waits as `:stopped` and may `:resume` while someone else
  # still brews. `Quacks.Game` makes the stop final (`stop/2`) once nobody brews.
  def step(g, seat, :stop) do
    g = Game.update_player(g, seat, &%{&1 | phase: :stopped})
    if length(g.seats) > 1, do: Game.record(g, seat, :stopped), else: g
  end

  def step(g, seat, :resume),
    do: g |> Game.update_player(seat, &%{&1 | phase: :potions}) |> Game.record(seat, :resumed)

  # Yellow (§4): the white chip directly before the yellow goes back in the bag; its
  # space stays empty, the yellow chip does not move back, the white sum reverts.
  def step(g, seat, :return_white) do
    %{drawn: [yellow, {white, _index} | rest]} = Game.player(g, seat)
    g = Game.update_player(g, seat, &%{&1 | drawn: [yellow | rest], phase: :potions})
    return_to_bag(g, seat, white)
  end

  def step(g, seat, :keep), do: Game.update_player(g, seat, &%{&1 | phase: :potions})

  # Yellow Set 6: 1 ruby, the yellow (the newest chip) moves 3 more spaces.
  def step(g, seat, {:chip, :yellow_ruby}) do
    g
    |> Game.update_player(seat, fn %{drawn: [{chip, i} | rest]} = p ->
      i = min(i + 3, PotTrack.last())
      %{p | rubies: p.rubies - 1, drawn: [{chip, i} | rest], pot_index: i}
    end)
    |> Game.effect(seat, {:yellow, 6}, {:extra, 3})
    |> step(seat, :chip_done)
  end

  # Locoweed 5: the newest such chip leaves the pot for the bag; its space stays
  # empty. When it is the newest chip, the next chip counts from the chip before it.
  def step(g, seat, {:chip, {:return, chip}}) do
    g
    |> Game.update_player(seat, fn p ->
      drawn = List.keydelete(p.drawn, chip, 0)
      %{p | drawn: drawn, pot_index: last_index(drawn, p)}
    end)
    |> return_to_bag(seat, chip)
    |> Game.effect(seat, {:locoweed, 5}, {:returned, chip})
    |> step(seat, :chip_done)
  end

  def step(g, seat, :chip_done),
    do: Game.update_player(g, seat, &%{&1 | chip_choices: [], phase: :potions})

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

  # Red Set 6 while brewing: a chip set aside goes in the pot as a normal draw.
  def step(%{sets: %{red: 6}} = g, seat, {:red, {:place, chip}} = action) do
    case Game.player(g, seat) do
      %{phase: :potions} ->
        g
        |> Game.update_player(seat, &%{&1 | aside: List.delete(&1.aside, chip)})
        |> resolve_draw(seat, chip)

      _ ->
        place_aside(g, seat, action)
    end
  end

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

  # Red Set 6 after stopping (or exploding): the chip moves its own value with no
  # action (⚠️, like R2); a white one can still explode the pot. Then the chips still
  # aside wait until the explosion choice is made.
  defp place_aside(g, seat, {:red, {:place, chip}}) do
    p = Game.player(g, seat)
    g = Game.update_player(g, seat, &%{&1 | pending: List.delete(&1.pending, chip)})
    g = put_on_pot(g, seat, chip, p.pot_index + elem(chip, 1))

    cond do
      not p.exploded? and exploded?(g, seat) ->
        g
        |> Game.update_player(seat, &%{&1 | aside: &1.pending, pending: []})
        |> explode(seat)

      Game.player(g, seat).pending == [] ->
        done(g, seat)

      true ->
        g
    end
  end

  @doc false
  # The stop is final. A card may open a choice on stop (B7); otherwise the player is
  # done (after the red chips beside the pot).
  def stop(g, seat) do
    g = Fortune.on_stop(g, seat)
    if Game.player(g, seat).phase == :fortune_choice, do: g, else: finish(g, seat)
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
  # The newest chip leaves the pot (or the overflow bowl) for the bag (flask, B10).
  def take_back(g, seat) do
    case Game.player(g, seat) do
      %{bowl: [chip | rest]} ->
        g |> Game.update_player(seat, &%{&1 | bowl: rest}) |> return_to_bag(seat, chip)

      %{drawn: [{chip, _index} | rest]} = p ->
        g
        |> Game.update_player(seat, &%{&1 | drawn: rest, pot_index: last_index(rest, p)})
        |> return_to_bag(seat, chip)
    end
  end

  @doc false
  # The newest chip drawn this round (in the bowl or the pot) is white.
  def last_white?(%Player{bowl: [chip | _]}), do: match?({:white, _}, chip)
  def last_white?(%Player{drawn: drawn}), do: match?([{{:white, _}, _} | _], drawn)

  @doc false
  # B7 (official ruling, `herb-witches.md` §2.6): the chip moves its printed value, has
  # no action and cannot explode the pot; then the player is done. ⚠️ No bonus move
  # either (red, Y2 doubling): the bonus is the chip's action.
  def place_last(g, seat, {_colour, value} = chip) do
    g
    |> put_on_pot(seat, chip, Game.player(g, seat).pot_index + value)
    |> finish(seat)
  end

  defp clear_offer(g, seat),
    do: Game.update_player(g, seat, &%{&1 | pending: [], phase: :potions})

  defp return_all(g, seat, chips), do: Enum.reduce(chips, g, &return_to_bag(&2, seat, &1))

  @doc false
  # Place a drawn chip with its on-draw action (also for the silver witch S2's offer).
  # R2: a drawn red chip is not placed; it goes beside the pot.
  def resolve_draw(%{sets: %{red: 2}} = g, seat, {:red, _} = chip) do
    g
    |> Game.update_player(seat, &%{&1 | aside: [chip | &1.aside]})
    |> Game.effect(seat, {:red, 2}, {:aside, chip})
  end

  # Place a chip as the next chip in the pot, then run its on-draw effect (§3.1).
  # B2: a chip drawn inside the crow skull's window cannot explode the pot for real.
  # B3: a draw the card asks for cannot explode the pot (`Fortune.safe_draw?/2`).
  # Overflow bowl: the chip goes in the bowl, with no action (book `:bowl`).
  def resolve_draw(g, seat, chip) do
    p = Game.player(g, seat)
    protected? = p.mods.protect > 0
    safe? = Fortune.safe_draw?(g, p)
    {acting, book} = if overflow?(g, p), do: {chip, :bowl}, else: acting(g, p, chip)

    g =
      g
      |> update_mods(seat, &%{&1 | protect: max(&1.protect - 1, 0)})
      |> place(seat, chip, acting, book)

    cond do
      not exploded?(g, seat) or safe? -> on_draw(g, seat, acting, next_chip_lost(g, seat, book))
      protected? -> protected_explosion(g, seat)
      true -> explode(g, seat)
    end
  end

  # House rule `overflow` (default): a chip after a chip on the last space goes in the
  # bowl. Without it the chip stays on the last space.
  defp overflow?(%{rules: %{overflow: false}}, _p), do: false
  defp overflow?(_g, %Player{drawn: drawn}), do: match?([{_, 53} | _], drawn)

  # Overflow bowl: on the last space an action for the next chip is lost (the next chip
  # goes in the bowl). Blue Set 1 (the offer) and Y2 (next chip double).
  defp next_chip_lost(%{rules: %{overflow: true}} = g, seat, book)
       when book in [{:blue, 1}, {:yellow, 2}] do
    if Game.player(g, seat).pot_index == PotTrack.last(), do: :bowl, else: book
  end

  defp next_chip_lost(_g, _seat, book), do: book

  # The chip a drawn chip acts as, and its book. Locoweed Set 2 copies the value and
  # the on-draw action of the last coloured chip in the pot (no coloured chip: value
  # 1, no action, book `:none`). ⚠️ Earlier locoweed chips are skipped (they acted as
  # that same chip); the copy keeps colour locoweed for every count; step-B actions
  # are not copied (`herb-witches.md` §2.3).
  defp acting(%{sets: %{locoweed: 2}} = g, p, {:locoweed, _} = chip) do
    case Enum.find(p.drawn, fn {{c, _}, _} -> c not in [:white, :locoweed] end) do
      nil -> {chip, :none}
      {{colour, _} = copied, _index} -> {copied, {colour, set(g, colour)}}
    end
  end

  defp acting(g, _p, {colour, _} = chip), do: {chip, {colour, set(g, colour)}}

  @doc """
  The highest white sum `seat` may have: the house rule's limit (default 7), or more
  with B5 or the Y3 mandrake. The highest of the three wins.
  """
  @spec explode_above(Game.t(), Game.seat()) :: 5..9
  def explode_above(g, seat) do
    Enum.max([
      g.rules.explode_above,
      Game.player(g, seat).mods.explode_above,
      Fortune.explode_above(g)
    ])
  end

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

  # Blue Set 5: VP by value when the pot has at least that many orange chips.
  defp on_draw(g, seat, {:blue, value}, {:blue, 5} = book) do
    if count(Game.player(g, seat).drawn, :orange) >= value,
      do:
        g
        |> Game.update_player(seat, &%{&1 | vp: &1.vp + value})
        |> Game.effect(seat, book, {:vp, value}),
      else: g
  end

  # Blue Set 6: a ruby per white 1-chip among the `value` chips before the blue.
  defp on_draw(g, seat, {:blue, value}, {:blue, 6} = book) do
    [_blue | before] = Game.player(g, seat).drawn

    case before |> Enum.take(value) |> Enum.count(&match?({{:white, 1}, _}, &1)) do
      0 ->
        g

      n ->
        g
        |> Game.update_player(seat, &%{&1 | rubies: &1.rubies + n})
        |> Game.effect(seat, book, {:rubies, n})
    end
  end

  # Yellow Set 5: peek at one more chip; the yellow moves on by its value (locoweed 1),
  # the chip goes back in the bag. ⚠️ The peeked chip has no effect, even a white one.
  defp on_draw(g, seat, _chip, {:yellow, 5} = book) do
    case take_random(g, seat, 1) do
      {[], g} ->
        g

      {[{_, v} = peek], g} ->
        g
        |> Game.update_player(seat, fn %{drawn: [{chip, i} | rest]} = p ->
          i = min(i + v, PotTrack.last())
          %{p | drawn: [{chip, i} | rest], pot_index: i, bag: [peek | p.bag]}
        end)
        |> Game.effect(seat, book, {:peek, peek})
    end
  end

  # Red Set 6: draw one more chip and set it aside; it must be placed this round.
  defp on_draw(g, seat, _chip, {:red, 6} = book) do
    case take_random(g, seat, 1) do
      {[], g} ->
        g

      {[aside], g} ->
        g
        |> Game.update_player(seat, &%{&1 | aside: [aside | &1.aside]})
        |> Game.effect(seat, book, {:aside, aside})
    end
  end

  # Yellow Set 6: with a ruby, the player may pay it for 3 more spaces (a choice).
  defp on_draw(g, seat, _chip, {:yellow, 6}) do
    if Game.player(g, seat).rubies > 0,
      do: Game.update_player(g, seat, &%{&1 | chip_choices: [:yellow_ruby], phase: :chip_choice}),
      else: g
  end

  # Locoweed 5: the player may return one coloured pot chip (this locoweed too).
  defp on_draw(g, seat, _chip, {:locoweed, 5}) do
    choices =
      for {{colour, _} = chip, _} <- Game.player(g, seat).drawn,
          colour != :white,
          uniq: true,
          do: {:return, chip}

    Game.update_player(g, seat, &%{&1 | chip_choices: Enum.sort(choices), phase: :chip_choice})
  end

  defp on_draw(g, _seat, _chip, _book), do: g

  # Put a chip on the pot `value` (+ bonus) spaces after the previous chip and
  # remember the space it landed on, so the page can draw it there. Y2 doubles the
  # whole move of the next chip, once. `acting` and `book` give the move (see
  # `acting/3`); a chip for the overflow bowl (`:bowl`) just goes in.
  defp place(g, seat, chip, _acting, :bowl), do: put_on_pot(g, seat, chip, PotTrack.last())

  defp place(g, seat, chip, {_, value} = acting, book) do
    p = Game.player(g, seat)
    {bonus, effects} = bonus(acting, book, p)
    move = value + bonus + Fortune.extra_move(g, acting)

    effects =
      if chip == acting, do: effects, else: [{{:locoweed, 2}, {:copied, acting}} | effects]

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
  # With `overflow` and a chip already on the last space, it goes in the bowl.
  defp put_on_pot(g, seat, chip, index) do
    if overflow?(g, Game.player(g, seat)) do
      g
      |> Game.update_player(seat, &%{&1 | bowl: [chip | &1.bowl]})
      |> Game.record(seat, {:overflow, chip})
    else
      index = min(index, PotTrack.last())

      g
      |> Game.update_player(seat, &%{&1 | drawn: [{chip, index} | &1.drawn], pot_index: index})
      |> Game.record(seat, {:drew, chip, index})
    end
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

  # Red Set 5: move by the highest red value already in the pot, if that is higher.
  defp bonus({_, value}, {:red, 5} = book, p) do
    case Enum.max(for({{:red, v}, _} <- p.drawn, do: v), fn -> 0 end) do
      high when high > value -> {high - value, [{book, {:extra, high - value}}]}
      _ -> {0, []}
    end
  end

  # Locoweed Set 1: rat stone distance + 1, at most 4 (solo: no rats, so 1).
  defp bonus(_chip, {:locoweed, 1} = book, p) do
    n = min(p.rat_stone + 1, 4)
    {n - 1, [{book, {:moves, n}}]}
  end

  # Locoweed 4: 1 per colour in the pot, white not counted, locoweed always counted.
  defp bonus(_chip, {:locoweed, 4} = book, p) do
    n = p.drawn |> MapSet.new(fn {{c, _}, _} -> c end) |> MapSet.put(:locoweed)
    n = n |> MapSet.delete(:white) |> MapSet.size()
    {n - 1, [{book, {:moves, n}}]}
  end

  # Locoweed 6: the printed values of the white chips in the pot, at least 1.
  defp bonus(_chip, {:locoweed, 6} = book, p) do
    n = max(1, Enum.sum(for {{:white, v}, _} <- p.drawn, do: v))
    {n - 1, [{book, {:moves, n}}]}
  end

  defp bonus({:white, 1}, _book, %{mods: %{white1_plus1: true}}),
    do: {1, [{{:red, 4}, :white_plus1}]}

  defp bonus(_chip, _book, _p), do: {0, []}

  defp set(g, colour), do: Map.get(g.sets, colour, 1)
  defp count(drawn, colour), do: Enum.count(drawn, &match?({{^colour, _}, _}, &1))
  defp on_ruby?(g, seat), do: PotTrack.at(Game.player(g, seat).pot_index).ruby?

  defp update_mods(g, seat, fun), do: Game.update_player(g, seat, &%{&1 | mods: fun.(&1.mods)})

  # The space of the newest chip in the pot, or the start space when the pot is empty.
  @doc false
  def last_index([{_chip, index} | _], _p), do: index
  def last_index([], p), do: Player.start_index(p)

  @doc false
  def return_to_bag(g, seat, chip) do
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
