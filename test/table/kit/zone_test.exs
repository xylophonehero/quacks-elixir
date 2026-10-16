defmodule Table.Kit.ZoneTest do
  use ExUnit.Case, async: true

  alias Table.Kit.Zone

  doctest Zone

  test "public zones show every viewer the items" do
    zone = Zone.new([:a, :b])
    assert Zone.view(zone, nil) == zone and Zone.view(zone, 3) == zone
  end

  test "hidden zones hide the items even from the owner, but keep the count" do
    zone = Zone.new([:a, :b], owner: 0, visibility: :hidden)
    assert Zone.view(zone, 0).items == [:hidden, :hidden]
    assert Zone.size(Zone.view(zone, 0)) == 2
  end

  test "bad options raise" do
    assert_raise ArgumentError, fn -> Zone.new([], visibility: :secret) end
    assert_raise ArgumentError, fn -> Zone.new([], visibility: :owner) end
  end
end
