defmodule QuacksWeb.StaticCheck do
  @moduledoc """
  Round 18: a page that outlived a deploy reloads. LiveView reconnects an open tab
  to the new server, which renders new markup, but the tab keeps the old `app.css`;
  a utility class that is new in this deploy has no rule there. That is how the
  round-16 results grid fell to one column on a phone (its
  `grid-cols-[minmax(0,1fr)_...]` class only existed in the new stylesheet).

  `on_mount` (every LiveView, `QuacksWeb.live_view/0`): when the connected
  socket's tracked assets (`phx-track-static` in the root layout) differ from the
  server's (`Phoenix.LiveView.static_changed?/1`), push `quacks:reload`; app.js
  reloads the page once, so the new stylesheet comes with the new markup. Without a
  digest manifest (dev, test) nothing ever differs.
  """
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) and static_changed?(socket),
      do: {:cont, push_event(socket, "quacks:reload", %{})},
      else: {:cont, socket}
  end
end
