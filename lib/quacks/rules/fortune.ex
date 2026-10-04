defmodule Quacks.Rules.Fortune do
  @moduledoc """
  The 24 Fortune Teller cards: 11 blue (a rule for the whole round) and 13 purple
  (resolved once before the round). Names and texts from `docs/research/rulebook.md`
  §5. ⚠️ That list is a fan transcription of the North Star English edition.

  The rules live in `Quacks.Game.Fortune`; this module is data only.
  """

  @type id ::
          :b1
          | :b2
          | :b3
          | :b4
          | :b5
          | :b6
          | :b7
          | :b8
          | :b9
          | :b10
          | :b11
          | :p1
          | :p2
          | :p3
          | :p4
          | :p5
          | :p6
          | :p7
          | :p8
          | :p9
          | :p10
          | :p11
          | :p12
          | :p13
  @type card :: %{id: id, colour: :blue | :purple, name: String.t(), text: String.t()}

  @cards [
    {:b1, "Bubbling Over",
     "If your white tokens total exactly 7 when you stop drawing, move your droplet marker a space forward."},
    {:b2, "Toil and Trouble",
     "If your cauldron explodes this round, the player to your left gets to take any 2-value token from the supply."},
    {:b3, "Second Chances",
     "After you put the first 5 tokens on your cauldron, you can choose to continue drawing or put all of your tokens back in your bag and begin the round all over again. Once only."},
    {:b4, "Double Double",
     "Whenever anyone rolls the bonus die this round, they can roll it twice."},
    {:b5, "Portentous Potables",
     "This round, the cauldron explosion limit is increased from 7 to 9."},
    {:b6, "Pumpkin Party", "This round, every orange token moves an extra space forward."},
    {:b7, "Safety Procedure",
     "Beginning with the start player, if you stop before your cauldron explodes, draw up to 5 tokens from your bag. You can put one of them on your cauldron."},
    {:b8, "Lucky Devil",
     "If your final space this round shows a ruby, score 2 victory points (even if your cauldron has exploded)."},
    {:b9, "Flask Rabbit", "At the end of the round, refill all flasks for free."},
    {:b10, "Cauldron Bubble",
     "This round, you can put the first white token you draw back into your bag."},
    {:b11, "Fire Burn", "If your final space this round shows a ruby, take an extra ruby."},
    {:p1, "Choices, Choices", "Take a black token OR any 2-value token OR 3 rubies."},
    {:p2, "Drop It", "Move your droplet marker a space forward."},
    {:p3, "Wheeling and Dealing",
     "You can trade in a ruby for any 1-value token besides orange, purple or black."},
    {:p4, "Charity", "The player(s) with the fewest rubies can take a ruby."},
    {:p5, "Beginner's Luck",
     "The player(s) with the fewest victory points receives a green 1 token."},
    {:p6, "Boomberry Cleanse", "Score 4 victory points OR remove a white 1 token from your bag."},
    {:p7, "Infestation",
     "Count your rat tails again and move your rat marker that many extra spaces."},
    {:p8, "Less is More",
     "Everyone draws 5 tokens from their bags. The player(s) with the lowest sum takes a blue 2 token. Everyone else takes a ruby. Put the tokens back."},
    {:p9, "Good Start",
     "You can move your rat marker back by 1-3 spaces and take that many rubies."},
    {:p10, "Rat-a-Tat",
     "Take any 4-value token OR score a victory point for each rat tail you're currently behind the leader."},
    {:p11, "Decisions, Decisions...",
     "Move your droplet marker 2 spaces forward OR take a purple token."},
    {:p12, "Take a Chance", "Everyone rolls the bonus die once and gets the reward shown."},
    {:p13, "Flea Market",
     "Draw 4 tokens from your bag. You can trade one in for the next higher value of the same colour from the supply. If not possible, take a green 1 instead. Put all tokens back."}
  ]

  @ids Enum.map(@cards, &elem(&1, 0))

  # Rulebook §6.2: cards that need other players are not in a solo deck.
  @not_solo [:p4, :p5, :p8, :b2]

  @doc "All 24 cards, blue first."
  @spec all() :: [card]
  def all, do: Enum.map(@ids, &card/1)

  @doc "One card by id."
  @spec card(id) :: card
  def card(id) do
    {^id, name, text} = List.keyfind(@cards, id, 0)
    colour = if String.starts_with?(Atom.to_string(id), "b"), do: :blue, else: :purple
    %{id: id, colour: colour, name: name, text: text}
  end

  @doc "The card ids in a deck for `players` players: solo leaves out four cards."
  @spec ids(1..8) :: [id]
  def ids(1), do: @ids -- @not_solo
  def ids(_players), do: @ids
end
