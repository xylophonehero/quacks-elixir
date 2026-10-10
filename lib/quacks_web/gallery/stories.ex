defmodule QuacksWeb.Gallery.Stories do
  @moduledoc """
  The gallery's stories (`/dev/gallery`, `QuacksWeb.GalleryLive`), as in Storybook:
  a story is one thing to look at, with **args** (typed values with a range) that
  the viewer's controls change, and named **presets** (a set of args).

  `catalog/0` lists the groups, in sidebar order:

  - the components of `QuacksWeb.Gallery.Fixtures.catalog/0`. A story with args
    (`arg_stories/1`) takes the place of the variants that only differ by its
    args (`claims`; their old URLs go to the story with those args). Every other
    variant is a story with no args, so a new variant shows up by itself.
  - "Screens": the whole game page for a phase (`QuacksWeb.GameLive.preview/3`).
  - one group per scenario kind (`Quacks.Scenarios`): a story per scenario, whose
    steps are the `step` arg, drawn as a full screen from the game at that step.

  The args live in the URL (`?players=8`, only the values that differ from the
  default), so a link reproduces the view. `args/2` reads them back (an int is
  clamped to its range; a bad value is the default).
  """

  alias Quacks.Game
  alias Quacks.Scenarios
  alias Quacks.Scenarios.Script
  alias QuacksWeb.Gallery.Fixtures

  @typedoc """
  One arg: `name` (its URL key), `type` (`:int` with `min`/`max`, `:bool`, or
  `:enum` with `values`), `default`, and optional `labels` (value => text).
  """
  @type arg :: %{
          required(:name) => String.t(),
          required(:type) => :int | :bool | :enum,
          required(:default) => term,
          optional(:min) => integer,
          optional(:max) => integer,
          optional(:values) => [String.t()],
          optional(:labels) => %{term => String.t()}
        }
  @typedoc """
  One story: `group` and `id` (its URL, `/dev/gallery/<group>/<id>`), `title`,
  `note` (the component it shows), `height` (frame px, or `:screen`: a phone's or
  a desktop's height for the width), `args` (a list, or a function of the raw
  URL params for args that depend on others), `presets` (`{id, title, args}`),
  `claims` (old variant ids => their args), `build` (args => the frame's assigns)
  and `live` (args => the path of the live game, scenarios only).
  """
  @type story :: %{
          group: String.t(),
          id: String.t(),
          title: String.t(),
          note: String.t(),
          height: pos_integer | :screen,
          args: [arg] | (map -> [arg]),
          presets: [{String.t(), String.t(), map}],
          claims: %{String.t() => map},
          build: (map -> map),
          live: (map -> String.t()) | nil
        }
  @type group :: %{id: String.t(), title: String.t(), stories: [story]}

  @doc "Every group with its stories, in sidebar order."
  @spec catalog() :: [group]
  def catalog do
    components =
      for c <- Fixtures.catalog() do
        own = arg_stories(c.id)
        claimed = own |> Enum.flat_map(&Map.keys(&1.claims)) |> MapSet.new()

        plain =
          for v <- c.variants, v.id not in claimed do
            story(c.id, v.id, v.title, c.note, c.height, [], fn _args -> v.build.() end)
          end

        %{
          id: c.id,
          title: c.title,
          stories:
            Enum.map(own, &Map.merge(&1, %{group: c.id, note: c.note, height: c.height})) ++ plain
        }
      end

    components ++ [%{id: "screens", title: "Screens", stories: screens()}] ++ scenario_groups()
  end

  @doc "The story `id` of group `group`, or nil."
  @spec story(String.t(), String.t()) :: story | nil
  def story(group, id) do
    with %{stories: stories} <- Enum.find(catalog(), &(&1.id == group)),
         do: Enum.find(stories, &(&1.id == id))
  end

  @doc "The story and args that took the place of an old variant id, or nil."
  @spec claimed(String.t(), String.t()) :: {story, map} | nil
  def claimed(group, variant) do
    with %{stories: stories} <- Enum.find(catalog(), &(&1.id == group)) do
      Enum.find_value(stories, fn s -> if a = s.claims[variant], do: {s, a} end)
    end
  end

  @doc "The story's args for the raw URL params `params`."
  @spec specs(story, map) :: [arg]
  def specs(%{args: args}, params) when is_function(args), do: args.(params)
  def specs(%{args: args}, _params), do: args

  @doc "The story's arg values from the URL params: every arg, parsed, clamped, or its default."
  @spec args(story, map) :: map
  def args(story, params) do
    Map.new(specs(story, params), &{&1.name, parse(&1, params[&1.name])})
  end

  @doc "The URL params for `args`: only the values that differ from the default."
  @spec query(story, map) :: %{String.t() => String.t()}
  def query(story, args) do
    for spec <- specs(story, stringify(args)),
        Map.has_key?(args, spec.name),
        value = parse(spec, to_string(args[spec.name])),
        value != spec.default,
        into: %{},
        do: {spec.name, to_string(value)}
  end

  @doc "The frame's assigns for `args`: `{:ok, assigns}`, or `{:error, message}` when these args reach no such state."
  @spec build(story, map) :: {:ok, map} | {:error, String.t()}
  def build(story, args) do
    {:ok, story.build.(args)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp stringify(args), do: Map.new(args, fn {k, v} -> {k, to_string(v)} end)

  defp parse(%{type: :int, min: min, max: max, default: d}, value) do
    case Integer.parse(to_string(value)) do
      {n, ""} -> n |> max(min) |> min(max)
      _bad -> d
    end
  end

  defp parse(%{type: :bool, default: d}, value) do
    case value do
      v when v in ["true", "1", "on"] -> true
      v when v in ["false", "0"] -> false
      _ -> d
    end
  end

  defp parse(%{type: :enum, values: values, default: d}, value),
    do: if(value in values, do: value, else: d)

  # -- arg constructors -------------------------------------------------------------------

  defp int(name, min, max, default, labels \\ nil),
    do: %{name: name, type: :int, min: min, max: max, default: default, labels: labels}

  defp bool(name, default \\ false), do: %{name: name, type: :bool, default: default}

  defp enum(name, values, default),
    do: %{name: name, type: :enum, values: values, default: default}

  defp story(group, id, title, note, height, args, build, extra \\ %{}) do
    Map.merge(
      %{
        group: group,
        id: id,
        title: title,
        note: note,
        height: height,
        args: args,
        presets: [],
        claims: %{},
        build: build,
        live: nil
      },
      extra
    )
  end

  # An arg story of a Fixtures component (group, note and height come from it).
  defp arg_story(id, title, args, build, extra),
    do: story(nil, id, title, nil, nil, args, build, extra)

  # -- the component stories with args -------------------------------------------------

  @results_steps [
    {"die", :die, "die"},
    {"black", :black, "black book"},
    {"green", :green, "green book"},
    {"purple", :purple, "purple book"},
    {"space", :space, "scoring space"}
  ]

  defp arg_stories("results") do
    round_args = [
      int("players", 2, 8, 5),
      bool("long_names"),
      int("exploded", 0, 7, 1),
      int("vp_digits", 1, 3, 1)
    ]

    steps =
      for {id, kind, label} <- @results_steps do
        claims =
          %{"5p-#{id}" => %{}}
          |> Map.merge(
            case id do
              "space" ->
                %{
                  "2p-space" => %{"players" => 2},
                  "8p-space" => %{"players" => 8, "long_names" => true}
                }

              "die" ->
                %{"8p-die" => %{"players" => 8, "long_names" => true}}

              _ ->
                %{}
            end
          )

        arg_story(
          "step-#{id}",
          "Results: #{label}",
          round_args,
          &Fixtures.results_story(kind, &1),
          %{
            claims: claims,
            presets: results_presets(id)
          }
        )
      end

    steps ++
      [
        arg_story(
          "recap-shop",
          "Recap: the shop",
          [int("players", 2, 8, 5), bool("long_names")],
          &Fixtures.recap_story(:shop, &1),
          %{claims: %{"recap-shop" => %{}}}
        ),
        arg_story(
          "recap-scored",
          "Recap: round scored",
          [int("players", 2, 8, 5), bool("long_names"), int("vp_digits", 1, 3, 1)],
          &Fixtures.recap_story(:standings, &1),
          %{
            claims: %{
              "recap-standings" => %{},
              "recap-2p" => %{"players" => 2},
              "recap-8p" => %{"players" => 8, "long_names" => true, "vp_digits" => 3}
            },
            presets: [
              {"2p", "2 players", %{"players" => 2}},
              {"8p-long", "8 long names, 3-digit VP",
               %{"players" => 8, "long_names" => true, "vp_digits" => 3}}
            ]
          }
        ),
        arg_story(
          "chance",
          "Take a Chance",
          [int("players", 2, 8, 5)],
          &Fixtures.chance_story/1,
          %{claims: %{"chance" => %{}}}
        )
      ]
  end

  defp arg_stories("pot") do
    [
      arg_story(
        "brew",
        "Brewing: the scoring ring",
        [int("chips", 0, 6, 6)],
        &Fixtures.pot_story/1,
        %{
          claims: %{"empty" => %{"chips" => 0}, "mid-brew" => %{}},
          presets: [{"empty", "Empty (nothing drawn)", %{"chips" => 0}}]
        }
      )
    ]
  end

  defp arg_stories("tiles") do
    [
      arg_story(
        "tiles",
        "Player tiles",
        [
          int("players", 1, 8, 5),
          enum("state", ~w(brewing stopped exploded shop done), "brewing"),
          bool("long_names"),
          int("vp_digits", 1, 3, 1),
          bool("bots")
        ],
        &Fixtures.tiles_story/1,
        %{
          claims: %{
            "1p" => %{"players" => 1},
            "2p" => %{"players" => 2},
            "5p" => %{},
            "8p" => %{"players" => 8, "long_names" => true},
            "exploded" => %{"players" => 4, "state" => "exploded"},
            "crown" => %{"players" => 4, "state" => "done"},
            "shop" => %{"state" => "shop"},
            "bots" => %{"players" => 3, "bots" => true, "vp_digits" => 3}
          },
          presets: [
            {"1p", "1 player", %{"players" => 1}},
            {"8p-long", "8 long names", %{"players" => 8, "long_names" => true}},
            {"4p-exploded", "4: one exploded, one stopped",
             %{"players" => 4, "state" => "exploded"}},
            {"4p-crown", "4: all done, the crown", %{"players" => 4, "state" => "done"}},
            {"3p-bots", "3 with bots, 3-digit VP",
             %{"players" => 3, "bots" => true, "vp_digits" => 3}}
          ]
        }
      )
    ]
  end

  defp arg_stories("bar") do
    [
      arg_story(
        "crow",
        "Crow skull",
        [int("chips", 1, 5, 4)],
        &Fixtures.crow_story/1,
        %{
          claims: %{"crow-1" => %{"chips" => 1}, "crow-4" => %{}, "crow-5" => %{"chips" => 5}},
          presets: [{"1", "1 chip", %{"chips" => 1}}, {"5", "5 chips (by hand)", %{"chips" => 5}}]
        }
      )
    ]
  end

  defp arg_stories("track") do
    [
      arg_story(
        "track",
        "Score / rat track",
        [int("players", 2, 8, 4), enum("spread", ~w(early tied above-50 big-gaps), "early")],
        &Fixtures.track_story/1,
        %{
          claims: %{
            "early" => %{},
            "tied" => %{"players" => 5, "spread" => "tied"},
            "above-50" => %{"spread" => "above-50"},
            "big-gaps" => %{"players" => 5, "spread" => "big-gaps"},
            "8p" => %{"players" => 8, "spread" => "big-gaps"}
          },
          presets: [
            {"tied", "Ties (5 players)", %{"players" => 5, "spread" => "tied"}},
            {"8p", "8 players, big gaps", %{"players" => 8, "spread" => "big-gaps"}}
          ]
        }
      )
    ]
  end

  defp arg_stories(_component), do: []

  # Purple needs seat 1's brew (it explodes with 2 players): no 2-player preset.
  defp results_presets(step) do
    [
      step != "purple" && {"2p", "2 players", %{"players" => 2}},
      {"8p-long", "8 long names, 3-digit VP",
       %{"players" => 8, "long_names" => true, "vp_digits" => 3}},
      {"3-exploded", "5 players, 3 exploded", %{"exploded" => 3}}
    ]
    |> Enum.filter(& &1)
  end

  # -- screens ----------------------------------------------------------------------------

  @screen_note "GameLive.render/1 from a fixture (GameLive.preview/3)"

  defp screens do
    names = bool("long_names")

    [
      screen("brewing", "Brewing", [int("players", 1, 8, 4), names], &Fixtures.brewing_screen/1,
        presets: [
          {"1p", "Solo", %{"players" => 1}},
          {"8p-long", "8 long names", %{"players" => 8, "long_names" => true}}
        ]
      ),
      screen(
        "choice",
        "A choice",
        [
          int("players", 1, 8, 2),
          enum("choice", ~w(crow mandrake chip_choice explosion), "crow"),
          names
        ],
        &Fixtures.choice_screen/1,
        presets: [
          {"mandrake", "Mandrake", %{"choice" => "mandrake"}},
          {"chip-choice", "Chip choice (green II)", %{"choice" => "chip_choice"}},
          {"explosion", "Exploded", %{"choice" => "explosion"}}
        ]
      ),
      screen(
        "evaluation",
        "Evaluation step",
        [
          int("players", 2, 8, 4),
          enum("step", Enum.map(@results_steps, &elem(&1, 0)), "die"),
          names,
          int("exploded", 0, 7, 1)
        ],
        &Fixtures.evaluation_screen/1,
        presets: [
          {"8p-space", "8 long names: scoring space",
           %{"players" => 8, "long_names" => true, "step" => "space"}}
        ]
      ),
      screen(
        "scored",
        "Round scored",
        [
          int("players", 2, 8, 4),
          enum("step", ~w(standings shop), "standings"),
          names,
          int("vp_digits", 1, 3, 1)
        ],
        &Fixtures.scored_screen/1,
        presets: [
          {"8p-long", "8 long names, 3-digit VP",
           %{"players" => 8, "long_names" => true, "vp_digits" => 3}}
        ]
      ),
      screen("shop", "Shop", [int("players", 1, 8, 4), names], &Fixtures.shop_screen/1),
      screen("over", "Game over", [int("players", 1, 8, 4), names], &Fixtures.over_screen/1)
    ]
  end

  defp screen(id, title, args, build, extra \\ []),
    do: story("screens", id, title, @screen_note, :screen, args, build, Map.new(extra))

  # -- scenarios --------------------------------------------------------------------------

  defp scenario_groups do
    entries = Scenarios.all()

    for {kind, heading} <- Scenarios.kinds() do
      %{
        id: "scenario-#{kind}",
        title: "Scenarios: #{heading}",
        stories: for(e <- entries, e.kind == kind, do: scenario_story(e))
      }
    end
  end

  @doc "The story id of a scenario (its id with `-` for `/`)."
  @spec scenario_id(Scenarios.entry()) :: String.t()
  def scenario_id(entry), do: String.replace(entry.id, "/", "-")

  defp scenario_story(entry) do
    default = Scenarios.players(entry)

    story(
      "scenario-#{entry.kind}",
      scenario_id(entry),
      entry.title,
      "Quacks.Scenarios #{Scenarios.key(entry)}",
      :screen,
      fn params ->
        players = parse(int("players", 2, 5, default), params["players"])
        steps = scenario_steps(entry, players)
        labels = steps |> Enum.with_index(1) |> Map.new(fn {s, i} -> {i, "#{i} · #{s.label}"} end)
        [int("step", 1, max(length(steps), 1), 1, labels), int("players", 2, 5, default)]
      end,
      fn args -> scenario_screen(entry, args) end,
      %{
        scenario: entry,
        live: fn args ->
          q = %{"step" => args["step"]}
          q = if args["players"] != default, do: Map.put(q, "players", args["players"]), else: q
          Scenarios.path(entry) <> "?" <> URI.encode_query(q)
        end
      }
    )
  end

  defp scenario_steps(entry, players) do
    case Scenarios.build(entry, players: players) do
      {:ok, script} -> script.steps
      {:error, _} -> []
    end
  end

  @doc false
  # A scenario step as a full screen: the game after the step's actions, the moments
  # of the rounds before (and this round's card once you drew) already seen.
  def scenario_screen(entry, %{"step" => i, "players" => players}) do
    case Scenarios.build(entry, players: players) do
      {:ok, script} ->
        step = Enum.at(script.steps, i - 1) || raise "no step #{i}"
        g = Script.game_at(script, step.at)
        names = Map.new(g.seats, &{&1, if(&1 == 0, do: "You", else: "Bot #{&1}")})

        %{
          view: :screen,
          game: g,
          note: step.note,
          preview: [names: names, bots: script.bots, seen: seen_before(g)]
        }

      {:error, reason} ->
        raise "the scenario did not build: #{inspect(reason)}"
    end
  end

  defp seen_before(%Game{round: r} = g) do
    drawn? = Game.player(g, 0).drawn != []
    %{recap: r - 1, results: r - 1, card: if(drawn?, do: r, else: r - 1)}
  end
end
