defmodule Codex.Bot.TechPlan do
  @moduledoc """
  Data for `Codex.Bot.Plan`: what to tech, what to keep in hand.

  - `plan/1`: the codex cards to tech, in order, 2 per turn. The start is the
    Bashing vs Finesse example of the community teching guide
    (`docs/research/codex-bot.md` §3.3); the rest of the codex follows, best
    first.
  - `worker_order/0`: the hand cards to make workers first (the community
    order; `docs/research/codex-bot.md` §3.1).
  """

  @plans %{
    "Bashing" =>
      ~w(iron-man iron-man revolver-ocelot intimidate regular-sized-rhinoceros hired-stomper
         regular-sized-rhinoceros eggship trojan-duck trojan-duck),
    "Finesse" =>
      ~w(nimble-fencer discord nimble-fencer two-step maestro appel-stomp grounded-guide
         cloud-sprite blademaster blademaster)
  }

  # Cards to tech when the plan is done and the side must still tech (< 10 workers).
  @fillers %{
    "Bashing" => ~w(the-boot wrecking-ball sneaky-pig harvest-reaper hired-stomper eggship),
    "Finesse" =>
      ~w(harmony leaping-lizard backstabber star-crossed-starlet maestro grounded-guide)
  }

  @worker_order ~w(helpful-turtle fruit-ninja spark granfalloon-flagbearer tenderfoot
                   older-brother brick-thief wither timely-messenger bloom)

  @doc "The tech plan of a spec (`[]` for a spec with no plan)."
  @spec plan(String.t()) :: [String.t()]
  def plan(spec), do: Map.get(@plans, spec, [])

  @doc "The fillers of a spec: what to tech after the plan while the side must tech."
  @spec fillers(String.t()) :: [String.t()]
  def fillers(spec), do: Map.get(@fillers, spec, [])

  @doc "The starter cards to make workers first (best worker first)."
  @spec worker_order() :: [String.t()]
  def worker_order, do: @worker_order
end
