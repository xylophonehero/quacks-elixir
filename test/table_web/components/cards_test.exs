defmodule TableWeb.Components.CardsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TableWeb.Components.{Cards, HeartsTable, Theme}
  alias TableWeb.Gallery.Hearts

  defp doc(html), do: LazyHTML.from_fragment(html)
  defp count(doc, sel), do: doc |> LazyHTML.query(sel) |> Enum.count()
  defp attrs(doc, sel, name), do: doc |> LazyHTML.query(sel) |> LazyHTML.attribute(name)

  test "the deck has 52 different cards and each code reads back" do
    deck = Cards.deck()
    assert length(deck) == 52
    assert deck |> Enum.map(&Cards.code/1) |> Enum.uniq() |> length() == 52
    for c <- deck, do: assert(Cards.parse(Cards.code(c)) == c)
    assert Cards.code({10, :hearts}) == "10H"
    assert Cards.code({12, :spades}) == "QS"
    assert Cards.parse("1X") == nil
    assert Cards.name({12, :spades}) == "queen of spades"
  end

  test "a card shows its suit, its code and its rank twice" do
    html = render_component(&Cards.card/1, card: {10, :diamonds}, id: "t-card-10D") |> doc()
    assert attrs(html, ".tb-card", "data-suit") == ["diamonds"]
    assert attrs(html, ".tb-card", "data-flip") == ["card"]
    assert count(html, "text.tb-rank") == 2
  end

  test "a hand: the illegal cards are disabled, the ids hold the card codes" do
    cards = [{2, :clubs}, {9, :clubs}, {4, :hearts}]

    html =
      render_component(&Cards.hand/1,
        id: "t-hand-s",
        scope: "t",
        cards: cards,
        legal: [{2, :clubs}, {9, :clubs}],
        on_tap: "play",
        motion: %{{4, :hearts} => %{from: "t-deck", delay: 56}}
      )
      |> doc()

    assert count(html, "button.tb-card") == 3
    assert attrs(html, "button[disabled]", "id") == ["t-card-4H"]
    assert attrs(html, "button[data-state=legal]", "phx-value-card") == ["2C", "9C"]
    assert attrs(html, "#t-card-4H", "data-from") == ["t-deck"]
    assert attrs(html, "#t-card-4H", "data-flip-delay") == ["56"]
  end

  test "a hand with no tap has no buttons" do
    html = render_component(&Cards.hand/1, id: "h", scope: "t", cards: [{2, :clubs}]) |> doc()
    assert count(html, "button") == 0
    assert count(html, "div.tb-card") == 1
  end

  test "the trick puts each card in its seat's slot and marks the winner" do
    plays = [{:w, {3, :clubs}}, {:n, {11, :clubs}}, {:s, {2, :clubs}}, {:e, {6, :clubs}}]
    html = render_component(&Cards.trick/1, id: "t-trick", scope: "t", plays: plays, winner: :n)
    html = doc(html)
    assert attrs(html, "[data-seat=n] .tb-card", "id") == ["t-card-JC"]
    assert attrs(html, "[data-state=won]", "data-card") == ["JC"]
    assert attrs(html, ".tb-trick", "data-lead") == ["w"]
    assert count(html, ".tb-slot[data-empty]") == 0
  end

  test "the table has the hook, the seats' hands and piles" do
    t = Hearts.state("play", tap: true)

    html =
      render_component(&HeartsTable.table/1, Map.merge(Map.delete(t, :east), %{id: "t"}))
      |> doc()

    assert attrs(html, "#t", "phx-hook") == ["TableMotion"]
    assert count(html, "#t-fx[phx-update=ignore]") == 1
    assert count(html, "#t-hand-n .tb-card") == 12
    assert count(html, "#t-hand-s button.tb-card") == 13
    assert count(html, "#t-pile-n[data-count='4']") == 1
  end

  test "the theme root and picker: every theme, the hook only with remember" do
    root = render_component(&Theme.root/1, id: "r", inner_block: []) |> doc()
    assert attrs(root, "#r", "data-theme") == [Theme.default()]
    assert attrs(root, "#r", "phx-hook") == []

    root = render_component(&Theme.root/1, id: "r", remember: true, inner_block: []) |> doc()
    assert attrs(root, "#r", "phx-hook") == ["TableTheme"]

    picker = render_component(&Theme.picker/1, id: "p", theme: "nord") |> doc()
    assert attrs(picker, "[data-pick-theme]", "data-pick-theme") == Theme.ids()
    assert attrs(picker, "[aria-pressed=true][data-pick-theme]", "data-pick-theme") == ["nord"]
  end

  describe "the motion fixtures" do
    test "the deal sends every card from the deck, in deal order" do
      {before, aft} = Hearts.motion("deal")
      assert before.deck == 52
      assert map_size(aft.motion.hand) == 13
      assert Enum.all?(aft.motion.backs, fn {_seat, m} -> map_size(m) == 13 end)
      delays = for {_c, m} <- aft.motion.hand, do: m.delay
      assert Enum.uniq(delays) == delays
    end

    test "a pass gives 3 cards and gets 3 new ones" do
      for dir <- ~w(left right across) do
        {before, aft} = Hearts.motion("pass-" <> dir)
        assert length(before.selected) == 3
        assert length(aft.hand) == 13
        assert length(aft.new) == 3
        assert map_size(before.motion.hand) == 3
      end
    end

    test "the trick goes to the winner's pile" do
      {before, aft} = Hearts.motion("collect")
      assert length(before.plays) == 4
      assert aft.plays == []
      assert aft.seats[before.winner].taken == before.seats[before.winner].taken + 4
    end
  end
end
