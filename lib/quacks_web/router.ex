defmodule QuacksWeb.Router do
  use QuacksWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {QuacksWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :allow_framing
    plug QuacksWeb.Plugs.PlayerToken
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # No pipeline: the browser pipeline only accepts html.
  scope "/", QuacksWeb do
    get "/manifest.webmanifest", PwaController, :manifest
  end

  scope "/", QuacksWeb do
    pipe_through :browser

    live "/", LobbyLive
    live "/g/:id", GameLive
    # Gated in the controller: dev, or DEBUG_TOKEN.
    get "/debug/replay", DebugReplayController, :show
  end

  # The other table games (`Table.games/0`): pick one, set it up, play a room.
  scope "/games" do
    pipe_through :browser

    live "/", TableWeb.GamesLive
    live "/hearts/new", HeartsWeb.SetupLive
    live "/generic/new", TableWeb.GenericSetupLive
    live "/codenames_duet/new", CodenamesDuetWeb.SetupLive
    live "/codex/new", CodexWeb.SetupLive
    live "/:game/:code", TableWeb.TableLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", QuacksWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:quacks, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: QuacksWeb.Telemetry
    end
  end

  # The gallery (`QuacksWeb.GalleryLive`: stories with args, screens, scenarios) and
  # the scenarios' live games. In every build; `QuacksWeb.Plugs.Gallery` answers 404
  # unless the runtime flag `:gallery` is on (dev, test, staging; not prod).
  pipeline :gallery do
    plug QuacksWeb.Plugs.Gallery
  end

  scope "/dev", QuacksWeb do
    pipe_through [:browser, :gallery]

    live_session :gallery, on_mount: QuacksWeb.Plugs.Gallery do
      live "/gallery", GalleryLive
      live "/gallery/:component/:variant", GalleryLive
      live "/gallery/frame/:component/:variant", GalleryFrameLive
    end

    # Scenarios (`Quacks.Scenarios`): the index goes to the gallery; one item opens
    # as a live game on the game page.
    get "/scenarios", ScenarioController, :index
    get "/scenarios/:kind/*id", ScenarioController, :show
  end

  # Issue #71: WebinarGeek shows the game in an iframe. `frame-ancestors` decides who
  # may embed it, so the SAMEORIGIN default of `put_secure_browser_headers` goes.
  defp allow_framing(conn, _opts) do
    conn
    |> delete_resp_header("x-frame-options")
    |> put_resp_header(
      "content-security-policy",
      "frame-ancestors " <> Application.fetch_env!(:quacks, :frame_ancestors)
    )
  end
end
