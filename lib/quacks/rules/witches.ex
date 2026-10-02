defmodule Quacks.Rules.Witches do
  @moduledoc """
  The 12 herb witch cards of The Herb Witches (`docs/research/herb-witches.md` §2.1):
  3 types (the penny colour) x 4 witches. The rules live in `Quacks.Game.Witches`.

  Ids are ours (`:s1`–`:s4` silver, `:c1`–`:c4` copper, `:g1`–`:g4` gold). Only the
  silver cards have a printed header in the rulebook; the other titles are ours ⚠️.
  """

  @type colour :: :silver | :copper | :gold
  @type id :: :s1 | :s2 | :s3 | :s4 | :c1 | :c2 | :c3 | :c4 | :g1 | :g2 | :g3 | :g4
  @type card :: %{id: id, colour: colour, title: String.t(), text: String.t()}

  @cards [
    %{
      id: :s1,
      colour: :silver,
      title: "Flask after the explosion",
      text:
        "Your pot exploded: use your full flask. The last white chip goes back in the bag and you may draw on."
    },
    %{
      id: :s2,
      colour: :silver,
      title: "Draw 6 chips",
      text:
        "Draw 6 chips from your bag. Place any of them in your pot, in any order, with their actions. The rest go back in the bag."
    },
    %{
      id: :s3,
      colour: :silver,
      title: "Two whites back",
      text:
        "Return the last white chip, or the last 2 white chips, in your pot to the bag. The gaps stay empty."
    },
    %{
      id: :s4,
      colour: :silver,
      title: "No explosion penalty",
      text:
        "Your pot exploded: take the victory points and buy chips. On the highest scoring space you roll the bonus die too."
    },
    %{
      id: :c1,
      colour: :copper,
      title: "Upgrade",
      text:
        "Upgrade the last 2 chips in your pot by one level, or 1 chip anywhere in your pot (1 → 2, 2 → 4; not orange). The bigger chip goes in your bag."
    },
    %{
      id: :c2,
      colour: :copper,
      title: "Double coins",
      text: "Double your coins for buying. Still at most 2 chips of different colours."
    },
    %{
      id: :c3,
      colour: :copper,
      title: "One free copy",
      text: "Buy a chip and take an identical chip for free."
    },
    %{
      id: :c4,
      colour: :copper,
      title: "Rubies to coins",
      text: "Get 2 coins for each ruby you have. You keep the rubies."
    },
    %{
      id: :g1,
      colour: :gold,
      title: "Colours in the pot",
      text:
        "Victory points for the different colours in your pot (not white): 1–4 → 3, 5 → 4, 6 → 7, 7 → 10, 8 → 14."
    },
    %{
      id: :g2,
      colour: :gold,
      title: "Count the bag",
      text:
        "2 victory points for each chip in your bag that is a coloured 2-, 4- or 6-chip, a purple chip or a locoweed chip."
    },
    %{
      id: :g3,
      colour: :gold,
      title: "Rubies for points",
      text:
        "Your scoring space has a ruby: take as many rubies as it shows victory points. You keep the victory points."
    },
    %{
      id: :g4,
      colour: :gold,
      title: "Cheap rubies",
      text:
        "This end of round, the droplet and the flask cost 1 ruby instead of 2, as often as you like."
    }
  ]

  @by_id Map.new(@cards, &{&1.id, &1})

  @doc "The card with `id`."
  @spec card(id) :: card
  def card(id), do: Map.fetch!(@by_id, id)

  @doc "The 4 witch ids of one colour."
  @spec ids(colour) :: [id]
  def ids(colour), do: for(%{colour: ^colour, id: id} <- @cards, do: id)

  @doc """
  Turn up one witch of each colour, with a jump of the game's `rng` (a different
  jump from the Fortune Teller deck), so the game's own random stream stays the same.
  """
  @spec deal(:rand.state()) :: %{colour => id}
  def deal(rng) do
    {witches, _rng} =
      Enum.map_reduce([:silver, :copper, :gold], rng |> :rand.jump() |> :rand.jump(), fn
        colour, rng ->
          {i, rng} = :rand.uniform_s(4, rng)
          {{colour, Enum.at(ids(colour), i - 1)}, rng}
      end)

    Map.new(witches)
  end
end
