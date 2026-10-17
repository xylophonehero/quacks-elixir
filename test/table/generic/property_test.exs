defmodule Table.Generic.PropertyTest do
  @moduledoc """
  Random op sequences on a bare table (no referee): the invariants of the engine.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Table.Generic.Game
  alias Table.Kit.Zone

  defp seed, do: tuple({integer(1..100_000), integer(1..100_000), integer(1..100_000)})

  defp table do
    gen all(
          spec <- member_of(["crazy_eights", "go_fish"]),
          players <- integer(2..5),
          seed <- seed()
        ) do
      {:ok, game} = Game.new(%{spec: spec, players: players, referee: nil}, seed)
      game
    end
  end

  # An op on the game's own zones and counters; valid or not.
  defp op(game) do
    zones = Map.keys(game.zones)
    cards = game.spec.cards
    counters = Map.keys(game.counters)

    one_of([
      tuple(
        {constant(:move),
         one_of([member_of(cards), map(integer(1..4), &{:top, &1}), constant(:all)]),
         member_of(zones), member_of(zones)}
      ),
      tuple({constant(:shuffle), member_of(zones)}),
      tuple(
        {constant(:deal), integer(1..3), member_of(zones),
         list_of(member_of(zones), min_length: 1, max_length: 3)}
      ),
      tuple({constant(:flip), member_of(zones), member_of([:public, :owner, :hidden])}),
      tuple({constant(:set), member_of(counters), one_of([integer(-5..5), constant("x")])}),
      tuple({constant(:add), member_of(["nope" | counters]), integer(-3..3)}),
      tuple({constant(:turn), integer(0..6)}),
      tuple({constant(:phase), member_of(["a", "b"])}),
      tuple(
        {constant(:ask), integer(0..5), constant("?"),
         list_of(
           one_of([
             member_of(["x", "y"]),
             tuple({constant(:card), member_of(zones), member_of(cards)})
           ]),
           max_length: 3
         )}
      )
    ])
  end

  defp ops(game), do: list_of(op(game), max_length: 40)

  defp run(game, ops) do
    Enum.reduce(ops, {game, []}, fn op, {game, trace} ->
      case Game.apply_ops(game, [op]) do
        {:ok, next} -> {next, [{:ok, game, next} | trace]}
        {:error, _} -> {game, [{:error, game, op} | trace]}
      end
    end)
  end

  property "every card stays in exactly one zone; an invalid op changes nothing" do
    check all(game <- table(), ops <- ops(game), max_runs: 150) do
      deck = Enum.sort(game.spec.cards)
      {last, trace} = run(game, ops)

      for {result, before, x} <- trace do
        case result do
          :ok -> assert Enum.sort(Game.all_cards(x)) == deck
          :error -> assert Game.apply_ops(before, [x]) |> elem(0) == :error
        end
      end

      assert Enum.sort(Game.all_cards(last)) == deck
    end
  end

  property "replay of the op log gives the same state" do
    check all(game <- table(), ops <- ops(game), max_runs: 150) do
      {last, _} = run(game, ops)
      assert Game.replay(last.opts, last.seed, last.log) == {:ok, last}
    end
  end

  property "a view never shows a card that the viewer could not see" do
    check all(game <- table(), ops <- ops(game), max_runs: 150) do
      viewers = [:spectator | game.seats]
      # The cards each viewer has seen at some time: in a zone it could see.
      seen = Map.new(viewers, &{&1, visible_cards(game, &1)})

      {last, seen} =
        Enum.reduce(ops, {game, seen}, fn op, {game, seen} ->
          case Game.apply_ops(game, [op]) do
            {:ok, next} ->
              {next,
               Map.new(seen, fn {v, cards} -> {v, MapSet.union(cards, visible_cards(next, v))} end)}

            {:error, _} ->
              {game, seen}
          end
        end)

      for viewer <- viewers do
        view = Game.view(last, viewer)
        shown = MapSet.new(terms(view) |> Enum.filter(&(&1 in last.spec.cards)))
        never = MapSet.difference(shown, seen[viewer])
        assert MapSet.size(never) == 0, "#{inspect(viewer)} sees #{inspect(never)}"

        for {id, z} <- last.zones,
            not Zone.visible?(z, viewer),
            do: assert(Enum.all?(view.zones[id].items, &(&1 == :hidden)))
      end
    end
  end

  defp visible_cards(game, viewer) do
    for {_, z} <- game.zones, Zone.visible?(z, viewer), c <- z.items, into: MapSet.new(), do: c
  end

  # Every string in a term (deep), but not the spec names map's keys: `names`
  # holds only the cards that show, so it is in the check too.
  defp terms(t) when is_binary(t), do: [t]
  defp terms(t) when is_tuple(t), do: t |> Tuple.to_list() |> Enum.flat_map(&terms/1)
  defp terms(t) when is_list(t), do: Enum.flat_map(t, &terms/1)
  defp terms(%_{} = t), do: t |> Map.from_struct() |> terms()
  defp terms(t) when is_map(t), do: Enum.flat_map(t, fn {k, v} -> terms(k) ++ terms(v) end)
  defp terms(_t), do: []
end
