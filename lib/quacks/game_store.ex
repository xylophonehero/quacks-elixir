defmodule Quacks.GameStore do
  @moduledoc """
  Games on disk, so they survive a deploy or a restart. Plain functions, no process.

  Each running game has one **game file**, `<dir>/<id>.json`: its bundle
  (`Quacks.GameServer.bundle/1`, absent while the game waits) plus a `"table"` key
  with what a resume needs (seats, tokens, names, colours, bots, settings, `seen`).
  The `Quacks.GameServer` writes it (debounced) after each change and deletes it when
  the game ends for good. At boot `restore/1` starts a server for every file.

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
