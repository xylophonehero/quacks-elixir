defmodule Quacks.AI.Profile do
  @moduledoc """
  How a bot plays, as data (`docs/research/ai-opponents.md` §3.2). `get/1` returns one
  of three profiles: `:cautious`, `:balanced`, `:reckless`.

  - `max_bust`: per round, the highest chance of an explosion at which the bot still
    draws. `margin_shift` moves it up per VP behind the best other player (down when
    ahead), at most ±0.10 (twice the shift in round 9).
  - `explode_vp_from`: after an explosion, take coins (`:buy`) before this round, VP
    from it. Round 9 is always VP.
  - `flask_min_white`: use the flask only on a white chip of this value or more.
  - `colour_weight`, `value_weight`: how much the shop likes a colour and a chip
    value. `black_max`: more black chips than this score badly; purple scores badly
    before round `purple_from`.
  - `ruby_plan`: what the rubies buy first (`:flask` refill, `:droplet`); droplets
    only up to round `droplet_until`.
  - `stop_rule`: `:threshold` (draw while the bust chance is under `max_bust`) or
    `:ev` (draw while one more draw is worth more than a stop, `Quacks.AI.Expectimax`,
    `ev_depth` draws deep). `flask_rule`: `:heuristic` (`flask_min_white`, then the
    stop rule) or `:ev` (the flask when the best play after it beats a stop now by
    more than `flask_cost`). Both value a scoring space with `coin_weight` per round,
    1 per VP and `ruby_value` per ruby.
  - `choice_rule`: the fortune, chip, gold witch and essence-space choices.
    `:default` (fortune random but never dominated; chips and witches: the first;
    essence: the furthest space), `:random` (any legal choice) or `:scored`
    (`Quacks.AI.Choice`, a static value table).
  """

  @type name :: :cautious | :balanced | :reckless
  @type t :: %__MODULE__{
          name: name,
          bot_name: String.t(),
          label: String.t(),
          max_bust: %{(1..9) => float},
          margin_shift: float,
          explode_vp_from: 1..10,
          flask_min_white: 1..3,
          colour_weight: %{atom => float},
          value_weight: %{pos_integer => float},
          black_max: non_neg_integer,
          purple_from: 1..9,
          ruby_plan: [:flask | :droplet],
          droplet_until: 0..8,
          stop_rule: :threshold | :ev,
          flask_rule: :heuristic | :ev,
          choice_rule: :default | :random | :scored,
          ev_depth: 1..6,
          coin_weight: %{(1..9) => float},
          ruby_value: float,
          flask_cost: float
        }

  defstruct [
    :name,
    :bot_name,
    :label,
    :max_bust,
    margin_shift: 0.01,
    explode_vp_from: 6,
    flask_min_white: 2,
    colour_weight: %{},
    value_weight: %{1 => 1.0, 2 => 1.7, 4 => 2.6, 6 => 3.5},
    black_max: 2,
    purple_from: 3,
    ruby_plan: [:flask, :droplet],
    droplet_until: 6,
    stop_rule: :threshold,
    flask_rule: :heuristic,
    choice_rule: :default,
    ev_depth: 3,
    coin_weight: %{
      1 => 1.5,
      2 => 1.4,
      3 => 1.2,
      4 => 1.0,
      5 => 0.8,
      6 => 0.5,
      7 => 0.25,
      8 => 0.12,
      9 => 0.2
    },
    ruby_value: 1.0,
    flask_cost: 2.0
  ]

  @names %{cautious: "Careful Clara", balanced: "Steady Sam", reckless: "Bold Bruno"}
  @labels %{cautious: "Cautious", balanced: "Balanced", reckless: "Reckless"}

  @doc "Every profile name, from careful to bold."
  @spec all() :: [name]
  def all, do: [:cautious, :balanced, :reckless]

  @doc "The bot's display name per profile, e.g. `%{balanced: \"Steady Sam\", ...}`."
  @spec names() :: %{name => String.t()}
  def names, do: @names

  @doc "The profile's display label, e.g. `\"Balanced\"`."
  @spec label(name) :: String.t()
  def label(name), do: Map.fetch!(@labels, name)

  @doc "The profile called `name`."
  @spec get(name) :: t
  def get(name), do: %{fields(name) | name: name, bot_name: @names[name], label: @labels[name]}

  @variants %{
    "ev" => [stop_rule: :ev],
    "strong" => [stop_rule: :ev, choice_rule: :scored],
    "flaskev" => [flask_rule: :ev],
    "random" => [choice_rule: :random],
    "scored" => [choice_rule: :scored],
    "d1" => [ev_depth: 1],
    "d2" => [ev_depth: 2],
    "d4" => [ev_depth: 4],
    "d5" => [ev_depth: 5]
  }

  @doc """
  A profile from text, for the simulator: a name with `+` modifiers, e.g.
  `"balanced+ev+flaskev"` (`ev`, `flaskev`, `random`, `scored`, `strong` (`ev` and
  `scored`), `d1`..`d5` for `ev_depth`). `"file:priv/bots/tuned.json"` loads a
  weights file (`Quacks.AI.Weights`). The struct's `name` is the whole text as an atom, so the simulator
  tells the variants apart.

      iex> {:ok, p} = Quacks.AI.Profile.parse("balanced+ev")
      iex> {p.name, p.stop_rule, p.flask_rule}
      {:"balanced+ev", :ev, :heuristic}
  """
  @spec parse(String.t()) :: {:ok, t} | {:error, String.t()}
  def parse("file:" <> path), do: Quacks.AI.Weights.load(String.trim(path))

  def parse(text) do
    [base | mods] = text |> String.trim() |> String.split("+")
    known = Map.new(all(), &{Atom.to_string(&1), &1})

    with {:ok, name} <- Map.fetch(known, base) |> or_error("unknown profile #{base}"),
         {:ok, changes} <- changes(mods) do
      profile = struct!(get(name), changes)
      {:ok, if(mods == [], do: profile, else: %{profile | name: String.to_atom(text)})}
    end
  end

  defp changes(mods) do
    Enum.reduce_while(mods, {:ok, []}, fn mod, {:ok, acc} ->
      case Map.fetch(@variants, mod) do
        {:ok, change} -> {:cont, {:ok, acc ++ change}}
        :error -> {:halt, {:error, "unknown modifier #{mod}"}}
      end
    end)
  end

  defp or_error({:ok, _} = ok, _message), do: ok
  defp or_error(:error, message), do: {:error, message}

  defp fields(:cautious) do
    %__MODULE__{
      max_bust: bust([0.25, 0.22, 0.20, 0.18, 0.15, 0.12, 0.10, 0.10, 0.08]),
      explode_vp_from: 5,
      colour_weight: %{
        orange: 1.2,
        blue: 1.3,
        red: 1.0,
        yellow: 1.0,
        purple: 1.5,
        black: 1.5,
        green: 0.9
      },
      value_weight: %{1 => 1.0, 2 => 1.4, 4 => 2.0, 6 => 2.8},
      black_max: 1,
      purple_from: 4,
      ruby_plan: [:flask, :droplet],
      droplet_until: 5
    }
  end

  defp fields(:balanced) do
    %__MODULE__{
      max_bust: bust([0.60, 0.55, 0.50, 0.45, 0.30, 0.25, 0.15, 0.15, 0.10]),
      explode_vp_from: 7,
      flask_min_white: 3,
      colour_weight: %{
        red: 1.2,
        orange: 1.0,
        blue: 1.1,
        purple: 3.0,
        black: 3.0,
        green: 0.8,
        yellow: 0.8
      },
      value_weight: %{1 => 1.0, 2 => 1.7, 4 => 3.2, 6 => 4.0},
      black_max: 1,
      ruby_plan: [:droplet, :flask]
    }
  end

  defp fields(:reckless) do
    %__MODULE__{
      max_bust: bust([0.70, 0.65, 0.60, 0.55, 0.45, 0.40, 0.30, 0.30, 0.30]),
      margin_shift: 0.015,
      explode_vp_from: 7,
      flask_min_white: 3,
      colour_weight: %{
        red: 1.4,
        orange: 0.9,
        blue: 1.0,
        purple: 3.5,
        black: 2.0,
        green: 0.7,
        yellow: 0.8
      },
      value_weight: %{1 => 1.0, 2 => 1.8, 4 => 3.6, 6 => 4.5},
      black_max: 1,
      ruby_plan: [:droplet, :flask],
      droplet_until: 7
    }
  end

  defp bust(list), do: Map.new(Enum.with_index(list, 1), fn {p, round} -> {round, p} end)
end
