defmodule TableWeb.GamesLive do
  @moduledoc """
  `/games`: pick a game. Quacks opens its own lobby (`/`); a table game opens
  its set-up page (`Table.games/0`). A room code field joins a table game's room.
  """
  use QuacksWeb, :live_view

  alias Table.Server

  @impl true
  def mount(_params, _session, socket) do
    games =
      Table.games() |> Enum.sort() |> Enum.map(fn {key, game} -> Map.put(game, :key, key) end)

    {:ok,
     assign(socket,
       page_title: "Games",
       games: games,
       form: to_form(%{"code" => ""}, as: :join)
     )}
  end

  @impl true
  def handle_event("join", %{"join" => %{"code" => code}}, socket) do
    code = code |> String.trim() |> String.upcase()

    case Server.find(code) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "No game with the code #{code}.")
         |> assign(form: to_form(%{"code" => code}, as: :join))}

      key ->
        {:noreply, push_navigate(socket, to: "/games/#{key}/#{code}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} full>
      <div class="min-h-dvh bg-stone-100 px-4 py-8 text-stone-900 sm:py-14">
        <div class="mx-auto flex max-w-xl flex-col gap-6">
          <header class="flex flex-col gap-1">
            <h1 class="text-3xl font-bold tracking-tight">Games</h1>
            <p class="text-stone-600">Pick a game, or join a room with its code.</p>
          </header>

          <ul id="game-list" class="flex flex-col gap-3">
            <li>
              <.link
                id="pick-quacks"
                navigate={~p"/"}
                class="group flex items-center gap-4 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-stone-900/10 transition hover:-translate-y-0.5 hover:shadow-md active:translate-y-0"
              >
                <span class="grid size-14 shrink-0 place-items-center rounded-xl bg-amber-100 text-3xl">
                  🧪
                </span>
                <span class="flex min-w-0 flex-col">
                  <span class="text-lg font-semibold">The Quacks of Quedlinburg</span>
                  <span class="text-sm text-stone-600">
                    Brew potions, push your luck. 1 to 8 players.
                  </span>
                </span>
                <.icon
                  name="hero-chevron-right"
                  class="ml-auto size-5 shrink-0 text-stone-400 transition group-hover:translate-x-0.5"
                />
              </.link>
            </li>
            <li :for={g <- @games}>
              <.link
                id={"pick-#{g.key}"}
                navigate={g.setup}
                class="group flex items-center gap-4 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-stone-900/10 transition hover:-translate-y-0.5 hover:shadow-md active:translate-y-0"
              >
                <span class="grid size-14 shrink-0 place-items-center rounded-xl bg-emerald-100 text-3xl text-red-600">
                  ♥
                </span>
                <span class="flex min-w-0 flex-col">
                  <span class="text-lg font-semibold">{g.name}</span>
                  <span class="text-sm text-stone-600">{g.blurb}</span>
                </span>
                <.icon
                  name="hero-chevron-right"
                  class="ml-auto size-5 shrink-0 text-stone-400 transition group-hover:translate-x-0.5"
                />
              </.link>
            </li>
          </ul>

          <.form
            for={@form}
            id="join-form"
            phx-submit="join"
            class="flex items-end gap-2 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-stone-900/10"
          >
            <div class="min-w-0 flex-1">
              <.input
                field={@form[:code]}
                label="Room code"
                placeholder="ABCDE"
                autocomplete="off"
                class="w-full rounded-lg border border-stone-300 px-3 py-2 font-mono uppercase tracking-widest"
              />
            </div>
            <button
              id="join-submit"
              type="submit"
              class="mb-2 rounded-lg bg-stone-900 px-4 py-2 font-semibold text-white transition hover:bg-stone-700 active:scale-[0.97]"
            >
              Join
            </button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
