defmodule QuacksWeb.UiSnapshotTest do
  @moduledoc """
  UI snapshots: the rendered HTML of every gallery story (default args and each
  preset), every screen and every scenario step, compared with the stored copy in
  `test/snapshots/`. A refactor must keep them the same.

      mix test --only snapshot                      # compare
      UPDATE_SNAPSHOTS=1 mix test --only snapshot   # write them again

  The HTML is the frame's connected render (`live/2`), with the unstable parts
  replaced (LiveView ids, session tokens, csrf) and one tag per line, so a diff
  shows the lines that changed.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.Scenarios
  alias QuacksWeb.Gallery.Stories

  @moduletag :snapshot

  @dir Path.expand("../snapshots", __DIR__)
  @context 3
  @max_lines 60

  cases =
    for g <- Stories.catalog(), s <- g.stories do
      case s do
        %{scenario: entry} ->
          {:ok, script} = Scenarios.build(entry)

          for i <- 1..length(script.steps),
              do: {"#{g.id}/#{s.id}/step-#{i}", "/dev/gallery/frame/#{g.id}/#{s.id}?step=#{i}"}

        _ ->
          for {id, _title, args} <- [{"default", "", %{}} | s.presets] do
            args = Map.new(args, fn {k, v} -> {k, to_string(v)} end)
            query = Stories.query(s, Stories.args(s, args))

            {"#{g.id}/#{s.id}/#{id}",
             "/dev/gallery/frame/#{g.id}/#{s.id}?#{URI.encode_query(query)}"}
          end
      end
    end
    |> List.flatten()

  @names MapSet.new(cases, &elem(&1, 0))

  for {name, path} <- cases do
    @tag snapshot_name: name, snapshot_path: path
    test "snapshot #{name}", %{conn: conn, snapshot_name: name, snapshot_path: path} do
      {:ok, _view, html} = live(conn, path)
      check(name, normalise(html))
    end
  end

  test "every snapshot file belongs to a story" do
    stale =
      for file <- Path.wildcard(Path.join(@dir, "**/*.html")),
          name = file |> Path.relative_to(@dir) |> String.replace_suffix(".html", ""),
          name not in @names,
          do: name

    if update?() do
      Enum.each(stale, &File.rm!(file(&1)))
    else
      assert stale == [],
             "snapshots with no story (UPDATE_SNAPSHOTS=1 deletes them): #{inspect(stale)}"
    end
  end

  defp update?, do: System.get_env("UPDATE_SNAPSHOTS") in ["1", "true"]

  defp file(name), do: Path.join(@dir, name <> ".html")

  defp check(name, html) do
    path = file(name)

    cond do
      update?() ->
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, html)

      not File.exists?(path) ->
        flunk("no snapshot for #{name}: run UPDATE_SNAPSHOTS=1 mix test --only snapshot")

      true ->
        expected = File.read!(path)

        if expected != html do
          actual = Path.join([System.tmp_dir!(), "quacks-snapshots", name <> ".html"])
          File.mkdir_p!(Path.dirname(actual))
          File.write!(actual, html)

          flunk("""
          snapshot #{name} changed (#{Path.relative_to_cwd(path)}; now: #{actual}):
          #{diff(expected, html)}
          UPDATE_SNAPSHOTS=1 mix test --only snapshot accepts the change.
          """)
        end
    end
  end

  # One tag per line, the attributes of a tag sorted (their order follows map
  # order, which changes between runs); LiveView ids, session tokens and the csrf
  # token replaced; icon path data hashed.
  defp normalise(html) do
    html
    |> String.replace(~r/"phx-[A-Za-z0-9_-]{16}"/, ~s("phx-ID"))
    |> String.replace(~r/data-phx-session="[^"]*"/, ~s(data-phx-session=""))
    |> String.replace(~r/data-phx-static="[^"]*"/, ~s(data-phx-static=""))
    |> String.replace(~r/name="csrf-token" content="[^"]*"/, ~s(name="csrf-token" content=""))
    |> String.replace(~r/name="_csrf_token" value="[^"]*"/, ~s(name="_csrf_token" value=""))
    |> String.replace(~r/ d="([^"]{80,})"/, fn attr -> ~s( d="#hash:#{short_hash(attr)}") end)
    |> String.replace(
      ~r/<([a-zA-Z][\w:-]*)((?:\s+[^\s=>"\/]+(?:="[^"]*")?)+)\s*(\/?)>/,
      &sort_attrs/1
    )
    |> String.replace(~r/>\s*</, ">\n<")
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp sort_attrs(tag) do
    [_, name, attrs, close] = Regex.run(~r/^<([^\s>\/]+)(.*?)\s*(\/?)>$/s, tag)
    sorted = ~r/[^\s=]+(?:="[^"]*")?/ |> Regex.scan(attrs) |> List.flatten() |> Enum.sort()
    "<" <> Enum.join([name | sorted], " ") <> close <> ">"
  end

  # Icon path data as a hash: it still shows a change, in a few bytes.
  defp short_hash(text),
    do: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower) |> binary_part(0, 12)

  # The changed lines with #{@context} lines around them, `-` stored, `+` now.
  defp diff(expected, actual) do
    String.split(expected, "\n")
    |> List.myers_difference(String.split(actual, "\n"))
    |> Enum.flat_map(fn {op, lines} -> Enum.map(lines, &{op, &1}) end)
    |> Enum.with_index()
    |> then(fn lines ->
      changed = for {{op, _}, i} <- lines, op != :eq, do: i
      keep = MapSet.new(for i <- changed, j <- (i - @context)..(i + @context), do: j)

      lines
      |> Enum.filter(fn {_, i} -> i in keep end)
      |> Enum.map(fn {{op, line}, _} -> prefix(op) <> line end)
      |> Enum.take(@max_lines)
      |> Enum.join("\n")
    end)
  end

  defp prefix(:eq), do: "  "
  defp prefix(:del), do: "- "
  defp prefix(:ins), do: "+ "
end
