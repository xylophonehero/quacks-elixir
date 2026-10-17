defmodule Codex.AI.Weights do
  @moduledoc """
  The numbers of the Codex evaluator (`Codex.AI.Eval`) and of the bots that use
  it, as data. `defaults/0` is the source of truth in git; `mix codex.tune`
  changes them by self-play and writes a new `defaults/0` for a person to
  review (`docs/research/codex-bot.md`, "Stage 2 results").

  Each weight multiplies one feature of `Codex.AI.Eval.features/2` (the side's
  value minus the other side's value), except:

  - `threat_base`, `threat_patrol`, `lethal`: the threat term
    (`Codex.AI.Eval.threat/2`), a cost for the bot's side only.
  - `ready`: the bot's forces that are not exhausted (`Codex.AI.Eval.ready/2`).
  - `exhaust_cost`: what `Codex.Bot.Plan` takes off an attack or an exhaust
    ability (the force cannot patrol after it).

  `spec/0` gives each tuned weight a range; `to_unit/1` and `from_unit/1` map
  the weights to `[0, 1]^n` and back for the cross-entropy method.
  """

  # The stage-1 numbers (`Codex.Bot.Plan.eval/2` before stage 2): the default
  # bot plays as before. The new features start at 0.
  @stage1 %{
    base_hp: 1.5,
    low_hp: 0.5,
    force_atk: 1.0,
    force_hp: 1.0,
    keywords: 1.0,
    heroes: 2.0,
    hero_levels: 1.0,
    tech_buildings: 4.0,
    add_ons: 2.0,
    building_damage: -0.5,
    gold: 0.3,
    ongoing: 1.0,
    workers: 0.0,
    hand: 0.0,
    tech_cards: 0.0,
    patrol_hp: 0.0,
    threat_base: 0.0,
    threat_patrol: 0.0,
    lethal: 0.0,
    ready: 0.0,
    exhaust_cost: 0.5
  }

  @defaults @stage1

  # {key, low, high}
  @spec_list [
    {:base_hp, 0.5, 3.0},
    {:low_hp, -1.0, 2.0},
    {:force_atk, 0.0, 3.0},
    {:force_hp, 0.0, 3.0},
    {:keywords, 0.0, 3.0},
    {:heroes, 0.0, 6.0},
    {:hero_levels, 0.0, 3.0},
    {:tech_buildings, 0.0, 10.0},
    {:add_ons, 0.0, 6.0},
    {:building_damage, -2.0, 0.0},
    {:gold, 0.0, 1.5},
    {:ongoing, 0.0, 4.0},
    {:workers, 0.0, 2.0},
    {:hand, -1.0, 2.0},
    {:tech_cards, -0.5, 1.0},
    {:patrol_hp, 0.0, 1.5},
    {:threat_base, 0.0, 2.0},
    {:threat_patrol, 0.0, 1.5},
    {:lethal, 0.0, 30.0},
    {:ready, 0.0, 2.0},
    {:exhaust_cost, 0.0, 2.0}
  ]

  @doc "The weights of the default bots."
  @spec defaults() :: %{atom => float}
  def defaults, do: @defaults

  @doc "The stage-1 weights (the stage-1 bot as it was measured)."
  @spec stage1() :: %{atom => float}
  def stage1, do: @stage1

  @doc "The tuned weights: `{key, low, high}`."
  @spec spec() :: [{atom, float, float}]
  def spec, do: @spec_list

  @doc """
  The weights in `[0, 1]`, in `spec/0` order.

      iex> w = Codex.AI.Weights.defaults()
      iex> Codex.AI.Weights.from_unit(Codex.AI.Weights.to_unit(w)) == w
      true
  """
  @spec to_unit(map) :: [float]
  def to_unit(weights) do
    for {key, lo, hi} <- @spec_list, do: (Map.fetch!(weights, key) - lo) / (hi - lo)
  end

  @doc "The weights of a unit vector (each clamped to `[0, 1]`, rounded to 3 decimals)."
  @spec from_unit([float]) :: map
  def from_unit(unit) do
    @spec_list
    |> Enum.zip(unit)
    |> Map.new(fn {{key, lo, hi}, u} ->
      {key, Float.round(lo + min(max(u, 0.0), 1.0) * (hi - lo), 3)}
    end)
  end

  @doc "Read a weights file (JSON, `%{\"weights\" => %{name => number}}`) over the defaults."
  @spec load(Path.t()) :: {:ok, map} | {:error, String.t()}
  def load(path) do
    with {:ok, text} <- File.read(path),
         {:ok, %{"weights" => w}} <- Jason.decode(text) do
      {:ok,
       Enum.reduce(@defaults, %{}, fn {k, v}, acc ->
         Map.put(acc, k, w |> Map.get(Atom.to_string(k), v) |> Kernel./(1))
       end)}
    else
      _ -> {:error, "cannot read the weights file #{path}"}
    end
  end

  @doc "Write `weights` and `meta` (notes on the run) to `path` as JSON."
  @spec save(Path.t(), map, map) :: :ok
  def save(path, weights, meta \\ %{}) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{weights: weights, meta: meta}, pretty: true))
  end
end
