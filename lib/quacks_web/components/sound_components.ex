defmodule QuacksWeb.SoundComponents do
  @moduledoc """
  The sound parts of the page (`docs/research/sounds.md`, `QuacksWeb.Sounds`):
  the menu's Sound row (`sound_settings/1`) and a cue (`sound_cue/1`), an empty
  element whose hook plays one sound when it mounts. `assets/js/sound.js` plays
  the sounds; the server keeps no sound state.
  """
  use Phoenix.Component

  @doc """
  The menu row: Sound On / Off and the volume (Low, Medium, High). Client only:
  the `SoundSettings` hook reads and writes `localStorage["quacks:sound"]`, and
  `phx-update="ignore"` keeps a patch from resetting the checked inputs. The
  rendered state is the default (On, Medium); the hook sets the saved one. A
  change plays a white chip's sound at the new volume.
  """
  attr :id, :string, default: "sound-settings"

  def sound_settings(assigns) do
    ~H"""
    <form
      id={@id}
      class="space-y-2 text-sm"
      phx-hook="SoundSettings"
      phx-update="ignore"
      aria-label="Sound"
      data-role="sound-settings"
      data-preview={QuacksWeb.Sounds.chip_sound({:white, 1})}
    >
      <.segments
        id={@id}
        name="on"
        legend="Sound"
        options={[{"on", "On", true}, {"off", "Off", false}]}
      />
      <.segments
        id={@id}
        name="volume"
        legend="Volume"
        options={[{"0.4", "Low", false}, {"0.7", "Medium", true}, {"1", "High", false}]}
      />
    </form>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :legend, :string, required: true
  attr :options, :list, required: true, doc: "`{value, label, checked}`"

  defp segments(assigns) do
    ~H"""
    <fieldset>
      <legend class="mb-1 font-semibold">{@legend}</legend>
      <div class="segmented flex gap-1 rounded-lg bg-parchment-deep p-1">
        <label
          :for={{value, label, checked} <- @options}
          class="relative flex min-h-10 flex-1 cursor-pointer items-center justify-center px-2 py-1 text-center leading-tight"
        >
          <input
            type="radio"
            id={"#{@id}-#{@name}-#{value}"}
            name={@name}
            value={value}
            checked={checked}
            class="segment"
          />
          <span class="relative">{label}</span>
        </label>
      </div>
    </fieldset>
    """
  end

  @doc """
  An empty element that plays `sound` once when it mounts (the `SoundCue` hook).
  With `once`, once per browser tab: a reload does not play it again (the key
  goes to `sessionStorage`, as the explosion's buzz).
  """
  attr :id, :string, required: true
  attr :sound, :string, required: true
  attr :once, :string, default: nil, doc: "a key: play only the first time in this tab"
  attr :delay, :integer, default: 0, doc: "ms after the mount"

  def sound_cue(assigns) do
    ~H"""
    <span
      id={@id}
      phx-hook="SoundCue"
      data-sound={@sound}
      data-once={@once}
      data-delay={@delay}
      hidden
      data-role="sound-cue"
    ></span>
    """
  end
end
