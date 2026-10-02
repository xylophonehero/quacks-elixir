# Agentic Elixir/Phoenix: best practices (researched 2026-10-02)

Scope: a new Phoenix LiveView project (Elixir 1.18.3 / OTP 27, board-game engine) where Claude Code
sub-agents write most of the code. Facts below were checked against hexdocs, hex.pm, GitHub and a
throwaway `mix phx.new probe` run with the locally installed `phx_new-1.8.15` archive.
Items marked ⚠️ come from one secondary source or were not reproduced locally.

---

## 0. Versions to pin (verified 2026-10-02)

| Package | Version | Date | Source |
|---|---|---|---|
| phoenix | 1.8.15 | 2026-09-25 | https://hex.pm/packages/phoenix/versions |
| phx_new archive | 1.8.15 | installed locally (`mix archive`) | https://phoenix.hexdocs.pm/Mix.Tasks.Phx.New.html |
| phoenix_live_view | 1.2.12 (generator pins `~> 1.2.0`) | 2026-09-16 | https://hex.pm/packages/phoenix_live_view |
| tailwind (hex installer) | `~> 0.5`, downloads Tailwind 4.3.3 | Phoenix 1.8.15 changelog | https://phoenix.hexdocs.pm/changelog.html |
| daisyui | git dep `saadeghi/daisyui` tag v5.5.20 | generated mix.exs | (local probe) |
| usage_rules | 1.2.8 | 2026-09-07 | https://hex.pm/packages/usage_rules |
| tidewave | 0.9.1 | 2026-09-23 | https://hex.pm/packages/tidewave |
| stream_data | 1.4.0 | 2026-07-14 | https://hex.pm/packages/stream_data |
| credo | 1.7.19 | 2026-06-05 | https://hex.pm/packages/credo |
| dialyxir | 1.4.8 | 2026-09-05 | https://hex.pm/packages/dialyxir |

```bash
mix archive.install hex phx_new 1.8.15          # already installed on this machine
mix phx.new quacks --no-ecto --no-mailer --no-gettext   # pick flags; see §7
```

---

## 1. Phoenix's AGENTS.md and `usage_rules`

**What ships.** Since 1.8.0, `mix phx.new` writes `AGENTS.md` at the project root (flag to skip:
`--no-agents-md`). Verified locally with 1.8.15: 436 lines, structured as:

```
## Project guidelines                 # hand-editable: "use mix precommit", "use Req, never httpoison/tesla"
### Phoenix v1.8 guidelines           # <Layouts.app>, current_scope, <.icon>, <.input>
### JS and CSS guidelines             # Tailwind v4 import syntax, no @apply, no inline <script>
### UI/UX & design guidelines
<!-- usage-rules-start -->
<!-- phoenix:elixir-start -->   ## Elixir / Mix / Test guidelines   (lines 49-104)
<!-- phoenix:phoenix-start -->  ## Phoenix guidelines
<!-- phoenix:html-start -->     ## Phoenix HTML guidelines
<!-- phoenix:liveview-start --> ## Phoenix LiveView guidelines      (lines 203-435, the bulk)
<!-- usage-rules-end -->
```

Everything between the HTML comment markers is owned by `usage_rules` and gets overwritten on
sync. Write project rules **above** `<!-- usage-rules-start -->`. (Zach Daniel on
https://elixirforum.com/t/what-is-the-way-i-should-think-about-agent-md-s-upgradability/72074 ;
Chris McCord: "usage_rules or copy paste ... this file can serve as a basis for your own guidelines".)

Note: the generated file says "**Always** manually write your own tailwind-based components
instead of using daisyUI" even though the generator installs daisyUI. Decide one way (see §7)
and delete the contradicting line.

**`usage_rules` (ash-project).** Packages ship `usage-rules.md` and optional `usage-rules/*.md`
sub-rules; the tool copies them into your rules file between fenced markers. Phoenix ships
sub-rules `phoenix:elixir`, `phoenix:phoenix`, `phoenix:ecto`, `phoenix:html`, `phoenix:liveview`
(`phoenix:all` = all of them). Built-ins: `:usage_rules` (`usage_rules:elixir`, `usage_rules:otp`).

v1.2.x is **config-driven** (mix.exs is the source of truth; packages removed from config are
removed from the file on next sync):

```elixir
# mix.exs
def project do
  [..., usage_rules: usage_rules()]
end

defp usage_rules do
  [
    file: "AGENTS.md",
    usage_rules: [:usage_rules, "phoenix:all"],        # add :stream_data etc. if they ship rules
    skills: [location: ".claude/skills", package_skills: []]  # optional
  ]
end

defp deps, do: [{:usage_rules, "~> 1.1", only: [:dev]}, ...]
```

```bash
mix usage_rules.sync                       # regenerate fenced sections; run after every `mix deps.update`
mix usage_rules.search_docs "check all" -p stream_data   # hexdocs search, markdown for agents
```

⚠️ Older posts (e.g. Hashrocket) show CLI-flag style
`mix usage_rules.sync AGENTS.md --all --inline ... --link-to-folder deps`. The current
hexdocs task page documents only the config form; treat flags as legacy.

Sources: https://usage-rules.hexdocs.pm/readme.html ,
https://usage-rules.hexdocs.pm/Mix.Tasks.UsageRules.Sync.html ,
https://github.com/ash-project/usage_rules ,
https://www.phoenixframework.org/blog/phoenix-1-8-released ,
https://hashrocket.com/blog/posts/supercharging-ai-assisted-development-in-phoenix-applications

---

## 2. Tidewave and other MCP servers

**Tidewave (Dashbit, Apache-2.0).** A Plug mounted in your dev endpoint; exposes the *running*
app over MCP at `http://localhost:4000/tidewave/mcp`. Tools: `project_eval` (run Elixir in the
app), `get_docs` (docs at the locked dep versions), `get_source_location`, `get_logs`,
`execute_sql_query` (skip if `--no-ecto`), plus `get_models`, `get_ecto_schemas`,
`get_ash_resources` (⚠️ last three from a secondary write-up). Works best with LiveView >= 1.1.

```elixir
# mix.exs
{:tidewave, "~> 0.9", only: :dev}

# lib/quacks_web/endpoint.ex — right above `if code_reloading? do`
if Mix.env() == :dev do
  plug Tidewave
end

# config/dev.exs (recommended by Tidewave for LiveView 1.1+)
config :phoenix_live_view, debug_heex_annotations: true, debug_attributes: true
```

```bash
# or: mix archive.install hex igniter_new && mix igniter.install tidewave
claude mcp add --transport http tidewave http://localhost:4000/tidewave/mcp   # do NOT pick "Authenticate"
# in Claude Code: /mcp  -> expect "connected"
```

Security: binds to localhost only; `allow_remote_access` and `allowed_origins` exist for
containers. Tidewave Web (paid, in-browser agent) is separate; the MCP server is free.

**Other MCP servers worth knowing**
- ElixirLS built-in MCP (v0.29+, Aug 2025): `elixirLS.mcpEnabled: true`, TCP port
  `3789 + hash(workspace)`, tools `find_definition`, `get_environment`, `get_docs`,
  `get_type_info`, `find_implementations`, `get_module_dependencies`; needs the bundled
  `tcp_to_stdio_bridge.exs` for Claude Code. ⚠️ Only useful if you also run ElixirLS; Tidewave's
  `get_docs` + `mix usage_rules.search_docs` cover most of this.
  https://elixirforum.com/t/elixirls-mcp-server/71992
- `hexdocs-mcp` (npm, `npx -y hexdocs-mcp`) and `hexpm-mcp` (Elixir, 24 tools incl. OSV checks).
  ⚠️ versions not verified. https://github.com/joshrotenberg/hexpm-mcp

Recommendation: Tidewave only. One MCP, zero extra processes, and it is the one José Valim's
team maintains for exactly this use.

Sources: https://github.com/tidewave-ai/tidewave_phoenix ,
https://tidewave.hexdocs.pm/mcp_claude_code.html ,
https://dashbit.co/blog/the-path-to-tidewave ,
https://codex.danielvaughan.com/2026/05/24/codex-cli-elixir-phoenix-development-mcp-servers-tidewave-hexdocs-workflows/

---

## 3. Verification loop for agents

**What `mix phx.new` 1.8.15 generates (verified):**

```elixir
preferred_envs: [precommit: :test],
aliases: [
  precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
]
```

**Recommended extension** (add credo + dialyxir + the test-side warnings flag):

```elixir
# mix.exs deps
{:credo, "~> 1.7", only: [:dev, :test], runtime: false},
{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
{:stream_data, "~> 1.4", only: [:dev, :test]},

# aliases
precommit: [
  "compile --warnings-as-errors",
  "deps.unlock --unused",
  "format --check-formatted",       # fail, don't silently rewrite, when run by CI
  "credo --strict",
  "test --warnings-as-errors"
],
# dialyzer is slow (minutes on first PLT build). Keep it out of precommit; run on CI / before PR.
```

`mix test --warnings-as-errors` (Elixir >= 1.12) catches warnings emitted while compiling *test*
files; `mix compile --warnings-as-errors` is still needed for `lib/`. Use both
(https://dashbit.co/blog/tests-with-warnings-as-errors).

**Loop an agent should run after each change (fast to slow):**

```bash
mix format                              # 1. auto-fix style; never argue with it
mix compile --warnings-as-errors        # 2. compiler is the best reviewer Elixir has
mix test --failed                       # 3. re-run what was red last time
mix test path/to/changed_test.exs       # 4. the file you touched
mix precommit                           # 5. full gate before declaring "done"
mix dialyzer                            # 6. once per PR / on CI (cache _build and priv/plts)
```

Why this order: the generated AGENTS.md already tells agents "use `mix precommit` when done" and
"run previously failed tests with `mix test --failed`"; steps 1-4 keep the feedback under a few
seconds so the agent iterates instead of guessing. Elixir's fast compile + precise warnings is
the main reason people report Claude Code does unusually well in Elixir
(https://elixirforum.com/t/elixir-is-a-cheatcode-when-using-claude-code/74656).

Consider a Claude Code `PostToolUse` hook on `Edit|Write` for `*.ex|*.exs` that runs
`mix format <file>` and `mix compile --warnings-as-errors`; the `elixir-phoenix` plugin author
found prose rules had "0% firing rate" while hooks always fire
(https://elixirforum.com/t/plugin-for-claude-code-amp-codex-pi-opencode-specialist-agents-and-an-enforced-elixir-phoenix-development-workflow/76040).

Credo config: `mix credo gen.config`, then enable `Credo.Check.Readability.Specs` so missing
`@spec` on public functions fails `--strict`.

---

## 4. Code conventions that help agents

Consensus across Elixir Forum CONVENTIONS.md threads, Allan MacGregor's write-up, the
BobbieBarker ADR set, and the generated Phoenix rules:

1. **Pure core, thin shell.** Game rules live in plain modules under `lib/quacks/` with no
   process, no PubSub, no Phoenix import. `Quacks.Game.apply(game, action) :: {:ok, game} | {:error, reason}`.
   A GenServer per table only holds the struct and broadcasts; LiveView only renders and
   forwards events. (Fly.io turn-based game post; adamvietro/game_site architecture.)
2. **Pattern-match in function heads instead of `if`/`cond`/`case` on the same value.** The head
   documents the contract; agents and humans read it the same way.
3. **Explicit structs with `@enforce_keys` and `@type t`.** Make illegal states unrepresentable:
   phases as atoms in a closed `@type phase :: :drawing | :bidding | :scoring`, not strings.
4. **`@spec` on every public function, `@doc` with an `iex>` example, `@moduledoc` on every module.**
   Doctests make the docs executable, so an agent cannot leave stale examples.
5. **Return `{:ok, _} | {:error, reason}`; chain with `with`.** Reserve `!` functions for
   programmer errors. Never `Map.get(x, k, default)` to paper over a missing key.
6. **One module per concept, verb-first function names** (`draw_token/1`, not `token_draw/1`);
   contexts (`Quacks.Games`, `Quacks.Lobby`) are the only entry points the web layer calls.
7. **No defensive dual-handling** (atom *and* string keys). Agents do this by default; forbid it.
8. **`@impl true` on every callback**; `start_supervised!/1` in tests; no `Process.sleep/1`
   (both already in the generated `phoenix:elixir` rules).
9. **Keep the "don'ts" short and specific.** Forum experience: long general guidelines decay;
   short, specific, checkable rules hold. Put a rule in a hook or Credo check when you can.

Sources: https://elixirforum.com/t/coding-with-llms-conventions-md-for-elixir-do-you-have-your-own-what-does-it-contain/69677 ,
https://elixirforum.com/t/heres-how-im-coding-elixir-with-ai-results-are-mixed-mostly-positive-how-about-you/71588 ,
https://allanmacgregor.com/posts/why-ai-coding-agents-love-elixir ,
https://github.com/BobbieBarker/adrs (42 Elixir/OTP ADRs with Wrong/Correct examples, `.claude/rules/` ready),
https://fly.io/blog/building-a-distributed-turn-based-game-system-in-elixir/ ,
https://hexdocs.pm/elixir/code-anti-patterns.html

---

## 5. Test practices for agent-written code

- **ExUnit + doctests on every pure module**: `doctest Quacks.Game` in the test file. Cheap,
  and forces examples in `@doc`.
- **Property tests for the engine** with StreamData 1.4 (`use ExUnitProperties`). Good
  invariants for a board game: token conservation (bag + pot + discard is constant), a legal
  move never raises, `apply/2` is deterministic for a seeded RNG, scoring is monotone, replaying
  a recorded action log reproduces the final state, every reachable state has at least one legal
  action or is terminal.

```elixir
property "applying any legal action keeps token conservation" do
  check all game <- GameGen.game(), action <- GameGen.legal_action(game), max_runs: 200 do
    {:ok, next} = Quacks.Game.apply(game, action)
    assert Quacks.Game.token_count(next) == Quacks.Game.token_count(game)
  end
end
```

  Generators: `member_of/1`, `one_of/1`, `fixed_map/1`, `list_of/1`, `uniq_list_of/1`,
  `frequency/1`, `bind/2`, `map/2`, `constant/1`. Set
  `config :stream_data, max_runs: if(System.get_env("CI"), do: 500, else: 50)` in
  `config/test.exs` so local runs stay fast. StreamData is stateless; for model-based stateful
  testing use `stream_state` (⚠️ small project) or PropCheck.
- **Inject randomness** (`:rand` seed or a shuffle function) so engine tests are reproducible;
  the agent cannot "fix" a flaky test it cannot reproduce.
- **LiveView tests** with `Phoenix.LiveViewTest` + `lazy_html` (already generated, `only: :test`);
  test the context API first, LiveView second.
- Workflow: `mix test --failed` -> single file -> `mix test`. Tell agents a red test is never
  "fine because it's demo code" (a recurring failure mode reported on the forum).

Sources: https://stream-data.hexdocs.pm/ExUnitProperties.html ,
https://github.com/whatyouhide/stream_data , https://elixirschool.com/en/lessons/testing/stream_data ,
https://github.com/hauleth/stream_state

---

## 6. Project docs for agents

Claude Code reads `AGENTS.md` natively when there is no `CLAUDE.md`; when both exist, make
`CLAUDE.md` a thin layer that imports it (`@AGENTS.md` on line 1; imports nest up to 4 hops).
Keep each instruction file under ~200 lines of *your* content; the generated Phoenix section
is long but loads once and is what Phoenix's team tuned. Use `.claude/rules/*.md` with
`paths:` frontmatter for rules that only matter in part of the tree.

Suggested layout:

```
AGENTS.md            # project rules ABOVE the usage-rules markers; synced Phoenix rules below
CLAUDE.md            # "@AGENTS.md" + Claude-only notes (sub-agent etiquette, hooks)
.claude/rules/
  engine.md          # paths: [lib/quacks/**, test/quacks/**]  -> pure functions, property tests
  liveview.md        # paths: [lib/quacks_web/**]              -> Layouts.app, no logic in LV
docs/
  CONTEXT.md         # domain glossary: Ingredient, Bag, Pot, Flask, Ruby, Explosion, Round, Phase
  adr/0001-pure-engine-core.md, 0002-no-ecto.md, 0003-daisyui.md ...
  research/          # this file
```

- **CONTEXT.md / glossary**: one line per domain term, the Elixir name for it, and the module
  that owns it. Agents name things consistently only if the vocabulary is written down.
- **ADRs** (Nygard format: Context / Decision / Consequences, status line, one page). Record stack
  decisions early (LiveView-only, no Ecto, daisyUI yes/no, RNG strategy); agents otherwise drift
  back to defaults. Link ADRs from AGENTS.md.
- Run `/doctor prompt-audit` periodically; contradictory rules are picked arbitrarily.

Sources: https://code.claude.com/docs/en/memory , https://agents.md ,
https://adr.github.io/ , https://github.com/BobbieBarker/adrs

---

## 7. Generator flags, Tailwind v4 and daisyUI

`mix phx.new` 1.8.15 flags that matter here: `--no-ecto`, `--no-mailer`, `--no-gettext`,
`--no-dashboard`, `--no-agents-md`, `--no-tailwind`, `--no-esbuild`, `--no-assets`,
`--adapter bandit|cowboy` (default bandit), `--binary-id`, `--umbrella`.
**There is no `--no-daisyui` flag** (requested on
https://elixirforum.com/t/option-to-pass-a-no-daisy-flag-when-creating-a-new-phoenix-project/72106 ,
not merged as of 1.8.15).

Tailwind v4 wiring (verified in the probe): no `tailwind.config.js`; `assets/css/app.css` starts
with `@import "tailwindcss" source(none);` plus `@source` lines for `../css`, `../js`,
`../../lib/quacks_web` and the colocated-hooks build dir. Keep that block; the generated
AGENTS.md forbids `@apply` and inline `<script>`.

daisyUI is a git dep in `mix.exs` (`{:daisyui, github: "saadeghi/daisyui", tag: "v5.5.20",
sparse: "packages/bundle", app: false, compile: false}`) loaded via
`@plugin "daisyui/packages/bundle/daisyui" { themes: false; }` plus two
`@plugin "daisyui/packages/bundle/daisyui-theme" {...}` blocks (light "Phoenix" / dark "Elixir",
switched by `data-theme` set in `root.html.heex`). `core_components.ex` uses daisyUI classes
(`btn`, `badge`, `alert`, `fieldset`, `input`, `table`...) in 12 places.

**Keep daisyUI (recommended for a game UI you want to ship fast):** delete the "never use daisyUI"
line from AGENTS.md; agents then get a theme system and components for free. Add a `quacks` theme
with https://daisyui.com/theme-generator/ .

**Remove daisyUI:** drop the `:daisyui` dep, delete the three `@plugin "daisyui/..."` blocks in
`app.css`, remove the theme toggle script in `root.html.heex`, and rewrite the daisyUI classes in
`core_components.ex` and `layouts.ex` as plain Tailwind. Then `mix assets.build`. Expect an hour
of work; the forum thread calls it "a huge headache" for a reason.
(Petar Radošević's note describes the pre-1.8.1 vendor-file layout, where the plugin lived in
`assets/vendor/daisyui.js`; in 1.8.15 it is a mix dep, so follow the steps above instead.)

Sources: https://phoenix.hexdocs.pm/Mix.Tasks.Phx.New.html , https://phoenix.hexdocs.pm/changelog.html ,
https://petar.dev/notes/removing-daisy-ui-from-phoenix/ , https://daisyui.com/docs/config/

---

## Minimal starting checklist

```bash
mix phx.new quacks --no-ecto --no-mailer --no-gettext      # keep LiveView, Tailwind, AGENTS.md
cd quacks
# deps: usage_rules, tidewave, credo, dialyxir, stream_data (see §1-3,5)
mix deps.get && mix usage_rules.sync
echo '@AGENTS.md' > CLAUDE.md
claude mcp add --transport http tidewave http://localhost:4000/tidewave/mcp
mix precommit
```
