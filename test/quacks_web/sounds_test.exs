defmodule QuacksWeb.SoundsTest do
  @moduledoc """
  The sound manifest (`QuacksWeb.Sounds`, `docs/research/sounds.md` §4.5): the files
  exist and have a licence line, the chip fallback chain, the scoring replay, and
  the page parts (the menu's Sound row, `<body data-sounds>`, the pot chips' sound).
  No audio test: the manual phone checklist is §4.5.
  """
  use QuacksWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import QuacksWeb.LiveHelpers
  alias Quacks.GameServer
  alias QuacksWeb.Sounds

  @dir Path.expand("../../priv/static/sounds", __DIR__)

  describe "the files" do
    test "the MVP files are there, each with a licence line" do
      licences = File.read!(Path.join(@dir, "LICENSES.md"))

      assert Enum.all?(~w(boom ruby gameover), &(&1 in Sounds.files()))

      for name <- Sounds.files() do
        assert File.exists?(Path.join(@dir, "#{name}.m4a"))
        assert licences =~ "`#{name}.m4a`", "#{name}.m4a has no line in LICENSES.md"
      end
    end

    test "the manifest maps each file to its static path" do
      manifest = Jason.decode!(Sounds.manifest())
      assert Map.keys(manifest) == Sounds.files()

      for {name, path} <- manifest do
        assert path =~ ~r{^/sounds/#{name}(-[0-9a-f]+)?\.m4a}
        assert File.exists?(Path.join(@dir, "#{name}.m4a"))
      end
    end

    test "each chip's sound is a file or a synth" do
      for chip <- Sounds.chips() do
        assert Sounds.chip_sound(chip) in (Sounds.files() ++ Sounds.synths())
      end

      assert Sounds.fortune_sound() in (Sounds.files() ++ Sounds.synths())
    end
  end

  describe "the chip fallback" do
    @files ~w(boom chip-white-1 chip-white-3 chip-orange-1 chip-green-2)

    test "its own file, else the nearest lower value, else plop" do
      assert Sounds.chip_sound({:white, 1}, @files) == "chip-white-1"
      assert Sounds.chip_sound({:white, 2}, @files) == "chip-white-1"
      assert Sounds.chip_sound({:white, 3}, @files) == "chip-white-3"
      assert Sounds.chip_sound({:orange, 6}, @files) == "chip-orange-1"
      assert Sounds.chip_sound({:green, 4}, @files) == "chip-green-2"
      assert Sounds.chip_sound({:green, 1}, @files) == "plop"
      assert Sounds.chip_sound({:black, 1}, @files) == "plop"
      assert Sounds.chip_sound({:purple, nil}, @files) == "plop"
    end

    test "every chip of the game is listed once" do
      chips = Sounds.chips()
      assert length(chips) == length(Enum.uniq(chips))
      assert {:white, 3} in chips and {:orange, 6} in chips and {:locoweed, 1} in chips
    end
  end

  describe "the scoring replay" do
    test "black, green and purple: one cue per row with chips, in the stage's order" do
      rows = [
        %{seat: 0, chips: [{:green, 2}, {:green, 1}]},
        %{seat: 1, chips: []},
        %{seat: 2, chips: [{:green, 4}]}
      ]

      cues = Sounds.replay(%{kind: :book, book: :green, rows: rows}, [2, 1, 0])
      assert cues == [[0, Sounds.chip_sound({:green, 4})], [2, Sounds.chip_sound({:green, 2})]]
    end

    test "no cue on other steps" do
      rows = [%{seat: 0, chips: [{:red, 1}]}]
      assert Sounds.replay(%{kind: :book, book: :red, rows: rows}, [0]) == []
      assert Sounds.replay(%{kind: :die, rows: []}, [0]) == []
    end

    test "the results stage carries the cues" do
      slide = %{kind: :book, book: :purple, set: 1, rows: [%{seat: 0, chips: [{:purple, 1}]}]}

      html =
        render_component(&QuacksWeb.TileRevealComponents.results_stage/1,
          rows: [%{seat: 0, why: [], got: [{:vp, 1}], none: false, lead: false}],
          slide: slide,
          index: 2,
          names: %{0 => "Ann"}
        )

      [cue] = query(html, "#stage-sound-2[phx-hook=SoundReplay]") |> Enum.to_list()

      assert Jason.decode!(LazyHTML.attribute(cue, "data-cues") |> hd()) ==
               [[0, Sounds.chip_sound({:purple, 1})]]
    end
  end

  describe "the page" do
    setup do
      {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, %{fortune: false})
      %{id: id}
    end

    test "<body> lists the sound files", %{id: id} do
      html = browser("solo-#{id}") |> get(~p"/g/#{id}") |> html_response(200)

      [sounds] =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("body")
        |> LazyHTML.attribute("data-sounds")

      assert Map.keys(Jason.decode!(sounds)) == Sounds.files()
    end

    test "the menu has the Sound row, client only", %{id: id} do
      {:ok, view, _html} = live(browser("solo-#{id}"), ~p"/g/#{id}")
      assert has_element?(view, "#sound-settings[phx-hook=SoundSettings][phx-update=ignore]")
      assert has_element?(view, "#sound-settings-on-on[checked]")
      assert has_element?(view, "#sound-settings-volume-0\\.7[checked]")
    end

    test "your drawn chip carries its sound", %{id: id} do
      {:ok, view, _html} = live(browser("solo-#{id}"), ~p"/g/#{id}")
      view |> element("button[data-slot=draw]") |> render_click()
      [chip] = view |> render() |> query("#pot-0-lg [data-role=pot-chip]") |> Enum.to_list()
      [sound] = LazyHTML.attribute(chip, "data-sound")
      assert sound in (Sounds.files() ++ Sounds.synths())
    end
  end
end
