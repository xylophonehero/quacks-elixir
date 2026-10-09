defmodule Quacks.Player do
  @moduledoc """
  One seat at the table: the bag, the pot, the resources and the player's own state
  inside the potions phase. `Quacks.Game` keeps one per seat in `players`.

  `rat_stone` is how far the rat stone moved past the droplet at round start;
  `rat_end` is its space once the round's first chip is in the pot (nil before), so
  a later droplet move does not move it.

  `phase` is the player's own state while the game is in `:potions` or `:shopping`,
  and marks the seats that still answer in the concurrent choice phases
  (`:fortune_choice`, `:chip_choice`, `:witch_choice`).
  `:stopped` is a soft stop: the player waits and may `:resume` while another player
  still brews (not in round 9). `done?` is true once the stop is final or the
  explosion is resolved this round (`phase == :done`). In `:shopping` the phase is
  `:shop` (buy once, rubies, `:end_round`) → `:ready`; `bought?` is true once the
  seat bought (or bought nothing).
  Round 9 "Stir!" (2+ players): `pending_choice` holds the seat's `:draw` or `:stop`
  for the next step while it waits (`:waiting_stir`) for the other brewing seats.
  `explosion_choice` remembers `:vp` or `:buy` until the evaluation runs (`:witch`:
  the silver witch S4 took the penalty away).
  `fortune_used?` is true once a once-per-round card power (B3, B10) is used.
  `pending` holds a blue offer, a Safety Procedure offer (B7) or a Flea Market draw
  (P13): chips out of the bag until the player chooses. `mods` holds the round
  modifiers of the Set 2–4 chips (see `t:mods/0`).

  `aside` holds red Set 2 chips beside the pot: drawn, not in the bag, kept across
  rounds until placed or returned. `chip_choices` holds what the player may still
  choose in the evaluation's chip-action step (G2, G4, P2, P4; see `t:chip_choice/0`).

  Reverse pot side (house rule `pot_side: :back`): `tube` is the test-tube droplet
  (glass 0..12, `Quacks.Rules.TestTubes`), and `droplet_moves` counts the droplet
  moves that wait for the player's choice (pot droplet or test tube). While it is
  above 0, `Quacks.Game.phase/2` is `:droplet_choice`.

  `bowl` is the overflow bowl (The Herb Witches): chips drawn after a chip sits on the
  last space (53), newest first. They have no action and are not in the pot, but white
  bowl chips count toward the explosion. They go back in the bag at the end of the round.

  The Alchemists (`Quacks.Game.Essence`): `patient` is the seat's patient (nil until
  chosen), `essence` the essence marker (0..10; set in the essence phase, spent by
  patient actions in the next preparation phase, back to 0 at the next essence phase),
  `display` the Nervousness chips laid out (out of the bag, back at round end) and
  `essence_pending` what the seat's essence waits for (`t:essence_pending/0`).
  """

  alias Quacks.Rules.{Chips, PotTrack}

  defstruct bag: [],
            drawn: [],
            pending: [],
            pot_index: 0,
            droplet: 0,
            tube: 0,
            droplet_moves: 0,
            flask: true,
            rubies: 1,
            coins: 0,
            vp: 0,
            exploded?: false,
            explosion_choice: nil,
            rat_stone: 0,
            rat_end: nil,
            phase: :potions,
            done?: false,
            fortune_used?: false,
            aside: [],
            chip_choices: [],
            bowl: [],
            pennies: %{},
            witch_offer: [],
            ruby_price: 2,
            starters: [],
            pending_choice: nil,
            bought?: false,
            patient: nil,
            essence: 0,
            essence_pending: nil,
            display: [],
            mods: %{explode_above: 0, next_chip_x2: false, white1_plus1: false, protect: 0}

  @type phase ::
          :potions
          | :yellow_choice
          | :blue_choice
          | :explosion_choice
          | :fortune_choice
          | :red_choice
          | :chip_choice
          | :witch_choice
          | :waiting_stir
          | :essence_offer
          | :essence_choice
          | :essence_bonus
          | :ear_worm
          | :stopped
          | :done
          | :shop
          | :ready
  @typedoc "A chip in the pot and the 0..53 space it sits on."
  @type placed :: {Chips.chip(), 0..53}
  @type t :: %__MODULE__{
          bag: [Chips.chip()],
          drawn: [placed],
          pending: [Chips.chip()],
          pot_index: 0..53,
          droplet: non_neg_integer,
          tube: 0..12,
          droplet_moves: non_neg_integer,
          flask: boolean,
          rubies: non_neg_integer,
          coins: non_neg_integer,
          vp: non_neg_integer,
          exploded?: boolean,
          explosion_choice: nil | :vp | :buy | :witch,
          rat_stone: non_neg_integer,
          rat_end: non_neg_integer | nil,
          phase: phase,
          done?: boolean,
          fortune_used?: boolean,
          aside: [Chips.chip()],
          chip_choices: [chip_choice],
          bowl: [Chips.chip()],
          pennies: %{optional(Quacks.Rules.Witches.colour()) => boolean},
          witch_offer: [Chips.chip()],
          ruby_price: 1 | 2,
          starters: [Chips.chip()],
          pending_choice: nil | :draw | :stop,
          bought?: boolean,
          patient: nil | Quacks.Rules.Alchemists.id(),
          essence: 0..10,
          essence_pending: essence_pending,
          display: [Chips.chip()],
          mods: mods
        }
  @typedoc """
  One step-B choice still open: a G2 green chip of value 1/2/4 (`{:gain, value}`),
  up to `n` rubies for G4 (`{:ruby_move, n}`), a P2 trade up to `tier`
  (`{:purple_trade, tier}`), a P4 swap up to `tier` (`{:upgrade, tier}`), a G5
  starter chip worth up to `value` (`{:starter, value}`) or a P5 purchase with
  `coins` (`{:purple_buy, coins}`). During the potions phase (player phase
  `:chip_choice`) it holds Y6's offer `:yellow_ruby` or locoweed 5's `{:return, chip}`
  (one per coloured chip in the pot).
  """
  @type chip_choice ::
          {:gain, 1 | 2 | 4}
          | {:starter, 1 | 2 | 4}
          | {:purple_buy, pos_integer}
          | :yellow_ruby
          | {:return, Chips.chip()}
          | {:ruby_move, 1..2}
          | {:purple_trade, 1..3}
          | {:upgrade, 1..3}
  @typedoc """
  What the seat's essence waits for (The Alchemists). Essence phase: `{:space, reach}`
  while it picks a space (`:essence_choice`), `{:ear_worm, draws_left}`, `{:swap, 1, 2
  | 4}` or `{:buy, coins}` (a glass's bonus). Preparation phase: `{:offers, offers}`,
  the patient offers after draws, oldest first (`{:carrot | :wing | :wing_bowl | :hump,
  chip}`; the first is open in `:essence_offer`).
  """
  @type essence_pending ::
          nil
          | {:space, 0..10}
          | {:ear_worm, non_neg_integer}
          | {:swap, 1, 2 | 4}
          | {:buy, pos_integer}
          | {:offers, [{:carrot | :wing | :wing_bowl | :hump, Chips.chip()}]}
  @typedoc """
  Round modifiers from Set 2–4 chips, reset at the end of the round: the white limit
  raised by Y3 (0 = not raised), the next chip moves double (Y2), white 1-chips move 2 (R4), and how many more
  drawn chips the crow skull protects (B2).
  """
  @type mods :: %{
          explode_above: 0 | 8 | 9,
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

  @doc "Sum of white chip values in the pot and the overflow bowl this round."
  @spec white_sum(t) :: non_neg_integer
  def white_sum(%__MODULE__{drawn: drawn, bowl: bowl}) do
    pot = for({{:white, v}, _index} <- drawn, reduce: 0, do: (acc -> acc + v))
    for({:white, v} <- bowl, reduce: pot, do: (acc -> acc + v))
  end

  @doc "The chips in the pot without their positions, newest first."
  @spec pot_chips(t) :: [Chips.chip()]
  def pot_chips(%__MODULE__{drawn: drawn}), do: Enum.map(drawn, fn {chip, _index} -> chip end)

  @doc "The scoring space: directly after the last placed chip, clamped to the spoon."
  @spec scoring_index(t) :: 0..53
  def scoring_index(%__MODULE__{pot_index: i}), do: min(i + 1, PotTrack.last())

  @doc """
  End of round: the pot (and the Nervousness display) goes back in the bag, the round
  state clears (step F). `aside`, `pennies`, `starters`, `tube`, `droplet_moves`,
  `patient` and the `essence` marker stay.
  """
  @spec reset(t) :: t
  def reset(%__MODULE__{} = p) do
    %{
      p
      | bag: pot_chips(p) ++ p.bowl ++ p.display ++ p.bag,
        display: [],
        essence_pending: nil,
        drawn: [],
        bowl: [],
        pending: [],
        coins: 0,
        exploded?: false,
        explosion_choice: nil,
        rat_stone: 0,
        rat_end: nil,
        pot_index: p.droplet,
        witch_offer: [],
        ruby_price: 2,
        phase: :potions,
        done?: false,
        fortune_used?: false,
        chip_choices: [],
        pending_choice: nil,
        bought?: false,
        mods: %__MODULE__{}.mods
    }
  end
end
