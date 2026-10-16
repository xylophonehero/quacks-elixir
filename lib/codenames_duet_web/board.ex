defmodule CodenamesDuetWeb.Board do
  @moduledoc """
  The Codenames Duet board on the table page (`TableWeb.TableLive`, a
  `TableWeb.Board`). It draws one seat's `Table.View` (`CodenamesDuet.Game.view/2`).

  - The 5 × 5 words. Your side of the key tints each whole card (green agent,
    near-black assassin with a red edge, sand bystander), and an agent or an
    assassin has an icon (a person, a skull), so the key reads without colour. Only your own side is in the view, so only your own side is in the
    page; "Hide my key" takes it out of the page too (for screen sharing).
  - The clue giver types one word and picks a number 0..9; the engine's error
    (`{:invalid_clue, reason}`) shows under the field (`act_error/3`).
  - The guesser taps a card to pick it and taps it again (or "Guess") to guess:
    the confirm step of codenames.game. "End guessing" after the first guess.
  - A found agent covers its card (a flip, `data-fresh`). A bystander mark is a
    token on the clue giver's edge of the card: your side at the bottom, your
    partner's at the top. Two marks cover the card.
  - The status row: whose turn, the clue, the agents found (of 15), the timer
    tokens. A banner in sudden death. The log lists each clue with its guesses.
  - At the end: the result, the score of a win (rulebook §6.4), both sides of the
    key on every card (your side as the tint, your partner's as a band on the top),
    and Play again.

  The colours are the table themes (`TableWeb.Components.Theme`, `--tb-*`); the
  board's own CSS is `assets/css/codenames.css` (`cd-*`).
  """
  @behaviour TableWeb.Board

  use QuacksWeb, :html

  alias TableWeb.Components.Theme

  @greens 15

  # -- TableWeb.Board -------------------------------------------------------------

  @impl true
  def init(socket) do
    Phoenix.Component.assign(socket,
      picked: nil,
      hide_key: false,
      clue_error: nil,
      clue_form: clue_form(),
      fresh: []
    )
  end

  defp clue_form(params \\ %{"word" => "", "number" => "1"}), do: to_form(params, as: :clue)

  @impl true
  def put_view(socket, env, old) do
    v = env.view
    a = socket.assigns
    new_game? = old != nil and length(v.log) < length(old.view.log)

    socket =
      Phoenix.Component.assign(socket,
        view: v,
        actions: env.actions,
        me: me(env),
        fresh: if(old && !new_game?, do: fresh(old.view, v), else: []),
        picked: if(a.picked != nil and {:guess, a.picked} in env.actions, do: a.picked)
      )

    if v.phase != :clue or new_game?,
      do: Phoenix.Component.assign(socket, clue_form: clue_form(), clue_error: nil),
      else: socket
  end

  # The cards that changed since the old view: a new agent or a new bystander mark.
  defp fresh(old, new) do
    agents = Map.keys(new.agents) -- Map.keys(old.agents)

    marks =
      for {i, sides} <- new.bystanders,
          length(sides) > length(Map.get(old.bystanders, i, [])),
          do: i

    Enum.uniq(agents ++ marks)
  end

  @impl true
  def handle_event("clue_change", %{"clue" => params}, socket),
    do:
      {:noreply, Phoenix.Component.assign(socket, clue_form: clue_form(params), clue_error: nil)}

  def handle_event("clue", %{"clue" => %{"word" => word} = params}, socket) do
    number = int(params["number"])
    socket = Phoenix.Component.assign(socket, clue_form: clue_form(params), clue_error: nil)

    if match?([{:clue, :word, _} | _], socket.assigns.actions),
      do: {:act, {:clue, word, number}, socket},
      else: {:noreply, socket}
  end

  def handle_event("pick", %{"index" => index}, socket) do
    i = int(index)
    a = socket.assigns

    cond do
      {:guess, i} not in a.actions -> {:noreply, socket}
      a.picked == i -> {:act, {:guess, i}, Phoenix.Component.assign(socket, picked: nil)}
      true -> {:noreply, Phoenix.Component.assign(socket, picked: i)}
    end
  end

  def handle_event("guess", _params, %{assigns: %{picked: i}} = socket) when is_integer(i),
    do: {:act, {:guess, i}, Phoenix.Component.assign(socket, picked: nil)}

  def handle_event("unpick", _params, socket),
    do: {:noreply, Phoenix.Component.assign(socket, picked: nil)}

  def handle_event("end_turn", _params, socket) do
    if :end_turn in socket.assigns.actions,
      do: {:act, :end_turn, Phoenix.Component.assign(socket, picked: nil)},
      else: {:noreply, socket}
  end

  def handle_event("toggle_key", _params, socket),
    do: {:noreply, Phoenix.Component.assign(socket, hide_key: !socket.assigns.hide_key)}

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def act_error({:invalid_clue, reason}, {:clue, _, _}, socket),
    do: Phoenix.Component.assign(socket, clue_error: reason)

  def act_error(reason, _action, socket),
    do: Phoenix.LiveView.put_flash(socket, :error, "Not now (#{inspect(reason)}).")

  attr :reason, :any, required: true, doc: "a `CodenamesDuet.Clue.reason/0`"

  defp clue_error(%{reason: {:visible_word, word}} = assigns) do
    assigns = assign(assigns, word: word)

    ~H"""
    <strong class="tracking-wide uppercase">{@word}</strong>
    is on the board. A clue cannot be a word on the board, a form of it or a part of it.
    """
  end

  defp clue_error(%{reason: :not_one_word} = assigns),
    do: ~H"Give one word: letters only. A hyphen or an apostrophe inside is fine."

  defp clue_error(%{reason: :too_long} = assigns), do: ~H"The clue can have 30 letters at most."
  defp clue_error(%{reason: _} = assigns), do: ~H"Pick a number from 0 to 9."

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp me(%{seat: :spectator}), do: 0
  defp me(%{seat: seat}), do: seat

  defp int(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} -> n
      _ -> -1
    end
  end

  # -- the page ------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} full>
      <.page {assigns} />
    </Layouts.app>
    """
  end

  @doc "The page without the layout (also the gallery's board story)."
  def page(assigns) do
    v = assigns.view
    me = assigns.me
    partner = 1 - me
    over? = v.phase == :over
    spectator? = assigns.seat == :spectator

    assigns =
      assign(assigns,
        partner: partner,
        over?: over?,
        spectator?: spectator?,
        show_key?: !spectator? and !assigns.hide_key and !over?,
        clue_giver?: match?([{:clue, :word, _} | _], assigns.actions),
        guesser?: Enum.any?(assigns.actions, &match?({:guess, _}, &1)),
        open_seat?: get_in(assigns.seats, [partner, :open]) == true,
        log: log_entries(v.log),
        name: &name(assigns.seats, &1, me, spectator?)
      )

    ~H"""
    <Theme.root
      id="duet-root"
      theme={assigns[:theme]}
      remember={assigns[:theme] == nil}
      class="min-h-dvh bg-tb-base-200 text-tb-base-content"
      data-phase={@view.phase}
    >
      <div class="cd-page mx-auto flex max-w-6xl flex-col gap-2 px-2 pt-2 pb-6 sm:gap-3 sm:px-4 sm:pt-4 lg:grid lg:grid-cols-[minmax(0,1fr)_21rem] lg:items-start lg:gap-4">
        <div class="flex min-w-0 flex-col gap-2 sm:gap-3">
          <.top_bar code={@code} seats={@seats} me={@me} spectator?={@spectator?} />
          <.invite :if={@open_seat? and !@spectator?} code={@code} key={@key} />
          <.status_row {assigns} />
          <div
            :if={@view.phase == :sudden_death}
            id="duet-sudden-death"
            class="cd-banner flex items-center gap-2 rounded-tb bg-tb-warning px-3 py-2 text-sm font-semibold text-tb-warning-content"
            role="status"
          >
            <.icon name="hero-bolt-mini" class="size-4 shrink-0" />
            <span>
              Sudden death: no more clues. Each of you guesses on the other's side; one wrong touch loses.
            </span>
          </div>
          <.over_panel :if={@over?} view={@view} name={@name} me={@me} partner={@partner} />
          <.grid
            view={@view}
            me={@me}
            partner={@partner}
            actions={@actions}
            picked={@picked}
            fresh={@fresh}
            show_key?={@show_key?}
            over?={@over?}
          />
          <.action_area {assigns} />
        </div>

        <aside class="flex min-w-0 flex-col gap-2 sm:gap-3">
          <.key_legend
            :if={!@spectator?}
            hide_key={@hide_key}
            over?={@over?}
            greens_left={@view.greens_left}
            partner_name={@name.(@partner)}
          />
          <.clue_log log={@log} words={@view.words} name={@name} />
          <details class="rounded-tb bg-tb-base-100 px-3 py-2 ring-1 ring-tb-base-content/10">
            <summary class="cursor-pointer text-sm font-medium select-none">Table colours</summary>
            <Theme.picker id="duet-picker" class="pt-2" deck_switch={false} />
          </details>
        </aside>
      </div>
    </Theme.root>
    """
  end

  @doc """
  The gallery's theme story: the grid and the key legend of one board in every
  table theme, side by side (as the Hearts themes story).
  """
  def themes(assigns) do
    v = assigns.view
    over? = v.phase == :over

    assigns =
      assign(assigns,
        partner: 1 - assigns.me,
        over?: over?,
        show_key?: assigns.seat != :spectator and !assigns.hide_key and !over?
      )

    ~H"""
    <div class="min-h-dvh bg-neutral-900 p-2 sm:p-4" data-role="duet-themes">
      <div class="mx-auto grid max-w-[90rem] grid-cols-1 gap-3 sm:gap-4 md:grid-cols-2">
        <Theme.root
          :for={t <- Theme.themes()}
          id={"th-#{t.id}"}
          theme={t.id}
          class="flex flex-col gap-2 overflow-hidden rounded-tb bg-tb-base-200 p-2 ring-1 ring-white/10"
        >
          <h2 class="flex items-center justify-between text-sm font-bold">
            {t.name}
            <span class="text-xs font-normal text-tb-base-content/60">
              {if t.dark, do: "dark", else: "light"}
            </span>
          </h2>
          <.grid
            view={@view}
            me={@me}
            partner={@partner}
            actions={@actions}
            picked={@picked}
            fresh={[]}
            show_key?={@show_key?}
            over?={@over?}
            prefix={"th-#{t.id}"}
          />
          <.key_legend
            hide_key={@hide_key}
            over?={@over?}
            partner_name="Bob"
            prefix={"th-#{t.id}"}
          />
        </Theme.root>
      </div>
    </div>
    """
  end

  defp name(_seats, me, me, false), do: "You"
  defp name(seats, s, _me, _spectator?), do: get_in(seats, [s, :name]) || "Player #{s + 1}"

  # -- the parts --------------------------------------------------------------------------

  attr :code, :string, required: true
  attr :seats, :map, required: true
  attr :me, :integer, required: true
  attr :spectator?, :boolean, required: true

  defp top_bar(assigns) do
    ~H"""
    <header class="flex items-center gap-2">
      <.link
        navigate={~p"/games"}
        class="grid size-9 shrink-0 place-items-center rounded-full bg-tb-base-100 ring-1 ring-tb-base-content/10 transition hover:bg-tb-base-300 active:scale-95"
        aria-label="Games"
      >
        <.icon name="hero-arrow-left" class="size-4" />
      </.link>
      <h1 class="truncate text-lg font-bold">Codenames Duet</h1>
      <span
        id="duet-code"
        class="shrink-0 rounded-full bg-tb-base-100 px-2 py-0.5 font-mono text-xs tracking-widest ring-1 ring-tb-base-content/10"
        title="room code"
      >
        {@code}
      </span>
      <span
        id="duet-players"
        class="ml-auto min-w-0 truncate text-xs text-tb-base-content/70 sm:text-sm"
      >
        {seat_name(@seats, 0)} &amp; {seat_name(@seats, 1)}
      </span>
    </header>
    """
  end

  defp seat_name(seats, s) do
    case seats[s] do
      %{open: true} -> "…"
      %{name: name} -> name
      _ -> "Player #{s + 1}"
    end
  end

  defp status_row(assigns) do
    v = assigns.view
    used = v.options.timer - v.timer
    assigns = assign(assigns, used: used, status: status(assigns))

    ~H"""
    <div
      id="duet-status-row"
      class="flex flex-wrap items-center gap-x-3 gap-y-1.5 rounded-tb bg-tb-base-100 px-3 py-2 ring-1 ring-tb-base-content/10"
    >
      <p id="duet-status" class="min-w-0 flex-1 basis-40 text-sm font-semibold sm:text-base">
        {@status}
      </p>
      <p
        :if={@view.clue && !@over?}
        id="duet-clue"
        class="cd-clue flex items-baseline gap-1.5 rounded-full bg-tb-neutral px-3 py-1 text-tb-neutral-content"
        title={"Clue from #{@name.(@view.giver)}"}
      >
        <span class="text-sm font-bold tracking-wide uppercase">{elem(@view.clue, 0)}</span>
        <span class="text-sm font-black tabular-nums">{elem(@view.clue, 1)}</span>
      </p>
      <div class="flex w-full items-center gap-3">
        <p id="duet-found" class="flex items-center gap-1 text-sm" title="Agents found">
          <span class="cd-agent-dot size-3 rounded-full"></span>
          <span class="font-bold tabular-nums">{@view.found}/{greens()}</span>
          <span class="text-tb-base-content/70">agents</span>
        </p>
        <div
          id="duet-timer"
          class="ml-auto flex flex-wrap items-center justify-end gap-1"
          title={"#{@view.timer} of #{@view.options.timer} timer tokens left"}
        >
          <span class="sr-only">{@view.timer} turns left</span>
          <span
            :for={t <- 1..@view.options.timer}
            data-token
            data-used={t > @view.options.timer - @used}
            class="cd-token size-3.5 rounded-full sm:size-4"
          ></span>
        </div>
      </div>
    </div>
    """
  end

  defp greens, do: @greens

  defp status(%{spectator?: true, view: %{phase: :over}}), do: "Game over (you are watching)"
  defp status(%{spectator?: true}), do: "You are watching"
  defp status(%{over?: true, view: %{result: :won}}), do: "You won together!"
  defp status(%{over?: true}), do: "You lost"
  defp status(%{open_seat?: true}), do: "Waiting for your partner to join"

  defp status(%{view: %{phase: :clue, giver: nil}, clue_giver?: true} = a),
    do: "Give the first clue, or wait for #{a.name.(a.partner)}'s"

  defp status(%{view: %{phase: :clue}, clue_giver?: true}), do: "Your turn: give a clue"

  defp status(%{view: %{phase: :clue}} = a),
    do: "#{a.name.(a.partner)} is thinking of a clue"

  defp status(%{view: %{phase: :guess}, guesser?: true}), do: "Your turn: guess"
  defp status(%{view: %{phase: :guess}} = a), do: "#{a.name.(a.partner)} is guessing"

  defp status(%{view: %{phase: :sudden_death}, guesser?: true} = a),
    do: "Guess on #{possessive(a.name.(a.partner))} side"

  defp status(%{view: %{phase: :sudden_death}} = a),
    do: "#{a.name.(a.partner)} guesses on your side"

  defp possessive("You"), do: "your"
  defp possessive(name), do: "#{name}'s"

  attr :view, :map, required: true
  attr :name, :any, required: true
  attr :me, :integer, required: true
  attr :partner, :integer, required: true

  defp over_panel(assigns) do
    ~H"""
    <section
      id="duet-over"
      data-result={@view.result}
      class={[
        "cd-over flex flex-col gap-2 rounded-tb px-4 py-3 ring-1 ring-black/10",
        if(@view.result == :won,
          do: "cd-won",
          else: "bg-tb-neutral text-tb-neutral-content"
        )
      ]}
    >
      <div class="flex items-center gap-3">
        <h2 class="text-xl font-bold">
          {if @view.result == :won, do: "You won!", else: "You lost"}
        </h2>
        <p :if={@view.score} id="duet-score" class="ml-auto text-right">
          <span class="text-3xl font-black tabular-nums">{@view.score}</span>
          <span class="block text-xs opacity-80">points</span>
        </p>
      </div>
      <p class="text-sm">{reason(@view)}</p>
      <p :if={@view.score} class="text-xs opacity-80">
        3 points for each token left after the last turn, 1 for each stop{if @view.sudden_death,
          do: ", minus 1 for sudden death"}. More than 5 is good; 9 or 10 is great.
      </p>
      <p class="text-xs opacity-80">
        The whole key shows: your side as the colour of each card, {possessive(@name.(@partner))} as the band on the top edge.
      </p>
      <div class="flex gap-2">
        <.link
          navigate={~p"/games"}
          class="flex-1 rounded-tb px-4 py-2 text-center font-semibold ring-1 ring-current/30 transition hover:bg-black/5 active:scale-[0.97]"
        >
          Games
        </.link>
        <button
          id="play-again"
          type="button"
          phx-click="play_again"
          class={[
            "flex-1 rounded-tb px-4 py-2 font-semibold shadow-sm transition hover:brightness-110 active:scale-[0.97]",
            if(@view.result == :won,
              do: "bg-tb-neutral text-tb-neutral-content",
              else: "bg-tb-primary text-tb-primary-content"
            )
          ]}
        >
          Play again
        </button>
      </div>
    </section>
    """
  end

  defp reason(%{reason: :all_found}), do: "All 15 agents found."
  defp reason(%{reason: :assassin}), do: "An assassin was touched. You both lose."
  defp reason(%{reason: :sudden_death}), do: "A wrong guess in sudden death. You both lose."
  defp reason(_view), do: ""

  attr :view, :map, required: true
  attr :me, :integer, required: true
  attr :partner, :integer, required: true
  attr :actions, :list, required: true
  attr :picked, :integer, default: nil
  attr :fresh, :list, default: []
  attr :show_key?, :boolean, required: true
  attr :over?, :boolean, required: true
  attr :prefix, :string, default: "duet", doc: "the DOM id prefix (the themes story has 8 grids)"

  defp grid(assigns) do
    v = assigns.view
    cards = for {word, i} <- Enum.with_index(v.words), do: card_info(assigns, word, i)

    assigns = assign(assigns, cards: cards)

    ~H"""
    <div class="tb-felt rounded-tb p-1.5 sm:p-3">
      <div id={"#{@prefix}-grid"} class="cd-grid" lang="en">
        <.card :for={c <- @cards} card={c} me={@me} prefix={@prefix} />
      </div>
    </div>
    """
  end

  # One card's data: its state, its key colours (yours; both at the end), its marks.
  defp card_info(%{view: v} = assigns, word, i) do
    marks = Map.get(v.bystanders, i, [])
    agent? = Map.has_key?(v.agents, i)
    guessable? = {:guess, i} in assigns.actions

    %{
      index: i,
      word: word,
      agent?: agent?,
      marks: marks,
      guessable?: guessable?,
      state: card_state(assigns.picked == i, guessable?, agent? or length(marks) == 2),
      key: own_key(v, assigns, i),
      partner_key: v.revealed_key && Enum.at(v.revealed_key[assigns.partner], i),
      fresh?: i in assigns.fresh,
      touched?: i == touched(v)
    }
  end

  # The word whose wrong guess lost the game (an assassin, or a bystander in sudden death).
  defp touched(%{result: :lost, log: [{:game_over, _, _}, {:guess, _, i, _} | _]}), do: i
  defp touched(_view), do: nil

  defp card_state(true, _guessable?, _covered?), do: "picked"
  defp card_state(_picked?, true, _covered?), do: "open"
  defp card_state(_picked?, _guessable?, true), do: "covered"
  defp card_state(_picked?, _guessable?, _covered?), do: "idle"

  defp own_key(%{revealed_key: %{} = revealed}, assigns, i), do: Enum.at(revealed[assigns.me], i)
  defp own_key(%{key: [_ | _] = key}, %{show_key?: true}, i), do: Enum.at(key, i)
  defp own_key(_view, _assigns, _i), do: nil

  attr :card, :map, required: true
  attr :me, :integer, required: true
  attr :prefix, :string, default: "duet"

  defp card(assigns) do
    {text, fit} = fit(assigns.card.word)
    assigns = assign(assigns, text: text, fit: fit)

    ~H"""
    <button
      id={"#{@prefix}-card-#{@card.index}"}
      type="button"
      class="cd-card"
      data-state={@card.state}
      data-key={@card.key}
      data-partner-key={@card.partner_key}
      data-agent={@card.agent?}
      data-marks={@card.marks != [] && Enum.join(@card.marks, " ")}
      data-fresh={@card.fresh?}
      data-touched={@card.touched?}
      disabled={!@card.guessable?}
      phx-click={@card.guessable? && "pick"}
      phx-value-index={@card.index}
      aria-label={card_label(@card)}
    >
      <span class="cd-face">
        <span class="cd-word" style={"--fit: #{@fit}"}>{@text}</span>
        <span :if={@card.agent?} class="cd-agent" aria-hidden="true">
          <.icon name="hero-user-solid" class="size-full" />
        </span>
        <span
          :if={@card.key in [:green, :assassin] and @card.state != "covered"}
          class="cd-key-icon"
          data-icon={@card.key}
          aria-hidden="true"
        >
          <.key_icon colour={@card.key} />
        </span>
        <span
          :for={side <- @card.marks}
          class="cd-mark"
          data-side={if side == @me, do: "me", else: "partner"}
          aria-hidden="true"
        ></span>
        <span :if={@card.state == "picked"} class="cd-pick" aria-hidden="true">Guess?</span>
      </span>
    </button>
    """
  end

  attr :colour, :atom, required: true

  # The icon of a key colour: a person for an agent, a skull for an assassin.
  defp key_icon(%{colour: :green} = assigns),
    do: ~H"""
    <.icon name="hero-user-solid" class="size-full" />
    """

  defp key_icon(%{colour: :assassin} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="currentColor" class="size-full">
      <path
        fill-rule="evenodd"
        clip-rule="evenodd"
        d="M12 2C6.9 2 3 5.6 3 10.3c0 2.7 1.3 4.9 3.4 6.3V19a2 2 0 0 0 2 2h7.2a2 2 0 0 0 2-2v-2.4c2.1-1.4 3.4-3.6 3.4-6.3C21 5.6 17.1 2 12 2Zm-3.5 7.3a2.1 2.1 0 1 0 0 4.2 2.1 2.1 0 0 0 0-4.2Zm7 0a2.1 2.1 0 1 0 0 4.2 2.1 2.1 0 0 0 0-4.2ZM12 14.2l-1.4 2.3h2.8L12 14.2Z"
      />
    </svg>
    """
  end

  @suffixes ~w(ization ative ation tion sion ment ness ence ance ture ship ity ing ive)

  @doc """
  A word as the card shows it, and its `--fit` (the letters of its longest line,
  for the font size). A word of 9 or more letters gets a soft hyphen (U+00AD)
  before a common ending when that makes two lines of 3 letters or more; a word
  of 10 or more with no such ending gets it in the middle. It breaks there only
  when the whole word does not fit.

      iex> CodenamesDuetWeb.Board.fit("ocean")
      {"ocean", 5}
      iex> CodenamesDuetWeb.Board.fit("representative")
      {"represent\u00ADative", 10}
  """
  @spec fit(String.t()) :: {String.t(), pos_integer}
  def fit(word) do
    len = String.length(word)

    case len >= 9 && break_at(word, len) do
      at when is_integer(at) ->
        {head, tail} = String.split_at(word, at)
        {head <> "\u00AD" <> tail, max(at + 1, len - at)}

      _ ->
        {word, len}
    end
  end

  # The break: a common ending scores 2 better than the middle, so it wins when its
  # longest line is at most 2 letters longer. Below 10 letters only an ending breaks.
  defp break_at(word, len) do
    middle = div(len + 1, 2)

    by_suffix =
      for suffix <- @suffixes,
          String.ends_with?(word, suffix),
          at = len - String.length(suffix),
          at >= 3 and len - at >= 3,
          do: {at, max(at + 1, len - at) - 2}

    by_middle = if len >= 10, do: [{middle, max(middle + 1, len - middle)}], else: []

    case by_suffix ++ by_middle do
      [] -> nil
      breaks -> breaks |> Enum.min_by(&elem(&1, 1)) |> elem(0)
    end
  end

  defp card_label(c) do
    [
      c.word,
      c.agent? && "agent found",
      c.marks != [] && "bystander mark",
      c.key && "your key: #{colour_name(c.key)}",
      c.partner_key && "partner's key: #{colour_name(c.partner_key)}"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(", ")
  end

  defp colour_name(:green), do: "agent"
  defp colour_name(:assassin), do: "assassin"
  defp colour_name(:neutral), do: "bystander"

  defp action_area(%{over?: true} = assigns), do: ~H""
  defp action_area(%{spectator?: true} = assigns), do: ~H""

  defp action_area(%{clue_giver?: true} = assigns) do
    ~H"""
    <.form
      for={@clue_form}
      id="clue-form"
      phx-change="clue_change"
      phx-submit="clue"
      class="flex flex-col gap-2 rounded-tb bg-tb-base-100 p-3 ring-1 ring-tb-base-content/10"
    >
      <label for="clue-word" class="text-sm font-semibold">
        Your clue: one word and a number
        <span class="font-normal text-tb-base-content/70">
          ({@view.greens_left} agents left on your side)
        </span>
      </label>
      <div class="flex gap-2">
        <input
          type="text"
          id="clue-word"
          name={@clue_form[:word].name}
          value={@clue_form[:word].value}
          maxlength="30"
          autocomplete="off"
          autocapitalize="none"
          spellcheck="false"
          enterkeyhint="send"
          placeholder="clue"
          aria-describedby={@clue_error && "clue-error"}
          aria-invalid={@clue_error && "true"}
          class={[
            "min-w-0 flex-1 rounded-tb border bg-tb-base-100 px-3 py-2 text-lg font-semibold tracking-wide uppercase placeholder:normal-case placeholder:font-normal placeholder:tracking-normal",
            if(@clue_error, do: "border-tb-error", else: "border-tb-base-content/25")
          ]}
        />
        <button
          id="clue-submit"
          type="submit"
          class="shrink-0 rounded-tb bg-tb-primary px-4 py-2 font-semibold text-tb-primary-content shadow-sm transition hover:brightness-110 active:scale-[0.97]"
        >
          Give clue
        </button>
      </div>
      <p :if={@clue_error} id="clue-error" class="text-sm font-medium text-tb-error" role="alert">
        <.clue_error reason={@clue_error} />
      </p>
      <fieldset>
        <legend class="sr-only">Number</legend>
        <div class="grid grid-cols-10 gap-1">
          <label
            :for={n <- 0..9}
            for={"clue-number-#{n}"}
            class={[
              "cd-num flex cursor-pointer items-center justify-center rounded-tb py-1.5 text-base font-bold tabular-nums ring-1 transition active:scale-95",
              if(to_string(@clue_form[:number].value) == to_string(n),
                do: "bg-tb-neutral text-tb-neutral-content ring-tb-neutral",
                else: "bg-tb-base-100 ring-tb-base-content/20 hover:bg-tb-base-200"
              )
            ]}
          >
            <input
              type="radio"
              id={"clue-number-#{n}"}
              name={@clue_form[:number].name}
              value={n}
              checked={to_string(@clue_form[:number].value) == to_string(n)}
              class="sr-only"
            />
            {n}
          </label>
        </div>
      </fieldset>
    </.form>
    """
  end

  defp action_area(%{guesser?: true} = assigns) do
    assigns =
      assign(assigns, picked_word: assigns.picked && Enum.at(assigns.view.words, assigns.picked))

    ~H"""
    <div
      id="guess-bar"
      class="flex min-h-14 items-center gap-2 rounded-tb bg-tb-base-100 px-3 py-2 ring-1 ring-tb-base-content/10"
    >
      <%= if @picked_word do %>
        <p class="min-w-0 flex-1 truncate text-sm">
          Guess <strong class="tracking-wide uppercase">{@picked_word}</strong>?
        </p>
        <button
          id="guess-cancel"
          type="button"
          phx-click="unpick"
          class="shrink-0 rounded-tb px-3 py-2 text-sm font-semibold ring-1 ring-tb-base-content/25 transition hover:bg-tb-base-200 active:scale-[0.97]"
        >
          Cancel
        </button>
        <button
          id="guess-confirm"
          type="button"
          phx-click="guess"
          class="shrink-0 rounded-tb bg-tb-primary px-4 py-2 font-semibold text-tb-primary-content shadow-sm transition hover:brightness-110 active:scale-[0.97]"
        >
          Guess
        </button>
      <% else %>
        <p class="min-w-0 flex-1 text-sm text-tb-base-content/80">
          Tap a word, then tap it again to guess.
        </p>
        <button
          :if={:end_turn in @actions}
          id="end-guessing"
          type="button"
          phx-click="end_turn"
          class="shrink-0 rounded-tb px-4 py-2 font-semibold ring-1 ring-tb-base-content/25 transition hover:bg-tb-base-200 active:scale-[0.97]"
        >
          End guessing
        </button>
      <% end %>
    </div>
    """
  end

  defp action_area(assigns), do: ~H""

  attr :code, :string, required: true
  attr :key, :string, required: true

  defp invite(assigns) do
    ~H"""
    <div
      id="duet-invite"
      class="flex flex-col gap-1 rounded-tb bg-tb-base-100 px-3 py-2 text-sm ring-2 ring-tb-accent"
    >
      <p>
        Send this link to your partner, or the code <strong class="font-mono tracking-widest">{@code}</strong>:
      </p>
      <span class="block truncate rounded bg-tb-base-200 px-2 py-1 font-mono text-xs select-all">
        {url(~p"/games/#{@key}/#{@code}")}
      </span>
    </div>
    """
  end

  attr :hide_key, :boolean, required: true
  attr :over?, :boolean, required: true
  attr :greens_left, :integer, default: nil
  attr :partner_name, :string, required: true
  attr :prefix, :string, default: "duet"

  defp key_legend(assigns) do
    ~H"""
    <div
      id={"#{@prefix}-key-legend"}
      class="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-tb bg-tb-base-100 px-3 py-2 text-xs ring-1 ring-tb-base-content/10"
    >
      <span class="font-semibold">{if @over?, do: "The key", else: "Your key"}</span>
      <span class="flex items-center gap-1">
        <span class="cd-swatch" data-swatch="green"><.key_icon colour={:green} /></span>agent
      </span>
      <span class="flex items-center gap-1">
        <span class="cd-swatch" data-swatch="assassin"><.key_icon colour={:assassin} /></span>assassin
      </span>
      <span class="flex items-center gap-1">
        <span class="cd-swatch" data-swatch="neutral"></span>bystander
      </span>
      <button
        :if={!@over?}
        id={if @prefix == "duet", do: "hide-key", else: "#{@prefix}-hide-key"}
        type="button"
        phx-click="toggle_key"
        aria-pressed={to_string(@hide_key)}
        class="ml-auto flex items-center gap-1 rounded-full px-2.5 py-1 font-semibold ring-1 ring-tb-base-content/20 transition hover:bg-tb-base-200 active:scale-95 aria-pressed:bg-tb-neutral aria-pressed:text-tb-neutral-content"
      >
        <.icon name={if @hide_key, do: "hero-eye-mini", else: "hero-eye-slash-mini"} class="size-3.5" />
        {if @hide_key, do: "Show my key", else: "Hide my key"}
      </button>
    </div>
    """
  end

  attr :log, :list, required: true
  attr :words, :list, required: true
  attr :name, :any, required: true

  defp clue_log(assigns) do
    ~H"""
    <section class="rounded-tb bg-tb-base-100 px-3 py-2 ring-1 ring-tb-base-content/10">
      <p class="text-sm font-semibold">Clues</p>
      <p :if={@log == []} class="py-1 text-sm text-tb-base-content/60">No clue yet.</p>
      <ol id="duet-log" class="flex flex-col divide-y divide-tb-base-content/10">
        <li
          :for={entry <- @log}
          data-clue={entry.word}
          class="flex flex-col gap-1 py-1.5"
        >
          <p class="flex items-baseline gap-1.5 text-sm">
            <%= if entry.word do %>
              <span class="text-tb-base-content/70">{@name.(entry.giver)}:</span>
              <strong class="tracking-wide uppercase">{entry.word}</strong>
              <strong class="tabular-nums">{entry.number}</strong>
            <% else %>
              <strong>Sudden death</strong>
            <% end %>
            <span :if={entry.ending} class="ml-auto text-xs text-tb-base-content/60">
              {ending(entry.ending)}
            </span>
          </p>
          <p :if={entry.guesses != []} class="flex flex-wrap gap-1">
            <span
              :for={{_seat, i, colour} <- entry.guesses}
              data-guess
              data-colour={colour}
              class="cd-guess rounded px-1.5 py-0.5 text-[11px] font-semibold tracking-wide uppercase"
            >
              {Enum.at(@words, i)}
            </span>
          </p>
        </li>
      </ol>
    </section>
    """
  end

  defp ending(:neutral), do: "bystander"
  defp ending(:stopped), do: "stopped"
  defp ending(:side_done), do: "side done"

  @doc false
  # The clues of the log, newest first: `%{giver, word, number, guesses, ending}`.
  # Sudden death is one entry with no word.
  def log_entries(log) do
    log
    |> Enum.reverse()
    |> Enum.reduce([], fn
      {:clue, giver, word, number}, acc ->
        [%{giver: giver, word: word, number: number, guesses: [], ending: nil} | acc]

      {:sudden_death, _}, acc ->
        [%{giver: nil, word: nil, number: nil, guesses: [], ending: nil} | acc]

      {:guess, seat, i, colour}, [entry | rest] ->
        [%{entry | guesses: entry.guesses ++ [{seat, i, colour}]} | rest]

      {:turn_end, _, how, _}, [entry | rest] ->
        [%{entry | ending: how} | rest]

      _event, acc ->
        acc
    end)
  end
end
