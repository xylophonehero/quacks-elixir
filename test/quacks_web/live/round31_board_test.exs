defmodule QuacksWeb.Round31BoardTest do
  @moduledoc """
  Round 31 (board): the 💥 burst for an explosion, and the draw flight from the bag to the pot.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.Game
  alias QuacksWeb.Icons

  describe "the 💥 burst" do
    test "the explosion symbol is our layered burst, not explosion-rays" do
      sprite = render_component(&Icons.sprite/1, %{})
      [symbol] = Regex.run(~r{<symbol id="icon-explosion".*?</symbol>}s, sprite)

      for colour <- ~w(#d6322c #f28a1e #ffd94a), do: assert(symbol =~ colour)
      assert length(Regex.scan(~r/<path/, symbol)) == 3
    end
  end

  describe "the draw flight" do
    test "only your own large pot is marked for PotMotion's bag-to-pot flight" do
      game = Game.new(seed: {1, 2, 3})
      seat = game.players |> Map.keys() |> Enum.min()

      pot = fn opts ->
        render_component(&QuacksWeb.PotComponents.pot/1, [game: game, seat: seat] ++ opts)
      end

      assert pot.(flask: :full) =~ ~s(data-mine="true")
      refute pot.([]) =~ "data-mine"
      refute pot.(size: :sm, flask: :full) =~ "data-mine"
    end

    test "app.js flies one new chip from the bag, with no flight under reduced motion" do
      js = File.read!("assets/js/app.js")

      assert js =~ "this.el.dataset.mine && this.bag()) this.fly(added[0])"
      assert js =~ ~r/fly\(chip[^{]*\{\n\s+if \(reduced\(\)\) return/
    end
  end
end
