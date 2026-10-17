defmodule Quacks.ArchiveTest do
  @moduledoc """
  `Quacks.Archive`: the pull from Fly (a stubbed `fly` runner), the pull from GitHub
  (a `Req.Test` stub) and the load of archive files and bundles.
  """
  # Not async: the GitHub stub is global config.
  use ExUnit.Case, async: false

  alias Mix.Tasks.Quacks.Games.Pull
  alias Quacks.{Archive, BugReports, Game, Session}

  @bundle Path.expand("../fixtures/bundles/bug_89.json", __DIR__)

  # A fake `fly`: `ls` lists `files`, `tar ... | base64` sends the named ones.
  defp runner(files, test_pid, tmp) do
    fn ["ssh", "console", "-a", app, "-C", "sh -c '" <> command] ->
      send(test_pid, {:fly, app, command})

      cond do
        String.starts_with?(command, "cd /data/games/finished 2>/dev/null && find ") ->
          {Enum.map_join(files, "\n", &("./" <> elem(&1, 0))) <> "\n./quacks/not a game.txt\n", 0}

        String.contains?(command, "tar cf - ") ->
          [_, names] = Regex.run(~r/tar cf - (.*) \| base64/, command)
          wanted = String.split(names, " ")
          {tar(files, wanted, tmp), 0}
      end
    end
  end

  defp tar(files, wanted, tmp) do
    tar = Path.join(tmp, "out.tar")
    chosen = for {name, body} <- files, name in wanted, do: {String.to_charlist(name), body}
    :ok = :erl_tar.create(String.to_charlist(tar), chosen)
    tar |> File.read!() |> Base.encode64() |> chunk()
  end

  # base64 in lines, as the `base64` command prints it
  defp chunk(text),
    do: text |> String.codepoints() |> Enum.chunk_every(76) |> Enum.map_join("\n", &Enum.join/1)

  @tag :tmp_dir
  test "pull_fly copies the new archive files only, read-only commands", %{tmp_dir: tmp} do
    files = [
      {"quacks/aaa.json", ~s({"format":1})},
      {"quacks/bbb.json", ~s({"format":1,"b":2})},
      {"hearts/ABCDE.json", ~s({"format":1,"game":"hearts"})}
    ]

    dest = Path.join(tmp, "quacks-staging")
    File.mkdir_p!(Path.join(dest, "quacks"))
    File.write!(Path.join(dest, "quacks/aaa.json"), "old")

    assert {:ok, %{remote: 3, new: new}} =
             Archive.pull_fly("quacks-staging", dest, runner: runner(files, self(), tmp))

    assert new |> Enum.map(&Path.relative_to(&1, dest)) |> Enum.sort() == [
             "hearts/ABCDE.json",
             "quacks/bbb.json"
           ]

    assert File.read!(Path.join(dest, "quacks/bbb.json")) == ~s({"format":1,"b":2})
    assert File.read!(Path.join(dest, "quacks/aaa.json")) == "old"

    assert_received {:fly, "quacks-staging", "cd /data/games/finished" <> _}
    assert_received {:fly, "quacks-staging", tar}
    assert tar =~ "cd /data/games/finished && tar cf - hearts/ABCDE.json quacks/bbb.json | base64"

    # --game: one game only
    File.rm_rf!(dest)

    assert {:ok, %{remote: 1, new: [only]}} =
             Archive.pull_fly("quacks-staging", dest,
               game: "hearts",
               runner: runner(files, self(), tmp)
             )

    assert Path.relative_to(only, dest) == "hearts/ABCDE.json"
  end

  @tag :tmp_dir
  test "pull_fly reports a failed fly command", %{tmp_dir: tmp} do
    runner = fn _args -> {"Error: app not found", 1} end

    assert {:error, {:fly, 1, "Error: app not found"}} =
             Archive.pull_fly("nope", tmp, runner: runner)
  end

  @tag :tmp_dir
  test "pull_github writes the bundle of each bug report issue", %{tmp_dir: tmp} do
    bundle = @bundle |> File.read!() |> Jason.decode!()

    Req.Test.stub(BugReports, fn conn ->
      assert conn.request_path == "/repos/xylophonehero/quacks-elixir/issues"
      assert conn.query_string =~ "labels=bug-report"

      Req.Test.json(conn, [
        %{
          "number" => 89,
          "body" =>
            "text\n<details><summary>Replay bundle</summary>\n\n```json\n#{Jason.encode!(bundle)}\n```\n</details>"
        },
        %{"number" => 2, "body" => "no bundle here"}
      ])
    end)

    assert {:ok, [path]} = Archive.pull_github(tmp)
    assert Path.basename(path) == "github-89.json"
    assert {:ok, game} = Archive.load(path)

    assert %{humans: [0], bots: %{1 => "expert", 2 => "expert", 3 => "expert"}, over?: false} =
             game
  end

  @tag :tmp_dir
  test "load reads an archive file: humans, bot profiles and the game", %{tmp_dir: tmp} do
    bundle = @bundle |> File.read!() |> Jason.decode!()

    body = %{
      "format" => 1,
      "id" => "abc",
      "seats" => [
        %{"seat" => 0, "human" => true, "bot" => nil},
        %{"seat" => 1, "human" => false, "bot" => "expert"},
        %{"seat" => 2, "human" => false, "bot" => "balanced"},
        %{"seat" => 3, "human" => true, "bot" => nil}
      ],
      "bundle" => bundle
    }

    path = Path.join(tmp, "abc.json")
    File.write!(path, Jason.encode!(body))

    assert {:ok, %{id: "abc", humans: [0, 3], bots: %{1 => "expert", 2 => "balanced"}} = game} =
             Archive.load(path)

    assert %Game{round: 5} = game.session.game
    assert {:ok, %Session{}} = Session.from_bundle(game.bundle)
  end

  @tag :tmp_dir
  test "load_dir skips files that are not games; humans: overrides the file", %{tmp_dir: tmp} do
    File.cp!(@bundle, Path.join(tmp, "g.json"))
    File.write!(Path.join(tmp, "bad.json"), ~s({"x": 1}))

    File.write!(Path.join(tmp, "h.json"), ~s({"format": 1, "game": "hearts", "log": []}))

    assert {[game], [{bad, :not_a_game}, {hearts, {:not_quacks, "hearts"}}]} =
             Archive.load_dir(tmp, humans: [1])

    assert Path.basename(bad) == "bad.json"
    assert Path.basename(hearts) == "h.json"
    assert game.humans == [1]
    assert game.bots == %{0 => "expert", 2 => "expert", 3 => "expert"}
  end

  @tag :tmp_dir
  test "mix quacks.games.pull copies an app's archive to <dest>/<app>/", %{tmp_dir: tmp} do
    Mix.shell(Mix.Shell.Process)
    files = [{"quacks/ccc.json", ~s({"format":1})}, {"hearts/X.json", "{}"}]
    Application.put_env(:quacks, :archive_pull, runner: runner(files, self(), tmp))

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
      Application.delete_env(:quacks, :archive_pull)
    end)

    Pull.run(["--app", "quacks-staging", "--dest", tmp, "--game", "quacks"])
    assert File.exists?(Path.join([tmp, "quacks-staging", "quacks", "ccc.json"]))
    refute File.exists?(Path.join([tmp, "quacks-staging", "hearts", "X.json"]))
    assert_received {:mix_shell, :info, [line]}
    assert line =~ "quacks-staging: 1 finished games on the server, 1 new"
  end
end
