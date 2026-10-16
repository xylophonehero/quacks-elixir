defmodule Table.Generic.OracleTest do
  @moduledoc "Hearts played by `Hearts.Game`, written as generic ops on a mirror."
  use ExUnit.Case, async: true

  alias Table.Generic.{Game, Oracle, Spec}

  test "the first deal: every hand in the mirror, the deck empty" do
    {:ok, hearts, mirror, ops} = Oracle.start(%{players: 4}, {1, 2, 3})
    assert Oracle.agree?(hearts, mirror)
    assert mirror.zones["deck"].items == []
    assert Enum.count(ops, &match?({:move, _, "deck", _}, &1)) == 52
  end

  test "whole seeded games with 3, 4 and 5 players: the mirror agrees after every step" do
    for players <- 3..5, seed <- [{1, 2, 3}, {9, 9, 9}] do
      assert {:ok, steps, hearts, mirror} = Oracle.trace(%{players: players}, seed)
      assert Oracle.agree?(hearts, mirror)
      assert {:over, scores} = Hearts.Game.status(hearts)
      assert Game.status(mirror) == {:over, scores}
      assert Enum.any?(steps, &match?(%{action: {:pass, _}}, &1))
      assert Enum.all?(steps, &(&1.ops != [] or match?({:pass, _}, &1.action)))
    end
  end

  test "a play step: the card to the trick, then the next seat's prompt" do
    {:ok, hearts, mirror, _ops} = Oracle.start(%{players: 4}, {1, 2, 3})

    {hearts, mirror} =
      Enum.reduce(0..3, {hearts, mirror}, fn seat, {h, m} ->
        cards = Enum.take(h.hands[seat], 3)
        {:ok, h, m, _} = Oracle.step(h, m, seat, {:pass, cards})
        {h, m}
      end)

    seat = hearts.turn
    [card] = Hearts.Game.legal_cards(hearts, seat)
    {:ok, _hearts, mirror, ops} = Oracle.step(hearts, mirror, seat, {:play, card})
    id = Spec.card_id(card)

    assert [{:move, ^id, _, "trick"}, {:phase, "playing"}, {:turn, next}, {:ask, next, _, _}] =
             ops

    assert Game.status(mirror) == {:playing, [next]}
  end

  test "same_effect? compares results, not the order of ops" do
    {:ok, _hearts, mirror, _ops} = Oracle.start(%{players: 4}, {1, 2, 3})
    [a, b | _] = mirror.zones["hand:0"].items
    one = [{:move, a, "hand:0", "trick"}, {:move, b, "hand:0", "trick"}]
    two = Enum.reverse(one)
    assert Oracle.same_effect?(mirror, one, two)
    refute Oracle.same_effect?(mirror, one, tl(one))
    refute Oracle.same_effect?(mirror, one, [{:move, "nope", "hand:0", "trick"}])
  end
end
