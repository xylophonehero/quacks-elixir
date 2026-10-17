defmodule Codex.Cards do
  @moduledoc """
  The Codex card definitions: plain data from the codexcarddb raw files
  (`priv/codex/<colour>.json`, `priv/codex/heroes.json`; research
  `docs/research/codex.md` §14), read at compile time.

  A card is found by its slug: the name in lower case, with each run of other
  characters as one `-` ("Star-Crossed Starlet" → `"star-crossed-starlet"`). The
  slug is also the name of its art file (`priv/static/images/codex/<slug>.webp`,
  made by `mix codex.cards`).

  Two records in the data have the same name (the two arts of Dancer and of Angry
  Dancer): the first one is kept. `"worker"` is not in the data: it is the
  face-down card of a starting worker.

      iex> Codex.Cards.get("timely-messenger").cost
      1
      iex> length(Codex.Cards.starter())
      10
      iex> length(Codex.Cards.codex("Bashing"))
      12
  """

  @files ~w(neutral red green blue black heroes)

  for file <- @files do
    @external_resource Path.join([__DIR__, "../../priv/codex", file <> ".json"])
  end

  @typedoc "One card definition."
  @type t :: %{
          slug: String.t(),
          name: String.t(),
          type: String.t(),
          subtype: String.t() | nil,
          subtypes: [String.t()],
          spec: String.t() | nil,
          color: String.t(),
          cost: non_neg_integer | nil,
          tech: non_neg_integer | nil,
          atk: non_neg_integer | nil,
          hp: non_neg_integer | nil,
          text: [String.t()],
          target: boolean,
          zone: String.t(),
          bands: [band] | nil
        }

  @typedoc "A hero's level band: from `level` on, `atk`/`hp` and the band's text."
  @type band :: %{
          level: pos_integer,
          atk: non_neg_integer,
          hp: non_neg_integer,
          text: [String.t()]
        }

  @doc "The slug of a card name."
  @spec slug(String.t()) :: String.t()
  def slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  slugify = fn name ->
    name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
  end

  text = fn rec, prefix ->
    for i <- 1..4, line = rec["#{prefix}_#{i}"], is_binary(line) and line != "", do: line
  end

  card = fn rec ->
    hero? = rec["type"] == "Hero"

    bands =
      if hero? do
        [
          %{level: 1, atk: rec["ATK_1"], hp: rec["HP_1"], text: text.(rec, "base_text")},
          %{
            level: rec["mid_level"],
            atk: rec["ATK_2"],
            hp: rec["HP_2"],
            text: text.(rec, "mid_text")
          },
          %{
            level: rec["max_level"],
            atk: rec["ATK_3"],
            hp: rec["HP_3"],
            text: text.(rec, "max_text")
          }
        ]
      end

    %{
      slug: slugify.(rec["name"]),
      name: rec["name"],
      type: rec["type"],
      subtype: rec["subtype"],
      subtypes: String.split(rec["subtype"] || "", ~r/[\s—-]+/, trim: true),
      spec: rec["spec"],
      color: rec["color"],
      cost: rec["cost"],
      tech: rec["tech_level"],
      atk: if(hero?, do: rec["ATK_1"], else: rec["ATK"]),
      hp: if(hero?, do: rec["HP_1"], else: rec["HP"]),
      text: text.(rec, "rules_text"),
      target: rec["target_icon"] == true,
      zone: rec["starting_zone"],
      bands: bands
    }
  end

  worker = %{
    slug: "worker",
    name: "Worker",
    type: "Worker",
    subtype: nil,
    subtypes: [],
    spec: nil,
    color: "Neutral",
    cost: nil,
    tech: nil,
    atk: nil,
    hp: nil,
    text: ["A starting worker. Gives 1 gold in each upkeep."],
    target: false,
    zone: "worker",
    bands: nil
  }

  records =
    for file <- @files,
        rec <-
          __DIR__ |> Path.join("../../priv/codex/#{file}.json") |> File.read!() |> JSON.decode!(),
        do: rec

  cards = Enum.uniq_by(Enum.map(records, card) ++ [worker], & &1.slug)

  @cards Map.new(cards, &{&1.slug, &1})
  @order Enum.map(cards, & &1.slug)

  @doc "Every card, in the order of the data files."
  @spec all() :: [t]
  def all, do: Enum.map(@order, &Map.fetch!(@cards, &1))

  @doc "The card with `slug`, or nil."
  @spec get(String.t()) :: t | nil
  def get(slug), do: Map.get(@cards, slug)

  @doc "The card with `slug`; raises when there is none."
  @spec fetch!(String.t()) :: t
  def fetch!(slug), do: Map.fetch!(@cards, slug)

  @doc ~s{The 10 slugs of a colour's starting deck (one copy each): "Neutral", "Red", "Green", "Blue", "Black".}
  @spec starter(String.t()) :: [String.t()]
  def starter(color \\ "Neutral"),
    do: for(c <- all(), c.zone == "deck", c.color == color, do: c.slug)

  @doc "The colours with a starting deck here."
  @spec colors() :: [String.t()]
  def colors, do: ~w(Neutral Red Green Blue Black)

  @doc "The specs of a colour (Neutral: Bashing, Finesse)."
  @spec specs(String.t()) :: [String.t()]
  def specs(color) do
    for(c <- all(), c.type == "Hero", c.color == color, uniq: true, do: c.spec)
  end

  @doc "The colour of a spec (its hero's colour)."
  @spec spec_color(String.t()) :: String.t()
  def spec_color(spec), do: fetch!(hero(spec)).color

  @doc "The 12 codex slugs of `spec` (the codex has 2 copies of each)."
  @spec codex(String.t()) :: [String.t()]
  def codex(spec), do: for(c <- all(), c.zone == "codex", c.spec == spec, do: c.slug)

  @doc "The slug of the hero of `spec`."
  @spec hero(String.t()) :: String.t()
  def hero(spec),
    do: Enum.find_value(all(), fn c -> c.type == "Hero" and c.spec == spec and c.slug end)

  @doc "True when the card is a hero."
  @spec hero?(String.t()) :: boolean
  def hero?(slug), do: match?(%{type: "Hero"}, get(slug))

  @doc "The max level of a hero (its last band), or nil."
  @spec max_level(String.t()) :: pos_integer | nil
  def max_level(slug) do
    case get(slug) do
      %{bands: [_, _, %{level: max}]} -> max
      _ -> nil
    end
  end

  @doc "The band of a hero at `level`: the last band whose level is at most `level`."
  @spec band(String.t(), pos_integer) :: band | nil
  def band(slug, level) do
    case get(slug) do
      %{bands: [_ | _] = bands} -> bands |> Enum.filter(&(&1.level <= level)) |> List.last()
      _ -> nil
    end
  end
end
