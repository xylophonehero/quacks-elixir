defmodule QuacksWeb.Icons do
  @moduledoc """
  Game icons as inline SVG: one per ingredient colour, game piece and patient.

  The files are in `priv/static/images/icons/` (game-icons.net, CC BY 3.0; see
  `docs/CREDITS.md`). They are read at compile time, so the page gets the paths
  inline and the browser fetches nothing. Each icon is one filled silhouette on a
  512 viewBox with `fill="currentColor"`: set its colour with a `text-*` class.

  To swap an icon, copy the new file into `priv/static/images/icons/` and change its
  file name in `@files` below.
  """
  use Phoenix.Component

  @dir Path.expand("../../../priv/static/images/icons", __DIR__)

  # subject => file in `@dir`. Ingredients by chip colour, then pieces, then patients.
  @files %{
    white: "cherry-bomb-1.svg",
    orange: "pumpkin-1.svg",
    green: "spider-1.svg",
    blue: "crow-skull-2.svg",
    red: "toadstool-1.svg",
    yellow: "mandrake-1.svg",
    purple: "ghosts-breath-1.svg",
    black: "hawkmoth-1.svg",
    locoweed: "locoweed-2.svg",
    flask: "flask-1.svg",
    droplet: "droplet-1.svg",
    ruby: "ruby-1.svg",
    rat: "rat-1.svg",
    die: "die-1.svg",
    vp: "victory-point-1.svg",
    book: "spell-book-1.svg",
    tube: "test-tube-1.svg",
    bag: "bag-1.svg",
    cauldron: "cauldron-2.svg",
    penny: "penny-1.svg",
    witch: "witch-1.svg",
    nervousness: "patient-nervousness-2.svg",
    ear_worm: "patient-ear-worm-1.svg",
    carrot_nose: "patient-carrot-nose-1.svg",
    wing_ears: "patient-wing-ears-3.svg",
    chicken_eyes: "patient-chicken-eyes-1.svg",
    witch_hump: "patient-witch-hump-1.svg",
    forgetfulness: "patient-forgetfulness-1.svg",
    vampirism: "patient-vampirism-2.svg"
  }

  # subject => the markup inside the file's <svg> element.
  @icons Map.new(@files, fn {name, file} ->
           path = Path.join(@dir, file)
           @external_resource path
           [_, inner] = Regex.run(~r{<svg[^>]*>(.*)</svg>}s, File.read!(path))
           {name, String.trim(inner)}
         end)

  @ingredients ~w(white orange green blue red yellow purple black locoweed)a
  @pieces ~w(flask droplet ruby rat die vp book tube bag cauldron penny witch)a
  @patients ~w(nervousness ear_worm carrot_nose wing_ears chicken_eyes witch_hump forgetfulness vampirism)a

  @doc "The ingredient colours that have an icon."
  def ingredients, do: @ingredients

  @doc "The piece names that have an icon."
  def pieces, do: @pieces

  @doc "The patient ids that have an icon."
  def patients, do: @patients

  @doc """
  The icon of an ingredient (chip colour), e.g. the pumpkin for `:orange`.

      <.ingredient_icon colour={:orange} class="size-6 text-chip-orange" />
  """
  attr :colour, :atom, required: true, values: @ingredients
  attr :class, :any, default: "size-5"
  attr :rest, :global, include: ~w(x y width height)

  def ingredient_icon(assigns), do: svg(assign(assigns, :name, assigns.colour))

  @doc """
  The icon of a game piece: #{Enum.map_join(@pieces, ", ", &"`:#{&1}`")}.

      <.piece_icon name={:ruby} class="size-4 text-ruby" />
  """
  attr :name, :atom, required: true, values: @pieces
  attr :class, :any, default: "size-5"
  attr :rest, :global, include: ~w(x y width height)

  def piece_icon(assigns), do: svg(assigns)

  @doc """
  The icon of a patient (The Alchemists), by `Quacks.Rules.Alchemists` id.

      <.patient_icon id={:ear_worm} class="size-5" />
  """
  attr :id, :atom, required: true, values: @patients
  attr :class, :any, default: "size-5"
  attr :rest, :global, include: ~w(x y width height)

  def patient_icon(assigns), do: svg(assign(assigns, :name, assigns.id))

  defp svg(assigns) do
    assigns = assign(assigns, :inner, Phoenix.HTML.raw(Map.fetch!(@icons, assigns.name)))

    ~H"""
    <svg
      viewBox="0 0 512 512"
      fill="currentColor"
      class={@class}
      aria-hidden="true"
      data-icon={@name}
      {@rest}
    >
      {@inner}
    </svg>
    """
  end
end
