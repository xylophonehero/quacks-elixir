defmodule Codex.AI.Determinize do
  @moduledoc """
  A full `%Codex.Game{}` from a bot's fair view (`Codex.Game.bot_view/2`), with
  the hidden cards dealt at random (`docs/research/codex-bot.md` §4.2.3). A
  search can then play actions on it with the engine.

  - The bot's own deck: its starting deck and the codex cards it teched, less
    the cards it sees (hand, discard pile, workers, in play, trash), shuffled.
  - The other side's codex: the codex cards it has not been seen to have,
    as many as its codex count. Its workers: first its starting workers (plain
    worker cards). Its hand, deck, discard pile and hired workers: the rest of
    its starting deck and codex, less the cards in play and in the trash,
    dealt by the zone counts.

  The new cards get ids from #{100_000} up, so they never take the id of a
  hidden real card. Only `Table.Kit.Rng` gives the randomness: the same view
  and rng give the same game.
  """

  alias Codex.{Cards, Game}
  alias Table.Kit.Rng

  @first_id 100_000
  @start_workers %{0 => 4, 1 => 5}
  @hidden [:hand, :deck, :discard, :workers]

  @doc "A sampled game for the bot in `me` from `view`, and the next rng."
  @spec sample(map, 0 | 1, Rng.t()) :: {Game.t(), Rng.t()}
  def sample(view, me, rng) do
    g = Codex.Bot.Plan.game_of(view)
    g = %{g | rng: Rng.fork(rng, 3)}
    {g, rng} = own_deck(g, view, me, rng)
    {g, rng} = other_side(g, view, 1 - me, rng)
    {g, rng}
  end

  defp own_deck(g, view, me, rng) do
    side = view.sides[me]
    teched = minus(codex_pool(side), slugs(g, side.zones.codex))
    pool = minus(Cards.starter(side.starter) ++ teched, seen(g, me))
    {deck, rng} = Rng.shuffle(pool, rng)
    {deal(g, me, :deck, Enum.take(deck, count(side.zones.deck))), rng}
  end

  defp other_side(g, view, s, rng) do
    zones = view.sides[s].zones
    seen = seen(g, s)
    codex_left = minus(codex_pool(view.sides[s]), seen)
    {codex_left, rng} = Rng.shuffle(codex_left, rng)
    {codex, teched} = Enum.split(codex_left, count(zones.codex))
    rest = minus(Cards.starter(view.sides[s].starter), seen) ++ teched
    {rest, rng} = Rng.shuffle(rest, rng)
    g = deal(g, s, :codex, codex)
    # The starting workers are plain worker cards.
    plain = min(count(zones.workers), @start_workers[s])
    g = deal(g, s, :workers, List.duplicate("worker", plain))
    zones = %{zones | workers: count(zones.workers) - plain}

    {g, _} =
      Enum.reduce(@hidden, {g, rest}, fn zone, {g, left} ->
        {take, left} = Enum.split(left, count(zones[zone]))
        {deal(g, s, zone, take), left}
      end)

    {g, rng}
  end

  defp codex_pool(side),
    do: for(sp <- side.specs, slug <- Cards.codex(sp), c <- [slug, slug], do: c)

  # The slugs of the cards of side `s` that the view shows outside its codex
  # (not its heroes and not tokens).
  defp seen(g, s) do
    codex = MapSet.new(g.sides[s].zones.codex)

    for {id, c} <- g.cards,
        c.seat == s,
        not MapSet.member?(codex, id),
        Cards.fetch!(c.card).zone in ["deck", "codex"],
        do: c.card
  end

  defp slugs(g, ids), do: Enum.map(ids, &g.cards[&1].card)

  # `list` without one copy of each slug of `remove`.
  defp minus(list, remove), do: list -- remove

  defp count(n) when is_integer(n), do: n
  defp count(list), do: length(list)

  # New cards of `slugs` on top of zone `zone` of side `s`.
  defp deal(g, _s, _zone, []), do: g

  defp deal(g, s, zone, slugs) do
    start = max(@first_id, (g.cards |> Map.keys() |> Enum.max(fn -> 0 end)) + 1)
    ids = Enum.to_list(start..(start + length(slugs) - 1))

    cards =
      Enum.zip(ids, slugs)
      |> Enum.reduce(g.cards, fn {id, slug}, acc ->
        card = Game.new_card(id, slug, s)
        Map.put(acc, id, if(zone == :workers, do: %{card | face_down: true}, else: card))
      end)

    g = %{g | cards: cards}
    update_in(g.sides[s].zones[zone], &(ids ++ &1))
  end
end
