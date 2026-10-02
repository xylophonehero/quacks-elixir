defmodule Quacks.Player do
  @moduledoc """
  One seat at the table: the bag, the pot, the resources and the player's own state
  inside the potions phase. `Quacks.Game` keeps one per seat in `players`.

  `phase` is the player's own state while the game is in `:potions`; `done?` is true
  once the player has stopped or resolved an explosion this round (`phase == :done`).
  `explosion_choice` remembers `:vp` or `:buy` until the evaluation runs.
  `fortune_used?` is true once a once-per-round card power (B3, B10) is used.
  `pending` holds a blue offer, a Safety Procedure offer (B7) or a Flea Market draw
  (P13): chips out of the bag until the player chooses. `mods` holds the round
  modifiers of the Set 2–4 chips (see `t:mods/0`).

  `aside` holds red Set 2 chips beside the pot: drawn, not in the bag, kept across
  rounds until placed or returned. `chip_choices` holds what the player may still
  choose in the evaluation's chip-action step (G2, G4, P2, P4; see `t:chip_choice/0`).
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
            fortune_used?: false,
            aside: [],
            chip_choices: [],
            mods: %{explode_above: 7, next_chip_x2: false, white1_plus1: false, protect: 0}

  @type phase ::
          :potions
          | :yellow_choice
          | :blue_choice
          | :explosion_choice
          | :fortune_choice
          | :red_choice
          | :done
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
          fortune_used?: boolean,
          aside: [Chips.chip()],
          chip_choices: [chip_choice],
          mods: mods
        }
  @typedoc """
  One step-B choice still open: a G2 green chip of value 1/2/4 (`{:gain, value}`),
  up to `n` rubies for G4 (`{:ruby_move, n}`), a P2 trade up to `tier`
  (`{:purple_trade, tier}`) or a P4 swap up to `tier` (`{:upgrade, tier}`).
  """
  @type chip_choice ::
          {:gain, 1 | 2 | 4}
          | {:ruby_move, 1..2}
          | {:purple_trade, 1..3}
          | {:upgrade, 1..3}
  @typedoc """
  Round modifiers from Set 2–4 chips, reset at the end of the round: the white limit
  (Y3), the next chip moves double (Y2), white 1-chips move 2 (R4), and how many more
  drawn chips the crow skull protects (B2).
  """
  @type mods :: %{
          explode_above: 7..9,
          next_chip_x2: boolean,
          white1_plus1: boolean,
          protect: non_neg_integer
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

  @doc "End of round: the pot goes back in the bag, the round state clears (step F). `aside` stays."
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
        fortune_used?: false,
        chip_choices: [],
        mods: %__MODULE__{}.mods
    }
  end
end
