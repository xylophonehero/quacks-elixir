defmodule QuacksWeb.BugReportComponents do
  @moduledoc """
  "Report a problem" (`Quacks.BugReports`): a bug button for the game header and
  the waiting panel, and the dialog with the form. The form sends `"report"`
  with `report[text]` and `report[browser]`, a JSON string app.js fills in on
  submit (user agent, viewport, `navigator.onLine`, the last console errors).

  `n` counts the reports sent from this page: each success renders a fresh, closed
  dialog (`bug-report-N`), so the form is empty again with no client state.
  """
  use QuacksWeb, :html

  attr :n, :integer, required: true
  attr :class, :any, default: nil

  def bug_report_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={JS.dispatch("quacks:modal", to: "#bug-report-#{@n}")}
      aria-label="Report a problem"
      title="Report a problem"
      class={[
        "inline-flex size-11 shrink-0 cursor-pointer items-center justify-center rounded-full transition-[background-color,scale] duration-150 ease-out hover:bg-black/15 active:scale-95",
        @class
      ]}
      data-role="open-bug-report"
    >
      <.icon name="hero-bug-ant" class="size-6" />
    </button>
    """
  end

  attr :n, :integer, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :error, :string, default: nil

  def bug_report_sheet(assigns) do
    ~H"""
    <.dialog_sheet id={"bug-report-#{@n}"} label="Report a problem" auto_open={false}>
      <h2 class="sheet-head mb-1 text-lg font-bold">Report a problem</h2>
      <p class="mb-3 text-sm text-ink-soft">
        Tell us what went wrong. We attach your room id, the current game state and your
        browser details, so we can play the game back to this point.
      </p>
      <.form
        for={@form}
        id={"bug-report-form-#{@n}"}
        phx-submit="report"
        data-bug-report
        class="space-y-2"
      >
        <.input
          field={@form[:text]}
          type="textarea"
          rows="5"
          maxlength="2000"
          required
          autofocus
          placeholder="What happened? What did you expect?"
          aria-label="What went wrong"
          class="w-full rounded-md border border-ink-soft bg-parchment-light px-2 py-2 text-base text-ink"
        />
        <input type="hidden" name={@form[:browser].name} value="" data-role="browser-details" />
        <p
          :if={@error}
          class="text-sm font-semibold text-red-800"
          role="alert"
          data-role="report-error"
        >
          {@error}
        </p>
        <div class="flex justify-end *:min-h-11">
          <.button variant={:primary} phx-disable-with="Sending…" data-role="send-report">
            Send report
          </.button>
        </div>
      </.form>
    </.dialog_sheet>
    """
  end
end
