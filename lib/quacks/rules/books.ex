defmodule Quacks.Rules.Books do
  @moduledoc """
  The ingredient books as player-facing text, one entry per `{colour, set}` the
  engine supports. Sources: `docs/research/rulebook.md` §4 (Set 1),
  `docs/research/ingredient-sets-and-customisation.md` §1.3 (Sets 2–4) and
  `docs/research/herb-witches.md` §2.3–2.5 (Sets 5–6, black, locoweed, orange 6).

  `trigger` says when the book acts: `:on_draw` (when the chip is placed),
  `:step_b` (evaluation step B), `:passive` (for the rest of the round) or `:none`.
  A book whose reward grows with the number of chips also has `tiers`, one
  `{label, text}` row per tier; its `text` is then the one-line summary.
  """

  alias Quacks.Rules.Chips

  @type trigger :: :on_draw | :step_b | :passive | :none
  @type book :: %{
          name: String.t(),
          text: String.t(),
          trigger: trigger,
          prices: [pos_integer],
          tiers: [{String.t(), String.t()}]
        }

  @names %{
    white: "Cherry bomb",
    orange: "Pumpkin",
    green: "Garden spider",
    blue: "Crow skull",
    red: "Toadstool",
    yellow: "Mandrake",
    purple: "Ghost's breath",
    black: "Hawkmoth",
    locoweed: "Locoweed"
  }

  @books %{
    {:white, 1} => {:none, "Your pot explodes when your white chips total more than 7."},
    {:orange, 1} => {:none, "The chip only fills the pot."},
    {:orange, 2} => {:none, "Adds the orange 6-chip (22 coins). Orange chips only fill the pot."},
    {:green, 1} =>
      {:step_b, "1 ruby for each green chip that is your last or next-to-last chip."},
    {:green, 2} =>
      {:step_b,
       "For each green chip last or next-to-last: green 1 gives an orange 1, green 2 a blue 1 or red 1, green 4 a yellow 1 or purple 1."},
    {:green, 3} =>
      {:step_b,
       "If your white chips total exactly 7, your last chip moves on by the sum of your green values."},
    {:green, 4} =>
      {:step_b,
       "For each green chip last or next-to-last, you may pay 1 ruby to move your droplet 1 space."},
    {:green, 5} =>
      {:step_b,
       "For each green chip last or next-to-last, pick a pot chip of equal or lower value: it is a first chip of the next round."},
    {:green, 6} =>
      {:step_b, "Roll the bonus die once for each green chip that is last or next-to-last."},
    {:blue, 1} =>
      {:on_draw,
       "Draw 1, 2 or 4 more chips (its value). You may place one of them; the rest go back."},
    {:blue, 2} =>
      {:on_draw,
       "Protects the next 1, 2 or 4 chips (its value): if your pot explodes in that window, you get both VP and coins."},
    {:blue, 3} => {:on_draw, "If it lands on a ruby space, take 1 ruby."},
    {:blue, 4} => {:on_draw, "If it lands on a ruby space, score VP equal to its value."},
    {:blue, 5} =>
      {:on_draw,
       "If your pot has at least as many orange chips as its value, score VP equal to its value."},
    {:blue, 6} =>
      {:on_draw,
       "Look back at as many chips as its value: 1 ruby for each white 1-chip among them."},
    {:red, 1} =>
      {:on_draw, "1 or 2 orange chips in your pot: move 1 more space. 3 or more: 2 more."},
    {:red, 2} =>
      {:on_draw,
       "Put it beside the pot. After you stop, place it, keep it for a later round or return it to the bag."},
    {:red, 3} => {:on_draw, "Right after a white chip: move that white chip's value more."},
    {:red, 4} =>
      {:passive,
       "Once a red chip is in your pot, each white 1-chip after it moves 2 spaces (it still counts 1)."},
    {:red, 5} =>
      {:on_draw, "If a higher red chip is already in your pot, move by that higher value."},
    {:red, 6} =>
      {:on_draw,
       "Draw one more chip and set it aside. Place it when you like; you must place it this round, even after an explosion."},
    {:yellow, 1} =>
      {:on_draw, "Right after a white chip: you may put that white chip back in your bag."},
    {:yellow, 2} => {:on_draw, "The next chip you place moves twice as far."},
    {:yellow, 3} =>
      {:passive, "Your 1st yellow chip raises the white limit to 8, your 3rd to 9."},
    {:yellow, 4} =>
      {:on_draw, "Your 1st, 2nd and 3rd yellow chip this round move 1, 2 and 3 more spaces."},
    {:yellow, 5} =>
      {:on_draw,
       "Peek at one more chip: the yellow moves on by its value (locoweed 1). The chip goes back."},
    {:yellow, 6} => {:on_draw, "You may pay 1 ruby to move it 3 more spaces."},
    {:purple, 1} => {:step_b, "VP, rubies and droplet moves by the number of purple chips."},
    {:purple, 2} =>
      {:step_b,
       "You may trade in 1, 2 or 3 purple chips from your pot (back to the supply) for one reward tier. Once per round. You may trade fewer than you drew."},
    {:purple, 3} =>
      {:step_b, "VP per purple chip by its space: 0–9 none, 10–19 1 VP, 20–29 2 VP, 30+ 3 VP."},
    {:purple, 4} =>
      {:step_b,
       "Swap one chip in your pot for a bigger chip of its colour (into your bag); more purple chips, bigger swap."},
    {:purple, 5} =>
      {:step_b,
       "The VP of the spaces with a purple chip become coins to buy up to 2 chips. Round 9: VP, 5 for 1."},
    {:purple, 6} =>
      {:step_b,
       "Each purple chip scores VP equal to the printed value of the chip right after it (locoweed 1)."},
    {:black, 1} =>
      {:step_b,
       "As many black chips as your opponent (more than one neighbour): droplet +1. More (than both): also 1 ruby."},
    {:black, 5} =>
      {:step_b,
       "A black chip you buy goes in the left player's bag; your droplet moves 1. Step B: 1 ruby per black chip in the left pot and per black last or next-to-last in yours."},
    {:black, 6} =>
      {:step_b,
       "The furthest black chip at the table moves its owner's droplet 1; the second furthest gives 1 ruby."},
    {:locoweed, 5} =>
      {:on_draw, "Moves your rat stone distance plus 1, at most 4. No rats: it moves 1."},
    {:locoweed, 6} =>
      {:on_draw,
       "Copies the move and action of the last coloured chip in your pot (white skipped). None: moves 1, no action."}
  }

  # The reward tiers, from `docs/research/ingredient-sets-and-customisation.md` §1.3.
  @tiers %{
    {:purple, 1} => [
      {"1 purple", "1 VP"},
      {"2 purple", "1 VP · 1 ruby"},
      {"3+ purple", "2 VP · droplet +1"}
    ],
    {:purple, 2} => [
      {"1 purple", "black 1 · 1 VP · 1 ruby"},
      {"2 purple", "green 1 · blue 2 · 3 VP · droplet +1"},
      {"3 purple", "yellow 4 · 6 VP · 1 ruby · droplet +2"}
    ],
    {:purple, 4} => [
      {"1 purple", "a 1-chip → a 2-chip"},
      {"2 purple", "a 2-chip → a 4-chip"},
      {"3+ purple", "a 1-chip → a 4-chip"}
    ]
  }

  @doc """
  The book `{colour, set}`: its name, trigger, text, prices (coins per chip value,
  low to high) and reward `tiers` (`[]` for most books).

      iex> Quacks.Rules.Books.get({:green, 1})
      %{
        name: "Garden spider",
        trigger: :step_b,
        text: "1 ruby for each green chip that is your last or next-to-last chip.",
        prices: [4, 8, 14],
        tiers: []
      }
  """
  @spec get({Chips.colour(), 1..6}) :: book
  def get({colour, set} = key) do
    {trigger, text} = Map.fetch!(@books, key)
    sets = %{colour => set}

    prices =
      for {^colour, _} = chip <- Chips.shop(:herb_witches, sets), do: Chips.price(chip, sets)

    %{
      name: @names[colour],
      trigger: trigger,
      text: text,
      prices: prices,
      tiers: Map.get(@tiers, key, [])
    }
  end

  @doc "Every supported `{colour, set}`, sorted."
  @spec keys() :: [{Chips.colour(), 1..6}]
  def keys, do: @books |> Map.keys() |> Enum.sort()

  @doc "The sets of `colour` that have a book, e.g. `[1, 5, 6]` for black."
  @spec sets(Chips.colour()) :: [1..6]
  def sets(colour), do: for({^colour, set} <- keys(), do: set)

  @doc """
  The books in play, as `{colour, set}` in table order: orange, green, blue, red,
  yellow, purple, black, then locoweed when it is picked.
  """
  @spec in_play(Chips.expansion(), Chips.sets()) :: [{Chips.colour(), 1..6}]
  def in_play(expansion, sets) do
    colours = [:orange, :green, :blue, :red, :yellow, :purple, :black]
    books = for colour <- colours, do: {colour, Chips.set(expansion, sets, colour)}

    case Chips.set(expansion, sets, :locoweed) do
      nil -> books
      set -> books ++ [{:locoweed, set}]
    end
  end
end
