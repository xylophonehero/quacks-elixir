defmodule Quacks.GoldenBundlesTest do
  @moduledoc """
  G1 (architecture review §5.4): committed replay bundles load to the same game.

  Each file in `test/fixtures/bundles/` is a `Quacks.Session.bundle/1` (JSON). Five
  were played by bots on the code of 2026-10-16; `bug_89.json` is the bundle of the
  real bug report #89 (version 1, the player names removed). `digests.exs` holds,
  per bundle, the final `Game.score/1`, round, phase, log length and an
  `:erlang.phash2/1` of each seat's bag and pot. The test replays each bundle with
  `Session.from_bundle/1` and compares the digest.

  Unlike a test that replays twice on today's code, this one fails when a change
  gives other draws for the same seed and actions (#83), or when an old bundle no
  longer loads (#80). If a change is meant to do that, record again with
  `GOLDEN_RECORD=1 mix test test/quacks/golden_bundles_test.exs` and say so in the
  PR (the bot bundles are played again; `bug_89.json` stays).
  """
  use ExUnit.Case, async: true

  alias Quacks.{Game, Golden, Session}
  alias Quacks.Rules.BookPresets

  @dir Path.expand("../fixtures/bundles", __DIR__)
  @digests Path.join(@dir, "digests.exs")

  # The bot games: name -> {seed, players, Session options}.
  @played [
    solo_base: {{101, 1, 1}, 1, []},
    four_limited: {{102, 2, 2}, 4, [rules: %{supply: :limited}]},
    herb_witches_back: {{103, 3, 3}, 3, [expansions: [:herb_witches], rules: %{pot_side: :back}]},
    alchemists_picks:
      {{104, 4, 4}, 2, [expansions: [:alchemists], patients: %{0 => :witch_hump, 1 => :random}]},
    eight_both_sets_5_6:
      {{105, 5, 5}, 8,
       [
         expansions: [:herb_witches, :alchemists],
         sets: Map.merge(BookPresets.get(:set5).sets, %{blue: 6, red: 6, purple: 6})
       ]}
  ]

  setup_all do
    Golden.load_atoms()
  end

  test "every committed bundle replays to its recorded digest" do
    if Golden.record?(), do: record()

    want = Golden.read_term!(@digests)
    files = @dir |> Path.join("*.json") |> Path.wildcard() |> Enum.sort()
    assert Enum.map(files, &name/1) == want |> Map.keys() |> Enum.sort()

    for file <- files do
      assert {:ok, session} = file |> File.read!() |> Jason.decode!() |> Session.from_bundle()
      assert {name(file), digest(session.game)} == {name(file), Map.fetch!(want, name(file))}
    end
  end

  test "the bug report bundle is version 1 and was a 4-player Alchemists game" do
    bundle = @dir |> Path.join("bug_89.json") |> File.read!() |> Jason.decode!()
    assert %{"version" => 1, "players" => 4, "opts" => %{"expansions" => ["alchemists"]}} = bundle
    assert {:ok, %Session{game: %Game{round: round}}} = Session.from_bundle(bundle)
    assert round == 5
  end

  defp name(file), do: file |> Path.basename(".json") |> String.to_atom()

  defp digest(%Game{} = game) do
    %{
      score: Game.score(game),
      round: game.round,
      phase: game.phase,
      log: length(game.log),
      bags: Map.new(game.seats, &{&1, :erlang.phash2(Game.player(game, &1).bag)}),
      pots: Map.new(game.seats, &{&1, :erlang.phash2(Game.pot_chips(game, &1))})
    }
  end

  # Play the bot bundles again and write every digest.
  defp record do
    for {name, {seed, players, opts}} <- @played do
      session = seed |> Session.new(players, opts) |> Golden.play()
      true = Game.over?(session.game)
      json = Jason.encode_to_iodata!(Session.bundle(session), pretty: true)
      File.write!(Path.join(@dir, "#{name}.json"), [json, "\n"])
    end

    digests =
      for file <- Path.wildcard(Path.join(@dir, "*.json")), into: %{} do
        {:ok, session} = file |> File.read!() |> Jason.decode!() |> Session.from_bundle()
        {name(file), digest(session.game)}
      end

    Golden.write_term!(@digests, digests)
  end
end
