defmodule Quacks.AI.ShopFit do
  @moduledoc """
  Fits the shop numbers of a profile (`colour_weight`, `value_weight`) to the buys
  of a player (`docs/research/learn-from-nick.md`), as a start point for
  `Quacks.AI.Tune`.

  The model is the bot's own buy scorer (`Quacks.AI.Shop.score/4`) as a choice
  model: of the legal buys `o` (with "buy nothing"), the player takes `b` with the
  chance `exp(beta * score(b)) / sum(exp(beta * score(o)))`. The fit maximises the
  log-likelihood of the observed buys minus `prior * sum((u - u0)^2)`, where `u`
  are the numbers scaled to `[0, 1]` (`Quacks.AI.Weights`) and `u0` those of the
  start profile. With few buys the prior keeps the fit near the start profile. The
  search is the cross-entropy method (deterministic per `seed:`); `beta` is fitted
  too.
  """

  alias Quacks.AI.{Shop, Tune, Weights}

  @beta_max 5.0

  @doc """
  Fit `profile`'s shop numbers to `examples` (`Quacks.AI.Review.buy_examples/1`).
  Options: `prior:` (default 10.0), `iterations:` (default 60), `population:`
  (default 64), `elite:` (default 8), `seed:` (default 1).

  Returns `%{profile:, n:, beta:, log_lik:, start_log_lik:, agreement:,
  start_agreement:}`: the log-likelihood is per buy (higher is better), the
  agreement the share of buys where the best-scored option is the one taken.
  """
  @spec fit([map], Quacks.AI.Profile.t(), keyword) :: map
  def fit(examples, profile, opts \\ []) do
    idx = indices()
    u0 = Weights.to_unit(profile)
    start = Enum.map(idx, &Enum.at(u0, &1)) ++ [1.0 / @beta_max]

    ctx = %{
      examples: examples,
      profile: profile,
      idx: idx,
      u0: u0,
      prior: Keyword.get(opts, :prior, 10.0)
    }

    rng = :rand.seed_s(:exsss, {Keyword.get(opts, :seed, 1), 77, 7})
    population = Keyword.get(opts, :population, 64)
    elite = Keyword.get(opts, :elite, 8)

    {mean, _sd, _rng} =
      Enum.reduce(
        1..Keyword.get(opts, :iterations, 60),
        {start, List.duplicate(0.1, length(start)), rng},
        fn
          _, {mean, sd, rng} ->
            {samples, rng} = Tune.sample(mean, sd, population, rng)

            best =
              [mean | samples]
              |> Enum.sort_by(&(-objective(&1, ctx)))
              |> Enum.take(elite)

            {m, s} = Tune.update(mean, sd, best)
            {m, s, rng}
        end
      )

    fitted = profile_of(mean, ctx)
    beta = beta(mean)
    beta0 = beta(start)

    %{
      profile: fitted,
      n: length(examples),
      beta: beta,
      log_lik: per_buy(log_lik(examples, fitted, beta), examples),
      start_log_lik: per_buy(log_lik(examples, profile, beta0), examples),
      agreement: agreement(examples, fitted),
      start_agreement: agreement(examples, profile)
    }
  end

  @doc "The share of `examples` where `profile`'s best-scored buy is the one taken."
  @spec agreement([map], Quacks.AI.Profile.t()) :: float | nil
  def agreement([], _profile), do: nil

  def agreement(examples, profile) do
    hits =
      Enum.count(examples, fn e ->
        Enum.max_by(e.options, &Shop.score(&1, e.round, e.owned, profile)) == e.chosen
      end)

    hits / length(examples)
  end

  @doc "The log-likelihood of `examples` under `profile` with `beta`."
  @spec log_lik([map], Quacks.AI.Profile.t(), float) :: float
  def log_lik(examples, profile, beta) do
    examples
    |> Enum.map(fn e ->
      scores = Enum.map(e.options, &(beta * Shop.score(&1, e.round, e.owned, profile)))
      top = Enum.max(scores)
      log_sum = top + :math.log(Enum.sum(Enum.map(scores, &:math.exp(&1 - top))))
      beta * Shop.score(e.chosen, e.round, e.owned, profile) - log_sum
    end)
    |> Enum.sum()
  end

  defp objective(x, ctx) do
    profile = profile_of(x, ctx)
    u = Enum.drop(x, -1)
    u0 = Enum.map(ctx.idx, &Enum.at(ctx.u0, &1))
    penalty = Enum.zip_with(u, u0, &((&1 - &2) ** 2)) |> Enum.sum()
    log_lik(ctx.examples, profile, beta(x)) - ctx.prior * penalty
  end

  defp profile_of(x, ctx) do
    unit =
      ctx.idx
      |> Enum.zip(Enum.drop(x, -1))
      |> Enum.reduce(ctx.u0, fn {i, v}, acc -> List.replace_at(acc, i, v) end)

    Weights.from_unit(ctx.profile, unit)
  end

  defp beta(x), do: max(List.last(x), 0.01) * @beta_max

  defp per_buy(_ll, []), do: nil
  defp per_buy(ll, examples), do: ll / length(examples)

  # The positions of the shop's numbers in `Weights.spec/0`.
  defp indices do
    Weights.spec()
    |> Enum.with_index()
    |> Enum.filter(fn {{key, _, _, _}, _i} ->
      match?({f, _} when f in [:colour_weight, :value_weight], key)
    end)
    |> Enum.map(&elem(&1, 1))
  end
end
