import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :quacks, QuacksWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "HjVZrZiwgUJyTXU9jGhDhqCXDaNmL5pIylSd5fjeSqbEvcGMu3njEqubw4dm2lr2",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Bots act at once in tests (see Quacks.GameServer).
config :quacks, bot_delay: 0

# Bug reports: GitHub is a `Req.Test` stub, reports go to a temp dir, and the debug
# replay route is closed (`Quacks.BugReports`, `QuacksWeb.DebugReplayController`).
config :quacks, :github_req_options, plug: {Req.Test, Quacks.BugReports}
config :quacks, :bug_reports, github_token: nil
config :quacks, :bug_report_dir, Path.join(System.tmp_dir!(), "quacks-bug-reports-test")
config :quacks, :debug_token, nil
