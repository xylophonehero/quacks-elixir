defmodule QuacksWeb.ScenariosLive do
  @moduledoc """
  The scenario index (dev and test only, `/dev/scenarios`): every rules item
  (`Quacks.Scenarios.all/0`) grouped by kind, with its link
  (`QuacksWeb.ScenarioController`), whether it is hand-written and its last test
  result (`Quacks.Scenarios.results/0`, written by
  `test/quacks_web/live/scenarios_test.exs`).
  """
  use QuacksWeb, :live_view

  alias Quacks.Scenarios

  @impl true
  def mount(_params, _session, socket) do
    entries = Scenarios.all()

    {:ok,
     assign(socket,
       page_title: "Scenarios",
       kinds:
         for({kind, heading} <- Scenarios.kinds(), do: {kind, heading, by_group(entries, kind)}),
       results: Scenarios.results(),
       total: length(entries),
       hand: Enum.count(entries, & &1.hand)
     )}
  end

  defp by_group(entries, kind) do
    entries
    |> Enum.filter(&(&1.kind == kind))
    |> Enum.chunk_by(& &1.group)
    |> Enum.map(&{hd(&1).group, &1})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="scenarios" class="mx-auto max-w-3xl space-y-6 pb-10">
        <header class="space-y-1">
          <h1 class="font-hand text-3xl font-bold">Scenarios</h1>
          <p class="text-sm text-parchment-dim">
            Dev only. One real game per rules item, played to the step where it acts. {@total} items, {@hand} hand-written. Test results come from <code class="font-mono text-xs">mix test test/quacks_web/live/scenarios_test.exs</code>.
          </p>
        </header>
        <section :for={{kind, heading, groups} <- @kinds} id={"kind-#{kind}"} class="space-y-2">
          <h2 class="text-xl font-bold">{heading}</h2>
          <div
            :for={{group, entries} <- groups}
            class="paper space-y-1 rounded-lg p-3"
            data-role="scenario-group"
          >
            <h3 class="text-xs font-bold tracking-wide text-ink-soft uppercase">{group}</h3>
            <ul class="divide-y divide-ink/10">
              <li
                :for={e <- entries}
                id={"scenario-#{String.replace(Scenarios.key(e), "/", "-")}"}
                class="flex min-h-11 items-center gap-2 py-1"
                data-role="scenario"
              >
                <.link
                  href={Scenarios.path(e)}
                  class="flex-1 font-semibold text-ink underline-offset-2 hover:underline"
                >
                  {e.title}
                  <span class="font-mono text-xs font-normal text-ink-soft">{e.id}</span>
                </.link>
                <span
                  :if={e.hand}
                  class="rounded bg-gold/60 px-1.5 py-0.5 text-xs font-semibold text-ink"
                  data-role="hand-written"
                >
                  hand-written
                </span>
                <.result result={@results[Scenarios.key(e)]} />
              </li>
            </ul>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :result, :map, default: nil

  defp result(%{result: nil} = assigns) do
    ~H"""
    <span class="w-14 text-right text-xs text-ink-soft" data-role="test-result" data-status="none">
      no run
    </span>
    """
  end

  defp result(assigns) do
    ~H"""
    <span
      class={[
        "w-14 rounded px-1.5 py-0.5 text-center text-xs font-semibold",
        if(@result["status"] == "pass", do: "bg-green-700 text-white", else: "bg-red-700 text-white")
      ]}
      title={@result["status"] == "fail" && "#{@result["step"]}: #{@result["message"]}"}
      data-role="test-result"
      data-status={@result["status"]}
    >
      {if @result["status"] == "pass", do: "pass", else: "fail"}
    </span>
    """
  end
end
