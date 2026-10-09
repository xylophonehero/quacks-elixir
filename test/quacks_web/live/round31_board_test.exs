defmodule QuacksWeb.Round31BoardTest do
  @moduledoc """
  Round 31 (board): the 💥 burst for an explosion, the board numbers and the
  VP crown, and the draw flight from the bag to the pot.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias QuacksWeb.Icons

  describe "the 💥 burst" do
    test "the explosion symbol is our layered burst, not explosion-rays" do
      sprite = render_component(&Icons.sprite/1, %{})
      [symbol] = Regex.run(~r{<symbol id="icon-explosion".*?</symbol>}s, sprite)

      for colour <- ~w(#d6322c #f28a1e #ffd94a), do: assert(symbol =~ colour)
      assert length(Regex.scan(~r/<path/, symbol)) == 3
    end
  end
end
