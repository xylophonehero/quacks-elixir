defmodule QuacksWeb.Router do
  use QuacksWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {QuacksWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
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
end
