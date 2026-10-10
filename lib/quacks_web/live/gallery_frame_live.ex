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

  import QuacksWeb.GameComponents,
    only: [
      chip: 1,
      pot: 1,
      player_chip: 1,
      rat_track: 1,
      fuse_meter: 1,
      reward_line: 1,
      seat_loop: 1,
      loop_columns: 1,
      loop_start: 3,
      round_leaders: 1
    ]

  alias QuacksWeb.{CardRevealComponents, GameLive, TileRevealComponents, TipComponents}
  alias QuacksWeb.Gallery.Stories

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

  # The components send their real events; the gallery ignores them.
  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # A screen's results step settles its standings as on the page.
  @impl true
  def handle_info({tick, _ref} = msg, socket) when tick in [:reveal_settle, :reveal_tick],
    do: GameLive.handle_info(msg, socket)

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
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
        <GameLive.crow_panel actions={@actions} game={@game} me={@me} />
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
      <GameLive.bar_choice
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

  attr :actions, :list, required: true
  attr :stop_slot, :atom, required: true
  attr :class, :any, default: nil

  # A copy of the page's action bar (it is inline in `GameLive.render/1`).
  # REVIEW: if GameLive moves it into a component, use that here.
  defp action_bar(assigns) do
    ~H"""
    <section
      class={["action-bar *:min-h-12 *:touch-manipulation", @class]}
      data-role="action-bar"
    >
      <.button disabled={@stop_slot not in @actions} data-slot="stop">
        {if @stop_slot == :resume, do: "Resume", else: "Stop"}
        <.kbd>s</.kbd>
      </.button>
      <.button
        disabled={:use_flask not in @actions}
        class="flex-col gap-0! px-1! max-lg:hidden!"
        aria-label="Use the flask"
        data-slot="flask"
      >
        <.piece_icon name={:flask} class="size-5" />
        <.kbd>f</.kbd>
      </.button>
      <.button disabled={:draw not in @actions} variant={:primary} data-slot="draw">
        Draw
        <.kbd>d</.kbd>
      </.button>
    </section>
    """
  end

  # As `GameLive` places the hint in the bar's band.
  defp tip_shift("bag"), do: "-mb-12"
  defp tip_shift("risk"), do: "ml-[4.5rem]"
  defp tip_shift(_key), do: nil
end
