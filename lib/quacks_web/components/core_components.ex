defmodule QuacksWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is plain Tailwind CSS v4 (no component library).
  Useful references:

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  # text-base on phones: iOS zooms into a focused field under 16px, and the page stays
  # zoomed, so bottom sheets end up below the screen.
  @field_class "w-full rounded-lg border border-zinc-300 px-3 py-2 text-base sm:text-sm focus:border-zinc-500 focus:outline-none"
  @field_error_class "border-red-400"

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      phx-remove={hide("##{@id}")}
      role="alert"
      class="fixed inset-x-4 bottom-28 z-50 sm:inset-x-auto sm:top-20 sm:left-4 sm:bottom-auto"
      {@rest}
    >
      <%!-- Phones: above the bottom bar. Larger screens: under the header on the left,
           clear of the Menu button, the bug icon and the tablet tabs. Info toasts
           close by themselves (GameLive `info/3`). --%>
      <div class={[
        "flex items-start gap-3 rounded-lg border p-4 shadow-md sm:w-96 text-wrap",
        @kind == :info && "border-sky-300 bg-sky-50 text-sky-900",
        @kind == :error && "border-red-300 bg-red-50 text-red-900"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label="close">
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  An info sheet on the browser's Popover API: a bottom sheet on phones, closed by a
  tap outside or Esc. A `sheet_button` with the same `id` opens it. No JS.

  With `inline_lg`, large screens show the content in place instead (the sheet
  button hides there), so one element serves both layouts.

  ## Examples

      <.sheet_button for="sheet-log">Log</.sheet_button>
      <.sheet id="sheet-log" label="Log"><.action_log log={@log} /></.sheet>
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :inline_lg, :boolean, default: false
  attr :rest, :global
  slot :inner_block, required: true

  def sheet(assigns) do
    ~H"""
    <div
      id={@id}
      popover
      class={["sheet paper", @inline_lg && "sheet-inline-lg"]}
      role="dialog"
      aria-label={@label}
      {@rest}
    >
      <button
        type="button"
        popovertarget={@id}
        popovertargetaction="hide"
        class="sheet-close"
        aria-label="Close"
      >
        <.icon name="hero-x-mark" class="size-5" />
      </button>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc "A button that opens the `sheet` with id `for`."
  attr :for, :string, required: true
  attr :class, :any, default: nil

  attr :variant, :atom,
    default: nil,
    values: [nil, :secondary],
    doc: "`:secondary` for parchment, beside `button/1`'s secondary buttons"

  attr :rest, :global
  slot :inner_block, required: true

  def sheet_button(assigns) do
    ~H"""
    <button
      type="button"
      popovertarget={@for}
      class={[
        "inline-flex min-h-11 min-w-11 items-center justify-center gap-1 rounded-lg px-3",
        "text-sm font-semibold touch-manipulation",
        "cursor-pointer transition-[scale,background-color] duration-150 ease-out active:scale-[.98]",
        if(@variant == :secondary,
          do: "bg-parchment-light text-ink shadow-sm ring-1 ring-ink/25 hover:bg-white",
          else: "bg-iron-dark text-parchment ring-1 ring-iron hover:bg-iron"
        ),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  A modal `<dialog>` for a decision the player must make. It opens itself when it
  enters the page and leaves with the page's next render that drops it, so the
  server needs no "is open" state. The backdrop stays see-through, so the pot shows
  behind. Close it to look at the board; `JS.dispatch("quacks:modal", to: "#id")`
  opens it again.

  With `auto_open={false}` it waits for that dispatch; `then_open` names a dialog
  to open when this one closes (the round results open the shop that way), and
  `on_close` runs JS commands then (they stick across patches, unlike a class set
  by plain JS).

  Focus on open: give the dialog's one primary button `autofocus`; a dialog with no
  primary button sets `focus_self` instead (an empty focus target at its top), so
  the close × never takes the focus.

  `side={:panel}`: on screens ≥ 64rem the dialog opens non-modal (`show()`: no
  backdrop, the page stays live) where it sits in the page, as a panel in the right
  column; below that it is the usual bottom sheet. `side={:hidden}`: on those
  screens it does not open at all (the side column already shows its content); it
  counts as closed at once. app.js picks the mode when it opens.

  A tap on the dimmed backdrop closes a modal sheet (app.js), like its ×.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :auto_open, :boolean, default: true
  attr :then_open, :string, default: nil, doc: "id of a dialog to open on close"
  attr :on_close, JS, default: nil, doc: "JS commands app.js runs when it closes"
  attr :class, :any, default: nil, doc: "extra classes"

  attr :side, :atom,
    default: nil,
    values: [nil, :panel, :hidden],
    doc: "on screens ≥ 64rem: a non-modal panel in place (`:panel`) or not opened (`:hidden`)"

  attr :focus_self, :boolean,
    default: false,
    doc:
      "the dialog itself takes the focus on open (a choice without one primary button); otherwise the button with `autofocus` does"

  slot :inner_block, required: true

  def dialog_sheet(assigns) do
    # The server never renders `open`; showModal() adds it in the browser. Without
    # ignore_attributes("open") the next LiveView patch would remove it again and
    # close the dialog. The "quacks:modal" listener in app.js calls showModal().
    ~H"""
    <dialog
      id={@id}
      class={["sheet paper", @class]}
      aria-label={@label}
      phx-mounted={
        if @auto_open,
          do: JS.ignore_attributes("open") |> JS.dispatch("quacks:modal"),
          else: JS.ignore_attributes("open")
      }
      data-then-open={@then_open}
      data-on-close={@on_close}
      data-side={@side}
    >
      <%!-- Chrome ignores `autofocus` on the <dialog> itself, so the focus starts here. --%>
      <span :if={@focus_self} tabindex="-1" autofocus data-role="focus-start" class="outline-none" />
      <form method="dialog">
        <button class="sheet-close" aria-label="Close">
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </form>
      {render_slot(@inner_block)}
    </dialog>
    """
  end

  @doc """
  Renders a button with navigation support.

  `variant`: `:primary` (gold, the one main action of a dialog), `:secondary`
  (parchment with an ink ring, for other choices on parchment) or `:ghost` (text
  only, for skip or cancel). Without a variant the button is the outline style
  for the wood table (Stop, the bar's extra actions).

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant={:primary}>Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled autofocus type)

  attr :class, :any, default: nil, doc: "extra classes, added after the variant's"
  attr :variant, :atom, default: nil, values: [nil, :primary, :secondary, :ghost]
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{
      primary: "bg-gold text-ink shadow-md shadow-black/25 hover:brightness-110",
      secondary: "bg-parchment-light text-ink shadow-sm ring-1 ring-ink/25 hover:bg-white",
      ghost: "text-ink-soft underline-offset-4 hover:bg-ink/10 hover:text-ink hover:underline",
      nil:
        "bg-iron-dark/60 text-parchment ring-2 ring-parchment/45 ring-inset hover:bg-iron-dark hover:ring-parchment/70"
    }

    assigns =
      assign(assigns, :class, [
        "inline-flex cursor-pointer items-center justify-center gap-1.5 rounded-lg px-4 py-2 text-sm font-semibold",
        "touch-manipulation select-none transition-[scale,background-color,box-shadow,filter,opacity] duration-150 ease-out",
        "active:scale-[.98] phx-click-loading:opacity-70",
        "focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-droplet",
        "disabled:cursor-not-allowed disabled:opacity-60 disabled:shadow-none disabled:saturate-[.3] disabled:active:scale-100",
        Map.fetch!(variants, assigns.variant),
        assigns.class
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="mb-2">
      <label for={@id}>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="inline-flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "size-4 rounded border-zinc-300"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="mb-2">
      <label for={@id}>
        <span :if={@label} class="mb-1 block text-sm font-medium text-zinc-700">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || field_class(), @errors != [] && (@error_class || field_error_class())]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="mb-2">
      <label for={@id}>
        <span :if={@label} class="mb-1 block text-sm font-medium text-zinc-700">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || field_class(),
            @errors != [] && (@error_class || field_error_class())
          ]}
          {@rest}
        >{Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="mb-2">
      <label for={@id}>
        <span :if={@label} class="mb-1 block text-sm font-medium text-zinc-700">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Form.normalize_value(@type, @value)}
          class={[
            @class || field_class(),
            @errors != [] && (@error_class || field_error_class())
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  defp field_class, do: @field_class
  defp field_error_class, do: @field_error_class

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-red-600">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-ink-soft">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="w-full text-left text-sm [&_td]:px-3 [&_td]:py-2 [&_th]:px-3 [&_th]:py-2 [&_tbody_tr:nth-child(even)]:bg-zinc-50">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">Actions</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="divide-y divide-zinc-200">
      <li :for={item <- @item} class="py-3">
        <div>
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # You can make use of gettext to translate error messages by
    # uncommenting and adjusting the following code:

    # if count = opts[:count] do
    #   Gettext.dngettext(QuacksWeb.Gettext, "errors", msg, msg, count, opts)
    # else
    #   Gettext.dgettext(QuacksWeb.Gettext, "errors", msg, opts)
    # end

    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
