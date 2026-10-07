# Elixir and Phoenix, through Quacks: Resources

Versions pinned to the repo: Elixir 1.18.3 and OTP 27.3.4.9 (`Dockerfile`), Phoenix 1.8.15, Phoenix LiveView 1.2.12, Phoenix PubSub 2.3.0 (`mix.lock`).

Verification note (2026-10-07): the build sandbox blocks hexdocs.pm, fly.io, elixir-lang.org, erlang.org and elixirforum.com, so no URL here could be fetched live. Instead each hexdocs page was checked against the guide file at the pinned git tag of its source repo (hexdocs names a page after its file), each Fly page against `superfly/docs`, and each community link against the official elixir-lang.org site source or Phoenix's own community guide. The one link not checked that way is marked.

## Knowledge

### The repo itself (first stop)

- [Guide: How Quacks is built](https://github.com/xylophonehero/quacks-elixir/blob/staging/docs/GUIDE.md)
  The repo's own 11-chapter guide, written for a React developer. Use for: every lesson; the lessons are a path through it. Line numbers drift; function names stay searchable.
- [docs/CONTEXT.md](https://github.com/xylophonehero/quacks-elixir/blob/staging/docs/CONTEXT.md)
  The game glossary: chips, phases, log entries. Use for: any game term a lesson uses.

### Elixir (official, v1.18.3)

- [Elixir guide: Processes](https://hexdocs.pm/elixir/1.18.3/processes.html)
  Spawn, send, receive, links. Use for: lesson 3 and any "what is a process" question.
- [Elixir guide: Pattern matching](https://hexdocs.pm/elixir/1.18.3/pattern-matching.html)
  The match operator, pin, tuples and lists. Use for: lesson 2, reading any function head.
- [Elixir guide: case, cond, and if](https://hexdocs.pm/elixir/1.18.3/case-cond-and-if.html)
  Guards and the branching forms. Use for: lesson 2, `when` clauses.
- [Elixir guide: Structs](https://hexdocs.pm/elixir/1.18.3/structs.html)
  `defstruct`, update syntax, why structs are not plain maps. Use for: `%Quacks.Game{}` and `%Quacks.Player{}`.
- [`with/1` in Kernel.SpecialForms](https://hexdocs.pm/elixir/1.18.3/Kernel.SpecialForms.html#with/1)
  The reference for `with`, including `else`. Use for: Session.apply, the bot tick, BugReports.submit.
- [Mix and OTP: Client-server communication with GenServer](https://hexdocs.pm/elixir/1.18.3/genservers.html)
  The official GenServer walkthrough. Use for: lesson 3, `call` versus `cast`.
- [Mix and OTP: Supervision trees and applications](https://hexdocs.pm/elixir/1.18.3/supervisor-and-application.html)
  Supervisors and the application callback. Use for: lesson 5, `Quacks.Application`.
- [`GenServer` module docs](https://hexdocs.pm/elixir/1.18.3/GenServer.html)
  Callbacks, timeouts, return tuples. Use for: `@idle_timeout`, `handle_info(:timeout, ...)`.
- [Erlang `rand` module](https://www.erlang.org/doc/apps/stdlib/rand.html) (not checked against source; OTP 27 docs layout)
  The `_s` functions that take and return explicit state. Use for: lesson 2, why the engine bans `:rand.uniform/1`.

### Phoenix and LiveView (official)

- [Phoenix LiveView 1.2.12: Welcome](https://hexdocs.pm/phoenix_live_view/1.2.12/welcome.html)
  The overview: life-cycle, two mounts, how events flow. Use for: lessons 1 and 4.
- [`Phoenix.LiveView` module docs, 1.2.12](https://hexdocs.pm/phoenix_live_view/1.2.12/Phoenix.LiveView.html)
  The callbacks (`mount`, `handle_event`, `handle_info`) in the authors' words. Use for: lesson 1's primary source.
- [LiveView: Bindings](https://hexdocs.pm/phoenix_live_view/1.2.12/bindings.html)
  `phx-click`, `phx-value-*` and the other client bindings. Use for: how a tap becomes an event.
- [LiveView: Assigns and HEEx templates](https://hexdocs.pm/phoenix_live_view/1.2.12/assigns-eex.html)
  Change tracking and what makes a diff small or large. Use for: lessons 4 and 7.
- [LiveView: Deployments and recovery](https://hexdocs.pm/phoenix_live_view/1.2.12/deployments.html)
  What happens to open tabs during a deploy. Use for: lesson 8.
- [`Phoenix.PubSub` 2.3.0](https://hexdocs.pm/phoenix_pubsub/2.3.0/Phoenix.PubSub.html)
  `subscribe/2`, `broadcast/3`, and how it works across nodes. Use for: lessons 1 and 9.
- [Phoenix 1.8.15: Deploying on Fly.io](https://hexdocs.pm/phoenix/1.8.15/fly.html)
  Phoenix's own Fly guide. Use for: lesson 8.

### Fly.io (how Quacks deploys)

Quacks runs one always-on `shared-cpu-1x` machine with 256 MB in `ams`, with the volume `quacks_data` at `/data` (`fly.toml`, `fly.staging.toml`). `.github/workflows/fly-deploy.yml` deploys `master` to `quacks` and `staging` to `quacks-staging`.

- [Fly: Elixir getting started](https://fly.io/docs/elixir/getting-started/)
  Launching a Phoenix app on Fly. Use for: lesson 8.
- [Fly: App configuration (fly.toml)](https://fly.io/docs/reference/configuration/)
  Every `fly.toml` key: `[mounts]`, `[http_service]`, `auto_stop_machines`, `[[vm]]`. Use for: reading `fly.toml`.
- [Fly: Volumes overview](https://fly.io/docs/volumes/overview/)
  A volume belongs to one machine. Use for: lessons 8 and 9, why Quacks stays on one machine.
- [Fly: Continuous deployment with GitHub Actions](https://fly.io/docs/launch/continuous-deployment-with-github-actions/)
  The pattern `fly-deploy.yml` follows. Use for: lesson 8.
- [Fly: Clustering Elixir apps](https://fly.io/docs/elixir/the-basics/clustering/)
  DNS clustering of BEAM nodes on Fly. Use for: lesson 9 (`DNSCluster` is already in the supervision tree, switched off).

### Books

- [Book: _Elixir in Action_, 3rd edition, by Saša Jurić (Manning)](https://www.manning.com/books/elixir-in-action-third-edition)
  The best book on the BEAM's process model for people coming from other languages; featured on elixir-lang.org. Use for: lessons 3, 5, 7 (processes, supervision, the runtime).
- [Book: _Programming Phoenix LiveView_ by Bruce Tate and Sophie DeBenedetto (Pragmatic)](https://pragprog.com/titles/liveview/programming-phoenix-liveview/)
  Listed in Phoenix's own community guide. Use for: LiveView lifecycle and components in depth.

## Wisdom (Communities)

- [Elixir Forum](https://elixirforum.com/)
  The main, well-moderated forum; the core teams answer there. Use for: design questions ("one GenServer per game?"), review of a pattern before steering an agent.
- [Elixir Slack](https://elixir-slack.community/)
  Linked from elixir-lang.org. Use for: quick questions, `#phoenix` and `#liveview` channels.
- [Elixir Discord](https://discord.gg/elixir)
  Linked from elixir-lang.org and Phoenix's community guide. Use for: real-time help, the `#phoenix` channel.

## Gaps

- No live-verified source yet for BEAM memory per process and scheduler internals (lesson 7). Candidates: _The BEAM Book_ and the Erlang efficiency guide; check them before that lesson.
- Distributed registries for lesson 9 (Horde, `:global`, `:pg`) need a pinned, primary source.
