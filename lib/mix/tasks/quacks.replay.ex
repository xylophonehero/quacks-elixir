defmodule Mix.Tasks.Quacks.Replay do
  @shortdoc "Loads a bug report's game: saves its bundle and prints the replay URL"
  @moduledoc """
  Reads the replay bundle of a bug report issue (`Quacks.BugReports.fetch_bundle/2`),
  writes it to `tmp/replay-<issue>.json` and prints the `/debug/replay` URL that
  loads it into a running server.

      mix quacks.replay 123 [--at 212] [--seat 0] [--port 4020] [--serve]

  The GitHub token comes from `BUG_REPORT_GITHUB_TOKEN`, else `gh auth token`; the
  repo from `BUG_REPORT_GITHUB_REPO` (default `xylophonehero/quacks-elixir`).
  `--port` (default 4000) is the server's port in the URL; with `--serve` the task
  starts the endpoint on that port itself and keeps running (the URL fetches the
  issue again there). Without `--serve`, the URL carries the bundle (base64), so the
  server needs no token.
  """
  use Mix.Task

  alias Quacks.BugReports

  @switches [at: :integer, seat: :integer, port: :integer, serve: :boolean]

  @impl true
  def run(argv) do
    {opts, args} = OptionParser.parse!(argv, strict: @switches)
    issue = issue!(args)
    port = opts[:port] || 4000
    if opts[:serve], do: System.put_env("PORT", to_string(port))
    token = System.get_env("BUG_REPORT_GITHUB_TOKEN") || gh_token()
    configure(token)

    bundle =
      case BugReports.fetch_bundle(issue, token) do
        {:ok, bundle} -> bundle
        {:error, reason} -> Mix.raise("Could not read issue ##{issue}: #{inspect(reason)}")
      end

    path = Path.join(File.cwd!(), "tmp/replay-#{issue}.json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode_to_iodata!(bundle, pretty: true))
    Mix.shell().info("Bundle: #{path} (#{length(bundle["log"] || [])} actions)")
    Mix.shell().info("Open: http://localhost:#{port}/debug/replay?#{query(issue, bundle, opts)}")
    if opts[:serve], do: serve()
  end

  defp issue!([issue]), do: String.to_integer(issue)

  defp issue!(_args),
    do: Mix.raise("Usage: mix quacks.replay ISSUE [--at N] [--seat S] [--port P] [--serve]")

  # The app's config, with the token for `BugReports` (and the served endpoint).
  defp configure(token) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:req)
    config = Application.get_env(:quacks, :bug_reports, [])

    Application.put_env(:quacks, :bug_reports, Keyword.put(config, :github_token, token),
      persistent: true
    )
  end

  # Served here, the server reads the issue itself; else the URL carries the bundle.
  defp query(issue, bundle, opts) do
    source =
      if opts[:serve],
        do: [issue: issue],
        else: [bundle: Base.url_encode64(Jason.encode!(bundle), padding: false)]

    URI.encode_query(source ++ Enum.filter([at: opts[:at], seat: opts[:seat]], &elem(&1, 1)))
  end

  defp serve do
    Application.put_env(:phoenix, :serve_endpoints, true, persistent: true)
    Mix.Task.run("run", ["--no-halt"])
  end

  defp gh_token do
    case System.cmd("gh", ["auth", "token"], stderr_to_stdout: true) do
      {token, 0} -> String.trim(token)
      _error -> nil
    end
  rescue
    _no_gh -> nil
  end
end
