# Quacks

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Bug reports from the game become GitHub issues with a replay bundle; see
"Debugging a report" in `docs/CONTEXT.md` (`mix quacks.replay ISSUE`). Production
env vars: `BUG_REPORT_GITHUB_TOKEN` (fine-grained, Issues read/write),
`BUG_REPORT_GITHUB_REPO` (optional) and `DEBUG_TOKEN` (opens `/debug/replay`).

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
