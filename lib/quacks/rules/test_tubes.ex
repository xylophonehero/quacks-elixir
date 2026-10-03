defmodule Quacks.Rules.TestTubes do
  @moduledoc """
  The test-tube track on the reverse side of the pot (house rule `pot_side: :back`,
  `docs/research/pot-reverse-and-faq.md` §1.2): 13 glasses, 0..12. The second droplet
  starts on glass 0 (no bonus); each move goes 1 glass right and pays that glass's
  bonus at once. ⚠️ Read from the rulebook image; glass 12 is the end of the track.
  """

  @typedoc "A glass bonus: 1 ruby, victory points, or a chip that goes into the bag."
  @type bonus :: :ruby | {:vp, 1..4} | {:chip, Quacks.Rules.Chips.chip()}

  @glasses {nil, :ruby, {:vp, 1}, {:chip, {:blue, 1}}, {:vp, 2}, {:chip, {:black, 1}}, {:vp, 2},
            {:chip, {:red, 2}}, {:vp, 3}, {:chip, {:purple, 1}}, {:vp, 3}, {:chip, {:yellow, 4}},
            {:vp, 4}}

  @doc "The last glass (12): the test-tube droplet cannot move past it."
  @spec last() :: 12
  def last, do: tuple_size(@glasses) - 1

  @doc """
  The bonus of `glass` (1..12); glass 0 is the start and has none.

      iex> Quacks.Rules.TestTubes.bonus(3)
      {:chip, {:blue, 1}}
  """
  @spec bonus(0..12) :: bonus | nil
  def bonus(glass), do: elem(@glasses, glass)
end
