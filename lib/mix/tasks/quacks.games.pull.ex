defmodule Mix.Tasks.Quacks.Games.Pull do
  @shortdoc "Copies finished games (Fly archive, GitHub bug reports) to tmp/finished/"
  @moduledoc """
  Copies finished games to the laptop for `mix quacks.review`
  (`docs/research/learn-from-nick.md`).

      mix quacks.games.pull --app quacks-staging
      mix quacks.games.pull --app quacks --app quacks-staging --github

  - `--app NAME` (more than one is fine): the archive files of that Fly app
    (`<GAMES_DIR>/finished/*.json`, `Quacks.GameStore.archive/3`) go to
    `<dest>/<app>/`. Read-only on the server (`fly ssh console` with `ls` and
    `tar`); files that are there already are not copied again. Needs `fly auth
    login`.
  - `--github`: the replay bundles of the bug report issues go to
    `<dest>/github/github-<issue>.json`. The token comes from
    `BUG_REPORT_GITHUB_TOKEN`, else `gh auth token` (a public repo needs none).
  - `--dest` (default `tmp/finished`).
  """
  use Mix.Task

  alias Quacks.Archive

  @switches [app: :keep, github: :boolean, dest: :string]

  @impl true
  def run(argv) do
    {opts, _args} = OptionParser.parse!(argv, strict: @switches)
    dest = opts[:dest] || "tmp/finished"
    apps = Keyword.get_values(opts, :app)

    if apps == [] and !opts[:github],
      do: Mix.raise("Usage: mix quacks.games.pull --app APP [--app APP2] [--github] [--dest DIR]")

    Mix.Task.run("app.config")
    Enum.each(apps, &pull_app(&1, dest))
    if opts[:github], do: pull_github(dest)
  end

  defp pull_app(app, dest) do
    dir = Path.join(dest, app)

    case Archive.pull_fly(app, dir, Application.get_env(:quacks, :archive_pull, [])) do
      {:ok, %{remote: n, new: new}} ->
        Mix.shell().info(
          "#{app}: #{n} finished games on the server, #{length(new)} new in #{dir}"
        )

      {:error, reason} ->
        Mix.raise("#{app}: cannot pull: #{inspect(reason)}")
    end
  end

  defp pull_github(dest) do
    {:ok, _} = Application.ensure_all_started(:req)
    dir = Path.join(dest, "github")
    token = System.get_env("BUG_REPORT_GITHUB_TOKEN") || gh_token()

    case Archive.pull_github(dir, token) do
      {:ok, paths} -> Mix.shell().info("github: #{length(paths)} bug report bundles in #{dir}")
      {:error, reason} -> Mix.raise("github: cannot pull: #{inspect(reason)}")
    end
  end

  defp gh_token do
    case System.cmd("gh", ["auth", "token"], stderr_to_stdout: true) do
      {token, 0} -> String.trim(token)
      _other -> nil
    end
  rescue
    _error -> nil
  end
end
