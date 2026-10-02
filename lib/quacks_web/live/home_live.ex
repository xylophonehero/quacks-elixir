defmodule QuacksWeb.HomeLive do
  @moduledoc "Placeholder page. Game UI comes later."
  use QuacksWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-3xl font-bold">Quacks</h1>
    </Layouts.app>
    """
  end
end
