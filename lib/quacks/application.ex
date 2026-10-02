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
      # One `Quacks.GameServer` per game, found by its id (see that module).
      {Registry, keys: :unique, name: Quacks.GameRegistry},
      {DynamicSupervisor, name: Quacks.GameSupervisor, strategy: :one_for_one},
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
