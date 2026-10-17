defmodule TableWeb.GenericSetupLive do
  @moduledoc """
  `/games/generic/new?spec=<name>`: set up a room of a generic card game (a spec
  of `Table.Generic.Spec.fixtures/0` that has a referee). Your name, the
  players and how many seats are bots. Create makes the room
  (`Table.Server.create/3`, you get seat 0) and opens `/games/generic/<code>`.
  """
  use QuacksWeb, :live_view

  alias Table.Generic.{Referee, Spec}
  alias Table.Server

  @impl true
  def mount(params, session, socket) do
    case playable(params["spec"] || "crazy_eights") do
      nil ->
        {:ok, socket |> put_flash(:error, "No such game.") |> push_navigate(to: ~p"/games")}

      spec ->
        players = spec.players.first + 1
        form = %{"name" => "", "players" => "#{players}", "bots" => "#{players - 1}"}

        {:ok,
         assign(socket,
           page_title: "#{spec.title}: new game",
           token: session["player_token"],
           spec: spec,
           params: form,
           form: to_form(form, as: :setup)
         )}
    end
  end

  defp playable(name) do
    with {:ok, spec} <- Spec.normalise(name),
         true <- Referee.for(spec.referee) != nil do
      spec
    else
      _ -> nil
    end
  end

  @impl true
  def handle_event("change", %{"setup" => params}, socket) do
    old = socket.assigns.params
    params = Map.merge(old, params)
    n = players(params, socket.assigns.spec)
    all_but_you? = int(old["bots"], 0) == int(old["players"], n) - 1
    bots = if all_but_you?, do: n - 1, else: min(int(params["bots"], 0), n - 1)
    params = Map.put(params, "bots", "#{bots}")
    {:noreply, assign(socket, params: params, form: to_form(params, as: :setup))}
  end

  def handle_event("create", %{"setup" => params}, socket) do
    %{spec: spec, token: token} = socket.assigns
    params = Map.merge(socket.assigns.params, params)
    n = players(params, spec)

    config = %{
      name: params["name"],
      bots: params["bots"] |> int(n - 1) |> max(0) |> min(n - 1),
      level: :random,
      opts: %{spec: spec.name, players: n}
    }

    case Server.create("generic", config, token) do
      {:ok, code} ->
        {:noreply, push_navigate(socket, to: "/games/generic/#{code}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create (#{inspect(reason)}).")}
    end
  end

  defp players(params, spec) do
    params["players"]
    |> int(spec.players.first)
    |> max(spec.players.first)
    |> min(spec.players.last)
  end

  defp int(value, default) do
    case Integer.parse(to_string(value)) do
      {n, ""} -> n
      _ -> default
    end
  end

  @impl true
  def render(assigns) do
    players = players(assigns.params, assigns.spec)
    bots = int(assigns.params["bots"], players - 1)
    assigns = assign(assigns, players: players, bots: bots)

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
            <h1 class="text-2xl font-bold tracking-tight">{@spec.title}</h1>
          </header>

          <.form
            for={@form}
            id="generic-setup"
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
              <legend class="mb-2 text-sm font-semibold">Players</legend>
              <div class="flex flex-wrap gap-2">
                <.choice
                  :for={n <- @spec.players}
                  id={"players-#{n}"}
                  name="setup[players]"
                  value={n}
                  checked={@players == n}
                  label={"#{n}"}
                />
              </div>
            </fieldset>

            <fieldset class="flex flex-col gap-2">
              <legend class="mb-2 text-sm font-semibold">Bots</legend>
              <div class="flex flex-wrap gap-2">
                <.choice
                  :for={n <- 0..(@players - 1)}
                  id={"bots-#{n}"}
                  name="setup[bots]"
                  value={n}
                  checked={@bots == n}
                  label={"#{n}"}
                />
              </div>
              <p id="seats-note" class="text-sm text-stone-600">
                {seats_note(@players, @bots)}
              </p>
            </fieldset>

            <p class="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-900 ring-1 ring-amber-200">
              A generic table: the rules run as operations on zones and counters.
            </p>

            <button
              id="generic-create"
              type="submit"
              class="rounded-xl bg-emerald-700 px-4 py-3 text-lg font-semibold text-white shadow-sm transition hover:bg-emerald-600 active:scale-[0.98]"
            >
              Create game
            </button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp seats_note(_players, bots) when bots == 0, do: "No bots: share the link with friends."

  defp seats_note(players, bots) when players - 1 == bots,
    do: "You and #{bots} bots. The game starts at once."

  defp seats_note(players, bots),
    do: "You, #{bots} bots and #{players - 1 - bots} open seats: share the link."

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :any, required: true
  attr :checked, :boolean, default: false
  attr :label, :string, required: true

  defp choice(assigns) do
    ~H"""
    <label
      for={@id}
      class={[
        "flex min-w-12 cursor-pointer items-center justify-center rounded-lg px-3 py-2 text-lg font-semibold ring-1 transition active:scale-[0.97]",
        if(@checked,
          do: "bg-emerald-700 text-white ring-emerald-700",
          else: "bg-white text-stone-800 ring-stone-300 hover:bg-stone-50"
        )
      ]}
    >
      <input type="radio" id={@id} name={@name} value={@value} checked={@checked} class="sr-only" />
      {@label}
    </label>
    """
  end
end
