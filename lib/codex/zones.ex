defmodule Codex.Zones do
  @moduledoc """
  The zones of a `Codex.Game`: find a card, take it out of its zone, put it in
  another. Shared by the sandbox actions (`Codex.Game`) and the rules
  (`Codex.Rules`). Every move goes through `remove/2` and `insert/4`, so a card is
  always in exactly one zone (card conservation).

  A zone is `{seat, name}` or `:trash`. A location (`locate/2`) is a zone or
  `{seat, :patrol, slot}`.
  """

  @patrol_slots [:squad_leader, :elite, :scavenger, :technician, :lookout]
  @list_zones [:deck, :hand, :discard, :codex, :command, :workers, :in_play]

  @doc "The 5 patrol slots, left to right."
  def patrol_slots, do: @patrol_slots

  @doc "The list zones of a side (every zone but `patrol`)."
  def list_zones, do: @list_zones

  @doc """
  The zone of card `id`: `{seat, name}`, `{seat, :patrol, slot}` or `:trash`
  (nil when it is in no zone). Works on a game and on a view.
  """
  def locate(game, id), do: Enum.find_value(placements(game), fn {i, at} -> i == id && at end)

  @doc "Every card in a zone, as `{id, location}`. A view's decks are counts: left out."
  def placements(%{sides: sides, trash: trash}),
    do: Enum.map(trash, &{&1, :trash}) ++ Enum.flat_map(sides, &side_placements/1)

  defp side_placements({seat, side}), do: Enum.flat_map(side.zones, &zone_placements(seat, &1))

  defp zone_placements(seat, {:patrol, slots}),
    do: for({slot, id} <- slots, id, do: {id, {seat, :patrol, slot}})

  defp zone_placements(seat, {zone, ids}) when is_list(ids),
    do: for(id <- ids, do: {id, {seat, zone}})

  defp zone_placements(_seat, {_zone, _count}), do: []

  @doc "The name of a zone or location (`:patrol` for a slot)."
  def zone_name(:trash), do: :trash
  def zone_name({_seat, zone}), do: zone
  def zone_name({_seat, :patrol, _slot}), do: :patrol
  def zone_name(nil), do: nil

  @doc "The seat of a zone or location (nil for the trash)."
  def zone_seat({seat, _}), do: seat
  def zone_seat({seat, :patrol, _}), do: seat
  def zone_seat(_), do: nil

  @doc "The card ids of a list zone."
  def zone_ids(game, :trash), do: game.trash
  def zone_ids(game, {seat, zone}), do: Map.fetch!(game.sides[seat].zones, zone)

  @doc "Replace the ids of a list zone."
  def put_zone(game, :trash, ids), do: %{game | trash: ids}
  def put_zone(game, {seat, zone}, ids), do: put_in(game.sides[seat].zones[zone], ids)

  @doc "Take card `id` out of its zone."
  def remove(game, id) do
    case locate(game, id) do
      {seat, :patrol, slot} -> put_in(game.sides[seat].zones.patrol[slot], nil)
      nil -> game
      zone -> put_zone(game, zone, List.delete(zone_ids(game, zone), id))
    end
  end

  @doc "Put card `id` (in no zone) into `zone`: a patrol slot, an index, or nil for the end."
  def insert(game, id, {seat, :patrol}, slot),
    do: put_in(game.sides[seat].zones.patrol[slot], id)

  def insert(game, id, zone, nil), do: put_zone(game, zone, zone_ids(game, zone) ++ [id])

  def insert(game, id, zone, i),
    do: put_zone(game, zone, List.insert_at(zone_ids(game, zone), i, id))

  @doc "Move card `id` to `zone` (see `insert/4`)."
  def move(game, id, zone, at \\ nil), do: game |> remove(id) |> insert(id, zone, at)

  @doc "Change card `id` with `fun`."
  def update_card(game, id, fun), do: %{game | cards: Map.update!(game.cards, id, fun)}

  @doc "The cards in play of `seat` (in play and in the patrol zone), in order."
  def in_play(game, seat) do
    zones = game.sides[seat].zones
    zones.in_play ++ for(slot <- @patrol_slots, id = zones.patrol[slot], do: id)
  end

  @doc "The patrollers of `seat`: `{slot, id}` left to right."
  def patrollers(game, seat),
    do: for(slot <- @patrol_slots, id = game.sides[seat].zones.patrol[slot], do: {slot, id})

  @doc "The patrol slot of card `id`, or nil."
  def slot_of(game, id) do
    case locate(game, id) do
      {_seat, :patrol, slot} -> slot
      _ -> nil
    end
  end

  @doc "The seat that controls card `id` (the side of its zone), or nil."
  def controller(game, id), do: zone_seat(locate(game, id))
end
