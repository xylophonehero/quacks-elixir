defmodule Quacks.AI do
  @moduledoc """
  Heuristic bot for one seat (`docs/research/ai-opponents.md` §3). Pure: `decide/4`
  reads the open game (bags, pots, scores) and returns one action out of
  `Quacks.Game.legal_actions/2`. It never reads `game.rng`; it has its own rng
  (`new_rng/2`) for its random choices, which the caller keeps between calls.

  One action per call. A multi-step turn (the shop: buy, rubies, `:end_round`) asks
  again after each action. `:none` means "nothing to do now": no legal action, or
  the seat is stopped (the bot never resumes).

      iex> game = Quacks.Game.new(seed: {1, 2, 3}, players: 2)
      iex> {action, _rng} = Quacks.AI.decide(game, 1, Quacks.AI.Profile.get(:balanced), Quacks.AI.new_rng({1, 2, 3}, 1))
      iex> action
      :draw
  """

  @behaviour Quacks.AI.Decider

  alias Quacks.AI.{Odds, Profile, Shop}
  alias Quacks.Game
  alias Quacks.Game.Potions

  @shift_cap 0.10

  @doc """
  The bot's own rng for `seat` in a game with seed `seed`; separate from the game rng.
  """
  @spec new_rng({integer, integer, integer}, Game.seat()) :: :rand.state()
  def new_rng({a, b, c}, seat), do: :rand.seed_s(:exsss, {a, b, c + 7919 * (seat + 1)})

  @impl true
  @spec decide(Game.t(), Game.seat(), Profile.t(), :rand.state()) ::
          {Game.action(), :rand.state()} | :none
  def decide(game, seat, profile, rng) do
    phase = Game.phase(game, seat)

    case Game.legal_actions(game, seat) do
      [] ->
        :none

      _legal when phase == :stopped ->
        :none

      legal ->
        {action, rng} =
          choose(phase, %{game: game, seat: seat, profile: profile, legal: legal}, rng)

        # Last resort: an unknown book or card must never stall the game.
        {if(action in legal, do: action, else: hd(legal)), rng}
    end
  end

  defp choose(:potions, ctx, rng), do: {potions(ctx), rng}
  defp choose(:yellow_choice, _ctx, rng), do: {:return_white, rng}
  defp choose(:blue_choice, ctx, rng), do: {blue(ctx), rng}
  defp choose(:explosion_choice, ctx, rng), do: {explosion(ctx), rng}

  defp choose(:red_choice, ctx, rng),
    do: {first(ctx.legal, &match?({:red, {:place, _}}, &1)), rng}

  defp choose(:chip_choice, ctx, rng), do: {first(ctx.legal, &(&1 != :chip_done)), rng}
  defp choose(:witch_choice, ctx, rng), do: {first(ctx.legal, &(&1 != :witch_done)), rng}
  defp choose(:fortune_choice, ctx, rng), do: random(undominated(ctx), rng)
  # Reverse pot side: the test tube while it is legal (until glass 12), else the pot.
  defp choose(:droplet_choice, ctx, rng),
    do: {first(ctx.legal, &(&1 == {:droplet, :tube})) || hd(ctx.legal), rng}

  defp choose(:shop, ctx, rng), do: {Shop.pick(ctx.game, ctx.seat, ctx.profile, ctx.legal), rng}
  defp choose(_phase, ctx, rng), do: {hd(ctx.legal), rng}

  # -- potions: draw or stop ----------------------------------------------------------

  # Red Set 6 chips set aside are free moves: place them first. Draw while the odds
  # are under the threshold (always at 0); over it, return the white with the
  # flask or card B10 when that makes the next draw good again; else stop.
  defp potions(%{game: game, seat: seat, legal: legal} = ctx) do
    limit = threshold(ctx)
    p = Odds.next_draw(game, seat)

    cond do
      place = Enum.find(legal, &match?({:red, {:place, _}}, &1)) -> place
      :draw not in legal -> :stop
      p == 0 or p <= limit -> :draw
      return = white_return(ctx, limit) -> return
      true -> :stop
    end
  end

  # The highest bust chance the bot draws at: the round's `max_bust` plus the
  # margin shift per VP behind the best other player (capped; doubled in round 9).
  defp threshold(%{game: game, seat: seat, profile: profile}) do
    scores = Game.score(game)
    others = scores |> Map.delete(seat) |> Map.values()
    gap = if others == [], do: 0, else: Enum.max(others) - scores[seat]
    factor = if game.round == 9, do: 2, else: 1
    shift = (profile.margin_shift * gap * factor) |> min(@shift_cap) |> max(-@shift_cap)
    profile.max_bust[game.round] + shift
  end

  defp white_return(%{game: game, seat: seat, profile: profile, legal: legal}, limit) do
    with {:white, w} <- last_chip(Game.player(game, seat)),
         true <- Odds.after_return(game, seat, w) <= limit do
      cond do
        {:fortune, :return_white} in legal -> {:fortune, :return_white}
        :use_flask in legal and (w >= profile.flask_min_white or game.round == 9) -> :use_flask
        true -> nil
      end
    else
      _ -> nil
    end
  end

  defp last_chip(%{bowl: [chip | _]}), do: chip
  defp last_chip(%{drawn: [{chip, _} | _]}), do: chip
  defp last_chip(_p), do: nil

  # -- on-draw choices ----------------------------------------------------------------

  # Blue: the coloured chip that moves furthest; a white only when it cannot explode.
  defp blue(%{game: game, seat: seat, legal: legal}) do
    room = Potions.explode_above(game, seat) - Game.white_sum(game, seat)
    places = for {:place, chip} <- legal, do: chip
    {whites, coloured} = Enum.split_with(places, &match?({:white, _}, &1))
    safe = Enum.filter(whites, fn {:white, w} -> w <= room end)

    case Enum.sort_by(coloured, &elem(&1, 1), :desc) ++ Enum.sort_by(safe, &elem(&1, 1), :desc) do
      [] -> :return_all
      [chip | _] -> {:place, chip}
    end
  end

  # Coins (a buy) early, VP late; round 9 always VP.
  defp explosion(%{game: %{round: round}, profile: profile}) do
    if round < 9 and round < profile.explode_vp_from,
      do: {:explosion_choice, :buy},
      else: {:explosion_choice, :vp}
  end

  # -- concurrent choices --------------------------------------------------------------

  # Dominated choices are out: `:skip` when the card's gain is free (P3 costs a
  # ruby, P9 rat spaces: there it stays), `:return_all` when a chip of the B7 offer
  # could go in the pot for free.
  @paid_cards [:p3, :p9]

  defp undominated(%{game: game, legal: legal}) do
    dominated =
      if game.fortune_card in @paid_cards,
        do: [{:fortune, :return_all}],
        else: [{:fortune, :skip}, {:fortune, :return_all}]

    case legal -- dominated do
      [] -> legal
      better -> better
    end
  end

  defp random(list, rng) do
    {i, rng} = :rand.uniform_s(length(list), rng)
    {Enum.at(list, i - 1), rng}
  end

  defp first(legal, fun), do: Enum.find(legal, fun)
end
