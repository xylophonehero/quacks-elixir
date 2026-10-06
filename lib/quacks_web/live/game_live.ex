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
  runs along the top edge), your status, the players row (one name card per seat,
  solo too; a tap opens that player's sheet), the pot, and the bottom bar with only
  Stop/Resume and Draw. Around the pot: the witches (top left), this round's fortune card (top
  right), the flask (bottom left) and the bag (bottom right). The log, the share
  link and the books are in the menu. A new fortune card shows in a small dialog
  once per round.

  From 64rem the right column is the context space (layouts 1 and 2): the
  decision, only while one waits, as a non-modal panel (`dialog_sheet` with
  `side`), then the witches. The card's dialog does not open there unless it holds
  a choice. From 80rem (desktop) the fortune teller tops that column
  (`fortune_panel/1`, it plays a reveal when a new card comes) and the books in
  play are a column left of the pot (`books_in_play/1`; a book lights up on its
  replay beat). From 64 to 80rem (tablet) the fortune teller sits in full under the
  pot and the right column has two CSS-only tabs, "Decision" and "Books"; a new
  decision checks "Decision". Below 64rem the same dialogs are bottom sheets; a tap on the dimmed
  backdrop or × closes one to look at the pot, and while a decision waits, one
  button ("Back to shop", "Back to choice") takes the place of Stop and Draw and
  opens it again.

  The host's browser remembers the last settings (localStorage, the `ConfigMemory`
  hook in app.js): each change is pushed as `"save_config"`, and a fresh configure
  screen sends them back once as `"load_config"`.

  A new fortune card shows in the reveal overlay (below); when it asks this seat a
  choice, the card and the choice are one dialog instead. The shop has two steps, each its own dialog: first
  your chips, the buy (one row of chip tiles per colour) and "Done"; then "Spend
  rubies" (the ruby options and witch calls) and "Keep rubies".

  The reveal overlay (round 14, `QuacksWeb.Reveal`, `reveal_overlay/1`): the round's
  card at its start, the evaluation when the shop phase begins and the final
  scoring at the end, one slide at a time, per browser (`@reveal`). Next, Skip,
  Enter, Space, Esc; Auto mode advances on a server timer. Under it each name
  card's VP and ruby counters tick on their replay beats. Its end marks the moment
  seen (`GameServer.ack/4`) and opens the waiting shop or decision. A seat that can
  buy nothing (it exploded and took the VP, or has too few coins) skips the buy and
  gets the rubies step; with nothing to spend there either, its round ends by
  itself once the overlay ended (`auto_done/2`). A buy or ruby spend that leaves
  nothing else to do ends the round for this seat at once.

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
  The dialog says the move is free and names where it came from (e.g. the
  Hawkmoth); the rubies step comes after it and after the buy.

  Mandrake: the server answers "put the white chip back?" for a human seat at once
  (`GameServer.keep_white/2`); a bar above the buttons offers "Keep the white chip
  instead" until the next action of any seat. The rat tails of the round show under
  the players row while the round brews.

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
  import QuacksWeb.BugReportComponents
  import QuacksWeb.RevealComponents

  alias Quacks.{Game, GameServer, Player}
  alias Quacks.Game.Fortune
  alias Quacks.Rules.{Alchemists, Books, Chips, PotTrack, TestTubes}
  alias QuacksWeb.{Replay, Reveal}

  # The colours with an ingredient book (white has none), for `offer_books/1`.
  @book_colours Chips.order() -- [:white]

  @doc "Join game `id`: take a free seat, or watch when the game is full."
  @impl true
  def mount(%{"id" => id}, session, socket) do
    case GameServer.get(id) do
      {:ok, table} ->
        if connected?(socket), do: Phoenix.PubSub.subscribe(Quacks.PubSub, GameServer.topic(id))

        seat =
          case GameServer.claim_seat(id, session["player_token"], watch: connected?(socket)) do
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
           open_sheet: nil,
           seen: seen(table, seat),
           reveal: nil,
           reveal_mode: :step,
           reveal_speed: :normal,
           reduced: false
         )
         |> new_report()
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
    case decode(encoded) do
      {:ok, action} ->
        play(socket, seat, action)

      {:error, :bad_action} ->
        {:noreply, put_flash(socket, :error, "That move could not be read.")}
    end
  end

  def handle_event("action", _params, socket),
    do: {:noreply, put_flash(socket, :error, "You are watching this game.")}

  # Keys (`phx-window-keydown` on the grid): d or Space draws, s stops, f uses the
  # flask, b opens or closes the bag, Enter takes the open decision's one primary
  # button. app.js adds to each
  # keydown whether the focus is in a field (`typing`), on a button or link
  # (`control`: Space and Enter already press it) and whether a modal dialog is
  # open (`modal`). A key does something only when its action is legal for this
  # seat now; it goes through `play/3`, the same path as a tap on the button.
  # Esc needs no code: the browser closes the dialog or the books.
  # While the reveal shows, Enter and Space are Next (a focused button presses
  # itself); no other key acts.
  def handle_event("hotkey", %{"key" => key} = params, %{assigns: %{reveal: %{}}} = socket) do
    if key in ["Enter", " "] and params["control"] != true and params["typing"] != true,
      do: {:noreply, next_slide(socket)},
      else: {:noreply, socket}
  end

  def handle_event("hotkey", %{"key" => key} = params, %{assigns: %{seat: seat}} = socket)
      when is_integer(seat) do
    case hotkey_action(key, params, socket.assigns) do
      nil -> {:noreply, socket}
      # The bag sheet is a popover: only the browser can toggle it (app.js).
      :toggle_bag -> {:noreply, push_event(socket, "quacks:toggle", %{id: "sheet-bag"})}
      action -> play(socket, seat, action)
    end
  end

  def handle_event("hotkey", _params, socket), do: {:noreply, socket}

  # Mandrake: the server put the white chip back for us; keep it instead (only right
  # after, see `GameServer.keep_white/2`).
  def handle_event("keep_white", _params, %{assigns: %{seat: seat}} = socket)
      when is_integer(seat) do
    case GameServer.keep_white(socket.assigns.id, seat) do
      {:ok, game} -> {:noreply, put_game(socket, game)}
      {:error, :not_found} -> {:noreply, ended(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Too late to keep the white chip.")}
    end
  end

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

    config =
      %{sets: parse_sets(params, alchemists), witches: parse_witches(form["witches"])}
      |> Map.merge(expansions(form, alchemists))

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
          rules: parse_rules(form.("rules")),
          witches: parse_witches(form.("witches"))
        },
        expansions(%{"expansion" => to_string(saved["expansion"] == true)}, alchemists)
      )

    case GameServer.configure(socket.assigns.id, socket.assigns.token, config) do
      {:ok, table} -> {:noreply, assign_table(socket, table)}
      {:error, :not_found} -> {:noreply, ended(socket)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("load_config", _saved, socket), do: {:noreply, socket}

  # Bots (host only): "Add bot" on an empty seat row puts a named bot there at once;
  # × empties the seat again.
  def handle_event("add_bot", %{"seat" => seat}, socket) do
    case GameServer.add_bot(socket.assigns.id, socket.assigns.token, String.to_integer(seat)) do
      {:ok, _seat} -> {:noreply, socket}
      {:error, :not_found} -> {:noreply, ended(socket)}
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
      {:error, :not_found} -> {:noreply, ended(socket)}
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

  # The debug replay's scrubber (`GameServer.seek/2`, `GameServer.set_frozen/2`).
  def handle_event("seek", %{"to" => to}, %{assigns: %{debug: %{}}} = socket) do
    case GameServer.seek(socket.assigns.id, String.to_integer(to)) do
      {:ok, game} -> {:noreply, socket |> put_game(game) |> refresh_debug()}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("freeze", %{"frozen" => frozen}, %{assigns: %{debug: %{}}} = socket) do
    GameServer.set_frozen(socket.assigns.id, frozen == "true")
    {:noreply, refresh_debug(socket)}
  end

  # "Report a problem" (`Quacks.BugReports`): `browser` is app.js's JSON.
  def handle_event("report", %{"report" => %{"text" => text} = params}, socket) do
    report = %{
      game_id: socket.assigns.id,
      seat: socket.assigns.seat,
      text: text,
      browser: browser_details(params["browser"])
    }

    case Quacks.BugReports.submit(report) do
      {:ok, %{url: url, number: number}} ->
        {:noreply,
         socket
         |> update(:reports, &(&1 + 1))
         |> new_report()
         |> info(reported(url, number), 8000)}

      {:error, :not_found} ->
        {:noreply, ended(socket)}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           report_form: to_form(params, as: :report),
           report_error: report_error(reason)
         )}
    end
  end

  def handle_event("undo", _params, socket) do
    case GameServer.undo(socket.assigns.id) do
      {:ok, game} -> {:noreply, put_game(socket, game)}
      {:error, :not_found} -> {:noreply, ended(socket)}
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
      {:error, :not_found} -> {:noreply, ended(socket)}
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
      when is_integer(seat) and kind in ["card", "results", "final"] and is_integer(round) do
    key = {String.to_existing_atom(kind), round}

    socket =
      case socket.assigns.reveal do
        %{key: ^key} -> close_reveal(socket)
        _other -> socket |> mark_seen(key) |> auto_done()
      end

    {:noreply, socket}
  end

  def handle_event("seen", _params, socket), do: {:noreply, socket}

  # The reveal overlay (`QuacksWeb.Reveal`, round 14): Next (a tap on the slide,
  # Enter, Space) shows the next slide, the last one closes it; Skip jumps to the
  # last slide; Esc or × close it. Closing marks the moment seen and opens what
  # waited for it (the shop, a decision, the game-over sheet).
  def handle_event("reveal_next", _params, %{assigns: %{reveal: %{}}} = socket),
    do: {:noreply, next_slide(socket)}

  def handle_event("reveal_skip", _params, %{assigns: %{reveal: %{} = reveal}} = socket) do
    last = length(reveal.slides) - 1

    if reveal.index >= last,
      do: {:noreply, close_reveal(socket)},
      else: {:noreply, show_slide(socket, last)}
  end

  def handle_event("reveal_close", _params, %{assigns: %{reveal: %{}}} = socket),
    do: {:noreply, close_reveal(socket)}

  def handle_event(event, _params, socket)
      when event in ["reveal_next", "reveal_skip", "reveal_close"],
      do: {:noreply, socket}

  # The menu's reveal settings, from this browser (`RevealSettings` in app.js: on
  # mount with `reduced`, then on every change). Reduced motion: Step only.
  def handle_event("reveal_settings", params, socket) do
    reduced = Map.get(params, "reduced", socket.assigns.reduced) == true
    mode = if params["mode"] == "auto" and not reduced, do: :auto, else: :step
    speed = Enum.find(Reveal.speeds(), :normal, &(Atom.to_string(&1) == params["speed"]))

    socket = assign(socket, reveal_mode: mode, reveal_speed: speed, reduced: reduced)

    case socket.assigns.reveal do
      %{index: index} -> {:noreply, show_slide(socket, index)}
      nil -> {:noreply, socket}
    end
  end

  # A spectator takes back a seat that no page holds ("Rejoin as …"): the seat moves
  # to this browser's token (`GameServer.rejoin/4`) when the typed name matches.
  def handle_event(
        "rejoin",
        %{"rejoin" => %{"seat" => seat, "name" => typed}},
        %{assigns: %{seat: nil}} = socket
      ) do
    %{id: id, token: token} = socket.assigns

    with {seat, ""} <- Integer.parse(to_string(seat)),
         {:ok, seat} <- GameServer.rejoin(id, token, seat, typed),
         {:ok, table} <- GameServer.get(id) do
      {:noreply,
       socket
       |> assign(seat: seat, seen: seen(table, seat))
       |> assign_table(table)
       |> put_game(table.game)
       |> info("Welcome back, #{name(table.names, seat)}.")}
    else
      {:error, :not_found} -> {:noreply, ended(socket)}
      {:error, :name} -> {:noreply, put_flash(socket, :error, "That is not the seat's name.")}
      _error -> {:noreply, put_flash(socket, :error, "That seat is taken.")}
    end
  end

  def handle_event("rejoin", _params, socket), do: {:noreply, socket}

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
    case GameServer.rename(socket.assigns.id, seat, name) do
      :ok -> {:noreply, socket}
      {:error, :not_found} -> {:noreply, ended(socket)}
    end
  end

  def handle_event("rename", _params, socket), do: {:noreply, socket}

  # The colour picker in your seat row. A colour taken in the meantime does nothing:
  # the broadcast re-renders it as taken.
  def handle_event("colour", %{"colour" => colour}, %{assigns: %{seat: seat}} = socket)
      when is_integer(seat) do
    with {colour, ""} <- Integer.parse(to_string(colour)),
         {:error, :not_found} <- GameServer.set_colour(socket.assigns.id, seat, colour) do
      {:noreply, ended(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  # A player detail sheet renders its body only while open: the players row's chip
  # sends "open_player", the sheet's closing (app.js, `data-on-hide`) "close_player"
  # with its seat. A tap on a second chip while a sheet is open closes the first one
  # (the popovers light-dismiss), and that close can arrive after the new open: it
  # only clears the sheet it names.
  def handle_event("open_player", %{"seat" => seat}, socket) when is_integer(seat),
    do: {:noreply, assign(socket, open_sheet: seat)}

  def handle_event("close_player", %{"seat" => seat}, %{assigns: %{open_sheet: seat}} = socket),
    do: {:noreply, assign(socket, open_sheet: nil)}

  def handle_event("close_player", _params, socket), do: {:noreply, socket}

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
    case GameServer.get(id) do
      {:ok, table} ->
        {:noreply,
         assign(socket,
           names: table.names,
           colours: table.colours,
           rejoinable: table.rejoinable
         )}

      {:error, :not_found} ->
        {:noreply, ended(socket)}
    end
  end

  # A spectator took back an away seat: the table hears it (the rejoiner itself
  # already got its welcome).
  def handle_info({:rejoined, _id, seat}, %{assigns: %{seat: seat}} = socket),
    do: {:noreply, socket}

  def handle_info({:rejoined, _id, seat}, socket),
    do: {:noreply, info(socket, "Someone rejoined as #{name(socket.assigns.names, seat)}.")}

  # The host left the waiting table and this seat took over.
  def handle_info({:host, _id, seat}, %{assigns: %{game: nil, seat: seat}} = socket)
      when is_integer(seat),
      do: {:noreply, socket |> reseat() |> info("You are now the host.")}

  def handle_info({:host, _id, _seat}, socket), do: {:noreply, socket}

  # Someone pressed "Play again": everyone follows to the new game.
  def handle_info({:play_again, _id, new_id}, socket),
    do: {:noreply, push_navigate(socket, to: ~p"/g/#{new_id}")}

  def handle_info(:uncopied, socket), do: {:noreply, assign(socket, copied: false)}

  # Auto mode: the slide's time is up (a stale tick, from a slide left before, is
  # ignored).
  def handle_info({:reveal_tick, ref}, %{assigns: %{reveal: %{tick: ref}}} = socket),
    do: {:noreply, next_slide(socket)}

  def handle_info({:reveal_tick, _ref}, socket), do: {:noreply, socket}

  # An info toast closes by itself (`info/3`), unless a newer one took its place.
  def handle_info({:clear_info, msg}, socket) do
    if Phoenix.Flash.get(socket.assigns.flash, :info) == msg,
      do: {:noreply, clear_flash(socket, :info)},
      else: {:noreply, socket}
  end

  # A page closed before the game began gives its seat back.
  @impl true
  def terminate(_reason, %{assigns: %{game: nil, seat: seat}} = socket) when is_integer(seat),
    do: GameServer.leave_seat(socket.assigns.id, socket.assigns.token)

  def terminate(_reason, _socket), do: :ok

  defp refresh_debug(socket) do
    case GameServer.get(socket.assigns.id) do
      {:ok, table} -> assign(socket, debug: table.debug)
      {:error, :not_found} -> ended(socket)
    end
  end

  # A debug replay (`/debug/replay`): step through the bundle's actions; the bots
  # wait until unfrozen.
  attr :debug, :map, required: true

  defp scrubber(assigns) do
    ~H"""
    <section class="space-y-2 rounded-md bg-ink/10 p-2" aria-label="Debug replay" data-role="scrubber">
      <h3 class="font-bold">Debug replay</h3>
      <div class="flex items-center gap-2 *:min-h-11">
        <.button
          phx-click="seek"
          phx-value-to={@debug.at - 1}
          disabled={@debug.at == 0}
          aria-label="One action back"
          variant={:secondary}
          data-role="seek-back"
        >
          <.icon name="hero-chevron-left" class="size-5" />
        </.button>
        <span class="flex-1 text-center tabular-nums" data-role="scrub-position">
          Action {@debug.at} of {@debug.total}
        </span>
        <.button
          phx-click="seek"
          phx-value-to={@debug.at + 1}
          disabled={@debug.at >= @debug.total}
          aria-label="One action forward"
          variant={:secondary}
          data-role="seek-forward"
        >
          <.icon name="hero-chevron-right" class="size-5" />
        </.button>
      </div>
      <.button
        phx-click="freeze"
        phx-value-frozen={to_string(!@debug.frozen)}
        variant={:secondary}
        class="w-full"
        data-role="freeze-bots"
      >
        {if @debug.frozen, do: "Unfreeze bots", else: "Freeze bots"}
      </.button>
    </section>
    """
  end

  defp new_report(socket) do
    assign(socket,
      reports: socket.assigns[:reports] || 0,
      report_form: to_form(%{"text" => ""}, as: :report),
      report_error: nil
    )
  end

  # Only the fields `Quacks.BugReports` knows, from the browser's JSON.
  defp browser_details(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{} = details} ->
        %{
          ua: details["ua"],
          viewport: details["viewport"],
          online: details["online"],
          errors: Enum.filter(List.wrap(details["errors"]), &is_binary/1)
        }

      _bad ->
        %{}
    end
  end

  defp browser_details(_json), do: %{}

  # The toast after a report: a link to the issue; without a GitHub token, the file.
  # An info toast that closes after `ms` (4 s by default).
  defp info(socket, msg, ms \\ 4000) do
    Process.send_after(self(), {:clear_info, msg}, ms)
    put_flash(socket, :info, msg)
  end

  # No GitHub token: the report is a file on the server; its path is not for players.
  defp reported("file://" <> _path, nil), do: "Thanks. Saved locally."

  defp reported(url, number) do
    {:safe, href} = Phoenix.HTML.html_escape(url)

    {:safe,
     [
       "Thanks. ",
       ~s(<a href="),
       href,
       ~s(" target="_blank" rel="noopener" class="font-semibold underline">),
       "Issue ##{number} opened",
       "</a>"
     ]}
  end

  defp report_error(:empty), do: "Please write what went wrong."
  defp report_error(:too_long), do: "Please keep it under 2000 characters."
  defp report_error(:not_seated), do: "Only players at the table can send a report."
  defp report_error(:rate_limited), do: "One report a minute, please. Try again soon."
  defp report_error(_other), do: "The report could not be sent. Please try again."

  defp reseat(socket) do
    %{id: id, token: token} = socket.assigns

    case GameServer.get(id) do
      {:ok, table} ->
        seat =
          case GameServer.claim_seat(id, token) do
            {:ok, seat} -> seat
            {:error, _full} -> nil
          end

        socket |> assign(seat: seat) |> assign_table(table)

      {:error, :not_found} ->
        ended(socket)
    end
  end

  # The game process is gone (it stopped or crashed): back to the lobby.
  defp ended(socket) do
    socket |> put_flash(:error, "This game has ended.") |> push_navigate(to: ~p"/")
  end

  # One move of this seat, from a tap or a key.
  defp play(socket, seat, action) do
    case GameServer.apply(socket.assigns.id, seat, action) do
      {:ok, game} ->
        {:noreply, socket |> put_game(game) |> auto_done(shop_move?(action))}

      {:error, {:illegal_action, action, _phase}} ->
        {:noreply, put_flash(socket, :error, "#{label(action)} is not allowed right now.")}

      {:error, :not_found} ->
        {:noreply, ended(socket)}
    end
  end

  # The action of a key, or nil. Letters and Space are ignored while typing or with a
  # modal dialog open; Space and Enter on a focused control leave it to the browser.
  defp hotkey_action(key, params, assigns) do
    cond do
      params["typing"] == true -> nil
      key in [" ", "Enter"] and params["control"] == true -> nil
      key != "Enter" and params["modal"] == true -> nil
      true -> key |> String.downcase() |> key_action(assigns)
    end
  end

  defp key_action(key, assigns) when key in ["d", " "], do: bar_action(:draw, assigns)
  defp key_action("s", assigns), do: bar_action(assigns.stop_slot, assigns)
  defp key_action("f", assigns), do: bar_action(:use_flask, assigns)
  defp key_action("b", %{me: %Player{}}), do: :toggle_bag
  defp key_action("enter", assigns), do: enter_action(assigns)
  defp key_action(_key, _assigns), do: nil

  # `@actions` is empty while a decision is open, so a key cannot skip a dialog.
  defp bar_action(action, assigns), do: if(action in assigns.actions, do: action)

  # Enter: the one primary button. The empty rubies step's Done; in the shop Buy
  # with chips ticked, else Done; in a decision its only button.
  defp enter_action(%{skip_rubies: true}), do: :end_round

  defp enter_action(%{decision: :shop, selected: selected, all_actions: actions}) do
    buy = {:buy, selected}
    if buy in actions, do: buy
  end

  defp enter_action(%{decision: :rubies, all_actions: actions}),
    do: if(not ruby_options?(actions) and :end_round in actions, do: :end_round)

  defp enter_action(%{decision: decision, all_actions: actions})
       when decision not in [nil, :patient_choice, :essence_choice] do
    case {dialog_buttons(actions, decision), Enum.filter(actions, &(pick_chips(&1) != []))} do
      {[one], []} -> one
      _other -> nil
    end
  end

  defp enter_action(_assigns), do: nil

  # What an exploded seat waits for, under "Your pot exploded" (64rem).
  defp exploded_next(%Player{phase: :explosion_choice}),
    do: "Next: take the VP or buy (the choice above)."

  defp exploded_next(_me), do: "Next: the evaluation, when everyone has stopped."

  # The table's seats and settings. `@players` is the seat count (while waiting: the
  # count the host picked); `@sets`, `@rules` and `@expansion` feed the configure forms.
  defp assign_table(socket, table) do
    assign(socket,
      players: table.players,
      names: table.names,
      colours: table.colours,
      bots: table.bots,
      creator: table.creator,
      rejoinable: table.rejoinable,
      debug: table.debug,
      sets: table.sets || %{},
      rules: Map.merge(Game.default_rules(), table.rules || %{}),
      witches: table.witches,
      expansion: :herb_witches in table.expansions,
      alchemists: :alchemists in table.expansions,
      # Nobody changed the books or options yet (see "load_config"). Only the
      # creator's saved settings may load: a handed-over table keeps its settings.
      fresh:
        is_integer(socket.assigns.seat) and socket.assigns.seat == table.founder and
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

      {:error, :not_found} ->
        ended(socket)

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
      witches: form.(table.witches),
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
      <div class="flex items-center justify-between gap-2">
        <h1 class="font-hand text-2xl font-bold">
          <.link navigate={~p"/"}>Quacks</.link>
          <span class="font-mono text-xs font-normal text-parchment-dim">{@id}</span>
        </h1>
        <.bug_report_button :if={@seat} n={@reports} class="-mr-2" />
      </div>
      <.bug_report_sheet :if={@seat} n={@reports} form={@report_form} error={@report_error} />
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
              class="hit-44 -mr-1 ml-auto min-h-9 cursor-pointer rounded-full px-3 text-sm font-semibold text-ink-soft transition-[color,background-color,transform] duration-150 ease-out hover:bg-ink/10 hover:text-ink active:scale-95"
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
          witches={@witches}
          disabled={!@host}
        />
        <%!-- The browser owns `open`: a patch must not close it while the host steps. --%>
        <details
          id="options-section"
          class="mt-3"
          open={!@host}
          phx-mounted={JS.ignore_attributes("open")}
        >
          <summary class="cursor-pointer font-bold">Options</summary>
          <div class="mt-2"><.options_form rules={@rules} disabled={!@host} /></div>
        </details>
      </section>
      <.spectator_note :if={is_nil(@seat)} rejoinable={@rejoinable} names={@names} />
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
      <.announcer log={@game.log} names={if @players > 1, do: @names} />
      <%!-- One grid for every screen: each block names its area (`data-area`) and
           app.css places the areas per layout (portrait, landscape phone, 64rem,
           80rem). The DOM order is the reading order. The pot's area never depends
           on the other areas' content, so the pot never moves (round 11).
           Your seat colour runs along the top edge. Keys: `hotkey` below. --%>
      <div
        id="game"
        class={["game-grid", @seat && @players > 1 && ["border-t-4", seat_border(@seat)]]}
        data-role={@seat && "my-seat"}
        phx-window-keydown="hotkey"
      >
        <header
          class="flex min-w-0 items-center gap-2 px-3 pt-[max(0.25rem,env(safe-area-inset-top))] lg:px-6"
          data-area="header"
        >
          <%!-- Phones need the room for "You are": the menu has the lobby link. --%>
          <h1 class="sr-only font-hand text-2xl leading-none font-bold sm:not-sr-only phone-landscape:sr-only">
            <.link navigate={~p"/"}>Quacks</.link>
            <span class="font-mono text-xs font-normal text-parchment-dim">
              {@id}
            </span>
          </h1>
          <p
            :if={@seat && @players > 1}
            class="flex max-w-[7rem] shrink-0 flex-col items-start gap-0.5 sm:max-w-[10rem]"
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
          <div class="ml-auto min-w-0"><.round_phase game={@game} seat={@seat || 0} /></div>
          <%!-- Phones: the round's card waits here, not on the pot's rim. --%>
          <.fortune_tile :if={@game.fortune_card} id={@game.fortune_card} compact class="lg:hidden" />
          <%!-- Below 80rem (no books column) the books open in a sheet: a drawer on
               the right from 48rem, so it never covers the pot. --%>
          <button
            type="button"
            popovertarget="sheet-books"
            aria-label={"Ingredient books (#{length(Books.in_play(@game.expansion, @game.sets))})"}
            class="relative -mx-1 inline-flex size-11 shrink-0 items-center justify-center xl:hidden"
            data-role="open-books"
          >
            <.icon name="hero-book-open" class="size-6" />
            <span
              class="absolute top-0.5 right-0 min-w-4 rounded-full bg-parchment px-1 text-[10px] leading-4 font-bold text-ink tabular-nums"
              aria-hidden="true"
              data-role="books-count"
            >
              {length(Books.in_play(@game.expansion, @game.sets))}
            </span>
          </button>
          <.bug_report_button :if={@seat} n={@reports} class="-mx-1" />
          <button
            type="button"
            popovertarget="sheet-menu"
            aria-label="Menu"
            class="-mr-2 inline-flex size-11 shrink-0 items-center justify-center"
          >
            <.icon name="hero-bars-3" class="size-6" />
          </button>
        </header>

        <div class="space-y-1 px-2 lg:px-6" data-area="players">
          <%!-- A new replay clears the `replay-done` that JS added at the end of the
               last one (JS-added classes stick across patches). First in the block:
               as the last child it would add `space-y` margin to the row. --%>
          <i
            :if={replaying?(@game, @seen)}
            id={"replay-start-#{@game.round}"}
            hidden
            phx-mounted={JS.remove_class("replay-done", to: "#players-row")}
          />
          <.status :if={@seat} game={@game} seat={@seat} beats={stat_beats(@game, @seat, @seen)} />
          <%!-- Up to 4 cards share the row; with more it scrolls sideways. After the
               brew each card's counters tick on the replay beats; the card with the
               last beat ends the replay (`replay_end/3`, app.js). On phones the
               counts row has two lines, so the row keeps its height. --%>
          <nav
            id="players-row"
            class={[
              "-mx-2 grid snap-x auto-cols-[minmax(5.5rem,1fr)] grid-flow-col grid-rows-[auto_2.125rem] gap-1 overflow-x-auto px-2 py-0.5 [scrollbar-width:none] sm:auto-cols-[minmax(9rem,1fr)] sm:grid-rows-[auto_auto] phone-landscape:auto-cols-[minmax(5.5rem,1fr)]",
              not replaying?(@game, @seen) && "replay-done"
            ]}
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
              updates={if results?(@game), do: Replay.updates(@game, seat), else: []}
              ticks={replaying?(@game, @seen)}
            />
          </nav>
        </div>

        <%!-- Only a spectator has a notice here; it does not change while watching. --%>
        <div :if={is_nil(@seat)} class="px-2 pt-1 text-sm lg:px-6" data-area="notices">
          <.spectator_note rejoinable={@rejoinable} names={@names} />
        </div>

        <%!-- Desktop (80rem): the books in play, a column left of the pot. --%>
        <.books_in_play
          id="books-column"
          game={@game}
          beats={book_beats(@game, @seat, @seen)}
          class="hidden pt-2 pb-3 pl-4 xl:flex"
          data-area="books"
        />

        <div class="pot-column flex min-h-0 flex-col px-4 py-1 lg:px-6 lg:py-2" data-area="pot">
          <.flask_strip
            :if={@me && @me.patient}
            game={@game}
            seat={@seat}
            beat={replay_marks(@game, @seat)[:essence]}
          />
          <%!-- The pot is the largest square that fits (see `.pot-box` in app.css);
               its controls sit in the square's corners: witches top left, Skip top
               right, the flask (inside the SVG) bottom left, the bag bottom right.
               What comes and goes here is absolute, so the square never changes. --%>
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
                effects={replay_effects(@game, @seat, @seen)}
              />
              <%!-- Small enough for the free corner outside the round rim. --%>
              <.sheet_button
                :if={@game.witches}
                for="sheet-witches"
                class="absolute top-0 left-0 flex-col gap-0! rounded-2xl px-1.5! py-1 text-[10px] leading-tight lg:hidden"
                data-role="witches-button"
              >
                <span class="flex -space-x-1.5">
                  <.piece_icon name={:penny} class="size-4 text-penny-copper" />
                  <.piece_icon name={:penny} class="size-4 text-penny-silver" />
                  <.piece_icon name={:penny} class="size-4 text-penny-gold" />
                </span>
                Witches
              </.sheet_button>
              <p
                :if={stir?(@game)}
                class="absolute top-0 left-1/2 -translate-x-1/2 rounded-full bg-gold px-3 py-0.5 text-sm font-bold whitespace-nowrap text-ink shadow-md"
                data-role="stir"
              >
                Stir! Everyone draws together.
              </p>
              <%!-- Red Set 2 chips and the overflow bowl hang over the pot's lower rim. --%>
              <div
                :if={(@me && @me.aside != []) || @game.players[@seat || 0].bowl != []}
                class="absolute inset-x-12 bottom-0 flex items-end justify-center gap-2"
                data-role="beside-pot"
              >
                <.aside :if={@me && @me.aside != []} chips={@me.aside} />
                <.bowl
                  :if={@game.players[@seat || 0].bowl != []}
                  chips={@game.players[@seat || 0].bowl}
                />
              </div>
              <.bag_button :if={@me} count={length(@me.bag)} class="absolute right-0 bottom-0" />
            </div>
          </div>
          <%!-- A landscape phone moves the tubes to the right column (app.css). --%>
          <div :if={@game.rules.pot_side == :back} class="shrink-0 pt-1" data-area="tubes">
            <.test_tubes
              tube={@game.players[@seat || 0].tube}
              class="mx-auto block h-auto w-full max-w-sm"
            />
          </div>
        </div>

        <%!-- The context area (64rem): what happens now. The fortune teller on top,
             the round's results while they play, the decision while one waits,
             then the witches. Below 64rem it is `display: contents` and holds only
             the sheets. --%>
        <aside class="context-column" data-area="context" data-role="side-column">
          <.fortune_panel
            :if={@game.fortune_card}
            id={"fortune-panel-#{@game.round}"}
            card={@game.fortune_card}
            class="hidden shrink-0 lg:flex"
          />
          <.chance_panel
            :if={@game.fortune_card == :p12 and @game.phase in [:potions, :fortune_choice]}
            id={"chance-#{@game.round}"}
            rolls={chance_rolls(@game, @seat, @names)}
          />
          <.results_panel
            :if={replaying?(@game, @seen)}
            id={"results-#{@game.round}"}
            rows={result_rows(@game, @seat, @names)}
            round={@game.round}
          />
          <%!-- The decision: a panel here from 64rem, a bottom sheet below. The shop
                   waits for the update chips, a decision for a new card (they hand
                   over). The fortune choice lives in the card's dialog. --%>
          <.dialog_sheet
            :if={@decision && @decision != :fortune_choice}
            id={"decision-#{@decision}"}
            label={phase_name(@decision)}
            auto_open={is_nil(@reveal)}
            focus_self={not primary_on_open?(@decision, @all_actions)}
            side={:panel}
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
                <%!-- First what caused the move (a black chip for the hawkmoth). --%>
                <ul
                  :if={(sources = droplet_sources(@game.log, @seat)) != []}
                  class="space-y-1 text-sm text-ink-soft"
                  data-role="droplet-sources"
                >
                  <li :for={{cause, text} <- sources} class="flex items-center gap-2">
                    <.droplet_cause cause={cause} />{text}
                  </li>
                </ul>
                <p class="text-sm">
                  A free move (no rubies): move your pot droplet or your test-tube droplet.
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
                <.chip
                  :if={chip = offer_chip(@me.essence_pending)}
                  chip={chip}
                  data-role="offer-chip"
                />
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
          <%!-- A card that asks this seat a choice: the card and the choice in one
               dialog. It enters the page (and opens itself) when the choice comes, at
               the round's start or later (Safety Procedure waits for every stop); a
               choice sent closes it. A card without a choice shows in the reveal
               overlay (round 14). --%>
          <.dialog_sheet
            :if={@decision == :fortune_choice}
            id={"card-round-#{@game.round}"}
            label="New fortune teller card"
            on_close={JS.push("seen", value: %{kind: "card", round: @game.round})}
            focus_self={choice_variant(text_actions(@all_actions)) != :primary}
            side={:panel}
          >
            <div class="space-y-3" data-role="card-modal">
              <div class="flex items-center gap-1">
                <h2 class="text-xl font-bold">Round {@game.round}: a new card</h2>
                <.offer_books
                  id="card-books"
                  game={@game}
                  offer={[@me.pending, @all_actions]}
                />
              </div>
              <.fortune_card id={@game.fortune_card} choice flip />
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
            </div>
          </.dialog_sheet>
          <.sheet :if={@game.witches} id="sheet-witches" label="Herb witches" inline_lg>
            <%!-- The title row holds the × (it floats right), so it never squeezes the
                 first card (round 14). --%>
            <h2 class="min-h-8 font-hand text-2xl leading-8 font-bold" data-role="witches-title">
              Herb witches
            </h2>
            <section class="clear-both space-y-2 pt-1" aria-label="Herb witches">
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
        </aside>

        <%!-- The bar: Stop and Draw, and what the brew asks for now. Phones and
             tablets: a fixed-height bar under the pot (app.css `.game-bar`), and
             the rare extras (`.game-tray`) float over the pot's lower band. From
             64rem it is the foot of the context column. --%>
        <footer class="game-bar" data-area="bar">
          <div class="game-tray">
            <section
              :if={keep_white?(@game, @seat, @bots)}
              class="paper flex items-center gap-2 rounded-lg px-2 py-1.5 text-sm shadow-lg"
              aria-label="Mandrake"
              data-role="mandrake-undo"
            >
              <span class="min-w-0 flex-1">Mandrake: the white chip went back in your bag.</span>
              <.button
                id="keep-white"
                phx-click="keep_white"
                variant={:secondary}
                class="min-h-11 shrink-0"
              >
                Keep the white chip instead
              </.button>
            </section>
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
            <p
              :if={left = @me && ear_worm_left(@me)}
              class="rounded-md bg-gold px-2 py-1 text-sm font-bold text-ink shadow-lg"
              data-role="ear-worm"
            >
              Ear worm: draw {left} more, no explosion
            </p>
            <section
              :if={places(@actions) != [] or forgets(@actions) != []}
              class="flex min-h-11 items-center gap-2 rounded-lg bg-iron-dark/90 px-2 shadow-lg"
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
            <%!-- Phones: the bonus die (from 64rem it rolls in the results panel). --%>
            <.replay_die
              :if={replaying?(@game, @seen)}
              lines={replay_die_lines(@game, @seat)}
              class="flex shadow-lg lg:hidden"
            />
          </div>
          <%!-- An empty rubies step (nothing to spend, no witch to call) is one tap:
               the update chips stay on the cards until then. --%>
          <.button
            :if={@skip_rubies}
            variant={:primary}
            class="min-h-12 w-full text-base"
            phx-click="action"
            phx-value-action={encode(:end_round)}
            data-role="round-done"
          >
            Done
            <.kbd>Enter</.kbd>
          </.button>
          <%!-- While a decision waits it takes the place of Stop and Draw on phones
               and reopens its sheet (closed to look at the pot). Hidden while a
               sheet is open: it would show above the sheet's edge. From 64rem the
               decision is a panel in the context column, and this shows only when
               that panel was closed. --%>
          <.button
            :if={@decision}
            variant={:primary}
            class="min-h-12 w-full text-base [body:has(dialog[open])_&]:invisible lg:[body:has(dialog[open])_&]:hidden"
            data-role="decision-button"
            phx-click={JS.dispatch("quacks:modal", to: decision_dialog(@decision, @game))}
          >
            {back_label(@decision, @game)}
          </.button>
          <.button
            :if={Game.over?(@game)}
            variant={:primary}
            class="min-h-12 w-full text-base"
            phx-click={JS.dispatch("quacks:modal", to: "#game-over")}
          >
            Show the result
          </.button>
          <div :if={@seat && @game.phase == :potions} class="flex flex-col gap-1" data-role="fuse-row">
            <.reward_line game={@game} seat={@seat} />
            <div class="flex"><.fuse_meter game={@game} seat={@seat} /></div>
          </div>
          <%!-- From 64rem an exploded pot puts its result here, where Stop and Draw
               were, and says what comes next. --%>
          <section
            :if={@me && @me.exploded? && @game.phase == :potions}
            class="hidden rounded-lg bg-ruby/20 px-3 py-2 text-parchment ring-1 ring-ruby-light/50 lg:block"
            aria-label="Exploded"
            data-role="exploded-panel"
          >
            <p class="font-hand text-2xl leading-tight font-bold">Your pot exploded</p>
            <p class="text-sm">{exploded_next(@me)}</p>
          </section>
          <%!-- Two fixed slots: Stop (Resume while stopped) and Draw. Never moved
               while the game runs, only disabled; gone at game over and while
               everyone shops (the shop has its own buttons). From 64rem Draw is the
               large button on top, Stop and the flask under it. --%>
          <section
            :if={@seat && not Game.over?(@game) && not results?(@game)}
            class={[
              "action-bar *:min-h-12 *:touch-manipulation",
              @decision && "max-lg:hidden",
              @me && @me.exploded? && "lg:hidden"
            ]}
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
              <.kbd>s</.kbd>
            </.button>
            <%!-- From 64rem: the flask as a button too (on the pot it is on every screen). --%>
            <.button
              :if={@me}
              phx-click="action"
              phx-value-action={encode(:use_flask)}
              disabled={:use_flask not in @actions}
              class="flex-col gap-0! px-1! max-lg:hidden!"
              aria-label="Use the flask"
              title="Put the white chip back in the bag"
              data-slot="flask"
            >
              <.piece_icon name={:flask} class="size-5" />
              <.kbd>f</.kbd>
            </.button>
            <.button
              phx-click="action"
              phx-value-action={encode(:draw)}
              disabled={:draw not in @actions}
              variant={:primary}
              data-slot="draw"
            >
              Draw a chip
              <.kbd>d</.kbd>
            </.button>
          </section>
        </footer>
      </div>

      <%!-- The log lives behind the menu on every screen (round 10). --%>
      <.sheet id="sheet-log" label="Log">
        <.action_log log={@game.log} names={if @players > 1, do: @names} />
      </.sheet>
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
        <%!-- A wrapper: the sheet flattens a `.paper` child, and the card keeps its edge. --%>
        <div class="pt-8 pb-2"><.fortune_card id={@game.fortune_card} /></div>
      </.sheet>
      <.sheet
        :for={seat <- @game.seats}
        id={"sheet-player-#{seat}"}
        label={name(@names, seat)}
        data-on-hide={JS.push("close_player", value: %{seat: seat})}
      >
        <div :if={@open_sheet == seat} class="space-y-2">
          <.result_lines :if={results?(@game)} game={@game} seat={seat} />
          <.player_card game={@game} seat={seat} name={name(@names, seat)} you={seat == @seat} />
        </div>
      </.sheet>

      <.bug_report_sheet :if={@seat} n={@reports} form={@report_form} error={@report_error} />

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
            <.sheet_button for="sheet-log" variant={:secondary}>Log</.sheet_button>
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
          <.reveal_settings mode={@reveal_mode} speed={@reveal_speed} reduced={@reduced} />
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
          <%!-- Why the browser offers no Install (round 14): app.js fills the line. --%>
          <p
            id="app-status"
            class="font-mono text-xs text-ink-soft"
            phx-hook="AppStatus"
            phx-update="ignore"
            data-role="app-status"
          >
            App: worker: … · display: … · install prompt: …
          </p>
          <.scrubber :if={@debug} debug={@debug} />
        </div>
      </.sheet>

      <%!-- From 48rem a drawer from the right (app.css `.sheet-drawer`): it slides
           over the context column, never over the pot, and stays open when a
           decision comes (app.js waits until it closes). --%>
      <.sheet id="sheet-books" label="Ingredient books" class="sheet-drawer">
        <h2 class="mb-2 text-lg font-bold">Ingredient books</h2>
        <div
          class="grid gap-2.5 sm:grid-cols-2 md:grid-cols-1 phone-landscape:grid-cols-1"
          data-role="books-in-play"
        >
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

      <.dialog_sheet
        :if={Game.over?(@game)}
        id="game-over"
        label="Game over"
        auto_open={is_nil(@reveal)}
      >
        <.game_over game={@game} names={@names} players={@players} bots={@bots} seat={@seat} />
      </.dialog_sheet>

      <%!-- The round's reveals, one slide at a time (round 14). Last in the page, so
           it stays on top when app.js opens the modals again (`remodal`). --%>
      <.reveal_overlay
        :if={@reveal}
        reveal={@reveal}
        names={@names}
        seat={@seat}
        auto_ms={reveal_ms(@reveal, @reveal_mode, @reveal_speed)}
        close_label={close_label(@reveal, @decision, @skip_rubies)}
      />
    </Layouts.app>
    """
  end

  # A browser without a seat watches. A seat that no page has held for 30 s (its
  # player lost the cookie or changed browser) can be taken back: "Rejoin as <name>"
  # opens a small form, and the seat's name must be typed to confirm.
  attr :rejoinable, :list, required: true
  attr :names, :map, required: true

  defp spectator_note(assigns) do
    ~H"""
    <div class="space-y-1.5 rounded-md bg-iron-dark px-2 py-1" data-role="spectator">
      <p>All seats are taken. You are watching.</p>
      <div :if={@rejoinable != []} class="space-y-2" data-role="rejoin">
        <span class="text-sm text-parchment-dim">Is one of these seats yours?</span>
        <div :for={seat <- @rejoinable} class="space-y-1.5">
          <.button
            type="button"
            phx-click={
              JS.toggle(to: "#rejoin-form-#{seat}", display: "flex")
              |> JS.focus(to: "#rejoin-name-#{seat}")
            }
            variant={:secondary}
            class="min-h-11"
            data-role="rejoin-seat"
            data-seat={seat}
          >
            Rejoin as {name(@names, seat)}
          </.button>
          <.form
            for={to_form(%{"seat" => seat, "name" => ""}, as: :rejoin)}
            id={"rejoin-form-#{seat}"}
            class="hidden flex-wrap items-end gap-2"
            phx-submit="rejoin"
            data-role="rejoin-form"
          >
            <input type="hidden" name="rejoin[seat]" value={seat} />
            <label class="min-w-0 flex-1 text-sm">
              Type <b>{name(@names, seat)}</b>
              to confirm
              <input
                id={"rejoin-name-#{seat}"}
                type="text"
                name="rejoin[name]"
                autocomplete="off"
                class="mt-1 block min-h-11 w-full rounded-md bg-parchment px-2 text-ink"
              />
            </label>
            <.button variant={:primary} class="min-h-11">Rejoin</.button>
          </.form>
        </div>
      </div>
    </div>
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
          "hit-44 size-8 shrink-0 cursor-pointer rounded-full shadow-[inset_0_0_0_1px_rgb(0_0_0/0.25)] transition-transform duration-150 ease-out active:scale-90 disabled:cursor-not-allowed disabled:opacity-35 disabled:active:scale-100",
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
      class="hit-44"
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
            <div class="flex items-center gap-1.5 pl-0.5" data-role="shop-row-label">
              <span class="font-hand text-[15px] leading-tight font-bold">
                {Books.get({elem(hd(row), 0), 1}).name}
              </span>
              <span class="text-[11px] text-ink-soft">
                {elem(hd(row), 0)} · book {roman(Chips.set(@game.expansion, @sets, elem(hd(row), 0)))}
              </span>
              <%!-- The book's text opens in place, under the row (not another sheet). --%>
              <button
                type="button"
                class="-my-2 ml-auto inline-flex size-9 shrink-0 cursor-pointer items-center justify-center rounded-full text-ink-soft transition-[color,scale] duration-150 ease-out hit-44 hover:text-ink active:scale-90 aria-expanded:text-ink"
                aria-expanded="false"
                aria-controls={"shop-book-#{i}"}
                phx-click={
                  JS.toggle(
                    to: "#shop-book-#{i}",
                    in:
                      {"transition-[opacity,translate] duration-150 ease-out",
                       "opacity-0 -translate-y-1", "opacity-100 translate-y-0"},
                    out: {"transition-opacity duration-100 ease-out", "opacity-100", "opacity-0"}
                  )
                  |> JS.toggle_attribute({"aria-expanded", "true", "false"})
                }
                data-role="book-info"
              >
                <.icon name="hero-information-circle" class="size-5" />
                <span class="sr-only">Book</span>
              </button>
            </div>
            <ul class="grid grid-cols-3 gap-1.5" data-role="shop-row">
              <li :for={chip <- row} class="min-w-0">
                <%!-- A tile, not a checkbox: the box is hidden, the tile shows its state. --%>
                <label class={[
                  "relative flex min-h-12 min-w-0 items-center gap-1.5 rounded-lg bg-parchment-light px-2 text-sm",
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
                  <%!-- In a side panel (64rem up) the tile is the phone one: chip, value, price. --%>
                  <span
                    class="sr-only sm:not-sr-only lg:sr-only phone-landscape:sr-only"
                    data-role="tile-name"
                  >
                    {chip_name(chip)}
                  </span>
                  <span
                    class="ml-auto inline-flex shrink-0 items-center gap-1 font-semibold tabular-nums text-ink-soft"
                    data-role="price"
                  >
                    {Chips.price(chip, @sets)}<span class="book-coin" /><span class="sr-only">coins</span>
                  </span>
                </label>
              </li>
            </ul>
            <div
              id={"shop-book-#{i}"}
              class="hidden rounded-lg bg-parchment-deep/60 px-2 py-1.5"
              data-role="shop-book"
            >
              <.book_list
                books={row_books(row, @game)}
                players={map_size(@game.players)}
                rules={@game.rules}
              />
            </div>
          </div>
        </form>
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
      <%!-- The purse and the buttons stay at the bottom of the sheet while it scrolls.
           A size container: the Enter hints show only where the bar has the room
           (round 12: at 64rem the sheet is a narrow column and the bar overflowed). --%>
      <div
        class="@container/shop-bar sticky bottom-0 z-10 -mx-4 mt-3 flex min-w-0 items-center gap-2 bg-parchment px-4 pt-2 pb-[max(0.75rem,env(safe-area-inset-bottom))] shadow-[0_-8px_12px_-10px_rgb(0_0_0/0.35)] *:min-h-12"
        data-role="shop-footer"
      >
        <p
          :if={@buying?}
          class={[
            "flex min-w-0 shrink items-center gap-1 font-hand text-xl leading-none font-bold whitespace-nowrap tabular-nums",
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
          class={["min-w-0", if(@buying?, do: "flex-none px-3", else: "flex-1")]}
          data-role="shop-done"
        >
          Done
          <.kbd :if={!@buying?}>Enter</.kbd>
        </.button>
        <.button
          :if={@buying?}
          phx-click="action"
          phx-value-action={encode({:buy, @selected})}
          variant={:primary}
          class="min-w-0 flex-1 px-3 whitespace-nowrap"
          disabled={@selected == [] or {:buy, @selected} not in @actions}
          data-role="shop-buy"
        >
          <span class="truncate">{buy_label(@selected, @total)}</span>
          <.kbd :if={@selected != []} show={shop_kbd()}>Enter</.kbd>
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

  # The Buy button's Enter hint: from 64rem, and only when the shop bar is 24rem
  # wide (Done alone always has the room).
  defp shop_kbd, do: "hidden lg:@min-[24rem]/shop-bar:inline-block"

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
  The shop's chips as rows, one per colour in the board's order (`Chips.order/0`:
  orange, blue, red, yellow, green, black, purple, locoweed), each from the lowest
  value up; together they are `Chips.shop/2` for `expansion` and `sets`.
  The orange 6 and the locoweed row show only when they are in play.
  """
  @spec shop_rows(Chips.expansion(), Chips.sets()) :: [[Chips.chip()]]
  def shop_rows(expansion \\ nil, sets \\ %{}) do
    shop = Chips.shop(expansion, sets)

    for colour <- Chips.order(),
        row = shop |> Enum.filter(&(elem(&1, 0) == colour)) |> Enum.sort(),
        row != [],
        do: row
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
          <%!-- Without a pool (a card's or a chip action's "take one"), the colour
               word under the chip, so a pick does not read as only its value. --%>
          <span
            :if={action && !@pool && !over}
            class="mt-0.5 text-[11px] leading-4 font-semibold text-ink-soft"
            data-role="pick-colour"
          >
            {chips |> List.last() |> elem(0)}
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

  # The board's colour order (`Chips.order/0`, white first), then value.
  defp chip_order(action), do: Enum.map(pick_chips(action), &Chips.sort_key/1)

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
        <.book_list books={@books} players={map_size(@game.players)} rules={@game.rules} />
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
      skip_rubies: false,
      stop_slot: :stop,
      essence_pick: nil,
      reveal: nil
    )
  end

  defp put_game(socket, game) do
    socket = mark_round_change(socket, game)
    seat = socket.assigns.seat
    me = if seat, do: game.players[seat]
    actions = if seat && not Game.over?(game), do: Game.legal_actions(game, seat), else: []
    {decision, skip_rubies} = decide(actions, seat && Game.phase(game, seat), me)

    socket
    |> assign(
      game: game,
      me: me,
      selected: [],
      decision: decision,
      all_actions: actions,
      actions: if(decision || skip_rubies, do: [], else: Enum.reject(actions, &witch?/1)),
      skip_rubies: skip_rubies,
      stop_slot: stop_slot(game, me),
      essence_pick: essence_pick(me, socket.assigns[:essence_pick])
    )
    |> open_reveal()
  end

  # -- the reveal overlay (round 14) ----------------------------------------------------

  # A seat that has not seen the game's moment gets its slides (`Reveal.slides/2`),
  # from the first one: also after a reload. Taken once, so a bot's move does not
  # change what the overlay shows. A fortune choice shows its card in its own
  # dialog, so no overlay then. A spectator gets none.
  defp open_reveal(%{assigns: %{seat: seat, game: game} = assigns} = socket)
       when is_integer(seat) do
    key = Reveal.moment(game)

    case reveal_step(assigns, key) do
      :keep -> socket
      :drop -> assign(socket, reveal: nil)
      :drop_seen -> socket |> assign(reveal: nil) |> mark_seen(key)
      :open -> start_reveal(socket, key, Reveal.slides(game, seat))
    end
  end

  defp open_reveal(socket), do: socket

  # What the overlay does with the game's moment `key`.
  defp reveal_step(_assigns, nil), do: :keep

  # The choice dialog shows the card (also when the choice comes while the overlay
  # shows it): it counts as seen.
  defp reveal_step(%{decision: :fortune_choice} = assigns, {:card, _round} = key),
    do: if(seen_key?(assigns.seen, key), do: :drop, else: :drop_seen)

  defp reveal_step(%{reveal: %{key: key}}, key), do: :keep

  defp reveal_step(assigns, key), do: if(seen_key?(assigns.seen, key), do: :drop, else: :open)

  defp start_reveal(socket, _key, []), do: socket

  defp start_reveal(socket, key, slides) do
    socket
    |> assign(reveal: %{key: key, slides: slides, index: 0, tick: nil})
    |> show_slide(0)
  end

  defp seen_key?(seen, {kind, round}), do: seen?(seen, kind, %{round: round})

  defp next_slide(%{assigns: %{reveal: %{index: index, slides: slides}}} = socket) do
    if index + 1 < length(slides),
      do: show_slide(socket, index + 1),
      else: close_reveal(socket)
  end

  # Show slide `index`; in Auto mode its timer starts (`Process.send_after/3`, only
  # on a live page). A new tick ref drops the pending one.
  defp show_slide(%{assigns: %{reveal: reveal} = assigns} = socket, index) do
    tick = if assigns.reveal_mode == :auto and connected?(socket), do: make_ref()

    if tick do
      ms = reveal.slides |> Enum.at(index) |> Reveal.duration(Reveal.factor(assigns.reveal_speed))
      Process.send_after(self(), {:reveal_tick, tick}, ms)
    end

    assign(socket, reveal: %{reveal | index: index, tick: tick})
  end

  # The end of the reveal: the moment counts as seen (`GameServer.ack/4`), the
  # pot's replay shows its end state, and what waited opens (app.js `quacks:open`).
  defp close_reveal(%{assigns: %{reveal: %{key: key}}} = socket) do
    socket
    |> assign(reveal: nil)
    |> mark_seen(key)
    |> auto_done()
    |> open_waiting()
  end

  defp mark_seen(%{assigns: %{seat: seat}} = socket, {kind, round}) when is_integer(seat) do
    GameServer.ack(socket.assigns.id, seat, kind, round)
    update(socket, :seen, &Map.put(&1, kind, round))
  end

  defp mark_seen(socket, _key), do: socket

  defp open_waiting(%{assigns: %{game: game, decision: decision}} = socket) do
    cond do
      Game.over?(game) -> push_event(socket, "quacks:open", %{to: "#game-over"})
      decision -> push_event(socket, "quacks:open", %{to: decision_dialog(decision, game)})
      true -> socket
    end
  end

  # This seat's decision, and whether it is a rubies step to skip (nothing to spend,
  # no witch to call).
  defp decide(actions, phase, me) do
    case decision(actions, phase, me) do
      :rubies ->
        if Enum.any?(actions, &ruby_step_action?/1), do: {:rubies, false}, else: {nil, true}

      decision ->
        {decision, false}
    end
  end

  defp stop_slot(game, %Player{phase: :stopped}), do: if(stir?(game), do: :stop, else: :resume)
  defp stop_slot(_game, _me), do: :stop

  defp ruby_step_action?({:rubies, _}), do: true
  defp ruby_step_action?(action), do: witch?(action)

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
  # A spectator has seen them all: no card or results open on top of each other.
  defp seen?(:all, _kind, _game), do: true
  defp seen?(seen, kind, game), do: seen[kind] == game.round

  defp seen(_table, nil), do: :all
  defp seen(table, seat), do: Map.get(table.seen, seat, %{})

  # The round results show from the shop until the round ends (round 9 has no shop).
  defp results?(game), do: game.phase == :shopping

  # The update chips of the round still play (this seat has not seen them).
  defp replaying?(game, seen), do: results?(game) and not seen?(seen, :results, game)

  # Auto mode: the shown slide's time (the overlay's timer bar), else nil.
  defp reveal_ms(%{slides: slides, index: index}, :auto, speed),
    do: slides |> Enum.at(index) |> Reveal.duration(Reveal.factor(speed))

  defp reveal_ms(_reveal, _mode, _speed), do: nil

  # The last slide's button names what comes next.
  defp close_label(%{key: {:final, _}}, _decision, _skip), do: "See the results"
  defp close_label(_reveal, :shop, _skip), do: "To the shop"
  defp close_label(_reveal, :rubies, _skip), do: "Spend rubies"
  defp close_label(%{key: {:results, _}}, _decision, true), do: "Done"
  defp close_label(_reveal, _decision, _skip), do: "Close"

  # The results panel's rows (64rem, while the replay plays): every seat's bonus
  # die, one after the other (Take a Chance), then this seat's own lines: the books
  # of step B, the scoring space, the card. Each row keeps its replay beat
  # (`Replay.beats/3`), so the panel, the pot and the name cards play in step.
  defp result_rows(game, seat, names) do
    dice =
      for s <- game.seats, line <- Replay.beats(game, s), line.kind == :die do
        Map.merge(line, %{seat: s, who: if(s == seat, do: "You", else: name(names, s))})
      end

    mine =
      for line <- (seat && Replay.beats(game, seat)) || [], line.kind != :die do
        Map.merge(line, %{seat: seat, who: nil})
      end

    Enum.sort_by(dice ++ mine, & &1.beat)
  end

  # Take a Chance (card p12): every seat rolled the bonus die at the round's start.
  # `[{seat, who, face}]` in seat order, from the log (the engine logs one roll each).
  defp chance_rolls(game, seat, names) do
    rolls =
      game.log
      |> Enum.take_while(&(not match?({:round_end, _}, &1)))
      |> Enum.flat_map(fn
        {s, {:fortune, :p12, face}} -> [{s, face}]
        _entry -> []
      end)
      |> Map.new()

    for s <- game.seats,
        face = rolls[s],
        do: {s, if(s == seat, do: "You", else: name(names, s)), face}
  end

  # The rolls of Take a Chance in the context column (64rem), one die after the
  # other: each lands, then its reward shows (`.chance-row` in app.css, two steps
  # of 300 ms each). The id names the round, so it plays once when it enters.
  attr :id, :string, required: true
  attr :rolls, :list, required: true

  defp chance_panel(assigns) do
    ~H"""
    <section
      :if={@rolls != []}
      id={@id}
      class="paper hidden shrink-0 rounded-xl px-3 py-2 shadow-md lg:block"
      aria-label="Take a Chance"
      data-role="chance-panel"
    >
      <h2 class="font-hand text-xl leading-tight font-bold">Take a Chance</h2>
      <ol class="mt-1.5 space-y-1.5">
        <li
          :for={{{seat, who, face}, i} <- Enum.with_index(@rolls)}
          class="chance-row flex items-center gap-2 text-sm"
          style={"--beat: #{2 * i}"}
          data-beat={2 * i}
          data-role="chance-roll"
          data-seat={seat}
        >
          <.die face={face} />
          <span class="chance-text inline-flex min-w-0 items-center gap-1 font-semibold">
            <.seat_dot seat={seat} />{who}: {die_text(face)}
          </span>
        </li>
      </ol>
    </section>
    """
  end

  # Round results in the context column (64rem): the dice land, then each book's
  # result shows on its beat (`.result-row` in app.css; at once with reduced motion
  # or after Skip). Phones keep the die in the bar and the chips on the name cards.
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :round, :integer, required: true

  defp results_panel(assigns) do
    ~H"""
    <section
      :if={@rows != []}
      id={@id}
      class="results-panel paper hidden shrink-0 rounded-xl px-3 py-2 shadow-md lg:block"
      aria-label="Round results"
      data-role="results-panel"
    >
      <h2 class="font-hand text-xl leading-tight font-bold">Round {@round}: evaluation</h2>
      <ol class="mt-1.5 space-y-1.5">
        <li
          :for={row <- @rows}
          class={[
            "flex items-center gap-2 text-sm",
            if(row.kind == :die, do: "replay-die", else: "result-row")
          ]}
          style={"--beat: #{row.beat}"}
          data-role="result-row"
          data-kind={row.kind}
          data-seat={row.seat}
          data-beat={row.beat}
        >
          <%= if row.kind == :die do %>
            <.die face={row.face} />
            <span class="replay-die-text min-w-0 font-semibold">
              <span :if={row.who} class="mr-1 inline-flex items-center gap-1">
                <.seat_dot seat={row.seat} />{row.who}:
              </span>{row.text}
            </span>
          <% else %>
            <span class="grid size-9 shrink-0 place-items-center rounded-full bg-parchment-deep/70">
              <.ingredient_icon
                :if={row.kind in [:green, :black, :purple]}
                colour={row.kind}
                class={["size-6", book_ink(row.kind)]}
              />
              <.icon
                :if={row.kind not in [:green, :black, :purple]}
                name="hero-sparkles"
                class="size-5 text-ink-soft"
              />
            </span>
            <span class="min-w-0 font-semibold">{row.text}</span>
          <% end %>
        </li>
      </ol>
    </section>
    """
  end

  # While the replay plays: on which beat each book lights up, `%{colour => beat}`
  # (the first line of a green, black or purple book).
  defp book_beats(game, seat, seen) do
    if replaying?(game, seen) do
      for line <- Replay.beats(game, seat || 0),
          line.kind in [:green, :black, :purple],
          reduce: %{},
          do: (acc -> Map.put_new(acc, line.kind, line.beat))
    else
      %{}
    end
  end

  # While the replay plays (scoring sequence): the rubies and VP tags on the pot, the
  # bonus die beside it, and the beats the VP and ruby counters tick on (a ruby
  # counter when its last ruby lands, see app.css).
  defp replay_effects(game, seat, seen) do
    if replaying?(game, seen),
      do: game |> Replay.beats(seat || 0) |> Replay.pot_effects(),
      else: []
  end

  defp replay_die_lines(game, seat),
    do: game |> Replay.beats(seat || 0) |> Enum.filter(&(&1.kind == :die))

  # With `:from`, the values the counters start from (`Replay.before/2`): on the tab
  # that ends the round the strip was never drawn with the old values.
  defp stat_beats(game, seat, seen) do
    if replaying?(game, seen),
      do:
        for(
          %{kind: kind, beat: beat} <- Replay.updates(game, seat),
          kind in [:vp, :rubies],
          into: %{from: Replay.before(game, seat)},
          do: {kind, beat}
        ),
      else: %{}
  end

  # While the round results show: what lights up on the pot on which replay beat
  # (the same beats as the dialog's lines, so both play in step).
  defp replay_marks(game, seat) do
    if results?(game), do: game |> Replay.beats(seat || 0) |> Replay.highlights(), else: %{}
  end

  # A shop with "Done" as the only move left (nothing to buy, no rubies to spend, no
  # witch to call: `skip_rubies`) ends this seat's round by itself, so the player is
  # not asked for a bare "Done". Right after its own buy or ruby spend (`acted?`),
  # else not while the round's beats still play: the update chips stay until they
  # are read (the "seen" event comes back here).
  defp auto_done(socket, acted? \\ false)

  defp auto_done(
         %{assigns: %{skip_rubies: true, seat: seat, game: game} = assigns} = socket,
         acted?
       )
       when is_integer(seat) do
    with false <- not acted? and replaying?(game, assigns.seen),
         {:ok, game} <- GameServer.apply(assigns.id, seat, :end_round) do
      put_game(socket, game)
    else
      _ -> socket
    end
  end

  defp auto_done(socket, _acted?), do: socket

  defp shop_move?({kind, _what}), do: kind in [:buy, :rubies]
  defp shop_move?(_action), do: false

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

  # The server's Mandrake answer for this seat is the newest action (nothing happened
  # since), so the player may still keep the white chip. Bots answer for themselves.
  defp keep_white?(game, seat, bots) when is_integer(seat) and not is_map_key(bots, seat),
    do: match?([{^seat, {:returned, {:white, _}}}, {^seat, :return_white} | _], game.log)

  defp keep_white?(_game, _seat, _bots), do: false

  # Why the waiting droplet moves came (reverse pot side): this seat's log events that
  # moved its droplet since its last droplet choice (or the round's start).
  defp droplet_sources(log, seat) do
    log
    |> Enum.take_while(
      &(not match?({^seat, {:droplet, _}}, &1) and not match?({:round_end, _}, &1))
    )
    |> Enum.filter(fn
      {^seat, {:black, _}} -> true
      {^seat, {:bonus_die, :droplet}} -> true
      {^seat, {:purple, 3, _}} -> true
      {^seat, {:fortune, _id, :droplet}} -> true
      {^seat, {:essence_bonus, {:droplet, _}}} -> true
      _entry -> false
    end)
    |> Enum.reverse()
    |> Enum.map(fn {_seat, event} -> {cause(event), label(event)} end)
  end

  # What moved the droplet, as a picture: the chip of the book (a black chip for the
  # hawkmoth), the die, the card or the flask.
  defp cause({:black, _}), do: {:chip, {:black, 1}}
  defp cause({:purple, 3, _}), do: {:chip, {:purple, 1}}
  defp cause({:bonus_die, face}), do: {:die, face}
  defp cause({:fortune, _id, _outcome}), do: :card
  defp cause(_event), do: :essence

  attr :cause, :any, required: true

  defp droplet_cause(%{cause: {:chip, _chip}} = assigns),
    do: ~H"""
    <.chip chip={elem(@cause, 1)} data-role="droplet-cause" />
    """

  defp droplet_cause(%{cause: {:die, _face}} = assigns),
    do: ~H"""
    <span data-role="droplet-cause"><.die face={elem(@cause, 1)} /></span>
    """

  defp droplet_cause(assigns),
    do: ~H"""
    <span
      class="grid size-9 shrink-0 place-items-center rounded-full bg-parchment-deep"
      data-role="droplet-cause"
    >
      <.icon name="hero-sparkles" class="size-5" />
    </span>
    """

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

  defp back_label(:rubies, %Game{round: 9}), do: "Back to final scoring"
  defp back_label(decision, _game) when decision in [:shop, :rubies], do: "Back to shop"
  defp back_label(_decision, _game), do: "Back to choice"

  # Whether a decision dialog opens with one enabled primary button (it takes the
  # focus); otherwise the dialog itself does. The shop's Buy is disabled until a
  # chip is ticked; ruby options make "Keep rubies" a ghost.
  defp primary_on_open?(:shop, actions), do: not Enum.any?(actions, &match?({:buy, _}, &1))
  defp primary_on_open?(:rubies, actions), do: not ruby_options?(actions)
  defp primary_on_open?(:patient_choice, _actions), do: false
  defp primary_on_open?(:essence_choice, _actions), do: true

  defp primary_on_open?(decision, actions),
    do: choice_variant(dialog_buttons(actions, decision)) == :primary

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
  # Copper, silver, gold: the order of the rulebook's pennies (round 14).
  defp witches(game), do: for(c <- [:copper, :silver, :gold], do: {c, game.witches[c]})

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

  # Round 9 has no shop: the coins stay and convert to VP at the end (5 for 1).
  defp action_label({:explosion_choice, :buy}, %Game{round: 9}, me),
    do: "Take coins (#{PotTrack.at(Player.scoring_index(me)).coins}, converted to VP at the end)"

  defp action_label({:explosion_choice, :buy}, _game, me),
    do: "Take coins (#{PotTrack.at(Player.scoring_index(me)).coins} to spend)"

  defp action_label(action, game, _me), do: label(action, game.fortune_card)

  defp ruby_use(:droplet, %{rules: %{pot_side: :back}}, _me), do: "pot droplet +1"
  defp ruby_use(:droplet, _game, _me), do: "droplet +1"
  defp ruby_use(:flask, _game, _me), do: "refill flask"

  defp ruby_use(:tube, _game, me), do: "test tube (#{next_glass(me)})"

  defp next_glass(me), do: "bonus: #{tube_bonus(TestTubes.bonus(me.tube + 1))}"

  defp name(names, seat), do: Map.get(names, seat, GameServer.default_name(seat))

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
