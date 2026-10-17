defmodule Quacks.GameStore do
  @moduledoc """
  Games on disk, so they survive a deploy or a restart. Plain functions, no process.

  Each running game has one **game file**, `<dir>/<id>.json`: its bundle
  (`Quacks.GameServer.bundle/1`, absent while the game waits) plus a `"table"` key
  with what a resume needs (seats, tokens, names, colours, bots, settings, `seen`).
  The `Quacks.GameServer` writes it (debounced) after each change and deletes it when
  the game ends for good. At boot `restore/1` starts a server for every file.

  **Finished games** (the archive): when a game ends, the server writes
  `<dir>/finished/<id>.json` (`archive/3`): the bundle, the seats (name, human or
  bot and its profile, VP), the standings, the winners, the app version and
  `finished_at`. The game file goes later as before; the archive stays. Only the
  newest 1000 archive files and at most 50 MB stay (`prune/3`). `restore/1`
  does not read them. `mix quacks.games.pull` copies them to a laptop.

  The directory is `config :quacks, :games_dir` (`GAMES_DIR` at runtime); `nil` (the
  test default) turns the store off. A write goes to a temp file first and is then
  renamed, so a crash never leaves half a file.
  """

  require Logger

  alias Quacks.GameServer

  @doc "The configured games directory, or nil (no store)."
  @spec dir() :: Path.t() | nil
  def dir, do: Application.get_env(:quacks, :games_dir)

  @doc "The game file of `id` in `dir`."
  @spec path(Path.t(), GameServer.id()) :: Path.t()
  def path(dir, id), do: Path.join(dir, id <> ".json")

  @doc """
  Write `body` (JSON-ready) as the game file of `id`. A `nil` dir does nothing. A
  failure is logged and returned, never raised: the game plays on in memory.
  """
  @spec write(Path.t() | nil, GameServer.id(), map) :: :ok | {:error, term}
  def write(nil, _id, _body), do: :ok

  def write(dir, id, body) do
    file = path(dir, id)
    tmp = file <> ".tmp"

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(tmp, Jason.encode_to_iodata!(body)),
         :ok <- File.rename(tmp, file) do
      :ok
    else
      {:error, reason} = error ->
        Logger.warning("game #{id}: cannot write #{file}: #{inspect(reason)}")
        error
    end
  end

  @max_finished 1000
  @max_finished_bytes 50_000_000

  @doc "The directory of the finished games (the archive) in `dir`."
  @spec finished_dir(Path.t()) :: Path.t()
  def finished_dir(dir), do: Path.join(dir, "finished")

  @doc """
  Write `body` (JSON-ready) as the archive file of the finished game `id`, then
  `prune/3` the archive. A `nil` dir does nothing. A failure is logged and
  returned, never raised.
  """
  @spec archive(Path.t() | nil, GameServer.id(), map) :: :ok | {:error, term}
  def archive(nil, _id, _body), do: :ok

  def archive(dir, id, body) do
    fdir = finished_dir(dir)

    case write(fdir, id, body) do
      :ok ->
        prune(fdir)
        :ok

      error ->
        error
    end
  end

  @doc """
  Keep the newest `max_files` archive files (default #{@max_finished}) whose sizes
  add up to at most `max_bytes` (default #{@max_finished_bytes}); delete the rest.
  Newest = the latest modification time. Returns the deleted paths.
  """
  @spec prune(Path.t(), pos_integer, pos_integer) :: [Path.t()]
  def prune(fdir, max_files \\ @max_finished, max_bytes \\ @max_finished_bytes) do
    files =
      fdir
      |> Path.join("*.json")
      |> Path.wildcard()
      |> Enum.flat_map(&stat/1)
      |> Enum.sort_by(fn {path, mtime, _size} -> {mtime, path} end, :desc)

    {_kept, _bytes, gone} =
      Enum.reduce(files, {0, 0, []}, fn {path, _mtime, size}, {n, bytes, gone} ->
        if n < max_files and bytes + size <= max_bytes,
          do: {n + 1, bytes + size, gone},
          else: {n, bytes, [path | gone]}
      end)

    Enum.each(gone, &File.rm/1)
    Enum.reverse(gone)
  end

  defp stat(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime, size: size}} -> [{path, mtime, size}]
      {:error, _} -> []
    end
  end

  @doc "Read and decode a game file."
  @spec read(Path.t()) :: {:ok, map} | {:error, term}
  def read(file) do
    with {:ok, json} <- File.read(file),
         {:ok, %{"table" => %{"id" => _}} = body} <- Jason.decode(json) do
      {:ok, body}
    else
      {:ok, _other} -> {:error, :invalid}
      error -> error
    end
  end

  @doc "Delete the game file of `id` (no file: fine). A `nil` dir does nothing."
  @spec delete(Path.t() | nil, GameServer.id()) :: :ok
  def delete(nil, _id), do: :ok

  def delete(dir, id) do
    _ = File.rm(path(dir, id))
    :ok
  end

  @doc """
  Start a `Quacks.GameServer` for every game file in `dir` (bots play on) and log
  `restored N games`. A file that does not load is renamed `<id>.json.bad` and
  logged; it never stops the boot. Returns the ids started.
  """
  @spec restore(Path.t() | nil) :: [GameServer.id()]
  def restore(dir \\ dir())
  def restore(nil), do: []

  def restore(dir) do
    # A game file names its actions and settings as strings that must be existing
    # atoms. In dev, modules load on first use, so at boot those atoms may not exist
    # yet: load the app's modules first (a release has loaded them already).
    {:ok, modules} = :application.get_key(:quacks, :modules)
    Enum.each(modules, &Code.ensure_loaded/1)

    ids =
      dir
      |> Path.join("*.json")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(&restore_file(&1, dir))

    Logger.info("restored #{length(ids)} games from #{dir}")
    ids
  end

  defp restore_file(file, dir) do
    with {:ok, body} <- read(file),
         {:ok, id} <- GameServer.start_from_bundle(body, restore: true, dir: dir) do
      [id]
    else
      {:error, :already_started} -> []
      error -> quarantine(file, error)
    end
  rescue
    error -> quarantine(file, error)
  catch
    :exit, reason -> quarantine(file, reason)
  end

  defp quarantine(file, error) do
    Logger.error("cannot restore #{file} (#{inspect(error)}); renamed to .bad")
    _ = File.rename(file, file <> ".bad")
    []
  end

  @doc """
  The supervisor child that restores the games at boot: it runs `restore/0` in the
  supervisor's start (so the Endpoint opens only after the games are back) and
  then needs no process (`:ignore`).
  """
  def child_spec(_arg),
    do: %{id: __MODULE__, start: {__MODULE__, :start_restore, []}, restart: :temporary}

  @doc false
  def start_restore do
    restore()
    :ignore
  end
end
