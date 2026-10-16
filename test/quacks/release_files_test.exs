defmodule Quacks.ReleaseFilesTest do
  @moduledoc """
  The Docker build copies only `lib`, `priv`, `assets`, `config` and `rel`
  (`Dockerfile`). A file that `lib` reads at compile time from another folder
  (`docs/`, `test/`) is there in dev and test but missing in the release, and the
  feature is silently empty on staging (the generic game specs, 2026-10-17).
  """
  use ExUnit.Case, async: true

  test "lib reads no file from a folder the release build leaves out" do
    offenders =
      for file <- Path.wildcard("lib/**/*.ex"),
          # mix tasks run in dev, from the checkout
          not String.starts_with?(file, "lib/mix/"),
          {line, n} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          line =~ ~r{Path\.(expand|join)\(.*"[^"]*\b(docs|test)/},
          do: "#{file}:#{n}: #{String.trim(line)}"

    assert offenders == []
  end
end
