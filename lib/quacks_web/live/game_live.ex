defmodule QuacksWeb.GameLive do
  @moduledoc """
  The game page, `/g/:id`, for 1 to 8 players. The game itself lives in a
  `Quacks.GameServer` process; this LiveView asks it for a seat on mount (by the
  browser's player token), subscribes to the game's PubSub topic and re-renders on
  every `{:game, id, game}` broadcast. Every button comes from
  `Quacks.Game.legal_actions/2` for this browser's seat and every click goes through
  `Quacks.GameServer.apply/3`. The page itself knows no rules. A browser without a
  seat (the game is full) watches: it sees every pot and no buttons.

  Before the game begins (`GameServer` status `:waiting`) the page is the waiting
  panel (round 26; the settings were made in the spell book, `QuacksWeb.LobbyLive`):
  one row per seat (name, colour, bot, host, "you" with your name field and colour
  picker), with The Alchemists your patient ("Random" or one of the 3 dealt), the
  link to share while a seat is open, and for the host "Start game" (every seat
  taken, `GameServer.begin/2`) or "Fill with bots" (`GameServer.fill_bots/2`).
  Every seat change is broadcast, so every waiting page reads the table again.
  Closing the page before the start frees the seat (`terminate/2`).

  The layout, top to bottom: the header ("You are" and your seat colour, which also
  runs along the top edge), your status, the players row (round 27: one tile per seat
  in a fixed seat loop, solo too; a tap opens that player's sheet), the pot, and the bottom bar with only
  Stop/Resume and Draw. Around the pot (round 22): this round's fortune card with the witches
  below it (top left), the kept Toadstool chips (top right), the flask (bottom
  left) and the bag (bottom right). The log, the share link and the books are in
  the menu. A new fortune card hovers over the pot once per round, with a bottom
  sheet under it.

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
  button ("Back to shop", "Back to choice", "Continue" for the card's choice) takes the place of Stop and Draw and
  opens it again.

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
  import QuacksWeb.CardRevealComponents

  import QuacksWeb.SetupComponents

  import QuacksWeb.AlchemistsComponents
  import QuacksWeb.BugReportComponents
  import QuacksWeb.RevealComponents
  import QuacksWeb.TileRevealComponents

  alias Quacks.{Game, GameServer, Player}
  alias Quacks.Game.Fortune
  alias Quacks.Rules.{Alchemists, Books, Chips, PotTrack, TestTubes}
  alias QuacksWeb.{Replay, Reveal, TileReveal}

  # The colours with an ingredient book (white has none), for `offer_books/1`.
  @book_colours Chips.order() -- [:white]

  # The standings slide's first render shows the old ranks this long (round 18; the
  # tests set it long and send the tick themselves).
  @settle_ms Application.compile_env(:quacks, :reveal_settle_ms, 300)

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
           card_grown: false,
           result_closed: false,
           reveal_mode: :step,
           reveal_speed: :normal,
           risk: :percent,
           reveal_show: :overlay,
           reveal_choice: :overlay,
           phone: false,
           reduced: false
         )
         |> new_report()
         |> assign_table(table)
         |> put_game(table.game)
         |> result_on_mount()}

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

  # Round 24: while the corner card is grown, Enter and Space shrink it again.
  def handle_event("hotkey", %{"key" => key} = params, %{assigns: %{card_grown: true}} = socket)
      when key in ["Enter", " "] do
    if params["typing"] == true,
      do: {:noreply, socket},
      else: {:noreply, shrink_card(socket)}
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

  # The waiting panel (round 26): your patient (The Alchemists), Start, and the
  # host's "Fill with bots" (a bot in every free seat, then the game begins).
  def handle_event("patient", params, %{assigns: %{seat: seat}} = socket)
      when is_integer(seat) do
    pick = parse_patient(params["patient"], socket.assigns.patients || [])

    case GameServer.pick_patient(socket.assigns.id, seat, pick) do
      {:error, :not_found} -> {:noreply, ended(socket)}
      _ok_or_late -> {:noreply, socket}
    end
  end

  def handle_event("patient", _params, socket), do: {:noreply, socket}

  def handle_event("fill_bots", _params, socket) do
    case GameServer.fill_bots(socket.assigns.id, socket.assigns.token) do
      {:ok, game} -> {:noreply, socket |> reseat() |> put_game(game)}
      {:error, :not_found} -> {:noreply, ended(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Only the host can start.")}
    end
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
  # Round 22: the game's last slide (the podium with Play again) stays; × or Esc
  # close it, and "Show the result" opens it again.
  def handle_event(
        "reveal_next",
        _params,
        %{assigns: %{reveal: %{key: {:final, _}} = r}} = socket
      )
      when r.index == length(r.slides) - 1,
      do: {:noreply, socket}

  # Round 29: a tap on the final tally while it plays finishes it at once (the new
  # totals and ranks) and pauses Auto; the next tap shows the podium.
  def handle_event(
        "reveal_next",
        _params,
        %{assigns: %{reveal: %{key: {:final, _}, settled: false} = r}} = socket
      ),
      do:
        {:noreply,
         assign(socket, reveal: %{r | settled: true, settle: nil, tick: nil, paused: true})}

  def handle_event("reveal_next", _params, %{assigns: %{reveal: %{}}} = socket),
    do: {:noreply, next_slide(socket)}

  def handle_event("show_result", _params, socket), do: {:noreply, open_result(socket)}

  # Round 24: a tap on the big card over the pot (or anywhere, `#card-tap`). A new
  # card goes on (`next_slide/1`: into the corner, or its result or choice sheet); a
  # grown corner card shrinks again.
  def handle_event("card_tap", _params, %{assigns: %{reveal: %{held: true}}} = socket),
    do: {:noreply, next_slide(socket)}

  def handle_event("card_tap", _params, %{assigns: %{card_grown: true}} = socket),
    do: {:noreply, shrink_card(socket)}

  def handle_event("card_tap", _params, socket), do: {:noreply, socket}

  # Round 24: a tap on the corner card grows it back into the big card over the pot
  # (the reverse view transition). Not while a new card or a reveal shows.
  def handle_event(
        "card_grow",
        _params,
        %{assigns: %{reveal: nil, game: %Game{} = game}} = socket
      )
      when game.fortune_card != nil do
    {:noreply,
     socket
     |> push_event("quacks:vt", %{type: "card"}, dispatch: :before)
     |> assign(card_grown: true)}
  end

  def handle_event("card_grow", _params, socket), do: {:noreply, socket}

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

    choice = reveal_choice(params["show"], socket.assigns.reveal_choice)
    # Round 28: phones always play the results on the tiles (no overlay).
    phone = Map.get(params, "phone", socket.assigns.phone) in [true, "true"]
    show = if phone, do: :tiles, else: choice
    # Round 29: the risk shown beside the white meter (`quacks:risk` in this browser).
    risk =
      Enum.find(
        [:off, :percent, :chips],
        socket.assigns.risk,
        &(Atom.to_string(&1) == params["risk"])
      )

    socket =
      assign(socket,
        reveal_mode: mode,
        reveal_speed: speed,
        reveal_show: show,
        reveal_choice: choice,
        risk: risk,
        phone: phone,
        reduced: reduced
      )

    case socket.assigns.reveal do
      # Round 27: the settings come after mount, so the results' reveal starts again
      # where the Results setting says (the overlay or the tiles).
      %{key: {:results, _} = key} = reveal when reveal.tiles != (show == :tiles) ->
        slides = Reveal.slides(socket.assigns.game, socket.assigns.seat)
        {:noreply, socket |> assign(reveal: nil) |> start_reveal(key, slides)}

      %{index: index} ->
        {:noreply, show_slide(socket, index)}

      nil ->
        {:noreply, socket}
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

  # The standings slide (round 18): its first render shows the old ranks; this tick
  # sets the new ones, and CSS glides the rows (a stale tick is ignored).
  def handle_info({:reveal_settle, ref}, %{assigns: %{reveal: %{settle: ref} = reveal}} = socket),
    do: {:noreply, assign(socket, reveal: %{reveal | settled: true, settle: nil})}

  def handle_info({:reveal_settle, _ref}, socket), do: {:noreply, socket}

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
  # count the host picked); `@sets` names the books for the shop. `@patients` is The
  # Alchemists' deal (nil without it), `@patient_picks` each seat's pick so far.
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
      patients: table.patients,
      patient_picks: table.patient_picks
    )
  end

  # Phones: one screen, no page scroll. Rows: header, status, notices, the pot (takes
  # the free space), the bottom bar. Bag, log, players, card text and the menu are
  # sheets; a decision opens as a dialog over the pot. Large screens add a right
  # column where the bag, log and players sheets show in place.
  @impl true
  def render(%{game: nil} = assigns) do
    assigns =
      assign(assigns,
        host: host?(assigns.seat, assigns.creator),
        full: map_size(assigns.names) >= assigns.players
      )

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
      <%!-- Round 26: the settings were made in the spell book; this panel only seats
           the players. --%>
      <section
        id="waiting-panel"
        class="paper mx-auto max-w-md space-y-3 rounded-lg p-3"
        aria-label="Waiting for players"
      >
        <div class="flex items-baseline justify-between gap-2">
          <h2 class="text-lg font-bold">Waiting for players</h2>
          <span class="text-sm font-semibold tabular-nums" data-role="waiting-for-players">
            {map_size(@names)} of {@players} seated
          </span>
        </div>
        <ol class="space-y-1" aria-label="Seats">
          <li
            :for={seat <- 0..(@players - 1)}
            class="flex min-h-11 flex-wrap items-center gap-x-2 rounded-md bg-parchment-light px-2"
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
            <span :if={!@names[seat]} class="text-ink-soft italic">open seat</span>
            <span :if={@names[seat] && seat == @creator} class="text-xs text-ink-soft">host</span>
            <span :if={seat == @seat} class="ml-auto text-xs font-semibold">you</span>
            <.colour_picker :if={seat == @seat} colours={@colours} seat={seat} />
          </li>
        </ol>
        <%!-- Round 29: Share (the phone's share sheet) is the main button; where the
             browser has no share sheet, Copy link stands in (app.css `.share-only`).
             The room code is large, to read aloud. --%>
        <div :if={!@full} id="invite" class="space-y-2 text-sm" data-role="invite">
          <div class="text-center">
            <span class="block text-xs font-semibold text-ink-soft">Room code</span>
            <span
              class="block font-hand text-4xl leading-tight font-bold tracking-[0.3em] text-ink"
              data-role="room-code"
              aria-label={"Room code " <> Enum.join(String.graphemes(@id), " ")}
            >
              {@id}
            </span>
          </div>
          <div class="flex gap-2">
            <input
              type="text"
              readonly
              value={url(~p"/g/#{@id}")}
              aria-label="Game link"
              data-role="share-link"
              class="min-w-0 flex-1 rounded-md border border-ink-soft bg-parchment-light px-2 py-2 font-mono text-sm text-ink"
            />
            <.button
              id="share-game"
              phx-click={
                JS.dispatch("quacks:share",
                  detail: %{
                    title: "Quacks",
                    text: "Join my Quacks game. Room code: #{@id}",
                    url: url(~p"/g/#{@id}")
                  }
                )
              }
              variant={:primary}
              class="share-only hit-44"
              data-role="share-game"
            >
              <.icon name="hero-share" class="size-4" /> Share
            </.button>
            <.copy_link url={url(~p"/g/#{@id}")} copied={@copied} class="share-fallback" />
          </div>
        </div>
        <.patient_picker
          :if={@patients && @seat && Map.has_key?(@patient_picks, @seat)}
          class="pt-1"
          id="waiting-patient"
          patients={@patients}
          chosen={@patient_picks[@seat]}
        />
      </section>
      <.spectator_note :if={is_nil(@seat)} rejoinable={@rejoinable} names={@names} />
      <%!-- The action stays in reach at the bottom while the patients scroll. --%>
      <div
        :if={@seat}
        class="sticky bottom-0 z-10 -mx-4 -mb-6 flex items-center justify-end gap-3 border-t-2 border-black/30 bg-wood-dark/95 px-4 pt-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] shadow-[0_-10px_20px_-12px_rgb(0_0_0/0.7)] backdrop-blur-sm sm:-mx-6 sm:-mb-12 sm:rounded-t-xl sm:px-6"
        data-role="start-bar"
      >
        <.button
          :if={@host and @full}
          phx-click="begin"
          variant={:primary}
          class="min-h-12 px-6 text-base"
          data-role="start-game"
        >
          Start game
        </.button>
        <p :if={@host and !@full} class="min-w-0 flex-1 text-sm leading-snug text-parchment-dim">
          Share the link, or play the open seats with bots.
        </p>
        <.button
          :if={@host and !@full}
          phx-click="fill_bots"
          variant={:primary}
          class="min-h-12 shrink-0 px-5 text-base"
          data-role="fill-bots"
        >
          Fill with bots
        </.button>
        <p :if={!@host} class="min-w-0 flex-1 text-sm font-semibold" data-role="waiting-for-host">
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
            <span class="pl-1 text-tag leading-none font-bold tracking-wide text-parchment-dim uppercase">
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
              class="absolute top-0.5 right-0 min-w-[18px] rounded-full bg-parchment px-1 text-tag leading-[18px] font-bold text-ink tabular-nums"
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
          <%!-- Round 27: one tile per seat in a fixed seat loop (`seat_loop/1`):
               one row up to 4 seats, two rows from 5, the second row backwards, so
               neighbours touch. The tiles never re-order and have a fixed height.
               After the brew each tile's counters tick on the replay beats; the
               tile with the last beat ends the replay (`replay_end/3`, app.js). --%>
          <nav
            id="players-row"
            class={[
              "-mx-2 grid gap-1 px-2 pt-1.5 pb-0.5",
              not replaying?(@game, @seen) && "replay-done"
            ]}
            style={"grid-template-columns: repeat(#{loop_columns(length(@game.seats))}, minmax(0, 1fr))"}
            aria-label="Players"
            data-role="players-row"
            data-columns={loop_columns(length(@game.seats))}
          >
            <.player_chip
              :for={{seat, row, col} <- seat_loop(@game.seats)}
              game={@game}
              seat={seat}
              name={name(@names, seat)}
              you={seat == @seat}
              bot={Map.has_key?(@bots, seat)}
              lead={seat in round_leaders(@game)}
              row={row}
              col={col}
              updates={if results?(@game), do: Replay.updates(@game, seat), else: []}
              ticks={replaying?(@game, @seen) and not tiles_playing?(@reveal)}
              totals={tiles_playing?(@reveal) && tile_totals(@game, @reveal)[seat]}
              news={
                (@reveal_show == :tiles or @game.phase == :potions) &&
                  TileReveal.news(@game, seat, @reveal)
              }
              rolls={if @reveal_show == :tiles, do: TileReveal.rolls(@game, seat), else: []}
            />
          </nav>
          <%!-- Round 16: the rat track, a fixed height while the rats rule is on. --%>
          <.rat_track
            :if={@game.rules.rats and length(@game.seats) > 1}
            game={@game}
            seat={@seat}
            names={@names}
            vps={tiles_playing?(@reveal) && tile_vps(@game, @reveal)}
          />
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
            preview
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
              <%!-- Round 29: your own explosion's beat (app.css `.boom`); the hook
                   buzzes the phone once (app.js `Boom`). --%>
              <p
                :if={@me && @me.exploded? && @game.phase == :potions}
                id={"boom-#{@game.round}"}
                class="boom"
                phx-hook="Boom"
                data-key={"#{@id}-#{@game.round}"}
                aria-hidden="true"
                data-role="boom"
              >
                BOOM
              </p>
              <%!-- Round 22: the top left corner holds the round's card (a tap
                   shows its text) and, below it, the witches. Small enough for the
                   free corner outside the round rim. --%>
              <div
                :if={@game.fortune_card || @game.witches}
                class="absolute top-0 left-0 flex flex-col items-start gap-1.5"
                data-role="pot-corner"
              >
                <.fortune_tile
                  :if={@game.fortune_card}
                  id={@game.fortune_card}
                  dom_id="corner-card"
                  click="card_grow"
                />
                <.sheet_button
                  :if={@game.witches}
                  for="sheet-witches"
                  class="flex-col gap-0! rounded-2xl px-1.5! py-1 text-[10px] leading-tight lg:hidden"
                  data-role="witches-button"
                >
                  <span class="flex -space-x-1.5">
                    <.piece_icon name={:penny} class="size-4 text-penny-copper" />
                    <.piece_icon name={:penny} class="size-4 text-penny-silver" />
                    <.piece_icon name={:penny} class="size-4 text-penny-gold" />
                  </span>
                  Witches
                </.sheet_button>
              </div>
              <p
                :if={stir?(@game)}
                class="absolute top-0 left-1/2 -translate-x-1/2 rounded-full bg-gold px-3 py-0.5 text-sm font-bold whitespace-nowrap text-ink shadow-md"
                data-role="stir"
              >
                Stir! Everyone draws together.
              </p>
              <%!-- Round 22: a new card hovers over the pot, large; when it goes it
                   shrinks into the corner card (a view transition, `card_vt/2`).
                   Round 24: first with no sheet and a "Tap to continue" caption; a
                   tap anywhere (`#card-tap`) goes on. The grown corner card shows
                   here too. Absolute, under the tap layer: the pot stays where it
                   is. --%>
              <div
                :if={pot_card?(assigns)}
                id={"pot-card-#{@game.round}"}
                class={[
                  "pot-card",
                  if(@reveal || @card_grown, do: "pot-card-reveal", else: "lg:hidden")
                ]}
                aria-hidden="true"
                data-role="pot-card"
              >
                <%!-- Round 25: the grown corner card has no flip; the card
                     transition alone grows it (the shrink played backwards). --%>
                <.fortune_card id={@game.fortune_card} flip_id="pot-card-flip" flip={!@card_grown} />
                <.card_reveals
                  id={"pot-card-reveals-#{@game.round}"}
                  card={@game.fortune_card}
                  reveals={Quacks.Game.Fortune.reveals(@game)}
                  order={Game.turn_order(@game)}
                  seat={@seat}
                  names={@names}
                  game={@game}
                  class="paper rounded-md border-l-4 border-chip-purple p-2"
                />
                <p
                  :if={card_tap?(assigns)}
                  id={"card-caption-#{@game.round}-#{@card_grown}"}
                  class="card-caption"
                  data-role="card-caption"
                >
                  Tap to continue
                </p>
              </div>
              <%!-- Round 22: the kept Toadstool chips (red Set 2) wait in the top
                   right corner, a small pill outside the round rim. --%>
              <.aside
                :if={@me && @me.aside != []}
                chips={@me.aside}
                class="absolute top-0 right-0"
              />
              <%!-- The overflow bowl hangs over the pot's lower rim. --%>
              <div
                :if={@game.players[@seat || 0].bowl != []}
                class="absolute inset-x-12 bottom-0 flex items-end justify-center gap-2"
                data-role="bowl-strip"
              >
                <.bowl chips={@game.players[@seat || 0].bowl} />
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
            :if={@decision && @decision != :fortune_choice && !@bar_choice}
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
              <.red_rows
                :if={@decision == :red_choice}
                actions={@all_actions}
                pool={@me.pending}
                game={@game}
                me={@me}
              />
              <.chip_picks
                :if={@decision not in [:blue_choice, :witch_offer, :red_choice]}
                actions={@all_actions}
                game={@game}
                me={@me}
              />
              <.ladder
                :if={@decision == :chip_choice}
                rungs={ladder(@me, @all_actions, @game)}
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
                  :if={not ladder_action?(action)}
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
            auto_open={is_nil(@reveal)}
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
              <%!-- Phones: the card hovers over the pot instead (`pot_card?/1`). --%>
              <div class={pot_card?(assigns) && "max-lg:hidden"}>
                <.fortune_card id={@game.fortune_card} choice flip />
              </div>
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
          <%!-- Round 29: the results' steps on the tiles take the bar's place. --%>
          <.tile_stage :if={tiles_playing?(@reveal)} reveal={@reveal} mode={@reveal_mode} />
          <.button
            :if={@skip_rubies && !tiles_playing?(@reveal)}
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
            :if={@decision && !@bar_choice && !tiles_playing?(@reveal)}
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
            phx-click="show_result"
            data-role="show-result"
          >
            Show the result
          </.button>
          <%!-- Round 29: one row, the white meter, then the reward and the risk as icons. --%>
          <div
            :if={@seat && @game.phase == :potions}
            class="flex min-w-0 items-center gap-2"
            data-role="fuse-row"
          >
            <.fuse_meter game={@game} seat={@seat} />
            <.reward_line game={@game} seat={@seat} risk={@risk} />
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
          <.bar_choice
            :if={@bar_choice && not Game.over?(@game) && !tiles_playing?(@reveal)}
            choice={@bar_choice}
            actions={@all_actions}
            game={@game}
            me={@me}
          />
          <section
            :if={@seat && not Game.over?(@game) && not results?(@game) && !@bar_choice}
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
              Draw
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
        <.card_reveals
          id="sheet-fortune-reveals"
          card={@game.fortune_card}
          reveals={Quacks.Game.Fortune.reveals(@game)}
          order={Game.turn_order(@game)}
          seat={@seat}
          names={@names}
          game={@game}
        />
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
            <.sheet_button
              :if={@game.fortune_card}
              for="sheet-fortune"
              variant={:secondary}
              data-role="menu-fortune"
            >
              Fortune teller
            </.sheet_button>
            <.fullscreen_button id="fullscreen-menu" />
          </div>
          <.reveal_settings
            mode={@reveal_mode}
            speed={@reveal_speed}
            show={@reveal_choice}
            risk={@risk}
            phone={@phone}
            reduced={@reduced}
          />
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

      <%!-- The round's reveals, one slide at a time (round 14). Last in the page, so
           it stays on top when app.js opens the modals again (`remodal`). --%>
      <%!-- Round 24: while the big card waits for its tap, the whole screen is one
           button (over the page, under the dialogs' top layer). --%>
      <button
        :if={@game.fortune_card && card_tap?(assigns)}
        id="card-tap"
        type="button"
        class="fixed inset-0 z-40 cursor-pointer touch-manipulation"
        phx-click="card_tap"
        aria-label={card_tap_label(@game.fortune_card)}
        data-role="card-tap"
      />
      <.reveal_overlay
        :if={@reveal && not @reveal.held && not @reveal[:tiles]}
        reveal={@reveal}
        names={@names}
        seat={@seat}
        auto_ms={
          reveal_ms(
            @reveal,
            reveal_mode(@reveal, %{reduced: @reduced, reveal_mode: @reveal_mode}),
            @reveal_speed
          )
        }
        close_label={close_label(@reveal, @decision, @skip_rubies)}
      >
        <:podium :if={Game.over?(@game)}>
          <.game_over
            game={@game}
            names={@names}
            players={@players}
            bots={@bots}
            seat={@seat}
            share_url={url(~p"/g/#{@id}")}
          />
        </:podium>
      </.reveal_overlay>
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

  @doc """
  A "Copy link" button: it asks the browser to copy `url` (the `quacks:copy`
  listener in app.js) and tells the server, which shows "Copied" for 2 seconds.
  """
  attr :url, :string, required: true
  attr :copied, :boolean, default: false
  attr :class, :any, default: nil

  def copy_link(assigns) do
    ~H"""
    <.button
      phx-click={JS.dispatch("quacks:copy", detail: %{text: @url}) |> JS.push("copied")}
      variant={:secondary}
      class={["hit-44", @class]}
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
  rows for the rest. Solo: the score. This browser's place has a gold ring and
  "you" (round 29; no VP breakdown any more). Then, stuck to the sheet's bottom, "Play again" (`GameServer.play_again/2`: the
  same table again; focused when the dialog opens) and "Return to lobby".

  The podium rises place by place, the winner last, and a gold shimmer crosses the
  title (app.css `.podium-step`, `.win-shimmer`); reduced motion: fades only.
  """
  attr :game, Game, required: true
  attr :names, :map, required: true
  attr :players, :integer, required: true
  attr :bots, :map, default: %{}
  attr :seat, :integer, default: nil, doc: "this browser's seat, for \"You win!\""
  attr :share_url, :string, default: nil, doc: "the game's link, for Share (round 22)"

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
            "grid size-9 place-items-center rounded-full font-hand text-lg font-bold text-ink",
            if(seat == @seat,
              do: "ring-3 ring-gold ring-offset-2 ring-offset-parchment",
              else: "ring-2 ring-black/25"
            ),
            seat_bg(seat)
          ]}>
            {String.first(name(@names, seat))}
          </span>
          <span class="mt-1 line-clamp-2 w-full text-sm leading-tight font-semibold break-words">
            {name(@names, seat)}
          </span>
          <.you_tag :if={seat == @seat} />
          <.bot_badge :if={@bots[seat] && seat != @seat} />
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
          class={[
            "flex items-center gap-2 rounded-md bg-parchment-deep/60 px-2 py-1 text-left",
            seat == @seat && "ring-2 ring-gold"
          ]}
          data-seat={seat}
          data-place={place}
          data-role="final-score"
        >
          <span class="w-5 font-hand font-bold">{place}</span>
          <.seat_dot seat={seat} />
          <span class="min-w-0 flex-1 truncate font-semibold">{name(@names, seat)}</span>
          <.you_tag :if={seat == @seat} />
          <.bot_badge :if={@bots[seat] && seat != @seat} />
          <span class="font-hand text-lg font-bold tabular-nums">{vp} VP</span>
        </li>
      </ol>
      <%!-- Round 29 (F3): the actions stay at the sheet's bottom edge. --%>
      <div class="sticky-actions sticky bottom-0 z-10" data-role="game-over-actions">
        <div class="sticky-actions-bar grid grid-cols-2 gap-2 *:min-h-12">
          <.button
            phx-click="play_again"
            variant={:primary}
            class="col-span-2 text-base"
            data-role="play-again"
            autofocus
          >
            Play again
          </.button>
          <.button
            phx-click="lobby"
            variant={:secondary}
            class={[!@share_url && "col-span-2"]}
            data-role="return-to-lobby"
          >
            Back to lobby
          </.button>
          <.button
            :if={@share_url}
            phx-click={
              JS.dispatch("quacks:share",
                detail: %{text: share_text(@ranked, @names, @players), url: @share_url}
              )
            }
            variant={:secondary}
            data-role="share-result"
          >
            <.icon name="hero-share" class="size-4" /> Share
          </.button>
        </div>
      </div>
    </section>
    """
  end

  # Round 29 (F3): the podium marks this browser's own place.
  defp you_tag(assigns) do
    ~H"""
    <span
      class="rounded-full bg-gold px-1.5 text-[0.65rem] leading-4 font-bold tracking-wider text-ink uppercase"
      data-role="you"
    >
      you
    </span>
    """
  end

  # Round 22: what Share sends: the places and their VP, one line.
  defp share_text([{seat, vp, _place}], names, 1),
    do: "#{name(names, seat)} brewed #{vp} VP in Quacks."

  defp share_text(ranked, names, _players) do
    places =
      Enum.map_join(ranked, ", ", fn {s, vp, place} -> "#{place}. #{name(names, s)} #{vp} VP" end)

    "Quacks of Quedlinburg: #{places}."
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

  @doc """
  The shop dialogs: everything this seat may do between brewing and the next round,
  in two steps (`step`).

  `:shop`, while a buy is legal: on top, every chip the player owns (bag, pot and bowl), as counts. Then, while a
  buy is legal, a form of checkboxes, one per kind of chip, in a row per colour
  (see `shop_rows/0`), priced with the game's Ingredient books (`Chips.price/2`).
  The engine decides what may be ticked: a box is disabled when adding its chip
  to the selection is not a legal buy. "Buy selected" sends `{:buy, selected}`.

  The copper witches are here too. "Skip" buys nothing (`{:buy, []}`): with nothing
  ticked it is the one button; with chips ticked it is a small secondary button
  beside Buy (round 29: a mis-tap does not end the shop with nothing).

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
        <h3 class="text-tag font-semibold text-ink-soft">Your chips: {length(@owned)}</h3>
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
              <span class="text-tag text-ink-soft">
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
          class={["min-w-0", if(@selected != [], do: "flex-none px-3 text-sm", else: "flex-1")]}
          data-role="shop-done"
        >
          Skip
          <.kbd :if={!@buying?}>Enter</.kbd>
        </.button>
        <.button
          :if={@buying? and @selected != []}
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

  @doc """
  Round 29: a choice in the bar, where Stop and Draw sit (`@bar_choice`), not a sheet.
  It keeps the bar's height (`min-h-12`), so the pot does not move.

  `:explosion_choice`: Take VP or Take coins, each with its icon, its number and a
  one-line hint. On a phone it shows after the explosion's beat (BOOM over the pot,
  about 700 ms, `.bar-choice-late` in app.css), so a tap meant for Draw does not
  choose.

  `:rubies`: Skip, then one button per ruby use, each "2" (the seat's
  `ruby_price`) and the ruby, then its icon: the test tube (reverse pot side only),
  the flask, the pot (droplet +1). Round 9: 2 rubies buy 1 VP. A use that is not
  possible now is disabled and says why ("Flask full").
  """
  attr :choice, :atom, required: true, values: [:explosion_choice, :rubies]
  attr :actions, :list, required: true
  attr :game, Game, required: true
  attr :me, Player, required: true

  def bar_choice(%{choice: :explosion_choice} = assigns) do
    space = PotTrack.at(Player.scoring_index(assigns.me))
    assigns = assign(assigns, space: space, final?: assigns.game.round == 9)

    ~H"""
    <section
      id={"bar-explosion-#{@game.round}"}
      class="bar-choice bar-choice-late grid grid-cols-2 gap-2 *:min-h-12 *:touch-manipulation"
      aria-label="Your pot exploded: take the victory points or the coins"
      data-role="bar-explosion"
    >
      <.button
        phx-click="action"
        phx-value-action={encode({:explosion_choice, :vp})}
        disabled={{:explosion_choice, :vp} not in @actions}
        class="flex-col gap-0! px-2! py-1! leading-tight"
        aria-label={action_label({:explosion_choice, :vp}, @game, @me)}
        data-choice="vp"
      >
        <span class="flex items-center gap-1 text-base">
          <.piece_icon name={:vp} class="size-5" /> Take VP +{@space.vp}
        </span>
        <span class="text-xs font-normal opacity-80">Score now, no coins</span>
      </.button>
      <.button
        phx-click="action"
        phx-value-action={encode({:explosion_choice, :buy})}
        disabled={{:explosion_choice, :buy} not in @actions}
        class="flex-col gap-0! px-2! py-1! leading-tight"
        aria-label={action_label({:explosion_choice, :buy}, @game, @me)}
        data-choice="buy"
      >
        <span class="flex items-center gap-1 text-base">
          <.piece_icon name={:coin} class="size-5" /> Take coins {@space.coins}
        </span>
        <span class="text-xs font-normal opacity-80">
          {if @final?, do: "Turn into VP at the end", else: "Shop, no VP"}
        </span>
      </.button>
    </section>
    """
  end

  def bar_choice(%{choice: :rubies} = assigns) do
    assigns =
      assign(assigns,
        uses: ruby_uses(assigns.game),
        price: if(assigns.game.round == 9, do: 2, else: assigns.me.ruby_price)
      )

    ~H"""
    <section
      id="bar-rubies"
      class="bar-choice flex gap-1.5 *:min-h-12 *:min-w-0 *:flex-1 *:touch-manipulation"
      aria-label={"Spend rubies: you have #{@me.rubies}"}
      data-role="bar-rubies"
    >
      <.button
        phx-click="action"
        phx-value-action={encode(:end_round)}
        disabled={:end_round not in @actions}
        class="px-1!"
        data-role="rubies-skip"
      >
        Skip
      </.button>
      <.button
        :for={use <- @uses}
        phx-click="action"
        phx-value-action={encode({:rubies, use})}
        disabled={{:rubies, use} not in @actions}
        variant={:primary}
        class="flex-col gap-0! px-1! py-1! leading-tight"
        aria-label={action_label({:rubies, use}, @game, @me)}
        title={
          if {:rubies, use} in @actions,
            do: action_label({:rubies, use}, @game, @me),
            else: ruby_why(use, @me, @actions)
        }
        data-ruby={use}
      >
        <span class="flex items-center gap-0.5 text-base tabular-nums">
          {@price}<.piece_icon name={:ruby} class="size-4 text-ruby" />
          <.piece_icon name={ruby_icon(use)} class="ml-0.5 size-5" />
        </span>
        <span class="max-w-full truncate text-[11px] font-normal">
          {ruby_why(use, @me, @actions)}
        </span>
      </.button>
    </section>
    """
  end

  # The ruby uses in the bar: round 9 only buys VP; the test tube is on the reverse
  # pot side only.
  defp ruby_uses(%Game{round: 9}), do: [:vp]
  defp ruby_uses(%Game{rules: %{pot_side: :back}}), do: [:tube, :flask, :droplet]
  defp ruby_uses(_game), do: [:flask, :droplet]

  defp ruby_icon(:tube), do: :tube
  defp ruby_icon(:flask), do: :flask
  defp ruby_icon(:droplet), do: :pot
  defp ruby_icon(:vp), do: :vp

  # The small line on a ruby button: what it does, or why it cannot.
  defp ruby_why(use, me, actions) do
    cond do
      {:rubies, use} in actions -> ruby_what(use)
      use == :flask and me.flask -> "Flask full"
      use == :tube and me.tube >= TestTubes.last() -> "Tubes full"
      true -> "Too few rubies"
    end
  end

  defp ruby_what(:tube), do: "Test tube"
  defp ruby_what(:flask), do: "Refill flask"
  defp ruby_what(:droplet), do: "Droplet +1"
  defp ruby_what(:vp), do: "1 VP"

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

  # Round 28: under a Flea Market chip that cannot go up, the reason.
  defp blocked_reason(%Game{fortune_card: :p13} = game, [chip]) do
    case Quacks.Game.Fortune.flea_block(game, chip) do
      nil -> nil
      reason -> flea_reason(reason)
    end
  end

  defp blocked_reason(_game, _chips), do: nil

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
    picks = Enum.filter(assigns.actions, &(pick_chips(&1) != []))

    groups =
      case assigns.pool do
        nil ->
          title = &pick_title(&1, assigns.game.fortune_card)

          for t <- picks |> Enum.map(title) |> Enum.uniq() do
            tiles =
              picks
              |> Enum.filter(&(title.(&1) == t))
              |> Enum.sort_by(&chip_order/1)
              |> Enum.map(&{pick_chips(&1), &1})

            {t, tiles}
          end

        pool ->
          [
            {nil, for(chip <- pool, do: {[chip], pool_pick(picks, chip)})}
          ]
      end

    limit = white_limit(assigns.game, assigns.me)

    groups =
      for {title, tiles} <- groups, tiles != [] do
        {title,
         for(
           {chips, action} <- tiles,
           do: {chips, action, action && over_limit(action, assigns.me, limit)}
         )}
      end

    assigns = assign(assigns, groups: groups, limit: limit)

    ~H"""
    <div :for={{title, tiles} <- @groups} class="space-y-1" data-role="chip-picks">
      <p :if={title} class="text-sm font-semibold">{title}</p>
      <ul class="flex flex-wrap items-start gap-2">
        <li :for={{chips, action, over} <- tiles} class="flex flex-col items-center">
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
            title={blocked_reason(@game, chips) || "Not playable"}
          >
            <.chip :for={chip <- chips} chip={chip} data-role="offer-chip" />
          </span>
          <span
            :if={!action && blocked_reason(@game, chips)}
            class="mt-0.5 w-16 text-center text-tag leading-4 font-semibold text-ink-soft"
            data-role="pick-blocked"
          >
            {blocked_reason(@game, chips)}
          </span>
          <span
            :if={over}
            class={[
              "mt-0.5 rounded-full px-1.5 text-tag leading-4 font-bold",
              if(over == :explodes, do: "bg-ruby text-white", else: "bg-gold text-ink")
            ]}
            data-role="explode-warning"
          >
            {if over == :explodes, do: "explodes!", else: "over #{@limit}, safe"}
          </span>
          <span
            :if={(!over and @pool) && pick_verb(action)}
            class="mt-0.5 text-tag leading-4 font-semibold text-ink-soft"
            data-role="pick-verb"
          >
            {pick_verb(action)}
          </span>
          <%!-- Without a pool (a card's or a chip action's "take one"), the colour
               word under the chip, so a pick does not read as only its value. --%>
          <span
            :if={action && !@pool && !over}
            class="mt-0.5 text-tag leading-4 font-semibold text-ink-soft"
            data-role="pick-colour"
          >
            {chips |> List.last() |> elem(0)}
          </span>
        </li>
      </ul>
    </div>
    """
  end

  # Round 22: the Toadstool choice (red Set 2), one row per chip: the chip, then
  # Place, Keep and Return as three equal buttons (they stack under the chip on a
  # narrow phone). One line of help at the top.
  attr :actions, :list, required: true
  attr :pool, :list, required: true, doc: "the Toadstool chips that wait (`player.pending`)"
  attr :game, Game, required: true
  attr :me, Player, required: true

  defp red_rows(assigns) do
    ~H"""
    <div
      class="paper space-y-2 rounded-md border-l-4 border-ruby p-2 text-sm"
      aria-label="Toadstool choice"
      data-role="red-rows"
    >
      <p class="text-ink-soft">
        Each Toadstool chip: place it now, keep it beside the pot for later, or return it to the bag.
      </p>
      <ul class="space-y-2">
        <li
          :for={{chip, i} <- Enum.with_index(@pool)}
          id={"red-row-#{i}"}
          class="flex flex-col gap-2 rounded-md bg-parchment-deep/50 p-2 min-[26rem]:flex-row min-[26rem]:items-center"
          data-role="red-row"
        >
          <div class="flex shrink-0 items-center gap-2">
            <.chip chip={chip} size={:lg} data-role="red-chip" />
            <span class="font-hand text-lg font-bold min-[26rem]:hidden">
              Toadstool {elem(chip, 1)}
            </span>
          </div>
          <div class="grid flex-1 grid-cols-3 gap-2">
            <.button
              :for={{kind, label, hint} <- red_kinds()}
              :if={{:red, {kind, chip}} in @actions}
              type="button"
              phx-click="action"
              phx-value-action={encode({:red, {kind, chip}})}
              variant={if kind == :place, do: :primary, else: :secondary}
              autofocus={i == 0 and kind == :place}
              aria-label={action_label({:red, {kind, chip}}, @game, @me)}
              class="min-h-12 flex-col gap-0! px-1! leading-tight"
              data-role={"red-#{kind}"}
            >
              <span class="font-bold">{label}</span>
              <span class="text-tag font-normal opacity-80">{hint}</span>
            </.button>
          </div>
        </li>
      </ul>
    </div>
    """
  end

  defp red_kinds,
    do: [
      {:place, "Place", "after your last chip"},
      {:keep, "Keep", "for later"},
      {:return, "Return", "to the bag"}
    ]

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

  defp pool_pick(picks, chip), do: Enum.find(picks, &(pick_chips(&1) == [chip]))

  defp upgrade?({:chip, {:upgrade, _from, _to}}), do: true
  defp upgrade?(_action), do: false

  # The buttons of a choice that are not chips ("Return all", "Done", "3 rubies").
  defp text_actions(actions), do: Enum.filter(actions, &(pick_chips(&1) == []))

  @doc """
  Round 24: the chip actions of a ladder book with every rung, in order: Ghost's
  breath II (trade 1, 2 or 3 purple), Garden spider IV (pay 1 or 2 rubies) and
  Ghost's breath IV (the swaps of the tiers this pot does not reach). A rung the
  player can take is a button; one they cannot is greyed, `aria-disabled`, with
  its reason.
  """
  attr :rungs, :list, required: true, doc: "`ladder/2`: `%{action, label, reason}` maps"

  def ladder(assigns) do
    ~H"""
    <section
      :if={@rungs != []}
      class="flex flex-col gap-2"
      aria-label="Chip actions"
      data-role="ladder"
    >
      <%= for rung <- @rungs do %>
        <.button
          :if={is_nil(rung.reason)}
          phx-click="action"
          phx-value-action={encode(rung.action)}
          variant={:secondary}
          class="min-h-11"
          data-role="ladder-rung"
        >
          {rung.label}
        </.button>
        <div
          :if={rung.reason}
          class="flex min-h-11 cursor-not-allowed flex-col justify-center rounded-lg border border-dashed border-ink/30 px-3 py-1.5 text-sm text-ink/50"
          role="button"
          aria-disabled="true"
          data-role="ladder-rung-off"
        >
          <span class="font-semibold">{rung.label}</span>
          <span class="text-xs" data-role="ladder-reason">{rung.reason}</span>
        </div>
      <% end %>
    </section>
    """
  end

  # The rungs of this seat's open ladder choices (`me.chip_choices`, the engine's
  # data); the legal ones come from `legal_actions/2`, the rest from the book.
  defp ladder(%Player{} = me, actions, game) do
    purple = Enum.count(Player.pot_chips(me), &match?({:purple, _}, &1))
    label = &action_label(&1, game, me)
    Enum.flat_map(me.chip_choices, &rungs(&1, me, purple, actions, label))
  end

  defp ladder(_me, _actions, _game), do: []

  defp rungs({:purple_trade, _tier}, _me, purple, actions, label) do
    for t <- 1..3 do
      action = {:chip, {:purple_trade, t}}

      %{
        action: action,
        label: label.(action),
        reason: if(action not in actions, do: "needs #{t} purple, you have #{purple}")
      }
    end
  end

  # Garden spider IV: one ruby per green chip on the last two spaces.
  defp rungs({:ruby_move, greens}, me, _purple, actions, label) do
    for k <- 1..2 do
      action = {:chip, {:pay_ruby_move, k}}

      %{
        action: action,
        label: label.(action),
        reason: ruby_reason(action in actions, k, greens, me)
      }
    end
  end

  # Ghost's breath IV: the swaps are chip picks; the tiers above the pot's purple
  # chips show here, greyed.
  defp rungs({:upgrade, tier}, _me, purple, _actions, _label) do
    book = Books.get({:purple, 4})

    for {{_label, text}, t} <- Enum.with_index(book.tiers, 1), t > tier do
      %{
        action: nil,
        label: "Ghost's breath: swap #{text}",
        reason: "needs #{t} purple, you have #{purple}"
      }
    end
  end

  defp rungs(_choice, _me, _purple, _actions, _label), do: []

  defp ruby_reason(true = _legal, _k, _greens, _me), do: nil

  defp ruby_reason(_legal, k, greens, _me) when k > greens,
    do: "needs #{k} green chips on the last two spaces, you have #{greens}"

  defp ruby_reason(_legal, k, _greens, me),
    do: "needs #{k} #{if k == 1, do: "ruby", else: "rubies"}, you have #{me.rubies}"

  defp ladder_action?({:chip, {kind, _}}) when kind in [:purple_trade, :pay_ruby_move], do: true
  defp ladder_action?(_action), do: false

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
  # The shop selection stays while this seat's phase stays and the selection is still
  # a legal buy (round 28: another seat's buy must not untick ours); it empties when
  # this seat buys, leaves the shop or a new round starts.
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
      bar_choice: nil,
      all_actions: [],
      actions: [],
      skip_rubies: false,
      stop_slot: :stop,
      essence_pick: nil,
      reveal: nil
    )
  end

  defp put_game(socket, game) do
    was = pot_card?(socket.assigns)
    socket = mark_round_change(socket, game)
    seat = socket.assigns.seat
    me = if seat, do: game.players[seat]
    actions = if seat && not Game.over?(game), do: Game.legal_actions(game, seat), else: []
    phase = seat && Game.phase(game, seat)
    {decision, skip_rubies} = decide(actions, phase, me)

    socket
    |> assign(
      game: game,
      me: me,
      selected: kept_selection(socket.assigns, game, phase, actions),
      decision: decision,
      bar_choice: bar_choice(decision, actions),
      all_actions: actions,
      actions: if(decision || skip_rubies, do: [], else: Enum.reject(actions, &witch?/1)),
      skip_rubies: skip_rubies,
      stop_slot: stop_slot(game, me),
      essence_pick: essence_pick(me, socket.assigns[:essence_pick]),
      card_grown: socket.assigns[:card_grown] == true and same_round?(socket.assigns[:game], game)
    )
    |> open_reveal()
    |> card_vt(was)
  end

  defp kept_selection(
         %{game: %Game{} = old, selected: [_ | _] = selected} = assigns,
         game,
         phase,
         actions
       ) do
    same? =
      old.round == game.round and Game.phase(old, assigns.seat) == phase and
        old.players[assigns.seat] == game.players[assigns.seat]

    if same? and {:buy, selected} in actions, do: selected, else: []
  end

  defp kept_selection(_assigns, _game, _phase, _actions), do: []

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
      :open -> start_reveal(socket, key, Reveal.slides(game, seat))
      :result -> open_result(socket)
    end
  end

  # A spectator gets only the game's last slide.
  defp open_reveal(%{assigns: %{game: game, reveal: nil, result_closed: false}} = socket) do
    if Game.over?(game), do: open_result(socket), else: socket
  end

  defp open_reveal(socket), do: socket

  # Round 22: a page that opens on a finished game (a reload, a rejoin) shows the
  # game's last slide, also when the final scoring was not seen to its end.
  defp result_on_mount(%{assigns: %{game: %Game{phase: :over}}} = socket), do: open_result(socket)
  defp result_on_mount(socket), do: socket

  # Round 22: the game's last slide (the podium and its actions), straight away: after
  # a reload or rejoin of a finished game, and from "Show the result".
  defp open_result(%{assigns: %{game: game}} = socket) do
    case Reveal.slides(game, socket.assigns.seat) do
      [] ->
        socket

      slides ->
        socket
        |> start_reveal(Reveal.moment(game), slides)
        |> show_slide(length(slides) - 1)
    end
  end

  # What the overlay does with the game's moment `key`.
  defp reveal_step(_assigns, nil), do: :keep

  defp reveal_step(%{reveal: %{key: key}}, key), do: :keep

  # The final scoring seen: its last slide, once per page (until × closes it).
  defp reveal_step(%{reveal: nil, result_closed: false} = assigns, {:final, _} = key),
    do: if(seen_key?(assigns.seen, key), do: :result, else: :open)

  defp reveal_step(assigns, key), do: if(seen_key?(assigns.seen, key), do: :drop, else: :open)

  defp start_reveal(socket, _key, []), do: socket

  defp start_reveal(socket, key, slides) do
    # Round 27 (experimental): "On tiles" plays the results' scoring steps on the
    # player tiles (`QuacksWeb.TileReveal`); no step to play, the overlay as before.
    tiles =
      if socket.assigns.reveal_show == :tiles and match?({:results, _}, key),
        do: TileReveal.slides(slides),
        else: []

    socket
    |> assign(
      reveal: %{
        key: key,
        slides: if(tiles == [], do: slides, else: tiles),
        tiles: tiles != [],
        index: 0,
        tick: nil,
        settled: true,
        settle: nil,
        paused: false,
        held: match?({:card, _}, key)
      },
      card_grown: false
    )
    |> show_slide(0)
  end

  defp seen_key?(seen, {kind, round}), do: seen?(seen, kind, %{round: round})

  # Round 24: a new card first hovers over the pot with no sheet (`held`). Next (a
  # tap, Enter, Space, the Auto tick) then opens its result sheet when the card did
  # something to this seat, else it ends the reveal: the card shrinks into the corner,
  # or the card's choice opens (`open_waiting/1`).
  defp next_slide(%{assigns: %{reveal: %{held: true} = reveal} = assigns} = socket) do
    if assigns.decision != :fortune_choice and card_result?(reveal),
      do: socket |> assign(reveal: %{reveal | held: false}) |> show_slide(reveal.index),
      else: close_reveal(socket)
  end

  defp next_slide(%{assigns: %{reveal: %{index: index, slides: slides}}} = socket) do
    if index + 1 < length(slides),
      do: show_slide(socket, index + 1),
      else: close_reveal(socket)
  end

  # Show slide `index`; in Auto mode its timer starts (`Process.send_after/3`, only
  # on a live page). A new tick ref drops the pending one. The standings slide first
  # shows the old ranks; 300 ms later the settle tick sets the new ones (round 18).
  defp show_slide(%{assigns: %{reveal: reveal} = assigns} = socket, index) do
    slide = Enum.at(reveal.slides, index)
    # The game's last slide waits for Play again: no Auto timer there.
    final_last? = match?({:final, _}, reveal.key) and index == length(reveal.slides) - 1

    tick =
      if reveal_mode(reveal, assigns) == :auto and connected?(socket) and not final_last?,
        do: make_ref()

    settle = if slide.kind in [:standings, :tally] and connected?(socket), do: make_ref()

    if tick do
      ms = slide_ms(reveal, slide, assigns.reveal_speed)

      Process.send_after(self(), {:reveal_tick, tick}, ms)
    end

    if settle,
      do: Process.send_after(self(), {:reveal_settle, settle}, settle_ms(slide, assigns))

    assign(socket,
      reveal: %{reveal | index: index, tick: tick, settled: is_nil(settle), settle: settle}
    )
  end

  # Round 29: the final scoring plays in Auto mode by default (a tap pauses it);
  # reduced motion keeps Step.
  defp reveal_mode(%{key: {:final, _}, paused: false}, %{reduced: false}), do: :auto
  defp reveal_mode(%{key: {:final, _}}, _assigns), do: :step
  defp reveal_mode(_reveal, assigns), do: assigns.reveal_mode

  # The final tally settles once its parts have popped in (app.css `.tally-part`:
  # one every 0.35 beat, the 4th row's last at --i 11).
  defp settle_ms(%{kind: :tally, rows: rows}, assigns) do
    parts = rows |> Enum.map(&(&1.from_rank * 3 + length(&1.parts))) |> Enum.max(fn -> 0 end)
    max(@settle_ms, 500 + round(parts * 0.35 * Reveal.beat_ms(assigns.reveal_speed)))
  end

  defp settle_ms(_slide, _assigns), do: @settle_ms

  # Round 22: the new card hovers over the pot while its reveal shows, or while the
  # card's choice waits with no chips drawn (Safety Procedure and Flea Market draw
  # chips: there the pot matters, so the card stays in the dialog).
  defp pot_card?(%{reveal: %{key: {:card, _}}, game: %Game{fortune_card: card}}) when card != nil,
    do: true

  defp pot_card?(%{card_grown: true, game: %Game{fortune_card: card}}) when card != nil,
    do: true

  defp pot_card?(%{decision: :fortune_choice, me: %Player{pending: []}, game: game}),
    do: game.fortune_card != nil

  defp pot_card?(_assigns), do: false

  # The patch that takes the pot card away runs as a view transition of type `card`
  # (app.js `quacks:vt`): the big card shrinks into the corner card (app.css).
  defp card_vt(socket, true = _was) do
    if pot_card?(socket.assigns),
      do: socket,
      else: push_event(socket, "quacks:vt", %{type: "card"}, dispatch: :before)
  end

  defp card_vt(socket, _was), do: socket

  # The card's result: what it did to this seat (`Reveal`, the slide's `outcomes`).
  defp card_result?(%{slides: [%{outcomes: [_ | _]} | _]}), do: true
  defp card_result?(%{slides: [%{reveals: reveals} | _]}) when map_size(reveals) > 0, do: true
  defp card_result?(_reveal), do: false

  # Round 24: the big card over the pot is tappable while a new card waits for its
  # tap, or while the grown corner card shows.
  defp card_tap?(%{reveal: %{held: true}}), do: true
  defp card_tap?(%{card_grown: grown}), do: grown

  # The tap layer reads the card for screen readers (the big card is aria-hidden).
  defp card_tap_label(id) do
    card = Quacks.Rules.Fortune.card(id)
    "#{card.name}: #{card.text} Continue"
  end

  defp shrink_card(socket) do
    socket
    |> push_event("quacks:vt", %{type: "card"}, dispatch: :before)
    |> assign(card_grown: false)
  end

  # The end of the reveal: the moment counts as seen (`GameServer.ack/4`), the
  # pot's replay shows its end state, and what waited opens (app.js `quacks:open`).
  defp close_reveal(%{assigns: %{reveal: %{key: key}}} = socket) do
    was = pot_card?(socket.assigns)

    socket
    |> assign(reveal: nil, result_closed: match?({:final, _}, key))
    |> card_vt(was)
    |> mark_seen(key)
    |> auto_done()
    |> open_waiting()
  end

  defp mark_seen(%{assigns: %{seat: seat}} = socket, {kind, round}) when is_integer(seat) do
    GameServer.ack(socket.assigns.id, seat, kind, round)
    update(socket, :seen, &Map.put(&1, kind, round))
  end

  defp mark_seen(socket, _key), do: socket

  defp open_waiting(%{assigns: %{game: game, decision: decision} = assigns} = socket) do
    if decision && !assigns[:bar_choice] && not Game.over?(game),
      do: push_event(socket, "quacks:open", %{to: decision_dialog(decision, game)}),
      else: socket
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

  # Round 29: the choices that take the place of Stop and Draw in the bar (no sheet):
  # the explosion's, and the rubies step when no witch can be called there.
  defp bar_choice(:explosion_choice, _actions), do: :explosion_choice
  defp bar_choice(:rubies, actions), do: if(Enum.any?(actions, &witch?/1), do: nil, else: :rubies)
  defp bar_choice(_decision, _actions), do: nil

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

  defp same_round?(%Game{round: round}, %Game{round: round}), do: true
  defp same_round?(_old, _new), do: false

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

  # A slide's time in Auto mode; on the tiles a step is a few beats (round 27).
  defp slide_ms(%{tiles: true}, _slide, speed), do: TileReveal.duration(speed)
  defp slide_ms(_reveal, slide, speed), do: Reveal.duration(slide, Reveal.factor(speed))

  # Round 27 (experimental): the evaluation plays on the tiles (`TileReveal`).
  defp tiles_playing?(reveal), do: match?(%{tiles: true}, reveal)

  # `{vp, rubies, vp_before, rubies_before}` per seat: after this step and before it.
  defp tile_totals(game, %{slides: slides, index: index}) do
    now = TileReveal.totals(game, slides, index)
    before = TileReveal.totals(game, slides, index - 1)

    droplets = TileReveal.droplets(game, slides, index)

    Map.new(now, fn {s, {vp, rubies}} ->
      {vp0, rubies0} = before[s]
      {s, %{vp: vp, rubies: rubies, droplet: droplets[s], vp_from: vp0, rubies_from: rubies0}}
    end)
  end

  # The Results choice from the settings; none sent (the phone form): keep it.
  defp reveal_choice("tiles", _current), do: :tiles
  defp reveal_choice(nil, current), do: current
  defp reveal_choice(_show, _current), do: :overlay

  # The rat track follows the tiles' running VP while the steps play.
  defp tile_vps(game, reveal),
    do: Map.new(tile_totals(game, reveal), fn {s, totals} -> {s, totals.vp} end)

  # Auto mode: the shown slide's time (the overlay's timer bar), else nil.
  # The game's last slide (the podium) and a paused final tally have no timer.
  defp reveal_ms(%{key: {:final, _}, slides: slides, index: index}, _mode, _speed)
       when index == length(slides) - 1,
       do: nil

  defp reveal_ms(%{slides: slides, index: index}, :auto, speed),
    do: slides |> Enum.at(index) |> Reveal.duration(Reveal.factor(speed))

  defp reveal_ms(_reveal, _mode, _speed), do: nil

  # The last slide's button names what comes next.
  defp close_label(%{key: {:card, _}}, _decision, _skip), do: "Continue"
  defp close_label(_reveal, :shop, _skip), do: "To the shop"
  defp close_label(_reveal, :rubies, _skip), do: "Spend rubies"
  defp close_label(_reveal, :droplet_choice, _skip), do: "Move the droplet"
  # Round 29 (F1): round 9 has no "Done": the final tally follows by itself.
  defp close_label(%{key: {:results, 9}}, _decision, true), do: "Continue"
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
  # Round 29 (Q10): the card's choice opens after its reveal: "Continue".
  defp back_label(:fortune_choice, _game), do: "Continue"
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
