defmodule QuacksWeb.PresetsLiveTest do
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.GameServer
  alias Quacks.Rules.BookPresets

  setup %{conn: conn} do
    %{conn: init_test_session(conn, player_token: "presets-#{System.unique_integer()}")}
  end

  test "themed books work without witch coins, including at the created table", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?step=books")
    view |> element("#preset-cherry_bombs") |> render_click()

    assert_push_event(view, "save_config", %{
      preset: "cherry_bombs",
      expansion: false,
      witches: %{}
    })

    refute has_element?(view, "#expansion[checked]")
    assert has_element?(view, "#preset-cherry_bombs[aria-pressed=true]")
    refute has_element?(view, "#preset-combo")
    assert has_element?(view, "#preset-set5")
    assert has_element?(view, "#preset-set6")

    {:error, {:live_redirect, %{to: "/g/" <> id}}} =
      view |> element("#new-game") |> render_click()

    {:ok, table} = GameServer.get(id)
    assert table.sets == BookPresets.get(:cherry_bombs).sets
    assert table.witches == %{}
    refute MapSet.member?(table.expansions, :herb_witches)
  end

  test "enabling witches after picking books applies coins; changing and disabling clears them",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?step=books")
    preset = BookPresets.get(:cherry_bombs)
    view |> element("#preset-cherry_bombs") |> render_click()
    view |> element("#books") |> render_change(preset_form(preset, true))

    assert_push_event(view, "save_config", %{
      preset: "cherry_bombs",
      expansion: true,
      witches: %{gold: "g2", silver: "s3", copper: "c1"}
    })

    assert has_element?(view, "#preset-cherry_bombs[aria-pressed=true]")
    assert has_element?(view, "#page-witch-gold input[value=g2][checked]")

    custom =
      Map.put(preset_form(preset, true), "witches", %{
        "gold" => "g1",
        "silver" => "s3",
        "copper" => "c1"
      })

    view |> element("#books") |> render_change(custom)
    refute has_element?(view, "#preset-cherry_bombs[aria-pressed=true]")
    assert has_element?(view, "[data-role=preset-label]", "Custom")

    view |> element("#books") |> render_change(preset_form(preset, false))
    assert_push_event(view, "save_config", %{expansion: false, witches: %{}})
    view |> element("#preset-set6") |> render_click()
    view |> element("#books") |> render_change(preset_form(BookPresets.get(:set6), true))
    assert_push_event(view, "save_config", %{preset: "set6", witches: %{}})
  end

  test "picking with witches on and restoring keeps exact picks and manual overrides", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/?step=books")
    view |> element("#books") |> render_change(preset_form(BookPresets.get(:beginner), true))
    view |> element("#preset-playing_safe") |> render_click()

    assert_push_event(view, "save_config", %{
      preset: "playing_safe",
      witches: %{gold: "g4", silver: "s1", copper: "c3"}
    })

    saved = preset_form(BookPresets.get(:playing_safe), true)
    render_hook(view, "load_config", saved)
    assert has_element?(view, "#preset-playing_safe[aria-pressed=true]")
    assert has_element?(view, "#page-witch-silver input[value=s1][checked]")

    custom = put_in(saved, ["witches", "silver"], "s2")
    render_hook(view, "load_config", custom)
    assert has_element?(view, "[data-role=preset-label]", "Custom")
    assert has_element?(view, "#page-witch-silver input[value=s2][checked]")

    render_hook(view, "load_config", Map.put(custom, "expansion", false))
    refute has_element?(view, "#expansion[checked]")
    assert has_element?(view, "#preset-playing_safe[aria-pressed=true]")

    {:error, {:live_redirect, %{to: "/g/" <> id}}} =
      view |> element("#new-game") |> render_click()

    {:ok, table} = GameServer.get(id)
    assert table.witches == %{}
  end

  defp preset_form(preset, enabled?) do
    %{
      "sets" =>
        Map.new(preset.sets, fn {colour, book} -> {to_string(colour), to_string(book)} end),
      "expansion" => enabled?,
      "witches" =>
        Map.new(preset.witches, fn {colour, witch} -> {to_string(colour), to_string(witch)} end)
    }
  end
end
