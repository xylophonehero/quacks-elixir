defmodule CodexWeb.SetupLive do
  @moduledoc """
  `/games/codex/new`: start a Codex room. The first-game set-up is fixed
  (`Codex.Game.new/2`): P1 Bashing (Troq Bashar) against P2 Finesse (River
  Montoya). You play P1 against the bot (`Codex.Bot`), or both sides on this
  screen (hot-seat). Create makes the room (`Table.Server.create/3`) and opens
  it at `/games/codex/<code>`.
  """
  use QuacksWeb, :live_view

  alias Table.Server

  @key "codex"

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       page_title: "Codex: new sandbox",
       token: session["player_token"],
       form: to_form(%{"name" => "", "opponent" => "bot"}, as: :setup)
     )}
  end

  @impl true
  def handle_event("change", %{"setup" => params}, socket),
    do: {:noreply, assign(socket, form: to_form(params, as: :setup))}

  def handle_event("create", params, socket) do
    name = get_in(params, ["setup", "name"]) || ""
    bot? = get_in(params, ["setup", "opponent"]) != "hotseat"
    config = %{name: name, opts: %{bot: bot?}, bots: if(bot?, do: 1, else: 0)}

    case Server.create(@key, config, socket.assigns.token) do
      {:ok, code} ->
        {:noreply, push_navigate(socket, to: "/games/#{@key}/#{code}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create (#{inspect(reason)}).")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} full>
      <div class="min-h-dvh bg-stone-100 px-4 py-6 text-stone-900 sm:py-12">
        <div class="mx-auto flex max-w-xl flex-col gap-5">
          <header class="flex items-center gap-3">
            <.link
              navigate={~p"/games"}
              class="grid size-10 place-items-center rounded-full bg-white shadow-sm ring-1 ring-stone-900/10 transition hover:bg-stone-50"
              aria-label="Back to games"
            >
              <.icon name="hero-arrow-left" class="size-5" />
            </.link>
            <h1 class="text-2xl font-bold tracking-tight">Codex sandbox</h1>
          </header>

          <p class="text-stone-600">
            The first game of Codex: P1 plays Bashing (Troq Bashar), P2 plays Finesse
            (River Montoya). The table follows the rules; Free mode lets you move any card
            by hand.
          </p>

          <.form
            for={@form}
            id="codex-setup"
            phx-change="change"
            phx-submit="create"
            class="flex flex-col gap-5 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-stone-900/10 sm:p-6"
          >
            <ul class="grid gap-2 text-sm text-stone-700 sm:grid-cols-2">
              <li class="rounded-xl bg-rose-50 p-3 ring-1 ring-rose-200">
                <strong class="block text-rose-900">P1 · Bashing</strong>
                Troq Bashar, 4 workers, the neutral starting deck.
              </li>
              <li class="rounded-xl bg-sky-50 p-3 ring-1 ring-sky-200">
                <strong class="block text-sky-900">P2 · Finesse</strong>
                River Montoya, 5 workers, the neutral starting deck.
              </li>
            </ul>
            <fieldset class="flex flex-col gap-2">
              <legend class="mb-2 text-sm font-semibold">Opponent</legend>
              <div class="grid gap-2 sm:grid-cols-2">
                <label
                  :for={
                    {value, title, text} <- [
                      {"bot", "The bot", "You play P1; the bot plays P2."},
                      {"hotseat", "Hot-seat", "You play both sides on this screen."}
                    ]
                  }
                  for={"opponent-#{value}"}
                  class={[
                    "flex cursor-pointer flex-col gap-0.5 rounded-xl p-3 ring-1 transition active:scale-[0.99]",
                    if(@form[:opponent].value == value,
                      do: "bg-emerald-700 text-white ring-emerald-700",
                      else: "bg-white text-stone-800 ring-stone-300 hover:bg-stone-50"
                    )
                  ]}
                >
                  <input
                    type="radio"
                    id={"opponent-#{value}"}
                    name="setup[opponent]"
                    value={value}
                    checked={@form[:opponent].value == value}
                    class="sr-only"
                  />
                  <span class="font-semibold">{title}</span>
                  <span class="text-sm opacity-80">{text}</span>
                </label>
              </div>
            </fieldset>
            <.input
              field={@form[:name]}
              label="Your name (optional)"
              placeholder="Player 1"
              maxlength="20"
              autocomplete="nickname"
              class="w-full rounded-lg border border-stone-300 px-3 py-2"
            />
            <button
              id="codex-create"
              type="submit"
              class="rounded-xl bg-emerald-700 px-4 py-3 text-lg font-semibold text-white shadow-sm transition hover:bg-emerald-600 active:scale-[0.98]"
            >
              Open the table
            </button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
