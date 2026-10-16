defmodule TableWeb.Components.Theme do
  @moduledoc """
  The colour themes of the card table and the theme picker.

  The themes are the colour values of eight daisyUI 5 themes (MIT, see
  `docs/CREDITS.md`), as `--tb-*` tokens in `assets/css/table.css`. They apply
  only inside `root/1` (`.tb-root[data-theme]`), so a Quacks page does not change.

  The viewer's theme and deck (2 or 4 colours) stay in the browser's
  `localStorage` (`table:theme`, `table:deck`): the `TableTheme` hook
  (`assets/js/table.js`) reads them when the root mounts and writes them when a
  picker button is tapped. The server renders the default; the hook owns
  `data-theme` and `data-deck` after that (`JS.ignore_attributes/1`).
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @themes [
    %{id: "emerald", name: "Emerald", dark: false},
    %{id: "light", name: "Light", dark: false},
    %{id: "cupcake", name: "Cupcake", dark: false},
    %{id: "retro", name: "Retro", dark: false},
    %{id: "nord", name: "Nord", dark: false},
    %{id: "forest", name: "Forest", dark: true},
    %{id: "dracula", name: "Dracula", dark: true},
    %{id: "night", name: "Night", dark: true}
  ]

  @doc "The themes, in picker order (the default first)."
  @spec themes() :: [%{id: String.t(), name: String.t(), dark: boolean}]
  def themes, do: @themes

  @doc "The theme ids."
  @spec ids() :: [String.t()]
  def ids, do: Enum.map(@themes, & &1.id)

  @doc "The default theme: a light felt, white cards, clear red and black."
  @spec default() :: String.t()
  def default, do: "emerald"

  @doc """
  The table's root: the theme tokens apply inside it. With `remember`, the
  viewer's stored theme and deck replace `theme` and `deck` when it mounts.
  """
  attr :id, :string, required: true
  attr :theme, :string, default: nil
  attr :deck, :string, default: "2", values: ~w(2 4)
  attr :remember, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def root(assigns) do
    ~H"""
    <div
      id={@id}
      class={["tb-root", @class]}
      data-theme={@theme || default()}
      data-deck={@deck}
      data-themes={@remember && Enum.join(ids(), " ")}
      phx-hook={@remember && "TableTheme"}
      phx-mounted={@remember && JS.ignore_attributes(["data-theme", "data-deck"])}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  The theme picker: one swatch button per theme and a 4-colour deck switch. It
  must be inside a `root/1` with `remember`; a tap sends `table:pick` to it.
  """
  attr :id, :string, required: true
  attr :theme, :string, default: nil
  attr :deck, :string, default: "2"
  attr :deck_switch, :boolean, default: true, doc: "show the 4-colour deck switch (cards only)"
  attr :class, :any, default: nil

  def picker(assigns) do
    assigns = assign(assigns, current: assigns.theme || default())

    ~H"""
    <div id={@id} class={["flex flex-wrap items-center gap-1.5", @class]} data-role="theme-picker">
      <span class="sr-only">Table colours</span>
      <button
        :for={t <- themes()}
        id={"#{@id}-#{t.id}"}
        type="button"
        class="group flex items-center gap-1.5 rounded-full bg-tb-base-100 py-1 pr-2.5 pl-1 text-xs font-medium text-tb-base-content ring-1 ring-tb-base-content/15 transition hover:ring-tb-base-content/40 active:scale-[0.97] aria-pressed:ring-2 aria-pressed:ring-tb-accent"
        data-pick-theme={t.id}
        aria-pressed={to_string(t.id == @current)}
        phx-click={JS.dispatch("table:pick", detail: %{theme: t.id})}
        phx-mounted={JS.ignore_attributes("aria-pressed")}
      >
        <.swatch theme={t.id} />
        {t.name}
      </button>
      <button
        :if={@deck_switch}
        id={"#{@id}-deck"}
        type="button"
        class="flex items-center gap-1.5 rounded-full bg-tb-base-100 px-2.5 py-1 text-xs font-medium text-tb-base-content ring-1 ring-tb-base-content/15 transition hover:ring-tb-base-content/40 active:scale-[0.97] aria-pressed:ring-2 aria-pressed:ring-tb-accent"
        data-pick-deck
        aria-pressed={to_string(@deck == "4")}
        phx-click={JS.dispatch("table:pick", detail: %{deck: "toggle"})}
        phx-mounted={JS.ignore_attributes("aria-pressed")}
      >
        <span class="tb-four flex gap-px font-bold" aria-hidden="true">
          <span class="text-(--tb-card-red)">♥</span><span class="text-(--tb-card-blue)">♦</span><span class="text-(--tb-card-green)">♣</span><span>♠</span>
        </span>
        4-colour deck
      </button>
    </div>
    """
  end

  @doc "A theme's colours in a dot: the felt, the card back and the accent."
  attr :theme, :string, required: true

  def swatch(assigns) do
    ~H"""
    <span
      class="tb-root relative inline-flex size-6 overflow-hidden rounded-full ring-1 ring-black/20"
      data-theme={@theme}
      aria-hidden="true"
    >
      <span class="tb-felt absolute inset-0"></span>
      <span class="absolute top-1 left-1.5 h-4 w-3 rounded-[2px] bg-tb-primary ring-1 ring-tb-card-face"></span>
      <span class="absolute right-0.5 bottom-0.5 size-2 rounded-full bg-tb-accent"></span>
    </span>
    """
  end
end
