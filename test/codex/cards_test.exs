defmodule Codex.CardsTest do
  use ExUnit.Case, async: true

  alias Codex.Cards

  test "the first slice: 10 starters, 12 codex cards per spec, the 2 heroes" do
    assert length(Cards.starter()) == 10
    assert length(Cards.codex("Bashing")) == 12
    assert length(Cards.codex("Finesse")) == 12
    assert Cards.hero("Bashing") == "troq-bashar"
    assert Cards.hero("Finesse") == "river-montoya"
    assert Cards.max_level("troq-bashar") == 8
    assert Cards.max_level("timely-messenger") == nil
  end

  test "hero bands" do
    assert %{level: 1, atk: 2, hp: 3} = Cards.band("troq-bashar", 4)
    assert %{level: 5, atk: 3, hp: 4} = Cards.band("troq-bashar", 7)
    assert %{level: 8, atk: 4, hp: 5, text: [_]} = Cards.band("troq-bashar", 8)
  end

  test "card fields from the data" do
    assert %{name: "Brick Thief", type: "Unit", cost: 2, atk: 2, hp: 1, tech: 0, text: [_, _]} =
             Cards.get("brick-thief")

    assert Cards.slug("Star-Crossed Starlet") == "star-crossed-starlet"
    assert Cards.slug("Heroes' Hall") == "heroes-hall"
  end

  test "mix codex.cards crops every card of the first slice" do
    cropped = Map.values(Mix.Tasks.Codex.Cards.sheet())
    assert Enum.all?(cropped, &Cards.get/1)

    needed =
      Cards.starter() ++
        Cards.codex("Bashing") ++
        Cards.codex("Finesse") ++ ["troq-bashar", "river-montoya", "worker-x4", "worker-x5"]

    assert needed -- cropped == []
    assert length(Enum.uniq(cropped)) == length(cropped)
  end

  test "mix codex.cards crops every Red and Green card, hero and token" do
    cropped =
      for {_name, map} <- Mix.Tasks.Codex.Cards.sheets(), slug <- Map.values(map), do: slug

    assert Enum.all?(cropped, &Cards.get/1), inspect(Enum.reject(cropped, &Cards.get/1))

    needed =
      for color <- ~w(Red Green),
          slug <-
            Cards.starter(color) ++
              Enum.flat_map(Cards.specs(color), &[Cards.hero(&1) | Cards.codex(&1)]),
          do: slug

    assert needed -- cropped == []
    assert ~w(shark pirate wisp frog beast squirrel hunter water-elemental) -- cropped == []
  end
end
