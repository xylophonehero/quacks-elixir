# Deployment options for Quacks (researched 2026-10-03)

App facts (from `mix.exs`, `config/runtime.exs`, `config/prod.exs`): Phoenix 1.8.15, LiveView 1.2,
Bandit, no Ecto, no `rel/` dir, no `assets/package.json`. Prod reads `SECRET_KEY_BASE` (raises if
missing), `PHX_HOST` (default `example.com`), `PORT` (default 4000), `PHX_SERVER`, optional
`DNS_CLUSTER_QUERY`. Binds `::` (IPv6 any, dual-stack on Linux). `force_ssl` with
`rewrite_on: [:x_forwarded_proto]` is already set, so TLS-terminating proxies work.

**Key constraint:** games live in GenServers. Any host that stops, sleeps or redeploys the VM loses
every running game. "Sleeps when idle" = games die between sessions. That is acceptable only if
nobody leaves a game mid-way overnight.

⚠️ = could not verify on a primary source, or sources conflict.

## Summary table

| Host | Cost / month | Always-on? | WebSockets | Effort | Custom domain + TLS |
|---|---|---|---|---|---|
| Gigalixir free | $0 | Yes, but scaled to 0 after 30 days with no deploy | Yes | S-M | Yes, free |
| Fly.io 256 MB | ~$2.19 (+$2 if dedicated IPv4) | Yes if `auto_stop_machines = "off"` | Yes | S | Yes (10 certs free) |
| Northflank sandbox | $0 (card required) | Yes, "no sleeping" | Yes ⚠️ | M | Yes, free |
| Hetzner CX23 | €5.49 + VAT (€4.99 IPv6-only) | Yes | Yes (you run it) | M-L | You do it (Caddy) |
| Home Pi + Cloudflare Tunnel | $0 + domain + power | As long as your Pi is up | Yes | M | Yes (domain on CF) |
| Home Pi + Tailscale Funnel | $0 | As long as your Pi is up | ⚠️ likely | M | `*.ts.net` only |
| Oracle Always Free A1 | $0 | Yes, but idle reclamation | Yes (you run it) | L | You do it |
| Railway Hobby | $5 (incl. $5 usage) | Yes | Yes | S | Yes (2 domains) |
| Render | Free sleeps; Starter $7 | Free: no (15 min idle) | Yes | S | Yes |
| Koyeb | Free sleeps; Pro $29 | Free: no (1 h idle) | Yes | S | Yes |
| Zeabur | $0-5 plan + your own server | n/a (shared cluster gone) | — | — | — |

## Fly.io
- No free tier for new orgs. Trial = 2 h machine runtime or 7 days. Pay-as-you-go, no plan fee.
- shared-cpu-1x continuous: 256 MB **$2.19**, 512 MB **$3.69**, 1 GB **$6.70**. Stopped machine:
  $0.15 per GB rootfs / 30 days. Shared IPv4 + IPv6 free; dedicated IPv4 $2. First 10 single-host
  TLS certs free, then $0.10. ⚠️ Old "invoices under $5 waived" rule is not on the page any more.
- `fly launch` detects Phoenix, runs `phx.gen.release --docker`, writes `fly.toml`, sets
  `SECRET_KEY_BASE`, adds `ERL_AFLAGS "-proto_dist inet6_tcp"` (only matters for clustering).
  Deploy = `fly deploy` (remote builder, no local Docker needed).
- **Auto-stop default kills games.** `fly launch` sets `auto_stop_machines = "stop"`,
  `min_machines_running = 0`. With one machine, the proxy checks "every few minutes" and stops it
  when load is 0. Open LiveView sockets count as load (heartbeat every 30 s) ⚠️ docs do not say so
  explicitly. When the last tab closes, the machine stops and all GenServer games are lost. Fix: set
  `auto_stop_machines = "off"` (or `min_machines_running = 1`). Each `fly deploy` also restarts.
- 256 MB is tight for BEAM + LiveView but fine for a few players; take 512 MB if you see OOM.
- https://docs.fly.io/about/pricing · https://docs.fly.io/launch/autostop-autostart/ ·
  https://docs.fly.io/reference/fly-proxy-autostop-autostart/ · https://docs.fly.io/elixir/getting-started

## Gigalixir (Elixir-specific PaaS)
- Free tier: **1 instance, 0.5 GB**, no card ⚠️ (not stated on pricing page), custom domain + SSL
  included. App is scaled to 0 replicas if you do not deploy for 30 days (warning email at day 23).
  Standard tier from $10/month, never sleeps.
- Deploy = `git push gigalixir` with buildpacks. Needs `elixir_buildpack.config` (versions) and, for
  assets, `phoenix_static_buildpack.config` + an `assets/package.json` whose `deploy` script runs
  `cd .. && mix assets.deploy`. Quacks has no `package.json` and the folder is **not a git repo
  yet**, so both must be added. ⚠️ Docs example pins Elixir 1.17 / OTP 26; check 1.18 / 27 support.
- WebSockets: Phoenix-first host, LiveView works ⚠️ not stated on a page I fetched.
- https://www.gigalixir.com/pricing · https://docs.gigalixir.com/getting-started-guide

## Northflank
- Developer Sandbox: 2 services, 2 jobs, 1 addon, "always-on compute – no sleeping". **Payment
  method required** for all plans. Docs say "should not be used for production applications".
  ⚠️ Free service size not stated; smallest paid plan nf-compute-10 = 0.1 vCPU / 256 MB, $2.70.
- Free SSL + custom domains on all tiers. Deploys a Dockerfile from Git.
- https://northflank.com/pricing · https://northflank.com/docs/v1/application/billing/pricing-on-northflank

## Render
- Free web service spins down after **15 min** with no inbound HTTP or WebSocket message; ~1 min
  cold start; 750 free hours/month; data lost on spin-down. WebSockets supported; custom domain +
  TLS on free. Starter $7 (0.5 vCPU, 512 MB) is always-on. Hobby workspace is free (Pro $25 flat).
- Must bind `PORT` (default 10000) on 0.0.0.0; our `::` bind should cover it ⚠️ untested.
- https://render.com/docs/free · https://render.com/docs/web-services · https://render.com/pricing

## Railway
- Trial $5 one-time (30 days, no card). Free plan $0 with $1/month credit and **0 custom domains**.
  Hobby **$5/month incl. $5 usage**, 2 custom domains. RAM ~$10/GB-month, CPU ~$20/vCPU-month,
  per second. ~256 MB idle BEAM ≈ $2.50 + small CPU, so it fits in the $5 ⚠️ estimate.
- No forced sleep (app sleeping is opt-in). WebSockets work ⚠️ not on pricing page.
- https://railway.com/pricing

## Koyeb
- One free instance per org: 512 MB, 0.1 vCPU, Frankfurt or Washington, **scales to zero after 1 h
  without traffic** (cannot disable). Since Feb 2026 a card + $29 pre-auth hold is required and
  sign-up defaults to Pro ($29/month incl. $10 compute). Not a fit.
- https://www.koyeb.com/pricing · https://www.koyeb.com/docs/run-and-scale/scale-to-zero

## Zeabur
- Shared cluster deprecated: no new projects since 2026-03-15, no new services since 2026-04-01.
  Plans (Free / Dev $5 / Pro $19) now manage **your own** servers. Only useful on top of a VPS.
- https://zeabur.com/pricing · https://zeabur.com/changelogs/phasing-out-shared-cluster

## Hetzner Cloud VPS
- CX23 (2 vCPU, 4 GB, 40 GB NVMe, 20 TB traffic): **€5.49/month excl. VAT** after the 2026
  increases (was €3.99). CAX11 (ARM) ~€5.99. Primary IPv4 included; IPv6-only saves €0.50.
  ⚠️ Hetzner's own page did not render prices and showed the shared plans as "currently
  unavailable" (Sept-Oct 2026); prices from costgoat / third parties.
- Two ways: (a) `MIX_ENV=prod mix release` built on a matching Linux box/CI, copied over, run by
  systemd with an `EnvironmentFile`; (b) `mix phx.gen.release --docker` image + `docker run`.
  Put Caddy in front for automatic Let's Encrypt TLS and WebSocket proxying. You own patching.
- IPv6-only box: friends on IPv4-only networks cannot reach it unless you front it with Cloudflare.
- https://www.hetzner.com/cloud/cost-optimized · https://costgoat.com/pricing/hetzner

## Oracle Cloud Always Free (ARM A1)
- 1,500 OCPU-h + 9,000 GB-h/month = 2 OCPU / 12 GB (one or two VMs), home region only. Idle VMs are
  **reclaimed** when CPU, network and memory are all < 20 % (p95) for 7 days. A hobby game server
  will look idle. ⚠️ Upgrading to Pay-As-You-Go reportedly exempts you (not on the page). "Out of
  host capacity" errors are common. Same release/Docker + Caddy work as Hetzner. Effort L.
- https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm

## Raspberry Pi / home server
- Run the release (ARM64 build) or Docker image under systemd. Power ~€1/month ⚠️ estimate.
- **Cloudflare Tunnel** (`cloudflared`): free, unmetered, WebSockets on by default. A named tunnel
  needs a domain on Cloudflare DNS (~$10/year). Quick tunnels (`*.trycloudflare.com`) need no
  account but get a random URL each start, 200 in-flight request cap, no SLA: demo only.
- **Tailscale Funnel**: free on Personal plan, ports 443/8443/10000, auto TLS, but only
  `<machine>.<tailnet>.ts.net` (no custom domain) and fixed bandwidth limits. ⚠️ WebSocket support
  not stated in docs.
- Uptime = your home internet and power. Nick's laptop asleep = site down.
- https://tailscale.com/kb/1223/funnel ·
  https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/ ·
  https://flaviocopes.com/cloudflare-quick-tunnels/

## Phoenix-side checklist (any host)
- `mix phx.gen.release --docker` writes `Dockerfile`, `.dockerignore`, `rel/overlays/bin/server`
  (sets `PHX_SERVER=true`). Migrate script and `lib/quacks/release.ex` are only added with Ecto ⚠️.
  Images: builder `hexpm/elixir:<ver>-erlang-<ver>-debian-<ver>`, runner `debian:<ver>`.
- Runtime env: `SECRET_KEY_BASE` (`mix phx.gen.secret`), `PHX_HOST` (public hostname, **must** be
  set — default `example.com` breaks LiveView), `PORT` (platform-given), `PHX_SERVER=true` (or use
  `bin/server`). Ignore `DNS_CLUSTER_QUERY` (no clustering).
- `check_origin`: prod default is `true` = WebSocket origin must match `url: [host: PHX_HOST]`. If
  the app answers on two hosts (e.g. `quacks.fly.dev` and a custom domain), set
  `check_origin: ["https://a.example", "https://b.fly.dev"]` in `runtime.exs`, or LiveView will
  reconnect-loop with "could not check origin".
- Every deploy restarts the VM = all games lost. Deploy when nobody is playing.
- https://phoenix.hexdocs.pm/releases.html

## Ranked recommendation (ponytail: cheapest that stays always-on with WebSockets)
1. **Fly.io, 1 × shared-cpu-1x 256 MB, `auto_stop_machines = "off"`** — ~$2.19/month, shared IPv4,
   free TLS + custom domain, `fly launch` does the Phoenix work for us. Least effort per euro.
2. **Gigalixir free** — $0 and Phoenix-native, but needs the `package.json`/buildpack shim, a git
   repo, and a deploy every 30 days. Best if Nick wants literally $0.
3. **Northflank sandbox** — $0, always-on, but card required and "not for production".
4. **Railway Hobby** — $5 flat, easy, no gotchas.
5. **Hetzner CX23** — €5.49 + VAT; worth it only if the box also hosts other things.
6. Home Pi + Cloudflare Tunnel — free if a Pi already runs 24/7.
Skip: Render free / Koyeb free (sleep kills games), Zeabur (no shared hosting), Oracle (reclaim).

## Top pick: Fly.io in 10 steps
1. `brew install flyctl && fly auth signup` (card needed after the trial).
2. `cd ~/dev/quacks-elixir && fly launch --no-deploy` — accept Phoenix detection, pick `ams`/`fra`, no Postgres.
3. Check it generated `Dockerfile`, `.dockerignore`, `rel/overlays/bin/server`, `fly.toml`.
4. In `fly.toml` `[http_service]`: `auto_stop_machines = "off"`, `min_machines_running = 1`.
5. In `fly.toml` `[env]`: `PHX_HOST = "<app>.fly.dev"` (`PORT = "8080"` is set by launch).
6. `fly secrets list` — confirm `SECRET_KEY_BASE`; else `fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)`.
7. `fly deploy`, then `fly scale count 1` and `fly scale memory 256` (512 if OOM).
8. Open `https://<app>.fly.dev`, start a game in two browsers, confirm LiveView connects.
9. Optional domain: `fly certs add quacks.example.com`, add the DNS records it prints, set
   `PHX_HOST` to it and add both hosts to `check_origin`.
10. `fly logs` to watch; redeploy with `fly deploy` only when no game is running.
