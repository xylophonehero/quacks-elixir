defmodule Table.Generic.Oracle do
  @moduledoc """
  The true ops of a real game, for step B: it plays Hearts with `Hearts.Game`
  and writes each step as generic ops on a mirror table (`Table.Generic.Game`
  with `hearts_spec/1`). An LLM referee's ops for the same step can then be
  compared with these (`same_effect?/3`).

  The mirror zones: `deck` (hidden), `hand:<s>` and `pass:<s>` (owner), `trick`
  (public), `taken:<s>` (public). The counters: `score:<s>` and
  `hearts_broken` (0 or 1). `agree?/2` checks that each zone has the same cards
  as the Hearts state (in any order: a hand is sorted in Hearts). A chosen pass
  stays in the Hearts hand until all seats pass; in the mirror it is in `pass:<s>`.

  What does not translate yet (a gap for step B): the pass is a prompt to every
  seat at once, and `pending` has one seat. So the mirror asks only in the
  play phase. A deal is a shuffle and then one `move` per card: the mirror's
  shuffle is not the Hearts shuffle, so the moves name the cards.
  """

  alias Hearts.AI.Random, as: RandomBot
  alias Hearts.Game, as: HeartsGame
  alias Table.Generic.{Game, Spec}

  @type step :: %{seat: non_neg_integer, action: term, ops: [Table.Generic.Ops.t()]}

  @doc "The mirror spec for a Hearts table of `players` seats."
  @spec hearts_spec(3..5) :: map
  def hearts_spec(players) do
    %{
      "name" => "hearts_mirror",
      "title" => "Hearts (mirror)",
      "players" => %{"min" => players, "max" => players},
      "deck" => Enum.map(HeartsGame.deck(players), &Spec.card_id/1),
      "referee" => nil,
      "zones" => [
        %{"id" => "deck", "visibility" => "hidden", "layout" => "pile", "deck" => true},
        %{"id" => "hand", "per_seat" => true, "visibility" => "owner", "layout" => "hand"},
        %{"id" => "pass", "per_seat" => true, "visibility" => "owner", "layout" => "row"},
        %{"id" => "trick", "visibility" => "public", "layout" => "row"},
        %{"id" => "taken", "per_seat" => true, "visibility" => "public", "layout" => "pile"}
      ],
      "counters" => [
        %{"id" => "score", "per_seat" => true, "value" => 0},
        %{"id" => "hearts_broken", "value" => 0}
      ],
      "setup" => []
    }
  end

  @doc """
  A Hearts game from `opts` and `seed`, its mirror, and the ops of the first deal.
  """
  @spec start(map, Table.Kit.Rng.seed()) ::
          {:ok, HeartsGame.t(), Game.t(), [Table.Generic.Ops.t()]} | {:error, term}
  def start(opts, seed) do
    with {:ok, hearts} <- HeartsGame.new(opts, seed),
         players = length(hearts.seats),
         {:ok, mirror} <-
           Game.new(%{spec: hearts_spec(players), players: players, referee: nil}, seed),
         ops = translate(%{hearts | log: []}, hearts),
         {:ok, mirror} <- Game.apply_ops(mirror, ops) do
      {:ok, hearts, mirror, ops}
    end
  end

  @doc """
  One step: `seat` does `action` in Hearts; the ops of the step go to the mirror.
  `{:error, {:mismatch, zones}}` when the mirror does not agree after it.
  """
  @spec step(HeartsGame.t(), Game.t(), non_neg_integer, term) ::
          {:ok, HeartsGame.t(), Game.t(), [Table.Generic.Ops.t()]} | {:error, term}
  def step(hearts, mirror, seat, action) do
    with {:ok, after_} <- HeartsGame.apply(hearts, seat, action),
         ops = action_ops(seat, action) ++ translate(hearts, after_),
         {:ok, mirror} <- Game.apply_ops(mirror, ops),
         [] <- disagree(after_, mirror) do
      {:ok, after_, mirror, ops}
    else
      zones when is_list(zones) -> {:error, {:mismatch, zones}}
      error -> error
    end
  end

  @doc """
  A whole game: every seat plays `Hearts.AI.Random` (own seeds). The trace of
  steps, and the last Hearts state and mirror.
  """
  @spec trace(map, Table.Kit.Rng.seed()) ::
          {:ok, [step], HeartsGame.t(), Game.t()} | {:error, term}
  def trace(opts, {a, b, c} = seed) do
    with {:ok, hearts, mirror, ops} <- start(opts, seed) do
      bots = Map.new(hearts.seats, &{&1, RandomBot.new({a + &1 + 1, b, c})})
      loop(hearts, mirror, bots, [%{seat: nil, action: :start, ops: ops}])
    end
  end

  defp loop(hearts, mirror, bots, steps) do
    case HeartsGame.status(hearts) do
      {:over, _} ->
        {:ok, Enum.reverse(steps), hearts, mirror}

      {:playing, [seat | _]} ->
        {action, bot} = RandomBot.choose(HeartsGame.view(hearts, seat), bots[seat])

        case step(hearts, mirror, seat, action) do
          {:ok, hearts, mirror, ops} ->
            loop(hearts, mirror, %{bots | seat => bot}, [
              %{seat: seat, action: action, ops: ops} | steps
            ])

          error ->
            error
        end
    end
  end

  @doc "True when the mirror's zones and counters agree with the Hearts state."
  @spec agree?(HeartsGame.t(), Game.t()) :: boolean
  def agree?(hearts, mirror), do: disagree(hearts, mirror) == []

  @doc """
  True when `a` and `b` give the same zones (as sets), counters, turn and result
  from `mirror`. Both must apply. Use it to compare a referee's ops with the
  oracle's: the order of cards in a zone and the rng may differ.
  """
  @spec same_effect?(Game.t(), [Table.Generic.Ops.t()], [Table.Generic.Ops.t()]) :: boolean
  def same_effect?(mirror, a, b) do
    with {:ok, ga} <- Game.apply_ops(mirror, a),
         {:ok, gb} <- Game.apply_ops(mirror, b) do
      effect(ga) == effect(gb)
    else
      _ -> false
    end
  end

  defp effect(g) do
    {Map.new(g.zones, fn {id, z} -> {id, Enum.sort(z.items)} end), g.counters, g.turn, g.result}
  end

  # -- the translator ------------------------------------------------------------------

  defp action_ops(seat, {:pass, cards}),
    do: for(c <- cards, do: {:move, Spec.card_id(c), "hand:#{seat}", "pass:#{seat}"})

  defp action_ops(_seat, _action), do: []

  @doc """
  The ops from Hearts state `before` to `after_`, from the new log events (the
  chosen pass cards come from the action: `step/4`). Ends with the phase, the
  turn and, in the play phase, the prompt to the seat to play.
  """
  @spec translate(HeartsGame.t(), HeartsGame.t()) :: [Table.Generic.Ops.t()]
  def translate(before, after_) do
    events = after_.log |> Enum.take(length(after_.log) - length(before.log)) |> Enum.reverse()
    Enum.flat_map(events, &event_ops(&1, after_)) ++ tail(after_)
  end

  defp event_ops({:deal, hand_no, _dir, hands}, game) do
    gather =
      if hand_no > 1,
        do: for(s <- game.seats, do: {:move, :all, "taken:#{s}", "deck"}),
        else: []

    deal =
      for {s, cards} <- Enum.sort(hands),
          c <- cards,
          do: {:move, Spec.card_id(c), "deck", "hand:#{s}"}

    gather ++ [{:set, "hearts_broken", 0}, {:shuffle, "deck"} | deal]
  end

  defp event_ops({:pass, _dir, moves}, _game) do
    for {from, {to, cards}} <- Enum.sort(moves),
        c <- cards,
        do: {:move, Spec.card_id(c), "pass:#{from}", "hand:#{to}"}
  end

  defp event_ops({:play, s, c}, _game), do: [{:move, Spec.card_id(c), "hand:#{s}", "trick"}]
  defp event_ops({:hearts_broken, _s}, _game), do: [{:set, "hearts_broken", 1}]
  defp event_ops({:trick_won, s, _cards, _p}, _game), do: [{:move, :all, "trick", "taken:#{s}"}]

  defp event_ops({:hand_scored, %{totals: totals}}, _game),
    do: for({s, t} <- Enum.sort(totals), do: {:set, "score:#{s}", t})

  defp event_ops({:game_over, _winners, totals}, _game), do: [{:end, totals}]
  defp event_ops({:pass_chosen, _s}, _game), do: []

  defp tail(%{phase: :over}), do: []

  defp tail(%{phase: :passing}), do: [{:phase, "passing"}]

  defp tail(%{phase: :playing, turn: t} = game) do
    cards = for c <- HeartsGame.legal_cards(game, t), do: {:card, "hand:#{t}", Spec.card_id(c)}
    [{:phase, "playing"}, {:turn, t}, {:ask, t, "Play a card", cards}]
  end

  # -- the check -------------------------------------------------------------------------

  defp disagree(hearts, mirror) do
    want =
      Map.new(
        [{"trick", Enum.map(hearts.trick, &elem(&1, 1))}, {"deck", []}] ++
          Enum.flat_map(hearts.seats, fn s ->
            [
              {"hand:#{s}", hearts.hands[s] -- Map.get(hearts.passes, s, [])},
              {"pass:#{s}", Map.get(hearts.passes, s, [])},
              {"taken:#{s}", Map.get(hearts.taken, s, [])}
            ]
          end),
        fn {id, cards} -> {id, cards |> Enum.map(&Spec.card_id/1) |> Enum.sort()} end
      )

    zones = for {id, z} <- mirror.zones, Enum.sort(z.items) != want[id], do: id

    scores =
      for s <- hearts.seats, mirror.counters["score:#{s}"] != hearts.scores[s], do: "score:#{s}"

    broken =
      if mirror.counters["hearts_broken"] == 1 != hearts.hearts_broken,
        do: ["hearts_broken"],
        else: []

    Enum.sort(zones ++ scores ++ broken)
  end
end
