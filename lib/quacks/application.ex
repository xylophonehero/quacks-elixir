defmodule Quacks.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      QuacksWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:quacks, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Quacks.PubSub},
      # Start a worker by calling: Quacks.Worker.start_link(arg)
      # {Quacks.Worker, arg},
      # Start to serve requests, typically the last entry
      QuacksWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Quacks.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    QuacksWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
