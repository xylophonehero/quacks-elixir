defmodule CodexWeb.Gallery do
  @moduledoc """
  The gallery's Codex sandbox story (`/dev/gallery/codex/board`): the real board
  page (`CodexWeb.Board.page/1`) at a game state, with no room process.

  Each state is a real `Codex.Game` from a fixed seed, played on with
  `Codex.Game.apply/3`, so it looks the same on every run. The page's assigns come
  from `Board.init/1` and `Board.put_view/3`, as on the live page.
  """

  alias Codex.Game
  alias CodexWeb.Board

  @seed {7, 8, 9}

  @doc "The board states."
  @spec states() :: [String.t()]
  def states,
    do:
      ~w(mid-game start red-green blue-black bb-choice bb-codex-pick selected chips focus patrol aim expanded zoom opp-open attack attack-base opp-turn tech codex discard buildings log free bot crowded)

  @doc "The board story. Args: `state`, `pov` (0 or 1), `reveal`."
  @spec board_story(map) :: map
  def board_story(args) do
    state = args["state"]

    {:ok, start} = Game.new(%{bot: state == "bot", preset: preset(state)}, @seed)
    game = game(state, start)

    pov = if args["pov"] == "P2", do: 1, else: 0

    socket =
      %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, flash: %{}, code: "GALRY", seats: %{}}
      }
      |> Board.init()
      |> Board.put_view(envelope(game), nil)
      |> Phoenix.Component.assign(pov: pov, reveal: args["reveal"] == true)
      |> extra(state, game)

    %{view: :codex_board, board: socket.assigns}
  end

  defp preset("red-green"), do: "red_green"
  defp preset("crowded"), do: "red_green"
  defp preset("blue-black"), do: "blue_black"
  defp preset("bb-" <> _), do: "blue_black"
  defp preset(_state), do: "first"

  defp game(state, start) when state in ["start", "red-green", "blue-black"], do: start
  defp game("bb-" <> _, start), do: blue_pick(start)
  # Against the bot, on the bot's turn: the page waits.
  defp game("bot", start), do: elem(Game.apply(start, 0, :end_turn), 1)
  defp game("crowded", start), do: crowded(start)
  defp game(_state, start), do: mid_game(start)

  defp envelope(game) do
    %Table.View{
      version: 1,
      seat: 0,
      status: Game.status(game),
      actions: Game.legal_actions(game, 0),
      view: Game.view(game, 0)
    }
  end

  # A choice pick: Reputable Newsman names a cost (a button for each value).
  defp extra(socket, "bb-choice", game) do
    id = card_of(game, "reputable-newsman")

    Phoenix.Component.assign(socket,
      selected: id,
      targeting: %{key: {:play, id, nil}, picked: []}
    )
  end

  # A codex pick: Jurisdiction plays a spell from the codex (a button for each card).
  defp extra(socket, "bb-codex-pick", game) do
    id = card_of(game, "jurisdiction")

    Phoenix.Component.assign(socket,
      selected: id,
      targeting: %{key: {:play, id, nil}, picked: []}
    )
  end

  defp extra(socket, "selected", game) do
    [id | _] = game.sides[0].zones.in_play
    Phoenix.Component.assign(socket, selected: id)
  end

  # A desktop: the mouse on P1's hero (squad leader): its action chips show.
  defp extra(socket, "chips", game) do
    Phoenix.Component.assign(socket, hover: game.sides[0].zones.patrol.squad_leader)
  end

  # A desktop: the keyboard focus ring on P1's first unit in play (a static
  # copy of :focus-visible).
  defp extra(socket, "focus", game) do
    [id | _] = game.sides[0].zones.in_play
    Phoenix.Component.assign(socket, focus: id)
  end

  # Patrol (the P key or the chip): the first unit selected, its free slots lit.
  defp extra(socket, "patrol", game) do
    [id | _] = game.sides[0].zones.in_play
    Phoenix.Component.assign(socket, selected: id, patrolling: true)
  end

  # A desktop: P1's Granfalloon Flagbearer dragged onto River Montoya: the arrow,
  # the preview at its head, the legal targets lit and the rest dimmed (the hook
  # draws it from `demo_aim`).
  defp extra(socket, "aim", game) do
    [id | _] = game.sides[0].zones.in_play
    river = game.sides[1].zones.patrol.lookout
    Phoenix.Component.assign(socket, demo_aim: "#{id} #cx-card-#{river}")
  end

  # Free mode, the hero selected, its sheet expanded: the full card, all actions, tokens.
  defp extra(socket, "expanded", game) do
    {:ok, game} = Game.apply(game, 0, {:free_mode, true})
    hero = game.sides[0].zones.patrol.squad_leader

    socket
    |> Board.put_view(envelope(game), nil)
    |> Phoenix.Component.assign(selected: hero, expanded: true)
  end

  # A long press on a card on the board: its full face over the table.
  defp extra(socket, "zoom", game) do
    [id | _] = game.sides[0].zones.in_play
    Phoenix.Component.assign(socket, zoom: id)
  end

  # A phone: the opponent's whole side, open as a sheet from the top.
  defp extra(socket, "opp-open", _game), do: Phoenix.Component.assign(socket, opp_open: true)

  # A pick in progress: P1's first ready force attacks; its targets glow.
  defp extra(socket, "attack", game) do
    case Enum.find(Game.legal_actions(game, 0), &match?({:attack, _, _}, &1)) do
      {:attack, a, _} ->
        Phoenix.Component.assign(socket,
          selected: a,
          targeting: %{key: {:attack, a, nil}, picked: []}
        )

      nil ->
        socket
    end
  end

  # An attack with no patroller in the way: the base of P2 is the target (a
  # phone: a big tile; a desktop: the base portrait lit).
  defp extra(socket, "attack-base", game) do
    %{elite: bloom, lookout: river} = game.sides[1].zones.patrol

    game =
      Enum.reduce(
        [
          {:free_mode, true},
          {:move, bloom, {1, :discard}, 0},
          {:move, river, {1, :in_play}, nil},
          {:free_mode, false}
        ],
        game,
        fn action, game -> elem(Game.apply(game, 0, action), 1) end
      )

    socket
    |> Board.put_view(envelope(game), nil)
    |> extra("attack", game)
  end

  # Against the bot: P1 ends the turn, the bot plays its turn, the turn comes
  # back: the card with what the bot did.
  defp extra(socket, "opp-turn", _game) do
    {:ok, start} = Game.new(%{bot: true, preset: "first"}, @seed)
    {:ok, game} = Game.apply(start, 0, :end_turn)
    {:ok, game} = Game.apply(game, 0, tech(game, :tech))
    bot = Stream.iterate(game, &bot_step/1) |> Enum.find(&(&1.active == 0))

    socket
    |> Board.put_view(envelope(game), nil)
    |> Board.put_view(envelope(bot), envelope(game))
  end

  # The tech step: the codex sheet with one card picked.
  defp extra(socket, "tech", game) do
    {:ok, game} = Game.apply(game, 0, :end_turn)
    socket = Board.put_view(socket, envelope(game), nil)
    [id | _] = game.sides[game.active].zones.codex

    Phoenix.Component.assign(socket,
      tech_pick: [game.cards[id].card],
      drawer: {game.active, :tech}
    )
  end

  defp extra(socket, "codex", _game), do: Phoenix.Component.assign(socket, drawer: {0, :codex})

  defp extra(socket, "discard", _game),
    do: Phoenix.Component.assign(socket, drawer: {0, :discard})

  defp extra(socket, "buildings", _game),
    do: Phoenix.Component.assign(socket, drawer: {0, :buildings})

  defp extra(socket, "log", _game), do: Phoenix.Component.assign(socket, drawer: :log)

  defp extra(socket, "free", game) do
    {:ok, game} = Game.apply(game, 0, {:free_mode, true})
    Board.put_view(socket, envelope(game), nil)
  end

  defp extra(socket, _state, _game), do: socket

  defp bot_step(game) do
    {action, _} = Codex.Bot.choose(Game.view(game, 1), nil)
    {:ok, game} = Game.apply(game, 1, action)
    game
  end

  # `:tech`: the first legal pick of the tech step.
  defp tech(game, :tech), do: Enum.find(Game.legal_actions(game, 0), &match?({:tech, _}, &1))
  defp tech(_game, action), do: action

  # Turn 3 of P1: heroes out with levels, units in play and on patrol, tokens,
  # gold, a tech building, cards in the discard piles and the trash. Brick Thief
  # (+1/+1 rune) is exhausted.
  # Blue vs Black: P1 with Bigby Hayes in play, 10 gold, Reputable Newsman and
  # Jurisdiction in hand (the new target picks: a choice and a codex card).
  defp blue_pick(game) do
    find = fn slug ->
      Enum.find(
        Enum.sort(Map.keys(game.cards)),
        &(game.cards[&1].card == slug and game.cards[&1].seat == 0)
      )
    end

    [
      {:free_mode, true},
      {:adjust, 0, :gold, 6},
      {:move, find.("bigby-hayes"), {0, :in_play}, nil},
      {:move, find.("reputable-newsman"), {0, :hand}, 0},
      {:move, find.("jurisdiction"), {0, :hand}, 0},
      {:free_mode, false}
    ]
    |> Enum.reduce(game, fn action, game -> elem(Game.apply(game, 0, action), 1) end)
  end

  defp card_of(game, slug),
    do: Enum.find(game.sides[0].zones.hand, &(game.cards[&1].card == slug))

  defp mid_game(game) do
    [p1_hero] = game.sides[0].zones.command
    [p2_hero] = game.sides[1].zones.command
    [a, b, c, d, _] = game.sides[0].zones.hand
    [e, f, g | _] = game.sides[1].zones.hand
    [x | _] = game.sides[0].zones.codex

    [
      {:free_mode, true},
      {:adjust, 0, :gold, 4},
      {:move, a, {0, :in_play}, nil},
      {:move, b, {0, :in_play}, nil},
      {:move, p1_hero, {0, :patrol}, :squad_leader},
      {:adjust_card, p1_hero, :level, 4},
      {:adjust_card, p1_hero, :damage, 1},
      {:toggle, b, :exhausted},
      {:adjust_card, b, :plus, 1},
      {:move, c, {0, :discard}, 0},
      {:move, x, {0, :discard}, 0},
      {:building, 0, :tech_1},
      :end_turn,
      :tech,
      {:adjust, 1, :gold, 5},
      {:move, e, {1, :patrol}, :elite},
      {:move, p2_hero, {1, :patrol}, :lookout},
      {:adjust_card, p2_hero, :level, 2},
      {:move, f, {1, :in_play}, nil},
      {:adjust_card, f, :damage, 1},
      {:move, g, :trash, nil},
      {:adjust, 0, :base_hp, -3},
      {:draw, 1, 2},
      :end_turn,
      :tech,
      {:move, d, {0, :workers}, nil},
      {:adjust, 0, :gold, -1},
      {:draw, 0, 2},
      {:toggle, b, :exhausted},
      {:free_mode, false}
    ]
    |> Enum.reduce(game, fn action, game ->
      {:ok, game} = Game.apply(game, 0, tech(game, action))
      game
    end)
  end

  # A full board (Red vs Green, 3 heroes each): per side 5 patrollers and 6 units
  # in play (codex units), Tech I, Tech II and a Tower; some units exhausted or
  # damaged. The phone layout must fit all of it on one screen.
  defp crowded(game) do
    moves =
      Enum.flat_map([0, 1], fn s ->
        units =
          game.sides[s].zones.codex
          |> Enum.filter(&(Codex.Cards.fetch!(game.cards[&1].card).type == "Unit"))
          |> Enum.uniq_by(&game.cards[&1].card)
          |> Enum.take(11)

        {patrol, in_play} = Enum.split(units, 5)

        Enum.zip(patrol, Game.patrol_slots())
        |> Enum.map(fn {id, slot} -> {:move, id, {s, :patrol}, slot} end)
        |> Kernel.++(Enum.map(in_play, &{:move, &1, {s, :in_play}, nil}))
        |> Kernel.++([
          {:toggle, Enum.at(in_play, 1), :exhausted},
          {:adjust_card, Enum.at(patrol, 0), :damage, 1},
          {:building, s, :tech_1},
          {:building, s, :tech_2},
          {:building, s, :tower},
          {:adjust, s, :gold, 6}
        ])
      end)

    [{:free_mode, true} | moves]
    |> Kernel.++([{:free_mode, false}])
    |> Enum.reduce(game, fn action, game ->
      case Game.apply(game, 0, action) do
        {:ok, game} -> game
        {:error, _} -> game
      end
    end)
  end
end
