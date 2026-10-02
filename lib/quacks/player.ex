defmodule Quacks.Player do
  @moduledoc """
  One seat at the table: the bag, the pot, the resources and the player's own state
  inside the potions phase. `Quacks.Game` keeps one per seat in `players`.

  `phase` is the player's own state while the game is in `:potions`; `done?` is true
  once the player has stopped or resolved an explosion this round (`phase == :done`).
  `explosion_choice` remembers `:vp` or `:buy` until the evaluation runs.
  `fortune_used?` is true once a once-per-round card power (B3, B10) is used.
  `pending` holds a blue offer, a Safety Procedure offer (B7) or a Flea Market draw
  (P13): chips out of the bag until the player chooses.
  """

  alias Quacks.Rules.{Chips, PotTrack}

  defstruct bag: [],
            drawn: [],
            pending: [],
            pot_index: 0,
            droplet: 0,
            flask: true,
            rubies: 1,
            coins: 0,
            vp: 0,
            exploded?: false,
            explosion_choice: nil,
            rat_stone: 0,
            phase: :potions,
            done?: false,
            fortune_used?: false

  @type phase ::
          :potions | :yellow_choice | :blue_choice | :explosion_choice | :fortune_choice | :done
  @typedoc "A chip in the pot and the 0..53 space it sits on."
  @type placed :: {Chips.chip(), 0..53}
  @type t :: %__MODULE__{
          bag: [Chips.chip()],
          drawn: [placed],
          pending: [Chips.chip()],
          pot_index: 0..53,
          droplet: non_neg_integer,
          flask: boolean,
          rubies: non_neg_integer,
          coins: non_neg_integer,
          vp: non_neg_integer,
          exploded?: boolean,
          explosion_choice: nil | :vp | :buy,
          rat_stone: non_neg_integer,
          phase: phase,
          done?: boolean,
          fortune_used?: boolean
        }

  @doc "A player at the start of the game with `bag`."
  @spec new([Chips.chip()]) :: t
  def new(bag), do: %__MODULE__{bag: bag}

  @doc "Where the first chip of the round counts from: the droplet, or the rat stone."
  @spec start_index(t) :: non_neg_integer
  def start_index(%__MODULE__{droplet: droplet, rat_stone: rat_stone}), do: droplet + rat_stone

  @doc "Sum of white chip values in the pot this round."
  @spec white_sum(t) :: non_neg_integer
  def white_sum(%__MODULE__{drawn: drawn}) do
    for({{:white, v}, _index} <- drawn, reduce: 0, do: (acc -> acc + v))
  end

  @doc "The chips in the pot without their positions, newest first."
  @spec pot_chips(t) :: [Chips.chip()]
  def pot_chips(%__MODULE__{drawn: drawn}), do: Enum.map(drawn, fn {chip, _index} -> chip end)

  @doc "The scoring space: directly after the last placed chip, clamped to the spoon."
  @spec scoring_index(t) :: 0..53
  def scoring_index(%__MODULE__{pot_index: i}), do: min(i + 1, PotTrack.last())

  @doc "End of round: the pot goes back in the bag, the round state clears (step F)."
  @spec reset(t) :: t
  def reset(%__MODULE__{} = p) do
    %{
      p
      | bag: pot_chips(p) ++ p.bag,
        drawn: [],
        pending: [],
        coins: 0,
        exploded?: false,
        explosion_choice: nil,
        rat_stone: 0,
        pot_index: p.droplet,
        phase: :potions,
        done?: false,
        fortune_used?: false
    }
  end
end
