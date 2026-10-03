defmodule Quacks.AI.Names do
  @moduledoc """
  Bot names: a short list of alchemist and witch names. `pick/2` takes one that is
  not at the table yet, with the table's rng (`:rand` `_s` API); when the list runs
  out the bot is "Bot N".
  """

  @names ~w(Agatha Balthazar Cordelia Dorian Elspeth Fenwick Griselda Hubert Isolde Jasper
            Lavinia Mortimer Ottoline Percival Quintus Rosalind Septimus Theodora Ulric
            Wilhelmina)

  @doc "Every name in the list."
  @spec all() :: [String.t()]
  def all, do: @names

  @doc """
  A name not in `taken`, and the advanced rng.

      iex> rng = :rand.seed_s(:exsss, {1, 2, 3})
      iex> {name, _rng} = Quacks.AI.Names.pick(Quacks.AI.Names.all() -- ["Ulric"], rng)
      iex> name
      "Ulric"
      iex> {name, _rng} = Quacks.AI.Names.pick(["Bot 1" | Quacks.AI.Names.all()], rng)
      iex> name
      "Bot 2"
  """
  @spec pick([String.t()], :rand.state()) :: {String.t(), :rand.state()}
  def pick(taken, rng) do
    case @names -- taken do
      [] ->
        {Enum.find(Stream.map(Stream.iterate(1, &(&1 + 1)), &"Bot #{&1}"), &(&1 not in taken)),
         rng}

      free ->
        {i, rng} = :rand.uniform_s(length(free), rng)
        {Enum.at(free, i - 1), rng}
    end
  end
end
