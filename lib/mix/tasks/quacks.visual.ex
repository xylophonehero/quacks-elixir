defmodule Mix.Tasks.Quacks.Visual do
  @shortdoc "Pixel diff of every gallery frame between two git refs"
  @moduledoc """
  Takes a screenshot of every gallery frame (`QuacksWeb.Gallery.Stories.frames/0`,
  the list of the HTML snapshots) on two git refs, at 360, 392 and 1280 px, and
  writes an HTML report of the shots that changed: base | head | diff, sorted by
  the part of the shot that changed.

      mix quacks.visual BASE [HEAD] [--only TEXT] [--widths 360,392,1280]
                        [--jobs 4] [--tolerance 4] [--out DIR] [--ports 4105,4106] [--keep]

  HEAD is `HEAD` when you give no second ref. For each ref the task makes a
  worktree under `tmp/visual/` (the deps are a link, `_build` a copy of this
  one's, so a build takes some seconds), builds the assets and starts a server
  in the test env (as the HTML snapshots: no reload, no page timers). The frame list comes from this
  checkout: a frame that one ref does not have shows as a changed shot.

  The shots: a Chrome with the DevTools port `CDP_PORT` (default 9223), else a
  headless Chrome that the task starts (`CHROME`, default Google Chrome) and
  stops. Reduced motion, every CSS animation and transition at 0 s, and a shot
  counts only when two captures in a row are the same.

  The report: `--out` (default `docs/assets/visual/<base>..<head>/`, not in git),
  `index.html` and `summary.json`. `--only` keeps the frames whose name has the
  text (`--only screens/`, `--only bar/`); give it more than once for more.
  `--tolerance` (default 4) is how far a colour channel (0..255) can be off and
  still count as the same: text and gradients can be 1 or 2 off from one render
  to the next. `--keep` keeps the worktrees (the servers always stop at the end).
  """
  use Mix.Task

  alias QuacksWeb.Gallery.Stories

  @switches [
    only: :keep,
    widths: :string,
    jobs: :integer,
    out: :string,
    ports: :string,
    keep: :boolean,
    tolerance: :integer
  ]
  @script "docs/assets/visual.mjs"

  @impl true
  def run(argv) do
    {opts, refs} = OptionParser.parse!(argv, strict: @switches)
    {base, head} = refs!(refs)
    root = File.cwd!()
    started = System.monotonic_time(:millisecond)

    Mix.Task.run("app.config")
    frames = frames(Keyword.get_values(opts, :only))
    [base_port, head_port] = ports(opts[:ports])
    out = Path.expand(opts[:out] || "docs/assets/visual/#{slug(base)}..#{slug(head)}", root)
    File.rm_rf!(out)
    File.mkdir_p!(out)

    sides = [
      %{role: "base", ref: base, sha: sha!(base), port: base_port},
      %{role: "head", ref: head, sha: sha!(head), port: head_port}
    ]

    info(
      "#{length(frames)} frames; base #{base} (#{hd(sides).sha}), head #{head} (#{List.last(sides).sha})"
    )

    {:ok, _} = Application.ensure_all_started(:req)

    try do
      sides =
        sides |> Enum.map(&Task.async(fn -> build(&1, root) end)) |> Task.await_many(:infinity)

      sides = Enum.map(sides, &serve/1)
      chrome = chrome(root)

      try do
        job = %{
          frames: Enum.map(frames, &Tuple.to_list/1),
          widths: widths(opts[:widths]),
          base: url(hd(sides)),
          head: url(List.last(sides)),
          out: out,
          cdp: cdp_port(),
          jobs: opts[:jobs] || 4,
          tolerance: opts[:tolerance] || 4
        }

        path = Path.join(out, "job.json")
        File.write!(path, Jason.encode!(job))
        {_, status} = System.cmd("node", [Path.join(root, @script), path], into: IO.stream())
        if status != 0, do: Mix.raise("#{@script} failed (#{status})")
      after
        stop(chrome)
      end
    after
      Enum.each(sides, &stop_server(&1, root))
      unless opts[:keep], do: Enum.each(sides, &remove(&1, root))
    end

    info("Done in #{div(System.monotonic_time(:millisecond) - started, 1000)} s")
  end

  defp refs!([base]), do: {base, "HEAD"}
  defp refs!([base, head]), do: {base, head}

  defp refs!(_refs),
    do: Mix.raise("Usage: mix quacks.visual BASE [HEAD] [--only TEXT] [--widths 360,392,1280]")

  defp frames([]), do: Stories.frames()

  defp frames(only) do
    case Enum.filter(Stories.frames(), fn {name, _} ->
           Enum.any?(only, &String.contains?(name, &1))
         end) do
      [] -> Mix.raise("No frame name has #{inspect(only)}")
      frames -> frames
    end
  end

  defp widths(nil), do: [360, 392, 1280]
  defp widths(text), do: text |> String.split(",") |> Enum.map(&String.to_integer/1)

  defp ports(nil), do: [4105, 4106]
  defp ports(text), do: text |> String.split(",") |> Enum.map(&String.to_integer/1)

  defp cdp_port, do: String.to_integer(System.get_env("CDP_PORT", "9223"))

  defp slug(ref), do: String.replace(ref, ~r/[^\w.-]+/, "-")

  defp sha!(ref) do
    case System.cmd("git", ["rev-parse", "--short", "#{ref}^{commit}"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      {error, _} -> Mix.raise("Not a git ref: #{ref} (#{String.trim(error)})")
    end
  end

  defp url(side), do: %{url: "http://127.0.0.1:#{side.port}", ref: side.ref, sha: side.sha}

  defp dir(side, root), do: Path.join([root, "tmp/visual", side.role])

  # A worktree at the ref with this checkout's deps (a link) and _build (a copy:
  # a clone on APFS, so only the changed modules compile), then the assets.
  defp build(side, root) do
    dir = dir(side, root)
    remove(side, root)
    git!(["worktree", "add", "--detach", "--force", dir, side.sha], root)
    File.ln_s!(real(Path.join(root, "deps")), Path.join(dir, "deps"))
    copy = if match?({:unix, :darwin}, :os.type()), do: "-cR", else: "-R"
    {_, 0} = System.cmd("cp", [copy, Path.join(root, "_build"), Path.join(dir, "_build")])
    info("#{side.role}: building #{side.ref}")
    log = Path.join(dir, "build.log")

    case System.cmd("sh", ["-c", "mix assets.build > build.log 2>&1"],
           cd: dir,
           env: [{"MIX_ENV", "test"}]
         ) do
      {_, 0} -> side
      _ -> Mix.raise("#{side.role}: build failed, see #{log}")
    end
  end

  defp real(path) do
    case File.read_link(path) do
      {:ok, target} -> Path.expand(target, Path.dirname(path))
      {:error, _} -> path
    end
  end

  # A server in the test env, as the HTML snapshots render: no watchers, no code
  # or live reload, and no timers that move the page on by themselves
  # (`show_move_ms: 0`, `upgrade_ms: 0` in config/test.exs). A shot would catch
  # such a timer at a different point on each run.
  @serve """
  File.write!("server.pid", System.pid())
  config = Application.get_env(:quacks, QuacksWeb.Endpoint)
  config = Keyword.merge(config, server: true, check_origin: false)
  Application.put_env(:quacks, QuacksWeb.Endpoint, config)
  {:ok, _} = Application.ensure_all_started(:quacks)
  """

  defp serve(side) do
    dir = dir(side, File.cwd!())
    log = Path.join(dir, "server.log")

    spawn_logged(
      System.find_executable("mix"),
      ["run", "--no-start", "--no-halt", "-e", @serve],
      log,
      dir,
      [{~c"MIX_ENV", ~c"test"}, {~c"PORT", ~c"#{side.port}"}]
    )

    wait!("#{side.role} server (#{log})", fn ->
      match?(
        {:ok, %{status: 200}},
        Req.get("http://127.0.0.1:#{side.port}/dev/gallery", retry: false)
      )
    end)

    info("#{side.role}: serving #{side.ref} on :#{side.port}")
    side
  end

  # The Chrome on CDP_PORT, else a headless one of our own (returned, to stop).
  defp chrome(root) do
    if cdp_up?() do
      nil
    else
      bin =
        System.get_env("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")

      profile = Path.join(root, "tmp/visual/chrome")
      File.mkdir_p!(profile)

      args = [
        "--headless=new",
        "--remote-debugging-port=#{cdp_port()}",
        "--user-data-dir=#{profile}",
        "--no-first-run",
        "--no-default-browser-check",
        "--hide-scrollbars",
        "--disable-gpu",
        "--force-color-profile=srgb",
        "--mute-audio",
        "about:blank"
      ]

      pid = spawn_logged(bin, args, Path.join(profile, "chrome.log"), root, [])
      wait!("Chrome on :#{cdp_port()}", &cdp_up?/0)
      info("Chrome: headless on :#{cdp_port()}")
      pid
    end
  end

  defp cdp_up? do
    match?(
      {:ok, %{status: 200}},
      Req.get("http://127.0.0.1:#{cdp_port()}/json/version", retry: false)
    )
  end

  # A program in the background, its output to `log`; returns its OS pid.
  defp spawn_logged(bin, args, log, dir, env) do
    port =
      Port.open({:spawn_executable, ~c"/bin/sh"}, [
        :binary,
        :exit_status,
        args: ["-c", ~s(exec "$0" "$@" > "#{log}" 2>&1), bin | args],
        cd: dir,
        env: env
      ])

    {:os_pid, pid} = Port.info(port, :os_pid)
    pid
  end

  defp wait!(what, ready?, tries \\ 600) do
    cond do
      ready?.() -> :ok
      tries == 0 -> Mix.raise("#{what} did not start")
      true -> wait_more(what, ready?, tries)
    end
  end

  defp wait_more(what, ready?, tries) do
    Process.sleep(200)
    wait!(what, ready?, tries - 1)
  end

  # The beam's own pid (its server.pid): `mix` starts it as a child of the pid
  # that `spawn_logged/5` returns.
  defp stop_server(side, root) do
    case File.read(Path.join(dir(side, root), "server.pid")) do
      {:ok, pid} -> stop(pid)
      {:error, _} -> :ok
    end
  end

  defp stop(nil), do: :ok
  defp stop(pid), do: System.cmd("kill", [to_string(pid)], stderr_to_stdout: true)

  defp remove(side, root) do
    dir = dir(side, root)
    System.cmd("git", ["worktree", "remove", "--force", dir], cd: root, stderr_to_stdout: true)
    File.rm_rf!(dir)
    System.cmd("git", ["worktree", "prune"], cd: root)
  end

  defp git!(args, root) do
    case System.cmd("git", args, cd: root, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {error, _} -> Mix.raise("git #{Enum.join(args, " ")}: #{error}")
    end
  end

  defp info(text), do: Mix.shell().info(text)
end
