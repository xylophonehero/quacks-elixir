defmodule Quacks.GameFacadeTest do
  @moduledoc """
  Issue #79: `Quacks.Game` is the engine's only door. These tests fail when the
  facade grows, or when code outside the engine calls past it.
  """
  use ExUnit.Case, async: true

  # The contract, then the reads for the board and the bots. Add a function here only
  # when a caller outside the engine needs it; engine helpers go in
  # `Quacks.Game.State`.
  @facade [
    # the contract
    new: 1,
    legal_actions: 1,
    legal_actions: 2,
    apply: 2,
    apply: 3,
    phase: 2,
    over?: 1,
    score: 1,
    default_rules: 0,
    expansion?: 2,
    # the reads
    player: 2,
    turn_order: 1,
    start_seat: 1,
    white_sum: 1,
    white_sum: 2,
    pot_chips: 1,
    pot_chips: 2,
    scoring_index: 1,
    scoring_index: 2,
    white_limit: 2,
    safe_draw?: 2,
    card_reveals: 1,
    flea_block: 2,
    available?: 2,
    in_supply?: 2,
    black_targets: 2,
    standings: 1,
    essence_reach: 2,
    dealt_patients: 1
  ]

  # The engine's own modules. Only the engine calls them.
  @internal [
    Quacks.Game.State,
    Quacks.Game.Round,
    Quacks.Game.Potions,
    Quacks.Game.Evaluation,
    Quacks.Game.Fortune,
    Quacks.Game.Witches,
    Quacks.Game.Essence
  ]

  # The one exception (architecture review, opportunity 1): the gallery fixtures are
  # test support in `lib/` and build states with the engine helpers.
  @allowed %{QuacksWeb.Gallery.Fixtures => [Quacks.Game.State]}

  test "Quacks.Game exports only the facade" do
    exported = Quacks.Game.__info__(:functions) -- [__struct__: 0, __struct__: 1]
    assert Enum.sort(exported) == Enum.sort(@facade)
  end

  test "no module outside the engine calls an engine submodule" do
    {:ok, modules} = :application.get_key(:quacks, :modules)
    engine = [Quacks.Game | @internal]

    calls =
      for module <- modules,
          module not in engine,
          {callee, fun, arity} <- remote_calls(module),
          callee in @internal,
          callee not in Map.get(@allowed, module, []),
          do: "#{inspect(module)} calls #{inspect(callee)}.#{fun}/#{arity}"

    assert calls == []
  end

  # The remote functions that `module`'s compiled code calls (the BEAM import table).
  defp remote_calls(module) do
    {^module, binary, _file} = :code.get_object_code(module)
    {:ok, {^module, [imports: imports]}} = :beam_lib.chunks(binary, [:imports])
    imports
  end
end
