defmodule QuacksWeb.GalleryFrameLive do
  @moduledoc """
  One gallery frame (`/dev/gallery/frame/:component/:variant?<args>`): one story of
  `QuacksWeb.Gallery.Stories` with its args, built into assigns
  (`QuacksWeb.Gallery.Fixtures`), on the game background with the real app CSS.
  `QuacksWeb.GalleryLive` loads it in one iframe at a real viewport width, so the
  viewport breakpoints apply.

  A component frame copies the page's wrappers that the component's CSS needs (the
  bar's `.game-bar`, the pot's `.pot-square`, the players row grid). A screen (and
  a scenario step) is the whole game page: `GameLive.preview/3` makes the page's
  assigns from the game and `GameLive.render/1` draws it. Clicks do nothing. Args
  that reach no such state (e.g. a purple book step with no purple chip) show
  the reason instead.
  """
  use QuacksWeb, :live_view

  import QuacksWeb.BarComponents, only: [action_bar: 1, fuse_meter: 1, reward_line: 1]

  import QuacksWeb.TileComponents,
    only: [player_chip: 1, seat_loop: 1, loop_columns: 1, loop_start: 3, round_leaders: 1]

  import QuacksWeb.PotComponents, only: [pot: 1, bag_button: 1, chip_counts: 1, shown_bag: 3]

  import QuacksWeb.TrackComponents, only: [rat_track: 1]

  import QuacksWeb.ChipComponents, only: [chip: 1]

  import QuacksWeb.SoundComponents, only: [sound_settings: 1]

  alias QuacksWeb.{
    BarComponents,
    CardRevealComponents,
    GameLive,
    TileRevealComponents,
    TipComponents
  }

  alias QuacksWeb.Gallery.Stories
  alias QuacksWeb.Sounds

  # The choices that put an info row in the fuse row's place (as `GameLive` does).
  @info_choices [
    :chip_choice,
    :droplet_choice,
    :essence_bonus,
    :yellow_choice,
    :witch_offer,
    :red_choice,
    :essence_offer
  ]

  @impl true
  def mount(%{"component" => component, "variant" => variant} = params, _session, socket) do
    socket =
      assign(socket,
        page_title: "#{component}/#{variant}",
        component: component,
        variant: variant
      )

    case story(component, variant, params) do
      {story, args} ->
        case Stories.build(story, args) do
          {:ok, %{view: :screen} = fx} ->
            {:ok, socket |> GameLive.preview(fx.game, fx.preview) |> assign(view: :screen)}

          {:ok, fx} ->
            {:ok, assign(socket, fx)}

          {:error, message} ->
            {:ok, assign(socket, view: :error, message: message)}
        end

      nil ->
        {:ok, push_navigate(socket, to: "/dev/gallery")}
    end
  end

  # The story, or the story with args that took an old variant's place.
  defp story(component, variant, params) do
    case Stories.story(component, variant) do
      nil ->
        with {story, args} <- Stories.claimed(component, variant),
             do: {story, Stories.args(story, Map.merge(stringify(args), params))}

      story ->
        {story, Stories.args(story, params)}
    end
  end

  defp stringify(args), do: Map.new(args, fn {k, v} -> {k, to_string(v)} end)

  # Round 45, the chip motion story: Play patches the pot to the change, Reset back.
  @impl true
  def handle_event("motion", %{"to" => to}, socket) when to in ["before", "after"],
    do: {:noreply, assign(socket, stage: String.to_existing_atom(to))}

  # The components send their real events; the gallery ignores them.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # A screen's results step settles its standings as on the page.
  @impl true
  def handle_info({tick, _ref} = msg, socket) when tick in [:reveal_settle, :reveal_tick],
    do: GameLive.handle_info(msg, socket)

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(%{view: :setup} = assigns) do
    ~H"""
    <div
      id="gallery-frame"
      class="contents"
      data-component={@component}
      data-variant={@variant}
      data-view="setup"
    >
      {QuacksWeb.LobbyLive.render(@lobby)}
    </div>
    """
  end

  def render(%{view: :screen} = assigns) do
    ~H"""
    <div
      id="gallery-frame"
      class="contents"
      data-component={@component}
      data-variant={@variant}
      data-view="screen"
    >
      {GameLive.render(assigns)}
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} full>
      <div
        id="gallery-frame"
        class="min-h-dvh"
        data-component={@component}
        data-variant={@variant}
      >
        <.frame {assigns} />
      </div>
    </Layouts.app>
    """
  end

  defp frame(%{view: :error} = assigns) do
    ~H"""
    <p class="m-3 rounded-md bg-black/30 p-3 font-mono text-sm" data-role="gallery-error">
      These args reach no such state: {@message}
    </p>
    """
  end

  # The bottom of the game page: a stand-in for the pot's lower band, then the bar.
  # From 64rem the bar is the context column's foot (22rem wide, on the right).
  defp frame(%{view: :stage} = assigns) do
    ~H"""
    <.bottom>
      <TileRevealComponents.results_stage
        rows={@rows}
        slide={@slide}
        index={@index}
        names={@names}
        seat={@seat}
        collapsed={@collapsed}
        note={@note}
      />
      <TileRevealComponents.tile_stage reveal={@reveal} mode={:step} />
    </.bottom>
    """
  end

  defp frame(%{view: :card} = assigns) do
    ~H"""
    <.bottom>
      <CardRevealComponents.card_stage
        id="gallery-card-stage"
        card={@card}
        reveals={@reveals}
        order={@order}
        seat={@seat}
        names={@names}
        game={@game}
      />
      <.button variant={:primary} class="min-h-12 w-full text-base">Continue</.button>
    </.bottom>
    """
  end

  defp frame(%{view: :bar} = assigns) do
    fuse? = assigns.game.phase == :potions and assigns.choice not in @info_choices
    assigns = assign(assigns, fuse?: fuse?, crow?: assigns.choice == :blue_choice)

    ~H"""
    <.bottom tip={@tip && @tip.key}>
      <:context :if={@crow?}>
        <BarComponents.crow_panel actions={@actions} game={@game} me={@me} />
      </:context>
      <div class="game-tray">
        <TipComponents.tip_card :if={@tip} tip={@tip} class={tip_shift(@tip.key)} />
      </div>
      <div
        :if={@fuse?}
        class={["flex min-w-0 items-center gap-2", @crow? && "max-lg:hidden"]}
        data-role="fuse-row"
      >
        <.fuse_meter game={@game} seat={@seat} />
        <.reward_line game={@game} seat={@seat} />
      </div>
      <BarComponents.bar_choice
        :if={@choice}
        choice={@choice}
        actions={@actions}
        game={@game}
        me={@me}
        seat={@seat}
      />
      <.action_bar
        :if={!@choice or @crow?}
        actions={@actions}
        stop_slot={@stop_slot}
        class={@crow? && "max-lg:hidden"}
      />
    </.bottom>
    """
  end

  defp frame(%{view: :pot} = assigns) do
    ~H"""
    <div class="pot-box flex h-dvh items-center justify-center p-2">
      <div class="pot-square pot-hearth relative" data-role="pot-area">
        <.pot game={@game} seat={@seat} class="block size-full" rings={@rings} flask={@flask} />
      </div>
    </div>
    """
  end

  # Round 45: the large pot before and after one change; Play runs it (a patch, so
  # `PotMotion` plays as in the game, with your own pot's sounds).
  defp frame(%{view: :motion} = assigns) do
    after? = assigns[:stage] == :after
    game = if after?, do: assigns.after, else: assigns.before
    me = game.players[assigns.seat]

    assigns =
      assign(assigns,
        game: game,
        me: me,
        after?: after?,
        bag: shown_bag(game, assigns.seat, after? and assigns.bagged),
        flask: if(me.flask, do: :full, else: :empty)
      )

    ~H"""
    <div class="mx-auto flex h-dvh max-w-xl flex-col gap-2 p-2" data-role="motion">
      <div class="flex items-center gap-2">
        <button
          id="motion-play"
          type="button"
          class="paper rounded-lg px-4 py-2 font-semibold text-ink shadow-sm ring-1 ring-black/20 transition active:scale-[0.97] disabled:opacity-50"
          phx-click="motion"
          phx-value-to="after"
          disabled={@after?}
        >
          Play
        </button>
        <button
          id="motion-reset"
          type="button"
          class="rounded-lg px-4 py-2 text-parchment ring-1 ring-parchment/40 transition active:scale-[0.97] disabled:opacity-50"
          phx-click="motion"
          phx-value-to="before"
          disabled={!@after?}
        >
          Reset
        </button>
        <span class="font-mono text-xs text-parchment-dim">{@kind}</span>
      </div>
      <div class="pot-box relative flex min-h-0 flex-1 items-center justify-center">
        <div class="pot-square pot-hearth relative" data-role="pot-area">
          <.pot
            game={@game}
            seat={@seat}
            class="block size-full"
            flask={@flask}
            bagged={@after? && @bagged}
          />
        </div>
        <.bag_button count={length(@bag)} class="absolute right-1 bottom-1" />
      </div>
      <section class="paper rounded-lg p-2 text-ink">
        <h2 class="text-xs font-semibold text-ink-soft">In the bag: {length(@bag)}</h2>
        <.chip_counts chips={@bag} id="motion-bag-counts" />
      </section>
    </div>
    """
  end

  defp frame(%{view: :tiles} = assigns) do
    ~H"""
    <div class="space-y-1 px-2 pt-2 lg:px-6">
      <nav
        id="players-row"
        class="replay-done -mx-2 grid gap-1 px-2 pt-1.5 pb-0.5"
        style={"grid-template-columns: repeat(#{2 * loop_columns(length(@game.seats))}, minmax(0, 1fr))"}
        aria-label="Players"
        data-role="players-row"
      >
        <.player_chip
          :for={{seat, row, col} <- seat_loop(@game.seats)}
          game={@game}
          seat={seat}
          name={@names[seat]}
          you={seat == @seat}
          bot={seat in @bots}
          lead={seat in round_leaders(@game)}
          row={row}
          col={col}
          start={loop_start(length(@game.seats), row, col)}
        />
      </nav>
    </div>
    """
  end

  defp frame(%{view: :track} = assigns) do
    ~H"""
    <div class="px-2 pt-3 lg:px-6">
      <.rat_track game={@game} seat={@seat} names={@names} />
    </div>
    """
  end

  defp frame(%{view: :chips} = assigns) do
    ~H"""
    <div class="space-y-3 p-3">
      <section :for={size <- [:xs, :sm, :md, :lg]} class="space-y-1" data-size={size}>
        <h2 class="font-mono text-xs text-parchment-dim">:{size}</h2>
        <div class="flex flex-wrap items-center gap-x-3 gap-y-2">
          <span :for={colour <- @colours} class="flex items-center gap-1.5" title={colour}>
            <.chip :for={value <- @values} chip={{colour, value}} size={size} />
          </span>
        </div>
      </section>
      <section class="paper space-y-1 rounded-lg p-2 text-ink">
        <h2 class="font-mono text-xs">on parchment, :sm and :lg</h2>
        <div class="flex flex-wrap items-center gap-2">
          <span :for={colour <- @colours} class="flex items-center gap-1.5">
            <.chip :for={value <- @values} chip={{colour, value}} size={:sm} />
            <.chip chip={{colour, List.last(@values)}} size={:lg} />
          </span>
        </div>
      </section>
    </div>
    """
  end

  # The Sounds story: a button per sound (app.js `quacks:sound`), the game's
  # moments first, then every chip with the sound it plays (its own file, or the
  # fallback), and the menu's Sound row to set the volume.
  defp frame(%{view: :sounds} = assigns) do
    assigns =
      assign(assigns,
        moments: [
          {"bloop", "Droplet moves"},
          {"ruby", "Ruby"},
          {Sounds.fortune_sound(), "Fortune teller"},
          {"gameover", "Game over"},
          {Sounds.flask_sound(), "Flask (FL1)"}
        ],
        shuffles:
          for {label, name, what} <- Sounds.shuffle_candidates() do
            picked = if name == Sounds.shuffle_sound(), do: ", in the game"
            {name, "#{label}: #{what}#{picked}"}
          end,
        booms:
          for {label, name, what} <- Sounds.boom_candidates() do
            picked = if name == Sounds.boom_sound(), do: ", in the game"
            {name, "#{label}: #{what}#{picked}"}
          end,
        chips: Enum.map(Sounds.gallery_chips(), &{&1, Sounds.chip_sound(&1)})
      )

    ~H"""
    <div class="mx-auto max-w-xl space-y-4 p-3" data-role="sounds">
      <p class="text-sm text-parchment-dim">
        Tap a button to hear it at its game level. Sound must be On. iPhone: the silent switch mutes the game.
      </p>
      <section class="paper space-y-2 rounded-lg p-3 text-ink">
        <.sound_settings id="gallery-sound-settings" />
      </section>
      <section class="space-y-1.5">
        <h2 class="font-mono text-xs text-parchment-dim">moments</h2>
        <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
          <.sound_button :for={{name, label} <- @moments} :if={name} name={name} label={label} />
        </div>
      </section>
      <section class="space-y-1.5">
        <h2 class="font-mono text-xs text-parchment-dim">explosion: your pot bursts</h2>
        <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <.sound_button :for={{name, label} <- @booms} name={name} label={label} />
        </div>
      </section>
      <section class="space-y-1.5">
        <h2 class="font-mono text-xs text-parchment-dim">
          chip shuffle: the chips go back to the bag
        </h2>
        <div class="grid grid-cols-1 gap-2 sm:grid-cols-3">
          <.sound_button :for={{name, label} <- @shuffles} name={name} label={label} />
        </div>
      </section>
      <section class="space-y-1.5">
        <h2 class="font-mono text-xs text-parchment-dim">your draw: every chip</h2>
        <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
          <.sound_button :for={{chip, name} <- @chips} name={name} chip={chip} />
        </div>
      </section>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, default: nil
  attr :chip, :any, default: nil

  defp sound_button(assigns) do
    ~H"""
    <button
      type="button"
      id={"sound-#{if @chip, do: "chip-#{elem(@chip, 0)}-#{elem(@chip, 1)}", else: @name}"}
      class="paper flex min-h-12 items-center gap-2 rounded-lg px-3 py-2 text-left text-sm text-ink shadow-sm ring-1 ring-black/20 transition hover:brightness-105 active:scale-[0.97]"
      phx-click={JS.dispatch("quacks:sound", detail: %{name: @name})}
      data-role="sound-button"
      data-sound={@name}
    >
      <.chip :if={@chip} chip={@chip} size={:sm} />
      <span class="min-w-0 flex-1">
        <span class="block font-semibold">
          {chip_label(@chip) || @label}
        </span>
        <span class="block truncate font-mono text-[11px] text-ink-soft">{@name}</span>
      </span>
    </button>
    """
  end

  # Round 44: a locoweed's sound goes by how far it moved, not by its value.
  defp chip_label(nil), do: nil
  defp chip_label({:locoweed, n}), do: "locoweed, moved #{n}"
  defp chip_label({colour, value}), do: "#{colour} #{value}"

  attr :tip, :string, default: nil
  slot :context, doc: "from 64rem: the context column's panel, over the bar"
  slot :inner_block, required: true

  # `#game` with `data-tip` lights the hint's target (app.css `[data-tip]`).
  defp bottom(assigns) do
    ~H"""
    <div id="game" class="flex h-dvh flex-col" data-tip={@tip}>
      <div class="flex min-h-0 flex-1">
        <div class="min-h-0 min-w-0 flex-1" aria-hidden="true">
          <div class="pot-hearth mx-auto aspect-square h-full max-w-full rounded-full opacity-60" />
        </div>
        <aside
          :if={@context != []}
          class="hidden w-[22rem] shrink-0 flex-col justify-end p-3 pl-0 lg:flex"
          data-area="context"
        >
          {render_slot(@context)}
        </aside>
      </div>
      <footer class="game-bar lg:ml-auto lg:w-[22rem]" data-area="bar">
        {render_slot(@inner_block)}
      </footer>
    </div>
    """
  end

  # As `GameLive` places the hint in the bar's band.
  defp tip_shift("bag"), do: "-mb-12"
  defp tip_shift("risk"), do: "ml-[4.5rem]"
  defp tip_shift(_key), do: nil
end
