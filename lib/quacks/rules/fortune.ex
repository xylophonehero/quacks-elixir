defmodule Quacks.Rules.Fortune do
  @moduledoc """
  The 24 Fortune Teller cards of the base game: 11 blue (a rule for the whole round)
  and 13 purple (resolved once before the round). Names and texts from
  `docs/research/rulebook.md` §5. ⚠️ That list is a fan transcription of the North
  Star English edition.

  The Alchemists box adds 20 cards (`:ap1`…`:ap10` purple, `:ab1`…`:ab10` blue;
  `docs/research/alchemists-fortune-cards.md`, Schmidt English text): 14 for any
  game, 3 that need The Herb Witches (`expansion: :herb_witches`) and 3 that need
  The Alchemists (`expansion: :alchemists`). The 14 are in every deck (the base game
  too); a card with an expansion is in the deck only when that expansion is in play.
  The house rule `alch_cards: false` takes all 20 out (`Quacks.Game`).

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
          | :ap1
          | :ap2
          | :ap3
          | :ap4
          | :ap5
          | :ap6
          | :ap7
          | :ap8
          | :ap9
          | :ap10
          | :ab1
          | :ab2
          | :ab3
          | :ab4
          | :ab5
          | :ab6
          | :ab7
          | :ab8
          | :ab9
          | :ab10
  @type card :: %{
          id: id,
          colour: :blue | :purple,
          name: String.t(),
          text: String.t(),
          expansion: nil | :alchemists | :herb_witches
        }

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
     "Draw 4 tokens from your bag. You can trade one in for the next higher value of the same colour from the supply. If not possible, take a green 1 instead. Put all tokens back."},
    # The Alchemists box (Schmidt English card text).
    {:ap1, "Spoiled for choice",
     "Choose: Receive 1 ruby, 1 die roll and 3 additional rat-tails OR 1 red 2-chip."},
    {:ap2, "Ruby fever",
     "Each player immediately draws one chip from the bag and takes as many rubies as the value of the chip drawn. Then return the chips to the bag and begin the Preparation Phase."},
    {:ap3, "Give and take",
     "You can surrender 1, 2, or 4 rubies. Take a 1-chip, 2-chip, or 4-chip (any color except purple) in return OR take 2 rubies."},
    {:ap4, "Rich offerings",
     "Choose: Receive 8 additional rat-tails OR roll 4 times OR move your droplet forward 3 spaces."},
    {:ap5, "A small donation",
     "If you have 2 or more rat-tails in your cauldron at the start of a round, you may roll the die once."},
    {:ap6, "A rat to cherish",
     "You may surrender up to 3 rubies. For each ruby you surrender, you receive 3 additional rat-tails."},
    {:ap7, "A quick exchange",
     "You may surrender one of your witch pennies in exchange for a chip of your choice."},
    {:ap8, "Neighbor in need",
     "Choose: The player to your left may permanently remove a white 1-chip OR take a chip of their choice."},
    {:ap9, "Useful rodent",
     "You may forgo 2, 4, or 6 rat-tails and take a 1-chip, 2-chip, or 4-chip in exchange (any color except purple)."},
    {:ap10, "A powerful tipple",
     "You may move your droplet back 1 or 2 spaces and take a 2-chip or 4-chip in exchange."},
    {:ab1, "From good to better",
     "After you STOP: you can permanently remove 1 colored 2-chip or 4-chip from your cauldron. Take another 2-chip or 4-chip from the supply pile in exchange and place it in the same position."},
    {:ab2, "Sale",
     "If you buy 2 chips in this round, you receive the cheaper one a second time for free."},
    {:ab3, "The white blessing",
     "After you STOP: If the last chip in your cauldron is white, receive as many victory points as the value indicated on that chip."},
    {:ab4, "A rat's blessing",
     "In this round, your purchasing power increases by twice the number of rat-tails in your cauldron."},
    {:ab5, "A good neighborhood",
     "If your cauldron has not exploded yet, you may return your white 3-chip to your bag at ANY time. If you do so, the player to your left receives 2 rubies."},
    {:ab6, "A blessing in disguise",
     "If your cauldron explodes in this round, your essence increases by 2 additional spaces."},
    {:ab7, "Essential essence",
     "The player(s) whose essence has the highest value after the Essence Phase may roll the die once OR refill their flask."},
    {:ab8, "Visit from a witch",
     "Immediately draw a random herb witch from the ones not currently in play. Each player may use this once in this round for free."},
    {:ab9, "All's well that ends well.",
     "Your essence increases by the number of spaces corresponding to the value of the last chip in your cauldron."},
    {:ab10, "A joyful reunion",
     "At the end of the round, one of your witch pennies is returned to you."}
  ]

  # The Alchemists box: the cards with an expansion symbol.
  @needs %{
    ap7: :herb_witches,
    ab8: :herb_witches,
    ab10: :herb_witches,
    ab6: :alchemists,
    ab7: :alchemists,
    ab9: :alchemists
  }

  @ids Enum.map(@cards, &elem(&1, 0))
  @base Enum.reject(@ids, &String.starts_with?(Atom.to_string(&1), "a"))
  @box @ids -- @base

  # Rulebook §6.2: cards that need other players are not in a solo deck. The
  # Alchemists box: our solo game has no rats and no left neighbour.
  @not_solo [:p4, :p5, :p8, :b2, :ap5, :ap6, :ap8, :ap9, :ab4]

  @doc "All 44 cards: the 24 base cards (blue first), then the 20 of The Alchemists."
  @spec all() :: [card]
  def all, do: Enum.map(@ids, &card/1)

  @doc "One card by id."
  @spec card(id) :: card
  def card(id) do
    {^id, name, text} = List.keyfind(@cards, id, 0)
    colour = if Atom.to_string(id) =~ ~r/^a?b/, do: :blue, else: :purple
    %{id: id, colour: colour, name: name, text: text, expansion: @needs[id]}
  end

  @doc "Whether `id` is one of the 20 cards of The Alchemists box."
  @spec alchemists?(id) :: boolean
  def alchemists?(id), do: id in @box

  @doc """
  The card ids in a deck for `players` players with `expansions` in play: the 24
  base cards and the 14 general box cards, plus each box card whose expansion is in
  play. Solo leaves out the cards that need other players.
  """
  @spec ids(1..8, Enumerable.t()) :: [id]
  def ids(players, expansions \\ []) do
    expansions = MapSet.new(expansions)
    box = Enum.filter(@box, &(@needs[&1] == nil or MapSet.member?(expansions, @needs[&1])))
    ids = @base ++ box
    if players == 1, do: ids -- @not_solo, else: ids
  end

  @doc "The 24 base card ids (the deck with the house rule `alch_cards: false`)."
  @spec base_ids(1..8) :: [id]
  def base_ids(players), do: if(players == 1, do: @base -- @not_solo, else: @base)
end
