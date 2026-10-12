defmodule QuacksWeb.Sounds do
  @moduledoc """
  The game's sounds (`docs/research/sounds.md`). This module is the manifest: the
  sound files in `priv/static/sounds/` (`name.m4a`, one name each) and the sound
  name for each moment. `assets/js/sound.js` plays them with Web Audio.

  A sound name is a file name (without `.m4a`) or a synth name: app.js makes a
  synth sound (`plop`, `bloop`, `chime`) with Web Audio, with no file.

  The chips: a sound per colour and value, `chip-<colour>-<value>.m4a`. A chip with
  no file of its own takes the nearest lower value of its colour that has one,
  else the synth `plop`. So a new chip file needs no code change: put it in the
  folder (the module recompiles when the folder changes). The same for
  `fortune.m4a` (else the synth `chime`).
  """

  alias Quacks.Rules.Chips

  @dir Path.expand("../../priv/static/sounds", __DIR__)

  @files @dir |> Path.join("*.m4a") |> Path.wildcard() |> Enum.map(&Path.basename(&1, ".m4a"))
  for name <- @files, do: @external_resource(Path.join(@dir, name <> ".m4a"))

  @doc false
  def __mix_recompile__?, do: on_disk() != @files

  defp on_disk,
    do: @dir |> Path.join("*.m4a") |> Path.wildcard() |> Enum.map(&Path.basename(&1, ".m4a"))

  # Every chip of the game, in the board's colour order (`Chips.order/0`).
  @chips for colour <- Chips.order(),
             value <-
               %{white: [1, 2, 3], orange: [1, 6], purple: [1], black: [1], locoweed: [1]}
               |> Map.get(colour, [1, 2, 4]),
             do: {colour, value}

  @synths ~w(plop bloop chime)

  @doc "The sound files (names without `.m4a`), sorted."
  @spec files() :: [String.t()]
  def files, do: Enum.sort(@files)

  @doc "The synth sounds of app.js (no file)."
  @spec synths() :: [String.t()]
  def synths, do: @synths

  @doc "Every chip of the game (`{colour, value}`), for the gallery's Sounds story."
  @spec chips() :: [Chips.chip()]
  def chips, do: @chips

  @doc """
  The gallery's chips: every chip of the game, and every other chip file
  (`chip-<colour>-<value>.m4a`, e.g. a locoweed book's value), in board order.
  """
  @spec gallery_chips() :: [{atom, integer}]
  def gallery_chips do
    colours = Map.new(Chips.order(), &{to_string(&1), &1})

    files =
      for "chip-" <> rest <- @files,
          [colour, value] <- [String.split(rest, "-")],
          Map.has_key?(colours, colour),
          {v, ""} <- [Integer.parse(value)],
          do: {colours[colour], v}

    (@chips ++ files) |> Enum.uniq() |> Enum.sort_by(&Chips.sort_key/1)
  end

  @doc """
  The `data-sounds` value on `<body>`: JSON of name => the file's (digested) path.
  """
  @spec manifest() :: String.t()
  def manifest do
    @files
    |> Map.new(&{&1, QuacksWeb.Endpoint.static_path("/sounds/#{&1}.m4a")})
    |> Jason.encode!()
  end

  @doc """
  The sound name of a chip: its own file, else the nearest lower value of its
  colour with a file, else the synth `plop`. `files`: the sound files (tests).

      iex> QuacksWeb.Sounds.chip_sound({:black, 1}) in ["chip-black-1", "plop"]
      true
  """
  @spec chip_sound(Chips.chip() | {atom, term}, [String.t()]) :: String.t()
  def chip_sound({colour, value}, files \\ @files) do
    prefix = "chip-#{colour}-"

    lower =
      for name <- files,
          String.starts_with?(name, prefix),
          {v, ""} <- [Integer.parse(String.replace_prefix(name, prefix, ""))],
          is_integer(value) and v <= value,
          do: {v, name}

    case Enum.max_by(lower, &elem(&1, 0), fn -> nil end) do
      {_v, name} -> name
      nil -> "plop"
    end
  end

  @doc """
  Round 44 (Nick): the sound of a chip that lands in the pot `moved` spaces on
  from the chip before it. Locoweed has one value, so its sound goes by how far it
  moved (`chip-locoweed-1` to `-6`, more is 6); every other chip by its value
  (`chip_sound/2`).

      iex> QuacksWeb.Sounds.pot_sound({:locoweed, 1}, 9, ["chip-locoweed-1", "chip-locoweed-6"])
      "chip-locoweed-6"
  """
  @spec pot_sound(Chips.chip(), integer | nil, [String.t()]) :: String.t()
  def pot_sound(chip, moved, files \\ @files)

  def pot_sound({:locoweed, _}, moved, files) when is_integer(moved),
    do: chip_sound({:locoweed, moved |> max(1) |> min(6)}, files)

  def pot_sound(chip, _moved, files), do: chip_sound(chip, files)

  @doc "The fortune teller's new card: `fortune.m4a`, else the synth `chime`."
  @spec fortune_sound() :: String.t()
  def fortune_sound, do: if("fortune" in @files, do: "fortune", else: "chime")

  @doc """
  The scoring replay: on the black, green and purple book steps each seat's row
  plays its colour's chip sound when its result shows. `rows` are the step's rows
  (`%{seat, chips}`), `seats` the seats in the stage's row order. A row with no
  counted chip plays nothing. Gives `[[row_index, sound], ...]`; other steps `[]`.
  """
  @spec replay(map, [integer]) :: [[integer | String.t()]]
  def replay(%{kind: :book, book: colour, rows: rows}, seats)
      when colour in [:black, :green, :purple] do
    for {seat, i} <- Enum.with_index(seats),
        %{chips: [_ | _] = chips} <- [Enum.find(rows, &(&1.seat == seat))],
        do: [i, chip_sound(Enum.find(chips, hd(chips), &(elem(&1, 0) == colour)))]
  end

  def replay(_slide, _seats), do: []
end
