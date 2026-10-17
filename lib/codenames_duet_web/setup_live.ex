defmodule CodenamesDuetWeb.SetupLive do
  @moduledoc """
  `/games/codenames_duet/new`: set up a Codenames Duet room. Your name, your
  partner (a friend, or a bot: `CodenamesDuet.AI.Vectors`) and the timer tokens
  (`CodenamesDuet.Game.defaults/0`, 1 to 11; more tokens make the game easier,
  rulebook §1.5). Create makes the room (`Table.Server.create/3`, you get seat 0)
  and opens it at `/games/codenames_duet/<code>`. With a friend, the code and the
  invite link show until your friend joins; with a bot, the game starts at once.
  """
  use QuacksWeb, :live_view

  alias CodenamesDuet.Game
  alias Table.Server

  @key "codenames_duet"
  @timers 1..11

  @impl true
  def mount(_params, session, socket) do
    params = %{"name" => "", "partner" => "friend", "timer" => to_string(Game.defaults().timer)}

    {:ok,
     assign(socket,
       page_title: "Codenames Duet: new game",
       token: session["player_token"],
       params: params,
       form: to_form(params, as: :setup)
     )}
  end

  @impl true
  def handle_event("change", %{"setup" => params}, socket) do
    params = Map.merge(socket.assigns.params, params)
    {:noreply, assign(socket, params: params, form: to_form(params, as: :setup))}
  end

  def handle_event("create", %{"setup" => params}, socket) do
    params = Map.merge(socket.assigns.params, params)

    case Server.create(@key, config(params), socket.assigns.token) do
      {:ok, code} ->
        {:noreply, push_navigate(socket, to: "/games/#{@key}/#{code}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create (#{inspect(reason)}).")}
    end
  end

  defp config(%{"partner" => "bot"} = params),
    do: %{name: params["name"], opts: %{timer: timer(params)}, bots: 1, level: :vectors}

  defp config(params), do: %{name: params["name"], opts: %{timer: timer(params)}}

  defp timer(params) do
    default = Game.defaults().timer

    case Integer.parse(to_string(params["timer"])) do
      {n, ""} -> if n in @timers, do: n, else: default
      _ -> default
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        timer: timer(assigns.params),
        timers: @timers,
        bot?: assigns.params["partner"] == "bot"
      )

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
            <h1 class="text-2xl font-bold tracking-tight">Codenames Duet</h1>
          </header>

          <p class="text-stone-600">
            A game for 2. You each see your own side of the key. Take turns to give a
            one-word clue; your partner touches the words. Find all 15 agents together,
            and do not touch an assassin.
          </p>

          <.form
            for={@form}
            id="duet-setup"
            phx-change="change"
            phx-submit="create"
            class="flex flex-col gap-5 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-stone-900/10 sm:p-6"
          >
            <.input
              field={@form[:name]}
              label="Your name"
              placeholder="Player 1"
              maxlength="20"
              autocomplete="nickname"
              class="w-full rounded-lg border border-stone-300 px-3 py-2"
            />

            <fieldset class="flex flex-col gap-2">
              <legend class="mb-2 text-sm font-semibold">Partner</legend>
              <div class="grid grid-cols-2 gap-2">
                <label
                  :for={{value, title, note, icon} <- partners()}
                  for={"partner-#{value}"}
                  class={[
                    "flex cursor-pointer items-center gap-3 rounded-xl px-3 py-2.5 ring-1 transition active:scale-[0.98]",
                    if(@params["partner"] == value,
                      do: "bg-emerald-700 text-white ring-emerald-700",
                      else: "bg-white text-stone-800 ring-stone-300 hover:bg-stone-50"
                    )
                  ]}
                >
                  <input
                    type="radio"
                    id={"partner-#{value}"}
                    name="setup[partner]"
                    value={value}
                    checked={@params["partner"] == value}
                    class="sr-only"
                  />
                  <.icon name={icon} class="size-6 shrink-0" />
                  <span class="flex flex-col leading-tight">
                    <span class="font-semibold">{title}</span>
                    <span class="text-xs opacity-80">{note}</span>
                  </span>
                </label>
              </div>
            </fieldset>

            <fieldset class="flex flex-col gap-2">
              <legend class="mb-2 text-sm font-semibold">Timer tokens (turns)</legend>
              <div class="grid grid-cols-6 gap-2 sm:grid-cols-11">
                <label
                  :for={n <- @timers}
                  for={"timer-#{n}"}
                  class={[
                    "flex cursor-pointer items-center justify-center rounded-lg py-2 text-lg font-semibold tabular-nums ring-1 transition active:scale-[0.97]",
                    if(@timer == n,
                      do: "bg-emerald-700 text-white ring-emerald-700",
                      else: "bg-white text-stone-800 ring-stone-300 hover:bg-stone-50"
                    )
                  ]}
                >
                  <input
                    type="radio"
                    id={"timer-#{n}"}
                    name="setup[timer]"
                    value={n}
                    checked={@timer == n}
                    class="sr-only"
                  />
                  {n}
                </label>
              </div>
              <p id="timer-note" class="text-sm text-stone-600">{timer_note(@timer)}</p>
            </fieldset>

            <button
              id="duet-create"
              type="submit"
              class="rounded-xl bg-emerald-700 px-4 py-3 text-lg font-semibold text-white shadow-sm transition hover:bg-emerald-600 active:scale-[0.98]"
            >
              Create game
            </button>
            <p id="create-note" class="-mt-2 text-sm text-stone-600">
              <%= if @bot? do %>
                The game starts at once. The bot reads word links from
                <a
                  href="https://github.com/commonsense/conceptnet-numberbatch"
                  class="underline hover:text-stone-900"
                >ConceptNet Numberbatch</a>
                (<a
                  href="https://creativecommons.org/licenses/by-sa/4.0/"
                  class="underline hover:text-stone-900"
                >CC BY-SA 4.0</a>).
              <% else %>
                You get a code and a link to send to your partner.
              <% end %>
            </p>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp partners,
    do: [
      {"friend", "A friend", "Send a link", "hero-user-plus"},
      {"bot", "A bot", "Play now", "hero-cpu-chip"}
    ]

  defp timer_note(9), do: "9 is the standard game."
  defp timer_note(n) when n > 9, do: "#{n} turns: easier than the standard 9."
  defp timer_note(n), do: "#{n} turns: harder than the standard 9."
end
