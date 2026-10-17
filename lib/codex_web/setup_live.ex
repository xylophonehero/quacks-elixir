defmodule CodexWeb.SetupLive do
  @moduledoc """
  `/games/codex/new`: start a Codex room. The set-up is a preset
  (`Codex.Game.presets/0`: Bashing vs Finesse, Red vs Green, Blue vs Black) or
  a custom pick of a starting deck and one spec for each side. You play P1 against the bot (`Codex.Bot`), or both sides on this
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
       form:
         to_form(
           %{
             "name" => "",
             "opponent" => "bot",
             "preset" => "first",
             "p1_starter" => "Red",
             "p1_spec" => "Fire",
             "p2_starter" => "Green",
             "p2_spec" => "Growth"
           },
           as: :setup
         )
     )}
  end

  @impl true
  def handle_event("change", %{"setup" => params}, socket),
    do:
      {:noreply,
       assign(socket, form: to_form(Map.merge(socket.assigns.form.params, params), as: :setup))}

  def handle_event("create", params, socket) do
    name = get_in(params, ["setup", "name"]) || ""
    bot? = get_in(params, ["setup", "opponent"]) != "hotseat"
    p = Map.merge(socket.assigns.form.params, params["setup"] || %{})
    opts = Map.take(p, ~w(preset p1_starter p1_spec p2_starter p2_spec)) |> Map.put("bot", bot?)
    config = %{name: name, opts: opts, bots: if(bot?, do: 1, else: 0)}

    case Server.create(@key, config, socket.assigns.token) do
      {:ok, code} ->
        {:noreply, push_navigate(socket, to: "/games/#{@key}/#{code}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create (#{inspect(reason)}).")}
    end
  end

  defp spec_options do
    for color <- Codex.Cards.colors(), spec <- Codex.Cards.specs(color) do
      {"#{spec} (#{Codex.Cards.fetch!(Codex.Cards.hero(spec)).name}, #{color})", spec}
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
            Codex for two. The table follows the rules; Free mode lets you move any card
            by hand. P1 starts with 4 workers, P2 with 5.
          </p>

          <.form
            for={@form}
            id="codex-setup"
            phx-change="change"
            phx-submit="create"
            class="flex flex-col gap-5 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-stone-900/10 sm:p-6"
          >
            <fieldset class="flex flex-col gap-2">
              <legend class="mb-2 text-sm font-semibold">Decks</legend>
              <div class="grid gap-2 sm:grid-cols-2">
                <label
                  :for={
                    {value, title, text} <- [
                      {"first", "Bashing vs Finesse", "The first game: neutral decks, 1 hero each."},
                      {"red_green", "Red vs Green",
                       "3 heroes each: Anarchy, Blood, Fire against Balance, Feral, Growth."},
                      {"blue_black", "Blue vs Black",
                       "3 heroes each: Law, Peace, Truth against Demonology, Disease, Necromancy."},
                      {"custom", "Custom", "A starting deck and 1 spec for each side."}
                    ]
                  }
                  for={"preset-#{value}"}
                  class={[
                    "flex cursor-pointer flex-col gap-0.5 rounded-xl p-3 ring-1 transition active:scale-[0.99]",
                    if(@form[:preset].value == value,
                      do: "bg-emerald-700 text-white ring-emerald-700",
                      else: "bg-white text-stone-800 ring-stone-300 hover:bg-stone-50"
                    )
                  ]}
                >
                  <input
                    type="radio"
                    id={"preset-#{value}"}
                    name="setup[preset]"
                    value={value}
                    checked={@form[:preset].value == value}
                    class="sr-only"
                  />
                  <span class="font-semibold">{title}</span>
                  <span class="text-sm opacity-80">{text}</span>
                </label>
              </div>
              <div
                :if={@form[:preset].value == "custom"}
                id="codex-custom"
                class="grid gap-3 sm:grid-cols-2"
              >
                <div
                  :for={{p, label} <- [{"p1", "P1"}, {"p2", "P2"}]}
                  class="flex flex-col gap-2 rounded-xl bg-stone-50 p-3 ring-1 ring-stone-200"
                >
                  <strong class="text-sm">{label}</strong>
                  <.input
                    field={@form[:"#{p}_starter"]}
                    type="select"
                    label="Starting deck"
                    options={Enum.map(Codex.Cards.colors(), &{&1, &1})}
                    class="w-full rounded-lg border border-stone-300 px-3 py-2"
                  />
                  <.input
                    field={@form[:"#{p}_spec"]}
                    type="select"
                    label="Spec (hero)"
                    options={spec_options()}
                    class="w-full rounded-lg border border-stone-300 px-3 py-2"
                  />
                </div>
              </div>
            </fieldset>
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
