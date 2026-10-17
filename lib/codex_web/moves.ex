defmodule CodexWeb.Moves do
  @moduledoc """
  The rules-mode interaction of the Codex board (`CodexWeb.Board`), as pure
  functions over the legal actions (`Codex.Game.legal_actions/2`). The board never
  decides what is legal: it offers only what this list holds.

  - `buttons/2`: the action buttons of a selected card.
  - `drop/4`: the action for a card dropped on (or tapped into) a zone.
  - Targeting: an action with targets (play a spell, attack, an ability) starts a
    target pick. `options/3` gives the next values to tap after the targets
    picked so far, and the full action when the pick is complete.

  A targeting key is `{kind, card_id, name}`: `{:play, id, nil}`,
  `{:attack, id, nil}`, `{:ability, id, name}`. A target value is a card id, a
  building `{:building, seat, name}`, or nil (skip that part of the card).
  """

  @type key :: {:play | :attack | :ability, pos_integer, atom | nil}

  @doc "The targeting key and the targets of an action, or nil for an action with no target step."
  @spec split(term) :: {key, list} | nil
  def split({:play, id, targets}), do: {{:play, id, nil}, targets}
  def split({:attack, id, target}), do: {{:attack, id, nil}, [target]}
  def split({:ability, id, name, targets}), do: {{:ability, id, name}, targets}
  def split(_action), do: nil

  @doc """
  The buttons for card `id`: `%{key: dom_suffix, label: text, do: action}` for
  an action with no targets, or `%{..., target: key}` to start a target pick.
  """
  @spec buttons([term], pos_integer) :: [map]
  def buttons(actions, id) do
    direct =
      for action <- actions, direct_button?(action, id), do: direct(action)

    picks =
      actions
      |> Enum.map(&split/1)
      |> Enum.filter(&match?({{_, ^id, _}, [_ | _]}, &1))
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()
      |> Enum.map(&pick_button/1)

    Enum.uniq_by(direct ++ picks, & &1.key)
  end

  defp direct_button?({:hire, id}, id), do: true
  defp direct_button?({:summon, id}, id), do: true
  defp direct_button?({:level_up, id}, id), do: true
  defp direct_button?({:sideline, id}, id), do: true
  defp direct_button?({:play, id, []}, id), do: true
  defp direct_button?({:ability, id, _name, []}, id), do: true
  defp direct_button?(_action, _id), do: false

  defp direct({:hire, _} = a), do: %{key: "hire", label: "Hire as a worker (1 gold)", do: a}
  defp direct({:summon, _} = a), do: %{key: "summon", label: "Summon", do: a}
  defp direct({:level_up, _} = a), do: %{key: "level", label: "Level up (1 gold)", do: a}
  defp direct({:sideline, _} = a), do: %{key: "sideline", label: "Sideline", do: a}
  defp direct({:play, _, []} = a), do: %{key: "play", label: "Play", do: a}

  defp direct({:ability, _, name, []} = a),
    do: %{key: "ability-#{name}", label: ability_label(name), do: a}

  defp pick_button({:play, _, _} = key), do: %{key: "play-pick", label: "Play…", target: key}
  defp pick_button({:attack, _, _} = key), do: %{key: "attack", label: "Attack…", target: key}

  defp pick_button({:ability, _, name} = key),
    do: %{key: "ability-#{name}", label: ability_label(name) <> "…", target: key}

  @doc """
  The action chips of card `id` (on the card on a desktop, and its keys): the
  buttons of `buttons/2` plus Patrol, each with a `kind` and maybe a `hotkey`.
  A chip with one legal target is the full action (`do`, and `one`: the
  target), so one click acts. Else it starts a pick (`target`), or for Patrol
  it lists the free slots (`patrol`).
  """
  @spec chips([term], pos_integer) :: [map]
  def chips(actions, id) do
    buttons = for b <- buttons(actions, id), do: b |> fold(actions) |> put_kind()

    case for({:patrol, ^id, slot} <- actions, do: slot) do
      [] -> buttons
      [slot] -> buttons ++ [put_kind(%{key: "patrol", do: {:patrol, id, slot}})]
      slots -> buttons ++ [put_kind(%{key: "patrol", patrol: slots})]
    end
  end

  # A pick with one legal target and no second step: the full action.
  defp fold(%{target: key} = b, actions) do
    with %{values: [value]} when value != nil <- options(actions, key, []),
         %{complete: action, values: []} when action != nil <- options(actions, key, [value]) do
      b |> Map.delete(:target) |> Map.merge(%{do: action, one: value})
    else
      _ -> b
    end
  end

  defp fold(b, _actions), do: b

  defp put_kind(%{key: key} = chip) do
    {kind, hotkey} = kind(key)
    chip |> Map.put(:kind, kind) |> Map.put(:hotkey, hotkey)
  end

  defp kind("attack"), do: {:attack, "a"}
  defp kind("level"), do: {:level, "l"}
  defp kind("patrol"), do: {:patrol, "p"}
  defp kind("sideline"), do: {:sideline, "p"}
  defp kind("hire"), do: {:hire, nil}
  defp kind("summon"), do: {:summon, nil}
  defp kind("play" <> _), do: {:play, nil}
  defp kind("ability-" <> _), do: {:ability, nil}

  @doc "The button text of a card ability."
  @spec ability_label(atom) :: String.t()
  def ability_label(:sideline), do: "Sideline a patroller"
  def ability_label(:stop_music), do: "Stop the music"
  def ability_label(:wreck), do: "Deal 2 to a building"
  def ability_label(:blast), do: "Sacrifice: 2 damage to a patrolling unit (1 gold)"
  def ability_label(:shoot), do: "1 damage (and 1 to your base)"
  def ability_label(:burn), do: "Remove 2 blood runes: 1 damage"
  def ability_label(:prospect), do: "Gain 1 gold"
  def ability_label(:spore), do: "Move a +1/+1 rune (1 gold)"
  def ability_label(:spore_tap), do: "Move a +1/+1 rune (exhaust)"
  def ability_label(:rune_move), do: "Move a +1/+1 rune"
  def ability_label(:instant_build), do: "Tech buildings build at once"
  def ability_label(:lob), do: "1 damage to a building"
  def ability_label(:firebat), do: "2 damage to a patroller or building (1 gold)"
  def ability_label(:sanatorium), do: "Draw, put up to 2 units into play (1 gold)"
  def ability_label(:mine), do: "Gain 3 gold, flip a coin"
  def ability_label(:firehouse), do: "2 damage"
  def ability_label(:elm), do: "+1/+1 runes"
  def ability_label(:jaina_1), do: "1 damage to a patrolling unit or building"
  def ability_label(:jaina_3), do: "3 damage to a unit or building"
  def ability_label(:argagarg), do: "+1 ATK / +1 armor to a unit"
  def ability_label(:hide), do: "Discard 2 cards: stealth"
  def ability_label(:tiger), do: "Fetch a Tiger from the codex (4 gold)"
  def ability_label(:magistrate), do: "Disable a unit or hero (1 gold)"
  def ability_label(:javelin), do: "Remove a javelin rune: long-range"
  def ability_label(:exhume), do: "Play a buried unit"
  def ability_label(:stash), do: "Stash a card (keep it at the draw)"
  def ability_label(:bigby_draw), do: "Draw a card"
  def ability_label(:mirror), do: "Another Mirror Illusion (2 gold)"
  def ability_label(:mirror_copy), do: "A Mirror copies a unit (2 gold)"
  def ability_label(:fetch), do: "Discard a card: fetch a Demonology spell (1 gold)"
  def ability_label(:plague), do: "Sacrifice a unit: a -1/-1 rune"
  def ability_label(:skeleton), do: "A Skeleton (1 gold)"
  def ability_label(:bone_draw), do: "Sacrifice a Skeleton: draw"
  def ability_label(:arrest), do: "Disable a tech 0-II unit"
  def ability_label(name), do: name |> to_string() |> String.replace("_", " ")

  @doc """
  The next target values of a pick of `key` after `picked`, and the complete
  action when `picked` is a full list of targets of a legal action.
  """
  @spec options([term], key, list) :: %{values: list, complete: term | nil}
  def options(actions, key, picked) do
    n = length(picked)

    matches =
      for action <- actions,
          {^key, targets} <- [split(action)],
          Enum.take(targets, n) == picked,
          do: {action, targets}

    %{
      values: for({_a, t} <- matches, length(t) > n, uniq: true, do: Enum.at(t, n)),
      complete: Enum.find_value(matches, fn {a, t} -> length(t) == n && a end)
    }
  end

  @doc """
  The action for card `id` moved to `zone` (`{seat, name}`, with `at` a patrol
  slot): hire, play, summon, patrol, sideline. `{:target, key}` when the play
  needs targets; `:error` when no legal action matches.
  """
  @spec drop([term], pos_integer, term, term) :: {:act, term} | {:target, key} | :error
  def drop(actions, id, {_seat, :workers}, _at), do: find(actions, {:hire, id})
  def drop(actions, id, {_seat, :patrol}, slot), do: find(actions, {:patrol, id, slot})

  def drop(actions, id, {_seat, :in_play}, _at) do
    cond do
      {:play, id, []} in actions -> {:act, {:play, id, []}}
      {:summon, id} in actions -> {:act, {:summon, id}}
      {:sideline, id} in actions -> {:act, {:sideline, id}}
      Enum.any?(actions, &match?({:play, ^id, [_ | _]}, &1)) -> {:target, {:play, id, nil}}
      true -> :error
    end
  end

  def drop(_actions, _id, _zone, _at), do: :error

  defp find(actions, action), do: if(action in actions, do: {:act, action}, else: :error)
end
