defmodule Quacks.AI.Weights do
  @moduledoc """
  The tunable numbers of a bot profile as a vector, for `Quacks.AI.Tune`
  (`docs/research/bot-training.md` §5). Each entry of `spec/0` is one number with a
  range; `to_unit/1` maps a profile into `[0, 1]^n` and `from_unit/2` back.
  `load/1` and `save/3` read and write a weights file (JSON) such as
  `priv/bots/tuned.json`; `Quacks.AI.Profile.parse("file:priv/bots/tuned.json")`
  gives the tuned profile.
  """

  alias Quacks.AI.Profile

  @colours [:red, :orange, :blue, :purple, :black, :green, :yellow]

  # {key, low, high, :float | :int}
  @spec_list for(r <- 1..9, do: {{:coin_weight, r}, 0.0, 3.0, :float}) ++
               [{:ruby_value, 0.0, 3.0, :float}, {:explode_vp_from, 1, 10, :int}] ++
               for(c <- @colours, do: {{:colour_weight, c}, 0.0, 5.0, :float}) ++
               for(v <- [1, 2, 4, 6], do: {{:value_weight, v}, 0.0, 6.0, :float}) ++
               [
                 {:black_max, 0, 3, :int},
                 {:purple_from, 1, 9, :int},
                 {:droplet_until, 0, 8, :int},
                 {:flask_min_white, 1, 3, :int},
                 {:droplet_first, 0, 1, :int}
               ]

  @doc "The tuned numbers: `{key, low, high, :float | :int}`."
  @spec spec() :: [{term, number, number, :float | :int}]
  def spec, do: @spec_list

  @doc """
  The profile's numbers in `[0, 1]`, in `spec/0` order.

      iex> p = Quacks.AI.Profile.get(:balanced)
      iex> Quacks.AI.Weights.from_unit(p, Quacks.AI.Weights.to_unit(p)) == p
      true
  """
  @spec to_unit(Profile.t()) :: [float]
  def to_unit(profile) do
    for {key, lo, hi, _kind} <- @spec_list, do: (get(profile, key) - lo) / (hi - lo)
  end

  @doc "`profile` with the numbers of `unit` (clamped to `[0, 1]`; ints rounded)."
  @spec from_unit(Profile.t(), [float]) :: Profile.t()
  def from_unit(profile, unit) do
    @spec_list
    |> Enum.zip(unit)
    |> Enum.reduce(profile, fn {{key, lo, hi, kind}, u}, acc ->
      x = lo + min(max(u, 0.0), 1.0) * (hi - lo)
      put(acc, key, if(kind == :int, do: round(x), else: Float.round(x, 3)))
    end)
  end

  defp get(p, {field, k}), do: Map.get(Map.fetch!(p, field), k, 0.8)
  defp get(p, :droplet_first), do: if(hd(p.ruby_plan) == :droplet, do: 1, else: 0)
  defp get(p, key), do: Map.fetch!(p, key)

  defp put(p, {field, k}, x), do: Map.update!(p, field, &Map.put(&1, k, x))
  defp put(p, :droplet_first, 1), do: %{p | ruby_plan: [:droplet, :flask]}
  defp put(p, :droplet_first, 0), do: %{p | ruby_plan: [:flask, :droplet]}
  defp put(p, key, x), do: Map.put(p, key, x)

  @doc """
  Write `profile`'s numbers to `path` as JSON, with `base` (the profile text it
  starts from) and `meta` (free notes, e.g. the tuning run).
  """
  @spec save(Path.t(), String.t(), Profile.t(), map) :: :ok
  def save(path, base, profile, meta \\ %{}) do
    values =
      Map.new(@spec_list, fn {key, _, _, _} -> {key_name(key), get(profile, key)} end)

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{base: base, values: values, meta: meta}, pretty: true))
  end

  @doc "The profile in the weights file at `path`, named after the file (`:tuned`)."
  @spec load(Path.t()) :: {:ok, Profile.t()} | {:error, String.t()}
  def load(path) do
    with {:ok, text} <- read(path),
         {:ok, %{"base" => base, "values" => values}} <- decode(text),
         {:ok, profile} <- Profile.parse(base) do
      tuned =
        Enum.reduce(@spec_list, profile, fn {key, _, _, _}, acc ->
          put_value(acc, key, Map.fetch(values, key_name(key)))
        end)

      {:ok, %{tuned | name: path |> Path.basename(".json") |> String.to_atom()}}
    end
  end

  defp put_value(profile, key, {:ok, x}), do: put(profile, key, x)
  defp put_value(profile, _key, :error), do: profile

  defp read(path) do
    case File.read(path) do
      {:ok, text} -> {:ok, text}
      {:error, reason} -> {:error, "cannot read #{path}: #{:file.format_error(reason)}"}
    end
  end

  defp decode(text) do
    case Jason.decode(text) do
      {:ok, %{"base" => _, "values" => _} = map} -> {:ok, map}
      _ -> {:error, "not a weights file"}
    end
  end

  defp key_name({field, k}), do: "#{field}.#{k}"
  defp key_name(key), do: Atom.to_string(key)
end
