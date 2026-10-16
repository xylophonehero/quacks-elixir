defmodule TableWeb.CodenamesDuetLiveTest do
  @moduledoc """
  The Codenames Duet pages: `/games` → `/games/codenames_duet/new` → a room at
  `/games/codenames_duet/<code>` for two people.

  Most tests put the fixed board of `CodenamesDuet.Scenario` (known words and
  key) into the room before the pages open, so a test knows each card's colours.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import QuacksWeb.LiveHelpers

  alias CodenamesDuet.{Game, Key, Scenario}
  alias Table.Server

  @key "codenames_duet"

  defp create(token, opts) do
    {:ok, code} = Server.create(@key, %{opts: opts, name: "Ann"}, token)
    code
  end

  # A room with the fixed board (`Scenario.fixed/1`): the pages that open after
  # this see it.
  defp fixed_room(token, opts \\ %{}, game \\ nil) do
    code = create(token, opts)
    game = game || Scenario.fixed(opts)
    [{pid, _}] = Registry.lookup(Table.Registry, {@key, code})
    :sys.replace_state(pid, &%{&1 | game: game})
    code
  end

  defp game(code), do: Server.state(@key, code).game

  defp open_room(token, code),
    do: live(init_test_session(build_conn(), player_token: token), "/games/#{@key}/#{code}")

  # Both pages of a fixed room: Ann at seat 0, Bob at seat 1.
  defp two_pages(opts \\ %{}) do
    ann = token("ann")
    bob = token("bob")
    code = fixed_room(ann, opts)
    {:ok, a, _} = open_room(ann, code)
    {:ok, b, _} = open_room(bob, code)
    _ = render(a)
    %{a: a, b: b, code: code}
  end

  defp give_clue(view, word, number) do
    view
    |> form("#clue-form", clue: %{word: word, number: to_string(number)})
    |> render_submit()
  end

  # A guess: the first tap picks the card, the second tap guesses it.
  defp guess(view, index) do
    view |> element("#duet-card-#{index}") |> render_click()
    view |> element("#duet-card-#{index}") |> render_click()
  end

  defp guess_all(view, indexes), do: Enum.each(indexes, &guess(view, &1))

  test "pick, set up, create: the room shows the code and the invite link", %{conn: conn} do
    conn = init_test_session(conn, player_token: token("host"))
    {:ok, games, _} = live(conn, "/games")
    assert has_element?(games, "#pick-codenames_duet")

    {:ok, setup, _} =
      games |> element("#pick-codenames_duet") |> render_click() |> follow_redirect(conn)

    assert has_element?(setup, "#timer-#{Game.defaults().timer}:checked")

    assert {:error, {:live_redirect, %{to: "/games/codenames_duet/" <> code = to}}} =
             setup
             |> form("#duet-setup", setup: %{name: "Ann", timer: "11"})
             |> render_submit()

    {:ok, room, _} = live(conn, to)
    assert has_element?(room, "#duet-grid")
    assert has_element?(room, "#duet-invite")
    assert has_element?(room, "#duet-code", code)
    assert render(room) =~ "/games/#{@key}/#{code}"
    assert game(code).timer == 11
    assert Server.state(@key, code).seats[0].name == "Ann"
    assert count(render(room), "#duet-timer [data-token]") == 11
  end

  test "a second browser takes seat 1, a reload keeps the seat, a third browser watches" do
    ann = token("ann")
    code = fixed_room(ann)
    {:ok, a, _} = open_room(ann, code)
    assert has_element?(a, "#duet-invite")

    {:ok, b, _} = open_room(token("bob"), code)
    refute has_element?(b, "#duet-invite")
    _ = render(a)
    refute has_element?(a, "#duet-invite")

    {:ok, a2, _} = open_room(ann, code)
    assert has_element?(a2, "#clue-form")
    assert Server.state(@key, code).seats[0].token == ann

    {:ok, c, _} = open_room(token("carl"), code)
    assert has_element?(c, "#duet-status", "watching")
    refute has_element?(c, "#clue-form")
    refute has_element?(c, "[data-key]")
  end

  test "a clue, a green guess, then a bystander ends the turn" do
    %{a: a, b: b, code: code} = two_pages()

    # Both can give the first clue.
    assert has_element?(a, "#clue-form")
    assert has_element?(b, "#clue-form")

    give_clue(a, "Zulu", 2)
    assert has_element?(a, "#duet-clue", "zulu")
    assert has_element?(b, "#duet-clue", "zulu")
    refute has_element?(a, "#clue-form")
    refute has_element?(b, "#clue-form")
    refute has_element?(b, "#end-guessing")

    # The first tap only picks the card.
    b |> element("#duet-card-0") |> render_click()
    assert has_element?(b, "#duet-card-0[data-state=picked]")
    assert has_element?(b, "#guess-confirm")
    assert game(code).agents == %{}
    b |> element("#duet-card-0") |> render_click()
    assert game(code).agents == %{0 => 1}
    assert has_element?(b, "#duet-card-0[data-agent]")
    _ = render(a)
    assert has_element?(a, "#duet-card-0[data-agent]")
    assert has_element?(a, "#duet-found", "1/15")
    assert has_element?(b, "#end-guessing")

    # Index 18 is a bystander on Ann's side: the turn ends, one token used.
    guess(b, 18)
    assert game(code).bystanders == %{18 => [0]}
    assert has_element?(b, "#duet-card-18[data-marks='0']")
    assert has_element?(b, "#duet-timer [data-token][data-used]")
    assert has_element?(b, "#clue-form")
    _ = render(a)
    refute has_element?(a, "#clue-form")
    assert has_element?(a, "#duet-log [data-clue='zulu'] [data-guess]")
    assert count(render(a), "#duet-log [data-clue='zulu'] [data-guess]") == 2
  end

  test "End guessing uses a token and passes the clue" do
    %{a: a, b: b, code: code} = two_pages()
    give_clue(a, "zulu", 1)
    guess(b, 1)
    b |> element("#end-guessing") |> render_click()
    assert game(code).timer == 8
    assert has_element?(b, "#clue-form")
  end

  test "an invalid clue shows the engine's error under the field" do
    %{a: a, code: code} = two_pages()

    give_clue(a, "ALPHA", 1)
    assert has_element?(a, "#clue-error", "alpha")
    assert game(code).phase == :clue

    give_clue(a, "two words", 1)
    assert has_element?(a, "#clue-error", "one word")

    give_clue(a, "zulu", 1)
    refute has_element?(a, "#clue-error")
    assert game(code).phase == :guess
  end

  test "the page never holds the partner's key while the game is on" do
    %{a: a, b: b} = two_pages()
    pairs = Key.pairs()

    for {view, seat} <- [{a, 0}, {b, 1}], {pair, i} <- Enum.with_index(pairs) do
      own = pair |> elem(seat) |> to_string()
      assert has_element?(view, "#duet-card-#{i}[data-key=#{own}]")
    end

    refute render(a) =~ "data-partner-key"

    # The same seat-0 page for two keys that differ only on seat 1's side.
    ann = token("ann")
    base = Scenario.fixed()
    other = %{base | key: %{base.key | 1 => Enum.reverse(base.key[1])}}
    html = fn game -> ann |> fixed_room(%{}, game) |> then(&page_html(ann, &1)) end
    assert html.(base) == html.(other)
  end

  defp page_html(token, code) do
    {:ok, view, _} = open_room(token, code)

    view
    |> element("#duet-grid")
    |> render()
  end

  test "hide my key removes the key marks from the page" do
    %{a: a} = two_pages()
    assert has_element?(a, "[data-key]")
    a |> element("#hide-key") |> render_click()
    refute has_element?(a, "[data-key]")
    a |> element("#hide-key") |> render_click()
    assert has_element?(a, "[data-key]")
  end

  test "win: all 15 green words found; the key shows, the score, Play again" do
    %{a: a, b: b, code: code} = two_pages()

    give_clue(a, "zulu", 9)
    guess_all(b, Scenario.greens(0))
    # Ann's side is done: Bob gives every clue now.
    assert game(code).done == [0]
    assert has_element?(b, "#clue-form")
    _ = render(a)
    refute has_element?(a, "#clue-form")
    give_clue(b, "yolk", 9)
    _ = render(a)
    guess_all(a, Scenario.greens(1) -- Scenario.greens(0))

    assert game(code).result == :won
    _ = render(b)

    for view <- [a, b] do
      assert has_element?(view, "#duet-over[data-result=won]")
      assert has_element?(view, "#duet-score")
      assert has_element?(view, "#duet-card-14[data-partner-key]")
    end

    a |> element("#play-again") |> render_click()
    _ = render(a)
    refute has_element?(a, "#duet-over")
    assert game(code).phase == :clue
  end

  test "lose: the guesser touches an assassin" do
    %{a: a, b: b, code: code} = two_pages()
    give_clue(a, "zulu", 1)
    guess(b, 15)
    assert game(code).result == :lost
    assert has_element?(b, "#duet-over[data-result=lost]", "assassin")
    assert has_element?(b, "#duet-card-15[data-touched]")
    _ = render(a)
    assert has_element?(a, "#duet-over[data-result=lost]")
    refute has_element?(a, "#duet-score")
  end

  test "sudden death: a banner, no clue, a wrong guess loses" do
    %{a: a, b: b, code: code} = two_pages(%{timer: 1})
    give_clue(a, "zulu", 1)
    guess(b, 18)
    assert game(code).phase == :sudden_death
    _ = render(a)

    for view <- [a, b] do
      assert has_element?(view, "#duet-sudden-death")
      refute has_element?(view, "#clue-form")
      refute has_element?(view, "#end-guessing")
    end

    # Ann guesses on Bob's side: 8 is green there, 19 a bystander.
    guess(a, 8)
    assert game(code).agents[8] == 0
    guess(a, 19)
    assert game(code).result == :lost
    assert has_element?(a, "#duet-over[data-result=lost]")
  end
end
