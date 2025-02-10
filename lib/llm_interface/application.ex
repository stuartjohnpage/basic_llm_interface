defmodule LlmInterface.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LlmInterfaceWeb.Telemetry,
      LlmInterface.Repo,
      {DNSCluster, query: Application.get_env(:llm_interface, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LlmInterface.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: LlmInterface.Finch},
      # Start a worker by calling: LlmInterface.Worker.start_link(arg)
      # {LlmInterface.Worker, arg},
      # Start to serve requests, typically the last entry
      LlmInterfaceWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LlmInterface.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LlmInterfaceWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
