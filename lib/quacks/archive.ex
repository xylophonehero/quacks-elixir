defmodule Quacks.Archive do
  @moduledoc """
  Finished games on a laptop, for `mix quacks.review` and `mix quacks.tune --starts`
  (`docs/research/learn-from-nick.md`).

  - `pull_fly/3` copies the archive files of a Fly app (`Quacks.GameStore.archive/4`,
    `<GAMES_DIR>/finished/<game>/*.json`: Quacks and every `Table.Server` game) to
    `<dest>/<game>/`. It only reads on the server: one `fly ssh console` that
    lists the files, then one per 100 new files that sends them as a base64 tar on
    stdout. Files that are there already are not copied again.
  - `pull_github/2` writes the replay bundle of every bug report issue
    (`Quacks.BugReports.list_bundles/1`) as `github-<issue>.json`.
  - `load/2` and `load_dir/2` read either kind of file into a `t:game/0`.
  """

  alias Quacks.{BugReports, Game, Session}

  @remote_dir "/data/games/finished"
  @chunk 100
  @name ~r/\A[a-z0-9_]+\/[A-Za-z0-9_-]+\.json\z/

  @typedoc """
  A game to review. `humans`: the seats people played; `bots`: the profile name of
  each bot seat (a bundle without profiles gets `:bot_profile`, default
  `"expert"`). `over?`: the game ended (bug report bundles stop where the report
  was sent).
  """
  @type game :: %{
          id: String.t(),
          path: Path.t(),
          bundle: map,
          players: pos_integer,
          names: [String.t() | nil],
          humans: [Game.seat()],
          bots: %{Game.seat() => String.t()},
          session: Session.t(),
          over?: boolean
        }

  @typedoc "Runs `fly` with the arguments: `{stdout, exit status}` (`System.cmd/3`)."
  @type runner :: ([String.t()] -> {String.t(), non_neg_integer})

  # -- pull -----------------------------------------------------------------------------

  @doc """
  Copy the archive files of Fly app `app` into `dest/<game>/`. Options:
  `game:` only this game key (`"quacks"`, `"hearts"`, ...; default all),
  `remote_dir:` (default `#{@remote_dir}`), `runner:` (a `t:runner/0`, default
  the `fly` CLI). Returns `{:ok, %{remote: n, new: [paths]}}` (`remote`: the
  files of the chosen games on the server) or `{:error, reason}`.
  """
  @spec pull_fly(String.t(), Path.t(), keyword) ::
          {:ok, %{remote: non_neg_integer, new: [Path.t()]}} | {:error, term}
  def pull_fly(app, dest, opts \\ []) do
    runner = Keyword.get(opts, :runner, &fly/1)
    remote = Keyword.get(opts, :remote_dir, @remote_dir)
    File.mkdir_p!(dest)

    with {:ok, names} <- remote_names(runner, app, remote, opts[:game]),
         missing = Enum.reject(names, &File.exists?(Path.join(dest, &1))),
         {:ok, paths} <- fetch_all(runner, app, remote, missing, dest) do
      {:ok, %{remote: length(names), new: paths}}
    end
  end

  defp fetch_all(runner, app, remote, names, dest) do
    names
    |> Enum.chunk_every(@chunk)
    |> Enum.reduce_while({:ok, []}, fn chunk, {:ok, acc} ->
      case fetch_chunk(runner, app, remote, chunk, dest) do
        {:ok, paths} -> {:cont, {:ok, acc ++ paths}}
        error -> {:halt, error}
      end
    end)
  end

  defp remote_names(runner, app, remote, game) do
    case ssh(runner, app, "cd #{remote} 2>/dev/null && find . -name \"*.json\" -type f || true") do
      {out, 0} ->
        names =
          out
          |> String.split("\n", trim: true)
          |> Enum.map(&(&1 |> String.trim() |> String.trim_leading("./")))
          |> valid()

        {:ok,
         if(game, do: Enum.filter(names, &String.starts_with?(&1, game <> "/")), else: names)}

      {out, status} ->
        {:error, {:fly, status, String.slice(out, 0, 500)}}
    end
  end

  defp valid(names), do: names |> Enum.filter(&Regex.match?(@name, &1)) |> Enum.sort()

  defp fetch_chunk(runner, app, remote, names, dest) do
    with {out, 0} <-
           ssh(runner, app, "cd #{remote} && tar cf - #{Enum.join(names, " ")} | base64"),
         {:ok, tar} <- out |> String.replace(~r/\s/, "") |> Base.decode64(),
         {:ok, files} <- :erl_tar.extract({:binary, tar}, [:memory]) do
      {:ok,
       for {name, body} <- files,
           name = name |> to_string() |> String.trim_leading("./"),
           name in names do
         path = Path.join(dest, name)
         File.mkdir_p!(Path.dirname(path))
         File.write!(path, body)
         path
       end}
    else
      {out, status} when is_binary(out) -> {:error, {:fly, status, String.slice(out, 0, 500)}}
      :error -> {:error, :bad_base64}
      {:error, reason} -> {:error, {:tar, reason}}
    end
  end

  defp ssh(runner, app, command),
    do: runner.(["ssh", "console", "-a", app, "-C", "sh -c '#{command}'"])

  defp fly(args), do: System.cmd("fly", args)

  @doc """
  Write the replay bundle of every bug report issue (open or closed, label
  `bug-report`) to `dest/github-<issue>.json`. Returns `{:ok, [paths]}`.
  """
  @spec pull_github(Path.t(), String.t() | nil) :: {:ok, [Path.t()]} | {:error, term}
  def pull_github(dest, token \\ nil) do
    with {:ok, bundles} <- BugReports.list_bundles(token) do
      File.mkdir_p!(dest)

      {:ok,
       for {number, bundle} <- bundles do
         path = Path.join(dest, "github-#{number}.json")
         File.write!(path, Jason.encode_to_iodata!(bundle, pretty: true))
         path
       end}
    end
  end

  # -- load -----------------------------------------------------------------------------

  @doc """
  Every game file in `dir` (`*.json`, also in subdirectories) that loads, sorted by
  path; with the files that do not load as `{path, reason}`.
  """
  @spec load_dir(Path.t(), keyword) :: {[game], [{Path.t(), term}]}
  def load_dir(dir, opts \\ []) do
    dir
    |> Path.join("**/*.json")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&{&1, load(&1, opts)})
    |> Enum.split_with(&match?({_, {:ok, _}}, &1))
    |> then(fn {ok, bad} ->
      {Enum.map(ok, fn {_, {:ok, g}} -> g end), Enum.map(bad, fn {p, {:error, r}} -> {p, r} end)}
    end)
  end

  @doc """
  One game file: an archive file (`"format" => 1`) or a bundle (a bug report's, or
  `Quacks.Session.bundle/1`). Options: `bot_profile:` for bundles that do not name
  the bots' profile (default `"expert"`), `humans:` a list of seats that overrides
  the file (a bot game such as a golden bundle has none).
  """
  @spec load(Path.t(), keyword) :: {:ok, game} | {:error, term}
  def load(path, opts \\ []) do
    with {:ok, text} <- File.read(path),
         {:ok, body} <- Jason.decode(text) do
      from_body(body, path, opts)
    end
  end

  defp from_body(%{"format" => 1, "game" => game}, _path, _opts) when game != "quacks",
    do: {:error, {:not_quacks, game}}

  defp from_body(%{"format" => 1, "bundle" => bundle, "seats" => seats} = body, path, opts) do
    bots = for %{"seat" => s, "human" => false, "bot" => b} <- seats, into: %{}, do: {s, b}
    humans = for %{"seat" => s, "human" => true} <- seats, do: s
    build(bundle, body["id"] || Path.basename(path, ".json"), path, humans, bots, opts)
  end

  defp from_body(%{"log" => _} = bundle, path, opts) do
    players = bundle["players"]
    bot_seats = bundle["bots"]

    {humans, bots} =
      if is_list(bot_seats) do
        profile = Keyword.get(opts, :bot_profile, "expert")
        {Enum.to_list(0..(players - 1)) -- bot_seats, Map.new(bot_seats, &{&1, profile})}
      else
        # A bot game: the golden bundles were played by `:balanced` bots.
        {[], Map.new(0..(players - 1), &{&1, Keyword.get(opts, :bot_profile, "balanced")})}
      end

    build(bundle, Path.basename(path, ".json"), path, humans, bots, opts)
  end

  defp from_body(_body, _path, _opts), do: {:error, :not_a_game}

  defp build(bundle, id, path, humans, bots, opts) do
    {humans, bots} =
      case opts[:humans] do
        nil ->
          {humans, bots}

        seats ->
          all = Enum.to_list(0..(bundle["players"] - 1))
          {seats, Map.new(all -- seats, &{&1, Map.get(bots, &1, "expert")})}
      end

    case Session.from_bundle(bundle) do
      {:ok, session} ->
        {:ok,
         %{
           id: id,
           path: path,
           bundle: bundle,
           players: session.players,
           names: bundle["names"] || List.duplicate(nil, session.players),
           humans: Enum.sort(humans),
           bots: bots,
           session: session,
           over?: Game.over?(session.game)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
