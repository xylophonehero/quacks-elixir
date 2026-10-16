defmodule HeartsWeb.SetupLive do
  @moduledoc """
  `/games/hearts/new`: set up a Hearts room. Your name, the players (3 to 5), how
  many seats are bots (all but you by default), the bots' level, and the main
  options of `Hearts.Game.defaults/0` (game end, shooting the moon, J♦).
  Create makes the room (`Table.Server.create/3`, you get seat 0) and opens it
  at `/games/hearts/<code>`. Free seats are for friends: they join by the link
  or the code.
  """
  use QuacksWeb, :live_view

  alias Hearts.Game
  alias Table.Server

  @targets [50, 75, 100, 150]

  @impl true
  def mount(_params, session, socket) do
    params = %{
      "name" => "",
      "players" => "4",
      "bots" => "3",
      "level" => "heuristic",
      "target" => to_string(Game.defaults().target),
      "moon" => to_string(Game.defaults().moon),
      "jack_of_diamonds" => to_string(Game.defaults().jack_of_diamonds)
    }

    {:ok,
     assign(socket,
       page_title: "Hearts: new game",
       token: session["player_token"],
       params: params,
       form: to_form(params, as: :setup)
     )}
  end

  @impl true
  def handle_event("change", %{"setup" => params}, socket) do
    params = socket.assigns.params |> Map.merge(params) |> fit_bots(socket.assigns.params)
    {:noreply, assign(socket, params: params, form: to_form(params, as: :setup))}
  end

  def handle_event("create", %{"setup" => params}, socket) do
    params = Map.merge(socket.assigns.params, params)

    case Server.create("hearts", config(params), socket.assigns.token) do
      {:ok, code} ->
        {:noreply, push_navigate(socket, to: "/games/hearts/#{code}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create (#{inspect(reason)}).")}
    end
  end

  # A new player count keeps "all but you" when it was all but you.
  defp fit_bots(%{"players" => p} = params, %{"players" => old_p, "bots" => old_b}) do
    n = int(p, 4)
    all_but_you? = int(old_b, 0) == int(old_p, 4) - 1
    bots = if all_but_you?, do: n - 1, else: min(int(params["bots"], 0), n - 1)
    Map.put(params, "bots", to_string(bots))
  end

  defp config(params) do
    players = params["players"] |> int(4) |> max(3) |> min(5)

    %{
      name: params["name"],
      bots: params["bots"] |> int(players - 1) |> max(0) |> min(players - 1),
      level: if(params["level"] == "random", do: :random, else: :heuristic),
      opts: %{
        players: players,
        target:
          if(int(params["target"], 100) in @targets, do: int(params["target"], 100), else: 100),
        moon: if(params["moon"] == "subtract", do: :subtract, else: :add_to_others),
        jack_of_diamonds: params["jack_of_diamonds"] == "true"
      }
    }
  end

  defp int(value, default) do
    case Integer.parse(to_string(value)) do
      {n, ""} -> n
      _ -> default
    end
  end

  @impl true
  def render(assigns) do
    players = int(assigns.params["players"], 4)
    bots = int(assigns.params["bots"], players - 1)
    assigns = assign(assigns, players: players, bots: bots, targets: @targets)

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
            <h1 class="text-2xl font-bold tracking-tight">
              <span class="text-red-600">♥</span> Hearts
            </h1>
          </header>

          <.form
            for={@form}
            id="hearts-setup"
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
              <div class="grid grid-cols-3 gap-2">
                <.choice
                  :for={n <- 3..5}
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
              <div class="grid grid-cols-5 gap-2">
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

            <.input
              field={@form[:level]}
              type="select"
              label="Bot level"
              options={[
                {"Good (plays by rules of thumb)", "heuristic"},
                {"Easy (random cards)", "random"}
              ]}
              class="w-full rounded-lg border border-stone-300 bg-white px-3 py-2"
            />

            <.input
              field={@form[:target]}
              type="select"
              label="The game ends at"
              options={Enum.map(@targets, &{"#{&1} points", to_string(&1)})}
              class="w-full rounded-lg border border-stone-300 bg-white px-3 py-2"
            />

            <.input
              field={@form[:moon]}
              type="select"
              label="Shooting the moon"
              options={[{"Everyone else gets 26", "add_to_others"}, {"You lose 26", "subtract"}]}
              class="w-full rounded-lg border border-stone-300 bg-white px-3 py-2"
            />

            <.input
              field={@form[:jack_of_diamonds]}
              type="checkbox"
              label="Jack of diamonds: −10 points"
              class="size-5 rounded border-stone-300 accent-emerald-700"
            />

            <button
              id="hearts-create"
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

  defp seats_note(players, bots) do
    case players - 1 - bots do
      0 -> "You and #{bots} bots. The game starts at once."
      1 -> "You, #{bots} bots and 1 open seat: share the link with a friend."
      open -> "You, #{bots} bots and #{open} open seats: share the link with friends."
    end
  end

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
        "flex cursor-pointer items-center justify-center rounded-lg py-2 text-lg font-semibold ring-1 transition active:scale-[0.97]",
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
