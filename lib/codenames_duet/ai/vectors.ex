defmodule CodenamesDuet.AI.Vectors do
  @moduledoc """
  The Duet bot partner: word vectors (`CodenamesDuet.AI.Vectors.Data`, ConceptNet
  Numberbatch), no network, no API key. It reads only its own view
  (`CodenamesDuet.Game.view/2`): its side of the key, the marks on the table and
  the log. Nearness is a z value (`Data.z/3`), so the parameters suit each vector
  set.

  ## Clue giver

  The candidate clues are the nearest clue words of its unfound greens (from the
  data), less the ones `CodenamesDuet.Clue.check/3` refuses and less its own
  older clues (and their forms): it never gives a clue twice. For each
  candidate it plays its partner as a noisy reader (`score/8`): in each sample
  the reader takes the open words nearest the clue first; a green goes on, a
  bystander ends the turn, an assassin loses the game. The number is the one
  with the best mean of greens found less the risk of the assassin. A rare word
  or a word that is not a concrete noun costs a little.

  It learns from its partner: a green that an older clue pointed at, but the
  partner did not find, counts as less near (the partner reads those clues in
  another way), so the bot tries other words for it.

  ## Guesser

  It ranks the words it can guess by nearness to the clue (a word that is an
  assassin on its own side gets a penalty: a third of those are assassins on the
  other side too, rulebook §1.4). It guesses the first word (one guess is a
  must), then the next while the count is under the clue's number and the word is
  above a floor. Else it ends the turn. A clue that is not in the data gives one
  guess, then the end of the turn.

  ## Sudden death

  It guesses the word nearest to any of its partner's clues.

  Random choices (the noise, equal values) use the bot's own `:rand` state, so a
  seed gives the same play.
  """

  alias CodenamesDuet.AI.Vectors.Data
  alias CodenamesDuet.Clue
  alias Table.Kit.Rng

  # All nearness values are z values (`Data.z/3`): standard deviations above the
  # mean nearness of two board words, the same scale for each vector set.
  @params %{
    # The lowest nearness of a green to a candidate clue in the shortlist.
    floor: 1.0,
    # The giver's model of its partner (see `score/8`): the noise on each
    # nearness, the reader's floor, the number of samples.
    sigma: 1.2,
    read_floor: 1.5,
    samples: 40,
    # The highest clue number the bot gives.
    max_number: 3,
    # An assassin costs this many greens (less when time is short).
    loss: 5.0,
    hurry_loss: 3.0,
    # A green that an older clue of the bot pointed at and the partner did not
    # find counts this much less near, for each such clue.
    missed: 0.5,
    # The guesser goes on only above this.
    guess_floor: 0.0,
    # A word that is an assassin on the guesser's own side.
    own_assassin: 0.5,
    # The cost of the rarest clue word (the data lists the clue words by frequency).
    rare_cost: 0.4,
    # The cost of a clue word that is not a concrete noun ("mop" is better than "avoid").
    abstract_cost: 0.3,
    # The candidates that get an exact score (the nearest by the neighbour lists).
    shortlist: 150
  }

  @typedoc """
  The bot: its random state, its vector sets (`Data.set()`) to give and to guess,
  and its parameters.
  """
  @type t :: %{rng: Rng.t(), giver: Data.set(), guesser: Data.set(), params: map}

  @doc """
  A new bot: its random state from `seed`. Options: `giver` and `guesser`, the
  vector sets for its clues and its guesses (default `:main`; the bench gives the
  guesser another set: a partner that does not share the giver's vectors), and
  `params` (changes to the default parameters, for the bench).
  """
  @spec new({integer, integer, integer}, keyword) :: t
  def new(seed, opts \\ []) do
    %{
      rng: Rng.seed(seed),
      giver: Keyword.get(opts, :giver, :main),
      guesser: Keyword.get(opts, :guesser, :main),
      params: Map.merge(@params, Map.new(Keyword.get(opts, :params, %{})))
    }
  end

  @doc "The default parameters."
  @spec params() :: map
  def params, do: @params

  @doc "The action for `view`, and the next bot state."
  @spec choose(map, t) :: {CodenamesDuet.Game.action(), t}
  def choose(view, %{rng: rng} = bot) do
    {action, rng} = act(view, rng, bot)
    {action, %{bot | rng: rng}}
  end

  defp act(%{legal_actions: [{:clue, :word, _} | _]} = view, rng, bot),
    do: give_clue(view, rng, bot.giver, bot.params)

  defp act(%{phase: :sudden_death} = view, rng, bot),
    do: sudden_death(view, rng, bot.guesser, bot.params)

  defp act(%{phase: :guess} = view, rng, bot), do: guess(view, rng, bot.guesser, bot.params)

  # -- the clue giver ------------------------------------------------------------------

  defp give_clue(view, rng, set, p) do
    me = view.viewer
    open = guessable(view, me)
    greens = for i <- open, Enum.at(view.key, i) == :green, do: i
    colours = Enum.map(open, &{&1, Enum.at(view.key, &1)})
    visible = visible_words(view)
    index = Map.new(open, &{&1, Data.lookup(Enum.at(view.words, &1), set)})
    old = own_clues(view, me)
    missed = missed(old, greens, index, set, p)
    {noise, rng} = noise(length(open), p.samples, rng)
    loss = if hurry?(view), do: p.hurry_loss, else: p.loss

    scored =
      greens
      |> shortlist(view.words, set, p)
      |> Enum.reject(&repeat?(&1, old, set))
      |> Enum.filter(&(Clue.check(&1, 1, visible) == :ok))
      |> Enum.map(&score(&1, colours, index, missed, noise, loss, set, p))

    case scored do
      [] -> fallback(visible, old, rng, set)
      _ -> pick_best(scored, & &1.value, rng, &{:clue, &1.word, &1.n})
    end
  end

  # The candidates near the most greens, by the neighbour lists.
  defp shortlist(greens, words, set, p) do
    greens
    |> Enum.flat_map(&Data.neighbours(Enum.at(words, &1), set))
    |> Enum.group_by(&elem(&1, 0), &Data.to_z(elem(&1, 1), set))
    |> Enum.map(fn {word, zs} ->
      {word, Enum.count(zs, &(&1 >= p.floor)), Enum.sum(zs)}
    end)
    |> Enum.sort_by(fn {word, n, sum} -> {-n, -sum, word} end)
    |> Enum.take(p.shortlist)
    |> Enum.map(&elem(&1, 0))
  end

  # The bot's own clues so far, oldest first: `[{word, number}]`.
  defp own_clues(view, me) do
    for {:clue, ^me, word, number} <- Enum.reverse(view.log), do: {word, number}
  end

  # A clue the bot gave before (or a form of it) is never given again.
  defp repeat?(word, old, set) do
    Enum.any?(old, fn {w, _} ->
      Clue.conflict?(word, w) or Data.lookup(word, set) == Data.lookup(w, set)
    end)
  end

  # For each unfound green: the number of the bot's older clues that pointed at it
  # (it is one of the `number` greens nearest that clue, above the floor). The
  # partner did not read those clues as the bot did.
  defp missed(old, greens, index, set, p) do
    for {word, number} <- old,
        c = Data.lookup(word, set),
        c != nil,
        i <- pointed_at(c, number, greens, index, set, p),
        reduce: %{} do
      acc -> Map.update(acc, i, 1, &(&1 + 1))
    end
  end

  # The `number` greens nearest clue `c`, above the floor.
  defp pointed_at(c, number, greens, index, set, p) do
    greens
    |> Enum.filter(&index[&1])
    |> Enum.map(&{&1, Data.z(c, index[&1], set)})
    |> Enum.filter(&(elem(&1, 1) >= p.floor))
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.take(number)
    |> Enum.map(&elem(&1, 0))
  end

  # Few tokens for the greens left (more than 2 a turn): more risk.
  defp hurry?(view), do: 15 - view.found > 2 * view.timer

  # `samples` lists of standard normal values, one for each open word.
  defp noise(words, samples, rng) do
    Enum.map_reduce(1..samples, rng, fn _, rng ->
      Enum.map_reduce(1..words//1, rng, fn _, rng -> :rand.normal_s(rng) end)
    end)
  end

  # The value of clue `word`: the partner is a reader whose nearness is the bot's
  # plus noise (sigma). In each sample the reader takes the open words nearest
  # first, while they are above read_floor (the first guess is a must) and the
  # count is under the number: a green goes on, a bystander ends the turn, an
  # assassin loses the game. The number is the one with the best mean of greens
  # found less `loss` times the chance of the assassin.
  defp score(word, colours, index, missed, noise, loss, set, p) do
    c = Data.lookup(word, set)

    zs =
      Enum.map(colours, fn {i, colour} ->
        z = if index[i], do: Data.z(c, index[i], set), else: 0.0
        {colour, if(colour == :green, do: z - p.missed * Map.get(missed, i, 0), else: z)}
      end)

    outcomes = Enum.map(noise, &read(zs, &1, p))

    {value, n} =
      1..p.max_number
      |> Enum.map(fn n ->
        {found, lost} =
          Enum.reduce(outcomes, {0, 0}, fn {greens, stop}, {f, l} ->
            {f + min(greens, n), l + if(stop == :assassin and greens < n, do: 1, else: 0)}
          end)

        {(found - loss * lost) / length(outcomes), -n}
      end)
      |> Enum.max()

    cost = p.rare_cost * c / 20_000 + if(Data.concrete?(c, set), do: 0, else: p.abstract_cost)
    %{word: word, n: -n, value: value - cost}
  end

  # One reading: `{greens before the stop, the colour of the stop}` (`:none`:
  # the reader stops on its own).
  defp read(zs, noise, p) do
    zs
    |> Enum.zip_with(noise, fn {colour, z}, e -> {z + p.sigma * e, colour} end)
    |> Enum.sort(:desc)
    |> Enum.with_index()
    |> Enum.reduce_while(0, fn
      {{z, _}, k}, greens when k > 0 and z < p.read_floor -> {:halt, {greens, :none}}
      {{_, :green}, _}, greens -> {:cont, greens + 1}
      {{_, colour}, _}, greens -> {:halt, {greens, colour}}
    end)
    |> case do
      {_, _} = outcome -> outcome
      greens -> {greens, :none}
    end
  end

  # No candidate: any legal clue word, number 1.
  defp fallback(visible, old, rng, set) do
    word =
      Enum.find(
        Data.clue_words(set),
        &(Clue.check(&1, 1, visible) == :ok and not repeat?(&1, old, set))
      )

    {{:clue, word, 1}, rng}
  end

  # -- the guesser ----------------------------------------------------------------------

  defp guess(view, rng, set, p) do
    {clue, number} = view.clue
    options = for {:guess, i} <- view.legal_actions, do: i

    case Data.lookup(clue, set) do
      nil -> blind(view, options, rng)
      c -> guess_near(view, options, [c], number, rng, set, p)
    end
  end

  # An unknown clue: one guess (a must), the safest by its own key, then stop.
  defp blind(%{guesses: 0} = view, options, rng) do
    safe = Enum.reject(options, &(Enum.at(view.key, &1) == :assassin))
    {i, rng} = Rng.pick(if(safe == [], do: options, else: safe), rng)
    {{:guess, i}, rng}
  end

  defp blind(_view, _options, rng), do: {:end_turn, rng}

  defp guess_near(%{guesses: g} = view, options, clues, number, rng, set, p)
       when g < number or g == 0 do
    {[{top, best} | _], rng} = rank(view, options, clues, rng, set, p)
    go? = g == 0 or best >= p.guess_floor
    {if(go?, do: {:guess, top}, else: :end_turn), rng}
  end

  defp guess_near(_view, _options, _clues, _number, rng, _set, _p), do: {:end_turn, rng}

  # -- sudden death ------------------------------------------------------------------------

  defp sudden_death(view, rng, set, p) do
    partner = 1 - view.viewer
    options = for {:guess, i} <- view.legal_actions, do: i

    clues =
      for {:clue, ^partner, word, _} <- view.log,
          c <- List.wrap(Data.lookup(word, set)),
          do: c

    case clues do
      [] ->
        blind(%{view | guesses: 0}, options, rng)

      _ ->
        {[{i, _} | _], rng} = rank(view, options, clues, rng, set, p)
        {{:guess, i}, rng}
    end
  end

  # -- shared ----------------------------------------------------------------------------

  # The options by their best nearness (z) to any of `clues`, highest first; the
  # bot's own assassins lower. Ties in a random order.
  defp rank(view, options, clues, rng, set, p) do
    {order, rng} = Rng.shuffle(options, rng)

    ranked =
      order
      |> Enum.map(fn i ->
        w = Data.lookup(Enum.at(view.words, i), set)
        z = if w, do: clues |> Enum.map(&Data.z(&1, w, set)) |> Enum.max(), else: 0.0
        penalty = if Enum.at(view.key || [], i) == :assassin, do: p.own_assassin, else: 0
        {i, z - penalty}
      end)
      |> Enum.sort_by(&elem(&1, 1), :desc)

    {ranked, rng}
  end

  defp pick_best(items, value, rng, action) do
    best = items |> Enum.map(value) |> Enum.max()
    top = items |> Enum.filter(&(value.(&1) >= best - 1.0e-9)) |> Enum.sort_by(& &1.word)
    {item, rng} = Rng.pick(top, rng)
    {action.(item), rng}
  end

  # The words the partner can still guess on `side`: no agent, no mark from `side`.
  defp guessable(view, side) do
    for i <- 0..24,
        not Map.has_key?(view.agents, i),
        side not in Map.get(view.bystanders, i, []),
        do: i
  end

  defp visible_words(view) do
    for {word, i} <- Enum.with_index(view.words),
        not Map.has_key?(view.agents, i),
        length(Map.get(view.bystanders, i, [])) < 2,
        do: word
  end
end
