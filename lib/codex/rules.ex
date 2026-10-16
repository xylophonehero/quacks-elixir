defmodule Codex.Rules do
  @moduledoc """
  The rules of Codex (1-hero mode) on a `Codex.Game`: the turn, the actions of
  the active side and the state checks. Source: `docs/research/codex.md`
  (rulebook v46, "S1", and the official rulings). A `# REVIEW:` comment marks a
  reading of an unclear rule.

  ## The turn (S1 p. 6)

  1. Ready: the active side's cards in play are readied; their arrival fatigue
     ends. (P1 has nothing to ready on its first turn.)
  2. Upkeep: 1 gold per worker, at most 20 gold (S1 p. 3).
  3. Main phase: the actions below, in any order.
  4. `:end_turn` ends the main phase: the patrol zone is locked in, the hand is
     discarded and the side draws that many cards + 2, at most 5 (S1 p. 2).
  5. Then the other side's turn starts.

  ## Actions (main phase)

  - `{:hire, card_id}`: hire a worker: pay 1 gold and put a card from the hand
    face down in the workers zone. At most once per turn (S1 p. 3).
  - `:end_turn`.

  `legal/1` lists every legal action of the active side; `act/2` refuses any
  other action.
  """

  alias Codex.{Cards, Zones}
  alias Table.Kit.Rng

  @gold_cap 20
  @hand_cap 5

  # -- legal actions -----------------------------------------------------------------------

  @doc "Every legal rules action of the active side."
  @spec legal(map) :: [term]
  def legal(%{phase: :over}), do: []

  def legal(%{phase: :main, active: s} = game) do
    hires(game, s) ++ [:end_turn]
  end

  defp hires(game, s) do
    side = game.sides[s]
    if side.hired or side.gold < 1, do: [], else: for(id <- side.zones.hand, do: {:hire, id})
  end

  # -- doing an action ----------------------------------------------------------------------

  @doc "Do a rules action, or `{:error, reason}` when it is not legal now."
  @spec act(map, term) :: {:ok, map} | {:error, term}
  def act(game, action) do
    if action in legal(game),
      do: {:ok, do_act(game, action)},
      else: {:error, reason(game, action)}
  end

  defp do_act(game, {:hire, id}) do
    s = game.active

    game
    |> Zones.move(id, {s, :workers})
    |> Zones.update_card(id, &%{&1 | face_down: true})
    |> update_side(s, &%{&1 | gold: &1.gold - 1, hired: true})
  end

  defp do_act(game, :end_turn), do: end_turn(game)

  # Why an action is refused: the first rule that it breaks.
  defp reason(%{phase: :over}, _action), do: :game_over

  defp reason(game, {:hire, id}) do
    side = game.sides[game.active]

    cond do
      side.hired -> :worker_hired
      side.gold < 1 -> :no_gold
      id not in side.zones.hand -> :not_in_hand
      true -> :illegal
    end
  end

  defp reason(_game, _action), do: :illegal

  # -- the turn ------------------------------------------------------------------------------

  @doc "Start the turn of `seat`: ready, upkeep, then its main phase."
  @spec start_turn(map, 0 | 1) :: map
  def start_turn(game, seat) do
    game = %{game | active: seat, phase: :main}

    game
    |> update_side(seat, &%{&1 | turn: &1.turn + 1, hired: false, reshuffled: false})
    |> ready(seat)
    |> upkeep(seat)
  end

  defp ready(game, seat) do
    Enum.reduce(Zones.in_play(game, seat), game, fn id, game ->
      Zones.update_card(game, id, &%{&1 | exhausted: false, fatigued: false, attacked: false})
    end)
  end

  defp upkeep(game, seat) do
    workers = length(game.sides[seat].zones.workers)
    gain_gold(game, seat, workers)
  end

  @doc "Add gold to a side, at most 20 (S1 p. 3)."
  @spec gain_gold(map, 0 | 1, integer) :: map
  def gain_gold(game, seat, n),
    do: update_side(game, seat, &%{&1 | gold: min(&1.gold + n, @gold_cap)})

  # End of the main phase: discard and draw, then the other side's turn.
  defp end_turn(game) do
    s = game.active
    hand = game.sides[s].zones.hand

    game =
      Enum.reduce(hand, game, fn id, game -> Zones.move(game, id, {s, :discard}, 0) end)

    game
    |> draw(s, min(length(hand) + 2, @hand_cap), :draw_phase)
    |> start_turn(1 - s)
  end

  @doc """
  Draw `n` cards for `seat`. When the deck is empty the discard pile is shuffled
  into a new deck. In the main phase (`:main`) that happens at most once; then
  the draws stop (S1 p. 2). `:draw_phase` and `:free` have no such limit.
  """
  @spec draw(map, 0 | 1, non_neg_integer, :main | :draw_phase | :free) :: map
  def draw(game, _seat, 0, _when), do: game

  def draw(game, seat, n, phase),
    do: Enum.reduce(1..n, game, fn _, g -> draw_one(g, seat, phase) end)

  defp draw_one(game, seat, phase) do
    side = game.sides[seat]

    case side.zones do
      %{deck: [top | rest], hand: hand} ->
        game
        |> Zones.put_zone({seat, :deck}, rest)
        |> Zones.put_zone({seat, :hand}, hand ++ [top])

      %{deck: [], discard: []} ->
        game

      %{deck: [], discard: _} when phase == :main and side.reshuffled ->
        game

      %{deck: [], discard: discard} ->
        {deck, rng} = Rng.shuffle(discard, game.rng)

        %{game | rng: rng, log: [{:reshuffle, seat} | game.log]}
        |> Zones.put_zone({seat, :discard}, [])
        |> Zones.put_zone({seat, :deck}, deck)
        |> update_side(seat, &%{&1 | reshuffled: &1.reshuffled or phase == :main})
        |> draw_one(seat, phase)
    end
  end

  # -- state checks ----------------------------------------------------------------------------

  @doc "The state checks after every action: a base at 0 HP ends the game (S1 p. 1)."
  @spec cleanup(map) :: map
  def cleanup(%{phase: :over} = game), do: game

  def cleanup(game) do
    case Enum.find([0, 1], &(game.sides[&1].base_hp <= 0)) do
      nil -> game
      loser -> %{game | phase: :over, winner: 1 - loser}
    end
  end

  @doc "A card that leaves play: no damage, runes, exhaustion or turn state; a hero at level 1."
  @spec reset(map) :: map
  def reset(card) do
    %{
      card
      | damage: 0,
        plus: 0,
        minus: 0,
        exhausted: false,
        fatigued: false,
        attacked: false,
        armor_used: false,
        tmp_atk: 0,
        tmp_hp: 0,
        stealth: false,
        extra: %{},
        level: card.level && 1
    }
  end

  # -- stats -------------------------------------------------------------------------------------

  @doc "ATK/HP now of every unit and hero in play: `%{id => {atk, hp}}`."
  @spec all_stats(map) :: %{pos_integer => {integer, integer}}
  def all_stats(game) do
    for s <- [0, 1],
        id <- Zones.in_play(game, s),
        stats = stats(game, id),
        into: %{},
        do: {id, stats}
  end

  @doc "ATK/HP now of card `id`, or nil for a card with no stats."
  @spec stats(map, pos_integer) :: {integer, integer} | nil
  def stats(game, id) do
    c = game.cards[id]

    {atk, hp} =
      case c.level && Cards.band(c.card, c.level) do
        %{atk: a, hp: h} -> {a, h}
        _ -> {Cards.fetch!(c.card).atk, Cards.fetch!(c.card).hp}
      end

    if is_integer(atk) and is_integer(hp) do
      runes = c.plus - c.minus
      {atk + runes + c.tmp_atk, hp + runes + c.tmp_hp}
    end
  end

  # -- helpers ----------------------------------------------------------------------------------

  @doc false
  def update_side(game, seat, fun), do: update_in(game.sides[seat], fun)
end
