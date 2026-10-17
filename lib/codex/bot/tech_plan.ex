defmodule Codex.Bot.TechPlan do
  @moduledoc """
  Data for `Codex.Bot.Plan`: what to tech, what to keep in hand.

  - `plan/1`: the codex cards to tech, in order, 2 per turn. The start is the
    Bashing vs Finesse example of the community teching guide
    (`docs/research/codex-bot.md` §3.3); the rest of the codex follows, best
    first. The Blue and Black plans are the guide's 3-hero plans, keyed by the
    main (first) spec; they mix cards of the colour's three specs.
  - `worker_order/0`: the hand cards to make workers first (the community
    order; `docs/research/codex-bot.md` §3.1).
  """

  @plans %{
    "Bashing" =>
      ~w(iron-man iron-man revolver-ocelot intimidate regular-sized-rhinoceros hired-stomper
         regular-sized-rhinoceros eggship trojan-duck trojan-duck),
    "Finesse" =>
      ~w(nimble-fencer discord nimble-fencer two-step maestro appel-stomp grounded-guide
         cloud-sprite blademaster blademaster),
    # Blue and Black: the guide's 3-hero plans, by the main (first) spec.
    "Law" => ~w(brave-knight overeager-cadet injunction overeager-cadet justice-juggernaut
         censorship-council judgment-day insurance-agent lawbringer-gryphon community-service),
    "Peace" => ~w(overeager-cadet free-speech flagstone-garrison overeager-cadet drill-sergeant
         drill-sergeant spectral-flagbearer hallucination spectral-flagbearer boot-camp),
    "Truth" => ~w(tax-collector spectral-hound free-speech spectral-hound reteller-of-truths
         macciatus-the-whisperer reteller-of-truths eyes-of-the-chancellor liberty-gryphon
         liberty-gryphon),
    "Demonology" =>
      ~w(bone-collector bone-collector plague-spitter sickness blackhand-dozer voidblocker
         shrine-of-forbidden-knowledge doom-grasp zarramonde-the-obliterator
         zarramonde-the-obliterator),
    "Disease" =>
      ~w(dark-pact bone-collector shadow-blade hooded-executioner cursed-crow metamorphosis
         gorgon cursed-ghoul carrion-curse death-and-decay),
    "Necromancy" =>
      ~w(bone-collector bone-collector lich-s-bargain skeletal-lord lord-of-shadows dark-pact
         lord-of-shadows crypt-crawler zarramonde-the-obliterator dark-pact)
  }

  # Cards to tech when the plan is done and the side must still tech (< 10 workers).
  @fillers %{
    "Bashing" => ~w(the-boot wrecking-ball sneaky-pig harvest-reaper hired-stomper eggship),
    "Finesse" =>
      ~w(harmony leaping-lizard backstabber star-crossed-starlet maestro grounded-guide),
    "Law" => ~w(scribe tax-collector arresting-constable guardian-of-the-gates general-s-hammer),
    "Peace" => ~w(brave-knight elite-training flagstone-spy air-hammer debilitator-alpha),
    "Truth" => ~w(spectral-roc spectral-tiger hallucination spectral-flagbearer),
    "Demonology" => ~w(twilight-baron soul-stone shadow-blade banefire-golem dark-pact),
    "Disease" => ~w(plague-spitter crypt-crawler sickness abomination plague-lab),
    "Necromancy" => ~w(hooded-executioner necromancer wight corpse-catapult doom-grasp)
  }

  # Neutral (the card ratings), then Blue and Black (the teching guide's
  # worker picks first).
  @worker_order ~w(helpful-turtle fruit-ninja spark granfalloon-flagbearer tenderfoot
                   older-brother brick-thief wither timely-messenger bloom
                   bluecoat-musketeer traffic-director lawful-search building-inspector
                   jandra-the-negator skeletal-archery sacrifice-the-weak deteriorate)

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
