# 5. Routes and the LiveView lifecycle

[Back to the guide](../GUIDE.md)

## The router

The `:browser` pipeline (`lib/quacks_web/router.ex:4-12`) is a list of *plugs*. A
plug is a function `conn -> conn`, the Express middleware idea. Our only custom plug
is the last one, `QuacksWeb.Plugs.PlayerToken` (chapter 4).

```elixir
scope "/", QuacksWeb do
  pipe_through :browser

  live "/", LobbyLive
  live "/g/:id", GameLive
end
```

(`lib/quacks_web/router.ex:18-23`)

Two pages. The `scope` adds the `QuacksWeb.` prefix. `:id` becomes `params["id"]` in
`mount/3`.

**Not here: `live_session` and `handle_params`.** Apps with login group their
LiveViews in a `live_session` with `on_mount` hooks that load the user. This app has
no accounts, so it has no `live_session` and no `current_scope`; the token plug does
the identity job. `handle_params/3` runs after `mount` and on every `<.link patch>`
(a URL change inside one LiveView). Both pages read their params once in `mount` and
change page with `push_navigate`, so neither defines it. A URL that changes inside
the game page (`/g/:id?sheet=log`) would go there.

## The lifecycle of one tab

```mermaid
sequenceDiagram
  participant Br as Browser
  participant EP as Endpoint + Router
  participant LV as GameLive process
  Br->>EP: GET /g/abcdef
  EP->>LV: mount (connected? = false), render
  LV-->>Br: full HTML (static, no process kept)
  Br->>EP: websocket /live (app.js)
  EP->>LV: new process: mount (connected? = true), render
  LV->>LV: subscribe "game:abcdef"
  Br->>LV: phx-click "action"
  LV->>LV: handle_event, assign
  LV-->>Br: diff only
  Note over LV: PubSub message arrives
  LV->>LV: handle_info, assign
  LV-->>Br: diff only
```

`mount/3` runs **twice**. The first run answers the HTTP request with plain HTML
(fast first paint). Then `app.js` opens the websocket and a new LiveView process
mounts again. That process lives as long as the tab. So `mount` subscribes only when
connected (`lib/quacks_web/live/game_live.ex:102`):

```elixir
if connected?(socket), do: Phoenix.PubSub.subscribe(Quacks.PubSub, GameServer.topic(id))
```

`GameLive.mount/3` (`lib/quacks_web/live/game_live.ex:99-130`) gets the table (not
found: flash and `push_navigate` to `/`), subscribes, claims a seat (`nil` for a
spectator), and assigns the id, token, seat, table and game.

`assign/2` is how a LiveView keeps state. `socket.assigns` is a map; the template
reads it as `@name`. When an assign changes, LiveView re-renders only the template
parts that read it, and sends only the diff.

## Events: from a click to the engine

```heex
<.button
  phx-click="action"
  phx-value-action={encode(:draw)}
  disabled={:draw not in @actions}
  variant="primary"
  data-slot="draw"
>
  Draw a chip
</.button>
```

(`lib/quacks_web/live/game_live.ex:805-813`)

`phx-click="action"` sends the event `"action"`; `phx-value-action` adds
`%{"action" => "..."}` to the params. One handler serves every game move
(`lib/quacks_web/live/game_live.ex:133-148`):

```elixir
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
```

- The head matches the event name, the params *and* the socket. The guard
  `when is_integer(seat)` sends spectators (`seat: nil`) to the second clause.
- A bad payload or an illegal move shows a flash; the process does not crash
  (`test/quacks_web/live/game_live_test.exs:60-66` checks it).
- A new rule needs no new `handle_event`.

## Encoding actions into `phx-value-*`

Actions are terms like `{:buy, [{:green, 2}]}`; HTML attributes are strings. So
(`lib/quacks_web/live/game_live.ex:1902`):

```elixir
def encode(action), do: action |> :erlang.term_to_binary() |> Base.url_encode64(padding: false)
```

`decode/1` (`lib/quacks_web/live/game_live.ex:1909-1918`) reverses it with
`Plug.Crypto.non_executable_binary_to_term(binary, [:safe])`. The value comes from
the browser, so it is untrusted. `[:safe]` refuses to create new atoms (atoms are
never garbage-collected, so atoms from users are a memory leak), and
`non_executable_` refuses functions. A decoded but illegal action still meets
`legal_actions/2` in the engine. One encoder covers every action shape, and the
engine is the only validator.

## Broadcasts arrive as `handle_info`

PubSub messages arrive in the mailbox like any message
(`lib/quacks_web/live/game_live.ex:302-312`):

```elixir
# The game began: seats were renumbered, so ask for ours again.
def handle_info({:game, _id, game}, %{assigns: %{game: nil}} = socket),
  do: {:noreply, socket |> reseat() |> put_game(game)}

# Our own moves arrive twice (reply and broadcast); skip the copy we already have.
def handle_info({:game, _id, game}, socket) do
  if game == socket.assigns.game,
    do: {:noreply, socket},
    else: {:noreply, put_game(socket, game)}
end
```

`game == socket.assigns.game` compares by value, deeply. No custom `equals`.
`{:play_again, _id, new_id}` calls `push_navigate/2`, so every tab moves to the next
game (`lib/quacks_web/live/game_live.ex:324-325`).

## Derived assigns: `@me`, `@decision`, `@actions`

The template never calls the engine in a loop. `put_game/2` computes what the page
needs, once per new game (`lib/quacks_web/live/game_live.ex:1655-1672`):

```elixir
seat = socket.assigns.seat
me = if seat, do: game.players[seat]
actions = if seat && not Game.over?(game), do: Game.legal_actions(game, seat), else: []
decision = decision(actions, seat && Game.phase(game, seat), me)
```

- `@me`: this seat's `%Player{}`, or `nil` for a spectator.
- `@all_actions`: every legal action of this seat.
- `@decision`: which decision dialog must be open, from the seat's phase
  (`lib/quacks_web/live/game_live.ex:1762-1774`); `nil` while brewing.
- `@actions`: the actions for the bottom bar; empty while a decision is open, so the
  bar cannot bypass the dialog.

This is the React "selector" idea. Because `put_game/2` is the only place that sets
these assigns, the reply path and the broadcast path cannot disagree.

## Flash, navigation, two renders

- `put_flash(socket, :error, "...")` shows a toast; `<Layouts.app>` renders it
  (`lib/quacks_web/components/layouts.ex:49`).
- `push_navigate(socket, to: ~p"/g/#{id}")` starts a new LiveView. `~p` is a
  *verified route*: the compiler checks that the path exists in the router.
- Before the game begins, `@game` is `nil`. `render/1` has two clauses
  (`lib/quacks_web/live/game_live.ex:412` and `:562`): `def render(%{game: nil} =
  assigns)` draws the configure screen, the other the board. The begin broadcast
  sets `@game`, and the next render picks the other clause.
- `terminate/2` frees the seat when a tab closes before the start
  (`lib/quacks_web/live/game_live.ex:331-334`).

`LobbyLive` is the small version of the same pattern: subscribe to `"lobby"`, list
`GameServer.open_games/0`, list again on `:games_changed`
(`lib/quacks_web/live/lobby_live.ex:20-42`).
