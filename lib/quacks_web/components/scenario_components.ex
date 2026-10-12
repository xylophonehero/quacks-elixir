defmodule QuacksWeb.ScenarioComponents do
  @moduledoc """
  The step bar of a scenario table (dev only, `Quacks.Scenarios`): a small bar on
  top of the game page. "Step 2/4: resolve", the step's note, the step buttons (they
  seek the debug table, `GameServer.seek/2`), the links to the previous and next
  item of the same kind, the scenario in the gallery, "Play on" (unfreezes the bots) and a fold
  button (the bar folds to one row, in the browser only).
  """
  use Phoenix.Component

  import QuacksWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

  @doc "The step bar; `debug` is the table's `debug` with a `scenario` (string keys)."
  attr :debug, :map, required: true

  def step_bar(assigns) do
    %{"steps" => steps} = scenario = assigns.debug.scenario
    at = assigns.debug.at
    i = steps |> Enum.filter(&(&1["at"] <= at)) |> length() |> Kernel.-(1)
    step = if i >= 0, do: Enum.at(steps, i)

    assigns =
      assign(assigns,
        scenario: scenario,
        steps: steps,
        step: step,
        n: i + 1,
        exact: step != nil and step["at"] == at,
        prev_step: if(i > 0, do: Enum.at(steps, i - 1)),
        next_step: Enum.at(steps, i + 1),
        at: at
      )

    ~H"""
    <nav
      id="scenario-bar"
      class="group/sb fixed top-0 left-1/2 z-[60] w-max max-w-[calc(100%-1rem)] -translate-x-1/2 rounded-b-lg bg-black/80 px-1.5 py-0.5 text-xs text-white shadow-lg backdrop-blur-sm"
      aria-label="Scenario steps"
      data-role="scenario-bar"
      data-step={@step && @step["label"]}
    >
      <div class="flex items-center gap-1">
        <button
          type="button"
          id="scenario-prev"
          phx-click="seek"
          phx-value-to={@prev_step && @prev_step["at"]}
          disabled={@prev_step == nil}
          class={step_class()}
          aria-label="Previous step"
        >
          <.icon name="hero-chevron-left" class="size-4" />
        </button>
        <span class="tabular-nums" data-role="scenario-step" title={@step && @step["note"]}>
          <%= if @step do %>
            {@n}/{length(@steps)} <b>{@step["label"]}</b>
            <span :if={!@exact} class="opacity-70">+{@at - @step["at"]}</span>
          <% else %>
            before step 1
          <% end %>
        </span>
        <button
          type="button"
          id="scenario-next"
          phx-click="seek"
          phx-value-to={@next_step && @next_step["at"]}
          disabled={@next_step == nil}
          class={[step_class(), "font-semibold"]}
          aria-label="Next step"
        >
          Next <.icon name="hero-chevron-right" class="size-4" />
        </button>
        <span class="h-4 w-px bg-white/30" aria-hidden="true"></span>
        <.link
          href={@scenario["prev"]}
          class={item_class(@scenario["prev"])}
          aria-label="Previous item"
          id="scenario-prev-item"
        >
          <.icon name="hero-chevron-double-left" class="size-4" />
        </.link>
        <.link
          href={@scenario["index"]}
          class="max-w-28 truncate font-semibold underline-offset-2 hover:underline sm:max-w-48"
          title={"#{@scenario["title"]}: all scenarios"}
          id="scenario-index"
        >
          {@scenario["title"]}
        </.link>
        <.link
          href={@scenario["next"]}
          class={item_class(@scenario["next"])}
          aria-label="Next item"
          id="scenario-next-item"
        >
          <.icon name="hero-chevron-double-right" class="size-4" />
        </.link>
        <button
          type="button"
          id="scenario-fold"
          phx-click={JS.toggle_class("folded", to: "#scenario-bar")}
          class={step_class()}
          aria-label="Fold the step bar"
          title="Fold / unfold"
        >
          <.icon
            name="hero-chevron-up"
            class="size-4 transition-transform group-[.folded]/sb:rotate-180"
          />
        </button>
      </div>
      <div
        class="flex items-baseline justify-center gap-2 pb-0.5 text-[0.7rem] group-[.folded]/sb:hidden"
        data-role="scenario-note"
      >
        <span :if={@step && @step["note"]} class="opacity-80">{@step["note"]}</span>
        <button
          :if={@debug.frozen}
          type="button"
          id="scenario-play"
          phx-click="freeze"
          phx-value-frozen="false"
          class="shrink-0 cursor-pointer underline underline-offset-2 hover:text-gold"
          title="Unfreeze the bots and play on by hand"
        >
          Play on
        </button>
      </div>
    </nav>
    """
  end

  defp step_class,
    do:
      "inline-flex cursor-pointer items-center rounded px-1 py-0.5 hover:bg-white/15 disabled:cursor-default disabled:opacity-30"

  defp item_class(nil), do: "pointer-events-none rounded px-1 py-0.5 opacity-30"
  defp item_class(_href), do: "rounded px-1 py-0.5 hover:bg-white/15"
end
