defmodule QuacksWeb.TipComponents do
  @moduledoc """
  Round 38: the first-time hint card (`tip_card/1`) and its menu row
  (`tips_settings/1`). The hint (`QuacksWeb.Tips`) is a parchment card in the
  bottom context area; it never dims the screen and the player can still play.
  """
  use Phoenix.Component

  import QuacksWeb.CoreComponents, only: [button: 1]

  @doc """
  One hint: its head, its text, "No more tips" (`tip_off`) and the main button
  (`tip_done`, "Got it" or "Next tip"). It comes in a moment after its moment, so
  it never lands in the middle of a step's own animation (app.css `.tip-card`).
  """
  attr :tip, :map, required: true
  attr :class, :any, default: nil

  def tip_card(assigns) do
    ~H"""
    <section
      id={"tip-#{@tip.key}"}
      class={["tip-card pointer-events-auto relative z-50", @class]}
      role="status"
      aria-label={"Tip: #{@tip.label}"}
      data-role="tip"
      data-tip={@tip.key}
    >
      <p class="flex items-baseline justify-between gap-2 text-tag font-bold tracking-wide text-ink-soft uppercase">
        <span>Tip</span>
        <span data-role="tip-label">{@tip.label}</span>
      </p>
      <p class="text-sm leading-snug text-ink" data-role="tip-text">{@tip.text}</p>
      <div class="flex items-center justify-end gap-2">
        <button
          type="button"
          phx-click="tip_off"
          class="mr-auto min-h-11 cursor-pointer px-1 text-sm font-semibold text-ink-soft underline underline-offset-2 touch-manipulation hover:text-ink"
          data-role="tip-off"
        >
          No more tips
        </button>
        <.button
          variant={:primary}
          phx-click="tip_done"
          phx-value-key={@tip.key}
          class="min-h-11 touch-manipulation px-4"
          data-role="tip-done"
        >
          {@tip.button}
        </.button>
      </div>
    </section>
    """
  end

  @doc """
  The menu row (T2.11): "Tips: On / Off" (event `tips`) and "Show again"
  (`tips_again`, it clears the seen hints and turns the tips on).
  """
  attr :on, :boolean, required: true

  def tips_settings(assigns) do
    ~H"""
    <form
      id="tips-settings"
      class="flex items-center gap-2 text-sm"
      phx-change="tips"
      aria-label="Tips"
      data-role="tips-settings"
    >
      <fieldset class="flex min-w-0 flex-1 items-center gap-2">
        <legend class="sr-only">Tips</legend>
        <span class="font-semibold" aria-hidden="true">Tips</span>
        <div class="segmented flex flex-1 gap-1 rounded-lg bg-parchment-deep p-1">
          <label
            :for={{value, label} <- [on: "On", off: "Off"]}
            class="relative flex min-h-10 flex-1 cursor-pointer items-center justify-center px-2 py-1 text-center leading-tight"
          >
            <input
              type="radio"
              id={"tips-#{value}"}
              name="tips"
              value={value}
              checked={@on == (value == :on)}
              class="segment"
            />
            <span class="relative">{label}</span>
          </label>
        </div>
      </fieldset>
      <.button
        type="button"
        variant={:secondary}
        phx-click="tips_again"
        class="min-h-11 shrink-0"
        data-role="tips-again"
      >
        Show again
      </.button>
    </form>
    """
  end
end
