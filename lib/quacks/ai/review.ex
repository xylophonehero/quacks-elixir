defmodule Quacks.AI.Review do
  @moduledoc """
  A review of played games (`mix quacks.review`, `docs/research/learn-from-nick.md`):
  how the human seats play, where they and the tuned bot differ, and the mistakes of
  the bots.

  Every action of a game's log is one step. A step is a **decision** when the seat
  had a choice; its kind is one of:

  - `:draw_stop`: `:draw`, `:stop` or `:use_flask` in the potions phase.
  - `:explosion`: coins or VP after an explosion.
  - `:buy`: the shop's buy (`{:buy, []}` is "buy nothing").
  - `:rubies`: what the rubies buy, or the end of the shop step.
  - `:choice`: a fortune card, book, witch, essence or chip choice.

  For each human decision the review asks the tuned bot (`Quacks.AI.Expert`) what
  it would do in the same state. Draw/stop is valued with `Quacks.AI.Expectimax`
  (the tuned bot's own value scale: coins per round, VP, rubies). The other kinds
  are valued by **rollouts**: each option is played to the end of the game
  `futures` times, every seat played by its bot (a human seat by the tuned bot),
  with the same game rng seeds for every option (common random numbers). The value
  of a future is the seat's final VP minus the best other seat's VP (its VP in a
  solo game). A loss is the mean value of the best option minus that of the chosen
  one; `se` is the standard error of that difference over the futures. The best of
  many noisy options is biased upwards, so a loss counts as a mistake only when it
  is more than 2 `se`.
  """

  alias Quacks.{AI, Game, Player, Session}
  alias Quacks.AI.{Bench, Expectimax, Odds, Profile, Shop}
  alias Table.Kit.Rng

  @choices [
    :fortune_choice,
    :chip_choice,
    :witch_choice,
    :essence_choice,
    :essence_bonus,
    :essence_offer,
    :upgrade,
    :blue_choice,
    :red_choice,
    :yellow_choice,
    :droplet_choice,
    :patient_choice
  ]
  @rollout_kinds [:explosion, :buy, :rubies, :choice]
  @bot_kinds [:draw_stop | @rollout_kinds]

  @doc """
  Review `games` (`Quacks.Archive.load_dir/2`). Options:

  - `human_won:` only games a human seat won (or leads, in a game that did not end).
  - `futures:` rollouts per option (default 16); `max_options:` options per bot
    decision (default 10: the chosen one and the best by the tuned bot's shop
    score or the legal order).
  - `bot_kinds:` the kinds of bot decisions to roll out (default all); `[]` skips
    the bot review.
  - `seed:` (default 1), `jobs:` (default `Quacks.AI.Bench.default_jobs/0`),
    `top:` rows in the top lists (default 15), `profile:` the reference bot
    (default `Profile.get(:expert)`).

  Returns a JSON-ready map; `markdown/1` writes it as text.
  """
  @spec run([Quacks.Archive.game()], keyword) :: map
  def run(games, opts \\ []) do
    ctx = %{
      tuned: Keyword.get_lazy(opts, :profile, fn -> Profile.get(:expert) end),
      futures: Keyword.get(opts, :futures, 16),
      max_options: Keyword.get(opts, :max_options, 10),
      bot_kinds: Keyword.get(opts, :bot_kinds, @bot_kinds),
      seed: Keyword.get(opts, :seed, 1),
      jobs: Keyword.get(opts, :jobs, Bench.default_jobs())
    }

    top = Keyword.get(opts, :top, 15)
    selected = if opts[:human_won], do: Enum.filter(games, &human_won?/1), else: games
    reviewed = Enum.map(selected, &review_game(&1, ctx))
    decisions = Enum.flat_map(reviewed, & &1.decisions)
    {human, bot} = Enum.split_with(decisions, & &1.human?)

    %{
      settings: %{
        human_won: opts[:human_won] == true,
        futures: ctx.futures,
        max_options: ctx.max_options,
        seed: ctx.seed,
        reference: Atom.to_string(ctx.tuned.name)
      },
      games: %{
        loaded: length(games),
        reviewed: length(selected),
        finished: Enum.count(selected, & &1.over?),
        human_decisions: length(human),
        bot_decisions: length(bot),
        list: Enum.map(reviewed, & &1.summary)
      },
      style: style(human, bot, reviewed),
      agreement: agreement(human),
      differences: human |> Enum.filter(&(&1[:loss] && &1.loss > 0)) |> top_by_loss(top),
      bot_mistakes: bot_mistakes(bot, top)
    }
  end

  @doc "True when a human seat leads the standings (the winner of a finished game)."
  @spec human_won?(Quacks.Archive.game()) :: boolean
  def human_won?(%{humans: []}), do: false
  def human_won?(%{humans: humans, session: s}), do: hd(Game.standings(s.game)) in humans

  # -- one game -------------------------------------------------------------------------

  defp review_game(g, ctx) do
    steps = steps(g)
    profiles = profiles(g, ctx.tuned)

    decisions =
      steps
      |> Enum.with_index()
      |> Enum.flat_map(fn {step, i} -> decision(step, i, g, ctx) end)
      |> evaluate(g, profiles, ctx)

    final = g.session.game

    %{
      decisions: decisions,
      summary: %{
        id: g.id,
        players: g.players,
        humans: g.humans,
        names: g.names,
        round: final.round,
        over: g.over?,
        human_won: human_won?(g),
        scores: final |> Game.score() |> Enum.sort() |> Enum.map(&elem(&1, 1)),
        standings: Game.standings(final),
        explosions: explosions(steps, g)
      }
    }
  end

  @doc """
  Every step of `game`'s log: `{game before, seat, action}`, oldest first, then the
  final game as `{game, nil, nil}`.
  """
  @spec steps(Quacks.Archive.game()) :: [{Game.t(), Game.seat() | nil, Game.action() | nil}]
  def steps(%{bundle: bundle, session: session}) do
    {:ok, %Session{game: start}} = Session.from_bundle(bundle, 0)

    {steps, final} =
      session.actions
      |> Enum.reverse()
      |> Enum.map_reduce(start, fn {seat, action}, game ->
        {:ok, next} = Game.apply(game, seat, action)
        {{game, seat, action}, next}
      end)

    steps ++ [{final, nil, nil}]
  end

  # The bot of each seat for rollouts: its own profile; a human seat gets the tuned bot.
  defp profiles(g, tuned) do
    Map.new(0..(g.players - 1), fn seat ->
      {seat, if(seat in g.humans, do: tuned, else: profile(g.bots[seat], tuned))}
    end)
  end

  defp profile(nil, tuned), do: tuned

  defp profile(name, tuned) do
    case Profile.parse(name) do
      {:ok, p} -> p
      {:error, _} -> tuned
    end
  end

  defp decision({_game, nil, nil}, _i, _g, _ctx), do: []

  defp decision({game, seat, action}, i, g, ctx) do
    phase = Game.phase(game, seat)
    legal = Game.legal_actions(game, seat)
    kind = kind(phase, action, legal)
    human? = seat in g.humans

    if kind == nil do
      []
    else
      base = %{
        game: g.id,
        step: i,
        seat: seat,
        human?: human?,
        round: game.round,
        kind: kind,
        action: action,
        options: options(kind, legal),
        state: game
      }

      [base |> put_reference(human?, ctx) |> put_features(kind)]
    end
  end

  @doc false
  def kind(:potions, action, legal) when action in [:draw, :stop, :use_flask] do
    if length(Enum.filter(legal, &(&1 in [:draw, :stop, :use_flask]))) >= 2, do: :draw_stop
  end

  def kind(:explosion_choice, {:explosion_choice, _}, [_, _ | _]), do: :explosion
  def kind(:shop, {:buy, _}, _legal), do: :buy

  def kind(:shop, action, legal) when action == :end_round or is_tuple(action) do
    if (action == :end_round or elem(action, 0) == :rubies) and
         Enum.any?(legal, &match?({:rubies, _}, &1)),
       do: :rubies
  end

  def kind(phase, _action, [_, _ | _]) when phase in @choices, do: :choice
  def kind(_phase, _action, _legal), do: nil

  defp options(:draw_stop, legal), do: Enum.filter(legal, &(&1 in [:draw, :stop, :use_flask]))
  defp options(:buy, legal), do: for({:buy, _} = a <- legal, do: a)

  defp options(:rubies, legal),
    do: Enum.filter(legal, &(&1 == :end_round or match?({:rubies, _}, &1)))

  defp options(_kind, legal), do: legal

  # What the tuned bot does in the same state (human decisions only).
  defp put_reference(d, false, _ctx), do: d

  # In the shop the bot buys first, then spends rubies: compare a buy with its best
  # buy and a ruby step with its ruby step (`Quacks.AI.Shop.pick/4` on those options).
  defp put_reference(%{kind: kind, state: game, seat: seat} = d, true, ctx)
       when kind in [:buy, :rubies],
       do: Map.put(d, :tuned, Shop.pick(game, seat, ctx.tuned, d.options))

  defp put_reference(%{state: game, seat: seat} = d, true, ctx) do
    case AI.decide(game, seat, ctx.tuned, AI.new_rng({ctx.seed, 0, 0}, seat)) do
      {action, _rng} -> Map.put(d, :tuned, action)
      :none -> d
    end
  rescue
    _ -> d
  end

  defp put_features(%{kind: :draw_stop, state: game, seat: seat} = d, _kind) do
    p = Game.player(game, seat)
    Map.merge(d, %{bust: Odds.next_draw(game, seat), white: Player.white_sum(p)})
  end

  defp put_features(%{kind: :buy, state: game, seat: seat} = d, _kind) do
    p = Game.player(game, seat)
    Map.put(d, :owned, p.bag ++ Player.pot_chips(p) ++ p.bowl)
  end

  defp put_features(d, _kind), do: d

  # Rounds that exploded per seat: `%{seat => [round]}`.
  defp explosions(steps, g) do
    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [{a, _, _}, {b, _, _}] -> round_end(a, b) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> then(fn by_seat -> Map.new(0..(g.players - 1), &{&1, Map.get(by_seat, &1, [])}) end)
  end

  defp round_end(%{phase: :shopping}, _b), do: []

  defp round_end(a, %{phase: phase} = b) when phase in [:shopping, :over] do
    for({seat, p} <- b.players, p.exploded?, do: {seat, a.round})
  end

  defp round_end(_a, _b), do: []

  # -- evaluation -----------------------------------------------------------------------

  defp evaluate(decisions, g, profiles, ctx) do
    decisions
    |> Task.async_stream(&value(&1, g, profiles, ctx),
      max_concurrency: ctx.jobs,
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, d} -> Map.delete(d, :state) end)
  end

  # Human draw/stop: expectimax with the tuned bot's values.
  defp value(%{human?: true, kind: :draw_stop, action: action} = d, _g, _profiles, ctx)
       when action in [:draw, :stop] do
    %{stop: stop, draw: draw} = Expectimax.ev(d.state, d.seat, ctx.tuned)
    chosen = if action == :draw, do: draw, else: stop
    best = if draw > stop, do: :draw, else: :stop

    Map.merge(d, %{
      ev: %{stop: stop, draw: draw},
      best: best,
      loss: max(draw, stop) - chosen,
      method: "expectimax"
    })
  end

  # Human buys, explosions, rubies and choices that differ from the tuned bot: roll
  # out both.
  defp value(%{human?: true, kind: kind, tuned: tuned, action: action} = d, g, profiles, ctx)
       when kind in @rollout_kinds and tuned != action do
    case rollouts(d, [action, tuned], g, profiles, ctx) do
      nil -> d
      r -> Map.merge(d, r)
    end
  end

  defp value(%{human?: true} = d, _g, _profiles, _ctx), do: d

  # Bot decisions: roll out the options.
  defp value(%{human?: false, kind: kind} = d, g, profiles, ctx) do
    if kind in ctx.bot_kinds do
      others = d |> capped(ctx) |> List.delete(d.action)
      r = rollouts(d, Enum.take([d.action | others], ctx.max_options), g, profiles, ctx)
      if r, do: Map.merge(d, r), else: d
    else
      d
    end
  end

  # The options to roll out: for a buy the best by the tuned bot's shop score.
  defp capped(%{kind: :buy, options: options, round: round, owned: owned}, ctx),
    do: Enum.sort_by(options, fn {:buy, chips} -> -Shop.score(chips, round, owned, ctx.tuned) end)

  defp capped(%{options: options}, _ctx), do: options

  # Each option `futures` times on the same seeds. The first option is the chosen one.
  defp rollouts(%{state: game, seat: seat, step: step}, [chosen | _] = options, g, profiles, ctx) do
    seeds = for j <- 1..ctx.futures, do: {ctx.seed, :erlang.phash2({g.id, step}), j}

    values =
      for option <- Enum.uniq(options) do
        {option, Enum.map(seeds, &future(game, seat, option, profiles, &1))}
      end
      |> Enum.reject(fn {_o, vs} -> Enum.any?(vs, &is_nil/1) end)

    case Enum.find(values, &(elem(&1, 0) == chosen)) do
      nil ->
        nil

      {_, mine} ->
        {best, theirs} = Enum.max_by(values, fn {_o, vs} -> mean(vs) end)
        diffs = Enum.zip_with(theirs, mine, &(&1 - &2))

        %{
          best: best,
          loss: mean(diffs),
          se: se(diffs),
          values: Map.new(values, fn {o, vs} -> {label(o), Float.round(mean(vs), 2)} end),
          method: "rollouts x#{ctx.futures}",
          chosen_value: mean(mine),
          options_tried: length(values)
        }
    end
  end

  defp future(game, seat, option, profiles, seed) do
    game = %{game | rng: Rng.seed(seed)}

    case Game.apply(game, seat, option) do
      {:ok, next} -> next |> Bench.play_out(profiles, seed) |> Game.score() |> margin(seat)
      {:error, _} -> nil
    end
  rescue
    _ -> nil
  end

  defp margin(scores, seat) do
    others = scores |> Map.delete(seat) |> Map.values()
    if others == [], do: scores[seat], else: scores[seat] - Enum.max(others)
  end

  # -- summaries ------------------------------------------------------------------------

  defp style(human, bot, reviewed) do
    human_stops = Enum.filter(human, &(&1.kind == :draw_stop and &1.action == :stop))
    human_draws = Enum.filter(human, &(&1.kind == :draw_stop and &1.action == :draw))
    bot_stops = Enum.filter(bot, &(&1.kind == :draw_stop and &1.action == :stop))
    buys = for %{kind: :buy, action: {:buy, chips}, round: r} <- human, do: {r, chips}

    %{
      stops_by_round: by_round(human_stops, &stop_row/1),
      bot_stops_by_round: by_round(bot_stops, &stop_row/1),
      draws: %{
        n: length(human_draws),
        bust_mean: avg(human_draws, & &1.bust),
        tuned_would_stop: share(human_draws, &(&1[:best] == :stop))
      },
      explosions: explosion_rows(human, reviewed),
      buys_by_round:
        buys
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Map.new(fn {r, list} -> {r, Enum.map(list, &label({:buy, &1}))} end),
      buys_by_colour: buys |> Enum.flat_map(&elem(&1, 1)) |> Enum.frequencies_by(&elem(&1, 0)),
      buys_by_value: buys |> Enum.flat_map(&elem(&1, 1)) |> Enum.frequencies_by(&elem(&1, 1)),
      no_buy: Enum.count(buys, &(elem(&1, 1) == [])),
      rubies:
        human |> Enum.filter(&(&1.kind == :rubies)) |> Enum.frequencies_by(&label(&1.action)),
      flask: Enum.count(human, &(&1.action == :use_flask)),
      choices:
        human |> Enum.filter(&(&1.kind == :choice)) |> Enum.frequencies_by(&label(&1.action))
    }
  end

  defp stop_row(list) do
    %{
      n: length(list),
      bust_mean: avg(list, & &1.bust),
      white_mean: avg(list, & &1.white),
      tuned_would_draw: share(list, &(&1[:best] == :draw)),
      ev_loss_mean: avg(Enum.filter(list, & &1[:loss]), & &1.loss)
    }
  end

  defp explosion_rows(human, reviewed) do
    choices = Enum.filter(human, &(&1.kind == :explosion))

    rounds =
      for %{summary: s} <- reviewed, seat <- s.humans, r <- 1..s.round, r < s.round or s.over do
        {r, r in Map.get(s.explosions, seat, [])}
      end

    rounds
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {r, list} ->
      picks = Enum.filter(choices, &(&1.round == r))

      {r,
       %{
         rounds: length(list),
         exploded: Enum.count(list, & &1),
         coins: Enum.count(picks, &(&1.action == {:explosion_choice, :buy})),
         vp: Enum.count(picks, &(&1.action == {:explosion_choice, :vp}))
       }}
    end)
  end

  defp agreement(human) do
    human
    |> Enum.filter(&Map.has_key?(&1, :tuned))
    |> Enum.group_by(& &1.kind)
    |> Map.new(fn {kind, list} ->
      agree = Enum.count(list, &(&1.tuned == &1.action))
      {kind, %{n: length(list), agree: agree, rate: agree / length(list)}}
    end)
  end

  defp bot_mistakes(bot, top) do
    rolled = Enum.filter(bot, & &1[:loss])
    mistakes = Enum.filter(rolled, &mistake?/1)

    %{
      by_kind:
        rolled
        |> Enum.group_by(& &1.kind)
        |> Map.new(fn {kind, list} ->
          m = Enum.filter(list, &mistake?/1)

          {kind,
           %{
             n: length(list),
             mistakes: length(m),
             loss_per_decision: avg(list, & &1.loss),
             loss_of_mistakes: m |> Enum.map(& &1.loss) |> Enum.sum()
           }}
        end),
      top: top_by_loss(mistakes, top)
    }
  end

  defp mistake?(%{loss: loss, se: se}), do: loss > 0 and loss > 2 * se
  defp mistake?(_d), do: false

  defp top_by_loss(list, n) do
    list
    |> Enum.sort_by(&(-&1.loss))
    |> Enum.take(n)
    |> Enum.map(&row/1)
  end

  defp row(d) do
    %{
      game: d.game,
      step: d.step,
      seat: d.seat,
      round: d.round,
      kind: d.kind,
      chosen: label(d.action),
      best: label(d[:best]),
      tuned: d[:tuned] && label(d.tuned),
      loss: Float.round(d.loss / 1, 2),
      se: d[:se] && Float.round(d.se / 1, 2),
      method: d[:method],
      bust: d[:bust] && Float.round(d.bust, 2),
      values: d[:values]
    }
  end

  defp by_round(list, fun),
    do: list |> Enum.group_by(& &1.round) |> Map.new(fn {r, l} -> {r, fun.(l)} end)

  # -- training data --------------------------------------------------------------------

  @doc """
  The human seats' shop buys of `games`, for `Quacks.AI.ShopFit`: `%{round, owned,
  options: [chips], chosen: chips}`.
  """
  @spec buy_examples([Quacks.Archive.game()]) :: [map]
  def buy_examples(games) do
    for g <- games,
        {game, seat, {:buy, chips}} <- steps(g),
        seat in g.humans,
        Game.phase(game, seat) == :shop do
      p = Game.player(game, seat)

      %{
        round: game.round,
        owned: p.bag ++ Player.pot_chips(p) ++ p.bowl,
        options: for({:buy, c} <- Game.legal_actions(game, seat), do: c),
        chosen: chips
      }
    end
  end

  @doc """
  Start positions for training (`mix quacks.tune --starts`): each game's state at
  the start of every round from 2 on (nobody has drawn yet).
  """
  @spec start_positions([Quacks.Archive.game()]) :: [Game.t()]
  def start_positions(games) do
    for g <- games,
        [{a, _, _}, {b, _, _}] <- g |> steps() |> Enum.chunk_every(2, 1, :discard),
        b.round > a.round,
        do: b
  end

  # -- text -----------------------------------------------------------------------------

  @doc "An action as short text: `buy red 2 + blue 1`, `draw`, `explosion_choice vp`."
  @spec label(term) :: String.t()
  def label(nil), do: "-"
  def label({:buy, []}), do: "buy nothing"

  def label({:buy, chips}) when is_list(chips),
    do: "buy " <> Enum.map_join(chips, " + ", &label/1)

  def label(atom) when is_atom(atom), do: Atom.to_string(atom)

  def label(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map_join(" ", &label/1)

  def label(list) when is_list(list), do: "[" <> Enum.map_join(list, ", ", &label/1) <> "]"
  def label(other), do: to_string(other)

  @doc "The report of `run/2` as markdown."
  @spec markdown(map) :: String.t()
  def markdown(r) do
    IO.iodata_to_binary([
      games_text(r),
      style_text(r.style),
      compare_text(r),
      bots_text(r.bot_mistakes)
    ])
  end

  defp games_text(r) do
    [
      "# Review of #{r.games.reviewed} games\n\n",
      "Reference bot: `#{r.settings.reference}`. Rollouts: #{r.settings.futures} futures per option",
      ", seed #{r.settings.seed}. Only games a human won or leads: #{r.settings.human_won}.\n\n",
      "## Games\n\n",
      table(
        ["game", "players", "humans", "round", "over", "human won/leads", "scores"],
        for g <- r.games.list do
          [g.id, g.players, inspect(g.humans), g.round, g.over, g.human_won]
          |> Kernel.++([Enum.join(g.scores, " / ")])
        end
      ),
      "\nDecisions: #{r.games.human_decisions} human, #{r.games.bot_decisions} bot.\n\n"
    ]
  end

  @empty_stops %{n: 0, bust_mean: nil, white_mean: nil, tuned_would_draw: nil, ev_loss_mean: nil}

  defp style_text(s) do
    [
      "## Human style\n\n### Stops per round\n\n",
      "Bust = the chance that the next draw explodes. \"Tuned would draw\" = the tuned bot's ",
      "expectimax says a draw is worth more. EV loss in VP (the tuned bot's value scale).\n\n",
      table(
        ["round", "stops", "bust", "white", "tuned would draw", "EV loss"] ++
          ["bots: stops", "bots: bust", "bots: white"],
        for round <- 1..9, s.stops_by_round[round] || s.bot_stops_by_round[round] do
          h = Map.merge(@empty_stops, s.stops_by_round[round] || %{})
          b = Map.merge(@empty_stops, s.bot_stops_by_round[round] || %{})

          [round, h.n, pct(h.bust_mean), num(h.white_mean), pct(h.tuned_would_draw)] ++
            [num(h.ev_loss_mean), b.n, pct(b.bust_mean), num(b.white_mean)]
        end
      ),
      "\nDraws: #{s.draws.n}, mean bust #{pct(s.draws.bust_mean)}, the tuned bot would stop at ",
      "#{pct(s.draws.tuned_would_stop)} of them.\n\n",
      "### Explosions\n\n",
      table(
        ["round", "rounds", "exploded", "took coins", "took VP"],
        for(
          {round, e} <- Enum.sort(s.explosions),
          do: [round, e.rounds, e.exploded, e.coins, e.vp]
        )
      ),
      "\n### Shop\n\n",
      table(
        ["round", "buys"],
        for({round, list} <- Enum.sort(s.buys_by_round), do: [round, Enum.join(list, "; ")])
      ),
      "\nBy colour: #{counts(s.buys_by_colour)}. By value: #{counts(s.buys_by_value)}. ",
      "No buy: #{s.no_buy}.\n\n",
      "Rubies: #{counts(s.rubies)}. Flask used: #{s.flask}.\n\n",
      "Choices (books, cards, witches): #{counts(s.choices)}.\n\n"
    ]
  end

  defp compare_text(r) do
    [
      "## Human vs tuned bot\n\n",
      table(
        ["kind", "decisions", "same as tuned", "agreement"],
        for({kind, a} <- Enum.sort(r.agreement), do: [kind, a.n, a.agree, pct(a.rate)])
      ),
      "\n### Biggest differences (the human's loss)\n\n",
      rows_table(r.differences)
    ]
  end

  defp bots_text(m) do
    [
      "\n## Bot mistakes\n\n",
      "A mistake: the best option by rollouts beats the bot's choice by more than 2 standard ",
      "errors.\n\n",
      table(
        ["kind", "decisions", "mistakes", "mean loss per decision", "sum of mistake losses"],
        for {kind, k} <- Enum.sort(m.by_kind) do
          [kind, k.n, k.mistakes, num(k.loss_per_decision), num(k.loss_of_mistakes)]
        end
      ),
      "\n### Top bot mistakes\n\n",
      rows_table(m.top)
    ]
  end

  defp rows_table([]), do: "None.\n"

  defp rows_table(rows) do
    table(
      ["game", "round", "seat", "kind", "chosen", "best", "loss", "± 2 se", "method"],
      for d <- rows do
        [
          d.game,
          d.round,
          d.seat,
          d.kind,
          d.chosen,
          d.best,
          num(d.loss),
          d.se && num(2 * d.se),
          d.method
        ]
      end
    )
  end

  defp table(head, rows) do
    line = fn cells -> "| " <> Enum.map_join(cells, " | ", &cell/1) <> " |\n" end
    [line.(head), line.(Enum.map(head, fn _ -> "---" end)), Enum.map(rows, line)]
  end

  defp cell(nil), do: "-"
  defp cell(x), do: x |> to_string() |> String.replace("|", "\\|")

  defp counts(map) when map_size(map) == 0, do: "none"

  defp counts(map),
    do: map |> Enum.sort_by(&(-elem(&1, 1))) |> Enum.map_join(", ", fn {k, n} -> "#{k} #{n}" end)

  defp pct(nil), do: nil
  defp pct(x), do: "#{round(x * 100)} %"
  defp num(nil), do: nil
  defp num(x), do: :erlang.float_to_binary(x / 1, decimals: 2)

  defp avg(list, fun) do
    values = list |> Enum.map(fun) |> Enum.reject(&is_nil/1)
    if values == [], do: nil, else: Enum.sum(values) / length(values)
  end

  defp share([], _fun), do: nil
  defp share(list, fun), do: Enum.count(list, fun) / length(list)

  defp mean([]), do: 0.0
  defp mean(list), do: Enum.sum(list) / length(list)

  defp se(list) when length(list) < 2, do: 0.0

  defp se(list) do
    m = mean(list)
    :math.sqrt(Enum.sum(Enum.map(list, &((&1 - m) ** 2))) / (length(list) - 1) / length(list))
  end
end
