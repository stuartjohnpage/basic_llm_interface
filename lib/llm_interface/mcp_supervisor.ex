defmodule LlmInterface.MCPSupervisor do
  @moduledoc """
  Supervisor for MCP clients and related processes.

  This supervisor ensures that:
  1. All MCP transports start first
  2. All MCP clients start after their transports
  3. The MCPTools registry starts after all clients are ready

  Uses a rest_for_one strategy to ensure proper ordering and dependencies.
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    hexdocs_mcp_client_name = Keyword.fetch!(opts, :hexdocs_mcp_client_name)
    google_maps_client_name = Keyword.fetch!(opts, :google_maps_client_name)
    # test_client_name = Keyword.fetch!(opts, :test_client_name)

    children = [
      # Group 1: Transports
      Supervisor.child_spec(
        {Hermes.Transport.STDIO,
         [
           name: LlmInterfaceWeb.HexDocsMCPTransport,
           client: hexdocs_mcp_client_name,
           command: "npx",
           args: ["-y", "hexdocs-mcp@0.2.0"]
         ]},
        id: :hexdocs_mcp_transport
      ),
      Supervisor.child_spec(
        {Hermes.Transport.STDIO,
         [
           name: LlmInterfaceWeb.GoogleMapsMCPTransport,
           client: google_maps_client_name,
           command: "npx",
           args: ["-y", "@modelcontextprotocol/server-google-maps"],
           env: %{
             "GOOGLE_MAPS_API_KEY" => System.get_env("GOOGLE_MAPS_API_KEY")
           },
           capabilities: %{"roots" => %{"listChanged" => true}, "sampling" => %{}}
         ]},
        id: :google_maps_mcp_transport
      ),
      # Supervisor.child_spec(
      #   {Hermes.Transport.STDIO,
      #    [
      #      name: LlmInterfaceWeb.TestMCPTransport,
      #      client: test_client_name,
      #      command: "npx",
      #      args: ["-y", "@modelcontextprotocol/server-everything"]
      #    ]},
      #   id: :test_mcp_transport
      # ),

      # Group 2: Clients - start after transports
      Supervisor.child_spec(
        {Hermes.Client,
         [
           name: hexdocs_mcp_client_name,
           transport: [layer: Hermes.Transport.STDIO, name: LlmInterfaceWeb.HexDocsMCPTransport],
           client_info: %{
             "name" => "LlmInterfaceWeb",
             "version" => "1.0.0"
           }
         ]},
        id: :hexdocs_mcp_client
      ),
      Supervisor.child_spec(
        {Hermes.Client,
         [
           name: google_maps_client_name,
           transport: [
             layer: Hermes.Transport.STDIO,
             name: LlmInterfaceWeb.GoogleMapsMCPTransport
           ],
           client_info: %{
             "name" => "LlmInterfaceWeb",
             "version" => "1.0.0"
           }
         ]},
        id: :google_maps_mcp_client
      ),
      # Supervisor.child_spec(
      #   {Hermes.Client,
      #    [
      #      name: test_client_name,
      #      transport: [layer: Hermes.Transport.STDIO, name: LlmInterfaceWeb.TestMCPTransport],
      #      client_info: %{
      #        "name" => "LlmInterfaceWeb",
      #        "version" => "1.0.0"
      #      }
      #    ]},
      #   id: :test_mcp_client
      # ),

      # Group 3: Tools Registry - starts after all clients are ready
      {LlmInterface.MCPTools, []}
    ]

    # Use rest_for_one strategy - if a process fails, all processes started after it are restarted
    # This ensures dependency order is maintained during restarts
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
