defmodule Quacks.BugReportsTest do
  @moduledoc "Bug reports become GitHub issues with a replay bundle (`Quacks.BugReports`)."
  # The GitHub token is application config: not async.
  use ExUnit.Case, async: false

  alias Quacks.{BugReports, GameServer, Session}

  setup do
    on_exit(fn -> Application.put_env(:quacks, :bug_reports, github_token: nil) end)
  end

  defp playing do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    {:ok, 0} = GameServer.claim_seat(id, "a")
    {:ok, 1} = GameServer.claim_seat(id, "b")
    {:ok, _game} = GameServer.begin(id, "a")
    {:ok, _game} = GameServer.apply(id, 0, :draw)
    id
  end

  defp report(id, seat \\ 0, text \\ "The pot froze\nafter a draw") do
    %{
      game_id: id,
      seat: seat,
      text: text,
      browser: %{ua: "TestBrowser/1.0", viewport: "390x844", online: true, errors: ["boom"]}
    }
  end

  test "submit opens an issue with context, browser, log and a bundle that replays" do
    Application.put_env(:quacks, :bug_reports, github_token: "secret", github_repo: "me/quacks")
    id = playing()
    test = self()

    Req.Test.stub(BugReports, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)

      send(
        test,
        {:request, conn.method, conn.request_path,
         Plug.Conn.get_req_header(conn, "authorization"), Jason.decode!(raw)}
      )

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{html_url: "https://github.com/me/quacks/issues/7", number: 7})
    end)

    assert {:ok, %{url: "https://github.com/me/quacks/issues/7", number: 7}} =
             BugReports.submit(report(id))

    assert_receive {:request, "POST", "/repos/me/quacks/issues", ["Bearer secret"], issue}
    assert issue["labels"] == ["bug-report"]
    assert issue["title"] == "[bug] round 1 · The pot froze"
    body = issue["body"]
    assert body =~ "The pot froze\nafter a draw"
    assert body =~ "| Room | `#{id}` |"
    assert body =~ "| Seat | 0 (Player 1) |"
    assert body =~ "| Round | 1 |"
    assert body =~ "User agent: TestBrowser/1.0"
    assert body =~ "- boom"
    assert body =~ "### Last log lines"
    assert body =~ "Player 1: Drew"

    {:ok, bundle} = BugReports.extract_bundle(body)
    assert bundle["seat"] == 0 and bundle["names"] == ["Player 1", "Player 2"]
    {:ok, table} = GameServer.get(id)
    {:ok, session} = Session.from_bundle(bundle)
    assert session.game == table.game
  end

  test "without a token the report goes to a file" do
    id = playing()
    assert {:ok, %{url: "file://" <> path, number: nil}} = BugReports.submit(report(id))
    assert path =~ ~r/-#{id}\.md$/
    assert {:ok, _bundle} = path |> File.read!() |> BugReports.extract_bundle()
  end

  test "one report per seat per minute; text and seat are checked" do
    id = playing()
    assert {:error, :empty} = BugReports.submit(report(id, 0, "   "))
    assert {:error, :too_long} = BugReports.submit(report(id, 0, String.duplicate("a", 2001)))
    assert {:error, :not_seated} = BugReports.submit(report(id, nil))
    assert {:error, :not_found} = BugReports.submit(report("nosuch"))
    assert {:ok, _} = BugReports.submit(report(id, 0))
    assert {:error, :rate_limited} = BugReports.submit(report(id, 0))
    assert {:ok, _} = BugReports.submit(report(id, 1))
  end

  test "a GitHub error is an error" do
    Application.put_env(:quacks, :bug_reports, github_token: "secret")
    id = playing()
    Req.Test.stub(BugReports, &Plug.Conn.send_resp(&1, 422, "nope"))
    assert {:error, {:github, 422}} = BugReports.submit(report(id))
    # A failed report does not count against the limit.
    Req.Test.stub(BugReports, fn conn ->
      conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{html_url: "u", number: 1})
    end)

    assert {:ok, _} = BugReports.submit(report(id))
  end

  test "a report from the configure screen has no bundle" do
    {:ok, id} = GameServer.start(2)
    {:ok, 0} = GameServer.claim_seat(id, "a")
    assert {:ok, %{url: "file://" <> path}} = BugReports.submit(report(id))
    text = File.read!(path)
    assert text =~ "[bug] lobby · The pot froze"
    assert {:error, :no_bundle} = BugReports.extract_bundle(text)
  end

  test "fetch_bundle reads the bundle from an issue" do
    Req.Test.stub(BugReports, fn conn ->
      assert conn.request_path == "/repos/xylophonehero/quacks-elixir/issues/12"

      Req.Test.json(conn, %{
        body:
          "text\n<details><summary>Replay bundle</summary>\n\n```json\n{\"version\":1}\n```\n</details>"
      })
    end)

    assert {:ok, %{"version" => 1}} = BugReports.fetch_bundle(12, nil)
  end
end
