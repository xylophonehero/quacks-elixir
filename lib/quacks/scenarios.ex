defmodule Quacks.Scenarios do
  @moduledoc """
  Scenarios (dev and test only, `/dev/scenarios`): one real game per rules item that
  plays to the moment where the item acts, in steps you can walk through on the real
  game page.

  `all/0` lists one entry per item, from the rules data: every Fortune Teller card
  (`Quacks.Rules.Fortune`), every ingredient book (`Quacks.Rules.Books`), every
  Alchemists patient (`Quacks.Rules.Alchemists`), every herb witch
  (`Quacks.Rules.Witches`) and a few other rules. Most entries use the generic
  builder of their kind (`Quacks.Scenarios.Builders`); a hand-written entry
  (`hand: true`) adds its own choices and stricter checks.

  `build/1` plays the scenario (`Quacks.Scenarios.Script`): a seeded
  `Quacks.Session`, every action through `Quacks.Game.apply/3`, steps marked on the
  way. `bundle/2` turns it into a replay bundle for
  `Quacks.GameServer.start_from_bundle/2`, so the game runs in the real
  `GameServer` and `GameLive` (the `/debug/replay` path).

  To add a hand-written scenario: add its options to `hand/0` (see the builders for
  `me:`, `others:`, `ready:` and `checks:`). The test
  `test/quacks_web/live/scenarios_test.exs` runs every entry.
  """

  alias Quacks.Game
  alias Quacks.Rules.{Alchemists, Books, Fortune}
  alias Quacks.Rules.Witches, as: WitchCards
  alias Quacks.Scenarios.{Builders, Script}

  @kinds [
    {"card", "Fortune Teller cards"},
    {"chip", "Ingredient books"},
    {"patient", "Alchemists patients"},
    {"witch", "Herb witches"},
    {"rule", "Other rules"}
  ]

  @typedoc """
  One scenario: `kind` and `id` (its URL, `/dev/scenarios/<kind>/<id>`), `title`,
  `group` (a heading on the index), `hand` (hand-written) and `build` (the script).
  """
  @type entry :: %{
          kind: String.t(),
          id: String.t(),
          title: String.t(),
          group: String.t(),
          hand: boolean,
          build: (-> {:ok, Script.t()} | {:error, term})
        }

  @doc "The kinds, in index order: `{kind, heading}`."
  @spec kinds() :: [{String.t(), String.t()}]
  def kinds, do: @kinds

  @doc "Every scenario, in index order."
  @spec all() :: [entry]
  def all, do: cards() ++ chips() ++ patients() ++ witches() ++ rules()

  @doc "The scenario at `kind`/`id`, or nil."
  @spec get(String.t(), String.t()) :: entry | nil
  def get(kind, id), do: Enum.find(all(), &(&1.kind == kind and &1.id == id))

  @doc "The URL path of a scenario."
  @spec path(entry) :: String.t()
  def path(%{kind: kind, id: id}), do: "/dev/scenarios/#{kind}/#{id}"

  @doc "The key of a scenario, `kind/id` (test tags, snapshot folders)."
  @spec key(entry) :: String.t()
  def key(%{kind: kind, id: id}), do: "#{kind}/#{id}"

  @doc "The scenarios before and after `entry` of the same kind: `{prev, next}` (nil at the ends)."
  @spec neighbours(entry) :: {entry | nil, entry | nil}
  def neighbours(entry) do
    same = Enum.filter(all(), &(&1.kind == entry.kind))
    i = Enum.find_index(same, &(&1.id == entry.id))
    {if(i > 0, do: Enum.at(same, i - 1)), Enum.at(same, i + 1)}
  end

  @doc "Play the scenario: `{:ok, script}` or `{:error, reason}` (no seed reached its goal)."
  @spec build(entry) :: {:ok, Script.t()} | {:error, term}
  def build(%{build: build}), do: build.()

  @doc """
  The replay bundle of a built scenario, with the steps for the step bar under
  `"scenario"` (`key`, `title`, `steps` as `%{label, at, note}`, `prev`, `next`).
  """
  @spec bundle(entry, Script.t()) :: map
  def bundle(entry, script) do
    {prev, next} = neighbours(entry)

    script
    |> Script.bundle()
    |> Map.put(:scenario, %{
      key: key(entry),
      title: entry.title,
      index: "/dev/scenarios",
      prev: prev && path(prev),
      next: next && path(next),
      steps: Enum.map(script.steps, &Map.take(&1, [:label, :at, :note]))
    })
  end

  # -- the catalog ----------------------------------------------------------------------

  defp cards do
    for %{id: id, name: name, colour: colour} <- Fortune.all() do
      key = "card/#{id}"

      entry("card", "#{id}", "#{String.upcase("#{id}")} #{name}", "#{colour} cards", fn ->
        Builders.card(id, hand(key))
      end)
    end
  end

  defp chips do
    for {colour, set} = book <- Books.keys() do
      key = "chip/#{colour}/#{set}"
      %{name: name} = Books.get(book)

      entry("chip", "#{colour}/#{set}", "#{name} #{roman(set)}", "#{colour}", fn ->
        Builders.chip(book, hand(key))
      end)
    end
  end

  defp patients do
    for id <- Alchemists.patients() do
      entry("patient", "#{id}", Alchemists.get(id).name, "patients", fn ->
        Builders.patient(id, hand("patient/#{id}"))
      end)
    end
  end

  defp witches do
    for colour <- [:silver, :copper, :gold], id <- WitchCards.ids(colour) do
      %{title: title} = WitchCards.card(id)
      key = "witch/#{colour}/#{id}"

      entry("witch", "#{colour}/#{id}", "#{String.upcase("#{id}")} #{title}", "#{colour}", fn ->
        Builders.witch(id, hand(key))
      end)
    end
  end

  defp rules do
    [
      entry("rule", "tube9", "Round 9: the test tube (reverse pot side)", "pot", fn ->
        Builders.tube9(hand("rule/tube9"))
      end)
    ]
  end

  defp entry(kind, id, title, group, build) do
    %{
      kind: kind,
      id: id,
      title: title,
      group: group,
      hand: Map.has_key?(hand(), "#{kind}/#{id}"),
      build: build
    }
  end

  defp hand(key), do: Map.get(hand(), key, [])

  # -- hand-written scenarios -------------------------------------------------------------

  @doc false
  # The hand-written scenarios: builder options per key. See `Quacks.Scenarios.Builders`.
  def hand do
    %{
      "card/p12" => take_a_chance(),
      "card/p13" => flea_market(),
      "card/p6" => boomberry_cleanse(),
      "chip/blue/1" => crow_skull(),
      "chip/yellow/1" => mandrake(),
      "chip/purple/5" => ghosts_breath_v(),
      "chip/black/1" => black_book(),
      "chip/green/1" => green_book(),
      "witch/gold/g1" => gold_witch_g1(),
      "rule/tube9" => []
    }
  end

  defp take_a_chance do
    [
      # A tap on the card shows a row per seat: the face and what it gave.
      sees: %{"reveal" => ["#card-tap"]},
      taps: %{
        "reveal" => [
          {"#card-tap", for(seat <- 0..2, do: "#card-stage-2-row-#{seat} [data-role=reveal-die]")}
        ]
      },
      checks: %{
        "reveal" => fn g ->
          rolled = for {seat, {:fortune, :p12, _face}} <- this_round(g), do: seat
          Enum.sort(rolled) == g.seats or "not every seat rolled the die: #{inspect(rolled)}"
        end
      }
    ]
  end

  defp flea_market do
    [
      # Your 4 chips and everyone's rows are on show while you choose.
      sees: %{"reveal" => ["#card-stage-2-row-0"]},
      # You trade a chip up (a seed where you can); the bots skip.
      ready: %{
        resolve: fn g ->
          Enum.any?(Game.legal_actions(g, 0), &match?({:fortune, {:upgrade, _}}, &1))
        end
      },
      me: fn _g, legal -> Enum.find(legal, &match?({:fortune, {:upgrade, _}}, &1)) end,
      others: fn _g, _seat, legal -> if {:fortune, :skip} in legal, do: {:fortune, :skip} end,
      checks: %{
        "reveal" => fn g ->
          length(Game.player(g, 0).pending) == 4 or "you do not see 4 chips"
        end,
        "resolve" => fn g ->
          Enum.any?(this_round(g), &match?({0, {:fortune, :p13, {:upgrade, _}}}, &1)) and
            Game.player(g, 0).pending == []
        end
      }
    ]
  end

  defp boomberry_cleanse do
    [
      sees: %{"reveal" => ["[data-role=choice-grid]"]},
      # You take the white 1 out; bot 1 takes the 4 VP.
      me: fn _g, legal ->
        if {:fortune, :remove_white} in legal, do: {:fortune, :remove_white}
      end,
      others: fn _g, seat, legal ->
        if seat == 1 and {:fortune, :vp} in legal, do: {:fortune, :vp}
      end,
      checks: %{
        "resolve" => fn g ->
          log = this_round(g)

          ({0, {:fortune, :p6, :remove_white}} in log and {1, {:fortune, :p6, {:vp, 4}}} in log) or
            "not: you removed a white 1, bot 1 took 4 VP"
        end
      }
    ]
  end

  defp crow_skull do
    [
      # The offer is in the bar: the crow skull, then the drawn chip.
      sees: %{"placed" => ["footer [data-role=bar-blue] [data-pool-chip]"]},
      checks: %{
        "placed" => fn g ->
          p = Game.player(g, 0)

          (p.phase == :blue_choice and length(p.pending) == 1) or
            "no crow skull offer of 1 chip"
        end,
        "chosen" => fn g -> Game.player(g, 0).pending == [] end
      }
    ]
  end

  defp mandrake do
    [
      sees: %{"placed" => ["footer #bar-pick-yellow_choice"]},
      # The mandrake lands right after a white chip; you put the white back.
      ready: fn g -> Game.phase(g, 0) == :yellow_choice end,
      me: fn _g, legal -> if :return_white in legal, do: :return_white end,
      checks: %{
        "placed" => fn g -> Game.phase(g, 0) == :yellow_choice end,
        "chosen" => fn g ->
          match?([{:yellow, 1} | _], Game.pot_chips(g, 0)) and
            Enum.any?(this_round(g), &match?({0, {:returned, {:white, _}}}, &1))
        end
      }
    ]
  end

  defp ghosts_breath_v do
    [
      # The buy needs a rare draw: seed 73 since round 41 (the bots keep more whites
      # out of the pot).
      tries: 100,
      sees: %{"book choice" => ["[data-role=purple-buy]"]},
      # The purple chips' spaces pay for a chip: you buy the first offer.
      me: fn g, legal ->
        if Game.phase(g, 0) == :chip_choice,
          do: Enum.find(legal, &match?({:chip, {:buy, [_ | _]}}, &1))
      end,
      checks: %{
        "book choice" => fn g ->
          Enum.any?(Game.legal_actions(g, 0), &match?({:chip, {:buy, _}}, &1)) or
            "no Ghost's breath V buy"
        end
      }
    ]
  end

  defp black_book do
    [
      checks: %{
        "results" => fn g ->
          Enum.any?(this_round(g), &match?({0, {:black, _}}, &1)) or "black book I paid nothing"
        end
      }
    ]
  end

  defp green_book do
    [
      checks: %{
        "results" => fn g ->
          Enum.any?(this_round(g), &match?({0, {:green_rubies, _}}, &1)) or "no green rubies"
        end
      }
    ]
  end

  defp gold_witch_g1 do
    [
      sees: %{"call" => ["dialog#decision-witch_choice"]},
      checks: %{
        "called" => fn g ->
          Enum.any?(g.log, &match?({0, {:witch, :g1, {:vp, n}}} when n > 0, &1)) or
            "G1 gave no VP"
        end
      }
    ]
  end

  # -- test results ------------------------------------------------------------------

  @doc """
  Where the scenario test writes its results (`record/2`) and step snapshots:
  `tmp/scenarios` under the project.
  """
  @spec dir() :: String.t()
  def dir, do: Path.join(File.cwd!(), "tmp/scenarios")

  @doc """
  Write the last test result of `entry`: `:pass` or `{:fail, step_label, message}`.
  The index (`/dev/scenarios`) reads it back with `results/0`.
  """
  @spec record(entry, :pass | {:fail, String.t(), String.t()}) :: :ok
  def record(entry, result) do
    data =
      case result do
        :pass -> %{status: "pass"}
        {:fail, step, message} -> %{status: "fail", step: step, message: message}
      end

    file = Path.join([dir(), "results", String.replace(key(entry), "/", "-") <> ".json"])
    File.mkdir_p!(Path.dirname(file))
    at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    File.write!(file, Jason.encode!(Map.put(data, :at, at)))
  end

  @doc "The last test result per scenario key (`kind/id`), from `record/2`'s files."
  @spec results() :: %{String.t() => map}
  def results do
    keys = Map.new(all(), &{String.replace(key(&1), "/", "-"), key(&1)})

    for file <- Path.wildcard(Path.join([dir(), "results", "*.json"])),
        key = keys[Path.basename(file, ".json")],
        {:ok, data} <- [file |> File.read!() |> Jason.decode()],
        into: %{},
        do: {key, data}
  end

  # The log of the round so far (newest first), up to the last round's end.
  @doc false
  def this_round(g), do: Enum.take_while(g.log, &(not match?({:round_end, _}, &1)))

  defp roman(n), do: Enum.at(~w(I II III IV V VI), n - 1)
end
