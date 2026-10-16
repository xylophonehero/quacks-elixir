defmodule Mix.Tasks.Quacks.SmokeTest do
  @moduledoc """
  G5 (architecture review §5.4): `mix quacks.sim` and `mix quacks.replay` run once
  each. The tasks call `Quacks.Game`, `Quacks.AI` and `Quacks.Session` directly, so
  a refactor of those (#80) must keep them working.
  """
  # Not async: `quacks.replay` writes the GitHub token into the app config and a
  # file under `tmp/`.
  use ExUnit.Case, async: false

  alias Mix.Tasks.Quacks.{Replay, Sim}
  alias Quacks.{BugReports, Session}

  @bundle Path.expand("../fixtures/bundles/bug_89.json", __DIR__)

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  defp infos do
    Stream.repeatedly(fn ->
      receive do
        {:mix_shell, :info, [line]} -> line
      after
        0 -> nil
      end
    end)
    |> Enum.take_while(& &1)
  end

  test "quacks.sim plays one short game and prints the table" do
    Sim.run(~w(--games 1 --profiles balanced,reckless --seed 3))

    [summary, header | rows] = infos()
    assert summary =~ ~r/^1 games, 2 players, /
    assert header =~ ~r/^\s*profile\s+seats\s+VP/
    assert Enum.any?(rows, &(&1 =~ ~r/^\s*balanced\s+1\s/))
    assert Enum.any?(rows, &(&1 =~ ~r/^\s*reckless\s+1\s/))
  end

  test "quacks.replay saves the issue's bundle and prints a URL that carries it" do
    config = Application.get_env(:quacks, :bug_reports)
    System.put_env("BUG_REPORT_GITHUB_TOKEN", "smoke-test")
    path = Path.join(File.cwd!(), "tmp/replay-89.json")

    on_exit(fn ->
      System.delete_env("BUG_REPORT_GITHUB_TOKEN")
      Application.put_env(:quacks, :bug_reports, config)
      File.rm(path)
    end)

    json = File.read!(@bundle)

    Req.Test.stub(BugReports, fn conn ->
      assert conn.request_path == "/repos/xylophonehero/quacks-elixir/issues/89"

      Req.Test.json(conn, %{
        body: "<details><summary>Replay bundle</summary>\n\n```json\n#{json}\n```\n</details>"
      })
    end)

    Replay.run(~w(89 --at 12 --seat 0))

    ["Bundle: " <> saved, "Open: " <> url] = infos()
    assert saved =~ "tmp/replay-89.json (251 actions)"
    assert File.read!(path) |> Jason.decode!() == Jason.decode!(json)

    %URI{path: "/debug/replay", query: query} = URI.parse(url)
    assert %{"bundle" => encoded, "at" => "12", "seat" => "0"} = URI.decode_query(query)
    bundle = encoded |> Base.url_decode64!(padding: false) |> Jason.decode!()
    assert {:ok, %Session{}} = Session.from_bundle(bundle, 12)
  end
end
