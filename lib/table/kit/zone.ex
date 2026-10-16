defmodule Table.Kit.Zone do
  @moduledoc """
  A place on the table that holds items (a hand, a bag, a pot, a card row), with
  an owner and a visibility:

  - `:public`: every viewer sees the items.
  - `:owner`: only the owner sees the items; other viewers see only how many.
  - `:hidden`: no viewer sees the items, not even the owner (a face-down deck).

  A game's `view/2` uses `view/2` here to hide what a seat must not see. The viewer
  is a seat, or `nil` for a spectator.

      iex> hand = Table.Kit.Zone.new([:ace, :king], owner: 1, visibility: :owner)
      iex> Table.Kit.Zone.view(hand, 1).items
      [:ace, :king]
      iex> Table.Kit.Zone.view(hand, 0).items
      [:hidden, :hidden]
  """

  @enforce_keys [:items, :visibility]
  defstruct items: [], owner: nil, visibility: :public

  @type visibility :: :public | :owner | :hidden
  @type t(item) :: %__MODULE__{items: [item | :hidden], owner: term, visibility: visibility}
  @type t :: t(term)

  @visibilities [:public, :owner, :hidden]

  @doc """
  A zone with `items`. Options: `owner:` (default nil) and `visibility:` (default
  `:public`). An `:owner` zone must have an owner.
  """
  @spec new(Enumerable.t(), keyword) :: t
  def new(items, opts \\ []) do
    owner = Keyword.get(opts, :owner)
    visibility = Keyword.get(opts, :visibility, :public)

    if visibility not in @visibilities,
      do: raise(ArgumentError, "visibility must be one of #{inspect(@visibilities)}")

    if visibility == :owner and owner == nil,
      do: raise(ArgumentError, "an :owner zone needs an owner")

    %__MODULE__{items: Enum.to_list(items), owner: owner, visibility: visibility}
  end

  @doc """
  True when `viewer` can see the items.

      iex> zone = Table.Kit.Zone.new([1], owner: 0, visibility: :owner)
      iex> {Table.Kit.Zone.visible?(zone, 0), Table.Kit.Zone.visible?(zone, nil)}
      {true, false}
  """
  @spec visible?(t, term) :: boolean
  def visible?(%__MODULE__{visibility: :public}, _viewer), do: true
  def visible?(%__MODULE__{visibility: :owner, owner: owner}, viewer), do: viewer == owner
  def visible?(%__MODULE__{visibility: :hidden}, _viewer), do: false

  @doc """
  The zone as `viewer` sees it: an item the viewer cannot see becomes `:hidden`, so
  the count stays.
  """
  @spec view(t, term) :: t
  def view(%__MODULE__{} = zone, viewer) do
    if visible?(zone, viewer),
      do: zone,
      else: %{zone | items: List.duplicate(:hidden, length(zone.items))}
  end

  @doc "The number of items."
  @spec size(t) :: non_neg_integer
  def size(%__MODULE__{items: items}), do: length(items)
end
