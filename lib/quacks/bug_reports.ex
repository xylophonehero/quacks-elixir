defmodule Quacks.BugReports do
  @moduledoc """
  Bug reports from the game page, filed as GitHub issues.

  `submit/1` reads the table from `Quacks.GameServer`, writes a markdown issue (the
  player's text, a context table, the browser details, the last log lines in words
  and the replay bundle, `Quacks.Session.bundle/1`, as JSON) and opens it through
  the GitHub REST API. `fetch_bundle/1` reads that bundle back from an issue, for
  `GameServer.start_from_bundle/2` (the `/debug/replay` route and `mix
  quacks.replay`).

  Config (`config/runtime.exs`): `BUG_REPORT_GITHUB_TOKEN` (a token with Issues
  read/write on the repo) and `BUG_REPORT_GITHUB_REPO` (default
  `xylophonehero/quacks-elixir`). Without a token the report goes to
  `tmp/bug-reports/<timestamp>-<room>.md` and the result is a `file://` URL.

  Limits: one report per seat of a room per minute, text up to 2000 characters,
  only from a seated player. The body stays under 60 000 characters: the log lines
  go first, never the bundle.
  """

  alias Quacks.{Game, GameServer}
  alias QuacksWeb.GameComponents

  @max_text 2000
  @max_body 60_000
  @log_lines 20
  @window_ms 60_000
  @table __MODULE__
  @default_repo "xylophonehero/quacks-elixir"

  @git_sha (try do
              case System.cmd("git", ["rev-parse", "--short", "HEAD"], stderr_to_stdout: true) do
                {sha, 0} -> String.trim(sha)
                _other -> "unknown"
              end
            rescue
              _error -> "unknown"
            end)

  @typedoc "What the browser adds: user agent, viewport, `navigator.onLine`, console errors."
  @type browser :: %{
          optional(:ua) => String.t(),
          optional(:viewport) => String.t(),
          optional(:online) => boolean,
          optional(:errors) => [String.t()]
        }

  @type report :: %{
          game_id: GameServer.id(),
          seat: Game.seat() | nil,
          text: String.t(),
          browser: browser
        }

  @doc "The rate limit table. `Quacks.Application` creates it at start."
  @spec create_table() :: :ok
  def create_table do
    :ets.new(@table, [:named_table, :public, :set])
    :ok
  end

  @doc """
  File a report. `{:ok, %{url: url, number: n | nil}}`; errors: `:empty` (no text),
  `:too_long`, `:not_seated`, `:rate_limited`, `:not_found` (no such game) or
  `{:github, status}`.
  """
  @spec submit(report) ::
          {:ok, %{url: String.t(), number: pos_integer | nil}}
          | {:error, :empty | :too_long | :not_seated | :rate_limited | :not_found | term}
  def submit(%{game_id: id, seat: seat, text: text} = report) do
    text = String.trim(text || "")

    with :ok <- check_text(text),
         :ok <- check_seat(seat),
         :ok <- check_rate(id, seat),
         {:ok, table} <- GameServer.get(id),
         {:ok, result} <- file(issue(table, seat, text, Map.get(report, :browser, %{}))) do
      :ets.insert(@table, {{id, seat}, now()})
      {:ok, result}
    end
  end

  defp check_text(""), do: {:error, :empty}

  defp check_text(text),
    do: if(String.length(text) > @max_text, do: {:error, :too_long}, else: :ok)

  defp check_seat(seat) when is_integer(seat), do: :ok
  defp check_seat(_seat), do: {:error, :not_seated}

  defp check_rate(id, seat) do
    case :ets.lookup(@table, {id, seat}) do
      [{_key, at}] -> if now() - at < @window_ms, do: {:error, :rate_limited}, else: :ok
      [] -> :ok
    end
  end

  defp now, do: System.monotonic_time(:millisecond)

  @doc """
  The issue for a report: `%{title, body, room}`. Public for tests; `submit/1`
  files it.
  """
  @spec issue(GameServer.table(), Game.seat(), String.t(), browser) :: %{
          title: String.t(),
          body: String.t(),
          room: String.t()
        }
  def issue(table, seat, text, browser) do
    bundle =
      case GameServer.bundle(table.id) do
        {:ok, bundle} -> Map.put(bundle, :seat, seat)
        {:error, _} -> nil
      end

    %{
      title: "[bug] #{where(table.game)} · #{text |> first_line() |> String.slice(0, 60)}",
      body: body(table, seat, text, browser, bundle),
      room: table.id
    }
  end

  defp where(nil), do: "lobby"
  defp where(game), do: "round #{game.round}"

  defp first_line(text), do: text |> String.split("\n", parts: 2) |> hd() |> String.trim()

  defp body(table, seat, text, browser, bundle) do
    head = [
      text,
      "\n\n### Context\n\n",
      context(table, seat),
      "\n### Browser\n\n",
      browser(browser)
    ]

    tail =
      if bundle,
        do: [
          "\n<details><summary>Replay bundle</summary>\n\n```json\n",
          Jason.encode!(bundle),
          "\n```\n\n</details>\n"
        ],
        else: []

    fixed = IO.iodata_length(head) + IO.iodata_length(tail)
    lines = table |> log_words() |> fit(fixed)
    IO.iodata_to_binary([head, log_block(lines), tail])
  end

  # Drop the oldest log lines until the body fits.
  defp fit(lines, fixed) do
    if lines == [] or fixed + IO.iodata_length(log_block(lines)) <= @max_body,
      do: lines,
      else: fit(tl(lines), fixed)
  end

  defp log_block([]), do: []

  defp log_block(lines),
    do: ["\n### Last log lines (oldest first)\n\n", Enum.map(lines, &["- ", &1, "\n"])]

  # The newest log lines in the words of the page's log, oldest first.
  defp log_words(%{game: nil}), do: []

  defp log_words(table) do
    names = if table.players > 1, do: table.names

    table.game.log
    |> GameComponents.log_text(@log_lines, names)
    |> Enum.reverse()
  end

  defp context(table, seat) do
    game = table.game

    rows = [
      {"Room", "`#{table.id}`"},
      {"Seat", "#{seat} (#{Map.get(table.names, seat, GameServer.default_name(seat))})"},
      {"Status", table.status},
      {"Round", game && game.round},
      {"Phase", game && game.phase},
      {"Player phase", game && Game.phase(game, seat)},
      {"Players",
       "#{table.players} (bots: #{table.bots |> Map.keys() |> Enum.sort() |> inspect()})"},
      {"Expansions", table.expansions |> Enum.sort() |> Enum.join(", ")},
      {"Rules", "`#{inspect((game && game.rules) || table.rules)}`"},
      {"Sets", "`#{inspect((game && game.sets) || table.sets)}`"},
      {"Actions", game && length(game.log)},
      {"App", "#{Application.spec(:quacks, :vsn)} (#{@git_sha})"}
    ]

    ["| | |\n|---|---|\n", Enum.map(rows, fn {k, v} -> "| #{k} | #{cell(v)} |\n" end)]
  end

  defp cell(nil), do: "—"
  defp cell(value), do: value |> to_string() |> String.replace("|", "\\|")

  defp browser(browser) do
    errors =
      browser
      |> Map.get(:errors, [])
      |> List.wrap()
      |> Enum.take(-10)
      |> Enum.map(&["- ", &1 |> to_string() |> String.slice(0, 300), "\n"])

    [
      "```\n",
      "User agent: #{browser[:ua]}\n",
      "Viewport: #{browser[:viewport]}\n",
      "Online: #{inspect(browser[:online])}\n",
      "```\n",
      if(errors == [], do: "\nNo console errors.\n", else: ["\nConsole errors:\n\n", errors])
    ]
  end

  # -- filing --------------------------------------------------------------------------

  defp file(issue) do
    case config(:github_token) do
      token when is_binary(token) and token != "" -> post(issue, token)
      _none -> write(issue)
    end
  end

  defp post(issue, token) do
    case Req.post(req(token),
           url: "/repos/#{repo()}/issues",
           json: %{title: issue.title, body: issue.body, labels: ["bug-report"]}
         ) do
      {:ok, %{status: 201, body: %{"html_url" => url, "number" => number}}} ->
        {:ok, %{url: url, number: number}}

      {:ok, %{status: status}} ->
        {:error, {:github, status}}

      {:error, exception} ->
        {:error, {:github, exception}}
    end
  end

  defp write(issue) do
    dir = Application.get_env(:quacks, :bug_report_dir, Path.join(File.cwd!(), "tmp/bug-reports"))
    stamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic) |> String.replace(~r/\..*/, "")
    path = Path.join(dir, "#{stamp}-#{issue.room}.md")
    File.mkdir_p!(dir)
    File.write!(path, ["# ", issue.title, "\n\n", issue.body])
    {:ok, %{url: "file://" <> path, number: nil}}
  end

  # -- reading back --------------------------------------------------------------------

  @doc """
  The replay bundle (string keys) of issue `number`, through the GitHub API.
  `token` defaults to the configured one; a public repo needs none.
  """
  @spec fetch_bundle(pos_integer, String.t() | nil) ::
          {:ok, map} | {:error, :no_bundle | {:github, term}}
  def fetch_bundle(number, token \\ config(:github_token)) do
    case Req.get(req(token), url: "/repos/#{repo()}/issues/#{number}") do
      {:ok, %{status: 200, body: %{"body" => body}}} -> extract_bundle(body)
      {:ok, %{status: status}} -> {:error, {:github, status}}
      {:error, exception} -> {:error, {:github, exception}}
    end
  end

  @doc "The bundle in an issue body (or a report file), decoded."
  @spec extract_bundle(String.t() | nil) :: {:ok, map} | {:error, :no_bundle}
  def extract_bundle(body) when is_binary(body) do
    with [_, json] <-
           Regex.run(~r/<summary>Replay bundle<\/summary>\s*```json\s*(.+?)\s*```/s, body),
         {:ok, bundle} when is_map(bundle) <- Jason.decode(json) do
      {:ok, bundle}
    else
      _ -> {:error, :no_bundle}
    end
  end

  def extract_bundle(_body), do: {:error, :no_bundle}

  defp req(token) do
    Req.new(
      [
        base_url: "https://api.github.com",
        headers: [accept: "application/vnd.github+json", "x-github-api-version": "2022-11-28"],
        retry: false
      ] ++
        if(token in [nil, ""], do: [], else: [auth: {:bearer, token}]) ++
        Application.get_env(:quacks, :github_req_options, [])
    )
  end

  defp repo, do: config(:github_repo) || @default_repo

  defp config(key), do: Application.get_env(:quacks, :bug_reports, []) |> Keyword.get(key)
end
