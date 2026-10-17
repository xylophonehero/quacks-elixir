defmodule CodenamesDuet.AI.Vectors do
  @moduledoc """
  The Duet bot partner: word vectors (`CodenamesDuet.AI.Vectors.Data`, GloVe), no
  network, no API key. It reads only its own view (`CodenamesDuet.Game.view/2`):
  its side of the key, the marks on the table and the log.

  ## Clue giver

  The candidate clues are the nearest clue words of its unfound greens (from the
  data), less the ones `CodenamesDuet.Clue.check/3` refuses. For each candidate it
  ranks the words the partner can still guess on its side by similarity. The
  **danger** is the highest similarity of a word that is not an unfound green,
  plus 0.1 for an assassin. The clue's number is the count of greens above
  `danger + margin` and above a floor. The value of a clue is that count (more
  than 3 counts less) plus its weakest margin; the best value wins. With no clue
  for 1 or more, it takes the clue of the safest single green, number 1.

  ## Guesser

  It ranks the words it can guess by similarity to the clue (a word that is an
  assassin on its own side gets a penalty: a third of those are assassins on the
  other side too, rulebook §1.4). It guesses the first word (one guess is a
  must), then the next while the count is under the clue's number and the word is
  above a floor; one more than the number only when that word is clearly near
  and clearly ahead of the next. Else it ends the turn. A clue that is not in the
  data gives one guess, then the end of the turn.

  ## Sudden death

  It guesses the word nearest to any of its partner's clues.

  Equal choices are broken with the bot's own `:rand` state, so a seed gives the
  same play.
  """

  alias CodenamesDuet.AI.Vectors.Data
  alias CodenamesDuet.Clue
  alias Table.Kit.Rng

  # A green must beat the danger by this much to count.
  @margin 0.05
  # The margin when time is short (see `hurry?/1`).
  @hurry_margin 0.02
  # An assassin is this much more dangerous than its similarity.
  @assassin_bias 0.1
  # The lowest similarity of a word the clue points at.
  @floor 0.3
  # The guesser goes on only above this.
  @guess_floor 0.25
  # One guess more than the number: this near, and this far ahead of the next.
  @bonus_sim 0.5
  @bonus_gap 0.12
  # A word that is an assassin on the guesser's own side.
  @own_assassin_penalty 0.12
  # The cost of a rare clue word (the data lists the clue words by frequency).
  @rare_cost 0.4
  # The candidates that get an exact score (the nearest by the neighbour lists).
  @shortlist 150

  @typedoc "The bot: its random state and its vector sets (`Data.set()`) to give and to guess."
  @type t :: %{rng: Rng.t(), giver: Data.set(), guesser: Data.set()}

  @doc """
  A new bot: its random state from `seed`. Options: `giver` and `guesser`, the
  vector sets for its clues and its guesses (default `:main`). The bench gives
  the guesser another set: a partner that does not share the giver's vectors.
  """
  @spec new({integer, integer, integer}, keyword) :: t
  def new(seed, opts \\ []) do
    %{
      rng: Rng.seed(seed),
      giver: Keyword.get(opts, :giver, :main),
      guesser: Keyword.get(opts, :guesser, :main)
    }
  end

  @doc "The action for `view`, and the next bot state."
  @spec choose(map, t) :: {CodenamesDuet.Game.action(), t}
  def choose(view, %{rng: rng} = bot) do
    {action, rng} = act(view, rng, bot)
    {action, %{bot | rng: rng}}
  end

  defp act(%{legal_actions: [{:clue, :word, _} | _]} = view, rng, bot),
    do: give_clue(view, rng, bot.giver)

  defp act(%{phase: :sudden_death} = view, rng, bot), do: sudden_death(view, rng, bot.guesser)
  defp act(%{phase: :guess} = view, rng, bot), do: guess(view, rng, bot.guesser)

  # -- the clue giver ------------------------------------------------------------------

  defp give_clue(view, rng, set) do
    me = view.viewer
    open = guessable(view, me)
    greens = for i <- open, Enum.at(view.key, i) == :green, do: i
    others = for i <- open, Enum.at(view.key, i) != :green, do: {i, Enum.at(view.key, i)}
    visible = visible_words(view)
    index = Map.new(open, &{&1, Data.lookup(Enum.at(view.words, &1), set)})

    scored =
      greens
      |> shortlist(view.words, set)
      |> Enum.filter(&(Clue.check(&1, 1, visible) == :ok))
      |> Enum.map(&score(&1, greens, others, index, hurry?(view), set))

    case Enum.filter(scored, &(&1.n > 0)) do
      [] -> fallback(scored, visible, rng, set)
      good -> pick_best(good, & &1.value, rng, &{:clue, &1.word, &1.n})
    end
  end

  # The candidates near the most greens, by the neighbour lists.
  defp shortlist(greens, words, set) do
    greens
    |> Enum.flat_map(&Data.neighbours(Enum.at(words, &1), set))
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {word, sims} ->
      {word, Enum.count(sims, &(&1 >= @floor)), Enum.sum(sims)}
    end)
    |> Enum.sort_by(fn {word, n, sum} -> {-n, -sum, word} end)
    |> Enum.take(@shortlist)
    |> Enum.map(&elem(&1, 0))
  end

  # Few tokens for the greens left (more than 2 a turn): bigger clues, less margin.
  defp hurry?(view), do: 15 - view.found > 2 * view.timer

  defp score(word, greens, others, index, hurry?, set) do
    margin = if hurry?, do: @hurry_margin, else: @margin
    c = Data.lookup(word, set)
    sim = fn i -> if index[i], do: Data.cosine(c, index[i], set), else: 0.0 end

    danger =
      others
      |> Enum.map(fn {i, colour} ->
        sim.(i) + if(colour == :assassin, do: @assassin_bias, else: 0)
      end)
      |> Enum.max(fn -> 0.0 end)

    sims = greens |> Enum.map(sim) |> Enum.sort(:desc)
    targets = Enum.filter(sims, &(&1 >= @floor and &1 >= danger + margin))
    n = length(targets)
    weakest = if n > 0, do: List.last(targets) - danger, else: hd(sims) - danger

    count = if hurry?, do: n, else: min(n, 3) + 0.5 * max(n - 3, 0)
    # A common word is a better clue (the rarest costs @rare_cost).
    rare = @rare_cost * c / 20_000
    %{word: word, n: n, value: count + weakest - rare, safety: weakest - rare}
  end

  # No clue for 1 or more: the safest single green, number 1; else any legal word.
  defp fallback([_ | _] = scored, _visible, rng, _set),
    do: pick_best(scored, & &1.safety, rng, &{:clue, &1.word, 1})

  defp fallback([], visible, rng, set) do
    word = Enum.find(Data.clue_words(set), &(Clue.check(&1, 1, visible) == :ok))
    {{:clue, word, 1}, rng}
  end

  # -- the guesser ----------------------------------------------------------------------

  defp guess(view, rng, set) do
    {clue, number} = view.clue
    options = for {:guess, i} <- view.legal_actions, do: i

    case Data.lookup(clue, set) do
      nil -> blind(view, options, rng)
      c -> guess_near(view, options, [c], number, rng, set)
    end
  end

  # An unknown clue: one guess (a must), the safest by its own key, then stop.
  defp blind(%{guesses: 0} = view, options, rng) do
    safe = Enum.reject(options, &(Enum.at(view.key, &1) == :assassin))
    {i, rng} = Rng.pick(if(safe == [], do: options, else: safe), rng)
    {{:guess, i}, rng}
  end

  defp blind(_view, _options, rng), do: {:end_turn, rng}

  defp guess_near(%{guesses: g} = view, options, clues, number, rng, set)
       when g < number or g == 0 do
    {[{top, best} | _], rng} = rank(view, options, clues, rng, set)
    go? = g == 0 or best >= @guess_floor
    {if(go?, do: {:guess, top}, else: :end_turn), rng}
  end

  # The one guess more than the number (§4.6): a word clearly near this clue or an
  # older clue of the same giver (a word that clue left behind).
  defp guess_near(%{guesses: g} = view, options, clues, number, rng, set)
       when g == number and number > 0 do
    {ranked, rng} = rank(view, options, clues ++ older_clues(view, set), rng, set)

    case ranked do
      [{top, best}, {_, next} | _] when best >= @bonus_sim and best - next >= @bonus_gap ->
        {{:guess, top}, rng}

      [{top, best}] when best >= @bonus_sim ->
        {{:guess, top}, rng}

      _ ->
        {:end_turn, rng}
    end
  end

  defp guess_near(_view, _options, _clues, _number, rng, _set), do: {:end_turn, rng}

  # The giver's clues before this one.
  defp older_clues(%{giver: giver, log: log}, set) do
    [_current | older] = Enum.drop_while(log, &(not match?({:clue, _, _, _}, &1)))
    for {:clue, ^giver, word, _} <- older, c <- List.wrap(Data.lookup(word, set)), do: c
  end

  # -- sudden death ------------------------------------------------------------------------

  defp sudden_death(view, rng, set) do
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
        {[{i, _} | _], rng} = rank(view, options, clues, rng, set)
        {{:guess, i}, rng}
    end
  end

  # -- shared ----------------------------------------------------------------------------

  # The options by their best similarity to any of `clues`, highest first; the
  # bot's own assassins lower. Ties in a random order.
  defp rank(view, options, clues, rng, set) do
    {order, rng} = Rng.shuffle(options, rng)

    ranked =
      order
      |> Enum.map(fn i ->
        w = Data.lookup(Enum.at(view.words, i), set)
        sim = if w, do: clues |> Enum.map(&Data.cosine(&1, w, set)) |> Enum.max(), else: 0.0
        penalty = if Enum.at(view.key || [], i) == :assassin, do: @own_assassin_penalty, else: 0
        {i, sim - penalty}
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
