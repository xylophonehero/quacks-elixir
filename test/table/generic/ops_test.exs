defmodule Table.Generic.OpsTest do
  use ExUnit.Case, async: true

  alias Table.Generic.Ops

  doctest Ops

  @ops [
    {:move, "QS", "hand:0", "discard"},
    {:move, {:top, 2}, "deck", "hand:1"},
    {:move, :all, "trick", "taken:3"},
    {:shuffle, "deck"},
    {:deal, 5, "deck", ["hand:0", "hand:1"]},
    {:flip, "discard", :hidden},
    {:set, "suit", "hearts"},
    {:set, "score:0", 12},
    {:add, "passes", -1},
    {:turn, 2},
    {:phase, "choose_suit"},
    {:ask, 0, "Pick", ["draw", {:card, "hand:0", "7H"}]},
    {:end, %{0 => 10, 1 => 0}}
  ]

  test "encode and decode are inverse, also through JSON text" do
    for op <- @ops do
      json = op |> Ops.encode() |> Jason.encode!() |> Jason.decode!()
      assert Ops.decode_op(json) == {:ok, op}
    end

    assert Ops.decode(%{"ops" => Enum.map(@ops, &Ops.encode/1)}) == {:ok, @ops}
  end

  test "every encoded op fits one variant of the schema" do
    variants = Ops.schema()["properties"]["ops"]["items"]["anyOf"]

    for op <- @ops do
      json = Ops.encode(op)

      assert Enum.any?(variants, fn v ->
               v["properties"]["op"]["const"] == json["op"] and
                 Enum.sort(Map.keys(json)) == Enum.sort(v["required"]) and
                 Map.keys(json) -- Map.keys(v["properties"]) == []
             end),
             "no schema variant for #{inspect(json)}"
    end
  end

  test "bad shapes are errors that name the op" do
    assert Ops.decode([%{"op" => "shuffle", "zone" => "deck"}, %{"op" => "move", "from" => "a"}]) ==
             {:error, {1, :bad_fields}}

    assert {:error, {0, :bad_card_ref}} =
             Ops.decode([%{"op" => "move", "top" => 0, "from" => "a", "to" => "b"}])

    assert {:error, {0, {:unknown_keys, ["extra"]}}} =
             Ops.decode([%{"op" => "turn", "seat" => 1, "extra" => true}])

    assert {:error, {0, :bad_visibility}} =
             Ops.decode([%{"op" => "flip", "zone" => "a", "visibility" => "secret"}])

    assert {:error, {0, :bad_scores}} =
             Ops.decode([%{"op" => "end", "scores" => [%{"seat" => "0", "score" => 1}]}])

    assert {:error, {0, :bad_options}} =
             Ops.decode([%{"op" => "ask", "seat" => 0, "prompt" => "?", "choices" => [1]}])

    assert Ops.decode("move") == {:error, :not_a_list}
    assert Ops.decode([42]) == {:error, {0, :not_an_op}}
  end
end
