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
  `side`), then the witches; the bar at its foot plays the results' steps (round
  39). The card's dialog does not open there unless it holds a choice. From 80rem
  (desktop) the fortune teller tops that column (`fortune_panel/1`, it plays a
  reveal when a new card comes) and a column left of the pot holds the books in
  play (`books_in_play/1`; a book lights up on its replay beat) and the witches,
  each folded until a click opens it (`fold/1`, round 39). From 64 to 80rem (tablet) the fortune teller sits in full under the
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
  scoring at the end, one slide at a time, per browser (`@reveal`). Round 39: once
  the browser sends its settings the evaluation plays on the tiles on every
  screen; the overlay is only the default until then. Next, Skip,
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
  seat does now (`TileComponents.seat_state/2`), and a player who has finished sees
  who they wait for. A stopped player's Stop button becomes Resume.

  With The Herb Witches the page also shows the 3 witches (a sheet on phones, the
  right column from 64rem, the left column from 80rem) with a button to call one when the engine allows
  it. The overflow bowl shows under the pot once it has chips.

  With the reverse pot side (`pot_side: :back`) the test-tube rack shows under the
  pot, and each waiting droplet move opens the "Droplet" dialog (pot droplet or
  test tube). After the evaluation it waits for the round results, like the shop.
  The dialog says the move is free and names where it came from (e.g. the
  Hawkmoth); the rubies step comes after it and after the buy.

  Mandrake: the server answers "put the white chip back?" for a human seat at once
  (`GameServer.keep_white/2`); the white chip then hovers over the bag with a round
  undo button that keeps it in the pot, until the next action of any seat. The rat tails of the round show under
  the players row while the round brews.

  With The Alchemists every seat first picks a patient (a dialog with 3 cards).
  The flask strip runs above the pot: the patient badge (it opens the patient
  sheet) and the essence marker. A lower essence space is picked in a dialog with
  a stepper; Chicken eyes and Vampirism pick a chip; Ear worm draws with the Draw
  button. Next round, the patient's offers open as a decision under the drawn
  chip, Nervousness lays its chips out above the action bar and Forgetfulness
  returns a pot chip from its sheet.

  Actions travel to the browser as a URL-safe binary (`QuacksWeb.ActionCode`) so tuples like
  `{:buy, [{:green, 2}]}` survive the round trip without a parser per action shape.
  """
  use QuacksWeb, :live_view

  import QuacksWeb.ActionCode
  import QuacksWeb.BarComponents
  import QuacksWeb.ChipComponents
  import QuacksWeb.GameText
  import QuacksWeb.PanelComponents
  import QuacksWeb.PotComponents
  import QuacksWeb.TileComponents
  import QuacksWeb.TrackComponents
  import QuacksWeb.CardRevealComponents

  import QuacksWeb.SetupComponents

  import QuacksWeb.AlchemistsComponents
  import QuacksWeb.BugReportComponents
  import QuacksWeb.RevealComponents
  import QuacksWeb.TileRevealComponents
  import QuacksWeb.TipComponents
  import QuacksWeb.ScenarioComponents

  alias Quacks.{Game, GameServer, Player}
  alias Quacks.Game.Fortune
  alias Quacks.Rules.Books
  alias QuacksWeb.{BarComponents, Replay, Reveal, TileReveal, Tips}

  # The small choices in the bar (`BarComponents.pick_choices/0`).
  @pick_choices BarComponents.pick_choices()

  # The standings slide's first render shows the old ranks this long (round 18; the
  # tests set it long and send the tick themselves).
  @settle_ms Application.compile_env(:quacks, :reveal_settle_ms, 300)

  # A paid droplet move or flask refill shows on the pot this long before the round
  # ends by itself (round 32, `done_after/2`; 0 in the tests: at once).
  @show_move_ms Application.compile_env(:quacks, :show_move_ms, 800)

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
           card_toast: nil,
           reveal_mode: :step,
           reveal_speed: :normal,
           risk: :percent,
           reveal_show: :overlay,
           reduced: false,
           rubies_kept: nil,
           tips: nil
         )
         |> attach_hook(:tips, :handle_event, &tip_closer/3)
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
      # Round 35 (item 7): "Done" on a book's step moves on to the next book with a
      # choice of this seat; on the last one it ends the choices.
      {:ok, :chip_done} when socket.assigns.reveal != nil ->
        if tile_hold(socket.assigns) == :chip_choice and later_choices?(socket.assigns),
          do: {:noreply, show_slide(socket, socket.assigns.reveal.index + 1)},
          else: play(socket, seat, :chip_done)

      {:ok, action} ->
        play(socket, seat, action)

      {:error, :bad_action} ->
        {:noreply, put_flash(socket, :error, "That move could not be read.")}
    end
  end

  def handle_event("action", _params, socket),
    do: {:noreply, put_flash(socket, :error, "You are watching this game.")}

  # Round 36: a tap on a glowing pot chip with more than one choice (P4: a 1-chip
  # may become a 2- or a 4-chip) opens its choices in the bar; Back closes them.
  def handle_event("pot_pick", %{"action" => encoded}, socket) do
    pick =
      case decode(encoded) do
        {:ok, chip} -> pot_pick(socket.assigns.all_actions, chip)
        _bad -> nil
      end

    {:noreply, assign(socket, pot_pick: pick)}
  end

  def handle_event("pot_pick", _params, socket), do: {:noreply, assign(socket, pot_pick: nil)}

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
      when is_integer(seat) and kind in ["card", "results"] and is_integer(round) do
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

  # Round 35 (item 5): "Keep" in the results' rubies step; the shop's rubies step
  # after the buy is then skipped.
  def handle_event(
        "rubies_keep",
        _params,
        %{assigns: %{reveal: %{rubies: true} = reveal}} = socket
      ) do
    {:noreply,
     socket
     |> assign(rubies_kept: socket.assigns.game.round, reveal: %{reveal | rubies: false})
     |> next_slide()}
  end

  def handle_event("rubies_keep", _params, socket), do: {:noreply, socket}

  def handle_event(event, _params, socket)
      when event in ["reveal_next", "reveal_skip", "reveal_close"],
      do: {:noreply, socket}

  # The menu's reveal settings, from this browser (`RevealSettings` in app.js: on
  # mount with `reduced`, then on every change). Reduced motion: Step only.
  def handle_event("reveal_settings", params, socket) do
    reduced = Map.get(params, "reduced", socket.assigns.reduced) == true
    mode = if params["mode"] == "auto" and not reduced, do: :auto, else: :step
    speed = Enum.find(Reveal.speeds(), :normal, &(Atom.to_string(&1) == params["speed"]))

    # Round 39: every screen plays the results on the tiles and their stage (no
    # overlay over the pot). The overlay stays only until this first push.
    show = :tiles
    # Round 29: the risk shown beside the white meter (`quacks:risk` in this browser).
    risk =
      Enum.find(
        [:off, :percent, :chips],
        socket.assigns.risk,
        &(Atom.to_string(&1) == params["risk"])
      )

    # Round 38: the hints this browser has seen (`quacks:tips`), only in the push
    # on mount; the form's own changes leave them.
    tips = browser_tips(params["tips"], socket.assigns.tips)

    socket =
      assign(socket,
        reveal_mode: mode,
        reveal_speed: speed,
        reveal_show: show,
        risk: risk,
        reduced: reduced,
        tips: tips
      )

    case socket.assigns.reveal do
      # Round 27: the settings come after mount, so the results' reveal starts again
      # where the Results setting says (the overlay or the tiles).
      %{key: {:results, _} = key} = reveal when reveal.tiles != (show == :tiles) ->
        game = socket.assigns.game

        if TileReveal.evaluating?(game),
          do: {:noreply, assign(socket, reveal: nil)},
          else:
            {:noreply,
             socket |> assign(reveal: nil) |> start_reveal(key, Reveal.result_slides(game))}

      %{index: index} ->
        {:noreply, show_slide(socket, index)}

      # Round 35: on the tiles the results may begin now (the choices phase).
      nil ->
        {:noreply, if(socket.assigns.game, do: open_reveal(socket), else: socket)}
    end
  end

  # Round 38: the hint's main button ("Got it", "Next tip"). The fortune card's
  # hint takes the place of Continue, so it also goes on (`next_slide/1`); a hint
  # on a results step lets Auto go on again (`arm_tick/1`).
  def handle_event("tip_done", %{"key" => key}, socket) do
    case current_tip(socket.assigns) do
      %{key: ^key} -> {:noreply, socket |> see_tip(key) |> after_tip(key)}
      _tip -> {:noreply, socket}
    end
  end

  def handle_event("tip_done", _params, socket), do: {:noreply, socket}

  # "No more tips" on a hint, and the menu's Tips row (On, Off, Show again).
  def handle_event("tip_off", _params, socket),
    do: {:noreply, socket |> put_tips(off: true) |> arm_tick()}

  def handle_event("tips", %{"tips" => value}, socket),
    do: {:noreply, socket |> put_tips(off: value == "off") |> arm_tick()}

  def handle_event("tips_again", _params, socket),
    do: {:noreply, put_tips(socket, off: false, seen: MapSet.new())}

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

  def handle_info(:auto_done, socket), do: {:noreply, auto_done(socket, true)}

  def handle_info(:uncopied, socket), do: {:noreply, assign(socket, copied: false)}

  # Auto mode: the slide's time is up (a stale tick, from a slide left before, is
  # ignored).
  # Round 38: a hint on the card or a results step holds Auto until it closes.
  def handle_info({:reveal_tick, ref}, %{assigns: %{reveal: %{tick: ref} = reveal}} = socket) do
    if reveal_tip?(current_tip(socket.assigns)),
      do: {:noreply, assign(socket, reveal: %{reveal | tick: nil})},
      else: {:noreply, next_slide(socket)}
  end

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
        {:noreply, socket |> put_game(game) |> close_card_reveal(action) |> done_after(action)}

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
    # Round 38: the first-time hint for this moment (`QuacksWeb.Tips`), or nil.
    assigns = assign(assigns, :tip, placed_tip(assigns))

    ~H"""
    <Layouts.app flash={@flash} full style={seat_style(@colours)}>
      <.step_bar :if={@debug[:scenario]} debug={@debug} />
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
        data-tip={@tip && @tip.key}
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
            style={"grid-template-columns: repeat(#{2 * loop_columns(length(@game.seats))}, minmax(0, 1fr))"}
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
              start={loop_start(length(@game.seats), row, col)}
              updates={if results?(@game), do: Replay.updates(@game, seat), else: []}
              ticks={replaying?(@game, @seen) and not tiles_playing?(@reveal)}
              totals={tiles_playing?(@reveal) && tile_totals(@game, @reveal)[seat]}
              news={
                (@reveal_show == :tiles or @game.phase == :potions) &&
                  TileReveal.news(@game, seat, @reveal)
              }
              rolls={if @reveal_show == :tiles, do: tile_rolls(@game, seat, @reveal), else: []}
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

        <%!-- Desktop (80rem): a column left of the pot with the books in play and
             (round 39) the herb witches, each folded until a click opens it. So
             the context column has room for the evaluation. --%>
        <div
          id="left-column"
          class="hidden min-h-0 flex-col gap-2 overflow-y-auto pt-2 pb-3 pl-4 xl:flex"
          data-area="books"
        >
          <.books_in_play id="books-column" game={@game} beats={book_beats(@game, @seat, @seen)} />
          <.fold :if={@game.witches} id="witches-column" label="Herb witches">
            <:title>
              <.piece_icon name={:witch} class="size-4 self-center" /> Herb witches
              <span
                :if={(n = callable_witches(@game, @all_actions)) > 0}
                class="rounded-full bg-gold px-2 font-sans text-xs leading-5 font-bold text-ink"
                data-role="witches-callable"
              >
                {n} to call
              </span>
            </:title>
            <.witches_list game={@game} me={@me} seat={@seat} actions={@all_actions} />
          </.fold>
        </div>

        <div class="pot-column flex min-h-0 flex-col px-4 py-1 lg:px-6 lg:py-2" data-area="pot">
          <.flask_strip
            :if={@me && @me.patient}
            game={@game}
            seat={@seat}
            beat={replay_marks(@game, @seat, @reveal)[:essence]}
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
                beats={replay_marks(@game, @seat, @reveal)}
                effects={replay_effects(@game, @seat, @seen, @reveal)}
                droplet={tiles_playing?(@reveal) && @me && tile_totals(@game, @reveal)[@seat].droplet}
                fx_key={if tiles_playing?(@reveal), do: "s#{@reveal.index}-", else: ""}
                bagged={bagged?(assigns)}
                targets={pot_targets(assigns)}
              />
              <%!-- Round 31: the game's end lies over the pot: the score chart. --%>
              <QuacksWeb.FinalComponents.final_board
                :if={Game.over?(@game)}
                game={@game}
                names={@names}
                bots={@bots}
                seat={@seat}
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
                  if(@reveal || @card_grown || @decision == :fortune_choice,
                    do: "pot-card-reveal",
                    else: "lg:hidden"
                  )
                ]}
                aria-hidden="true"
                data-role="pot-card"
              >
                <%!-- Round 25: the grown corner card has no flip; the card
                     transition alone grows it (the shrink played backwards). --%>
                <.fortune_card id={@game.fortune_card} flip_id="pot-card-flip" flip={!@card_grown} />
                <%!-- Round 30: every player's chips under the grown card. Round 31:
                     also while the card's choice waits in the bar (Flea Market), and
                     after the new card's tap (`next_slide/1` grows it). --%>
                <%!-- Round 36: the everyone-card rows are in the results stage
                     (`card_stage/1`, over the bar), not under the card. --%>
                <p
                  :if={card_tap?(assigns)}
                  id={"card-caption-#{@game.round}-#{@card_grown}"}
                  class="card-caption"
                  data-role="card-caption"
                >
                  Tap to continue
                </p>
              </div>
              <p
                :if={@card_toast && @card_toast.round == @game.round && !pot_card?(assigns)}
                id={"card-toast-#{@card_toast.round}"}
                class="card-toast"
                role="status"
                data-role="card-toast"
              >
                {@card_toast.text}
              </p>
              <%!-- Round 30: the top right corner holds your ruby total (the
                   scoring's rubies fly to it) and, below it, the kept Toadstool
                   chips (red Set 2, round 22), small pills outside the round rim. --%>
              <div
                :if={@me}
                class="absolute top-0 right-0 flex flex-col items-end gap-1.5"
                data-role="pot-corner-right"
              >
                <.ruby_badge
                  rubies={ruby_total(@game, @me, @seat, @reveal)}
                  beats={stat_beats(@game, @seat, @seen, @reveal)}
                />
                <.aside :if={@me.aside != []} chips={@me.aside} />
              </div>
              <%!-- The overflow bowl hangs over the pot's lower rim. --%>
              <div
                :if={@game.players[@seat || 0].bowl != []}
                class="absolute inset-x-12 bottom-0 flex items-end justify-center gap-2"
                data-role="bowl-strip"
              >
                <.bowl chips={@game.players[@seat || 0].bowl} />
              </div>
              <.bag_button
                :if={@me}
                count={length(@me.bag)}
                class="absolute right-0 bottom-0"
                tap={match?(%{key: "bag"}, @tip) && JS.push("tip_done", value: %{key: "bag"})}
              />
              <%!-- Round 38: a hint while the bottom context area is busy (a
                   choice, the results) floats over the pot's lower band. --%>
              <.tip_card
                :if={@tip && @tip.place == :pot}
                tip={@tip}
                class="absolute! inset-x-1 bottom-1"
              />
              <%!-- Mandrake: the white chip that went back hovers over the bag, with
                   an undo button that keeps it in the pot (`keep_white`). --%>
              <div
                :if={white = keep_white?(@game, @seat, @bots) && returned_white(@game)}
                class="absolute right-1.5 bottom-14 flex flex-col items-center gap-1"
                data-role="mandrake-undo"
              >
                <button
                  id="keep-white"
                  type="button"
                  phx-click="keep_white"
                  class={[
                    "paper grid size-11 touch-manipulation place-items-center rounded-full shadow-lg",
                    "transition-transform duration-100 ease-out active:scale-90"
                  ]}
                  aria-label="Mandrake: the white chip went back in your bag. Keep it in the pot"
                  title="Keep the white chip"
                >
                  <.icon name="hero-arrow-uturn-left" class="size-5" />
                </button>
                <span class="mandrake-bob"><.chip chip={white} /></span>
              </div>
              <%!-- Round 36: Mandrake V peeked at one more chip (it moved the
                   chip on by its value and went back): that chip over the bag,
                   until your next draw. --%>
              <div
                :if={peek = @me && @game.phase == :potions && peeked(@game.log, @seat)}
                id={"peek-#{@game.round}-#{length(@me.drawn)}"}
                class="peek-rise pointer-events-none absolute right-1.5 bottom-14 flex flex-col items-center"
                role="status"
                aria-label={"Mandrake: peeked at #{chip_name(peek)}, back in the bag"}
                title={"Peeked at #{chip_name(peek)}, back in the bag"}
                data-role="peek-chip"
                data-chip={chip_name(peek)}
              >
                <span class="mandrake-bob"><.chip chip={peek} /></span>
                <.icon name="hero-arrow-down" class="size-4 text-parchment drop-shadow" />
              </div>
            </div>
          </div>
          <%!-- A landscape phone moves the tubes to the right column (app.css). --%>
          <div :if={@game.rules.pot_side == :back} class="shrink-0 pt-1" data-area="tubes">
            <.test_tubes
              id="tubes-main"
              tube={@game.players[@seat || 0].tube}
              class="mx-auto block h-auto w-full max-w-xs"
            />
          </div>
        </div>

        <%!-- The context area (64rem): what happens now. The fortune teller on top,
             the decision while one waits, then the witches (64-80rem). The bar at
             its foot plays the results' steps (round 39: on every screen). Below
             64rem it is `display: contents` and holds only the sheets. --%>
        <aside class="context-column" data-area="context" data-role="side-column">
          <.fortune_panel
            :if={@game.fortune_card}
            id={"fortune-panel-#{@game.round}"}
            card={@game.fortune_card}
            class="hidden shrink-0 lg:flex"
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
            pot
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
              <div class="sheet-head flex items-center gap-1">
                <h2 class="text-xl font-bold">{phase_name(@decision)}</h2>
                <.offer_books
                  id="offer-books"
                  game={@game}
                  offer={[@me.pending, @me.witch_offer, @all_actions]}
                />
              </div>
              <p
                :if={hint = bonus_hint(@me.essence_pending)}
                class="text-sm font-semibold"
                data-role="essence-bonus"
              >
                {hint}
              </p>
              <.witch_card :for={id <- witches_acting(@game, @all_actions)} id={id} />
              <.chip_picks actions={@all_actions} game={@game} me={@me} />
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
          <%!-- Round 36: Ghost's breath V's buys. Round 39: a panel in the context
               area, no sheet; its purse and Take are in the bar. --%>
          <.purple_buy
            :if={(buys = purple_buys(assigns)) != []}
            buys={buys}
            selected={@selected}
            game={@game}
            me={@me}
          />
          <%!-- Round 40: the crow skull's choice, from 64rem (the bar has it below). --%>
          <.crow_panel
            :if={@bar_choice == :blue_choice && !tiles_playing?(@reveal)}
            actions={@all_actions}
            game={@game}
            me={@me}
          />
          <%!-- From 80rem the witches are in the left column instead (round 39). --%>
          <.sheet
            :if={@game.witches}
            id="sheet-witches"
            label="Herb witches"
            class="sheet-pot sheet-left-xl"
            inline_lg
          >
            <%!-- The title row holds the × (it floats right), so it never squeezes the
                 first card (round 14). --%>
            <h2
              class="sheet-head min-h-8 font-hand text-2xl leading-8 font-bold lg:text-parchment"
              data-role="witches-title"
            >
              Herb witches
            </h2>
            <.witches_list
              game={@game}
              me={@me}
              seat={@seat}
              actions={@all_actions}
              class="clear-both pt-1"
            />
          </.sheet>
        </aside>

        <%!-- The bar: Stop and Draw, and what the brew asks for now. Phones and
             tablets: a fixed-height bar under the pot (app.css `.game-bar`), and
             the rare extras (`.game-tray`) float over the pot's lower band. From
             64rem it is the foot of the context column. --%>
        <footer class="game-bar" data-area="bar">
          <div class="game-tray">
            <%!-- Round 38: the first-time hint, over the pot's lower band. --%>
            <.tip_card :if={@tip && @tip.place == :bar} tip={@tip} class={tip_shift(@tip.key)} />
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
          </div>
          <%!-- The bonus die while the overlay plays the results (only until the
               browser's settings come, round 39). Round 33: in the info row over
               the step bar, no overlay over the test tubes. --%>
          <div
            :if={replaying?(@game, @seen) and die_step?(@reveal)}
            id="info-die"
            class="flex flex-col gap-1"
            data-role="info-row"
          >
            <.replay_die
              lines={replay_die_lines(@game, @seat)}
              class="flex min-h-9 bg-iron-dark/90 shadow-lg"
            />
          </div>
          <%!-- An empty rubies step (nothing to spend, no witch to call) is one tap:
               the update chips stay on the cards until then. --%>
          <%!-- Round 36: an everyone-card's results (Round 30 grown card, round
               35 choice card) in the results stage, over the bar. --%>
          <.card_stage
            :if={card_stage?(assigns)}
            id={"card-stage-#{@game.round}"}
            card={@game.fortune_card}
            reveals={Reveal.card_reveals(@game)}
            order={Game.turn_order(@game)}
            seat={@seat}
            names={@names}
            game={@game}
          />
          <%!-- Round 35: the results stage, over the step bar. --%>
          <.results_stage
            :if={
              tiles_playing?(@reveal) && tile_slide(@reveal) &&
                tile_hold(assigns) not in [:droplet_choice, :chip_choice]
            }
            rows={TileReveal.stage_rows(@game, tile_slide(@reveal), stage_choosing(@game, @reveal))}
            slide={tile_slide(@reveal)}
            index={@reveal.index}
            names={@names}
            seat={@seat}
            collapsed={tile_hold(assigns) not in [nil, :waiting]}
            note={hold_note(tile_hold(assigns))}
          />
          <%!-- Round 35: a decision on the step on show takes the step bar's place. --%>
          <.bar_choice
            :if={tile_hold(assigns) == :rubies}
            choice={:rubies}
            actions={@all_actions}
            game={@game}
            me={@me}
            seat={@seat}
            keep
          />
          <.bar_choice
            :if={tile_hold(assigns) == :chip_choice}
            choice={:chip_choice}
            actions={step_chip_actions(assigns) ++ [:chip_done]}
            game={@game}
            me={@me}
            seat={@seat}
            pot_pick={@pot_pick}
            selected={@selected}
          />
          <.bar_choice
            :if={tile_hold(assigns) == :droplet_choice}
            choice={:droplet_choice}
            actions={@all_actions}
            game={@game}
            me={@me}
            seat={@seat}
          />
          <%!-- Round 29: the results' steps on the tiles take the bar's place. --%>
          <.tile_stage
            :if={tiles_playing?(@reveal) && tile_hold(assigns) in [nil, :waiting]}
            waiting={tile_hold(assigns) == :waiting}
            reveal={@reveal}
            mode={@reveal_mode}
            close_label={close_label(@reveal, @decision, @skip_rubies)}
          />
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
            :if={
              @decision && !@bar_choice && !card_continue?(assigns) &&
                (!tiles_playing?(@reveal) or other_decision?(assigns))
            }
            variant={:primary}
            class="min-h-12 w-full text-base [body:has(dialog[open])_&]:invisible lg:[body:has(dialog[open])_&]:hidden"
            data-role="decision-button"
            phx-click={JS.dispatch("quacks:modal", to: decision_dialog(@decision, @game))}
          >
            {back_label(@decision, @game)}
          </.button>
          <%!-- Round 31: at the game's end, Play again / Lobby (and Share). --%>
          <QuacksWeb.FinalComponents.final_actions
            :if={Game.over?(@game)}
            game={@game}
            names={@names}
            share_url={url(~p"/g/#{@id}")}
          />
          <%!-- Round 29: one row, the white meter, then the reward and the risk as icons. --%>
          <%!-- Round 33: a choice with an info row takes this row's place. --%>
          <%!-- Round 40: the crow skull's info row takes it below 64rem. --%>
          <div
            :if={
              @seat && @game.phase == :potions && !info_choice?(@bar_choice) &&
                !tiles_playing?(@reveal)
            }
            class={["flex min-w-0 items-center gap-2", @bar_choice == :blue_choice && "max-lg:hidden"]}
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
          <%!-- Round 30: while the round's card waits over the pot, one Continue
               takes the place of Stop and Draw (hidden, like for a decision). It
               does what a tap on the card does (above the tap layer, `#card-tap`);
               Enter too (`hotkey`). --%>
          <%!-- Round 38: the card's first-time hint takes Continue's place. --%>
          <.button
            :if={card_continue?(assigns) and not match?(%{key: "card"}, @tip)}
            id="card-continue"
            variant={:primary}
            class="relative z-50 min-h-12 w-full text-base touch-manipulation"
            phx-click="card_tap"
            data-role="card-continue"
          >
            Continue
            <.kbd>Enter</.kbd>
          </.button>
          <.bar_choice
            :if={@bar_choice && not Game.over?(@game) && !tiles_playing?(@reveal)}
            choice={@bar_choice}
            actions={@all_actions}
            game={@game}
            me={@me}
            seat={@seat}
            pot_pick={@pot_pick}
            selected={@selected}
          />
          <%!-- Round 40: from 64rem the crow skull's choice is in the context
               column, so Stop and Draw (disabled) stay here. --%>
          <section
            :if={
              @seat && not Game.over?(@game) && not results?(@game) &&
                (!@bar_choice or @bar_choice == :blue_choice) && !tiles_playing?(@reveal)
            }
            class={[
              "action-bar *:min-h-12 *:touch-manipulation",
              @bar_choice == :blue_choice && "max-lg:hidden",
              card_continue?(assigns) && "hidden",
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
      <.sheet :if={@me && @me.patient} id="sheet-patient" label="Patient" class="sheet-pot">
        <.patient_card id={@me.patient} reached={if @me.essence > 0, do: @me.essence} />
        <p class="mt-2 text-sm font-semibold" data-role="patient-essence">
          Essence: {@me.essence}
        </p>
      </.sheet>
      <.sheet
        :if={forgets(@actions) != []}
        id="sheet-forget"
        label="Forgetfulness"
        class="sheet-pot"
      >
        <h2 class="sheet-head font-hand text-2xl font-bold">Forgetfulness</h2>
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
      <.sheet
        :if={@game.fortune_card}
        id="sheet-fortune"
        label="Fortune teller card"
        class="sheet-pot"
      >
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
        class="sheet-pot"
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
          <h2 class="sheet-head text-lg font-bold">Game {@id}</h2>
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
            risk={@risk}
            reduced={@reduced}
          />
          <.tips_settings :if={@seat} on={tips_on?(@tips)} />
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
        <h2 class="sheet-head mb-2 text-lg font-bold">Ingredient books</h2>
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
  @doc """
  The game page's assigns for `game` with no `GameServer` (the gallery's screens
  and scenario steps, `QuacksWeb.GalleryFrameLive`): what `mount/3` and
  `put_game/2` assign, from a table made of the options, so `render/1` draws the
  real page from a fixture.

  Options: `seat` (default 0), `names` (seat => name), `bots` (a list of seats),
  `seen` (the moments this seat has seen: `:all`, the default, opens no reveal; a
  map such as `%{recap: 1}` lets the next moment's reveal open), `step` (the
  results or recap step on show, on the tiles: a slide kind such as `:die`, or a
  book colour). A waiting decision opens (`quacks:open`) when no reveal plays.
  """
  @spec preview(Phoenix.LiveView.Socket.t(), Game.t(), keyword) :: Phoenix.LiveView.Socket.t()
  def preview(socket, %Game{} = game, opts \\ []) do
    seats = game.seats

    names =
      Keyword.get_lazy(opts, :names, fn -> Map.new(seats, &{&1, GameServer.default_name(&1)}) end)

    table = %{
      players: length(seats),
      names: names,
      colours: Map.new(seats, &{&1, &1}),
      bots: Map.new(Keyword.get(opts, :bots, []), &{&1, :balanced}),
      creator: 0,
      rejoinable: [],
      debug: nil,
      sets: game.sets,
      patients: nil,
      patient_picks: %{}
    }

    socket
    |> assign(
      id: "gallery",
      token: nil,
      seat: Keyword.get(opts, :seat, 0),
      seed: {0, 0, 0},
      copied: false,
      open_sheet: nil,
      seen: Keyword.get(opts, :seen, :all),
      reveal: nil,
      card_grown: false,
      card_toast: nil,
      reveal_mode: :step,
      reveal_speed: :normal,
      risk: :percent,
      reveal_show: :tiles,
      reduced: false,
      rubies_kept: nil,
      tips: nil
    )
    |> new_report()
    |> assign_table(table)
    |> put_game(game)
    |> preview_step(opts[:step])
    |> preview_open()
  end

  # As on the page, a waiting decision opens once no reveal plays (`close_reveal/1`).
  defp preview_open(%{assigns: %{reveal: nil}} = socket), do: open_waiting(socket)
  defp preview_open(socket), do: socket

  defp preview_step(%{assigns: %{reveal: %{tiles: true, slides: slides}}} = socket, step)
       when step != nil do
    case Enum.find_index(slides, &(&1.kind == step or &1[:book] == step)) do
      nil -> socket
      i -> show_slide(socket, i + 1)
    end
  end

  defp preview_step(socket, _step), do: socket

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
      pot_pick: nil,
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
    kept = socket.assigns[:rubies_kept] == game.round
    {decision, skip_rubies} = decide(actions, phase, me, kept)

    socket
    |> assign(
      game: game,
      me: me,
      selected: kept_selection(socket.assigns, game, phase, actions),
      decision: decision,
      bar_choice: bar_choice(decision, actions, me),
      all_actions: actions,
      actions: if(decision || skip_rubies, do: [], else: Enum.reject(actions, &witch?/1)),
      skip_rubies: skip_rubies,
      stop_slot: stop_slot(game, me),
      essence_pick: essence_pick(me, socket.assigns[:essence_pick]),
      pot_pick: pot_pick(actions, socket.assigns[:pot_pick]),
      card_grown:
        (socket.assigns[:card_grown] == true and same_round?(socket.assigns[:game], game)) or
          chose_card?(socket.assigns, decision, game)
    )
    |> open_reveal()
    |> resume_reveal()
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

    if same? and ({:buy, selected} in actions or {:chip, {:buy, selected}} in actions),
      do: selected,
      else: []
  end

  defp kept_selection(_assigns, _game, _phase, _actions), do: []

  # -- the reveal overlay (round 14) ----------------------------------------------------

  # A seat that has not seen the game's moment gets its slides (`Reveal.slides/2`),
  # from the first one: also after a reload. Taken once, so a bot's move does not
  # change what the overlay shows. A fortune choice shows its card in its own
  # dialog, so no overlay then. A spectator gets none.
  defp open_reveal(%{assigns: %{seat: seat, game: game} = assigns} = socket)
       when is_integer(seat) do
    key = reveal_key(game, assigns)

    case reveal_step(assigns, key) do
      :keep -> refresh_tiles(socket)
      :drop -> assign(socket, reveal: nil)
      :open -> start_reveal(socket, key, reveal_slides(game, seat, key))
    end
  end

  defp open_reveal(socket), do: socket

  # Round 35 (item 7): on the tiles the results begin with the chip actions'
  # choices (each choice waits on its book's step); the overlay waits for the shop.
  # Round 37 (item 4): at a round's start the last round's recap (the shop, then
  # "Round scored") plays first, before the new card.
  defp reveal_key(game, %{reveal_show: :tiles} = assigns) do
    cond do
      TileReveal.evaluating?(game) -> {:results, game.round}
      recap_due?(game, assigns) -> {:recap, game.round - 1}
      true -> Reveal.moment(game)
    end
  end

  defp reveal_key(game, _assigns), do: Reveal.moment(game)

  defp reveal_slides(game, _seat, {:results, _}), do: Reveal.result_slides(game)
  defp reveal_slides(game, _seat, {:recap, _}), do: Reveal.recap_slides(game)
  defp reveal_slides(game, seat, _key), do: Reveal.slides(game, seat)

  # Round 35: while the steps play on the tiles they follow the game (a choice
  # made, the shop opened); the step on show stays on show.
  defp refresh_tiles(
         %{assigns: %{reveal: %{tiles: true, key: {:results, _}} = reveal, game: game}} = socket
       ) do
    case TileReveal.live(game, Reveal.result_slides(game)) do
      new when new in [[], reveal.slides] ->
        socket

      new ->
        shown = Enum.at(reveal.slides, reveal.index - 1)
        at = Enum.find_index(new, &(step_key(&1) == step_key(shown)))
        index = if at, do: at + 1, else: min(reveal.index, length(new))
        assign(socket, reveal: %{reveal | slides: new, index: max(index, 1)})
    end
  end

  defp refresh_tiles(socket), do: socket

  defp step_key(nil), do: nil
  defp step_key(slide), do: {slide.kind, slide[:book]}

  # What the overlay does with the game's moment `key`.
  defp reveal_step(_assigns, nil), do: :keep

  defp reveal_step(%{reveal: %{key: key}}, key), do: :keep

  defp reveal_step(assigns, key), do: if(seen_key?(assigns.seen, key), do: :drop, else: :open)

  defp start_reveal(socket, _key, []), do: socket

  defp start_reveal(socket, key, slides) do
    # Round 27 (experimental): "On tiles" plays the results' scoring steps on the
    # player tiles (`QuacksWeb.TileReveal`); no step to play, the overlay as before.
    tiles =
      case key do
        {:results, _} when socket.assigns.reveal_show == :tiles ->
          TileReveal.live(socket.assigns.game, slides)

        {:recap, _} ->
          slides

        _key ->
          []
      end

    # Nothing to play yet while the evaluation asks its choices: wait.
    if tiles == [] and TileReveal.evaluating?(socket.assigns.game),
      do: socket,
      else: begin_reveal(socket, key, slides, tiles)
  end

  defp begin_reveal(socket, key, slides, tiles) do
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
        held: match?({:card, _}, key),
        rubies: false
      },
      card_grown: false
    )
    |> show_slide(if(tiles == [], do: 0, else: 1))
  end

  defp seen_key?(seen, {kind, round}), do: seen?(seen, kind, %{round: round})

  # Round 24: a new card first hovers over the pot with no sheet (`held`). Next (a
  # tap, Enter, Space, the Auto tick) ends the reveal. Round 31: no result sheet. A
  # card that drew chips for everyone stays over the pot, grown, with every player's
  # row (a tap shrinks it); else it shrinks into the corner, and a short toast says
  # what it did to this seat (`card_toast/2`).
  defp next_slide(%{assigns: %{reveal: %{held: true} = reveal} = assigns} = socket) do
    cond do
      assigns.decision == :fortune_choice -> close_reveal(socket)
      card_rows?(reveal) -> socket |> assign(card_grown: true) |> close_reveal()
      true -> socket |> card_toast(reveal) |> close_reveal()
    end
  end

  # Round 35: on the tiles the step on show is `index - 1` (the results stage and
  # the bar name it); the first step shows at once (index 1). On the last step
  # ("Round scored") Next closes.
  # A decision on the step on show holds it (`tile_hold/1`). Round 35 (item 5):
  # this seat spends its rubies (`reveal.rubies`), when a ruby buys something.
  # Round 37 (item 4): after the last step of the results (the scoring space),
  # since "Round scored" comes after the shop now.
  defp next_slide(
         %{assigns: %{reveal: %{tiles: true, index: index, slides: slides} = reveal}} = socket
       ) do
    cond do
      tile_hold(socket.assigns) != nil ->
        assign(socket, reveal: %{reveal | tick: nil})

      index >= length(slides) and match?({:results, _}, reveal.key) and
          ruby_due?(socket.assigns) ->
        assign(socket, reveal: %{reveal | rubies: true, tick: nil})

      index >= length(slides) ->
        close_reveal(socket)

      true ->
        show_slide(socket, index + 1)
    end
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

    tick =
      if reveal_mode(reveal, assigns) == :auto and connected?(socket),
        do: make_ref()

    settle = if match?(%{kind: :standings}, slide) and connected?(socket), do: make_ref()

    if tick do
      ms = slide_ms(%{reveal | index: index}, slide, assigns.reveal_speed)

      Process.send_after(self(), {:reveal_tick, tick}, ms)
    end

    if settle,
      do: Process.send_after(self(), {:reveal_settle, settle}, @settle_ms)

    assign(socket,
      reveal: %{reveal | index: index, tick: tick, settled: is_nil(settle), settle: settle}
    )
  end

  defp reveal_mode(_reveal, assigns), do: assigns.reveal_mode

  # Round 22: the new card hovers over the pot while its reveal shows, or while the
  # card's choice waits with no chips drawn (Safety Procedure and Flea Market draw
  # chips: there the pot matters, so the card stays in the dialog).
  # Round 37: not while the last round's recap plays (its panel is on show).
  defp pot_card?(%{reveal: %{key: {:recap, _}}}), do: false

  defp pot_card?(%{reveal: %{key: {:card, _}}, game: %Game{fortune_card: card}}) when card != nil,
    do: true

  defp pot_card?(%{card_grown: true, game: %Game{fortune_card: card}}) when card != nil,
    do: true

  defp pot_card?(%{decision: :fortune_choice, game: game}), do: game.fortune_card != nil

  defp pot_card?(_assigns), do: false

  # The patch that takes the pot card away runs as a view transition of type `card`
  # (app.js `quacks:vt`): the big card shrinks into the corner card (app.css).
  defp card_vt(socket, true = _was) do
    if pot_card?(socket.assigns),
      do: socket,
      else: push_event(socket, "quacks:vt", %{type: "card"}, dispatch: :before)
  end

  defp card_vt(socket, _was), do: socket

  # Round 30: the cards that drew chips for every player (`Fortune.reveals/1`).
  defp card_rows?(%{slides: [%{reveals: reveals} | _]}), do: map_size(reveals) > 0
  defp card_rows?(_reveal), do: false

  # Round 31: one line for what the card did to this seat (`Reveal`, the slide's
  # `outcomes`), e.g. "Drop It: droplet +1". Nothing for a card that did nothing.
  defp card_toast(socket, %{key: {:card, round}, slides: [%{outcomes: [_ | _]} = slide | _]}) do
    name = Quacks.Rules.Fortune.card(slide.card).name
    did = Enum.map_join(slide.outcomes, ", ", &card_outcome(&1, slide.card))
    assign(socket, card_toast: %{round: round, text: "#{name}: #{did}"})
  end

  defp card_toast(socket, _reveal), do: socket

  # Round 24: the big card over the pot is tappable while a new card waits for its
  # tap, or while the grown corner card shows.
  # Round 31: not while the card's choice waits in the bar (its buttons go on).
  defp card_tap?(%{bar_choice: :fortune_choice}), do: false
  defp card_tap?(%{reveal: %{held: true}}), do: true
  defp card_tap?(%{card_grown: grown}), do: grown

  # Round 30: the contextual button area shows Continue while the card waits.
  # A choice in the bar (the explosion's) keeps its place.
  defp card_continue?(%{seat: seat, bar_choice: nil, game: %Game{fortune_card: card}} = assigns)
       when is_integer(seat) and card != nil,
       do: card_tap?(assigns)

  defp card_continue?(_assigns), do: false

  # -- first-time hints (round 38, `QuacksWeb.Tips`) -----------------------------------

  # The hint for this page now: only for a person's seat, once this browser sent
  # its seen hints (`RevealSettings`), and while the tips are on.
  defp current_tip(%{tips: %{off: false, seen: seen}, seat: seat, game: %Game{}} = assigns)
       when is_integer(seat) do
    if Map.has_key?(assigns.bots, seat), do: nil, else: Tips.pick(tip_moment(assigns), seen)
  end

  defp current_tip(_assigns), do: nil

  # A choice with the card's rows over the bar: the hint goes over the pot.
  defp placed_tip(assigns) do
    case current_tip(assigns) do
      %{key: "choice"} = tip -> if card_stage?(assigns), do: %{tip | place: :pot}, else: tip
      tip -> tip
    end
  end

  # The moment the page shows now (see `QuacksWeb.Tips`). An overlay over the page
  # (the reveal overlay) has none: a hint would sit under it; nor has the grown
  # card over the pot (its Continue goes first).
  defp tip_moment(%{game: game, reveal: reveal} = assigns) do
    cond do
      Game.over?(game) -> %{phase: :none}
      match?(%{key: {:card, _}, held: true}, reveal) -> card_moment(assigns)
      tiles_playing?(reveal) -> tile_moment(assigns)
      reveal != nil or card_continue?(assigns) -> %{phase: :none}
      true -> play_moment(assigns)
    end
  end

  # Nothing over the page: a choice in the bar, the shop, or the brew.
  defp play_moment(%{game: game} = assigns) do
    cond do
      assigns.bar_choice != nil -> %{phase: :choice}
      assigns.decision == :shop -> %{phase: :shop}
      game.phase == :potions and :draw in assigns.actions -> brew_moment(assigns)
      true -> %{phase: :none}
    end
  end

  defp card_moment(assigns),
    do: if(card_continue?(assigns), do: %{phase: :card}, else: %{phase: :none})

  # On the tiles: the first step of the results, or "Round scored" with the score
  # track at the top. A choice on the step on show is a choice.
  defp tile_moment(%{reveal: reveal, game: game} = assigns) do
    hold = tile_hold(assigns)
    track? = game.rules.rats and length(game.seats) > 1

    cond do
      hold in [:chip_choice, :droplet_choice, :rubies] ->
        %{phase: :choice}

      hold != nil ->
        %{phase: :none}

      match?({:results, _}, reveal.key) and reveal.index == 1 ->
        %{phase: :scoring, auto: assigns.reveal_mode == :auto}

      track? and match?(%{kind: :standings}, tile_slide(reveal)) ->
        %{phase: :scored}

      true ->
        %{phase: :none}
    end
  end

  defp brew_moment(%{game: game, seat: seat, me: me}) do
    %{
      phase: :brew,
      white: Game.white_sum(game, seat),
      rats: me.rat_stone,
      drawn: length(me.drawn)
    }
  end

  # A hint in the bar's band keeps its targets in view: the card's hint stands
  # where Continue was (it hides), the bag's hint goes down over the white meter
  # (the bag is above it), the risk hint leaves the flask free on the left.
  defp tip_shift("card"), do: "-mb-14"
  defp tip_shift("bag"), do: "-mb-12"
  defp tip_shift("risk"), do: "ml-[4.5rem]"
  defp tip_shift(_key), do: nil

  # The hints that hold the card or a results step (Auto waits for them).
  defp reveal_tip?(%{key: key}), do: key in ["card", "scoring", "scored"]
  defp reveal_tip?(_tip), do: false

  # Round 38: what else closes the hint on show (it then counts as seen): any
  # move (Draw too) or pick, a tap on the card or the results' Next and Skip, their
  # keys, and a tap on a player tile for the players' hint. A lifecycle hook, so
  # every event handler stays as it was.
  defp tip_closer(event, _params, socket)
       when event in ~w(action card_tap reveal_next reveal_skip reveal_close rubies_keep
                        pot_pick essence_pick keep_white select),
       do: {:cont, see_current_tip(socket, & &1)}

  defp tip_closer("hotkey", %{"key" => key}, socket) when key in ["d", "s", "Enter", " "],
    do: {:cont, see_current_tip(socket, & &1)}

  defp tip_closer("open_player", _params, socket),
    do: {:cont, see_current_tip(socket, &(&1 == "players"))}

  defp tip_closer(_event, _params, socket), do: {:cont, socket}

  defp see_current_tip(socket, closes?) do
    case current_tip(socket.assigns) do
      %{key: key} -> if closes?.(key), do: see_tip(socket, key), else: socket
      nil -> socket
    end
  end

  defp see_tip(socket, key),
    do: put_tips(socket, seen: MapSet.put(socket.assigns.tips.seen, key))

  # The tips change: keep them, and write them back to this browser (app.js).
  defp put_tips(socket, changes) do
    tips = Map.merge(socket.assigns.tips || Tips.from_browser(nil), Map.new(changes))

    socket
    |> assign(tips: tips)
    |> push_event("quacks:tips", Tips.to_browser(tips))
  end

  defp browser_tips(stored, _tips) when is_map(stored), do: Tips.from_browser(stored)
  defp browser_tips(_stored, tips), do: tips

  defp tips_on?(%{off: true}), do: false
  defp tips_on?(_tips), do: true

  defp after_tip(%{assigns: %{reveal: %{held: true}}} = socket, "card"), do: next_slide(socket)
  defp after_tip(socket, _key), do: arm_tick(socket)

  # Auto mode: the step on show starts its timer again after a hint held it.
  defp arm_tick(%{assigns: %{reveal: %{tick: nil, index: index} = reveal} = assigns} = socket) do
    if reveal_mode(reveal, assigns) == :auto and tile_hold(assigns) == nil and
         connected?(socket) do
      tick = make_ref()
      ms = slide_ms(reveal, Enum.at(reveal.slides, index), assigns.reveal_speed)
      Process.send_after(self(), {:reveal_tick, tick}, ms)
      assign(socket, reveal: %{reveal | tick: tick})
    else
      socket
    end
  end

  defp arm_tick(socket), do: socket

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
    |> assign(reveal: nil)
    |> card_vt(was)
    |> mark_seen(key)
    |> auto_done()
    |> after_recap(key)
  end

  # Round 37: the recap ends where the new round's card begins.
  defp after_recap(socket, {:recap, _}), do: open_reveal(socket)
  defp after_recap(socket, _key), do: open_waiting(socket)

  # Round 37 (item 4): the last round's recap is due at the round's start (this
  # seat has not drawn yet) until this seat has seen it. Not in round 1, the shop
  # or after the game.
  defp recap_due?(%Game{round: round, phase: phase} = game, %{seat: seat, seen: seen})
       when is_integer(seat) and round > 1 and phase not in [:shopping, :over] do
    Game.player(game, seat).drawn == [] and not seen?(seen, :recap, %{round: round - 1})
  end

  defp recap_due?(_game, _assigns), do: false

  # Round 31: the card's choice is made in the bar while the new card still hovers
  # (its reveal held): the choice ends the reveal, the card goes to the corner.
  defp close_card_reveal(
         %{assigns: %{reveal: %{key: {:card, _}, held: true}}} = socket,
         {:fortune, _}
       ),
       do: close_reveal(socket)

  defp close_card_reveal(socket, _action), do: socket

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
  # Round 35: rubies kept in the results' rubies step (`kept`) skip the shop's
  # rubies step after the buy, unless a witch can be called there.
  defp decide(actions, phase, me, kept) do
    step? = if kept, do: &witch?/1, else: &ruby_step_action?/1

    case decision(actions, phase, me) do
      :rubies ->
        if Enum.any?(actions, step?), do: {:rubies, false}, else: {nil, true}

      decision ->
        {decision, false}
    end
  end

  # Round 29: the choices that take the place of Stop and Draw in the bar (no sheet):
  # the explosion's, and the rubies step when no witch can be called there.
  # Round 37: the gold witch G4 stays in the bar (her own button) while a ruby is
  # left to spend at 1; any other witch call opens the sheet.
  defp bar_choice(:rubies, actions, %Player{rubies: rubies}) do
    bar? = fn action -> action == {:witch, :gold} and rubies >= 1 end
    if Enum.any?(actions, &(witch?(&1) and not bar?.(&1))), do: nil, else: :rubies
  end

  defp bar_choice(decision, actions, _me), do: bar_choice(decision, actions)

  defp bar_choice(:explosion_choice, _actions), do: :explosion_choice
  # Round 31: the card's choice too (no sheet; the card stays over the pot).
  defp bar_choice(:fortune_choice, _actions), do: :fortune_choice
  # Round 33: the chip actions and the droplet's free move too, with an info row.
  defp bar_choice(:chip_choice, _actions), do: :chip_choice
  defp bar_choice(:droplet_choice, _actions), do: :droplet_choice
  # Round 36: Chicken eyes' swap is a tap on the pot chip (the sheet covered the pot).
  defp bar_choice(:essence_bonus, actions),
    do: if(Enum.any?(actions, &match?({:essence, {:swap, _}}, &1)), do: :essence_bonus)

  defp bar_choice(choice, _actions) when choice in @pick_choices, do: choice
  defp bar_choice(_decision, _actions), do: nil

  # Round 33: the bar choices with an info row (it takes the white track's row).
  defp info_choice?(:blue_choice), do: false

  defp info_choice?(choice),
    do: choice in [:chip_choice, :droplet_choice, :essence_bonus | @pick_choices]

  defp stop_slot(game, %Player{phase: :stopped}), do: if(stir?(game), do: :stop, else: :resume)
  defp stop_slot(_game, _me), do: :stop

  # Round 31: round 9's "2 rubies → 1 VP" is no step: whatever the seat keeps
  # converts by itself at its "Done" (`Game` `final_conversion`), so the step only
  # shows when a ruby buys something else (rounds 1 to 8: droplet, flask, tube).
  defp ruby_step_action?({:rubies, :vp}), do: false
  defp ruby_step_action?({:rubies, _}), do: true
  defp ruby_step_action?(action), do: witch?(action)

  # The patch that moves on to a new round runs as a view transition (app.js,
  # `quacks:vt`; app.css moves only the round counter). The event goes out before
  # the patch.
  defp mark_round_change(%{assigns: %{game: %Game{round: old}}} = socket, %Game{round: new})
       when new > old,
       do: push_event(socket, "quacks:vt", %{}, dispatch: :before)

  defp mark_round_change(socket, _game), do: socket

  # Round 35: this seat just made the choice of a card that offers everyone one:
  # the card grows over the pot with what everyone took (`Fortune.reveals/1`),
  # live while the others still choose; a tap or Continue shrinks it.
  # Round 37 (item 10): Flea Market too, so the trade shows before the round goes on.
  defp chose_card?(%{decision: :fortune_choice, game: old}, decision, game)
       when decision != :fortune_choice,
       do:
         same_round?(old, game) and
           (Fortune.choice_card?(game.fortune_card) or game.fortune_card == :p13)

  defp chose_card?(_assigns, _decision, _game), do: false

  defp same_round?(%Game{round: round}, %Game{round: round}), do: true
  defp same_round?(_old, _new), do: false

  # The stepper keeps its space while the essence choice is open; it starts at the reach.
  defp essence_pick(%{essence_pending: {:space, reach}}, pick) when pick in 0..reach//1,
    do: pick

  defp essence_pick(%{essence_pending: {:space, reach}}, _pick), do: reach
  defp essence_pick(_me, _pick), do: nil

  # The dialog that holds this seat's decision (the fortune choice is in the card's).
  defp decision_dialog(decision, _game), do: "#decision-#{decision}"

  # This seat closed the card (`:card`) or the round results (`:results`) of this round.
  # A spectator has seen them all: no card or results open on top of each other.
  defp seen?(:all, _kind, _game), do: true
  defp seen?(seen, kind, game), do: seen[kind] == game.round

  defp seen(_table, nil), do: :all
  defp seen(table, seat), do: Map.get(table.seen, seat, %{})

  # The round results show from the shop until the round ends (round 9 has no shop).
  defp results?(game), do: game.phase == :shopping

  # Round 35: the round went to the shop (the results closed, this seat shops or is
  # ready): the chips leave the pot for the bag.
  defp bagged?(%{game: game, reveal: nil, me: %{phase: phase}, decision: decision} = assigns)
       when phase in [:shop, :ready] and decision in [nil, :shop, :rubies],
       do: results?(game) and not replaying?(game, assigns.seen)

  defp bagged?(_assigns), do: false

  # The update chips of the round still play (this seat has not seen them).
  defp replaying?(game, seen), do: results?(game) and not seen?(seen, :results, game)

  # A slide's time in Auto mode; on the tiles a step is a few beats (round 27).
  # Round 35: the step on show is `index - 1` (`show_slide/2` gets `index`); the die
  # step waits for its dice to roll.
  defp slide_ms(%{tiles: true, slides: slides, index: index}, _slide, speed),
    do: TileReveal.duration(speed, Enum.at(slides, index - 1))

  defp slide_ms(_reveal, slide, speed), do: Reveal.duration(slide, Reveal.factor(speed))

  # Round 27 (experimental): the evaluation plays on the tiles (`TileReveal`).
  defp tiles_playing?(reveal), do: match?(%{tiles: true}, reveal)

  # Round 35: the decision that holds the step on show, or nil: the rubies step
  # before "Round scored" (item 5).
  # Item 7: a chip actions' choice on its book's step, a free droplet move on the
  # step that won it; `:waiting` while the next step waits for other players.
  defp tile_hold(%{reveal: %{tiles: true, rubies: true}}), do: :rubies

  defp tile_hold(%{reveal: %{tiles: true} = reveal} = assigns) do
    cond do
      assigns.decision == :droplet_choice and droplet_due?(assigns) -> :droplet_choice
      assigns.decision == :chip_choice and step_chip_actions(assigns) != [] -> :chip_choice
      TileReveal.evaluating?(assigns.game) and reveal.index >= length(reveal.slides) -> :waiting
      true -> nil
    end
  end

  defp tile_hold(_assigns), do: nil

  # This seat's chip actions for the book on show.
  defp step_chip_actions(%{reveal: reveal, all_actions: actions}) do
    case tile_slide(reveal) do
      %{kind: :book, book: colour} ->
        Enum.filter(actions, &(TileReveal.choice_colour(&1) == colour))

      _slide ->
        []
    end
  end

  # A chip actions' choice of this seat waits on a step after the one on show.
  defp later_choices?(%{reveal: %{slides: slides, index: index}, all_actions: actions}) do
    colours = actions |> Enum.map(&TileReveal.choice_colour/1) |> Enum.reject(&is_nil/1)

    slides
    |> Enum.drop(index)
    |> Enum.any?(fn slide -> slide.kind == :book and slide[:book] in colours end)
  end

  # A free droplet move is due on the step on show: this seat has more moves
  # waiting than the steps still to come bring.
  defp droplet_due?(%{reveal: %{slides: slides, index: index}, game: game, seat: seat}) do
    later = slides |> Enum.drop(index) |> TileReveal.moves_in(seat)
    Game.player(game, seat).droplet_moves > later
  end

  # This seat may spend rubies before "Round scored": a ruby buys something now
  # (not round 9: its rubies turn into VP by themselves) and it did not keep them.
  defp ruby_due?(%{seat: seat, game: %Game{phase: :shopping, round: round}} = assigns)
       when is_integer(seat) and round < 9 do
    assigns.rubies_kept != round and
      (Enum.any?(assigns.all_actions, &match?({:rubies, use} when use != :vp, &1)) or
         (assigns.me.rubies >= 1 and g4_call?(assigns.game, assigns.all_actions)))
  end

  defp ruby_due?(_assigns), do: false

  # Round 35: the next step waits while this seat has a decision the steps do not
  # ask (a gold witch): its button shows under the step bar.
  defp other_decision?(assigns),
    do:
      tile_hold(assigns) == :waiting and
        assigns.decision not in [nil, :chip_choice, :droplet_choice]

  # The seats that still choose in the book on show (their row says so).
  defp stage_choosing(game, reveal) do
    case tile_slide(reveal) do
      %{kind: :book, book: colour} -> TileReveal.choosing(game, colour)
      _slide -> []
    end
  end

  # The results stage's one line while a decision holds the step.
  defp hold_note(:rubies), do: {"Spend rubies", "before the round is scored"}
  defp hold_note(_hold), do: nil

  # After a game update while the steps play on the tiles: a rubies step with
  # nothing left to buy moves on to "Round scored"; in Auto a step whose hold
  # ended gets its timer again.
  defp resume_reveal(%{assigns: %{reveal: %{tiles: true, rubies: true} = reveal}} = socket) do
    if ruby_due?(socket.assigns),
      do: socket,
      else:
        socket
        |> assign(rubies_kept: socket.assigns.game.round, reveal: %{reveal | rubies: false})
        |> next_slide()
  end

  defp resume_reveal(%{assigns: %{reveal: %{tiles: true}}} = socket),
    do: socket |> end_choices() |> rearm()

  defp resume_reveal(socket), do: socket

  defp rearm(%{assigns: %{reveal: %{tiles: true, tick: nil, index: index}} = assigns} = socket) do
    if reveal_mode(assigns.reveal, assigns) == :auto and tile_hold(assigns) == nil,
      do: show_slide(socket, index),
      else: socket
  end

  defp rearm(socket), do: socket

  # Item 7: a choice left only in a book step already passed ("Done" there) ends
  # the seat's choices once no later step holds one.
  defp end_choices(%{assigns: %{decision: :chip_choice, seat: seat} = assigns} = socket)
       when is_integer(seat) do
    if step_chip_actions(assigns) == [] and not later_choices?(assigns) do
      case GameServer.apply(assigns.id, seat, :chip_done) do
        {:ok, game} -> put_game(socket, game)
        _error -> socket
      end
    else
      socket
    end
  end

  defp end_choices(socket), do: socket

  # Round 31: the step Next scored last (nil before the first), and whether the
  # bonus die strip plays (while the die step is the last scored).
  defp tile_slide(%{index: 0}), do: nil
  defp tile_slide(%{slides: slides, index: index}), do: Enum.at(slides, index - 1)

  # The die faces by the crown wait until the die step is scored.
  defp tile_rolls(game, seat, %{tiles: true, slides: slides, index: index}) do
    if slides |> Enum.take(index) |> Enum.any?(&(&1.kind == :die)),
      do: TileReveal.rolls(game, seat),
      else: []
  end

  defp tile_rolls(game, seat, _reveal), do: TileReveal.rolls(game, seat)

  # Round 35: on the tiles the die rolls in the results stage, on its row.
  defp die_step?(%{tiles: true}), do: false
  defp die_step?(_reveal), do: true

  # Your ruby total by the pot: while the steps play on the tiles, after the step shown.
  defp ruby_total(game, _me, seat, %{tiles: true} = reveal),
    do: tile_totals(game, reveal)[seat].rubies

  defp ruby_total(_game, me, _seat, _reveal), do: me.rubies

  # `{vp, rubies, vp_before, rubies_before}` per seat: after the last scored step
  # and before it (round 31: the step the bar names is not scored yet).
  defp tile_totals(game, %{slides: slides, index: index}) do
    now = TileReveal.totals(game, slides, index - 1)
    before = TileReveal.totals(game, slides, index - 2)

    droplets = TileReveal.droplets(game, slides, index - 1)

    Map.new(now, fn {s, {vp, rubies}} ->
      {vp0, rubies0} = before[s]
      {s, %{vp: vp, rubies: rubies, droplet: droplets[s], vp_from: vp0, rubies_from: rubies0}}
    end)
  end

  # The rat track follows the tiles' running VP while the steps play.
  defp tile_vps(game, reveal),
    do: Map.new(tile_totals(game, reveal), fn {s, totals} -> {s, totals.vp} end)

  # Auto mode: the shown slide's time (the overlay's timer bar), else nil.
  defp reveal_ms(%{slides: slides, index: index}, :auto, speed),
    do: slides |> Enum.at(index) |> Reveal.duration(Reveal.factor(speed))

  defp reveal_ms(_reveal, _mode, _speed), do: nil

  # The last slide's button names what comes next.
  defp close_label(%{key: {:card, _}}, _decision, _skip), do: "Continue"
  defp close_label(%{key: {:recap, _}}, _decision, _skip), do: "Next round"
  defp close_label(_reveal, :shop, _skip), do: "To the shop"
  defp close_label(_reveal, :rubies, _skip), do: "Spend rubies"
  defp close_label(_reveal, :droplet_choice, _skip), do: "Move the droplet"

  # Round 29 (F1): round 9 has no "Done": the game's end follows by itself (round 31: the chart over the pot).
  defp close_label(%{key: {:results, 9}}, _decision, true), do: "Continue"
  defp close_label(%{key: {:results, _}}, _decision, true), do: "Done"
  defp close_label(_reveal, _decision, _skip), do: "Close"

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
  defp replay_effects(game, seat, _seen, %{tiles: true} = reveal),
    do: game |> TileReveal.step_lines(seat || 0, tile_slide(reveal)) |> Replay.pot_effects()

  defp replay_effects(game, seat, seen, _reveal) do
    if replaying?(game, seen),
      do: game |> Replay.beats(seat || 0) |> Replay.pot_effects(),
      else: []
  end

  defp replay_die_lines(game, seat),
    do: game |> Replay.beats(seat || 0) |> Enum.filter(&(&1.kind == :die))

  # With `:from`, the values the counters start from (`Replay.before/2`): on the tab
  # that ends the round the strip was never drawn with the old values.
  # Round 31: while the steps play on the tiles, the ruby counter ticks with the
  # step that brings rubies (beat 0 of the step, when its rubies land).
  defp stat_beats(game, seat, _seen, %{tiles: true} = reveal) do
    %{rubies_from: from} = tile_totals(game, reveal)[seat]
    gains = Map.get(tile_slide(reveal) || %{}, :gains, %{})

    case gains[seat] do
      {_vp, rubies} when rubies > 0 -> %{rubies: 0, from: %{rubies: from}}
      _none -> %{}
    end
  end

  defp stat_beats(game, seat, seen, _reveal) do
    if replaying?(game, seen),
      do:
        for(
          %{kind: kind, beat: beat} <- Replay.updates(game, seat),
          kind == :rubies,
          into: %{from: Replay.before(game, seat)},
          do: {kind, beat}
        ),
      else: %{}
  end

  # While the round results show: what lights up on the pot on which replay beat
  # (the same beats as the dialog's lines, so both play in step).
  defp replay_marks(game, seat, %{tiles: true} = reveal),
    do: TileReveal.marks(game, seat || 0, tile_slide(reveal))

  defp replay_marks(game, seat, _reveal) do
    if results?(game), do: game |> Replay.beats(seat || 0) |> Replay.highlights(), else: %{}
  end

  # A shop with "Done" as the only move left (nothing to buy, no rubies to spend, no
  # witch to call: `skip_rubies`) ends this seat's round by itself, so the player is
  # not asked for a bare "Done". Right after its own buy or ruby spend (`acted?`),
  # else not while the round's beats still play: the update chips stay until they
  # are read (the "seen" event comes back here).
  defp auto_done(socket, acted? \\ false)

  # Round 35: not while the steps play on the tiles (a ruby spent in the results'
  # rubies step); `close_reveal/1` calls it again.
  defp auto_done(%{assigns: %{reveal: %{tiles: true}}} = socket, _acted?), do: socket

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

  # Round 32: rubies paid for the droplet or the flask end the round only after the
  # pot showed the move (`PotMotion` hop, 520 ms; flask fill, 700 ms), so the next
  # round's card does not cover it.
  defp done_after(%{assigns: %{skip_rubies: true}} = socket, {:rubies, what})
       when what in [:droplet, :flask] and @show_move_ms > 0 do
    Process.send_after(self(), :auto_done, @show_move_ms)
    socket
  end

  defp done_after(socket, action), do: auto_done(socket, shop_move?(action))

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

  # Round 36: the everyone-card's rows show in the results stage while the card is
  # grown over the pot, or while its choice waits (once a seat chose).
  defp card_stage?(%{game: %Game{fortune_card: card} = game} = assigns) when card != nil do
    (assigns.card_grown or
       (assigns.decision == :fortune_choice and Fortune.reveal_card?(card))) and
      not tiles_playing?(assigns.reveal) and Reveal.card_reveals(game) != %{}
  end

  defp card_stage?(_assigns), do: false

  # Round 36: Ghost's breath V's buys while its choice is open in the bar.
  defp purple_buys(assigns),
    do: assigns |> pot_choice_actions() |> Enum.filter(&match?({:chip, {:buy, [_ | _]}}, &1))

  # Round 36: the pot chip picked for its choices, while it still has them.
  defp pot_pick(actions, chip) do
    if chip && Enum.any?(actions, &(pot_action?(&1) and pot_chip(&1) == chip)), do: chip
  end

  # Round 36: the pot chips the open choice is about (`pot_action?/1`), for the
  # pot: one choice is sent at a tap, more open them in the bar (`pot_pick`).
  defp pot_targets(%{seat: seat, game: %Game{} = game, me: %Player{} = me} = assigns)
       when is_integer(seat) do
    assigns
    |> pot_choice_actions()
    |> Enum.filter(&pot_action?/1)
    |> Enum.group_by(&pot_chip/1)
    |> Map.new(fn
      {chip, [action]} ->
        {chip, %{event: "action", value: encode(action), label: action_label(action, game, me)}}

      {chip, _actions} ->
        {chip,
         %{event: "pot_pick", value: encode(chip), label: "#{chip_name(chip)}: choose its swap"}}
    end)
  end

  defp pot_targets(_assigns), do: %{}

  # The actions of the bar's open choice (the same list the bar shows).
  defp pot_choice_actions(assigns) do
    cond do
      tile_hold(assigns) == :chip_choice -> step_chip_actions(assigns)
      tiles_playing?(assigns.reveal) or Game.over?(assigns.game) -> []
      assigns.bar_choice in [:chip_choice, :essence_bonus] -> assigns.all_actions
      true -> []
    end
  end

  # Round 36: the chip Mandrake V peeked at on this seat's newest draw this round.
  defp peeked(log, seat) when is_integer(seat) do
    log
    |> Stream.take_while(
      &(not match?({^seat, {:drew, _, _}}, &1) and not match?({:round_end, _}, &1))
    )
    |> Enum.find_value(fn
      {^seat, {:effect, {:yellow, 5}, {:peek, chip}}} -> chip
      _entry -> nil
    end)
  end

  defp peeked(_log, _seat), do: nil

  # The white chip of the newest Mandrake answer (see `keep_white?/3`).
  defp returned_white(%{log: [{_seat, {:returned, chip}} | _]}), do: chip

  # The Ear worm line: draws left, no explosion.
  defp ear_worm_left(%{phase: :ear_worm, essence_pending: {:ear_worm, n}}), do: n
  defp ear_worm_left(_me), do: nil

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

  defp name(names, seat), do: Map.get(names, seat, GameServer.default_name(seat))

  # Seats by VP, highest first.

  defp seed_param({a, b, c}), do: "#{a},#{b},#{c}"

  defp ladder_action?({:chip, {kind, _}}) when kind in [:purple_trade, :pay_ruby_move], do: true
  defp ladder_action?(_action), do: false
end
