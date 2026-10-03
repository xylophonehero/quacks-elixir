defmodule Quacks.Rules.Books do
  @moduledoc """
  The ingredient books as player-facing text, one entry per `{colour, set}` the
  engine supports. Sources: `docs/research/rulebook.md` §4 (Set 1),
  `docs/research/ingredient-sets-and-customisation.md` §1.3 (Sets 2–4) and
  `docs/research/herb-witches.md` §2.3–2.5 (Sets 5–6, black, locoweed, orange 6) and
  `docs/research/alchemists.md` §2 (locoweed 8–10).

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
    {:white, 1} =>
      {:none,
       "Your pot explodes when your white chips total more than your limit (7, unless a house rule, mandrake Set 3 or a card raises it); the chip is still placed and you must stop."},
    {:orange, 1} => {:none, "The chip only fills the pot."},
    {:orange, 2} =>
      {:none,
       "Orange 1- and 6-chips only fill the pot 1 or 6 spaces; no book, witch or card can upgrade an orange chip."},
    {:green, 1} =>
      {:step_b, "1 ruby for each green chip that is your last or next-to-last chip."},
    {:green, 2} =>
      {:step_b,
       "For each green chip that is your last or next-to-last chip, you may put 1 chip from the supply into your bag."},
    {:green, 3} =>
      {:step_b,
       "If your white chips total exactly 7, your last chip moves on by the sum of your green values."},
    {:green, 4} =>
      {:step_b,
       "For each green chip last or next-to-last, you may pay 1 ruby to move your droplet 1 space."},
    {:green, 5} =>
      {:step_b,
       "For each green chip that is your last or next-to-last chip, you may pick a chip in your pot worth at most that green (locoweed 1); next round it is placed first, in the order you picked, with its normal action."},
    {:green, 6} =>
      {:step_b, "Roll the bonus die once for each green chip that is last or next-to-last."},
    {:blue, 1} =>
      {:on_draw,
       "Draw 1, 2 or 4 more chips (its value): you may place one of them, it acts at once, and the rest go back to your bag."},
    {:blue, 2} =>
      {:on_draw,
       "Protects your next 1, 2 or 4 drawn chips (its value): if one of them explodes the pot, you still get VP and coins but no bonus die; windows do not add up, the larger one counts."},
    {:blue, 3} => {:on_draw, "If it lands on a ruby space, take 1 ruby."},
    {:blue, 4} => {:on_draw, "If it lands on a ruby space, score VP equal to its value."},
    {:blue, 5} =>
      {:on_draw,
       "If your pot has at least as many orange chips as its value, score VP equal to its value."},
    {:blue, 6} =>
      {:on_draw,
       "Look back at as many chips as its value: 1 ruby for each white 1-chip among them."},
    {:red, 1} =>
      {:on_draw,
       "Moves 1 more space with 1 or 2 orange chips in your pot, 2 more with 3 or more."},
    {:red, 2} =>
      {:on_draw,
       "When drawn, put it beside the pot; after you stop (also after an explosion), decide for each red chip there: place it after your last chip (it moves its value), keep it for a later round, or return it to your bag."},
    {:red, 3} => {:on_draw, "Right after a white chip: move that white chip's value more."},
    {:red, 4} =>
      {:passive,
       "Once a red chip is in your pot, each white 1-chip after it moves 2 spaces (it still counts 1)."},
    {:red, 5} =>
      {:on_draw, "If a higher red chip is already in your pot, move by that higher value."},
    {:red, 6} =>
      {:on_draw,
       "Draw 1 more chip and set it aside; place it when you like, but this round, even after an explosion (a white one still counts; placed after you stop, it has no action)."},
    {:yellow, 1} =>
      {:on_draw, "Right after a white chip: you may put that white chip back in your bag."},
    {:yellow, 2} =>
      {:on_draw,
       "The next chip you place moves twice as far, bonus spaces included (lost if this yellow is on the last space)."},
    {:yellow, 3} =>
      {:passive, "Your 1st yellow chip raises the white limit to 8, your 3rd to 9."},
    {:yellow, 4} =>
      {:on_draw, "Your 1st, 2nd and 3rd yellow chip this round move 1, 2 and 3 more spaces."},
    {:yellow, 5} =>
      {:on_draw,
       "Draw 1 more chip: the yellow moves on by its value (locoweed 1), then the chip goes back to your bag with no effect, even a white one."},
    {:yellow, 6} => {:on_draw, "You may pay 1 ruby to move it 3 more spaces."},
    {:purple, 1} =>
      {:step_b,
       "Count the purple chips in your pot and take the one reward for that count; 4 or more count as 3."},
    {:purple, 2} =>
      {:step_b,
       "Once per round you may trade in 1, 2 or 3 purple chips from your pot (back to the supply, fewer than you drew is allowed) for the reward tier of that count."},
    {:purple, 3} =>
      {:step_b,
       "Each purple chip scores VP by the number printed on its space: 0–9 none, 10–19 1 VP, 20–29 2 VP, 30 or more 3 VP."},
    {:purple, 4} =>
      {:step_b,
       "You may swap one green, blue, red or yellow chip in your pot for a bigger one of its colour from the supply, straight into your bag; more purple chips allow a bigger swap, a smaller one is always allowed."},
    {:purple, 5} =>
      {:step_b,
       "Add the VP of every space with a purple chip: you may spend that sum now on up to 2 chips of different colours (it never adds to your shop coins; in round 9 each 5 gives 1 VP)."},
    {:purple, 6} =>
      {:step_b,
       "Each purple chip scores VP equal to the printed value of the chip right after it (locoweed 1)."},
    {:black, 1} => {:step_b, "Compare your black chips with the other players' (see table)."},
    {:black, 5} =>
      {:step_b,
       "A black chip you buy or get from a card goes into the left player's bag (solo: back to the supply) and your droplet moves 1; at step B take 1 ruby per black chip in the left player's pot and per black chip that is your last or next-to-last chip."},
    {:black, 6} =>
      {:step_b,
       "The owner of the furthest black chip at the table moves the droplet 1 and the owner of the second-furthest takes 1 ruby; one player can get both and ties share (solo: 1 black chip gives the droplet, 2 the ruby too)."},
    {:locoweed, 5} =>
      {:on_draw, "Moves your rat stone distance plus 1, at most 4 (no rats: it moves 1)."},
    {:locoweed, 6} =>
      {:on_draw,
       "Acts as the last coloured chip in your pot (white and locoweed skipped): same value, bonus move and on-draw action, but it stays locoweed for every count; no coloured chip: it moves 1 with no action."},
    # The Alchemists (`docs/research/alchemists.md` §2). Book A (7) needs the essence phase.
    {:locoweed, 8} =>
      {:on_draw,
       "Moves 1 space for each colour in your pot, white not counted and locoweed always counted (so at least 1)."},
    {:locoweed, 9} =>
      {:on_draw,
       "Moves 1; then you may return 1 coloured chip (not white, this locoweed allowed) from your pot to your bag, and the other chips stay where they are."},
    {:locoweed, 10} =>
      {:on_draw,
       "Moves as many spaces as the printed values of the white chips in your pot add up to, at least 1."}
  }

  # The reward tiers, from `docs/research/rulebook.md` §4,
  # `docs/research/ingredient-sets-and-customisation.md` §1.3 and `docs/research/herb-witches.md`.
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
    ],
    {:green, 2} => [
      {"green 1", "orange 1"},
      {"green 2", "blue 1 or red 1"},
      {"green 4", "yellow 1 or purple 1"}
    ],
    {:red, 1} => [
      {"0 orange", "no extra"},
      {"1–2 orange", "+1 space"},
      {"3+ orange", "+2 spaces"}
    ],
    {:yellow, 3} => [
      {"1st yellow", "white limit 8"},
      {"3rd yellow", "white limit 9"}
    ],
    {:yellow, 4} => [
      {"1st yellow", "+1 space"},
      {"2nd yellow", "+2 spaces"},
      {"3rd yellow", "+3 spaces"},
      {"4th+ yellow", "no bonus"}
    ],
    {:purple, 3} => [
      {"space 0–9", "0 VP"},
      {"space 10–19", "1 VP"},
      {"space 20–29", "2 VP"},
      {"space 30+", "3 VP"}
    ],
    {:black, 1} => [
      {"2 players: same count", "droplet +1"},
      {"2 players: more", "droplet +1 · 1 ruby"},
      {"3+ players: more than 1 neighbour", "droplet +1"},
      {"3+ players: more than both", "droplet +1 · 1 ruby"},
      {"solo: 1+ black", "droplet +1 (house rule: also 1 ruby)"}
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
  @spec get({Chips.colour(), 1..10}) :: book
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
  @spec keys() :: [{Chips.colour(), 1..10}]
  def keys, do: @books |> Map.keys() |> Enum.sort()

  @doc "The sets of `colour` that have a book, e.g. `[1, 5, 6]` for black."
  @spec sets(Chips.colour()) :: [1..10]
  def sets(colour), do: for({^colour, set} <- keys(), do: set)

  @doc """
  The books in play, as `{colour, set}` in table order: orange, green, blue, red,
  yellow, purple, black, then locoweed when it is picked.
  """
  @spec in_play(Chips.expansion(), Chips.sets()) :: [{Chips.colour(), 1..10}]
  def in_play(expansion, sets) do
    colours = [:orange, :green, :blue, :red, :yellow, :purple, :black]
    books = for colour <- colours, do: {colour, Chips.set(expansion, sets, colour)}

    case Chips.set(expansion, sets, :locoweed) do
      nil -> books
      set -> books ++ [{:locoweed, set}]
    end
  end
end
