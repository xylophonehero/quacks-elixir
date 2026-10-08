defmodule QuacksWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  require Logger

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    :telemetry.attach(
      "quacks-live-event-timing",
      [:phoenix, :live_view, :handle_event, :stop],
      &__MODULE__.log_event/4,
      nil
    )

    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://telemetry-metrics.hexdocs.pm
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @slow_ms 50

  @doc """
  One line per LiveView event (round 28): `live_event view=GameLive event=action
  ms=1.2`, at `:info` from #{@slow_ms} ms, else `:debug`. The time is the server's
  `handle_event` only (it includes the `GameServer` call), not the render or the network.
  """
  def log_event(_event, %{duration: duration}, %{socket: socket, event: event}, _config) do
    ms = System.convert_time_unit(duration, :native, :microsecond) / 1000
    level = if ms >= @slow_ms, do: :info, else: :debug

    Logger.log(level, fn ->
      view = socket.view |> Module.split() |> List.last()
      "live_event view=#{view} event=#{event} ms=#{Float.round(ms, 2)}"
    end)
  end

  def log_event(_event, _measurements, _metadata, _config), do: :ok

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {QuacksWeb, :count_users, []}
    ]
  end
end
