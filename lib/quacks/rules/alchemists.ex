defmodule Quacks.Rules.Alchemists do
  @moduledoc """
  The 8 patients of The Alchemists (`docs/research/alchemists-essences.md` §2.5): the
  essence card glass slots, the Witch's hump table and the patient deal. The rules
  live in `Quacks.Game.Essence`.

  ⚠️ Every slot value was read from small card pictures in the English rulebook (A2).
  Nick: correct `@slots` from the real essence cards in the box. The texts are verified.

  Slot terms (one list per flask space 1..10, `[]` = empty glass):
  `{:vp, n}` VP now, `:rat` a rat stone of 1 next round, `{:draw, n}` Nervousness
  display, `{:ear_worm, n}` forced draws, `{:buy, coins}` Vampirism, and the Chicken
  eyes glasses `{:rubies, n}`, `{:chip, chip}`, `{:swap, 1, 2 | 4}`, `:flask`,
  `{:dice, n}`, `{:droplet, n}`.
  """

  alias Quacks.Rules.Chips

  @type id ::
          :nervousness
          | :ear_worm
          | :carrot_nose
          | :wing_ears
          | :chicken_eyes
          | :witch_hump
          | :forgetfulness
          | :vampirism
  @type term_ ::
          {:vp, pos_integer}
          | :rat
          | {:draw, pos_integer}
          | {:ear_worm, pos_integer}
          | {:buy, pos_integer}
          | {:rubies, pos_integer}
          | {:chip, Chips.chip()}
          | {:swap, 1, 2 | 4}
          | :flask
          | {:dice, pos_integer}
          | {:droplet, pos_integer}
  @type patient :: %{
          id: id,
          name: String.t(),
          de: String.t(),
          when: :preparation | :end_of_essence,
          start_chips: [Chips.chip()],
          slots: %{(1..10) => [term_]},
          text: String.t()
        }

  @max_space 10

  # Order of the rulebook (A2 pp. 4–6).
  @patients [
    :nervousness,
    :ear_worm,
    :carrot_nose,
    :wing_ears,
    :chicken_eyes,
    :witch_hump,
    :forgetfulness,
    :vampirism
  ]

  # ⚠️ Read from the card pictures; correct from the box.
  @vp_tail [[{:vp, 1}], [{:vp, 1}], [{:vp, 2}], [{:vp, 2}]]
  @slots %{
    nervousness: [[:rat] | for(n <- [1, 2, 3, 4, 5, 6, 7, 8, 10], do: [{:draw, n}])],
    ear_worm:
      for(n <- 1..8, do: [{:ear_worm, div(n + 1, 2)} | if(rem(n, 2) == 0, do: [:rat], else: [])]) ++
        [[{:ear_worm, 5}], [{:ear_worm, 6}]],
    carrot_nose: [[:rat], [], [:rat], [], [:rat], []] ++ @vp_tail,
    wing_ears: [[:rat], [], [], [], [], []] ++ @vp_tail,
    chicken_eyes: [
      [{:rubies, 1}],
      [{:chip, {:orange, 1}}],
      [{:swap, 1, 2}],
      [:flask],
      [{:chip, {:red, 1}}],
      [{:rubies, 3}],
      [{:dice, 2}],
      [{:droplet, 2}],
      [{:swap, 1, 4}],
      [{:dice, 4}]
    ],
    witch_hump: [[:rat], [], [:rat], [], [:rat], []] ++ @vp_tail,
    forgetfulness: [[], [], [], [], [], []] ++ @vp_tail,
    vampirism: [[:rat] | for(n <- 2..10, do: [{:buy, n}])]
  }

  @info %{
    nervousness:
      {"Nervousness", "Schreckhaftigkeit", :preparation, [],
       "Space 1: 1 rat tail next round. Else, at the start of the next preparation phase draw that many chips; the white ones go back, the rest lie out. Before each chip you may place one of them instead of drawing."},
    ear_worm:
      {"Ear worm", "Ohrwurm", :end_of_essence, [],
       "At the end of the essence phase draw that many chips one by one and place them with their actions. The pot cannot explode."},
    carrot_nose:
      {"Carrot nose", "Rübennase", :preparation, [{:orange, 1}],
       "Start with 1 more pumpkin. Next preparation phase: each time you draw a pumpkin you may spend 2 essence to put it on the next ruby space."},
    wing_ears:
      {"Wing ears", "Segelohren", :preparation, [],
       "Next preparation phase: each time you draw a white chip that does not explode the pot, spend 2 essence to move it double, or 3 essence to return it to the bag."},
    chicken_eyes:
      {"Chicken eyes", "Hühneraugen", :end_of_essence, [],
       "Take the bonus of your space at the end of the essence phase."},
    witch_hump:
      {"Witch's hump", "Hexenbuckel", :preparation, [],
       "Next preparation phase: each time you place a chip on a ruby space, you may spend 2 essence. 1-chip: 1 ruby. 2-chip or hawkmoth: roll the bonus die. 3-chip or ghost's breath: a mandrake 1. 4-chip or locoweed: 3 VP."},
    forgetfulness:
      {"Forgetfulness", "Vergesslichkeit", :preparation, [{:black, 1}, {:red, 1}],
       "Start with 1 more hawkmoth and toadstool. Next preparation phase: return a coloured pot chip (not locoweed) to the bag for as much essence as its value."},
    vampirism:
      {"Vampirism", "Vampirismus", :end_of_essence, [],
       "Space 1: 1 rat tail next round. Else buy 1 chip for as many coins as your space at the end of the essence phase."}
  }

  @doc "The 8 patient ids, in rulebook order."
  @spec patients() :: [id]
  def patients, do: @patients

  @doc "The patient `id` with its card text and slots (see the moduledoc)."
  @spec get(id) :: patient
  def get(id) do
    {name, de, at, start_chips, text} = Map.fetch!(@info, id)
    slots = @slots |> Map.fetch!(id) |> Enum.with_index(1) |> Map.new(fn {s, i} -> {i, s} end)
    %{id: id, name: name, de: de, when: at, start_chips: start_chips, slots: slots, text: text}
  end

  @doc "The glass of `id` at flask space `space` (0 is the bulb: no glass)."
  @spec slot(id, 0..10) :: [term_]
  def slot(_id, 0), do: []
  def slot(id, space) when space in 1..@max_space, do: Enum.at(Map.fetch!(@slots, id), space - 1)

  @doc "The last flask space. Higher reaches are capped here."
  @spec max_space() :: 10
  def max_space, do: @max_space

  @doc """
  The Witch's hump bonus for a chip placed on a ruby space: by value, hawkmoth as 2,
  ghost's breath as 3, locoweed as 4. ⚠️ The orange 6-chip has none (`nil`).

      iex> Quacks.Rules.Alchemists.hump_bonus({:black, 1})
      {:dice, 1}
  """
  @spec hump_bonus(Chips.chip()) :: term_ | nil
  def hump_bonus({:black, _}), do: hump(2)
  def hump_bonus({:purple, _}), do: hump(3)
  def hump_bonus({:locoweed, _}), do: hump(4)
  def hump_bonus({_colour, value}), do: hump(value)

  defp hump(1), do: {:rubies, 1}
  defp hump(2), do: {:dice, 1}
  defp hump(3), do: {:chip, {:yellow, 1}}
  defp hump(4), do: {:vp, 3}
  defp hump(_), do: nil

  @doc """
  Draw 3 different patients, with a jump of the game's `rng` (other jumps than the
  Fortune Teller deck and the witches), so the game's own stream stays the same.
  """
  @spec deal(:rand.state()) :: [id]
  def deal(rng) do
    rng = rng |> :rand.jump() |> :rand.jump() |> :rand.jump()

    {keyed, _rng} =
      Enum.map_reduce(@patients, rng, fn id, rng ->
        {u, rng} = :rand.uniform_s(rng)
        {{u, id}, rng}
      end)

    keyed |> Enum.sort() |> Enum.take(3) |> Enum.map(&elem(&1, 1))
  end
end
