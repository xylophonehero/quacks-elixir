defmodule QuacksWeb.GameText do
  @moduledoc """
  The words of the game page: a label for each action and log entry (`label/1`),
  the log lines (`log_lines/3`), chip and phase names, and the VP breakdown of
  the results. Plain strings, no markup; the components and `QuacksWeb.GameLive`
  import it.
  """

  alias Quacks.{Game, GameServer}
  alias Quacks.Rules.{Alchemists, Books, Chips}
  alias Quacks.Rules.Fortune
  alias Quacks.Rules.Witches
  alias QuacksWeb.{AlchemistsComponents, Replay}

  @doc ~s[When a book acts, as a label: "On draw", "Evaluation (step B)", ...]
  @spec trigger_label(Books.trigger()) :: String.t()
  def trigger_label(:on_draw), do: "On draw"
  def trigger_label(:step_b), do: "Evaluation (step B)"
  def trigger_label(:passive), do: "All round"
  def trigger_label(:none), do: "No action"

  @doc "Why Flea Market cannot trade a chip up (`Fortune.flea_block/2`), in a few words."
  def flea_reason(:white), do: "white stays"
  def flea_reason(:top), do: "no higher value"
  def flea_reason(:none_left), do: "none to trade for"

  @doc """
  The newest `limit` lines of `log` in the words of `action_log/1`, newest first
  (a bug report's log). `names` as in `action_log/1`.
  """
  @spec log_text(list, pos_integer, map | nil) :: [String.t()]
  def log_text(log, limit, names),
    do: for({_seat, line} <- log_lines(log, limit, names), do: line)

  @doc """
  The newest `limit` entries of `log` as `{seat, text}`, newest first, without the
  actions an event already narrates. `seat` is nil when no seat dot shows.
  """
  @spec log_lines(list, pos_integer, map | nil) :: [{Game.seat() | nil, String.t()}]
  def log_lines(log, limit, names) do
    log
    |> drop_stop_before_stopped()
    |> Enum.reject(&(&1 |> untag() |> narrated_by_event?()))
    |> Enum.take(limit)
    |> Enum.map(&log_line(&1, names))
  end

  # `{seat, text}`; seat is nil when no dot shows (solo, or an untagged entry).
  defp log_line({seat, entry}, names) when is_integer(seat) and is_map(names),
    do: {seat, "#{Map.get(names, seat, GameServer.default_name(seat))}: #{log_label(entry)}"}

  defp log_line(entry, _names), do: {nil, entry |> untag() |> log_label()}

  # The `:stop` action and the `:stopped` event are one stop, and `:resume` and
  # `:resumed` are one resume: keep the event only.
  defp drop_stop_before_stopped(log) do
    [nil | log]
    |> Enum.zip(log)
    |> Enum.reject(fn {newer, entry} -> echo?(newer, entry) end)
    |> Enum.map(&elem(&1, 1))
  end

  defp echo?({seat, :stopped}, {seat, :stop}), do: true
  defp echo?({seat, :resumed}, {seat, :resume}), do: true
  defp echo?(_newer, _entry), do: false

  defp untag({seat, entry}) when is_integer(seat), do: entry
  defp untag(entry), do: entry

  # The log tells what happened, in the past tense: an action the player took reads
  # "Bought nothing", not the button's "Buy nothing". Events already read so.
  defp log_label(:stop), do: "Stopped"
  defp log_label(:resume), do: "Resumed brewing"
  defp log_label({:explosion_choice, :vp}), do: "Exploded: took the VP"
  defp log_label({:explosion_choice, :buy}), do: "Exploded: took the coins"
  defp log_label({:buy, []}), do: "Bought nothing"
  defp log_label(:keep), do: "Mandrake: kept the white chip"
  defp log_label({:place, chip}), do: "Crow skull: placed #{chip_name(chip)}"
  defp log_label(:return_all), do: "Crow skull: returned all drawn chips to the bag"
  defp log_label(:chip_done), do: "Finished the chip actions"

  defp log_label({:red, {:place, chip}}),
    do: "Toadstool: placed #{chip_name(chip)} after the last chip"

  defp log_label({:red, {:keep, chip}}), do: "Toadstool: kept #{chip_name(chip)} beside the pot"
  defp log_label({:red, {:return, chip}}), do: "Toadstool: returned #{chip_name(chip)} to the bag"
  defp log_label({:essence, {:space, n}}), do: "Essence: took space #{n}"
  defp log_label({:essence, {:swap, chip}}), do: "Chicken eyes: swapped #{chip_name(chip)}"
  defp log_label({:essence, {:place, chip}}), do: "Nervousness: placed #{chip_name(chip)}"
  defp log_label({:essence, :pass}), do: "Essence: passed"
  defp log_label({:witch, colour}), do: "Called the #{colour} witch"

  defp log_label({:witch, :silver, {:place, chip}}),
    do: "Silver witch: placed #{chip_name(chip)}"

  defp log_label({:witch, :silver, :return_all}), do: "Silver witch: returned the rest to the bag"
  defp log_label(:witch_done), do: "Kept the gold penny"
  defp log_label(entry), do: label(entry)

  defp narrated_by_event?(:draw), do: true
  # The event right after says it: `{:returned, chip}`, `{:bought, chips}` or the
  # witch's `{:witch, id, outcome}`.
  defp narrated_by_event?(:use_flask), do: true
  defp narrated_by_event?(:return_white), do: true
  defp narrated_by_event?({:essence, {:buy, _chip}}), do: true
  defp narrated_by_event?({:witch, :silver, n}) when is_integer(n), do: true
  defp narrated_by_event?({:witch, :copper, _choice}), do: true
  defp narrated_by_event?({:buy, [_ | _]}), do: true
  defp narrated_by_event?({:rubies, _}), do: true
  defp narrated_by_event?({:droplet, :tube}), do: true
  defp narrated_by_event?(:end_round), do: true
  # Every card choice logs its outcome right after, as `{:fortune, id, outcome}`.
  defp narrated_by_event?({:fortune, _choice}), do: true
  # Every chip choice logs its `{:effect, ...}` right after.
  defp narrated_by_event?({:chip, _choice}), do: true
  # Every essence spend logs `{:essence_spent, n, what}` right after.
  defp narrated_by_event?({:essence, what}) when what in [:carrot, :double, :return, :hump],
    do: true

  defp narrated_by_event?({:essence, {:forget, _chip}}), do: true
  defp narrated_by_event?(_entry), do: false

  @doc """
  The VP `seat` got from the last round's coins and rubies (the round 9
  conversion), or nil when the log has no such entry yet. Reads both log shapes,
  `{:final_conversion, coins_vp, rubies_vp}` and
  `{:final_conversion, coins, coins_vp, rubies, rubies_vp}`.
  """
  @spec buying_power([term], Game.seat()) :: non_neg_integer | nil
  def buying_power(log, seat) do
    Enum.find_value(log, fn
      {^seat, {:final_conversion, cvp, rvp}} -> cvp + rvp
      {^seat, {:final_conversion, _coins, cvp, _rubies, rvp}} -> cvp + rvp
      _entry -> nil
    end)
  end

  @doc """
  Where `seat`'s `total` VP came from, read from the log, as `[{part, vp}]` in a
  fixed order, parts with 0 VP left out. The parts: `:brewing` (scoring spaces,
  overflow bowl, test tubes), `:die` (bonus die), `:chips` (chip and book
  actions), `:rubies` (2 rubies for 1 VP), `:final` (the round 9 conversion),
  `:essence` (The Alchemists), `:witches` (witch calls), `:cards` (fortune teller
  cards), `:pennies` (unused witch pennies at the end) and `:other`, the rest of
  `total`, so the parts always add up to `total`.
  """
  @spec vp_breakdown([term], Game.seat(), integer) :: [{atom, integer}]
  def vp_breakdown(log, seat, total) do
    known =
      for({^seat, entry} <- log, {part, vp} = vp_part(entry), vp != 0, do: {part, vp})
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {part, vps} -> {part, Enum.sum(vps)} end)

    other = total - (known |> Map.values() |> Enum.sum())
    parts = Map.put(known, :other, other)

    for part <- [
          :brewing,
          :die,
          :chips,
          :rubies,
          :final,
          :essence,
          :witches,
          :cards,
          :pennies,
          :other
        ],
        vp = Map.get(parts, part, 0),
        vp != 0,
        do: {part, vp}
  end

  @doc "The name of a `vp_breakdown/3` part."
  @spec vp_part_name(atom) :: String.t()
  def vp_part_name(:brewing), do: "Brewing"
  def vp_part_name(:die), do: "Bonus die"
  def vp_part_name(:chips), do: "Chip actions"
  def vp_part_name(:rubies), do: "Rubies"
  def vp_part_name(:final), do: "Final coins and rubies"
  def vp_part_name(:essence), do: "Essence"
  def vp_part_name(:witches), do: "Witches"
  def vp_part_name(:cards), do: "Fortune cards"
  def vp_part_name(:pennies), do: "Unused pennies"
  def vp_part_name(:other), do: "Other"

  @doc "What a `vp_breakdown/3` part counts, for its tooltip."
  @spec vp_part_hint(atom) :: String.t()
  def vp_part_hint(:brewing), do: "Victory points of your scoring spaces"
  def vp_part_hint(:die), do: "The bonus die"
  def vp_part_hint(:chips), do: "Purple, green, black and other chip actions"
  def vp_part_hint(:rubies), do: "2 rubies for 1 victory point"
  def vp_part_hint(:final), do: "Round 9: coins and rubies turned into victory points"
  def vp_part_hint(:essence), do: "The Alchemists: essence and the patient's glasses"
  def vp_part_hint(:witches), do: "Victory points from the witches you called"
  def vp_part_hint(:cards), do: "Victory points from fortune teller cards"
  def vp_part_hint(:pennies), do: "2 victory points for each witch penny you did not use"
  def vp_part_hint(:other), do: "Points that no other part shows, for example rat tails"

  defp vp_part({:pot_vp, vp, _index}), do: {:brewing, vp}
  defp vp_part({:bowl, _chips, vp}), do: {:brewing, vp}
  defp vp_part({:tube, _glass, {:vp, n}}), do: {:brewing, n}
  defp vp_part({:bonus_die, face}), do: {:die, die_vp(face)}
  defp vp_part({:effect, {:green, 6}, {:bonus_die, face}}), do: {:die, die_vp(face)}
  defp vp_part({:rubies_spent, :vp}), do: {:rubies, 1}
  defp vp_part({:final_conversion, cvp, rvp}), do: {:final, cvp + rvp}
  defp vp_part({:final_conversion, _coins, cvp, _rubies, rvp}), do: {:final, cvp + rvp}
  defp vp_part({:essence_vp, n}), do: {:essence, n}
  defp vp_part({:essence_bonus, {:vp, n}}), do: {:essence, n}
  defp vp_part({:witch, _id, {:vp, n}}), do: {:witches, n}
  defp vp_part({:fortune, _id, {:vp, n}}), do: {:cards, n}
  defp vp_part({:pennies, n}), do: {:pennies, n}

  defp vp_part({:purple, _, _} = entry), do: {:chips, gain_vp(entry)}
  defp vp_part({:effect, _, _} = entry), do: {:chips, gain_vp(entry)}
  defp vp_part(_entry), do: {:other, 0}

  defp gain_vp(entry) do
    case Replay.gain(entry) do
      {vp, _rubies} -> vp
      nil -> 0
    end
  end

  defp die_vp({:vp, n}), do: n
  defp die_vp(_face), do: 0

  @doc """
  Like `label/1`, but a fortune card choice is worded for `card` (the current
  `game.fortune_card`): the same `{:fortune, :vp}` means 4 VP on P6 and VP per rat
  tail on P10.
  """
  @spec label(term, Fortune.id() | nil) :: String.t()
  def label({:fortune, choice}, card), do: fortune_choice(choice, card)
  def label(action, _card), do: label(action)

  @doc """
  Human label for an action or a log entry. Unknown shapes fall back to `inspect/1`,
  so a new engine action never crashes the page.
  """
  @spec label(term) :: String.t()
  def label(:draw), do: "Draw a chip"
  def label(:stop), do: "Stop"
  def label(:resume), do: "Resume brewing"
  def label(:stopped), do: "Stopped"
  def label(:resumed), do: "Resumed brewing"
  def label(:use_flask), do: "Use flask"
  def label(:end_round), do: "End round"
  def label({:explosion_choice, :vp}), do: "Exploded: take the victory points"
  def label({:explosion_choice, :buy}), do: "Exploded: buy chips instead"
  def label({:rubies, :droplet}), do: "Spend 2 rubies: droplet +1"
  def label({:rubies, :flask}), do: "Spend 2 rubies: refill flask"
  def label({:rubies, :vp}), do: "2 rubies → 1 VP"
  def label({:rubies, :tube}), do: "Spend 2 rubies: test tube +1"
  def label({:droplet, :pot}), do: "Pot droplet +1"
  def label({:droplet, :tube}), do: "Test tube +1"
  def label({:tube, glass, bonus}), do: "Test tube #{glass}: #{tube_bonus(bonus)}"
  def label({:buy, []}), do: "Buy nothing"

  # No price here: it depends on the game's books. The shop shows the prices.
  def label({:buy, chips}) when is_list(chips),
    do: "Buy #{Enum.map_join(chips, " + ", &chip_name/1)}"

  def label(:return_white), do: "Mandrake: put the white chip back in the bag"
  def label(:keep), do: "Mandrake: keep the white chip"
  def label({:place, {colour, value}}), do: "Crow skull: place #{colour} #{value}"
  def label(:return_all), do: "Crow skull: return all drawn chips to the bag"
  def label({:bonus_die, face}), do: "Bonus die: #{die_text(face)}"
  def label({:drew, chip, index}), do: "Drew #{chip_name(chip)} → space #{index}"
  def label({:returned, chip}), do: "Returned #{chip_name(chip)} to the bag"
  def label({:exploded, white_sum}), do: "Exploded (white #{white_sum})"
  def label({:bought, chips}), do: "Bought #{Enum.map_join(chips, " + ", &chip_name/1)}"
  def label({:rubies_spent, :droplet}), do: "Spent 2 rubies: droplet +1"
  def label({:rubies_spent, :flask}), do: "Spent 2 rubies: flask refilled"
  def label({:rubies_spent, :vp}), do: "Spent 2 rubies: +1 VP"
  def label({:rubies_spent, :tube}), do: "Spent 2 rubies: test tube +1"
  def label({:green_rubies, n}), do: "Garden spider: +#{n} #{plural(n, "ruby", "rubies")}"
  def label({:purple, 1, :vp1}), do: "Ghost's breath (tier 1): +1 VP"
  def label({:purple, 2, :vp1_ruby}), do: "Ghost's breath (tier 2): +1 VP, +1 ruby"
  def label({:purple, 3, :vp2_droplet}), do: "Ghost's breath (tier 3): +2 VP, droplet +1"
  def label({:black, :droplet}), do: "Hawkmoth: droplet +1"
  def label({:black, :droplet_ruby}), do: "Hawkmoth: droplet +1, +1 ruby"
  def label({:rats, tails}), do: "Rats: #{tails} #{plural(tails, "tail", "tails")}"
  def label({:pot_ruby, index}), do: "Scoring space #{index}: +1 ruby"
  def label({:pot_vp, vp, index}), do: "Scoring space #{index}: +#{vp} VP"
  def label({:round_end, round}), do: "— Round #{round} over —"

  def label({:final_conversion, coins, coins_vp, rubies, rubies_vp}),
    do:
      "Final: #{coins} coins → #{coins_vp} VP, #{rubies} #{plural(rubies, "ruby", "rubies")} → #{rubies_vp} VP"

  def label({:fortune, choice}), do: fortune_choice(choice, nil)
  def label({:fortune_drawn, id}), do: "Fortune teller: #{Fortune.card(id).name}"

  def label({:fortune_skipped, id}),
    do: "Fortune teller: #{Fortune.card(id).name} (skipped in solo)"

  def label({:fortune, id, outcome}),
    do: "#{Fortune.card(id).name}: #{fortune_outcome(outcome, id)}"

  def label({:chip, {:gain, chip}}), do: "Garden spider: take #{chip_name(chip)}"

  def label({:chip, {:pay_ruby_move, n}}),
    do: "Garden spider: pay #{n} #{plural(n, "ruby", "rubies")}, droplet +#{n}"

  def label({:chip, {:purple_trade, tier}}),
    do: "Ghost's breath: trade #{tier} purple for #{purple_trade(tier)}"

  def label({:chip, {:upgrade, from, to}}),
    do: "Ghost's breath: swap #{chip_name(from)} for #{chip_name(to)}"

  def label(:chip_done), do: "Done with chip actions"

  def label({:red, {:place, chip}}),
    do: "Toadstool: place #{chip_name(chip)} after your last chip"

  def label({:red, {:keep, chip}}), do: "Toadstool: keep #{chip_name(chip)} beside the pot"
  def label({:red, {:return, chip}}), do: "Toadstool: return #{chip_name(chip)} to the bag"
  def label({:rubies_spent, :droplet, 1}), do: "Spent 1 ruby: droplet +1"
  def label({:rubies_spent, :flask, 1}), do: "Spent 1 ruby: flask refilled"
  def label({:rubies_spent, :tube, 1}), do: "Spent 1 ruby: test tube +1"
  def label({:overflow, chip}), do: "#{chip_name(chip)} went in the overflow bowl"
  def label({:bowl, _chips, vp}), do: "Overflow bowl: +#{vp} VP"
  def label({:pennies, vp}), do: "Unused witch pennies: +#{vp} VP"
  def label({:expansion, :herb_witches}), do: "Playing with The Herb Witches"
  def label({:expansion, :alchemists}), do: "Playing with The Alchemists"

  def label({:patients, ids}),
    do: "Patients dealt: #{Enum.map_join(ids, ", ", &Alchemists.get(&1).name)}"

  def label({:patient, id}), do: "Patient: #{Alchemists.get(id).name}"

  def label({:essence, space, parts}) when is_map(parts),
    do: "Essence: space #{space} (#{Enum.join(AlchemistsComponents.parts_text(parts), ", ")})"

  def label({:essence, {:space, n}}), do: "Essence: take space #{n}"
  def label({:essence, {:swap, chip}}), do: "Chicken eyes: swap #{chip_name(chip)}"
  def label({:essence, {:buy, chip}}), do: "Vampirism: buy #{chip_name(chip)}"
  def label({:essence, {:place, chip}}), do: "Nervousness: place #{chip_name(chip)}"
  def label({:essence, {:forget, chip}}), do: "Forgetfulness: return #{chip_name(chip)}"
  def label({:essence, :pass}), do: "No thanks"
  def label({:essence, :carrot}), do: "Spend 2 essence: pumpkin to the next ruby space"
  def label({:essence, :double}), do: "Spend 2 essence: move the white chip double"
  def label({:essence, :return}), do: "Spend 3 essence: white chip back to the bag"
  def label({:essence, :hump}), do: "Spend 2 essence: Witch's hump bonus"

  def label({:essence_bonus, term}),
    do: "Essence bonus: #{AlchemistsComponents.term_text(term)}"

  def label({:essence_vp, n}), do: "Final essence: +#{n} VP"
  def label({:essence_rat, n}), do: "Essence: rat stone +#{n}"

  def label({:essence_spent, n, what}), do: "Spent #{n} essence: #{essence_use(what)}"

  def label({:display, chips}), do: "Nervousness: laid out #{chip_list(chips)}"
  def label({:witch, colour}), do: "Call the #{colour} witch"

  def label({:witch, :silver, n}) when is_integer(n),
    do: "Silver witch: return the last #{plural(n, "white chip", "#{n} white chips")}"

  def label({:witch, :silver, {:place, chip}}), do: "Silver witch: place #{chip_name(chip)}"
  def label({:witch, :silver, :return_all}), do: "Silver witch: return the rest to the bag"

  def label({:witch, :copper, {:upgrade, chips}}),
    do: "Copper witch: upgrade #{Enum.map_join(chips, " + ", &chip_name/1)}"

  def label({:witch, :copper, {:buy, chips, copy}}),
    do: "Copper witch: buy #{Enum.map_join(chips, " + ", &chip_name/1)}, free #{chip_name(copy)}"

  def label({:witch, id, outcome}), do: "#{Witches.card(id).title}: #{witch_outcome(outcome, id)}"
  def label(:witch_done), do: "Keep the gold penny"
  def label({:chip, :yellow_ruby}), do: "Mandrake: pay 1 ruby, move 3 more"
  def label({:chip, {:return, chip}}), do: "Locoweed: return #{chip_name(chip)} to the bag"

  def label({:chip, {:starter, chip}}),
    do: "Garden spider: start the next round with #{chip_name(chip)}"

  def label({:chip, {:buy, chips}}),
    do: "Ghost's breath: take #{Enum.map_join(chips, " + ", &chip_name/1)}"

  def label({:effect, book, detail}), do: effect(book, detail)
  def label({seat, {:effect, _, _} = entry}) when is_integer(seat), do: label(entry)
  def label(other), do: inspect(other)

  # A Set 2–4 chip effect, for the log. One head per `{:effect, {colour, set}, detail}`
  # shape in the Log table of `docs/CONTEXT.md`.
  defp effect({:green, 2}, {:gain, chip}), do: "Garden spider: took #{chip_name(chip)}"

  defp effect({:green, 3}, {:moved_last, n}),
    do: "Garden spider: exactly 7 white, last chip moved #{n} #{plural(n, "space", "spaces")}"

  defp effect({:green, 4}, {:droplet, n}),
    do: "Garden spider: paid #{n} #{plural(n, "ruby", "rubies")}, droplet +#{n}"

  defp effect({:blue, 2}, {:protect, n}),
    do: "Crow skull: the next #{n} #{plural(n, "chip is", "chips are")} protected"

  defp effect({:blue, 2}, :protected_explosion),
    do: "Crow skull: protected, kept VP and coins"

  defp effect({:blue, 3}, :ruby), do: "Crow skull: on a ruby space, +1 ruby"
  defp effect({:blue, 4}, {:vp, n}), do: "Crow skull: on a ruby space, +#{n} VP"
  defp effect({:red, 2}, {:aside, chip}), do: "Toadstool: #{chip_name(chip)} beside the pot"
  defp effect({:red, 3}, {:extra, n}), do: "Toadstool: +#{n} after a white chip"
  defp effect({:red, 4}, :white_plus1), do: "Toadstool: white 1 moved 2"
  defp effect({:yellow, 2}, {:doubled, n}), do: "Mandrake: moved double (#{n} spaces)"
  defp effect({:yellow, 3}, {:limit, n}), do: "Mandrake: white limit now #{n}"
  defp effect({:yellow, 4}, {:extra, n}), do: "Mandrake: +#{n} #{plural(n, "space", "spaces")}"

  defp effect({:purple, 2}, {:trade, tier}),
    do: "Ghost's breath: traded for #{purple_trade(tier)}"

  defp effect({:purple, 3}, {:vp, n}), do: "Ghost's breath: +#{n} VP from pot fields"

  defp effect({:purple, 4}, {:upgrade, from, to}),
    do: "Ghost's breath: swapped #{chip_name(from)} for #{chip_name(to)} (into the bag)"

  # The Herb Witches books (Sets 5 and 6, black, locoweed).
  defp effect({:red, 5}, {:extra, n}), do: "Toadstool: +#{n}, a higher red is in the pot"
  defp effect({:red, 6}, {:aside, chip}), do: "Toadstool: #{chip_name(chip)} set aside"
  defp effect({:yellow, 5}, {:peek, chip}), do: "Mandrake: peeked at #{chip_name(chip)}, moved on"
  defp effect({:yellow, 6}, {:extra, n}), do: "Mandrake: paid 1 ruby, +#{n} spaces"
  defp effect({:blue, 5}, {:vp, n}), do: "Crow skull: +#{n} VP for the pumpkins"

  defp effect({:blue, 6}, {:rubies, n}),
    do: "Crow skull: +#{n} #{plural(n, "ruby", "rubies")} for white 1-chips"

  defp effect({:green, 5}, {:starter, chip}),
    do: "Garden spider: #{chip_name(chip)} starts the next round"

  defp effect({:green, 5}, {:first, chip}), do: "Garden spider: #{chip_name(chip)} placed first"
  defp effect({:green, 6}, {:bonus_die, face}), do: "Garden spider: " <> label({:bonus_die, face})

  defp effect({:purple, 5}, {:bought, chips}),
    do: "Ghost's breath: took #{Enum.map_join(chips, " + ", &chip_name/1)}"

  defp effect({:purple, 5}, {:vp, n}), do: "Ghost's breath: +#{n} VP from the purple spaces"
  defp effect({:purple, 6}, {:vp, n}), do: "Ghost's breath: +#{n} VP from the chips after purple"

  defp effect({:black, 2}, {:to_left, _seat}),
    do: "Hawkmoth: black chip into the left player's bag, droplet +1"

  defp effect({:black, 2}, :to_supply), do: "Hawkmoth: black chip back to the supply, droplet +1"

  defp effect({:black, 2}, {:rubies, n}),
    do: "Hawkmoth: +#{n} #{plural(n, "ruby", "rubies")}"

  defp effect({:black, 3}, :droplet), do: "Hawkmoth: furthest black chip, droplet +1"
  defp effect({:black, 3}, :ruby), do: "Hawkmoth: second furthest black chip, +1 ruby"
  defp effect({:black, 3}, :droplet_ruby), do: "Hawkmoth: droplet +1, +1 ruby"
  defp effect({:locoweed, _}, {:moves, n}), do: "Locoweed: moved #{n}"

  defp effect({:locoweed, 5}, {:returned, chip}),
    do: "Locoweed: #{chip_name(chip)} back to the bag"

  defp effect({:locoweed, 2}, {:copied, chip}), do: "Locoweed: acted as #{chip_name(chip)}"
  defp effect(book, detail), do: inspect({:effect, book, detail})

  # What a witch did, for the log.
  defp witch_outcome(:flask, _id), do: "the flask took the white chip back"
  defp witch_outcome({:offer, n}, _id), do: "drew #{n} #{plural(n, "chip", "chips")}"

  defp witch_outcome({:return_white, n}, _id),
    do: "#{n} white #{plural(n, "chip", "chips")} back in the bag"

  defp witch_outcome(:no_penalty, _id), do: "no explosion penalty"

  defp witch_outcome({:upgrade, chips}, _id),
    do: "upgraded #{Enum.map_join(chips, " + ", &chip_name/1)}"

  defp witch_outcome({:coins, n}, :c2), do: "coins doubled to #{n}"
  defp witch_outcome({:coins, n}, _id), do: "+#{n} coins"
  defp witch_outcome({:copy, chip}, _id), do: "free #{chip_name(chip)}"
  defp witch_outcome({:vp, n}, _id), do: "+#{n} VP"
  defp witch_outcome({:rubies, n}, _id), do: "+#{n} #{plural(n, "ruby", "rubies")}"
  defp witch_outcome(:ruby_price, _id), do: "droplet and flask cost 1 ruby"
  defp witch_outcome(other, _id), do: inspect(other)

  defp purple_trade(1), do: "black 1, 1 VP, 1 ruby"
  defp purple_trade(2), do: "green 1, blue 2, 3 VP, droplet +1"
  defp purple_trade(3), do: "yellow 4, 6 VP, 1 ruby, droplet +2"

  # A `{:fortune, choice}` button. `card` is the current card; nil means unknown.
  defp fortune_choice({:take, chip}, :p3), do: "Trade 1 ruby for #{chip_name(chip)}"
  defp fortune_choice({:take, chip}, _card), do: "Take #{chip_name(chip)}"
  defp fortune_choice(:rubies, _card), do: "Take 3 rubies"
  defp fortune_choice(:vp, :p6), do: "Score 4 VP"
  defp fortune_choice(:vp, :p10), do: "Score 1 VP per rat tail behind the leader"
  defp fortune_choice(:vp, _card), do: "Score victory points"
  defp fortune_choice(:remove_white, _card), do: "Remove a white 1 from your bag"

  defp fortune_choice({:rats_back, n}, _card),
    do: "Rat stone back #{n}, take #{n} #{plural(n, "ruby", "rubies")}"

  defp fortune_choice(:droplet, :p11), do: "Droplet 2 forward"
  defp fortune_choice(:droplet, _card), do: "Droplet forward"

  defp fortune_choice({:upgrade, chip}, _card),
    do: "Trade #{chip_name(chip)} for the next value up"

  defp fortune_choice(:skip, _card), do: "No thanks"
  defp fortune_choice(:restart_round, _card), do: "Second Chances: start the round again"
  defp fortune_choice(:return_white, _card), do: "Cauldron Bubble: put the white chip back"
  defp fortune_choice({:place, chip}, _card), do: "Safety Procedure: place #{chip_name(chip)}"
  defp fortune_choice(:return_all, _card), do: "Safety Procedure: return all to the bag"
  defp fortune_choice(other, _card), do: inspect({:fortune, other})

  @doc "Round 24: what card `id` did for a player (`outcome` of its log entry), as text."
  @spec card_outcome(term, atom) :: String.t()
  def card_outcome(outcome, id), do: outcome |> fortune_outcome(id) |> String.capitalize()

  # What a card did for a player, for the log.
  defp fortune_outcome({:drew, chips}, :p8),
    do: "drew #{chip_list(chips)} (sum #{chips |> Enum.map(&elem(&1, 1)) |> Enum.sum()})"

  defp fortune_outcome({:drew, chips}, :b3), do: "put back #{chip_list(chips)}"
  defp fortune_outcome({:drew, chips}, _id), do: "drew #{chip_list(chips)}"
  defp fortune_outcome(face, :p12), do: "rolled the die: #{die_text(face)}"
  defp fortune_outcome(:droplet, :p11), do: "droplet +2"
  defp fortune_outcome(:droplet, _id), do: "droplet +1"
  defp fortune_outcome({:take, chip}, _id), do: "took #{chip_name(chip)}"
  defp fortune_outcome(:restart_round, _id), do: "started the round again"
  defp fortune_outcome({:place, chip}, _id), do: "placed #{chip_name(chip)}"
  defp fortune_outcome(:return_all, _id), do: "returned all chips to the bag"
  defp fortune_outcome({:vp, n}, _id), do: "+#{n} VP"
  defp fortune_outcome(:flask, _id), do: "flask refilled"
  defp fortune_outcome(:return_white, _id), do: "white chip back in the bag"
  defp fortune_outcome(:ruby, _id), do: "+1 ruby"
  defp fortune_outcome(:rubies, _id), do: "+3 rubies"
  defp fortune_outcome(:skip, _id), do: "passed"
  defp fortune_outcome(:remove_white, _id), do: "removed a white 1 from the bag"
  defp fortune_outcome({:rats, n}, _id), do: "rat stone +#{n}"

  defp fortune_outcome({:rats_back, n}, _id),
    do: "rat stone back #{n}, +#{n} #{plural(n, "ruby", "rubies")}"

  defp fortune_outcome({:upgrade, chip}, _id), do: "traded #{chip_name(chip)} up"
  defp fortune_outcome(:orange, _id), do: "took orange 1"
  defp fortune_outcome(other, _id), do: inspect(other)

  defp chip_list(chips), do: Enum.map_join(chips, ", ", &chip_name/1)

  defp essence_use(:carrot), do: "pumpkin to the next ruby space"
  defp essence_use(:double), do: "white chip moved double"
  defp essence_use(:return), do: "white chip back to the bag"
  defp essence_use(:hump), do: "Witch's hump"
  defp essence_use({:forget, chip}), do: "#{chip_name(chip)} back to the bag"

  @doc ~s(A bonus die face in words: "2 VP", "ruby", "droplet +1", "orange 1 chip".)
  def die_text({:vp, n}), do: "#{n} VP"
  def die_text(:ruby), do: "ruby"
  def die_text(:droplet), do: "droplet +1"
  def die_text(:orange), do: "orange 1 chip"
  def die_text(other), do: inspect(other)

  @doc ~s(A test-tube glass bonus in words: "1 ruby", "2 VP", "blue 1 chip".)
  @spec tube_bonus(Quacks.Rules.TestTubes.bonus()) :: String.t()
  def tube_bonus(:ruby), do: "1 ruby"
  def tube_bonus({:vp, n}), do: "#{n} VP"
  def tube_bonus({:chip, chip}), do: "#{chip_name(chip)} chip"

  @doc "`one` for 1, else `many`."
  @spec plural(integer, String.t(), String.t()) :: String.t()
  def plural(1, one, _many), do: one
  def plural(_n, _one, many), do: many

  @doc ~s("green 2" for `{:green, 2}`; locoweed has no value: "locoweed".)
  @spec chip_name(Chips.chip()) :: String.t()
  def chip_name({:locoweed, _}), do: "locoweed"
  def chip_name({colour, value}), do: "#{colour} #{value}"

  @doc "The name of a phase, as the header shows it."
  @spec phase_name(atom) :: String.t()
  def phase_name(:potions), do: "Brewing"
  def phase_name(:explosion_choice), do: "Explosion"
  def phase_name(:yellow_choice), do: "Mandrake"
  def phase_name(:blue_choice), do: "Crow skull"
  def phase_name(:fortune_choice), do: "Fortune teller"
  def phase_name(:chip_choice), do: "Chip actions"
  def phase_name(:witch_choice), do: "Gold witch"
  def phase_name(:witch_offer), do: "Silver witch"
  def phase_name(:red_choice), do: "Toadstool"
  def phase_name(:stopped), do: "Waiting"
  def phase_name(:shop), do: "Shop"
  def phase_name(:rubies), do: "Spend rubies"
  def phase_name(:droplet_choice), do: "Droplet"
  def phase_name(:waiting_stir), do: "Stir!"
  def phase_name(:ready), do: "Ready"
  def phase_name(:done), do: "Done"
  def phase_name(:over), do: "Over"
  def phase_name(:patient_choice), do: "Patient"
  def phase_name(:essence), do: "Essence"
  def phase_name(:essence_choice), do: "Essence"
  def phase_name(:essence_bonus), do: "Essence bonus"
  def phase_name(:ear_worm), do: "Ear worm"
  def phase_name(:essence_offer), do: "Essence"
  def phase_name(other), do: inspect(other)
end
