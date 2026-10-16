defmodule Mix.Tasks.Quacks.Visual do
  @shortdoc "Pixel diff of every gallery frame between two git refs"
  @moduledoc """
  Takes a screenshot of every gallery frame (`QuacksWeb.Gallery.Stories.frames/0`,
  the list of the HTML snapshots) on two git refs, at 360, 392 and 1280 px, and
  writes an HTML report of the shots that changed: base | head | diff, sorted by
  the part of the shot that changed.

      mix quacks.visual BASE [HEAD] [--only TEXT] [--widths 360,392,1280]
                        [--jobs 4] [--tolerance 4] [--out DIR] [--ports 4105,4106]
                        [--cdp-port 9223] [--keep]

  HEAD is `HEAD` when you give no second ref. For each ref the task makes a
  worktree under `tmp/visual/<role>-<port>/` (the deps are a link, `_build` a copy
  of this one's, so a build takes some seconds), builds the assets and starts a
  server in the test env (as the HTML snapshots: no reload, no page timers). Each
  ref gives its own frame list: a frame that only head has is **new** (the head
  shot only), a frame that only base has is **removed** (the base shot only).
  When a build fails, the task copies its `build.log` into the report folder and
  shows its last 30 lines.

  The shots: a Chrome with the DevTools port `--cdp-port` (else `CDP_PORT`, else
  9223), else a headless Chrome that the task starts (`CHROME`, default Google
  Chrome) and stops. Give other `--ports` and `--cdp-port` to run two at once. Reduced motion, every CSS animation and transition at 0 s, and a shot
  counts only when two captures in a row are the same.

  The report: `--out` (default `docs/assets/visual/<base>..<head>/`, not in git),
  `index.html` and `summary.json`. `--only` keeps the frames whose name has the
  text (`--only screens/`, `--only bar/`); give it more than once for more.
  `--tolerance` (default 4) is how far a colour channel (0..255) can be off and
  still count as the same: text and gradients can be 1 or 2 off from one render
  to the next. `--keep` keeps the worktrees (the servers always stop at the end; remove them
  with `git worktree remove --force DIR`).
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
    tolerance: :integer,
    cdp_port: :integer
  ]
  @script "docs/assets/visual.mjs"

  @impl true
  def run(argv) do
    {opts, refs} = OptionParser.parse!(argv, strict: @switches)
    {base, head} = refs!(refs)
    root = File.cwd!()
    started = System.monotonic_time(:millisecond)

    Mix.Task.run("app.config")
    only = Keyword.get_values(opts, :only)
    cdp = opts[:cdp_port] || String.to_integer(System.get_env("CDP_PORT", "9223"))
    [base_port, head_port] = ports(opts[:ports])
    out = Path.expand(opts[:out] || "docs/assets/visual/#{slug(base)}..#{slug(head)}", root)
    File.rm_rf!(out)
    File.mkdir_p!(out)

    sides =
      for {role, ref, port} <- [{"base", base, base_port}, {"head", head, head_port}] do
        %{role: role, ref: ref, sha: sha!(ref), port: port, dir: dir(role, port, root)}
      end

    info("base #{base} (#{hd(sides).sha}), head #{head} (#{List.last(sides).sha})")

    {:ok, _} = Application.ensure_all_started(:req)

    try do
      sides =
        sides
        |> Enum.map(&Task.async(fn -> build(&1, root) end))
        |> Task.await_many(:infinity)
        |> built!(out)

      sides = Enum.map(sides, &serve/1)
      [base_frames, head_frames] = Enum.map(sides, &served_frames/1)
      frames = frames(base_frames, head_frames, only)
      info(frames_line(frames))
      chrome = chrome(root, cdp)

      try do
        job = %{
          frames: frames,
          widths: widths(opts[:widths]),
          base: url(hd(sides)),
          head: url(List.last(sides)),
          out: out,
          cdp: cdp,
          jobs: opts[:jobs] || 4,
          tolerance: opts[:tolerance] || 4
        }

        path = Path.join(out, "job.json")
        File.write!(path, Jason.encode!(job))
        {_, status} = System.cmd("node", [Path.join(root, @script), path], into: IO.stream())
        if status != 0, do: Mix.raise("#{@script} failed (#{status})")
      after
        stop_chrome(chrome, cdp)
      end
    after
      Enum.each(sides, &stop_server/1)
      if opts[:keep], do: kept(sides, root, cdp), else: clean(sides, root, cdp)
    end

    info("Done in #{div(System.monotonic_time(:millisecond) - started, 1000)} s")
  end

  defp refs!([base]), do: {base, "HEAD"}
  defp refs!([base, head]), do: {base, head}

  defp refs!(_refs),
    do: Mix.raise("Usage: mix quacks.visual BASE [HEAD] [--only TEXT] [--widths 360,392,1280]")

  # Every frame of the two refs, in head's order and then the frames that only
  # base has: `%{name, base: path | nil, head: path | nil}` (nil: the ref does
  # not have the frame).
  defp frames(base_frames, head_frames, only) do
    base_paths = Map.new(base_frames)
    head_names = MapSet.new(head_frames, &elem(&1, 0))

    both =
      for {name, path} <- head_frames, do: %{name: name, base: base_paths[name], head: path}

    removed =
      for {name, path} <- base_frames,
          name not in head_names,
          do: %{name: name, base: path, head: nil}

    case Enum.filter(both ++ removed, &only?(&1.name, only)) do
      [] -> Mix.raise("No frame name has #{inspect(only)}")
      frames -> frames
    end
  end

  defp only?(_name, []), do: true
  defp only?(name, only), do: Enum.any?(only, &String.contains?(name, &1))

  defp frames_line(frames) do
    new = Enum.count(frames, &is_nil(&1.base))
    removed = Enum.count(frames, &is_nil(&1.head))
    "#{length(frames)} frames (#{new} new, #{removed} removed)"
  end

  defp widths(nil), do: [360, 392, 1280]
  defp widths(text), do: text |> String.split(",") |> Enum.map(&String.to_integer/1)

  defp ports(nil), do: [4105, 4106]
  defp ports(text), do: text |> String.split(",") |> Enum.map(&String.to_integer/1)

  defp slug(ref), do: String.replace(ref, ~r/[^\w.-]+/, "-")

  defp sha!(ref) do
    case System.cmd("git", ["rev-parse", "--short", "#{ref}^{commit}"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      {error, _} -> Mix.raise("Not a git ref: #{ref} (#{String.trim(error)})")
    end
  end

  defp url(side), do: %{url: "http://127.0.0.1:#{side.port}", ref: side.ref, sha: side.sha}

  # One folder per role and port, so two runs (other ports) do not meet.
  defp dir(role, port, root), do: Path.join([root, "tmp/visual", "#{role}-#{port}"])

  # A worktree at the ref with this checkout's deps (a link) and _build (a copy:
  # a clone on APFS, so only the changed modules compile), then the assets and
  # the ref's frame list. Runs in a task: an error comes back as
  # `{:error, side, text}`, not as a raise (a raise in a linked task stops this
  # process at once, with no `after`: the servers and worktrees stayed).
  defp build(side, root) do
    remove(side.dir, root)
    git!(["worktree", "add", "--detach", "--force", side.dir, side.sha], root)
    File.ln_s!(real(Path.join(root, "deps")), Path.join(side.dir, "deps"))
    copy = if match?({:unix, :darwin}, :os.type()), do: "-cR", else: "-R"
    {_, 0} = System.cmd("cp", [copy, Path.join(root, "_build"), Path.join(side.dir, "_build")])
    info("#{side.role}: building #{side.ref}")

    case System.cmd("sh", ["-c", "mix assets.build > build.log 2>&1"],
           cd: side.dir,
           env: [{"MIX_ENV", "test"}]
         ) do
      {_, 0} -> {:ok, Map.put(side, :frames, ref_frames(side))}
      _ -> {:error, side, "build failed"}
    end
  rescue
    error -> {:error, side, Exception.message(error)}
  end

  # The ref's own `Stories.frames/0` (nil: the ref has no such function, see
  # `served_frames/1`).
  @frames """
  frames = Enum.map(QuacksWeb.Gallery.Stories.frames(), &Tuple.to_list/1)
  File.write!("frames.json", Jason.encode!(frames))
  """

  defp ref_frames(side) do
    {output, status} =
      System.cmd("mix", ["run", "--no-start", "-e", @frames],
        cd: side.dir,
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    case {status, File.read(Path.join(side.dir, "frames.json"))} do
      {0, {:ok, text}} ->
        text |> Jason.decode!() |> Enum.map(&List.to_tuple/1)

      _ ->
        error = output |> String.split("\n") |> Enum.find("", &(&1 =~ "** ("))
        info("#{side.role}: no frame list at #{side.ref}: #{String.trim(error)}")
        nil
    end
  end

  # A ref with no frame list (older than `Stories.frames/0`): the frames of this
  # checkout that its server gives (status 200; a frame it does not know
  # redirects to the gallery).
  defp served_frames(%{frames: nil} = side) do
    frames =
      Stories.frames()
      |> Task.async_stream(
        fn {_name, path} = frame ->
          {frame, Req.get("http://127.0.0.1:#{side.port}#{path}", retry: false, redirect: false)}
        end,
        max_concurrency: 8,
        timeout: :infinity
      )
      |> Enum.flat_map(fn
        {:ok, {frame, {:ok, %{status: 200}}}} -> [frame]
        _ -> []
      end)

    info("#{side.role}: #{length(frames)} frames of this checkout's list give status 200")
    frames
  end

  defp served_frames(side), do: side.frames

  # A failed build: its log goes into the report folder (the cleanup removes
  # tmp/visual) and its last 30 lines to the terminal, then the run stops.
  defp built!(results, out) do
    failed = for {:error, side, text} <- results, do: failed(side, text, out)
    if failed != [], do: Mix.raise(Enum.join(failed, "; "))
    for {:ok, side} <- results, do: side
  end

  defp failed(side, text, out) do
    log = Path.join(side.dir, "build.log")
    copy = Path.join(out, "build-#{side.role}.log")

    case File.read(log) do
      {:ok, body} ->
        File.cp!(log, copy)
        tail = body |> String.split("\n") |> Enum.take(-31) |> Enum.join("\n")
        Mix.shell().error("#{side.role} (#{side.ref}): last lines of build.log\n#{tail}")
        "#{side.role}: #{text}, see #{copy}"

      {:error, _} ->
        "#{side.role}: #{text}"
    end
  end

  defp real(path) do
    case File.read_link(path) do
      {:ok, target} -> Path.expand(target, Path.dirname(path))
      {:error, _} -> path
    end
  end

  # Both servers make the same URLs (a join link shows host and port), so the
  # port is not a change.
  # A server in the test env, as the HTML snapshots render: no watchers, no code
  # or live reload, and no timers that move the page on by themselves
  # (`show_move_ms: 0`, `upgrade_ms: 0` in config/test.exs). A shot would catch
  # such a timer at a different point on each run.
  @serve """
  File.write!("server.pid", System.pid())
  config = Application.get_env(:quacks, QuacksWeb.Endpoint)
  config = Keyword.merge(config, server: true, check_origin: false, url: [host: "localhost", port: 4000])
  Application.put_env(:quacks, QuacksWeb.Endpoint, config)
  {:ok, _} = Application.ensure_all_started(:quacks)
  """

  defp serve(side) do
    dir = side.dir
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

  # The Chrome on the CDP port, else a headless one of our own (returned, to stop).
  defp chrome(root, cdp) do
    if cdp_up?(cdp) do
      nil
    else
      bin =
        System.get_env("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")

      profile = chrome_dir(root, cdp)
      File.mkdir_p!(profile)

      args = [
        "--headless=new",
        "--remote-debugging-port=#{cdp}",
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
      wait!("Chrome on :#{cdp}", fn -> cdp_up?(cdp) end)
      info("Chrome: headless on :#{cdp}")
      pid
    end
  end

  defp chrome_dir(root, cdp), do: Path.join(root, "tmp/visual/chrome-#{cdp}")

  defp cdp_up?(cdp) do
    match?(
      {:ok, %{status: 200}},
      Req.get("http://127.0.0.1:#{cdp}/json/version", retry: false)
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
  defp stop_server(side) do
    case File.read(Path.join(side.dir, "server.pid")) do
      {:ok, pid} -> stop(pid)
      {:error, _} -> :ok
    end
  end

  # Our own Chrome: stop it and wait (max. 5 s) until it is gone, so that it
  # does not write its profile again after `clean/3`.
  defp stop_chrome(nil, _cdp), do: :ok

  defp stop_chrome(pid, cdp) do
    stop(pid)
    Enum.find(1..25, &chrome_gone?(&1, cdp))
  end

  defp chrome_gone?(_try, cdp) do
    if cdp_up?(cdp) do
      Process.sleep(200)
      false
    else
      true
    end
  end

  defp stop(nil), do: :ok
  defp stop(pid), do: System.cmd("kill", [to_string(pid)], stderr_to_stdout: true)

  # Every exit: this run's worktrees (also their git entries) and Chrome
  # profile, then tmp/visual when no other run uses it.
  defp clean(sides, root, cdp) do
    Enum.each(sides, &remove(&1.dir, root))
    File.rm_rf!(chrome_dir(root, cdp))
    File.rmdir(Path.join(root, "tmp/visual"))
  end

  defp kept(sides, root, cdp) do
    File.rm_rf!(chrome_dir(root, cdp))

    for side <- sides,
        do: info("#{side.role}: kept #{side.dir} (git worktree remove --force DIR)")
  end

  defp remove(dir, root) do
    System.cmd("git", ["worktree", "remove", "--force", dir], cd: root, stderr_to_stdout: true)
    File.rm_rf!(dir)
    System.cmd("git", ["worktree", "prune"], cd: root, stderr_to_stdout: true)
  end

  defp git!(args, root) do
    case System.cmd("git", args, cd: root, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {error, _} -> Mix.raise("git #{Enum.join(args, " ")}: #{error}")
    end
  end

  defp info(text), do: Mix.shell().info(text)
end
