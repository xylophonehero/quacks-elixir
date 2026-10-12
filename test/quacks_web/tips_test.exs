defmodule QuacksWeb.TipsTest do
  @moduledoc "Round 38: the first-time hint picker, one table over the moments."
  use ExUnit.Case, async: true

  alias QuacksWeb.Tips

  @brew %{phase: :brew, white: 0, rats: 0, drawn: 0}
  @chain ["brew", "bag", "players"]

  # {moment, seen keys, the hint key or nil}
  @table [
    {%{phase: :none}, [], nil},
    {%{phase: :card}, [], "card"},
    {%{phase: :card}, ["card"], nil},
    {@brew, [], "brew"},
    {@brew, ["brew"], "bag"},
    {@brew, ["brew", "bag"], "players"},
    {@brew, @chain, nil},
    {%{@brew | drawn: 2, white: 2}, @chain, nil},
    {%{@brew | drawn: 2, white: 3}, @chain, "risk"},
    {%{@brew | drawn: 2, white: 3}, ["brew"], "bag"},
    {%{@brew | drawn: 2, white: 5}, ["risk" | @chain], nil},
    {%{@brew | rats: 2}, @chain, "rats"},
    {%{@brew | rats: 2}, [], "rats"},
    {%{@brew | rats: 2, drawn: 1}, @chain, nil},
    {%{@brew | rats: 2}, ["rats" | @chain], nil},
    {%{phase: :choice}, [], "choice"},
    {%{phase: :choice}, ["choice"], nil},
    {%{phase: :scoring}, [], "scoring"},
    {%{phase: :scoring}, ["scoring"], nil},
    {%{phase: :scored}, ["scoring"], "scored"},
    {%{phase: :scored}, ["scored"], nil},
    {%{phase: :shop}, [], "shop"},
    {%{phase: :shop}, ["shop"], nil}
  ]

  test "one hint per moment, each only once" do
    for {moment, seen, want} <- @table do
      got = Tips.pick(moment, MapSet.new(seen))
      assert (got && got.key) == want, "#{inspect(moment)} seen #{inspect(seen)}"
    end
  end

  test "every hint has a head, a text, a main button and a place" do
    for key <- Tips.keys() do
      tip = Tips.tip(key)
      assert tip.key == key
      assert tip.label != "" and tip.text != ""
      assert tip.button in ["Got it", "Next tip"]
      assert tip.place in [:bar, :pot]
    end
  end

  test "the scoring hint in Auto mode names no Next" do
    assert Tips.pick(%{phase: :scoring}, []).text =~ "Tap Next"
    refute Tips.pick(%{phase: :scoring, auto: true}, []).text =~ "Next"
  end

  test "the players hint stays generic, word for word" do
    assert Tips.tip("players").text ==
             "These are the players. Each tile shows their score and how their brew is going. Tap a tile for more."
  end

  test "the browser's state: version 1 only, known keys only" do
    assert Tips.from_browser(%{"v" => 1, "seen" => ["bag", "nope"], "off" => true}) ==
             %{seen: MapSet.new(["bag"]), off: true}

    assert Tips.from_browser(%{"v" => 2, "seen" => ["bag"]}) == %{seen: MapSet.new(), off: false}
    assert Tips.from_browser(nil) == %{seen: MapSet.new(), off: false}
    assert Tips.from_browser(%{"v" => 1, "seen" => "bag"}) == %{seen: MapSet.new(), off: false}

    assert Tips.to_browser(%{seen: MapSet.new(["brew", "bag"]), off: false}) ==
             %{v: 1, seen: ["bag", "brew"], off: false}
  end
end
