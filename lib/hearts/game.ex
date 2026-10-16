defmodule Hearts.Game do
  @moduledoc """
  The Hearts engine: pure functions over a `%Hearts.Game{}` struct.

  Rules: `docs/games/hearts/rulebook.md` (the § numbers below refer to it).
  Glossary: `docs/games/hearts/CONTEXT.md`.

  The API follows the draft `Table.Game` contract (#78):

  - `new(opts, seed)` makes a game and deals the first hand.
  - `legal_actions(game, seat)` lists the actions of a seat.
  - `apply(game, seat, action)` returns `{:ok, game} | {:error, reason}`.
  - `status(game)` is `{:playing, seats_to_act} | {:over, scores}`.
  - `view(game, seat | :spectator)` is what one seat may see.

  Randomness (the shuffle) uses only the `:rand` state in `game.rng`, so a seed gives
  the same game every time.

      iex> {:ok, game} = Hearts.Game.new(%{}, {1, 2, 3})
      iex> Hearts.Game.status(game)
      {:playing, [0, 1, 2, 3]}
      iex> length(game.hands[0])
      13
  """

  alias Table.Kit.{Deck, PlayingCards, Rng}

  @queen {12, :spades}
  @jack {11, :diamonds}
  @suit_order [:clubs, :diamonds, :spades, :hearts]

  @defaults %{
    players: 4,
    no_points_first_trick: true,
    queen_breaks_hearts: false,
    moon: :add_to_others,
    jack_of_diamonds: false,
    target: 100,
    ties: :share
  }

  @type seat :: non_neg_integer()
  @type card :: PlayingCards.card()
  @type direction :: :left | :right | :across | :none
  @type action :: {:pass, [card]} | {:play, card}
  @type phase :: :passing | :playing | :over

  @typedoc """
  One entry of `game.log` (newest first). The UI animates from these.

  - `{:deal, hand_no, direction, %{seat => [card]}}`: a new hand is dealt.
  - `{:pass_chosen, seat}`: a seat has chosen its 3 cards (the cards stay secret).
  - `{:pass, direction, %{from_seat => {to_seat, [card]}}}`: all passes move together.
  - `{:play, seat, card}`: a card goes to the trick.
  - `{:hearts_broken, seat}`: the first heart (or Q♠ with `queen_breaks_hearts`) of the hand.
  - `{:trick_won, seat, [card], points}`: the trick goes to the winner (cards in play order).
  - `{:hand_scored, %{hand: n, points: %{seat => int}, moon: seat | nil, totals: %{seat => int}}}`
  - `{:game_over, winners, totals}`
  """
  @type event :: tuple()

  @type t :: %__MODULE__{
          options: map(),
          seed: {integer, integer, integer},
          rng: :rand.state(),
          seats: [seat],
          hand_no: non_neg_integer(),
          phase: phase,
          hands: %{seat => [card]},
          passes: %{seat => [card]},
          trick: [{seat, card}],
          leader: seat | nil,
          turn: seat | nil,
          tricks: non_neg_integer(),
          taken: %{seat => [card]},
          hearts_broken: boolean(),
          scores: %{seat => integer},
          winners: [seat],
          log: [event]
        }

  defstruct [
    :options,
    :seed,
    :rng,
    :leader,
    :turn,
    seats: [],
    hand_no: 0,
    phase: :passing,
    hands: %{},
    passes: %{},
    trick: [],
    tricks: 0,
    taken: %{},
    hearts_broken: false,
    scores: %{},
    winners: [],
    log: []
  ]

  @doc "The default options (rulebook §6)."
  @spec defaults() :: map()
  def defaults, do: @defaults

  @doc """
  A new game with the first hand dealt. `opts` is a map or keyword list of the
  options in `defaults/0`; `seed` is a `{int, int, int}` tuple.
  """
  @spec new(map() | keyword(), {integer, integer, integer}) :: {:ok, t} | {:error, term}
  def new(opts \\ %{}, seed)

  def new(opts, seed) when is_list(opts), do: new(Map.new(opts), seed)

  def new(opts, {a, b, c} = seed)
      when is_map(opts) and is_integer(a) and is_integer(b) and is_integer(c) do
    with {:ok, options} <- validate(opts) do
      seats = Enum.to_list(0..(options.players - 1))

      game = %__MODULE__{
        options: options,
        seed: seed,
        rng: Rng.seed(seed),
        seats: seats,
        scores: Map.new(seats, &{&1, 0})
      }

      {:ok, deal(game)}
    end
  end

  def new(_opts, seed), do: {:error, {:invalid_seed, seed}}

  defp validate(opts) do
    Enum.reduce_while(opts, {:ok, @defaults}, fn {key, value}, {:ok, acc} ->
      cond do
        not Map.has_key?(@defaults, key) -> {:halt, {:error, {:unknown_option, key}}}
        valid_option?(key, value) -> {:cont, {:ok, Map.put(acc, key, value)}}
        true -> {:halt, {:error, {:invalid_option, key, value}}}
      end
    end)
  end

  defp valid_option?(:players, n), do: n in [3, 4, 5]
  defp valid_option?(:moon, v), do: v in [:add_to_others, :subtract]
  defp valid_option?(:ties, v), do: v in [:share, :play_on]
  defp valid_option?(:target, v), do: is_integer(v) and v > 0
  defp valid_option?(_key, v), do: is_boolean(v)

  # -- Rules data -------------------------------------------------------------

  @doc "The deck for `players` seats (§1.3)."
  @spec deck(3..5) :: [card]
  def deck(3), do: PlayingCards.deck() -- [{2, :diamonds}]
  def deck(4), do: PlayingCards.deck()
  def deck(5), do: PlayingCards.deck() -- [{2, :clubs}, {2, :diamonds}]

  @doc """
  Sorts a hand for display: clubs, diamonds, spades, hearts, then by rank.

      iex> Hearts.Game.sort_hand([{14, :hearts}, {3, :clubs}, {12, :spades}])
      [{3, :clubs}, {12, :spades}, {14, :hearts}]
  """
  @spec sort_hand([card]) :: [card]
  def sort_hand(cards), do: PlayingCards.sort(cards, suits: @suit_order)

  @doc "The card that leads the first trick (§3.1)."
  @spec first_lead(t) :: card
  def first_lead(%__MODULE__{options: %{players: 5}}), do: {3, :clubs}
  def first_lead(%__MODULE__{}), do: {2, :clubs}

  @doc "The pass direction of the current hand (§2.2, §2.3)."
  @spec pass_direction(t) :: direction
  def pass_direction(%__MODULE__{options: %{players: n}, hand_no: hand_no}) do
    cycle = if n == 4, do: [:left, :right, :across, :none], else: [:left, :right, :none]
    Enum.at(cycle, rem(hand_no - 1, length(cycle)))
  end

  @doc "The seat that gets the cards of `seat` (§1.4, §2.2)."
  @spec pass_target(seat, direction, pos_integer) :: seat
  def pass_target(seat, :left, n), do: rem(seat + 1, n)
  def pass_target(seat, :right, n), do: rem(seat - 1 + n, n)
  def pass_target(seat, :across, n), do: rem(seat + 2, n)

  @doc """
  The points of some cards (§4.1, §4.3): 1 per heart, 13 for the Q♠, and −10 for the
  J♦ when `jack_of_diamonds` is on.
  """
  @spec points([card], map()) :: integer
  def points(cards, options \\ @defaults) do
    Enum.reduce(cards, 0, fn card, sum -> sum + card_points(card, options) end)
  end

  defp card_points({_, :hearts}, _), do: 1
  defp card_points(@queen, _), do: 13
  defp card_points(@jack, %{jack_of_diamonds: true}), do: -10
  defp card_points(_, _), do: 0

  defp penalty?(card), do: card == @queen or suit(card) == :hearts

  defp suit({_rank, suit}), do: suit

  # -- Queries ----------------------------------------------------------------

  @doc """
  `{:playing, seats}` with the seats that can act now, or `{:over, scores}`.
  While passing, every seat that has not chosen its cards can act.
  """
  @spec status(t) :: {:playing, [seat]} | {:over, %{seat => integer}}
  def status(%__MODULE__{phase: :over, scores: scores}), do: {:over, scores}

  def status(%__MODULE__{phase: :passing} = game),
    do: {:playing, Enum.reject(game.seats, &Map.has_key?(game.passes, &1))}

  def status(%__MODULE__{phase: :playing, turn: turn}), do: {:playing, [turn]}

  @doc "True when the game has ended."
  @spec over?(t) :: boolean
  def over?(%__MODULE__{phase: phase}), do: phase == :over

  @doc """
  The actions `seat` can take now: `{:pass, [c1, c2, c3]}` (each set of 3 cards from
  the hand, sorted) while passing, `{:play, card}` on its turn, else `[]`.
  """
  @spec legal_actions(t, seat | :spectator) :: [action]
  def legal_actions(%__MODULE__{phase: :passing} = game, seat) do
    if seat in game.seats and not Map.has_key?(game.passes, seat),
      do: game.hands[seat] |> combinations(3) |> Enum.map(&{:pass, &1}),
      else: []
  end

  def legal_actions(%__MODULE__{phase: :playing, turn: seat} = game, seat),
    do: game |> legal_cards(seat) |> Enum.map(&{:play, &1})

  def legal_actions(%__MODULE__{}, _seat), do: []

  defp combinations(_, 0), do: [[]]
  defp combinations([], _), do: []

  defp combinations([x | rest], k),
    do: Enum.map(combinations(rest, k - 1), &[x | &1]) ++ combinations(rest, k)

  @doc "The cards `seat` may play to the current trick (§3.1–§3.5)."
  @spec legal_cards(t, seat) :: [card]
  def legal_cards(%__MODULE__{} = game, seat) do
    hand = Map.get(game.hands, seat, [])

    case game.trick do
      [] -> lead_cards(game, hand)
      [{_, {_, led}} | _] -> follow_cards(game, hand, led)
    end
  end

  defp lead_cards(%__MODULE__{tricks: 0} = game, _hand), do: [first_lead(game)]
  defp lead_cards(%__MODULE__{hearts_broken: true}, hand), do: hand

  defp lead_cards(_game, hand) do
    case Enum.reject(hand, &(suit(&1) == :hearts)) do
      [] -> hand
      others -> others
    end
  end

  defp follow_cards(game, hand, led) do
    if Enum.any?(hand, &(suit(&1) == led)),
      do: PlayingCards.playable(hand, led),
      else: discards(game, hand)
  end

  defp discards(%__MODULE__{tricks: 0, options: %{no_points_first_trick: true}}, hand) do
    case Enum.reject(hand, &penalty?/1) do
      [] -> hand
      safe -> safe
    end
  end

  defp discards(_game, hand), do: hand

  @doc """
  What `seat` may see (or `:spectator`): its own hand and pass, the size of the other
  hands, the public table and the log with the other hands and passes hidden.
  """
  @spec view(t, seat | :spectator) :: map()
  def view(%__MODULE__{} = game, viewer) do
    %{
      viewer: viewer,
      phase: game.phase,
      options: game.options,
      seats: game.seats,
      hand_no: game.hand_no,
      pass_direction: pass_direction(game),
      hand: Map.get(game.hands, viewer),
      hand_sizes: Map.new(game.hands, fn {seat, cards} -> {seat, length(cards)} end),
      pass: Map.get(game.passes, viewer),
      passed: game.passes |> Map.keys() |> Enum.sort(),
      trick: game.trick,
      leader: game.leader,
      turn: game.turn,
      tricks: game.tricks,
      hearts_broken: game.hearts_broken,
      taken: game.taken,
      points_taken:
        Map.new(game.taken, fn {seat, cards} -> {seat, points(cards, game.options)} end),
      scores: game.scores,
      winners: game.winners,
      legal_actions: legal_actions(game, viewer),
      log: Enum.map(game.log, &redact(&1, viewer))
    }
  end

  defp redact({:deal, n, dir, hands}, viewer),
    do: {:deal, n, dir, Map.new(hands, fn {s, cards} -> {s, hidden(cards, s == viewer)} end)}

  defp redact({:pass, dir, moves}, viewer) do
    {:pass, dir,
     Map.new(moves, fn {from, {to, cards}} ->
       {from, {to, hidden(cards, viewer in [from, to])}}
     end)}
  end

  defp redact(event, _viewer), do: event

  defp hidden(cards, true), do: cards
  defp hidden(cards, false), do: length(cards)

  # -- Actions ----------------------------------------------------------------

  @doc """
  Applies `action` for `seat`. Returns `{:ok, game}` or `{:error, reason}`; on an
  error nothing changes.
  """
  @spec apply(t, seat, action) :: {:ok, t} | {:error, term}
  def apply(%__MODULE__{phase: :over}, _seat, _action), do: {:error, :game_over}

  def apply(%__MODULE__{} = game, seat, action) do
    if seat in game.seats, do: do_apply(game, seat, action), else: {:error, :unknown_seat}
  end

  defp do_apply(%__MODULE__{phase: :passing} = game, seat, {:pass, cards}) when is_list(cards) do
    cond do
      Map.has_key?(game.passes, seat) -> {:error, :already_passed}
      not valid_pass?(cards, game.hands[seat]) -> {:error, :invalid_pass}
      true -> {:ok, choose_pass(game, seat, sort_hand(cards))}
    end
  end

  defp do_apply(%__MODULE__{phase: :playing} = game, seat, {:play, card}) do
    cond do
      game.turn != seat -> {:error, :not_your_turn}
      card not in game.hands[seat] -> {:error, :not_in_hand}
      card in legal_cards(game, seat) -> {:ok, play(game, seat, card)}
      true -> {:error, play_error(game, seat, card)}
    end
  end

  defp do_apply(_game, _seat, _action), do: {:error, :invalid_action}

  defp valid_pass?(cards, hand) do
    length(cards) == 3 and length(Enum.uniq(cards)) == 3 and Enum.all?(cards, &(&1 in hand))
  end

  defp play_error(%__MODULE__{trick: [], tricks: 0}, _seat, _card), do: :must_lead_first_club
  defp play_error(%__MODULE__{trick: []}, _seat, _card), do: :hearts_not_broken

  defp play_error(%__MODULE__{trick: [{_, {_, led}} | _]} = game, seat, _card) do
    if Enum.any?(game.hands[seat], &(suit(&1) == led)),
      do: :must_follow_suit,
      else: :no_points_first_trick
  end

  # -- Dealing and passing ------------------------------------------------------

  defp deal(%__MODULE__{seats: seats} = game) do
    n = length(seats)
    cards = deck(n)
    {deck, rng} = cards |> Deck.new() |> Deck.shuffle(game.rng)
    {hands, _empty} = Deck.deal(deck, seats, div(length(cards), n))
    hands = Map.new(hands, fn {seat, cs} -> {seat, sort_hand(cs)} end)

    game = %{
      game
      | hand_no: game.hand_no + 1,
        rng: rng,
        hands: hands,
        passes: %{},
        trick: [],
        tricks: 0,
        taken: Map.new(seats, &{&1, []}),
        hearts_broken: false,
        phase: :passing,
        leader: nil,
        turn: nil
    }

    direction = pass_direction(game)
    game = log(game, {:deal, game.hand_no, direction, hands})

    if direction == :none, do: start_play(game), else: game
  end

  defp choose_pass(game, seat, cards) do
    game = %{game | passes: Map.put(game.passes, seat, cards)} |> log({:pass_chosen, seat})

    if map_size(game.passes) == length(game.seats), do: execute_pass(game), else: game
  end

  defp execute_pass(%__MODULE__{seats: seats, passes: passes} = game) do
    direction = pass_direction(game)
    n = length(seats)

    moves =
      Map.new(passes, fn {from, cards} -> {from, {pass_target(from, direction, n), cards}} end)

    received =
      Enum.reduce(moves, %{}, fn {_from, {to, cards}}, acc -> Map.put(acc, to, cards) end)

    hands =
      Map.new(game.hands, fn {seat, hand} ->
        {seat, sort_hand((hand -- passes[seat]) ++ received[seat])}
      end)

    %{game | hands: hands, passes: %{}}
    |> log({:pass, direction, moves})
    |> start_play()
  end

  defp start_play(game) do
    lead = first_lead(game)
    {leader, _} = Enum.find(game.hands, fn {_, hand} -> lead in hand end)
    %{game | phase: :playing, leader: leader, turn: leader}
  end

  # -- Play -----------------------------------------------------------------------

  defp play(%__MODULE__{} = game, seat, card) do
    breaks? =
      not game.hearts_broken and
        (suit(card) == :hearts or
           (card == @queen and game.options.queen_breaks_hearts))

    game =
      %{
        game
        | hands: Map.update!(game.hands, seat, &List.delete(&1, card)),
          trick: game.trick ++ [{seat, card}],
          hearts_broken: game.hearts_broken or breaks?
      }
      |> log({:play, seat, card})
      |> then(&if(breaks?, do: log(&1, {:hearts_broken, seat}), else: &1))

    if length(game.trick) == length(game.seats),
      do: finish_trick(game),
      else: %{game | turn: next_seat(game, seat)}
  end

  defp next_seat(game, seat), do: rem(seat + 1, length(game.seats))

  defp finish_trick(%__MODULE__{trick: trick} = game) do
    cards = Enum.map(trick, &elem(&1, 1))
    {winner, _card} = PlayingCards.trick_winner(trick)

    game =
      %{
        game
        | taken: Map.update!(game.taken, winner, &(cards ++ &1)),
          tricks: game.tricks + 1,
          trick: [],
          leader: winner,
          turn: winner
      }
      |> log({:trick_won, winner, cards, points(cards, game.options)})

    if Enum.all?(game.hands, fn {_, hand} -> hand == [] end), do: score_hand(game), else: game
  end

  # -- Scoring --------------------------------------------------------------------

  @doc """
  The points of each seat for the hand that just ended, and the moon shooter
  (§4.1–§4.3). `taken` maps each seat to the cards that it won.
  """
  @spec hand_points(%{seat => [card]}, map()) :: {%{seat => integer}, seat | nil}
  def hand_points(taken, options) do
    base =
      Map.new(taken, fn {seat, cards} ->
        {seat, points(cards, %{options | jack_of_diamonds: false})}
      end)

    moon = Enum.find(Map.keys(base), &(base[&1] == 26))

    points =
      base
      |> moon_points(moon, options.moon)
      |> jack_points(taken, options.jack_of_diamonds)

    {points, moon}
  end

  defp moon_points(base, nil, _), do: base

  defp moon_points(base, moon, :add_to_others),
    do: Map.new(base, fn {seat, _} -> {seat, if(seat == moon, do: 0, else: 26)} end)

  defp moon_points(base, moon, :subtract),
    do: Map.new(base, fn {seat, _} -> {seat, if(seat == moon, do: -26, else: 0)} end)

  defp jack_points(points, _taken, false), do: points

  defp jack_points(points, taken, true) do
    case Enum.find(taken, fn {_, cards} -> @jack in cards end) do
      {seat, _} -> Map.update!(points, seat, &(&1 - 10))
      nil -> points
    end
  end

  defp score_hand(%__MODULE__{} = game) do
    {points, moon} = hand_points(game.taken, game.options)
    totals = Map.merge(game.scores, points, fn _, a, b -> a + b end)

    game =
      %{game | scores: totals}
      |> log({:hand_scored, %{hand: game.hand_no, points: points, moon: moon, totals: totals}})

    case game_winners(totals, game.options) do
      nil ->
        deal(game)

      winners ->
        %{game | phase: :over, winners: winners, turn: nil} |> log({:game_over, winners, totals})
    end
  end

  @doc """
  The winners when the game ends with these totals (§5.1, §5.2), or `nil` when it goes on.

      iex> Hearts.Game.game_winners(%{0 => 100, 1 => 40, 2 => 60, 3 => 40}, Hearts.Game.defaults())
      [1, 3]
      iex> Hearts.Game.game_winners(%{0 => 99, 1 => 40, 2 => 60, 3 => 40}, Hearts.Game.defaults())
      nil
  """
  @spec game_winners(%{seat => integer}, map()) :: [seat] | nil
  def game_winners(totals, options) do
    low = totals |> Map.values() |> Enum.min()
    winners = for {seat, score} <- Enum.sort(totals), score == low, do: seat

    cond do
      Enum.all?(totals, fn {_, score} -> score < options.target end) -> nil
      options.ties == :play_on and length(winners) > 1 -> nil
      true -> winners
    end
  end

  defp log(game, event), do: %{game | log: [event | game.log]}
end
