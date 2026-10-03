defmodule QuacksWeb.GameLive do
  @moduledoc """
  The game page, `/g/:id`, for 1 to 8 players. The game itself lives in a
  `Quacks.GameServer` process; this LiveView asks it for a seat on mount (by the
  browser's player token), subscribes to the game's PubSub topic and re-renders on
  every `{:game, id, game}` broadcast. Every button comes from
  `Quacks.Game.legal_actions/2` for this browser's seat and every click goes through
  `Quacks.GameServer.apply/3`. The page itself knows no rules. A browser without a
  seat (the game is full) watches: it sees every pot and no buttons.

  Before the game begins (`GameServer` status `:waiting`) the page is the configure
  screen: the player count (a − / + stepper), the Ingredient books, the options
  (`QuacksWeb.SetupComponents`), a link to share, one slot per seat and "Start game"
  (`GameServer.begin/2`). Only the host (the creator) may change the settings; each
  change goes through `GameServer.configure/3`, and the broadcast that follows makes
  every waiting page read the table again, so the others see the settings read-only.
  Closing the page before the start frees the seat (`terminate/2`).

  The layout, top to bottom: the header ("You are" and your seat colour, which also
  runs along the top edge), your status, the players row (one chip per seat; a tap
  opens that player's sheet), the pot, and the bottom bar with only Stop/Resume and
  Draw. Around the pot: the witches (top left), this round's fortune card (top
  right), the flask (bottom left) and the bag (bottom right). The log, the share
  link and the books are in the menu. A new fortune card shows in a small dialog
  once per round.

  The host's browser remembers the last settings (localStorage, the `ConfigMemory`
  hook in app.js): each change is pushed as `"save_config"`, and a fresh configure
  screen sends them back once as `"load_config"`.

  A new fortune card shows in one dialog; when it asks this seat a choice, the
  choice is in the same dialog. The shop has two steps, each its own dialog: first
  your chips, the buy (one row of chip tiles per colour) and "Done"; then "Spend
  rubies" (the ruby options and witch calls) and "Keep rubies". The first step opens
  when the round results close. A seat that can buy nothing (it exploded and took
  the VP, or has too few coins) skips it: the results say "OK" and the rubies step
  follows. A buy that leaves nothing else to do ends the round for this seat at once.

  In every choice between chips (crow skull, toadstool, silver witch, fortune cards,
  chip actions) the chips themselves are the buttons (`chip_picks/1`); only options
  without a chip ("Return all", "Done", "3 rubies") are text buttons.

  Round 9 with 2+ players is the "Stir!" round: everyone picks Draw or Stop, and the
  picks resolve together. A banner says so; after the pick both buttons are disabled
  until the step resolves, and a stopped player has no Resume.

  While everyone brews or shops at the same time, each player chip shows what that
  seat does now (`GameComponents.seat_state/2`), and a player who has finished sees
  who they wait for. A stopped player's Stop button becomes Resume.

  With The Herb Witches the page also shows the 3 witches (a sheet on phones, the
  right column on large screens) with a button to call one when the engine allows
  it. The overflow bowl shows under the pot once it has chips.

  With the reverse pot side (`pot_side: :back`) the test-tube rack shows under the
  pot, and each waiting droplet move opens the "Droplet" dialog (pot droplet or
  test tube). After the evaluation it waits for the round results, like the shop.

  With The Alchemists every seat first picks a patient (a dialog with 3 cards).
  The flask strip runs above the pot: the patient badge (it opens the patient
  sheet) and the essence marker. A lower essence space is picked in a dialog with
  a stepper; Chicken eyes and Vampirism pick a chip; Ear worm draws with the Draw
  button. Next round, the patient's offers open as a decision under the drawn
  chip, Nervousness lays its chips out above the action bar and Forgetfulness
  returns a pot chip from its sheet.

  Actions travel to the browser as a URL-safe binary (see `encode/1`) so tuples like
  `{:buy, [{:green, 2}]}` survive the round trip without a parser per action shape.
  """
  use QuacksWeb, :live_view

  import QuacksWeb.GameComponents

  import QuacksWeb.SetupComponents

  import QuacksWeb.AlchemistsComponents

  alias Quacks.{Game, GameServer, Player}
  alias Quacks.Game.Fortune
  alias Quacks.Rules.{Alchemists, Books, Chips, PotTrack, TestTubes}
  alias QuacksWeb.Replay

  # The shop, one row per colour in the board's step B order; each row runs from
  # the lowest value to the highest. Chips not in the game's shop drop out.
  @shop_rows [
    [{:orange, 1}, {:orange, 6}],
    [{:blue, 1}, {:blue, 2}, {:blue, 4}],
    [{:red, 1}, {:red, 2}, {:red, 4}],
    [{:yellow, 1}, {:yellow, 2}, {:yellow, 4}],
    [{:black, 1}],
    [{:green, 1}, {:green, 2}, {:green, 4}],
    [{:purple, 1}],
    [{:locoweed, 1}]
  ]

  # The colours with an ingredient book (white has none), for `offer_books/1`.
  @book_colours [:orange, :blue, :red, :yellow, :black, :green, :purple, :locoweed]

  @doc "Join game `id`: take a free seat, or watch when the game is full."
  @impl true
  def mount(%{"id" => id}, session, socket) do
    case GameServer.get(id) do
      {:ok, table} ->
        if connected?(socket), do: Phoenix.PubSub.subscribe(Quacks.PubSub, GameServer.topic(id))

        seat =
          case GameServer.claim_seat(id, session["player_token"]) do
            {:ok, seat} -> seat
            {:error, _full} -> nil
          end

        # The claim may have added our own name; read the table again for it.
        {:ok, table} = if seat, do: GameServer.get(id), else: {:ok, table}

        {:ok,
         socket
         |> assign(
           page_title: "Quacks #{id}",
           id: id,
           token: session["player_token"],
           seat: seat,
           seed: table.seed,
           copied: false,
           seen: Map.get(table.seen, seat, %{})
         )
         |> assign_table(table)
         |> put_game(table.game)}

      {:error, :not_found} ->
        {:ok,
         socket |> put_flash(:error, "Game #{id} does not exist.") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("action", %{"action" => encoded}, %{assigns: %{seat: seat}} = socket)
      when is_integer(seat) do
    with {:ok, action} <- decode(encoded),
         {:ok, game} <- GameServer.apply(socket.assigns.id, seat, action) do
      {:noreply, put_game(socket, finish_shop(game, socket.assigns.id, seat, action))}
    else
      {:error, {:illegal_action, action, _phase}} ->
        {:noreply, put_flash(socket, :error, "#{label(action)} is not allowed right now.")}

      {:error, :bad_action} ->
        {:noreply, put_flash(socket, :error, "That move could not be read.")}
    end
  end

  def handle_event("action", _params, socket),
    do: {:noreply, put_flash(socket, :error, "You are watching this game.")}

  # The shop form re-sends every ticked checkbox on each change; no key means none.
  def handle_event("select", params, socket) do
    selected =
      params
      |> Map.get("chips", [])
      |> Enum.flat_map(fn encoded ->
        case decode(encoded) do
          {:ok, {colour, value}} when is_atom(colour) and is_integer(value) -> [{colour, value}]
          _ -> []
        end
      end)
      |> Enum.sort()

    {:noreply, assign(socket, selected: selected)}
  end

  # The configure screen (host only): the player count stepper and the two forms.
  def handle_event("players", %{"count" => count}, socket) do
    case Integer.parse(count) do
      {players, ""} -> {:noreply, configure(socket, %{players: players})}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("sets", %{"sets" => params} = form, socket) when is_map(params) do
    # The Herb Witches change no book; without The Alchemists locoweed III falls back.
    alchemists = form["alchemists"] == "true"
    config = %{sets: parse_sets(params, alchemists)} |> Map.merge(expansions(form, alchemists))
    {:noreply, configure(socket, config)}
  end

  def handle_event("rules", %{"rules" => params}, socket) when is_map(params),
    do: {:noreply, configure(socket, %{rules: parse_rules(params)})}

  def handle_event("rule_step", %{"rule" => rule, "to" => to}, socket),
    do: {:noreply, configure(socket, %{rules: step_rule(socket.assigns.rules, rule, to)})}

  # A fresh configure screen gets the host's last settings from the browser (the
  # `ConfigMemory` hook in app.js). Bad or stale values fall back to the defaults.
  def handle_event("load_config", saved, %{assigns: %{fresh: true}} = socket)
      when is_map(saved) do
    alchemists = saved["alchemists"] == true
    form = fn key -> if is_map(saved[key]), do: saved[key], else: %{} end
    players = if is_integer(saved["players"]), do: saved["players"], else: socket.assigns.players

    players =
      players |> min(8) |> max(max(map_size(socket.assigns.names), 1))

    config =
      Map.merge(
        %{
          players: players,
          sets: parse_sets(form.("sets"), alchemists),
          rules: parse_rules(form.("rules"))
        },
        expansions(%{"expansion" => to_string(saved["expansion"] == true)}, alchemists)
      )

    case GameServer.configure(socket.assigns.id, socket.assigns.token, config) do
      {:ok, table} -> {:noreply, assign_table(socket, table)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("load_config", _saved, socket), do: {:noreply, socket}

  # Bots (host only): "Add bot" on an empty seat row puts a named bot there at once;
  # × empties the seat again.
  def handle_event("add_bot", %{"seat" => seat}, socket) do
    case GameServer.add_bot(socket.assigns.id, socket.assigns.token, String.to_integer(seat)) do
      {:ok, _seat} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash(socket, :error, "That seat is not free now.")}
    end
  end

  def handle_event("remove_bot", %{"seat" => seat}, socket) do
    GameServer.remove_bot(socket.assigns.id, socket.assigns.token, String.to_integer(seat))
    {:noreply, socket}
  end

  def handle_event("begin", _params, socket) do
    case GameServer.begin(socket.assigns.id, socket.assigns.token) do
      {:ok, game} -> {:noreply, socket |> reseat() |> put_game(game)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Only the creator can start.")}
    end
  end

  # The essence choice's stepper: a space between 0 and the reach.
  def handle_event("essence_pick", %{"space" => space}, socket) do
    case {Integer.parse(space), socket.assigns.me} do
      {{n, ""}, %{essence_pending: {:space, reach}}} when n in 0..reach//1 ->
        {:noreply, assign(socket, essence_pick: n)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("undo", _params, socket) do
    case GameServer.undo(socket.assigns.id) do
      {:ok, game} -> {:noreply, put_game(socket, game)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Undo is for solo games only.")}
    end
  end

  # Solo menu: a new game for the same books, house rules and expansion.
  def handle_event("new_game", _params, socket) do
    %{sets: sets, rules: rules, expansions: expansions} = socket.assigns.game
    {:ok, id} = GameServer.start(socket.assigns.players, nil, sets, rules, expansions)
    {:ok, 0} = GameServer.claim_seat(id, socket.assigns.token)
    {:noreply, push_navigate(socket, to: ~p"/g/#{id}")}
  end

  # After the game: the next game for the same table (`GameServer.play_again/2`).
  # Every page hears `{:play_again, id, new_id}` and moves there too.
  def handle_event("play_again", _params, socket) do
    case GameServer.play_again(socket.assigns.id, socket.assigns.token) do
      {:ok, new_id} -> {:noreply, push_navigate(socket, to: ~p"/g/#{new_id}")}
      _error -> {:noreply, put_flash(socket, :error, "Play again is not possible.")}
    end
  end

  def handle_event("lobby", _params, socket), do: {:noreply, push_navigate(socket, to: ~p"/")}

  # The fortune card or the round results closed: the table keeps it, so a reload
  # does not open them again (`GameServer.ack/4`).
  def handle_event(
        "seen",
        %{"kind" => kind, "round" => round},
        %{assigns: %{seat: seat}} = socket
      )
      when is_integer(seat) and kind in ["card", "results"] and is_integer(round) do
    kind = String.to_existing_atom(kind)
    GameServer.ack(socket.assigns.id, seat, kind, round)
    {:noreply, update(socket, :seen, &Map.put(&1, kind, round))}
  end

  def handle_event("seen", _params, socket), do: {:noreply, socket}

  # The browser copied the link (see `copy_link/1`); say so for 2 seconds.
  def handle_event("copied", _params, socket) do
    Process.send_after(self(), :uncopied, 2000)
    {:noreply, assign(socket, copied: true)}
  end

  # The nickname: the seat row's input sends it as you type (`"name"`), the menu's
  # input when it loses focus (`"value"`).
  def handle_event("rename", %{"name" => name}, socket),
    do: handle_event("rename", %{"value" => name}, socket)

  def handle_event("rename", %{"value" => name}, %{assigns: %{seat: seat}} = socket)
      when is_integer(seat) and is_binary(name) do
    :ok = GameServer.rename(socket.assigns.id, seat, name)
    {:noreply, socket}
  end

  def handle_event("rename", _params, socket), do: {:noreply, socket}

  # The colour picker in your seat row. A colour taken in the meantime does nothing:
  # the broadcast re-renders it as taken.
  def handle_event("colour", %{"colour" => colour}, %{assigns: %{seat: seat}} = socket)
      when is_integer(seat) do
    with {colour, ""} <- Integer.parse(to_string(colour)),
         do: GameServer.set_colour(socket.assigns.id, seat, colour)

    {:noreply, socket}
  end

  def handle_event("colour", _params, socket), do: {:noreply, socket}

  @impl true
  # The game began: seats were renumbered, so ask for ours again.
  def handle_info({:game, _id, game}, %{assigns: %{game: nil}} = socket),
    do: {:noreply, socket |> clear_flash(:info) |> reseat() |> put_game(game)}

  # Our own moves arrive twice (reply and broadcast); skip the copy we already have.
  # A broadcast sent before our own call's reply can come after it: every action
  # adds to the log, so a shorter log is an older game, and we skip it too.
  def handle_info({:game, _id, game}, socket) do
    current = socket.assigns.game

    if game == current or length(game.log) < length(current.log),
      do: {:noreply, socket},
      else: {:noreply, put_game(socket, game)}
  end

  # While waiting, a seat change may also change the creator.
  def handle_info({:names, _id, _names}, %{assigns: %{game: nil}} = socket),
    do: {:noreply, reseat(socket)}

  def handle_info({:names, id, _names}, socket) do
    {:ok, table} = GameServer.get(id)
    {:noreply, assign(socket, names: table.names, colours: table.colours)}
  end

  # The host left the waiting table and this seat took over.
  def handle_info({:host, _id, seat}, %{assigns: %{game: nil, seat: seat}} = socket)
      when is_integer(seat),
      do: {:noreply, socket |> reseat() |> put_flash(:info, "You are now the host.")}

  def handle_info({:host, _id, _seat}, socket), do: {:noreply, socket}

  # Someone pressed "Play again": everyone follows to the new game.
  def handle_info({:play_again, _id, new_id}, socket),
    do: {:noreply, push_navigate(socket, to: ~p"/g/#{new_id}")}

  def handle_info(:uncopied, socket), do: {:noreply, assign(socket, copied: false)}

  # A page closed before the game began gives its seat back.
  @impl true
  def terminate(_reason, %{assigns: %{game: nil, seat: seat}} = socket) when is_integer(seat),
    do: GameServer.leave_seat(socket.assigns.id, socket.assigns.token)

  def terminate(_reason, _socket), do: :ok

  defp reseat(socket) do
    %{id: id, token: token} = socket.assigns
    {:ok, table} = GameServer.get(id)

    seat =
      case GameServer.claim_seat(id, token) do
        {:ok, seat} -> seat
        {:error, _full} -> nil
      end

    socket |> assign(seat: seat) |> assign_table(table)
  end

  # The table's seats and settings. `@players` is the seat count (while waiting: the
  # count the host picked); `@sets`, `@rules` and `@expansion` feed the configure forms.
  defp assign_table(socket, table) do
    assign(socket,
      players: table.players,
      names: table.names,
      colours: table.colours,
      bots: table.bots,
      creator: table.creator,
      sets: table.sets || %{},
      rules: Map.merge(Game.default_rules(), table.rules || %{}),
      expansion: :herb_witches in table.expansions,
      alchemists: :alchemists in table.expansions,
      # Nobody changed the books or options yet (see "load_config").
      fresh:
        table.sets in [nil, %{}] and table.rules in [nil, %{}] and
          MapSet.size(table.expansions) == 0
    )
  end

  # The configure form's two toggles as `GameServer.configure/3` options.
  defp expansions(form, alchemists) do
    %{
      expansion: if(form["expansion"] == "true", do: :herb_witches),
      expansions: if(alchemists, do: [:alchemists], else: [])
    }
  end

  # Send the host's change to the server; the reply is the new table, which the
  # browser keeps for the next game (see "load_config").
  defp configure(socket, config) do
    case GameServer.configure(socket.assigns.id, socket.assigns.token, config) do
      {:ok, table} ->
        socket |> assign_table(table) |> push_event("save_config", saved_config(table))

      {:error, :not_creator} ->
        put_flash(socket, :error, "Only the host can change the game.")

      {:error, _} ->
        put_flash(socket, :error, "That setting is not possible now.")
    end
  end

  # The table's settings in the shape of the configure forms (strings), for the
  # browser's memory; "load_config" reads them back through `parse_sets/1` and
  # `parse_rules/1`.
  defp saved_config(table) do
    form = fn map -> Map.new(map || %{}, fn {key, value} -> {key, to_string(value)} end) end

    %{
      players: table.players,
      sets: form.(table.sets),
      rules: form.(table.rules),
      expansion: :herb_witches in table.expansions,
      alchemists: :alchemists in table.expansions
    }
  end

  # Phones: one screen, no page scroll. Rows: header, status, notices, the pot (takes
  # the free space), the bottom bar. Bag, log, players, card text and the menu are
  # sheets; a decision opens as a dialog over the pot. Large screens add a right
  # column where the bag, log and players sheets show in place.
  @impl true
  def render(%{game: nil} = assigns) do
    assigns = assign(assigns, host: host?(assigns.seat, assigns.creator))

    ~H"""
    <Layouts.app flash={@flash} style={seat_style(@colours)}>
      <h1 class="font-hand text-2xl font-bold">
        <.link navigate={~p"/"}>Quacks</.link>
        <span class="font-mono text-xs font-normal text-parchment-dim">{@id}</span>
      </h1>
      <div :if={@host} id="config-memory" phx-hook="ConfigMemory" data-fresh={@fresh} hidden />
      <section class="paper space-y-3 rounded-lg p-3" aria-label="New game">
        <h2 class="text-lg font-bold">New game</h2>
        <p :if={!@host and @creator} class="text-sm text-ink-soft" data-role="read-only">
          {name(@names, @creator)} sets the game up.
        </p>
        <div class="flex items-center gap-3" data-role="player-count">
          <span class="font-semibold">Players</span>
          <.button
            phx-click="players"
            phx-value-count={@players - 1}
            disabled={!@host or @players <= max(map_size(@names), 1)}
            aria-label="Fewer players"
            variant={:secondary}
            class="size-11 px-0 text-xl"
          >
            −
          </.button>
          <span class="w-6 text-center text-2xl font-bold tabular-nums" data-role="count">
            {@players}
          </span>
          <.button
            phx-click="players"
            phx-value-count={@players + 1}
            disabled={!@host or @players >= 8}
            aria-label="More players"
            variant={:secondary}
            class="size-11 px-0 text-xl"
          >
            +
          </.button>
        </div>
        <ol class="space-y-1" aria-label="Seats">
          <li
            :for={seat <- 0..(@players - 1)}
            class="flex min-h-9 flex-wrap items-center gap-x-2 rounded-md bg-parchment-light px-2"
            data-seat={seat}
            data-role="seat-slot"
          >
            <.seat_dot :if={@names[seat]} seat={seat} />
            <span
              :if={!@names[seat]}
              class="size-2.5 shrink-0 rounded-full ring-1 ring-ink-soft/40 ring-inset"
            />
            <form
              :if={seat == @seat}
              id="rename-form"
              phx-change="rename"
              phx-submit="rename"
              class="min-w-0 flex-1"
            >
              <input
                type="text"
                name="name"
                id="seat-name"
                phx-hook="NameMemory"
                value={if @names[seat] != GameServer.default_name(seat), do: @names[seat]}
                placeholder={GameServer.default_name(seat)}
                phx-debounce="blur"
                maxlength="20"
                autocomplete="off"
                aria-label="Your name"
                class="w-full border-0 border-b border-dashed border-transparent bg-transparent py-1.5 text-base font-semibold text-ink outline-none transition-colors duration-150 placeholder:text-ink placeholder:opacity-100 hover:border-ink-soft/40 focus:border-ink-soft focus:placeholder:text-ink-soft/60"
              />
            </form>
            <span :if={@names[seat] && seat != @seat} class="font-semibold">{@names[seat]}</span>
            <.bot_badge :if={@bots[seat]} />
            <span :if={!@names[seat]} class="text-ink-soft italic">empty</span>
            <span :if={@names[seat] && seat == @creator} class="text-xs text-ink-soft">host</span>
            <span :if={seat == @seat} class="ml-auto text-xs font-semibold">you</span>
            <.colour_picker :if={seat == @seat} colours={@colours} seat={seat} />
            <button
              :if={@host and @bots[seat]}
              type="button"
              phx-click="remove_bot"
              phx-value-seat={seat}
              aria-label={"Remove #{@names[seat]}"}
              data-role="remove-bot"
              class="-mr-1 ml-auto grid size-9 cursor-pointer place-items-center rounded-full text-ink-soft transition-[color,background-color,transform] duration-150 ease-out hover:bg-ink/10 hover:text-ink active:scale-90"
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
            <button
              :if={@host and !@names[seat]}
              type="button"
              phx-click="add_bot"
              phx-value-seat={seat}
              data-role="add-bot"
              class="-mr-1 ml-auto min-h-9 cursor-pointer rounded-full px-3 text-sm font-semibold text-ink-soft transition-[color,background-color,transform] duration-150 ease-out hover:bg-ink/10 hover:text-ink active:scale-95"
            >
              + Add bot
            </button>
          </li>
        </ol>
        <p class="rounded-md bg-droplet/25 px-2 py-1" data-role="waiting-for-players">
          {map_size(@names)} of {@players} seated.
        </p>
        <div :if={@players > 1} class="space-y-1 text-sm">
          <span class="font-semibold">Share this link to invite players</span>
          <div class="flex gap-2">
            <input
              type="text"
              readonly
              value={url(~p"/g/#{@id}")}
              aria-label="Game link"
              data-role="share-link"
              class="min-w-0 flex-1 rounded-md border border-ink-soft bg-parchment-light px-2 py-2 font-mono text-sm text-ink"
            />
            <.copy_link url={url(~p"/g/#{@id}")} copied={@copied} />
          </div>
        </div>
      </section>
      <section class="paper rounded-lg p-3" aria-label="Settings">
        <.books_form
          sets={@sets}
          expansion={@expansion}
          alchemists={@alchemists}
          pot_side={@rules.pot_side}
          players={@players}
          disabled={!@host}
        />
        <details class="mt-3" open={!@host}>
          <summary class="cursor-pointer font-bold">Options</summary>
          <div class="mt-2"><.options_form rules={@rules} disabled={!@host} /></div>
        </details>
      </section>
      <p :if={is_nil(@seat)} class="rounded-md bg-iron-dark px-2 py-1" data-role="spectator">
        All seats are taken. You are watching.
      </p>
      <%!-- Start stays in reach at the bottom while the settings scroll. --%>
      <div
        :if={@seat}
        class="sticky bottom-0 z-10 -mx-4 -mb-6 flex items-center gap-3 border-t-2 border-black/30 bg-wood-dark/95 px-4 pt-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] shadow-[0_-10px_20px_-12px_rgb(0_0_0/0.7)] backdrop-blur-sm sm:-mx-6 sm:-mb-12 sm:rounded-t-xl sm:px-6"
        data-role="start-bar"
      >
        <p class="min-w-0 flex-1 text-sm leading-snug text-parchment-dim" data-role="setup-summary">
          {setup_summary(@players, @expansion, @alchemists, @rules)}
        </p>
        <.button
          :if={starter?(@seat, @creator)}
          phx-click="begin"
          variant={:primary}
          class="min-h-12 shrink-0 px-6 text-base"
          data-role="start-game"
        >
          Start game
        </.button>
        <p
          :if={!starter?(@seat, @creator)}
          class="shrink-0 text-sm font-semibold"
          data-role="waiting-for-host"
        >
          Waiting for {name(@names, @creator)} to start the game.
        </p>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} full style={seat_style(@colours)}>
      <%!-- Your seat colour runs along the top edge, over both columns on large screens. --%>
      <div class={[
        "lg:grid lg:h-dvh lg:grid-cols-[minmax(0,1fr)_22rem]",
        @seat && @players > 1 && ["lg:border-t-4", seat_border(@seat)]
      ]}>
        <div
          class={[
            "grid h-dvh grid-rows-[auto_auto_auto_minmax(0,1fr)_auto] overflow-hidden lg:h-full lg:px-4",
            @seat && @players > 1 && ["border-t-4 lg:border-t-0", seat_border(@seat)]
          ]}
          data-role={@seat && "my-seat"}
        >
          <header class="flex min-w-0 items-center gap-2 px-3 pt-[max(0.25rem,env(safe-area-inset-top))]">
            <%!-- Phones need the room for "You are": the menu has the lobby link. --%>
            <h1 class="sr-only font-hand text-2xl leading-none font-bold sm:not-sr-only">
              <.link navigate={~p"/"}>Quacks</.link>
              <span class="font-mono text-xs font-normal text-parchment-dim">
                {@id}
              </span>
            </h1>
            <p
              :if={@seat && @players > 1}
              class="flex min-w-0 flex-col items-start gap-0.5"
              data-role="you-are"
            >
              <span class="pl-1 text-[10px] leading-none font-bold tracking-wide text-parchment-dim uppercase">
                You
              </span>
              <span
                class={[
                  "max-w-full truncate rounded-full bg-parchment px-2 py-0.5 text-xs font-semibold text-ink ring-2 sm:text-sm",
                  seat_ring(@seat)
                ]}
                title={name(@names, @seat)}
              >
                {name(@names, @seat)}
              </span>
            </p>
            <div class="ml-auto shrink-0"><.round_phase game={@game} seat={@seat || 0} /></div>
            <button
              type="button"
              popovertarget="sheet-books"
              aria-label="Ingredient books"
              class="-mx-1 inline-flex size-11 shrink-0 items-center justify-center"
              data-role="open-books"
            >
              <.icon name="hero-book-open" class="size-6" />
            </button>
            <button
              :if={results?(@game)}
              type="button"
              phx-click={JS.dispatch("quacks:modal", to: "#round-results")}
              aria-label="Round results"
              class="-mx-1 inline-flex size-11 shrink-0 items-center justify-center"
              data-role="open-results"
            >
              <.icon name="hero-trophy" class="size-6" />
            </button>
            <button
              type="button"
              popovertarget="sheet-menu"
              aria-label="Menu"
              class="-mr-2 inline-flex size-11 shrink-0 items-center justify-center"
            >
              <.icon name="hero-bars-3" class="size-6" />
            </button>
          </header>

          <div class="space-y-1 px-2">
            <.status :if={@seat} game={@game} seat={@seat} />
            <nav
              :if={@players > 1}
              class="grid grid-cols-[repeat(auto-fit,minmax(5.5rem,1fr))] gap-1 sm:grid-cols-[repeat(auto-fit,minmax(9rem,1fr))]"
              aria-label="Players"
              data-role="players-row"
            >
              <.player_chip
                :for={seat <- @game.seats}
                game={@game}
                seat={seat}
                name={name(@names, seat)}
                you={seat == @seat}
                bot={Map.has_key?(@bots, seat)}
              />
            </nav>
          </div>

          <div class="space-y-1 px-2 pt-1 text-sm">
            <p :if={is_nil(@seat)} class="rounded-md bg-iron-dark px-2 py-1" data-role="spectator">
              All seats are taken. You are watching.
            </p>
            <p
              :if={stir?(@game)}
              class="rounded-md bg-gold px-2 py-0.5 font-bold text-ink"
              data-role="stir"
            >
              Stir! Everyone draws together.
            </p>
            <p
              :if={text = @players > 1 and not Game.over?(@game) and turn_text(@game, @seat, @names)}
              class="px-1 font-semibold"
              data-role="turn"
            >
              {text}
            </p>
          </div>

          <div class="flex min-h-0 flex-col p-2">
            <.flask_strip
              :if={@me && @me.patient}
              game={@game}
              seat={@seat}
              beat={replay_marks(@game, @seat)[:essence]}
            />
            <%!-- The pot is the largest square that fits (see `.pot-box` in app.css);
                 its controls sit in the square's corners: witches top left, the card
                 top right, the flask (inside the SVG) bottom left, the bag bottom right. --%>
            <div class="pot-box flex min-h-0 flex-1 items-start justify-center lg:items-center">
              <div class="pot-square pot-hearth relative" data-role="pot-area">
                <.pot
                  game={@game}
                  seat={@seat || 0}
                  class="block size-full"
                  rings={rings(@game)}
                  flask={@me && if(@me.flask, do: :full, else: :empty)}
                  flask_click={if :use_flask in @actions, do: encode(:use_flask)}
                  beats={replay_marks(@game, @seat)}
                />
                <%!-- Small enough for the free corner outside the round rim. --%>
                <.sheet_button
                  :if={@game.witches}
                  for="sheet-witches"
                  class="absolute top-0 left-0 flex-col gap-0! rounded-2xl px-1.5! py-1 text-[10px] leading-tight lg:hidden"
                  data-role="witches-button"
                >
                  <span class="flex -space-x-1.5">
                    <.piece_icon name={:penny} class="size-4 text-penny-silver" />
                    <.piece_icon name={:penny} class="size-4 text-penny-copper" />
                    <.piece_icon name={:penny} class="size-4 text-penny-gold" />
                  </span>
                  Witches
                </.sheet_button>
                <.fortune_tile
                  :if={@game.fortune_card}
                  id={@game.fortune_card}
                  class="absolute top-0 right-0"
                />
                <.bag_button :if={@me} count={length(@me.bag)} class="absolute right-0 bottom-0" />
              </div>
            </div>
            <.test_tubes
              :if={@game.rules.pot_side == :back}
              tube={@game.players[@seat || 0].tube}
              class="mx-auto block h-auto w-full max-w-sm shrink-0 pt-1"
            />
            <div
              :if={(@me && @me.aside != []) || @game.players[@seat || 0].bowl != []}
              class="flex items-start gap-2 pt-1"
            >
              <.aside :if={@me && @me.aside != []} chips={@me.aside} />
              <div :if={@game.players[@seat || 0].bowl != []} class="ml-auto max-w-[60%]">
                <.bowl chips={@game.players[@seat || 0].bowl} />
              </div>
            </div>
          </div>

          <footer class="space-y-2 px-2 pt-1 pb-[max(0.5rem,env(safe-area-inset-bottom))]">
            <section
              :if={extra_actions(@actions) != []}
              class="flex flex-wrap gap-2 *:min-h-11 *:flex-1 *:touch-manipulation"
              aria-label="More actions"
            >
              <.button
                :for={action <- extra_actions(@actions)}
                phx-click="action"
                phx-value-action={encode(action)}
              >
                {action_label(action, @game, @me)}
              </.button>
            </section>
            <.button
              :if={@decision}
              variant={:primary}
              class="min-h-12 w-full text-base"
              phx-click={JS.dispatch("quacks:modal", to: decision_dialog(@decision, @game))}
            >
              {case @decision do
                :shop -> "Open the shop"
                :rubies -> "Spend rubies"
                decision -> "Choose: #{phase_name(decision)}"
              end}
            </.button>
            <.button
              :if={Game.over?(@game)}
              variant={:primary}
              class="min-h-12 w-full text-base"
              phx-click={JS.dispatch("quacks:modal", to: "#game-over")}
            >
              Show the result
            </.button>
            <%!-- Phones: the flask glows, and this line says why (large screens: its title). --%>
            <p
              :if={:use_flask in @actions}
              class="flex items-center gap-1.5 px-1 text-sm font-semibold text-parchment lg:hidden"
              data-role="flask-hint"
            >
              <.icon name="hero-arrow-uturn-left" class="size-4 shrink-0 text-gold" />
              Tap the flask to put the white chip back in the bag.
            </p>
            <p
              :if={left = @me && ear_worm_left(@me)}
              class="rounded-md bg-gold px-2 py-1 text-sm font-bold text-ink"
              data-role="ear-worm"
            >
              Ear worm: draw {left} more, no explosion
            </p>
            <section
              :if={places(@actions) != [] or forgets(@actions) != []}
              class="flex min-h-11 items-center gap-2"
              aria-label="Patient actions"
              data-role="patient-actions"
            >
              <div
                :if={places(@actions) != []}
                class="flex min-w-0 flex-1 items-center gap-1.5 overflow-x-auto"
                data-role="display"
              >
                <span class="shrink-0 text-xs leading-tight font-semibold text-parchment-dim">
                  Laid out:<br />tap to place
                </span>
                <button
                  :for={chip <- @me.display}
                  type="button"
                  phx-click="action"
                  phx-value-action={encode({:essence, {:place, chip}})}
                  aria-label={"Place #{chip_name(chip)}"}
                  data-role="display-chip"
                  class="grid size-11 shrink-0 cursor-pointer place-items-center rounded-full transition-transform duration-100 ease-out touch-manipulation active:scale-90"
                >
                  <.chip chip={chip} />
                </button>
              </div>
              <.sheet_button
                :if={forgets(@actions) != []}
                for="sheet-forget"
                class="ml-auto shrink-0"
                data-role="forget-button"
              >
                <.icon name="hero-arrow-uturn-left" class="size-4" /> Forget a chip
              </.sheet_button>
            </section>
            <div
              :if={@seat && @game.phase == :potions}
              class="flex items-center gap-2"
              data-role="fuse-row"
            >
              <.fuse_meter game={@game} seat={@seat} />
              <.next_reward game={@game} seat={@seat} />
            </div>
            <%!-- Two fixed slots: Stop (Resume while stopped) left, Draw right.
                 Never moved while the game runs, only disabled; gone at game over
                 and while everyone shops (the shop has its own buttons). --%>
            <section
              :if={@seat && not Game.over?(@game) && not results?(@game)}
              class="grid grid-cols-2 gap-2 *:min-h-12 *:touch-manipulation"
              aria-label="Actions"
              data-role="action-bar"
            >
              <.button
                phx-click="action"
                phx-value-action={encode(@stop_slot)}
                disabled={@stop_slot not in @actions}
                data-slot="stop"
              >
                {if @stop_slot == :resume, do: "Resume", else: "Stop"}
              </.button>
              <.button
                phx-click="action"
                phx-value-action={encode(:draw)}
                disabled={:draw not in @actions}
                variant={:primary}
                data-slot="draw"
              >
                Draw a chip
              </.button>
            </section>
          </footer>
        </div>

        <aside
          class="contents lg:flex lg:h-full lg:flex-col lg:gap-3 lg:overflow-y-auto lg:py-3 lg:pr-3"
          data-role="side-column"
        >
          <.sheet :if={@game.witches} id="sheet-witches" label="Herb witches" inline_lg>
            <section class="space-y-2" aria-label="Herb witches">
              <.witch_card
                :for={{colour, id} <- witches(@game)}
                id={id}
                spent={@me != nil and not @me.pennies[colour]}
              >
                <div :if={@seat} class="flex flex-wrap gap-2 *:min-h-11">
                  <.button
                    :for={action <- calls(@all_actions, colour)}
                    phx-click="action"
                    phx-value-action={encode(action)}
                    variant={:secondary}
                  >
                    {call_text(action)}
                  </.button>
                </div>
              </.witch_card>
            </section>
          </.sheet>
          <.sheet id="sheet-log" label="Log" inline_lg>
            <.action_log log={@game.log} names={if @players > 1, do: @names} />
          </.sheet>
        </aside>
      </div>

      <.sheet :if={@me && @me.patient} id="sheet-patient" label="Patient">
        <.patient_card id={@me.patient} reached={if @me.essence > 0, do: @me.essence} />
        <p class="mt-2 text-sm font-semibold" data-role="patient-essence">
          Essence: {@me.essence}
        </p>
      </.sheet>
      <.sheet :if={forgets(@actions) != []} id="sheet-forget" label="Forgetfulness">
        <h2 class="font-hand text-2xl font-bold">Forgetfulness</h2>
        <p class="text-sm text-ink-soft">
          Tap a chip in your pot to return it to the bag. It costs as much essence as its value. You have {@me.essence}.
        </p>
        <ul class="mt-3 flex flex-wrap gap-2" data-role="forget-chips">
          <li :for={{:essence, {:forget, chip}} = action <- forgets(@actions)}>
            <button
              type="button"
              phx-click="action"
              phx-value-action={encode(action)}
              popovertarget="sheet-forget"
              popovertargetaction="hide"
              data-role="forget-chip"
              class="flex min-h-11 cursor-pointer items-center gap-1.5 rounded-full bg-parchment-light py-1 pr-3 pl-1 text-sm font-semibold shadow-sm ring-1 ring-ink/25 transition-[scale] duration-150 ease-out touch-manipulation active:scale-[0.96]"
            >
              <.chip chip={chip} /> Return (−{elem(chip, 1)})
            </button>
          </li>
        </ul>
      </.sheet>
      <.sheet :if={@me} id="sheet-bag" label="Bag">
        <.bag bag={@me.bag} />
      </.sheet>
      <.sheet :if={@game.fortune_card} id="sheet-fortune" label="Fortune teller card">
        <.fortune_card id={@game.fortune_card} />
      </.sheet>
      <.sheet
        :for={seat <- @game.seats}
        :if={@players > 1}
        id={"sheet-player-#{seat}"}
        label={name(@names, seat)}
      >
        <.player_card game={@game} seat={seat} name={name(@names, seat)} you={seat == @seat} />
      </.sheet>

      <.sheet id="sheet-menu" label="Menu">
        <div class="space-y-3 text-sm">
          <h2 class="text-lg font-bold">Game {@id}</h2>
          <label :if={@seat && @players > 1} class="block space-y-1">
            <span class="flex items-center gap-1.5 font-semibold">
              <.seat_dot seat={@seat} /> Your name
            </span>
            <input
              type="text"
              value={name(@names, @seat)}
              phx-blur="rename"
              maxlength="20"
              aria-label="Your name"
              class="w-full rounded-md border border-ink-soft bg-parchment-light px-2 py-2 text-base text-ink"
            />
          </label>
          <div class="flex flex-wrap gap-2 *:min-h-11">
            <.sheet_button for="sheet-log" variant={:secondary} class="lg:hidden">Log</.sheet_button>
            <.copy_link :if={@players > 1} url={url(~p"/g/#{@id}")} copied={@copied} />
            <.button
              :if={@seat && @players == 1}
              phx-click="undo"
              disabled={@game.log == []}
              variant={:secondary}
            >
              Undo
            </.button>
            <.button :if={@seat && @players == 1} phx-click="new_game" variant={:secondary}>
              New game
            </.button>
            <.button navigate={~p"/"} variant={:secondary}>Lobby</.button>
            <.sheet_button for="sheet-books" variant={:secondary}>Books</.sheet_button>
          </div>
          <p>
            Seed
            <.link navigate={~p"/?seed=#{seed_param(@seed)}"} class="underline">{seed_param(@seed)}</.link>
          </p>
          <p :if={MapSet.size(@game.expansions) > 0} class="text-xs" data-role="expansions">
            Expansions: {Enum.map_join(
              Enum.filter([:herb_witches, :alchemists], &Game.expansion?(@game, &1)),
              " · ",
              &expansion_name/1
            )}
          </p>
          <.books sets={@game.sets} />
          <.house_rules rules={@game.rules} />
        </div>
      </.sheet>

      <.sheet id="sheet-books" label="Ingredient books">
        <h2 class="mb-2 text-lg font-bold">Ingredient books</h2>
        <div class="grid gap-2.5 sm:grid-cols-2" data-role="books-in-play">
          <.book_tile
            :for={{colour, set} <- Books.in_play(@game.expansion, @game.sets)}
            colour={colour}
            set={set}
            players={@players}
          />
        </div>
      </.sheet>

      <%!-- "Round N" between rounds: its id names the round, so it enters the page
           (and plays, app.css `.round-title`) once per round. A tap skips it. --%>
      <div
        :if={not Game.over?(@game)}
        id={"round-title-#{@game.round}"}
        class="round-title"
        phx-click={JS.hide()}
        data-role="round-title"
        aria-hidden="true"
      >
        <div class="round-title-card paper">
          <span class="text-xs font-bold tracking-[0.2em] text-ink-soft uppercase">Round</span>
          <span class="font-hand text-6xl leading-none font-bold tabular-nums">{@game.round}</span>
          <span class="text-xs font-semibold text-ink-soft">of 9</span>
        </div>
      </div>

      <%!-- The shop waits for the round results (they hand over on close). The
           fortune choice lives in the card's dialog. --%>
      <.dialog_sheet
        :if={@decision && @decision != :fortune_choice}
        id={"decision-#{@decision}"}
        label={phase_name(@decision)}
        auto_open={
          not (after_results?(@decision) and results?(@game) and not seen?(@seen, :results, @game))
        }
        focus_self={not primary_on_open?(@decision, @all_actions)}
      >
        <.shop
          :if={shop_step?(@decision)}
          game={@game}
          seat={@seat}
          selected={@selected}
          step={@decision}
        />
        <.patient_picks :if={@decision == :patient_choice} picks={patient_actions(@all_actions)} />
        <.essence_choice
          :if={@decision == :essence_choice}
          patient={@me.patient}
          reach={elem(@me.essence_pending, 1)}
          pick={@essence_pick}
          parts={essence_parts(@game.log, @seat)}
          take={encode({:essence, {:space, @essence_pick}})}
        />
        <div
          :if={not shop_step?(@decision) and @decision not in [:patient_choice, :essence_choice]}
          class="space-y-3"
        >
          <div class="flex items-center gap-1">
            <h2 class="text-xl font-bold">{phase_name(@decision)}</h2>
            <.offer_books
              id="offer-books"
              game={@game}
              offer={[@me.pending, @me.witch_offer, @all_actions]}
            />
          </div>
          <div :if={@decision == :droplet_choice} class="space-y-2" data-role="droplet-choice">
            <p class="text-sm">
              Move your pot droplet or your test-tube droplet.
              <span :if={@me.droplet_moves > 1} class="font-semibold">
                {@me.droplet_moves} moves to place.
              </span>
            </p>
            <.test_tubes tube={@me.tube} />
          </div>
          <p
            :if={hint = bonus_hint(@me.essence_pending)}
            class="text-sm font-semibold"
            data-role="essence-bonus"
          >
            {hint}
          </p>
          <.blue_offer
            :if={@decision == :essence_offer}
            title={offer_hint(@me.essence_pending)}
            hint={"Your essence: #{@me.essence}"}
            label="Patient offer"
            accent="border-gold"
          >
            <.chip :if={chip = offer_chip(@me.essence_pending)} chip={chip} data-role="offer-chip" />
          </.blue_offer>
          <.blue_offer :if={@decision == :blue_choice}>
            <.chip_picks actions={@all_actions} pool={@me.pending} game={@game} me={@me} />
          </.blue_offer>
          <.blue_offer
            :if={@decision == :witch_offer}
            title="The silver witch drew:"
            hint="Tap them one by one, in any order, or return the rest."
            label="Silver witch offer"
            accent="border-penny-silver"
          >
            <.chip_picks actions={@all_actions} pool={@me.witch_offer} game={@game} me={@me} />
          </.blue_offer>
          <.witch_card :for={id <- witches_acting(@game, @all_actions)} id={id} />
          <.blue_offer
            :if={@decision == :red_choice}
            title="Toadstool chips beside the pot:"
            hint="Tap a chip to place it after your last chip, or keep it for later, or return it to the bag."
            label="Toadstool choice"
            accent="border-ruby"
          >
            <.chip_picks actions={@all_actions} pool={@me.pending} game={@game} me={@me} />
          </.blue_offer>
          <.chip_picks
            :if={@decision not in [:blue_choice, :witch_offer, :red_choice]}
            actions={@all_actions}
            game={@game}
            me={@me}
          />
          <section
            class={[
              "gap-2 *:min-h-11",
              if(@decision == :explosion_choice, do: "grid grid-cols-2", else: "flex flex-col")
            ]}
            aria-label="Actions"
            data-role="decision-actions"
          >
            <.button
              :for={action <- dialog_buttons(@all_actions, @decision)}
              phx-click="action"
              phx-value-action={encode(action)}
              variant={choice_variant(dialog_buttons(@all_actions, @decision))}
              autofocus={choice_variant(dialog_buttons(@all_actions, @decision)) == :primary}
              class={choice_class(action)}
            >
              {action_label(action, @game, @me)}
            </.button>
          </section>
        </div>
      </.dialog_sheet>

      <.dialog_sheet
        :if={results?(@game)}
        id="round-results"
        label="Round results"
        auto_open={not seen?(@seen, :results, @game)}
        class={seen?(@seen, :results, @game) && "replay-done"}
        then_open={if after_results?(@decision), do: "decision-#{@decision}"}
        on_close={
          JS.add_class("replay-done")
          |> JS.push("seen", value: %{kind: "results", round: @game.round})
        }
      >
        <.round_results game={@game} names={if @players > 1, do: @names} me={@seat || 0} />
        <form
          method="dialog"
          class="sticky -bottom-4 -mx-4 mt-3 flex bg-parchment px-4 pt-2 pb-4 *:min-h-11 *:flex-1"
        >
          <.button variant={:primary} data-role="results-ok" autofocus>
            {if @decision == :shop, do: "To the shop", else: "OK"}
          </.button>
        </form>
      </.dialog_sheet>

      <.dialog_sheet :if={Game.over?(@game)} id="game-over" label="Game over">
        <.game_over game={@game} names={@names} players={@players} bots={@bots} seat={@seat} />
      </.dialog_sheet>

      <%!-- The new card of the round, on top of everything. Its id names the round,
           so it enters the page (and opens itself) once per round. When the card
           asks this seat a choice, the choice is here too (one dialog, not two);
           a choice sent closes it. --%>
      <.dialog_sheet
        :if={@game.fortune_card && not Game.over?(@game)}
        id={"card-round-#{@game.round}"}
        label="New fortune teller card"
        auto_open={@decision == :fortune_choice or not seen?(@seen, :card, @game)}
        on_close={JS.push("seen", value: %{kind: "card", round: @game.round})}
        focus_self={
          @decision == :fortune_choice and choice_variant(text_actions(@all_actions)) != :primary
        }
      >
        <div class="space-y-3" data-role="card-modal">
          <div class="flex items-center gap-1">
            <h2 class="text-xl font-bold">Round {@game.round}: a new card</h2>
            <.offer_books
              :if={@decision == :fortune_choice}
              id="card-books"
              game={@game}
              offer={[@me.pending, @all_actions]}
            />
          </div>
          <.fortune_card id={@game.fortune_card} choice={@decision == :fortune_choice} flip />
          <%= if @decision == :fortune_choice do %>
            <.fortune_offer :if={@me.pending != []} card={@game.fortune_card}>
              <.chip_picks
                actions={@all_actions}
                pool={@me.pending}
                game={@game}
                me={@me}
                click={card_click(@game)}
              />
            </.fortune_offer>
            <.chip_picks
              :if={@me.pending == []}
              actions={@all_actions}
              game={@game}
              me={@me}
              click={card_click(@game)}
            />
            <section class="flex flex-col gap-2 *:min-h-11" aria-label="Actions">
              <.button
                :for={action <- text_actions(@all_actions)}
                phx-click={card_click(@game)}
                phx-value-action={encode(action)}
                variant={choice_variant(text_actions(@all_actions))}
                autofocus={choice_variant(text_actions(@all_actions)) == :primary}
              >
                {action_label(action, @game, @me)}
              </.button>
            </section>
          <% else %>
            <form method="dialog" class="flex *:min-h-11 *:flex-1">
              <.button variant={:primary} autofocus>OK</.button>
            </form>
          <% end %>
        </div>
      </.dialog_sheet>
    </Layouts.app>
    """
  end

  @colour_names ~w(gold teal violet coral lime rose sky slate)

  # Your seat's colour picker on the configure screen: the 8 palette colours, one tap
  # sets yours; colours other seats have are struck through and cannot be picked.
  # A tap sends the name field first, so a name typed just before is not lost.
  attr :colours, :map, required: true
  attr :seat, :integer, required: true

  defp colour_picker(assigns) do
    assigns =
      assign(assigns,
        mine: assigns.colours[assigns.seat],
        taken: assigns.colours |> Map.delete(assigns.seat) |> Map.values(),
        swatches: Enum.with_index(@colour_names, &{&2, &1})
      )

    ~H"""
    <div
      class="flex w-full gap-1.5 pt-0.5 pb-2"
      role="group"
      aria-label="Your colour"
      data-role="colour-picker"
    >
      <button
        :for={{colour, label} <- @swatches}
        type="button"
        phx-click={
          JS.dispatch("submit", to: "#rename-form") |> JS.push("colour", value: %{colour: colour})
        }
        disabled={colour in @taken}
        aria-label={if colour in @taken, do: "#{label} (taken)", else: label}
        aria-pressed={to_string(colour == @mine)}
        data-colour={colour}
        class={[
          "relative size-8 shrink-0 cursor-pointer overflow-hidden rounded-full shadow-[inset_0_0_0_1px_rgb(0_0_0/0.25)] transition-transform duration-150 ease-out active:scale-90 disabled:cursor-not-allowed disabled:opacity-35 disabled:active:scale-100",
          palette_bg(colour),
          colour == @mine && "ring-2 ring-ink ring-offset-2 ring-offset-parchment-light"
        ]}
      >
        <span
          :if={colour in @taken}
          class="absolute inset-x-0 top-1/2 h-0.5 -translate-y-1/2 -rotate-45 bg-ink"
          aria-hidden="true"
        />
      </button>
    </div>
    """
  end

  @doc """
  A "Copy link" button: it asks the browser to copy `url` (the `quacks:copy`
  listener in app.js) and tells the server, which shows "Copied" for 2 seconds.
  """
  attr :url, :string, required: true
  attr :copied, :boolean, default: false

  def copy_link(assigns) do
    ~H"""
    <.button
      phx-click={JS.dispatch("quacks:copy", detail: %{text: @url}) |> JS.push("copied")}
      variant={:secondary}
      data-role="copy-link"
    >
      <.icon name={if @copied, do: "hero-check", else: "hero-link"} class="size-4" />
      {if @copied, do: "Copied", else: "Copy link"}
    </.button>
    """
  end

  @doc """
  The end of the game. With 2+ players: who won, a podium for the first three
  (places from the VP, so a tie shares a place; the winner wears the laurel) and
  rows for the rest. Solo: the score. Then where each player's VP came from
  (`GameComponents.vp_breakdown/3`), "Play again" (`GameServer.play_again/2`: the
  same table again; focused when the dialog opens) and "Return to lobby".

  The podium rises place by place, the winner last, and a gold shimmer crosses the
  title (app.css `.podium-step`, `.win-shimmer`); reduced motion: fades only.
  """
  attr :game, Game, required: true
  attr :names, :map, required: true
  attr :players, :integer, required: true
  attr :bots, :map, default: %{}
  attr :seat, :integer, default: nil, doc: "this browser's seat, for \"You win!\""

  def game_over(assigns) do
    ranked = placed_ranking(assigns.game)
    winners = for {seat, _vp, 1} <- ranked, do: seat

    assigns =
      assign(assigns,
        ranked: ranked,
        podium: ranked |> Enum.take(3) |> Enum.with_index() |> podium_order(),
        rest: Enum.drop(ranked, 3),
        title: win_title(winners, assigns.seat, assigns.names)
      )

    ~H"""
    <section class="space-y-4 text-center" data-role="game-over">
      <p class="text-xs font-bold tracking-[0.12em] text-ink-soft uppercase">Game over</p>
      <h2
        :if={@players > 1}
        class="win-shimmer -mt-3 flex items-center justify-center gap-2 text-3xl font-bold"
        data-role="winner"
      >
        <.piece_icon name={:vp} class="size-8 shrink-0 text-gold drop-shadow-sm" />{@title}
      </h2>
      <h2
        :if={@players == 1}
        class="win-shimmer -mt-3 flex items-center justify-center gap-2 text-3xl font-bold"
      >
        <.piece_icon name={:vp} class="size-8 shrink-0 text-gold drop-shadow-sm" />
        <span>
          <span class="tabular-nums">{Game.score(@game)[0]}</span> victory points
        </span>
      </h2>
      <ol
        :if={@players > 1}
        class="mx-auto grid max-w-sm grid-cols-3 items-end gap-2 px-1"
        aria-label="Podium"
      >
        <li
          :for={{{seat, vp, place}, beat} <- @podium}
          class={["podium-step flex min-w-0 flex-col items-center", place == 1 && "podium-win"]}
          style={"--beat: #{beat}"}
          data-seat={seat}
          data-place={place}
          data-role="final-score"
        >
          <.piece_icon
            :if={place == 1}
            name={:vp}
            class="podium-crown mb-0.5 size-7 text-gold drop-shadow"
            data-role="crown"
          />
          <span class={[
            "grid size-9 place-items-center rounded-full font-hand text-lg font-bold text-ink ring-2 ring-black/25",
            seat_bg(seat)
          ]}>
            {String.first(name(@names, seat))}
          </span>
          <span class="mt-1 line-clamp-2 w-full text-sm leading-tight font-semibold break-words">
            {name(@names, seat)}
          </span>
          <.bot_badge :if={@bots[seat]} />
          <span class="font-hand text-2xl leading-none font-bold tabular-nums">
            {vp}<span class="sr-only"> victory points</span>
          </span>
          <span
            class={[
              "podium-block mt-1 flex w-full items-start justify-center rounded-t-md pt-1 font-hand text-xl font-bold text-ink/70 shadow-inner",
              seat_bg(seat),
              podium_height(place)
            ]}
            aria-label={"Place #{place}"}
          >
            {place}
          </span>
        </li>
      </ol>
      <ol :if={@rest != []} class="space-y-1">
        <li
          :for={{seat, vp, place} <- @rest}
          class="flex items-center gap-2 rounded-md bg-parchment-deep/60 px-2 py-1 text-left"
          data-seat={seat}
          data-place={place}
          data-role="final-score"
        >
          <span class="w-5 font-hand font-bold">{place}</span>
          <.seat_dot seat={seat} />
          <span class="min-w-0 flex-1 truncate font-semibold">{name(@names, seat)}</span>
          <.bot_badge :if={@bots[seat]} />
          <span class="font-hand text-lg font-bold tabular-nums">{vp} VP</span>
        </li>
      </ol>
      <div class="space-y-1.5 text-left" aria-label="Where the VP came from">
        <div
          :for={{seat, vp, _place} <- @ranked}
          class="rounded-md bg-parchment-deep/50 px-2 py-1.5"
          data-seat={seat}
          data-role="vp-breakdown"
        >
          <p :if={@players > 1} class="flex items-center gap-1.5 text-sm font-semibold">
            <.seat_dot seat={seat} />{name(@names, seat)}
          </p>
          <ul class="mt-0.5 flex flex-wrap gap-1 text-xs">
            <li
              :for={{part, part_vp} <- vp_breakdown(@game.log, seat, vp)}
              class="inline-flex items-center gap-1 rounded-full bg-parchment-light px-2 py-0.5 ring-1 ring-ink/10"
              data-part={part}
              data-role={part == :final && "buying-power"}
              title={vp_part_hint(part)}
            >
              {vp_part_name(part)}
              <span class="font-bold tabular-nums">{signed(part_vp)}</span>
            </li>
          </ul>
        </div>
      </div>
      <div class="flex gap-2 *:min-h-12 *:flex-1">
        <.button phx-click="lobby" variant={:secondary} data-role="return-to-lobby">
          Return to lobby
        </.button>
        <.button phx-click="play_again" variant={:primary} data-role="play-again" autofocus>
          Play again
        </.button>
      </div>
    </section>
    """
  end

  # The ranking as `{seat, vp, place}`, best first; equal VP share a place.
  defp placed_ranking(game) do
    ranked = ranking(game)
    for {seat, vp} <- ranked, do: {seat, vp, 1 + Enum.count(ranked, fn {_, v} -> v > vp end)}
  end

  # The podium left to right: 2nd, 1st, 3rd. Its beat is the order it rises in: last
  # place first, the winner last.
  defp podium_order([first, second, third]),
    do: [{elem(second, 0), 1}, {elem(first, 0), 2}, {elem(third, 0), 0}]

  defp podium_order([first, second]), do: [{elem(second, 0), 0}, {elem(first, 0), 1}]
  defp podium_order(one), do: Enum.map(one, fn {entry, _i} -> {entry, 0} end)

  defp podium_height(1), do: "h-16"
  defp podium_height(2), do: "h-11"
  defp podium_height(_place), do: "h-7"

  defp win_title([seat], seat, _names), do: "You win!"
  defp win_title([seat], _me, names), do: "#{name(names, seat)} wins!"

  defp win_title(seats, me, names) do
    if me in seats,
      do: "You share the win!",
      else: "#{Enum.map_join(seats, " and ", &name(names, &1))} share the win!"
  end

  defp signed(n) when n >= 0, do: "+#{n}"
  defp signed(n), do: "#{n}"

  @doc """
  The shop dialogs: everything this seat may do between brewing and the next round,
  in two steps (`step`).

  `:shop`, while a buy is legal: on top, every chip the player owns (bag, pot and bowl), as counts. Then, while a
  buy is legal, a form of checkboxes, one per kind of chip, in a row per colour
  (see `shop_rows/0`), priced with the game's Ingredient books (`Chips.price/2`).
  The engine decides what may be ticked: a box is disabled when adding its chip
  to the selection is not a legal buy. "Buy selected" sends `{:buy, selected}`.

  The copper witches are here too. "Done" buys nothing (`{:buy, []}`).

  `:rubies`, after the buy (or when there is nothing to buy): the ruby options
  (`{:rubies, _}`), other witch calls, and "Keep rubies" (`:end_round`). Both steps
  are the engine's one `:shop` sub-phase.
  """
  attr :game, Game, required: true
  attr :seat, :integer, default: 0
  attr :selected, :list, required: true, doc: "ticked chips, sorted"
  attr :step, :atom, default: :shop, values: [:shop, :rubies]

  def shop(assigns) do
    sets = assigns.game.sets
    me = assigns.game.players[assigns.seat]
    total = assigns.selected |> Enum.map(&Chips.price(&1, sets)) |> Enum.sum()
    actions = Game.legal_actions(assigns.game, assigns.seat)
    copper = copper_actions(actions, assigns.selected)

    assigns =
      assign(assigns,
        me: me,
        actions: actions,
        buying?: Enum.any?(actions, &match?({:buy, _}, &1)),
        copper: copper,
        others: Enum.reject(actions, &(match?({:buy, _}, &1) or &1 in [:end_round | copper])),
        owned: Player.pot_chips(me) ++ me.bowl ++ me.bag,
        sets: sets,
        rows: shop_rows(assigns.game.expansion, sets),
        total: total,
        remaining: me.coins - total
      )

    assigns = assign(assigns, locked: locked_colours(assigns.game, assigns.rows))

    ~H"""
    <section :if={@step == :shop} class="space-y-2" aria-label="Shop">
      <h2 class="text-xl font-bold">Shop</h2>
      <div class="rounded-md bg-parchment-deep/60 px-2 py-1" data-role="shop-bag">
        <h3 class="text-xs font-semibold text-ink-soft">Your chips: {length(@owned)}</h3>
        <.chip_counts chips={@owned} />
      </div>
      <div :if={@buying?} class="space-y-2">
        <p class="text-sm">Tap up to two chips of different colours.</p>
        <form id="shop" phx-change="select" class="space-y-2">
          <div :for={{row, i} <- Enum.with_index(@rows)} class="space-y-0.5">
            <p class="flex items-baseline gap-1.5 pl-0.5" data-role="shop-row-label">
              <span class="font-hand text-[15px] leading-tight font-bold">
                {Books.get({elem(hd(row), 0), 1}).name}
              </span>
              <span class="text-[11px] text-ink-soft">
                {elem(hd(row), 0)} · book {roman(Chips.set(@game.expansion, @sets, elem(hd(row), 0)))}
              </span>
            </p>
            <ul
              class="grid grid-cols-[1fr_1fr_1fr_auto] gap-1.5"
              data-role="shop-row"
            >
              <li :for={chip <- row}>
                <%!-- A tile, not a checkbox: the box is hidden, the tile shows its state. --%>
                <label class={[
                  "relative flex min-h-12 items-center gap-1.5 rounded-lg bg-parchment-light px-2 text-sm",
                  "ring-1 ring-ink/20 select-none touch-manipulation",
                  "transition-[scale,box-shadow,background-color] duration-150 ease-out",
                  "has-checked:bg-gold/30 has-checked:ring-[3px] has-checked:ring-ink",
                  "has-focus-visible:outline-3 has-focus-visible:outline-droplet",
                  cond do
                    elem(chip, 0) in @locked -> "shop-locked"
                    blocked?(chip, @selected, @actions) -> "opacity-40"
                    true -> "cursor-pointer active:scale-[0.96]"
                  end
                ]}>
                  <input
                    type="checkbox"
                    name="chips[]"
                    value={encode(chip)}
                    checked={chip in @selected}
                    disabled={blocked?(chip, @selected, @actions)}
                    class="peer sr-only"
                  />
                  <span
                    class="absolute -top-2 -right-2 hidden size-5 items-center justify-center rounded-full bg-ink text-gold shadow peer-checked:flex"
                    data-role="tile-check"
                  >
                    <.icon name="hero-check" class="size-3.5" />
                  </span>
                  <span
                    :if={elem(chip, 0) in @locked}
                    class="absolute -top-1.5 -left-1.5 grid size-5 place-items-center rounded-full bg-iron-dark text-parchment shadow"
                    data-role="tile-lock"
                  >
                    <.icon name="hero-lock-closed-mini" class="size-3" />
                    <span class="sr-only">Not in the shop yet</span>
                  </span>
                  <.chip chip={chip} size={:md} />
                  <span class="sr-only sm:not-sr-only">{chip_name(chip)}</span>
                  <span
                    class="ml-auto inline-flex items-center gap-1 font-semibold tabular-nums text-ink-soft"
                    data-role="price"
                  >
                    {Chips.price(chip, @sets)}<span class="book-coin" /><span class="sr-only">coins</span>
                  </span>
                </label>
              </li>
              <li class="col-start-4">
                <button
                  type="button"
                  popovertarget={"shop-book-#{i}"}
                  class="inline-flex size-11 items-center justify-center text-ink-soft"
                  data-role="book-info"
                >
                  <.icon name="hero-information-circle" class="size-6" />
                  <span class="sr-only">Book</span>
                </button>
              </li>
            </ul>
          </div>
        </form>
        <.sheet
          :for={{row, i} <- Enum.with_index(@rows)}
          id={"shop-book-#{i}"}
          label="Ingredient book"
        >
          <.book_list books={row_books(row, @game)} players={map_size(@game.players)} />
        </.sheet>
      </div>
      <.witch_card :if={@copper != []} id={@game.witches.copper}>
        <div class="flex flex-col gap-2 *:min-h-11">
          <.button
            :for={action <- @copper}
            phx-click="action"
            phx-value-action={encode(action)}
            variant={:secondary}
          >
            {label(action)}
          </.button>
        </div>
      </.witch_card>
      <%!-- The purse and the buttons stay at the bottom of the sheet while it scrolls. --%>
      <div
        class="sticky -bottom-4 z-10 -mx-4 mt-3 flex items-center gap-2 bg-parchment px-4 pt-2 pb-4 shadow-[0_-8px_12px_-10px_rgb(0_0_0/0.35)] *:min-h-12"
        data-role="shop-footer"
      >
        <p
          :if={@buying?}
          class={[
            "flex shrink-0 items-center gap-1 font-hand text-xl leading-none font-bold tabular-nums",
            @remaining < 0 && "text-ruby"
          ]}
          data-role="shop-total"
          aria-label={"#{@me.coins} coins, #{@remaining} left after this buy"}
        >
          <span class="book-coin" />{@me.coins}<span class="text-base text-ink-soft">→</span>{@remaining}
        </p>
        <.button
          phx-click="action"
          phx-value-action={encode({:buy, []})}
          variant={if @buying?, do: :secondary, else: :primary}
          autofocus={!@buying?}
          class={["flex-1", @buying? && "px-3"]}
          data-role="shop-done"
        >
          Done
        </.button>
        <.button
          :if={@buying?}
          phx-click="action"
          phx-value-action={encode({:buy, @selected})}
          variant={:primary}
          class="flex-[2] px-3 whitespace-nowrap"
          disabled={@selected == [] or {:buy, @selected} not in @actions}
          data-role="shop-buy"
        >
          {buy_label(@selected, @total)}
        </.button>
      </div>
    </section>
    <section :if={@step == :rubies} class="space-y-2" aria-label="Spend rubies">
      <h2 class="text-xl font-bold">Spend rubies</h2>
      <div class="space-y-2" data-role="shop-rubies">
        <.witch_card :for={id <- witches_acting(@game, @others)} id={id} />
        <p class="flex items-center gap-1.5 text-sm">
          <.icon name="hero-sparkles" class="size-4 text-ruby" />
          You have {@me.rubies} {if @me.rubies == 1, do: "ruby", else: "rubies"}.
        </p>
        <div class="flex flex-col gap-2 *:min-h-11">
          <.button
            :for={action <- @others}
            phx-click="action"
            phx-value-action={encode(action)}
            variant={:secondary}
          >
            {action_label(action, @game, @me)}
          </.button>
        </div>
      </div>
      <div class="flex *:min-h-12 *:flex-1">
        <.button
          phx-click="action"
          phx-value-action={encode(:end_round)}
          variant={if ruby_options?(@others), do: :ghost, else: :primary}
          autofocus={!ruby_options?(@others)}
          data-role="rubies-done"
        >
          {if ruby_options?(@others), do: "Keep rubies", else: "Done"}
        </.button>
      </div>
    </section>
    """
  end

  # The start bar's line: "3 players · Herb Witches · The Alchemists · test tubes".
  defp setup_summary(players, herb_witches?, alchemists?, rules) do
    [
      if(players == 1, do: "Solo", else: "#{players} players"),
      herb_witches? && "Herb Witches",
      alchemists? && "The Alchemists",
      rules.pot_side == :back && "test tubes"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp buy_label([], _total), do: "Buy"
  defp buy_label(selected, total), do: "Buy #{length(selected)} · #{total} coins"

  # The colours of `rows` the shop does not sell yet this round (yellow before round
  # 2, purple before 3), though the box has them.
  defp locked_colours(game, rows) do
    for [{colour, _} | _] = row <- rows,
        Enum.any?(row, &Game.in_supply?(game, &1)),
        not Enum.any?(row, &Game.available?(game, &1)),
        do: colour
  end

  defp ruby_options?(actions), do: Enum.any?(actions, &match?({:rubies, _}, &1))

  # The copper witch buttons in the shop. C3 (a buy with a free copy) shows only for
  # the chips ticked now.
  defp copper_actions(actions, selected) do
    Enum.filter(actions, fn
      {:witch, :copper, {:buy, chips, _copy}} -> chips == selected
      {:witch, :copper, _} -> true
      {:witch, :copper} -> true
      _ -> false
    end)
  end

  @doc """
  The shop's chips as rows, one per colour (orange, blue, red, yellow, black, green,
  purple, locoweed); together they are `Chips.shop/2` for `expansion` and `sets`.
  The orange 6 and the locoweed row show only when they are in play.
  """
  @spec shop_rows(Chips.expansion(), Chips.sets()) :: [[Chips.chip()]]
  def shop_rows(expansion \\ nil, sets \\ %{}) do
    shop = Chips.shop(expansion, sets)
    for row <- @shop_rows, row = Enum.filter(row, &(&1 in shop)), row != [], do: row
  end

  # The books of the colours in a shop row (one colour per row).
  defp row_books([{colour, _value} | _], game),
    do: [{colour, Chips.set(game.expansion, game.sets, colour)}]

  @doc """
  The chips of a choice as its controls: each chip is a button that sends its
  action. With `pool` (the chips a crow skull, the silver witch, the toadstools or a
  fortune card drew, duplicates included) every pool chip shows, and one without an
  action is dimmed; the toadstool's keep and return are small buttons under the
  chip. Without `pool`, one button per chip action ("any 2-value chip": one chip
  per colour), in the shop's row order, under a title per kind. Actions without a
  chip are not here (`text_actions/1`).
  """
  attr :actions, :list, required: true, doc: "the seat's legal actions"
  attr :pool, :list, default: nil
  attr :game, Game, required: true
  attr :me, Player, required: true
  attr :click, :any, default: "action", doc: "the `phx-click` of each chip"

  def chip_picks(assigns) do
    picks = Enum.filter(assigns.actions, &(pick_chips(&1) != [] and not side_pick?(&1)))

    groups =
      case assigns.pool do
        nil ->
          title = &pick_title(&1, assigns.game.fortune_card)

          for t <- picks |> Enum.map(title) |> Enum.uniq() do
            tiles =
              picks
              |> Enum.filter(&(title.(&1) == t))
              |> Enum.sort_by(&chip_order/1)
              |> Enum.map(&{pick_chips(&1), &1, []})

            {t, tiles}
          end

        pool ->
          [
            {nil,
             for(chip <- pool, do: {[chip], pool_pick(picks, chip), sides(assigns.actions, chip)})}
          ]
      end

    limit = white_limit(assigns.game, assigns.me)

    groups =
      for {title, tiles} <- groups, tiles != [] do
        {title,
         for(
           {chips, action, sides} <- tiles,
           do: {chips, action, sides, action && over_limit(action, assigns.me, limit)}
         )}
      end

    assigns = assign(assigns, groups: groups, limit: limit)

    ~H"""
    <div :for={{title, tiles} <- @groups} class="space-y-1" data-role="chip-picks">
      <p :if={title} class="text-sm font-semibold">{title}</p>
      <ul class="flex flex-wrap items-start gap-2">
        <li :for={{chips, action, sides, over} <- tiles} class="flex flex-col items-center">
          <button
            :if={action}
            type="button"
            phx-click={@click}
            phx-value-action={encode(action)}
            aria-label={pick_label(action_label(action, @game, @me), over, @limit)}
            title={pick_label(action_label(action, @game, @me), over, @limit)}
            data-role="chip-pick"
            data-over={over && to_string(over)}
            class={[
              "inline-flex min-h-11 min-w-11 cursor-pointer items-center justify-center gap-1 rounded-full p-1",
              "bg-parchment-light shadow-sm touch-manipulation select-none",
              "transition-[scale,box-shadow] duration-150 ease-out hover:ring-2 hover:ring-ink/60",
              "active:scale-[0.94] focus-visible:outline-3 focus-visible:outline-droplet",
              if(over == :explodes, do: "ring-2 ring-ruby", else: "ring-1 ring-ink/25")
            ]}
          >
            <%= for {chip, i} <- Enum.with_index(chips) do %>
              <.icon :if={i > 0 and upgrade?(action)} name="hero-arrow-right" class="size-4" />
              <.chip chip={chip} data-role={if @pool, do: "offer-chip"} />
            <% end %>
          </button>
          <span
            :if={!action}
            class="inline-flex size-11 items-center justify-center opacity-40"
            title="Not playable"
          >
            <.chip :for={chip <- chips} chip={chip} data-role="offer-chip" />
          </span>
          <span
            :if={over}
            class={[
              "mt-0.5 rounded-full px-1.5 text-[11px] leading-4 font-bold",
              if(over == :explodes, do: "bg-ruby text-white", else: "bg-gold text-ink")
            ]}
            data-role="explode-warning"
          >
            {if over == :explodes, do: "explodes!", else: "over #{@limit}, safe"}
          </span>
          <span
            :if={(!over and @pool) && sides == [] && pick_verb(action)}
            class="mt-0.5 text-[11px] leading-4 font-semibold text-ink-soft"
            data-role="pick-verb"
          >
            {pick_verb(action)}
          </span>
          <div :if={sides != []} class="flex">
            <button
              :for={side <- sides}
              type="button"
              phx-click={@click}
              phx-value-action={encode(side)}
              aria-label={action_label(side, @game, @me)}
              data-role="chip-side"
              class="min-h-11 px-1.5 text-xs font-semibold text-ink-soft underline underline-offset-2 hover:text-ink"
            >
              {side_text(side)}
            </button>
          </div>
        </li>
      </ul>
    </div>
    """
  end

  # The chips an action shows as its control; [] for an action without a chip.
  defp pick_chips({:place, chip}), do: [chip]
  defp pick_chips({:red, {_kind, chip}}), do: [chip]
  defp pick_chips({:witch, :silver, {:place, chip}}), do: [chip]
  defp pick_chips({:fortune, {kind, chip}}) when kind in [:take, :place, :upgrade], do: [chip]
  defp pick_chips({:chip, {kind, chip}}) when kind in [:gain, :starter, :return], do: [chip]
  defp pick_chips({:chip, {:upgrade, from, to}}), do: [from, to]
  defp pick_chips({:chip, {:buy, chips}}), do: chips
  defp pick_chips({:essence, {kind, chip}}) when kind in [:swap, :buy], do: [chip]
  defp pick_chips(_action), do: []

  # The highest white sum that does not explode, for `me` (the rule, B5, Wing ears…).
  defp white_limit(game, me),
    do: Enum.max([game.rules.explode_above, me.mods.explode_above, Fortune.explode_above(game)])

  # A white chip whose placing takes the pot over the limit: `:explodes`, or `:safe`
  # for Safety Procedure (B7: a placed chip cannot explode the pot).
  defp over_limit(action, me, limit) do
    case place_chip(action) do
      {:white, v} when is_integer(v) ->
        if Player.white_sum(me) + v > limit, do: over_kind(action)

      _ ->
        nil
    end
  end

  defp over_kind({:fortune, {:place, _chip}}), do: :safe
  defp over_kind(_action), do: :explodes

  defp place_chip({:place, chip}), do: chip
  defp place_chip({:fortune, {:place, chip}}), do: chip
  defp place_chip({:witch, :silver, {:place, chip}}), do: chip
  defp place_chip(_action), do: nil

  defp pick_label(label, :explodes, _limit), do: "#{label}: explodes the pot"
  defp pick_label(label, :safe, limit), do: "#{label}: over #{limit}, cannot explode"
  defp pick_label(label, _over, _limit), do: label

  # The word under an offered chip, so a pick says what it does.
  defp pick_verb(action) do
    cond do
      place_chip(action) -> "Place"
      match?({:fortune, {:upgrade, _}}, action) -> "Trade up"
      true -> nil
    end
  end

  # The toadstool's keep and return: small buttons under their chip.
  defp side_pick?({:red, {kind, _chip}}), do: kind in [:keep, :return]
  defp side_pick?(_action), do: false

  defp sides(actions, chip), do: for({:red, {k, ^chip}} = a <- actions, k != :place, do: a)

  defp side_text({:red, {:keep, _chip}}), do: "Keep"
  defp side_text({:red, {:return, _chip}}), do: "Return"

  defp pool_pick(picks, chip), do: Enum.find(picks, &(pick_chips(&1) == [chip]))

  defp upgrade?({:chip, {:upgrade, _from, _to}}), do: true
  defp upgrade?(_action), do: false

  # The buttons of a choice that are not chips ("Return all", "Done", "3 rubies").
  defp text_actions(actions), do: Enum.filter(actions, &(pick_chips(&1) == []))

  # Shop row order (white, which the shop has not, first), then value.
  defp chip_order(action) do
    for {colour, value} <- pick_chips(action),
        do: {Enum.find_index(@book_colours, &(&1 == colour)) || -1, value}
  end

  defp pick_title({:chip, {:gain, _chip}}, _card), do: "Garden spider: take one"

  defp pick_title({:chip, {:starter, _chip}}, _card),
    do: "Garden spider: start the next round with"

  defp pick_title({:chip, {:buy, _chips}}, _card), do: "Ghost's breath: take"
  defp pick_title({:chip, {:upgrade, _from, _to}}, _card), do: "Ghost's breath: swap"
  defp pick_title({:chip, {:return, _chip}}, _card), do: "Locoweed: return one to your bag"
  defp pick_title({:fortune, {:take, _chip}}, :p3), do: "Trade 1 ruby for one"
  defp pick_title({:fortune, {:take, _chip}}, _card), do: "Take one"
  defp pick_title({:essence, {:swap, _chip}}, _card), do: "Swap one"
  defp pick_title({:essence, {:buy, _chip}}, _card), do: "Buy one"
  defp pick_title(_action, _card), do: nil

  # A choice in the card's dialog sends its action and closes the dialog.
  defp card_click(game),
    do: JS.push("action") |> JS.dispatch("quacks:close", to: "#card-round-#{game.round}")

  @doc """
  An ⓘ button for a dialog that offers chips: it opens a sheet with the ingredient
  books of the colours in `offer` (any nesting of lists and tuples, e.g. the
  player's `pending` chips and the legal actions). Renders nothing without a
  coloured chip.
  """
  attr :id, :string, required: true
  attr :game, Game, required: true
  attr :offer, :any, required: true

  def offer_books(assigns) do
    colours = assigns.offer |> chip_colours() |> Enum.uniq()

    assigns =
      assign(assigns,
        books:
          for(
            colour <- @book_colours,
            colour in colours,
            do: {colour, Chips.set(assigns.game.expansion, assigns.game.sets, colour)}
          )
      )

    ~H"""
    <span :if={@books != []} class="contents">
      <button
        type="button"
        popovertarget={@id}
        class="-my-2 inline-flex size-11 shrink-0 items-center justify-center text-ink-soft"
        aria-label="Ingredient books"
        data-role="offer-books"
      >
        <.icon name="hero-information-circle" class="size-6" />
      </button>
      <.sheet id={@id} label="Ingredient books">
        <h2 class="mb-2 text-lg font-bold">Ingredient books</h2>
        <.book_list books={@books} players={map_size(@game.players)} />
      </.sheet>
    </span>
    """
  end

  defp chip_colours({colour, value}) when colour in @book_colours and is_integer(value),
    do: [colour]

  defp chip_colours(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> chip_colours()
  defp chip_colours(list) when is_list(list), do: Enum.flat_map(list, &chip_colours/1)
  defp chip_colours(_term), do: []

  # A ticked chip can always be unticked; an unticked one is blocked unless adding it
  # to the selection is a legal buy.
  defp blocked?(chip, selected, actions),
    do: chip not in selected and {:buy, Enum.sort([chip | selected])} not in actions

  # `@game` is the game and `@me` this browser's player (nil when watching).
  # Every state change empties the shop selection; it only means something in the shop.
  # `@decision` is the phase whose choice this seat must make now (shown in a
  # dialog), or nil. `@actions` are the brewing buttons of the bottom bar.
  # `@stop_slot` is the action of the bar's left slot: `:resume` while this seat is
  # `:stopped`, else `:stop`.
  # `@all_actions` are every legal action of this seat; witch calls show on the witch
  # cards, so the bottom bar leaves them out. The silver witch S2's offer is a
  # decision of its own (`:witch_offer`).
  defp put_game(socket, nil) do
    assign(socket,
      game: nil,
      me: nil,
      selected: [],
      decision: nil,
      all_actions: [],
      actions: [],
      stop_slot: :stop,
      essence_pick: nil
    )
  end

  defp put_game(socket, game) do
    socket = mark_round_change(socket, game)
    seat = socket.assigns.seat
    me = if seat, do: game.players[seat]
    actions = if seat && not Game.over?(game), do: Game.legal_actions(game, seat), else: []
    decision = decision(actions, seat && Game.phase(game, seat), me)

    assign(socket,
      game: game,
      me: me,
      selected: [],
      decision: decision,
      all_actions: actions,
      actions: if(decision, do: [], else: Enum.reject(actions, &witch?/1)),
      stop_slot:
        if(me != nil and me.phase == :stopped and not stir?(game), do: :resume, else: :stop),
      essence_pick: essence_pick(me, socket.assigns[:essence_pick])
    )
  end

  # The patch that moves on to a new round runs as a view transition (app.js,
  # `quacks:vt`; app.css moves only the round counter). The event goes out before
  # the patch.
  defp mark_round_change(%{assigns: %{game: %Game{round: old}}} = socket, %Game{round: new})
       when new > old,
       do: push_event(socket, "quacks:vt", %{}, dispatch: :before)

  defp mark_round_change(socket, _game), do: socket

  # The stepper keeps its space while the essence choice is open; it starts at the reach.
  defp essence_pick(%{essence_pending: {:space, reach}}, pick) when pick in 0..reach//1,
    do: pick

  defp essence_pick(%{essence_pending: {:space, reach}}, _pick), do: reach
  defp essence_pick(_me, _pick), do: nil

  # The dialog that holds this seat's decision (the fortune choice is in the card's).
  defp decision_dialog(:fortune_choice, game), do: "#card-round-#{game.round}"
  defp decision_dialog(decision, _game), do: "#decision-#{decision}"

  # This seat closed the card (`:card`) or the round results (`:results`) of this round.
  defp seen?(seen, kind, game), do: seen[kind] == game.round

  # The round results show from the shop until the round ends (round 9 has no shop).
  defp results?(game), do: game.phase == :shopping

  # While the round results show: what lights up on the pot on which replay beat
  # (the same beats as the dialog's lines, so both play in step).
  defp replay_marks(game, seat) do
    if results?(game), do: game |> Replay.beats(seat || 0) |> Replay.highlights(), else: %{}
  end

  # A buy that leaves "Done" as the only legal move (no rubies to spend, no witch to
  # call) ends the shop at once, so the player is not asked twice.
  defp finish_shop(game, id, seat, {:buy, _chips}) do
    with [:end_round] <- Game.legal_actions(game, seat),
         {:ok, game} <- GameServer.apply(id, seat, :end_round) do
      game
    else
      _ -> game
    end
  end

  defp finish_shop(game, _id, _seat, _action), do: game

  # The host starts the game (with nobody hosting, any seated player may).
  defp starter?(nil, _creator), do: false
  defp starter?(seat, creator), do: creator in [nil, seat]

  # Only the creator (the host) changes the settings.
  defp host?(seat, creator), do: seat != nil and seat == creator

  # Round 9 with 2+ players: everyone draws together (the engine's "stir").
  defp stir?(game), do: game.phase == :potions and game.round == 9 and length(game.seats) > 1

  # Every seat's scoring space, for the rings on the big pot.
  defp rings(game), do: Map.new(game.seats, &{&1, Game.scoring_index(game, &1)})

  # Bar actions without a fixed slot (Draw, Stop/Resume) or a pot control (the flask),
  # e.g. B3's restart or R6's place.
  # Patient actions have their own rows (Nervousness display, Forgetfulness sheet).
  defp extra_actions(actions),
    do: Enum.reject(actions -- [:draw, :stop, :resume, :use_flask], &match?({:essence, _}, &1))

  defp places(actions), do: for({:essence, {:place, chip}} <- actions, do: chip)
  defp forgets(actions), do: for({:essence, {:forget, _}} = action <- actions, do: action)

  # `[{id, encoded}]` for the patient choice.
  defp patient_actions(actions), do: for({:patient, id} = a <- actions, do: {id, encode(a)})

  # The `{:essence, reach, parts}` log entry of `seat` (newest), for the essence choice.
  defp essence_parts(log, seat) do
    Enum.find_value(log, fn
      {^seat, {:essence, _reach, %{} = parts}} -> parts
      _entry -> nil
    end)
  end

  # The Ear worm line: draws left, no explosion.
  defp ear_worm_left(%{phase: :ear_worm, essence_pending: {:ear_worm, n}}), do: n
  defp ear_worm_left(_me), do: nil

  # What a Chicken eyes or Vampirism bonus asks for.
  defp bonus_hint({:swap, 1, to}),
    do: "Chicken eyes: swap a 1-chip in your pot for a #{to}-chip of the same colour."

  defp bonus_hint({:buy, coins}), do: "Vampirism: buy 1 chip for up to #{coins} coins."
  defp bonus_hint(_pending), do: nil

  # The patient offer waiting now, for its dialog.
  defp offer_hint({:offers, [{:carrot, _} | _]}), do: "Carrot nose: you drew a pumpkin."

  defp offer_hint({:offers, [{kind, _} | _]}) when kind in [:wing, :wing_bowl],
    do: "Wing ears: you drew a white chip."

  defp offer_hint({:offers, [{:hump, chip} | _]}),
    do: "Witch's hump: a chip on a ruby space. Bonus: #{term_text(Alchemists.hump_bonus(chip))}."

  defp offer_hint(_pending), do: nil

  defp offer_chip({:offers, [{_kind, chip} | _]}), do: chip
  defp offer_chip(_pending), do: nil

  defp expansion_name(:herb_witches), do: "The Herb Witches"
  defp expansion_name(:alchemists), do: "The Alchemists"

  defp decision([], _phase, _me), do: nil
  # The shop's two steps: buy while a buy is legal, then rubies.
  # A seat that can buy nothing (it exploded and took the VP, or has too few coins)
  # skips the buy, unless a copper witch can help it there.
  defp decision(actions, :shop, _me),
    do: if(Enum.any?(actions, &shop_action?/1), do: :shop, else: :rubies)

  defp decision(_actions, :potions, %{witch_offer: [_ | _]}), do: :witch_offer
  # Ear worm draws with the bar's Draw button.
  defp decision(_actions, :ear_worm, _me), do: nil
  defp decision(_actions, :potions, _me), do: nil
  defp decision(_actions, :stopped, _me), do: nil
  defp decision(_actions, phase, _me), do: phase

  defp shop_step?(decision), do: decision in [:shop, :rubies]

  # Whether a decision dialog opens with one enabled primary button (it takes the
  # focus); otherwise the dialog itself does. The shop's Buy is disabled until a
  # chip is ticked; ruby options make "Keep rubies" a ghost.
  defp primary_on_open?(:shop, actions), do: not Enum.any?(actions, &match?({:buy, _}, &1))
  defp primary_on_open?(:rubies, actions), do: not ruby_options?(actions)
  defp primary_on_open?(:patient_choice, _actions), do: false
  defp primary_on_open?(:essence_choice, _actions), do: true

  defp primary_on_open?(decision, actions),
    do: choice_variant(dialog_buttons(actions, decision)) == :primary

  # The decisions that wait while the round results show (they open on "OK").
  defp after_results?(decision), do: decision in [:shop, :rubies, :droplet_choice]
  defp shop_action?({:buy, [_ | _]}), do: true
  defp shop_action?({:witch, :copper, _}), do: true
  defp shop_action?(_action), do: false

  # The shop dialog has the buys and copper witches in `shop/1`; the rest are buttons.
  defp dialog_actions(actions, :shop),
    do: Enum.reject(actions, &(match?({:buy, _}, &1) or match?({:witch, :copper, _}, &1)))

  defp dialog_actions(actions, _decision), do: actions

  defp dialog_buttons(actions, decision),
    do: actions |> dialog_actions(decision) |> text_actions()

  # One primary per dialog: a lone action is the way on (gold); a choice between
  # several actions is a set of equal secondary buttons.
  defp choice_variant([_one]), do: :primary
  defp choice_variant(_actions), do: :secondary

  # The explosion's two answers are big cards with their number.
  defp choice_class({:explosion_choice, _}), do: "min-h-16 text-base leading-tight"
  defp choice_class(_action), do: nil

  defp witch?({:witch, _}), do: true
  defp witch?({:witch, _, _}), do: true
  defp witch?(_action), do: false

  # The witches in penny order: silver, copper, gold.
  defp witches(game), do: for(c <- [:silver, :copper, :gold], do: {c, game.witches[c]})

  # The witches that `actions` can call, for the decision dialog.
  defp witches_acting(%{witches: nil}, _actions), do: []

  defp witches_acting(game, actions) do
    for {colour, id} <- witches(game), calls(actions, colour) != [], do: id
  end

  # The calls a witch card offers: the plain call, and S3's two choices. Choices
  # that belong to a dialog (S2's offer, the copper choices in the shop) stay there.
  defp calls(actions, colour) do
    Enum.filter(actions, fn
      {:witch, ^colour} -> true
      {:witch, ^colour, n} -> is_integer(n)
      _ -> false
    end)
  end

  defp call_text({:witch, _colour}), do: "Call"
  defp call_text({:witch, _colour, 1}), do: "Call: the last white back"
  defp call_text({:witch, _colour, n}), do: "Call: the last #{n} whites back"

  # A button label; G4 makes the rubies phase cost 1 ruby. The reverse pot side
  # names the droplet ("pot droplet") and the next glass's bonus.
  defp action_label({:rubies, what}, game, me) when what in [:droplet, :tube, :flask],
    do:
      "Spend #{if me.ruby_price == 1, do: "1 ruby", else: "2 rubies"}: #{ruby_use(what, game, me)}"

  defp action_label({:droplet, :tube}, _game, me), do: "Test tube (#{next_glass(me)})"

  defp action_label({:essence, :hump}, _game, %{essence_pending: {:offers, [{:hump, c} | _]}}),
    do: "Spend 2 essence: #{term_text(Alchemists.hump_bonus(c))}"

  defp action_label({:essence, :pass}, _game, %{phase: :essence_offer}), do: "No"

  # The explosion's two answers, with what the scoring space pays.
  defp action_label({:explosion_choice, :vp}, _game, me),
    do: "Take VP (+#{PotTrack.at(Player.scoring_index(me)).vp})"

  defp action_label({:explosion_choice, :buy}, _game, me),
    do: "Take coins (#{PotTrack.at(Player.scoring_index(me)).coins} to spend)"

  defp action_label(action, game, _me), do: label(action, game.fortune_card)

  defp ruby_use(:droplet, %{rules: %{pot_side: :back}}, _me), do: "pot droplet +1"
  defp ruby_use(:droplet, _game, _me), do: "droplet +1"
  defp ruby_use(:flask, _game, _me), do: "refill flask"

  defp ruby_use(:tube, _game, me), do: "test tube (#{next_glass(me)})"

  defp next_glass(me), do: "bonus: #{tube_bonus(TestTubes.bonus(me.tube + 1))}"

  defp name(names, seat), do: Map.get(names, seat, GameServer.default_name(seat))

  # What happens now, for the line under the players row. A seat that still has to
  # act is told what everyone does (nil once it is brewing); a seat that is finished
  # sees who it waits for.
  defp turn_text(game, seat, names) do
    busy = Enum.filter(game.seats, &busy?(game, game.players[&1]))

    cond do
      seat in busy or busy == [] or seat == nil ->
        everyone_text(game, seat)

      game.phase == :potions and game.players[seat].pending_choice ->
        chose_text(game, seat, busy, names)

      true ->
        waiting_text(busy, names)
    end
  end

  # The brewing hint goes once this seat drew its first chip of the round.
  defp everyone_text(%{phase: :potions} = game, seat) do
    cond do
      stir?(game) -> "Pick Draw or Stop."
      seat && game.players[seat].drawn != [] -> nil
      true -> "Everyone brews at the same time."
    end
  end

  defp everyone_text(%{phase: :shopping}, _seat), do: "Everyone shops at the same time."

  defp everyone_text(%{phase: phase}, _seat),
    do: "Everyone may #{phase_verb(phase)} at the same time."

  defp chose_text(game, seat, busy, names),
    do: "You chose #{game.players[seat].pending_choice}. " <> waiting_text(busy, names)

  defp waiting_text(seats, names) do
    "Waiting for #{length(seats)} #{if length(seats) == 1, do: "player", else: "players"}: " <>
      Enum.map_join(seats, ", ", &name(names, &1)) <> "."
  end

  # A seat that still has to act in this step: brewing (not stopped, done or waiting
  # for the stir), shopping, or answering the concurrent choice of the game phase.
  defp busy?(%{phase: :potions}, player), do: player.phase not in [:stopped, :done, :waiting_stir]
  defp busy?(%{phase: :shopping}, player), do: player.phase != :ready
  defp busy?(%{phase: :patient_choice}, player), do: player.patient == nil

  defp busy?(%{phase: :essence}, player),
    do:
      player.phase in [:essence_choice, :essence_bonus, :ear_worm] or
        player.phase in [:blue_choice, :yellow_choice, :chip_choice]

  defp busy?(%{phase: phase}, player), do: player.phase == phase

  defp phase_verb(:fortune_choice), do: "resolve the fortune teller card"
  defp phase_verb(:chip_choice), do: "choose chip actions"
  defp phase_verb(:witch_choice), do: "decide on the gold witch"
  defp phase_verb(:patient_choice), do: "choose a patient"
  defp phase_verb(:essence), do: "distil their essence"

  # Seats by VP, highest first.
  defp ranking(game), do: game |> Game.score() |> Enum.sort_by(fn {_seat, vp} -> -vp end)

  defp seed_param({a, b, c}), do: "#{a},#{b},#{c}"

  @doc "Turn an action term into a URL-safe string for `phx-value-action`."
  @spec encode(Game.action()) :: String.t()
  def encode(action), do: action |> :erlang.term_to_binary() |> Base.url_encode64(padding: false)

  @doc """
  Reverse of `encode/1`. Uses `Plug.Crypto.non_executable_binary_to_term/2` with `:safe`,
  so a crafted payload can create neither functions nor new atoms.
  """
  @spec decode(String.t()) :: {:ok, term} | {:error, :bad_action}
  def decode(encoded) when is_binary(encoded) do
    with {:ok, binary} <- Base.url_decode64(encoded, padding: false) do
      {:ok, Plug.Crypto.non_executable_binary_to_term(binary, [:safe])}
    end
  rescue
    ArgumentError -> {:error, :bad_action}
  else
    {:ok, term} -> {:ok, term}
    :error -> {:error, :bad_action}
  end
end
